# Axiom

![GitHub CI](https://github.com/chrispaig3/Axiom/actions/workflows/ci.yml/badge.svg)

**A functional systems language that ships a binary, not a runtime.**

<img width="1500" height="1024" alt="Image" src="https://github.com/user-attachments/assets/38a9afb6-3570-4797-ba57-488e004f4e66" />

> Algebraic data types, exhaustive matching and an effect system the compiler checks, lowered through LLVM to a native executable with no VM, no collector and no libc inside it.

The compiler is written in Axiom: 103,476 lines of it, which rebuild
themselves from a committed LLVM seed until two successive compilers are
**byte-identical**. And because the syntax is uniform S-expressions with a
machine-readable diagnostic surface (`AXSYM`, `AXDL`, content-derived `NID`s,
`--diagnostic-format=ai`), it is as legible to an agent generating code as to
the person reviewing it. That was a design goal, not an afterthought.

**Where this fits:** if you want a small, explicit, statically-typed language
that produces a self-contained binary you can reason about instruction by
instruction — and you would rather have a compiler that argues with you than
one that guesses — Axiom is built for you. If you want a mature ecosystem, a
package registry, or green threads, it is not there yet, and
[Implementation status](docs/status.md) says exactly how far each piece has
got.

---

## A whole program

```scheme
(import IO)

(data Shape
  (Circle Int)
  (Square Int))

(:: area (-> Shape Int))

(fn (area s)
  (match s
    ((Circle r) (* 3 (* r r)))
    ((Square w) (* w w))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((a (area (Circle 4))))
    {
      (println "area = {a}")
      0
    }
  )
)
```

Algebraic data types; a `match` the compiler proves exhaustive; string
interpolation that calls the compiler's own renderer, chosen from the static
type of the hole; and an effect the checker verified against what the body
does. Drop the `Square` arm and it does not compile.
[The language reference](docs/reference.md) has the rest.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chrispaig3/axiom/trunk/scripts/install.sh | bash
export PATH="$HOME/.axiom/bin:$PATH"
```

It verifies the archive's SHA-256, then builds and runs a program that
*imports a standard-library module* before reporting success. Archives are
published for `linux-aarch64` and `darwin-aarch64`; on any other host it says
so and points here. `linux-x86_64` is fully supported and tested — its CI leg
runs the whole battery — it just has no prebuilt archive.

Building from a checkout needs no compiler: `bootstrap/` carries the
compiler's own LLVM IR, one file per target.

```bash
git clone https://github.com/chrispaig3/Axiom.git && cd Axiom
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

[CONTRIBUTING § Quick Start](CONTRIBUTING.md#quick-start) has the
prerequisites per platform and what the bootstrap is doing.

## Quick start

Put this in `hello.ax`:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello from Axiom! 🚀")
    0
  })
```

```bash
axiom run hello.ax                              # compile and run
axiom build --input hello.ax --output hello     # or keep the binary
axiom explain AX3042                            # every code has a full explanation
axiom repl                                      # Axiom 0.7.5 - REPL
```

`IO` is Axiom's own standard library — that binary calls no C function, not
for printing, not for allocation. Delete the `;@axiom:effect(io)` line and
the compiler tells you the claim is missing, with the path to the syscall.

For something the size of a real program, [`examples/`](examples/README.md)
holds a web server, a batch job over a million records, and the generator
that writes this repository's own API reference. Every one of them is run by
a gate in CI, which is the only reason they still work.

### Targets

`--target` selects the platform to generate code for, and with it both the
syscall ABI and which platform modules the standard library resolves to:

```bash
axiom --target=linux-x86_64 emit-llvm main.ax -o main.ll
```

Supported: `darwin-aarch64`, `darwin-x86_64`, `freebsd-x86_64`,
`linux-aarch64`, `linux-x86_64`, `windows-x86_64`. Defaults to the host.

**A target joins that list when a CI leg executes what the compiler emits
there.** That is the definition of *supported* in this repository, stated
here once; `docs/reference.md`, `SECURITY.md` and `CONTRIBUTING.md` point at
this paragraph rather than restating it, and `scripts/check-doc-drift.sh`
holds the copies of the list to each other and to the compiler's own
`--target` table.

Two standing exceptions, named rather than left quiet. `darwin-x86_64`
predates the rule and is executed by no runner, which is why it ships no
artifact; `freebsd-aarch64` is assembled and relocation-checked but is
executed by no runner either, because an aarch64 guest is TCG-emulated on
every runner GitHub offers and the 300-minute budget was measured and
dropped. `scripts/check-release-targets.sh` requires that sentence to be
here: a target that is supported, ships nothing, and is tested nowhere makes
the word mean nothing, so silence about one is a gate failure.

---

## Documentation

| | |
|---|---|
| [Language reference](docs/reference.md) | The whole language, section by section |
| [Examples](examples/README.md) | Worked programs — a web server, a batch job, an API-reference generator — each one pinned by a gate |
| [Implementation status](docs/status.md) | What is complete, functional, or partial — with the fixture that proves each row |
| [Standard library API](docs/stdlib-api.md) | Every public name, generated from the source and gated against it |
| [Diagnostics](docs/diagnostics.md) | `AXDL`, `AXSYM`, `NID`, and the agent-facing output formats |
| [Memory model](docs/memory-model.md) | The allocator, reference counting, regions, and every rule's probe |
| [Error model](docs/error-model.md) | `Result`, `Error`, and how failure travels |
| [FFI](docs/ffi.md) | Calling Rust, and Rust calling Axiom |
| [Effects](docs/reference.md#effects) | Declaring, handling, and what the compiler checks |
| [Agent harness](docs/agent-harness.md) | The tooling built on the machine-readable surface |
| [CONTRIBUTING](CONTRIBUTING.md) | Building, testing, the gate battery, and how to add to it |

---

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has
the project layout, how the compiler works, how to add a diagnostic or a
standard-library function, and the rule every change here is held to: **if
you claim it, gate it.**

> **Like what you see?** [⭐ Star the repo](https://github.com/chrispaig3/Axiom/stargazers)
> and [🍴 fork it](https://github.com/chrispaig3/Axiom/fork) — a star helps
> other people find Axiom, and a fork is where your first contribution starts.

## License

MIT — see [LICENSE](LICENSE).
