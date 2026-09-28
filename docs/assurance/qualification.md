# Qualification strategy

This page sets out how the repository's evidence could one day support
a qualification argument, and what is missing. It is a strategy
skeleton, not a claim: no configuration here is qualified. §4 keeps
machine-assisted work separate from the independent assessment that
every standard below requires.

## 1. Scope

A qualification argument would cover:

- one named [configuration](configurations.md): target, OS, toolchain,
  `--opt` level and runtime profile;
- the compiler and runtime sources at one commit;
- the seed chain that built them (`bootstrap/CHAIN`);
- the backend tools: `llc`, `cc` and, for FFI crates, the pinned Rust
  toolchain.

Anything outside that tuple, such as another target, another LLVM or
another `--opt`, needs its own evidence. Today only H1, H2 and H3 run
the gates, and E1 checks emission. Execution on freebsd, windows and
darwin-x86_64 is unverified.

## 2. Standards mapping (strategy only)

No standard's objectives are claimed as met. This mapping records which
objectives the current evidence would speak to, for each standard's
current edition, so a future assessor doesn't start from a blank page.
Nothing here is legal or certification advice.

- **Aviation (DO-178C / DO-330, AC 20-193 for multicore):** the gates
  map most directly onto verification objectives and onto tool
  qualification (DO-330), for a development tool whose output is
  verified by other means. Missing: requirements-based coverage
  analysis, structural coverage (MC/DC where applicable), tool
  operational requirements and multicore interference analysis.
- **Automotive (ISO 26262):** a tool confidence level would need an
  argument from the bootstrap determinism evidence (`stage2 == stage3`,
  `check-reproducible.sh`) plus the diagnostic corpus. Software
  verification would need the unit, design and test trace that this
  directory only sketches. Missing: the TCL argument, ASIL-appropriate
  coverage and fault-injection evidence.
- **General (IEC 61508):** comparable gaps: a systematic-capability
  argument, verified configurations and anomaly tracking.
- **Space (ECSS-E-ST-40 / ECSS-Q-ST-80):** the requirements matrix
  ([requirements.md](requirements.md)) and the scorecard follow the
  traceability shape those standards ask for. Missing: the process
  evidence around them, such as reviews, NCRs and qualification test
  reports.
- **Defence and others:** the actual programme's assurance requirements
  govern, and nothing here substitutes for them.

## 3. Required artifacts and their state

| Artifact | State |
|---|---|
| Requirements-to-design-to-code-to-test traceability | Skeleton: [requirements.md](requirements.md) and plan findings F1–F12 |
| Hazard analysis / security threat analysis | Absent |
| Trusted-component list | Partial: seed chain, `llc`/`cc`, pinned Rust; no version-pinned LLVM |
| Tool operational requirements and qualification strategy | This page, strategy only |
| Verification independence | §4: not satisfied by repository evidence alone |
| Structural coverage evidence | Absent (no coverage runs exist) |
| Configuration management / change impact / anomaly tracking | Partial: git history and the gates; no anomaly log yet |
| Known limitations / errata / user safety manual | Partial: the gaps in [scorecard.md](scorecard.md) and the stated `MM-PAR-7` limits; no safety manual |
| Support / vulnerability-response / regression policy | Absent |

## 4. AI-assisted work is not independent assessment

Machine-assisted implementation and review, including the parallel
agents behind the assurance programme, don't satisfy any standard's
verification-independence requirement. They are a productivity input
to the evidence, reviewed like any other contributor's work. Every
landed change names the gate or fixture that checks it, and the gates
replay that evidence without trusting its author.

Before anything can be called "approved" or "certified", an
independent, competent assessor, separate from the implementation work,
must accept the evidence for a specific application, platform,
configuration and development process. Nothing in this repository is
approved, and no document here says it is.

## 5. What would come next

In dependency order:

1. An anomaly log.
2. Hazard and threat analyses.
3. The open fuzzing findings (R-E1, `tests/fuzz/MANIFEST`).
4. Sanitizer and coverage runs on the hosted configurations.
5. The rest of R-C2: mutex, timeout, cancellation and typed results.
   The channel (R-C2a) and the machine-code inspection of the atomics
   (R-C3) have landed.
6. The restricted embedded profile, with its resource report (R-D1).
7. QEMU execution evidence, marked as emulator evidence (R-D2).
8. Only then, a per-standard tool-qualification argument over a frozen
   configuration.
