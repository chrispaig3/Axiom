# Self-Hosting Completion Plan

## Goal

Bootstrap the Axiom compiler: stage0 (Rust) compiles stage1 (Axiom), stage1
compiles stage2, stage2 compiles stage3. Verify stage2 == stage3 (byte-identical
LLVM IR). Then the Rust compiler can be removed.

## Current State (verified 2026-08-01)

- 1,608 lines of Axiom source in `self_host/`: core, lexer, parser (complete),
  typecheck (stubs), codegen (partial but functional for self-hosted subset)
- All files pass `axiom diagnostics=ai check` (Rust compiler type-checks the self-hosted code)
- The self-hosted compiler **compiles itself** — reads `self_host/main.ax`, emits
  deterministic LLVM IR
- Rust compiler: 13,010 lines, 175 tests, all targeting 4 platforms — **all pass**

## Completed Items (since last update)

### Rust Compiler Fixes (`axiom-ir/src/generator.rs`)

- **Terminator check in `emit_to_func`** (`generator.rs:2571-2578`): Skips non-alloca
  instructions when the current block already has a Br/CondBr/Ret terminator,
  preventing invalid LLVM IR with multiple terminators per block.
- **`current_block_has_terminator` helper** (`generator.rs:2598`): Returns true if
  the current block's last instruction is a terminator.
- **EIf handler fix** (`generator.rs:1747-1813`): After evaluating each branch,
  checks for existing terminator before appending Store/Br to merge label. When
  both branches terminate (both tail-calls), skips the merge block entirely.
- **gen_function Ret fix** (`generator.rs:545`): Checks for existing terminator
  before emitting Ret after the function body.

### Self-hosted Codegen (`self_host/codegen.ax`)

- **cast handling** (`codegen.ax:308-310`): `isCastName` uses `strEq` to detect
  `(cast Type expr)`. In `dispatchCall`, cast is treated as a no-op — evaluates
  the last argument and returns its value directly instead of emitting an
  undefined `@cast` call.
- **emitLet variable binding** (`codegen.ax:535-549`): Added symbol table
  (CG fields 6=`symnames`, 7=`symregs`). `emitLet` pushes name→register bindings.
  `emitVar` looks up let-bound variables via `lookupSym`/`lookupSymIn` before
  falling back to type-registry constructor lookup or `%name`.
- **TypeEntry nameLen** (`codegen.ax:13-33`): Added `nameLen` field to TypeEntry.
  `addType` precomputes `strLen(name)` during registration. `lookupType`
  precomputes `strLen(name)` once before entering the recursive lookup.
  `lookupByIdx` compares nameLen first (fast integer equality), then falls back
  to `==` pointer comparison for the final check.
- **emitVar constructor lookup** (`codegen.ax:254-286`): After checking the
  symbol table, `emitVar` calls `lookupType` on the CG's types Vec. If a
  nullary constructor (arity 0) matches, emits the tag constant instead of
  `%name`. Non-nullary constructors emit `0` as a placeholder.

### File I/O (`stdlib/Sys.ax`, `self_host/main.ax`)

- **readFile** (`Sys.ax:119-135`): Opens a file path with `sysOpenPath`, reads up
  to 64 KiB into an allocated buffer, wraps the result as a string, and closes
  the fd. Returns an empty string on any error.
- **main.ax** (`main.ax:21`): Uses `readFile` to load `self_host/main.ax` at
  runtime instead of a hardcoded test string.

## Verified Properties

- **Determinism**: The self-hosted compiler produces byte-identical LLVM IR
  across two successive runs (`diff` confirms identical output).
- **Self-compilation**: `./stage1` reads `self_host/main.ax` and emits valid
  LLVM IR for the `writeStdout` and `main` functions.
- **All Rust tests pass**: `cargo test --release` → 175/175 pass.

## Remaining Gaps

### 1. String comparison in recursive context (Rust compiler IR generator bug)

`strEq`/`strCmp` on values derived from `memGetWord(vecGet(...))` in a recursive
function causes a segfault. The workaround (`==` pointer comparison with `nameLen`
pre-filter) is correct for the current self-hosted source (which doesn't use
constructor applications in expressions), but will break when:

- Constructor applications in code (e.g., `(Just 42)`) are compiled
- The self-hosted source itself references constructors (e.g., `TK_LPAREN` used
  as values in `lexer.ax` / `parser.ax`)

**Root cause**: Axiom's Rust compiler IR generator bug — the specific pattern of
`strEq(memGetWord(vecGet(...)))` in a recursive function generates incorrect IR.

**Fix needed**: Debug and fix the IR generator, OR implement byte-level
comparison using `__load8` in a non-recursive helper that isolates the crash.

### 2. Import resolution

The self-hosted compiler parses `(import Module)` declarations but ignores them
(`emitDecl` only handles `TAG_D_FN`). All imported functions appear as
undefined external references in the generated IR. For IR diff validation
this is acceptable (deterministic externs), but for producing a linkable
executable, import resolution is needed:

- Search path resolution
- Recursive compilation of imported modules
- Symbol table merging across modules

### 3. Codegen features not yet implemented

| Feature | Used by self-host source? | Status |
|---|---|---|
| `data` constructor applications (e.g., `(Just 42)`) | Yes (lexer/parser constructors) | **Partial** — nullary ctors work via emitVar lookup; non-nullary ctors work via dispatchCall if lookupType returns match |
| `match` expressions | No (uses if chains) | **Not implemented** |
| Lambda `(fn (x) body)` | No (all functions top-level) | **Not implemented** |
| Multi-binding `let` | No (nested single lets) | **Not implemented** |
| Struct construction | Yes (Token, Span, ASTNode, etc.) | **Partial** — handled by dispatchCall→emitConstructor (needs lookupType to work) |
| String literal expressions | No (uses strFromLit) | **Not implemented** |

Note: The existing `dispatchCall`/`emitConstructor` code handles struct
construction and non-nullary constructors, but requires `lookupType` to
correctly match the constructor name. With the current `==` pointer comparison
workaround, constructor matching fails for different string objects (different
tokens of the same name). This means struct/constructor construction in
imported modules (like lexer.ax, parser.ax) would not emit correctly if those
were being compiled by the self-hosted compiler.

### 4. Typechecker is non-functional

All `checkExpr` branches return placeholder `TAG_NIL` types. The self-hosted
compiler bypasses type checking for its own codegen (since the Rust compiler
validates types at build time). For a standalone self-hosted compiler, the
typechecker must:

- Track variable types through let bindings, lambda params, function args
- Track data constructor types and tags
- Handle function application (including binops, comparisons)
- Produce proper type information for the codegen

## Implementation Plan (Updated)

### Phase A: Fix constructor string comparison (P0 — needed for complete self-hosting)

- Debug the Rust IR generator bug causing `strEq(memGetWord(vecGet))` crash
- OR implement byte-level comparison using `__load8` in a non-recursive helper
- Verify with a test source that uses constructor applications

### Phase B: Import resolution (P0 — needed for complete self-hosting)

- Implement module search path resolution
- Recursive compilation of imported modules
- Declaration merging across modules
- Handle stdlib module paths

### Phase C: Remaining codegen features (P1)

- **C1**: Fix lookupType for non-nullary constructors (depends on Phase A)
- **C2**: Implement match expressions when needed
- **C3**: Implement lambda / closures when needed

### Phase D: Complete typechecker (P1)

- Implement checkExpr for all expression types
- Extend typecheck context for local variables and data constructors

### Phase E: Bootstrap and fixpoint

**E1. Stage1 build** (done — Rust compiler builds stage1)

**E2. Stage2 IR output** (done — stage1 compiles itself, emits IR)

**E3. Stage3 IR build** (blocked by import resolution — stage2 needs to compile
with full import support to match stage1's output)

**E4. Verification**: `diff <(stage1_ir) <(stage2_ir)` and `diff <(stage2_ir) <(stage3_ir)`

### Phase F: Remove legacy Rust compiler

Only after stage2 == stage3 proven identical for multiple bootstrap cycles.

## Key Decisions

### D1: Deterministic IR diff suffices for bootstrap validation

The plan's validation uses `diff` of LLVM IR output between stages, not of
linked executables. Undefined external references (from unresolved imports)
are acceptable as long as they are deterministic.

### D2: Pointer comparison workaround for constructor lookup

The `==` pointer comparison with `nameLen` pre-filter is a temporary workaround
for the `strEq` crash in recursive contexts. It works for the bootstrap because
`main.ax` doesn't directly reference constructors from imported modules. The
correct fix requires the Rust compiler IR generator bug investigation.

### D3: Typechecker is optional for codegen correctness

The self-hosted codegen treats all values as i64 and doesn't rely on type
information for code generation. A working typechecker is needed for error
reporting, not for codegen correctness (in the current design).

## Risk Updates

1. **Runtime recursion depth**: Still a risk — the self-hosted compiler uses
   heavy recursion. Mitigation: compile with `--opt 2` for TCO.

2. **Constructor matching failure**: The `==` pointer comparison workaround
   means constructor names from different tokens won't match. This is OK for
   `main.ax` since it doesn't use constructor values, but will fail when
   compiling `lexer.ax` or `parser.ax` (which use `TK_*` constructors as
   values). This is the next blocker to address.

3. **Import chains**: The self-hosted compiler's import chain is:
   core → Mem, Str → Vec → lexer → parser → typecheck → codegen → main.
   Resolving this requires recursive compilation across ~6 files.

## Order of Implementation

1. **Phase A**: Fix string comparison for constructor matching
2. **Phase B**: Implement import resolution
3. **Phase E**: Stage1 → Stage2 → Stage3 fixpoint
4. **Phase C**: Remaining codegen features (as needed)
5. **Phase D**: Typechecker completion
6. **Phase F**: Remove Rust compiler
