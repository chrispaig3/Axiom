# The `.axir` record file, and the MIR projection through AXSYM

**Status.** The format, its reader, and the AXSYM projection shipped in
0.7.3, gated by `scripts/check-mir-roundtrip.sh` and
`scripts/check-mir-projection.sh`. The AXDL half is **designed and not
built**, and §5 says exactly what blocks it. The block-and-instruction
half of the grammar was **specified and read, and written by nothing**
until 2026-09-04, because there was no mid-level IR in the tree for it
to describe. There is one now — `self_host/mir.ax` — and
`symbols --axir --mir` writes it; §2 says what that means in practice.

This document is the design record for both halves. It is not a
tutorial: `axiom help symbols` is the user-facing text.

## 1. Why the extension is not `.mir`

LLVM owns `.mir`. It is Machine IR — the post-instruction-selection form
`llc -stop-after=<pass>` writes — and this toolchain writes it today.
Measured 2026-09-03 on the development machine: `llc --version` reports
Homebrew LLVM 23.1.0 for arm64-apple-darwin25.6.0, and

```console
$ axiom emit-llvm s1.ax > s1.ll        # 1,312 lines
$ llc -stop-after=finalize-isel -o s1.mir s1.ll
$ wc -c s1.mir
  248183 s1.mir
```

exits 0. Axiom's own mid-level IR sits **above** LLVM IR; LLVM's Machine
IR sits **below** it. Two different intermediate representations in one
tree cannot share one file extension without every later tool sniffing
content to work out which one it is holding.

So the extension is `.axir`, and the first line of every file is a magic
line rather than a comment:

```text
axir 1 <target> <version>
```

The magic line is **load-bearing on day one**, not decoration for a
future reader. `axiom symbols --axir <FILE>` decides what to do with
`<FILE>` by reading it: a file that opens `axir 1 ` is read back and
re-emitted, anything else is compiled. `scripts/check-mir-roundtrip.sh`
asserts both directions — a record file named `.ax` still reads back,
and a source file named `.axir` still compiles — so the name of the file
never decides.

## 2. The grammar

One fact per line, LF-terminated, ASCII, whitespace-delimited, and
colourless. These are AXSYM's rules, deliberately: a second set of rules
for a second agent-facing stream is a second thing to get wrong.

```text
axir 1 <target> <version>
F <name> <file>:<line>:<c1>-<c2> "<type>" @<nid>
sig <arity>
param <index> <name>
region <flows-cur> <flows-from> <result-from> <result-cur> <unknown>
blk <label> %<param>...
op %<n> <opcode> <operand>...
term <opcode> <operand>...
end
```

The kind set is **closed**. `axirRead` refuses a line whose first word
it does not know and a line whose field count is wrong, with a message
naming the kind, the way the driver's flag table refuses an unknown
flag. A format that silently drops a line it does not recognise is a
format that reports less than it was given, which is this repository's
named hazard.

**What is written today.** The header, `sig`, `param`, and — under
`--mir` — `region` followed by the function's body: one `blk` per basic
block, one `op` per instruction and one `term` per terminator, of the
SSA IR in `self_host/mir.ax` as `mLowerFn` lowered it. `self_host/axir.ax`
imports `mir` for exactly that, and is the one module of the compiler
that does; `scripts/check-mir.sh` §6 pins the importer set rather than
leaving it to grow.

**A body is all or nothing, and it is verified before it is written.**
`mLowerFn` lowers a subset of the checked AST and refuses the whole
function outside it — it never answers a partial one — and what it does
answer goes through `mirVerify` before a line is rendered. A record
carrying a body its own verifier complains about would publish a defect
in the lowering as a fact about the program. Measured 2026-09-04: 389 of
the 839 records for a probe importing every stdlib module carry a body,
and 1,457 of `self_host/main.ax`'s 4,097.

**Under `--mir`, not without it.** `--mir` is the flag documented as
slow — it forces the region-facts fixpoint — and lowering plus verifying
every function is the same kind of cost on the same stream. Measured
2026-09-04 on `self_host/main.ax`: `--axir` 7.2s, `--axir --mir` 31.7s,
and the AXSYM `symbols --mir` on the same file — which lowers nothing —
37.6s, so nearly all of the difference is the fixpoint that flag already
forced. `check-mir-roundtrip.sh` asserts that the default stream carries
no body line, and that the `--mir` stream with its body lines deleted is
the default stream.

**`blk` widened when the body started being written**, and that is a
change to the grammar rather than to its implementation. It was a fixed
two atoms; it is now a label plus a block-parameter list. This IR has
block parameters instead of phi nodes, so a join block names its
incoming value once and each `br` names the argument — and a `blk` that
could write the arguments down but not the parameter they land in is a
record no reader can turn back into a function. The parameters carry the
`%` sigil and the reader strips it, so a register spelled without one is
refused: `tests/axir/blk-param-without-sigil.bad`.

**What is read and still written by nothing.** The grammar is a format
rather than a spelling of one lowering, so the reader accepts block
labels and opcodes this IR does not have — a reader that took only
today's output would refuse tomorrow's. `tests/axir/body.axir` is that
corpus: `entry`, `loop`, `alloc`, `store`, `phi`.
`tests/axir/lowered.axir` is the other side, the emitted shape verbatim.

**Escaping.** A parameter name goes through `saAxSafe`, the escaper
`symbols.ax` already uses for AXTAG payloads on an AXSYM line: every
structural byte as `%XX`. The header name does **not**, and that is a
decision rather than an oversight — see §3.

## 3. The join key is the whole header tuple, not the nid

`docs/compatibility.md` COMPAT-2 says the nid *is* a name's identity.
Across modules that is measurably false.

Measured 2026-09-03 over `axiom symbols self_host/main.ax --builtins
--diagnostic-format ai`: 4,153 lines, 4,068 carrying a nid, **4,066
distinct**. The two collisions are between genuinely different
functions:

| name | one | the other | nid |
| --- | --- | --- | --- |
| `die` | `stdlib/IO.ax:501` | `self_host/main.ax:2009` | `@52fb9ccad9feab1b` |
| `jsonHexDigit` | `self_host/render.ax:1184` | `stdlib/Json.ax:453` | `@9adebbbea99ca85b` |

The nid is FNV-1a 64 over `DKind:name` and the name it hashes is the
**bare** one, so two modules declaring the same unmangled name collide
by construction. A record's header line therefore repeats AXSYM's whole
tuple verbatim — name, location, quoted type, nid — and a tool joining
the two streams joins on the tuple.

Because the join is byte equality, the record must spell the tuple
**exactly** as `symLine` does. `symLine` does not escape the name; nor
does `axirHeader`. What makes that safe is that a declared name is an
identifier and an operator is punctuation, neither of which can carry a
structural byte — a name that could is a generated one, and
`symFnRowSkipped` drops it before either renderer sees it.
`scripts/check-mir-projection.sh` asserts the two tuple sequences are
equal, in order, so the day the spellings diverge is the day that gate
reddens rather than the day a join silently misses a row.

## 4. The AXSYM projection: `--mir`

`FnEnt` word 8 is the region-facts record `rgnFactsNew` builds in
`self_host/typecheck.ax` (stage S3 of the memory-model design): a
per-function interprocedural dataflow summary. Until this release it was
computed, spent on `AX3049` and `AX3060`–`AX3063`, and thrown away.

`axiom symbols --mir` prints it as metadata:

```console
F keep p.ax:3:5-9 "(Int -> (Int -> Int))" @ee8bd13… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F pass p.ax:12:5-9 "(Int -> (Int -> Int))" @c4b4251… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F fresh p.ax:16:5-10 "(Int -> Int)" @24c9891… #effects=Alloc #mir-params=1 #mir-result-fresh
F idf p.ax:20:5-8 "(Int -> (Int -> Int))" @e27158c… #mir-params=2 #mir-result-from=a
```

`pass` calls `keep` and does nothing else; the summary is
interprocedural, so `pass`'s row carries the escape too.

| key | what it says |
| --- | --- |
| `#mir-params=` | the arity the facts were computed over |
| `#mir-escapes=` | this body stores a value it allocated into these parameters |
| `#mir-result-fresh` | the result is allocated in this body |
| `#mir-result-from=` | these parameters' values reach the result |
| `#mir-incomplete` | the walk hit a call head it could not resolve, so this row is a lower bound |
| `#mir-truncated` | the module's facts fixpoint stopped at its round cap, so **every** row is a lower bound |

**The keys are placed after the author's AXTAGs**, like every other
derived key, for the reason `symbols.ax` spells out at `smTagMetas`:
`symTagFrom` answers the *last* `#key` on the line, so a compiler-owned
key placed after the tags cannot be shadowed by a forged one.

**Silence by default has two independent guards.** The first is the
flag. The second is that `rgnEnsureFacts` runs **on demand** — for a
program that names a region or claims `restrict(no-escape)`, and
otherwise never — so a program that does neither has word 8 at 0 and
there is nothing to print whatever anyone asks. Measured 2026-09-03:
removing the flag guard alone leaves `check-mir-projection.sh` green,
because the fixpoint still has not run. Both guards must go for the
silence assertion to fire, and the gate's header says so.

**`--mir` is slow, and the help text says so.** It forces a walk that
would otherwise not run at all. Measured 2026-09-03, three runs each
way with `/usr/bin/time -p`:

| command | without | with |
| --- | --- | --- |
| `axiom check self_host/main.ax` | 0.72s | 21.7s |
| `axiom symbols --diagnostic-format=ai self_host/main.ax` | 10.6s | 79.8s |

### 4.1 The two sentinels, and why they are not optional

`#effects=` has carried `#effects-incomplete` since it shipped, for the
same reason and in the same shape: the key is a **lower bound**, and a
reader who cannot tell a lower bound from a set learns something false.
`docs/agent-harness.md` §3.4 already has `Agent.Policy` reading
`#effects=` that way. A dataflow summary published without its
admissions would be a policy gate reporting a guarantee the compiler
does not have — the AXTAG forgery hole's shape, arriving through the
compiler's own front door instead of through a forged tag.

`#mir-truncated` is the sharper of the two, because the truncation it
reports is real and was silent. `rgnRounds` caps at **40 rounds** and,
until this release, returned with no diagnostic on the truncating
branch. A monotone chain fixpoint over N functions needs up to N rounds,
so a call chain deeper than the cap stops propagating before it has
converged. Measured 2026-09-03 on generated chains `f0 -> f1 -> … -> fN`
whose leaf does `(memSetWord p 0 (memAlloc 8))`, with
`restrict(no-escape)` on `f0`:

| depth | `axiom check` |
| --- | --- |
| 5, 20, 30, 38, 39 | `AX3049` — refused |
| 40, 41, 42, 60 | `OK` — **accepted** |

The bisect is exact: depth 39 refuses, depth 40 accepts a claim the
analysis can itself refute one round later. Timing confirms saturation
rather than convergence — 0.05s at depth 5, 0.11s at 20, 0.24s at 39,
and 0.24s at 60: linear in rounds, then flat.

**Fixing the cap is the region workstream's job, not this one's.**
`inferEffects` in the same file is the shape it wants: it passes
`limit = (vecLen decls) + 1`, runs forward and reverse passes, and
switches to a worklist over `callersIdxBuild` after round 1 — a bound
that cannot truncate a monotone chain fixpoint. What this workstream
fixed is the **silence**: `rgnRounds` now records the truncation, and
`check-mir-projection.sh` pins the sentinel to the boundary (present at
depth 41, absent at depth 5). That is the only assertion in the tree
that watches the cap at all, and when the constant is replaced it is
what will say whether the replacement worked.

Measured on real code the sentinel is not noise: `axiom symbols --mir`
over `self_host/main.ax` reports **0** truncated rows out of 4,114, with
4,023 carrying a summary, 1,157 an escaping parameter and 1,854 the
per-row `#mir-incomplete`.

## 5. The AXDL half: designed, and blocked

An `AX3049` message today names the call path in prose, inside the
quoted message, and carries **no** related location at all:

```text
E AX3049 f.ax:9:5-16 restrict-violated "`parseConfig` performs IO through parseConfig -> readSection -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3" …
```

Measured 2026-09-03: `grep -h AX3049 tests/diagnostics/*.axdl | grep -c
' \^'` is **0**, and the JSON sibling shows `"related":[]` beside that
same message — `render.ax`'s `jsonRelatedArray` is wired and merely
empty. 16 of the 201 `.axdl` goldens carry a resolved `->` chain in a
message; the codes inside them are 26 `AX3049`, 15 `AX3051`, 10
`AX3037`, 9 `AX3004`, 6 `AX3053`, 3 `AX3057`, 2 `AX3038` and one each of
`AX3039`, `AX3011` and `AX3010`. An agent reading any of them has to
re-resolve every hop itself.

Populating the `Diag`'s `secs` vector would make all three renderers
emit the path at once — AXDL's `^` field, the human renderer's `-`
underline, and the JSON `related` array — with no change to any
renderer. **It is blocked on one struct.**

`DLabel` is `(span, msg)`. It has no `unit`, so a related location can
only point into the diagnostic's *own* source file. `DFrame`, the
expansion-backtrace element, does carry one, and `diag.ax`'s comment on
it says why: the file is spelled out "because, uniquely among the line's
fields, this one points into a DIFFERENT source than the diagnostic's
own unit". Four of the six hops in the example above are in `stdlib/`,
so cross-unit is the common case here, not the corner.

The design, for when it is unblocked:

1. Widen `DLabel` with a `unit` slot.
2. Render `^file:LOC:"msg"` when the unit differs from the diagnostic's
   own and the bare `^LOC:"msg"` when it does not — exactly the shape
   `&` already has, so the grammar gains a variant it has already
   demonstrated rather than a new sigil.
3. Populate `secs` at the `AX3049`/`AX3051` emit sites from the same
   walk that builds the prose chain.
4. Extend `check-diagnostics.sh`: for every golden whose message carries
   a `->` chain, each name in that chain must have a matching `^` field
   on the same line. Ablation: drop one hop from `secs` while leaving
   the prose intact; the counts disagree and the gate reddens.

**Why none of it was written.** AXDL and AXSYM are stable formats and
step 2 is a change to AXDL's grammar, which is deferred pending a
decision. The fallback that needs no decision — emit `^` only for the
hops in the diagnostic's own unit and leave the rest as prose — is
*worse than doing nothing*, because it makes the field list look
complete when it is not, which is the failure mode this whole document
is about.

**What is not blocked, and shipped instead.** The `.axir` file carries
the file of every function in its header tuple. An agent holding an
`AX3049` message and the `.axir` file for the same program can resolve
every hop in the chain by name without a grammar change, because a hop
is a function and every function has a record. That is the join the
AXDL half would make one line shorter, not a capability it would add.

**One trap for whoever does write it.** `check-diagnostics.sh` line 161
is `axdl_only() { grep -E '^[EWNH] ' || true; }`, and the same regex
appears in `check-frontend-parity.sh` and three places in
`check-render-selfhost.sh`. The corpus uses only `E` (382 lines) and `W`
(40); `N` and `H` are reserved and unused. A new AXDL line kind outside
that set would be dropped in silence by five gates — a gate that reports
less than it knows. Do not add a line kind; the fields above are enough.

## 6. What is gated

| claim | gate |
| --- | --- |
| a record file survives its own reader unchanged, over the stdlib corpus and `self_host/main.ax` | `scripts/check-mir-roundtrip.sh` |
| the reader decomposes rather than passing lines through — a non-normal file is normalised, and the normal form is a fixed point | `scripts/check-mir-roundtrip.sh` |
| the grammar is closed: every `tests/axir/*.bad` fixture is refused, with a message | `scripts/check-mir-roundtrip.sh` |
| the magic line, not the file name, selects the reader — in both directions | `scripts/check-mir-roundtrip.sh` |
| every `#mir-*` value is re-derivable from its record's raw words, decoded independently | `scripts/check-mir-projection.sh` |
| every AXSYM row has a record, in order, with the same header tuple | `scripts/check-mir-projection.sh` |
| without `--mir` the stream is unchanged, and with it the stream is additive on the byte level | `scripts/check-mir-projection.sh` |
| `#mir-truncated` is present at chain depth 41 and absent at depth 5 | `scripts/check-mir-projection.sh` |
| the AXSYM goldens do not move | `scripts/check-tools-selfhost.sh` |
| a `#mir-*` key is not a compatibility contract | `scripts/check-compat.sh` — `CONTRACT_META` is an explicit allowlist and `#mir-` is not on it |

| the body is written under `--mir` and nowhere else, and `--mir` is additive on the byte level | `scripts/check-mir-roundtrip.sh` |
| a floor under how many records carry a body, and an opcode census derived from `mBinOp` and `axirTermLine` rather than listed | `scripts/check-mir-roundtrip.sh` |
| `mir` is imported by `axir.ax` alone, and `mireval` by nothing in the compiler | `scripts/check-mir.sh` §6 |

**Formerly not gated by the emitted corpus, and now gated by it:** the
`blk`/`op`/`term` half of the grammar rested on the hand-written
`tests/axir/body.axir` alone, because nothing emitted those lines. Since
2026-09-04 the emitted corpus covers them — 1,846 bodies over the two
corpora, every one of the 13 opcode spellings and 5 terminator spellings
reached, 1,236 blocks carrying a parameter — and that file is a
supplement rather than the whole evidence. What it supplements is the
half nothing emits: labels and opcodes outside this lowering, which the
reader must still accept.
