---
name: axiom-helper
description: Guides for working with the Axiom compiler, ensuring correctness (proper diagnostic usage, AXTAG validation, exhaustive pattern matching), robustness (poison propagation, FFI safety, freestanding discipline), and productivity (quick reference commands, project structure, diagnostic code lookup, AXSYM symbol lookup).
---

# Axiom Helper — Agent Skill

## 1. Compiler invocation: always use `axiom --diagnostic-format=ai`

Every Axiom compiler command should pass the AI-optimized diagnostic
format:

```bash
axiom --diagnostic-format=ai check source.ax
axiom --diagnostic-format=ai build --input source.ax --output myprog
axiom --diagnostic-format=ai symbols source.ax
axiom --diagnostic-format=ai run source.ax
axiom --diagnostic-format=ai emit-llvm source.ax -o output.ll
```

`--diagnostic-format` is a global option and is accepted on either side
of the subcommand — `axiom check --diagnostic-format=ai f.ax` works too.
It produces one dense, greppable, colorless AXDL line per diagnostic: no
re-rendered source text, no ANSI codes, no Unicode box drawing. The
`human` renderer is the only coloured surface the compiler has, and it is
for human consumption; use it only when `ai` output is insufficient.

Diagnostics go to **stderr** in every format, including the trailing
`compilation failed due to N previous error` line. `check` answers `OK`
on stdout when nothing is wrong.

`axiom --help` is the authority on flags, and `scripts/check-driver.sh`
keeps it honest: every accepted flag and command must appear in `--help`.
Read it rather than guessing.

## 2. Project structure at a glance

```
axiom/
├── self_host/     # THE COMPILER, written in Axiom
├── stdlib/        # the standard library, also written in Axiom
├── bootstrap/     # the compiler's own LLVM IR, per target - the seed
├── tests/         # the corpus: selfhost, diagnostics, stdlib, fmt,
│                  #   frontend, lsp, repl, tools, docs, ffi
├── scripts/       # the gates; scripts/lib/gate.sh is their shared preamble
├── rust/          # the FFI side: axiom-bindgen, axiom-ffi, axiom-abi,
│                  #   the proc macros, and the example crates
├── tree-sitter-axiom/  # editor grammar, queries, tree-shape corpus
└── docs/          # docs/diagnostics.md is the AXDL/AXSYM reference
```

README.md's *Compiler structure* table is the normative per-module
description of `self_host/`; read it rather than re-deriving one. Three
modules it omits: `expand.ax` (macro expansion, its own pass, between
import resolution and the checker), `namespace.ax` (how a bare name
reaches a definition and which names may leave a module), and `style.ax`
(the ANSI colour, which only the human renderer imports).

The compiler pipeline is:

```
Source (.ax) → lexer.ax → parser.ax → expand.ax → typecheck.ax
             → codegen.ax → LLVM IR → llc → cc → Executable
```

Module dependencies flow one way, and the `(import ...)` lines are the
proof: `core` imports no compiler module; `lexer` imports `core`;
`parser` imports `lexer`; `expand`, `typecheck` and `codegen` import
`parser`; `driver` imports `codegen`; `main` imports everything. The
lexer does not know about types, and `codegen.ax` does not import
`typecheck.ax` — emission reads the AST and the mangled namespace, not
the checker's judgements.

## 3. Correctness patterns

### 3.1 Validate AXTAG annotations

AXTAG metadata (`;@axiom:<key>(<value>)` comments above declarations) is
compiler-checked. The most important validation is that `effect(io)`
claims match what the body actually performs — a `__syscallN`, a call to
something that performs one, or a call to an `extern` — and `pure` claims
match a body that performs nothing. A mismatch emits `AX3010`
(`axtag-mismatch`), an **error** since 2026-08-25: it fails the build,
so the exit status is enough. A claim the walk could not check is
`AX3037`, which is still a warning and still invisible to an agent
reading only the exit status.

When writing or reviewing Axiom source:
- Always pair `;@axiom:effect(io)` with code that actually reaches a
  syscall, directly or through a callee, or with a `handle` expression.
- Never annotate a function as `pure` if anything it calls performs an
  effect. Probed: a `;@axiom:pure` function whose body calls an `extern`
  reports `` `pure` claim contradicted: body performs IO ``.
- Use `axiom --diagnostic-format=ai symbols source.ax` to verify which
  AXTAG metadata was accepted (`#effect=io`, `#pure`, etc.). Tags the
  checker does not validate (`no_refactor`, `owned(arena=frame)`) are
  preserved and emitted unchecked.

### 3.2 Check pattern matching exhaustiveness

Axiom checks exhaustive pattern matching at compile time. Missing
constructors and wrong-arity constructor patterns are compile errors
(`AX3005` / `AX3009`). When writing `match` expressions, ensure every
constructor of the matched type is covered.

```scheme
;; Correct: all constructors covered
(match val
  ((Nothing) default)
  ((Just x) x))

;; Incorrect: Missing Nothing arm — compile error AX3005
(match val
  ((Just x) x))
```

The `AX3005` line names the constructors it did not find
(`"non-exhaustive pattern match: missing Nothing"`), so the fix is
mechanical: add those arms, or a `_` wildcard.

Nested constructor patterns are supported and checked recursively:

```scheme
(match lst
  ((Cons h (Cons h2 t)) ...)   ; correctly matches and binds h, h2, t
  ((Nil) ...))
```

### 3.3 Use stable diagnostic codes for pattern matching

Diagnostic codes are stable across wording changes. Never rename or reuse
a code — a retired code's number is burned, not recycled. Ranges are
namespaced by compiler stage:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis, type checking, macro expansion |
| `AX4xxx` | Codegen, the native toolchain, and extern grounding |
| `AX5xxx` | Module / import resolution |

Look up any code with `axiom explain AX3001` or see all codes with
`axiom explain --list`. That list is the registry, and
`scripts/check-doc-drift.sh` holds it to the tree in both directions:
every code with a construction site outside `explain.ax` is listed, and
every listed code has a construction site.

### 3.4 Poison propagation is the whole cascade story

When a type check fails, the checker reports once and then propagates the
**poison type** `TAG_T_ERR` (built by `mkTErr`, tested by `tyIsErr`)
rather than producing a fresh diagnostic for every downstream use.
`tyCompat` treats poison on either side as compatible with anything, and
it tests for poison *before* it tests for type variables — getting that
order wrong turns cascade suppression off for every poisoned type at
once.

Two details worth knowing before you add a diagnostic site:

- **Poison preserves shape where shape is load-bearing.**
  `tyPoisonUnknown` poisons the unknown *parts* of a signature and keeps
  the arrows, because a wholly poisoned signature reads to later passes
  as "every parameter is `Int`". One bad signature and four calls used to
  give five errors; this is what stops it.
- **Spanlessness is the second suppression, and it is exercised.** A node
  with no span suppresses its diagnostic rather than pointing it
  somewhere wrong. There are ten `span == 0` guards in
  `self_host/typecheck.ax`, and they are why a diagnostic never lands on
  line 1 column 1 by accident.

There is no dedup pass and no diagnostic grouping. AXDL has no `group`
field; if you are looking for one in the output, nothing emits it. The
Rust compiler carried a `group` key and a dedup pass with no call sites,
and neither was carried across. If a cascade ever turns up that poisoning
and the span guards cannot prevent, that is when to build one — with a
call site, rather than ahead of one.

### 3.5 Never duplicate diagnostic logic across renderers

All compiler messages go through `mkDiag` (`self_host/diag.ax`) with a
stable code, severity, span, and message. Never print raw strings from
compiler phases. When adding a new diagnostic, construct it at the site
that detects the condition and write its long-form text into
`self_host/explain.ax`: `scripts/check-tools-selfhost.sh` fails if a code
the corpus emits has no entry, and `scripts/check-doc-drift.sh` fails in
the other direction too.

## 4. Robustness patterns

### 4.1 Understand AXDL parsing rules

AXDL lines follow this grammar:

```
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [#"<label>"]
     [^<LOC>:"<related>"]* [!"<note>"]* [?<field>]* [&"<frame>"]*
```

- `SEV` is `E` (error) or `W` (warning). `N` and `H` are **reserved and
  never emitted**: a note and a help are FIELDS of a diagnostic (`!` and
  `?`), not diagnostics of their own. Only `E` fails a build.
- `LOC` is `file:line:col`, `file:line:col-col`, or `file:line:col-line:col`
- Slug is kebab-case and wording-independent
- Machine-applicable fixes use `~>` in the `?` field
- `&` is the macro expansion backtrace, outermost first. Uniquely among
  the line's fields its `FILE` is *not* the diagnostic's own — it indexes
  the macro's declaration in the macro's file.
- Fields appear in exactly the order above and every starred one repeats.
  A consumer that meets a field it does not know should fail rather than
  skip it.

**Parsing pitfall**: `"msg"` and `"replacement"` are Rust `Debug`-style
escaped strings, so a diagnostic is guaranteed to stay on one line. A
correct consumer must parse each quoted field as a proper escaped string
and only look for `~>` in the unquoted gap *between* fields — never do a
naive `str.split("~>")`, which can misfire if `~>` appears inside the
message itself.

`docs/diagnostics.md` is the normative AXDL and AXSYM reference.

### 4.2 Standard library and FFI safety

Axiom has a standard library written in Axiom (`stdlib/`: `Sys`, `Mem`,
`Str`, `Fmt`, `IO`, `Vec`, `Map`, `Json`, `Path`, `Utf8`, `Err`, `Ffi`,
`Intern`, `Show`, `Pre`, `Job`, `Rpc`), built on the freestanding
primitives `__syscall0`-`__syscall6`, `__load8`/`__store8`,
`__load64`/`__store64`, `__alloc`, and `__addr`. Use it: `(import IO)`
and `println`. Generated code calls no libc function, and
`scripts/check-freestanding.sh` enforces that in both directions — no
libc call in the emitted IR, and no libc symbol imported by the linked
executable.

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

Rules that matter when writing one:

- The type goes INLINE in the block. A separate `(:: name Type)` beside
  it is redundant.
- An extern's signature names only `Int`, `Float`, `Bool`, `Char`,
  `String` and `Foreign` — one machine word each way. A type variable, a
  `Handle`, or any other shape is `AX3036`, and the diagnostic's help
  field lists the permitted set. A polymorphic extern would make the
  emitter add a hidden evidence word that must never reach Rust.
- Calling an extern contributes the `IO` effect, exactly as calling
  `__syscallN` does, and it propagates transitively - so a caller two
  hops away needs `;@axiom:effect(io)`.
- Write `(symbol "...")` explicitly. A static link is one flat
  namespace and the default is the Axiom name.
- An opaque pointer crossing the boundary is typed `Foreign`, never
  `Int`. It is a real builtin type and the distinction is load-bearing: a
  `Foreign` field is kept out of the ARC reference map, so the release
  walk never follows it. Passing a `Foreign` where `Int` is declared is
  `AX3004`. On the Axiom side that pointer is usually wrapped in a
  `Handle` — a counted block carrying the Rust destructor, so the Rust
  value dies when its last Axiom holder does — via `ffiHandleNew` in
  `stdlib/Ffi.ax`.
- A shim returning bytes, or one that can fail, takes a trailing
  out-cell; its raw binding gets a `Raw` suffix and `axiom-bindgen`
  writes the Axiom wrapper. Do not hand-write those - regenerate.

Prefer `axiom build --crate DIR` over hand-writing a block: the driver
runs `axiom-bindgen` when the generated module is missing or older than
`DIR/src`, runs `cargo build --release` when the archive is missing, and
links it. `cargo run -p axiom-bindgen` and `cargo install --path
rust/axiom-bindgen` are the by-hand routes; see `docs/ffi.md` and
`rust/README.md`. `scripts/check-ffi.sh` is the gate, it enumerates
permitted external symbols rather than forbidding all of them
(`docs/memory-model.md` MM-FFI-5), and it *skips* when `cargo` is not on
`PATH` rather than failing.

- Sanitize file paths before passing them to native toolchain
  invocations (`opt`, `llc`, `cc`, `ar`). Never pass unsanitized user
  input to a shell. `driver.ax`'s `runTool` spawns them with an explicit
  argument vector through `stdlib/Sys.ax`'s `sysRunPath`/`sysSpawn`,
  never through a shell, and it should stay that way.

### 4.3 Memory safety discipline

Axiom source has no `malloc` and no `free`: allocation goes through the
backend's `mmap`-backed bump allocator. **The allocator is not
overridable.** Defining `axiom_alloc` yourself is refused outright with
`AX3026` (`reserved-runtime-name`) — the backend emits its own definition
unconditionally, and before that refusal existed the build died in `opt`
as a duplicate symbol after `check` had said OK. `union`, `region` and
`foreign` have been removed from the language - all three are still
reserved words and report `AX2004`. C is reachable only through an
`extern` block, and a Rust crate that is `no_std` reaches it without
importing any libc symbol at all - measured, `nm -u` on such an
executable is empty.

### 4.4 Handle input validation at every pipeline stage

All user-provided source files must be validated at every pipeline stage.
A malformed input must produce a diagnostic, not a panic or segfault. The
compiler never executes arbitrary code from source files during
compilation: code generation produces standalone LLVM IR, and even macro
expansion runs no user code — the `syntax/*` query vocabulary is closed
and compiler-implemented, and it answers from the declaration list at
expansion time.

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

# Compile and run immediately (further ARGS are forwarded to the program)
axiom --diagnostic-format=ai run source.ax

# Build against a Rust crate: bindgen, cargo and the link line, together
axiom --diagnostic-format=ai build --input source.ax --output program --crate /path/to/crate

# Start interactive REPL
axiom repl --no-banner

# Look up a diagnostic code
axiom explain AX3001

# List all known diagnostic codes
axiom explain --list

# List every top-level symbol and its type (AXSYM notation)
axiom --diagnostic-format=ai symbols source.ax

# Same, including always-in-scope built-in operators
axiom --diagnostic-format=ai symbols source.ax --builtins

# Verify AXTAG annotations were accepted (`#effect=io`, `#pure`, ...)
axiom --diagnostic-format=ai symbols source.ax | grep -E '#(effect|pure)'
```

Exit statuses are distinct and worth branching on: `1` the program is
wrong, `2` the command line is wrong, `3` a module could not be read or
parsed or the target name is unknown, `4` a native tool (`llc`, `cc`)
failed or is missing.

### 5.2 Use AXSYM to understand a codebase without re-reading it

`axiom --diagnostic-format=ai symbols source.ax` produces one line per
top-level declaration:

| KIND | Meaning |
|---|---|
| `F` | Function |
| `D` | Data type |
| `C` | Constructor |
| `S` | Struct |
| `A` | Type alias |
| `T` | Trait |

Real output for a file declaring a `data`, a `struct`, a `trait` and two
functions:

```
F add main.ax:10:5-8 "(Int -> (Int -> Int))" @27bcb2cac184465e
F main main.ax:13:6-10 "Int" @6159d363201f7f2a
D Option - "data Option" #ctors=Some,None
C Some - "(a -> Option a)" #of=Option
C None - "Option a" #of=Option
D Maybe main.ax:1:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
C Nothing main.ax:2:4-11 "Maybe a" #of=Maybe
C Just main.ax:3:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:5:9-14 "struct Point" @aa47cd1e9254cc56 #fields=x:Int,y:Int
T Eq main.ax:7:9-11 "trait Eq" @ddac825b09c14c67 #methods=
```

Three things to read off that:

- `@<hex>` is the **NID**, a content-derived id from `(kind, name)`. It
  survives edits elsewhere in the file, which `file:line:col` does not.
- A `-` in the location column means the symbol has no source span. The
  prelude's `Option`/`Some`/`None` arrive that way; the built-in
  operators are omitted entirely unless `--builtins` is passed.
- For a program with imports, `FILE` is the file that actually declared
  the symbol, not the entry file.

An agent asked to "add a function that formats a `Maybe Int`" can
`grep '^D Maybe'` and `grep '^C '` for the exact constructor set, and
`grep '^S Point'` for a struct's exact field shapes, instead of
re-reading the whole file.

### 5.3 Module imports resolution

Dotted module paths map directly to file paths relative to the entry file's directory:

```scheme
; Math/Ops.ax defines `square` as `(pub fn (square x) ...)`
(import Math.Ops (square))    ; brings in only `square`
(import Math.Ops)             ; brings in every `pub` decl - and only those
```

Key facts:
- Imports are transitive and diamond-safe (merged exactly once).
- Qualified access via `Mod::name` is supported. By default, imported declarations join the flat top-level namespace, but `Mod::name` disambiguates when the same name exists in multiple modules.
- Only `pub` declarations leave a module. A reference to a name that
  exists in a module that does not export it is `AX3023`
  (`private-name`), which is a *different* mistake from `AX3001`, a name
  defined nowhere.
- A bare name that two imported modules both define is `AX3014`
  (`ambiguous-name`); qualify it.
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

**Brace blocks for sequencing** — the value of the block is its last
expression:
```scheme
{
  (println "Starting...")
  (println "Working...")
  0
}
```

There is no `printf` and no `print` — probed, both are `AX3001`. `IO`'s
`println` and `writeStr`, and `Fmt`'s formatters, are the surface.

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
:help / :h            — Show all commands
:quit / :q / :exit    — Exit the REPL
:type <expr> / :t     — Show the type of an expression
:load <file> / :l     — Load a file into the REPL
:reset / :r           — Clear all definitions
:defs / :d            — Show all definitions in scope
:llvm <expr>          — Show the generated LLVM IR
:time <expr>          — Time an expression
```

Only lines beginning with `:` are dispatched as commands. The REPL's own
`:help` text advertises a bare `?` as a synonym; it is not one, and `?`
is read as an expression and fails to parse.

The REPL compiles to native code, not interpretation: declarations
accumulate as source text, and each expression is wrapped in a generated
module, compiled through the driver's own `llc`/`cc` invocations, run,
and its output reprinted as `result ...`.

There is **no line editing and no history**. The REPL reads plain lines,
with no readline layer, so arrow keys, in-place editing and a history
file do not exist and nothing is saved between sessions — its `:help`
text says otherwise. The editor-grade interface is the LSP's job
(`self_host/lsp.ax`, `axiom lsp`).

### 5.6 Diagnostic code lookup workflow

When you encounter an error code in AXDL output:
1. Run `axiom explain AX####` (e.g., `axiom explain AX3001`) to get the full explanation.
2. If the line carries a `?LOC:"msg"~>"replacement"` field, apply the
   replacement as a byte-range substitution — do not parse the English
   prose.
3. Fix the first error before re-reading the rest. Poison propagation
   means later errors are usually already suppressed, so what remains
   after the first fix is a different question, not the same one.
4. Verify the fix by re-running `axiom --diagnostic-format=ai check source.ax` and confirming zero errors.
5. Check for `W` lines even on a successful build. `AX3010` moves the
   exit status now, but `AX3037`/`AX3038`/`AX3039` do not — and those
   are the AXTAG claims the compiler could NOT check, which is the set
   worth reading by hand.

### 5.7 Testing and validation

- Unit tests are Axiom programs under `tests/selfhost/`, each carrying an
  `; expect N` first line naming the exit status it should produce.
  `scripts/check-self-host.sh` runs them with the self-hosted compiler and
  `scripts/check-bootstrap.sh` runs them again on the ladder built from
  the seed. A case with no `; expect N` is a failure, not a skip.
- Every diagnostic code the corpus emits must be explained;
  `scripts/check-tools-selfhost.sh` cross-checks that against
  `explain --list`, and `scripts/check-doc-drift.sh` checks the reverse.
- Renderer output is pinned by the goldens under `tests/diagnostics/` -
  `.axdl`, `.human` and `.json` per case - each with a half that a
  re-bless cannot satisfy. Regenerate deliberately with `AXIOM_BLESS=1`,
  never casually.
- The gates share one preamble, `scripts/lib/gate.sh`. A gate opens with
  `gate_init` and `gate_build_axc axc`, after which `$repo_root`,
  `$axiom`, `$work` and `$axc` mean what they mean everywhere else.
- Do NOT run `axiom fmt` over the repository: the tree is deliberately
  not kept in the formatter's normal form (CONTRIBUTING.md says so), and
  reformatting it buries real changes in churn.
- Build the compiler with `./scripts/bootstrap-from-seed.sh --install
  .axiom-bin`. That path needs `llc` and `cc` and nothing else — no
  `cargo`, no `rustc`. The Rust toolchain is needed only for the FFI side
  (`rust/`, `axiom-bindgen`, `scripts/check-ffi.sh`), which skips when
  `cargo` is absent.
