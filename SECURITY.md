# Security policy

If you've found a security problem in Axiom, thank you. Please report
it privately, and we'll work on it with you.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** button on this repository's
Security tab. It opens a private advisory that only the maintainer can
see.

Please don't open a public issue for a suspected vulnerability, and
don't include a working exploit in your first report. A description of
the kind of problem, and the conditions that trigger it, is enough to
start.

You can expect a first response within 7 days. Within 30 days you'll
get a decision: a fix, a mitigation, or an explanation of why the
behaviour is intended. Axiom has one maintainer, and that is the real
limit on response time, so please factor it in. No second reviewer or
successor has been named yet. When one is, this page will say so.

## Supported versions

The supported release is **0.7.8**. Security fixes are made against the
newest release and shipped as a new patch release. Earlier releases get
no fixes, and there is no long-term support branch.

Support window: the 0.7 line is supported until 0.8.0 lands, and after
that it gets nothing further, including security fixes. There is one
supported minor at a time, always the newest.

`scripts/check-version.sh` holds both of those paragraphs to the
`VERSION` file, so a release can't ship while this page names the wrong
version or the wrong window. Moving the window to a new minor is a
policy decision, so it's done by hand when the minor is cut.

You never depend on the maintainer to build Axiom. After cloning,
`scripts/bootstrap-from-seed.sh --install` with your own `llc` and `cc`
is all you need, and `scripts/check-offline-bootstrap.sh` keeps it that
way in CI. See `CONTRIBUTING.md` and `bootstrap/README.md`.

## In scope

- **The compiler** (`self_host/`) and **the standard library**
  (`stdlib/`). For example, a program that compiles to something other
  than what its source says, or a library function that reads or writes
  memory it wasn't given.
- **The seed** (`bootstrap/`): the six checked-in `.ll` files every
  build descends from. `scripts/check-seed-provenance.sh` regenerates
  all six from the source at the commit that last wrote them, and
  requires them to match byte for byte. `scripts/check-seed-lineage.sh`
  replays `bootstrap/CHAIN`, reproducing every seed ever committed from
  the one before it, back to a Rust compiler no Axiom seed touched. A
  way to defeat either check is in scope.
- **The installer** (`scripts/install.sh`), which is what `curl | bash`
  runs. It verifies a SHA-256 against a published checksum file, and it
  must never delete anything it didn't install. It compares the install
  prefix as a physical directory (so `$HOME/.` is `$HOME`), replaces
  only trees its `.axiom-install` record lists, and proves the new
  compiler works before it moves the old one aside.
  `scripts/check-install.sh` tests each of these, including that a
  tampered archive is rejected.
- **The FFI boundary** (`docs/ffi.md`). That covers a shape the boundary
  accepts and then misreads, and a safe Rust API in a generated binding
  that can still reach undefined behaviour. A binding's contract is
  that raw words are only reachable through `unsafe`, and that there is
  one runtime thread, through `AxRuntime`. `scripts/check-ffi.sh` holds
  that contract to compile errors.
- **`Net`'s handles**: a `TcpStream` or `TcpListener` whose operations
  reach a descriptor after the handle was closed, and a write to a
  closed peer that ends the process with SIGPIPE instead of answering
  an error.
- **`axiom fetch`**: a build compiled against a checkout that isn't a
  clone of the URL its manifest names.

## Out of scope

- **Unsound use of `cast`.** `cast` reinterprets a value without
  checking it, and `docs/memory-model.md` documents it as the
  language's escape hatch.
- **Calling `__syscallN` directly.** The standard library is written on
  raw syscalls, and any program may use them too.
- **Compile-time resource exhaustion.** The parser limits nesting
  (`AX2005`) and the macro expander limits expansion size (`AX3024`).
  Beyond those, a program that takes a long time to compile isn't a
  vulnerability.
- **Source-only targets.** `darwin-x86_64`, `freebsd-aarch64`,
  `freebsd-x86_64`, `linux-x86_64`, `windows-aarch64` and
  `windows-x86_64` are not supported targets. `README.md`'s Targets section defines supported: a
  CI job executes what the compiler emits there. No CI job runs the test
  battery on these, and no release archive is published for them. This
  policy doesn't cover binaries emitted for them until a CI job runs
  them.
- **Windows as a host.** The compiler doesn't run on Windows. There is
  no Windows seed in `bootstrap/`, and `scripts/install.sh` refuses a
  Windows host.
- **`rust/examples/`.** These crates exist to exercise the FFI tests.
  They aren't shipped, and the compiler doesn't depend on them.

## Threat boundaries

Treat fetched source and build dependencies as untrusted inputs. The
compiler's parser and expander limit nesting and expansion, but other
compile-time resource exhaustion remains possible. The emitted LLVM IR
passes through host tools that can change the executable. The runtime
protects typed containers and live handles; raw casts, `Int` addresses,
foreign shims and shared pages require the caller's contract. Release
archives and checksums come from the same origin and are not signed.

See [memory obligations](docs/memory-model.md#program-obligations),
[FFI safety](docs/ffi.md#safety-contract) and
[bootstrap threats](bootstrap/THREATS.md).

## The supply chain

The compiler is self-hosted, so the seed in `bootstrap/` is the root of
trust. Any single seed is open to Thompson's "trusting trust" attack,
because the compiler that regenerates it descends from a seed itself.
The answer is a root that isn't an Axiom seed at all.

The Rust implementation this repository deleted (`430a138`) is still
in its history at `bb730db`, and still builds with `cargo`. It compiles
the first seed commit's `self_host/` into a compiler whose output is
the first seed, byte for byte. Every seed since then reproduces from
the one before it. `bootstrap/CHAIN` records that lineage, and
`scripts/check-seed-lineage.sh` replays it:

- on every push that touches `bootstrap/`, it replays every link
  `bootstrap/CHAIN.checkpoint` doesn't certify, and always at least the
  newest one;
- every night, it replays the whole chain from `bb730db`.

The checkpoint records a digest of the part of the chain a full run
derived. The gate recomputes that digest from `bootstrap/CHAIN` on
every run, and if any covered row has changed, it throws the checkpoint
away and replays everything. The checkpoint is a record, not a
signature. Anyone who can edit a row can recompute the digest, but the
edit and the re-certification then land in one reviewable diff, and the
nightly run re-derives every row regardless. Three historical seeds
that nothing reproduces are listed there as orphans and bypassed, and
`bootstrap/README.md` explains the gap.

The replay trusts `git`, `llc`, `cc`, `cargo`, `rustc`, the crates
pinned by `bb730db`'s `Cargo.lock`, and the Rust source at `bb730db`,
which shares an author with `self_host/`. No Axiom binary runs before
the comparison. Removing `llc` and `cc` from that list is separate work,
and isn't claimed here.

Three more things are checked:

- the seed reproduces byte for byte from a named source hash
  (`bootstrap/STAMP`);
- every release binary carries a build id computed over every `.ax`
  byte under `self_host/` and `stdlib/`;
- the release workflow refuses to publish a binary that reports
  `(build unstamped)`.
