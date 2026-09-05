# Embedded Axiom — a proposal

<!-- STATUS, at the top where a reader stops: this document is a
     PROPOSAL, and three of its numbered items are now built. 4.6
     shipped in 0.7.5; 4.1 and 4.2 ship here. Each is struck in section
     8's table and rewritten in place to say what landed and what the
     proposal got wrong about it. 4.3, 4.4, 4.5 and the section 6
     reference port are still proposals, and nothing in them exists.
     Sections 2 and 3 are MEASUREMENTS taken on 2026-09-03 against the
     tree at that commit, with the command beside each, and they are
     the reason the proposal is worth writing.

     `docs/generics-design.md` is the template for this banner. When a
     numbered item here ships, strike it in section 8's table and say
     which commit did it - a design document whose reader has to guess
     which half is real is the failure mode this repository has already
     recorded twice. -->

## 1. Why this is a short document

Most languages proposing an embedded story have to subtract: a garbage
collector, a runtime, a scheduler, a C library, exception tables. Axiom
has none of those to remove. It is already a freestanding language that
emits a static binary and reaches the kernel through raw syscalls, and
`scripts/check-freestanding.sh` fails the build if that stops being true
at either level — no libc call in the emitted IR, and no libc symbol in
the linked executable.

So the question is not "can Axiom be made small". It is "which of the
three assumptions it makes about a hosted operating system have to
become configurable", and the answer is a short list.

## 2. The measured baseline

Every figure here was taken on darwin-aarch64 at 0.6.3, with the command
shown. Re-run them rather than quoting them.

| | measured | how |
|---|---|---|
| minimal program, `--opt 2` | **17,472 bytes** | `(fn (main) 0)`, `stat -f%z` |
| hello world with `IO` | **34,856 bytes** | `(println "hi")` |
| undefined symbols, either | **0** | `nm -u` |
| distinct syscalls, minimal program | **3** | `mmap`, `write`, `exit` — see below |
| runtime globals | 30 | `grep -cE '^@__axiom' min.ll` |
| emitted IR, minimal program | 570 lines | `wc -l min.ll` |
| stack floor, hello world, whole process | runs in **32 KiB**, fails at 16 | `ulimit -s`, bisected |
| stack, hello world, the Axiom program itself | **192 bytes** | `scripts/check-stack-bound.sh`, computed |
| arena chunk | **1 MiB**, per target | `MM-ALLOC-4`; `targetArenaChunkBytes`, pinned per target by `check-embedded.sh` (it was a literal in `emitAllocator` until 4.1) |

**The three syscalls are the whole of it, and that is the finding.** A
minimal Axiom program makes exactly three kinds of kernel call:

* `mmap` — one, to map the first arena chunk;
* `write` — only on a trap path, to put the message on fd 2;
* `exit` — to leave.

Everything else in those 570 lines is arithmetic on memory the program
already has. There is no dynamic loader, no relocation processing at
startup, no C runtime init, no atexit table, no locale, no `errno`.

## 3. What Axiom already has that an embedded target wants

* **A per-target syscall ABI, chosen at compile time.**
  `self_host/Host.<target>.ax` and `stdlib/Sys/Platform.<target>.ax` are
  the two files a target owns, and `--target` selects them. Adding a
  target is adding two files, not editing a hundred call sites.
* **Scope-based reclamation.** `region` (MM-RGN-1) reclaims everything
  allocated in a scope at its end, in constant time, with no traversal.
  On a device with no swap and a hard ceiling, this is the allocation
  discipline you want, and it is a language form rather than a
  convention.
* **A static refusal for recursion.** `;@axiom:restrict(no-recursion)`
  is a claim the compiler checks against the call graph
  (`scripts/check-restrictions.sh`), which is how a bounded stack becomes
  provable rather than hoped for.
* **A working freestanding Rust runtime as a worked example.**
  `rust/axiom-ffi/src/nostd_runtime.rs` already does, for the Rust side
  of the FFI, exactly what an embedded port must do for the Axiom side:
  raw `asm!` syscalls for four targets, a `GlobalAlloc` over
  `axiom_alloc`, a panic handler, and hand-written `memcpy`/`memset`/
  `strlen`. It is the shape of the answer, in the tree, compiling today.
* **Determinism.** No JIT, no adaptive anything. The arena's growth
  policy is "there isn't one" (MM-ALLOC-4), which is a liability on a
  server and an asset on a device: allocation is a bump and a compare.

## 4. What has to change — proposed, ranked by what blocks what

### 4.1 The 1 MiB chunk must become a target constant *(done — `check-embedded.sh`)*

It is `targetArenaChunkBytes`, in `self_host/codegen.ax`'s target table
beside `targetMmapNum` and the rest of the per-target numbers. Every
supported target answers 1 MiB, so every supported target emits the
allocator it always emitted — measured rather than argued: the seven
targets' `emit-llvm` output for three probes is byte-identical across
the change, and `check-embedded.sh`'s A1 pins the four lines per target
so that it stays so.

**This proposal named the wrong file, and following it would have
shipped the bug it exists to remove.** `Host.<target>.ax` answers
`hostTarget` — the target the compiler BINARY was itself compiled for,
selected by module resolution when the compiler is built, and read only
as the default when no `--target` is given. It is not the target a
program is being compiled *for*. `arenaChunkBytes` there would give a
darwin-hosted compiler cross-compiling to a bare-metal part darwin's
megabyte, silently. The constants are keyed by the target CODE instead,
which is what "the way the syscall numbers already are" actually means.

**A second constant came with it**, because the two are not
independent. `refill:` rounds a request LARGER than one chunk up to a
64 KiB grain, and a 4 KiB-chunk target that rounded a 5 KiB request to
64 KiB would ask for sixteen chunks' worth to serve one — against the
32 KiB static region section 5 budgets, that is an out-of-memory trap
for a request the arena has room for. `targetArenaGrainBytes` is
therefore the chunk where the chunk is the smaller, 64 KiB otherwise,
so no supported target moves. It has two emission sites, not one:
`emitArenaKeepHelper` is the arena's SECOND allocation path and rounds
the same way, and `check-embedded.sh` covers both.

The chunk-list walk, the mark/reset protocol and MM-ALLOC-14's overlap
rules are all size-independent, as this said; nothing else in the
allocator changed.

### 4.2 `mmap` must become an optional strategy *(done — `check-embedded.sh`)*

`targetArenaStaticBytes` is 0 on every supported target, and 0 means
`mmap` (or `VirtualAlloc`). Non-zero is a single region of that many
bytes, and `emitRuntimeMap` — the one door every chunk in the program
arrives through — branches on it at EMISSION time, so an emitted
program contains exactly one of the two and the other costs it nothing,
not even a branch. `targetArenaStaticBase` says where the region is:
zero means the emitter reserves it as a zero-initialised global and the
LINKER fixes the address, which is what a part with a normal `.bss`
wants; non-zero is an absolute SRAM window the board knows and no
`.bss` covers.

The static door is ten instructions with no branch and no call
(`emitArenaCarve`), because its two call sites read `%addr` and test it
themselves — a door that introduced a basic block would rewrite control
flow that the reset protocol and MM-ALLOC-14 both stand on. It ANSWERS
0 when the region is exhausted, which is below the `%failed_low` test
that already catches a refused `mmap`, so exhaustion reaches
`__axiom_out_of_memory` and exits 70 through the existing path: the
failure semantics needed no new design, exactly as this said.

**It runs, which is the half an emission check cannot establish.** With
the host target given a 256 KiB region and a 4 KiB chunk, a program
that allocates 52,800 bytes across fifteen chunks prints what the
`mmap` build of the same source prints, and a program that asks for
1,056,000 bytes exits 70 while the `mmap` build of THAT source exits 0
— so the 70 is the region's verdict and not the program's size. The
minimal program's three syscalls become two, and the one that leaves is
`mmap`.

**One other site still maps, and it is not this item's to close.** The
concurrency lowering asks for a 4 KiB `MAP_SHARED` page per binding —
how a forked child hands its result back. A statically reserved region
cannot stand in for it: the property wanted there is that the page
survives `fork` and is visible in *both* processes, and a `.bss` array
is copied. So a program that spells `parallel` still names `mmap` on a
static target. That is section 7's "threads are out of scope" arriving
for processes as well, and a bare-metal port answers it the way
windows-x86_64 already does — both primitives compile to a trap that
says so. It is named here rather than left for someone to find in the
IR.

**Two things this needed that it did not say.** *The trap's sentence
was false.* `__axiom_out_of_memory` printed `axiom: out of memory (mmap
failed)` on a target with no `mmap`; it now names the strategy that ran
out, with the status unmoved and a hosted target's bytes unmoved.
*Threads.* Under `--threads` the runtime's mutable globals become
`thread_local`, so every thread would start its bump pointer from a
cursor initialised to the same base and carve the same bytes twice,
while sharing the cursor instead makes it a data race on the one word
the whole heap is built from. A static target therefore answers no to
`targetHasThreads`, and `--threads` on one is refused as `AX4006`,
which already means precisely that. Section 7 puts threads out of scope
for bare metal; this is what that costs in code.

### 4.3 The trap path must be able to reach something other than fd 2

`write(2, msg, len)` is how every trap reports. A device may have a
UART, a semihosting channel, or nothing. Proposed: the target module
supplies `trapWrite`, defaulting to today's `write` on hosted targets;
on a bare-metal target it is whatever the board offers, or a no-op that
still exits with the right status. **The status codes must not change** —
`tests/stdlib/465-pop-empty-trap.exit` and its siblings pin them, and
they are the only thing an automated test on-device can observe.

### 4.4 A `--no-std`-shaped subset of the standard library

`Sys`, `IO`, `Path`, `Http`, `Rpc` and `Par` all assume a filesystem, a
process model, or sockets. `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`,
`Utf8` and `Err` do not. Proposed: mark the second group as the
freestanding subset and gate it — a probe that imports only those and
builds for a bare-metal target must produce a binary importing nothing
but the target's own primitives. That gate is a variant of
`check-freestanding.sh` and should be written *before* the port, because
it is what makes the subset a fact rather than an intention.

### 4.5 Interrupt handlers need an entry-point form

An ISR is a function the hardware calls with a fixed name and no
arguments, which must not allocate. Both halves already exist
separately: `--emit-staticlib` makes every `pub fn` a C symbol, and
`;@axiom:restrict(no-alloc)` is checked. Proposed: a target attribute
that combines them and additionally refuses a non-empty parameter list,
so an ISR that allocates is a compile error rather than a heap
corruption at 3 a.m.

### 4.6 A static stack bound from the call graph *(done — `check-stack-bound.sh`)*

This was the item to do first, and it is done. `scripts/lib/stack-bound.py`
computes the longest weighted path through a program's call graph and
reports "this binary needs at most N bytes of stack"; it REFUSES, naming
the site, when the question has no static answer — a cycle, a dynamic
frame, an extern whose frame is unknown, a function address it cannot
classify. `scripts/check-stack-bound.sh` gates it with twelve assertions
and three ablations.

**Two things this proposal said, that measurement contradicted.**

*"The emitter knows each frame's size."* It does not, and cannot. Axiom
emits LLVM **text** IR and shells out (`self_host/driver.ax`, `IR → opt →
llc → cc`); frame layout is LLVM's register allocator's decision, taken
after `codegen.ax` has stopped running. A number computed inside
`codegen.ax` would be either unsound or a large over-estimate. So the
sizes come from the same `llc` invocation the driver already makes:
llc's own `--stack-usage-file` where the toolchain has it (LLVM 19+),
and otherwise a prologue parse of `llc -filetype=asm`. The two are
cross-checked against each other over all **3,767** functions of the
compiler — 3,767 agree, 0 disagree — which is what earns the portable
parse its trust on a toolchain that offers no table.

*"Hello world needs 32 KiB of stack."* That figure is the **host
process's** dyld and libc startup, not the Axiom program. The program's
own need is **192 bytes**, and A6 gates it. The old number was measured
correctly and interpreted wrongly: bisecting `ulimit -s` on a binary
measures everything the process does, including everything that runs
before `main`.

**What made a precise answer possible**, both measured rather than
assumed:

* Every one of the compiler's 3,767 frames is reported `static`. There
  is no dynamic `alloca` anywhere in emitted IR, so a frame is a
  constant and a path is a sum. Nothing asserted this before; A3 does.
* The whole self-hosted compiler contains exactly **one** indirect call
  site (the foreign drop glue in `axiom_release`) and, once the
  backtrace symbol table `@__axiom_symtab` is excluded, **zero**
  address-taken functions. That site is therefore provably dead, and
  hello world gets a real bound rather than a refusal. A closure
  program, by contrast, resolves to exactly its own lambda and stays
  precise.

**The arithmetic is checked against a measurement**, because a computed
number nothing measures is a comment. Two generated `no-recursion` chain
programs at 400 and 1,200 frames, built at `--opt 0`:

| frames | computed | bisected `ulimit -s` floor |
|---|---|---|
| 400 | 204,864 B (200 KiB) | 193 KiB |
| 1,200 | 614,464 B (600 KiB) | 593 KiB |

The **difference** is the sharper half, because it cancels the
per-process constant entirely: 800 more frames cost 400 KiB computed and
400 KiB measured, exactly. `--opt 0` is required — at `--opt 1` the LLVM
inliner flattens a deep arithmetic chain to `ret i64 0`, and the bound
then correctly reports a tiny number without exercising the path
arithmetic.

**What is deferred, and is not pretended to be done.** `axiom
--stack-bound` as a compiler flag is what an embedded user finally
wants. The driver already holds the post-`opt` `.ll` and the `llc`
argument vector, so the plumbing exists; what it needs is an LLVM-IR
text scanner written in Axiom — a second grammar for a foreign language
— plus a diagnostic code with its registry, severity policy and
fixtures. The analysis is proved first; promoting it into the compiler
is a separate change.

## 5. Memory and stack budgets

Proposed budgets for a Cortex-M4-class part (192 KiB SRAM, 1 MiB flash),
derived from section 2's measurements rather than from a target:

| | proposed | basis |
|---|---|---|
| flash, runtime + minimal program | ≤ 24 KiB | 17,472 measured on aarch64; ARM Thumb-2 is typically smaller |
| flash, with the freestanding stdlib subset | ≤ 64 KiB | 34,856 measured with all of `IO` linked |
| SRAM, arena | 32 KiB, statically reserved | 8 × the proposed 4 KiB chunk |
| SRAM, stack | 8 KiB | hello world's own need is **192 bytes** computed (`check-stack-bound.sh`); the 8 KiB is headroom for a deeper program, and any `no-recursion` program's need is now a number rather than an estimate |
| SRAM, runtime globals | < 256 bytes | 30 globals, one word each |

This row used to carry the honest uncertainty that the stack figure was
the one I would not commit to: measured for one program, on one
architecture, with a host-sized `IO`, when the number that matters is
per-program. That is settled. `restrict(no-recursion)` plus a frame-size
sum over the call graph is section 4.6, it is built, and it turns this
row from an estimate into a check — for any program, not just this one.
What remains uncertain is the *other* direction: 192 bytes is hello
world on aarch64, and a Cortex-M4's frames are not aarch64's, so the
8 KiB above is headroom rather than a measurement of the target.

## 6. A minimal reference port

Proposed target: **`baremetal-aarch64`**, running under QEMU's `virt`
machine. Not because aarch64 is the interesting embedded target, but
because it is the one where the port can be *tested in CI* — the same
argument this repository already makes about what "supported" means
(README, Targets). A port nothing executes is not a port.

The deliverable is four files and a gate:

1. A row in `self_host/codegen.ax`'s target table — the name in
   `targetCode`, the triple, `targetArenaStaticBytes` and
   `targetArenaChunkBytes` (4.1 and 4.2, which exist), and `trapWrite`
   over the PL011 UART at `0x09000000` (4.3, which does not). Plus
   `self_host/Host.baremetal-aarch64.ax`, which is one line and answers
   only `hostTarget` — needed so that a compiler compiled FOR the part
   resolves the module at all, and carrying none of the values above,
   for the reason 4.1 records.
2. `stdlib/Sys/Platform.baremetal-aarch64.ax` — no filesystem, no
   process control; the descriptor calls answer `Err` rather than
   trapping, which the ERR-ADOPT work has already made expressible.
3. A linker script and a reset vector that sets `sp` and branches to
   `main`.
4. A blink fixture in a new embedded test directory — the smallest
   program that proves the loop: initialise, allocate, write a byte to
   the UART, reclaim, exit. (Described rather than named, on purpose.
   `check-doc-drift.sh` resolves every fixture path and every bare
   `NNN-name.ext` a document mentions, and it refused two spellings of
   this line before this one: a document may not name a file that does
   not exist. That is the gate working, and it is why section 8's
   *proposed* rows name a gate rather than a path.)
5. `scripts/check-embedded.sh` — which now EXISTS, for 4.1 and 4.2,
   and does none of the QEMU half. What it establishes today is that
   the two values a port must set are per-target values, that setting
   them changes the emitted program in the ways they claim, and that a
   program built with them set runs and traps correctly on the host.
   What the port adds to it is the device: build the four files above,
   run under `qemu-system-aarch64 -nographic -machine virt`, and assert
   the exact bytes on the UART and the exit status. The ablation this
   line asked for is already there and already runs on every gate
   invocation rather than being a drill — a program too large for the
   reserved region must exit 70, against a control that exits 0.

## 7. Out of scope, deliberately

* **Interrupts preempting the allocator.** The bump pointer is not
  reentrant. An ISR that allocates while `main` is mid-allocation
  corrupts the arena, and 4.5's refusal is the whole mitigation. Making
  the allocator interrupt-safe is a different and larger design.
* **Threads.** `parallel`'s thread lowering needs `pthread_create` and
  local-exec TLS; neither exists bare-metal, and `AX4006` already
  refuses `--threads` on a target without them.
* **Floating point.** No proposal to soft-float; targets without an FPU
  are out until someone needs one.
* **`no_std` Rust FFI on-device.** `nostd_runtime.rs` is the model, not
  the deliverable; binding a Rust crate from a bare-metal Axiom program
  is a second project.

## 8. Acceptance

A row is done when the gate named beside it is green in CI.

| # | item | gate | status |
|---|---|---|---|
| 4.1 | arena chunk is a target constant | `check-embedded.sh` (ablation) | **done** |
| 4.2 | static arena strategy | `check-embedded.sh` | **done** |
| 4.3 | `trapWrite` seam, statuses unchanged | existing `.exit` fixtures | proposed |
| 4.4 | freestanding stdlib subset | new variant of `check-freestanding.sh` | proposed |
| 4.5 | ISR entry form | `check-restrictions.sh` extension | proposed |
| 4.6 | static stack bound from the call graph | `check-stack-bound.sh` | **done** |
| 6 | the QEMU reference port | `check-embedded.sh` | proposed |

**4.6 was done first**, for the reason it was ranked first: every other
item is mechanical once the constants move, while the stack bound is the
only one that changes what the language can *promise*, and it is the
promise an embedded user actually needs. It is also the only one that
needed no compiler source change at all — which was not the expectation,
and is written up in 4.6.

**4.1 and 4.2 went together**, and the ranking was right that they are
mechanical: between them they are two rows of a target table, ten
instructions of emitted IR and a derived grain constant. What was NOT
mechanical is the part a document cannot rank — 4.1 named the wrong
file to put the constant in, 4.2's static arena needed the
out-of-memory sentence to stop being a false statement, and neither
noticed that a statically-carved arena has no thread lowering. All
three are written up above. The gate that closes them builds a second
compiler from a copy of `self_host/` with those two rows changed, which
is exactly the edit section 6's port will make, and requires that the
targets neither row names emit byte-identical IR.
