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

`scripts/check-fuzz.sh` holds every mutant to five properties:

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
  `llc -O0` accepts, or one `emit-llvm` refuses with `AX4008` alone,
  counted apart. IR with no `@__axiom_user_main` gets a stub first,
  because `emit-llvm` doesn't require `main`.
- **P4**, a program `check` accepts is one `axiom fmt` rewrites, or
  refuses with a code. The rewrite must be a fixed point, so formatting
  it again changes nothing, and it must still check.
- **P5**, a program `check` accepts prints the same output and exits
  with the same status built at `--opt 0` and at `--opt 2`. This runs
  on a sample: mutants of `tests/stdlib` and `tests/selfhost` programs
  with a `main`, at most 20,000 bytes, naming nothing that reaches out
  of the process (threads, processes, files, sockets, the clock or
  FFI). Each runs in a scratch directory with no input, for at most
  5 s and 1 MiB of output. A run cut short, or an `--opt 0` binary
  that answers differently twice, is inconclusive and counted apart.

The default budget is 600 mutants from seed 20260927, with P5 on at
most 30 of them. `--long` runs 6,000, with P5 on at most 300, nightly
in CI. The gate has six sections:

1. The generator: its selftest, including a pinned digest of 200
   mutants of an in-memory corpus, so cross-host determinism is
   checked on every CI leg. The run's mutants are also generated twice
   under two hash seeds and compared byte for byte.
2. The run, then P4 and P5 over the mutants it accepted.
3. Stage floors: every stage reached at least once, every mutant run,
   and under 1% identical to their source.
4. The controls. A planted wrapper compiler's SIGSEGV, hang, silent
   exit 1, exit 77, real refusal re-answered as exit 0, malformed JSON
   and non-IR line must each be reported as that failure, not excused.
   So must a formatted copy that no longer checks, and an `--opt 2`
   binary that prints one line more. An untouched mutant through the
   same wrapper must still pass P1 to P4.
5. The stored reproducers.
6. A tally of what the open rows excused.

Reach on the default run over the 764-file corpus: of 600 mutants,
274 (46%) got past the reader and 82 (14%) checked OK. Of those, 81
emitted and were llc-clean, and one was a bare-metal program refused
at emit by `AX4008`. The other 518 were refused with a code, all with
well-formed JSON. None hit an open row.

The corpus is `git ls-files`, so a new file moves the mutants. On the
734-file corpus the same counts were 280, 81, 81, 519 and 507. A
fuzzer of this kind mostly tests the reader's and the checker's
refusal paths. About a sixth of its budget reaches code generation.

### Findings

These came from 10,600 mutants: seed 1 ×1,000 and seed 2 ×3,000 while
the harness was built, then seed 20260927 ×600 and ×6,000 through the
gate. P4 and P5 found the last two on the default run. Each is minimised in `tests/fuzz/` and listed in its `MANIFEST`,
and the gate replays every one.

| Reproducer | What | Status |
|---|---|---|
| `render-spanless-cross.axfuzz` | `check` SIGSEGV (exit 139) in the human renderer. A user `fn` spelled `*` whose body allocates fails every stdlib `no-alloc` claim that multiplies, with a restriction path whose last hop has no span. `secNoteText` asked `diagSecCross` before the span and handed `fmtSpanIx` a null one. The AXDL and JSON renderers already asked the span first. | **fixed** (`self_host/render.ax`); now refused with its codes |
| `region-nonarrow-sig.axfuzz` | `check` SIGSEGV in the region pass. A signature that is not an arrow (`(:: wrapBox ())`) over a function with a parameter, called inside a `region`: `rgnKnownCall` asked `rgTyScalar` about `nthParamTy`'s fallback 0, a null type. | **fixed** (`self_host/typecheck.ax`: no type answers "not scalar", the safe direction the function already took for a type variable); now AX3004 |
| `dup-param-llc.axfuzz` | `(fn (f x x) x)` checked OK and emitted a `define` with `%x` twice, which `llc` refuses. | **fixed** (`checkDupParams`); now AX3006 |
| `builtin-name-value.axfuzz` | `cast`, `sizeof`, `alignof`, `handle` and the effect names checked OK as values and lowered to an SSA name nothing defines. | **fixed**; now AX3001 and AX3013 |
| `cast-missing-operand.axfuzz` | `(cast T)` with no operand checked OK and lowered the type name as a variable (`%Int`). | **fixed** (`checkCastForm`); now AX3013 |
| `primitive-value.axfuzz` | Thirteen one-argument primitives applied to nothing, such as `(__alloc)`, checked OK and lowered to an SSA name nothing defines. | **fixed** (`checkBareValue`); now AX3013 |
| `json-ax1001-partial-char.axfuzz`, `json-restrict-illformed.axfuzz` | `--diagnostic-format json` wrote ill-formed UTF-8: AX1001 quoted one byte of a multi-byte character, and AX3052 quoted a restriction tag's bytes verbatim. | **fixed**: the lexer's error token covers the whole character, and every renderer writes a byte that isn't UTF-8 as U+FFFD |
| `pub-twice.axfuzz` | P4: `(pub pub :: f Int)` checked OK, because the parser skipped a second `pub`, and `fmt`, which has its own grammar, refused the file with no code. `pub` inside an expression was skipped the same way. | **fixed** (`self_host/parser.ax`); now AX2001 |
| `match-arms-disagree.axfuzz` | P5: a `match` answered its last arm's type and compared no arm with another. A `String` arm in a function declared `Int` checked OK, and the program answered from the string's address: 208 at `--opt 0` and 176 at `--opt 2`. | **fixed** (`armJoin` in `self_host/typecheck.ax`): the arms are held to the first arm with a known type, as `if` holds its branches; now AX3004 |

No row is open. An open row would carry a signature, an extended regex
over the failing tool's own words matched at the row's stage: a mutant
failing that way prints as `XFAIL` and isn't counted red, and the row
itself must keep failing exactly so, or the gate goes red. A fixed row
is replayed as a regression on every run.

These were measured but aren't crashes, and aren't stored as
reproducers:

- **Compile time grows faster than quadratically in one `let`'s
  bindings.** `emit-llvm` on `(let ((v 333) ...) v)` takes 0.85 s for
  4,000 bindings, 4.7 s for 8,000 and 24.2 s for 16,000 (`check`:
  3.6 s). A 20,000-binding mutant didn't finish in 60 s. Blocks of
  32,000 statements emit in 0.45 s. The `long` edit is capped at 5,000,
  so the gate's deadline measures hangs and not this.
- **`llc -O0` is superlinear in one function's basic blocks.** A
  `println` branch repeated in an `if` chain takes 4 s of `llc` at
  1,000 branches (5.7 MB of IR) and 49 s at 2,000. A `--long` mutant
  that repeated one 4,878 times (180,538 blocks, 60 MB of IR) was still
  in `llc` after ten minutes. The `long` edit now also stops at
  100,000 bytes, where it stopped at 1,000,000.
- **`AX4008` is decided at emit, not at check.** A bare-metal program
  such as `tests/embedded/periodic.ax` checks OK and is refused for the
  host, because the refusal reads the module after unreachable
  functions are pruned. P3 counts such a mutant apart, as refused at
  emit, and not as a failure.
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

Green means these mutants, at this seed, on this host, met P1–P5. It
is evidence about the neighbourhood of the corpus, not about the
language. `scripts/check-fuzz.sh` won't find a crash that needs a
construct no corpus file comes near, and nothing guides the search
toward uncovered code (there is no coverage feedback).

P3 is `llc` accepting the IR, not the IR computing the right answer.
P5 compares two optimisation levels of one compiler on a sample, so it
sees a miscompilation only where they disagree. One that both levels
share, such as a wrong lowering in the emitter, is invisible, and so is
any program outside the sample.

Not fuzzed at all: the runtime, the LSP, the REPL, non-host
`--target`s and the command line. `fmt` is held only to P4, on
programs `check` accepts, and `build` and execution only on P5's
sample.
The default budget is 600 mutants a CI leg. The 6,000-mutant `--long`
budget runs nightly, in CI's `long-evidence` job.

## What is still open

- Coverage-guided fuzzing, and fuzzing of the LSP and the REPL. A
  miscompilation oracle beyond P5's two optimisation levels, such as a
  reference interpreter.
- Fuzzing of FFI boundaries and runtime operations. Sanitizers and
  race detectors. Schedule exploration, and memory-ordering litmus
  families beyond the six `scripts/check-atomics.sh` runs (SB, MP,
  LB, 2+2W, IRIW and a contended counter, R-C3). Allocation,
  cancellation and failure injection beyond the fault-injected count
  boundary (527) and the `reset_keeping` fixtures (165).
- Long-duration memory and concurrency stress. Inspection of optimised
  IR and machine code for critical lowering beyond the atomics.
  `check-atomics.sh` counts theirs at all four levels. The model
  assembles at one level per trace, not all four with diffing.
- Differential and metamorphic compiler tests beyond the bootstrap
  fixpoint (`stage2 == stage3`) and the MIR differential.
