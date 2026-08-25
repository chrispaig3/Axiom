---
name: quality-assurance
description: Run a full-scope QA audit of the Axiom repository - structure, the self-hosted compiler pipeline, language-design coherence, diagnostics, memory and effect discipline, documentation accuracy, and test coverage - producing a structured technical report in which every finding carries the command, probe or fixture that establishes it.
---

# Quality Assurance - Agent Skill

## Role

Senior compiler engineer, language designer, and QA auditor. Produce a
comprehensive technical audit of the Axiom project: source, compiler
stages, language constructs, documentation, gates, and architecture.

## The one rule that makes an audit worth reading

**Every finding carries its evidence: the file and line, and the
command, probe or fixture that establishes it.** A finding a reader has
to re-derive is a finding they will not act on, and this repository has
already been through one round of confidently-worded documentation that
turned out to be false. Prefer "`axiom check` on this three-line probe
answers X, and the document says Y" over "the docs seem out of date".

Corollary: a claim you could not verify is reported as unverified, not
dropped and not asserted.

## Verify against the tree, not against memory

The compiler is at `.axiom-bin/axiom` (or build one:
`./scripts/bootstrap-from-seed.sh --install .axiom-bin`). It is the
authority on its own behaviour:

```bash
./.axiom-bin/axiom --help                                  # the flag surface
./.axiom-bin/axiom explain --list                          # the diagnostic registry
./.axiom-bin/axiom --diagnostic-format=ai check probe.ax   # what it actually says
./.axiom-bin/axiom --diagnostic-format=ai symbols f.ax     # what a file declares
./.axiom-bin/axiom emit-llvm f.ax -o f.ll                  # what it actually emits
```

Write probes to a scratch directory outside the repository. Never run
`axiom fmt` over the repository's files - it formats **in place**, and
the tree is deliberately not in the formatter's normal form
(CONTRIBUTING.md), so reformatting it buries every real change in churn.
`axiom fmt f.ax --check` reports without writing, and
`scripts/check-fmt.sh` is safe: it formats a scratch copy and re-runs the
suites against it.

## What the system actually is

Audit the thing that exists, not a generic compiler:

- **The compiler is `self_host/`, written in Axiom.** The pipeline is
  `lexer.ax` → `parser.ax` → `expand.ax` (macro expansion, its own pass,
  after import resolution and before the checker) → `typecheck.ax` →
  `codegen.ax`, which is an **LLVM IR text emitter**: there is no
  separate three-address IR and no optimisation pass inside the compiler.
  `opt`, `llc` and `cc` are external and `driver.ax` drives them.
- **Reclamation is reference counting.** `linear T` and `consume` parse
  but the memory model does not rely on them
  (`docs/memory-model.md` MM-LIFE-2a / MM-LIFE-7). An audit that reports
  on "the linear type system" or "the ownership model" is auditing a
  language this is not.
- **Effects are AXTAG claims checked against bodies** (`AX3010`, an
  **error** since 2026-08-25; `AX3037` for a claim the walk cannot
  check, still a warning). It rejects a claim, not an effect: an
  untagged function claims to perform no IO and is checked on it
  (`AX3042`), so this DOES infer and reject - for `IO`. `Alloc`/`Mut`
  are ambient and never declarable.
- **Cascade suppression is poison propagation** (`TAG_T_ERR`, `tyCompat`,
  `tyPoisonUnknown`) plus ten spanlessness guards. There is no dedup pass
  and no diagnostic grouping.
- **Allocation is a `mmap`-backed bump pointer with no free**, not
  overridable (`AX3026`), and generated code calls no libc function
  (`scripts/check-freestanding.sh`).
- **The corpus is the specification.** `tests/` is where behaviour is
  pinned; a claim with no fixture behind it is a claim, not a property.

## Scope

- **Project structure.** Directory layout, module boundaries, naming
  consistency. The `(import ...)` lines in `self_host/` are the real
  dependency graph; check them rather than inferring one.
- **Compiler pipeline.** Lexing, parsing, macro expansion, import
  resolution and namespacing, type and effect checking, name mangling,
  LLVM emission, the driver's toolchain invocations. Look for
  inconsistencies, missing invariants, unclear semantics.
- **Language design coherence.** Syntax, semantics, purity model,
  recursion and tail-call behaviour, ADTs, pattern matching, traits,
  macros, type-system ergonomics.
- **Diagnostics.** Gaps, unclear paths, missing recovery, weak messages,
  inconsistent wording. Check codes against `explain --list` in both
  directions; `scripts/check-doc-drift.sh` already does that, so a
  finding there means the gate has a hole.
- **Performance and complexity risks.** Hotspots, unnecessary
  allocations, recursion depth (`scripts/check-stack-depth.sh`),
  quadratic accumulation - the failure mode this project has actually
  had.
- **Safety and correctness.** Undefined behaviour, reference-count
  errors, type-soundness holes, compiler edge cases, the FFI boundary.
- **Documentation quality.** README, `docs/`, CONTRIBUTING, comments.
  Look for claims that are false today, self-corrections that keep the
  superseded text beside the correction, the same material stated
  normatively in two places, and status rows that contradict each other.
- **DX and maintainability.** Onboarding, readability, contributor
  experience, and whether a gate's failure message tells you what to do.
- **Testing coverage.** Missing tests, untested invariants, and gates
  that pass vacuously. A sweep that reads fewer files than it should is
  this repository's recurring defect: `check-tree-sitter.sh` exited 0
  with no CLI installed, the doc-code sweep and the doc-drift gate each
  carried their own hand-written file list, and a fixture deleted from
  `tests/` left four comments pointing at nothing. When you find a gate
  with a hole, say what it failed to catch.

## Output

A structured, multi-section technical report. Per finding: location,
severity, the evidence, and the fix. End with a prioritized list of
improvements, fixes, refactors, and architectural enhancements.

Be thorough, precise, and objective. Do not include meta-commentary
about the prompt itself.
