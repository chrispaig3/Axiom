# Recovery and audit follow-through, 2026-09-27

## Scope and baseline

Recovery began from clean `trunk` at `d47998b000b096a19a822020d3c477b442a148cf`,
then also the recorded `origin/trunk`. The latest Claude session was
`09e99691-0dfa-432c-b059-beb6bda366a5`. Its salvage agent
`a249c404652512593` stopped at its session limit while investigating whether
its attempted MIR cherry-pick was already integrated. Its log and the
worktree agree; this report does not infer progress from a summary alone.

The recovery inventory below is read-only: no worktrees, branches, or unique
commits were deleted. Process liveness could not be determined because this
session could not run `ps`; clean status is not evidence that a checkout is
unused. An aborted duplicate cherry-pick, if performed during integration,
is reported separately from this initial inventory.

The previous audit is `axiom-audit/AUDIT.md` under the Codex visualization
artifact directory for this session. Its baseline was `560d45bb`, before the
fixes reviewed here. Finding identifiers F1–F11 below refer to that audit.

## Salvage inventory

The requested home-level directories `/Users/chris/.muse/worktrees` and
`/Users/chris/.claude/worktrees` do not exist. The actual recovery roots are
inside the repository: `.muse/worktrees` and `.claude/worktrees`.

All **12 Muse worktrees** were clean, with no staged, unstaged, or
non-ignored untracked changes. In the table, `subagent-` abbreviates the exact
shared directory prefix
`subagent-v2-01a0d7c6-ee03-7a21-9767-a53bec88669e-` under
`/Users/chris/.axiom/.muse/worktrees/`.

| Worktree | HEAD / branch | Disposition and evidence |
|---|---|---|
| `parent-s4-verdict` | `7e2aa0e9`, detached | Already an ancestor of trunk. |
| `subagent-01a0d7ca-6201-78f0-a544-39e1e10b368d` | `c5291fc0`, `wip/lsp-introspection-core` | Already integrated as `48257856`; `git cherry` reports an exact patch equivalent. |
| `subagent-01a0d7ca-6681-7fd1-a3b3-f7ff4567ae3f` | `9a986c1e`, `wip/lsp-hierarchy-actions` | Already integrated as `91d7098e`; exact patch equivalent. |
| `subagent-01a0d7ca-6a11-79c0-bb82-609233a5a860` | `bb747287`, `wip/website-docs-bloat` | Integrated as `53bde134`. All compiler, diagnostic, test, and semantic documentation changes have identical added/deleted hunks; only README and website line-count updates differ. Those counts have since been superseded. |
| `subagent-01a0d81a-325a-7ee0-a64d-5f28e293ff6e` | `60fa91be`, detached | MIR bitwise lowering already integrated as `df575059`; exact patch equivalent. |
| `subagent-01a0d81a-36ea-78a0-8409-dbe0959be1b0` | `60fa91be`, detached | Duplicate checkout of the preceding integrated commit. |
| `subagent-01a0dad7-f6f9-7962-bc71-09924101967d` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |
| `subagent-01a0dad7-faa0-71c1-ad95-b07ced9f994a` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |
| `subagent-01a0dad7-fe3b-7390-997e-e17b8e4333a8` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |
| `subagent-01a0dad8-018f-7153-b35f-dbb8869a37fe` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |
| `subagent-01a0dad8-04b7-7a60-a7cf-7cef8a4ff5e8` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |
| `subagent-01a0dad8-0800-7491-bdf2-6c098f9bf03e` | `139382b1`, detached | Already an ancestor of trunk; no local changes. |

The sole Claude worktree was
`/Users/chris/.axiom/.claude/worktrees/agent-a249c404652512593`, on branch
`worktree-agent-a249c404652512593` at `d47998b0`. It had an interrupted
cherry-pick of `df4bcd38`, with conflicts only in `CONTRIBUTING.md`,
`README.md`, `docs/status.md`, `scripts/check-effect-distribution.sh`, and
`web/src/data/site.ts`. It had no staged implementation changes or untracked
files.

That MIR implementation already landed as `79f7da50`. The original and
integrated commits have identical added/deleted implementation hunks,
including `typecheck.ax`, `explain.ax`, the MIR documentation, and tests.
At the recovery baseline, `self_host/mir.ax`, `mireval.ax`, `axir.ax`,
`scripts/check-mir.sh`, and all `140-while`/`141-for` fixture files are still
byte-identical to the source commit. Remaining differences are old census
updates and an effect-pin preimage. Reapplying the commit would restore
stale counts rather than recover a missing feature.

The nine other registered worktrees were clean:

| Worktree under `/private/tmp/` | HEAD | Disposition |
|---|---|---|
| `basecheck2` | `98b0be1f` | Ancestor of trunk. |
| `mir-while` | `df4bcd38` | Integrated as `79f7da50`, as established above. |
| `recount-443` | `44351428` | Ancestor of trunk. |
| `recount-old` | `cc0db27d` | Ancestor of trunk. |
| `recount-pre` | `b229afc7` | Ancestor of trunk. |
| `rgnwit2` | `7e2aa0e9` | Ancestor of trunk. |
| `scope-equiv` | `97c70fba` | Ancestor of trunk. |
| `scope-m3` | `560d45bb` | Ancestor of trunk. |
| `trunk-clean` | `481d99c6` | Benchmark change integrated as exact patch equivalent `e1b362ec`. |

All remaining local branch tips are ancestors of trunk. No unique useful
source change was identified for salvage. Commit ancestry alone would have
misclassified cherry-picked changes; the inventory also compares patches
and affected file contents. Original branches and worktrees remain
recoverable.

## Audit revalidation

The following dispositions are scoped to the original defects. Static
inspection of a correction is distinguished from executing its regression
suite. This does not certify every surrounding API or supported platform.

| Finding | Existing fix | Revalidated behavior and evidence |
|---|---|---|
| F1: safe Rust accepts raw owned handles | `ff911f48` | `self_host/rustbind.ax` and generated `rust/examples/host/src/hostlib.rs` make ownership-adopting `from_axiom` and raw-word wrappers unsafe; `(Vec Int)` arguments take typed `AxVecBuf` borrows. Raw-field `to_axiom` is unsafe too. `scripts/check-ffi.sh` contains compiler-error probes, legitimate controls, and ablations. Static review completed; execution status is listed below. |
| F2: equivalent installer prefix bypass | `e6bbdea0` | `scripts/install.sh` resolves physical directory identity before comparison, checks installation ownership, and validates a staged installation before replacing owned paths. `check-install.sh` covers equivalent spellings, symlinks, unrelated contents, upgrades, and failed probes, with destructive controls confined to scratch. Static review completed; execution status is listed below. |
| F3: static-file symlink escape | `65a35e07` | `httpServeFile` uses `sysOpenBeneath`; each relative component is opened descriptor-relative with `O_NOFOLLOW`, and intermediate components require directories. Root symlinks remain an explicit caller choice; links below the opened root are refused. `432-http-router.ax` covers outward file/directory links, inward links, and replacements between requests. This is not a concurrent filesystem stress proof. |
| F4: Rust host threading restriction unenforced | `ff911f48` | `AxRuntime::claim` uses a process-wide `OnceLock<ThreadId>`; every safe allocating constructor/generated call requires its thread-bound token. `AxVecBuf`, strings, and the token are not `Send`/`Sync`. The owner is permanent, including after its thread exits. FFI regressions cover safe misuse and a second thread's failed claim. |
| F5: dependency URL slug collisions | `7b4ff8cb` | `pkgDepKey` includes 128 bits of SHA-256 over the complete URL; `pkgVerify`/fetch also compare recorded origin. `check-driver.sh` changes between formerly colliding URLs and checks results 11 then 22, digest agreement, and wrong-origin rejection. This does not add revision pinning. |
| F6: failed clone accepted as present | `7b4ff8cb` | Fetch clones into a process-specific sibling, publishes via rename only after success, and validates existing origin. Driver regressions check repeated failure, recovery when the source appears, and refusal of an empty final checkout. This does not claim crash-durable storage or general concurrent-fetch coordination. |
| F7: ambiguous HTTP framing | `65a35e07` | All Content-Length values are checked under one strict decimal policy, field names use token validation, and invalid control bytes are rejected. Static review follows the public parser into these checks; the focused HTTP fixtures exercise small and ordinary buffer capacities. |
| F8: CI mentions counted as executions | `d246f2d6` | `ci-steps.py` parses job/step structure and narrow executable forms. Independent execution of `check-ci-coverage.sh` passed 13 checks, including 11 negative controls for missing/echoed/named/disabled/hidden-failure invocations and the original audit mutation. Nonliteral conditions are reported, not claimed always true. |
| F9: inaccurate Rust minimum | `a1f18c50` | Offline Cargo metadata confirms all eight workspace members inherit Rust 1.88. An independent Rust 1.88.0 locked/offline workspace check passed for all members except the archive-dependent host example. CI installs the declared minimum and the FFI gate exercises it. |
| F10: quadratic HTTP header scanning | `65a35e07` | `httpReadRaw` preserves a cursor and `httpHeadEndFrom` resumes with at most three bytes of overlap. `check-http-scan.sh` counts candidate positions and ablates resumption. No wall-clock speedup is claimed from source inspection. |
| F11: ratios below timing resolution | `3f6df419` | The benchmark retains samples, checks matching results, increases rounds, and requires positive adjusted time above startup cost and jitter before reporting a ratio. Five independent probes executed the actual embedded verdict code: zero, negative, and jitter-dominated cases were inconclusive without a ratio; valid within/over controls produced the expected verdicts. This validates verdict handling, not performance of the data structures. |

## Verification record

Independent commands executed during this recovery audit:

| Command or probe | Result |
|---|---|
| `bash scripts/check-ci-coverage.sh` | PASS: 13 checks, including all 11 negative workflow controls. |
| `cargo metadata --locked --offline --no-deps --manifest-path rust/Cargo.toml --format-version 1` plus assertions over every workspace member | PASS: all eight declare `rust_version` 1.88. |
| `cargo +1.88.0 check --locked --offline --manifest-path rust/Cargo.toml --workspace --exclude axiom-host` | PASS. Host excluded because it links an Axiom archive generated separately. |
| Extract and execute the embedded `bench-datastructures.sh` Python verdict function with five synthetic timing inputs | PASS: three inconclusive cases, one within-bound control, one over-bound control. No benchmark timing claim. |

Logs and probe results for these independent checks were retained under
`/private/tmp/axiom-recovery-audit-20260927/` during the session. That scratch
path is evidence storage, not a required repository dependency.

The installer, generated Rust, driver, and HTTP runtime regressions must be
reported from actual current-tree executions before treating their static
revalidation as a complete retest. Cross-platform runtime execution, live
network attacks, exhaustive fuzzing, and security certification are outside
this recovery audit. The final integration record may append additional
checks without changing what was established here.
