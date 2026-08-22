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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
fi
export AXIOM_STDLIB="$repo_root/stdlib"

# Cargo is required HERE and nowhere else. `bootstrap-from-seed.sh` still
# goes from committed LLVM IR through llc and cc with no Rust toolchain,
# which is what lets a checkout with no cargo still produce a compiler.
# A machine without cargo skips this gate rather than failing it.
if ! command -v cargo > /dev/null 2>&1; then
  echo "skip: cargo not on PATH; the FFI gate needs it to build the Rust side"
  echo "      (the compiler itself never does - see scripts/bootstrap-from-seed.sh)"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
status=0

# The names that are never permitted, whatever a manifest says. A
# manifest is a statement about what a CRATE needs; it is not a licence
# to reintroduce a libc dependency through the back door for names Axiom
# implements itself.
never_permitted='printf|puts|fopen|fwrite|fread|system|popen|execv|execve|posix_spawn'

symbols_of() {
  case "$(uname -s)" in
    Darwin) nm -u "$1" 2>/dev/null | sed 's/^_//' | sort -u ;;
    *)      nm -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' | sort -u ;;
  esac
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
  imports="$(symbols_of "$exe")"
  if [[ -n "$imports" ]]; then
    echo "FAIL $name: a program with no \`extern\` imports symbols"
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
  manifest="$crate_dir/axiom-allow.txt"
  [[ -f "$manifest" ]] || continue
  # `leaky` is the negative probe and is expected to FAIL; sweeping it
  # here would report its designed failure as a gate failure. It is
  # probed at the end, where the failure is the passing outcome.
  [[ "$crate" == "leaky" ]] && continue

  # `examples/nostd` is its own workspace (cargo unifies features across
  # members, and std's `panic_impl` collides with its `#[panic_handler]`),
  # so it is built by manifest path and its artifacts land under its own
  # target directory.
  if grep -q '^\[workspace\]' "$crate_dir/Cargo.toml"; then
    ( cd rust && cargo build --release -q --manifest-path "examples/$crate/Cargo.toml" ) \
      || { echo "FAIL $crate: cargo build failed"; status=1; continue; }
    lib="rust/examples/$crate/target/release/libaxiom_${crate//-/_}.a"
    search="rust/examples/$crate/target/release"
  else
    ( cd rust && cargo build --release -q -p "axiom-$crate" ) \
      || { echo "FAIL $crate: cargo build failed"; status=1; continue; }
    lib="rust/target/release/libaxiom_${crate//-/_}.a"
    search="rust/target/release"
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
    if grep -q 'agree' "$case_file" && ! printf '%s\n' "$out" | grep -q 'agree'; then
      echo "FAIL $crate/$name: ran to exit $got but never printed its \`agree\` line"
      printf '%s\n' "$out" | sed 's/^/    /' | head -5
      status=1; continue
    fi

    unexpected="$(comm -23 <(symbols_of "$exe") <(printf '%s\n' "$permitted" | grep . || true) || true)"
    if [[ -n "$unexpected" ]]; then
      echo "FAIL $crate/$name: imports symbols no manifest permits:"
      printf '%s\n' "$unexpected" | sed 's/^/    /' | head -20
      echo "    (add them to $manifest if they are genuinely required)"
      status=1; continue
    fi
    echo "ok   $crate/$name runs (exit $got) and imports only the $n_permitted permitted symbol(s)"
  done
done

# ---------------------------------------------------------------
# The generated bindings are checked in, and are REGENERATED here and
# compared. `axiom-bindgen` reads the Rust source and the proc macro
# reads the same annotations; two independent passes over one input can
# drift, and this is what notices. Same shape as `check-fmt.sh --check`.
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
      diff "$committed" "$fresh" | head -10 | sed 's/^/    /'
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
    diff rust/examples/host/src/hostlib.rs "$work/hostlib/hostlib.rs" | head -6 | sed 's/^/    /'
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

exit "$status"
