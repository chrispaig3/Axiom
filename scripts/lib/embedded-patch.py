#!/usr/bin/env python3
"""One edit to a copy of `self_host/codegen.ax`, by exact string match.

`scripts/check-embedded.sh` needs two kinds of edit and they are the
same mechanism, so they live together:

  variant:<code41>:<hostcode>
        THE POSITIVE ONE. Give one target a 4 KiB arena chunk and
        another a 256 KiB statically reserved arena - which is exactly
        the edit `docs/embedded-guide.md` section 6 says a bare-metal
        port makes to the target table, and nothing more. The gate then
        asserts what moved and what did not.

  silent:<hostcode>
        THE POSITIVE ONE FOR 4.3. Give the host silent traps - the
        no-op door of `docs/embedded-guide.md` 4.3 - so the gate can
        link, run and listen to a program whose traps exit without
        writing.

  <name>
        AN ABLATION. Break one thing, so that a named assertion in the
        gate has to go red. The gate runs itself once per drill under
        `--ablations` and refuses a drill that leaves it green.

EVERY PATCH IS ANCHORED ON AN EXACT STRING AND ABORTS IF IT IS NOT
THERE. An ablation that silently does not apply is a drill that proves
the gate can pass, which is the opposite of the point - and it happens:
`check-replcomp.sh` records `axiom fmt` reflowing three anchors out from
under three drills, which then passed by doing nothing. The gate's
runner treats an ABORT as a failure rather than a red for that reason.

The exit status is 0 when the patch applied and 1 when it did not, and
the message begins with `ABORT:` either way it fails, because that is
what the runner greps for.
"""
import re
import sys


def die(msg):
    print("ABORT: %s" % msg)
    sys.exit(1)


# --------------------------------------------------------------------
# The ablations. Each is (anchor, replacement, which assertion it aims
# at) - the third is documentation, printed when the drill applies, so
# a reader of the log knows what was supposed to go red.
# --------------------------------------------------------------------
ABLATIONS = {
    # Every target answers 4 KiB, so the supported targets stop emitting
    # the allocator they have always emitted. Anchored on the row's
    # current body (baremetal grew the `t == 7` arm over four lines, so
    # the pre-baremetal one-line body is gone); the VARIANT edit does
    # not anchor on the body at all - see `replace_defn`.
    "chunk": (
        """(pub fn (targetArenaChunkBytes t)
  (if (== t 7)
    4096
    1048576))""",
        "(pub fn (targetArenaChunkBytes t) 4096)",
        "A1 - the supported targets' emitted chunk",
    ),
    # `refill:` goes back to what it was before 4.1: the literal, twice,
    # written into the emitted text. The table still exists and still
    # answers; nothing reads it. The anchor is the four lines as they
    # stand - the two chunk lines read the EFFECTIVE chunk since the
    # ceiling flag landed, and re-anchoring here is part of that move.
    "literal": (
        """    (emitLine cg (concat "  %big = icmp ugt i64 %need, " (concat (fmtInt (arenaChunkBytes (memGetWord cg 26))) "")))
    (emitLine cg (concat "  %rounded0 = add i64 %need, " (concat (fmtInt (- (targetArenaGrainBytes (memGetWord cg 26)) 1)) "")))
    (emitLine cg (concat "  %rounded = and i64 %rounded0, " (concat (fmtInt (- 0 (targetArenaGrainBytes (memGetWord cg 26)))) "")))
    (emitLine cg (concat "  %chunk = select i1 %big, i64 %rounded, i64 " (concat (fmtInt (arenaChunkBytes (memGetWord cg 26))) "")))""",
        """    (emitLine cg "  %big = icmp ugt i64 %need, 1048576")
    (emitLine cg "  %rounded0 = add i64 %need, 65535")
    (emitLine cg "  %rounded = and i64 %rounded0, -65536")
    (emitLine cg "  %chunk = select i1 %big, i64 %rounded, i64 1048576")""",
        "A2 and A4 - the constant reaching the emitter at all",
    ),
    # The grain stops following the chunk, so a 4 KiB-chunk target still
    # rounds an oversized request up to 64 KiB.
    "grain": (
        """(pub fn (targetArenaGrainBytes t)
  (if (< (targetArenaChunkBytes t) 65536)
    (targetArenaChunkBytes t)
    65536))""",
        """(pub fn (targetArenaGrainBytes t) 65536)""",
        "A4 - the grain moving with the chunk",
    ),
    # `emitRuntimeMap` forgets the strategy: a static target still asks
    # for pages the way a hosted one does. The comparison is neutered
    # with a huge constant rather than replaced by `false`: the effect
    # walk prunes a literal-`false` branch, which would leave
    # `emitRuntimeMap` performing no IO against its `effect(io)` tag
    # and fail the BUILD on AX3010 - red for the wrong reason, hiding
    # whether A5 can fail. An opaque comparison keeps the call (and the
    # tag) while taking the branch nowhere any region reaches.
    "strategy": (
        """  (if (> (arenaStaticBytes (memGetWord cg 26)) 0)
    (emitArenaCarve cg sizeExpr)
    (if (== (targetUsesSyscallAsm (memGetWord cg 26)) 1)""",
        """  (if (> (arenaStaticBytes (memGetWord cg 26)) 999999999999)
    (emitArenaCarve cg sizeExpr)
    (if (== (targetUsesSyscallAsm (memGetWord cg 26)) 1)""",
        "A5 - the emitted program containing one strategy and not the other",
    ),
    # The carve never advances its cursor, so every chunk is the same
    # chunk and the second one hands back memory the first is using.
    "cursor": (
        """    (emitLine cg "  store i64 %ar_keep, ptr @__axiom_arena_cursor")""",
        """    (emitLine cg "  %ar_unused = add i64 %ar_keep, 0")""",
        "A6 - the static arena actually allocating",
    ),
    # The carve never answers 0, so a request past the end of the region
    # is handed an address inside it and exhaustion is never seen.
    "oomsig": (
        """    (emitLine cg "  %addr = select i1 %ar_fit, i64 %ar_cur, i64 0")""",
        """    (emitLine cg "  %addr = select i1 %ar_fit, i64 %ar_cur, i64 %ar_cur")""",
        "A6 - exhaustion reaching __axiom_out_of_memory",
    ),
    # The flag is never read, so a ceiling build is a mmap build in
    # disguise: the region, the capped growth and the 70 all vanish.
    # The replacement still scans argv (for a flag that is never
    # passed), because a body that reads nothing while keeping its
    # `effect(io)` tag would fail the build on AX3010 instead - red
    # for the wrong reason, hiding whether A7 can fail.
    "ceiling": (
        """(pub fn (heapCeilingBytes)
  (ceilingScan 1))""",
        """(pub fn (heapCeilingBytes) (if (argHas "--never-a-flag" 1) 1 0))""",
        "A7 - the flag reaching the emitter at all",
    ),
    # The silent branch never fires, so a silent target still writes:
    # the strategy row is read and ignored. Aims at A9's absence half.
    "trapwrite": (
        """  (if (== (targetTrapSilent (memGetWord cg 26)) 1)
    (emitLine cg "  ; trap message suppressed: the target asked for silent traps")""",
        """  (if (== (targetTrapSilent (memGetWord cg 26)) 999)
    (emitLine cg "  ; trap message suppressed: the target asked for silent traps")""",
        "A9 - the silent branch carrying the write away",
    ),
    # Every target is silent, so the supported targets stop emitting
    # the trap writes they have always emitted. Aims at A8.
    "allsilent": (
        """(pub fn (targetTrapSilent t)
  0)""",
        "(pub fn (targetTrapSilent t) 1)",
        "A8 - the supported targets' emitted trap writes",
    ),
    # The device primitives lose `volatile`: both emitters write an
    # ordinary load and store, so the probe's dead-looking first write
    # is `opt`'s to delete and every volatile count in A11 is 0. TWO
    # edits, one drill - the keyword is one property of one family, and
    # stripping half of it would leave A11 half-tested.
    "volatile": (
        [(""" = load volatile " (concat ty ", ptr ")) (concat pr (concat ", align " """,
          """ = load " (concat ty ", ptr ")) (concat pr (concat ", align " """),
         ("""(concat "  store volatile " (concat ty (concat " " sv)))""",
          """(concat "  store " (concat ty (concat " " sv)))""")],
        None,
        "A11 - the volatile keyword reaching the emitted accesses",
    ),
    # `__arm_dmb` becomes a `nop`: the program still builds and runs,
    # and orders nothing.
    "barrier": (
        '  (if (strEq nm "__arm_dmb")\n    "dmb sy"',
        '  (if (strEq nm "__arm_dmb")\n    "nop"',
        "A11 - each __arm_ primitive being its instruction",
    ),
    # Every target may run every primitive: nothing is ever refused as
    # AX4008, and an EL1 instruction reaches an x86-64 assembler.
    "refusal": (
        """(pub fn (devicePrimTargetOK nm t)
  (if (> (devicePrimBits nm) 0)""",
        """(pub fn (devicePrimTargetOK nm t)
  (if (>= (devicePrimBits nm) 0)""",
        "A11 - AX4008 drawing the target line",
    ),
    # `_start` stops writing VBAR_EL1: the table is still emitted and
    # linked, and nothing points the core at it, so a fault jumps
    # through the reset value and spins - the hang the table exists to
    # end. The FP enable and the ISB stay, so the drill removes exactly
    # the installation.
    "vbar": (
        '\\\\0Amsr vbar_el1, x9\\\\0Aisb',
        '\\\\0Aisb',
        "A12 - the vector table being installed",
    ),
    # An `asm` form's block with an output loses `sideeffect`: the
    # memory clobber still keeps it here, so the drill is read off the
    # emitted attributes, which is what the rule promises.
    "asmfx": (
        '(concat "  " r) " = call i64 asm sideeffect \\"")',
        '(concat "  " r) " = call i64 asm \\"")',
        "A15 - every inline-asm block being sideeffect",
    ),
    # `_start` builds the tables and never writes SCTLR_EL1: MAIR, TCR
    # and TTBR0 are set and nothing turns the MMU or the caches on, which
    # is the port as it was.
    "mmuoff": (
        '\\\\0Aorr x9, x9, x10\\\\0Amsr sctlr_el1, x9\\\\0Aisb',
        '\\\\0Aorr x9, x9, x10\\\\0Aisb',
        "A16 - the MMU and caches turned on",
    ),
    # The guard below the stack is mapped read-write like the stack, so
    # an overflow runs on into `.bss` and `.data` and faults somewhere
    # else, or not at all.
    "guard": (
        '(emitLine cg "  %a3 = select i1 %isg, i64 0, i64 %a4")',
        '(emitLine cg (concat "  %a3 = select i1 %isg, i64 " (concat (fmtInt mmuAttrData) ", i64 %a4")))',
        "A17 - the guard below the stack not mapped",
    ),
    # The fault exit no longer switches to the fault stack: a fault
    # taken with sp in the guard faults again on its first push, for
    # ever, and nothing is reported.
    "excstack": (
        '(emitAsmLine cg "mov sp, x9")\n      (emitAsmLine cg "mrs x1, esr_el1")',
        '(emitAsmLine cg "mrs x1, esr_el1")',
        "A17 - the fault exit running on its own stack",
    ),
    # Code is mapped read-write, and WXN - which would make any
    # writable page execute-never, and so the code unrunnable - is left
    # off with it. TWO edits, one drill: the property is that code can't
    # be written, and either edit alone leaves it true or the program
    # dead.
    "codewrite": (
        [("""(pub fn (mmuAttrCode)
  (+ mmuPageNormal (+ 128 (<< 1 54))))""",
          """(pub fn (mmuAttrCode)
  (+ mmuPageNormal (+ 0 (<< 1 54))))"""),
         ('\\\\0Amovk x10, #0x8, lsl #16', '')],
        None,
        "A18 - code read-only",
    ),
    # `isr(fault)` is parsed, checked and then ignored: no module has a
    # hook, so a fault takes the fixed 81 and a trap its own status.
    "hookoff": (
        """  (let ((fs (isrVectorNames (isrBindings (memGetWordVec cg 8) vecNew 0) "fault" 0 vecNew)))
    (if (== (vecLen fs) 1)""",
        """  (let ((fs (isrVectorNames (isrBindings (memGetWordVec cg 8) vecNew 0) "fault" 0 vecNew)))
    (if (== (vecLen fs) 999)""",
        "A19 - the hook binding reaching the fault exit",
    ),
    # A fault while the hook runs goes back into the hook: the guard
    # that sends it to the fixed exit is gone, so the hook faults, runs
    # again, faults again, and the guest never finishes.
    "reenter": (
        '"  br i1 %again, label %twice, label %say"',
        '"  br i1 false, label %twice, label %say"',
        "A20 - a fault inside the hook taking the fixed exit, once",
    ),
}


def replace_defn(src, name, newline, label):
    """Replace a target-table row outright, whatever its body has grown to.

    ANCHORED ON THE HEADER, NOT ON THE VALUE, and that is not tidiness.
    The `chunk` ablation rewrites `targetArenaChunkBytes`'s body to
    4096, and a variant patch anchored on the old body then found no
    anchor and ABORTED - which the runner reports as "the drill never
    applied", the one outcome that is neither a red nor a green. The
    drill HAD applied; it was the variant that could not. Anchoring on
    the header makes the two independent, which is what lets a drill
    that changes this row still be drilled.

    The row's end is found by balancing parentheses from the header
    line, so a body that grew - baremetal's `t == 7` arm spread the
    chunk row over four lines, and the old two-line arm then replaced
    the header plus one line and left `4096` orphaned in the scratch
    tree (AX2001, red for the wrong reason) - is replaced whole. The
    one-line form a drill leaves behind balances on its own line and
    takes the same path. A row whose parentheses never balance is a
    row that needs re-anchoring, and fails here rather than leaving
    its tail behind.
    """
    header = "(pub fn (%s t)" % name
    lines = src.split("\n")
    hits = [i for i, l in enumerate(lines)
            if l == header or l.startswith(header + " ")]
    if len(hits) != 1:
        die("%s did not apply - %d lines open `%s`, not one.\n"
            "       This edit replaces the row whole, from its header to\n"
            "       its balancing close paren; anything else is a row\n"
            "       that needs re-anchoring rather than a looser match."
            % (label, len(hits), header))
    i = hits[0]
    depth = 0
    j = None
    for k in range(i, len(lines)):
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', lines[k].split(";", 1)[0])
        for ch in code:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
        if depth == 0:
            j = k
            break
    if j is None:
        die("%s did not apply - the row under `%s` never balances.\n"
            "       A row that grew past a balanced definition needs\n"
            "       re-anchoring." % (label, header))
    lines[i:j + 1] = [newline]
    return "\n".join(lines)


def variant(src, spec):
    """The two target-table rows a bare-metal port writes."""
    parts = spec.split(":")
    if len(parts) != 3:
        die("variant needs `variant:<witness code>:<host code>`, got %r" % spec)
    c41, chost = parts[1], parts[2]
    if not c41.isdigit() or not chost.isdigit():
        die("variant target codes must be numbers, got %r and %r" % (c41, chost))
    if c41 == chost:
        die("the witness target and the host are the same code (%s); the gate's"
            " untouched targets would then be one fewer and that one would be"
            " carrying both edits" % c41)
    src = replace_defn(
        src, "targetArenaChunkBytes",
        "(pub fn (targetArenaChunkBytes t) (if (== t %s) 4096 (if (== t %s) 4096 1048576)))"
        % (c41, chost), "variant (chunk row)")
    src = replace_defn(
        src, "targetArenaStaticBytes",
        "(pub fn (targetArenaStaticBytes t) (if (== t %s) 262144 0))" % chost,
        "variant (static row)")
    return src


def silent(src, spec):
    """The target-table row a silent-trap port writes."""
    parts = spec.split(":")
    if len(parts) != 2:
        die("silent needs `silent:<host code>`, got %r" % spec)
    chost = parts[1]
    if not chost.isdigit():
        die("silent target code must be a number, got %r" % chost)
    return replace_defn(
        src, "targetTrapSilent",
        "(pub fn (targetTrapSilent t) (if (== t %s) 1 0))" % chost,
        "silent (trap row)")


def main():
    if len(sys.argv) != 3:
        die("usage: embedded-patch.py <name|variant:C41:CHOST> <codegen.ax>")
    name, path = sys.argv[1], sys.argv[2]
    src = open(path, encoding="utf-8").read()

    if name.startswith("variant"):
        src = variant(src, name)
        label = "variant"
        n_edits = 2
    elif name.startswith("silent"):
        src = silent(src, name)
        label = "silent variant"
        n_edits = 1
    elif name in ABLATIONS:
        old, new, aims = ABLATIONS[name]
        label = "ablation %s (aims at %s)" % (name, aims)
        # A drill is one edit, or - where one property has two emission
        # sites - a list of them, every one of which must apply.
        edits = old if isinstance(old, list) else [(old, new)]
        n_edits = len(edits)
        for o, nw in edits:
            n = src.count(o)
            if n != 1:
                die("%s did not apply - its anchor occurs %d times in %s, not once.\n"
                    "       An edit that does not apply proves nothing. Re-anchor it on:\n"
                    "       %s" % (label, n, path, o.strip().splitlines()[0]))
            src = src.replace(o, nw, 1)
    else:
        die("no ablation named %r; try one of: %s" % (name, " ".join(sorted(ABLATIONS))))

    open(path, "w", encoding="utf-8").write(src)
    print("     applied: %s (%d edit(s))" % (label, n_edits))


if __name__ == "__main__":
    main()
