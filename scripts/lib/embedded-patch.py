#!/usr/bin/env python3
"""One edit to a copy of `self_host/codegen.ax`, by exact string match.

`scripts/check-embedded.sh` needs two kinds of edit and they are the
same mechanism, so they live together:

  variant:<code41>:<hostcode>
        THE POSITIVE ONE. Give one target a 4 KiB arena chunk and
        another a 256 KiB statically reserved arena - which is exactly
        the edit `docs/embedded-proposal.md` section 6 says a bare-metal
        port makes to the target table, and nothing more. The gate then
        asserts what moved and what did not.

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
    # the allocator they have always emitted.
    "chunk": (
        "(pub fn (targetArenaChunkBytes t) 1048576)",
        "(pub fn (targetArenaChunkBytes t) 4096)",
        "A1 - the supported targets' emitted chunk",
    ),
    # `refill:` goes back to what it was before 4.1: the literal, twice,
    # written into the emitted text. The table still exists and still
    # answers; nothing reads it.
    "literal": (
        """    (emitLine cg (cat3 "  %big = icmp ugt i64 %need, " (fmtInt (targetArenaChunkBytes (memGetWord cg 26))) ""))
    (emitLine cg (cat3 "  %rounded0 = add i64 %need, " (fmtInt (- (targetArenaGrainBytes (memGetWord cg 26)) 1)) ""))
    (emitLine cg (cat3 "  %rounded = and i64 %rounded0, " (fmtInt (- 0 (targetArenaGrainBytes (memGetWord cg 26)))) ""))
    (emitLine cg (cat3 "  %chunk = select i1 %big, i64 %rounded, i64 " (fmtInt (targetArenaChunkBytes (memGetWord cg 26))) ""))""",
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
    65536
  )
)""",
        """(pub fn (targetArenaGrainBytes t) 65536)""",
        "A4 - the grain moving with the chunk",
    ),
    # `emitRuntimeMap` forgets the strategy: a static target still asks
    # for pages the way a hosted one does.
    "strategy": (
        """  (if (> (targetArenaStaticBytes (memGetWord cg 26)) 0)
    (emitArenaCarve cg sizeExpr)
  (if (== (targetUsesSyscallAsm (memGetWord cg 26)) 1)""",
        """  (if false
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
}


def replace_defn(src, name, newline, label):
    """Replace a one-line `(pub fn (<name> t) ...)` outright.

    ANCHORED ON THE HEADER, NOT ON THE VALUE, and that is not tidiness.
    The `chunk` ablation rewrites `targetArenaChunkBytes`'s body to
    4096, and a variant patch anchored on the old body then found no
    anchor and ABORTED - which the runner reports as "the drill never
    applied", the one outcome that is neither a red nor a green. The
    drill HAD applied; it was the variant that could not. Anchoring on
    the header makes the two independent, which is what lets a drill
    that changes this row still be drilled.
    """
    prefix = "(pub fn (%s t) " % name
    lines = src.split("\n")
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    if len(hits) != 1:
        die("%s did not apply - %d lines begin `%s`, not one.\n"
            "       This edit replaces a ONE-LINE definition; if that row has "
            "grown\n       a multi-line body, re-anchor it rather than "
            "loosening the match." % (label, len(hits), prefix))
    lines[hits[0]] = newline
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


def main():
    if len(sys.argv) != 3:
        die("usage: embedded-patch.py <name|variant:C41:CHOST> <codegen.ax>")
    name, path = sys.argv[1], sys.argv[2]
    src = open(path, encoding="utf-8").read()

    if name.startswith("variant"):
        src = variant(src, name)
        label = "variant"
        n_edits = 2
    elif name in ABLATIONS:
        old, new, aims = ABLATIONS[name]
        label = "ablation %s (aims at %s)" % (name, aims)
        n_edits = 1
        n = src.count(old)
        if n != 1:
            die("%s did not apply - its anchor occurs %d times in %s, not once.\n"
                "       An edit that does not apply proves nothing. Re-anchor it on:\n"
                "       %s" % (label, n, path, old.strip().splitlines()[0]))
        src = src.replace(old, new, 1)
    else:
        die("no ablation named %r; try one of: %s" % (name, " ".join(sorted(ABLATIONS))))

    open(path, "w", encoding="utf-8").write(src)
    print("     applied: %s (%d edit(s))" % (label, n_edits))


if __name__ == "__main__":
    main()
