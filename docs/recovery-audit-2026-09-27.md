# Recovery and audit follow-through, 2026-09-27

A salvage check of the repository's leftover worktrees and branches,
and a revalidation of the fixes for audit findings F1–F11. No unique
source change needed salvaging, and each finding has an existing fix,
revalidated within the limits noted below.

## Scope and baseline

Recovery started from a clean `trunk` at
`d47998b000b096a19a822020d3c477b442a148cf`, which was also the
recorded `origin/trunk`. The latest Claude session was
`09e99691-0dfa-432c-b059-beb6bda366a5`. Its salvage agent,
`a249c404652512593`, stopped at its session limit while checking
whether its attempted MIR cherry-pick was already integrated. Its log
and its worktree agree. This report doesn't infer progress from a
summary alone.

The inventory below is read-only: no worktrees, branches or unique
commits were deleted. This session couldn't run `ps`, so it couldn't
tell whether any process was still using a checkout. A clean status
doesn't prove a checkout is unused. If a duplicate cherry-pick was
aborted during integration, it is reported separately from this
inventory.

The previous audit is `axiom-audit/AUDIT.md`, in the Codex
visualisation artifact directory for this session. Its baseline was
`560d45bb`, before the fixes reviewed here. Findings F1–F11 below
refer to that audit.

## Salvage inventory

The requested home-level directories `/Users/chris/.muse/worktrees`
and `/Users/chris/.claude/worktrees` don't exist. The real recovery
roots are inside the repository: `.muse/worktrees` and
`.claude/worktrees`.

All **12 Muse worktrees** were clean, with no staged, unstaged or
non-ignored untracked changes. In the table, `subagent-` stands for
the shared directory prefix
`subagent-v2-01a0d7c6-ee03-7a21-9767-a53bec88669e-` under
`/Users/chris/.axiom/.muse/worktrees/`.

| Worktree | HEAD / branch | Disposition and evidence |
|---|---|---|
| `parent-s4-verdict` | `7e2aa0e9`, detached | Already an ancestor of trunk. |
| `subagent-01a0d7ca-6201-78f0-a544-39e1e10b368d` | `c5291fc0`, `wip/lsp-introspection-core` | Already integrated as `48257856`. `git cherry` reports an exact patch equivalent. |
| `subagent-01a0d7ca-6681-7fd1-a3b3-f7ff4567ae3f` | `9a986c1e`, `wip/lsp-hierarchy-actions` | Already integrated as `91d7098e`. Exact patch equivalent. |
| `subagent-01a0d7ca-6a11-79c0-bb82-609233a5a860` | `bb747287`, `wip/website-docs-bloat` | Integrated as `53bde134`. All compiler, diagnostic, test and semantic documentation changes have identical added and deleted hunks. Only README and website line-count updates differ, and later counts have replaced them. |
| `subagent-01a0d81a-325a-7ee0-a64d-5f28e293ff6e` | `60fa91be`, detached | MIR bitwise lowering, already integrated as `df575059`. Exact patch equivalent. |
| `subagent-01a0d81a-36ea-78a0-8409-dbe0959be1b0` | `60fa91be`, detached | Duplicate checkout of the integrated commit above. |
| `subagent-01a0dad7-f6f9-7962-bc71-09924101967d` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |
| `subagent-01a0dad7-faa0-71c1-ad95-b07ced9f994a` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |
| `subagent-01a0dad7-fe3b-7390-997e-e17b8e4333a8` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |
| `subagent-01a0dad8-018f-7153-b35f-dbb8869a37fe` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |
| `subagent-01a0dad8-04b7-7a60-a7cf-7cef8a4ff5e8` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |
| `subagent-01a0dad8-0800-7491-bdf2-6c098f9bf03e` | `139382b1`, detached | Already an ancestor of trunk. No local changes. |

The only Claude worktree was
`/Users/chris/.axiom/.claude/worktrees/agent-a249c404652512593`, on
branch `worktree-agent-a249c404652512593` at `d47998b0`. It held an
interrupted cherry-pick of `df4bcd38`, with conflicts only in
`CONTRIBUTING.md`, `README.md`, `docs/status.md`,
`scripts/check-effect-distribution.sh` and `web/src/data/site.ts`. It
had no staged implementation changes and no untracked files.

That MIR implementation had already landed as `79f7da50`. The
original and integrated commits have identical added and deleted
implementation hunks, including `typecheck.ax`, `explain.ax`, the MIR
documentation and the tests. At the recovery baseline,
`self_host/mir.ax`, `mireval.ax`, `axir.ax`, `scripts/check-mir.sh`
and all the `140-while` and `141-for` fixture files were still
byte-identical to the source commit. The remaining differences are
old census updates and an effect-pin preimage. Reapplying the commit
would restore stale counts, not a missing feature.

The nine other registered worktrees were clean:

| Worktree under `/private/tmp/` | HEAD | Disposition |
|---|---|---|
| `basecheck2` | `98b0be1f` | Ancestor of trunk. |
| `mir-while` | `df4bcd38` | Integrated as `79f7da50`, as shown above. |
| `recount-443` | `44351428` | Ancestor of trunk. |
| `recount-old` | `cc0db27d` | Ancestor of trunk. |
| `recount-pre` | `b229afc7` | Ancestor of trunk. |
| `rgnwit2` | `7e2aa0e9` | Ancestor of trunk. |
| `scope-equiv` | `97c70fba` | Ancestor of trunk. |
| `scope-m3` | `560d45bb` | Ancestor of trunk. |
| `trunk-clean` | `481d99c6` | Benchmark change integrated as exact patch equivalent `e1b362ec`. |

Every remaining local branch tip is an ancestor of trunk, and no
unique, useful source change was found to salvage. Commit ancestry
alone would have misclassified cherry-picked changes, so the inventory
also compared patches and the contents of affected files. The
original branches and worktrees are still recoverable.

## Audit revalidation

These dispositions cover the original defects only. Each row
separates static inspection of a fix from running its regression
suite. They don't certify every surrounding API or supported platform.

| Finding | Existing fix | Revalidated behaviour and evidence |
|---|---|---|
| F1: safe Rust accepts raw owned handles | `ff911f48` | `self_host/rustbind.ax` and the generated `rust/examples/host/src/hostlib.rs` make ownership-adopting `from_axiom` and raw-word wrappers unsafe. `(Vec Int)` arguments take typed `AxVecBuf` borrows. Raw-field `to_axiom` is unsafe too. `scripts/check-ffi.sh` contains compiler-error probes, legitimate controls and ablations. Static review is complete. For execution status, see *Verification record*. |
| F2: equivalent installer prefix bypass | `e6bbdea0` | `scripts/install.sh` resolves the physical directory identity before comparing, checks installation ownership, and validates a staged installation before replacing owned paths. `check-install.sh` covers equivalent spellings, symlinks, unrelated contents, upgrades and failed probes, and keeps its destructive controls inside scratch. Static review is complete. For execution status, see *Verification record*. |
| F3: static-file symlink escape | `65a35e07` | `httpServeFile` uses `sysOpenBeneath`. Each relative component is opened descriptor-relative with `O_NOFOLLOW`, and intermediate components must be directories. A root symlink stays an explicit caller choice, and links below the opened root are refused. The router's test covered outward file and directory links, inward links, and replacements between requests; it left with `Http` in 0.7.7, and `sysOpenBeneath` stays in `Sys`. This is not a concurrent filesystem stress proof. |
| F4: Rust host threading restriction unenforced | `ff911f48` | `AxRuntime::claim` uses a process-wide `OnceLock<ThreadId>`. Every safe allocating constructor and generated call requires its thread-bound token. `AxVecBuf`, strings and the token are neither `Send` nor `Sync`. The owner is permanent, even after its thread exits. FFI regressions cover safe misuse and a second thread's failed claim. |
| F5: dependency URL slug collisions | `7b4ff8cb` | `pkgDepKey` includes 128 bits of SHA-256 over the complete URL, and `pkgVerify` and fetch also compare the recorded origin. `check-driver.sh` switches between URLs that collided before the fix and checks results 11 then 22, digest agreement, and wrong-origin rejection. This doesn't add revision pinning. |
| F6: failed clone accepted as present | `7b4ff8cb` | Fetch clones into a process-specific sibling, publishes it by rename only after success, and validates an existing origin. Driver regressions check repeated failure, recovery once the source appears, and refusal of an empty final checkout. This doesn't claim crash-durable storage or general coordination of concurrent fetches. |
| F7: ambiguous HTTP framing | `65a35e07` | Every Content-Length value is checked under one strict decimal policy, field names use token validation, and invalid control bytes are rejected. Static review follows the public parser into these checks. The focused HTTP fixtures exercise small and ordinary buffer capacities. |
| F8: CI mentions counted as executions | `d246f2d6` | `ci-steps.py` parses job and step structure and narrow executable forms. An independent run of `check-ci-coverage.sh` passed 13 checks. They include 11 negative controls for missing, echoed, named, disabled and hidden-failure invocations, plus the original audit mutation. Nonliteral conditions are reported, not claimed to be always true. |
| F9: inaccurate Rust minimum | `a1f18c50` | Offline Cargo metadata confirms that all eight workspace members inherit Rust 1.88. An independent Rust 1.88.0 locked, offline workspace check passed for every member except the archive-dependent host example. CI installs the declared minimum, and the FFI gate exercises it. |
| F10: quadratic HTTP header scanning | `65a35e07` | `httpReadRaw` keeps a cursor, and `httpHeadEndFrom` resumes with at most three bytes of overlap. `check-http-scan.sh` counts candidate positions and ablates resumption. No wall-clock speedup is claimed from source inspection. |
| F11: ratios below timing resolution | `3f6df419` | The benchmark keeps samples, checks that results match, increases rounds, and requires positive adjusted time above startup cost and jitter before it reports a ratio. Five independent probes ran the actual embedded verdict code. The zero, negative and jitter-dominated cases were inconclusive, with no ratio. The valid within and over controls gave the expected verdicts. This validates verdict handling, not the performance of the data structures. |

## Verification record

These commands were run independently during this recovery audit:

| Command or probe | Result |
|---|---|
| `bash scripts/check-ci-coverage.sh` | PASS: 13 checks, including all 11 negative workflow controls. |
| `cargo metadata --locked --offline --no-deps --manifest-path rust/Cargo.toml --format-version 1`, plus assertions over every workspace member | PASS: all eight declare `rust_version` 1.88. |
| `cargo +1.88.0 check --locked --offline --manifest-path rust/Cargo.toml --workspace --exclude axiom-host` | PASS. The host is excluded because it links an Axiom archive that is generated separately. |
| Extract the Python verdict function embedded in `bench-datastructures.sh` and run it on five synthetic timing inputs | PASS: three inconclusive cases, one within-bound control, one over-bound control. No benchmark timing is claimed. |

Logs and probe results for these checks were kept under
`/private/tmp/axiom-recovery-audit-20260927/` during the session. That
scratch path stores evidence. The repository doesn't depend on it.

The installer, generated Rust, driver and HTTP runtime regressions
need results from real runs on the current tree before their static
revalidation counts as a complete retest. Cross-platform runtime
execution, live network attacks, exhaustive fuzzing and security
certification are outside this audit. The final integration record
may add more checks without changing what this record established.
