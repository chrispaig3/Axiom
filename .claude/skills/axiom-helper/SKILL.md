---
name: axiom-helper
description: Guides for working with the Axiom compiler, ensuring correctness (proper diagnostic usage, AXTAG validation, exhaustive pattern matching), robustness (cascade suppression awareness, FFI safety, poison propagation handling), and productivity (quick reference commands, project structure, diagnostic code lookup, AXSYM symbol lookup).
---

# Axiom Helper — Agent Skill

## 1. Compiler invocation: always use `axiom --diagnostic-format=ai`

Every Axiom compiler command must pass the AI-optimized diagnostic format:

```bash
axiom --diagnostic-format=ai check source.ax
axiom --diagnostic-format=ai build --input source.ax --output myprog
axiom --diagnostic-format=ai symbols source.ax
axiom --diagnostic-format=ai run source.ax
axiom --diagnostic-format=ai emit-llvm source.ax -o output.ll
```

`--diagnostic-format` is a global option, so it goes before the
subcommand. It produces one dense, greppable, colorless AXDL line per diagnostic — no re-rendered source text, no ANSI codes, no Unicode box drawing. The `human` renderer is for human consumption only; use it only when `ai` output is insufficient.

## 2. Project structure at a glance

```
axiom/
├── self_host/          # THE COMPILER, written in Axiom
│   ├── core.ax           # tokens and spans
│   ├── lexer.ax          # tokenizer
│   ├── parser.ax         # S-expression parser and AST
│   ├── typecheck.ax      # name resolution, types, effects, AXTAG validation
│   ├── codegen.ax        # import resolution, name mangling, LLVM emission
│   ├── diag.ax           # diagnostics, AXDL/JSON rendering, source maps
│   ├── render.ax         # human diagnostic renderer
│   ├── driver.ax         # `build`: opt, llc, cc
│   └── main.ax           # CLI entry point
├── bootstrap/          # the compiler's own LLVM IR, per target - the seed
├── hello_world/        # Sample program
├── docs/               # docs/diagnostics.md (AXDL/AXSYM reference)
└── README.md
```

The compiler pipeline is always:

```
Source (.ax) → lexer.ax → parser.ax → typecheck.ax → codegen.ax → LLVM IR → llc → cc → Executable
```

Cross-crate dependencies flow in one direction: lexer → parser → sema → ir → codegen. The lexer must not know about types; the parser must not know about effects; the codegen must not know about semantic analysis.

## 3. Correctness patterns

### 3.1 Validate AXTAG annotations

AXTAG metadata (`;@axiom:<key>(<value>)` comments above declarations) is compiler-checked. The most important validation is that `effect(io)` claims match what the body actually performs - a `__syscallN`, or a call to something that performs one - and `pure` claims match a body that performs nothing. Mismatches emit `AX3010` (`axtag-mismatch`).

When writing or reviewing Axiom source:
- Always pair `;@axiom:effect(io)` with code that actually reaches a syscall, directly or through a callee, or with a `handle` expression.
- Never annotate a function as `pure` if anything it calls performs an effect.
- Use `axiom --diagnostic-format=ai symbols source.ax` to verify which AXTAG metadata was accepted (`#effect=io`, `#pure`, etc.).

### 3.2 Check pattern matching exhaustiveness

Axiom checks exhaustive pattern matching at compile time. Missing constructors and wrong-arity constructor patterns are compile errors (`AX3005` / `AX3009`). When writing `match` expressions, ensure every constructor of the matched type is covered.

```scheme
;; Correct: all constructors covered
(match val
  ((Nothing) default)
  ((Just x) x))

;; Incorrect: Missing Nothing arm — compile error AX3005
(match val
  ((Just x) x))
```

Nested constructor patterns are supported and checked recursively:

```scheme
(match lst
  ((Cons h (Cons h2 t)) ...)   ; correctly matches and binds h, h2, t
  ((Nil) ...))
```

### 3.3 Use stable diagnostic codes for pattern matching

Diagnostic codes are stable across wording changes. Never rename or reuse a code. Ranges are namespaced by compiler stage:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, native toolchain |
| `AX5xxx` | Module / import resolution |

Look up any code with `axiom explain AX3001` or see all codes with `axiom explain --list`.

### 3.4 Prefer Poison propagation over ad-hoc cascade suppression

When a type check fails, the checker propagates `TypeId::TError` rather than producing new diagnostics for every downstream use. `dedup` is a secondary safety net for diagnostics that are truly independent but logically related.

If you see multiple diagnostics sharing the same `group` key in `ai` output, only the first is the root cause — the rest are cascading consequences of the same root-cause error.

### 3.5 Never duplicate diagnostic logic across renderers

All compiler messages must go through `mkDiag` (`self_host/diag.ax`) with a stable code, severity, span, and message. Never print raw strings from compiler phases. When adding a new diagnostic, construct it at the site that detects the condition and write its long-form text into `self_host/explain.ax` - `scripts/check-tools-selfhost.sh` fails if a code the corpus emits has no entry.

## 4. Robustness patterns

### 4.1 Understand AXDL parsing rules

AXDL lines follow this grammar:

```
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [#"<label>"]
     [^<LOC>:"<related>"]* [!"<note>"]* [?<field>]* [&"<frame>"]*
```

- `SEV` is one of `E` (error), `W` (warning), `N` (note), `H` (help)
- `LOC` is `file:line:col`, `file:line:col-col`, or `file:line:col-line:col`
- Slug is kebab-case and wording-independent
- Machine-applicable fixes use `~>` in the suggestion field

**Parsing pitfall**: `"msg"` and `"replacement"` are Rust `Debug`-style escaped strings. A correct consumer must parse each quoted field as a proper escaped string and only look for `~>` in the unquoted gap *between* fields — never do a naive `str.split("~>")`, which can misfire if `~>` appears inside the message itself.

### 4.2 Standard library and FFI safety

Axiom has a standard library written in Axiom (`stdlib/`: `Sys`, `Mem`,
`Str`, `Fmt`, `IO`), built on the freestanding primitives
`__syscall0`-`__syscall6`, `__load8`/`__store8`, `__load64`/`__store64`,
`__alloc`, and `__addr`. Use it: `(import IO)` and `println`. Generated
code calls no libc function, and `scripts/check-freestanding.sh`
enforces that.

**The FFI is `extern`, and it is never `foreign`.** `foreign` was
removed and remains a reserved word reporting `AX2004` with migration
advice, alongside `union` and `region` - never write one and never
suggest one. It is not a synonym for the new form: `foreign` named one
symbol and emitted a call the module never declared, which is why it
never linked.

A Rust binding is an `extern` BLOCK:

```scheme
(pub extern "axiom_demo"
  (add         :: (-> Int Int Int) (symbol "axffi_add"))
  (countVowels :: (-> String Int)  (symbol "axffi_count_vowels")))
```

and the program is built with the archive on the link line:

```bash
axiom build --input p.ax --output p --link-lib axiom_demo --link-search rust/target/release
```

Four rules matter when writing one:

- The type goes INLINE in the block. A separate `(:: name Type)` beside
  it draws a false `AX3015`.
- An extern may not be polymorphic. A type variable would make the
  emitter add a hidden evidence word that must never reach Rust.
- Calling an extern contributes the `IO` effect, exactly as calling
  `__syscallN` does, and it propagates transitively - so a caller two
  hops away needs `;@axiom:effect(io)`.
- Write `(symbol "...")` explicitly. A static link is one flat
  namespace and the default is the Axiom name.

Generate blocks with `cargo run -p axiom-bindgen` rather than by hand;
see `docs/ffi.md` and `rust/README.md`. `scripts/check-ffi.sh` is the
gate, and it enumerates permitted external symbols rather than
forbidding all of them (`docs/memory-model.md` MM-FFI-5).

- Sanitize file paths before passing them to native toolchain invocations (`llc`, `cc`). Never pass unsanitized user input to shell commands. Native tools are spawned with explicit argument vectors through `Sys.spawn`, never through a shell.

### 4.3 Memory safety discipline

Axiom source has no `malloc` and no `free`: allocation goes through the backend's `mmap`-backed bump allocator (overridable by defining `axiom_alloc`). `union`, `region` and `foreign` have been removed from the language - all three are still reserved words and report `AX2004`. C is reachable only through an `extern` block, and a Rust crate that is `no_std` with its `alloc` wired to `axiom_alloc` reaches it without importing any libc symbol at all - measured, `nm -u` on such an executable is empty.

### 4.4 Handle input validation at every pipeline stage

All user-provided source files must be validated at every pipeline stage. A malformed input must produce a diagnostic, not a panic or segfault. The compiler must never execute arbitrary code from source files during compilation — code generation produces standalone LLVM IR; no runtime evaluation of user code.

### 4.5 Recognize cascade suppression vs. poison propagation

Two distinct mechanisms suppress cascading errors:
1. **Poison propagation** (type checker): `TypeId::TError` is propagated after a type mismatch; subsequent checks on a poisoned type are skipped via `is_error()` guards. This prevents the primary cascade.
2. **`dedup` with grouping** (`Diagnostic::with_group`): Suppresses truly independent diagnostics that are logically related to a root cause already reported. Use this only when poisoning cannot apply (e.g., diagnostics from unrelated compiler stages that share a root cause).

If you are adding a new diagnostic site and find yourself grouping multiple diagnostics together, prefer poisoning first. Only reach for `.with_group(...)` + `dedup()` when a concrete cascade exists that poisoning and `is_error()` guards cannot prevent.

## 5. Productivity patterns

### 5.1 Quick reference: common commands

```bash
# Check syntax and types (no code generation) — MUST use diagnostics=ai
axiom --diagnostic-format=ai check source.ax

# Compile to native executable
axiom --diagnostic-format=ai build --input source.ax --output program

# Emit LLVM IR to stdout
axiom --diagnostic-format=ai emit-llvm source.ax

# Emit LLVM IR to a file
axiom --diagnostic-format=ai emit-llvm source.ax -o output.ll

# Compile and run immediately
axiom --diagnostic-format=ai run source.ax

# Start interactive REPL
axiom --diagnostic-format=ai repl

# Look up a diagnostic code
axiom explain AX3001

# List all known diagnostic codes
axiom explain --list

# List every top-level symbol and its type (AXSYM notation)
axiom --diagnostic-format=ai symbols source.ax

# Same, including always-in-scope built-in operators
axiom --diagnostic-format=ai symbols source.ax --builtins

# Verify AXTAG annotations are accepted
axiom --diagnostic-format=ai symbols source.ax | grep '@'
```

### 5.2 Use AXSYM to understand a codebase without re-reading it

`axiom --diagnostic-format=ai symbols source.ax` produces one line per top-level declaration:

| KIND | Meaning |
|---|---|
| `F` | Function |
| `D` | Data type |
| `C` | Constructor |
| `S` | Struct |
| `A` | Type alias |
| `T` | Trait |

Example output:

```
F add main.ax:11:5-8 "(Int -> (Int -> Int))"
D Maybe main.ax:3:7-12 "data Maybe" #ctors=Nothing,Just
C Nothing main.ax:4:4-11 "Maybe" #of=Maybe
C Just main.ax:5:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:7:9-14 "struct Point" #fields=x:Int,y:Int
```

An agent asked to "add a function that formats a `Maybe Int`" can `grep '^D Maybe'` and `grep '^C '` for the exact constructor set, and `grep '^S Point'` for a struct's exact field shapes, instead of re-reading the whole file.

### 5.3 Module imports resolution

Dotted module paths map directly to file paths relative to the entry file's directory:

```scheme
; Math/Ops.ax defines `square`
(import Math.Ops (square))    ; brings in only `square`
(import Math.Ops)             ; brings in every top-level decl
```

Key facts:
- Imports are transitive and diamond-safe (merged exactly once).
- Qualified access via `Mod::name` is supported. By default, imported declarations join the flat top-level namespace, but `Mod::name` disambiguates when the same name exists in multiple modules.
- A module path that doesn't resolve to a real file is `AX5001`.
- Diagnostics from imported files are attributed to the actual file, not the entry file.

### 5.4 Common Axiom patterns

**Functions (modern `fn` style):**
```scheme
(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))
```

**Let bindings with sequential evaluation:**
```scheme
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

**Brace blocks for sequencing:**
```scheme
{
  (printf "Starting...\n")
  (printf "Working...\n")
  0
}
```

**Algebraic data types:**
```scheme
(data Maybe (a)
  (Nothing)
  (Just a))
```

**Pattern matching:**
```scheme
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))
```

**Effects with AXTAG:**
```scheme
(import IO)

;@axiom:effect(io)
(fn (main) { (println "hello") 0 })
```

### 5.5 REPL commands for rapid prototyping

```
:help / :h / ?        — Show all commands
:quit / :q / :exit    — Exit the REPL
:type <expr> / :t     — Show the type of an expression
:load <file> / :l     — Load a file into the REPL
:reset / :r           — Clear all definitions
:defs / :d            — Show all definitions in scope
:llvm <expr>          — Show the generated LLVM IR
:time <expr>          — Time an expression
```

The REPL compiles to native code, not interpretation. Definitions accumulate across inputs and history is saved between sessions.

### 5.6 Diagnostic code lookup workflow

When you encounter an error code in AXDL output:
1. Run `axiom explain AX####` (e.g., `axiom explain AX3001`) to get the full explanation.
2. If the explanation mentions a suggestion with a replacement, apply it programmatically — do not parse the English prose.
3. For cascade suppression: if multiple diagnostics share the same group key, fix only the first (root cause).
4. Verify the fix by re-running `axiom --diagnostic-format=ai check source.ax` and confirming zero errors.

### 5.7 Testing and validation

- Unit tests are Axiom programs under `tests/selfhost/`, each carrying an `; expect N` line that `scripts/check-bootstrap.sh` runs and checks.
- Every diagnostic code the corpus emits must be explained; `scripts/check-tools-selfhost.sh` cross-checks that against `explain --list`.
- Renderer output is pinned by the goldens under `tests/diagnostics/` - `.axdl`, `.human` and `.json` per case - each with a half that a re-bless cannot satisfy. Regenerate deliberately with `AXIOM_BLESS=1`, never casually.
- Do NOT run `axiom fmt` over the repository: the tree is not kept in the formatter's normal form, and doing so buries real changes in churn.
- Build the compiler with `./scripts/bootstrap-from-seed.sh --install .axiom-bin`. There is no Rust toolchain and no `cargo`.