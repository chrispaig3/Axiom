#!/usr/bin/env bash
# The freestanding subset: eight standard-library modules a bare-metal
# program may import, gated as a fact rather than intended.
#
# docs/embedded-proposal.md 4.4 says `Pre`, `Mem`, `Str`, `Vec`, `Map`,
# `Fmt`, `Utf8` and `Err` assume no filesystem, process model or
# sockets, while `Sys`, `IO`, `Path`, `Http`, `Rpc` and `Par` do - and
# requires the split to be gated BEFORE the port, because a subset no
# gate holds is an intention. This is that gate, in three arms that
# fail for three different breakages:
#
#   1. CLOSURE. The transitive imports of every subset module stay
#      inside the subset, read off the `(import ...)` lines with a
#      fixed-point walk written here. A `Str` that started importing
#      `Sys` would still build, still pass every golden, and quietly
#      stop being freestanding; this arm is what would notice. Dotted
#      names count as their top level (`Sys.Platform` is `Sys`), and
#      files are read only for modules inside the subset, so an
#      outside name is reported rather than followed.
#   2. NO EXTERN. No subset module declares an `extern` block. An
#      `extern` item is the one other door out of a freestanding
#      program besides an import: it names a symbol no bare-metal
#      target provides, and nothing in the import closure can see it.
#      The pattern is `^\((pub )?extern "` - a block header with its
#      library string - which prose mentions (`an extern block`) and
#      compiler identifiers (`externTypeRefusal`) do not match.
#   3. END TO END. One probe importing all eight builds for every
#      supported target, and its import surface is the hello world's:
#      linked imports on the host, IR declares elsewhere. A
#      DIFFERENTIAL, not a list - no libc-name table is duplicated
#      here (that table is check-freestanding.sh's, and two copies of
#      one fact is how a boundary silently widens). Any libc call the
#      subset started emitting shows up as a declare the hello world
#      does not carry. The probe CALLS into seven of the eight - the
#      eighth, `Pre`, is macros, which leave no symbol to grep for -
#      and each call is asserted in the IR, so a use cannot be deleted
#      while its import stays.
#
# THE ABLATIONS, each on a copy of `stdlib/` the checkout never sees:
# a planted `(import Sys)` in `Str` must redden arm 1, and a planted
# `extern` block in `Mem` must redden arm 2. Each asserts its plant
# landed before believing the red, for check-compat.sh's `probe`
# reason: a `sed` matching nothing produces a green "ablation failed
# to fail" that reads exactly like a passing gate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"

SUBSET="Pre Mem Str Vec Map Fmt Utf8 Err"

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The library under test: the checkout's, unless a caller points
# elsewhere (the ablations do).
LIBROOT="$repo_root/stdlib"

for m in $SUBSET; do
  if [[ ! -f "$LIBROOT/$m.ax" ]]; then
    echo "FAIL the subset names $m, but $m.ax is gone - the list proves nothing about it"
    exit 1
  fi
done

# Direct imports of one file: the first token after `(import`,
# top-level only.
direct_imports() { # <file> -> names, one per line
  grep -oE '^\(import [A-Za-z_][A-Za-z0-9_.'"'"']*' "$1" 2>/dev/null \
    | sed -E 's/^\(import //; s/\..*//' | LC_ALL=C sort -u || true
}
in_subset() { # <name> -> 0 when member
  case " $SUBSET " in *" $1 "*) return 0;; *) return 1;; esac
}

# Arm 1 over $LIBROOT. Prints offending lines; quiet and 0 when clean.
arm_closure() {
  local m seen todo cur f dep n badlines=""
  for m in $SUBSET; do
    seen=" $m "
    todo="$m"
    n=0
    while [[ -n "$todo" && "$n" -lt 40 ]]; do
      n=$((n + 1))
      cur="${todo%% *}"
      if [[ "$todo" == *" "* ]]; then todo="${todo#* }"; else todo=""; fi
      [[ -z "$cur" ]] && continue
      f="$LIBROOT/$cur.ax"
      if [[ ! -f "$f" ]]; then
        badlines="$badlines$m reaches $cur, which has no file to read
"
        continue
      fi
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if ! in_subset "$dep"; then
          badlines="$badlines$m reaches $dep, outside the subset ($SUBSET)
"
          continue
        fi
        case "$seen" in
          *" $dep "*) ;;
          *) seen="$seen$dep "; todo="$todo $dep" ;;
        esac
      done < <(direct_imports "$f")
    done
    if (( n >= 40 )); then
      badlines="$badlines$m: closure walk did not converge; the imports cycle outside the subset
"
    fi
  done
  printf '%s' "$badlines"
}

# Arm 2 over $LIBROOT. Prints offending lines; quiet when clean.
arm_extern() {
  local m
  for m in $SUBSET; do
    grep -HnE '^\((pub )?extern "' "$LIBROOT/$m.ax" 2>/dev/null || true
  done
}

# --------------------------------------------------------------------
echo "== 1. the import closure of every subset module stays inside =="
# --------------------------------------------------------------------
if out="$(arm_closure)"; [[ -n "$out" ]]; then
  bad "imports leave the freestanding subset:"
  printf '%s\n' "$out" | sed 's/^/     /' | head -8
else
  ok "eight modules, every transitive import inside the subset"
fi

# --------------------------------------------------------------------
echo
echo "== 2. no subset module declares an extern block =="
# --------------------------------------------------------------------
if out="$(arm_extern)"; [[ -n "$out" ]]; then
  bad "extern blocks in the freestanding subset, which no bare-metal target provides:"
  printf '%s\n' "$out" | sed 's/^/     /' | head -4
else
  ok "no extern block in any of the eight (the pattern finds Ffi's)"
fi

# --------------------------------------------------------------------
echo
echo "== 3. one probe over all eight builds clean on every target =="
# --------------------------------------------------------------------
cat > "$work/nostd-probe.ax" <<'AX'
(import Pre)
(import Mem)
(import Str)
(import Vec)
(import Map)
(import Fmt)
(import Utf8)
(import Err)

(:: main Int)
(fn (main)
  (let ((v (vecPush vecNew 7)))
    {
      (when true 0)
      (+ (vecLen v) (+ (mapLen mapNew) (+ (strLen (fmtInt 42)) (+ (utf8SeqLen 65) (+ (memAlloc 16) (+ errDivideByZero (if (isOk (divChecked 10 2)) 1 0)))))))
    }))
AX
printf '(:: main Int)\n\n(fn (main) 0)\n' > "$work/nostd-hello.ax"

# Seven of the eight leave a symbol in the IR; the eighth, Pre, is
# macros, which expand away - its import resolves or the build below
# fails, which is its whole assertion.
checks=$((checks + 1))
if ! "$axc" emit-llvm --input "$work/nostd-probe.ax" --output "$work/nostd-probe.ll" > "$work/nostd.emit" 2>&1; then
  bad "the subset probe would not emit:"
  sed 's/^/     /' "$work/nostd.emit" | head -6
else
  prob=0
  for sym in 'Vec$vecLen' 'Map$mapLen' 'Str$strLen' 'Mem$memAlloc' 'Fmt$fmtInt' 'Utf8$utf8SeqLen' 'Err$divChecked'; do
    grep -qF "$sym" "$work/nostd-probe.ll" || { bad "the probe never reaches $sym - a use was deleted while its import stayed"; prob=1; }
  done
  (( prob )) || ok "the probe reaches all seven code modules (Pre resolves by building)"
fi

# The host half: linked imports, probe against hello.
checks=$((checks + 1))
if ! "$axc" build --input "$work/nostd-probe.ax" --output "$work/nostd-probe.bin" > "$work/nostd.build" 2>&1; then
  bad "the subset probe would not build:"
  sed 's/^/     /' "$work/nostd.build" | head -6
elif ! "$axc" build --input "$work/nostd-hello.ax" --output "$work/nostd-hello.bin" > /dev/null 2>&1; then
  bad "the hello control would not build, so the comparison below compares nothing"
else
  imports_of "$work/nostd-probe.bin" | LC_ALL=C sort -u > "$work/nostd-probe.imports"
  imports_of "$work/nostd-hello.bin" | LC_ALL=C sort -u > "$work/nostd-hello.imports"
  if cmp -s "$work/nostd-probe.imports" "$work/nostd-hello.imports"; then
    n=$(grep -c . "$work/nostd-probe.imports" || true)
    ok "linked imports are the hello world's ($n distinct)"
  else
    bad "the subset probe imports what hello does not:"
    LC_ALL=C comm -13 "$work/nostd-hello.imports" "$work/nostd-probe.imports" | sed 's/^/     + /' | head -8
  fi
fi

# Every target: IR declares, probe against hello. A libc call the
# subset started emitting is a declare hello does not carry. The
# runtime declares alone are the floor: an empty declare list on
# either side means the reader broke, not that the surface is clean.
checks=$((checks + 1))
prob=0
for t in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64 windows-x86_64; do
  if ! "$axc" --target="$t" emit-llvm --input "$work/nostd-probe.ax" --output "$work/nostd-p.$t.ll" > "$work/nostd.emit" 2>&1; then
    bad "[$t] the subset probe would not emit"; prob=1; continue
  fi
  if ! "$axc" --target="$t" emit-llvm --input "$work/nostd-hello.ax" --output "$work/nostd-h.$t.ll" > /dev/null 2>&1; then
    bad "[$t] the hello control would not emit"; prob=1; continue
  fi
  declares_of "$work/nostd-p.$t.ll" > "$work/nostd-p.$t.declares"
  declares_of "$work/nostd-h.$t.ll" > "$work/nostd-h.$t.declares"
  if [[ ! -s "$work/nostd-h.$t.declares" ]] && [[ "$t" == windows-* ]]; then
    bad "[$t] the control declares nothing - the runtime alone writes six, so the reader broke"; prob=1; continue
  fi
  if cmp -s "$work/nostd-p.$t.declares" "$work/nostd-h.$t.declares"; then
    n=$(grep -c . "$work/nostd-p.$t.declares" || true)
    echo "     [$t] $n declares, the hello world's"
  else
    bad "[$t] the subset probe declares what hello does not:"
    LC_ALL=C comm -13 "$work/nostd-h.$t.declares" "$work/nostd-p.$t.declares" | sed 's/^/       + /' | head -6
    prob=1
  fi
done
(( prob )) || ok "seven targets declare nothing beyond hello"

# --------------------------------------------------------------------
echo
echo "== ablations: each breakage, planted =="
# --------------------------------------------------------------------
abl_copy() {
  rm -rf "$work/abl-$1"; mkdir -p "$work/abl-$1"
  cp -r "$repo_root/stdlib" "$work/abl-$1/stdlib"
}
# ABLATION 1: Str imports Sys. Arm 1 must name Sys.
abl_copy import-sys
printf '(import Sys)\n' >> "$work/abl-import-sys/stdlib/Str.ax"
if ! grep -q '^(import Sys)$' "$work/abl-import-sys/stdlib/Str.ax"; then
  bad "ablation import-sys: the plant did not land, so the arm proved nothing"
else
  LIBROOT="$work/abl-import-sys/stdlib"
  if out="$(arm_closure)"; [[ "$out" == *"Sys"* ]]; then
    ok "ablation import-sys: arm 1 names the planted import, so arm 1 can fail"
  else
    bad "ablation import-sys: arm 1 silent with Sys planted - it cannot fail"
  fi
  LIBROOT="$repo_root/stdlib"
fi
# ABLATION 2: Mem gains an extern block. Arm 2 must name it.
abl_copy extern-mem
printf '(pub extern "nope"\n  (nope :: (-> Int Int) (symbol "axffi_nope")))\n' >> "$work/abl-extern-mem/stdlib/Mem.ax"
if ! grep -q '^(pub extern "nope"' "$work/abl-extern-mem/stdlib/Mem.ax"; then
  bad "ablation extern-mem: the plant did not land, so the arm proved nothing"
else
  LIBROOT="$work/abl-extern-mem/stdlib"
  if out="$(arm_extern)"; [[ "$out" == *"Mem.ax"* ]]; then
    ok "ablation extern-mem: arm 2 names the planted block, so arm 2 can fail"
  else
    bad "ablation extern-mem: arm 2 silent with the block planted - it cannot fail"
  fi
  LIBROOT="$repo_root/stdlib"
fi

echo
if (( failed > 0 )); then
  echo "check-nostd-subset: $failed of $checks checks failed"
  exit 1
fi
echo "check-nostd-subset: $checks checks - eight modules, closed imports, no extern,"
echo "                    and one probe over all of them importing nothing hello does not"
