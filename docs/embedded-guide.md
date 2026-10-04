# Embedded and OS integration guide — `baremetal-aarch64`

The port has been executed under QEMU TCG and checked by emission
gates. No behaviour here has been validated on hardware.

## 1. The target in one table

| | `baremetal-aarch64` |
|---|---|
| triple | `aarch64-unknown-none-elf`, little-endian |
| board it is tested on | QEMU `virt`, `-cpu cortex-a72`, TCG (emulated), no hardware |
| exception level | EL1 (QEMU starts a `-kernel` ELF there when EL2/EL3 are absent) |
| MMU | **on**, identity-mapped: code read-only, data execute-never, an unmapped guard below each stack, both caches on (section 6) |
| heap | a static arena in `.bss`: 32 KiB in 4 KiB chunks by default, `--heap-ceiling N` to set it (MM-ALLOC-7 status 70 on exhaustion) |
| console | PL011 UART data register at `0x09000000`, written by volatile byte stores |
| exit | ARM semihosting `SYS_EXIT` (`hlt #0xf000`), so the guest's status is QEMU's |
| threads | none: `--threads` is `AX4006` on a static arena |
| linker | `ld.lld` with a generated script (`driver.ax` `baremetalLinkScript`) |
| faults | an exception vector table in every image; an unhandled exception writes its registers on the UART and exits **81**, or calls the program's `isr(fault)` hook (section 5) |

## 2. Startup, linker layout, stack and initialisation

### The image

`axiom build --target=baremetal-aarch64` emits the IR, runs `llc` and
links with `ld.lld -T <generated script>`. There is no C runtime and
nothing dynamic. The script, in full:

```text
ENTRY(_start)
SECTIONS {
  . = 0x40000000;
  .text.boot : { KEEP(*(.text.boot)) }
  .text : { *(.text*) }
  . = ALIGN(4096);
  __axiom_rx_end = .;
  .rodata : { *(.rodata*) }
  .eh_frame : { *(.eh_frame*) }
  .got : { *(.got) *(.got.plt) }
  . = ALIGN(4096);
  __axiom_ro_end = .;
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(4096);
  __axiom_rw_end = .;
  . = . + 0x10000;
  __axiom_stack_lo = .;
  . = . + 0x2000;
  __stack_top = .;
  . = . + 0x1000;
  __axiom_exc_lo = .;
  . = . + 0x2000;
  __axiom_exc_top = .;
  __axiom_pt = .;
}
```

`virt` maps RAM at `0x40000000`, and QEMU's `-kernel` loads the ELF's
segments at their addresses and jumps to `_start`. The vector table is
`.text.vectors`, 2 KiB aligned, inside `.text`. The static arena is an
ordinary zero-initialised `.bss` array (`@__axiom_arena`), so the
linker places it and the loader zeroes it. Nothing at run time clears
memory.

Every boundary is page aligned, because the page tables map the image
one 4 KiB page at a time (section 6). The GOT sits with the read-only
data: a static link fills it and nothing writes it at run time.

### The stacks

Your program runs on the 8 KiB below `__stack_top`. Below it is a
64 KiB guard that isn't mapped, so a stack that outgrows 8 KiB faults
in the guard instead of writing into the arena. The fault is reported
as a stack overflow (section 5).

The guard catches an overflow. It doesn't prevent one. Bound the stack
statically: a `restrict(no-recursion)` call graph has a computable
bound (`scripts/check-stack-bound.sh`, and the restricted profile's
RP-7). An interrupt adds its 592-byte save area and its handler's
frames on top of whatever depth the main loop has reached.

A second stack of 8 KiB, above a 4 KiB guard of its own, belongs to
the fault exit. It switches to that stack before touching memory, so
it can still report a fault taken with the program's stack pointer
inside the guard. The fault hook runs there too.

### Initialisation

`_start` is emitted by `emitBaremetalStart`, naked, in `.text.boot`.
Before `main` runs a single instruction it does this:

1. `sp` := `__stack_top` (the reset value is undefined).
2. `CPACR_EL1.FPEN` := `0b11`, so FP and SIMD instructions don't trap.
   A `Float`, or a copy the compiler vectorised, would otherwise be an
   undefined-instruction exception.
3. `VBAR_EL1` := the vector table, then `ISB`. A fault from here on is
   reported.
4. The page tables are built, with the MMU still off
   (`@__axiom_mmu_tables`).
5. `MAIR_EL1`, `TCR_EL1` and `TTBR0_EL1` are written, the TLB and the
   instruction cache are invalidated, and `SCTLR_EL1` turns on the
   MMU, both caches, alignment checking and write-implies-execute-never
   (section 6).
6. `main` is called with `argc = argv = 0`. Its answer is the
   semihosting exit status.

Interrupts stay masked, their reset state, until your program unmasks
them. Nothing else is set up: no GIC and no timer. A program that
wants those sets them up itself.

## 3. Device access: volatile, barriers, and what is not synchronisation

The rule is `docs/memory-model.md` **MM-FFI-8**; this is the working
summary.

**The primitives.** Every argument and result is an `Int`; the address is
a byte address.

| Primitive | Instruction | Targets | Effect row |
|---|---|---|---|
| `(__vload8 a)` … `(__vload64 a)` | one volatile load of 8/16/32/64 bits, zero-extended | all | `Mut`, `Unsafe` |
| `(__vstore8 a v)` … `(__vstore64 a v)` | one volatile store of the low 8/16/32/64 bits | all | `Mut`, `Unsafe` |
| `__arm_dmb` / `__arm_dsb` / `__arm_isb` | `DMB SY` / `DSB SY` / `ISB` | any AArch64 | `Mut` |
| `__arm_cntvct` / `__arm_cntfrq` | read `CNTVCT_EL0` / `CNTFRQ_EL0` | any AArch64 | `IO` |
| `__arm_rndr` | read `RNDR` (FEAT_RNG), 0 when no value was ready | baremetal-aarch64 | `IO`, `Entropy` |
| `__arm_ctr` | read `CTR_EL0` | bare metal | `IO` |
| `(__arm_set_cntv_cval t)` / `(__arm_set_cntv_ctl c)` | write the virtual timer | bare metal | `Mut` |
| `__arm_irq_mask` / `__arm_irq_unmask` | `msr daifset, #2` / `msr daifclr, #2` | bare metal | `Mut` |
| `__arm_wfi` | `wfi` | bare metal | `IO` |
| `(__arm_dc_cvac a)` / `(__arm_dc_civac a)` | `dc cvac` / `dc civac` | bare metal | `Mut`, `Unsafe` |
| `__arm_tpidr` / `(__arm_set_tpidr v)` | read / write `TPIDR_EL1` | bare metal | none / `Mut` |

"Any AArch64" means the instruction runs at EL0, so an aarch64 host
(Linux, Darwin, FreeBSD) runs it too; "bare metal" means it needs EL1.
A primitive the target cannot execute is refused at build time as
`AX4008`. The check reads the module after unreachable functions are
pruned, so a helper nothing calls is never refused. A body that calls an `Unsafe`
primitive directly says `;@axiom:effect(unsafe)` (`AX3073`); one that
reads the counter says `;@axiom:effect(io)`.

**What volatile gives you.** The compiler keeps every volatile access:
it doesn't delete, merge, split, widen or narrow one, and it keeps two
volatile accesses in program order. That is what a device register
needs: a write nothing reads back is still a doorbell, and a 32-bit
register must be read as one 32-bit access. `scripts/check-embedded.sh`
A11 is the evidence: after `opt -O2`, a register written twice keeps
both writes while the same code through the ordinary `__store8`/
`__store64` loses the first, and `llc` emits each width as its own
instruction (`strb`/`strh`/`str w`/`str x` and the loads).

**What volatile does not give you**, each the program's obligation:

1. **Alignment.** The address must be a multiple of the width. The port
   sets `SCTLR_EL1.A`, so a misaligned access is an alignment fault,
   not a slow access.
2. **Ordering against ordinary memory.** The compiler may move an
   ordinary load or store across a volatile one, and the hardware may
   make ordinary writes visible after a later device write. Where a
   device reads memory the CPU wrote, such as a DMA descriptor, put
   `__arm_dsb` (or `__arm_dmb`) between the writes and the doorbell.
   RAM is cached, so a device that isn't coherent with the cache also
   needs the lines cleaned first, and invalidated before the CPU reads
   what the device wrote (section 6). Every `__arm_` primitive that
   orders, waits or writes is also a compiler barrier.
3. **Synchronisation.** Volatile is not atomic and creates no
   happens-before edge. Between threads use the atomics (MM-PAR-9); a
   volatile flag does not publish the data written before it. On one
   core, between an interrupt handler and the code it interrupted,
   volatile is the right tool for a word the handler writes and the
   main loop polls: what must be prevented is the compiler keeping
   the word in a register.
4. **Read-modify-write atomicity.** One naturally aligned access is
   single-copy atomic; a read, a mask and a write are three accesses.

For an instruction no primitive covers, such as reading `CurrentEL` or
another system register, write an `asm` form:

```scheme fragment
(:: currentEl Int)
;@axiom:effect(unsafe)
(fn (currentEl)
  (asm (aarch64 "mrs {e}, CurrentEL" (out e))))
```

The function says `effect(unsafe)`, because the compiler can't see what
the instruction does. A form with no arm for the target is `AX4008`,
like a primitive the target lacks, and the restricted profile refuses
one unless `--allow-asm` names its function (RP-9). The full form is in
[Inline assembly](reference.md#inline-assembly).

## 4. Alignment, endianness, integer width and ABI

- **Endianness.** Little-endian. A device that speaks big-endian (QEMU's
  `fw_cfg` DMA interface does) needs the bytes swapped in software.
- **Integer width.** Every Axiom value is one 64-bit word
  (`MM-VAL-1`); an 8/16/32-bit register value arrives zero-extended from
  `__vloadN` and leaves truncated through `__vstoreN`. Arithmetic wraps
  at 64 bits (`restrict(no-wrap)` refuses the operators that can).
- **Alignment.** The arena hands out 16-byte-aligned blocks
  (`MM-ALLOC-3`); a device access must be aligned to its own width.
- **ABI.** Functions follow AAPCS64 as LLVM lowers them for this triple;
  `x18` is an ordinary allocatable register here (it is reserved on
  Darwin), which is why every piece of assembly in the port that
  clobbers or preserves registers names it.

## 5. Exceptions, faults and interrupt handlers

Every image carries an exception vector table. By default a fault is
reported on the UART and ends the program with status 81. Bind a
function with `;@axiom:isr(fault)` and it decides what happens
instead. Interrupts reach a function you bind with `;@axiom:isr(irq)`.

### What happens on a fault

A synchronous exception (an alignment fault, a data or instruction
abort, an undefined instruction), an SError, an FIQ, or an IRQ with no
handler bound, is a fault. The fault exit writes one line:

```text
axiom: unhandled CPU exception at vector 0x0000000000000200 esr 0x0000000096000021 elr 0x0000000040001e40 far 0x00000000400059a1
```

With no hook bound, QEMU then exits 81. That line is
`tests/embedded/fault.ax`, a misaligned 32-bit load. ESR 0x96000021 is
EC 0x25 (a data abort at the current exception level) with DFSC 0x21
(alignment); ELR is the faulting instruction and FAR the odd address.

A data abort at an address in the guard below a stack adds a second
line:

```text
axiom: stack overflow: the fault address is in the guard page below a stack
```

That is `tests/embedded/overflow.ax`, a recursion with no base case:
ESR 0x96000047, a level-3 translation fault on a write.

The fault exit switches to its own stack before it touches memory, so
it can report a fault taken with the program's stack pointer in the
guard. It never returns to the code that faulted. A recovery point the
program armed isn't jumped to, because the jump would resume that code
in exception context with interrupts masked. A second fault while the
line is being written exits 81 without writing.

### Choose your fault policy

The language can't know the safe state of your system. Stopping a
motor, holding the last output, resetting, and waiting for a watchdog
are answers only you can give. `;@axiom:isr(fault)` binds the one
function that gives yours:

```scheme
(import IO)
(import Str)

(:: say (-> String Int))
;@axiom:effect(unsafe)
(fn (say s)
  {
    (for i in 0..(strLen s)
      (__vstore8 150994944 (strByte s i)))
    0
  })

(:: onFault (-> Int Int Int Int Int Int))
;@axiom:isr(fault)
(fn (onFault status vector esr elr far)
  {
    (say "safe state\n")
    status
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "running")
    0
  })
```

The runtime writes its own line first, as it does with no hook, so the
report survives whatever the hook decides. Then it calls the hook with
five `Int`s:

| Parameter | After a CPU exception | After a software trap |
|---|---|---|
| `status` | 81 | the trap's status, 70 to 85 |
| `vector` | the vector offset (0x200 for the port's faults) | -1 |
| `esr`, `elr`, `far` | `ESR_EL1`, `ELR_EL1`, `FAR_EL1` | 0 |

The hook's answer is the exit status. Answer `status` to keep the
default. Or never return: halt in a `wfi` loop, or reset the machine.
`tests/embedded/fault-reset.ax` resets through PSCI `SYSTEM_RESET`
over `hvc`, the conduit QEMU `virt` offers a guest it starts at EL1. On
a board the conduit is the firmware's choice.

Tested by `tests/embedded/fault-hook.ax` and `scripts/check-embedded.sh` A19.

### Software traps reach the hook too

A software trap outside any recovery point (out of memory, a division
by zero, a violated contract, and the rest of `MM-EXEC-16`'s statuses)
writes its sentence as it always does. Then, with a hook bound, it
calls the hook with its own status and vector -1, on the fault stack
with interrupts masked. So one function sees every way your program
can stop that it didn't ask for, and there is one safe state to
review.

A trap inside a recovery point still answers its status to the arming
call and never reaches the hook. Tested by `tests/embedded/trap-hook.ax`.

### What the hook may and may not do

The compiler checks these:

- The hook takes five `Int`s and answers an `Int`. Any other shape is
  `AX3010`.
- It doesn't allocate. `isr` implies `restrict(no-alloc)` (`AX3049`):
  the fault may have interrupted an allocation. Write to the UART with
  `__vstore8`, not `println`.
- It doesn't recurse. `isr` implies `restrict(no-recursion)`
  (`AX3049`): the hook runs on the 8 KiB fault stack, and the stack
  bound (RP-7) bounds it there.
- It doesn't wait for the program. A path to a system call, where
  every blocking library call ends, is `AX4009`. Halting in `wfi` is
  allowed.
- There is one hook. A second is `AX4008`, and so is the tag on any
  target but `baremetal-aarch64`.

These are yours to get right:

- The program's state may be corrupt. The fault is evidence that
  something already went wrong, so read only what you need and don't
  follow pointers the program built.
- There is no recovery across the boundary. The hook runs with no
  recovery point armed, so a trap inside it exits with its own status
  instead of unwinding into code the fault abandoned.
- D, A, I and F are masked while the hook runs. If you unmask
  interrupts inside it, an IRQ handler runs on the fault stack.
- A fault inside the hook doesn't re-enter it. The runtime writes one
  more line, `axiom: CPU exception in the fault handler at ...`, and
  exits 81. Tested by `tests/embedded/fault-in-hook.ax`.
- The exit status means something under QEMU or a debugger. On a board
  without one, semihosting's `hlt` is itself an exception, so the hook
  should end in a reset, a halt or a watchdog it stops feeding.
- The safe state is a system decision. The hook is where you put it,
  and "the hook ran" is never by itself "the system is safe".

### Interrupt handlers

`;@axiom:isr(irq)` binds one function to the IRQ vector. It's refused
as `AX4008` on any other target, for a vector name other than `irq` or
`fault`, and for a second handler. The rules are `docs/memory-model.md`
MM-EXEC-18:

- No nesting: IRQs stay masked for the handler's whole extent.
- No allocation and no recursion, both checked (`AX3049`).
- No waiting. A path to `__arm_wfi`, which would sleep with the
  interrupt that should wake it masked, or to a system call, is
  `AX4009`. A poll of a word the main loop writes waits too, and the
  compiler can't see it.
- No recovery across the boundary: a trap inside the handler exits
  with its own status.
- State shared with the main loop goes only through the unsafe layer:
  volatile accesses on the main loop's side, and IRQs masked around
  any multi-word read that must be consistent.

The handler takes no arguments. It finds its state through
`TPIDR_EL1` (`__arm_tpidr`), set before interrupts are unmasked.

Two complete examples run under QEMU. `tests/embedded/periodic.ax`
sets up the GICv2 and the virtual timer, re-arms the timer from its
handler, and runs a restricted step once per tick.
`tests/embedded/dma.ax` moves a buffer between the CPU and a DMA engine
under contract-checked ownership, with the timer as a deadline.

### The vector table is trusted code

The table is the one piece of hand-written assembly the port carries
besides `_start`. `emitBaremetalVectors` (`self_host/codegen.ax`) emits
it as `module asm`, and no check in the compiler looks inside it. It's
short:

- 16 slots of 128 bytes, 2 KiB aligned. Each slot is two instructions,
  `mov x0, #<slot offset>` and a branch to the fault exit. The
  exception is slot 5 (0x280, "current EL with SPx, IRQ") when a
  handler is bound, which branches to the IRQ entry. The port runs at
  EL1 on SP_EL1, so the 0x200 group is the one that fires; the others
  need a switch to SP_EL0 or a lower exception level, which the port
  never makes.
- The fault exit points sp at the fault stack, reads ESR_EL1, ELR_EL1
  and FAR_EL1 into x1 to x3, and calls `__axiom_cpu_exception`, an IR
  function that writes the report and exits 81 or calls the hook.
- The trap entry, only when a hook is bound, masks D, A, I and F,
  points sp at the fault stack and calls `__axiom_fault_trap`.
- The IRQ entry: `sub sp, sp, #592`; 24 `stp`s saving x0 to x18, x29,
  x30, ELR_EL1, SPSR_EL1, FPCR, FPSR, q0 to q7 and q16 to q31
  (everything AAPCS64 lets a callee clobber, and the exception state);
  `bl __axiom_irq_dispatch`; the mirror-image 24 `ldp`s;
  `add sp, sp, #592`; `eret`. The dispatch, in IR, clears the recovery
  slot, calls the tagged function, and puts the slot back.

`scripts/check-embedded.sh` A12, A17 and A19 check those lines in the
emitted IR.

## 6. MMU, MPU and caches

`_start` turns the MMU on before `main` runs. The translation tables
are identity-mapped: every virtual address is its physical address,
and the tables decide what each page may do.

| Range | Memory | Access |
|---|---|---|
| code: `.text.boot`, `.text` and the vector table | Normal | read-only, executable at EL1 |
| read-only data: `.rodata`, `.eh_frame`, `.got` | Normal | read-only, execute-never |
| data: `.data`, `.bss` and the arena in it | Normal | read-write, execute-never |
| 64 KiB guard | none | not mapped |
| the stack, 8 KiB | Normal | read-write, execute-never |
| 4 KiB guard | none | not mapped |
| the fault stack, 8 KiB | Normal | read-write, execute-never |
| the page tables | none | not mapped once the MMU is on |
| `0x08000000`, 2 MiB: the GIC | Device-nGnRnE | read-write, execute-never |
| `0x09000000`, 2 MiB: the UART, RTC, `fw_cfg`, GPIO | Device-nGnRnE | read-write, execute-never |
| everything else, address 0 included | none | not mapped |

Normal memory is inner and outer write-back, read- and write-allocate,
and inner shareable. The tables use 4 KiB pages: one level-1 table for
the 4 GiB the port addresses, and a level-3 table for every 2 MiB of
the image. `SCTLR_EL1` gets M (the MMU), C and I (both caches), A
(alignment checking), SA (stack-pointer alignment checking) and WXN
(every writable page is execute-never, whatever its descriptor says).

What that gives you:

- A store to code is a permission fault: ESR 0x9600004f
  (`tests/embedded/code-write.ax`).
- A branch into data is an instruction abort: ESR 0x8600000f
  (`tests/embedded/exec-data.ax`).
- An access outside the image and the two device blocks is a
  translation fault: ESR 0x96000006 at address 0
  (`tests/embedded/unmapped.ax`).
- A stack overflow is a translation fault in the guard, and the report
  says so (section 5).
- A misaligned access is an alignment fault on RAM as well as devices.
  That is why the bare target compiles with `+strict-align`: LLVM may
  not merge byte accesses into a wider unaligned one there.

The MMU is always on, and there is no flag to turn it off. The
protection is part of the port, and one configuration is one thing to
review. A peripheral outside the two device blocks faults: the map is
`emitMmuTables` in `self_host/codegen.ax`, and adding a block there is
the change a new device needs.

### Caches

RAM is cached, so cache maintenance matters. A device that isn't
coherent with the CPU's cache needs a buffer's lines cleaned
(`__arm_dc_cvac`) before it reads them, and cleaned and invalidated
(`__arm_dc_civac`) before the CPU reads what it wrote, each followed by
`__arm_dsb`. `tests/embedded/dma.ax` does both.

QEMU's TCG models no cache. C and I read back set, and nothing is
cached behind them, so no run here can show a missing clean or
invalidate. That needs hardware.

The image must reach `_start` coherent. QEMU writes it straight to
memory; a boot loader on a board must clean it to the point of
coherency first. `_start` invalidates only the lines of the tables it
builds.

### Limits

- There is no MPU configuration: `virt`'s Cortex-A72 has an MMU, not
  an MPU.
- A frame that moved the stack pointer more than 64 KiB before
  touching it could step over the guard. The compiler emits no frame
  that large.
- The tables are built for one core, the one that runs `_start`.

## 7. What was run where

| Evidence | Where it ran | Gate |
|---|---|---|
| volatile widths, `opt -O2` survival against a control, `llc` widths, every `__arm_` instruction, AX4008's target line | compile-only, every host | `check-embedded.sh` A11 |
| the volatile probe's answer, and the EL0 tier executing | the host the gate runs on (darwin-aarch64 when measured) | A11 |
| blink and its out-of-memory twin | QEMU `virt` (TCG) | A10 |
| the vector table's shape, `_start`'s writes, `+strict-align`, the IRQ entry and dispatch, AX4008 on bindings | compile-only, every host | A12 |
| an alignment fault exiting 81 with its registers | QEMU `virt` (TCG) | A12 |
| a periodic step on the virtual timer's interrupt through the GICv2, the restricted profile and a stack budget | QEMU `virt` (TCG); the profile and the bound compile-time | A13 |
| `fw_cfg` DMA under an ownership protocol, a contract stopping a device-owned read, a timer deadline | QEMU `virt` (TCG) | A14 |
| each target's `asm` arm, `opt -O2` keeping an unread block against a control, AX4008 for a missing arm | compile-only, every host | A15 |
| `tests/embedded/asm-el.ax` reading `CurrentEL` at EL1 through `asm` | QEMU `virt` (TCG) | A15 |
| `_start`'s order and registers, the descriptors decoded, periodic and DMA carrying the same `_start` | compile-only, every host | A16 |
| `SCTLR_EL1`, `TCR_EL1` and `MAIR_EL1` read back, and the image's layout | QEMU `virt` (TCG) | A16 |
| a stack overflow ending in the guard, named | QEMU `virt` (TCG) | A17 |
| a store to code, a branch into data and a read of address 0, each faulting where the map says | QEMU `virt` (TCG) | A18 |
| the hook's door, every trap exit reaching it, AX4008 for the hook, the fault exit bounded on its stack | compile-only, every host | A19 |
| the hook choosing the exit after a fault, after a trap, and by a PSCI reset | QEMU `virt` (TCG) | A19 |
| a fault inside the hook taking the fixed exit once | QEMU `virt` (TCG) | A20 |
| the fault hook's shape, recursion and waiting refused, each rule ablated | compile-only, every host | `check-isr.sh` |
| caches, cache maintenance, timing, bus faults, anything on hardware | **nothing** | none |

Where `qemu-system-aarch64` isn't on PATH, as on every CI runner, the
QEMU sections skip and say so. A skip is not a pass.
