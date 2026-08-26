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

The supported release is **0.3.4**. Security fixes are made against the
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
- **The seed** (`bootstrap/`) — the four checked-in `.ll` files every
  build descends from. `scripts/check-seed-provenance.sh` regenerates
  all four from the source at the commit that last wrote them and
  requires byte-identity; a way to defeat that is in scope.
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
- **Windows.** Not a supported target — `CONTRIBUTING.md` says so, and
  there is no build for it to be vulnerable.
- **`rust/`'s example crates.** `rust/examples/` exists to exercise the
  FFI gate. It is not shipped and not a dependency of the compiler.

## The supply chain

The compiler is self-hosted, so the seed is the trust root and Thompson's
attack stands against it: the compiler that regenerates the seed is
itself seed-descended. `docs/` records this as an open property rather
than a solved one — answering it needs a second, independent
implementation, and this repository deleted the one it had (`430a138`).

What *is* checked: the seed reproduces byte-identically from a named
source hash (`bootstrap/STAMP`), every release binary carries a build id
over every `.ax` byte under `self_host/` and `stdlib/`, and the release
workflow refuses to publish a binary that says `(build unstamped)`.
