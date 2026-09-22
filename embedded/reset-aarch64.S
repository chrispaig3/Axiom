// Reset vector for the bare-metal port: the stack, then `main`.
//
// Entered in EL1 with the MMU off, which is how QEMU's `-kernel`
// starts the primary CPU. Sets `sp` to the 8 KiB the linker script
// reserves, calls `main(0, 0)` - there are no arguments and no
// environment, and the `@main` wrapper stores both where `__argc`
// and `__argv` read them back - and reports the returned status
// through semihosting SYS_EXIT, the same sequence the in-module trap
// exits emit (`emitBaremetalExit`): X0 the operation (0x18), X1 the
// block, `hlt 0xf000`, reason ADP_Stopped_ApplicationExit in word 0
// and the status in word 1. The block here is this file's own
// 16 bytes of `.bss`, not the module's `@__axiom_exit_block`: that
// one is `internal` to the Axiom module and may be pruned from a
// program whose traps are, while this file must link against every
// program. With semihosting off the `hlt` faults instead of
// returning, so the `wfi` loop after it is the backstop, as it is
// there.
  .section .text.boot, "ax"
  .global _start
  .text
  .align 2
_start:
  ldr x0, =__stack_top
  mov sp, x0
  mov x0, #0
  mov x1, #0
  bl main
  // x0 holds main's status; keep it in x2 across the block stores.
  mov x2, x0
  ldr x1, =_reset_exit_block
  movz x0, #0x26
  movk x0, #0x2, lsl #16
  str x0, [x1]
  str x2, [x1, #8]
  mov x0, #0x18
  hlt 0xf000
1:
  wfi
  b 1b

  .bss
  .align 3
_reset_exit_block:
  .zero 16
