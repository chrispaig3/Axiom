#!/usr/bin/env python3
"""An executable model of Axiom's allocator, arena, region and count rules,
and the differential harness that holds the emitted runtime to it.

WHAT THIS IS. `Model` below is a second, independent statement of what
`axiom_alloc`, `axiom_retain`, `axiom_release`, `__axiom_arena_mark_fn`,
`__axiom_arena_reset_fn` and the `(region r ...)` form do to the bump
pointer, the per-class free lists and the 16-byte block header
(self_host/codegen.ax). It is written from docs/memory-model.md, not
transliterated from the IR: it knows offsets, counts, payload words and a
LIFO list per size class, and nothing about registers or chunks.

HOW IT IS CONNECTED TO THE RUNTIME. `Trace` drives the model with a
sequence of operations and, for each one, writes the same operation into
an Axiom program followed by the model's prediction of every observable
word as an in-program check: the handle's offset from an origin, its
alignment, its count word, its shape word, every payload word, the bump
pointer, the mark cell, and - after a reset - the bytes the reset
reclaimed. The program is compiled by the compiler under test and run;
it prints `<first failing check> <number failing>` and exits 0 only when
the runtime agreed with the model at every check. Random traces are
reproducible from their seed; `manifest.json` maps every check number to
its label so a failure names the rule it broke.

INVARIANTS the model maintains (asserted after every transition, so a
generator that drives it into an invalid state stops here, not in a
confusing runtime diff):

  I1 (MM-ALLOC-3)   every handle and every extent is 16-byte aligned; the
                    16-byte header sits immediately below the handle.
  I2                live extents never overlap and all lie below the bump.
  I3 (MM-LIFE-2k)   every free-list entry is a dead block of that class,
                    listed once; its count word is -2 - (next header), so
                    it reads as a count of at most -2.
  I4                a live block's count is in [0, 2^63-1].
  I5 (MM-RGN-2)     open scopes (marks and regions) nest: their saved
                    waterlines never decrease from outer to inner and
                    none is above the bump.
  I6 (MM-LIFE-2e)   immediately after any reset every free list is empty.
  I7                the trace fits one chunk (the single-chunk premise,
                    also checked at run time against the mark cell's
                    saved chunk end).

TRANSITION RULES checked against the runtime:

  alloc   (MM-ALLOC-3/6/7a/8b, MM-LIFE-2b/2d/2e) size 0 answers the bump
          and moves nothing; a size above 2^62 unsigned traps 70; otherwise
          the payload is rounded to 16 (sz0), a class <= 64 KiB pops its
          list head first, else the bump advances by sz0 + 16; the count
          word is 0, the shape word is (sz0/8) << 1, every payload word 0.
  retain  (MM-LIFE-2b/2k, MM-LIFE-2l) a negative count is left alone; a
          count of 2^63-1 traps 70 "reference count limit exceeded" with
          the header unchanged; otherwise +1.
  release (MM-LIFE-2e/2k) a negative or zero count is left alone; else -1,
          and at zero a leaf of 1..8192 words is filed LIFO on its class
          with its count word = -2 - (previous head's header); a larger
          one stays at count 0 and is never reused.
  mark    (MM-ALLOC-12) allocates a 24-byte cell like any 24-byte
          allocation (so it may pop class 32) and saves the bump after it.
  reset   (MM-ALLOC-14/16, MM-LIFE-2e) empties every free list, restores
          the saved bump, writes no byte of what it reclaims; marks whose
          cells it reclaimed become invalid; a mark may be reset twice.
  region  (MM-RGN-1/2, MM-RGN-6) entry saves the waterline in a stack cell
          and allocates nothing; normal exit is a reset to it.

SCOPE. One thread; one chunk (no refill, no chunk free list, no
MM-ALLOC-16a bad-mark walk); leaf blocks from `__alloc` (no record shapes,
no reference bitmaps, no dead-list drain, no foreign destructors, no
arrays); raw count adoption through `__retain`/`__release`; valid marks
and lexical regions only; count forging through a header store to reach
the exhaustion boundary without 2^63 retains.

NON-SCOPE (nothing here says anything about): graph destruction and the
dead-list walk (MM-LIFE-2d/2e record and array forms), cycles, chunk
refill and multi-chunk resets (MM-ALLOC-16a/16b/23), reset_keeping
(MM-ALLOC-15), recovery (MM-ALLOC-23), FFI and foreign handles
(MM-FFI-*), any concurrency (MM-PAR-*), static blocks (count -1),
invalid marks, resets across an open region, arbitrary words used as
handles, hardware faults, and every compiler-emitted retain/release (the
ownership events). A green run is agreement on the traces run, at the
opt levels run, on the host it ran on - not a proof about any other
trace.

Subcommands:
  generate DIR [--seeds S,S..] [--steps N] [--long]   write traces + manifest
  ablate KIND SRC.ll DST.ll                            one mutation witness
  label DIR TRACE N                                    name check N of TRACE
  selftest [--seeds N]                                 drive the model alone
"""

import argparse
from dataclasses import dataclass, field
import json
from pathlib import Path
import random
import re
import sys

MAX_COUNT = (1 << 63) - 1
POOL_CEILING = 65536          # largest filed payload, bytes (class 4096)
HUGE = 1 << 62                # MM-ALLOC-7a: sizes above this (unsigned) trap
CHUNK_BUDGET = 512 * 1024     # a trace must fit this far above its origin
DEFAULT_SEEDS = [7, 41, 20260927]
LONG_SEEDS = list(range(1000, 1064))


class Trap(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def padded(size):
    return (size + 15) & ~15


@dataclass
class Block:
    offset: int                 # handle offset from the trace origin
    size: int                   # padded payload bytes (sz0)
    count: int = 0              # the count word, exactly as the runtime holds it
    payload: list = field(default_factory=list)

    @property
    def header(self):
        return self.offset - 16

    @property
    def shape(self):
        words = self.size // 8
        return 0 if words > 16383 else words << 1

    @property
    def filable(self):
        return 1 <= self.size // 8 <= 8192


@dataclass
class Scope:
    kind: str                   # "mark" or "region"
    name: str
    saved: int                  # waterline a reset/exit restores
    cell: int = None            # a mark's cell offset (regions have none)


class Model:
    """The abstract machine. Offsets are relative to the trace origin, an
    address the runtime had already handed out when the trace began."""

    def __init__(self):
        self.bump = 0
        self.peak = 0
        self.blocks = {}        # offset -> Block, every block ever handed out and not reclaimed
        self.free = {}          # class -> [offset, ...], top of stack last
        self.scopes = []        # open marks and regions, outermost first
        self.reclaimed = {}     # offset -> Block, reclaimed by the LAST reset

    # --- links: the runtime stores ADDRESSES; the model stores offsets
    # and says how to spell the address in the program.
    def head(self, cls):
        pool = self.free.get(cls, [])
        return pool[-1] if pool else None

    def allocate(self, size):
        if size == 0:
            return None
        if size < 0 or size > HUGE:
            raise Trap(70, "axiom: out of memory (allocation size out of range)")
        sz0 = padded(size)
        cls = sz0 // 16
        offset = None
        if sz0 <= POOL_CEILING:
            pool = self.free.get(cls, [])
            if pool:
                offset = pool.pop()
        if offset is None:
            offset = self.bump + 16
            self.bump += sz0 + 16
            self.peak = max(self.peak, self.bump)
        self.blocks[offset] = Block(offset, sz0, 0, [0] * (sz0 // 8))
        self.invariant()
        return offset

    def retain(self, offset):
        block = self.blocks[offset]
        if isinstance(block.count, tuple) or block.count < 0:
            return
        if block.count == MAX_COUNT:
            raise Trap(70, "axiom: reference count limit exceeded")
        block.count += 1
        self.invariant()

    def release(self, offset):
        block = self.blocks[offset]
        if isinstance(block.count, tuple) or block.count <= 0:
            return
        block.count -= 1
        if block.count == 0 and block.filable:
            cls = block.size // 16
            previous = self.head(cls)
            # MM-LIFE-2k: the link, ENCODED. `None` (empty list) is 0.
            block.count = ("link", previous)
            self.free.setdefault(cls, []).append(offset)
        self.invariant()

    def forge(self, offset, value):
        """A header store: how a trace reaches the count boundary."""
        self.blocks[offset].count = value
        self.invariant()

    def mark(self, name):
        cell = self.allocate(24)
        self.scopes.append(Scope("mark", name, self.bump, cell))
        self.invariant()
        return cell

    def reset(self, name):
        index = max(i for i, s in enumerate(self.scopes) if s.name == name and s.kind == "mark")
        assert all(s.kind == "mark" for s in self.scopes[index:]), "reset across an open region"
        self.restore(self.scopes[index].saved)
        # The mark itself survives (its cell is below its waterline); the
        # marks taken after it were reclaimed with their cells.
        del self.scopes[index + 1:]
        self.invariant()

    def region_enter(self, name):
        self.scopes.append(Scope("region", name, self.bump))
        self.invariant()

    def region_exit(self, name):
        scope = self.scopes[-1]
        while scope.kind != "region":
            # marks taken inside the region die with it
            self.scopes.pop()
            scope = self.scopes[-1]
        assert scope.name == name
        self.scopes.pop()
        self.restore(scope.saved)
        self.invariant()

    def restore(self, waterline):
        self.free.clear()                                       # MM-LIFE-2e
        self.reclaimed = {o: b for o, b in self.blocks.items() if b.header >= waterline}
        self.blocks = {o: b for o, b in self.blocks.items() if b.header < waterline}
        self.bump = waterline

    def count_word(self, block):
        """The count word as a program expression over `origin`."""
        c = block.count
        if isinstance(c, tuple):
            nxt = c[1]
            return "-2" if nxt is None else f"(- -2 (+ origin {nxt - 16}))"
        return str(c)

    def invariant(self):
        seen = set()
        for cls, pool in self.free.items():
            for o in pool:
                assert o not in seen, "I3: duplicate free-list entry"
                seen.add(o)
                b = self.blocks[o]
                assert b.size // 16 == cls and isinstance(b.count, tuple), "I3: live block on a free list"
            for below, above in zip(pool, pool[1:]):
                assert self.blocks[above].count[1] == below, "I3: link does not name the next entry"
            if pool:
                assert self.blocks[pool[0]].count[1] is None, "I3: list tail links somewhere"
        extents = sorted((b.header, b.offset + b.size) for b in self.blocks.values())
        for start, end in extents:
            assert start % 16 == 0 and end % 16 == 0, "I1: misaligned extent"
            assert end <= self.bump, "I2: extent above the bump"
        for (_, end), (following, _) in zip(extents, extents[1:]):
            assert end <= following, "I2: overlapping extents"
        for b in self.blocks.values():
            if not isinstance(b.count, tuple):
                assert 0 <= b.count <= MAX_COUNT, "I4: count out of range"
        saved = [s.saved for s in self.scopes]
        assert saved == sorted(saved) and all(v <= self.bump for v in saved), "I5: scopes do not nest"
        assert 0 <= self.bump <= self.peak <= CHUNK_BUDGET, "I7: trace exceeds the one-chunk budget"


# ----------------------------------------------------------------------
# The trace: model transitions and the program that replays them.
# ----------------------------------------------------------------------

class Frame:
    """One lexical scope of the generated program: the top level or a region
    body. Its handles are declared in it because MM-RGN-3 refuses storing a
    region's allocation into an outer binding (AX3060)."""

    def __init__(self, kind, name):
        self.kind = kind
        self.name = name
        self.variables = []
        self.body = []


class Trace:
    def __init__(self, name, family="random"):
        self.name = name
        self.family = family
        self.model = Model()
        self.handles = {}       # variable -> offset, the names in scope that the model says are valid
        self.frames = [Frame("top", "main")]
        self.checks = []
        self.operations = 0
        self.perturb = None     # canary: check number whose expectation is deliberately wrong
        self.terminal = None    # (status, message) when the trace ends in a trap
        self.terminal_code = None
        self.region_seq = 0

    # --- emission
    @property
    def frame(self):
        return self.frames[-1]

    def emit(self, code):
        self.frame.body.append(code)

    def declare(self, name):
        self.frame.variables.append(name)

    def check(self, condition, label):
        """One prediction. The accumulator keeps the FIRST failing number
        in its low 32 bits and the number failing above them, so an
        ablation can say which check moved and how many did."""
        number = len(self.checks) + 1
        self.checks.append(label)
        if number == self.perturb:
            condition = f"(if {condition} false true)"
        self.emit(f"(set acc (check acc {condition} {number}))")

    def op(self, code):
        self.emit(code)
        self.operations += 1

    # --- observations
    def waterline(self, context):
        self.check(f"(== (- (__alloc 0) origin) {self.model.bump})", f"{context}: bump offset {self.model.bump}")

    def observe(self, var, label="", payload=True):
        o = self.handles[var]
        b = self.model.blocks[o]
        self.check(f"(== (__load64 (- {var} 16) 0) {self.model.count_word(b)})", f"{var} count word{label}")
        if payload:
            self.check(f"(== (__load64 (- {var} 8) 0) {b.shape})", f"{var} shape word{label}")
            self.payload(var, b, f"{var} payload{label}")

    def payload(self, address, block, label, only_nonzero=False):
        """The whole payload, exactly: word by word for a small block; for
        a large one, every word the model says is nonzero plus an
        in-program count of the nonzero words, which together pin every
        word without one check per zero word."""
        words = block.payload
        if len(words) <= 8 and not only_nonzero:
            for w, v in enumerate(words):
                self.check(f"(== (__load64 {address} {w}) {v})", f"{label} word {w}")
            return
        nonzero = [(w, v) for w, v in enumerate(words) if v]
        for w, v in nonzero:
            self.check(f"(== (__load64 {address} {w}) {v})", f"{label} word {w}")
        if not only_nonzero:
            self.check(f"(== (nonzero {address} {len(words)}) {len(nonzero)})",
                       f"{label}: {len(nonzero)} of {len(words)} words nonzero")

    def audit(self):
        """Every named live block, every word: a full-state comparison."""
        for var in sorted(self.handles):
            if not isinstance(self.model.blocks[self.handles[var]].count, tuple):
                self.observe(var, " (audit)")
        self.waterline("audit")

    # --- operations
    def allocate(self, var, size):
        self.declare(var)
        offset = self.model.allocate(size)
        self.handles[var] = offset
        self.op(f"(set {var} (__alloc {size}))")
        b = self.model.blocks[offset]
        self.check(f"(== (- {var} origin) {offset})", f"{var} = alloc {size}: offset {offset}")
        self.check(f"(== (& {var} 15) 0)", f"{var} alignment (MM-ALLOC-3)")
        self.check(f"(== (__load64 (- {var} 16) 0) 0)", f"{var} birth count (MM-LIFE-2b)")
        self.check(f"(== (__load64 (- {var} 8) 0) {b.shape})", f"{var} leaf shape (MM-LIFE-2d)")
        self.payload(var, b, f"{var} zeroed (MM-ALLOC-6)")
        self.waterline(f"{var} = alloc {size}")
        # any stale name for a block that was just handed out again is gone
        for other, o in list(self.handles.items()):
            if o == offset and other != var:
                del self.handles[other]

    def zero_alloc(self):
        # Not stored anywhere: inside a region, MM-RGN-3 refuses storing
        # even a zero-byte allocation into an outer binding (AX3060).
        self.operations += 1
        self.check(f"(== (- (__alloc 0) origin) {self.model.bump})", "alloc 0 answers the bump, twice (MM-ALLOC-8b)")
        self.waterline("alloc 0")

    def retain(self, var):
        self.model.retain(self.handles[var])
        self.op(f"(__retain {var})")
        self.observe(var, " after retain", payload=False)

    def release(self, var):
        self.model.release(self.handles[var])
        self.op(f"(__release {var})")
        self.observe(var, " after release", payload=False)

    def write(self, var, word, value):
        self.model.blocks[self.handles[var]].payload[word] = value
        self.op(f"(__store64 {var} {word} {value})")
        self.check(f"(== (__load64 {var} {word}) {value})", f"{var} write word {word}")

    def forge(self, var, value):
        self.model.forge(self.handles[var], value)
        self.op(f"(__store64 (- {var} 16) 0 {value})")
        self.observe(var, " after forge", payload=False)

    def mark(self, name):
        self.declare(name)
        cell = self.model.mark(name)
        self.op(f"(set {name} __axiom_arena_mark)")
        self.check(f"(== (- {name} origin) {cell})", f"mark {name} cell offset {cell}")
        self.check(f"(== (- (__load64 {name} 0) origin) {self.model.bump})", f"mark {name} saves the bump")
        # I7 at run time: the chunk end the cell saved is far enough away
        self.check(f"(>= (- (__load64 {name} 1) origin) {CHUNK_BUDGET})", f"mark {name}: trace fits the chunk")
        self.waterline(f"mark {name}")

    def after_restore(self, what):
        self.waterline(what)
        # MM-ALLOC-14: the reset wrote no byte of what it reclaimed. Read
        # it back BEFORE anything is allocated over it.
        for o, b in sorted(self.model.reclaimed.items()):
            self.check(f"(== (__load64 (+ origin {b.header}) 0) {self.model.count_word(b)})",
                       f"{what} leaves reclaimed header at {o} (MM-ALLOC-14)")
            self.payload(f"(+ origin {o})", b, f"{what} leaves reclaimed block {o} (MM-ALLOC-14)",
                         only_nonzero=True)
        # live payloads below the waterline are untouched
        for var in sorted(self.handles):
            b = self.model.blocks.get(self.handles[var])
            if b is not None and not isinstance(b.count, tuple):
                self.payload(var, b, f"{what} preserves {var}", only_nonzero=True)

    def drop_invalid(self):
        self.handles = {v: o for v, o in self.handles.items() if o in self.model.blocks}

    def reset(self, name):
        self.model.reset(name)
        self.op(f"(__axiom_arena_reset {name})")
        self.drop_invalid()
        self.after_restore(f"reset {name}")

    def region_open(self):
        self.region_seq += 1
        name = f"r{self.region_seq}"
        self.model.region_enter(name)
        self.frames.append(Frame("region", name))
        self.operations += 1
        return name

    def region_close(self):
        frame = self.frames.pop()
        assert frame.kind == "region"
        # names declared in the region leave scope with it
        for v in frame.variables:
            self.handles.pop(v, None)
        self.model.region_exit(frame.name)
        self.emit(frame)
        self.drop_invalid()
        self.after_restore(f"region {frame.name} exit")

    def open_marks(self):
        """Marks a reset may name here: taken in the current frame, since
        the innermost open region."""
        names = []
        for s in reversed(self.model.scopes):
            if s.kind == "region":
                break
            names.append(s.name)
        return [n for n in names if n in self.frame.variables]

    # --- rendering
    def render_frame(self, frame, indent):
        pad = " " * indent
        lines = []
        for item in frame.body:
            if isinstance(item, Frame):
                binds = " ".join(f"(mut {v} 0)" for v in item.variables) or "(mut unused 0)"
                lines.append(f"{pad}(region {item.name}")
                lines.append(f"{pad}  (let ({binds})")
                lines.append(f"{pad}    {{")
                lines.extend(self.render_frame(item, indent + 6))
                lines.append(f"{pad}      0")
                lines.append(f"{pad}    }}))")
            else:
                lines.append(pad + item)
        return lines

    def render(self, directory):
        assert len(self.frames) == 1, "unclosed region"
        top = self.frames[0]
        bindings = "\n".join(f"    (mut {v} 0)" for v in ["acc"] + top.variables)
        body = "\n".join(self.render_frame(top, 6))
        report = '''      (let ((first (& acc 4294967295)) (nfail (>> acc 32)))
        (println "{first} {nfail}"))'''
        if self.terminal:
            tail = f'''{report}
      {self.terminal_code}
      (println "NO TRAP")
      1'''
        else:
            tail = f'''{report}
      (if (== acc 0) 0 1)'''
        source = f''';; Generated by scripts/lib/runtime-model.py - trace {self.name} ({self.family}).
;; Each check is the model's prediction of one runtime word.
(import IO)

(:: nonzero (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (nonzero h n)
  (let ((mut k 0) (mut i 0))
    {{
      (while (< i n)
        (if (== (__load64 h i) 0) 0 (set k (+ k 1)))
        (set i (+ i 1)))
      k
    }}))

(:: check (-> Int Bool Int Int))
(fn (check acc condition number)
  (if condition
    acc
    (if (== (& acc 4294967295) 0)
      (+ acc (+ 4294967296 number))
      (+ acc 4294967296))))

;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let (
    (prime (__alloc 16))
    (origin (__alloc 0))
{bindings}
  )
    {{
{body}
{tail}
    }}))
'''
        (directory / f"{self.name}.ax").write_text(source)
        return {
            "name": self.name,
            "family": self.family,
            "operations": self.operations,
            "assertions": len(self.checks),
            "peak_bytes": self.model.peak,
            "expect_exit": self.terminal[0] if self.terminal else 0,
            "expect_stderr": self.terminal[1] if self.terminal else "",
            "canary_check": self.perturb,
            "checks": self.checks,
        }


# ----------------------------------------------------------------------
# Traces.
# ----------------------------------------------------------------------

def witness(kind, perturb=None):
    """Fixed traces, each the sharpest input for one mutation witness."""
    t = Trace(kind, "witness")
    t.perturb = perturb
    t.mark("outer")
    t.allocate("a", 32)
    t.retain("a")
    if kind == "dead":
        # MM-LIFE-2k: a second release of a FILED block must touch nothing.
        t.allocate("b", 32)
        t.retain("b")
        t.release("a")
        t.release("b")
        t.release("b")      # b is filed; its count word is a link
        t.retain("b")       # and so must a retain be
        t.allocate("x", 32)
        t.allocate("y", 32)
    elif kind == "reset":
        # MM-LIFE-2e: a reset scrubs the heads, so a filed block above the
        # mark is not handed out again below the new waterline.
        t.write("a", 0, 919)
        t.release("a")
        t.reset("outer")
        t.allocate("b", 32)
        t.retain("b")
        t.allocate("c", 32)
    elif kind == "scrub":
        # MM-ALLOC-6: a recycled block comes back zeroed.
        t.write("a", 0, 4242)
        t.write("a", 3, -1)
        t.release("a")
        t.allocate("b", 32)
    elif kind == "region":
        # MM-RGN-1: a region's normal exit restores the waterline.
        t.write("a", 1, 55)
        t.region_open()
        t.allocate("r", 48)
        t.write("r", 2, 66)
        t.region_open()
        t.allocate("s", 16)
        t.region_close()
        t.allocate("u", 16)
        t.region_close()
        t.allocate("b", 48)
    elif kind == "boundary":
        # The pool ceiling: 64 KiB files and is reused; 64 KiB + 16 never is.
        t.allocate("big", POOL_CEILING)
        t.retain("big")
        t.allocate("huge", POOL_CEILING + 16)
        t.retain("huge")
        t.release("big")
        t.release("huge")
        t.release("huge")
        t.allocate("big2", POOL_CEILING)
        t.allocate("huge2", POOL_CEILING + 16)
    else:
        raise SystemExit(f"no witness {kind}")
    t.audit()
    t.reset("outer")
    t.audit()
    return t


def exhaust_trace():
    """MM-LIFE-2l (tests/stdlib/527-retain-overflow.ax): the last
    representable retain succeeds and the next one traps 70."""
    t = Trace("exhaust", "terminal")
    t.mark("outer")
    t.allocate("a", 16)
    t.retain("a")
    t.forge("a", MAX_COUNT - 2)
    t.retain("a")
    t.retain("a")           # = 2^63-1, the last representable count
    t.release("a")
    t.retain("a")
    try:
        t.model.retain(t.handles["a"])
        raise SystemExit("model: exhaustion did not trap")
    except Trap as trap:
        t.terminal = (trap.status, trap.message)
    t.terminal_code = "(__retain a)"
    return t


def canary():
    """A trace whose model is deliberately wrong at ONE check: the harness
    must report exactly that check, or it cannot report anything."""
    # the offset check of `y`, which a correct runtime passes
    number = next(i for i, label in enumerate(witness("dead").checks, 1) if label.startswith("y = alloc"))
    t = witness("dead", perturb=number)
    t.name = "canary"
    t.family = "canary"
    return t


SIZES = [8, 16, 24, 32, 40, 48, 64, 80, 128, 256, 1000]


def randomized(seed, steps):
    rng = random.Random(seed)
    t = Trace(f"seed-{seed}")
    t.mark("outer")
    counter = [0]

    def fresh(prefix):
        counter[0] += 1
        return f"{prefix}{counter[0]}"

    dead = set()                        # names of filed blocks not yet reused
    for epoch in range(3):
        inner = None
        for step in range(steps):
            m = t.model
            live = [v for v, o in t.handles.items() if not isinstance(m.blocks[o].count, tuple)]
            owned = [v for v in live if m.blocks[t.handles[v]].count > 0]
            dead = {v for v in dead if v in t.handles and isinstance(m.blocks[t.handles[v]].count, tuple)}
            action = rng.randrange(100)
            if not live or (action < 25 and len(live) < 14):
                var = fresh("h")
                t.allocate(var, rng.choice(SIZES))
                if rng.randrange(5):
                    t.retain(var)
            elif action < 45 and owned:
                var = rng.choice(owned)
                t.release(var)
                if isinstance(m.blocks[t.handles[var]].count, tuple):
                    dead.add(var)
            elif action < 55 and dead:
                # a stray release or retain of a filed block: MM-LIFE-2k
                var = rng.choice(sorted(dead))
                (t.release if rng.randrange(2) else t.retain)(var)
            elif action < 63:
                var = rng.choice(live)
                if m.blocks[t.handles[var]].count < 6:
                    t.retain(var)
            elif action < 65 and owned:
                var = rng.choice(owned)
                t.forge(var, MAX_COUNT - rng.randrange(1, 3))
                t.retain(var)
            elif action < 67:
                t.zero_alloc()
            elif action < 72 and len(t.frames) < 3:
                t.region_open()
            elif action < 77 and len(t.frames) > 1:
                t.region_close()
            elif action < 80 and inner is None and len(t.frames) == 1:
                inner = fresh("m")
                t.mark(inner)
            elif action < 83 and inner is not None and inner in t.open_marks():
                t.reset(inner)
                if rng.randrange(3) == 0:
                    t.reset(inner)      # a mark may be reset twice
            else:
                var = rng.choice(live)
                size = m.blocks[t.handles[var]].size
                t.write(var, rng.randrange(size // 8), rng.randrange(-10**12, 10**12))
        while len(t.frames) > 1:
            t.region_close()
        t.audit()
        t.reset("outer")
        t.reset("outer")
        t.audit()
    return t


def all_traces(seeds, steps):
    traces = [witness(k) for k in ("dead", "reset", "scrub", "region", "boundary")]
    traces.append(exhaust_trace())
    traces.append(canary())
    traces += [randomized(seed, steps) for seed in seeds]
    return traces


# ----------------------------------------------------------------------
# Mutation witnesses: each rewrites ONE rule of the emitted runtime.
# ----------------------------------------------------------------------

def function_body(text, name):
    m = re.search(r"(define [^\n]*@" + re.escape(name) + r"\(.*?\n\})", text, re.S)
    if not m:
        raise SystemExit(f"cannot find @{name} for an isolated ablation")
    return m


def replace_once(body, old, new, what):
    if body.count(old) != 1:
        raise SystemExit(f"{what}: expected exactly one match, found {body.count(old)}")
    return body.replace(old, new)


def ablate(kind, source, target):
    text = source.read_text()
    if kind == "dead":
        # the pre-MM-LIFE-2k release: only -1 is left alone
        m = function_body(text, "axiom_release")
        body = replace_once(m.group(1), "  %stat = icmp slt i64 %c, 0", "  %stat = icmp eq i64 %c, -1", kind)
    elif kind == "reset":
        # no slab scrub on reset
        m = function_body(text, "__axiom_arena_reset_fn")
        body, n = re.subn(r"  br label %slabclear\nslabclear:.*?br i1 %sdone, label %resetbody, label %slabclear\n",
                          "  br label %resetbody\n", m.group(1), flags=re.S)
        if n != 1:
            raise SystemExit(f"reset: slabclear matched {n} times")
    elif kind == "scrub":
        # the handout wipe never runs
        m = function_body(text, "axiom_alloc")
        body = replace_once(m.group(1), "  %wmore = icmp ult i64 %wi, %stop", "  %wmore = icmp ult i64 %wi, %hb", kind)
    elif kind == "exhaust":
        # no refcount-exhaustion trap: the count wraps to a negative word
        m = function_body(text, "axiom_retain")
        body = replace_once(m.group(1), "  br i1 %full, label %overflow, label %increment",
                            "  br label %increment", kind)
    elif kind == "region":
        # a region's normal exit forgets its reset. A region exit hands the
        # reset its STACK cell (`ptrtoint ptr %cell`); a raw reset hands it
        # a mark word. Only the first kind is removed, and the region
        # witness has exactly two.
        m = function_body(text, "__axiom_user_main")
        cells = set(re.findall(r"  (%[\w.]+) = ptrtoint ptr %[\w.]+ to i64\n", m.group(1)))
        lines = m.group(1).split("\n")
        kept = [ln for ln in lines
                if not (re.match(r"  %[\w.]+ = call i64 @__axiom_arena_reset_fn\(i64 (%[\w.]+)\)$", ln)
                        and re.match(r".*\(i64 (%[\w.]+)\)$", ln).group(1) in cells)]
        if len(lines) - len(kept) != 2:
            raise SystemExit(f"region: removed {len(lines) - len(kept)} region exits, expected 2")
        body = "\n".join(kept)
    else:
        raise SystemExit(f"no ablation {kind}")
    text = text[:m.start()] + body + text[m.end():]
    target.write_text(text)


# ----------------------------------------------------------------------

def selftest(count):
    """Drive the model alone over many seeds: every invariant after every
    transition. Fast, and says nothing about the runtime."""
    total = 0
    for seed in range(count):
        t = randomized(seed, 60)
        total += t.operations
    witness_ops = sum(witness(k).operations for k in ("dead", "reset", "scrub", "region", "boundary"))
    print(f"model selftest: {count} random traces, {total} transitions, "
          f"{witness_ops} witness transitions, every invariant held")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    g = sub.add_parser("generate")
    g.add_argument("directory", type=Path)
    g.add_argument("--seeds", default=None, help="comma-separated seeds")
    g.add_argument("--steps", type=int, default=72)
    g.add_argument("--long", action="store_true", help=f"seeds {LONG_SEEDS[0]}..{LONG_SEEDS[-1]} as well")
    a = sub.add_parser("ablate")
    a.add_argument("kind", choices=["dead", "reset", "scrub", "exhaust", "region"])
    a.add_argument("source", type=Path)
    a.add_argument("target", type=Path)
    lab = sub.add_parser("label")
    lab.add_argument("directory", type=Path)
    lab.add_argument("trace")
    lab.add_argument("number", type=int)
    s = sub.add_parser("selftest")
    s.add_argument("--seeds", type=int, default=200)
    args = parser.parse_args()

    if args.command == "ablate":
        ablate(args.kind, args.source, args.target)
        return
    if args.command == "selftest":
        selftest(args.seeds)
        return
    if args.command == "label":
        rows = json.loads((args.directory / "manifest.json").read_text())
        row = next(r for r in rows if r["name"] == args.trace)
        n = args.number
        print(row["checks"][n - 1] if 1 <= n <= len(row["checks"]) else f"<no check {n}>")
        return

    seeds = [int(s) for s in args.seeds.split(",")] if args.seeds else list(DEFAULT_SEEDS)
    if args.long:
        seeds += LONG_SEEDS
    args.directory.mkdir(parents=True, exist_ok=True)
    rows = [trace.render(args.directory) for trace in all_traces(seeds, args.steps)]
    (args.directory / "manifest.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(f"model: {len(rows)} traces, {sum(r['operations'] for r in rows)} transitions, "
          f"{sum(r['assertions'] for r in rows)} runtime assertions, "
          f"peak waterline {max(r['peak_bytes'] for r in rows)} bytes above origin, "
          f"seeds {','.join(map(str, seeds))}")


if __name__ == "__main__":
    main()
