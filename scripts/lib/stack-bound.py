#!/usr/bin/env python3
"""A static stack bound for an Axiom program, from its call graph.

WHAT THIS IS. Given the post-`opt` LLVM IR of a program and the frame
size of every function in it, this computes the longest weighted path
through the call graph from a root (default `main`) and reports it as
"this binary needs at most N bytes of stack".  It REFUSES, naming the
site, whenever the question has no static answer: a cycle, a dynamic
frame, a callee whose frame is unknown, or a function address it cannot
classify.

WHERE THE FRAME SIZES COME FROM, and why not from the compiler.  The
workstream that asked for this assumed `self_host/codegen.ax` knows each
frame's size.  It does not, and cannot: `axiom` emits LLVM *text* IR and
shells out to opt/llc (self_host/driver.ax, `IR -> opt -> llc -> cc`);
the frame is decided by LLVM's register allocator, long after Axiom's
codegen has stopped running.  A number computed inside codegen.ax would
be either unsound or a large over-estimate.  So the sizes are taken from
the same llc invocation the driver already makes, by either route:

  --su FILE     llc's own `--stack-usage-file` table.  Exact, and it
                also reports static-vs-dynamic per frame.  Present in
                LLVM 23 (Homebrew, darwin); ABSENT in LLVM 18.1.3, which
                is what the Linux gate image and CI's apt llvm carry.
  --asm FILE    a prologue parse of `llc -filetype=asm`.  Portable to
                every toolchain, which is why it is the primary path.

Neither is trusted alone.  `--cross-check` requires the two to agree
function-for-function, which is what keeps the portable parse honest;
scripts/check-stack-bound.sh runs that over all ~3,767 functions of the
compiler itself.

THE x86_64 CORRECTION.  Both the `.su` table and the prologue exclude
the return address, which `call` pushes into the callee's frame.  On
AArch64 lr is saved by the callee's own `stp x29, x30` and is already
counted.  So on x86_64 the bound adds 8 bytes per non-musttail edge
along the path, and on aarch64 it adds nothing.

MUSTTAIL.  A `musttail call` is a guaranteed tail call: the caller's
frame is gone before the callee's is built, so it contributes
max(self, callee) rather than self + callee.  A plain `tail call` is
only a hint and LLVM is free to ignore it, so it is charged as an
ordinary call.

Exit statuses, one per refusal reason, so a gate can assert WHICH
refusal it got:
  0  a bound was computed
  1  usage / input error
  2  a frame is dynamic (an alloca whose size is not a constant)
  3  the call graph has a cycle
  4  a reachable callee has no frame in the table
  5  a function address could not be classified (default-deny)
  6  the root symbol is not defined in this module
  7  --cross-check found the two frame tables disagreeing

ABLATIONS.  AXIOM_ABLATE_STACK_BOUND is read here and nowhere else; it
exists so scripts/check-stack-bound.sh can prove its own assertions can
fail.  `flat` charges only the root's own frame, `nocycle` returns a
number for a cyclic graph, `noindirect` drops the symbol-table
exclusion so that every function looks address-taken.
"""

import argparse
import collections
import os
import re
import sys

# Globals whose initializers list function addresses for BACKTRACES, not
# for calling.  @__axiom_symtab is the address->name table the runtime
# walks when a program aborts, and it names every function in the
# program; @__axiom_bt_mainaddr is the one-entry `main` anchor beside
# it.  Counting these as address-taken would make every function a
# possible indirect target and no program would ever be boundable -
# which is exactly what the `noindirect` ablation demonstrates.
SYMTAB_GLOBALS = {"__axiom_symtab", "__axiom_bt_mainaddr"}

ABLATE = os.environ.get("AXIOM_ABLATE_STACK_BOUND", "")

EXIT_OK, EXIT_USAGE = 0, 1
EXIT_DYNAMIC, EXIT_CYCLE, EXIT_UNKNOWN_CALLEE = 2, 3, 4
EXIT_UNCLASSIFIED, EXIT_NO_ROOT, EXIT_CROSSCHECK = 5, 6, 7


def refuse(status, msg):
    print("REFUSE: " + msg)
    sys.exit(status)


# ---------------------------------------------------------------- frames

def read_su(path):
    """llc --stack-usage-file rows: `<module>:<fn>\\t<bytes>\\t<static|dynamic>`."""
    sizes, dynamic = {}, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("\t")
            if len(cols) < 2:
                continue
            name = cols[0].split(":", 1)[1] if ":" in cols[0] else cols[0]
            sizes[name] = int(cols[1])
            if len(cols) > 2 and cols[2].strip() != "static":
                dynamic.append(name)
    return sizes, dynamic


# AArch64 prologue: a pre-index writeback push moves sp by N; a plain
# `sub sp, sp, #N` (optionally shifted left 12) allocates the frame.  A
# NON-writeback `stp x29, x30, [sp, #144]` is a spill INTO a frame that
# `sub` already allocated and must not be counted twice - that shape is
# what codegen$resolveDecls emits, and double-counting it is the first
# thing the cross-check catches.
A64_PUSH = re.compile(r"^\s*(?:stp|str)\s+[\w]+\s*,\s*(?:[\w]+\s*,\s*)?\[sp,\s*#-(\d+)\]!")
A64_SUB = re.compile(r"^\s*sub\s+sp,\s*sp,\s*#(\d+)(?:\s*,\s*lsl\s*#(\d+))?")
X86_PUSH = re.compile(r"^\s*push[qlw]?\s+%\w+")
X86_SUB = re.compile(r"^\s*sub[qlw]?\s+\$(\d+),\s*%[er]sp")
# Anything that ends the straight-line prologue.
A64_END = re.compile(r"^\s*(?:bl?|br|blr|cbn?z|tbn?z|ret|b\.\w+)\b")
X86_END = re.compile(r"^\s*(?:j\w+|call\w*|ret\w*)\b")
LABEL = re.compile(r"^([A-Za-z_$.][\w.$]*):")


def read_asm(path, known=frozenset()):
    """Parse each function's prologue out of `llc -filetype=asm`.

    `known` is the set of function names the IR defines.  Assembly
    labels do not spell those names identically: Mach-O prefixes every
    global with an underscore, ELF does not.  Guessing "strip one
    leading underscore" is right on darwin and WRONG on Linux, where it
    would turn the label `_lam_0` into `lam_0` and lose the frame of
    every function whose Axiom name already begins with one.  So the
    mapping is resolved against `known` rather than assumed, and only
    falls back to the guess when the caller supplied no set.

    Scanning stops at the first control transfer or the second
    basic-block marker, so an `add sp, sp, #N` epilogue or a mid-body
    dynamic `sub sp` is never folded in - a dynamic frame is a refusal,
    not a number, and the `.su` cross-check is what proves this parse
    agrees with llc's own accounting.
    """
    sizes = {}
    cur, total, done, bbs = None, 0, False, 0
    a64_hits = x86_hits = 0

    def flush():
        if cur is not None:
            sizes[cur] = total

    with open(path) as fh:
        for line in fh:
            m = LABEL.match(line)
            if m:
                name = m.group(1)
                if name.startswith(".") or name.startswith("LBB") or name.startswith("Lloh"):
                    # A local label ends the straight-line prologue.
                    done = True
                    continue
                flush()
                if known:
                    if name in known:
                        cur = name
                    elif name.startswith("_") and name[1:] in known:
                        cur = name[1:]
                    else:
                        cur = name       # unknown to the IR; harmless
                else:
                    cur = name[1:] if name.startswith("_") else name
                total, done, bbs = 0, False, 0
                continue
            if cur is None or done:
                continue
            stripped = line.lstrip()
            if stripped.startswith("; %bb.") or stripped.startswith("# %bb."):
                bbs += 1
                if bbs > 1:
                    done = True
                continue
            if stripped.startswith((".cfi", ";", "#", "//")):
                continue
            m = A64_PUSH.match(line)
            if m:
                a64_hits += 1
                total += int(m.group(1))
                continue
            m = A64_SUB.match(line)
            if m:
                a64_hits += 1
                n = int(m.group(1))
                if m.group(2):
                    n <<= int(m.group(2))
                total += n
                continue
            if X86_PUSH.match(line):
                x86_hits += 1
                total += 8
                continue
            m = X86_SUB.match(line)
            if m:
                x86_hits += 1
                total += int(m.group(1))
                continue
            if A64_END.match(line) or X86_END.match(line):
                done = True
    flush()
    return sizes, ("x86_64" if x86_hits > a64_hits else "aarch64")


# -------------------------------------------------------------- the IR

DEFINE = re.compile(r'^define\b.*?@("[^"]+"|[\w.$]+)\s*\(')
DECLARE = re.compile(r'^declare\b.*?@("[^"]+"|[\w.$]+)\s*\(')
GLOBAL = re.compile(r'^@("[^"]+"|[\w.$]+)\s*=')
CALL = re.compile(
    r'\b(musttail|tail|notail)?\s*(?:call|invoke)\b[^@%]*?@("[^"]+"|[\w.$]+)\s*\(')
ICALL = re.compile(r'\b(?:musttail|tail|notail)?\s*(?:call|invoke)\b[^\n]*?\s(%[\w.]+)\s*\(')
# LLVM quotes an identifier containing `$` in some outputs and not in
# others: self_host's emitted IR has @Str$strLen, the same module after
# `opt` has @"Str$strLen".  Both forms must be scanned - matching only
# the bare one leaves the symbol table unread, and the address-taken set
# silently empty.
PTRTOINT_INSTR = re.compile(r'(?<!\()\bptrtoint ptr @("[^"]+"|[\w.$]+) to i64')
PTRTOINT_CONST = re.compile(r'\bptrtoint\s*\(\s*ptr @("[^"]+"|[\w.$]+) to i64\s*\)')
ANY_AT = re.compile(r'@("[^"]+"|[\w.$]+)')
# `%r = icmp ne i64 %frame, ptrtoint (ptr @main to i64)` - an address used
# ONLY as the operand of an integer comparison.  This is how the runtime's
# backtrace walker recognises the bottom of the stack.  `icmp` yields an
# i1, so the address flows nowhere and nothing can be called through it;
# treating it as address-taken would make `main` an indirect target of
# itself and leave hello world unboundable.  Narrow on purpose: only a
# comparison, and only when the comparison is the whole instruction.
ICMP_LINE = re.compile(r'^\s*%[\w.]+\s*=\s*icmp\b')
# An LLVM byte-array literal: c"...", with \XX escapes and no bare quote.
# The lookbehind is load-bearing. A QUOTED IR identifier whose last
# character is `c` - @"expand$expandRec" - ends with the two characters
# `c"`, and without the lookbehind this pattern started matching there
# and swallowed the rest of the line. On the compiler's own symbol
# table, one such name ate 130 of the entries that follow it, which
# presented as "130 function addresses I cannot classify" rather than as
# a parsing bug. A byte-array literal's `c` always begins a token.
CSTR = re.compile(r'(?<![\w$."])c"(?:[^"\\]|\\.)*"')


class Module(object):
    def __init__(self):
        self.defines = []
        self.declares = set()
        self.edges = collections.defaultdict(set)
        self.musttail = collections.defaultdict(set)
        self.indirect = collections.Counter()
        self.taken = set()
        self.unclassified = []
        self.fnnames = set()


def parse_ll(path):
    """Two passes.  The first collects the module's function names,
    because the default-deny in classify_line can only fire on a `@name`
    that IS a function - the IR is full of data globals (`@__axiom_bump`,
    string constants) whose names must not be mistaken for addresses.
    """
    m = Module()
    with open(path) as fh:
        for line in fh:
            d = DEFINE.match(line)
            if d:
                m.defines.append(d.group(1).strip('"'))
                continue
            d = DECLARE.match(line)
            if d:
                m.declares.add(d.group(1).strip('"'))
    m.fnnames = set(m.defines) | m.declares

    cur = None           # current function body, or None at module scope
    curglobal = None     # global whose initializer we are inside
    with open(path) as fh:
        for lineno, line in enumerate(fh, 1):
            if DEFINE.match(line):
                cur = DEFINE.match(line).group(1).strip('"')
                curglobal = None
                continue
            if cur is None:
                if DECLARE.match(line):
                    curglobal = None
                    continue
                g = GLOBAL.match(line)
                if g:
                    curglobal = g.group(1).strip('"')
            elif line.startswith("}"):
                cur = None
                continue
            classify_line(m, line, lineno, cur, curglobal)
    return m


def classify_line(m, line, lineno, cur, curglobal):
    """Account for EVERY `@name` on this line, or record it unclassified.

    This is a default-DENY, deliberately.  The address-taken set is only
    sound if every route by which a function's address can reach a
    pointer is either counted or refused; a future codegen that stashed
    an address in a global table, a select or a phi would otherwise
    silently shrink the set and make the bound WRONG rather than absent.
    """
    # A metadata definition (`!0 = !{ptr @f, ptr @g}`) names functions
    # but materialises no address: metadata is dropped before lowering
    # and no call can flow through it.  `opt` attaches these to a module
    # for its own bookkeeping, so hello world has ten of them; counting
    # them as address-taken would make every listed function an indirect
    # target for no reason.  Nothing else at module scope is skipped.
    if cur is None and line.startswith("!"):
        return

    # Strip LLVM byte-array literals before looking for names.  The
    # compiler's own codegen emits IR AS TEXT, so self_host's module is
    # full of string constants like
    #     @str_2355 = private constant [44 x i8] c"define internal i64 @__axiom_div_by_zero() \00"
    # The `@__axiom_div_by_zero` in there is a character sequence the
    # compiler will one day print, not a reference to anything in THIS
    # module.  Reading it as an address escape refused the compiler for
    # the wrong reason, and hid the cycle A4 is about.
    line = CSTR.sub('c""', line)

    consumed = []

    c = CALL.search(line)
    if c:
        kind = (c.group(1) or "").strip()
        callee = c.group(2).strip('"')
        consumed.append(callee)
        if not callee.startswith("llvm.") and cur is not None:
            (m.musttail if kind == "musttail" else m.edges)[cur].add(callee)

    for raw in PTRTOINT_INSTR.findall(line):
        name = raw.strip('"')
        consumed.append(name)
        if ICMP_LINE.match(line) and ABLATE != "noindirect":
            continue
        m.taken.add(name)

    compare_only = ICMP_LINE.match(line) is not None
    for raw in PTRTOINT_CONST.findall(line):
        name = raw.strip('"')
        consumed.append(name)
        if compare_only and ABLATE != "noindirect":
            continue
        owner = curglobal if cur is None else None
        if ABLATE == "noindirect" or owner not in SYMTAB_GLOBALS:
            m.taken.add(name)

    if cur is not None and ICALL.search(line):
        m.indirect[cur] += 1

    # Whatever FUNCTION @names are left over on this line are
    # unaccounted for.  Data globals are skipped: they are not addresses
    # anything can be called through.
    for raw in ANY_AT.findall(line):
        name = raw.strip('"')
        if name in consumed:
            consumed.remove(name)
            continue
        if name in m.fnnames and not name.startswith("llvm."):
            m.unclassified.append((lineno, name, line.strip()[:120]))


# --------------------------------------------------------------- solve

def longest_path(root, sizes, edges, musttail, ra_cost):
    """Iterative longest weighted path.  Never recursive.

    The analysis for a stack bound must not itself be depth-limited -
    the first prototype of this blew Python's recursion limit on a
    2,000-deep chain, which is precisely the program a user would ask
    about.  Two-phase explicit worklist: phase 0 opens a vertex, phase 1
    closes it once its callees are known.
    """
    memo, state = {}, {}
    stack = [(root, 0)]
    while stack:
        f, phase = stack.pop()
        if phase == 0:
            if f in memo:
                continue
            if state.get(f) == 1:
                if ABLATE != "nocycle":
                    refuse(EXIT_CYCLE, "cycle at %s" % f)
                memo[f] = sizes.get(f, 0)
                continue
            state[f] = 1
            stack.append((f, 1))
            for e in edges[f] | musttail[f]:
                if e not in memo:
                    stack.append((e, 0))
        else:
            if f in memo:
                continue
            below = max([memo[e] + ra_cost for e in edges[f] if e in memo] or [0])
            tail = max([memo[e] for e in musttail[f] if e in memo] or [0])
            own = sizes.get(f, 0)
            memo[f] = own if ABLATE == "flat" else max(own + below, tail)
            state[f] = 2
    return memo[root]


def main():
    ap = argparse.ArgumentParser(
        description="compute a static stack bound from a program's call graph")
    ap.add_argument("ll", help="post-opt LLVM IR of the program")
    ap.add_argument("--su", help="llc --stack-usage-file table")
    ap.add_argument("--asm", help="llc -filetype=asm output, for the prologue parse")
    ap.add_argument("--root", default="main")
    ap.add_argument("--arch", choices=["aarch64", "x86_64"],
                    help="default: inferred from --asm, else aarch64")
    ap.add_argument("--cross-check", action="store_true",
                    help="require --su and --asm to agree for every function")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if not args.su and not args.asm:
        print("usage: need at least one of --su or --asm", file=sys.stderr)
        sys.exit(EXIT_USAGE)

    mod = parse_ll(args.ll)
    defined = set(mod.defines)

    su_sizes, dynamic = read_su(args.su) if args.su else ({}, [])
    asm_sizes, asm_arch = read_asm(args.asm, defined) if args.asm else ({}, None)
    arch = args.arch or asm_arch or "aarch64"
    ra_cost = 8 if arch == "x86_64" else 0

    if args.cross_check:
        if not (args.su and args.asm):
            print("usage: --cross-check needs both --su and --asm", file=sys.stderr)
            sys.exit(EXIT_USAGE)
        agree = disagree = missing = 0
        detail = []
        for name in sorted(su_sizes):
            if name not in asm_sizes:
                missing += 1
                detail.append("missing %s" % name)
            elif asm_sizes[name] == su_sizes[name]:
                agree += 1
            else:
                disagree += 1
                detail.append("%s: prologue %d != llc %d"
                              % (name, asm_sizes[name], su_sizes[name]))
        print("cross-check: agree %d disagree %d missing %d of %d"
              % (agree, disagree, missing, len(su_sizes)))
        for d in detail[:20]:
            print("  " + d)
        if disagree or missing:
            sys.exit(EXIT_CROSSCHECK)

    # Prefer llc's own numbers when we have them; the prologue parse is
    # the portable fallback, and --cross-check is what earns that trust.
    sizes = dict(asm_sizes)
    sizes.update(su_sizes)

    if mod.unclassified:
        for lineno, name, text in mod.unclassified[:10]:
            print("  line %d: unclassified @%s in: %s" % (lineno, name, text))
        refuse(EXIT_UNCLASSIFIED,
               "%d function-address use(s) this analysis cannot classify; "
               "the address-taken set would be incomplete and the bound unsound"
               % len(mod.unclassified))

    targets = sorted(t for t in mod.taken if t in defined)
    n_indirect = sum(mod.indirect.values())
    if not args.quiet:
        print("functions=%d  addr-taken-fns=%s  indirect-sites=%d  arch=%s"
              % (len(mod.defines), targets or "none", n_indirect, arch))

    if args.root not in defined:
        refuse(EXIT_NO_ROOT, "no definition of root symbol `%s`" % args.root)

    if dynamic:
        refuse(EXIT_DYNAMIC,
               "%d frame(s) are dynamic, so no static bound exists: %s"
               % (len(dynamic), ", ".join(sorted(dynamic)[:5])))

    if n_indirect:
        if targets:
            for f in list(mod.indirect):
                mod.edges[f].update(targets)
            if not args.quiet:
                print("note: %d indirect site(s) resolved to the address-taken set"
                      % n_indirect)
        elif not args.quiet:
            print("note: %d indirect site(s), but no function's address is ever "
                  "taken -> provably dead" % n_indirect)

    reachable_callees = set()
    seen, work = set(), [args.root]
    while work:
        f = work.pop()
        if f in seen:
            continue
        seen.add(f)
        for e in mod.edges[f] | mod.musttail[f]:
            reachable_callees.add(e)
            work.append(e)
    unknown = sorted(e for e in reachable_callees if e not in sizes)
    if unknown:
        refuse(EXIT_UNKNOWN_CALLEE,
               "%d reachable callee(s) have no frame in the table (extern?): %s"
               % (len(unknown), ", ".join(unknown[:5])))

    bound = longest_path(args.root, sizes, mod.edges, mod.musttail, ra_cost)
    print("BOUND from %s: %d bytes" % (args.root, bound))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
