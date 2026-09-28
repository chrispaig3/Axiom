# The `.axir` record file, and the MIR projection through AXSYM

This record covers two ways the compiler hands its mid-level facts to
tools: the `.axir` record file, and the `#mir-*` keys that
`axiom symbols --mir` adds to AXSYM. It also records the AXDL change
that puts a diagnostic's call chain into related-location fields. For
the user-facing text, run `axiom help symbols`.

| Part | Status | Gated by |
| --- | --- | --- |
| The `.axir` format, its reader, and the AXSYM `--mir` projection | Shipped in 0.7.3 | `scripts/check-mir-roundtrip.sh`, `scripts/check-mir-projection.sh` |
| Body lines (`blk`, `op`, `term`) from `self_host/mir.ax`, written by `symbols --axir --mir` | Shipped in 0.7.5 | `scripts/check-mir-roundtrip.sh`, `scripts/check-mir.sh` |
| The AXDL half: call chains as related locations (§5) | Shipped in 0.7.5 | `scripts/check-diagnostics.sh` and the span verifier it runs |

## 1. Why the extension is not `.mir`

LLVM already uses `.mir` for Machine IR: the post-instruction-selection
form that `llc -stop-after=<pass>` writes. This toolchain produces it
today. With `llc` from Homebrew LLVM 23.1.0 for
arm64-apple-darwin25.6.0, this exits 0:

```console
$ axiom emit-llvm s1.ax > s1.ll        # 1,312 lines
$ llc -stop-after=finalize-isel -o s1.mir s1.ll
$ wc -c s1.mir
  248183 s1.mir
```

Axiom's mid-level IR sits above LLVM IR, and LLVM's Machine IR sits
below it. If two IRs in one tree shared an extension, every later tool
would have to sniff a file's contents to learn which one it held.

So the extension is `.axir`, and every file starts with a magic line
rather than a comment:

```text
axir 1 <target> <version>
```

The magic line does real work. `axiom symbols --axir` reads its input
file to decide what to do with it: a file that starts with `axir 1 ` is
read back and re-emitted, and anything else is compiled. `scripts/check-mir-roundtrip.sh` checks both directions: a
record file named `.ax` still reads back, and a source file named
`.axir` still compiles. The file name never decides.

## 2. The grammar

One fact per line: LF-terminated, ASCII, whitespace-delimited and
colourless. These are AXSYM's rules. A second set of rules for a second
agent-facing stream would be a second thing to get wrong.

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

The set of line kinds is closed. `axirRead` refuses a line whose first
word it doesn't know, or whose field count is wrong, with a message
naming the kind. The driver's flag table refuses an unknown flag the
same way. A format that silently dropped an unrecognised line would
report less than it was given, which is a hazard this repository
names.

### 2.1 What is written

Every record has its header, a `sig` line and one `param` line per
parameter. Under `--mir` it also has `region`, followed by the function's body: one `blk` per basic
block, one `op` per instruction and one `term` per terminator. The body
is the SSA IR in `self_host/mir.ax`, as `mLowerFn` lowered it.

`self_host/axir.ax` imports `mir` to write the body.
`scripts/check-mir.sh` §6 pins the exact set of modules that import
`mir` (`axir.ax`, `codegen.ax` and the test-only evaluator
`mireval.ax`), so a new consumer can't arrive unnoticed.

### 2.2 A body is all or nothing, and verified first

`mLowerFn` lowers a subset of the checked AST. Outside that subset it
refuses the whole function and never returns a partial one. What it
does return goes through `mirVerify` before a line is rendered. A
function that is refused, or whose lowering fails verification, keeps
its record with no body lines.

A body that failed its own verifier would publish a defect in the
lowering as a fact about the program. For a probe importing every
stdlib module, 389 of the 839 records carry a body. For
`self_host/main.ax`, 1,457 of 4,097 do.

### 2.3 Bodies are written only under `--mir`

`--mir` is the flag documented as slow, because it forces the
region-facts fixpoint. Lowering and verifying every function is the
same kind of cost on the same stream. On `self_host/main.ax`:

| command | time |
| --- | --- |
| `axiom symbols --axir` | 7.2s |
| `axiom symbols --axir --mir` | 31.7s |
| `axiom symbols --mir` (AXSYM, which lowers nothing) | 37.6s |

Nearly all of the difference is the fixpoint the flag already forced.
`check-mir-roundtrip.sh` checks that the default stream carries no body
line, and that the `--mir` stream with its `region` and body lines
deleted is the default stream.

### 2.4 `blk` carries block parameters

A `blk` line is a label followed by a block-parameter list. It was a
fixed two atoms before bodies were written, so this is a change to the
grammar itself.

This IR uses block parameters instead of phi nodes. A join block names
its incoming value once, and each `br` names the argument. A `blk` line
that wrote the arguments but not the parameters they land in would be
a record no reader could turn back into a function.

The parameters carry the `%` sigil and the reader strips it, so a
register spelled without one is refused:
`tests/axir/blk-param-without-sigil.bad`.

### 2.5 `term condbr` carries block arguments

A `while` passes its carried `mut`s to both the body and the exit. So
the `condbr` line names both successors, then the shared argument list:
`term condbr %9 bb2 bb3 %3 %4`. An `if` passes nothing, and its line
ends at the second successor.

The reader takes a variable operand list, so the bare and applied forms
are one rule. The `.mir` printer keeps the same uniformity:
`condbr %9, bb2, bb3` beside `condbr %9, bb2(%3, %4), bb3(%3, %4)`.

### 2.6 What the reader accepts that nothing writes

The grammar is a format, not the spelling of one lowering. So the
reader accepts block labels and opcodes this IR doesn't have. A reader
that took only today's output would refuse tomorrow's.

`tests/axir/body.axir` is that corpus: `entry`, `loop`, `alloc`,
`store`, `phi`. `tests/axir/lowered.axir` is the other side: the
emitted shape, verbatim.

### 2.7 Escaping

A parameter name goes through `saAxSafe`, the escaper `symbols.ax`
already uses for AXTAG payloads on an AXSYM line. It writes every
structural byte as `%XX`. The name in the header line is not escaped,
for the reason in §3.

## 3. The join key is the whole header tuple, not the nid

[`compatibility.md`](compatibility.md) COMPAT-2 says the nid *is* a
name's identity. Across modules, that doesn't hold.

Over `axiom symbols self_host/main.ax --builtins --diagnostic-format ai`
there are 4,153 lines, 4,068 of them carrying a nid, and 4,066 distinct
nids. The two collisions are between genuinely different functions:

| name | one | the other | nid |
| --- | --- | --- | --- |
| `die` | `stdlib/IO.ax:501` | `self_host/main.ax:2009` | `@52fb9ccad9feab1b` |
| `jsonHexDigit` | `self_host/render.ax:1184` | `stdlib/Json.ax:453` | `@9adebbbea99ca85b` |

The nid is FNV-1a 64 over `DKind:name`, and the name it hashes is the
bare one. So two modules declaring the same unmangled name collide by
construction. A record's header line therefore repeats AXSYM's whole
tuple verbatim (name, location, quoted type, nid), and a tool joins the
two streams on the tuple.

The join is byte equality, so the record must spell the tuple exactly
as `symLine` does. `symLine` doesn't escape the name, and neither does
`axirHeader`. That is safe because a declared name is an identifier and
an operator is punctuation, and neither can carry a structural byte. A
name that could is a generated one, and `symFnRowSkipped` drops it
before either renderer sees it.

`scripts/check-mir-projection.sh` checks that the two tuple sequences
are equal, in order. If the spellings ever diverge, that gate fails,
rather than a join silently missing a row.

## 4. The AXSYM projection: `--mir`

`FnEnt` word 8 is the region-facts record that `rgnFactsNew` builds in
`self_host/typecheck.ax` (stage S3 of the memory-model design). It is a
per-function, interprocedural dataflow summary. The checker spends it
on `AX3049` and `AX3060`–`AX3063`, and `axiom symbols --mir` prints it
as metadata:

```console
F keep p.ax:3:5-9 "(Int -> (Int -> Int))" @ee8bd13… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F pass p.ax:12:5-9 "(Int -> (Int -> Int))" @c4b4251… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F fresh p.ax:16:5-10 "(Int -> Int)" @24c9891… #effects=Alloc #mir-params=1 #mir-result-fresh
F idf p.ax:20:5-8 "(Int -> (Int -> Int))" @e27158c… #mir-params=2 #mir-result-from=a
```

`pass` calls `keep` and does nothing else. The summary is
interprocedural, so `pass`'s row carries the escape too.

| key | what it says |
| --- | --- |
| `#mir-params=` | the arity the facts were computed over |
| `#mir-escapes=` | this body stores a value it allocated into these parameters |
| `#mir-result-fresh` | the result is allocated in this body |
| `#mir-result-from=` | these parameters' values reach the result |
| `#mir-incomplete` | the walk hit a call head it could not resolve, so this row is a lower bound |
| `#mir-truncated` | the module's facts fixpoint stopped at its round cap, so **every** row is a lower bound |

The keys go after the author's AXTAGs, like every other derived key,
for the reason `symbols.ax` gives at `smTagMetas`. `symTagFrom` answers
the *last* `#key` on the line, so a compiler-owned key placed after the
tags can't be shadowed by a forged one.

Two independent guards keep the stream silent by default. The first is
the flag. The second is that `rgnEnsureFacts` runs on demand: only for
a program that names a region or claims `restrict(no-escape)`. A
program that does neither has word 8 at 0, so there is nothing to
print, whatever the flags.

Removing the flag guard alone leaves `check-mir-projection.sh` green,
because the fixpoint still hasn't run. Both guards must go before the
silence assertion fires, and the gate's header says so.

`--mir` is slow, and the help text says so. It forces a walk that
otherwise wouldn't run at all. Three runs each way with
`/usr/bin/time -p`:

| command | without | with |
| --- | --- | --- |
| `axiom check self_host/main.ax` | 0.72s | 21.7s |
| `axiom symbols --diagnostic-format=ai self_host/main.ax` | 10.6s | 79.8s |

### 4.1 The two sentinels, and why they are not optional

`#effects=` has always carried `#effects-incomplete`, for the same
reason and in the same shape. The key is a lower bound, and a reader
who can't tell a lower bound from a set learns something false.
[`agent-harness.md`](agent-harness.md) §3.4 already has `Agent.Policy`
reading `#effects=` that way.

Without its admissions, a dataflow summary would let a policy gate
report a guarantee the compiler doesn't have. That is the AXTAG forgery
hole, arriving through the compiler's own output instead of a forged
tag.

`#mir-truncated` is the sharper of the two, because the truncation it
reports was real and silent. `rgnRounds` once had a fixed cap of 40
rounds, and at first returned from the truncating branch with no
diagnostic. A monotone chain fixpoint over N functions needs up to N
rounds, so a call chain deeper than the cap stopped propagating before
it converged.

The evidence came from generated chains `f0 -> f1 -> … -> fN` whose
leaf does `(memSetWord p 0 (memAlloc 8))`, with `restrict(no-escape)`
on `f0`:

| depth | `axiom check`, under the 40-round cap |
| --- | --- |
| 5, 20, 30, 38, 39 | `AX3049`: refused |
| 40, 41, 42, 60 | `OK`: **accepted** |

The bisect was exact. Depth 39 was refused, and depth 40 accepted a
claim the analysis could refute one round later. Timing confirmed
saturation rather than convergence: 0.05s at depth 5, 0.11s at 20,
0.24s at 39 and 0.24s at 60. That is linear in rounds, then flat.

The bound is now `(vecLen decls) + 1`, as `inferEffects` passes it, so
every depth in that table is refused. `inferEffects`, in the same file,
is the model: it passes `limit = (vecLen decls) + 1`, runs forward and
reverse passes, and switches to a worklist over `callersIdxBuild` after
round 1. That bound can't truncate a monotone chain fixpoint. Not yet:
`rgnRounds` has the bound but not the worklist, which is still to come
for adversarial declaration orders.

`rgnRounds` still records a truncation, though it never reaches one, so
the sentinel is a net no program reaches. `check-mir-projection.sh`
checks that it is absent at depth 5 and at depth 60, with the escape
carried all the way to `f0`'s row. That is the one assertion in the
tree that watches the cap, and it is what showed the new bound works.

On real code the sentinel is not noise. `axiom symbols --mir` over
`self_host/main.ax` reports 0 truncated rows out of 4,541, with 1,322
rows carrying an escaping parameter and 2,061 carrying the per-row
`#mir-incomplete`.

<a id="5-the-axdl-half-shipped-2026-09-04"></a>
## 5. The AXDL half: call chains as related locations

### 5.1 The problem

An `AX3049` message named the call path in prose, inside the quoted
message, and carried no related location at all:

```text
E AX3049 f.ax:9:5-16 restrict-violated "`parseConfig` performs IO through parseConfig -> readSection -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3" …
```

`grep -h AX3049 tests/diagnostics/*.axdl | grep -c ' \^'` counted 0,
and the JSON form showed `"related":[]` beside the same message.
`render.ax`'s `jsonRelatedArray` was wired, and merely empty. 16 of the
204 `.axdl` goldens carried a resolved `->` chain in a message, and an
agent reading any of them had to re-resolve every hop itself.

The blocker was one struct. `DLabel` was `(span, msg)`, with no unit,
so a related location could only point into the diagnostic's own
source file. Four of the six hops above are in `stdlib/`, so cross-unit
is the common case here. Fixing it meant changing AXDL's grammar, which
is a stable format.

### 5.2 What shipped

Four steps, in order, each held to a check.

1. `DLabel` gained a `unit` slot, with the sentinel `-1` for "the
   diagnostic's own". It is `-1` rather than `0` because `0` is a real
   unit index (the entry file), and a secondary genuinely in unit 0
   must stay distinguishable from one that named no unit.
   `diagSecUnit` reads it and `diagAddSecondaryIn` writes it.
   `diagAddSecondary` keeps its arity and writes the sentinel. So the
   two fixtures that call it (`tests/selfhost/640-axdl-render.ax` and
   `tests/selfhost/645-axdl-repetition.ax`) didn't change, and neither
   did any golden that already carried a `^`.
2. Three spellings for a related location:
   - `^LOC:"msg"`, which the grammar always had;
   - `^FILE:LOC:"msg"`, for another unit, in the shape `&` already
     used;
   - `^-:"msg"`, for a hop with no location. `-` is what the primary
     `FILE:LOC` field already says for a spanless diagnostic.

   The third is what makes the whole thing checkable. A hop that is a
   builtin or an `extern` item has no declaration in any unit. Dropping
   it would give a field list that looks complete when it isn't. None
   of this adds a line kind, so the trap in §5.5 is untouched.
3. `AX3049`, `AX3051` and `AX3057` fill `secs` from the same vector the
   prose is rendered from. `witnessTextOf` and `witnessSecPath` take
   the path rather than walking for one, so the message and the fields
   can't disagree about which hops there are.
4. The gate. `tests/diagnostics/verify-axdl-spans.py` parses the two
   new spellings and checks hop-for-hop equality: the k-th `^` field's
   label is the (k+1)-th hop of the chain, spelled the same way, and
   there are exactly as many fields as hops after the first.
   `check-diagnostics.sh` runs it on the check path, and again before a
   bless returns.

### 5.3 The rule

There is one field per hop after the first. The first hop is the
declaration the diagnostic is already reported at, and its span is the
primary field. A hop with no declaration gets a field with `-` where
its location would be.

The count is exact only with both halves. Without the second, a shorter
chain would satisfy "one per hop", and the comparison would pass over a
field list that isn't the whole chain.

After the change, the corpus has 22 lines carrying a chain, and 51 hops
checked against a `^` field. Of those hops, 13 have no declaration to
point at and 22 are in another unit. Four floors on those four numbers
refuse a corpus that stops exercising any of them. A fifth, in
`check-diagnostics.sh` itself, reads the population off the checked-in
goldens with `grep`, because the equality says nothing when it holds
over zero lines.

The ablation: in a copied tree, `restrictPathSecs` was started at hop 2
instead of hop 1. That drops one hop from `secs` and leaves the prose
alone. The corpus was then re-blessed from the resulting compiler, and
the bless is refused. 22 goldens report the disagreement by name (`the
message names 4 hop(s) after the first [...] and the line carries 3`),
and two of the floors fail as well. A wrong chain can't be blessed into
the corpus.

### 5.4 Where it doesn't reach

A cross-unit related location can't be drawn in the human snippet. The
snippet is quoted from one source, and another file's line number would
put a caret under the wrong text. So it renders as a note carrying its
own file and position, the same way an expansion frame with no
reachable unit already degrades.

The LSP publishes neither the cross-unit kind nor the location-less
kind. The server holds one document and no unit table, so it drops a
hop it can't place rather than aiming it at the open file's URI.

Two consequences follow:

- A golden now cites `stdlib/IO.ax` by line. An edit that moves a line
  in `stdlib/` fails `check-diagnostics.sh`, with a diff you can read
  and a one-command re-bless.
- File names must be repository paths. Both corpus gates export a
  relative `AXIOM_STDLIB`, because the absolute one `gate_init` sets
  would put `/Users/somebody/checkout/stdlib/IO.ax` in a checked-in
  file. `verify-axdl-spans.py` refuses an absolute path outright.

An agent holding an `AX3049` and the `.axir` file could already resolve
every hop by name, because each header tuple carries the function's
file. This change makes that join one line shorter.

### 5.5 The line-kind trap

`check-diagnostics.sh` filters AXDL lines with
`axdl_only() { grep -E '^[EWNH] ' || true; }`. The same regex appears
in `check-frontend-parity.sh`, and in three places in
`check-render-selfhost.sh`. The corpus uses only `E` (382 lines) and
`W` (40). `N` and `H` are reserved and unused.

A new AXDL line kind outside that set would be dropped in silence by
five gates: a gate that reports less than it knows. This change added
three field spellings and no line kind.

## 6. What is gated

| claim | gate |
| --- | --- |
| a record file survives its own reader unchanged, over the stdlib corpus and `self_host/main.ax` | `scripts/check-mir-roundtrip.sh` |
| the reader decomposes rather than passing lines through: a non-normal file is normalised, and the normal form is a fixed point | `scripts/check-mir-roundtrip.sh` |
| the grammar is closed: every `tests/axir/*.bad` fixture is refused, with a message | `scripts/check-mir-roundtrip.sh` |
| the magic line, not the file name, selects the reader, in both directions | `scripts/check-mir-roundtrip.sh` |
| the body is written under `--mir` and nowhere else, and `--mir` is additive on the byte level | `scripts/check-mir-roundtrip.sh` |
| a floor under how many records carry a body, and an opcode census derived from `mBinOp` and `axirTermLine` rather than listed | `scripts/check-mir-roundtrip.sh` |
| `mir` is imported by exactly `axir.ax`, `codegen.ax` and `mireval.ax`, and `mireval` by nothing in the compiler | `scripts/check-mir.sh` §6 |
| every `#mir-*` value is re-derivable from its record's raw words, decoded independently | `scripts/check-mir-projection.sh` |
| every AXSYM row has a record, in order, with the same header tuple | `scripts/check-mir-projection.sh` |
| without `--mir` the stream is unchanged, and with it the stream is additive on the byte level | `scripts/check-mir-projection.sh` |
| `#mir-truncated` is absent at chain depths 5 and 60, and the depth-60 chain carries its escape to `f0`'s row | `scripts/check-mir-projection.sh` |
| the AXSYM goldens don't move | `scripts/check-tools-selfhost.sh` |
| a `#mir-*` key is not a compatibility contract | `scripts/check-compat.sh`: `CONTRACT_META` is an explicit allowlist, and `#mir-` isn't on it |
| a diagnostic's call chain is in its `^` fields, not only in its prose: one field per hop after the first, labelled with the hop's resolved name, in order | `tests/diagnostics/verify-axdl-spans.py`, run by `scripts/check-diagnostics.sh` on the check path and before a bless returns |
| a hop with no declaration is still a field (`^-:"name"`), so the list is the whole chain | the same equality, plus a floor on how many location-less fields the corpus carries |
| the cross-unit spelling is still produced, and its spans are true of `stdlib/`'s own bytes | the same verifier: every `^FILE:LOC` claim is recomputed from that file, and an absolute path is refused outright |
| the corpus still carries chains, so the equality doesn't hold over nothing | `scripts/check-diagnostics.sh`: the population is read off the checked-in goldens by `grep`, and floored |
| the human and JSON surfaces say the same thing about every related location, including the two kinds that can't be drawn in a snippet | `scripts/check-render-selfhost.sh`: one dash row per same-file field as an equality, and the note text derived from the AXDL field |

The emitted corpus covers the body half of the grammar: 1,846 bodies
over the two corpora, every one of the 13 opcode spellings and 5
terminator spellings, and 1,236 blocks carrying a parameter.
`tests/axir/body.axir` supplements it with the half nothing emits:
labels and opcodes outside this lowering, which the reader must still
accept.
