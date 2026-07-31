# Axiom P1 Implementation Plan

**Status:** Ready for implementation. P0 is complete (green CI on all four targets, `union`/`region` removed, Game of Life gated, tree-sitter grammar verified, `axiom run`/`fmt` bugs fixed, `docs/v1-roadmap.md` written).

**Critical path:** Prerequisite correctness fixes → P1 (B2, B3, B1, ADT variants in parallel) → P2 (memory model + S1) → P3 (macros, B4, concurrency) → P4 (self-hosting 2–5, HTTP) → P5 (LSP, fmt trivia).

---

## 1. Prerequisite correctness fixes

Fix these first. They are correctness bugs in the existing compiler that make P1 work unreliable if left open.

| # | Fix | Location | What to change |
|---|---|---|---|
| 1.1 | **`gen_lambda` cursor restore** | `axiom-ir/src/generator.rs:520-594` | Save `self.current_block` before `gen_lambda` and restore it after. Without this, any IR emitted after a lambda in the same outer function is appended to the lambda's entry block, producing invalid LLVM. |
| 1.2 | **`ECast` lowering** | `axiom-ir/src/generator.rs:596` (`gen_expr_to_func_with_allocas` match) | Add an `Expr::ECast(inner, target_ty)` arm. Emit `IrInst::Cast` with the correct source value and target type. Currently `(cast I32 x)` parses, type-checks, and silently generates no IR. |
| 1.3 | **Cast widening** | `axiom-codegen/src/lib.rs:829-847` | `IrInst::Cast` currently always emits `trunc`. Add widening: if `target_ty` is wider than `src_ty`, emit `zext` (for unsigned/bool→int) or `sext` (for signed). The existing `Ret` widening (`i1` → `i64`) is the model. |
| 1.4 | **Nested `PCon` field offset** | `axiom-ir/src/generator.rs:386-394` | The recursive `gen_sub_pattern_checks` call for nested `PCon` passes `field_offset: 1`. It must be `8` (bytes). The docstring and the `EMatch` call site both say "1 * 8 = 8 bytes"; the recursive call regressed to `1`. This makes nested constructor patterns read from the wrong byte offset. |
| 1.5 | **Match-failure trap** | `axiom-ir/src/generator.rs:1041-1241` (`EMatch`) | After the last arm's check block, the `merge_label` currently loads from an uninitialized `result_alloca` if no arm matched. Sema guarantees exhaustiveness, but defensive codegen should emit `unreachable` at the merge label fallthrough (or a call to `axiom_panic`). |
| 1.6 | **Argument evaluation order** | `axiom-ir/src/generator.rs:731-743` | `EApp` currently evaluates args right-to-left (innermost first via the unwind loop, then `reverse()`). Change to left-to-right by collecting args in a vector first, then evaluating each in order. |
| 1.7 | **Constructor tag collision** | `axiom-ir/src/generator.rs:42-53` (`find_constructor`) | `idx * 100 + cidx` caps at 100 constructors per type and ~100 types before collision. Change to `idx * 10000 + cidx` (or use a module-level counter) to make collision practically impossible. |
| 1.8 | **Unique alloca names** | `axiom-ir/src/generator.rs` (all `format!("_alloca_{}", ...)` sites) | Ensure alloca names are unique within a function across params, let-bindings, match-arm variables, and nested-pattern variables. The current `_alloca_{name}` scheme collides when shadowing occurs in the same function body. Prefix with the block or a per-binding counter (e.g. `_alloca_{block}_{name}_{counter}`). |

**Validation for §1:** Add one integration test per fix that fails on the current binary and passes after the fix. Gate them in CI alongside the existing suite.

---

## 2. P1 — Close the blockers

These four items are genuinely parallel. None depends on another. Schedule them concurrently.

### 2.1 B2: Guaranteed tail calls

**What:** Axiom has no loop construct; iteration is recursion. At `-O0` each call costs a stack frame, capping loops at ~200k iterations. The fix is not `opt`-dependent tail-call promotion; it is the IR generator emitting a self-tail-call as a branch to the function entry.

**Implementation:**
1. Add tail-position analysis to `axiom-ir/src/generator.rs`: walk each function body and detect when the final expression of a function is a call to itself with the same or fewer arguments.
2. For a detected self-tail-call, emit a branch to the function's entry block after reassigning parameters from the new arguments (store into the parameter allocas).
3. Add a CI gate: `game_of_life/stress.ax` or a dedicated `tests/tail-call.ax` that runs a 10-million-iteration tail loop at `-O0` and asserts it does not segfault.

**Exit criterion:** `10^7`-iteration tail loop at `-O0` completes without stack overflow.

### 2.2 B3: `Vec`, `Map`, `Intern` in Axiom

**What:** The standard library has raw memory and strings, but no growable array, hash map, or string interner. The Rust compiler uses `HashMap`/`Vec` pervasively; Axiom needs them before self-hosting can proceed.

**Implementation:**
1. `Vec` in `stdlib/Vec.ax`: growable array over `(__alloc ...)`, with `vecNew`, `vecPush`, `vecGet`, `vecLen`.
2. `Map` in `stdlib/Map.ax`: open-addressing hash map with linear probing. Key and value are `Int` (pointer-width) for the first version; generic maps follow once struct variants land.
3. `Intern` in `stdlib/Intern.ax`: intern a string literal or `Str` and return a unique `Int` handle.
4. Golden tests in `tests/stdlib/` for each: insert/lookup/delete round-trips, collision handling, empty-map behavior.

**Exit criterion:** `10^5`-element insert/lookup within 2× of the Rust equivalent; all stdlib tests pass.

### 2.3 B1: Closures (function values that survive codegen)

**What:** `lambda` parses and type-checks, but `gen_lambda` emits a top-level function and returns a global name. Calling it through a variable produces `call @unknown(...)` — invalid LLVM. Free variables are not captured.

**Implementation:**
1. **Representation decision:** closure record = `HeapAlloc` block containing a function pointer and captured variables.
2. **IR changes:** Add `CallIndirect` to `IrInst` (function pointer + args). Add `Closure` record layout instructions or reuse `HeapAlloc` + `StoreOffset`.
3. **IR generator:**
   - `gen_lambda` allocates a closure record, stores the lambda's generated function pointer in slot 0, then stores captured free variables in slots 1..N.
   - When a lambda reference is used as a value (not immediately called), emit the closure record.
   - When calling a value whose type is a function type, emit `CallIndirect`.
4. **Sema changes:** In `check_expr` for `ELam`, compute free variables (names referenced from the enclosing scope). Type-check that they are in scope and mutable/linear as needed.
5. **CI gate:** Higher-order probe `(:: apply2 (-> (-> Int Int) (-> Int Int))) (fn (apply2 f x) (f (f x)))` compiles, runs, and returns the correct result.

**Exit criterion:** Higher-order probe compiles and runs; closure capture tested.

### 2.4 ADT struct variants

**What:** `data` constructor fields are positional only. Rust-style `enum Shape { Circle { r: f64 } }` has no Axiom equivalent. This is the ADT revision item.

**Implementation:**
1. **Parser:** Allow named fields in `data` constructors: `(data Maybe (a) (Nothing) (Just { value : a }))`.
2. **AST:** Extend `DataCon` with an optional `fields: Vec<Field>` (named) alongside or instead of positional types.
3. **Sema:** Type-check named constructor fields; check that pattern names match declaration names.
4. **Pattern matching:** Support `(Just { x = v })`-style patterns. Bind by name.
5. **IR generator:** Store named fields at byte offsets computed from the declaration order (same as positional, just with name-based access in patterns).
6. **`set-field` / `.field` syntax:** Already exists for `struct`; reuse the same accessor syntax for `data` constructor fields.

**Exit criterion:** Struct-variant ADT compiles, matches exhaustively, field access works.

---

## 3. P2 — Memory model + S1

### 3.1 S1: Unboxed nullary constructors

**What:** `Nothing`, `Nil`, etc. currently heap-allocate a 1-word block. A nullary constructor is a constant and should be an immediate integer tag.

**Implementation:**
1. In `gen_construct`, when `args.is_empty()`, return `IrValue::Const(IrConst::Int(tag, i64_ty))` instead of `HeapAlloc`.
2. In `gen_expr_to_func_with_allocas` `EVar` arm, the existing nullary-constructor shortcut already returns `gen_construct` — it will automatically return the immediate.
3. In `EMatch` tag comparison, the tag is still loaded from offset 0; for immediate values, the load path is skipped (the match target is already the tag value).

**Exit criterion:** Nullary constructors compile to immediates; `game_of_life/` and all stdlib tests still pass.

### 3.2 P2: Memory model — arena watermark + tail-loop reset

**What:** The bump allocator never reclaims memory. A tail-recursive loop leaks linearly. The §2.2 measurement is 82× overhead at 2000 generations.

**Implementation (copy-at-boundary first, per roadmap §4.1):**
1. **Arena watermark:** Add `__axiom_arena_mark` and `__axiom_arena_reset` intrinsics (or Axiom primitives) that save/restore the bump pointer.
2. **Tail-loop reset:** In the IR generator, when emitting a self-tail-call (from B2), insert a watermark save before the call arguments are evaluated and a watermark restore immediately before the tail branch. Copy the new argument down to the watermark if it aliases the reclaimed region.
3. **Type-directed copy:** For the initial implementation, conservatively copy any argument that is a heap-allocated block (tagged pointer in the low bits, or a struct/ADT value). This is `O(live)` per iteration and sound.
4. **Linear types as the precision upgrade (later):** Once linear types are enforced, the no-alias obligation is proven by the type checker, and the copy can be skipped for linear arguments.

**Exit criterion:** `game_of_life/stress.ax` at 2000 generations uses O(1) memory in generation count: peak RSS within 2× of the same program at 20 generations (current ratio: 82×).

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
