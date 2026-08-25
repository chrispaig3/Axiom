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

## Unreleased

### Added

- **A shipped binary names the tree it was built from.** `axiom
  version` printed `axiom (self-hosted) 0.2.0` and nothing else, so two
  builds of two *different* trees at one version were the same binary
  to whoever held one — the half of the roadmap's P6 that
  `scripts/check-version.sh` has named in its own header since it was
  written. It now prints a **build id**: twelve hex characters of a
  hash over every `.ax` byte under `self_host/` and `stdlib/`, plus the
  commit and a `-dirty` flag when git can answer. The hash is the
  identity and the commit is the convenience, because a commit cannot
  distinguish two builds of one commit with an edit in the working
  directory and the hash can.

  The value is an ordinary string literal that
  `scripts/build-stamped.sh` rewrites **in a copy** of `self_host/`,
  never in the tree. The three alternatives were each priced and
  refused in `self_host/build.ax`: a compile-time environment read is a
  new built-in and therefore a seed window; a linker-injected symbol is
  an ungrounded `declare`, which `driver.ax` refuses at `AX4004` and is
  right to; stamping the archive answers for a release and not for the
  binary that outlives it. Because the rewrite happens in a copy and
  behind a script the ladder never runs, `check-bootstrap.sh` and
  `check-reproducible.sh` see nothing new — an unstamped build says
  exactly `unstamped`, which is not a value any stamped build could be
  confused with.

  `scripts/check-build-id.sh`, 12 checks, and the negative probe is
  the one that matters: one changed byte under `self_host/` or
  `stdlib/` must move the id, or the id names nothing. The release
  workflow now refuses to ship a binary reporting `(build unstamped)`.

- **The seed is the emission of source in this history, and here is the
  regeneration that says so.** `scripts/check-seed-provenance.sh`
  resolves the commit that last wrote `bootstrap/`, requires that
  commit's `self_host/**.ax` and `stdlib/**.ax` to hash to
  `bootstrap/STAMP`, and then regenerates all four seeds from them and
  requires byte-identity: **139,638 lines each, on all four targets**.
  Until this, nothing in the repository related the 5 MB under
  `bootstrap/` to any source in either direction — `SHA256SUMS` is a
  hash and a file committed together, which is a corruption check by
  its own README's words, and `check-bootstrap.sh` asks only whether
  the seed can BUILD this source.

  It found that `bootstrap/STAMP` was **wrong, by construction rather
  than by accident**. It recorded `git rev-parse HEAD` from inside
  `reseed.sh`, and the routine reason to reseed is that `self_host/`
  has just changed — so the tree is dirty when it runs, and HEAD is the
  commit *before* the one that carries the seed. It named `ee0e4e1`;
  the seed is `93a74e5`'s emission, and regenerating from `ee0e4e1`
  differs by **1,532 lines** — the seed defines `parser$nodeBName` and
  `parser$nodeCName`, which that commit's source does not declare.
  Nothing read the line, so nothing said so. `STAMP` now records a hash
  of the source bytes, which cannot be wrong at the moment it is
  written, and the gate derives the commit the other way round.

  This does **not** answer Ken Thompson, and `bootstrap/README.md` says
  why at length: the compiler doing the regenerating is itself
  seed-descended. What it converts is a 5 MB artifact you had to trust
  into a build product of `.ax` files you can read.

- **`axiom test`, and assertions to write tests with.** A test is a
  top-level function whose name begins with `test` and which takes no
  parameters; the runner appends a `main` to the file's own bytes and
  arms one recovery point per test, so a failed assertion, an unhandled
  effect, an allocation failure and a division by zero each end ONE
  test and answer with a status (`docs/error-model.md` `ERR-REC-6` —
  this is that mechanism's first consumer, and it needed no new
  machinery). `stdlib/Test.ax` is the assertion surface: `assertEq`,
  `assertNe`, `assertStrEq`, `assertTrue`, `assertFalse`, `testFail`,
  and the `Assert` effect a failed one performs.

  Nothing is skipped in silence, which is a runner's characteristic
  defect: a file that declares no test is a failure rather than an
  empty success, and a `test`-named function that takes parameters is
  refused by name rather than passed over. The `;@axiom:test` AXTAG was
  tried first and refused for the same reason — a tag above the `::`
  signature is dropped when the `fn` carries one of its own, so
  `symbols` reports `#effect=io` and no `#test` at all (probed
  2026-08-25), and a test that vanishes because its tag sat one
  declaration too high reads exactly like a passing one.

  `scripts/check-test-runner.sh` is the gate, and its negative probe is
  the part worth the cycles: every `assertEq` in the passing fixture is
  mutated in turn and each mutant must exit 1 with a `FAIL` line — five
  observed red. It also checks the report against a list `grep` derives
  from the fixture's own bytes, so a runner that ran four of five tests
  fails against a source outside the compiler.

- **The containers own what they hold, and can be freed.** The shape
  word gained an **array form** — one bit saying every payload word of a
  block is a handle — which is the only encoding that can describe an
  element buffer: the record form's bitmap holds 47 words and `Intern`'s
  string vector is 64 words before a single string is interned.
  `vecNewRef`, `mapNewRefVals` and `internNew` own their elements;
  `vecFree`, `mapFree` and `internFree` hand them back, four levels deep
  (`docs/memory-model.md` `MM-LIFE-2h`;
  `tests/stdlib/404-container-reference-maps.ax` answers 255, eight
  probes at one bit each). Containers built and dropped in a loop with
  no arena reset now hold **1,360 KiB flat** where the same program one
  word different grows to 61,344 (`scripts/check-container-reclaim.sh`).
- **A bounded live set has bounded memory.** The acceptance property
  above that one, and the readiness plan's P3 stated so it can be
  falsified: a 256-entry window over **2,000,000** inserts holds 1,392
  KiB, unmoved across a hundredfold in iterations, against 34,368 KiB
  with the eviction removed (`scripts/check-steady-state.sh`,
  `MM-LIFE-2i`).

- **A dying program names the frames it died in.** Three pieces, none of
  them debug metadata: `"frame-pointer"="all"` on the module's one
  attribute group, a table of address-beside-name over every symbol the
  module defines, and a walker that resolves each return address at
  `ra - 1`. All emitted text, so `-g` is still never passed, there is
  still no `!dbg` anywhere, and the committed seed still compiles
  `self_host/` unchanged. An allocation failure now reads:

  ```
  axiom: out of memory (mmap failed)
  axiom: backtrace (most recent call first)
    at __axiom_out_of_memory
    at axiom_alloc
    at Mem$memAlloc
    at __axiom_user_main
    at main
  ```

  Cost, measured 2026-08-24 at `--opt 2` on darwin-aarch64: a
  hello-world binary goes 65,704 → 82,536 bytes, the compiler itself
  1,452,688 → 1,471,520 (+1.3%), and `axiom check self_host/main.ax`
  is unchanged at 0.51 s. `scripts/check-backtrace.sh` pins the whole
  trace byte for byte at `--opt 0`, cross-checks every name it prints
  against `nm` at every optimisation level, and ablates the attribute
  per target — it discriminates on all four.

  What it deliberately is not: line numbers. Function-level frames
  answer most of production triage, and a line table is the part that
  needs real debug records.

### Fixed

- **A 256-entry cache grew without bound.** `mapNeedsGrow` reads `used`,
  and `used` counts tombstones, so a table under insert-and-remove churn
  reached the load factor with a live set that had not moved and
  doubled itself for entries that did not exist: 256 live keys, roughly
  524,288 slots, 10 MB. `mapRehashCap` now rehashes at the same capacity
  when the live entries would sit at a quarter load or less, which drops
  every tombstone and grows nothing — 10,048 → 1,392 KiB. Every other
  gate in the tree was green across it, including the container gate,
  which frees its containers whole and never removes an entry from one.

- **The shared CI artifact was trusted on a stamp nobody could fail.**
  `scripts/build-shared-axc.sh` claimed the artifact equals a fresh
  build and checked it by calling one pure function twice in one
  process over an unchanged tree. It now builds the compiler a second
  time and compares the IR both emit for `self_host/main.ax` — 144,818
  lines, byte for byte. (Not the binaries: the macOS linker stamps a
  UUID into every Mach-O, so two builds of one source differ by ~11 KB
  no compiler chose.)
- **`AXIOM_AXC` pointing at a compiler with no stamp went green.**
  `gate_build_axc` treated "no stamp beside the artifact" and "a stamp
  that no longer matches" as one event, and both fell through to
  rebuilding. So `AXIOM_AXC=.axiom-bin/axiom` — a real, working, seed
  compiler — was silently ignored while every gate reported success,
  having quietly paid the build the variable was set to avoid. The two
  are now separated by what the stamp says: a stale stamp rebuilds (as
  `check-fmt.sh` requires, since it runs its inner gates against a copy
  of the tree), and an absent one is refused.
- **Three files stated three different counts of one countable fact.**
  How many gates call `gate_build_axc` was written down as seventeen,
  eighteen and nineteen across six places, none of them swept by
  `check-doc-drift.sh` because they live in `scripts/` and in the
  workflow. The answer is eighteen, and `check-gate-lib.sh` now
  recomputes it and refuses any of the six that says otherwise. It
  found its first drift while being written, in its own comment.

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
- **A shared compiler artifact for CI** (`AXIOM_AXC`) — twenty-nine gates
  rebuild the same compiler; now one step builds it, and builds it
  twice to measure that the artifact emits the same IR as a fresh
  build. (Not the same *bytes*: the macOS linker stamps a UUID into
  every Mach-O, so two builds of one source differ by ~11 KB no
  compiler chose.) The cache is content-addressed, so an ablation of
  `self_host/` still invalidates it, and a path with no stamp beside it
  is refused rather than ignored. `scripts/check-gate-lib.sh` proves
  all three.

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
  A SIGSEGV yields nothing. (Since `0.2.0`: a trap now also prints a
  function-level backtrace — see Unreleased. Line numbers and SIGSEGV
  are still uncovered.)
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
  outside this repository. (True of `0.2.0`, and closed after it — see
  Unreleased.)
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
