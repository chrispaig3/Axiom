#!/usr/bin/env python3
"""Exercise internal sockaddr layout in a copied library, with fault controls."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--axiom', required=True)
args = parser.parse_args()
compiler = str(Path(args.axiom).resolve())
root = Path(__file__).resolve().parents[2]
expected = (root / 'tests/net/socket-address-layout.out').read_text()
with tempfile.TemporaryDirectory(prefix='axiom-socket-layout-') as temporary:
    work = Path(temporary)
    library = work / 'stdlib'
    shutil.copytree(root / 'stdlib', library)
    shutil.copyfile(root / 'tests/net/socket-address-layout.axp',
                    library / 'AddressLayoutFixture.ax')
    entry = work / 'probe.ax'
    entry.write_text('(import AddressLayoutFixture)\n(:: main ())\n'
                     ';@axiom:effect(io)\n(fn (main) (addressLayoutProbe))\n')
    env = dict(os.environ, AXIOM_STDLIB=str(library))
    env.pop('AXIOM_PATH', None)

    def run(level):
        binary = work / 'probe'
        subprocess.run([compiler, 'build', '--input', str(entry), '--output',
                        str(binary), '--opt', str(level)], env=env, cwd=work,
                       check=True, text=True)
        return subprocess.run([str(binary)], check=True, capture_output=True,
                              text=True, timeout=30).stdout

    for level in range(4):
        actual = run(level)
        assert actual == expected, (level, actual)
    source = library / 'Internal/SocketAddress.ax'
    original = source.read_text()
    ports = '(rawPutByte buf 2 (& (>> port 8) 255))\n    (rawPutByte buf 3 (& port 255))'
    assert ports in original
    source.write_text(original.replace(ports,
        '(rawPutByte buf 2 (& port 255))\n    (rawPutByte buf 3 (& (>> port 8) 255))', 1))
    actual = run(0)
    assert actual != expected and '127.0.0.1:8080 -> 127.0.0.1:36895\n' in actual, actual
    zero = '(rawSet buf 0 netAddr6Bytes)'
    assert zero in original
    source.write_text(original.replace(zero, zero + '\n    (rawPutByte buf 4 1)', 1))
    actual = run(0)
    assert actual != expected and 'FAIL flowinfo is left zero\n' in actual, actual
print('PASS: socket address layout at O0-O3; port-order and flowinfo fault controls')
