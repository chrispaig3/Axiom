# Embedded Axiom — a proposal

<!-- STATUS, at the top where a reader stops: this document is a
     PROPOSAL. Nothing in section 4 or later is built. Sections 2 and 3
     are MEASUREMENTS taken on 2026-09-03 against the tree at that
     commit, with the command beside each, and they are the reason the
     proposal is worth writing.

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
| stack floor, hello world | runs in **32 KiB**, fails at 16 | `ulimit -s`, bisected |
| arena chunk | **1 MiB**, fixed | `MM-ALLOC-4`; the literal is `self_host/codegen.ax:8342` |

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

### 4.1 The 1 MiB chunk must become a target constant *(blocking)*

`self_host/codegen.ax:8342` emits `icmp ugt i64 %need, 1048576` and
`:8345` selects `i64 1048576` as the chunk size. On a part with 256 KiB
of SRAM the first allocation fails. This is one literal and it should be
a value the target module supplies, the way the syscall numbers already
are — `Host.<target>.ax` gains `arenaChunkBytes`, and the emitter reads
it. **Proposed default for an MCU target: 4 KiB**, with the whole arena
statically reserved (see 4.2).

The chunk-list walk, the mark/reset protocol and MM-ALLOC-14's overlap
rules are all size-independent; nothing else in the allocator changes.

### 4.2 `mmap` must become an optional strategy *(blocking)*

A microcontroller has no `mmap` and often no MMU. The allocator needs a
second backing strategy: a single statically-reserved region, its base
and length fixed at link time, with the chunk list living inside it.
`__axiom_out_of_memory` already exists as the failure path and already
traps with a message and status 70, so the failure semantics need no new
design — only a new source of pages.

Proposed shape: `Host.<target>.ax` declares either `arenaMmap` or
`arenaStatic base len`, and `emitAllocator` branches on it once, at
emission time, so the emitted program contains exactly one of the two.

### 4.3 The trap path must be able to reach something other than fd 2

`write(2, msg, len)` is how every trap reports. A device may have a
UART, a semihosting channel, or nothing. Proposed: the target module
supplies `trapWrite`, defaulting to today's `write` on hosted targets;
on a bare-metal target it is whatever the board offers, or a no-op that
still exits with the right status. **The status codes must not change** —
`tests/stdlib/465-pop-empty-trap.exit` and its siblings pin them, and
they are the only thing an automated test on-device can observe.

### 4.4 A `--no-std`-shaped subset of the standard library

`Sys`, `IO`, `Path`, `Http`, `Rpc` and `Job` all assume a filesystem, a
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

## 5. Memory and stack budgets

Proposed budgets for a Cortex-M4-class part (192 KiB SRAM, 1 MiB flash),
derived from section 2's measurements rather than from a target:

| | proposed | basis |
|---|---|---|
| flash, runtime + minimal program | ≤ 24 KiB | 17,472 measured on aarch64; ARM Thumb-2 is typically smaller |
| flash, with the freestanding stdlib subset | ≤ 64 KiB | 34,856 measured with all of `IO` linked |
| SRAM, arena | 32 KiB, statically reserved | 8 × the proposed 4 KiB chunk |
| SRAM, stack | 8 KiB | hello world measured at under 32 KiB *with* `IO`'s buffers; a `no-recursion` program is bounded by its call graph |
| SRAM, runtime globals | < 256 bytes | 30 globals, one word each |

The honest uncertainty: the stack figure is the one I would not commit
to. It was measured for one program on one architecture with a
host-sized `IO`, and the number that matters is per-program. The static
answer is `restrict(no-recursion)` plus a frame-size sum over the call
graph, which the compiler can compute and does not today — that is
proposal 4.6 and it is the one worth doing first, because it turns the
budget above from an estimate into a check.

## 6. A minimal reference port

Proposed target: **`baremetal-aarch64`**, running under QEMU's `virt`
machine. Not because aarch64 is the interesting embedded target, but
because it is the one where the port can be *tested in CI* — the same
argument this repository already makes about what "supported" means
(README, Targets). A port nothing executes is not a port.

The deliverable is four files and a gate:

1. `self_host/Host.baremetal-aarch64.ax` — the triple, `arenaStatic`,
   and `trapWrite` over the PL011 UART at `0x09000000`.
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
   not exist. That is the gate working, and it is why section 8's rows
   say *proposed* rather than showing paths.)
5. `scripts/check-embedded.sh` — builds it, runs it under
   `qemu-system-aarch64 -nographic -machine virt`, and asserts the exact
   bytes on the UART and the exit status. With an ablation: raise the
   arena chunk above the reserved region and the gate must go red with
   status 70.

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
| 4.1 | arena chunk is a target constant | `check-embedded.sh` (ablation) | proposed |
| 4.2 | static arena strategy | `check-embedded.sh` | proposed |
| 4.3 | `trapWrite` seam, statuses unchanged | existing `.exit` fixtures | proposed |
| 4.4 | freestanding stdlib subset | new variant of `check-freestanding.sh` | proposed |
| 4.5 | ISR entry form | `check-restrictions.sh` extension | proposed |
| 4.6 | static stack bound from the call graph | new | proposed |
| 6 | the QEMU reference port | `check-embedded.sh` | proposed |

**Do 4.6 first.** Every other item is mechanical once the constants
move; the stack bound is the only one that changes what the language can
promise, and it is the promise an embedded user actually needs.
