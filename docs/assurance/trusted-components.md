# Trusted components

This page lists what a program built by Axiom trusts. Each section
names what would have to be wrong for the program to misbehave while
every check in this repository passes. Every count comes with the
command that re-derives it, so a reader can check it against the tree
they have.

## The toolchain

These are trusted, and not verified here.

| Component | Role | Pinned? | Evidence |
|---|---|---|---|
| `bootstrap/axiom-*.ll`, the six seeds | The compiler every build descends from | Yes: `bootstrap/SHA256SUMS`, `bootstrap/STAMP`, and the lineage in `bootstrap/CHAIN` | `scripts/check-seed-provenance.sh`, `scripts/check-seed-lineage.sh` ([bootstrap/THREATS.md](../../bootstrap/THREATS.md)) |
| `opt`, `llc` | IR optimisation and code generation | No. They are found on `PATH`. H3's measurements used LLVM 23.1.2, and CI uses the runner image's package ([configurations.md](configurations.md)) | `scripts/check-cross-targets.sh` and `scripts/check-atomics.sh` read their output. Nothing verifies them |
| `cc`, `ld.lld`, `lld-link` | Linking: hosted, bare metal and Windows | No | `scripts/check-freestanding.sh` (no libc import), `scripts/check-embedded.sh` |
| `rustc`, `cargo` and crates | The FFI side and the lineage anchor only. The compiler's own build needs neither | The toolchain action is pinned, and crates by `Cargo.lock` | `scripts/check-ffi.sh`, `scripts/check-seed-lineage.sh` |
| `python3`, `bash`, `git` | The gate harness and `scripts/axiom-report.py` | No | They produce evidence, not code; see [Evidence tools](#evidence-tools) |
| QEMU (`qemu-system-aarch64`) | Emulator runs of the bare-metal image | No | Its results are labelled as emulator evidence |

A qualification argument must name a version for every row marked
"No" and archive it with the configuration
([qualification.md](qualification.md) §1).

## The emitted runtime

Every program carries a runtime that the compiler writes into its IR.
For `tests/embedded/blink.ax` on `baremetal-aarch64` it is 19
functions:

- the allocator and counts: `axiom_alloc`, `axiom_retain`,
  `axiom_release`, `__axiom_arena_reset_fn`;
- the trap exits: `__axiom_bad_mark`, `__axiom_div_by_zero`,
  `__axiom_out_of_memory`, `__axiom_out_of_memory_size`,
  `__axiom_refcount_exhausted`, `__axiom_no_syscall`,
  `__axiom_cpu_exception`;
- recovery: `__axiom_recover_abort`, `__axiom_recover_load`;
- the backtracer: `__axiom_backtrace`, `__axiom_bt_name`,
  `__axiom_lineinit`;
- the UART writers, on bare metal only: `__axiom_uart_write`,
  `__axiom_uart_hex`;
- `__axiom_user_main`.

A hosted program adds the parallel runtime when it spawns. To list
them for any program:

```bash
axiom emit-llvm --target baremetal-aarch64 tests/embedded/blink.ax -o blink.ll
grep -o 'define [^@]*@[a-z_A-Z]*axiom[a-z_A-Z]*' blink.ll
```

The runtime is emitted by `self_host/codegen.ax`, which holds 19
inline-assembly emission sites and 2 module-level assembly blocks
(`grep -c 'asm sideeffect'` and `grep -c 'module asm'` on that file).
They are the recovery point, the trap exits, the bare-metal reset and
exception vectors, the semihosting door, and the AArch64 device and
barrier primitives. No type system or model here sees into them.

What checks the runtime:

- the executable model (`scripts/check-runtime-model.sh`): the
  allocator, arenas and regions only;
- the runtime fixtures in `tests/stdlib/`, at every `--opt`;
- the recovery register-file audit (`scripts/check-recover.sh`);
- the atomics' machine code (`scripts/check-atomics.sh`);
- the vector table under QEMU (`scripts/check-embedded.sh` A12).

## The unsafe layer

Twenty-six primitives are `Unsafe`. Sixteen are general
(`isUnsafePrim` in `self_host/typecheck.ax`): `__load8`, `__store8`,
`__store8v`, `__load64`, `__store64`, `__alloc`, `__addr`, `__retain`,
`__release`, `__call_word`, `__atomic_load`, `__atomic_store`,
`__atomic_add`, `__atomic_cas`, `__axiom_arena_reset` and
`__axiom_arena_reset_keeping`. Ten are device primitives
(`isUnsafeDevicePrim`): `__vload8`, `__vload16`, `__vload32`,
`__vload64`, `__vstore8`, `__vstore16`, `__vstore32`, `__vstore64`,
`__arm_dc_cvac` and `__arm_dc_civac`.

A declaration that performs an unsafe operation must say
`;@axiom:effect(unsafe)` (`AX3073`, an error). There are three: one of
those primitives, a call to a precondition interface, and a cast that
forges a reference (`MM-EXEC-9d` in
[memory-model.md](../memory-model.md)). The tag gives the declaration
one of two roles:

- a *trusted encapsulation*, with the tag alone: its author vouches
  that every well-typed call is safe, and its callers inherit nothing;
- a *precondition interface*, with `;@axiom:precondition(...)` beside
  it: every call is the caller's unsafe operation, and the text says
  what the caller must make true.

The trusted encapsulations are what a program trusts without being
asked. Each is a promise the compiler records and doesn't check:

| Where | Tag lines `effect(unsafe)` | Of those, precondition interfaces | Command |
|---|---|---|---|
| `stdlib/` | 280 | 82 | `git grep -hE '^ *;@axiom:(effect\(unsafe\) *$\|precondition\()' -- stdlib \| cut -d'(' -f1 \| sort \| uniq -c` |
| `self_host/` | 1,525 | 0 | the same, over `self_host` |

A program's own trusted set, the standard library's included, is one
`grep` over `symbols`:

```bash
axiom --diagnostic-format=ai symbols main.ax | grep '#unsafe=trusted'
```

Over a probe that imports every standard module, that lists 193
trusted encapsulations and 82 precondition interfaces on
darwin-aarch64. The other five tag lines are in the baremetal and
Windows `Sys/Platform` files. The precondition interfaces are the raw layer:
`Mem`'s words and bytes, `Vec`'s and `Map`'s heterogeneous readers and
their frees, `Str`'s raw constructors, `Ffi`'s cells and handles,
`Sys`'s caller buffers, and `Task.taskFold`'s step. Their
preconditions are the memory contract's program obligations, each with
a disposition in [memory-audit.md](memory-audit.md).
`scripts/axiom-report.py` lists exactly the reachable subset for a
given program, as obligations.

In `self_host/` every tag is trusted. The compiler's records and AST
nodes are `Int` handles made and read only by the compiler, which is
on the trusted list above.

Two things stay outside the set. A handle or buffer typed `Int`, such
as a channel handle or a `Sys` buffer address, can be forged without a
cast, so the interface that reads it trusts its caller without a tag
saying so (`MM-PAR-8`). And a trusted encapsulation's promise is
checked by review, not by the compiler.

## Evidence tools

The gates (`scripts/check-*.sh`), their Python libraries
(`scripts/lib/*.py`) and `scripts/axiom-report.py` produce evidence,
not code. A defect in them can't corrupt a program. It can make a
property look verified when it isn't (HZ-T1 in [hazards.md](hazards.md)).
The control is the ablation rule: every check is shown to fail on a
planted defect, and planted controls run on every invocation
(`scripts/check-fuzz.sh` §4, `scripts/check-report.sh` §5,
`scripts/check-runtime-model.sh` §5).

## What isn't trusted

- The checker accepting a program doesn't mean the program is correct.
  The executable must still be verified against its requirements on
  the target.
- An emulator run isn't hardware evidence.
- AI-assisted implementation and review aren't independent assessment
  ([qualification.md](qualification.md) §4).
