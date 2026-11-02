#!/usr/bin/env python3
"""Check Darwin timeout rounding and clamping without a 72-minute wait."""
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
with tempfile.TemporaryDirectory(prefix='axiom-wait-clamp-') as temporary:
    work = Path(temporary)
    library = work / 'stdlib'
    shutil.copytree(root / 'stdlib', library)
    wait = library / 'Internal/Wait.ax'
    original = wait.read_text()
    backend = ''';@axiom:effect(io)
;@axiom:effect(unsafe)
;@axiom:effect(block)
(fn (sysUlockWait addr expected us)
  (__syscall4 sysWaitWordNum 6 addr expected us))'''
    assert backend in original
    # Observe the argument at the syscall boundary; retain the production
    # conversion, clamp and result classification. Force that branch on Linux
    # too, so every host checks the overflow edge without sleeping for hours.
    observed = original.replace('(import Sys.Platform)', '(import Sys.Platform)\n(import IO)')
    observed = observed.replace('waitWordKind', '2').replace(backend, ''';@axiom:effect(io)
(fn (sysUlockWait addr expected us)
  { (println us) (- 0 eTimedOut) })''')
    (library / 'WaitClampFixture.ax').write_text('''(import Internal.Wait)
(import IO)
(pub :: waitClampProbe Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
;@axiom:effect(block)
(pub fn (waitClampProbe)
  { (let word (__alloc 8))
    { (__store64 word 0 7)
      (println (sysWaitWordTimeout word 7 1))
      (println (sysWaitWordTimeout word 7 1001))
      (println (sysWaitWordTimeout word 7 4294967295000))
      (println (sysWaitWordTimeout word 7 4294967295001))
      (println (sysWaitWordTimeout word 7 9223372036854775807))
      0 } })
''')
    entry = work / 'probe.ax'
    entry.write_text('''(import WaitClampFixture)
;@axiom:effect(io)
;@axiom:effect(block)
(fn (main) waitClampProbe)
''')
    env = dict(os.environ, AXIOM_STDLIB=str(library))
    env.pop('AXIOM_PATH', None)
    expected = '1\n1\n2\n1\n4294967295\n1\n4294967295\n0\n4294967295\n0\n'

    def run(source, level):
        wait.write_text(source)
        binary = work / 'probe'
        subprocess.run([compiler, 'build', '--input', str(entry), '--output',
                        str(binary), '--opt', str(level)], env=env, check=True,
                       capture_output=True, text=True)
        return subprocess.run([str(binary)], check=True, capture_output=True,
                              text=True, timeout=10).stdout

    for level in (0, 2):
        assert run(observed, level) == expected
    overflow = '(if (> nanos 4294967295000)'
    assert overflow in observed
    assert run(observed.replace(overflow, '(if false', 1), 0) != expected
    classification = '(sysWaitAnswer (sysUlockWait addr expected 4294967295) 1)'
    assert classification in observed
    assert run(observed.replace(classification, classification[:-2] + '0)', 1), 0) != expected
print('PASS: wait timeout rounding and clamp; overflow and timeout-classification controls')
