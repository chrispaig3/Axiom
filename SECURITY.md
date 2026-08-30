# Security Policy

## Reporting a vulnerability

Report privately, through GitHub's **Report a vulnerability** button on
the Security tab of this repository. That opens a private advisory
visible only to the maintainer.

Do not open a public issue for a suspected vulnerability, and do not
include a working exploit in the first report — a description of the
class of problem and the conditions that reach it is enough to start.

**Expect a first response within 7 days**, and a decision — fix,
mitigation, or "this is working as designed, here is why" — within 30.
This project has **one maintainer**, which is stated here rather than
implied: that is the honest bound on response time, and it is a risk a
consumer should price in.

## What is supported

The supported release is **0.5.0**. Security fixes are made against the
newest release and shipped as a new patch; earlier releases receive
nothing, and there is no long-term-support branch.

That line is not prose. `scripts/check-version.sh` holds it to
`VERSION` along with the eighteen other places the tree states a
version, so a release that forgets to move it fails before the tag is
cut.

## What is in scope

- **The compiler** (`self_host/`) and the **standard library**
  (`stdlib/`) — a program that compiles to something other than what it
  says, or a library function that reads or writes memory it was not
  given.
- **The seed** (`bootstrap/`) — the six checked-in `.ll` files every
  build descends from. `scripts/check-seed-provenance.sh` regenerates
  all six from the source at the commit that last wrote them and
  requires byte-identity, and `scripts/check-seed-lineage.sh` replays
  `bootstrap/CHAIN` - every seed ever committed reproduced from the one
  before it, back to a Rust compiler no Axiom seed touched; a way to
  defeat either is in scope.
- **The installer** (`scripts/install.sh`) — what `curl | bash` runs.
  It verifies a SHA-256 against a published checksum file, and
  `scripts/check-install.sh` proves that comparison is what refuses a
  tampered archive.
- **The FFI boundary** (`docs/ffi.md`) — a shape the boundary accepts
  and then misreads.

## What is out of scope

Said out loud rather than left unstated.

- **A program that uses `cast` unsoundly.** `cast` is an unchecked
  reinterpretation and `docs/memory-model.md` says so; it is the
  language's escape hatch, not a defect.
- **A program that calls `__syscallN` directly.** The standard library
  is written over raw syscalls and any program may do the same.
- **Denial of service by resource exhaustion at compile time.** The
  parser has a nesting limit (`AX2005`) and the expander a node budget
  (`AX3024`); beyond those, a program that takes a long time to compile
  is a program that takes a long time to compile.
- **Windows.** Not a supported target. `README.md`'s *Targets* section
  states what supported means — a CI leg executes what the compiler
  emits there — and the Windows leg runs under `continue-on-error`: the
  compiler emits and links for `windows-x86_64`, no artifact is
  published for it, and no Windows binary is something this policy
  covers until the target is on that list. `scripts/check-doc-drift.sh`
  holds this bullet to it.
- **`rust/`'s example crates.** `rust/examples/` exists to exercise the
  FFI gate. It is not shipped and not a dependency of the compiler.

## The supply chain

The compiler is self-hosted, so the seed is the trust root, and
Thompson's attack stands against any single seed: the compiler that
regenerates it is itself seed-descended. What answers that is a root
that is not an Axiom seed. The Rust implementation this repository
deleted (`430a138`) is still in its history at `bb730db`, still builds
with `cargo`, and compiles the first seed commit's `self_host/` into a
compiler whose emission is the first seed byte for byte; every seed
since reproduces from the one before it. `bootstrap/CHAIN` is that
lineage and `scripts/check-seed-lineage.sh` replays it - the newest
link on every push that touches `bootstrap/`, all of it nightly.
Three historical seeds that nothing reproduces are named there as
orphans and bypassed; `bootstrap/README.md` states the gap.

The trust base of that replay is `git`, `llc` and `cc`, `cargo` and
`rustc` and the crates `bb730db`'s `Cargo.lock` pins, and the Rust
source at `bb730db` - which shares an author with `self_host/`. No
Axiom binary is called before the comparison. Taking `llc` and `cc`
out of that list is a separate track and is not claimed here.

What *is* checked besides: the seed reproduces byte-identically from a
named source hash (`bootstrap/STAMP`), every release binary carries a
build id over every `.ax` byte under `self_host/` and `stdlib/`, and
the release workflow refuses to publish a binary that says
`(build unstamped)`.
