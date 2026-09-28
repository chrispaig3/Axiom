# Verification programme (R-E1)

This page covers what the executable model checks, what the compiler
fuzzer checks, how each gate runs, what they found, and what neither
covers. It goes with R-E1 in [requirements.md](requirements.md). The
scope statements of record are two docstrings:
`scripts/lib/runtime-model.py` for the model and `scripts/lib/fuzz.py`
for the fuzzer.

## The model

`scripts/lib/runtime-model.py` is a second, independent statement of
what the runtime does to the bump pointer, the per-class free lists
and the 16-byte block header. It covers `axiom_alloc`, `axiom_retain`,
`axiom_release`, the arena mark/reset functions and the
`(region r ...)` form. It is written from
[memory-model.md](../memory-model.md) (MM-ALLOC-3/6/7a/8b/12/14,
MM-LIFE-2b/2d/2e/2k/2l, MM-RGN-1/2/6), not transliterated from the IR.

The model knows offsets, counts, payload words and a LIFO list per
size class, and nothing about registers or chunks. Seven invariants
(I1–I7 in the docstring) are asserted after every transition. A
generator that drives the model into an invalid state therefore stops
in the model, instead of showing up as a confusing runtime diff.

Scope: one thread, one chunk, `__alloc` leaf blocks, raw count
adoption, valid marks and lexical regions. It also forges counts
through a header store to reach the exhaustion boundary without 2^63
retains.

The docstring states the non-scope at length: graph destruction,
cycles, chunk refill, `reset_keeping`, recovery, FFI, all concurrency,
statics, invalid marks, arbitrary words as handles, hardware faults,
and every compiler-emitted retain/release.

## The model's gate

`scripts/check-runtime-model.sh` runs 13 checks. `--long` widens the
seeds and levels.

1. The model alone: 200 random traces (2,000 under `--long`), with
   every invariant checked after every step. This shows the generator
   is valid. It says nothing about the runtime.
2. Every trace at `--opt 0` and `--opt 3` (all four under `--long`),
   compiled by the compiler under test. There are 10 traces: six fixed
   witnesses (`dead`, `reset`, `scrub`, `region`, `boundary`,
   `exhaust`), three seeded random walks, and the canary. Each must
   print `0 0` and exit as expected. A terminal trace (`exhaust`) must
   instead give the trap's 70 and its sentence.
3. The canary: a trace with a planted error in its model, at exactly
   one check, must report that check and exactly one failure. Without it, "every check
   passed" could mean "no check can fail".
4. The hand pipeline's control: each witness's IR is emitted by the
   compiler under test and assembled by the script through the
   driver's own `opt`/`llc`/`cc` steps, and must still pass. So the
   section 5 reds come from what the mutation changed, and not from a
   difference between the hand pipeline and the driver's.
5. Five mutation witnesses. Each rewrites one rule in the emitted
   runtime and must turn its trace red at a named check:
   `dead` (MM-LIFE-2k), `reset` (MM-LIFE-2e slab scrub), `scrub`
   (MM-ALLOC-6 handout wipe), `region` (MM-RGN-1 exit reset),
   `exhaust` (MM-LIFE-2l: without the trap the retain returns).
6. The exhaustion boundary, as a terminal trace in section 2.

A green run means agreement on the traces run, at the levels run, on
the host it ran on. The model is not a proof of the runtime, and the
runtime passing is not a proof of the model.

## Compiler-input fuzzing

`scripts/lib/fuzz.py` makes mutants of the tracked `.ax` corpus (734
files) from a seed. It uses its own splitmix64, so no interpreter or
host can move the stream. Mutant *I* is drawn from a stream of its
own, so `--only I` regenerates exactly the mutant a run reported.

A small reader finds balanced forms, atoms and literals. Each mutant
is one to three of these edits:

- delete, duplicate or swap a form;
- replace an atom, or a form's head, with one from another corpus
  file;
- splice in a form from another file;
- push an integer literal to a 64-bit edge;
- drop or insert a delimiter;
- truncate;
- insert NUL, control, non-ASCII or ill-formed UTF-8 bytes;
- edit a string or char literal;
- empty or wrap a form;
- nest a form around the parser's 1,024 limit;
- repeat a form's last child up to 5,000 times.

`scripts/check-fuzz.sh` holds every mutant to three properties:

- **P1**, `axiom check` answers: exit 0 with no `error[AXnnnn]` line,
  or exit 1 with one. A signal, a trap status, a refusal with no code,
  an error printed under exit 0, or no answer within 120 seconds is a
  failure.
- **P2**, a refusal's `--diagnostic-format json` output exits the same
  and is well-formed JSON Lines. `json_ok` in `fuzz.py` states the
  contract that `docs/diagnostics.md` and `renderDiagJson` give,
  including the optional `span`/`label`, the related entries and the
  trailer line.
- **P3**, a program `check` accepts is one `emit-llvm` compiles and
  `llc -O0` accepts. IR with no `@__axiom_user_main` gets a stub
  first, because `emit-llvm` doesn't require `main`.

The default budget is 600 mutants from seed 20260927 (32 s on H3).
`--long` runs 6,000 (484 s). The gate has six sections:

1. The generator: its selftest, including a pinned digest of 200
   mutants of an in-memory corpus, so cross-host determinism is
   checked on every CI leg. The run's mutants are also generated twice
   under two hash seeds and compared byte for byte.
2. The run.
3. Stage floors: every stage reached at least once, every mutant run,
   and under 1% identical to their source.
4. The controls. A planted wrapper compiler's SIGSEGV, hang, silent
   exit 1, exit 77, real refusal re-answered as exit 0, malformed JSON
   and non-IR line must each be reported as that failure, not excused.
   An untouched mutant through the same wrapper must still pass.
5. The stored reproducers.
6. A tally of what the open rows excused.

Reach on the default run over the 734-file corpus: of 600 mutants,
280 (47%) got past the reader and 81 (14%) checked OK. All 81 emitted
and were llc-clean. The other 519 were refused with a code, and 507 of
those had well-formed JSON. Twelve hit open rows as `XFAIL`.

The corpus is `git ls-files`, so a new file moves the mutants. On the
731-file corpus the same counts were 291, 83, 82, 517 and 504. A
fuzzer of this kind mostly tests the reader's and the checker's
refusal paths. About a sixth of its budget reaches code generation.

### Findings

These came from 10,600 mutants: seed 1 ×1,000 and seed 2 ×3,000 while
the harness was built, then seed 20260927 ×600 and ×6,000 through the
gate. Each is minimised in `tests/fuzz/` and listed in its `MANIFEST`,
and the gate replays every one.

| Reproducer | What | Status |
|---|---|---|
| `render-spanless-cross.axfuzz` | `check` SIGSEGV (exit 139) in the human renderer. A user `fn` spelled `*` whose body allocates fails every stdlib `no-alloc` claim that multiplies, with a restriction path whose last hop has no span. `secNoteText` asked `diagSecCross` before the span and handed `fmtSpanIx` a null one. The AXDL and JSON renderers already asked the span first. | **fixed** (`self_host/render.ax`); now refused with its codes |
| `region-nonarrow-sig.axfuzz` | `check` SIGSEGV in the region pass. A signature that is not an arrow (`(:: wrapBox ())`) over a function with a parameter, called inside a `region`: `rgnKnownCall` asked `rgTyScalar` about `nthParamTy`'s fallback 0, a null type. | **fixed** (`self_host/typecheck.ax`: no type answers "not scalar", the safe direction the function already took for a type variable); now AX3004 |
| `dup-param-llc.axfuzz` | `(fn (f x x) x)` checks OK and emits a `define` with `%x` twice, which `llc` refuses. `build` would fail at the toolchain with exit 4. No refusal exists (AX3020 is for macros). | open |
| `builtin-name-value.axfuzz` | `cast`, `sizeof`, `alignof`, `handle`, `IO`, `Pure`, `Alloc`, `Mut` and `Div` check OK as values and lower to an SSA name nothing defines. `isBuiltinName` admits them because a `handle` list parses as an application. The other twenty names in that list are refused there. | open |
| `cast-missing-operand.axfuzz` | `(cast T)` with no operand checks OK and lowers the type name as a variable (`%Int`, `%Bool`, a user `%Foo`). AX3069 refuses a surplus operand, nothing refuses a missing one, and `isCastLike` exempts `cast` from the saturation check. | open |
| `primitive-value.axfuzz` | Thirteen one-argument primitives applied to nothing, such as `(__floatToInt)`, `(__alloc)` and `(__atomic_load)`, check OK and lower to an SSA name nothing defines: a primitive has no function symbol to take the address of. Every primitive of two or more arguments is refused (AX3013). | open |
| `json-ax1001-partial-char.axfuzz`, `json-restrict-illformed.axfuzz` | `--diagnostic-format json` writes ill-formed UTF-8. AX1001 quotes *one* byte of a multi-byte character, so the human message is broken too. AX3052 quotes a restriction tag's bytes verbatim. `jsonEsc` escapes control bytes but passes ill-formed sequences through. 99 of the 6,000 `--long` mutants hit it. | open |

An open row's signature is an extended regex over the failing tool's
own words, matched at the row's stage. A mutant that fails that way is
printed as `XFAIL` and not counted red. The row itself must keep
failing exactly so, or the gate goes red.

Two signatures are broad by necessity, and say so. `not
UTF-8` excuses any ill-formed JSON, and the `cast` row's `'%[A-Z]...'`
would excuse any undefined capitalised SSA name.

These were measured but aren't crashes, and aren't stored as
reproducers:

- **Compile time grows faster than quadratically in one `let`'s
  bindings.** `emit-llvm` on `(let ((v 333) ...) v)` takes 0.85 s for
  4,000 bindings, 4.7 s for 8,000 and 24.2 s for 16,000 (`check`:
  3.6 s). A 20,000-binding mutant didn't finish in 60 s. Blocks of
  32,000 statements emit in 0.45 s. The `long` edit is capped at 5,000,
  so the gate's deadline measures hangs and not this.
- **`(import main)` from the repository root checks the whole
  compiler.** The resolver keeps `self_host/` and `stdlib/` relative
  to the working directory as a last-resort fallback
  (`moduleSearchDirs`). A mutant that turned `(import Vec)` into
  `(import main)` checked `self_host/main.ax` and its imports. It drew
  46 refusals and took 35 s, but finished. The gate's deadline is
  120 s because of it.
- **An operator-named `fn` is resolved two ways.** With `(fn (* a b)
  (+ a b))` in the entry file, `(* 6 7)` still answers 42, because
  codegen keeps the built-in. The effect walk, though, attributes the
  user function's effects to every stdlib use of `*`
  (`Vec$vecGrownCap -> *`). Nothing says the definition is
  unreachable.
- **A signature that is not an arrow is accepted over a function with
  parameters.** `(:: f ())(fn (f x) x)` and `(:: f (Int))(fn (f x) 0)`
  check OK. Only the calls are refused.

### What a green fuzzing run does not show

Green means these mutants, at this seed, on this host, met P1–P3. It
is evidence about the neighbourhood of the corpus, not about the
language. `scripts/check-fuzz.sh` won't find a crash that needs a
construct no corpus file comes near, and nothing guides the search
toward uncovered code (there is no coverage feedback).

P3 is `llc` accepting the IR, not the IR computing the right answer. A
miscompilation that yields valid IR is invisible.

Not fuzzed at all: `build`/`run` (linking and execution), the runtime,
`fmt`, the LSP, the REPL, non-host `--target`s and the command line.
The default budget is 600 mutants a CI leg, and `--long` isn't wired
to a schedule.

## What is still open

- The six open fuzzing findings above. Each is a row in
  `tests/fuzz/MANIFEST` that the gate holds failing until it is fixed.
- A scheduled `--long` fuzzing run, coverage-guided fuzzing, and
  fuzzing of `build`/`run`, the formatter, the LSP and the REPL. A
  miscompilation oracle (differential execution of accepted mutants).
- Fuzzing of FFI boundaries and runtime operations. Sanitizers and
  race detectors. Schedule exploration, and memory-ordering litmus
  families beyond the three `scripts/check-atomics.sh` runs (SB, MP
  and a contended counter, R-C3). Allocation, cancellation and failure
  injection beyond the fault-injected count boundary (527) and the
  `reset_keeping` fixtures (165).
- Long-duration memory and concurrency stress. Inspection of optimised
  IR and machine code for critical lowering beyond the atomics.
  `check-atomics.sh` counts theirs at all four levels. The model
  assembles at one level per trace, not all four with diffing.
- Differential and metamorphic compiler tests beyond the bootstrap
  fixpoint (`stage2 == stage3`) and the MIR differential.
