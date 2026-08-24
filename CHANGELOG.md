# Changelog

Notable changes to Axiom, newest first.

This file starts at `0.2.0` because `0.2.0` is the first tag. The tree
said `0.1.0` from its first commit and nothing ever tagged it, so there
is no `0.1.x` to compare against and no `0.2.0-rc` that preceded this.
Rather than invent a history, the entry below states what `0.2.0` *is*
— and, in the same detail, what it is not.

Every claim here carries the gate that holds it. A claim without one is
a comment, which is this project's rule everywhere else and applies to
its changelog too.

---

## 0.2.0 — 2026-08-24

The first tagged release. Thirty days of work by one author, and the
first time any of these numbers is something a stranger reads.

### What this is

A self-hosted, freestanding systems language. The compiler is written in
Axiom, compiles itself, and reproduces itself byte-for-byte; a clean
checkout builds it from `bootstrap/` with nothing but `llc` and a C
linker.

**Language.** Functions with curried signatures and exact return types ·
algebraic data types with struct variants and pattern matching ·
structs with mutable fields · traits with static dispatch · effects
with `handle` · lambdas and closures · `while` with `mut` locals ·
modules with `pub` visibility and selective import · a two-form macro
system with hygiene, declaration macros, and a closed `syntax/*`
compile-time query vocabulary.

**Runtime.** An `mmap`-backed bump allocator emitted by the backend, no
libc. Reclamation is the arena scope — `__axiom_arena_mark` /
`__axiom_arena_reset` — measured at **291× less memory** than the same
binary unscoped at ten thousand connections (`scripts/check-net.sh`,
run 2026-08-24: 512 KiB scoped against 149,328 KiB). The exact ratio
moves with the machine — the run recorded in that script's own header
reads 313× — so what the gate asserts is a **floor of 50×**, not either
number.

**Targets.** `darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`,
`linux-x86_64`. Three are executed in CI; **`darwin-x86_64` is
assembled and compared but never run** — no runner for it exists.

**Standard library.** Eighteen modules over the syscall primitives:
`Pre`, `Mem`, `Str`, `Utf8`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`,
`Path`, `IO`, `Show`, `Err`, `Json`, `Rpc`, `Job`, `Ffi`, `Agent.Tags`.
TCP sockets, readiness over `kqueue` *and* `epoll` behind one API, and
signals delivered into the event loop with no handler.

**FFI, both directions.** `extern` blocks bind Rust; `--emit-staticlib`
makes every `pub fn` a C symbol. Freestanding is tiered and measured: a
program with no `extern` imports **0** symbols, one bound to a `no_std`
crate also **0**, one bound to a `std` crate **188** — counted on
`darwin-aarch64`, which is the platform those three numbers are
literal on; the gate enumerates permitted symbols per platform rather
than forbidding all of them (`scripts/check-ffi.sh`).

**Tooling.** `build`, `check`, `run`, `emit-llvm`, `fmt`, `explain`,
`symbols`, `repl`, `lsp`, `version`. Diagnostics render as human text,
AXDL, or JSON; 57 codes, each constructed, explained and listed, gated
in both directions.

### Added in this release

- **`symbols --calls`** — the call graph the effect fixpoint already
  resolves, printed as `#calls=` beside `#effects=`. Gated by
  `scripts/check-agent-calls.sh` on four properties: no callee's effect
  escapes its caller, every inferred effect row carries an edge, every
  IO reaches a syscall or an `extern`, and the default stream is
  unchanged.
- **`VERSION` and `scripts/check-version.sh`** — one number, and a gate
  asserting that all eleven sites and the built compiler agree with it.
  Each site is named with the count it must yield, so a file that
  quietly stops stating the version at one of them is a failure rather
  than a smaller sweep, and the negative probe mutates every named file
  and requires every extractor to read the mutation back.
- **A release workflow and an installer** —
  `.github/workflows/release.yml` cuts a release when a `v*` tag is
  pushed, refusing to build until the tag, `VERSION` and the number the
  freshly built compiler prints are the same string; `scripts/install.sh`
  downloads an archive, verifies its SHA-256, and then compiles a
  program that *imports the standard library* through a bare-name
  `PATH` invocation before reporting success. Neither publishes a
  `darwin-x86_64` binary, because no runner has ever executed one.
  `CONTRIBUTING.md` has the procedure.
- **A shared compiler artifact for CI** (`AXIOM_AXC`) — eighteen gates
  rebuilt the same byte-identical compiler; now one step builds it. The
  cache is content-addressed, so an ablation of `self_host/` still
  invalidates it. `scripts/check-gate-lib.sh` proves that.

### Fixed

- **An installed compiler could not find its own standard library.**
  `argv[0]` is not `current_exe`, so a compiler found on `PATH` and
  invoked by its bare name — `export PATH=…/bin:$PATH`, then `axiom`,
  which is exactly what the installer sets up — resolved
  `<exe>/../stdlib` against the *working directory*. The first program
  a new user wrote that imported anything answered `AX5001 cannot
  resolve import IO` on a completely correct installation. The bare
  name is now resolved the way the shell resolved it: the first `PATH`
  entry holding a file of that name, and that entry only — resolving
  through *every* entry was the first attempt, and it let a compiler
  whose `stdlib/` had been deleted keep working against a different
  installation's. Gated in both directions by
  `scripts/check-driver.sh`, which installs a layout, resolves through
  it by bare name, and requires the same invocation to fail once
  `stdlib/` is removed.
- `netAccept` discarded the peer address and `bind` passed a literal
  addrlen, so IPv6 was impossible.
- An unhandled effect exited 71 in silence; a worker could vanish with
  nothing on stderr.
- A Rust panic and a division by zero both exited 72, so the two were
  indistinguishable by status.
- `+`, `-` and `*` wrap silently and had no checked counterpart;
  `addChecked` / `subChecked` / `mulChecked` now exist.
- `308-poll-readiness` asserted that two connects produce one poll wake
  carrying two events. No kernel promises that; it failed under load.

### Known limitations, stated plainly

These are measured, not suspected. They are why this is `0.2.0`.

- **No debug information.** No DWARF, no line tables, `-g` is never
  passed. A dying process yields an exit status and at most 35 bytes.
  A SIGSEGV yields nothing.
- **No fault containment.** There is no unwinding and no `catch`;
  handlers are tail-resumptive. A fault's only containment is the
  worker process dying.
- **Types share one flat namespace.** Two modules declaring the same
  type name collide **silently**, and the collision reaches the answer.
  Measured 2026-08-24: two modules each declaring `(struct Point (x :
  Int) (y : Int))` and `(struct Point (y : Int) (x : Int))`, a
  constructor in the second building `(y=10, x=20)`, and `p.x` read
  back. `check` says `OK`; the program answers **10**, having read the
  first module's layout, where **20** is correct. Note that a *value*
  name collision is caught — two modules exporting the same
  constructor is `AX3014 ambiguous name` — so the hole is specific to
  the type namespace. This is the single worst defect in the release.
- **`AX3040` is a known unsoundness that ships as a warning.** It
  cannot yet be promoted, because it cannot tell an unsound cast from a
  legitimately diverging function
  (`tests/diagnostics/351-diverging-tyvar.ax`).
- **Error handling is mid-migration.** `Err.ax` ships `Result`, but the
  standard library still signals failure with `-errno` sentinels at 84
  sites over 12 files, and a fallible call leaks the block it returns.
  Counted 2026-08-24, the way [docs/error-model.md](docs/error-model.md)
  §1.2 says to count them: `grep -cE "errno|sentinel|\(- 0 1\)"` across
  `stdlib/*.ax`.
- **No `axiom test`.** There is no test runner a consumer can use
  outside this repository.
- **No package management.** Dependencies are `$AXIOM_PATH`, a
  colon-separated environment variable. No manifest, lockfile or
  registry.
- **No throughput or latency gate.** Every timing gate asserts a ratio,
  deliberately, to avoid runner flakiness — which leaves rate
  uncovered.
- **No Windows, containers, or musl story.**

### Compatibility

`0.2.0` makes no compatibility promise. Language constructs have been
*removed outright* rather than deprecated. Four of them refuse loudly:
`union`, `region` and `foreign` are `AX2004` naming what happened to
them, and `--gc` is a driver refusal that says the tracing collector
belonged to the retired Rust implementation.

Two do not, and saying otherwise would be the kind of claim this file
exists to avoid:

- `begin` is an ordinary `AX3001 undefined variable begin`. It names no
  replacement and reads like a typo rather than a removal.
- A **sized integer type is not refused at all**. `i32`, `u64` and the
  rest are lowercase, so this compiler reads them as *type variables*:
  `(:: f (-> u64 Int))` checks **OK** and silently generalises, and
  `(:: main i32)` is a warning about an unwitnessed type variable
  (`AX3040`) rather than a word about sized integers. A program ported
  from a language that has them compiles and means something else.

A deprecation policy and a compatibility gate over the symbol stream
are the next release's work; until they exist, pin a commit.
