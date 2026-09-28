# Axiom

![GitHub CI](https://github.com/chrispaig3/Axiom/actions/workflows/ci.yml/badge.svg)

**The functional systems language. High-level thinking, native-level control.**

<img width="1600" height="900" alt="Axiom — High-level thinking. Native-level control. Electric lime symbol and warm white wordmark on graphite." src="https://raw.githubusercontent.com/chrispaig3/Axiom/trunk/assets/logo/Axiom_Logo.png" />

Axiom lets you model your ideas with algebraic data types and
exhaustive pattern matching, check side effects at compile time, and
ship a native executable with no VM, no garbage collector and no calls
into the C library.

- **Ship the binary. That's it.** Programs compile through LLVM to a
  native executable that carries its own allocator and talks to the
  kernel directly.
- **Make side effects explicit.** The compiler infers effects, requires
  functions that perform I/O to say so, and checks promises like
  `restrict(no-io)`.
- **Find the problem. Keep moving.** Every error has a precise
  location, a stable code, often a fix your editor can apply, and a
  full explanation behind `axiom explain`.
- **Built for you and your agents.** The syntax is uniform
  S-expressions, and the compiler can describe errors and symbols in a
  compact machine-readable form, so tools see the same facts you do.
- **Read the compiler, in Axiom.** The compiler is written in Axiom:
  108,294 lines of it. A clean checkout rebuilds it from committed LLVM
  IR, and the build stops unless two generations come out
  byte-identical.
- **Bring Rust along.** Declare Rust functions in an `extern` block,
  and `axiom build --crate` builds and links the crate for you.

Axiom is young. The core language is complete, the standard library,
FFI and editor support are functional, and macros are partial. There is
no package index and no green threads yet. [What's ready today](docs/status.md) lists
every feature with the test behind it.

## Install

Axiom needs `llc` from LLVM, and a C compiler for the final link.

```bash
# macOS
xcode-select --install
brew install llvm
export PATH="$(brew --prefix llvm)/bin:$PATH"

# Debian and Ubuntu
sudo apt-get install -y llvm clang
```

Then install the compiler:

```bash
curl -fsSL https://raw.githubusercontent.com/chrispaig3/axiom/trunk/scripts/install.sh | bash
export PATH="$HOME/.axiom/bin:$PATH"
```

The installer downloads a prebuilt archive for macOS or Linux on arm64
and checks its SHA-256. Before it replaces anything, it builds and runs
a small program with the new compiler. It only ever replaces an
installation it made itself. On any other host it stops and points you
here.

On any other host, including `linux-x86_64`, build from source. The
repository carries the compiler's own LLVM IR in `bootstrap/`, so all
you need is the prerequisites above:

```bash
git clone https://github.com/chrispaig3/Axiom.git && cd Axiom
./scripts/bootstrap-from-seed.sh --install .axiom-bin
export PATH="$PWD/.axiom-bin:$PATH"
```

[CONTRIBUTING](CONTRIBUTING.md#quick-start) explains what the bootstrap
does.

### Targets

`--target` picks the platform to generate code for. That sets the
syscall ABI and the standard library's platform modules:

```bash
axiom --target=linux-x86_64 emit-llvm main.ax -o main.ll
```

Supported: `darwin-aarch64`, `darwin-x86_64`, `freebsd-x86_64`,
`linux-aarch64`, `linux-x86_64`, `windows-x86_64`. The default is your
host.

A target is supported when a CI job executes what the compiler emits
there. There are two exceptions to know about. `darwin-x86_64` predates
that rule and is executed by no runner, so it ships no prebuilt
archive. `freebsd-aarch64` is accepted by `--target`, and its output is
assembled and checked, but it is not supported: every runner GitHub
offers would have to emulate an aarch64 FreeBSD guest, which is too
slow to run the tests.

## Quick start

Start a project and run it:

```bash
axiom new hello && cd hello && axiom run
```

```text
Hello from Axiom! 🚀
```

`axiom new` writes `Main.ax` and an `axiom.pkg` manifest. Inside a
project, `run` and `build` need no file name.

Here is a slightly bigger program. Put it in `shapes.ax`:

```scheme
(import IO)

(data Shape
  (Circle { r : Float })
  (Rect { w : Float, h : Float })
  (Triangle { b : Float, h : Float }))

(:: area (-> Shape Float))
;@axiom:restrict(no-io)
(fn (area s)
  (match s
    ((Circle {r = r}) (* 3.14159 (* r r)))
    ((Rect {w = w, h = h}) (* w h))
    ((Triangle {b = b, h = h}) (/ (* b h) 2.0))))

(:: report (-> String Shape Int))
;@axiom:effect(io)
(fn (report name s)
  (let ((a (area s)))
    (println "{name:<10}{a:>8.2}")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report "circle" (Circle 2.0))
    (report "rect" (Rect 3.0 4.5))
    (report "triangle" (Triangle 4.0 3.0))
    0
  })
```

```bash
axiom run shapes.ax
```

```text
circle       12.57
rect         13.50
triangle      6.00
```

`Shape` is a sum type with named fields, and `area` handles every case.
`area` promises it performs no I/O, and the compiler holds it to that.
`report` prints, so it says so with `effect(io)`. Delete that line and
the compiler tells you the claim is missing.

When a `match` misses a case, the compiler names the case and offers
the fix:

<!-- doc-gate:source light.ax -->
```scheme
(data Light
  (Red)
  (Amber)
  (Green))

(:: next (-> Light Light))
(fn (next l)
  (match l
    ((Red) (Green))
    ((Green) (Amber))))
```

<!-- doc-gate:render light.ax human -->
```text
error[AX3005]: non-exhaustive pattern match: missing Amber
 --> light.ax:8:10
  |
8 |   (match l
  |          ^ this `match` does not cover: Amber
  |
  = help: add the missing arms, each a `todo` until it is written ~>
              ((Amber) (todo "Amber"))
  = help: import `todo` from IO ~>
          (import IO (todo))
  = help: run `axiom explain AX3005` for a full explanation

compilation failed due to 1 previous error
```

The commands you'll use most:

```bash
axiom run shapes.ax             # compile and run
axiom build shapes.ax -o shapes # keep the native executable
axiom check shapes.ax           # type-check and verify effects, no code generation
axiom test                      # run every function whose name starts with test
axiom fmt shapes.ax             # the one canonical layout
axiom explain AX3005            # the full explanation for any error code
axiom repl                      # Axiom 0.7.6 - REPL
```

`IO` is part of Axiom's own standard library, so the `shapes` binary
calls no C library function, for printing or for allocation.

For programs the size of real work, [`examples/`](examples/README.md)
has a batch job over a million records, and the generator that writes
this repository's standard library reference.

## Documentation

| | |
|---|---|
| [Language reference](docs/reference.md) | The whole language, from your first program to macros and memory |
| [Examples](examples/README.md) | Complete programs, each one run in CI |
| [What's ready today](docs/status.md) | Every feature's status, with the test behind it |
| [Standard library](docs/stdlib-api.md) | Every public function, generated from the source |
| [Effects](docs/reference.md#effects) | How effects are inferred, declared, restricted and handled |
| [Diagnostics](docs/diagnostics.md) | Error codes, and the machine-readable formats for tools |
| [Editor setup](docs/lsp.md) | The language server, and how to connect your editor |
| [Calling Rust](docs/ffi.md) | The `extern` block, bindings, and Rust calling Axiom |
| [Memory model](docs/memory-model.md) | Allocation, reference counting and regions, in full |
| [Error model](docs/error-model.md) | `Result`, `Error`, and how failure travels |
| [Agent harness](docs/agent-harness.md) | Tooling for agents that read and write Axiom |
| [Contributing](CONTRIBUTING.md) | Building the compiler, running the tests, and adding to them |

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md)
walks through the project layout, how the compiler works, and how to add
a diagnostic or a standard library function. The rule every change
follows is **if you claim it, gate it**: every claim is backed by a
test that runs in CI.

If Axiom is useful to you, [star the repository](https://github.com/chrispaig3/Axiom/stargazers)
so other people can find it, and [fork it](https://github.com/chrispaig3/Axiom/fork)
to start your first contribution.

## License

MIT. See [LICENSE](LICENSE).
