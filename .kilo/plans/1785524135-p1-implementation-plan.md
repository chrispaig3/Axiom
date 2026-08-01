# Axiom v1 Implementation Status

**Status:** P0, P1, and P2 are **complete** (2026-08-01 audit). Currently working on **P3**.

**Critical path:** ~~P0 → P1 → P2 →~~ **P3 (B4 namespacing + macro hygiene + concurrency) ← WE ARE HERE** → P4 (self-hosting + HTTP) → P5 (LSP, fmt trivia).

---

## P0 — ALL DONE

Green CI on all four targets; `union`/`region` removed with migration diagnostics; Game of Life Turing-completeness proof; tree-sitter grammar; `fmt` destructive-bug fixed (refuses instead of silently deleting comments).

**Evidence:** All 7 CI gate scripts green. 175 tests pass (`cargo test --release --all`).

---

## P1 — ALL DONE

### Prerequisite correctness fixes (all 8)
| # | Fix | Status |
|---|---|---|
| 1.1 | `gen_lambda` cursor restore | DONE |
| 1.2 | `ECast` lowering | DONE |
| 1.3 | Cast widening (same-width, sext/zext, trunc) | DONE |
| 1.4 | Nested PCon field offset | DONE |
| 1.5 | Match-failure trap | DONE |
| 1.6 | Argument evaluation order (left-to-right) | DONE |
| 1.7 | Constructor tag collision (monotonic counter) | DONE |
| 1.8 | Unique alloca names | DONE |

### P1 blockers (all 4)
| Item | Status |
|---|---|
| B2: Guaranteed tail calls | DONE — self-tail-call logic with arena mark/reset/compact |
| B3: Vec, Map, Intern | DONE — stdlib modules + golden tests |
| B1: Closures | DONE — CallIndirect, closure records, codegen lowering |
| ADT struct variants | DONE — ConFields::Named, PConNamed parsing, field-name matching |

---

## P2 — ALL DONE

Memory model: arena inference with `ArenaMark`/`Reset`/`Compact`, tail-loop arena reset. S1: unboxed nullary constructors (nullary constructors are immediates, not heap blocks).

**Exit criterion met:** `stress.ax` memory usage bounded.

---

## P3 — Current work

### 3.1 B4: Namespacing — PARTIAL

**Current state:** `EQualified(path, name)` parses but sema discards the module path. Two modules CANNOT both define `new` without collision. Selective import `(import Mod (a b))` works but no qualified access.

**Remaining work:**
1. Track which module each declaration came from in sema (add `module: String` to `FnInfo`, `DataInfo`, etc.)
2. Allow same-named declarations from different modules when not both imported into the same scope
3. Implement module-qualified access: `Mod.name` resolves to `name` declared in `Mod`
4. Update `check_duplicate_definitions` to permit same-named declarations from different modules

**Exit criterion:** Two modules define the same name without collision when imported selectively; `Mod.name` access works.

### 3.2 Macro system — PARTIAL

**Current state:** Expansion pass before sema with pattern substitution works. `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3` macros. Cross-module macro import works. **No hygiene — no gensym/fresh-name generation, no scope sets.**

**Remaining work:**
1. **Scope sets (prerequisite for hygiene):** Add `scope: usize` to `Ident` in `axiom-ast/src/span.rs`. Teach name resolution to compare `(name, scope)` pairs.
2. **Gensym:** Fresh name generation for macro-introduced bindings.
3. **Expansion backtrace:** Add to `Diagnostic` so type errors in expanded code show the macro call chain.

**Exit criterion:** Hygiene test suite passes (classic `swap!`/`or` tests); a macro-introduced binding does not capture user code.

### 3.3 Concurrency — PENDING

No work started. Depends on the memory model (done). Design in `docs/v1-roadmap.md §4.4`. Structured concurrency, arena-scoped, deterministic.

**Exit criterion:** `parMap` is order-deterministic; parallel module type-checking works.

---

## P4 — Self-hosting phases 2–5 + HTTP

### Self-hosting
Follow `docs/self-hosting.md` phases 2–5: lexer → parser → IR/codegen → bootstrap fixpoint.

**Exit criterion:** `stage2 == stage3`; full test suite green under stage2.

### HTTP library
Non-blocking HTTP, deferred until after concurrency.

**Exit criterion:** HTTP server serves a request under load.

---

## P5 — LSP + fmt trivia preservation

### LSP
Reuse self-hosted frontend for completion and diagnostics.

### fmt trivia preservation
Lexer records comment spans; AST carries trivia; `fmt` re-emits.

**Exit criterion:** `fmt` round-trips every file in the repo, gated in CI.

---

## CI gates and negative tests

For every new capability:
- Add a **positive test**: the feature works.
- Add a **negative test**: the feature fails correctly when misused, asserting the exact diagnostic code (`AX####`).

Apply the same discipline that caught the PIE relocation bug: every gate must have a verified negative case.
