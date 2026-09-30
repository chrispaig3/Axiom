# Tool qualification strategy

This page sets out how the compiler and the evidence tools could be
qualified for a named configuration, and what each standard would ask.
No tool here is qualified, and this page claims no objective of any
standard as met.

## Sources

Three public texts were read in full for this page:

- FAA AC 20-193, "Use of Multi-Core Processors" (8 January 2024). Its
  objectives are quoted by identifier under
  [Aviation](#aviation-do-178c-do-330-and-ac-20-193).
- EASA AMC 20-193, "Use of multi-core processors" (Annex I to ED
  Decision 2022/001/R, 25 January 2022). It uses the same objective
  identifiers as the FAA's circular.
- ECSS-Q-ST-80C Rev.2, "Software product assurance" (30 April 2025),
  which supersedes Rev.1. Its clauses are named under
  [Space](#space-ecss-q-st-80c-rev2-and-ecss-e-st-40).

DO-178C, DO-330, ISO 26262:2018, IEC 61508:2010 and ECSS-E-ST-40 weren't
consulted, because their text isn't public. What this page says about
them is limited to their publicly documented structure, such as tool
qualification levels, tool confidence levels and tool classes, and it
names no clause of theirs. A qualification plan must be written against
the licensed editions by someone who holds them, and must re-derive
every row below.

## The tools and their roles

| Tool | Role | Is its output verified by other means? |
|---|---|---|
| `axiom build` (the compiler and its emitted runtime) with `opt`, `llc`, `cc` and `ld.lld` | A development tool: its output becomes part of the airborne, in-vehicle or on-board software | Only if the application verifies the executable object code against its requirements |
| `scripts/axiom-report.py` | A verification tool: it can fail to detect a recursion, an allocation or an unbounded stack | Its refusals can be re-checked by hand from `symbols` and the object. The absence of a refusal can't |
| The gate battery (`scripts/check-*.sh`) | Verification tools for the compiler itself | They are the evidence, and each is ablated |
| `scripts/lib/fuzz.py`, `scripts/lib/runtime-model.py`, `scripts/lib/protocol-model.py` | Verification tools for the compiler, the runtime and the concurrency library | Planted controls and mutation witnesses run on every invocation |
| `scripts/measure-coverage.sh` | A measurement of structural coverage of the compiler's object code | Its instrument is checked before each use (below) |

## Tool operational requirements

These are the requirements a qualified configuration would hold each
tool to, with the evidence that exists today.

| TOR | Requirement | Evidence today |
|---|---|---|
| TOR-1 | For an accepted program, the executable implements the source's meaning as `docs/reference.md` and `docs/memory-model.md` define it, at the configuration's `--opt` | The corpora, `.optstable` fixtures, the bootstrap fixpoint and the differential gates. There is no miscompilation oracle (HZ-C1) |
| TOR-2 | A program that breaks a checked rule is refused with a diagnostic and never compiled | The diagnostics corpus (`scripts/check-diagnostics.sh`); fuzzing (`scripts/check-fuzz.sh`), whose eight findings are fixed ([anomalies.md](anomalies.md)) |
| TOR-3 | Every runtime check the contract promises (bounds, division, allocation, count, contract, reset validity) is present in the object at every `--opt` | Trap fixtures with `.optstable` |
| TOR-4 | Two builds of one input under one configuration are byte-identical | `scripts/check-reproducible.sh` |
| TOR-5 | The object imports no libc symbol on a freestanding configuration | `scripts/check-freestanding.sh` |
| TOR-6 | `axiom-report.py` reports every reachable recursion, indirect call, foreign item, spawn and steady-state allocation, and never reports a stack bound lower than the object's worst path | `scripts/check-report.sh` and its ablations; the assumptions in [restricted-profile.md](../restricted-profile.md) |
| TOR-7 | A gate reports failure for every planted defect of the kind it exists to detect | The ablations recorded in each gate |

## Structural coverage

`scripts/measure-coverage.sh` measures block and decision coverage of
the compiler's own object code over its test corpora. The compiler is
rebuilt with SanitizerCoverage (one 8-bit counter per basic block,
pruning off), and each run's counters land in a shared mapping, so a
run that ends in a trap is still recorded. The instrument is checked
before its number is believed:

- the instrumented compiler emits byte-identical IR to the plain one on
  a sample of inputs;
- a program that divides by zero enters the backtracer, and one that
  doesn't never enters it;
- every run leaves both a counter file and a metadata file;
- a program that branches on its argument count reads that decision as
  one outcome of two after a run with no argument, and both after a
  second run with one.

A decision is a conditional branch or a `switch` in the instrumented
IR. SanitizerCoverage splits critical edges before it places counters,
so each outcome has a counter of its own, and `scripts/lib/coverage.py
decisions` reads them back per decision.

On H3 at `--opt 1`, 578 runs hit 25,715 of 61,827 blocks (41.6%) and
entered 2,075 of 4,578 functions (45.3%). Of 18,943 decisions, 10,251
were reached; 14,114 of 37,321 outcomes were taken (37.8%), and 4,175
decisions had every outcome taken (22.0%). Three decisions have an
outcome with no counter and aren't counted. The diagnostics module
reaches 86.5% of its blocks. The LSP, REPL, `Json` and `Tui` modules
read as unmeasured, because `scripts/measure-coverage.sh` runs nothing
that drives them.

This is block and decision coverage of the compiler's object code over
its own tests. It isn't MC/DC: a decision's conditions are the
source's, and nothing below the front end keeps them. It says nothing
about coverage of an application's object code, which the
application's own verification must measure.

## Standards mapping

This is a strategy only.

<a id="aviation-do-178c-do-330-and-amc-20-193"></a>
### Aviation: DO-178C, DO-330 and AC 20-193

The compiler is a development tool. Under DO-178C, a development tool
whose output isn't verified needs qualification at the level DO-330
assigns from the software level. The usual route for a compiler is to
verify its output instead: requirements-based testing and structural
coverage of the executable object code. Code the compiler adds that
doesn't trace to source is analysed separately; here that is the
emitted runtime, retain and release, and the trap exits. The runtime is
small and enumerated ([trusted-components.md](trusted-components.md)),
and its behaviour is modelled, which supports that analysis.

`axiom-report.py` is a verification tool. It would need qualification
at the verification-tool level if its output eliminated, reduced or
automated a verification activity, such as stack usage analysis,
without being verified itself. TOR-6 and `scripts/check-report.sh` are
the start of that data. Independent verification of the tool doesn't
exist.

AC 20-193 applies when a hosted application or the hardware item holding
the multi-core processor is IDAL A, B or C, with two or more cores
active. At IDAL A or B every objective applies. At IDAL C,
MCP_Resource_Usage_4 and MCP_Error_Handling_1 don't, and
MCP_Resource_Usage_3 may be left unmet when no hosted application must
be robustly partitioned, at the cost of verifying every component with
all the software running (its note d). MCP_Resource_Usage_2 is reserved:
AC 20-152A's objective COTS-8 covers it.

The circular's verification section (§5.5.2) warns that coupling
analysis done one core at a time can miss behaviour that comes from a
processor's memory model. That is where Axiom's concurrency evidence
bears. `MM-PAR-9` says which accesses are ordered between bindings, and
the litmus tests show the lowering keeps that order on the hosts that
run them. Axiom's contribution is otherwise small, stated per
objective:

| Objective | What it asks (paraphrased) | What Axiom contributes | What it can't |
|---|---|---|---|
| MCP_Planning_1 | Identify the MCP, its active cores, the software architecture and dynamic features | [configurations.md](configurations.md) names targets and runtime profiles | The MCP and its configuration are the system's |
| MCP_Planning_2 | Describe shared-resource use, its allocation and verification | The restricted profile is single-threaded plus ISRs (RP-4). The hosted profiles' sharing rules are `MM-PAR-9` to `MM-PAR-13` | Allocation of cache, bandwidth and devices |
| MCP_Resource_Usage_1 | Determine and document the MCP's configuration settings | None | The system's |
| MCP_Resource_Usage_3 | Identify interference channels and verify their mitigation | `MM-PAR-9` states what orders memory between bindings; the atomics are lowered and litmus-tested (`scripts/check-atomics.sh`) | Cache, interconnect and peripheral interference are hardware channels no language rule touches |
| MCP_Resource_Usage_4 | Verify that resource demands don't exceed what is available | A stack bound per build (RP-7) and heap ceilings (`--heap-ceiling`) | Worst-case execution time and bandwidth |
| MCP_Software_1 | Hosted software works correctly and completes in time in the final configuration | Nothing beyond HZ-C1's controls | Timing on the target |
| MCP_Software_2 | Data and control coupling between components is exercised, including through shared memory and the mechanisms that control access to it | `symbols --calls` gives one program's control coupling. `MM-PAR-9` to `MM-PAR-13` define what orders shared memory, and `scripts/check-atomics.sh` and `scripts/check-protocol-model.sh` exercise it | Coupling across programs and cores |
| MCP_Error_Handling_1 | Detect MCP failures and handle them safely | Trap statuses are defined, and recovery points exist | The safe state and any safety net are the system's |
| MCP_Accomplishment_Summary_1 | Summarise how each objective was met | This table is an input to it | None stated |

### Automotive: ISO 26262 Part 8

A tool's confidence level follows from its tool impact and from how
likely an error is to be detected. For the compiler, the argument
pairs its tool impact (it can introduce errors) with detection by the
application's own verification. For `axiom-report.py`, it pairs it
with the detection its self-checks and ablations provide.

The standard's qualification methods map as follows:

- validation: the gate battery and the TOR evidence above;
- evaluation of the development process: [plan.md](plan.md), the
  ablation rule and [support-policy.md](support-policy.md);
- increased confidence from use: none, because there is no field
  history.

### General: IEC 61508-3

Off-line support tools are classed by whether they can contribute
errors to the executable (the compiler, the highest class) or can only
fail to detect them (`axiom-report.py` and the gates). The evidence
expected for the highest class includes a specification or manual for
the tool (`docs/reference.md`, `docs/memory-model.md` and
[safety-manual.md](safety-manual.md)), its known defects
([anomalies.md](anomalies.md)), and evidence of validation for the
configuration.

<a id="space-ecss-e-st-40-and-ecss-q-st-80"></a>
### Space: ECSS-Q-ST-80C Rev.2 and ECSS-E-ST-40

ECSS-Q-ST-80C Rev.2 asks for these things of the tools and the code the
project builds with them. Each is the project's to meet; the repository
supplies inputs.

| Clause | What it asks (paraphrased) | What the repository supplies |
|---|---|---|
| 5.6.1.1 | Identify the methods and tools for every development activity | [configurations.md](configurations.md) names the compiler, the backend tools and the gates for each configuration |
| 5.6.1.2 | Justify each tool: the team's experience with it, its fit to the product, its availability for the product's whole development and maintenance life, and its fit to the product's security sensitivity | The compiler is built from the committed seed with no outside compiler (`scripts/bootstrap-from-seed.sh`), so its availability doesn't depend on a supplier. LLVM's does |
| 5.6.1.3 | Verify and report the correct use of the tools | The gates replay the evidence; [safety-manual.md](safety-manual.md) states the conditions of use |
| 5.6.2 | Choose the development environment on stated criteria, among them maintenance, supplier dependence and security | [support-policy.md](support-policy.md) and [trusted-components.md](trusted-components.md) |
| 6.2.3.2 | Define and apply measures for critical software, such as a safe language subset, 100% branch coverage at unit level, full source inspection, independent testing and removal of deactivated code | The restricted profile ([restricted-profile.md](../restricted-profile.md)) is a checked subset; decision coverage of the compiler's own object code is measured (above). Coverage of the application's code, inspection and independent testing aren't |
| 6.2.7 | Reuse of existing software, such as the LLVM tools and the seed | `bootstrap/CHAIN` and `bootstrap/SHA256SUMS` record the seed's provenance; the LLVM tools are pinned only by configuration ([configurations.md](configurations.md)) |
| 6.2.9 and 6.2.10 | Software security and the handling of security-sensitive software, new in Rev.2 and applied by the project's security sensitivity level | [threats.md](threats.md), [SECURITY.md](../../SECURITY.md), and the crypto suite's constant-time checks (`AX3092`, `scripts/check-crypto.sh`) |
| 6.3.5.2 | Agree test coverage goals for each test level from criticality and security sensitivity, and track them with metrics | The compiler's block and decision figures above. The goals are the project's |
| 6.3.5.7 | Check the coverage of configurable code in each tested configuration | Axiom's configurable code is chosen by `--target`, `--opt` and `--threads`, and the `.optstable` fixtures run `--opt` 0 to 3. Per-target coverage isn't measured |

ECSS-E-ST-40, which sets the software engineering processes and the
code coverage each criticality category requires, wasn't consulted.
Reviews, nonconformance reports and tool qualification against the
project's criticality category are the project's, and aren't in this
repository. Long-duration concerns such as resets, persistent state
and radiation effects are the system's (HZ-E4 in
[hazards.md](hazards.md)).

## Verification independence

Everything in this repository was produced by one maintainer working
with AI assistance. The gates re-run the evidence without trusting its
author, which makes it reproducible, but not independent. DO-178C,
ISO 26262, IEC 61508 and the ECSS standards all require verification
with independence at their higher levels, and none of that
independence exists here ([qualification.md](qualification.md) §4).
