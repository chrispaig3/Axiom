#!/usr/bin/env python3
"""Constant-time taint check over optimised LLVM IR.

Usage: ct-taint.py [--present-only] <module.ll> <spec> [<spec> ...]

Each <spec> is `<llvm-name>=<params>`, where <llvm-name> is the
function's IR name without `@` or quotes (`Crypto.Ct$ctSelect`) and
<params> is the `ct(...)` claim's value: a comma-separated list of
parameter names, a bare name for a secret VALUE and `*name` for an
address whose POINTEE is secret. Every other parameter is public.

The analysis is intraprocedural over the function as `opt` left it, so
whatever was inlined is checked where it landed. Taint is one of:

  S  a secret value
  M  an address (int or ptr) into secret memory, public itself

and propagates to a fixpoint through phis. A value loaded through an M
address is S; a value loaded through any other address is public (the
claim says which memory is secret). It reports, per function:

  branch   `br`/`switch` on an S value
  select   `select` on an S condition (the backend may branch)
  address  a load, store or getelementptr index that is S
  divide   `udiv`/`sdiv`/`urem`/`srem` with an S operand
  call     a call to a function that is not a checked kernel, with an
           S or M argument (inline asm and llvm intrinsics are fine)

Exit status 0 when every named function is clean and was found, 1
otherwise. A function that is not in the module is a failure: a check
that found nothing to check is not a pass. With `--present-only` an
absent function is skipped instead, for a caller that runs this over
several modules and asks separately whether each claim was checked in
at least one; every function checked prints `checked <name>`.
"""
import re, sys

def parse_functions(text):
    funcs = {}
    cur = None
    for line in text.split('\n'):
        if line.startswith('define '):
            m = re.search(r'@("([^"]+)"|([\w.$]+))\((.*)\)', line)
            name = m.group(2) or m.group(3)
            params = []
            for p in split_args(m.group(4)):
                pm = re.search(r'%([\w.$"]+)\s*$', p.strip())
                params.append(pm.group(1).strip('"') if pm else None)
            cur = (name, params, [])
            funcs[name] = cur
        elif cur is not None:
            if line.startswith('}'):
                cur = None
            else:
                cur[2].append(line)
    return funcs

def split_args(s):
    out, depth, buf = [], 0, ''
    for c in s:
        if c in '([{<':
            depth += 1
        elif c in ')]}>':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(buf); buf = ''
        else:
            buf += c
    if buf.strip():
        out.append(buf)
    return out

VAL = re.compile(r'%[\w.$"]+')

def operands(s):
    return [v[1:].strip('"') for v in VAL.findall(s)]

def check(name, params, body, secret_vals, secret_mems, kernels):
    taint = {}
    for p in params:
        if p is None:
            continue
        if p in secret_vals:
            taint[p] = 'S'
        elif p in secret_mems:
            taint[p] = 'M'
    def t(v):
        return taint.get(v)
    problems = []
    changed = True
    rounds = 0
    while changed and rounds < 50:
        changed = False
        rounds += 1
        problems = []
        for raw in body:
            line = raw.split(';')[0] if not re.search(r'asm\s', raw) else raw
            line = line.strip()
            if not line or line.endswith(':'):
                continue
            m = re.match(r'%([\w.$"]+)\s*=\s*(.*)$', line)
            res = m.group(1).strip('"') if m else None
            rhs = m.group(2) if m else line
            op = rhs.split()[0] if rhs.split() else ''
            if op in ('tail', 'musttail', 'notail'):
                op = rhs.split()[1]
            ops = operands(rhs)
            new = None
            if op == 'br':
                bm = re.match(r'br i1 %([\w.$"]+)', rhs)
                if bm and t(bm.group(1).strip('"')) == 'S':
                    problems.append(('branch', raw.strip()))
            elif op == 'switch':
                sm = re.match(r'switch \S+ %([\w.$"]+)', rhs)
                if sm and t(sm.group(1).strip('"')) == 'S':
                    problems.append(('branch', raw.strip()))
            elif op == 'select':
                sm = re.match(r'select (?:\w+ )*i1 %([\w.$"]+)', rhs)
                if sm and t(sm.group(1).strip('"')) == 'S':
                    problems.append(('select', raw.strip()))
                new = 'S' if any(t(o) == 'S' for o in ops) else None
            elif op in ('udiv', 'sdiv', 'urem', 'srem'):
                if any(t(o) == 'S' for o in ops):
                    problems.append(('divide', raw.strip()))
                new = 'S' if any(t(o) in ('S', 'M') for o in ops) else None
            elif op == 'load':
                am = re.search(r'ptr %([\w.$"]+)', rhs)
                a = am.group(1).strip('"') if am else None
                if a and t(a) == 'S':
                    problems.append(('address', raw.strip()))
                    new = 'S'
                elif a and t(a) == 'M':
                    new = 'S'
            elif op == 'store':
                am = re.search(r'ptr %([\w.$"]+)\s*(,|$)', rhs)
                a = am.group(1).strip('"') if am else None
                if a and t(a) == 'S':
                    problems.append(('address', raw.strip()))
            elif op == 'getelementptr':
                parts = split_args(rhs[len('getelementptr'):])
                base = operands(parts[1]) if len(parts) > 1 else []
                idx = [o for p in parts[2:] for o in operands(p)]
                if any(t(o) == 'S' for o in idx):
                    problems.append(('address', raw.strip()))
                    new = 'S'
                elif base and t(base[0]) in ('M', 'S'):
                    new = t(base[0])
            elif op == 'call' or op == 'invoke':
                if ' asm ' in rhs or 'asm sideeffect' in rhs:
                    new = 'S' if any(t(o) in ('S', 'M') for o in ops) else None
                else:
                    cm = re.search(r'@("([^"]+)"|([\w.$]+))\(', rhs)
                    callee = (cm.group(2) or cm.group(3)) if cm else ''
                    args = ops
                    tainted = any(t(o) in ('S', 'M') for o in args)
                    if callee.startswith('llvm.'):
                        new = 'S' if tainted else None
                    elif tainted and callee not in kernels:
                        problems.append(('call', raw.strip()))
                        new = 'S'
                    elif tainted:
                        new = 'S'
            elif op == 'phi':
                ts = [t(o) for o in ops]
                new = 'S' if 'S' in ts else ('M' if 'M' in ts else None)
            elif op in ('icmp', 'fcmp'):
                new = 'S' if any(t(o) in ('S',) for o in ops) else None
            elif op in ('inttoptr', 'ptrtoint', 'bitcast', 'zext', 'sext', 'trunc', 'freeze'):
                new = t(ops[0]) if ops else None
            elif op in ('add', 'sub', 'or', 'and', 'xor', 'shl', 'lshr', 'ashr', 'mul'):
                ts = [t(o) for o in ops]
                if 'S' in ts:
                    new = 'S'
                elif 'M' in ts:
                    new = 'M'
            elif op in ('extractvalue', 'insertvalue'):
                ts = [t(o) for o in ops]
                new = 'S' if 'S' in ts else ('M' if 'M' in ts else None)
            if res is not None and new is not None and taint.get(res) != new:
                if taint.get(res) != 'S':
                    taint[res] = new
                    changed = True
    return problems

def main():
    argv = sys.argv[1:]
    present_only = False
    if argv and argv[0] == '--present-only':
        present_only = True
        argv = argv[1:]
    if len(argv) < 2:
        print(__doc__)
        return 2
    text = open(argv[0], encoding='utf-8').read()
    funcs = parse_functions(text)
    specs = []
    for arg in argv[1:]:
        name, _, params = arg.partition('=')
        vals = set(); mems = set()
        for p in params.split(','):
            p = p.strip()
            if not p:
                continue
            if p.startswith('*'):
                mems.add(p[1:])
            else:
                vals.add(p)
        specs.append((name, vals, mems))
    kernels = {s[0] for s in specs}
    bad = 0
    for name, vals, mems in specs:
        if name not in funcs:
            if not present_only:
                print(f"MISSING {name}: not defined in {argv[0]}")
                bad += 1
            continue
        _, params, body = funcs[name]
        missing = [p for p in vals | mems if p not in params]
        if missing:
            print(f"CLAIM {name}: names {', '.join(sorted(missing))}, which is not a parameter")
            bad += 1
            continue
        probs = check(name, params, body, vals, mems, kernels)
        print(f"checked {name}")
        if probs:
            bad += 1
            print(f"FAIL {name}")
            for kind, line in probs[:8]:
                print(f"   {kind}: {line[:150]}")
        else:
            print(f"ok   {name}")
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
