# Implementation status, types, CLI and diagnostics

This page shows what works in Axiom today, what is partial, and what
has been removed. Most rows name the test or check that backs them. After
the status table come the primitive types, cross-compiling, the
command-line interface and a tour of the compiler's error messages. The list of supported
targets lives in the README's [Targets](../README.md#targets) section.

## Implementation status

| Feature | Status | Notes |
|---|---|---|
| Functions & types | **Complete** | Curried signatures and exact return types. Type variables are rigid inside the body, so `(:: f (-> a Int))` can't do arithmetic on its argument, and each call can choose any type for `a`, one per call, pinned by the first argument. Arguments that disagree with each other, such as `(same 1 "x")` on `(-> a a Bool)`, are `AX3004` at the second: `expected Int, found String`. `tests/selfhost/972-polymorphic-signature.ax`, `tests/diagnostics/998-placeholder-pinned.ax` |
| Operators (prefix) | **Complete** | Eighteen operators: arithmetic (`+`, `-`, `*`, `/`, `%`), bitwise (`&`, `\|`, `^`, `<<`, `>>`), comparison (`==`, `!=`, `<`, `>`, `<=`, `>=`) and logical (`&&`, `\|\|`). `tests/selfhost/910-operator-coverage.ax` |
| Let bindings | **Complete** | Names resolve, and bindings evaluate in order. `tests/selfhost/030-let.ax`, `tests/selfhost/100-letnest.ax` |
| if expressions | **Complete** | `if` branches and returns the value of the branch it takes. `tests/selfhost/040-if.ax` |
| begin blocks | **Removed** | Use `{ }` brace blocks or implicit sequencing. `(begin a b c)` is `AX2004`, which points you to the brace block. `tests/diagnostics/943-removed-begin.axbad` |
| brace blocks | **Complete** | `{ expr1 expr2 ... }` runs each expression in order and returns the last value. `tests/selfhost/080-seq.ax` |
| fn keyword | **Complete** | `fn` defines a function. The older `define` still parses, is read as `fn`, and `axiom fmt` rewrites it to `fn`. `tests/selfhost/020-call.ax`, the formatter case `182-define-rewrites.axp` |
| FFI | **Functional** | Axiom calls Rust through an `extern` block, and each call compiles to a direct native call with nothing to marshal for a scalar. `#[axiom_export]` writes the Rust shim, `axiom-bindgen` writes the Axiom module, and `axiom build --crate DIR` runs both, and `cargo build`, whenever their output is stale or missing. Scalars, strings, `Result`, `Option`, opaque handles, callbacks, records and vectors cross. A signature that isn't one word each way is `AX3036`, a mismatched declaration is `AX4005`, and a missing symbol is `AX4004`. Calling an extern adds `IO`, and a dead `Handle` runs Rust's `Drop` (`MM-FFI-6`). Rust calls Axiom through `--emit-staticlib` and `--emit-rust-binding` (`rust/examples/host`). A program with no `extern`, or one bound to a `no_std` crate, imports no symbols. Fixtures are in `tests/ffi/`, checked by `scripts/check-ffi.sh`. See [ffi.md](ffi.md) |
| Standard library | **Functional** | Twenty-six modules — `Pre`, `Mem`, `Str`, `Utf8`, `Vec`, `Map`, `Fmt`, `Err`, `Fallible`, `Intern`, `Sys`, `Path`, `IO`, `Ffi`, `Json`, `Rpc`, `Par`, `Chan`, `Sync`, `Task`, `Http`, `Test`, `Agent.Tags`, `Tui.Keys`, `Tui.Edit`, `Tui.Term` — in the order [Modules at a glance](reference.md#modules-at-a-glance) lists them. All are written in Axiom over the syscall primitives. `Vec`, `Map` and `Intern` are golden-tested and validated at 10⁵ elements. At 10⁶ elements with `--opt 2` on darwin-aarch64, they take 1.97×, 1.53× and 1.03× Rust's time with a fast hasher (`--fx`), and 1.96×, 0.67× and 0.88× with Rust's default SipHash. `scripts/bench-datastructures.sh` |
| Error handling | **Functional; adopted at the syscall seam** | `stdlib/Err.ax` provides `Result`, an `Error` record, `mapErr`, `andThen`, `mapOk`, `okOr`, `toOption`, `withContext`, the `try!` form, and `divChecked`, `remChecked`, `shlChecked` and `shrChecked` for the operations that otherwise trap with exit 72. In a propagating loop, recurse in a `match` arm rather than the scrutinee, and `let`-bind an error value that crosses a tail call. For batch jobs, the `Fallible` effect lets the loop's handler skip (`fallibleSkip`), default (`fallibleDefault`) or count (`fallibleCounting`) a bad record without unwinding, at 0 bytes a record (`ERR-REC-7`). Every `Sys` and `IO` call that can fail with an errno returns `(Result Int Error)`. Not yet: `Tui.Keys` and `Tui.Term` each keep one `-1` for "not found" (`compat/SENTINELS`), and `strByte`, `jsonGet` and `jsonParse` answer a bare `0` on failure. `tests/stdlib/371-err-module.ax`, `tests/stdlib/410-fallible.ax`. See [error-model.md](error-model.md) |
| Syscalls | **Complete** | `__syscall0` to `__syscall6` on Darwin and Linux, x86-64 and AArch64. Errors come back as `-errno` on every platform. `tests/selfhost/230-syscall.ax` |
| Allocation | **Functional; unbounded by default** | The compiler emits a bump allocator, backed by `mmap` on every supported target or by a static region on a target that declares one ([embedded-proposal.md](embedded-proposal.md)). `--heap-ceiling N` carves N bytes from `.bss` instead. Under it, running out traps with status 70, and `--threads` on a program that spawns is `AX4006`. There's no manual `free`, and defining `axiom_alloc` yourself is `AX3026`. Arena scopes are the reclamation strategy (`MM-ALLOC-22`); the reference counting that already emits stays but won't be extended (`MM-LIFE-2a`), and there's no tracing collector, so `--gc` is refused. A bounded live set keeps bounded memory without freeing a container or resetting an arena (`MM-LIFE-2i`). `tests/stdlib/362-arc-tail-boundary.ax`, `scripts/check-steady-state.sh`. See [memory-model.md](memory-model.md) |
| Crash diagnosis | **Function and line** | A trap prints its message, then `axiom: backtrace (most recent call first)` and one `  at <function>` line per frame. Frames in your code add the source line and column, as in `at e5 chain.ax:5:22`; runtime-helper frames show only the name. Not yet: there's no DWARF (`-g` is never passed), a SIGSEGV prints nothing, and above `--opt 0` inlined frames don't appear. `tests/stdlib/400-backtrace.ax`, `scripts/check-backtrace.sh` |
| Releases and versioning | **Functional** | `VERSION` is the single source of truth. A `v*` tag that agrees with it builds release archives for two targets from the committed seed. `axiom version` also prints a build id: a hash of every `.ax` byte under `self_host/` and `stdlib/`, plus the commit. The installer refuses a tampered archive, a missing checksum, or an archive with no `stdlib/`. No archive ships for `darwin-x86_64`, which is assembled and byte-compared but executed by no runner. `linux-x86_64` and `freebsd-x86_64` are fully supported and tested on every change, but ship no prebuilt archive. `scripts/check-install.sh`, `scripts/check-release-targets.sh` |
| Cross-compilation | **Functional** | `--target` selects the ABI and the platform's standard library modules. Every stdlib case is assembled for all seven targets at three optimisation levels and relocation-checked (`scripts/check-cross-targets.sh`). CI runs programs on five: `darwin-aarch64`, `linux-aarch64`, `linux-x86_64`, `freebsd-x86_64` (a real 14.4 kernel in a VM) and `windows-x86_64` (one hello world on `windows-latest`). `darwin-x86_64` and `freebsd-aarch64` are assembled and relocation-checked only; see [Targets](../README.md#targets) |
| Self-hosting | **Done** | The compiler is written in Axiom and reproduces itself byte for byte (`stage2 == stage3`, as objects and as IR). A clean checkout builds it from `bootstrap/` with only `llc` and a C linker, and the Rust implementation it replaced is gone. See [bootstrap/README.md](../bootstrap/README.md) |
| ADTs / data types | **Complete** | A constructor with fields is a heap-boxed tagged value, and a nullary constructor is just its tag, even in a type that mixes both kinds. Recursive types such as `List` and `Tree` need nothing special. `tests/selfhost/140-data.ax`, `tests/selfhost/400-mixed-nullary.ax`. See [Algebraic data types](reference.md#algebraic-data-types) |
| Structs | **Complete** | Declaration, construction with `(StructName expr1 expr2 ...)`, field access with `.field`, and `mut` fields you can update. `tests/selfhost/150-struct.ax` |
| Struct variants | **Complete** | A `data` constructor can have named fields. Patterns match them by name in any order, with punning (`{ w, h }`) and partial patterns. `tests/selfhost/810-struct-variant-pattern.ax`, `tests/stdlib/210-struct-variants.ax` |
| String literals | **Complete** | A literal is a `Str`: a static `{ length, bytes }` header with its length known at compile time, so it needs no allocation and no runtime scan. `tests/selfhost/310-strlit.ax`, `tests/selfhost/890-lexical-edges.ax`. See [Standard library](reference.md#standard-library) |
| Pattern matching (`match`) | **Complete** | Constructor patterns with or without fields, variables, wildcards, literals and nested patterns. The compiler reports non-exhaustive matches, wrong arity and undefined constructors. `Option` is built in, with `Some` and `None`. There are no tuple or list patterns. `tests/selfhost/385-literal-in-ctor.ax`, `tests/selfhost/810-struct-variant-pattern.ax` |
| Lambda / function values | **Complete** | A closure holds a code pointer and its captures, and can live in a `data` field. `(lambda (x y) b)` means `(lambda (x) (lambda (y) b))`, so you can apply it one argument at a time or all at once. `tests/selfhost/950-multi-param-lambda.ax`, `tests/stdlib/140-function-values.ax` |
| Lists | **Removed** | Use `(Vec T)`. The type `[T]` is `AX2004` with migration advice, and `[1 2 3]` is `AX2001`. `tests/diagnostics/944-removed-list-type.axbad` |
| Tuples | **Removed** | Use `struct` for products and `data` for sums. A tuple type such as `(Int String Bool)` is `AX2004` with migration advice. `()` is still the unit value. `tests/diagnostics/946-removed-tuple-type.axbad` |
| Type classes | **Replaced** | Traits replaced them, and capability records replaced traits; see the row below |
| Unions | **Removed** | Use `data` for a tagged sum or `struct` for a product. C interoperability isn't a goal, and `union` stays reserved and reports `AX2004` |
| Struct layout modifiers | **Removed** | `packed`, `repr(C)` and `align(N)` are `AX2001`. The FFI doesn't need them: a `#[axiom_record]` struct crosses as its fields, one word each ([ffi.md](ffi.md) §8) |
| Region syntax | **Checked scope, and annotated signatures with the escape rule** | `(region r body)` answers `body`'s value, then rolls the allocator back to where `body` started. Only scalars leave: a non-scalar value, or a non-scalar store to an outer binding, is `AX3059`. A nested region that reuses an open region's name is `AX3058`. A signature can name the region a reference lives in, as in `(:: intern (-> (String @s) (Table @r) (Sym @r)))`, and the escape rule `MM-RGN-3` refuses a store, return or capture that outlives it (`AX3060`–`AX3063`). Annotations don't change the emitted IR, and inside a region the compiler skips releases for values it can prove fresh. Not yet: a reference can't be promoted out of a region. `tests/stdlib/168-region.ax`, `tests/diagnostics/645-region-escape-store.ax`. See [Regions](reference.md#regions) and [memory-model-v2-design.md](memory-model-v2-design.md) §4 |
| Capability records | **Functional** | An interface is a parameterised struct of functions, such as `(struct ShowOf (a) (render : (-> a String)))`, and an instance is an ordinary value, `(ShowOf fmtInt)`, passed where it's needed. Calling a method is plain application, so a function generic over an interface can call its methods. `trait` and `impl` are reserved and report `AX2004` with migration advice. Rendering needs no record: `(format x)` renders any value from its static type, and `show` isn't a name a program can use. |
| Effects | **Enforced; two limits stated** | The compiler checks the built-in effects `IO`, `Pure`, `Alloc`, `Mut`, `Div` and `Unsafe`, declared effects and their `handle` expressions, and AXTAG metadata. A declaration that uses a raw primitive, calls a precondition interface or forges a reference must declare `Unsafe` (`AX3073`). A trusted wrapper ends that obligation; a precondition interface passes it to callers (`MM-EXEC-9d`). IO propagates through calls, so a function that reaches IO without declaring it is `AX3042`; a call through a capability record's field is marked `#effects-incomplete #effects-overapprox`. An effect operation needs a type (`AX3055`), a declared effect can't take a built-in's name (`AX3054`), and a handle list may name only declared effects (`AX3016`). An operation that reaches `main` unhandled is `AX3053`, a warning you can mark intended with `;@axiom:unhandled(trap)`. Two limits: a call the compiler can't resolve reports `#effects-incomplete`, and constructor allocation isn't counted (`MM-EXEC-9a` in [memory-model.md](memory-model.md)). `tests/selfhost/820-effect-handlers.ax`, `tests/diagnostics/450-effect-op-arity.ax` |

| Loops | **Complete** | `while` with `mut` bindings and `set` runs in constant stack (`tests/selfhost/500-while-mut.ax`). `for` has four shapes: `(for i lo hi body)` over a range, `(for i lo hi step body)` with a step (a negative one counts down), `(for x xs body)` over a `(Vec a)`, and `(for (x k) xs body)` with the index. The parser rewrites it to `let`, `while` and `set`, reading both ends and the step once, before the loop. A sixth element is `AX2001`, a literal step of `0` or a pair binder over a range is refused, and a non-container is `AX3004`. Self tail calls run in constant stack at every `--opt` level, in any tail position including a `let` body. So do mutual tail calls when the prototypes match and nothing is owed afterwards (the emitter marks them `musttail`). A tail call to a callee of a different arity, or one that hands over an owned temporary, stays a plain call: it needs `--opt 1` or higher and still has no guarantee ([memory-model.md](memory-model.md) MM-EXEC-6b/6c). Non-tail recursion is limited to about 60,000–80,000 frames. Tested by `tests/stdlib/466-for-loop.ax` and `tests/stdlib/467-mutual-tail.ax`. |
| Linear types | **Removed** | `linear` and `consume` are refused as `AX2004` with migration advice, like `union`, `foreign` and `deriving`. They never enforced anything. Memory is reclaimed deterministically by the reference count every heap block carries ([memory-model.md](memory-model.md)). |
| Macros | **Partial** | A head-list macro substitutes its arguments into one expression template. A rule-form macro picks the first rule whose patterns match: binders, `_`, literals, nested forms, `...` repetition and reserved `(literals ...)`. `emacro` does the same for expression templates. Macros expand in their own pass (`self_host/expand.ax`) before type checking, so everything they generate is checked. Hygiene is by renaming: a template's free names resolve where the macro is defined, and a parameter in binder position binds the caller's name. Declaration macros generate `fn`, `::`, `data`, `struct`, `type` and `effect` declarations in any module. They can ask about the program through the closed `syntax/*` queries (`join`, `constructors`, `fields`, `for`, `name`, `arity`, `defined`, `same`, `binders`, `fold`), which never run user code. `stdlib/Pre.ax` defines `when` and `unless`, and the derivers `deriveEq`, `deriveShow`, `deriveArity` and `showOr`. Multi-way branching needs no macro: write `(if t1 b1 t2 b2 ... els)`. Macros import across modules and can be qualified as `Mod::name`, in type position too. An entry-file function outranks an imported macro of the same name. A diagnostic inside an expansion carries a backtrace through each enclosing macro. Misuse has its own codes. `AX3027` is an unknown declaration keyword or an `emacro` in declaration position, and `AX3028` is zipped sequences of unequal length. `AX3033` is a rule that can never match, `AX3034` a `...` at the wrong depth, and `AX3035` a non-name passed where the template binds it. `AX3014` is a name two imported modules both declare, and `AX3023` a private macro named from outside. A template can't generate `import` or a nested `macro`, because each would reopen a phase that has already run. Not yet: a pattern can't test two binders for sameness (a repeated binder is `AX3020`). See [macro-system.md](macro-system.md). Tested by `tests/selfhost/392-macro-patterns.ax` and `tests/diagnostics/490-expansion-backtrace.ax`. |
| Concurrency | **Language form, two lowerings** | `(parallel p ((a e1) (b e2)) body)` runs its bindings beside the caller and joins them in the order written ([reference](reference.md#parallel--bindings-that-run-beside-the-caller)). By default each binding runs in a forked process. With `--threads` it runs on a platform thread that allocates in its own arena. Both give the same output and exit status, including when one binding traps. Only a word crosses a join (a `String` binding is `AX3004`), and capturing a reference the parent holds is `AX3064` under either lowering. Limit: when two bindings trap with different statuses, processes report the first-written one and threads report whichever fired first. Linux and macOS have both lowerings. FreeBSD runs processes, and `--threads` there is `AX4006`. Windows has neither: `--threads` is `AX4006`, and otherwise the build warns `AX4007` and the program exits with status 79 at its first spawn. `stdlib/Par.ax`, which replaces the `Job` module, is a bounded pool of closures that answers in submit order (`tests/stdlib/476-par-pool.ax`). `Chan`, `Sync` and `Task` add a bounded channel, a mutex with timed waits, and a task pool whose tasks answer typed results by serialization, with deadlines and cancellation ([memory-model.md](memory-model.md) `MM-PAR-10` to `MM-PAR-13`, `scripts/check-task.sh`). Tested by `tests/stdlib/470-parallel.ax` and `scripts/check-parallel.sh`. |
| API reference | **Generated** | [stdlib-api.md](stdlib-api.md) lists every public name in the standard library with its type, the effect row the compiler derived, and the first paragraph of the comment above it. It is written by `examples/axdoc/axdoc.ax`, an Axiom program. `scripts/check-stdlib-api.sh` keeps it identical to the generator's output and checks that every `pub` name in `stdlib/` appears exactly once. |
| Performance gates | **Rate covered** | Every timing gate compares a ratio, so a slow runner can't fail one. `scripts/check-arena-reset-rate.sh` turns rate into a ratio too: it puts an arena reset at about 1.35 µs against a few nanoseconds for a mark. That is 1.7–1.8% of the memory model's 77 µs per-connection budget. |
| Type soundness | **Four classes closed** | The checker refuses four kinds of program that would otherwise type-check and then read the wrong memory. A function declared to return a bare `Int` can't return a parameterised type, because `Int` keeps the address but loses the type arguments; a monomorphic type is still accepted (`tests/diagnostics/498-param-through-int.ax`). A C or Rust type name such as `u64` in type position is `AX3047`, where it would otherwise be read as a type variable (`tests/diagnostics/496-sized-integer-type.axbad`); uppercase near-misses such as `Double` are `AX3002` (`tests/diagnostics/495-widthless-types.ax`). A type variable the function must produce but no caller supplies is `AX3040`. A result variable is allowed when the function never returns, as in `(:: panic (-> String a))`, but that excuse doesn't extend to a variable inside a callback's type. The check follows variance through nested arrows and reads only the signature (`scripts/check-diverging-tyvar.sh`). A field read on a `data` type is `AX3070` unless every constructor declares that field at the same position with the same type (`tests/diagnostics/484-field-on-partial-data.ax`). |
| Test runner | **Functional** | `axiom test` runs every top-level function whose name starts with `test` and takes no parameters (`stdlib/Test.ax`). Each test has its own recovery point, so a failed assertion, an unhandled effect, an allocation failure or a division by zero ends only that test (`ERR-REC-6`). Optional `setup` and `teardown` functions run around every test, and a hook that traps fails that test. A file with no tests fails, and a test or hook that takes parameters is refused by name. Mark a test expected to fail with `;@axiom:expect` above its `fn` or `::`. It reports `xfail` when it fails, which doesn't count against the run, and `FAIL` when it passes. Not yet: tests can't run in parallel. See [Testing](reference.md#testing). Tested by `scripts/check-test-runner.sh` over `tests/testrunner/`. |
| Editor support | **Functional** | A [tree-sitter grammar](../tree-sitter-axiom/) with highlighting and rainbow-bracket queries, tested against all 835 `.ax` files in the repo and a 48-case tree-shape corpus. The language server is `self_host/lsp.ax`, and [lsp.md](lsp.md) is the editor guide. It answers twenty-six requests. Navigation: `definition` (locals and imported names too), `declaration` (the `::` signature, where `definition` goes to the `fn` body), `typeDefinition`, `references`, `documentHighlight`, `prepareRename`, `rename`, call hierarchy (prepare, incoming, outgoing) and type hierarchy (prepare, supertypes, subtypes). Reading: `hover`, `completion`, `signatureHelp`, `inlayHint`, `foldingRange`, `selectionRange`, `documentLink`, `documentSymbol` and `workspace/symbol`. Changing and running: `formatting`, `codeAction` (the compiler's fixes, an *Add type signature* assist and lint fixes), a `codeLens` to run `main`, and `axiom/expandMacro`. Three editor-only lints (`lint-dead-branch`, `lint-bool-if`, `lint-unused-let`) can be silenced per declaration with `;@axiom:nolint(...)`. Per-keystroke requests read the unexpanded parse tree, so names a macro would generate don't appear (`MAC-TOOL-3`). Highlighting comes from the grammar alone, and the server sends no semantic tokens. Tested by `scripts/check-lsp-selfhost.sh`. |
| Imports | **Functional** | `(import Mod.Sub ...)` merges declarations from other files, and `Mod::name` picks one out when names clash. See [Modules and imports](reference.md#modules-and-imports). |
| Module visibility | **Complete** | `pub` on a declaration, or an import's name list, decides which names are visible outside a module. Private helpers still exist, and a module behaves the same however it is imported. Naming a private one from outside is `AX3023`, and so is importing a name that doesn't exist, as in `(import M (noSuch))`. Tested by `tests/selfhost/920-private-declaration.ax` and `tests/selfhost/930-selective-import.ax`. |

## Type system

### Primitive types

| Type | Description | LLVM type |
|---|---|---|
| `Int` | 64-bit signed integer. | `i64` |
| `Float` | 64-bit IEEE-754 double. The word holds the bit pattern: each arithmetic operation `bitcast`s it to `double`, operates (`fadd double`, `fdiv double`, …) and `bitcast`s back. | `i64` |
| `Bool` | Boolean, with the literals `true` and `false`. A distinct type from `Int`, and the type `if` tests. | `i64` |
| `Char` | Character. A codepoint at run time, and a distinct type from `Int`. | `i64` |
| `String` | A `Str` handle: the address of a `{ length, bytes, owner }` header. One word wide like `Int`, but a distinct type. `(cast Int s)` converts a `String` to an `Int`. See [Standard library](reference.md#standard-library). | `i64` |
| `()` | Unit (no value). | `i64` |
| `Unit` | A distinct constructor, not a synonym for `()`. `symbols` renders them as `(Int -> ())` and `(Int -> Unit)`. See [Types](reference.md#types). | `i64` |
| `Void` | Void. Accepted, and distinct: a mismatch reports "found `Void`". | `i64` |
| `Any` | Generic pointer. Accepted, and one word like every other type. | `i64` |

Every entry in the LLVM column is `i64`. Types exist only while the
compiler checks your program, so every value is one machine word:
`(-> Bool Bool)` emits `define i64 @f(i64 %x)`. `Float` is the only
type whose word is read differently, and only by its arithmetic
operators. Nothing about a value's type reaches the emitted code,
which is why `MM-LIFE-2a` in the [memory model](memory-model.md)
treats codegen's shape word as the wall.

For compound types, type variables, aliases and casting, see
[Types](reference.md#type-system) in the reference.

## Cross-compiling

Pass `--target` to build for any supported target from any host:

```bash
axiom build --input source.ax --output program --target linux-aarch64
```

The target decides the syscall ABI and the triple, whatever machine
does the compiling. The README's [Targets](../README.md#targets)
section lists the supported targets.

Tested by `scripts/check-cross-targets.sh`, which assembles every target
from one host.

## CLI commands

These are the commands you'll use most. `axiom help <command>`
describes any one of them.

```bash
# Check syntax and types, without generating code
axiom check source.ax

# Compile to a native executable
axiom build --input source.ax --output program

# Print LLVM IR, or write it to a file
axiom emit-llvm source.ax
axiom emit-llvm source.ax -o output.ll

# Compile and run straight away
axiom run source.ax

# Run every test in a file, or in a directory
axiom test tests/testrunner/pass-tests.ax
axiom test tests/testrunner/

# Run only the tests whose name contains a string
axiom test tests/testrunner/ --filter Map

# Start the interactive REPL
axiom repl

# Print the version and build id. The id hashes every source byte the
# compiler was built from, plus the commit when there is one, so two
# different trees at the same version report different ids
axiom version
#   Axiom 0.7.6 (build 7ce43b921d1d 23b97d8285b4)

# Explain a diagnostic code, or list them all
axiom explain AX3001
axiom explain --list
```

For agents and other tools:

```bash
# Render diagnostics as AXDL, one line each
axiom --diagnostic-format=ai check source.ax

# Or as JSON Lines, one object per diagnostic
axiom --diagnostic-format=json check source.ax

# List every top-level symbol (functions, types, constructors, structs,
# aliases and so on) with its type or shape, in AXSYM notation. Imports
# are resolved, and each symbol names the file that declared it
axiom --diagnostic-format=ai symbols source.ax

# Also include the built-in operators and primitives that are always
# in scope (left out by default to keep the output short)
axiom --diagnostic-format=ai symbols source.ax --builtins

# Also print the call graph, as a `#calls=` field beside `#effects=`,
# so you can see why a function carries an effect
axiom --diagnostic-format=ai symbols source.ax --calls
```

[diagnostics.md](diagnostics.md) covers the notation in full: stable
error codes (`AX####`), cascade suppression, the human report format,
the AXDL diagnostic notation and the AXSYM symbol and type notation.

## Error messages

When your program doesn't compile, the report quotes the offending
line, underlines the exact span with a label, and gives you a stable
code to look up. Given `err.ax`:

<!-- doc-gate:source err.ax -->
```scheme refused
(:: main Int)
(fn (main)
  (if true (+ 1 2) false))
```

<!-- doc-gate:render err.ax human -->
```
error[AX3004]: type mismatch: expected Int, found Bool
 --> err.ax:3:20
  |
3 |   (if true (+ 1 2) false))
  |                    ^^^^^ this has type `Bool`, expected `Int`
  |
  = help: run `axiom explain AX3004` for a full explanation

compilation failed due to 1 previous error
```

The real output is in colour: severity and carets in the severity's
colour, the gutter blue and the `= help:` marker green. It stays in
colour when stderr is redirected. It's shown plain here because a
Markdown code block isn't a terminal. The palette is one table in
`self_host/style.ax`.

Codes are grouped by the stage of the compiler that reports them. A
code stays the same when its wording changes, so you can grep for it
and match on it.

- `AX1xxx`: lexer
- `AX2xxx`: parser
- `AX3xxx`: semantics
- `AX4xxx`: code generation and the build driver
- `AX5xxx`: modules

`axiom explain --list` prints them all.

A report with more than one span quotes each one, and skips the lines
between them. Given `count.ax`:

<!-- doc-gate:source count.ax -->
```scheme refused
(:: main Int)
(fn (main)
  (let ((x 0))
    {
      (set x 1)
      x
    }))
```

<!-- doc-gate:render count.ax human -->
```
error[AX3012]: cannot assign to immutable binding `x`
 --> count.ax:5:12
  |
3 |   (let ((x 0))
  |          - `x` is bound here
...
5 |       (set x 1)
  |            ^ `x` cannot be assigned
  |
  = help: declare it mutable: `(mut x ...)` ~> mut x
  = help: only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`
  = help: run `axiom explain AX3012` for a full explanation

compilation failed due to 1 previous error
```

Columns count characters, not bytes, so a caret lands where you expect
even on a line with an em dash in it. Tabs expand to the next multiple
of four. A line wider than 160 columns is quoted as a window, marked
`...` on each side that was cut.

### For agents and tooling

`--diagnostic-format=ai` renders the same diagnostic as **AXDL**: one
dense, colourless line per diagnostic, with no re-printed source and
no box drawing. `grep -c '^E '` counts the errors.

<!-- doc-gate:render err.ax ai -->
```
E AX3004 err.ax:3:20-25 type-mismatch "type mismatch: expected Int, found Bool" #"this has type `Bool`, expected `Int`"
compilation failed due to 1 previous error
```

That one line carries every fact in the diagnostic: the primary label,
every related span, every note and every help. It leaves out only the
`run axiom explain AX####` footer, which the human render adds for a
reader who wants prose.

A machine-applicable fix travels with the diagnostic as
`<loc>:"<msg>"~>"<replacement>"`. A tool can apply it as a byte-range
substitution, without parsing English. Here is `count.ax` in AXDL:

<!-- doc-gate:render count.ax ai -->
```
E AX3012 count.ax:5:12-13 assign-to-immutable "cannot assign to immutable binding `x`" #"`x` cannot be assigned" ^3:10-11:"`x` is bound here" ?3:10-11:"declare it mutable: `(mut x ...)`"~>"mut x" ?"only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`"
compilation failed due to 1 previous error
```

The fields always come in the same order: severity, code, file and
span, slug and message. Then come the primary label `#`, related spans
`^`, notes `!`, helps `?` and macro-expansion frames `&`. When a
parser suits you better than a grammar, `--diagnostic-format=json`
emits the same facts as JSON Lines. The full grammar is in
[diagnostics.md](diagnostics.md).

Tested by `scripts/check-doc-drift.sh`, which re-renders every block in
this section and compares it with the page.
