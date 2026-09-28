# Security threat analysis

This page applies STRIDE (spoofing, tampering, repudiation, information
disclosure, denial of service, elevation of privilege) to the trust
boundaries of Axiom's compiler and runtime. The seed's own supply chain
has a gated table in [bootstrap/THREATS.md](../../bootstrap/THREATS.md),
and the reporting process and scope are in
[SECURITY.md](../../SECURITY.md). This page covers the rest and links
to those instead of restating them.

Each row names the boundary, the threat, the controls with their
evidence, and what remains. A row with no control is a stated gap.

## Boundaries

1. Source in: the `.ax` text the compiler reads, which may be untrusted,
   such as a fetched dependency or an agent's output.
2. Compiler to toolchain: the IR handed to `opt`, `llc`, `cc` and
   `ld.lld`, which run as the user.
3. Seed and toolchain in: `bootstrap/*.ll`, the host LLVM and C
   toolchain, and the Rust crates on the FFI side.
4. Program at run time: the emitted runtime, the standard library, and
   any input the program reads.
5. FFI: foreign code linked into the program, and hosts that call in.
6. Between bindings: forked processes and threads that share pages.
7. Distribution: the installer and the release archives.

## Threats

| ID | Boundary | STRIDE | Threat | Controls and evidence | Gap |
|---|---|---|---|---|---|
| TH-1 | 1 | Denial of service | A crafted source crashes or hangs the compiler | The nesting limit `AX2005` and the expander budget `AX3024`; seeded fuzzing of `check` with crash, trap and hang detection (`scripts/check-fuzz.sh`: 600 mutants per CI run, 6,000 with `--long`) | `build`, `fmt`, the LSP and the REPL aren't fuzzed. Compile-time resource exhaustion beyond the two limits is out of scope (SECURITY.md) |
| TH-2 | 1 | Tampering | A crafted source makes the compiler emit code other than it means | HZ-C1's controls ([hazards.md](hazards.md)) | No miscompilation oracle |
| TH-3 | 1 | Spoofing | A dependency claims effects or restrictions it doesn't keep | Effects are checked against bodies (`AX3010` and `AX3042` are errors) and restrictions are refused (`AX3049`). A forged compiler-owned AXTAG key is shadowed, because the compiler's keys come after the author's tags | A dependency's `effect(unsafe)` functions are trusted code. List them with the resource report |
| TH-4 | 1 | Tampering | `axiom fetch` builds against a checkout that isn't the manifest's URL | In SECURITY.md's scope; `scripts/check-driver.sh` round-trips `fetch` offline through `file://` checkouts | The round trip is a functional check, not an adversarial one |
| TH-5 | 2 | Elevation of privilege | IR injection: a string literal or name that breaks out of its IR context | The emitter quotes every name LLVM doesn't accept bare (`@"a->b!"`), and an identifier can't contain `"` or `\` (`AX1001`), so a name can't close its quotes. Every byte of a string literal is written as a `\XX` escape, so no literal byte is ever IR syntax | Not fuzzed at the emit stage beyond `llc` accepting what `check` accepted |
| TH-6 | 3 | Tampering | A malicious seed or toolchain (trusting trust) | Seed provenance, lineage replay to a Rust anchor, and the supply-chain table ([bootstrap/THREATS.md](../../bootstrap/THREATS.md)) | `llc`, `cc`, `rustc` and the anchor's author are the trust base |
| TH-7 | 4 | Tampering | Memory corruption driven by a program's input | Bounds traps (77 for `vecGet` and `vecSet`); the allocator's size refusal (R-A5); release-path integrity (R-A7); count exhaustion (R-A9); the region escape refusals (`MM-RGN-*`) | `cast`, raw loads and stores, and `__call_word` are unsafe and unchecked. Integer arithmetic wraps unless a body claims `restrict(no-wrap)`, which is lexical |
| TH-8 | 4 | Denial of service | Input that drives unbounded allocation or deep recursion | `--heap-ceiling`; the profile's RP-1, RP-5 and RP-7 | Hosted programs outside the profile are unbounded by default |
| TH-9 | 4 | Information disclosure | Freed memory handed out still holding a previous owner's bytes | The handout scrub (`MM-ALLOC-6`, with the model's `scrub` witness) and the slab scrub on reset (`MM-LIFE-2e`, witness `reset`) | Memory never returns to the OS |
| TH-10 | 4 | Tampering | Path traversal from `Http`'s static root, or ambiguous request framing | In SECURITY.md's scope; `scripts/check-http-scan.sh` and `scripts/check-net.sh` | None stated |
| TH-11 | 5 | Elevation of privilege | Foreign code breaking the runtime's invariants, such as writing a handle or calling from a second thread | Host FFI needs `AxRuntime`, so one thread owns the runtime; raw words appear only inside `unsafe` in generated Rust (`scripts/check-ffi.sh`) | Foreign code is outside every analysis here. RP-3 refuses it in the profile unless named. `MM-FFI-7` (a captured `Foreign`) is unchecked |
| TH-12 | 6 | Tampering | One binding corrupting another's state | Forked bindings are isolated by default; thread captures are refused (`AX3064`, R-C1); atomics are seq_cst; tasks return bytes, not handles (`MM-PAR-13`) | Words shared through `MAP_SHARED` pages, and `Int` handles to channels, mutexes and tokens, are programmer obligations (`MM-PAR-8`) |
| TH-13 | 6 | Denial of service | A binding killed while holding a lock blocks every other binding | The mutex names its holder and poisons itself when the holder dies (`MM-PAR-11`); every blocking call has a timed form (`MM-PAR-12`) | A channel's lock doesn't notice a dead holder. After a sweep, only `chanFree` is safe on it (`MM-PAR-10`) |
| TH-14 | 6 | Denial of service | A task that never answers holds its pool | Per-task deadlines enforced by `SIGKILL` and a reap; cancellation tokens with a grace period (`MM-PAR-13`, `scripts/check-task.sh` §3) | A pool with no deadline waits as long as its slowest task |
| TH-15 | 7 | Tampering | A tampered release archive | `install.sh` checks the SHA-256 against the published checksum file (`scripts/check-install.sh` ablates the comparison); release binaries carry a build id over every `.ax` byte | The checksums and the archives come from one origin, and nothing is signed |

## Out of scope

A system's own threat model belongs to the system: its network
exposure, its update channel, its key handling, and physical access to
a device. This page covers what the compiler and runtime contribute,
as one input to that model.
