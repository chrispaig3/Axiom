# Qualification strategy

This page sets out how the repository's evidence could one day support
a qualification argument, and what is missing. No configuration here
is qualified. The detailed pages are listed in §3, and §4 keeps
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
another `--opt`, needs its own evidence. Today only H2 and H3 run the
gates, H1 is source-only, and E1 checks emission. Execution on the
source-only targets (every hosted target but the two aarch64 ones) is
unverified.

## 2. Standards mapping (strategy only)

No standard's objectives are claimed as met. This mapping records which
objectives the current evidence would speak to, for each standard's
current edition, so a future assessor doesn't start from a blank page.
Nothing here is legal or certification advice.

- **Aviation (DO-178C / DO-330, and AC 20-193 of 8 January 2024 for
  multi-core processors):** the gates map most directly onto
  verification objectives and onto tool qualification (DO-330), for a
  development tool whose output is verified by other means. AC 20-193's
  ten objectives are mapped one by one in
  [tool-qualification.md](tool-qualification.md); every one of them is
  the applicant's, and Axiom contributes the memory-ordering rules and
  their litmus evidence to MCP_Software_2. Missing: requirements-based
  coverage analysis, structural coverage (MC/DC where applicable) and
  any interference analysis, which needs the target processor.
- **Automotive (ISO 26262):** a tool confidence level would need an
  argument from the bootstrap determinism evidence (`stage2 == stage3`,
  `check-reproducible.sh`) plus the diagnostic corpus. Software
  verification would need the unit, design and test trace that this
  directory only sketches. Missing: the TCL argument, ASIL-appropriate
  coverage and fault-injection evidence.
- **General (IEC 61508):** comparable gaps: a systematic-capability
  argument, verified configurations and anomaly tracking.
- **Space (ECSS-Q-ST-80C Rev.2 of 30 April 2025, and ECSS-E-ST-40):**
  the requirements matrix ([requirements.md](requirements.md)) and the
  scorecard follow the traceability shape those standards ask for.
  [tool-qualification.md](tool-qualification.md) names the ECSS-Q-ST-80
  clauses on tools (5.6), critical software (6.2.3.2), reuse (6.2.7),
  security (6.2.9, 6.2.10) and test coverage (6.3.5.2, 6.3.5.7), and
  what the repository supplies for each. Missing: the process evidence
  around them, such as reviews, nonconformance reports and
  qualification test reports, and ECSS-E-ST-40's coverage rules, which
  weren't consulted.
- **Defence and others:** the actual programme's assurance requirements
  govern, and nothing here substitutes for them.

## 3. Required artifacts and their state

| Artifact | State |
|---|---|
| Requirements-to-design-to-code-to-test traceability | [requirements.md](requirements.md): each guarantee to its rule, implementation, owner, evidence and gaps |
| Hazard analysis and security threat analysis | [hazards.md](hazards.md) and [threats.md](threats.md), at component level. The system analyses are the integrator's |
| Trusted-component list | [trusted-components.md](trusted-components.md). The toolchain isn't version-pinned by the repository |
| Tool operational requirements and qualification strategy | [tool-qualification.md](tool-qualification.md): TOR-1 to TOR-7 and a strategy per standard, from public text only |
| Verification independence | Not satisfied by repository evidence (§4) |
| Structural coverage evidence | Block and decision coverage of the compiler's own object code (`scripts/measure-coverage.sh`). No MC/DC, and none of an application's code |
| Configuration management, change impact and anomaly tracking | [support-policy.md](support-policy.md) and [anomalies.md](anomalies.md) |
| Known limitations, errata and a user safety manual | [safety-manual.md](safety-manual.md), [anomalies.md](anomalies.md), and the Gaps column of [requirements.md](requirements.md) |
| Support, vulnerability-response and regression policy | [support-policy.md](support-policy.md) and [SECURITY.md](../../SECURITY.md) |
| Demonstrators | [demonstrators.md](demonstrators.md): all six built and gated, the two embedded ones under QEMU |

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

1. Race detection between forked bindings, and a heap sanitizer the
   arena works with. `scripts/check-race.sh` covers threads and
   globals.
2. Hardware execution on a named board, recorded apart from QEMU runs,
   with the MMU and caches on.
3. Frozen toolchain versions for one reference configuration.
4. Only then, a per-standard tool-qualification argument over that
   frozen configuration, written against the licensed standards and
   reviewed independently.
