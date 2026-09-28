# Support and change policy

This page says how a change reaches a release, how its impact is
judged, how a defect is recorded, and what you can expect after a
release. The vulnerability-reporting process and the support window
are in [SECURITY.md](../../SECURITY.md), and aren't restated here: one
supported minor line at a time, security fixes against the newest
release only, a first response within 7 days, and one maintainer.

## Configuration management

A build is identified by:

- the commit of `self_host/` and `stdlib/`: every release binary
  carries a build id over every `.ax` byte, and a release refuses to
  publish `(build unstamped)`;
- the seed it descends from (`bootstrap/STAMP`, `bootstrap/CHAIN`);
- the target, the `--opt` level and the runtime profile;
- the host toolchain's versions.

The repository records the first three. It doesn't pin the toolchain,
so you must archive those versions yourself
([trusted-components.md](trusted-components.md)).

A release is a `v*` tag on trunk after the battery and CI are green
(`CONTRIBUTING.md`, "Cutting a release"). `VERSION` is the single
source of the version number, and `scripts/check-version.sh` holds
every place that restates it.

Every change lands as a commit on trunk whose message states what was
wrong, why it went unseen, what changed, the measurements, and the
tests that pin it. There is no change board. With one maintainer,
review is the gate battery plus the author, which isn't independent
([tool-qualification.md](tool-qualification.md)).

## Change impact analysis

Before a change lands, its author states which of these it touches and
runs what each one requires:

| Touches | Required |
|---|---|
| `self_host/`, any compiler source | The full battery (`scripts/run-gates.sh`), including the bootstrap fixpoint, and the podman Linux battery (`scripts/run-gates-linux.sh`) for anything that reaches emitted code |
| The emitted runtime | All of the above, plus `scripts/check-runtime-model.sh`, `scripts/check-parallel.sh`, `scripts/check-recover.sh`, `scripts/check-atomics.sh` and `scripts/check-embedded.sh` |
| `stdlib/` modules the compiler imports | All of the above, because the seed compiles them too ([bootstrap/README.md](../../bootstrap/README.md)). Never a new primitive there without a reseed plan |
| A normative document | `scripts/check-doc-drift.sh` and every prose gate, with the rule's evidence updated in the same commit |
| A gate | The gate's own ablations, re-run, and `scripts/check-gate-lib.sh` if it calls `gate_build_axc` |
| A qualified configuration (none exists yet) | The configuration's full evidence, re-run and re-archived |

A change that moves a public signature, an effect row or an AXSYM key
is also held to `scripts/check-compat.sh`. Its baseline records the
contract, and `compat/BREAKING` records every intentional break.

## Anomaly management

Every defect found, whether by a user, a gate, the fuzzer or a review,
gets a row in [anomalies.md](anomalies.md) with its evidence and a
workaround, before or with its fix. Fuzzer findings are also kept as
minimised reproducers in `tests/fuzz/MANIFEST`. There, an open row must
keep failing as recorded, and a fixed row becomes a regression test. A
fix closes a row only with a test that fails without it.

## Regression management

- Every fixed defect keeps its fixture, and a gate that CI runs on H1
  to H3 runs every fixture.
- A gate is never weakened to pass. A changed expectation is a changed
  golden with its reason in the commit, and a removed check is stated
  in the changelog.
- A check that can't run on a host, for want of QEMU, procfs or
  `llvm-readobj`, prints SKIP with the reason and is counted apart from
  passes. A run's summary states passed, failed and skipped separately.
- Expensive coverage is scheduled, not dropped. CI's nightly run,
  also started by hand, replays the seed lineage in full
  (`scripts/check-seed-lineage.sh --full`) and runs the fuzzer's full
  budget and the model's every trace (`scripts/check-fuzz.sh --long`,
  `scripts/check-runtime-model.sh --long`). A push runs a sample of
  each.

## What you can expect

A defect in the supported release is fixed in a new patch release,
with its anomaly row closed and its regression test named in the
changelog. Earlier releases receive nothing. If you need a frozen
configuration supported for longer than one minor line, you need an
agreement this repository doesn't offer.
