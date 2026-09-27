# Verification programme (R-E1, partial)

What the executable model checks, how the gate runs it, and what
neither covers. Companion to [requirements.md](requirements.md)
R-E1 and the model's own docstring
(`scripts/lib/runtime-model.py`, the scope statement of record).

## The model

`scripts/lib/runtime-model.py` is a second, independent statement of
what `axiom_alloc`, `axiom_retain`, `axiom_release`, the arena
mark/reset functions and the `(region r ...)` form do to the bump
pointer, the per-class free lists and the 16-byte block header —
written from [memory-model.md](../memory-model.md)
(MM-ALLOC-3/6/7a/8b/12/14, MM-LIFE-2b/2d/2e/2k/2l, MM-RGN-1/2/6), not
transliterated from the IR. It knows offsets, counts, payload words
and a LIFO list per size class, and nothing about registers or
chunks. Seven invariants (I1–I7 in the docstring) are asserted after
every transition, so a generator that drives the model into an
invalid state stops in the model, not in a confusing runtime diff.

Scope: one thread, one chunk, `__alloc` leaf blocks, raw count
adoption, valid marks and lexical regions, count forging through a
header store to reach the exhaustion boundary without 2^63 retains.
Non-scope is stated at length in the docstring: graph destruction,
cycles, chunk refill, `reset_keeping`, recovery, FFI, all
concurrency, statics, invalid marks, arbitrary words as handles,
hardware faults, and every compiler-emitted retain/release.

## The gate

`scripts/check-runtime-model.sh` (13 checks; `--long` widens seeds
and levels):

1. The model alone: 200 random traces (2,000 under `--long`), every
   invariant after every step. Says the generator is valid; says
   nothing about the runtime.
2. Every trace at `--opt 0` and `--opt 3` (all four under `--long`),
   compiled by the compiler under test: 10 traces — six fixed
   witnesses (`dead`, `reset`, `scrub`, `region`, `boundary`,
   `exhaust`), three seeded random walks, and the canary — stdout
   `0 0` and the expected exit, or the trap's 70 and its sentence
   for a terminal trace (`exhaust`).
3. The canary: a trace whose model is deliberately wrong at ONE
   check must report exactly that check and exactly one failure.
   Without it, "every check passed" could mean "no check can fail".
4. The hand pipeline's control: each witness's IR, emitted by the
   compiler under test and assembled by the script through the
   driver's own `opt`/`llc`/`cc` steps, must still pass — so the
   section-5 reds are red because of what the mutation changed,
   not because the hand pipeline differs from the driver's.
5. Five mutation witnesses, each rewriting ONE rule in the emitted
   runtime and required to turn its trace red at a named check:
   `dead` (MM-LIFE-2k), `reset` (MM-LIFE-2e slab scrub), `scrub`
   (MM-ALLOC-6 handout wipe), `region` (MM-RGN-1 exit reset),
   `exhaust` (MM-LIFE-2l: without the trap the retain returns).
6. The exhaustion boundary as a terminal trace in section 2.

A green run is agreement on the traces run, at the levels run, on
the host it ran on. The model is not a proof of the runtime and the
runtime passing is not a proof of the model.

## What is still open

- Seeded compiler-input fuzzing in CI (the second half of R-E1 as
  plan.md states it).
- Fuzzing of FFI boundaries and runtime operations; sanitizers and
  race detectors; schedule exploration, and memory-ordering litmus
  families beyond the three `scripts/check-atomics.sh` runs (SB, MP
  and a contended counter, R-C3); allocation/cancellation/failure
  injection beyond the fault-injected count boundary (527) and the
  `reset_keeping` fixtures (165).
- Long-duration memory and concurrency stress; inspection of
  optimized IR and machine code for critical lowering beyond the
  atomics (`check-atomics.sh` counts theirs at all four levels; the
  model assembles at one level per trace, not all four with diffing).
- Differential and metamorphic compiler tests beyond the bootstrap
  fixpoint (`stage2 == stage3`) and the MIR differential.
