#!/usr/bin/env bash
# Pin the numeric checker through LLVM emission, then execute checked
# polymorphic results. Seeded expression wrappers explore casts, local
# inference, branches, generic data and calls through closures.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

python3 - "$axc" "$work" "$repo_root" <<'PY'
import math
from pathlib import Path
import subprocess
import sys

axc, work, root = sys.argv[1:]
work = Path(work)
sys.path.insert(0, str(Path(root) / 'scripts/lib'))
from fuzz import Rng

prelude = '''
(:: identity (-> a a))
(fn (identity x) x)
(data Box a (Boxed a))
(:: take (-> (Box a) a))
(fn (take box) (match box ((Boxed x) x)))
'''
ops = ['+', '-', '*', '/', '%', '==', '!=', '<', '<=', '>', '>=']
rng = Rng(0xA8108)


def wrap(expr, ty, kind):
    if kind == 0:
        return expr
    if kind == 1:
        return f'(identity {expr})'
    if kind == 2:
        return f'(let ((v {expr})) v)'
    if kind == 3:
        return f'(if true {expr} {expr})'
    if kind == 4:
        return f'(take (Boxed {expr}))'
    if kind == 5:
        return f'((lambda (x) x) {expr})'
    if kind == 7:
        return f'(let ((v {expr})) (- (- v)))'
    other = 'Float' if ty == 'Int' else 'Int'
    return f'(cast {ty} (cast {other} {expr}))'


def call(*args):
    return subprocess.run([axc, '--diagnostic-format=ai', *args],
                          capture_output=True, text=True, timeout=30)


def refused(path):
    ir = work / 'refused.ll'
    ir.unlink(missing_ok=True)
    for command in [('check', str(path)),
                    ('emit-llvm', str(path), '-o', str(ir))]:
        result = call(*command)
        if result.returncode != 1 or 'E AX3004 ' not in result.stderr:
            raise AssertionError(f'{path.name}: {command[0]} accepted mixed '
                                 f'operands or refused for another reason\n'
                                 f'{result.stderr}')
    if ir.exists():
        raise AssertionError(f'{path.name}: refusal still wrote LLVM IR')


# Each operator in each order is mandatory; the seeded cases combine
# up to three independently chosen wrappers around each operand.
cases = [(op, rev, 0) for op in ops for rev in [False, True]]
cases += [(rng.choice(ops), bool(rng.below(2)), 1 + rng.below(3))
          for _ in range(96)]
for i, (op, rev, depth) in enumerate(cases):
    integer = '0' if depth == 0 else str(1 + rng.below(31))
    floating = f'{1 + rng.below(31)}.0'
    for _ in range(depth):
        integer = wrap(integer, 'Int', rng.below(8))
        floating = wrap(floating, 'Float', rng.below(8))
    left, right = (floating, integer) if rev else (integer, floating)
    path = work / f'mixed-{i}.ax'
    path.write_text(prelude + f'(fn (probe) ({op} {left} {right}))\n'
                    '(:: main Int)\n(fn (main) 0)\n')
    refused(path)
print(f'ok   {len(cases)} mixed operand cases refused by check and emit-llvm')

# A removed top type cannot be used to evade the numeric comparison.
path = work / 'any.ax'
path.write_text('(:: probe (-> Any Float))\n(fn (probe x) (+ x 1.0))\n'
                '(:: main Int)\n(fn (main) 0)\n')
result = call('check', str(path))
assert result.returncode == 1 and 'E AX3002 ' in result.stderr, result.stderr
print('ok   Any is refused as an unknown type')

# The native answers are compared with Python arithmetic, not with
# compiler-generated goldens. Values are exact binary quarters.
prints, expected = [], []
for _ in range(48):
    a, b = (1 + rng.below(120)) / 4, 1 + rng.below(8)
    op = rng.choice(['+', '-', '*', '/'])
    left, right = str(a), f'{b}.0'
    for _ in range(1 + rng.below(3)):
        left = wrap(left, 'Float', rng.below(8))
        right = wrap(right, 'Float', rng.below(8))
    value = {'+': lambda: a + b, '-': lambda: a - b,
             '*': lambda: a * b, '/': lambda: a / b}[op]()
    prints.append(f'(println (__floatToInt ({op} {left} {right})))')
    expected.append(str(math.trunc(value)))
path = work / 'checked.ax'
path.write_text('(import IO)\n' + prelude + '(:: main Int)\n'
                ';@axiom:effect(io)\n(fn (main) {\n' +
                '\n'.join(prints) + '\n0 })\n')
fixtures = [(path, '\n'.join(expected) + '\n'),
            (Path(root) / 'tests/stdlib/700-polymorphic-float.ax',
             (Path(root) / 'tests/stdlib/700-polymorphic-float.out').read_text())]
for opt in [0, 2]:
    for source, want in fixtures:
        binary = work / 'numeric'
        result = call('build', str(source), '--opt', str(opt), '-o', str(binary))
        assert result.returncode == 0, result.stderr
        result = subprocess.run([str(binary)], capture_output=True,
                                text=True, timeout=30)
        assert result.returncode == 0 and result.stdout == want, (
            f'{source.name} at --opt {opt}: {result.stderr}\n{result.stdout}')
print('ok   seeded arithmetic and polymorphic Float fixtures agree at --opt 0 and 2')
PY
