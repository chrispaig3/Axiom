# Road to Axiom v1

What "v1" means, what is done, what is left, and — the part that changes
how the work should be scheduled — what actually blocks what.

This document follows the convention of
[docs/self-hosting.md](self-hosting.md): every capability claim is stated
with the observation that established it, so a reader can re-run the probe
rather than take the claim on trust. Where a number appears, the command
that produced it appears with it.

---

## 1. The dependency structure

The v1 feature list reads as a set of parallel workstreams. It is not one.
Four of the headline items cannot be started until earlier items land, and
scheduling them in parallel is the single most likely way for this effort
to produce a large amount of code that does not work.

```
                        ┌──────────────────────────┐
                        │  P0  green CI, no legacy │  ← done
                        └────────────┬─────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
     ┌─────────────────┐   ┌──────────────────┐   ┌──────────────────┐
     │ B1 closures     │   │ B2 guaranteed    │   │ ADT revision     │
     │ (function       │   │ tail calls       │   │ (struct variants)│
     │  values)        │   │                  │   │                  │
     └────────┬────────┘   └────────┬─────────┘   └────────┬─────────┘
              │                     │                      │
              │            ┌────────▼─────────┐            │
              │            │ B3 Vec/Map/      │            │
              │            │ Intern in Axiom  │            │
              │            └────────┬─────────┘            │
              │                     │                      │
              ▼                     ▼                      ▼
      ┌───────────────────────────────────────────────────────────────┐
      │  Memory model: arena inference + deterministic drop           │
      └──────────────────────────────┬────────────────────────────────┘
                                     │
               ┌─────────────────────┼─────────────────────┐
               ▼                     ▼                     ▼
      ┌────────────────┐   ┌──────────────────┐  ┌──────────────────┐
      │ Macro system   │   │ HTTP library     │  │ B4 namespacing   │
      └────────┬───────┘   └────────┬─────────┘  └────────┬─────────┘
               │                    │                     │
               │                    │                     │
               └──────────────┬─────┴─────────────────────┘
                             ▼
                    ┌──────────────────┐
                    │ Self-hosting     │
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────┐
                    │ LSP in Axiom     │
                    └──────────────────┘
```

The three edges worth arguing about, because they are the ones that look
optional:

**Macros depend on the memory model, not the reverse.** A macro expander
allocates heavily and transiently: it walks a syntax tree and builds
another one, discarding intermediate forms. Under the current allocator
that cost is unbounded — see §2.2 for the measurement. Writing the
expander first means writing it against an allocator it will have to be
rewritten for.

**HTTP depends on the memory model, not on native concurrency.** A
non-blocking HTTP library is an event loop plus per-connection state. An
event loop can be implemented in user space with the existing syscall
primitives; it does not require native concurrency. The memory model
provides the safety guarantees (no data races) that make a user-space
concurrency library sound.

**The LSP is last, and this is the least negotiable edge.** An LSP is
mostly maps and closures: a symbol index, an incremental cache, a table of
request handlers. Axiom today has `Vec`/`Map`/`Intern` (golden-tested and
validated at 10⁵; `Map`'s throughput is the open part), function values
(`B1`) and namespacing (`B4`). It is also the largest program that would be
written in Axiom, which makes it the worst possible vehicle for
discovering that the language cannot express something. Self-hosting the
compiler first is the cheaper way to find that out, because the compiler
already exists in Rust and can be differentially tested against itself —
see [self-hosting.md §3](self-hosting.md).

What genuinely *is* parallel: the ADT revision, guaranteed tail calls,
closures, and the data structures. None depends on another, and together
they unblock everything downstream.

---

## 2. Where things stand

### 2.1 Done, and verified

| | Evidence |
|---|---|
| CI green on all four targets | §3 below; two root-caused failures fixed. Re-checked and **was not green** — see §2.5 — for two further reasons, both now fixed |
| `fmt` round-trips every file | §2.3; 70/70, gated by `scripts/check-fmt.sh` |
| The REPL evaluates | §2.4; every result type, freestanding, gated by integration tests |
| Floating point works | §2.4b; arithmetic, comparison, conversion, formatting, and floats through ADTs — `tests/stdlib/240-float.ax` |
| Self-hosting fixpoint `stage2 == stage3` | `scripts/check-bootstrap.sh`, now run in CI (§2.5) |
| `union` removed, `region` removed | `AX2004` with migration advice; 3 regression tests |

| Editor grammar | [tree-sitter-axiom/](../tree-sitter-axiom/), 70/70 repo files, ~18 MB/s. The 18/18 this used to claim was true when the repo had 18 `.ax` files; the gate then silently skipped for want of its CLI while the real figure fell to 27/70. See the risk table |
| Freestanding stdlib | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO` over syscalls; no libc |
| Reproducible builds | byte-identical IR across runs, gated in CI |

Reproduce all of it:

```bash
cargo test --release --all
./scripts/run-stdlib-tests.sh
./scripts/check-freestanding.sh
./scripts/check-cross-targets.sh
./scripts/check-reproducible.sh
./scripts/check-tree-sitter.sh
./scripts/check-self-host.sh
./scripts/check-bootstrap.sh
./scripts/check-fmt.sh
```

All eight gates and `cargo test --release --all` pass, and
`cargo clippy --all-targets --all-features -- -D warnings` is clean.



### 2.3 `axiom fmt` round-trips source — and did not, in six ways

`fmt` was the one part of the CLI with no CI gate, and it had six
independent ways of silently destroying a source file. Formatting any of
the 70 `.ax` files in this repository lost something, and every loss was
reported as a successful format.

| Loss | Consequence |
|---|---|
| Every `(import ...)` declaration | Imports live in `Module::imports`; the printer walked only `Module::decls`. The formatted file no longer compiled |
| Every `pub` marker | The module's entire export surface. Parses fine, so nothing complains until an importer fails against a name still visibly present in the file |
| Every AXTAG | Real tokens, so the comment guard never counted them — the one category deleted without even a refusal. They are compiler-checked metadata |
| Every block comment | The lexer recorded spans for line comments only, so `#\| ... \|#` was invisible to the guard too |
| `((Red) 1)` → `(Red 1)` | A nullary constructor pattern becomes a *variable* pattern that binds anything. The first arm matches every value and every later arm is unreachable. Compiles, runs, returns the first arm's answer for every input |
| `(Circle { r : Int })` → `(Circle Int)` | A struct variant demoted to positional; every `s.r` and every named pattern then fails to resolve |

plus three spelling changes that were not losses but were not
round-trips either: `fn` rewritten to the legacy `define`, `(-> a b c)`
re-emitted curried as `(-> a (-> b c))` — growing a paren level per
parameter on every run — and `(let ((x 1)))` rewritten to `(let ((x = 1)))`,
a spelling that appears nowhere in the corpus and that the self-hosted
parser does not implement, so formatting a file broke the bootstrap.

Two of these had tests. Both tests asserted only an exit status, which is
why `fmt_counts_axtags_as_preserved` stayed green while the AXTAG it was
named after was being deleted.

**What changed.** Comments are now recovered from the spans the lexer
records as it discards them, and re-emitted by walking the tree and the
comment list together in source order: own-line comments are emitted
above the construct that followed them, trailing comments back onto the
line they annotated. A trailing comment is only re-attached to a
construct the formatter kept on one line, which is what makes the result
a fixed point — a one-line source construct that the printer breaks
across several lines would otherwise move its comment on every run.

`fmt` also verifies its own output before writing: the result must
re-parse, carry exactly the comments the input carried, and be a fixed
point under a second formatting pass. That check is a property rather
than a list of the bugs above, and it is what refuses rather than
destroys when a construct is still printed wrongly.

All 70 files now format. The gate is `scripts/check-fmt.sh`, which
formats a copy of the whole repository and re-runs the standard-library
and self-hosting suites against it — because the nullary-pattern bug
produced a program that parsed, compiled and ran, and only a behavioural
check could see it.

Trivia preservation is consequently **done** rather than scheduled for
P5. The LSP still needs the same machinery, and can reuse it.

### 2.4 Open blockers, unchanged

`B1`–`B4` and `S1`–`S5` from
[self-hosting.md §2](self-hosting.md#2-capability-gaps-measured) all still
hold. The ones on the critical path here:

- **B1** — function values. **(DONE)** Closure record, indirect call;
  `tests/stdlib/140-function-values.ax`.
- **B2** — recursion depth no longer depends on `--opt`: tail calls are
  guaranteed in the IR, and `while` (S5) gives an explicit loop that
  runs 10⁷ iterations in constant stack at `-O0`. *Non*-tail recursion
  is still bounded, measured at 60,000–80,000 frames on an 8 MiB
  stack.
- **B3** — `Vec`, `Map`, and `Intern` are golden-tested and validated at
  10⁵ (`tests/stdlib/200-scale.ax`) and benchmarked at 10⁶
  (`scripts/bench-datastructures.sh`). **`Map` now meets the 2×
  criterion: 1.80×**, from 14×. The cause was never the allocator this
  entry used to blame: `mapHash` was affine in the key for keys below
  2²², so sequential keys clustered and linear probing ran 71 probes
  per insert; a real avalanche hash (fmix64) plus byte-wide state tags
  fixed it, and the earlier "growth is six sevenths of the cost"
  ablation was the same bug measured through rehash. `Intern` is
  *faster* than Rust (0.73×); `Vec` is 3.4×, three header loads against
  a register-resident Rust `Vec`, ~5 ms absolute at compiler scale.
  See [self-hosting.md §2.1 B3](self-hosting.md#21-blockers) for the
  full correction.
- **B4** — namespacing: `Mod::name` qualified access works; two modules can define the same name without collision. **(DONE)**
- **S1** — **(DONE)** nullary constructors are immediates rather than
  heap blocks, in mixed types as well as all-nullary ones; a `match`
  over a mixed type reads the tag through a runtime
  immediate-vs-pointer guard. Constructors with fields still box. See
  [self-hosting.md §2.2 S1](self-hosting.md#22-serious-but-workable);
  pinned by `tests/stdlib/270-nullary-unboxed.ax`.

---

### 2.4 The REPL could not evaluate anything

The same reasoning that found six bugs in `fmt` — a surface with no gate
is a surface nobody has checked — applies to the two the risk table
names next. `explain` held up. `repl` did not: it could not evaluate a
single expression.

Typing `(+ 1 2)` produced raw `llc` output and no result. The wrapper the
REPL builds around a typed expression bound C's `printf` to print it, and
since strings became first-class in 7b786e1 a `String` is the address of
a `{len, bytes}` header rather than a `char*`. The call emitted `i64`
where the declaration said `ptr`, so `llc` rejected every module the REPL
produced. Had it assembled, `printf` would have read the length word as
its format string.

That binding also made the REPL the one code path in the project that
called libc, which `check-freestanding.sh` forbids everywhere else — its
output declared `printf`, `puts`, `malloc`, `free`, `memset`, `memcpy`
and `exit`. Printing now goes through `IO`, so the REPL is freestanding
like everything else.

Four further problems were behind that one:

- **Failures printed nothing.** Every stage was wrapped in `if let Ok(..)`
  with no `else`, so an expression that failed to parse, resolve,
  type-check or lower produced no output at all — the REPL printed the
  type and returned to the prompt, which reads as the evaluator having
  decided the answer was nothing.
- **`:time` timed the compiler giving up.** It printed a duration
  whenever code generation succeeded, including for expressions that
  never ran.
- **The wrapper existed in three copies** — evaluation, `:time` and
  `:llvm` each had their own — so `:llvm` still emitted libc calls after
  the first two were fixed. They are now one function.
- **Scratch files were written to the working directory.** The REPL could
  not run at all from a directory without write access, littered a
  project on any early exit, and two concurrent sessions overwrote each
  other's object file. They now go to a private directory under the
  system temp dir.

A `Char` result exposed a bug in the compiler rather than the REPL. A
character literal lowered as `U8` while `Char` maps to `i64` everywhere
else — in signatures, in `strByte`'s `zext i8 to i64`, in `__store8`'s
truncate — so *any* function returning a `Char` emitted `ret i8` from a
function declared `i64`. `axiom check` reported OK and the failure then
arrived from `opt`, about generated code, for a program the compiler had
just called well-typed. Nothing in the standard library returns a `Char`,
so nothing had noticed. Pinned by `tests/stdlib/230-char.ax`.

The REPL and `explain` are now covered by integration tests that drive
the real binary, including one asserting that every code `explain --list`
advertises can actually be explained.

### 2.4b Floating point is implemented

Found by probing whether the `Char` bug above was one of a class: a
literal whose IR type disagrees with what the type maps to in LLVM.
`Float` had exactly the same defect, and rather more behind it.

Axiom had a `Float` type name and a lexer that read `1.5`, and nothing
else. The arithmetic operators were registered as `Int -> Int -> Int`
builtins, so any float operand was a type error; code generation emitted
no floating-point instruction of any kind — no `fadd`, `fmul`, `fsub`,
`fdiv`; and a function declared to return `Float` emitted `ret double`
from a function LLVM declared to return `i64`, so the error arrived from
`opt` after `axiom check` had reported the program well typed. No `.ax`
file in the repository contained a float literal, which is why none of
it had been noticed.

**The representation.** Every Axiom value is one machine word, and a
`double` is 64 bits, so a float is carried as the `i64` holding its
IEEE-754 bit pattern *everywhere* — parameters, returns, constructor
fields, `Vec` slots — and is bitcast to `double` only inside the
arithmetic itself. Nothing else in the compiler learns that floats
exist: `data`, `struct`, closures, `Map` and polymorphism carry them
unchanged, and no calling convention, field layout or type mapping
needed to change. The bitcasts are free at runtime, and the register
allocator keeps a chain of float operations in FP registers.

The cost of that choice is that *nothing about a value says it is a
float* — only its type does, and by lowering time the type checker is
gone. So the IR generator reconstructs it from signatures: which
functions return floats, which parameters are floats, which constructor
fields and struct fields are, and which `let` bindings and pattern
bindings therefore are. That is what decides whether `(+ a b)` lowers to
`add` or `fadd`.

**What works**: arithmetic and ordered comparison (`fcmp o*`, so NaN
compares false), float parameters/returns/locals, floats through `data`
constructor fields and patterns, `__intToFloat`/`__floatToInt` numeric
conversion, and `Fmt`'s `fmtFloat`/`fmtFloatPrec` for fixed-point
output with correct rounding carry. Mixing `Int` and `Float` operands is
an error rather than an implicit widening, since a silent conversion is
how precision is lost with nothing in the source saying so; `cast`
reinterprets rather than converts, which is exactly what lets a float
travel through the `Int`-typed standard library and come back intact.

**What does not**: `%` and the bitwise operators stay `Int`-only, and
formatting is fixed-point rather than shortest-round-trip (Ryu/Grisu
needs big-integer arithmetic and is a module of its own). `F32` is
accepted as a type name but computed at double precision, because one
value is one word.

Covered by `tests/stdlib/240-float.ax` and five integration tests. The
formatter needed a fix of its own to keep up: it printed a float through
`Display`, so `2.0` came out as `2`, which re-lexes as an `Int` — caught
by `check-fmt.sh` rather than by anything about floats.

### 2.4c The representation bugs were a class, not three accidents

`Char`, `Float` and `Bool` each failed in the same shape, and each was
found only by trying it rather than by any gate:

| Type | What it emitted | Why |
|---|---|---|
| `Char` | `ret i8` from an `i64` function | the literal lowered as `U8`, while `Char` maps to `i64` |
| `Float` | `ret double` from an `i64` function | no float lowering existed at all |
| `Bool` | `store i64 true` | `i1` is genuinely narrower than a word, and was stored into a field unwidened |

All three passed `axiom check` and then failed in `llc` or `opt` — a
native-toolchain message about generated code, for a program the
compiler had just called well typed. And all three went unnoticed for
the same reason: nothing in `stdlib/`, `self_host/` or `tests/` puts a
`Char`, `Float` or `Bool` in a field, so the corpus never asked.

The underlying property is one sentence — *every Axiom value is one
machine word, and a field is one word* — and it is now tested as one
thing rather than three: `tests/stdlib/250-field-kinds.ax` is the matrix
of every value kind against `data` constructor fields (single and
multi-field, so offsets are exercised) and `struct` fields.

`Bool` is the only Axiom type narrower than a word, so it is the only
one needing a widening at a word boundary; that widening is now applied
wherever a value enters a word slot, not only in the two arithmetic
sites that already did it.

### 2.4d A gate is only as wide as the corpus it runs on

`check-fmt.sh` formats every `.ax` file in the repository and re-runs the
suites against the result, which sounds exhaustive and is not: the corpus
uses `data`, `struct`, `fn` and `macro` and nothing else. Counted
directly — `type`, `trait`, `impl`, `effect`, `foreign`, `cond` and
top-level `lambda` appear **zero** times across `stdlib/`, `self_host/`
and `tests/`. So the formatter was broken for most of the language with
the gate green:

- `(type N = Int)` lost its `=`;
- a `trait` lost its `where`, its supertrait parentheses and its method
  `::`, and emitted per-method parentheses the parser does not accept;
- an `impl` lost its `where`;
- a type application lost its grouping, so `(Node (Tree a) a (Tree a))`
  became a **five**-field constructor and `(-> (Tree Int) Int)` became a
  two-argument function.

That last one is the instructive case. It still parses — it is
well-formed source that means something else — so neither `fmt`'s own
round-trip verification nor a re-parse can see it. Only type-checking the
output catches it.

Two changes. `tests/fmt/syntax-zoo.ax` carries every declaration and
expression form the parser accepts, so the gate no longer depends on what
the standard library happens to need; and `check-fmt.sh` now
*type-checks* the formatted zoo rather than only re-parsing it. Verified
to fail when the regrouping bug is reintroduced.

The zoo immediately found the same blind spot in the editor grammar:
`tree-sitter-axiom` described a `trait` syntax the compiler does not
implement — methods individually parenthesised, `where` introducing a
default body inside one — so it accepted no real trait at all. Fixed and
now at 74/74 files.

### 2.4e The parser could hang

Found while probing malformed trait declarations. Four hand-written
effect-list loops shared a shape:

```rust
while !self.check(RParen) && !self.at_eof() {
    if self.check(IO) { … } else if self.is_ident() { … }
    // no final `else` - and no advance
}
```

A token that was neither a known effect, an identifier, nor `)` left the
position unchanged, and the loop spun forever. `(trait (S a) (x) ((-> a Int)))`
hung the compiler: no diagnostic, no crash, no output. That breaks the
rule the project holds everywhere else — a malformed input produces a
diagnostic, not a hang — and it is the worst failure mode of the three,
because there is nothing to report and nothing to attach a span to.

All four are now one `parse_effect_list` that either consumes a token or
returns `AX2001` with a span. A twelve-case malformed-input sweep over
the other parenthesised loops found no further hangs.

### 2.4f `cond` was implemented everywhere except where it mattered

A feature can be absent while most of its code is present. `cond` had a
lexer token with the syntax written out beside it, an `Expr::ECond` node
in the AST, type-checking in `axiom-sema`, effect walking, and a
formatter case. Two stages were missing, at opposite ends of the
pipeline:

- the **parser** had no `cond` case, so the word was reserved and could
  never be written — and every other stage's handling of it was
  unreachable code;
- the **IR generator** had no `ECond` arm either, so once the parser did
  produce one it fell through to the catch-all and the whole form
  evaluated to `0` whichever clause matched.

Both are now present. `cond` lowers to a chain of `if`, which is where
its tail-call behaviour comes from: `if` already detects a self tail call
in either branch, so `cond` inherits it rather than needing its own
analysis — three million iterations in constant stack, tested. A `cond`
with no `else` falls through to `0`, matching `while`, which also has no
last value to report. `else` is deliberately *not* a token: it lexes as
an ordinary identifier and is recognised by name inside `cond`, so it
stays usable as a variable everywhere else.

Covered by `tests/stdlib/260-cond.ax`, two integration tests, and an
entry in the syntax zoo.

The lesson is worth separating from the bug: **grep for a feature's name
across the crates and count the stages that mention it.** `cond`
appeared in five of seven. The two that did not were the two that make
it run.

### 2.4g Float-ness of a struct field, when two structs disagree

`EField` gives a field's *name* but not the struct it belongs to, and the
type checker is gone by the time the IR generator needs to know whether
`.v` is a float. Float-ness was therefore keyed on the field name alone,
so two structs declaring `v` — one `Float`, one `Int` — collided.

It now resolves towards integer unless *every* struct declaring that name
declares it float. The direction matters: resolving towards float emits
`fadd` for an integer field, silently computing nonsense from the bits;
resolving towards integer costs a float field its arithmetic only in a
program with two same-named fields of different kinds, and that surfaces
as a type error rather than a wrong answer. Pinned by an integration
test.

### 2.5 CI was not green, and could not have been

The claim in §2.1 that CI was green on all four targets did not hold when
re-checked, for two reasons that were each enough on their own.

**The `lint` job failed on eleven clippy warnings.** It runs
`cargo clippy --all-targets --all-features -- -D warnings`, and eleven
warnings were present on a clean checkout. Every other job declares
`needs: lint`, so the entire pipeline was blocked behind it — no test job,
no matrix, no cross-target check ever ran. All eleven are now fixed.

**The `test` matrix ran a script that does not exist.** The final step
invoked `scripts/check-game-of-life.sh`, which was removed in 720a0d5
along with the sample it ran; the step referencing it was not. Every run
of that job would have failed on a missing file — on all three matrix
platforms.

Two gates were also present in the tree and wired into nothing:
`check-self-host.sh`, the only gate that exercises stage1 end to end, and
`check-bootstrap.sh`, which checks the `stage2 == stage3` fixpoint that
the whole self-hosting effort is aimed at. Both now run in CI. Both pass;
the fixpoint is reached.

This is the same failure the risk table already names — a gate that
cannot fail, or does not run, reports success without checking anything —
appearing in the workflow file rather than in a script.

---

## 3. CI: the two failures, root-caused

Both were real, and both are worth recording because each was invisible in
the configuration where development happens.

**`llc: command not found` on darwin-aarch64.** The workflow ran
`echo "$(brew --prefix llvm)/bin" >> "$GITHUB_PATH"`. `brew --prefix
<formula>` prints the path a formula *would* occupy and exits zero when it
is absent, so the step succeeded while appending a non-existent directory,
and the failure surfaced one step later with no connection to its cause.
Fixed by installing before resolving the prefix.

**PIE link failure on linux-x86_64.** Four tests failed with
`relocation R_X86_64_32S against '.bss' can not be used when making a PIE
object`. `llc`'s default relocation model for ELF is `static`; every
current Linux distribution links PIE by default; and Axiom always has a
`.bss` global, the bump allocator's `@__axiom_bump` cursor.

Two things hid it. At `-O2` the x86 backend picks PC-relative addressing
anyway, so only `-O0` fails — and `axiom run` previously used the `-O0` path.
Darwin is position-independent unconditionally, so it cannot be reproduced
on macOS at all. Measured directly:

```
llc adt.ll -relocation-model=static -O0  →  5× R_X86_64_32S
llc adt.ll -relocation-model=pic    -O0  →  0× R_X86_64_32S
```

Fixed by passing `-relocation-model=pic` explicitly. Emitting a
`!"PIC Level"` module flag instead does *not* work — `llc` ignores it,
which was also measured — so every `llc` invocation in the project must
carry the option.

The gate that should have caught this now does:
`check-cross-targets.sh` assembles at `-O0` as well as `-O2`, and inspects
relocations rather than trusting `llc`'s exit status. Previously it
assembled only at the default `-O2` and only checked for a clean exit,
which is precisely why a linker-level bug passed a codegen gate.

---

## 4. Designs

Sketches at the level of detail needed to start, with the decisions that
have to be made called out as decisions rather than buried.

### 4.1 Memory model — arena inference with deterministic drop

**Requirements.** Compile-time arenas; type-checked lifetimes;
deterministic drop; no GC; no manual `free`; works with linear types,
lambdas, lists, tuples, and ADTs; supports self-hosting.

**The shape.** Every allocation belongs to an arena. Arenas are inferred
from where a value is created and how far it escapes — never written. That
inference is the reason `region` was deleted from the surface syntax: an
annotation the compiler can derive is an annotation that will be wrong.

1. **Per-activation arenas.** Each function body has an implicit arena. A
   value allocated in it and not escaping is reclaimed when the body
   returns, by rewinding a watermark. O(1) per activation, no per-object
   bookkeeping.
2. **Escape promotion.** A value that is returned, stored into a
   longer-lived structure, or captured by an escaping closure is allocated
   in the caller's arena instead. This is Tofte–Talpin region inference
   with the annotations removed.
3. **Linearity as the precision mechanism.** Inference alone cannot always
   decide. A linear value has exactly one owner, so its arena is its
   owner's arena, and `consume` is a deterministic drop point. This is what
   `linear`/`consume` were always for and why they are currently
   parsed-but-unused.

**The hard part, stated precisely.** Per-activation arenas do not help a
tail-recursive loop, and a tail-recursive loop is the case that matters
(§2.2). In `(advance (step board) (- n 1))` the activation never returns,
so a watermark is never rewound and the measurement stays linear. Fixing
it requires resetting the arena to the entry watermark at the tail call,
which is sound only if the new argument does not point into the memory
being reclaimed — a no-alias obligation on `step : Board -> Board`.

Three ways to discharge it, in increasing order of ambition:

| Approach | Discharges the obligation by | Cost |
|---|---|---|
| Copy at the boundary | copying the new argument down to the watermark | O(live) per iteration, always sound, simple |
| Linear consumption | requiring the loop parameter be linear, so the old value is provably dead | needs linear types finished; changes signatures |
| Full region inference | computing region-annotated types for the whole program | most precise, most research risk |

**Recommendation:** implement the first, because it is sound, simple, and
turns the §2.2 number from linear into constant, and it establishes the
watermark machinery the other two need. Then the second, since linear
types are already in the surface syntax. Treat the third as optional.



**What this does not do.** Nothing here reclaims a cycle, and nothing here
reclaims a value whose lifetime genuinely outlives every arena. Both are
accepted: Axiom's data is immutable and inductive, so cycles are not
constructible, and a value that outlives all arenas is a value that lives
until process exit — which is the correct answer for a compiler process.

### 4.2 Macro system — pattern-based, hygienic, no compile-time evaluation

**The tier decision, made explicitly.** There are two designs available,
and they differ in a security property this project has already committed
to.

- **Tier 1, pattern-based** (`syntax-rules`-shaped): a macro is a set of
  pattern/template pairs. Expansion is a rewrite. The compiler executes no
  user code.
- **Tier 2, procedural**: a macro is an Axiom function from syntax to
  syntax, run at compile time. Strictly more expressive, and it requires
  the compiler to execute arbitrary code from a source file — which
  directly contradicts the existing invariant that "the compiler must
  never execute arbitrary code from source files during compilation".

**Recommendation: tier 1 for v1.** Axiom is an S-expression language, so
pattern matching on syntax is a natural fit and covers the stated use
cases — deriving instances, eliminating the boilerplate that
the current stdlib is full of, and generating
the repetitive parts of a self-hosted compiler. Tier 2 should not be
smuggled in as an implementation detail of tier 1; it is a change to the
compiler's threat model and needs a sandbox and an explicit decision.

**Hygiene.** The mechanism is scope sets: an identifier becomes a
`(name, scopes)` pair rather than a bare name, every macro expansion
introduces a fresh scope, and resolution matches on both. Free identifiers
in a template resolve at the macro's *definition* site; binders introduced
by a template are renamed. Concretely this means adding a scope field to
`Ident` in `axiom-ast/src/span.rs` and teaching name resolution in
`axiom-sema` to compare scope sets. That is the first commit, and it is
independently testable before any macro exists.

**Type-checked output is free; good diagnostics are not.** Expansion runs
before semantic analysis, so expanded code is type-checked like any other
code. The problem is that a type error in expanded code points *inside the
macro*, at source the author never wrote. `Diagnostic` needs an expansion
backtrace — the chain of macro invocations a span passed through — and the
AXDL renderer needs a field for it. Without this, macros make the
diagnostic quality worse, and diagnostic quality is this project's
distinguishing feature.

**Acceptance criteria.**
- A `derive`-style macro generates a working `Eq` instance for a `data`
  type, with exhaustiveness still checked on the generated `match`.
- A macro that introduces a binding named `x` does not capture a
  user's `x`, and the reverse (the classic `swap!`/`or` hygiene tests).
- A type error inside an expansion reports the macro *and* the invocation
  site, both with real spans.
- Macros work over `data`, `struct`, lambdas, lists, and tuples — one
  corpus case each.

### 4.3 ADT revision — smaller than it sounds

Axiom already has Rust-style ADTs: tagged sums, recursive types, nested
constructor patterns, and compile-time exhaustiveness checking. That is
verified. The actual gap against Rust is
narrow:

1. **Struct variants. (DONE)** `(data Shape (Circle { r : Int })
   (Rect { w : Int, h : Int }))` declares named fields per variant.
   They are accessible by name (`s.r`) and matchable by name
   (`((Rect { w = w, h = h }) ...)`), independent of declaration order,
   and an arm may name a subset of the fields rather than supplying a
   placeholder for each one it ignores. Covered by
   `tests/stdlib/210-struct-variants.ax`, which checks the named and
   positional spellings agree on every constructor and that a reversed
   named pattern binds by name rather than by position.
2. **Nullary constructors should not allocate** (`S1`). **(DONE)**
   `(Nil)`, `(None)` and every other fieldless constructor is an
   immediate tag, in mixed types too; only constructors with fields
   allocate.
3. **Field punning in patterns. (DONE)** `{ w, h }` is `{ w = w, h = h }`.
   Mixes freely with explicit binding, and named patterns nest.

What remains of this item is *named construction* — `(Rect { w = 3, h = 4 })`
as an alternative to the positional `(Rect 3 4)`. Values are still built
positionally, in declaration order. This is the one place the type's
field names are not yet honoured, and it is the smaller half: a
constructor call is written once per value, whereas a pattern is written
once per use site, which is why matching was done first.

Item 2 landed ahead of the memory model: the representation change
needed nothing from the allocator, only a runtime immediate-vs-pointer
guard at match sites over mixed types.

### 4.4 Concurrency — delegated to third-party libraries

Concurrency is not a native feature of Axiom. The design below is preserved
as guidance for a future third-party library, but the compiler and standard
library will not ship with native concurrency primitives, a task scheduler,
or constructors like `parMap`.

**Rationale.** Axiom's memory model (arena inference, linear types) already
prevents data races by construction — no mutable aliasing is constructible.
A library author can build a safe, structured concurrency library on top of
this foundation without language-level support. Bundling concurrency into
the language would couple Axiom's release cadence to concurrency design
decisions that are better made independently, and would add surface area to
the compiler for a feature used by a subset of programs.

**Design guidance (for a third-party library).**

- Structured concurrency with no shared mutable state.
- Each task gets its own arena, reclaimed at join.
- Values handed to a task are copied or moved (linear types make moves safe).
- Results are moved into the parent arena at join.
- Determinism: results combined in argument order (`parMap`), independent of
  completion order. Scheduling may be nondeterministic; observable behaviour
  is not.
- Driving use case: parallel compilation (independent modules type-check in
  independent arenas with no shared state).

### 4.5 HTTP library — deferred on purpose

Small, resilient, non-blocking, pure Axiom. It needs, in order: `Vec` and
`Map` (`B3`) for headers and routing; an event loop (implementable in user
space with existing syscall primitives — native concurrency is not
required); and non-blocking syscalls, which are new `Sys` surface
(`epoll`/`kqueue`) with a per-platform module — the pattern
`stdlib/Sys/Platform.*.ax` already establishes.

Written before those, it is a blocking library with a socket API, which is
not the deliverable.

### 4.6 LSP — after self-hosting, not before

Requires `B1` (closures, for handler tables), `B3` (maps, for the symbol
index and incremental cache), and `B4` (namespacing, for a program of that
size). It should reuse the self-hosted frontend rather than reimplement
parsing, which is the whole architectural argument of rust-analyzer and
the reason self-hosting comes first.

The [tree-sitter grammar](../tree-sitter-axiom/) already covers the part of
the editor experience that does not need semantic analysis — highlighting
and structural selection — so this ordering costs users less than it
appears to.

---

## 5. Phases

Each phase lists its exit criterion. Within a phase, items are genuinely
parallel.

| Phase | Items | Exit criterion |
|---|---|---|
| **P0** *(done)* | Green CI; `union`/`region` removed; tree-sitter grammar | All seven gates green on all four targets |
| **P1** *(done)* | `B2` tail calls · `B3` `Vec`/`Map`/`Intern` golden tests and scale validation · `B1` closures · ADT struct variants | 10⁷-iteration loop at `-O0` ✓; higher-order probe runs ✓; struct variants match exhaustively, by name and punned ✓; `Map` within 2× of Rust ✓ (1.80×, was 14× — an affine-hash bug, not the allocator; see §2.4 B3) |
| **P2** | Memory model (§4.1) · ~~`S1` unboxed nullary constructors~~ **(DONE)** · ~~`Map` throughput~~ **(DONE, 1.80×)** | ~~`Map` insert at 10⁶ within 2× of Rust~~ ✓ met — and not by allocator work: the cost was an affine hash, corrected in B3. What remains of P2 is §4.1's actual subject, deterministic reclamation for long-running programs (the LSP, the HTTP server); the single-shot compiler process no longer has a P2-blocking measurement |
| **P3** | Macro system (§4.2) — hygiene done · ~~`B4` namespacing~~ **(DONE)** | Hygiene test passes; two modules define the same name without collision. A bare reference *inside* a module now binds to that module's own definition first, in both compilers: before it, an entry file defining `helper` silently redirected an imported module's own call to its own `helper` — importing a module changed what that module did, with no diagnostic from either side (`tests/selfhost/850-module-local-binding.ax`). Resolution outward from a module is still the merged declaration list rather than that module's import set, which is the remaining half of the flat-namespace decision |
| **P4** | Self-hosting phases 2–5 · HTTP library (§4.5) | `stage2 == stage3` ✓; HTTP server serves a request under load. Phase 3 (semantic analysis in Axiom) has begun and meets its criterion for the checks that exist: stage1 emits **byte-identical AXDL** for **all seventeen** `AX30xx` codes, gated three-way against a checked-in golden by `scripts/check-diagnostics.sh` (36 cases). Type checking proper is done — `parseSigDecl` keeps type structure, and `AX3004`/`AX3005`/`AX3007`/`AX3008` compare types exactly where stage0 does, with no unifier. Effect inference is a monotone fixpoint over the call graph with effect-transparent parameter marks, so its sets match stage0's. Imported modules are checked too, each rendered against its own filename. Phase 3's exit criterion is met; grouping is a no-op on both sides, since no producer in stage0 ever sets a group key. Phase 4 re-measured (2026-08-07): 0 of 71 comparable `.ll` pairs are byte-identical, and the raw-versus-post-`mem2reg` question the criterion was waiting on is now answered — normalising does not help (46 diff lines becomes 50 on the simplest program). What survives is stage1's calling convention, block structure and register naming, all three deliberate; the arithmetic already matches. So the criterion asked stage1 to adopt the retiring compiler's design choices rather than to converge on lowering, and **it has been replaced**: phase 4 now exits on behavioural equivalence between the compilers over both corpora at both optimisation levels through an identical toolchain, plus the four-target assembly check and the fixpoint (which still requires byte-identity where it carries meaning, `stage2 == stage3`). Widening the differential gate to carry that criterion found stage0's own output overflowing the stack on `320-effect-gc-roots` through a raw `llc` pipeline where stage1's does not, because stage0's frames carry a hidden closure parameter and spill their bindings — converging stage1's IR onto stage0's would have imported that. It also found the gate **was not in CI at all**, which is the risk this table's last-but-four row names; it runs there now, over 106 cases with a counted floor. Scouting also found that **nothing ran `tests/stdlib/` through stage1**, hiding five miscompiles; `scripts/check-stdlib-selfhost.sh` now gates them, and that gate now has **no skip list at all — 33 of 33 agree**, because the effect system lowers through stage1 too (evidence slots, outward dispatch from a handler performing its own effect, and the unhandled-operation trap). Doing it exposed a scalability ceiling underneath: the lexer's `lexTokens`/`dispatchChar` mutual tail calls cost a stage1-built compiler one frame pair per token, so it died between 96 KB and 146 KB of input where a stage0-built one read 396 KB. Both are loops now; measured past 814 KB |
| **P5** | LSP (§4.6) · ~~trivia preservation for `fmt`~~ **(DONE, §2.3)** · benchmarking · docs | Completion and diagnostics in a real editor; ~~`fmt` round-trips every file in the repo, gated in CI~~ ✓ 70/70, gated by `check-fmt.sh`; published performance profile |

**On effort.** P1 is weeks. P2 is the research risk and could be a month
or several depending on which option in §4.1 proves sufficient. P3–P5 are
each larger than everything before them combined; the LSP alone is
comparable in size to the current compiler. Any plan that shows these
completing together is not a plan.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| The memory model is attempted at full generality and stalls | Ship the copy-at-boundary option first; it is sound and turns the §2.2 number constant. Treat region inference as optional |
| Procedural macros arrive as an implementation detail and silently make the compiler an arbitrary-code executor | Tier 1 only; tier 2 requires an explicit, documented decision and a sandbox |
| Macros degrade diagnostics | Expansion backtrace in `Diagnostic` is part of the macro work, not a follow-up |
| The LSP is started early "in parallel" and blocks on missing language features | The dependency edges in §1 are the schedule; the tree-sitter grammar covers editor basics meanwhile |
| A gate passes while the property it protects is broken — as happened for PIE relocations | Every new gate gets a negative test proving it fails when it should. Done for the relocation and grammar gates |
| A tool with no CI gate is silently broken, as `fmt` was | Either gate it or make it fail loudly. `fmt` now verifies its own output before writing and is gated by `check-fmt.sh`, which checks behaviour — it formats a copy of the repo and re-runs the suites — because the worst of its six bugs produced a program that parsed, compiled and ran, and returned the wrong answer. The prediction held for the other two surfaces this row used to name: `repl` could not evaluate a single expression (§2.4), `explain` was sound. Both are now covered by tests that drive the real binary |
| An interactive tool is left untested *because* it is interactive | The REPL went unchecked on exactly that reasoning and was completely broken. It is line-oriented, so driving it over a pipe is all a test needs; `run_repl` in `axiom-cli/tests/integration.rs` is six lines |
| A step in the workflow file refers to a script that no longer exists, so a job fails for a reason unrelated to the code | Gates are scripts in `scripts/`, and CI steps only invoke them. The `Game of Life` step outlived its script by one commit and failed every matrix run until it was noticed here (§2.5) |
| A lint job that gates every other job fails, so nothing downstream ever runs | `needs: lint` means a clippy warning stops the whole pipeline. Keep `cargo clippy -- -D warnings` clean; eleven warnings had accumulated and blocked CI entirely (§2.5) |
| A gate that *skips* when its tool is missing is the same failure wearing a different hat | `check-tree-sitter.sh` exited 0 when the tree-sitter CLI was absent — which is every machine that has not run its `npm install` — so it reported success without checking anything. It hid two live breakages: the grammar rejected every `struct` with fields, and so most of `self_host/`, taking the corpus from a claimed 18/18 to an actual 27/70; and the highlight-query step named `game_of_life/Life.ax`, deleted in 720a0d5. Both fixed, and the gate now fails rather than skips unless `AXIOM_TREE_SITTER_OPTIONAL=1` is set |
| Removing `union`/`region` breaks unknown external code | Both stay reserved and report `AX2004` with the replacement, rather than being silently reinterpreted |
