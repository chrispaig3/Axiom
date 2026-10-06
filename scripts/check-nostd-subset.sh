#!/usr/bin/env bash
# The freestanding subset: the eight standard-library modules a
# bare-metal program may import, checked rather than assumed.
#
# docs/embedded-guide.md says `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`,
# `Utf8` and `Err` assume no filesystem, process model or sockets, while
# `Sys`, `IO`, `Path`, `Net`, `Rpc` and `Par` do. This gate holds that
# split in three arms, each catching a different breakage:
#
#   1. Closure. The transitive imports of every subset module stay inside
#      the subset, found by a fixed-point walk over the `(import ...)`
#      lines. A `Str` that imported `Sys` would still build and pass every
#      golden; only this arm notices. A dotted name counts as its top
#      level (`Sys.Platform` is `Sys`). Only subset files are read, so an
#      outside name is reported rather than followed.
#   2. No extern. No subset module declares an `extern` block, the other
#      way out of a freestanding program: it names a symbol no bare-metal
#      target provides, and the import walk can't see it. The pattern
#      `^\((pub )?extern "` matches a block header with its library
#      string, and not prose (`an extern block`) or identifiers
#      (`externTypeRefusal`).
#   3. End to end. One probe importing all eight builds for every
#      supported target, and its import surface must equal hello world's:
#      linked imports on the host, IR declares elsewhere. The comparison
#      is differential, so check-freestanding.sh's libc-name table has
#      no second copy here to drift from it. A libc call the subset starts
#      emitting shows up as a declare hello doesn't carry. The probe calls
#      into seven of the eight (`Pre` is macros, which leave no symbol)
#      and each call is asserted in the IR, so a use can't be deleted
#      while its import stays.
#
# The ablations run on a copy of `stdlib/`: a planted `(import Sys)` in
# `Str` must turn arm 1 red, and a planted `extern` block in `Mem` must
# turn arm 2 red. Each checks its plant landed before reading the arm,
# so a plant that missed is reported as one and never read as an arm
# that can't fail.
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

# The library under test: the checkout's, unless an ablation points
# elsewhere.
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

# Seven of the eight leave a symbol in the IR. `Pre` is macros, which
# expand away, so its only assertion is that its import resolves and the
# build below succeeds.
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

# Every target: IR declares, probe against hello. A libc call the subset
# starts emitting is a declare hello doesn't carry. On Windows the runtime
# always declares some functions, so an empty list for hello there means
# the reader broke.
checks=$((checks + 1))
prob=0
for t in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64 windows-x86_64 windows-aarch64; do
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
(( prob )) || ok "eight targets declare nothing beyond hello"

# --------------------------------------------------------------------
echo
echo "== ablations: each breakage, planted =="
# --------------------------------------------------------------------
abl_copy() {
  rm -rf "$work/abl-$1"; mkdir -p "$work/abl-$1"
  cp -r "$repo_root/stdlib" "$work/abl-$1/stdlib"
}
# Ablation 1: Str imports Sys. Arm 1 must name Sys.
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
# Ablation 2: Mem gains an extern block. Arm 2 must name it.
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
