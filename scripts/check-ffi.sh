#!/usr/bin/env bash
# Assert that Axiom's FFI opens exactly the door it declares, and no other.
#
# This is the gate `docs/memory-model.md` MM-FFI-5 requires: the one that
# "enumerates permitted external symbols rather than forbidding all of
# them". It REPLACES check-freestanding.sh's blanket ban for programs
# that use the FFI, and leaves that ban fully in force for programs that
# do not.
#
# The distinction is the whole point, and it is measurable. The same
# Axiom program, built two ways on darwin-aarch64:
#
#   no FFI                        `nm -u` -> 0 symbols
#   + a no_std  Rust staticlib    `nm -u` -> 0 symbols
#   + a std     Rust staticlib    `nm -u` -> 188 symbols, 18 of them on
#                                 check-freestanding.sh's forbidden list
#
# So there are three tiers, not two, and this gate checks all three:
#
#   1. A program with no `extern` declaration imports NOTHING. This is
#      the old contract, unchanged, and it is what makes "the FFI costs
#      non-users nothing" a checked claim rather than a promise.
#   2. A program bound to a no_std crate ALSO imports nothing. The
#      freestanding property survives the FFI when the crate can live in
#      core+alloc, which is the mode to reach for.
#   3. A program bound to a std crate imports only what its manifest
#      permits. Every name outside the manifest is a failure.
#
# A gate that has never been seen to fail is a gate nobody has checked,
# so the negative probes at the end are not optional decoration - they
# are the reason to believe the three checks above.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Cargo is required HERE and nowhere else. `bootstrap-from-seed.sh` still
# goes from committed LLVM IR through llc and cc with no Rust toolchain,
# which is what lets a checkout with no cargo still produce a compiler.
# A machine without cargo skips this gate rather than failing it.
if ! command -v cargo > /dev/null 2>&1; then
  echo "skip: cargo not on PATH; the FFI gate needs it to build the Rust side"
  echo "      (the compiler itself never does - see scripts/bootstrap-from-seed.sh)"
  exit 0
fi

status=0

# The names that are never permitted, whatever a manifest says. A
# manifest is a statement about what a CRATE needs; it is not a licence
# to reintroduce a libc dependency through the back door for names Axiom
# implements itself.
never_permitted='printf|puts|fopen|fwrite|fread|system|popen|execv|execve|posix_spawn'

# `-D` reads the DYNAMIC symbol table, which a relocatable object file
# does not have - so on Linux the reader answered empty for every `.o`,
# and the negative probe that exists to catch exactly that ("the symbol
# reader does NOT see an undefined symbol") was the thing reporting it.
# Fall back to the static table when the dynamic one is empty.
#
# The `@VERSION` suffix goes too. ELF symbol versioning is a property of
# the LINKAGE - `_Unwind_Resume@GCC_3.0` and `_Unwind_Resume` are one
# name - and a manifest enumerates names. Without this, no Linux symbol
# could ever match a manifest entry, which is most of why this gate has
# never been green on linux-x86_64.
symbols_of() {
  case "$(uname -s)" in
    Darwin) nm -u "$1" 2>/dev/null | sed 's/^_//' | sort -u ;;
    *)
      local dyn
      dyn="$(nm -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}')"
      [[ -z "$dyn" ]] && dyn="$(nm --undefined-only "$1" 2>/dev/null | awk '{print $NF}')"
      printf '%s\n' "$dyn" | grep . | sed 's/@.*$//' | sort -u
      ;;
  esac
}

# What the platform's own C runtime puts in EVERY executable, measured
# with the same `cc` the compiler shells out to - not a hardcoded list
# and not a manifest entry.
#
# On Mach-O this is empty, which is why the gate's header could say "no
# FFI -> nm -u -> 0 symbols" and mean it. On ELF it never is: `crt1.o`
# brings `__libc_start_main`, `__cxa_finalize`, `__gmon_start__` and the
# two `_ITM_*` transactional-memory stubs into a program that does
# nothing at all. Those are not a door Axiom opened and no manifest
# should have to list them.
#
# It cannot hide an FFI symbol: the floor is measured from a C program
# that links no Axiom archive and no Rust crate, so a name only reaches
# it by being what the linker adds unprompted.
platform_floor() {
  local c="$work/floor.c" exe="$work/floor.exe"
  printf 'int main(void){return 0;}\n' > "$c"
  cc "$c" -o "$exe" 2>/dev/null || return 0
  symbols_of "$exe"
}
floor_file="$work/platform-floor.txt"
platform_floor > "$floor_file" 2>/dev/null || : > "$floor_file"
echo "ok   platform floor: $(grep -c . "$floor_file" || true) symbol(s) the C runtime adds to any executable"

# `symbols_of` minus the floor.
imports_of() {
  symbols_of "$1" > "$work/imports.tmp"
  comm -23 "$work/imports.tmp" "$floor_file" || true
}

# ---------------------------------------------------------------
# Tier 1: a program with no `extern` imports nothing at all.
#
# check-freestanding.sh already sweeps tests/stdlib for this. What it
# cannot say is that adding the FFI to the LANGUAGE left those programs
# alone, so this re-asserts it against the FFI corpus's own non-FFI
# cases - the ones most likely to regress if `emitDecl` grew a arm that
# fires too eagerly.
# ---------------------------------------------------------------
tier1=0
for case_file in tests/ffi/no-extern/*.ax; do
  [[ -e "$case_file" ]] || break
  name="$(basename "$case_file" .ax)"
  exe="$work/t1-$name"
  if ! "$axiom" build --input "$case_file" --output "$exe" > "$work/t1-$name.log" 2>&1; then
    echo "FAIL $name: could not build"; sed 's/^/    /' "$work/t1-$name.log" | head -3
    status=1; continue
  fi
  imports="$(imports_of "$exe")"
  if [[ -n "$imports" ]]; then
    echo "FAIL $name: a program with no \`extern\` imports symbols beyond the platform floor"
    printf '%s\n' "$imports" | sed 's/^/    /' | head -10
    status=1; continue
  fi
  tier1=$((tier1 + 1))
done
echo "ok   $tier1 programs with no \`extern\` import nothing"
[[ "$tier1" -ge 3 ]] || { echo "FAIL only $tier1 cases reached the no-extern pass"; status=1; }

# ---------------------------------------------------------------
# Tiers 2 and 3: a program bound to a Rust crate imports only what that
# crate's manifest permits.
#
# The manifest lives beside the crate as `axiom-allow.txt`: one symbol
# name per line, `#` comments, blank lines ignored. It is checked in, so
# a crate that starts needing a new libc symbol changes a reviewed file
# rather than silently widening the boundary.
# ---------------------------------------------------------------
for crate_dir in rust/examples/*/; do
  [[ -d "$crate_dir" ]] || continue
  crate="$(basename "$crate_dir")"
  # A manifest is a MEASUREMENT of what a crate's dependencies require,
  # and that differs by platform: the darwin list names `_NSGetArgv` and
  # `_dyld_*`, the linux one names `__errno_location` and the libgcc
  # unwinder. One file cannot be both, and applying the darwin one on
  # linux is why every case here failed.
  manifest="$crate_dir/axiom-allow.$(uname -s | tr '[:upper:]' '[:lower:]').txt"
  [[ -f "$manifest" ]] || manifest="$crate_dir/axiom-allow.txt"
  [[ -f "$manifest" ]] || continue
  # `leaky` is the negative probe and is expected to FAIL; sweeping it
  # here would report its designed failure as a gate failure. It is
  # probed at the end, where the failure is the passing outcome.
  [[ "$crate" == "leaky" ]] && continue

  # `examples/nostd` is its own workspace (cargo unifies features across
  # members, and std's `panic_impl` collides with the one the
  # `nostd-runtime` feature defines),
  # so it is built by manifest path and its artifacts land under its own
  # target directory.
  if grep -q '^\[workspace\]' "$crate_dir/Cargo.toml"; then
    ( cd rust && cargo build --release -q --manifest-path "examples/$crate/Cargo.toml" ) \
      || { echo "FAIL $crate: cargo build failed"; status=1; continue; }
    lib="rust/examples/$crate/target/release/libaxiom_${crate//-/_}.a"
  else
    ( cd rust && cargo build --release -q -p "axiom-$crate" ) \
      || { echo "FAIL $crate: cargo build failed"; status=1; continue; }
    lib="rust/target/release/libaxiom_${crate//-/_}.a"
  fi
  [[ -f "$lib" ]] || { echo "FAIL $crate: no staticlib at $lib"; status=1; continue; }

  # `|| true` is load-bearing, and this script's own history is the
  # argument for it: the `nostd` manifest permits NOTHING, so every line
  # in it is a comment, so `grep -v` matches nothing and exits 1 - and
  # under `set -e` a bare `x="$(cmd)"` whose command exits non-zero takes
  # the whole script down. Measured: the gate printed its tier-1 and
  # tier-3 lines, then vanished before every negative probe, and exited
  # 0. A gate that skips its own probes and reports success is worse than
  # no gate. `check-freestanding.sh` records the identical trap at its
  # `foreign` probe; this one was written anyway.
  permitted="$(grep -vE '^\s*(#|$)' "$manifest" | tr -d ' \t' | sort -u || true)"
  n_permitted="$(printf '%s\n' "$permitted" | grep -c . || true)"

  # A manifest may not launder a name from the never-permitted list.
  if bad="$(printf '%s\n' "$permitted" | grep -E "^($never_permitted)$" || true)"; [[ -n "$bad" ]]; then
    echo "FAIL $crate: manifest permits names that are never permitted:"
    printf '%s\n' "$bad" | sed 's/^/    /'
    status=1; continue
  fi

  for case_file in tests/ffi/"$crate"/*.ax; do
    [[ -e "$case_file" ]] || break
    name="$(basename "$case_file" .ax)"
    exe="$work/$crate-$name"
    # `--crate DIR` is the whole build line: the generated `.ax`
    # binding module in `DIR/axiom` is searched for imports, so a case
    # that imports it exercises what `axiom-bindgen` actually wrote -
    # the out-cell and handle wrappers included - and the archive is
    # found under the crate's or its workspace's `target/release` and
    # linked because the `extern` block names it. For the `nostd`
    # crate, whose archive sits in its own target directory, the same
    # flag finds it one level down.
    if ! "$axiom" build --input "$case_file" --output "$exe" \
         --crate "$repo_root/$crate_dir" \
         > "$work/$crate-$name.log" 2>&1; then
      echo "FAIL $crate/$name: could not build"
      sed 's/^/    /' "$work/$crate-$name.log" | head -5
      # An AX4004 says the compiler could not find the symbol in the
      # archive. Whether the ARCHIVE is missing it or the compiler's
      # scan is, is the whole question, and the archive can answer it
      # here instead of over another round of CI.
      if grep -q 'AX4004' "$work/$crate-$name.log"; then
        want="$(sed -n 's/.*no linked archive defines `\([A-Za-z0-9_]*\)`.*/\1/p' "$work/$crate-$name.log" | head -1)"
        if [[ -n "$want" ]]; then
          echo "    ---- what $lib actually defines ----"
          if nm --defined-only "$lib" 2>/dev/null | grep -q "[ ]$want\$"; then
            echo "    the archive DOES define $want - the compiler's scan missed it"
          else
            echo "    the archive does NOT define $want"
          fi
          echo "    nearest axffi_ names in the archive:"
          nm --defined-only "$lib" 2>/dev/null | awk '{print $NF}' | grep '^axffi_' | sort -u | head -12 | sed 's/^/      /'
          # `blobDefines` requires the name NUL-delimited on BOTH sides -
          # `\0name\0` - so print the bytes either side of every
          # occurrence. If none is so delimited, that is the answer.
          echo "    every occurrence, with the byte on each side:"
          python3 - "$lib" "$want" <<'BYTES' | head -12 | sed 's/^/      /'
import sys
data = open(sys.argv[1], 'rb').read()
name = sys.argv[2].encode()
i = 0; n = 0
while n < 10:
    j = data.find(name, i)
    if j < 0: break
    before = data[j-1:j]; after = data[j+len(name):j+len(name)+1]
    print(f'off={j} before={before!r} after={after!r} delimited={before==b"\x00" and after==b"\x00"}')
    i = j + 1; n += 1
if n == 0: print('the byte scan finds no occurrence at all')
BYTES
        fi
      fi
      status=1; continue
    fi

    # RUN it. A gate that builds a program and never runs it cannot
    # tell a silent wrong answer from a pass, and the FFI's whole
    # failure class is the silent wrong answer: a Rust parameter named
    # `cell` shadowed by the wrapper's out-cell, a status returned as a
    # value. The trailer `; expect N` is the contract, as in
    # tests/selfhost; a case that prints an `...: agree` line must
    # print it.
    want="$(tail -n 1 "$case_file" | sed -n 's/^; expect \([0-9]*\).*/\1/p')"
    [[ -n "$want" ]] || want=0
    set +e
    out="$("$exe" 2>&1)"; got=$?
    set -e
    if [[ "$got" != "$want" ]]; then
      echo "FAIL $crate/$name: exit $got, expected $want"
      printf '%s\n' "$out" | sed 's/^/    /' | head -5
      status=1; continue
    fi
    # `agree` is looked for in the CODE, not in the comments. A case
    # whose prose merely discusses the word was required to print it,
    # which cost a real half-hour on 2026-08-24: 115-abort-status.ax
    # exited with exactly the status it declared and failed anyway,
    # because a sentence about the status used the word.
    if sed 's/;.*//' "$case_file" | grep -q 'agree' && ! printf '%s\n' "$out" | grep -q 'agree'; then
      echo "FAIL $crate/$name: ran to exit $got but never printed its \`agree\` line"
      printf '%s\n' "$out" | sed 's/^/    /' | head -5
      status=1; continue
    fi

    unexpected="$(comm -23 <(imports_of "$exe") <(printf '%s\n' "$permitted" | grep . || true) || true)"
    if [[ -n "$unexpected" ]]; then
      echo "FAIL $crate/$name: imports symbols no manifest permits:"
      # NOT truncated. A manifest is repaired by reading this list, and a
      # `head -20` on a set of ninety turns one fix into five rounds.
      printf '%s\n' "$unexpected" | sed 's/^/    /'
      echo "    (add them to $manifest if they are genuinely required)"
      status=1; continue
    fi
    echo "ok   $crate/$name runs (exit $got) and imports only the $n_permitted permitted symbol(s)"
  done
done

# ---------------------------------------------------------------
# A PROJECT CAN DECLARE ITS NATIVE DEPENDENCY, not only pass it as a
# flag. `axiom.pkg`'s `crate DIR` (2026-09-03) puts `DIR/axiom/` on the
# module search path and `DIR`'s three `target/release` directories on
# the link search path - the same two lists `--crate DIR` feeds.
#
# WHY IT IS HERE AND NOT ONLY IN check-packages.sh. That gate is
# cargo-free by design and proves the module half with a fake crate.
# This is the half that needs a real `libaxiom_demo.a`: the archive is
# found and linked with NO command-line flag at all, which is the
# property a third-party native package rests on. Measured on 0.7.3
# before the key existed: the same tree, the same archive, declared
# through `$AXIOM_PATH` exited 0 and declared in `axiom.pkg` exited 4
# with AX4004.
#
# It reuses the archive the tiers above already built, so it costs one
# `axiom build` rather than a cargo run.
mkdir -p "$work/pkgcrate"
cp tests/ffi/demo/010-add.ax "$work/pkgcrate/app.ax"
cat > "$work/pkgcrate/axiom.pkg" <<EOF
name  pkgcrate
crate $repo_root/rust/examples/demo
EOF
if ( cd "$work/pkgcrate" && "$axiom" build app.ax --output prog ) \
     > "$work/pkgcrate.log" 2>&1; then
  got_out="$( cd "$work/pkgcrate" && ./prog 2>&1 )" || true
  if [[ "$got_out" == "42" ]]; then
    echo "ok   a manifest \`crate\` links the archive with no flags, and the program answers 42"
  else
    echo "FAIL a manifest-declared crate built but answered '$got_out', expected 42"
    status=1
  fi
else
  echo "FAIL a manifest \`crate\` did not link the demo archive"
  sed 's/^/    /' "$work/pkgcrate.log" | head -8
  status=1
fi

# THE NEGATIVE PROBE, and it is what makes the check above mean
# anything: with the manifest moved aside and nothing else changed, the
# identical command must fail with AX4004. Without it the section would
# pass on a stray `$AXIOM_PATH` or a `-L` from somewhere else being
# what found the archive.
mv "$work/pkgcrate/axiom.pkg" "$work/pkgcrate/axiom.pkg.off"
rm -f "$work/pkgcrate/prog"
if ( cd "$work/pkgcrate" && "$axiom" build app.ax --output prog ) \
     > "$work/pkgcrate-off.log" 2>&1; then
  echo "FAIL the program still linked with no manifest - \`crate\` is not what found the archive"
  status=1
elif grep -q 'AX4004' "$work/pkgcrate-off.log"; then
  echo "ok   negative probe: without the manifest the same build is AX4004"
else
  echo "FAIL without the manifest the build failed, but not with AX4004"
  sed 's/^/    /' "$work/pkgcrate-off.log" | head -6
  status=1
fi

# ---------------------------------------------------------------
# The generated bindings are checked in, and are REGENERATED here and
# compared. `axiom-bindgen` reads the Rust source and the proc macro
# reads the same annotations; two independent passes over one input can
# drift, and this is what notices. Same shape as check-fmt-selfhost.sh's
# corpus golden: a checked-in artefact compared against a fresh one.
# ---------------------------------------------------------------
for crate_dir in rust/examples/*/; do
  [[ -d "$crate_dir" ]] || continue
  crate="$(basename "$crate_dir")"
  gen="$crate_dir/axiom"
  [[ -d "$gen" ]] || continue
  for committed in "$gen"/*.ax; do
    [[ -e "$committed" ]] || break
    module="$(basename "$committed" .ax)"
    fresh="$work/$module.regen.ax"
    if ! ( cd rust && cargo run --release -q -p axiom-bindgen -- \
             --src "examples/$crate/src" --lib "axiom_${crate//-/_}" \
             --module "$module" -o "$fresh" ) >/dev/null 2>&1; then
      echo "FAIL $crate: axiom-bindgen could not regenerate $module"; status=1; continue
    fi
    if ! diff -q "$committed" "$fresh" >/dev/null 2>&1; then
      echo "FAIL $crate/$module: the checked-in bindings differ from a fresh generation"
      { diff "$committed" "$fresh" || true; } | head -10 | sed 's/^/    /'
      status=1
    else
      echo "ok   $crate/$module is what axiom-bindgen generates today"
    fi
  done
done

# ---------------------------------------------------------------
# Negative probes. Everything above asserts a set relation, and a set
# relation is also satisfied by an empty corpus, a `nm` that answers
# nothing, and a manifest that permits everything.
# ---------------------------------------------------------------

# 1. `symbols_of` actually reports something. If it silently answers
#    empty for every input, tiers 1-3 all pass vacuously.
probe_c="$work/probe.c"
cat > "$probe_c" <<'PROBE'
extern long some_undefined_symbol_xyz(long);
int main(void) { return (int)some_undefined_symbol_xyz(1); }
PROBE
if cc -c "$probe_c" -o "$work/probe.o" 2>/dev/null; then
  if symbols_of "$work/probe.o" | grep -q '^some_undefined_symbol_xyz$'; then
    echo "ok   negative probe: the symbol reader reports an undefined symbol"
  else
    echo "FAIL negative probe: the symbol reader does NOT see an undefined symbol"
    echo "     every tier above would pass vacuously"
    status=1
  fi
else
  echo "FAIL negative probe: could not compile the symbol-reader probe"
  status=1
fi

# 2. The manifest comparison REFUSES a symbol outside the permitted set.
#    Checked on the comparison itself, not on a build, so it is exercised
#    on every run rather than only when something is already broken.
permitted_probe="$(printf 'alpha\nbeta\n')"
actual_probe="$(printf 'alpha\ngamma\n')"
missed="$(comm -23 <(printf '%s\n' "$actual_probe") <(printf '%s\n' "$permitted_probe"))"
if [[ "$missed" == "gamma" ]]; then
  echo "ok   negative probe: the manifest comparison flags an unpermitted symbol"
else
  echo "FAIL negative probe: the manifest comparison answered '$missed', expected 'gamma'"
  status=1
fi

# 3. And it DISCRIMINATES - a permitted symbol is not flagged. A
#    comparison that reported everything would satisfy probe 2 while
#    failing every real build.
kept="$(comm -23 <(printf 'alpha\n') <(printf '%s\n' "$permitted_probe"))"
if [[ -z "$kept" ]]; then
  echo "ok   negative probe: the manifest comparison leaves permitted symbols alone"
else
  echo "FAIL negative probe: the manifest comparison flagged the permitted '$kept'"
  status=1
fi

# 4. The source-level door still reports the RIGHT thing for the retired
#    keyword. `foreign` stays AX2004 forever: old source must keep
#    getting migration advice rather than being silently reinterpreted,
#    and the FFI is spelled `extern`, not `foreign`.
ffi_probe="$work/foreign-probe.ax"
cat > "$ffi_probe" <<'PROBE'
(foreign posix_spawn :: (-> Int Int Int Int Int Int) = "posix_spawn")
(pub :: main Int)
(pub fn (main) (posix_spawn 0 0 0 0 0))
PROBE
if probe_out="$("$axiom" --diagnostic-format=ai check "$ffi_probe" 2>&1)"; then
  echo "FAIL negative probe: a \`foreign\` binding compiles - it must stay AX2004"
  status=1
elif ! grep -q 'AX2004' <<< "$probe_out"; then
  echo "FAIL negative probe: \`foreign\` is refused, but not as a removed construct"
  printf '%s\n' "$probe_out" | sed 's/^/    /' | head -3
  status=1
else
  echo "ok   negative probe: \`foreign\` is still refused as a removed construct (AX2004)"
fi

# 5. P4 - THE ALLOWLIST CAN GO RED.
#
#    Every tier above asserts that a program's imports are a SUBSET of
#    what its manifest permits, and a subset relation is also satisfied
#    by an empty import set, a `nm` that answers nothing, and a manifest
#    that permits everything. `rust/examples/leaky` calls
#    `std::env::var` - dragging in `getenv` - against a manifest that
#    deliberately lists nothing, so the comparison MUST produce
#    unpermitted symbols. The failure is the passing outcome.
leaky_dir="rust/examples/leaky"
if [[ -d "$leaky_dir" ]]; then
  if ( cd rust && cargo build --release -q -p axiom-leaky ) 2>/dev/null; then
    leaky_exe="$work/leaky-probe"
    if AXIOM_PATH="$repo_root/$leaky_dir/axiom" \
       "$axiom" build --input tests/ffi/probe-leaky/010-uses-env.ax --output "$leaky_exe" \
       --link-lib axiom_leaky --link-search rust/target/release >/dev/null 2>&1; then
      leaky_permitted="$(grep -vE '^\s*(#|$)' "$leaky_dir/axiom-allow.txt" | tr -d ' \t' | sort -u || true)"
      leaky_bad="$(comm -23 <(symbols_of "$leaky_exe") <(printf '%s\n' "$leaky_permitted" | grep . || true) || true)"
      if [[ -n "$leaky_bad" ]]; then
        echo "ok   negative probe: the allowlist goes RED on a crate that leaks ($(printf '%s\n' "$leaky_bad" | grep -c .) unpermitted)"
      else
        echo "FAIL negative probe: the leaky crate imported nothing unpermitted"
        echo "     every tier above is passing vacuously"
        status=1
      fi
    else
      echo "FAIL negative probe: could not build the leaky probe"
      status=1
    fi
  else
    echo "FAIL negative probe: could not build rust/examples/leaky"
    status=1
  fi
fi

# 6. P5 - AN UNGROUNDED SYMBOL IS REFUSED BEFORE THE TOOLCHAIN.
#
#    This is the probe that tells the FFI apart from the `foreign` it
#    replaced. `foreign` emitted a call to an undeclared symbol, passed
#    `check`, and died two stages later inside `opt`. So this requires
#    AX4004 AND requires the strings `opt:` and `AX4003` to be ABSENT:
#    a refusal arriving from the native toolchain is the old bug wearing
#    a new name, and only their absence tells the two apart.
ung="tests/ffi/probe-ungrounded/020-missing-symbol.axbad"
if [[ -f "$ung" ]]; then
  if ung_out="$("$axiom" --diagnostic-format=ai build --input "$ung" --output "$work/ung" \
                 --link-lib axiom_demo --link-search rust/target/release 2>&1)"; then
    echo "FAIL negative probe: an extern naming a symbol nothing defines still BUILT"
    status=1
  elif ! grep -q 'AX4004' <<< "$ung_out"; then
    echo "FAIL negative probe: the ungrounded symbol was refused, but not as AX4004"
    printf '%s\n' "$ung_out" | sed 's/^/    /' | head -3
    status=1
  elif grep -qE 'opt:|AX4003' <<< "$ung_out"; then
    echo "FAIL negative probe: the refusal came from the TOOLCHAIN, not the compiler"
    echo "     that is the \`foreign\` bug wearing a new name"
    printf '%s\n' "$ung_out" | sed 's/^/    /' | head -3
    status=1
  else
    echo "ok   negative probe: an ungrounded symbol is AX4004, before opt or cc runs"
  fi
fi

# 7. P6 - A PREFIX OF A REAL SYMBOL IS NOT THAT SYMBOL.
#
#    The grounding check used to be a substring scan over the archive
#    bytes, so `axffi_ad` grounded against `axffi_add` and died in the
#    linker as AX4003 "put cc on PATH". It reads whole names now, and
#    names the neighbour it found.
pre="tests/ffi/probe-ungrounded/030-prefix-of-symbol.axbad"
if [[ -f "$pre" ]]; then
  if pre_out="$("$axiom" --diagnostic-format=ai build --input "$pre" --output "$work/pre" \
                 --crate "$repo_root/rust/examples/demo" 2>&1)"; then
    echo "FAIL negative probe: a prefix of a real symbol still BUILT"
    status=1
  elif ! grep -q 'AX4004' <<< "$pre_out"; then
    echo "FAIL negative probe: the prefix was refused, but not as AX4004"
    printf '%s\n' "$pre_out" | sed 's/^/    /' | head -3
    status=1
  elif ! grep -q 'axffi_add' <<< "$pre_out"; then
    echo "FAIL negative probe: AX4004 did not name the neighbouring symbol"
    printf '%s\n' "$pre_out" | sed 's/^/    /' | head -3
    status=1
  else
    echo "ok   negative probe: a prefix of a real symbol is AX4004, naming the real one"
  fi
fi

# 8. P7 - NOTHING LINKED is its own message, at the item.
nol="tests/ffi/probe-ungrounded/040-nothing-linked.axbad"
if [[ -f "$nol" ]]; then
  if nol_out="$("$axiom" --diagnostic-format=ai build --input "$nol" --output "$work/nol" 2>&1)"; then
    echo "FAIL negative probe: an extern with nothing linked still BUILT"
    status=1
  elif ! grep -q 'no archive is linked' <<< "$nol_out"; then
    echo "FAIL negative probe: nothing linked was not reported as such"
    printf '%s\n' "$nol_out" | sed 's/^/    /' | head -3
    status=1
  else
    echo "ok   negative probe: nothing linked is said in those words, at the item"
  fi
fi

# 9. P8 - A SHAPE THE CRATE DOES NOT EXPORT IS REFUSED.
#
#    Every `#[axiom_export]` shim carries a descriptor beside it, and a
#    two-argument declaration over the three-argument `axffi_add` is
#    AX4005 at the item rather than a call that reads a third register.
shp="tests/ffi/probe-ungrounded/050-shape-mismatch.axbad"
if [[ -f "$shp" ]]; then
  if shp_out="$("$axiom" --diagnostic-format=ai build --input "$shp" --output "$work/shp" \
                 --crate "$repo_root/rust/examples/demo" 2>&1)"; then
    echo "FAIL negative probe: a declaration of the wrong shape still BUILT"
    status=1
  elif ! grep -q 'AX4005' <<< "$shp_out"; then
    echo "FAIL negative probe: the wrong shape was refused, but not as AX4005"
    printf '%s\n' "$shp_out" | sed 's/^/    /' | head -3
    status=1
  else
    echo "ok   negative probe: a declaration of the wrong shape is AX4005, at the item"
  fi
fi

# ---------------------------------------------------------------
# The other direction: an Axiom library ARCHIVED for a Rust host.
# `--emit-staticlib` writes tests/ffi/host/hostlib.ax as an archive
# with no `main`; rust/examples/host links it and calls two Axiom
# functions, one of them over a String the host built with the
# archive's own `Str$strAlloc`.
# ---------------------------------------------------------------
hostlib="tests/ffi/host/hostlib.ax"
if [[ -f "$hostlib" && -d rust/examples/host ]]; then
  mkdir -p "$work/hostlib"
  if ! "$axiom" build --input "$hostlib" --output "$work/hostlib/libaxiom_hostlib.a" \
         --emit-staticlib --emit-rust-binding "$work/hostlib/hostlib.rs" > "$work/hostlib/build.log" 2>&1; then
    echo "FAIL host: could not emit the static archive"; sed 's/^/    /' "$work/hostlib/build.log" | head -5
    status=1
  elif nm "$work/hostlib/libaxiom_hostlib.a" 2>/dev/null | grep -qE ' T _?main$'; then
    echo "FAIL host: the archive defines \`main\`; a host has its own"
    status=1
  elif command -v rustfmt >/dev/null 2>&1 && ! cmp -s "$work/hostlib/hostlib.rs" rust/examples/host/src/hostlib.rs; then
    # The checked-in binding IS the generated one (the build runs
    # `rustfmt` over it when one is on PATH, and the checked-in copy
    # is that formatted file): a host that compiled against a stale
    # file would be calling shapes the archive no longer has. Without
    # rustfmt the raw text cannot be compared to the formatted copy,
    # and the run below is the check.
    echo "FAIL host: rust/examples/host/src/hostlib.rs differs from a fresh --emit-rust-binding"
    { diff rust/examples/host/src/hostlib.rs "$work/hostlib/hostlib.rs" || true; } | head -6 | sed 's/^/    /'
    status=1
  elif command -v rustfmt >/dev/null 2>&1 && ! rustfmt --edition 2021 --check "$work/hostlib/hostlib.rs" >/dev/null 2>&1; then
    echo "FAIL host: the generated binding is not rustfmt-clean"
    status=1
  elif ! host_out="$(cd rust && AXIOM_HOST_ARCHIVE_DIR="$work/hostlib" cargo run --release -q -p axiom-host 2>&1)"; then
    echo "FAIL host: the Rust host did not build or run"
    printf '%s\n' "$host_out" | sed 's/^/    /' | head -8
    status=1
  elif ! grep -q ' agree$' <<< "$host_out"; then
    echo "FAIL host: the Rust host ran but what it got back from Axiom did not agree"
    printf '%s\n' "$host_out" | sed 's/^/    /' | head -5
    status=1
  else
    echo "ok   host: a Rust binary calls the Axiom archive through its generated binding ($host_out)"
  fi
fi

# --------------------------------------------------------------------
# The HAND-WRITTEN Rust: clippy and rustfmt.
# --------------------------------------------------------------------
# Until 2026-09-03 neither ran anywhere. `.github/workflows/ci.yml`
# invoked only `cargo test --workspace --exclude axiom-host`, and its own
# comment records that `cargo fmt` and `cargo clippy` were dropped when
# the old Rust compiler was deleted - but the FFI workspace is still
# ~9,500 lines of hand-written Rust, most of it unsafe. The only rustfmt
# in this gate was the one above, over the file the compiler GENERATES.
#
# That is the gap that let the rest of this commit's findings stand: every
# boundary handle auto-`Send`, 116 unsafe operations unmarked inside
# `unsafe fn` bodies, 33 unsafe blocks with no `// SAFETY:` line, and 30
# undocumented public items. A tool with no gate is a tool nobody runs.
#
# `-D warnings` rather than a count, because the lint policy in
# `rust/Cargo.toml` is where the decisions live: a lint that should not
# fire is `allow`ed THERE, with the reason, and one that fires is a
# finding. `axiom-host` is excluded for the same reason `ci.yml` excludes
# it - it links a real Axiom archive and needs $AXIOM_HOST_ARCHIVE_DIR.
echo "== the hand-written Rust: clippy and rustfmt =="
if ! command -v cargo >/dev/null 2>&1; then
  echo "ok   cargo is not installed; the Rust lint pass is skipped (reported, not silent)"
elif ! cargo clippy --version >/dev/null 2>&1; then
  echo "ok   clippy is not installed; the lint pass is skipped (reported, not silent)"
else
  if clippy_out="$(cd rust && cargo clippy --workspace --exclude axiom-host \
                     --all-targets --quiet -- -D warnings 2>&1)"; then
    echo "ok   clippy is clean over the workspace under -D warnings"
  else
    echo "FAIL clippy reported findings in the hand-written Rust"
    printf '%s\n' "$clippy_out" | grep -E '^(error|warning)' | head -8 | sed 's/^/     /'
    status=1
  fi
  # AND THE `host` FEATURE, for the same reason as `nostd-runtime` below:
  # no workspace member enables it, so the sweep above never compiles
  # `axiom-ffi/src/host.rs` at all. Measured 2026-09-03, the first time
  # anything looked: four `doc_list_item_without_indentation`, one
  # `should_implement_trait`, and two undocumented public methods - on
  # the file that IS the Rust-calls-Axiom direction. `--all-targets`
  # works here (unlike the nostd pass), there being no panic handler to
  # collide with std's.
  if host_out="$(cd rust && cargo clippy -p axiom-ffi --features host \
                   --all-targets --quiet -- -D warnings 2>&1)"; then
    echo "ok   clippy is clean over the host feature under -D warnings"
  else
    echo "FAIL clippy reported findings in the host-direction binding"
    printf '%s\n' "$host_out" | grep -E '^(error|warning)' | head -6 | sed 's/^/     /'
    status=1
  fi
  # AND THE `nostd-runtime` FEATURE, SEPARATELY, because the sweep above
  # cannot reach it. No workspace member enables it, so
  # `--workspace --all-targets` never compiles it - measured: zero
  # mentions in that run's output. It is also the module that most needs
  # a lint gate: raw `asm!` syscalls for four targets, a `GlobalAlloc`, a
  # panic handler, and hand-written `memcpy`/`memmove`/`memset`/`memcmp`/
  # `bcmp`/`bzero`/`strlen`. On 2026-09-03 it carried 14 warnings unique
  # to this path, seven of them `missing_safety_doc` on the libc shims,
  # and it did not compile at all under edition 2024.
  #
  # NO `--all-targets` HERE, and the reason is structural rather than a
  # preference: the `lib test` target links std, and a `#[panic_handler]`
  # in a `no_std` crate then collides with std's - `error[E0152]: found
  # duplicate lang item panic_impl`. The library target is the whole of
  # what this feature has.
  if nostd_out="$(cd rust && cargo clippy -p axiom-ffi --no-default-features \
                    --features nostd-runtime --quiet -- -D warnings 2>&1)"; then
    echo "ok   clippy is clean over the nostd-runtime feature under -D warnings"
  else
    echo "FAIL clippy reported findings in the freestanding runtime"
    printf '%s\n' "$nostd_out" | grep -E '^(error|warning)' | head -6 | sed 's/^/     /'
    status=1
  fi
  if ! command -v rustfmt >/dev/null 2>&1; then
    echo "ok   rustfmt is not installed; the format check is skipped (reported)"
  elif ( cd rust && cargo fmt --all --check >/dev/null 2>&1 ); then
    echo "ok   every Rust file is rustfmt-clean (style_edition 2021, pinned in rust/rustfmt.toml)"
  else
    echo "FAIL the hand-written Rust is not rustfmt-clean; run \`cargo fmt --all\` in rust/"
    ( cd rust && cargo fmt --all --check 2>&1 ) | grep '^Diff in' \
      | sed 's/Diff in //; s/:.*//' | sort -u | head -6 | sed 's/^/     /'
    status=1
  fi
fi

exit "$status"
