# Axiom v1 Implementation Status

**Status:** P0, P1, P2, and P3 are **complete** (2026-08-01 audit). Currently working on **P4**.

**Critical path:** ~~P0 → P1 → P2 → P3 →~~ **P4 (self-hosting + HTTP) ← WE ARE HERE** → P5 (LSP, fmt trivia).

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

## P3 — ALL DONE

### 3.1 B4: Namespacing — DONE

**Current state:** `EQualified(path, name)` parses and sema resolves the module path. Two modules CAN both define `new` without collision. Selective import `(import Mod (a b))` works. Qualified access `Mod::name` resolves correctly, including through IR name mangling (`module$name` LLVM symbols).

**Completed work:**
1. Track module source in sema (`module: Option<String>` on `FnInfo`, `DataTypeInfo`, `DataConInfo`, `StructInfo`, `TypeAliasInfo`, `TraitInfo`) — done
2. Allow same-named declarations from different modules (`collect_declarations` checks `(name, module)` pair) — done
3. Module-qualified access: `Mod::name` resolves via `check_qualified_var`, filtering by module path — done
4. `check_duplicate_definitions` already compared `module_path` on AST Decls — done
5. IR mangling: `gen_function` emits `module$name` LLVM symbols; `fn_mangle_map` tracks bare→mangled mapping for unqualified EVar lookups; `EQualified` builds mangled name from path segments — done

**Exit criterion met:** Two modules define the same name without collision when imported selectively; `Mod::name` access works. All 175 tests pass.

### 3.2 Macro system — DONE

**Current state:** Expansion pass before sema with pattern substitution works. `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3` macros. Cross-module macro import works. **Hygiene implemented:** scope sets, gensym, and expansion backtrace on `Diagnostic`.

**Completed work:**
1. **Scope sets:** `Ident.scope: usize` field (default 0 for user code). Sema's local scope storage changed to `Vec<(String, usize, VarInfo)>`; `check_var` compares `(name, scope)` pairs. Function/constructor lookup ignores scope.
2. **Gensym:** Macro expander renames all binder sites (let vars, lambda params, match arms) to `__gensym_N` via `GENSYM_COUNTER`. References are renamed consistently. Template-originating Idents are marked with `TEMPLATE_MARKER` before substitution, then scoped to the expansion's scope value; user-substituted expressions retain scope 0.
3. **Expansion backtrace:** `Diagnostic.expansion_backtrace: Vec<String>` field added; `with_expansion_backtrace()` builder; AXDL renderer emits `&"call site"` entries.
4. `substitute` expanded to handle full expression tree (ELet, ELam, EMatch, ECond, etc.).
5. `expand_macros` updated to generate `EXPANSION_SCOPE` (atomic counter) per expansion.

**Exit criterion met:** Hygiene test passes (`or` macro's internal `temp` does not capture user's `temp`). All 175 tests pass. Existing Pre.ax macros (`when`, `unless`, `cond2`, `cond3`) continue to work.

### P3 — DONE

B4 namespacing and macro hygiene are complete. Both exit criteria met (175 tests pass).

### Concurrency — not a native feature

Concurrency is out of scope for the Axiom compiler and standard library. The
design in `docs/v1-roadmap.md §4.4` (structured, arena-scoped, deterministic,
no shared mutable state) is preserved as **guidance for a third-party
library**, but Axiom will not ship with native concurrency primitives, a
task scheduler, or `parMap` as a built-in.

Rationale: concurrency is a user-space concern. The memory model (arena
inference, linear types) provides the foundation — no data races are
constructible — so a library author can build a safe concurrency library on
top. Bundling one into the language would couple Axiom's release cadence to
concurrency design decisions that are better made independently.

---

## P4 — Current work: Self-hosting phases 2–5 + HTTP

### Self-hosting
Follow `docs/self-hosting.md` phases 2–5: lexer → parser → IR/codegen → bootstrap fixpoint.

**Exit criterion:** `stage2 == stage3`; full test suite green under stage2.

### HTTP library
Non-blocking HTTP. Does not require native concurrency — an event loop can
be implemented in user space with the existing primitives (syscalls, arena
allocation).

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
