#!/usr/bin/env python3
"""axiom-report: a per-function resource report, the restricted profile,
and a machine-code stack bound, for one Axiom program (R-D1).

WHAT IT READS. Two things the toolchain already produces, and nothing it
has to guess:

  * the compiler's own call graph and effect rows -
    `axiom --diagnostic-format=ai [--target T] symbols --calls --builtins
    FILE` - one `F` row per function with `#effects=` (the transitive
    effect row, a fixpoint the checker computes), `#calls=` (the
    resolved call edges), `#effect-params=` (a body that calls one of its
    own parameters), `#effects-incomplete` / `#effects-possible=` (the
    row's own admissions that it is a bound), `#effect=` (declared
    effects; `#effect=unsafe` is AX3073's checked marker of a body that
    calls an Unsafe primitive DIRECTLY), `#isr`, `#restrict=` (claims)
    and `#extern` (an `extern` item);
  * for `--stack`, the object file `llc` writes for the same IR with
    `-stack-size-section -function-sections`: each function's static
    frame from `.stack_sizes`, and its direct calls and tail calls from
    the relocations `llc` had to leave (R_AARCH64_CALL26 / JUMP26), with
    every indirect call site cross-checked against the post-`opt` IR.

THE PROFILE (`--profile restricted`) is a set of refusals over everything
reachable from the roots - `main`, every `#isr` row, and `--root NAME`:

  RP-1 recursion      no call-graph cycle. With `--stack`, a cycle the
                      machine code shows to be tail calls only (a loop:
                      no frame accumulates) is admitted and reported as
                      an obligation instead; termination stays the
                      program's.
  RP-2 indirect       no call the graph cannot follow: a body calling a
                      parameter (`#effect-params=`), a row that admits it
                      is a bound (`#effects-incomplete`,
                      `#effects-possible=`), or a call to `__call_word`.
  RP-3 foreign        no `extern` item, except one named by
                      `--allow-foreign NAME`.
  RP-4 concurrency    no spawn or join primitive: the profile is one
                      thread of control plus interrupt handlers.
  RP-5 steady state   from each steady root - every `#isr`, every row
                      claiming `restrict(no-alloc)`, and `--steady NAME`
                      - no allocation (`Alloc` in the row, which is
                      transitive).
  RP-6 unresolved     every `#calls=` edge resolves to a row. An edge
                      this tool cannot resolve is a refusal, never a
                      silent leaf.
  RP-7 stack          with `--stack`: the bound exists (no non-tail
                      cycle, no dynamic stack, no call into code with no
                      frame size) and, with `--stack-budget N`, is at
                      most N bytes including one interrupt frame.
  RP-8 blocking       no `#isr` row, and no `--nonblocking NAME` root,
                      reaches a call that may suspend it: a join, or a
                      body passing one of `BLOCKING_KERNEL`'s syscall
                      numbers (read, write, open, a child wait, accept,
                      connect, a poll wait, a futex or ulock wait).
  RP-9 inline asm     no `asm` form (MM-FFI-9), except in a function
                      named by `--allow-asm NAME`. The tool can't see
                      what the instructions do - whether they allocate,
                      block, trap or use stack - so each is a reviewed
                      exception rather than a fact it reads.

and obligations it lists but does not refuse, because they are the
explicit trusted boundary rather than a defect: every reachable function
that calls an Unsafe primitive directly (`#effect=unsafe`), every function
holding an `asm` form, every kernel
entry (`__syscallN`; on baremetal-aarch64 the compiler lowers these to
the no-syscall trap), IO, the stack analysis's assumptions, and each
root's trap statuses and whether it may block.

TRAPS. Each function's `traps` is the set of MM-EXEC-16 statuses a call
from it can end the process with: 72 and 83 for `/` and `%`, 84 for
`<<` and `>>`, 77 for `__indexTrap`, 80 for a contract, 82 for an
atomic, 75 and 76 for an arena reset, 78 for a spawn or join, 70
wherever the row has `Alloc`, and 71 wherever it holds a declared
effect (unless a caller handles it). The set is closed over the call
graph. Until 0.8.0 the `INT_MIN / -1` and overshift corners were
undefined rather than trapped, and the report listed them per function
under `undefined`; that field is gone with them.

WHAT IT DOES NOT DO, stated so a green report is not over-read:

  * it does not decide termination or execution time. A bounded stack is
    not a bounded latency; nothing here is a WCET bound;
  * a trap with no edge in the graph is not in a function's set: count
    exhaustion from the retains the compiler emits, stack exhaustion,
    and a CPU fault from an Unsafe access. The report names them;
  * "may block" is a property of the syscall number, not of the file
    descriptor: a `read` of a regular file is marked, and a `write` to
    one too, because the graph can't tell a file from a pipe;
  * the source graph is the checker's: a call the checker resolved is an
    edge, and code the compiler EMITS without a source call (retain,
    release, the allocator, trap exits) is visible only to `--stack`,
    which reads the machine code - that is what `--stack` is for;
  * `--stack` supports AArch64 and x86-64 ELF objects
    (baremetal-aarch64, linux-aarch64, linux-x86_64, freebsd-*); not
    Mach-O or PE. On x86-64 a call and a tail jump are read off the
    opcode byte before the relocated displacement, every frame is
    charged the 8-byte return address a call pushes, and indirect
    sites come from the IR alone. Frame sizes are those of the analysis object, built
    from the same IR at the same `--opt` with two extra llc flags that
    change section placement, not frames; an indirect call is assumed to
    reach only an address-taken function (a code pointer forged from an
    integer by `__call_word` breaks that, and `__call_word` is Unsafe);
    the C runtime's and the reset vector's own stack use are outside
    the object and are stated, not measured.

Exit status: 0 no refusal, 1 refusals, 2 the tool could not answer
(a compiler, llc or parse failure) - never 0 for an answer it did not
compute.
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

SPAWN_RE = re.compile(r'^__(par|thread|proc)_spawn')
JOIN_RE = re.compile(r'^__(par|thread|proc)_join')
KERNEL_RE = re.compile(r'^__syscall[0-6]$')
# The primitive an `asm` form lowers to (MM-FFI-9): `__asm.N`, N inputs.
ASM_RE = re.compile(r'^__asm\.[0-9]+$')
INDIRECT_BUILTINS = {'__call_word'}

# The builtins whose call can end the process with a trap status
# (MM-EXEC-16). The graph shows each as a leaf of the function whose body
# calls it: `/` and `%` trap on a zero divisor (72) and on `INT_MIN /
# -1` (83), `<<` and `>>` trap on an out-of-range amount (84),
# `__indexTrap` is `vecGet`'s range refusal, `__contract` a violated
# `pre`/`post`, the arena reset a bad mark (75) or a mark past a live
# handle (76).
TRAP_LEAVES = {'/': (72, 83), '%': (72, 83), '<<': (84,), '>>': (84,),
               '__indexTrap': (77,), '__contract': (80,),
               '__axiom_arena_reset': (75, 76), '__axiom_arena_reset_keeping': (75, 76)}
ATOMIC_RE = re.compile(r'^__atomic_')
BUILTIN_EFFECTS = {'IO', 'Alloc', 'Mut', 'Unsafe', 'Div', 'Pure'}

# The kernel entries that may suspend the caller until another party
# acts, named by the syscall-number constants every `Sys.Platform`
# module declares (the graph has an edge to the constant a body reads):
# `read` and `write` on a pipe, socket or terminal; `open` of a FIFO;
# waiting for a child; `accept` and `connect`; `epoll_wait`/`kevent`;
# a futex or `__ulock` wait, the timed forms included. A join blocks
# until its child ends.
BLOCKING_KERNEL = {'sysReadNum', 'sysWriteNum', 'sysOpenNum', 'sysOpenatNum', 'sysWait4Num',
                   'sysWaitIdNum', 'sysAcceptNum', 'sysConnectNum', 'sysPollWaitNum',
                   'sysWaitWordNum'}


class ReportError(Exception):
    pass


# --------------------------------------------------------------------
# The source graph
# --------------------------------------------------------------------

ROW_RE = re.compile(r'^F (\S+) (\S+) "((?:[^"\\]|\\.)*)"(?: (@[0-9a-f]+))?(.*)$')


def parse_metas(tail):
    """`#key=value` and `#flag` tokens. A key may repeat - two effect
    tags render as `#effect=io #effect=unsafe` - so every value is kept:
    `metas[k]` is the last (what `symTagFrom` answers for the
    compiler-owned keys, which come after the author's), and
    `metas['all:' + k]` is every value in order."""
    metas = {}
    for tok in re.findall(r'#(\S+)', tail):
        if '=' in tok:
            k, v = tok.split('=', 1)
        else:
            k, v = tok, True
        metas[k] = v
        metas.setdefault('all:' + k, []).append(v)
    return metas


def module_of(path, root_file, bases):
    """The qualifier `#calls=` spells for a row declared in `path`:
    '' for the root file, `Mod.Sub` for a module - its path under the
    root file's directory or the standard library, `.ax` and any
    platform suffix (`Platform.darwin.ax`) removed."""
    ap = os.path.realpath(path)
    if ap == os.path.realpath(root_file):
        return ''
    for base in [os.path.dirname(os.path.realpath(root_file))] + bases:
        if base and ap.startswith(base + os.sep):
            rel = ap[len(base) + 1:]
            parts = rel.split(os.sep)
            parts[-1] = parts[-1].split('.')[0]
            return '.'.join(parts)
    # A search-path module outside both bases: its file stem.
    return os.path.basename(ap).split('.')[0]


class Fn:
    __slots__ = ('qname', 'name', 'module', 'loc', 'metas', 'builtin',
                 'calls', 'effects')

    def __init__(self, name, module, loc, metas, builtin):
        self.name = name
        self.module = module
        self.qname = (module + '$' + name) if module else name
        self.loc = loc
        self.metas = metas
        self.builtin = builtin
        self.calls = [c for c in metas.get('calls', '').split(',') if c] if not builtin else []
        self.effects = set(e for e in metas.get('effects', '').split(',') if e)

    def flag(self, k):
        return k in self.metas


def load_source_graph(axiom, src, target):
    cmd = [axiom, '--diagnostic-format=ai']
    if target:
        cmd.append('--target=' + target)
    cmd += ['symbols', '--calls', '--builtins', src]
    p = subprocess.run(cmd, capture_output=True)
    out = p.stdout.decode('utf-8', 'replace')
    err = p.stderr.decode('utf-8', 'replace')
    # An error is an AXDL line on stderr. Only stderr is read for errors:
    # `E` is also the AXSYM kind of an `effect` declaration on stdout.
    errors = [l for l in err.splitlines() if re.match(r'E AX\d{4} ', l)]
    if errors:
        raise ReportError('the program does not check:\n' + '\n'.join(errors[:10]))
    if p.returncode != 0 or not out.strip():
        raise ReportError('`%s` exited %d:\n%s' % (' '.join(cmd), p.returncode, err[:2000]))
    # The search roots the compiler itself uses, in its order (its
    # AX5001 message lists them): `$AXIOM_PATH`, the standard library
    # beside the binary and one level up, then `self_host/` and
    # `stdlib/` relative to the working directory. A module found
    # through a root missing here would be named by its file stem,
    # its `#calls=` spelling would not resolve, and RP-6 would say so.
    bases = [os.path.realpath(b) for b in os.environ.get('AXIOM_PATH', '').split(':') if b]
    exe = shutil.which(axiom) or axiom
    for rel in ('../stdlib', '../../stdlib'):
        bases.append(os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(exe)), rel)))
    for rel in ('self_host', 'stdlib'):
        bases.append(os.path.realpath(rel))
    fns = {}
    for line in out.splitlines():
        if not line.startswith('F '):
            continue
        m = ROW_RE.match(line)
        if not m:
            raise ReportError('an F row this tool cannot parse: ' + line[:200])
        name, loc, _ty, _nid, tail = m.groups()
        metas = parse_metas(tail)
        builtin = loc == '-'
        path = loc.rsplit(':', 3)[0] if not builtin else ''
        module = '' if builtin else module_of(path, src, bases)
        f = Fn(name, module, loc, metas, builtin)
        if f.qname in fns and not builtin:
            raise ReportError('two rows claim %s' % f.qname)
        fns.setdefault(f.qname, f)
    return fns


def resolve(fns, caller, callee):
    """The row `callee` names from `caller`'s `#calls=`, or None."""
    if callee in fns:
        return fns[callee]
    # A bare name inside a module: a same-module call spelled bare.
    if '$' not in callee and caller.module:
        q = caller.module + '$' + callee
        if q in fns:
            return fns[q]
    return None


class Graph:
    def __init__(self, fns, roots):
        self.fns = fns
        self.roots = roots
        self.edges = {}       # qname -> [qname] (functions only)
        self.leaves = {}      # qname -> [builtin names]
        self.unresolved = {}  # qname -> [spelling]
        for f in fns.values():
            if f.builtin:
                continue
            es, ls, us = [], [], []
            for c in f.calls:
                t = resolve(fns, f, c)
                if t is None:
                    us.append(c)
                elif t.builtin:
                    ls.append(t.qname)
                else:
                    es.append(t.qname)
            self.edges[f.qname] = es
            self.leaves[f.qname] = ls
            self.unresolved[f.qname] = us

    def reach(self, roots):
        """BFS from `roots`: answers {qname: parent} (roots map to None)."""
        par = {}
        todo = []
        for r in roots:
            if r not in par:
                par[r] = None
                todo.append(r)
        while todo:
            n = todo.pop(0)
            for m in self.edges.get(n, []):
                if m not in par:
                    par[m] = n
                    todo.append(m)
        return par

    @staticmethod
    def path(par, n):
        out = []
        while n is not None:
            out.append(n)
            n = par[n]
        return list(reversed(out))

    def sccs(self, nodes):
        """Tarjan, iterative: the strongly connected components of the
        subgraph over `nodes`."""
        nodes = set(nodes)
        index, low, onstack, stack, out = {}, {}, set(), [], []
        counter = [0]
        for s in sorted(nodes):
            if s in index:
                continue
            work = [(s, iter(self.edges.get(s, [])))]
            index[s] = low[s] = counter[0]; counter[0] += 1
            stack.append(s); onstack.add(s)
            while work:
                v, it = work[-1]
                advanced = False
                for w in it:
                    if w not in nodes:
                        continue
                    if w not in index:
                        index[w] = low[w] = counter[0]; counter[0] += 1
                        stack.append(w); onstack.add(w)
                        work.append((w, iter(self.edges.get(w, []))))
                        advanced = True
                        break
                    elif w in onstack:
                        low[v] = min(low[v], index[w])
                if advanced:
                    continue
                work.pop()
                if work:
                    low[work[-1][0]] = min(low[work[-1][0]], low[v])
                if low[v] == index[v]:
                    comp = []
                    while True:
                        w = stack.pop(); onstack.discard(w)
                        comp.append(w)
                        if w == v:
                            break
                    out.append(sorted(comp))
        return out

    def cycle_through(self, comp):
        """A concrete cycle inside one SCC, as a path that repeats its
        first node - `a -> b -> a`, or `f -> f`."""
        cs = set(comp)
        start = comp[0]
        par = {start: None}
        todo = [start]
        while todo:
            n = todo.pop(0)
            for m in self.edges.get(n, []):
                if m == start:
                    return self.path(par, n) + [start]
                if m in cs and m not in par:
                    par[m] = n
                    todo.append(m)
        return [start, start]


# --------------------------------------------------------------------
# The machine-code stack bound (AArch64 and x86-64 ELF)
# --------------------------------------------------------------------

R_AARCH64_ABS64 = 257
R_AARCH64_JUMP26 = 282
R_AARCH64_CALL26 = 283
EM_AARCH64 = 183
EM_X86_64 = 62
R_X86_64_PC32 = 2
R_X86_64_PLT32 = 4


def uleb(data, i):
    v = s = 0
    while True:
        b = data[i]; i += 1
        v |= (b & 0x7f) << s
        s += 7
        if b < 0x80:
            return v, i


class Elf:
    def __init__(self, path):
        d = open(path, 'rb').read()
        if d[:4] != b'\x7fELF' or d[4] != 2 or d[5] != 1:
            raise ReportError('%s is not a little-endian ELF64 object' % path)
        (self.machine,) = struct.unpack_from('<H', d, 18)
        shoff, = struct.unpack_from('<Q', d, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3a)
        self.d = d
        self.secs = []
        for i in range(shnum):
            name, typ, flags, addr, off, size, link, info, align, entsize = \
                struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize)
            self.secs.append(dict(name=name, type=typ, flags=flags, off=off,
                                  size=size, link=link, info=info, entsize=entsize))
        strtab = self.secs[shstrndx]
        for s in self.secs:
            s['sname'] = self.cstr(strtab['off'] + s['name'])
        self.syms = []
        for s in self.secs:
            if s['type'] == 2:  # SHT_SYMTAB
                st = self.secs[s['link']]
                for k in range(s['size'] // 24):
                    nm, info, other, shndx, val, sz = struct.unpack_from('<IBBHQQ', d, s['off'] + 24 * k)
                    self.syms.append(dict(name=self.cstr(st['off'] + nm), type=info & 0xf,
                                          bind=info >> 4, shndx=shndx, value=val, size=sz))

    def cstr(self, off):
        e = self.d.index(b'\0', off)
        return self.d[off:e].decode('utf-8', 'replace')

    def relas(self, sec_index):
        """(offset, type, symbol, addend) for every RELA section applying
        to section `sec_index`."""
        out = []
        for s in self.secs:
            if s['type'] == 4 and s['info'] == sec_index:  # SHT_RELA
                for k in range(s['size'] // 24):
                    off, info, add = struct.unpack_from('<QQq', self.d, s['off'] + 24 * k)
                    out.append((off, info & 0xffffffff, self.syms[info >> 32], add))
        return out


def func_at(funcs_by_sec, shndx, off):
    for f in funcs_by_sec.get(shndx, []):
        if f['value'] <= off < f['value'] + max(f['size'], 1):
            return f['name']
    return None


def target_name(sym, add, funcs_by_sec):
    if sym['type'] == 3:  # STT_SECTION: the function at that offset
        return func_at(funcs_by_sec, sym['shndx'], add)
    return sym['name']


SYMTAB = '__axiom_symtab'
IRNAME = r'@("(?:[^"\\]|\\.)*"|[-A-Za-z0-9_$.]+)'
# The baremetal-aarch64 fault stack (docs/embedded-guide.md section 6):
# the entry a trap's exit branches to when a fault hook is bound, the two
# functions the fault exit starts from on that stack, and its size, which
# the linker script in `self_host/driver.ax` reserves.
FAULT_STACK_ENTRY = '__axiom_trap_entry'
FAULT_ROOTS = ('__axiom_cpu_exception', '__axiom_fault_trap')
FAULT_STACK_BYTES = 8192


def ir_facts(ir):
    """From the post-`opt` IR: functions holding an indirect call, a
    dynamically sized `alloca`, or inline assembly; and the functions
    whose ADDRESS escapes - named anywhere but as a direct callee.

    One table is excluded from the escape set, by name and under a
    checked condition: `@__axiom_symtab`, the backtrace symbol table,
    holds every function's address so a trap can name its frames. Its
    entries are compared with return addresses, never called; the
    exclusion holds only while every function that reads the table
    holds no indirect call site, and if one does, the table's entries
    count as escaped like any other."""
    fn_names = set(n.strip('"') for n in re.findall(r'^(?:define|declare) [^@]*' + IRNAME + r'\(', ir, re.M))
    indirect, dynamic, asm, escaped, symtab_users = set(), set(), set(), set(), set()
    symtab_entries = set()
    cur = None
    for line in ir.splitlines():
        m = re.match(r'^define [^@]*' + IRNAME + r'\(', line)
        if m:
            cur = m.group(1).strip('"')
            continue
        if line.startswith('}'):
            cur = None
            continue
        if cur is None:
            g = re.match(r'^' + IRNAME + r'\s*=', line)
            if g:
                gname = g.group(1).strip('"')
                for n in re.findall(IRNAME, line[g.end():]):
                    n = n.strip('"')
                    if n in fn_names:
                        (symtab_entries if gname == SYMTAB else escaped).add(n)
            continue
        if re.search(r'\bcall\b[^@%]*%[-A-Za-z0-9_.]+\(', line) and ' asm ' not in line:
            indirect.add(cur)
        if re.search(r'=\s*alloca\b[^,]*,\s*i\d+\s+%', line):
            dynamic.add(cur)
        if re.search(r'\bcall\b[^(]*\basm\b', line):
            asm.add(cur)
        # Two shapes name a function without letting its address flow
        # anywhere a call could read it: `icmp`, whose result is an i1
        # (the backtracer asks "is this return address main?"), and
        # `blockaddress(@f, %bb)`, a label's address for the line table,
        # which no call instruction can take.
        is_icmp = re.match(r'^\s*%[-A-Za-z0-9_.]+\s*=\s*icmp\b', line) is not None
        for mm in re.finditer(IRNAME, line):
            n = mm.group(1).strip('"')
            if n == SYMTAB:
                symtab_users.add(cur)
            if n not in fn_names:
                continue
            pre, post = line[:mm.start()], line[mm.end():]
            if post.startswith('(') and re.search(r'\bcall\b[^@]*$', pre):
                continue  # a direct callee
            if is_icmp or pre.endswith('blockaddress('):
                continue
            escaped.add(n)
    symtab_ok = not (symtab_users & indirect)
    if not symtab_ok:
        escaped |= symtab_entries
    return dict(indirect=indirect, dynamic=dynamic, asm=asm, escaped=escaped,
                symtab_users=sorted(symtab_users), symtab_excluded=symtab_ok and bool(symtab_entries))


def bound_graph(frames, calls, tails, problems, roots, names):
    """The worst-case stack from each root over a graph with two edge
    kinds. A CALL keeps the caller's frame beneath the callee; a TAIL
    call (a branch) replaces it. So

        v(f) = max(frame(f),
                   frame(f) + v(g)  for each call g,
                   v(h)             for each tail call h)

    A strongly connected component holding a call edge between two of
    its members grows without bound; one whose members are joined by
    tail calls only is a loop, and all its members share one value -
    the largest local contribution in it. Tarjan emits components sinks
    first, so each is valued after everything it reaches. A node with
    no frame (code outside the object) or a recorded problem is
    unbounded, and so is everything that reaches it."""
    succ = lambda f: sorted(calls.get(f, set()) | tails.get(f, set()))
    # Nodes reachable from the roots.
    seen, todo = set(), [r for r in roots if r in names or r in frames]
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        todo += [m for m in succ(n) if m not in seen]
    index, low, onst, st, comps = {}, {}, set(), [], []
    ctr = [0]
    for s0 in sorted(seen):
        if s0 in index:
            continue
        work = [(s0, iter(succ(s0)))]
        index[s0] = low[s0] = ctr[0]; ctr[0] += 1; st.append(s0); onst.add(s0)
        while work:
            v, it = work[-1]
            adv = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = ctr[0]; ctr[0] += 1; st.append(w); onst.add(w)
                    work.append((w, iter(succ(w))))
                    adv = True
                    break
                elif w in onst:
                    low[v] = min(low[v], index[w])
            if adv:
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = st.pop(); onst.discard(w); comp.append(w)
                    if w == v:
                        break
                comps.append(sorted(comp))
    val, via, bad = {}, {}, {}
    for comp in comps:  # sinks first
        cs = set(comp)
        reason = None
        for f in comp:
            if f not in frames:
                reason = ('%s has no frame size: code outside this object' % f, [f])
            elif f in problems:
                reason = ('%s: %s' % (f, '; '.join(problems[f])), [f])
            elif any(g in cs for g in calls.get(f, ())):
                g = sorted(x for x in calls[f] if x in cs)[0]
                reason = ('a cycle through a non-tail call', [f, g])
            else:
                for g in sorted(calls.get(f, set()) | tails.get(f, set())):
                    if g not in cs and g in bad:
                        reason = (bad[g][0], [f] + bad[g][1])
            if reason:
                break
        if reason:
            for f in comp:
                bad[f] = reason
            continue
        best, arg = -1, None
        for f in comp:
            c = (frames[f], [f])
            if c[0] > best:
                best, arg = c
            for g in sorted(calls.get(f, ())):
                if g not in cs and frames[f] + val[g] > best:
                    best, arg = frames[f] + val[g], [f] + via[g]
            for h in sorted(tails.get(f, ())):
                if h not in cs and val[h] > best:
                    best, arg = val[h], [f + '~>'] + via[h]
        head = arg[0][:-2] if arg[0].endswith('~>') else arg[0]
        for f in comp:
            val[f] = best
            # A member other than the argmax's reaches it by tail calls
            # inside the loop, holding no frame on the way.
            via[f] = arg if f == head else ['%s ~(loop)~>' % f] + arg
    results = {}
    for r in roots:
        if r not in names:
            results[r] = dict(bounded=False, reason='no function %s in the object' % r, path=[])
        elif r in bad:
            results[r] = dict(bounded=False, reason=bad[r][0], path=bad[r][1])
        else:
            results[r] = dict(bounded=True, bytes=val[r], path=via[r])
    return results


def stack_bound(axiom, src, target, opt, roots, workdir):
    """Answers a dict: per-root bound and worst path, or the reason a
    root is unbounded, plus the analysis's facts and assumptions."""
    ll = os.path.join(workdir, 'prog.ll')
    cmd = [axiom, 'emit-llvm', '--target=' + target, src, '-o', ll]
    p = subprocess.run(cmd, capture_output=True)
    if p.returncode != 0:
        raise ReportError('emit-llvm failed:\n' + p.stderr.decode('utf-8', 'replace')[:2000])
    irpath = ll
    if opt > 0:
        irpath = os.path.join(workdir, 'prog.opt.ll')
        p = subprocess.run(['opt', '-O%d' % opt, ll, '-S', '-o', irpath], capture_output=True)
        if p.returncode != 0:
            raise ReportError('opt failed:\n' + p.stderr.decode('utf-8', 'replace')[:2000])
    obj = os.path.join(workdir, 'prog.o')
    p = subprocess.run(['llc', irpath, '-filetype=obj', '-o', obj, '-O%d' % opt,
                        '-relocation-model=pic', '-stack-size-section', '-function-sections'],
                       capture_output=True)
    if p.returncode != 0:
        raise ReportError('llc failed:\n' + p.stderr.decode('utf-8', 'replace')[:2000])
    elf = Elf(obj)
    if elf.machine not in (EM_AARCH64, EM_X86_64):
        raise ReportError('--stack reads AArch64 and x86-64 ELF objects only; this is machine %d' % elf.machine)
    x86 = elf.machine == EM_X86_64
    funcs = [s for s in elf.syms if s['type'] == 2 and s['shndx'] != 0]  # STT_FUNC, defined
    funcs_by_sec = {}
    for f in funcs:
        funcs_by_sec.setdefault(f['shndx'], []).append(f)
    names = {f['name'] for f in funcs}
    # Frames, from .stack_sizes: an address (relocated to the function)
    # then a ULEB128 size, per function.
    frames = {}
    for i, s in enumerate(elf.secs):
        if s['sname'] != '.stack_sizes':
            continue
        rel = sorted(elf.relas(i), key=lambda r: r[0])
        rel_at = {r[0]: r for r in rel}
        j = 0
        data = elf.d[s['off']:s['off'] + s['size']]
        while j < len(data):
            r = rel_at.get(j)
            if r is None:
                raise ReportError('.stack_sizes entry at %d has no relocation' % j)
            fn = target_name(r[2], r[3], funcs_by_sec)
            size, j = uleb(data, j + 8)
            frames[fn] = size
    # Edges, from the code sections' relocations; and blr/br sites.
    calls, tails = {}, {}
    blr = {}
    address_taken = set()
    for i, s in enumerate(elf.secs):
        if not (s['flags'] & 0x4):  # SHF_EXECINSTR
            # Code addresses in data are the IR's to account for (a
            # global initializer naming a function is an escape there);
            # `.eh_frame` and `.stack_sizes` name every function and
            # take nobody's address.
            continue
        for off, typ, sym, add in elf.relas(i):
            caller = func_at(funcs_by_sec, i, off)
            t = target_name(sym, add, funcs_by_sec)
            if caller is None:
                continue
            if x86:
                # A rel32 call or jump has no relocation type of its
                # own: `call` is E8 before the displacement, `jmp` E9,
                # a conditional jump 0F 8x. A RIP-relative data access
                # has a ModRM byte there instead (mod 00, r/m 101),
                # which is never E8 or E9. The displacement is taken
                # from the end of the instruction, so a section
                # symbol's target is at addend + 4.
                if typ not in (R_X86_64_PLT32, R_X86_64_PC32):
                    continue
                code_at = elf.d[s['off']:s['off'] + s['size']]
                op = code_at[off - 1] if off >= 1 else None
                cond = off >= 2 and code_at[off - 2] == 0x0F and 0x80 <= code_at[off - 1] <= 0x8F
                t = target_name(sym, add + 4, funcs_by_sec)
                if op == 0xE8:
                    calls.setdefault(caller, set()).add(t)
                elif op == 0xE9 or cond:
                    if t != caller:
                        tails.setdefault(caller, set()).add(t)
            elif typ == R_AARCH64_CALL26:
                calls.setdefault(caller, set()).add(t)
            elif typ == R_AARCH64_JUMP26:
                if t != caller:
                    tails.setdefault(caller, set()).add(t)
            # Any other relocation naming a function (ADRP/ADD pairs,
            # literal pools) compiles one of the IR's own uses of that
            # address, including uses that let nothing flow: an `icmp`
            # against `@main`, a `blockaddress` for the line table.
            # `ir_facts` decides which uses escape, because the IR can
            # tell those shapes apart and the relocation cannot.
        if x86:
            # Variable-length instructions can't be scanned for an
            # indirect call without decoding; the IR's indirect sites
            # stand alone here, which the report states.
            continue
        code = elf.d[s['off']:s['off'] + s['size']]
        for k in range(0, len(code) - 3, 4):
            (w,) = struct.unpack_from('<I', code, k)
            if (w & 0xFFFFFC1F) == 0xD63F0000:  # BLR Xn
                c = func_at(funcs_by_sec, i, k)
                if c:
                    blr.setdefault(c, 0)
                    blr[c] += 1
    ir = open(irpath).read()
    irf = ir_facts(ir)
    ir_indirect, ir_dynamic, ir_asm = irf['indirect'], irf['dynamic'], irf['asm']
    address_taken |= irf['escaped'] & names
    problems = {}
    for c in blr:
        if c not in ir_indirect:
            problems.setdefault(c, []).append('a `blr` the IR shows no indirect call for')
    for f in ir_dynamic:
        problems.setdefault(f, []).append('a dynamically sized alloca')
    # `__axiom_trap_entry` is assembly in the baremetal-aarch64 vector
    # table, reached from a trap's exit when `isr(fault)` binds a hook. It
    # points sp at the fault stack and never returns, so it adds nothing
    # to the stack the trap was raised on; what runs after it is bounded
    # from the fault exit's own roots (`FAULT_ROOTS`).
    fault_entry = any(FAULT_STACK_ENTRY in ts for ts in list(calls.values()) + list(tails.values()))
    if fault_entry:
        frames[FAULT_STACK_ENTRY] = 0
    undefined = set()
    for f, ts in list(calls.items()) + list(tails.items()):
        for t in ts:
            if t not in frames:
                undefined.add(t)
    indirect_targets = sorted(address_taken)
    for f in ir_indirect:
        # An indirect site may reach any address-taken function.
        calls.setdefault(f, set()).update(address_taken)
    # On x86-64 a call pushes its 8-byte return address below the
    # caller's frame, and `.stack_sizes` counts neither: every frame is
    # charged 8 more. A tail jump reuses its caller's slot, so the sum is
    # an upper bound by 8 bytes per tail hop.
    extra = 8 if x86 else 0
    charged = {f: v + extra for f, v in frames.items()} if extra else frames
    results = bound_graph(charged, calls, tails, problems, roots, names)
    return dict(results=results, frames=frames, frame_extra=extra, machine='x86-64' if x86 else 'aarch64',
                fault_entry=fault_entry,
                indirect_sites=sorted(ir_indirect),
                indirect_targets=indirect_targets, asm=sorted(ir_asm),
                symtab_excluded=irf['symtab_excluded'], symtab_users=irf['symtab_users'],
                undefined=sorted(undefined), functions=len(funcs), ir=irpath, obj=obj)


# --------------------------------------------------------------------
# The report
# --------------------------------------------------------------------

def facts_of(g, q):
    f = g.fns[q]
    leaves = g.leaves.get(q, [])
    ind = []
    if f.flag('effect-params'):
        ind.append('calls parameter ' + f.metas['effect-params'])
    if f.flag('effects-incomplete'):
        ind.append('row incomplete')
    if f.flag('effects-possible'):
        ind.append('row over-approximate')
    ind += ['calls ' + l for l in leaves if l in INDIRECT_BUILTINS]
    traps = set()
    for l in leaves:
        traps.update(TRAP_LEAVES.get(l, ()))
        if ATOMIC_RE.match(l):
            traps.add(82)
        if SPAWN_RE.match(l) or JOIN_RE.match(l):
            traps.add(78)
    # The row is transitive already: out of memory wherever it allocates,
    # an unhandled operation wherever a declared effect is still in it.
    if 'Alloc' in f.effects:
        traps.add(70)
    if any(e not in BUILTIN_EFFECTS for e in f.effects):
        traps.add(71)
    blocking = [t for t in g.edges.get(q, [])
                if t.split('$')[-1] in BLOCKING_KERNEL and g.fns[t].module.endswith('Platform')]
    blocking += [l for l in leaves if JOIN_RE.match(l)]
    return dict(
        trap_direct=sorted(traps),
        block_direct=blocking,
        alloc='Alloc' in f.effects,
        io='IO' in f.effects,
        unsafe='unsafe' in f.metas.get('all:effect', []),
        extern=f.flag('extern'),
        isr=f.flag('isr'),
        spawn=[l for l in leaves if SPAWN_RE.match(l)],
        join=[l for l in leaves if JOIN_RE.match(l)],
        kernel=[l for l in leaves if KERNEL_RE.match(l)],
        asm=[l for l in leaves if ASM_RE.match(l)],
        indirect=ind,
        unresolved=g.unresolved.get(q, []),
        restrict=[r for r in str(f.metas.get('restrict', '')).split(',') if r],
    )


def close_over(g, reach, direct):
    """Each reachable function's `direct` set unioned with every set it
    can reach. Tarjan emits a component after every component it reaches,
    so one pass in emission order sees each successor's answer first; the
    members of one component share an answer."""
    reach = set(reach)
    comps = g.sccs(reach)
    comp_of = {q: i for i, c in enumerate(comps) for q in c}
    out = {}
    for i, comp in enumerate(comps):
        acc = set()
        for q in comp:
            acc |= set(direct.get(q, ()))
            for t in g.edges.get(q, []):
                if t in reach and comp_of[t] != i:
                    acc |= out[t]
        for q in comp:
            out[q] = acc
    return out


def first_hit(g, par_roots, pred):
    """The nearest function (BFS order) satisfying pred, with its path."""
    par = g.reach(par_roots)
    for q in par:
        if pred(q):
            return g.path(par, q)
    return None


def build_report(args):
    fns = load_source_graph(args.axiom, args.file, args.target)
    roots = []
    if 'main' in fns and not fns['main'].builtin:
        roots.append('main')
    isrs = sorted(q for q, f in fns.items() if not f.builtin and f.flag('isr') and f.module == '')
    # `isr(fault)` binds the fault hook: steady and nonblocking like any
    # handler, but it runs on the fault stack, not on top of another.
    fault_hooks = [q for q in isrs if fns[q].metas.get('isr') == 'fault']
    roots += [q for q in isrs if q not in roots]
    for r in args.root:
        if r not in fns:
            raise ReportError('--root %s names no function' % r)
        roots.append(r)
    if not roots:
        raise ReportError('no root: the file has no `main`, no `isr` and no --root')
    g = Graph(fns, roots)
    par = g.reach(roots)
    reach = list(par)
    facts = {q: facts_of(g, q) for q in reach}
    traps = close_over(g, reach, {q: facts[q]['trap_direct'] for q in reach})
    blocks = close_over(g, reach, {q: facts[q]['block_direct'] for q in reach})
    for q in reach:
        facts[q]['traps'] = sorted(traps[q])
        facts[q]['blocks'] = bool(blocks[q])
    for r in args.nonblocking:
        if r not in fns:
            raise ReportError('--nonblocking %s names no function' % r)
    refusals, obligations = [], []

    def refuse(rule, msg, path=None):
        refusals.append(dict(rule=rule, message=msg, path=path or []))

    def oblige(kind, msg, path=None):
        obligations.append(dict(kind=kind, message=msg, path=path or []))

    comps = [c for c in g.sccs(reach) if len(c) > 1 or c[0] in g.edges.get(c[0], [])]
    cycles = [g.cycle_through(c) for c in comps]
    stack = None
    if args.stack:
        machine_roots = list(args.stack_root) or (['_start'] if args.target == 'baremetal-aarch64' else ['main'])
        machine_roots += [fns[q].name for q in isrs if fns[q].name not in machine_roots]
        # A fault hook runs on the fault stack, from the fault exit, so
        # the exit's roots are bounded there, covering the report, the
        # hook's door and the hook.
        if fault_hooks and args.target == 'baremetal-aarch64':
            machine_roots += [r for r in FAULT_ROOTS if r not in machine_roots]
        work = tempfile.mkdtemp(prefix='axiom-report.')
        try:
            stack = stack_bound(args.axiom, args.file, args.target, args.opt, machine_roots, work)
        finally:
            if not args.keep:
                shutil.rmtree(work, ignore_errors=True)
            else:
                stack['workdir'] = work
    if args.profile == 'restricted':
        # RP-1
        for cyc in cycles:
            if stack is not None and all(r.get('bounded') for r in stack['results'].values()):
                oblige('recursion', 'a source-level cycle the machine code shows holds no frame across the cycle (tail calls or a loop): termination is the program\'s', cyc)
            else:
                refuse('RP-1', 'recursion: a call-graph cycle', cyc)
        # RP-2, RP-3, RP-4, RP-6
        for q in reach:
            fa = facts[q]
            pth = g.path(par, q)
            if fa['indirect']:
                refuse('RP-2', '%s makes a call the graph cannot follow (%s)' % (q, '; '.join(fa['indirect'])), pth)
            if fa['extern'] and fns[q].name not in args.allow_foreign and q not in args.allow_foreign:
                refuse('RP-3', '%s is an `extern` item' % q, pth)
            for l in fa['spawn'] + fa['join']:
                refuse('RP-4', '%s calls %s' % (q, l), pth + [l])
            for u in fa['unresolved']:
                refuse('RP-6', '%s calls `%s`, which resolves to no row' % (q, u), pth + [u])
            if fa['asm'] and fns[q].name not in args.allow_asm and q not in args.allow_asm:
                refuse('RP-9', '%s holds inline assembly' % q, pth)
        # RP-5
        steady = sorted(set(isrs + [q for q in reach if 'no-alloc' in facts[q]['restrict']] + list(args.steady)))
        for s in steady:
            if s not in fns:
                raise ReportError('--steady %s names no function' % s)
            if 'Alloc' in fns[s].effects:
                hit = first_hit(g, [s], lambda q: 'Alloc' in fns[q].effects and not any('Alloc' in fns[c].effects for c in g.edges.get(q, [])))
                refuse('RP-5', 'steady root %s allocates' % s, hit or [s])
        # RP-8: an interrupt handler never waits, and nor does a root the
        # program names nonblocking
        for s in sorted(set(isrs + list(args.nonblocking))):
            if s in facts and facts[s]['blocks']:
                hit = first_hit(g, [s], lambda q: bool(facts.get(q, {}).get('block_direct')))
                last = facts[hit[-1]]['block_direct'][0] if hit else ''
                refuse('RP-8', '%s may block: %s' % (s, last), (hit or [s]) + ([last] if last else []))
        # RP-7
        if stack is not None:
            # One interrupt's frames sit on top of the interrupted stack.
            # A fault hook's never do, because it runs on the fault stack.
            worst_isr = 0
            for q in isrs:
                if q in fault_hooks:
                    continue
                r = stack['results'].get(fns[q].name)
                if r and r.get('bounded'):
                    worst_isr = max(worst_isr, r['bytes'])
            for r, res in stack['results'].items():
                if not res.get('bounded'):
                    refuse('RP-7', 'no stack bound from %s: %s' % (r, res['reason']), res.get('path'))
            on_fault_stack = [fns[q].name for q in fault_hooks] + list(FAULT_ROOTS)
            for r, res in stack['results'].items():
                if res.get('bounded') and r in FAULT_ROOTS and res['bytes'] > FAULT_STACK_BYTES:
                    refuse('RP-7', 'the fault exit from %s is %d bytes, over the %d-byte fault stack' % (r, res['bytes'], FAULT_STACK_BYTES), res['path'])
            if args.stack_budget is not None:
                for r, res in stack['results'].items():
                    if res.get('bounded') and r not in [fns[q].name for q in isrs] and r not in on_fault_stack:
                        total = res['bytes'] + worst_isr
                        if total > args.stack_budget:
                            refuse('RP-7', 'stack from %s is %d bytes (%d + %d for one interrupt), over the %d-byte budget' % (r, total, res['bytes'], worst_isr, args.stack_budget), res['path'])
    # Obligations, whatever the profile
    for q in reach:
        fa = facts[q]
        if fa['unsafe']:
            oblige('unsafe', '%s calls an Unsafe primitive directly (%s): its preconditions are the trusted boundary' % (q, fns[q].loc), g.path(par, q))
        for l in fa['kernel']:
            oblige('kernel', '%s enters the kernel through %s%s' % (q, l, ' (lowered to the no-syscall trap, status 74, on this target)' if args.target == 'baremetal-aarch64' else ''), g.path(par, q) + [l])
        if fa['asm']:
            oblige('asm', '%s holds inline assembly (%s): what the instructions do, including any allocation, blocking, trap or stack use, is its declaration\'s to vouch for (MM-FFI-9)' % (q, fns[q].loc), g.path(par, q))
    if stack is None:
        oblige('stack', 'no stack bound computed (run with --stack on an AArch64 or x86-64 ELF target)')
    else:
        oblige('stack', ('%s: ' % stack['machine']) + ('each frame is charged 8 bytes more for the return address a call pushes, and indirect sites come from the post-opt IR alone (no machine-code cross-check); ' if stack['frame_extra'] else '') + 'frames are llc\'s .stack_sizes for the analysis object; indirect sites %s may reach only address-taken functions %s (no forged code pointers - `__call_word` of an arbitrary word breaks this and is Unsafe)%s; inline assembly in %s is assumed to use no stack beyond its frame; the reset vector and C runtime are outside the object%s' % (
            stack['indirect_sites'] or 'none', stack['indirect_targets'] or 'none',
            ('; the backtrace table @__axiom_symtab is excluded as never called, read only by %s, none of which holds an indirect call' % stack['symtab_users']) if stack.get('symtab_excluded') else '',
            stack['asm'] or 'none',
            ('; %s switches to the %d-byte fault stack and never returns, so a trap\'s exit adds nothing past it, and the fault exit (%s) is bounded on that stack' % (FAULT_STACK_ENTRY, FAULT_STACK_BYTES, ', '.join(FAULT_ROOTS))) if stack.get('fault_entry') else ''))
    for r in roots:
        ts = facts[r]['traps']
        if ts:
            oblige('traps', 'from %s the process may end with status %s (MM-EXEC-16); each function\'s set is in the report' % (
                r, ', '.join(str(t) for t in ts)))
        else:
            oblige('traps', 'from %s no call reaches a trap status' % r)
        if facts[r]['blocks']:
            hit = first_hit(g, [r], lambda q: bool(facts.get(q, {}).get('block_direct')))
            oblige('blocking', '%s may block: %s' % (r, ' -> '.join((hit or [r]) + [facts[hit[-1]]['block_direct'][0]] if hit else [r])), hit or [r])
    oblige('traps', 'not enumerated: count exhaustion (70, from retains the compiler emits), stack exhaustion (a signal; --stack bounds it), and a CPU fault from an Unsafe access or inline assembly (81 on baremetal-aarch64)')
    oblige('time', 'no execution-time bound: a bounded stack is not a bounded latency, and no loop is proven to terminate')
    return dict(file=args.file, target=args.target or 'host', opt=args.opt,
                profile=args.profile, roots=roots, isrs=isrs,
                reachable=len(reach), functions=facts,
                cycles=cycles, refusals=refusals, obligations=obligations,
                stack=stack and {k: v for k, v in stack.items() if k in ('results', 'frames', 'frame_extra', 'machine', 'indirect_sites', 'indirect_targets', 'asm', 'undefined', 'functions', 'symtab_excluded', 'symtab_users', 'workdir', 'obj')})


def render_text(rep, out):
    w = out.write
    w('axiom-report: %s (target %s, --opt %d, profile %s)\n' % (rep['file'], rep['target'], rep['opt'], rep['profile'] or 'none'))
    w('roots: %s\n' % ', '.join(rep['roots']))
    w('reachable functions: %d\n' % rep['reachable'])
    w('== per function (A alloc, I io, U unsafe-direct, X extern, R recursive, ~ indirect, S spawn/join, K kernel entry, T may trap, B may block) ==\n')
    rec = set(q for c in rep['cycles'] for q in c)
    for q in sorted(rep['functions']):
        fa = rep['functions'][q]
        marks = ''.join([
            'A' if fa['alloc'] else '.', 'I' if fa['io'] else '.', 'U' if fa['unsafe'] else '.',
            'X' if fa['extern'] else '.', 'R' if q in rec else '.', '~' if fa['indirect'] else '.',
            'S' if (fa['spawn'] or fa['join']) else '.', 'K' if fa['kernel'] else '.',
            'T' if fa['traps'] else '.', 'B' if fa['blocks'] else '.'])
        w('  %s %s%s%s\n' % (marks, q, '  [isr]' if fa['isr'] else '',
                             ('  traps ' + ','.join(str(t) for t in fa['traps'])) if fa['traps'] else ''))
    if rep['stack']:
        w('== stack (machine code) ==\n')
        for r, res in sorted(rep['stack']['results'].items()):
            if res.get('bounded'):
                w('  %s: %d bytes: %s\n' % (r, res['bytes'], ' -> '.join(res['path'])))
            else:
                w('  %s: UNBOUNDED: %s%s\n' % (r, res['reason'], (' (' + ' -> '.join(res.get('path') or []) + ')') if res.get('path') else ''))
    if rep['profile']:
        w('== refusals (profile %s): %d ==\n' % (rep['profile'], len(rep['refusals'])))
        for r in rep['refusals']:
            w('  %s %s%s\n' % (r['rule'], r['message'], (': ' + ' -> '.join(r['path'])) if r['path'] else ''))
    w('== obligations: %d ==\n' % len(rep['obligations']))
    for o in rep['obligations']:
        w('  %s: %s\n' % (o['kind'], o['message']))
    w('verdict: %s\n' % ('REFUSED (%d)' % len(rep['refusals']) if rep['refusals'] else 'no refusal'))


def selftest():
    """`bound_graph` on graphs whose answers are known by hand. Each case
    names the property it holds; a failure prints which."""
    fails = []

    def case(name, frames, calls, tails, roots, want):
        res = bound_graph(frames, {k: set(v) for k, v in calls.items()},
                          {k: set(v) for k, v in tails.items()}, {}, roots, set(frames) | set(roots))
        got = {r: (res[r]['bytes'] if res[r]['bounded'] else None) for r in roots}
        if got != want:
            fails.append('%s: got %s, want %s' % (name, got, want))

    # A chain of calls sums frames.
    case('chain', {'a': 16, 'b': 32, 'c': 8}, {'a': ['b'], 'b': ['c']}, {}, ['a'], {'a': 56})
    # A diamond takes the heavier arm, not the sum of both.
    case('diamond', {'a': 16, 'b': 100, 'c': 8, 'd': 4}, {'a': ['b', 'c'], 'b': ['d'], 'c': ['d']}, {}, ['a'], {'a': 120})
    # A tail call replaces the caller's frame.
    case('tail', {'a': 64, 'b': 16}, {}, {'a': ['b']}, ['a'], {'a': 64})
    case('tail-bigger', {'a': 16, 'b': 64}, {}, {'a': ['b']}, ['a'], {'a': 64})
    # A cycle of tail calls is a loop: bounded by its largest member's
    # own contribution, whichever member the root enters at.
    case('tail-loop', {'r': 8, 'a': 16, 'b': 48, 'c': 4}, {'r': ['a'], 'b': ['c']}, {'a': ['b'], 'b': ['a']}, ['r'], {'r': 8 + 52})
    # The same loop entered from a second root, after the first root
    # valued it: the answer must not depend on visiting order.
    case('tail-loop-2roots', {'r': 8, 's': 8, 'a': 100, 'b': 16}, {'r': ['b'], 's': ['a']}, {'a': ['b'], 'b': ['a']}, ['r', 's'], {'r': 108, 's': 108})
    # A cycle through a call is unbounded, and so is its caller.
    case('call-cycle', {'r': 8, 'a': 16}, {'r': ['a'], 'a': ['a']}, {}, ['r'], {'r': None})
    case('mixed-cycle', {'a': 16, 'b': 16}, {'a': ['b']}, {'b': ['a']}, ['a'], {'a': None})
    # Code with no frame size (outside the object) is unbounded.
    case('undefined', {'a': 16}, {'a': ['ext']}, {}, ['a'], {'a': None})
    # Unrelated unbounded code does not taint a bounded root.
    case('isolated', {'a': 16, 'b': 8, 'x': 8}, {'a': ['b'], 'x': ['x']}, {}, ['a', 'x'], {'a': 24, 'x': None})
    return fails


def main(argv):
    ap = argparse.ArgumentParser(description='Axiom resource report and restricted profile (R-D1).')
    ap.add_argument('file')
    ap.add_argument('--axiom', default=os.environ.get('AXIOM', 'axiom'))
    ap.add_argument('--target', default='')
    ap.add_argument('--opt', type=int, default=1)
    ap.add_argument('--profile', choices=['restricted'], default=None)
    ap.add_argument('--root', action='append', default=[])
    ap.add_argument('--steady', action='append', default=[])
    ap.add_argument('--nonblocking', action='append', default=[])
    ap.add_argument('--allow-foreign', action='append', default=[])
    ap.add_argument('--allow-asm', action='append', default=[])
    ap.add_argument('--stack', action='store_true')
    ap.add_argument('--stack-root', action='append', default=[])
    ap.add_argument('--stack-budget', type=int, default=None)
    ap.add_argument('--format', choices=['text', 'json'], default='text')
    ap.add_argument('--keep', action='store_true', help='keep the analysis object and IR')
    if argv == ['--selftest']:
        fails = selftest()
        for f in fails:
            sys.stdout.write('FAIL %s\n' % f)
        sys.stdout.write('selftest: %d cases failed\n' % len(fails))
        return 1 if fails else 0
    args = ap.parse_args(argv)
    try:
        rep = build_report(args)
    except ReportError as e:
        sys.stderr.write('axiom-report: %s\n' % e)
        return 2
    if args.format == 'json':
        json.dump(rep, sys.stdout, indent=1, sort_keys=True)
        sys.stdout.write('\n')
    else:
        render_text(rep, sys.stdout)
    return 1 if rep['refusals'] else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
