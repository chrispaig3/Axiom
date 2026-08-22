---
name: performance-engineering
description: Diagnose and optimize performance in this repository - Axiom compiler and stdlib code, the emitted LLVM IR, the bump-allocator and reference-counting memory model, and the FFI boundary into rust/. Use when something is slow, when a profile or benchmark needs interpreting, or when a change needs a before/after measurement that will survive review.
---

# Performance Engineering - Agent Skill

## Role

Diagnose, explain, and optimize the performance characteristics of the
system in front of you: Axiom source, the LLVM IR it emits, the native
toolchain that consumes it, the memory model underneath, or the Rust
shims across the FFI boundary.

## Objectives

1. Identify bottlenecks with **mechanistic clarity** (CPU, memory, I/O,
   allocation, syscalls, cache, process boundaries).
2. Produce **actionable, ordered optimization steps** with realistic
   expectations.
3. Surface **non-obvious insights** (layout, branch prediction, allocator
   behaviour, IR patterns).
4. Provide **verification steps** so the change can be confirmed, and
   confirmed again later.

## The house rule: measure, then say what you measured

This repository's one recorded performance win was found by measuring,
and it was in the place nobody predicted. `renderCG` built the emitted
module by left-folding `strConcat` over a vector of lines. `strConcat`
allocates a fresh buffer and copies both operands, and the allocator is a
bump pointer with no free, so each line copied everything emitted so far
and abandoned the previous copy: peak was the *sum* of every
intermediate, growing with the square of the output. Measuring the total
length once and copying into a single buffer took one self-compile from
16,973,522,240 bytes peak and 11.54 s to 72,958,912 bytes and 0.85 s,
with byte-identical output (`docs/self-hosting.md`).

Three things that example is here to teach:

- **The dominant cost was not lexing, parsing, checking or lowering. It
  was the last line of code generation.** Do not reason from where the
  code looks complicated.
- **Byte-identical output is part of the claim.** A faster code generator
  that emits different code is a different compiler, and the bootstrap
  fixpoint is what would catch that.
- **A number with no method beside it is not a measurement.** Say what
  you ran, on what input, how many times.

## What actually exists to measure with

There is **no runtime metrics facility and no profiler integration** in
this project. Do not tell anyone to consult one. What exists:

| Tool | What it answers |
|---|---|
| `scripts/bench-compile.sh` | where a compile spends its time, split by work inside the Axiom process (lex, parse, resolve, expand, check, emit) and work outside it (`opt`, `llc`, `cc`) |
| `scripts/bench-datastructures.sh` | `Vec`, `Map` and `Intern` against the Rust equivalents, whole process against whole process, startup measured separately and subtracted; `--check` enforces the within-2x criterion |
| `scripts/measure-memory-baseline.sh` | RSS held flat across generations under the managed-memory contract, with the unmanaged twin as the negative control; `scripts/check-memory-baseline.sh` is the gate wrapper |
| `axiom emit-llvm f.ax -o f.ll` | the actual IR, before `opt`. Reading it is the cheapest way to settle what the emitter did |
| `axiom build --opt 0-3` | the optimisation level handed to the toolchain; default 1 |
| `/usr/bin/time -l` (macOS) / `-v` (Linux) | peak footprint and wall clock, which is what the `strConcat` table above is |
| `scripts/check-reproducible.sh` | that two compiles of one input agree byte for byte, which is the precondition for any before/after comparison meaning anything |

Timing methodology this repository already settled, and that a new
benchmark must not un-settle: time **whole processes** doing identical
work and printing the same answer, measure process startup separately
with a do-nothing program of each language and subtract it, and pass
every value through something the optimiser cannot see through - the
first version of `bench-datastructures.sh` reported Rust doing 100,000
pushes and reads in 200 microseconds, which was not a fast `Vec`, it was
no `Vec` at all.

## What the machine underneath actually is

State these correctly or not at all:

- **Allocation is a `mmap`-backed bump pointer with no free**, and it is
  not overridable - defining `axiom_alloc` is refused as `AX3026`. Every
  intermediate buffer you allocate stays resident until the process ends.
  This is why quadratic copying shows up as a memory catastrophe before
  it shows up as a slow one.
- **Reclamation is reference counting**, not linearity and not a garbage
  collector. `linear T` and `consume` parse but are not what the memory
  model relies on (README.md's status table; `docs/memory-model.md`
  MM-LIFE-2a / MM-LIFE-7). What linearity would still buy is
  retain/release-free moves and early drops - say that, not that Axiom
  has linear types.
- **`stdlib/Map.ax` is an open-addressing hash map with a separate state
  array**, mutable, `Int` keys to machine-word values. It is not
  persistent. `stdlib/Vec.ax` and `stdlib/Intern.ax` are the other two
  structures the compiler leans on.
- **Generated code calls no libc function**, by gate
  (`scripts/check-freestanding.sh`). "Just call `memcpy`" is not
  available.
- **The FFI crossing is one machine word each way per argument**
  (`Int`, `Float`, `Bool`, `Char`, `String`, `Foreign`), and anything
  else goes through a wrapper `axiom-bindgen` generates. That wrapper,
  not the call, is usually where the cost is.

## Outputs

Produce these sections:

### 1. Diagnosis
What is slow and why, mechanistically: "this allocates on every
iteration", "this copies the accumulated output per line", "this crosses
the process boundary once per file".

### 2. Root cause
The underlying mechanism: algorithmic complexity, memory layout,
allocation pattern, syscall count, lock contention, branch
misprediction, or what the emitter chose to lower it to.

### 3. Optimization plan
An **ordered** list. Each item: what to change, why it helps, expected
impact.

### 4. Expected impact
Realistic, and qualitative when that is all the reasoning supports:
"removes the quadratic term", "cuts allocations by roughly the number of
lines emitted", "one syscall per file instead of per line". Do not invent
a percentage.

### 5. Verification
Name the command from the table above, the input, and the number of
runs. If output correctness is at risk, name the gate that proves it did
not change - for the compiler that is the byte-identical `stage2 ==
stage3` fixpoint in `scripts/bootstrap-from-seed.sh`.

## Non-capabilities

- Do not guess performance numbers without reasoning.
- Do not fabricate benchmarks, or cite a tool this repository does not have.
- Do not modify code unless explicitly asked.
- Do not propose optimizations that violate language semantics, break the
  freestanding discipline, or change emitted output while claiming to be
  a pure speed-up.
- Do not run `axiom fmt` over the tree while chasing a diff.
