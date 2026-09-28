# Embedded and OS integration guide — `baremetal-aarch64`

<!-- STATUS. This is the integration guide for the bare-metal port that
     docs/embedded-proposal.md section 6 built. It says what the port
     does, what a program on it may rely on, and - in the last section -
     exactly what was executed where. Every behaviour below was run under
     QEMU's TCG emulator or checked on emitted code; NOTHING here has run
     on hardware, and nothing here is a hardware, certification or
     mission-suitability claim. Where a property is emulator evidence or
     compile-only evidence, the sentence says which.

     The proposal is the design record and stays one; this is the
     reference a program's author reads. -->

## 1. The target in one table

| | `baremetal-aarch64` |
|---|---|
| triple | `aarch64-unknown-none-elf`, little-endian |
| board it is tested on | QEMU `virt`, `-cpu cortex-a72`, TCG (emulated), no hardware |
| exception level | EL1 (QEMU starts a `-kernel` ELF there when EL2/EL3 are absent) |
| MMU | **off** - every data access is Device-nGnRnE memory (section 6) |
| heap | a static arena in `.bss`: 32 KiB in 4 KiB chunks by default, `--heap-ceiling N` to set it (MM-ALLOC-7 status 70 on exhaustion) |
| console | PL011 UART data register at `0x09000000`, written by volatile byte stores |
| exit | ARM semihosting `SYS_EXIT` (`hlt #0xf000`), so the guest's status is QEMU's |
| threads | none: `--threads` is `AX4006` on a static arena |
| linker | `ld.lld` with a generated script (`driver.ax` `baremetalLinkScript`) |
| faults | an exception vector table in every image; an unhandled exception exits **81** with its registers on the UART |

## 2. Startup, linker layout, stack and initialisation

**The image.** `axiom build --target=baremetal-aarch64` emits the IR,
runs `llc` and links with `ld.lld -T <generated script>` - no C runtime,
nothing dynamic. The script, in full:

```
ENTRY(_start)
SECTIONS {
  . = 0x40000000;
  .text.boot : { KEEP(*(.text.boot)) }
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(16);
  __stack_top = . + 0x2000;
}
```

`virt` maps RAM at `0x40000000`, and QEMU's `-kernel` loads the ELF's
segments at their addresses and jumps to `_start`. The vector table is
`.text.vectors`, 2 KiB aligned, placed inside `.text` by the `.text*`
pattern. The static arena is an ordinary zero-initialised `.bss` array
(`@__axiom_arena`), so the linker places it and QEMU's loader zeroes
it; nothing at run time clears memory.

**The stack** is the 8 KiB above `.bss` (`__stack_top`), growing down
toward it. There is no guard: with the MMU off a stack that outgrows 8
KiB writes into the arena without a fault. The defence is static - a
`restrict(no-recursion)` call graph has a computable bound
(`scripts/check-stack-bound.sh`) - and an interrupt adds its 592-byte
save area and the handler's frames on top of whatever depth the main
loop is at when it arrives.

**Initialisation**, in `_start` (emitted by `emitBaremetalStart`, naked,
in `.text.boot`), before `main` runs a single instruction:

1. `sp` := `__stack_top` (the reset value is undefined);
2. `CPACR_EL1.FPEN` := `0b11`, so FP and SIMD instructions do not trap
   (a `Float`, or a copy the compiler vectorised, would otherwise be an
   undefined-instruction exception);
3. `VBAR_EL1` := the vector table, then `ISB`;
4. `main` is called with `argc = argv = 0`; its answer is the semihosting
   exit status.

Interrupts stay masked (their reset state) until the program unmasks
them. Nothing else is initialised: no MMU, no caches, no GIC, no timer -
a program that wants those sets them up itself.

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
| `__arm_ctr` | read `CTR_EL0` | bare metal | `IO` |
| `(__arm_set_cntv_cval t)` / `(__arm_set_cntv_ctl c)` | write the virtual timer | bare metal | `Mut` |
| `__arm_irq_mask` / `__arm_irq_unmask` | `msr daifset, #2` / `msr daifclr, #2` | bare metal | `Mut` |
| `__arm_wfi` | `wfi` | bare metal | `IO` |
| `(__arm_dc_cvac a)` / `(__arm_dc_civac a)` | `dc cvac` / `dc civac` | bare metal | `Mut`, `Unsafe` |
| `__arm_tpidr` / `(__arm_set_tpidr v)` | read / write `TPIDR_EL1` | bare metal | none / `Mut` |

"Any AArch64" means the instruction runs at EL0, so an aarch64 host
(Linux, Darwin, FreeBSD) runs it too; "bare metal" means it needs EL1.
A primitive the target cannot execute is refused at build time as
`AX4008`, reading the module AFTER unreachable functions are pruned - a
helper nothing calls is never refused. A body that calls an `Unsafe`
primitive directly says `;@axiom:effect(unsafe)` (`AX3073`); one that
reads the counter says `;@axiom:effect(io)`.

**What volatile gives you.** The compiler keeps every volatile access -
it does not delete, merge, split, widen or narrow one - and keeps two
volatile accesses in program order. That is what a device register
needs: a write nothing reads back is still a doorbell, and a 32-bit
register must be read as one 32-bit access. `scripts/check-embedded.sh`
A11 is the evidence: after `opt -O2`, a register written twice keeps
both writes while the same code through the ordinary `__store8`/
`__store64` loses the first, and `llc` emits each width as its own
instruction (`strb`/`strh`/`str w`/`str x` and the loads).

**What volatile does not give you**, each the program's obligation:

1. **Alignment.** The address must be a multiple of the width. With the
   MMU off a misaligned access is an alignment fault, not a slow access.
2. **Ordering against ordinary memory.** The compiler may move an
   ordinary load or store across a volatile one, and the hardware may
   make ordinary writes visible after a later device write. Where a
   device reads memory the CPU wrote - a DMA descriptor - put
   `__arm_dsb` (or `__arm_dmb`) between the writes and the doorbell.
   Every `__arm_` primitive that orders, waits or writes is also a
   compiler barrier.
3. **Synchronisation.** Volatile is not atomic and creates no
   happens-before edge. Between threads use the atomics (MM-PAR-9); a
   volatile flag does not publish the data written before it. On ONE
   core, between an interrupt handler and the code it interrupted,
   volatile IS the right tool for a word the handler writes and the
   main loop polls - what must be prevented is the compiler keeping
   the word in a register.
4. **Read-modify-write atomicity.** One naturally aligned access is
   single-copy atomic; a read, a mask and a write are three accesses.

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

**The vector table is trusted code.** It is the one piece of
hand-written assembly the port carries beyond `_start`, emitted as
`module asm` by `emitBaremetalVectors` (`self_host/codegen.ax`), and no
check in the compiler looks inside it. It is short on purpose:

- 16 slots of 128 bytes, 2 KiB aligned. Each slot is two instructions -
  `mov x0, #<slot offset>` and a branch to the fault exit - except slot
  5 (0x280, "current EL with SPx, IRQ") when a handler is bound, which
  branches to the IRQ entry. The port runs at EL1 on SP_EL1, so the
  0x200 group is the one that fires; the others need a switch to SP_EL0
  or a lower exception level, which the port never makes.
- The fault exit: `mrs` ESR_EL1, ELR_EL1 and FAR_EL1 into x1-x3 and
  `bl __axiom_cpu_exception`, an IR function that writes one line to
  the UART and exits 81 through semihosting. A second exception while
  reporting (a guard word) exits without writing.
- The IRQ entry: `sub sp, sp, #592`; 24 `stp`s saving x0-x18, x29, x30,
  ELR_EL1, SPSR_EL1, FPCR, FPSR, q0-q7 and q16-q31 (everything AAPCS64
  lets a callee clobber, and the exception state); `bl
  __axiom_irq_dispatch`; the mirror-image 24 `ldp`s; `add sp, sp, #592`;
  `eret`. The dispatch, in IR, clears the recovery slot, calls the
  tagged function, and puts the slot back.

`scripts/check-embedded.sh` A12 counts every one of those lines in the
emitted IR.

**Fault handling.** A synchronous exception (alignment fault, data or
instruction abort, undefined instruction), an SError, an FIQ, or an IRQ
with no handler bound, ends the program:

```
axiom: unhandled CPU exception at vector 0x0000000000000200 esr 0x0000000096000021 elr 0x0000000040001898 far 0x00000000400037c1
```

and QEMU exits 81. That line is `tests/embedded/fault.ax`, a misaligned
32-bit load, measured: ESR 0x96000021 is EC 0x25 (data abort, current
EL) with DFSC 0x21 (alignment), ELR the faulting instruction, FAR the
odd address. There is **no recovery policy hook**: the exit is fixed,
and a recovery point the program armed is not jumped to, because the
jump would resume code in exception context with interrupts masked. A
program that needs a different policy - log and reset, fall back to a
safe mode - needs a fault handler of its own, which this port does not
offer; and on any real system a CPU exception is evidence that
something upstream went wrong, so "the trap fired" is never by itself
"the system is safe".

**Interrupt handlers.** `;@axiom:isr(irq)` binds one function to the
IRQ vector (refused as `AX4008` elsewhere, for any other vector name,
and for a second handler). The rules are `docs/memory-model.md`
MM-EXEC-18: no nesting (IRQs are masked for the handler's whole
extent); no allocation (checked, `AX3049`); no recovery across the
boundary (a trap inside the handler exits with its own status); no
waiting on anything the main loop does; state shared with the main loop
only through the unsafe layer, read with volatile accesses on the
main-loop side and with IRQs masked around any multi-word read that
must be consistent. The handler takes no arguments and finds its state
through `TPIDR_EL1` (`__arm_tpidr`), set before interrupts are unmasked.

## 6. MMU, MPU and caches

The port runs with the **MMU off**, and says so rather than implying
protection it does not have:

- every data access is Device-nGnRnE memory: strongly ordered, never
  cached, never gathered - and a misaligned access faults, which is why
  the bare target compiles with `+strict-align` (LLVM may not merge byte
  accesses into a wider unaligned one there);
- there is no memory protection: no execute-never data, no read-only
  code, no stack guard page. A wild store can overwrite code; a stack
  overflow runs into the arena;
- the data cache is effectively off (SCTLR_EL1.C is 0 with the MMU off),
  so cache maintenance a driver performs is exercised for ordering and
  has nothing to be coherent with;
- there is no MPU configuration: `virt`'s Cortex-A72 has an MMU, not an
  MPU, and nothing here programs either.

Turning the MMU on (identity-mapped page tables, normal memory for RAM,
device memory for the peripherals) is what a real deployment does
first, and it changes what the cache and barrier sections require; it
is not in this port.

## 7. What was run where

| Evidence | Where it ran | Gate |
|---|---|---|
| volatile widths, `opt -O2` survival against a control, `llc` widths, every `__arm_` instruction, AX4008's target line | compile-only, every host | `check-embedded.sh` A11 |
| the volatile probe's answer, and the EL0 tier executing | the host the gate runs on (darwin-aarch64 when measured) | A11 |
| blink and its out-of-memory twin | QEMU `virt` (TCG) | A10 |
| the vector table's shape, `_start`'s writes, `+strict-align`, the IRQ entry and dispatch, AX4008 on bindings | compile-only, every host | A12 |
| an alignment fault exiting 81 with its registers | QEMU `virt` (TCG) | A12 |
| anything on hardware | **nothing** | - |

Where `qemu-system-aarch64` is not on PATH - every CI runner today -
the QEMU sections skip and say so; a skip is not a pass.
