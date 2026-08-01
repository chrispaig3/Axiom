# Axiom v1 Implementation Status

**Status:** P0, P1, P2, and P3 are **complete**. P4 self-hosting **in progress** — parser now handles all decl forms (data/struct/macro), codegen restructured with type registry + constructor support + multi-arg dispatch. One Vec stale-handle bug blocks codegen output >2 lines. HTTP deferred.

**Critical path:** ~~P0 → P1 → P2 → P3 →~~ **P4 (self-hosting) ← WE ARE HERE** → P5 (LSP, fmt trivia).

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

## P4 — Self-hosting (phases 2–5) ← IN PROGRESS

### Self-hosting

All 6 self-hosted source files compile and build. Parser now handles `data`, `struct`, and `macro` declarations instead of skipping them. Codegen restructured with type registry, multi-arg call flattening, and constructor support (heap alloc + GEP field stores). Known Vec stale-handle bug in `emitLine` prevents emitting >2 lines of LLVM IR without string corruption.

| File | Status | Description |
|---|---|---|
| `self_host/core.ax` | Done | Span, Token/TK, mkToken, accessors, TokenList |
| `self_host/lexer.ax` | Done | Character-at-a-time tokenizer with Vec output |
| `self_host/parser.ax` | Done | Recursive descent parser. **Now parses `data`, `struct`, `macro` decls.** Has `TAG_CTOR`/`TAG_FIELD` nodes for constructor metadata. |
| `self_host/typecheck.ax` | Done | Symbol table, name lookup, checkDecl dispatch (basic). |
| `self_host/codegen.ax` | Done | LLVM IR text emission. **Restructured:** type registry (`TypeEntry`), `scanDecls` pre-scan, multi-arg `EApp` flattening via `walkAppChain`, constructor emission via `emitAllocAndStore` with GEP-based field stores. Nullary data constructors return tag constants. Binary op/comparison dispatch unified in `emitCallN`. **Bug:** `emitLine` discards `vecPush` return value; after ~2+ pushes the CG[0] Vec handle goes stale, corrupting `renderCG` output. |
| `self_host/main.ax` | Basic | Compiler driver stub. Needs file/stdin I/O and CLI args. |

### Critical bug fixes — DONE

- **Heisenbug in `axiom-ir`** (commit `922ca12`): `IrValue::Tag` values were mishandled when passed as boxed arguments to constructors. The ALLOCA+StoreOffset path assumed only `IrValue::Const(Int)` would hit the nullary-tag boxing branch, but `IrValue::Tag` also needs boxing. Fixed `needs_box` to catch `IrValue::Tag(_)`, and `store_val` now matches both variants. Also added `tag_alloca_names` tracking for pattern-matched `Tag` bindings so tag-carrying allocas don't get incorrectly SSA-promoted.
- **Lexer cleanup:** Reduced `self_host/lexer.ax` from 40+ lines of dead code down to its minimal working core. Removed stale helper functions that were masking the heisenbug's root cause.

**Verification:** `test_heisenbug.ax` — lexing a single `)` character, extracting token kind/length into a data constructor for arithmetic — now returns correct deterministic output instead of intermittent garbage.

### Current blockers

1. **`emitLine` stale Vec handle:** `vecPush` may return a new handle when the Vec outgrows its initial capacity. `emitLine` calls `vecPush` inside a `{...}` block and discards the return value, so CG[0] points to a stale Vec after growth. Fix: capture the return value and `memSetWord cg 0` it. Same issue in `scanOne` for the types Vec at CG[3].
2. **Main driver:** `main.ax` hardcodes a test input. Needs stdin/file I/O.

### Next steps for P4:
- Fix Vec stale handle in `emitLine` and type registry paths
- Implement stdin I/O in `main.ax`
- Test codegen output for self_host source files
- Implement module import resolution
- Differential-test lexer/parser against Rust implementation on corpus
- Reach `stage2 == stage3` fixpoint

### HTTP library — deferred

Removed from P4 scope. Focus is on self-hosting the compiler toolchain.

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
