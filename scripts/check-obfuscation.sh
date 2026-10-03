#!/usr/bin/env bash
# Optional obfuscation must preserve execution, omit original literals
# and names from native binaries, retain its volatile control flow at
# O3, and pack assets without compiling their plaintext source.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

for level in 0 1 3; do
  bin="$work/obfuscated.O$level"
  "$axc" build --diagnostic-format=ai --obfuscate --emit-llvm \
    --opt "$level" "$repo_root/tests/obfuscation/Main.ax" -o "$bin"
  "$bin" --obfuscate > "$work/out"
  diff -u tests/obfuscation/Main.out "$work/out"
  python3 - "$bin" <<'PY'
from pathlib import Path
import sys
binary = Path(sys.argv[1]).read_bytes()
for plain in [b'AXIOM_PRIVATE_LITERAL_42e159a0', b'distinctiveStrategy', b'quoted!c', b'obfuscation/Main.ax']:
    assert plain not in binary, f'{plain!r} remains in the binary'
PY
  echo "ok   obfuscated binary: execution and absent plaintext at O$level"
done

# Ordinary builds still expose the literal: this ablation proves the
# binary scan would detect a disabled transformation.
"$axc" build --diagnostic-format=ai tests/obfuscation/Main.ax -o "$work/plain"
python3 - "$work/plain" <<'PY'
from pathlib import Path
import sys
assert b'AXIOM_PRIVATE_LITERAL_42e159a0' in Path(sys.argv[1]).read_bytes()
PY
"$axc" run --diagnostic-format=ai tests/obfuscation/Main.ax --obfuscate > "$work/run"
diff -u tests/obfuscation/Main.out "$work/run"

if command -v opt >/dev/null; then
  opt -S -O3 "$work/obfuscated.O3.ll" -o "$work/optimised.ll"
  grep -q 'load volatile i32' "$work/optimised.ll"
  grep -q 'br i1 %obf.test' "$work/optimised.ll"
fi
"$axc" emit-llvm --diagnostic-format=ai --obfuscate tests/obfuscation/Main.ax -o "$work/second.ll"
if cmp -s "$work/obfuscated.O3.ll" "$work/second.ll"; then
  echo 'FAIL: obfuscation reused a build seed' >&2
  exit 1
fi

for target in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-aarch64 freebsd-x86_64 windows-x86_64 windows-aarch64 baremetal-aarch64; do
  "$axc" emit-llvm --diagnostic-format=ai --obfuscate --target "$target" \
    tests/obfuscation/Main.ax -o "$work/$target.ll"
  llc -filetype=obj "$work/$target.ll" -o "$work/$target.o"
done

for flags in '--obfuscate=true' '--obfuscate --emit-staticlib'; do
  # Intentional word splitting: these are fixed flag lists, never user input.
  if "$axc" build --diagnostic-format=ai $flags tests/obfuscation/Main.ax -o "$work/refused" > "$work/refused.log" 2>&1; then
    echo "FAIL: accepted $flags" >&2; exit 1
  fi
  [[ ! -e "$work/refused" ]]
done

"$axc" build --diagnostic-format=ai examples/axobfuscate/Main.ax -o "$work/pack"
python3 - "$work/input" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b'AXIOM_PRIVATE_ASSET_9d214c\x00\xff\n')
PY
"$work/pack" "$work/input" "$work/Packed.ax" 'asset/test/v1'
cp tests/obfuscation/AssetUser.ax "$work/Main.ax"
"$axc" build --diagnostic-format=ai "$work/Main.ax" -o "$work/asset"
"$work/asset" > "$work/decoded"
cmp "$work/input" "$work/decoded"
python3 - "$work/Packed.ax" "$work/asset" <<'PY'
from pathlib import Path
import sys
for path in sys.argv[1:]:
    assert b'AXIOM_PRIVATE_ASSET_9d214c' not in Path(path).read_bytes(), path
PY
"$work/pack" "$work/input" "$work/Packed2.ax" 'asset/test/v1'
if cmp -s "$work/Packed.ax" "$work/Packed2.ax"; then
  echo 'FAIL: packing reused an envelope or key' >&2; exit 1
fi
echo 'ok   authenticated asset round trip, absent plaintext and fresh packing'
