# Follow a program through the compiler

Use the compiler's inspection commands to see a program's declarations,
effects and emitted code. This page connects those views and the
library conventions you meet while reading them.

```bash
axiom --diagnostic-format=ai check Main.ax
axiom --diagnostic-format=ai symbols Main.ax --calls
axiom --diagnostic-format=ai symbols Main.ax --mir --axir > Main.axir
axiom --diagnostic-format=ai emit-llvm Main.ax -o Main.ll
```

## The representations

| View | Contains | Where it fits |
|---|---|---|
| Tokens | Names, literals, delimiters and source spans | The lexer reads source bytes |
| Parsed AST | Declarations and expressions | The parser builds the syntax tree |
| Expanded AST | Resolved imports and expanded macros | Expansion precedes type checking |
| Checked AST | Types, resolved references and effect information | The backend reads the checked, expanded syntax |
| MIR facts | Region and escape facts, with lowered bodies where supported | Analysis and inspection alongside the AST |
| AXSYM | Declaration rows, stable IDs, tags, effects and optional call edges | `symbols` prints a tool-readable view |
| AXIR | Serialised inspection records, optionally including MIR bodies | `symbols --axir` writes or reads them |
| LLVM IR | Runtime helpers and target code | `emit-llvm` writes it; native builds optimise and assemble it |
| Object and executable | Machine code, then linked runtime and libraries | `llc` assembles; the target linker produces the image |

MIR and AXIR are inspection and analysis surfaces. Native compilation
uses the AST backend; an AXIR file is not a `build` input.
`symbols --mir` asks for the facts fixpoint and can take longer.

Tested by `scripts/check-mir-roundtrip.sh` and
`scripts/check-tools-selfhost.sh`.

## Find an imported module

A dotted name such as `Crypto.Random` maps to `Crypto/Random`.
For each suffix, the compiler searches the entry directory, manifest
dependencies and crates, `AXIOM_PATH`, command-line crates, then the
standard library. Suffixes run from `.<os>-<arch>.ax` to `.<os>.ax`
to `.ax`, so target-specific files have priority across roots.

`AXIOM_PATH` is a colon-separated list of module roots.
`AXIOM_STDLIB` selects the standard-library root; otherwise the
compiler searches beside its executable. `AXIOM_LINK_SEARCH` supplies
archive roots. The working directory contributes no implicit
`self_host/` or `stdlib/` root. See the
[module reference](reference.md#modules-and-imports) and [Rust linking](ffi.md).

## Recognise address and ownership types

| Value | Meaning | Obligation |
|---|---|---|
| `Int` used by `Mem` | A raw Axiom allocation address | Raw operations require valid ranges and Unsafe vouches |
| `Foreign` | A pointer crossing an `extern` boundary | Its external contract establishes validity; ARC does not follow it |
| `Handle` | A counted owner with a foreign destructor | Aliases share ownership; explicit close retires the resource |

The machine-word representation does not make these types
interchangeable. A generated sealed owner keeps its `Handle` private.
Use its generated operations to borrow or close the foreign object.
See the [memory model](memory-model.md) and
[FFI contracts](assurance/ffi-contract-audit.md).

## Choose a name or a new type

| Declaration | Effect |
|---|---|
| `(type Name = String)` | An alias; `Name` and `String` are interchangeable |
| `(subtype Percent is Int range 0..101)` | A distinct integer type; narrowing checks the range at run time |
| A `struct` or `data` wrapper | A nominal type with its own fields or constructors |
| A sealed struct | A wrapper whose constructor and fields stay private to its module |

Subtype ranges exclude their upper bound. Arithmetic uses the integer
representation; it does not statically prove a result remains in range.
See [type aliases](reference.md#type-aliases) and
[subtypes](reference.md#range-constrained-subtypes).

## Find the right library layer

`IO.println` and `IO.eprintln` are macros that format a value and write
a line. `IO.writeStr` writes existing bytes to a descriptor.
`Str.format` produces a string; `Fmt` contains the numeric formatters.
`Pre.when` and `Pre.unless` are macros, so import them before use.
Qualified access such as `IO::writeStr` identifies the owning module.
See the [generated API](stdlib-api.md) for exact signatures.

For entropy, `Sys.sysRandomBytes` fills caller-owned storage from the
kernel. `Crypto.Random.randomFill` wraps that source, or uses `RNDR` on
supported bare-metal CPUs. Both require a live writable range.
`secureRandomBytes` allocates the string for you and returns a `Result`.
See [cryptography](crypto.md).

`Chrono` keeps calendar values separate from the clock: its date-times
have no zone. `datetimeParseUtc` reads an offset-bearing timestamp and
normalises it to UTC, then returns a `NaiveDateTime` without an offset
field. The [date and time guide](chrono.md) explains this convention.

See also: [language reference](reference.md),
[symbol metadata](agent-tags.md) and
[compiler layout](../CONTRIBUTING.md#project-structure).
