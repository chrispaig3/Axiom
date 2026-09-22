/* Bare-metal AArch64 link: QEMU's `virt` machine, `-kernel` ELF.
 *
 * RAM starts at 0x40000000; the kernel is loaded at its link address.
 * ENTRY is `_start` in `reset-aarch64.S`, kept first in `.text` so the
 * branch from the load address lands on it. `.bss` carries the 32 KiB
 * static arena (`@__axiom_arena`: the emitter's zero-initialised
 * global, addressed by the linker) and the 8 KiB stack the reset
 * vector aims `sp` at; both arrive zeroed because QEMU zeroes the
 * segments the headers describe. Nothing here names an Axiom symbol
 * but the stack bounds: the arena's base is "fixed at link time"
 * without this script knowing it, which is what a zero
 * `targetArenaStaticBase` means.
 */
ENTRY(_start)
SECTIONS
{
  . = 0x40000000;
  .text : {
    KEEP(*(.text.boot))
    *(.text*)
  }
  .rodata : {
    *(.rodata*)
  }
  .data : {
    *(.data*)
  }
  .bss : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(16);
    __stack_lo = .;
    . += 8K;
    __stack_top = .;
    __bss_end = .;
  }
  _end = .;
}
