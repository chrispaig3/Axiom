# Axiom P1 Implementation Plan

**Status:** §1 prerequisites and §2 P1 blockers are **all complete** (2026-08-01 audit). P0 and P1 are done. Moving to P2.

**Critical path:** ~~Prerequisite correctness fixes → P1 (B2, B3, B1, ADT variants in parallel)~~ → **P2 (memory model + S1) ← WE ARE HERE** → P3 (macros, B4, concurrency) → P4 (self-hosting 2–5, HTTP) → P5 (LSP, fmt trivia).

---

## 1. Prerequisite correctness fixes — ALL DONE (2026-08-01)

All eight prerequisite fixes are implemented and tested:

| # | Fix | Status |
|---|---|---|
| 1.1 | **gen_lambda cursor restore** | DONE — both call sites save/restore `current_block` and `entry_block` |
| 1.2 | **ECast lowering** | DONE — `Expr::ECast` arm emits `IrInst::Cast` in `gen_expr_to_func_with_allocas` |
| 1.3 | **Cast widening** | DONE — `IrInst::Cast` codegen handles same-width, `sext`/`zext` widening, and `trunc` narrowing |
| 1.4 | **Nested PCon field offset** | DONE — recursive `gen_sub_pattern_checks` passes `field_offset: 8` |
| 1.5 | **Match-failure trap** | DONE — `IrInst::Unreachable` block inserted before merge_label in EMatch (2026-08-01) |
| 1.6 | **Argument evaluation order** | DONE — left-to-right evaluation via collection then sequential `gen_expr` |
| 1.7 | **Constructor tag collision** | DONE — `find_constructor` uses a single monotonic counter across all data types |
| 1.8 | **Unique alloca names** | DONE — `alloca_counter` serial number appended to every alloca name |

---

## 2. P1 — ALL DONE (2026-08-01)

All four P1 blockers are implemented and verified:

### 2.1 B2: Guaranteed tail calls — DONE

Full self-tail-call logic in `generator.rs`: arena mark/capture, arena reset + compact, parameter reassignment, and `Br` to entry. Simple tail-call fallback for non-self-recursive tail positions.

**Exit criterion met:** Tail loop at `-O0` completes without stack overflow.

### 2.2 B3: `Vec`, `Map`, `Intern` — DONE

All three modules exist in `stdlib/` and compile cleanly. Golden tests exist at `tests/stdlib/070-vec.ax`, `080-map.ax`, `090-intern.ax`.

**Exit criterion met:** Data structures compile and type-check; golden tests pass.

### 2.3 B1: Closures — DONE

`CallIndirect` IR instruction, closure record allocation with `AddrOf`, captured free variable loading from `_closure` record, and codegen lowering all implemented. Higher-order probe compiles and runs.

**Exit criterion met:** `apply2` compiles, runs, and returns correct result.

### 2.4 ADT struct variants — DONE

`ConFields::Named` in AST, `PConNamed` parsing, field-name validation in sema, named-field matching in `gen_sub_pattern_checks`, and `constructor_field_names` helper all implemented.

**Exit criterion met:** Struct-variant ADT compiles, matches exhaustively, field access works.

---

# Axiom P1 Implementation Plan

**Status:** P0, P1, and P2 are **complete** (2026-08-01 audit). Moving to P3.

**Completed:**
- P0: Green CI, union/region removed, Game of Life, tree-sitter, fmt bug fixed
- P1 (§1): All 8 prerequisite correctness fixes (lambda cursor, ECast, cast widening, PCon offset, ~~match trap~~, eval order, tag collision, unique allocas)
- P1 (§2): All 4 blockers (B2 tail calls, B3 Vec/Map/Intern, B1 closures, ADT struct variants)
- P2: Memory model (ArenaMark/Reset/Compact + tail-loop reset) and S1 (unboxed nullary constructors)

**Critical path:** ~~P0 → P1 → P2 →~~ **P3 (B4 namespacing + macro hygiene + concurrency) ← WE ARE HERE** → P4 (self-hosting + HTTP) → P5 (LSP, fmt trivia).

---

## 3. P3 — Current work

### 3.1 B4: Namespacing — PARTIAL

**Current state:** `EQualified(path, name)` parses but sema discards the module path. Two modules CANNOT both define `new` without collision. Selective import `(import Mod (a b))` provides filtering but no qualified access.

**Remaining work:**
1. Track which module each declaration came from in sema (add `module: String` to `FnInfo`, `DataInfo`, etc.).
2. Allow same-named declarations from different modules as long as they're not both imported into the same scope.
3. Implement module-qualified access: `Mod.name` resolves to `name` declared in `Mod`.
4. Update `check_duplicate_definitions` to permit same-named declarations from different modules.

**Exit criterion:** Two modules define the same name without collision when imported selectively; `Mod.name` access works.

### 3.2 Macro system — PARTIAL

**Current state:** Expansion pass before sema with pattern substitution works. `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3` macros. Cross-module macro import works. **No hygiene — no gensym/fresh-name generation, no scope sets.**

**Remaining work:**
1. **Hygiene:** Add scope/hygiene set to `Ident`. Teach name resolution to compare `(name, scope)` pairs.
2. **Gensym:** Fresh name generation for macro-introduced bindings.
3. **Expansion backtrace:** Add to `Diagnostic` so type errors in expanded code show the macro call chain.

**Exit criterion:** Hygiene test suite passes (the classic `swap!`/`or` tests); a macro-introduced binding does not capture user code.

### 3.3 Concurrency — PENDING

No work started. Depends on the memory model (done). Design in `docs/v1-roadmap.md §4.4`.

---

## 4. P3 — Macros, B4 namespacing, concurrency

These are ordered: macros depend on the memory model; concurrency depends on the memory model; B4 namespacing is independent but needed before the LSP.

### 4.1 B4: Namespacing

**What:** Imports merge declarations into one flat namespace. Two modules cannot both define `new`.

**Implementation:**
1. Proposal: module-qualified names `Mod.name` are the long-term goal, but for v1 a simpler approach is per-module scopes with explicit import lists (already partially supported via `(import Mod (a b))`).
2. The immediate fix is to allow same-named declarations in different modules as long as the importing module only brings in one of them.
3. Update `axiom-sema`'s `collect_declarations` and `check_duplicate_definitions` to track which module a declaration came from.

**Exit criterion:** Two modules define the same name without collision when imported selectively.

### 4.2 Macro system (tier 1, pattern-based)

**What:** `syntax-rules`-shaped pattern/template macros. Hygiene via scope sets. No compile-time evaluation of user code.

**Implementation:**
1. **Scope sets ( prerequisite for hygiene):** Add a `scope: usize` field to `Ident` in `axiom-ast/src/span.rs`. Teach name resolution in `axiom-sema` to compare `(name, scope)` pairs.
2. **Macro declaration syntax:** `(macro (name pattern ...) template ...)`.
3. **Expansion pass:** Run after parsing, before sema. Match input syntax against patterns, substitute template.
4. **Hygiene:** Fresh scope per expansion; free identifiers in templates resolve at definition site.
5. **Expansion backtrace:** Add to `Diagnostic` so type errors in expanded code show the macro call chain.

**Exit criterion:** `derive`-style macro generates working `Eq` instance; hygiene test suite passes.

### 4.3 Concurrency

**What:** Structured concurrency, arena-scoped, deterministic.

**Implementation:**
1. `parMap` and `spawn` primitives in `stdlib/`.
2. Each task gets its own arena; values moved across task boundaries are copied into the child arena.
3. Results combined in argument order (deterministic).

**Exit criterion:** `parMap` is order-deterministic; parallel module type-checking works.

---

## 5. P4 — Self-hosting phases 2–5 + HTTP

### 5.1 Self-hosting

Follow `docs/self-hosting.md` phases 2–5:
- Phase 2: Axiom lexer, golden-tested against Rust lexer.
- Phase 3: Axiom parser, golden-tested.
- Phase 4: Axiom IR + codegen, byte-identical `.ll` output.
- Phase 5: Axiom driver + bootstrap fixpoint (`stage2 == stage3`).

**Exit criterion:** `stage2 == stage3`; full test suite green under stage2.

### 5.2 HTTP library

**What:** Non-blocking HTTP, deferred until after concurrency and `Vec`/`Map` land.

**Implementation:**
1. Non-blocking syscalls (`epoll`/`kqueue`) as new `Sys` surface.
2. HTTP parser/builder in pure Axiom.
3. Event loop using concurrency primitives.

**Exit criterion:** HTTP server serves a request under load.

---

## 6. P5 — LSP + fmt trivia preservation

### 6.1 LSP

**What:** After self-hosting, reuse the Axiom frontend rather than reimplementing parsing.

**Exit criterion:** Completion and diagnostics in a real editor.

### 6.2 fmt trivia preservation

**What:** `fmt` currently cannot round-trip because the lexer discards comments.

**Implementation:**
1. Lexer records comment spans as trivia attached to the following token.
2. AST nodes carry optional leading/trailing trivia.
3. `fmt` re-emits trivia.
4. CI gate: `axiom fmt --check` passes on every file in the repo.

**Exit criterion:** `fmt` round-trips every file in the repo.

---

## 7. CI gates and negative tests

For every new capability:
- Add a **positive test**: the feature works.
- Add a **negative test**: the feature fails correctly when misused, and the test asserts the exact diagnostic code (`AX####`).

Apply the same discipline that caught the PIE relocation bug: every gate must have a verified negative case.

---

## 8. Suggested execution order

1. Complete §1 (prerequisite correctness fixes) — estimated ~1–2 days.
2. Start B2, B3, B1, and ADT variants (§2) in parallel — estimated ~2–4 weeks.
3. Landing S1 is part of B2/B1 work (nullary constructors interact with the allocator).
4. P2 memory model (§3) — estimated ~2–4 weeks (research risk).
5. P3 macros + B4 + concurrency — estimated ~3–4 weeks.
6. P4 self-hosting + HTTP — largest phase; treat as sequential.
7. P5 LSP + fmt — last.

**Do not parallelize P2–P5.** The dependency graph in `docs/v1-roadmap.md §1` is accurate; violating it is the fastest way to produce non-working code.
