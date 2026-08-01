# Self-Hosting Completion Plan

## Goal

Bootstrap the Axiom compiler: stage0 (Rust) compiles stage1 (Axiom), stage1
compiles stage2, stage2 compiles stage3. Verify stage2 == stage3 (byte-identical
LLVM IR). Then the Rust compiler can be removed.

## Current State (verified)

- 1,608 lines of Axiom source in `self_host/`: core, lexer, parser (complete),
  typecheck (stubs), codegen (partial, basic expressions only)
- All files pass `axiom check` (Rust compiler type-checks the self-hosted code)
- The self-hosted compiler runs and emits valid LLVM IR for simple programs
- Rust compiler: 13,010 lines, 175 tests, all targeting 4 platforms

## Critical Gaps

The self-hosted compiler cannot compile its own source. Root causes (in priority
order):

### 1. Codegen cannot emit constructs used in self-hosted source (#)

The self-hosted compiler's own code uses many features the codegen doesn't
handle:

| Feature in self-hosted code | Codegen status | Action needed |
|---|---|---|
| `data` constructors as values (e.g. `True`, `False`) | emitVar only returns `%name`, never tag constants | Implement nullary ctor tag emission |
| `match` expressions | emitExpr has `TAG_E_MATCH` but no handler | Implement match scrutinee + arms |
| `let` with multi-binding `((x 1) (y 2))` | Parser only handles single binding | Fix parser + codegen |
| `lambda` `(fn (x) body)` | No `TAG_E_LAM` handler in emitExpr | Implement lambda → LLVM function or inline |
| `struct` construction `(Foo x y)` | No struct constructor in emitExpr | Track structs, emit GEP+store |
| String literals `(__addr "...")` | Handled via `__addr` primitive | Already works via FFI |
| Imports | Parser produces TAG_D_IMPORT but codegen ignores | Implement import resolution |
| Top-level `::` sig decls | Parse-only, no codegen | Skip (no runtime effect) |

### 2. `lookupTypeIn` crash (runtime segfault)

`lookupTypeIn` in codegen.ax crashes when the types Vec has entries (data decls
registered) AND a variable name is looked up. Root cause: the recursive
function with `if`/`vecGet`/`strEq` pattern triggers a compiler codegen bug
in the Rust backend. This is an **Rust compiler bug**, not a self-hosted
source bug.

**Interim fix (already applied):** Simplified `emitVar` to skip `lookupType`
for variable references, always emitting `%name`. Nullary ctors go through
`dispatchCall`/`emitCall` path instead.

**Correct fix:** Debug the `lookupTypeIn` codegen bug. The issue appears to be
in how the Rust IR generator handles the specific pattern of recursive function
calls with `if`/`let`/`vecGet`/`strEq` when the types Vec is non-empty. This
needs investigation in `axiom-ir/src/generator.rs`.

### 3. No file I/O in main.ax

`main.ax` uses a hardcoded source string. The bootstrap can't work without:
- Reading source from a file path argument (argv)
- Resolving imports (module search path)
- Writing output to a file path argument

### 4. Typechecker is non-functional

All `checkExpr` branches return placeholder `TAG_NIL` types. A real type
checker must:
- Track variable types through let bindings, lambda params, function args
- Track data constructor types and tags
- Handle function application (including binops, comparisons)
- Produce proper type information for the codegen

## Implementation Plan

### Phase A: Stabilize the codegen foundation

**A1. Fix `lookupTypeIn` crash** (Rust compiler bug)

Investigate the codegen bug in `axiom-ir/src/generator.rs` that causes
`lookupTypeIn` to segfault when types Vec has entries. The pattern is:
- A recursive function
- That calls `vecGet` on its first argument
- Then `memGetWord` to read a field
- Then `strEq` to compare
- Then recurses

The Rust compiler generates incorrect LLVM for this pattern. The issue may
be in `gen_local_var`, `gen_match`, or `gen_call` in the IR generator.

Steps:
1. Use `axiom emit-llvm self_host/codegen.ax` to inspect the IR for
   `lookupTypeIn`
2. Compare with the IR for similar recursive functions (e.g. `scanCtors`)
   that work correctly
3. Identify the difference in the generated IR that causes the crash
4. Fix the IR generator

**A2. Re-enable `emitVar` type lookup**

Once A1 is fixed, restore the full `emitVar` that checks `lookupType` for
nullary constructor tags.

**A3. Fix `renderCG` / `renderFrom` stale handle**

The plan document says `emitLine` discards `vecPush` return value. Verify
this is fixed in the current code. If not:
```scheme
; emitLine should capture vecPush return and update CG[0]
(pub fn (emitLine cg line)
  (let ((updated (vecPush (memGetWord cg 0) (strDup line))))
    {
      (memSetWord cg 0 updated)
      cg
    }))
```

### Phase B: Complete the codegen

**B1. Implement `TAG_E_MATCH` handler**

Match expressions need:
- Evaluate scrutinee → register
- For each arm: compare against constructor tag
- Generate conditional branches to arm bodies
- Handle nullary constructors as tag comparisons
- Handle arity > 0 constructors (boxed comparison)

AST for match (`mkNode TAG_E_MATCH scrut arms 0`):
- `nodeA` = scrutinee
- `nodeB` = Vec of arm bodies (current parser only stores bodies, not patterns)

Note: The parser needs to store patterns alongside arm bodies. This requires
parser changes.

**B2. Implement `TAG_E_LAM` handler**

Lambda `(fn (x) body)` currently has no codegen path. Two options:
- Inline: if the lambda is used as a higher-order function argument, inline it
- Named function: emit a separate `define` block with the lambda body

For the self-hosted compiler, lambdas are used for:
- `let`-bound functions (which can be inlined)
- Higher-order operations (unlikely in self-hosted code)

Implementation: emit a named function `lambda_N` with the lambda's params and body,
return a function pointer. Store the function name as the "value".

**B3. Implement struct construction**

`(struct Point (x : Int) (y : Int))` should be constructable as `(Point x y)`.
The parser currently parses struct declarations but doesn't handle struct
construction in `emitExpr`. The `emitApp` handler's `dispatchCall` can be
extended to check if a name is a struct, and if so, allocate + store fields.

**B4. Implement nullary constructor tag emission**

When a nullary data constructor like `Nothing` or `True` is used as a value:
- Look it up in the type registry (via `lookupType`)
- If it's a data ctor with arity 0, emit its tag constant
- Currently `emitVar` skips this (temporary workaround)

This requires the `lookupTypeIn` fix from A1.

**B5. Fix `emitLet` for multi-binding**

The current parser only parses single-binding lets. The self-hosted compiler
code uses single-binding lets extensively, but the parser is broken (the
recent rewrite needs testing). Fix `parseLetExpr` to correctly parse
`(let ((x val)) body)` and store both name and value in the AST.

### Phase C: Complete the typechecker

**C1. Implement `checkExpr` for all expression types**

Currently all branches return `TAG_NIL` placeholders. Need to implement:
- `TAG_E_INT` → return Int type
- `TAG_E_STR` → return String type  
- `TAG_E_VAR` → look up variable type (including let bindings, params, data ctors)
- `TAG_E_APP` → function application type checking (binops, constructors, calls)
- `TAG_E_LAM` → function type
- `TAG_E_LET` → extend context with binding type, check body
- `TAG_E_IF` → check test is Bool, then/else have same type
- `TAG_E_BEGIN` → check each expr, return last
- `TAG_E_MATCH` → check scrutinee type, verify arm patterns, unify arm types
- `TAG_E_QUOTE` → return quoted type

**C2. Extend typecheck context**

The current `TCtx` (SymbolEntry, symbol Vec) is minimal. Need:
- Local variable type tracking (for let bindings and lambda params)
- Data constructor type tracking (arity, field types)
- Struct field type tracking

### Phase D: Bootstrap infrastructure

**D1. File I/O in main.ax**

Replace the hardcoded source string with:
- Read argv[1] as input file path
- Read file contents via `sysOpenPath` + `sysReadFd`
- Write output to argv[2] as output file path

**D2. Import resolution**

The self-hosted compiler needs to resolve `(import Mod)` to actual `.ax`
files. This requires:
- Search path resolution (like the Rust compiler's)
- Recursive compilation of imported modules
- Symbol table merging across modules

The self-hosted compiler currently parses imports but ignores them in codegen.

**D3. Stdlib integration**

The self-hosted compiler uses `Mem`, `Str`, `Vec`, `Sys` from the stdlib.
For the bootstrap, the stage1 binary must be able to find and compile these
dependencies. This requires the import resolution to work for stdlib modules.

### Phase E: Bootstrap and fixpoint

**E1. Stage1 build**

Compile the self-hosted compiler with the Rust compiler:
```bash
axiom build --input self_host/main.ax --output stage1
```

**E2. Stage2 build (self-hosting!)

Compile the self-hosted compiler with itself:
```bash
./stage1 self_host/main.ax stage2
```

This requires the stage1 binary to:
- Accept input and output file arguments
- Parse its own source
- Resolve all imports
- Generate correct LLVM IR matching the Rust compiler's output

**E3. Stage3 build and comparison**

Compile stage2 with stage2:
```bash
./stage2 self_host/main.ax stage3
```

Verify stage2 and stage3 produce byte-identical output:
```bash
diff <(./stage2 self_host/main.ax -) <(./stage3 self_host/main.ax -)
```

If not identical, find and fix the non-determinism (often hash map ordering
or timestamp embedding).

### Phase F: Remove legacy Rust compiler

Only after stage2 == stage3 proven identical for multiple bootstrap cycles:

1. Replace all Rust compiler subcommands that the self-hosted compiler supports
2. Keep Rust compiler in CI until self-hosted passes full test suite
3. Remove Rust source files one crate at a time, in dependency order
   (lexer → parser → ast → sema → ir → codegen → cli)

## Key Decisions

### D1: Function pointer vs closure for higher-order functions

The Rust compiler supports closures (B1 from the roadmap). For the self-hosted
compiler, the codegen can use function pointers for named functions and inline
small lambdas. Full closure support with captured variables is deferred until
the self-hosted compiler needs it (which it might not for the bootstrap).

### D2: Nullary constructor representation

Following the v1-roadmap §4.3 item S1: nullary constructors should be immediates
(tag constants), not heap blocks. Implement this in both the Rust compiler
(if not done) and the self-hosted codegen.

### D3: Bootstrap scope

The self-hosted compiler does NOT need to compile the entire Rust compiler's
source (13,010 lines). It only needs to compile the `self_host/` files
(~1,600 lines). This is achievable with the planned codegen improvements.

### D4: Differential testing approach

Use the Rust compiler as the reference implementation:
- Both compile the same `.ax` file
- Compare emitted LLVM IR
- Any divergence is a bug in the self-hosted compiler

This is the plan's suggested approach (Phase 2 - Frontend in the roadmap).

## Risks

1. **Runtime recursion depth**: The self-hosted compiler uses heavy recursion
   (parser, lexer, codegen). Without guaranteed tail calls, large programs
   will crash. The bump allocator means no reclamation between stages.
   Mitigation: compile the self-hosted compiler itself with `--opt 2`.

2. **Vec stale-handle bug**: The `emitLine` / `scanOne` functions may have
   stale Vec handles if `vecPush` causes reallocation. Must verify the fix
   is correct after all changes.

3. **`lookupTypeIn` crash**: This is a Rust compiler bug, not a self-hosted
   source bug. It may require deep debugging of the IR generator. Workaround
   exists but is not a permanent fix.

4. **Import resolution complexity**: Resolving module imports in the
   self-hosted compiler requires a search path, file reading, and recursive
   compilation. This is the most complex piece to implement.

## Validation Steps

1. `axiom check self_host/*.ax` — all self-hosted source type-checks
2. `axiom build --output stage1` — stage1 binary builds
3. `./stage1 self_host/main.ax stage2` — stage2 builds with stage1
4. `diff <(./stage1 self_host/main.ax -) <(./stage2 self_host/main.ax -)` —
   byte-identical output
5. `cargo test --release --all` — all Rust tests still pass
6. `scripts/check-freestanding.sh` — no libc dependency

## Open Questions

1. Can the self-hosted compiler handle its own import chains?
   (core → lexer → parser → typecheck → codegen → main, plus stdlib imports)

2. Does the `lookupTypeIn` crash affect any other recursive function in the
   self-hosted code? (Likely yes, but we haven't hit them yet.)

3. How much performance is needed? The self-hosted compiler doesn't need to
   be fast, but it must not crash on stack overflow for its own source.

## Order of Implementation

1. Phase A: Fix `lookupTypeIn` crash (A1), restore emitVar (A2)
2. Phase B: Implement remaining codegen handlers (B1-B5)
3. Phase C: Complete typechecker (C1-C2) — may be skippable if types aren't
   needed for codegen accuracy
4. Phase D: Bootstrap I/O and import resolution (D1-D3)
5. Stage 1 → Stage 2 → Stage 3 fixpoint (E1-E3)
6. Differential testing throughout (F)

**Minimum for stage2 == stage3**: Phases A+B+D+E (typechecker can remain
minimal if the codegen is deterministic and correct)
