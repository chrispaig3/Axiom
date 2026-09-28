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
| heap | a static arena in `.bss`, bounded by `--heap-ceiling N` or the target's row (MM-ALLOC-7 status 70 on exhaustion) |
| console | PL011 UART data register at `0x09000000`, written by volatile byte stores |
| exit | ARM semihosting `SYS_EXIT` (`hlt #0xf000`), so the guest's status is QEMU's |
| threads | none: `--threads` is `AX4006` on a static arena |
| linker | `ld.lld` with a generated script (`driver.ax` `baremetalLinkScript`) |

## 2. Device access: volatile, barriers, and what is not synchronisation

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

## 3. Alignment, endianness, integer width and ABI

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

## 4. What was run where

| Evidence | Where it ran | Gate |
|---|---|---|
| volatile widths, `opt -O2` survival against a control, `llc` widths, every `__arm_` instruction, AX4008's target line | compile-only, every host | `check-embedded.sh` A11 |
| the volatile probe's answer, and the EL0 tier executing | the host the gate runs on (darwin-aarch64 when measured) | A11 |
| blink and its out-of-memory twin | QEMU `virt` (TCG) | A10 |
| anything on hardware | **nothing** | - |

Where `qemu-system-aarch64` is not on PATH - every CI runner today -
the QEMU sections skip and say so; a skip is not a pass.
