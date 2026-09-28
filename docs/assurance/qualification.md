# Qualification strategy

How this repository's evidence could one day support a qualification
argument — and what is missing. This is a strategy skeleton, not a
claim: no configuration here is qualified, and §4 keeps
machine-assisted work distinct from the independent assessment every
standard below requires.

## 1. Scope

A qualification argument would cover one named
[configuration](configurations.md) (target, OS, toolchain, `--opt`
level, runtime profile), the compiler and runtime sources at one
commit, the seed chain that built them (`bootstrap/CHAIN`), and the
backend tools (`llc`, `cc`, and for FFI crates the pinned Rust
toolchain). Anything outside that tuple — another target, another
LLVM, another `--opt` — needs its own evidence. Today only H1/H2/H3
execute the battery and E1 checks emission; freebsd/windows/
darwin-x86_64 execution is unverified.

## 2. Standards mapping (strategy only)

No standard's objectives are claimed as met. The mapping records
which objectives the current evidence would speak to, per standard's
current edition, so a future assessor does not start from a blank
page. Nothing here is legal or certification advice.

- **Aviation (DO-178C / DO-330, AC 20-193 for multicore):** the gate
  battery maps most directly onto verification objectives and tool
  qualification (DO-330) for a development tool whose output is
  verified by other means. Missing: requirements-based coverage
  analysis, structural coverage (MC/DC where applicable), tool
  operational requirements, multicore interference analysis.
- **Automotive (ISO 26262):** tool confidence level would need
  argument from the bootstrap determinism evidence (`stage2 ==
  stage3`, `check-reproducible.sh`) plus the diagnostic corpus;
  software verification would need the unit/design/test trace this
  directory only sketches. Missing: TCL argument, ASIL-appropriate
  coverage, fault-injection evidence.
- **General (IEC 61508):** comparable gaps: systematic-capability
  argument, verified configurations, anomaly tracking.
- **Space (ECSS-E-ST-40 / ECSS-Q-ST-80):** the requirements matrix
  ([requirements.md](requirements.md)) and scorecard follow the
  traceability shape those standards ask for; missing: the process
  evidence (reviews, NCRs, qualification test reports) around them.
- **Defense and others:** the actual program's assurance
  requirements govern; nothing here substitutes for them.

## 3. Required artifacts and their state

| Artifact | State |
|---|---|
| Requirements-to-design-to-code-to-test traceability | skeleton: [requirements.md](requirements.md) + plan findings F1–F12 |
| Hazard analysis / security threat analysis | absent |
| Trusted-component list | partial: seed chain, `llc`/`cc`, pinned Rust; no version-pinned LLVM |
| Tool operational requirements + qualification strategy | this file, strategy only |
| Verification independence | §4: not satisfied by repository evidence alone |
| Structural coverage evidence | absent (no coverage runs exist) |
| Configuration management / change impact / anomaly tracking | partial: git history + gate battery; no anomaly log yet |
| Known limitations / errata / user safety manual | partial: [scorecard.md](scorecard.md) gaps + `MM-PAR-7` stated limits; no safety manual |
| Support / vulnerability-response / regression policy | absent |

## 4. AI-assisted work is not independent assessment

Machine-assisted implementation and review — including the parallel
agents behind the assurance programme — do not satisfy any standard's
verification-independence requirement. They are a productivity input
to the evidence, reviewed like any other contributor's work: every
landed change names the gate or fixture that checks it, and the
battery replays that evidence without trusting its author. An
independent, competent assessor, separate from the implementation
work, must still accept the evidence for a specific application,
platform, configuration, and development process before any
"approved" or "certified" statement. Nothing in this repository is
approved, and no document here says otherwise.

## 5. What would come next

In dependency order: anomaly log; hazard and threat analyses;
the open fuzzing findings (R-E1, `tests/fuzz/MANIFEST`); sanitizer and
coverage runs on the hosted configurations; the rest of R-C2 (mutex,
timeout, cancellation, typed results - the channel and the atomics'
machine-code inspection, R-C2a and R-C3, have landed); the restricted
embedded profile with its
resource report (R-D1); QEMU execution evidence marked as emulator
evidence (R-D2); and only then a per-standard tool-qualification
argument over a frozen configuration.
