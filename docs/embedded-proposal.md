# Embedded Axiom — a proposal

This proposal sets out what Axiom needs to run on a microcontroller,
and ranks the changes by what blocks what. Every item in it is now
built. Section 8 lists each one with the gate (a CI check script under
`scripts/`) that holds it, and each item says what landed and what the
proposal got wrong about it.

## 1. Why this is a short document

Most languages that propose an embedded story start by removing
things: a garbage collector, a runtime, a scheduler, a C library,
exception tables. Axiom has none of those. It is already freestanding:
it emits a static binary and reaches the kernel through raw syscalls.
`scripts/check-freestanding.sh` fails the build if that stops being
true at either level: a libc call in the emitted IR, or a libc symbol
in the linked executable.

So the question is which of Axiom's three assumptions about a hosted
operating system have to become configurable. The answer is a short
list.

## 2. The measured baseline

Every figure here was taken on darwin-aarch64 at 0.6.3, with the
command shown. Re-run them rather than quoting them.

| | measured | how |
|---|---|---|
| minimal program, `--opt 2` | **17,472 bytes** | `(fn (main) 0)`, `stat -f%z` |
| hello world with `IO` | **34,856 bytes** | `(println "hi")` |
| undefined symbols, either | **0** | `nm -u` |
| distinct syscalls, minimal program | **3** | `mmap`, `write`, `exit` (see below) |
| runtime globals | 30 | `grep -cE '^@__axiom' min.ll` |
| emitted IR, minimal program | 570 lines | `wc -l min.ll` |
| stack floor, hello world, whole process | runs in **32 KiB**, fails at 16 | `ulimit -s`, bisected (see 4.6) |
| stack, hello world, the Axiom program itself | **192 bytes** | `scripts/check-stack-bound.sh`, computed |
| arena chunk | **1 MiB**, per target | `MM-ALLOC-4`; `targetArenaChunkBytes` (4.1), pinned per target by `check-embedded.sh` |

The syscall row is the key finding. A minimal Axiom program makes
exactly three kinds of kernel call:

* `mmap`, once, to map the first arena chunk;
* `write`, only on a trap path, to put the message on fd 2;
* `exit`, to leave.

The rest of those 570 lines is arithmetic on memory the program
already has. There is no dynamic loader, no relocation at startup, no
C runtime initialisation, no atexit table, no locale and no `errno`.

Two rows depend on the platform, and one of them also depends on the
linker. 17,472 bytes is a Mach-O. The same program, from byte-identical
IR, is 16,416 bytes from gcc and ld.bfd on linux-x86_64, and 71,168
bytes from clang and lld on linux-aarch64. That 4.3x spread between two
supported ELF linkers comes from page policy and `crt1`, not from code.
Undefined symbols vary by format for the same reason: zero in a
Mach-O, and five or six startup hooks in an ELF.

So `check-embedded.sh` A3 checks the flash budget only on Mach-O, the
format section 5 prices it on, and prints the size on ELF and PE. On every
host it checks the two figures that belong to the runtime rather than
the toolchain: no import outside the platform's own startup set, and
exactly three distinct syscalls.

## 3. What Axiom already has that an embedded target wants

* A per-target syscall ABI, chosen at compile time.
  `self_host/Host.<target>.ax` and `stdlib/Sys/Platform.<target>.ax`
  are the two files a target owns, and `--target` selects them. Adding
  a target doesn't mean editing a hundred call sites. 4.1 corrects
  part of this: `Host.<target>.ax` names the target the compiler
  itself was built for, so the compiler's per-target constants live in
  `self_host/codegen.ax`'s target table instead.
* Scope-based reclamation. `region` (MM-RGN-1) reclaims everything
  allocated in a scope when the scope ends, in constant time and with
  no traversal. On a device with no swap and a hard memory ceiling,
  that's the allocation discipline you want, and it is a language form
  rather than a convention.
* A static refusal for recursion. `;@axiom:restrict(no-recursion)` is
  a claim the compiler checks against the call graph
  (`scripts/check-restrictions.sh`). That's what lets you prove a
  bounded stack instead of hoping for one.
* A freestanding runtime to copy, in Rust.
  `rust/axiom-ffi/src/nostd_runtime.rs` already does for the Rust side
  of the FFI what an embedded port must do for the Axiom side: raw
  `asm!` syscalls for four targets, a `GlobalAlloc` over `axiom_alloc`,
  a panic handler, and hand-written `memcpy`, `memset` and `strlen`.
  It is the shape of the answer, and it compiles in the tree today.
* Determinism. There is no JIT and nothing adaptive. The arena has no
  growth policy (MM-ALLOC-4), so allocation is a bump and a compare.
  That's a liability on a server and an asset on a device.

## 4. What has to change — proposed, ranked by what blocks what

### 4.1 The 1 MiB chunk must become a target constant *(done — `check-embedded.sh`)*

The chunk size is `targetArenaChunkBytes`, in `self_host/codegen.ax`'s
target table, beside `targetMmapNum` and the other per-target numbers.
Every supported target answers 1 MiB, so each still emits the
allocator it always emitted. For three probes, the seven targets'
`emit-llvm` output is byte-identical across the change, and
`check-embedded.sh` A1 pins the four lines per target so it stays that
way. `baremetal-aarch64`, the reference port in section 6, answers
4 KiB.

The proposal named the wrong file, and following it would have
shipped the bug this item exists to remove. `Host.<target>.ax` answers
`hostTarget`: the target the compiler binary itself was compiled for.
Module resolution selects it when the compiler is built, and the
compiler reads it only as the default when you give no `--target`. It
isn't the target a program is compiled for. An `arenaChunkBytes` there
would silently give a darwin-hosted compiler, cross-compiling to a
bare-metal part, darwin's megabyte. So the constants are keyed by the
target code instead, which is what "the way the syscall numbers
already are" means.

A second constant came with it, because the two depend on each other.
`refill:` rounds a request larger than one chunk up to a 64 KiB grain.
A 4 KiB-chunk target that rounded a 5 KiB request to 64 KiB would ask
for sixteen chunks' worth to serve one. Against the 32 KiB static
region section 5 budgets, that is an out-of-memory trap for a request
the arena has room for. So `targetArenaGrainBytes` is the chunk size
where the chunk is the smaller, and 64 KiB otherwise, and no supported
target moves.

The grain has two emission sites. `emitArenaKeepHelper` is the arena's
second allocation path and rounds the same way, and
`check-embedded.sh` covers both. The chunk-list walk, the mark and
reset protocol, and MM-ALLOC-14's overlap rules don't depend on the
chunk size, as the proposal said. Nothing else in the allocator
changed.

### 4.2 `mmap` must become an optional strategy *(done — `check-embedded.sh`)*

`targetArenaStaticBytes` is 0 on every supported target, and 0 means
`mmap` (or `VirtualAlloc`). Non-zero means a single region of that
many bytes. `emitRuntimeMap`, the one door every chunk in the program
arrives through, branches on it at emission time. So an emitted
program contains exactly one of the two strategies, and the other
costs it nothing, not even a branch. `baremetal-aarch64` answers
32 KiB.

`targetArenaStaticBase` says where the region is. Zero means the
emitter reserves it as a zero-initialised global and the linker fixes
the address, which suits a part with a normal `.bss`. Non-zero is an
absolute SRAM window the board knows and no `.bss` covers.

The static door (`emitArenaCarve`) is ten instructions with no branch
and no call. Its two call sites read `%addr` and test it themselves,
and a door that added a basic block would rewrite control flow that
the reset protocol and MM-ALLOC-14 both rely on. It answers 0 when the
region is exhausted. That is below the `%failed_low` test that already
catches a refused `mmap`, so exhaustion reaches
`__axiom_out_of_memory` and exits 70 through the existing path. The
failure semantics needed no new design, as the proposal said.

It also runs, which an emission check alone can't show. With the host
target given a 256 KiB region and a 4 KiB chunk, a program that
allocates 52,800 bytes across fifteen chunks prints what the `mmap`
build of the same source prints. A program that asks for 1,056,000
bytes exits 70, while the `mmap` build of that source exits 0, so the
70 is the region's verdict and not the program's size. The minimal program's three
syscalls become two, and `mmap` is the one that goes.

One other site still maps, and it is outside this item. The
concurrency lowering asks for a 4 KiB `MAP_SHARED` page per binding,
which is how a forked child hands its result back. A statically
reserved region can't stand in for it: the page must survive `fork`
and be visible in both processes, and a `.bss` array is copied. So a
program that uses `parallel` still names `mmap` on a static target.
That is section 7's "threads are out of scope", extended to processes.
A bare-metal port answers it the way windows-x86_64 already does: both
primitives compile to a trap that says so.

The item needed two things the proposal didn't mention:

* A true trap sentence. `__axiom_out_of_memory` printed
  `axiom: out of memory (mmap failed)` on a target with no `mmap`. It
  now names the strategy that ran out, with the status and a hosted
  target's bytes unchanged.
* A thread refusal. Under `--threads` the runtime's mutable globals
  become `thread_local`, so every thread would start its bump pointer
  from a cursor initialised to the same base and carve the same bytes
  twice. Sharing the cursor instead makes it a data race on the one
  word the whole heap is built from. So a static target answers no to
  `targetHasThreads`, and `--threads` on one is refused as `AX4006`,
  which already means exactly that. Section 7 puts threads out of
  scope for bare metal, and this is what that costs in code.

### 4.3 The trap path must be able to reach something other than fd 2 *(done — `check-embedded.sh` A8/A9)*

Every trap reports with `write(2, msg, len)`. A device may have a
UART, a semihosting channel, or nothing. The proposal: the target
module supplies `trapWrite`, defaulting to today's `write` on hosted
targets. On a bare-metal target it is whatever the board offers, or a
no-op that still exits with the right status.

**The status codes must not change.**
`tests/stdlib/465-pop-empty-trap.exit` and its siblings pin them, and
they are the only thing an automated test on the device can observe.

It shipped as `targetTrapSilent`, one row beside the arena rows. Zero
keeps today's write, and non-zero means no write at all.
`emitRuntimeWrite`, the single door the backtrace writer delegates to,
reads it at emission time. So a silent program carries a comment where
each write was, and no branch. The abort, the backtrace walk and the
exit with the trap's own status all still run.

A8 pins the writes on all seven targets, and the default's single
spelling. A9 builds a variant compiler that is silent on the host,
requires its suppressions to match the tree build's writes line for
line, and runs a dividing probe under both. Both exit 72. One writes
the sentence on fd 2 and the other writes zero bytes.

A UART gets a second row, `targetUartBase`, read by the same
`emitRuntimeWrite`. The reference port in section 6 uses it. The row
holds the PL011 data register's address, and `emitRuntimeWrite` calls
a helper that stores each byte there instead of writing fd 2. The port
leaves `targetTrapSilent` at 0, so no target is silent today.

### 4.4 A `--no-std`-shaped subset of the standard library *(done — `scripts/check-nostd-subset.sh`)*

`Sys`, `IO`, `Path`, `Http`, `Rpc` and `Par` all assume a filesystem,
a process model or sockets. `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`,
`Utf8` and `Err` don't. The proposal: mark the second group as the
freestanding subset, and gate it. A probe that imports only those
modules and builds for a bare-metal target must produce a binary that
imports nothing but the target's own primitives. That gate is a
variant of `check-freestanding.sh`, and it comes before the port,
because it is what makes the subset a fact rather than an intention.

`scripts/check-nostd-subset.sh` holds the split with three checks:

* the transitive imports of every subset module stay inside the
  subset;
* no subset module declares an `extern` block;
* a probe that imports all eight builds for every supported target,
  with the same import surface as hello world.

### 4.5 Interrupt handlers need an entry-point form *(done — `scripts/check-isr.sh`)*

An interrupt service routine (ISR) is a function the hardware calls by
a fixed name with no arguments, and it must not allocate. Both halves
already existed separately: `--emit-staticlib` makes every `pub fn` a
C symbol, and `;@axiom:restrict(no-alloc)` is checked. The proposal: a
target attribute that combines them and also refuses a non-empty
parameter list. Then an ISR that allocates is a compile error rather
than a heap corruption at 3 a.m.

It shipped as `;@axiom:isr`. The tag adds `no-alloc` to the claims the
restriction walk already checks, so the violation, the warning and
`strict` all behave as they do for a written `no-alloc`. A declaration
with parameters draws `AX3010`, and a typo within one edit of the tag
gets a suggestion (`AX3039`). It needed no target machinery: neither
half varies by target, and `--emit-staticlib` already exports every
`pub fn` on every target that builds archives.

`tests/diagnostics/651-isr-params.ax` and `652-isr-alloc.ax` pin the
refusals. The gate builds a `pub` ISR beside a plain function into an
archive that carries both symbols, and refuses the allocating fixture
under `--emit-staticlib` too.

### 4.6 A static stack bound from the call graph *(done — `check-stack-bound.sh`)*

This item was ranked first, and was done first.
`scripts/lib/stack-bound.py` computes the longest weighted path
through a program's call graph and reports "this binary needs at most
N bytes of stack". When the question has no static answer, it refuses
and names the site: a cycle, a dynamic frame, an extern whose frame is
unknown, or a function address it can't classify.
`scripts/check-stack-bound.sh` gates it with assertions A1 to A6 and
three ablations.

Measurement contradicted two things the proposal said.

First, the proposal said the emitter knows each frame's size. It
doesn't, and can't. Axiom emits LLVM text IR and runs
`IR → opt → llc → cc` (`self_host/driver.ax`). Frame layout is decided
by LLVM's register allocator, after `codegen.ax` has finished. A
number computed inside `codegen.ax` would be either unsound or a large
overestimate.

So the sizes come from the same `llc` invocation the driver already
makes: `llc --stack-usage-file` where the toolchain has it (LLVM 19
and later), and otherwise a prologue parse of `llc -filetype=asm`. The
two are cross-checked over all **3,767** functions of the compiler,
and all 3,767 agree. That is what earns the portable parse its trust
on a toolchain with no table.

Second, the proposal said hello world needs 32 KiB of stack. That
figure is the host process's dyld and libc startup, not the Axiom
program. The program's own need is **192 bytes**, and A6 gates it.
The 32 KiB was measured correctly and read wrongly: bisecting
`ulimit -s` on a binary measures everything the process does,
including everything that runs before `main`.

Two measured facts make a precise answer possible:

* Every one of the compiler's 3,767 frames is reported `static`.
  Emitted IR has no dynamic `alloca` anywhere, so a frame is a
  constant and a path is a sum. A3 asserts this.
* The whole self-hosted compiler contains exactly one indirect call
  site, the foreign drop glue in `axiom_release`. Once the backtrace
  symbol table `@__axiom_symtab` is excluded, it has zero address-taken
  functions. So that site is provably dead, and hello world gets a
  real bound rather than a refusal. A closure program resolves to
  exactly its own lambda and stays precise.

The arithmetic is checked against a measurement. Two generated
`no-recursion` chain programs, at 400 and 1,200 frames, built at
`--opt 0`:

| frames | computed | bisected `ulimit -s` floor |
|---|---|---|
| 400 | 204,864 B (200 KiB) | 193 KiB |
| 1,200 | 614,464 B (600 KiB) | 593 KiB |

The difference is the sharper check, because it cancels the
per-process constant: 800 more frames cost 400 KiB computed and
400 KiB measured, exactly. `--opt 0` is required. At `--opt 1` the
LLVM inliner flattens a deep arithmetic chain to `ret i64 0`, and the
bound then correctly reports a tiny number without exercising the path
arithmetic.

Not yet: `axiom --stack-bound`, the compiler flag an embedded user
ultimately wants. The driver already holds the post-`opt` `.ll` and
the `llc` argument vector, so the plumbing exists. What it needs is an
LLVM IR text scanner written in Axiom, which is a second grammar for a
foreign language, plus a diagnostic code with its registry entry,
severity policy and fixtures. The analysis is proved first. Moving it
into the compiler is a separate change.

### 4.7 Bounded heaps on hosted targets *(done — `check-embedded.sh` A7)*

4.2 put the second strategy behind a target-table row, and every
supported target answers zero to it. `--heap-ceiling N` selects it per
build instead of per target. The heap is carved from a `.bss` region
of exactly N bytes, with the growth unit capped by the region. A
growth unit larger than the region could never fit, so without the cap
the first carve would trap a program that fits.

The grain isn't capped. It only rounds a request that already exceeds
the growth unit, and such a request exceeds a small ceiling on its
own, so capping it would change nothing.

Exhaustion is MM-ALLOC-7's status 70 with the arena's sentence, the
same verdict a static bare-metal target gives. A program that fits
answers byte for byte what the `mmap` build answers. Non-numeric, zero
and missing values exit 2 before any subcommand runs.

A spawning program under `--threads` is refused at build time as
AX4006, by the existing diagnostic. One cursor can't serve two bump
pointers, and `targetHasThreads` already answers 0 wherever the region
is carved, so no new code refuses anything.

A7 gates it the way A6 gates the variant compiler. The same fitting
program answers 5050, and the same overflowing one exits 70 against a
control that exits 0. The IR carries the requested region, with the
capped growth unit and no `mmap`. The `ceiling` ablation, which stops
the flag being read, turns the gate red.

What this isn't:

* an allocator change, since the carve is 4.2's, byte for byte;
* a bare-metal target, which is section 6;
* a promise about fragmentation. A bump allocator reuses nothing until
  a reset, so the ceiling bounds total allocation, not live data.

## 5. Memory and stack budgets

Proposed budgets for a Cortex-M4-class part (192 KiB SRAM, 1 MiB
flash), derived from section 2's measurements rather than from a
target:

| | proposed | basis |
|---|---|---|
| flash, runtime + minimal program | ≤ 24 KiB | 17,472 bytes measured as a Mach-O (an ELF's size depends on its linker, §2); ARM Thumb-2 is typically smaller |
| flash, with the freestanding stdlib subset | ≤ 64 KiB | 34,856 bytes measured with all of `IO` linked |
| SRAM, arena | 32 KiB, statically reserved | 8 × the proposed 4 KiB chunk |
| SRAM, stack | 8 KiB | hello world's own need is **192 bytes**, computed (`check-stack-bound.sh`); the 8 KiB is headroom for a deeper program, and any `no-recursion` program's need is now a number rather than an estimate |
| SRAM, runtime globals | < 256 bytes | 30 globals, one word each |

The stack row was the proposal's one uncertain figure. It was measured
for one program, on one architecture, with a host-sized `IO`, when the
number that matters is per program.
Section 4.6 settles that: `restrict(no-recursion)` plus a frame-size
sum over the call graph turns the row into a check, for any program.
What remains uncertain is the other direction. 192 bytes is hello
world on aarch64, and a Cortex-M4's frames aren't aarch64's, so the
8 KiB is headroom rather than a measurement of the target.

## 6. A minimal reference port

The proposed target is **`baremetal-aarch64`**, running under QEMU's
`virt` machine. Aarch64 isn't the interesting embedded target, but
it's the one where the port can be tested in CI. That's the rule the
[README](../README.md#targets) already applies to what "supported"
means: a port nothing executes isn't a port.

The deliverable is four files and a gate, and all of it is built:

1. A row in `self_host/codegen.ax`'s target table: the name in
   `targetCode`, the triple, `targetArenaStaticBytes` and
   `targetArenaChunkBytes` (4.1 and 4.2), and `targetUartBase` for the
   PL011 UART at `0x09000000` (4.3). Plus
   `self_host/Host.baremetal-aarch64.ax`, which is one line and answers
   only `hostTarget`. It exists so that a compiler compiled for the
   part resolves the module at all, and it carries none of the values
   above, for the reason 4.1 gives.
2. `stdlib/Sys/Platform.baremetal-aarch64.ax`, with no filesystem and
   no process control. The descriptor calls answer `Err` rather than
   trapping wherever the answer fits the type, which the ERR-ADOPT work
   made expressible.
3. A linker script and a reset vector that sets `sp` and branches to
   `main`. The driver generates the script and links with `ld.lld`,
   and the reset vector is `_start`.
4. `tests/embedded/blink.ax` and its oversized twin
   `tests/embedded/blink-oom.ax`. They are the smallest programs that
   prove the loop: initialise, allocate, write to the UART, reclaim,
   exit.
5. `scripts/check-embedded.sh` A10, the QEMU half. It builds the
   fixtures above for `baremetal-aarch64`, boots each under
   `qemu-system-aarch64 -machine virt -nographic`, and checks the
   exact bytes on the UART and the exit status. Blink's UART output
   must equal its hosted stdout byte for byte, at exit 0. The oversized
   twin must exit with the status `tests/stdlib/314-out-of-memory.exit`
   pins, against a control that exits 0.

The guest's status reaches the host process through semihosting
SYS_EXIT (`hlt #0xf000`, x0 = 0x18, reason 0x20026 and the status in
two 64-bit words). That is the exit contract item 3 implements. Where
QEMU isn't installed, A10 reports that it skipped.

<a id="7-out-of-scope-deliberately"></a>
## 7. Out of scope

* Interrupts preempting the allocator. The bump pointer isn't
  reentrant. An ISR that allocates while `main` is mid-allocation
  corrupts the arena, and 4.5's refusal is the whole mitigation.
  Making the allocator interrupt-safe is a different and larger design.
* Threads. `parallel`'s thread lowering needs `pthread_create` and
  local-exec TLS. Neither exists on bare metal, and `AX4006` already
  refuses `--threads` on a target without them.
* Floating point. There is no soft-float proposal. Targets without an
  FPU are out until someone needs one.
* `no_std` Rust FFI on the device. `nostd_runtime.rs` is the model,
  not the deliverable. Binding a Rust crate from a bare-metal Axiom
  program is a second project.

## 8. Acceptance

A row is done when the gate named beside it is green in CI.

| # | item | gate | status |
|---|---|---|---|
| 4.1 | arena chunk is a target constant | `check-embedded.sh` (ablation) | **done** |
| 4.2 | static arena strategy | `check-embedded.sh` | **done** |
| 4.3 | `trapWrite` seam, statuses unchanged | `check-embedded.sh` (A8, A9) | **done** |
| 4.4 | freestanding stdlib subset | `check-nostd-subset.sh` | **done** |
| 4.5 | ISR entry form | `check-isr.sh` | **done** |
| 4.6 | static stack bound from the call graph | `check-stack-bound.sh` | **done** |
| 4.7 | bounded heaps on hosted targets | `check-embedded.sh` (A7, `ceiling` ablation) | **done** |
| 6 | the QEMU reference port | `check-embedded.sh` (A10) | **done** |

4.6 was done first, as ranked. Every other item is mechanical once the
constants move. The stack bound is the only one that changes what the
language can promise, and it is the promise an embedded user needs.
It also turned out to need no compiler source change at all, which 4.6
explains.

4.1 and 4.2 went together, and they were as mechanical as the ranking
said: two rows of a target table, ten instructions of emitted IR and a
derived grain constant. The surprises were ones a proposal can't rank:
the wrong file in 4.1, and the false out-of-memory sentence and the
missing thread refusal in 4.2. The gate that closes them builds a
second compiler from a copy of `self_host/` with those two rows
changed, which is the edit section 6's port makes. It requires the
targets neither row names to emit byte-identical IR.
