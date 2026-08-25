	.file	"fixed.ll"
	.text
	.globl	main                            // -- Begin function main
	.p2align	2
	.type	main,@function
main:                                   // @main
	.cfi_startproc
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	adrp	x8, __axiom_argc
	adrp	x9, __axiom_argv
	str	x0, [x8, :lo12:__axiom_argc]
	str	x1, [x9, :lo12:__axiom_argv]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	__axiom_user_main
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
                                        // -- End function
	.globl	axiom_alloc                     // -- Begin function axiom_alloc
	.p2align	2
	.type	axiom_alloc,@function
axiom_alloc:                            // @axiom_alloc
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	cbz	x0, .LBB1_10
// %bb.1:                               // %sized
	add	x8, x0, #15
	adrp	x11, __axiom_high
	and	x10, x8, #0xfffffffffffffff0
	cmp	x10, #16, lsl #12               // =65536
	add	x12, x10, #16
	b.hi	.LBB1_4
// %bb.2:                               // %try_pop
	lsr	x9, x8, #4
	adrp	x13, __axiom_slabs
	add	x13, x13, :lo12:__axiom_slabs
	ldr	x8, [x13, x9, lsl #3]
	cbz	x8, .LBB1_4
// %bb.3:                               // %pop
	ldr	x14, [x8]
	ldr	x15, [x11, :lo12:__axiom_high]
	add	x16, x8, x12
	str	x14, [x13, x9, lsl #3]
	mov	w9, #1                          // =0x1
	b	.LBB1_16
.LBB1_4:                                // %bump_path
	adrp	x13, __axiom_bump
	adrp	x14, __axiom_bump_end
	ldr	x8, [x13, :lo12:__axiom_bump]
	ldr	x9, [x14, :lo12:__axiom_bump_end]
	add	x16, x8, x12
	cmp	x16, x9
	b.ls	.LBB1_11
// %bb.5:                               // %refill
	mov	w8, #65537                      // =0x10001
	sub	x9, x10, #255, lsl #12          // =1044480
	mov	x15, #-1048577                  // =0xffffffffffefffff
	add	x8, x8, x10
	sub	x9, x9, #4065
	mov	x0, xzr
	add	x16, x8, #30
	adrp	x8, __axiom_free
	cmp	x9, x15
	and	x17, x16, #0xffffffffffff0000
	mov	w9, #1048576                    // =0x100000
	ldr	x16, [x8, :lo12:__axiom_free]
	csel	x9, x17, x9, lo
.LBB1_6:                                // %scan
                                        // =>This Inner Loop Header: Depth=1
	mov	x18, x0
	mov	x0, x16
	cbz	x16, .LBB1_12
// %bb.7:                               // %scan_test
                                        //   in Loop: Header=BB1_6 Depth=1
	ldp	x17, x16, [x0]
	cmp	x17, x9
	b.lo	.LBB1_6
// %bb.8:                               // %unlink
	add	x15, x17, x0
	cbz	x18, .LBB1_14
// %bb.9:                               // %unlink_mid
	str	x16, [x18, #8]
	b	.LBB1_15
.LBB1_10:                               // %zero
	adrp	x8, __axiom_bump
	ldr	x0, [x8, :lo12:__axiom_bump]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB1_11:                               // %fast
	ldr	x15, [x11, :lo12:__axiom_high]
	mov	w9, wzr
	str	x16, [x13, :lo12:__axiom_bump]
	b	.LBB1_16
.LBB1_12:                               // %map
	mov	x1, x9
	mov	x5, xzr
	mov	w8, #222                        // =0xde
	mov	w2, #3                          // =0x3
	mov	w3, #34                         // =0x22
	mov	x4, #-1                         // =0xffffffffffffffff
	//APP
	svc	#0
	//NO_APP
	mov	w15, #8191                      // =0x1fff
	add	x8, x0, #4095
	cmp	x8, x15
	b.lo	.LBB1_20
// %bb.13:                              // %mapped
	add	x15, x0, #16
	mov	x17, x9
	b	.LBB1_15
.LBB1_14:                               // %unlink_head
	str	x16, [x8, :lo12:__axiom_free]
.LBB1_15:                               // %install
	str	x17, [x0]
	adrp	x18, __axiom_chunk
	add	x8, x0, #16
	ldr	x16, [x18, :lo12:__axiom_chunk]
	mov	w9, wzr
	str	x16, [x0, #8]
	add	x16, x8, x12
	add	x12, x17, x0
	str	x0, [x18, :lo12:__axiom_chunk]
	str	x16, [x13, :lo12:__axiom_bump]
	str	x12, [x14, :lo12:__axiom_bump_end]
.LBB1_16:                               // %handout
	cmp	x16, x15
	csel	x12, x16, x15, lo
	csel	x13, x16, x15, hi
	cmp	w9, #0
	csel	x9, x16, x12, ne
	csel	x12, x15, x13, ne
	cmp	x8, x9
	str	x12, [x11, :lo12:__axiom_high]
	b.hs	.LBB1_19
// %bb.17:                              // %wipe_body.preheader
	mov	x11, x8
.LBB1_18:                               // %wipe_body
                                        // =>This Inner Loop Header: Depth=1
	str	xzr, [x11], #8
	cmp	x11, x9
	b.lo	.LBB1_18
.LBB1_19:                               // %wiped
	lsr	x9, x10, #2
	mov	w11, #131064                    // =0x1fff8
	add	x0, x8, #16
	cmp	x10, x11
	csel	x9, xzr, x9, hi
	stp	xzr, x9, [x8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB1_20:                               // %oom
	bl	__axiom_out_of_memory
.Lfunc_end1:
	.size	axiom_alloc, .Lfunc_end1-axiom_alloc
                                        // -- End function
	.globl	axiom_retain                    // -- Begin function axiom_retain
	.p2align	2
	.type	axiom_retain,@function
axiom_retain:                           // @axiom_retain
// %bb.0:                               // %entry
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB2_4
// %bb.1:                               // %chk
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldur	x8, [x0, #-16]
	mov	x29, sp
	cmn	x8, #1
	b.eq	.LBB2_3
// %bb.2:                               // %bump
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB2_3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB2_4:                                // %done
	ret
.Lfunc_end2:
	.size	axiom_retain, .Lfunc_end2-axiom_retain
                                        // -- End function
	.globl	axiom_release                   // -- Begin function axiom_release
	.p2align	2
	.type	axiom_release,@function
axiom_release:                          // @axiom_release
	.cfi_startproc
// %bb.0:                               // %start
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	stp	x26, x25, [sp, #16]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	mov	x21, xzr
	mov	x20, xzr
	mov	x23, xzr
	adrp	x19, __axiom_slabs
	add	x19, x19, :lo12:__axiom_slabs
                                        // implicit-def: $x22
                                        // implicit-def: $x24
	b	.LBB3_3
.LBB3_1:                                // %arrstep
                                        //   in Loop: Header=BB3_3 Depth=1
	sub	x8, x24, #1
	add	x9, x22, #1
	mov	w23, #1                         // =0x1
.LBB3_2:                                // %relchild
                                        //   in Loop: Header=BB3_3 Depth=1
	ldr	x0, [x20, x22, lsl #3]
	mov	x22, x9
	mov	x24, x8
.LBB3_3:                                // %relone
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB3_19 Depth 2
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB3_6
// %bb.4:                               // %chk
                                        //   in Loop: Header=BB3_3 Depth=1
	mov	x25, x0
	ldr	x8, [x25, #-16]!
	sub	x8, x8, #1
	cmn	x8, #3
	b.hi	.LBB3_6
// %bb.5:                               // %dec
                                        //   in Loop: Header=BB3_3 Depth=1
	str	x8, [x25]
	cbz	x8, .LBB3_8
.LBB3_6:                                // %after
                                        //   in Loop: Header=BB3_3 Depth=1
	mov	x0, x21
	mov	x21, x0
	cbz	x20, .LBB3_26
.LBB3_7:                                // %walk.peel
                                        //   in Loop: Header=BB3_3 Depth=1
	cbnz	x24, .LBB3_17
	b	.LBB3_23
.LBB3_8:                                // %dead0
                                        //   in Loop: Header=BB3_3 Depth=1
	ldur	x26, [x0, #-8]
	cmp	x26, #8, lsl #12                // =32768
	b.lo	.LBB3_11
// %bb.9:                               // %dead0
                                        //   in Loop: Header=BB3_3 Depth=1
	tbnz	w26, #0, .LBB3_11
// %bb.10:                              // %defer
                                        //   in Loop: Header=BB3_3 Depth=1
	str	x21, [x25]
	mov	x21, x0
	cbnz	x20, .LBB3_7
	b	.LBB3_26
.LBB3_11:                               // %notrec
                                        //   in Loop: Header=BB3_3 Depth=1
	tbz	w26, #0, .LBB3_15
// %bb.12:                              // %foreign
                                        //   in Loop: Header=BB3_3 Depth=1
	ldr	x9, [x0]
	cbz	x9, .LBB3_15
// %bb.13:                              // %foreign
                                        //   in Loop: Header=BB3_3 Depth=1
	ldr	x8, [x0, #8]
	cbz	x8, .LBB3_15
// %bb.14:                              // %fcall
                                        //   in Loop: Header=BB3_3 Depth=1
	str	xzr, [x0, #8]
	mov	x0, x8
	blr	x9
.LBB3_15:                               // %filev
                                        //   in Loop: Header=BB3_3 Depth=1
	ubfx	x8, x26, #1, #14
	sub	x9, x8, #1
	lsr	x9, x9, #13
	cbnz	x9, .LBB3_6
// %bb.16:                              // %push
                                        //   in Loop: Header=BB3_3 Depth=1
	lsl	x8, x8, #2
	and	x8, x8, #0xfff8
	ldr	x9, [x19, x8]
	str	x9, [x25]
	str	x25, [x19, x8]
	b	.LBB3_6
.LBB3_17:                               // %stepone.peel
                                        //   in Loop: Header=BB3_3 Depth=1
	cbnz	x23, .LBB3_1
// %bb.18:                              // %testbit.peel
                                        //   in Loop: Header=BB3_3 Depth=1
	lsr	x8, x24, #1
	tbnz	w24, #0, .LBB3_22
.LBB3_19:                               // %walk
                                        //   Parent Loop BB3_3 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	cbz	x8, .LBB3_23
// %bb.20:                              // %testbit
                                        //   in Loop: Header=BB3_19 Depth=2
	lsr	x10, x8, #1
	mov	w9, w8
	add	x22, x22, #1
	mov	x8, x10
	tbz	w9, #0, .LBB3_19
// %bb.21:                              // %relchild.loopexit
                                        //   in Loop: Header=BB3_3 Depth=1
	mov	x23, xzr
	add	x9, x22, #1
	mov	x8, x10
	b	.LBB3_2
.LBB3_22:                               //   in Loop: Header=BB3_3 Depth=1
	mov	x23, xzr
	add	x9, x22, #1
	b	.LBB3_2
.LBB3_23:                               // %fileD
                                        //   in Loop: Header=BB3_3 Depth=1
	ldur	x8, [x20, #-8]
	ubfx	x8, x8, #1, #14
	sub	x9, x8, #1
	lsr	x9, x9, #13
	cbnz	x9, .LBB3_25
// %bb.24:                              // %pushD
                                        //   in Loop: Header=BB3_3 Depth=1
	lsl	x8, x8, #2
	and	x8, x8, #0xfff8
	ldr	x9, [x19, x8]
	str	x9, [x20, #-16]!
	str	x20, [x19, x8]
.LBB3_25:                               // %drain
                                        //   in Loop: Header=BB3_3 Depth=1
	mov	x0, x21
.LBB3_26:                               // %drain
                                        //   in Loop: Header=BB3_3 Depth=1
	cbz	x0, .LBB3_28
// %bb.27:                              // %popD
                                        //   in Loop: Header=BB3_3 Depth=1
	ldp	x21, x8, [x0, #-16]
	mov	x22, xzr
	mov	x20, x0
	lsr	x9, x8, #16
	ubfx	x10, x8, #1, #14
	ands	x8, x8, #0x8000
	lsr	x23, x8, #15
	csel	x24, x9, x10, eq
	cbnz	x24, .LBB3_17
	b	.LBB3_23
.LBB3_28:                               // %done
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
	ret
.Lfunc_end3:
	.size	axiom_release, .Lfunc_end3-axiom_release
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_arena_mark_fn
	.type	__axiom_arena_mark_fn,@function
__axiom_arena_mark_fn:                  // @__axiom_arena_mark_fn
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w0, #24                         // =0x18
	mov	x29, sp
	bl	axiom_alloc
	adrp	x8, __axiom_bump
	adrp	x9, __axiom_bump_end
	adrp	x10, __axiom_chunk
	ldr	x8, [x8, :lo12:__axiom_bump]
	ldr	x9, [x9, :lo12:__axiom_bump_end]
	ldr	x10, [x10, :lo12:__axiom_chunk]
	stp	x8, x9, [x0]
	str	x10, [x0, #16]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end4:
	.size	__axiom_arena_mark_fn, .Lfunc_end4-__axiom_arena_mark_fn
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_arena_reset_fn
	.type	__axiom_arena_reset_fn,@function
__axiom_arena_reset_fn:                 // @__axiom_arena_reset_fn
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, __axiom_slabs
	add	x8, x8, :lo12:__axiom_slabs
	mov	w9, #4097                       // =0x1001
	mov	x29, sp
.LBB5_1:                                // %slabclear
                                        // =>This Inner Loop Header: Depth=1
	subs	x9, x9, #1
	str	xzr, [x8], #8
	b.ne	.LBB5_1
// %bb.2:                               // %resetbody
	adrp	x8, __axiom_chunk
	ldp	x11, x9, [x0, #8]
	ldr	x12, [x8, :lo12:__axiom_chunk]
	ldr	x10, [x0]
	cmp	x12, x9
	b.eq	.LBB5_8
// %bb.3:                               // %unwind.preheader
	cbz	x12, .LBB5_7
// %bb.4:                               // %unwind_body.preheader
	adrp	x13, __axiom_free
.LBB5_5:                                // %unwind_body
                                        // =>This Inner Loop Header: Depth=1
	ldr	x14, [x12, #8]
	ldr	x15, [x13, :lo12:__axiom_free]
	cmp	x14, x9
	str	x15, [x12, #8]
	str	x12, [x13, :lo12:__axiom_free]
	b.eq	.LBB5_7
// %bb.6:                               // %unwind_body
                                        //   in Loop: Header=BB5_5 Depth=1
	mov	x12, x14
	cbnz	x14, .LBB5_5
.LBB5_7:                                // %tail
	adrp	x12, __axiom_high
	str	x11, [x12, :lo12:__axiom_high]
.LBB5_8:                                // %restore
	adrp	x12, __axiom_bump
	adrp	x13, __axiom_bump_end
	mov	x0, xzr
	str	x10, [x12, :lo12:__axiom_bump]
	str	x11, [x13, :lo12:__axiom_bump_end]
	str	x9, [x8, :lo12:__axiom_chunk]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end5:
	.size	__axiom_arena_reset_fn, .Lfunc_end5-__axiom_arena_reset_fn
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_arena_reset_keeping_fn
	.type	__axiom_arena_reset_keeping_fn,@function
__axiom_arena_reset_keeping_fn:         // @__axiom_arena_reset_keeping_fn
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x2
	mov	x10, x1
	adrp	x8, __axiom_slabs
	add	x8, x8, :lo12:__axiom_slabs
	mov	w11, #4097                      // =0x1001
	mov	x29, sp
.LBB6_1:                                // %slabclear.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x11, x11, #1
	str	xzr, [x8], #8
	b.ne	.LBB6_1
// %bb.2:                               // %resetbody.i
	adrp	x12, __axiom_chunk
	ldp	x17, x11, [x0, #8]
	ldr	x13, [x12, :lo12:__axiom_chunk]
	ldr	x8, [x0]
	cmp	x13, x11
	b.eq	.LBB6_8
// %bb.3:                               // %unwind.preheader.i
	cbz	x13, .LBB6_7
// %bb.4:                               // %unwind_body.i.preheader
	adrp	x14, __axiom_free
.LBB6_5:                                // %unwind_body.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x15, [x13, #8]
	ldr	x16, [x14, :lo12:__axiom_free]
	cmp	x15, x11
	str	x16, [x13, #8]
	str	x13, [x14, :lo12:__axiom_free]
	b.eq	.LBB6_7
// %bb.6:                               // %unwind_body.i
                                        //   in Loop: Header=BB6_5 Depth=1
	mov	x13, x15
	cbnz	x15, .LBB6_5
.LBB6_7:                                // %tail.i
	adrp	x13, __axiom_high
	str	x17, [x13, :lo12:__axiom_high]
.LBB6_8:                                // %__axiom_arena_reset_fn.exit
	add	x13, x9, #15
	adrp	x14, __axiom_bump
	adrp	x15, __axiom_bump_end
	and	x13, x13, #0xfffffffffffffff0
	str	x8, [x14, :lo12:__axiom_bump]
	add	x16, x13, #16
	str	x17, [x15, :lo12:__axiom_bump_end]
	add	x18, x8, x16
	str	x11, [x12, :lo12:__axiom_chunk]
	cmp	x18, x17
	b.ls	.LBB6_11
// %bb.9:                               // %fresh
	add	x8, x13, #16, lsl #12           // =65536
	mov	x0, xzr
	mov	x5, xzr
	add	x8, x8, #31
	mov	w2, #3                          // =0x3
	mov	w3, #34                         // =0x22
	and	x11, x8, #0xffffffffffff0000
	mov	w8, #222                        // =0xde
	mov	x4, #-1                         // =0xffffffffffffffff
	mov	x1, x11
	mov	w17, #8191                      // =0x1fff
	//APP
	svc	#0
	//NO_APP
	add	x8, x0, #4095
	cmp	x8, x17
	b.lo	.LBB6_16
// %bb.10:                              // %adopt
	str	x11, [x0]
	add	x8, x0, #16
	add	x11, x0, x11
	ldr	x17, [x12, :lo12:__axiom_chunk]
	add	x16, x8, x16
	str	x17, [x0, #8]
	str	x11, [x15, :lo12:__axiom_bump_end]
	adrp	x11, __axiom_high
	str	x0, [x12, :lo12:__axiom_chunk]
	str	x16, [x14, :lo12:__axiom_bump]
	str	x16, [x11, :lo12:__axiom_high]
	b	.LBB6_12
.LBB6_11:                               // %inplace
	str	x18, [x14, :lo12:__axiom_bump]
.LBB6_12:                               // %copy
	lsr	x11, x13, #2
	mov	w12, #131064                    // =0x1fff8
	add	x0, x8, #16
	cmp	x13, x12
	csel	x11, xzr, x11, hi
	stp	xzr, x11, [x8]
	cbz	x9, .LBB6_15
// %bb.13:                              // %loop_body.preheader
	mov	x8, x0
.LBB6_14:                               // %loop_body
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x10], #1
	subs	x9, x9, #1
	strb	w11, [x8], #1
	b.ne	.LBB6_14
.LBB6_15:                               // %done
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB6_16:                               // %oom
	bl	__axiom_out_of_memory
.Lfunc_end6:
	.size	__axiom_arena_reset_keeping_fn, .Lfunc_end6-__axiom_arena_reset_keeping_fn
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_div_by_zero
	.type	__axiom_div_by_zero,@function
__axiom_div_by_zero:                    // @__axiom_div_by_zero
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w0, #72                         // =0x48
	mov	x29, sp
	bl	__axiom_recover_abort
	adrp	x1, .L__axiom_divzero_msg
	add	x1, x1, :lo12:.L__axiom_divzero_msg
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	mov	w2, #24                         // =0x18
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	bl	__axiom_backtrace
	mov	w8, #94                         // =0x5e
	mov	w0, #72                         // =0x48
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.Lfunc_end7:
	.size	__axiom_div_by_zero, .Lfunc_end7-__axiom_div_by_zero
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_out_of_memory
	.type	__axiom_out_of_memory,@function
__axiom_out_of_memory:                  // @__axiom_out_of_memory
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w0, #70                         // =0x46
	mov	x29, sp
	bl	__axiom_recover_abort
	adrp	x1, .L__axiom_oom_msg
	add	x1, x1, :lo12:.L__axiom_oom_msg
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	mov	w2, #35                         // =0x23
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	bl	__axiom_backtrace
	mov	w8, #94                         // =0x5e
	mov	w0, #70                         // =0x46
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.Lfunc_end8:
	.size	__axiom_out_of_memory, .Lfunc_end8-__axiom_out_of_memory
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_recover_abort
	.type	__axiom_recover_abort,@function
__axiom_recover_abort:                  // @__axiom_recover_abort
// %bb.0:                               // %entry
	adrp	x8, __axiom_recover_top
	ldr	x8, [x8, :lo12:__axiom_recover_top]
	cbnz	x8, .LBB9_2
// %bb.1:                               // %none
	mov	x0, xzr
	ret
.LBB9_2:                                // %jump
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	mov	x22, x8
	mov	x29, sp
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	ldp	x19, x20, [x8]
	ldp	x21, x8, [x8, #16]
	str	x0, [x22, #40]
	mov	x0, x8
	bl	__axiom_arena_reset_fn
	//APP
	mov	x9, x22
	mov	sp, x19
	mov	x29, x20
	br	x21
	//NO_APP
.Lfunc_end9:
	.size	__axiom_recover_abort, .Lfunc_end9-__axiom_recover_abort
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_str_eq
	.type	__axiom_str_eq,@function
__axiom_str_eq:                         // @__axiom_str_eq
// %bb.0:                               // %entry
	cmp	x0, x1
	b.ne	.LBB10_3
// %bb.1:
	mov	w0, #1                          // =0x1
.LBB10_2:                               // %common.ret
	ret
.LBB10_3:                               // %chk
	mov	x8, x0
	mov	x0, xzr
	cbz	x8, .LBB10_2
// %bb.4:                               // %chk
	cbz	x1, .LBB10_2
// %bb.5:                               // %lens
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x9, [x8]
	ldr	x10, [x1]
	mov	x29, sp
	cmp	x9, x10
	b.ne	.LBB10_9
// %bb.6:                               // %data
	ldr	x8, [x8, #8]
	ldr	x10, [x1, #8]
	mov	w0, #1                          // =0x1
.LBB10_7:                               // %loop
                                        // =>This Inner Loop Header: Depth=1
	cbz	x9, .LBB10_10
// %bb.8:                               // %body
                                        //   in Loop: Header=BB10_7 Depth=1
	ldrb	w11, [x8], #1
	sub	x9, x9, #1
	ldrb	w12, [x10], #1
	cmp	w11, w12
	b.eq	.LBB10_7
.LBB10_9:
	mov	x0, xzr
.LBB10_10:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end10:
	.size	__axiom_str_eq, .Lfunc_end10-__axiom_str_eq
                                        // -- End function
	.globl	Sys.Platform$sysRead            // -- Begin function Sys.Platform$sysRead
	.p2align	2
	.type	Sys.Platform$sysRead,@function
Sys.Platform$sysRead:                   // @"Sys.Platform$sysRead"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #63                         // =0x3f
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end11:
	.size	Sys.Platform$sysRead, .Lfunc_end11-Sys.Platform$sysRead
                                        // -- End function
	.globl	Sys.Platform$sysWrite           // -- Begin function Sys.Platform$sysWrite
	.p2align	2
	.type	Sys.Platform$sysWrite,@function
Sys.Platform$sysWrite:                  // @"Sys.Platform$sysWrite"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #64                         // =0x40
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end12:
	.size	Sys.Platform$sysWrite, .Lfunc_end12-Sys.Platform$sysWrite
                                        // -- End function
	.globl	Sys.Platform$sysOpen            // -- Begin function Sys.Platform$sysOpen
	.p2align	2
	.type	Sys.Platform$sysOpen,@function
Sys.Platform$sysOpen:                   // @"Sys.Platform$sysOpen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #56                         // =0x38
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end13:
	.size	Sys.Platform$sysOpen, .Lfunc_end13-Sys.Platform$sysOpen
                                        // -- End function
	.globl	Sys.Platform$sysClose           // -- Begin function Sys.Platform$sysClose
	.p2align	2
	.type	Sys.Platform$sysClose,@function
Sys.Platform$sysClose:                  // @"Sys.Platform$sysClose"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #57                         // =0x39
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end14:
	.size	Sys.Platform$sysClose, .Lfunc_end14-Sys.Platform$sysClose
                                        // -- End function
	.globl	Sys.Platform$sysExit            // -- Begin function Sys.Platform$sysExit
	.p2align	2
	.type	Sys.Platform$sysExit,@function
Sys.Platform$sysExit:                   // @"Sys.Platform$sysExit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #94                         // =0x5e
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end15:
	.size	Sys.Platform$sysExit, .Lfunc_end15-Sys.Platform$sysExit
                                        // -- End function
	.globl	Sys.Platform$sysLseek           // -- Begin function Sys.Platform$sysLseek
	.p2align	2
	.type	Sys.Platform$sysLseek,@function
Sys.Platform$sysLseek:                  // @"Sys.Platform$sysLseek"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #62                         // =0x3e
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end16:
	.size	Sys.Platform$sysLseek, .Lfunc_end16-Sys.Platform$sysLseek
                                        // -- End function
	.globl	Sys.Platform$openNeedsDirFd     // -- Begin function Sys.Platform$openNeedsDirFd
	.p2align	2
	.type	Sys.Platform$openNeedsDirFd,@function
Sys.Platform$openNeedsDirFd:            // @"Sys.Platform$openNeedsDirFd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end17:
	.size	Sys.Platform$openNeedsDirFd, .Lfunc_end17-Sys.Platform$openNeedsDirFd
                                        // -- End function
	.globl	Sys.Platform$atFdCwd            // -- Begin function Sys.Platform$atFdCwd
	.p2align	2
	.type	Sys.Platform$atFdCwd,@function
Sys.Platform$atFdCwd:                   // @"Sys.Platform$atFdCwd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, #-100                       // =0xffffffffffffff9c
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end18:
	.size	Sys.Platform$atFdCwd, .Lfunc_end18-Sys.Platform$atFdCwd
                                        // -- End function
	.globl	Sys.Platform$oRdonly            // -- Begin function Sys.Platform$oRdonly
	.p2align	2
	.type	Sys.Platform$oRdonly,@function
Sys.Platform$oRdonly:                   // @"Sys.Platform$oRdonly"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end19:
	.size	Sys.Platform$oRdonly, .Lfunc_end19-Sys.Platform$oRdonly
                                        // -- End function
	.globl	Sys.Platform$oWronlyCreateTrunc // -- Begin function Sys.Platform$oWronlyCreateTrunc
	.p2align	2
	.type	Sys.Platform$oWronlyCreateTrunc,@function
Sys.Platform$oWronlyCreateTrunc:        // @"Sys.Platform$oWronlyCreateTrunc"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #577                        // =0x241
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end20:
	.size	Sys.Platform$oWronlyCreateTrunc, .Lfunc_end20-Sys.Platform$oWronlyCreateTrunc
                                        // -- End function
	.globl	Sys.Platform$oWronlyCreateAppend // -- Begin function Sys.Platform$oWronlyCreateAppend
	.p2align	2
	.type	Sys.Platform$oWronlyCreateAppend,@function
Sys.Platform$oWronlyCreateAppend:       // @"Sys.Platform$oWronlyCreateAppend"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1089                       // =0x441
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end21:
	.size	Sys.Platform$oWronlyCreateAppend, .Lfunc_end21-Sys.Platform$oWronlyCreateAppend
                                        // -- End function
	.globl	Sys.Platform$seekEnd            // -- Begin function Sys.Platform$seekEnd
	.p2align	2
	.type	Sys.Platform$seekEnd,@function
Sys.Platform$seekEnd:                   // @"Sys.Platform$seekEnd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end22:
	.size	Sys.Platform$seekEnd, .Lfunc_end22-Sys.Platform$seekEnd
                                        // -- End function
	.globl	Sys.Platform$seekSet            // -- Begin function Sys.Platform$seekSet
	.p2align	2
	.type	Sys.Platform$seekSet,@function
Sys.Platform$seekSet:                   // @"Sys.Platform$seekSet"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end23:
	.size	Sys.Platform$seekSet, .Lfunc_end23-Sys.Platform$seekSet
                                        // -- End function
	.globl	Sys.Platform$spawnUsesPosixSpawn // -- Begin function Sys.Platform$spawnUsesPosixSpawn
	.p2align	2
	.type	Sys.Platform$spawnUsesPosixSpawn,@function
Sys.Platform$spawnUsesPosixSpawn:       // @"Sys.Platform$spawnUsesPosixSpawn"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end24:
	.size	Sys.Platform$spawnUsesPosixSpawn, .Lfunc_end24-Sys.Platform$spawnUsesPosixSpawn
                                        // -- End function
	.globl	Sys.Platform$sysFork            // -- Begin function Sys.Platform$sysFork
	.p2align	2
	.type	Sys.Platform$sysFork,@function
Sys.Platform$sysFork:                   // @"Sys.Platform$sysFork"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #220                        // =0xdc
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end25:
	.size	Sys.Platform$sysFork, .Lfunc_end25-Sys.Platform$sysFork
                                        // -- End function
	.globl	Sys.Platform$sysForkArg         // -- Begin function Sys.Platform$sysForkArg
	.p2align	2
	.type	Sys.Platform$sysForkArg,@function
Sys.Platform$sysForkArg:                // @"Sys.Platform$sysForkArg"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #17                         // =0x11
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end26:
	.size	Sys.Platform$sysForkArg, .Lfunc_end26-Sys.Platform$sysForkArg
                                        // -- End function
	.globl	Sys.Platform$sysExecve          // -- Begin function Sys.Platform$sysExecve
	.p2align	2
	.type	Sys.Platform$sysExecve,@function
Sys.Platform$sysExecve:                 // @"Sys.Platform$sysExecve"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #221                        // =0xdd
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end27:
	.size	Sys.Platform$sysExecve, .Lfunc_end27-Sys.Platform$sysExecve
                                        // -- End function
	.globl	Sys.Platform$sysWait4           // -- Begin function Sys.Platform$sysWait4
	.p2align	2
	.type	Sys.Platform$sysWait4,@function
Sys.Platform$sysWait4:                  // @"Sys.Platform$sysWait4"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #260                        // =0x104
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end28:
	.size	Sys.Platform$sysWait4, .Lfunc_end28-Sys.Platform$sysWait4
                                        // -- End function
	.globl	Sys.Platform$sysPosixSpawn      // -- Begin function Sys.Platform$sysPosixSpawn
	.p2align	2
	.type	Sys.Platform$sysPosixSpawn,@function
Sys.Platform$sysPosixSpawn:             // @"Sys.Platform$sysPosixSpawn"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end29:
	.size	Sys.Platform$sysPosixSpawn, .Lfunc_end29-Sys.Platform$sysPosixSpawn
                                        // -- End function
	.globl	Sys.Platform$sysUnlinkNum       // -- Begin function Sys.Platform$sysUnlinkNum
	.p2align	2
	.type	Sys.Platform$sysUnlinkNum,@function
Sys.Platform$sysUnlinkNum:              // @"Sys.Platform$sysUnlinkNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #35                         // =0x23
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end30:
	.size	Sys.Platform$sysUnlinkNum, .Lfunc_end30-Sys.Platform$sysUnlinkNum
                                        // -- End function
	.globl	Sys.Platform$sysMkdirNum        // -- Begin function Sys.Platform$sysMkdirNum
	.p2align	2
	.type	Sys.Platform$sysMkdirNum,@function
Sys.Platform$sysMkdirNum:               // @"Sys.Platform$sysMkdirNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #34                         // =0x22
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end31:
	.size	Sys.Platform$sysMkdirNum, .Lfunc_end31-Sys.Platform$sysMkdirNum
                                        // -- End function
	.globl	Sys.Platform$sysRmdirNum        // -- Begin function Sys.Platform$sysRmdirNum
	.p2align	2
	.type	Sys.Platform$sysRmdirNum,@function
Sys.Platform$sysRmdirNum:               // @"Sys.Platform$sysRmdirNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #35                         // =0x23
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end32:
	.size	Sys.Platform$sysRmdirNum, .Lfunc_end32-Sys.Platform$sysRmdirNum
                                        // -- End function
	.globl	Sys.Platform$sysRenameNum       // -- Begin function Sys.Platform$sysRenameNum
	.p2align	2
	.type	Sys.Platform$sysRenameNum,@function
Sys.Platform$sysRenameNum:              // @"Sys.Platform$sysRenameNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #38                         // =0x26
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end33:
	.size	Sys.Platform$sysRenameNum, .Lfunc_end33-Sys.Platform$sysRenameNum
                                        // -- End function
	.globl	Sys.Platform$sysGetdentsNum     // -- Begin function Sys.Platform$sysGetdentsNum
	.p2align	2
	.type	Sys.Platform$sysGetdentsNum,@function
Sys.Platform$sysGetdentsNum:            // @"Sys.Platform$sysGetdentsNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #61                         // =0x3d
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end34:
	.size	Sys.Platform$sysGetdentsNum, .Lfunc_end34-Sys.Platform$sysGetdentsNum
                                        // -- End function
	.globl	Sys.Platform$dirReadNeedsPosition // -- Begin function Sys.Platform$dirReadNeedsPosition
	.p2align	2
	.type	Sys.Platform$dirReadNeedsPosition,@function
Sys.Platform$dirReadNeedsPosition:      // @"Sys.Platform$dirReadNeedsPosition"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end35:
	.size	Sys.Platform$dirReadNeedsPosition, .Lfunc_end35-Sys.Platform$dirReadNeedsPosition
                                        // -- End function
	.globl	Sys.Platform$direntNameOffset   // -- Begin function Sys.Platform$direntNameOffset
	.p2align	2
	.type	Sys.Platform$direntNameOffset,@function
Sys.Platform$direntNameOffset:          // @"Sys.Platform$direntNameOffset"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #19                         // =0x13
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end36:
	.size	Sys.Platform$direntNameOffset, .Lfunc_end36-Sys.Platform$direntNameOffset
                                        // -- End function
	.globl	Sys.Platform$cwdUsesFcntlPath   // -- Begin function Sys.Platform$cwdUsesFcntlPath
	.p2align	2
	.type	Sys.Platform$cwdUsesFcntlPath,@function
Sys.Platform$cwdUsesFcntlPath:          // @"Sys.Platform$cwdUsesFcntlPath"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end37:
	.size	Sys.Platform$cwdUsesFcntlPath, .Lfunc_end37-Sys.Platform$cwdUsesFcntlPath
                                        // -- End function
	.globl	Sys.Platform$sysCwdNum          // -- Begin function Sys.Platform$sysCwdNum
	.p2align	2
	.type	Sys.Platform$sysCwdNum,@function
Sys.Platform$sysCwdNum:                 // @"Sys.Platform$sysCwdNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #17                         // =0x11
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end38:
	.size	Sys.Platform$sysCwdNum, .Lfunc_end38-Sys.Platform$sysCwdNum
                                        // -- End function
	.globl	Sys.Platform$fGetPath           // -- Begin function Sys.Platform$fGetPath
	.p2align	2
	.type	Sys.Platform$fGetPath,@function
Sys.Platform$fGetPath:                  // @"Sys.Platform$fGetPath"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end39:
	.size	Sys.Platform$fGetPath, .Lfunc_end39-Sys.Platform$fGetPath
                                        // -- End function
	.globl	Sys.Platform$eExist             // -- Begin function Sys.Platform$eExist
	.p2align	2
	.type	Sys.Platform$eExist,@function
Sys.Platform$eExist:                    // @"Sys.Platform$eExist"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #17                         // =0x11
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end40:
	.size	Sys.Platform$eExist, .Lfunc_end40-Sys.Platform$eExist
                                        // -- End function
	.globl	Sys.Platform$eIsDir             // -- Begin function Sys.Platform$eIsDir
	.p2align	2
	.type	Sys.Platform$eIsDir,@function
Sys.Platform$eIsDir:                    // @"Sys.Platform$eIsDir"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #21                         // =0x15
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end41:
	.size	Sys.Platform$eIsDir, .Lfunc_end41-Sys.Platform$eIsDir
                                        // -- End function
	.globl	Sys.Platform$sysGetPidNum       // -- Begin function Sys.Platform$sysGetPidNum
	.p2align	2
	.type	Sys.Platform$sysGetPidNum,@function
Sys.Platform$sysGetPidNum:              // @"Sys.Platform$sysGetPidNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #172                        // =0xac
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end42:
	.size	Sys.Platform$sysGetPidNum, .Lfunc_end42-Sys.Platform$sysGetPidNum
                                        // -- End function
	.globl	Sys.Platform$sysClockNum        // -- Begin function Sys.Platform$sysClockNum
	.p2align	2
	.type	Sys.Platform$sysClockNum,@function
Sys.Platform$sysClockNum:               // @"Sys.Platform$sysClockNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #113                        // =0x71
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end43:
	.size	Sys.Platform$sysClockNum, .Lfunc_end43-Sys.Platform$sysClockNum
                                        // -- End function
	.globl	Sys.Platform$clockIsGettimeofday // -- Begin function Sys.Platform$clockIsGettimeofday
	.p2align	2
	.type	Sys.Platform$clockIsGettimeofday,@function
Sys.Platform$clockIsGettimeofday:       // @"Sys.Platform$clockIsGettimeofday"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end44:
	.size	Sys.Platform$clockIsGettimeofday, .Lfunc_end44-Sys.Platform$clockIsGettimeofday
                                        // -- End function
	.globl	Sys.Platform$clockHasMonotonic  // -- Begin function Sys.Platform$clockHasMonotonic
	.p2align	2
	.type	Sys.Platform$clockHasMonotonic,@function
Sys.Platform$clockHasMonotonic:         // @"Sys.Platform$clockHasMonotonic"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end45:
	.size	Sys.Platform$clockHasMonotonic, .Lfunc_end45-Sys.Platform$clockHasMonotonic
                                        // -- End function
	.globl	Sys.Platform$sysSocketNum       // -- Begin function Sys.Platform$sysSocketNum
	.p2align	2
	.type	Sys.Platform$sysSocketNum,@function
Sys.Platform$sysSocketNum:              // @"Sys.Platform$sysSocketNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #198                        // =0xc6
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end46:
	.size	Sys.Platform$sysSocketNum, .Lfunc_end46-Sys.Platform$sysSocketNum
                                        // -- End function
	.globl	Sys.Platform$sysBindNum         // -- Begin function Sys.Platform$sysBindNum
	.p2align	2
	.type	Sys.Platform$sysBindNum,@function
Sys.Platform$sysBindNum:                // @"Sys.Platform$sysBindNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #200                        // =0xc8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end47:
	.size	Sys.Platform$sysBindNum, .Lfunc_end47-Sys.Platform$sysBindNum
                                        // -- End function
	.globl	Sys.Platform$sysListenNum       // -- Begin function Sys.Platform$sysListenNum
	.p2align	2
	.type	Sys.Platform$sysListenNum,@function
Sys.Platform$sysListenNum:              // @"Sys.Platform$sysListenNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #201                        // =0xc9
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end48:
	.size	Sys.Platform$sysListenNum, .Lfunc_end48-Sys.Platform$sysListenNum
                                        // -- End function
	.globl	Sys.Platform$sysAcceptNum       // -- Begin function Sys.Platform$sysAcceptNum
	.p2align	2
	.type	Sys.Platform$sysAcceptNum,@function
Sys.Platform$sysAcceptNum:              // @"Sys.Platform$sysAcceptNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #242                        // =0xf2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end49:
	.size	Sys.Platform$sysAcceptNum, .Lfunc_end49-Sys.Platform$sysAcceptNum
                                        // -- End function
	.globl	Sys.Platform$sysConnectNum      // -- Begin function Sys.Platform$sysConnectNum
	.p2align	2
	.type	Sys.Platform$sysConnectNum,@function
Sys.Platform$sysConnectNum:             // @"Sys.Platform$sysConnectNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #203                        // =0xcb
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end50:
	.size	Sys.Platform$sysConnectNum, .Lfunc_end50-Sys.Platform$sysConnectNum
                                        // -- End function
	.globl	Sys.Platform$sysSetSockOptNum   // -- Begin function Sys.Platform$sysSetSockOptNum
	.p2align	2
	.type	Sys.Platform$sysSetSockOptNum,@function
Sys.Platform$sysSetSockOptNum:          // @"Sys.Platform$sysSetSockOptNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #208                        // =0xd0
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end51:
	.size	Sys.Platform$sysSetSockOptNum, .Lfunc_end51-Sys.Platform$sysSetSockOptNum
                                        // -- End function
	.globl	Sys.Platform$sysGetSockOptNum   // -- Begin function Sys.Platform$sysGetSockOptNum
	.p2align	2
	.type	Sys.Platform$sysGetSockOptNum,@function
Sys.Platform$sysGetSockOptNum:          // @"Sys.Platform$sysGetSockOptNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #209                        // =0xd1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end52:
	.size	Sys.Platform$sysGetSockOptNum, .Lfunc_end52-Sys.Platform$sysGetSockOptNum
                                        // -- End function
	.globl	Sys.Platform$sysShutdownNum     // -- Begin function Sys.Platform$sysShutdownNum
	.p2align	2
	.type	Sys.Platform$sysShutdownNum,@function
Sys.Platform$sysShutdownNum:            // @"Sys.Platform$sysShutdownNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #210                        // =0xd2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end53:
	.size	Sys.Platform$sysShutdownNum, .Lfunc_end53-Sys.Platform$sysShutdownNum
                                        // -- End function
	.globl	Sys.Platform$sysFcntlNum        // -- Begin function Sys.Platform$sysFcntlNum
	.p2align	2
	.type	Sys.Platform$sysFcntlNum,@function
Sys.Platform$sysFcntlNum:               // @"Sys.Platform$sysFcntlNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #25                         // =0x19
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end54:
	.size	Sys.Platform$sysFcntlNum, .Lfunc_end54-Sys.Platform$sysFcntlNum
                                        // -- End function
	.globl	Sys.Platform$afInet             // -- Begin function Sys.Platform$afInet
	.p2align	2
	.type	Sys.Platform$afInet,@function
Sys.Platform$afInet:                    // @"Sys.Platform$afInet"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end55:
	.size	Sys.Platform$afInet, .Lfunc_end55-Sys.Platform$afInet
                                        // -- End function
	.globl	Sys.Platform$afInet6            // -- Begin function Sys.Platform$afInet6
	.p2align	2
	.type	Sys.Platform$afInet6,@function
Sys.Platform$afInet6:                   // @"Sys.Platform$afInet6"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #10                         // =0xa
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end56:
	.size	Sys.Platform$afInet6, .Lfunc_end56-Sys.Platform$afInet6
                                        // -- End function
	.globl	Sys.Platform$sockStream         // -- Begin function Sys.Platform$sockStream
	.p2align	2
	.type	Sys.Platform$sockStream,@function
Sys.Platform$sockStream:                // @"Sys.Platform$sockStream"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end57:
	.size	Sys.Platform$sockStream, .Lfunc_end57-Sys.Platform$sockStream
                                        // -- End function
	.globl	Sys.Platform$solSocket          // -- Begin function Sys.Platform$solSocket
	.p2align	2
	.type	Sys.Platform$solSocket,@function
Sys.Platform$solSocket:                 // @"Sys.Platform$solSocket"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end58:
	.size	Sys.Platform$solSocket, .Lfunc_end58-Sys.Platform$solSocket
                                        // -- End function
	.globl	Sys.Platform$soReuseAddr        // -- Begin function Sys.Platform$soReuseAddr
	.p2align	2
	.type	Sys.Platform$soReuseAddr,@function
Sys.Platform$soReuseAddr:               // @"Sys.Platform$soReuseAddr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end59:
	.size	Sys.Platform$soReuseAddr, .Lfunc_end59-Sys.Platform$soReuseAddr
                                        // -- End function
	.globl	Sys.Platform$soReusePort        // -- Begin function Sys.Platform$soReusePort
	.p2align	2
	.type	Sys.Platform$soReusePort,@function
Sys.Platform$soReusePort:               // @"Sys.Platform$soReusePort"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #15                         // =0xf
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end60:
	.size	Sys.Platform$soReusePort, .Lfunc_end60-Sys.Platform$soReusePort
                                        // -- End function
	.globl	Sys.Platform$soError            // -- Begin function Sys.Platform$soError
	.p2align	2
	.type	Sys.Platform$soError,@function
Sys.Platform$soError:                   // @"Sys.Platform$soError"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #4                          // =0x4
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end61:
	.size	Sys.Platform$soError, .Lfunc_end61-Sys.Platform$soError
                                        // -- End function
	.globl	Sys.Platform$fGetFl             // -- Begin function Sys.Platform$fGetFl
	.p2align	2
	.type	Sys.Platform$fGetFl,@function
Sys.Platform$fGetFl:                    // @"Sys.Platform$fGetFl"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #3                          // =0x3
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end62:
	.size	Sys.Platform$fGetFl, .Lfunc_end62-Sys.Platform$fGetFl
                                        // -- End function
	.globl	Sys.Platform$fSetFl             // -- Begin function Sys.Platform$fSetFl
	.p2align	2
	.type	Sys.Platform$fSetFl,@function
Sys.Platform$fSetFl:                    // @"Sys.Platform$fSetFl"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #4                          // =0x4
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end63:
	.size	Sys.Platform$fSetFl, .Lfunc_end63-Sys.Platform$fSetFl
                                        // -- End function
	.globl	Sys.Platform$oNonblock          // -- Begin function Sys.Platform$oNonblock
	.p2align	2
	.type	Sys.Platform$oNonblock,@function
Sys.Platform$oNonblock:                 // @"Sys.Platform$oNonblock"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2048                       // =0x800
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end64:
	.size	Sys.Platform$oNonblock, .Lfunc_end64-Sys.Platform$oNonblock
                                        // -- End function
	.globl	Sys.Platform$eAgain             // -- Begin function Sys.Platform$eAgain
	.p2align	2
	.type	Sys.Platform$eAgain,@function
Sys.Platform$eAgain:                    // @"Sys.Platform$eAgain"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #11                         // =0xb
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end65:
	.size	Sys.Platform$eAgain, .Lfunc_end65-Sys.Platform$eAgain
                                        // -- End function
	.globl	Sys.Platform$sockaddrHasLenByte // -- Begin function Sys.Platform$sockaddrHasLenByte
	.p2align	2
	.type	Sys.Platform$sockaddrHasLenByte,@function
Sys.Platform$sockaddrHasLenByte:        // @"Sys.Platform$sockaddrHasLenByte"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end66:
	.size	Sys.Platform$sockaddrHasLenByte, .Lfunc_end66-Sys.Platform$sockaddrHasLenByte
                                        // -- End function
	.globl	Sys.Platform$pollUsesKqueue     // -- Begin function Sys.Platform$pollUsesKqueue
	.p2align	2
	.type	Sys.Platform$pollUsesKqueue,@function
Sys.Platform$pollUsesKqueue:            // @"Sys.Platform$pollUsesKqueue"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end67:
	.size	Sys.Platform$pollUsesKqueue, .Lfunc_end67-Sys.Platform$pollUsesKqueue
                                        // -- End function
	.globl	Sys.Platform$sysPollCreateNum   // -- Begin function Sys.Platform$sysPollCreateNum
	.p2align	2
	.type	Sys.Platform$sysPollCreateNum,@function
Sys.Platform$sysPollCreateNum:          // @"Sys.Platform$sysPollCreateNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #20                         // =0x14
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end68:
	.size	Sys.Platform$sysPollCreateNum, .Lfunc_end68-Sys.Platform$sysPollCreateNum
                                        // -- End function
	.globl	Sys.Platform$sysPollWaitNum     // -- Begin function Sys.Platform$sysPollWaitNum
	.p2align	2
	.type	Sys.Platform$sysPollWaitNum,@function
Sys.Platform$sysPollWaitNum:            // @"Sys.Platform$sysPollWaitNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #22                         // =0x16
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end69:
	.size	Sys.Platform$sysPollWaitNum, .Lfunc_end69-Sys.Platform$sysPollWaitNum
                                        // -- End function
	.globl	Sys.Platform$sysPollCtlNum      // -- Begin function Sys.Platform$sysPollCtlNum
	.p2align	2
	.type	Sys.Platform$sysPollCtlNum,@function
Sys.Platform$sysPollCtlNum:             // @"Sys.Platform$sysPollCtlNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #21                         // =0x15
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end70:
	.size	Sys.Platform$sysPollCtlNum, .Lfunc_end70-Sys.Platform$sysPollCtlNum
                                        // -- End function
	.globl	Sys.Platform$pollEventSize      // -- Begin function Sys.Platform$pollEventSize
	.p2align	2
	.type	Sys.Platform$pollEventSize,@function
Sys.Platform$pollEventSize:             // @"Sys.Platform$pollEventSize"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #16                         // =0x10
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end71:
	.size	Sys.Platform$pollEventSize, .Lfunc_end71-Sys.Platform$pollEventSize
                                        // -- End function
	.globl	Sys.Platform$pollEventFdOffset  // -- Begin function Sys.Platform$pollEventFdOffset
	.p2align	2
	.type	Sys.Platform$pollEventFdOffset,@function
Sys.Platform$pollEventFdOffset:         // @"Sys.Platform$pollEventFdOffset"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #8                          // =0x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end72:
	.size	Sys.Platform$pollEventFdOffset, .Lfunc_end72-Sys.Platform$pollEventFdOffset
                                        // -- End function
	.globl	Sys.Platform$pollReadFilter     // -- Begin function Sys.Platform$pollReadFilter
	.p2align	2
	.type	Sys.Platform$pollReadFilter,@function
Sys.Platform$pollReadFilter:            // @"Sys.Platform$pollReadFilter"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end73:
	.size	Sys.Platform$pollReadFilter, .Lfunc_end73-Sys.Platform$pollReadFilter
                                        // -- End function
	.globl	Sys.Platform$pollAddOp          // -- Begin function Sys.Platform$pollAddOp
	.p2align	2
	.type	Sys.Platform$pollAddOp,@function
Sys.Platform$pollAddOp:                 // @"Sys.Platform$pollAddOp"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end74:
	.size	Sys.Platform$pollAddOp, .Lfunc_end74-Sys.Platform$pollAddOp
                                        // -- End function
	.globl	Sys.Platform$pollDelOp          // -- Begin function Sys.Platform$pollDelOp
	.p2align	2
	.type	Sys.Platform$pollDelOp,@function
Sys.Platform$pollDelOp:                 // @"Sys.Platform$pollDelOp"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end75:
	.size	Sys.Platform$pollDelOp, .Lfunc_end75-Sys.Platform$pollDelOp
                                        // -- End function
	.globl	Sys.Platform$pollSigsetSize     // -- Begin function Sys.Platform$pollSigsetSize
	.p2align	2
	.type	Sys.Platform$pollSigsetSize,@function
Sys.Platform$pollSigsetSize:            // @"Sys.Platform$pollSigsetSize"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #8                          // =0x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end76:
	.size	Sys.Platform$pollSigsetSize, .Lfunc_end76-Sys.Platform$pollSigsetSize
                                        // -- End function
	.globl	Sys.Platform$sysRandomNum       // -- Begin function Sys.Platform$sysRandomNum
	.p2align	2
	.type	Sys.Platform$sysRandomNum,@function
Sys.Platform$sysRandomNum:              // @"Sys.Platform$sysRandomNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #278                        // =0x116
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end77:
	.size	Sys.Platform$sysRandomNum, .Lfunc_end77-Sys.Platform$sysRandomNum
                                        // -- End function
	.globl	Sys.Platform$randomIsGetentropy // -- Begin function Sys.Platform$randomIsGetentropy
	.p2align	2
	.type	Sys.Platform$randomIsGetentropy,@function
Sys.Platform$randomIsGetentropy:        // @"Sys.Platform$randomIsGetentropy"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end78:
	.size	Sys.Platform$randomIsGetentropy, .Lfunc_end78-Sys.Platform$randomIsGetentropy
                                        // -- End function
	.globl	Sys.Platform$randomMaxChunk     // -- Begin function Sys.Platform$randomMaxChunk
	.p2align	2
	.type	Sys.Platform$randomMaxChunk,@function
Sys.Platform$randomMaxChunk:            // @"Sys.Platform$randomMaxChunk"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #256                        // =0x100
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end79:
	.size	Sys.Platform$randomMaxChunk, .Lfunc_end79-Sys.Platform$randomMaxChunk
                                        // -- End function
	.globl	Sys.Platform$signalUsesSignalFd // -- Begin function Sys.Platform$signalUsesSignalFd
	.p2align	2
	.type	Sys.Platform$signalUsesSignalFd,@function
Sys.Platform$signalUsesSignalFd:        // @"Sys.Platform$signalUsesSignalFd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end80:
	.size	Sys.Platform$signalUsesSignalFd, .Lfunc_end80-Sys.Platform$signalUsesSignalFd
                                        // -- End function
	.globl	Sys.Platform$sysSigProcMaskNum  // -- Begin function Sys.Platform$sysSigProcMaskNum
	.p2align	2
	.type	Sys.Platform$sysSigProcMaskNum,@function
Sys.Platform$sysSigProcMaskNum:         // @"Sys.Platform$sysSigProcMaskNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #135                        // =0x87
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end81:
	.size	Sys.Platform$sysSigProcMaskNum, .Lfunc_end81-Sys.Platform$sysSigProcMaskNum
                                        // -- End function
	.globl	Sys.Platform$sigBlockHow        // -- Begin function Sys.Platform$sigBlockHow
	.p2align	2
	.type	Sys.Platform$sigBlockHow,@function
Sys.Platform$sigBlockHow:               // @"Sys.Platform$sigBlockHow"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end82:
	.size	Sys.Platform$sigBlockHow, .Lfunc_end82-Sys.Platform$sigBlockHow
                                        // -- End function
	.globl	Sys.Platform$sigsetBytes        // -- Begin function Sys.Platform$sigsetBytes
	.p2align	2
	.type	Sys.Platform$sigsetBytes,@function
Sys.Platform$sigsetBytes:               // @"Sys.Platform$sigsetBytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #8                          // =0x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end83:
	.size	Sys.Platform$sigsetBytes, .Lfunc_end83-Sys.Platform$sigsetBytes
                                        // -- End function
	.globl	Sys.Platform$sysSignalFdNum     // -- Begin function Sys.Platform$sysSignalFdNum
	.p2align	2
	.type	Sys.Platform$sysSignalFdNum,@function
Sys.Platform$sysSignalFdNum:            // @"Sys.Platform$sysSignalFdNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #74                         // =0x4a
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end84:
	.size	Sys.Platform$sysSignalFdNum, .Lfunc_end84-Sys.Platform$sysSignalFdNum
                                        // -- End function
	.globl	Sys.Platform$sigInfoSize        // -- Begin function Sys.Platform$sigInfoSize
	.p2align	2
	.type	Sys.Platform$sigInfoSize,@function
Sys.Platform$sigInfoSize:               // @"Sys.Platform$sigInfoSize"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #128                        // =0x80
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end85:
	.size	Sys.Platform$sigInfoSize, .Lfunc_end85-Sys.Platform$sigInfoSize
                                        // -- End function
	.globl	Sys.Platform$pollSignalFilter   // -- Begin function Sys.Platform$pollSignalFilter
	.p2align	2
	.type	Sys.Platform$pollSignalFilter,@function
Sys.Platform$pollSignalFilter:          // @"Sys.Platform$pollSignalFilter"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end86:
	.size	Sys.Platform$pollSignalFilter, .Lfunc_end86-Sys.Platform$pollSignalFilter
                                        // -- End function
	.globl	Sys.Platform$sysKillNum         // -- Begin function Sys.Platform$sysKillNum
	.p2align	2
	.type	Sys.Platform$sysKillNum,@function
Sys.Platform$sysKillNum:                // @"Sys.Platform$sysKillNum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #129                        // =0x81
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end87:
	.size	Sys.Platform$sysKillNum, .Lfunc_end87-Sys.Platform$sysKillNum
                                        // -- End function
	.globl	Sys.Platform$sigTerm            // -- Begin function Sys.Platform$sigTerm
	.p2align	2
	.type	Sys.Platform$sigTerm,@function
Sys.Platform$sigTerm:                   // @"Sys.Platform$sigTerm"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #15                         // =0xf
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end88:
	.size	Sys.Platform$sigTerm, .Lfunc_end88-Sys.Platform$sigTerm
                                        // -- End function
	.globl	Sys.Platform$sigInt             // -- Begin function Sys.Platform$sigInt
	.p2align	2
	.type	Sys.Platform$sigInt,@function
Sys.Platform$sigInt:                    // @"Sys.Platform$sigInt"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end89:
	.size	Sys.Platform$sigInt, .Lfunc_end89-Sys.Platform$sigInt
                                        // -- End function
	.globl	Sys.Platform$forkChildIsZero    // -- Begin function Sys.Platform$forkChildIsZero
	.p2align	2
	.type	Sys.Platform$forkChildIsZero,@function
Sys.Platform$forkChildIsZero:           // @"Sys.Platform$forkChildIsZero"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end90:
	.size	Sys.Platform$forkChildIsZero, .Lfunc_end90-Sys.Platform$forkChildIsZero
                                        // -- End function
	.globl	Sys.Platform$acceptNonblockFlag // -- Begin function Sys.Platform$acceptNonblockFlag
	.p2align	2
	.type	Sys.Platform$acceptNonblockFlag,@function
Sys.Platform$acceptNonblockFlag:        // @"Sys.Platform$acceptNonblockFlag"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2048                       // =0x800
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end91:
	.size	Sys.Platform$acceptNonblockFlag, .Lfunc_end91-Sys.Platform$acceptNonblockFlag
                                        // -- End function
	.globl	Mem$memAlloc                    // -- Begin function Mem$memAlloc
	.p2align	2
	.type	Mem$memAlloc,@function
Mem$memAlloc:                           // @"Mem$memAlloc"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	axiom_alloc
.Lfunc_end92:
	.size	Mem$memAlloc, .Lfunc_end92-Mem$memAlloc
                                        // -- End function
	.globl	Mem$memAllocMapped              // -- Begin function Mem$memAllocMapped
	.p2align	2
	.type	Mem$memAllocMapped,@function
Mem$memAllocMapped:                     // @"Mem$memAllocMapped"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	mov	x19, x1
	mov	x20, x0
	bl	axiom_alloc
	cbz	x20, .LBB93_2
// %bb.1:                               // %label_5
	ldur	x8, [x0, #-8]
	mov	w10, #47                        // =0x2f
	ubfx	x9, x8, #1, #14
	cmp	x9, #47
	csel	x9, x9, x10, lo
	mov	x10, #-1                        // =0xffffffffffffffff
	lsl	x9, x10, x9
	bic	x9, x19, x9
	orr	x8, x8, x9, lsl #16
	stur	x8, [x0, #-8]
.LBB93_2:                               // %label_6
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end93:
	.size	Mem$memAllocMapped, .Lfunc_end93-Mem$memAllocMapped
                                        // -- End function
	.globl	Mem$memMarkArray                // -- Begin function Mem$memMarkArray
	.p2align	2
	.type	Mem$memMarkArray,@function
Mem$memMarkArray:                       // @"Mem$memMarkArray"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldur	x8, [x0, #-8]
	mov	x29, sp
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end94:
	.size	Mem$memMarkArray, .Lfunc_end94-Mem$memMarkArray
                                        // -- End function
	.globl	Mem$memMarkLeaf                 // -- Begin function Mem$memMarkLeaf
	.p2align	2
	.type	Mem$memMarkLeaf,@function
Mem$memMarkLeaf:                        // @"Mem$memMarkLeaf"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldur	x8, [x0, #-8]
	mov	x29, sp
	and	x8, x8, #0xffffffffffff7fff
	stur	x8, [x0, #-8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end95:
	.size	Mem$memMarkLeaf, .Lfunc_end95-Mem$memMarkLeaf
                                        // -- End function
	.globl	Mem$memCopy                     // -- Begin function Mem$memCopy
	.p2align	2
	.type	Mem$memCopy,@function
Mem$memCopy:                            // @"Mem$memCopy"
// %bb.0:
	cmp	x2, #1
	b.lt	.LBB96_4
// %bb.1:                               // %label_2.lr.ph.i
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x8, x0
	mov	x29, sp
.LBB96_2:                               // %label_2.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w9, [x1], #1
	subs	x2, x2, #1
	strb	w9, [x8], #1
	b.ne	.LBB96_2
// %bb.3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB96_4:                               // %"Mem$memCopyFrom.exit"
	ret
.Lfunc_end96:
	.size	Mem$memCopy, .Lfunc_end96-Mem$memCopy
                                        // -- End function
	.globl	Mem$memCopyFrom                 // -- Begin function Mem$memCopyFrom
	.p2align	2
	.type	Mem$memCopyFrom,@function
Mem$memCopyFrom:                        // @"Mem$memCopyFrom"
// %bb.0:
	subs	x8, x2, x3
	b.le	.LBB97_4
// %bb.1:                               // %label_2.lr.ph
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x9, x0, x3
	add	x10, x1, x3
	mov	x29, sp
.LBB97_2:                               // %label_2
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x10], #1
	subs	x8, x8, #1
	strb	w11, [x9], #1
	b.ne	.LBB97_2
// %bb.3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB97_4:                               // %label_3
	ret
.Lfunc_end97:
	.size	Mem$memCopyFrom, .Lfunc_end97-Mem$memCopyFrom
                                        // -- End function
	.globl	Mem$memSet                      // -- Begin function Mem$memSet
	.p2align	2
	.type	Mem$memSet,@function
Mem$memSet:                             // @"Mem$memSet"
// %bb.0:
	cmp	x2, #1
	b.lt	.LBB98_4
// %bb.1:                               // %label_2.lr.ph.i
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x8, x0
	mov	x29, sp
.LBB98_2:                               // %label_2.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x2, x2, #1
	strb	w1, [x8], #1
	b.ne	.LBB98_2
// %bb.3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB98_4:                               // %"Mem$memSetFrom.exit"
	ret
.Lfunc_end98:
	.size	Mem$memSet, .Lfunc_end98-Mem$memSet
                                        // -- End function
	.globl	Mem$memSetFrom                  // -- Begin function Mem$memSetFrom
	.p2align	2
	.type	Mem$memSetFrom,@function
Mem$memSetFrom:                         // @"Mem$memSetFrom"
// %bb.0:
	subs	x8, x2, x3
	b.le	.LBB99_4
// %bb.1:                               // %label_2.lr.ph
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x9, x0, x3
	mov	x29, sp
.LBB99_2:                               // %label_2
                                        // =>This Inner Loop Header: Depth=1
	subs	x8, x8, #1
	strb	w1, [x9], #1
	b.ne	.LBB99_2
// %bb.3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB99_4:                               // %label_3
	ret
.Lfunc_end99:
	.size	Mem$memSetFrom, .Lfunc_end99-Mem$memSetFrom
                                        // -- End function
	.globl	Mem$memCmp                      // -- Begin function Mem$memCmp
	.p2align	2
	.type	Mem$memCmp,@function
Mem$memCmp:                             // @"Mem$memCmp"
// %bb.0:
	cmp	x2, #1
	b.lt	.LBB100_5
// %bb.1:                               // %label_3.lr.ph.i
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, xzr
	mov	x29, sp
.LBB100_2:                              // %label_3.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x0, x9]
	ldrb	w10, [x1, x9]
	add	x9, x9, #1
	cmp	x9, x2
	sub	x8, x8, x10
	b.ge	.LBB100_4
// %bb.3:                               // %label_3.i
                                        //   in Loop: Header=BB100_2 Depth=1
	cbz	x8, .LBB100_2
.LBB100_4:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	mov	x0, x8
	ret
.LBB100_5:
	mov	x0, xzr
	ret
.Lfunc_end100:
	.size	Mem$memCmp, .Lfunc_end100-Mem$memCmp
                                        // -- End function
	.globl	Mem$memCmpFrom                  // -- Begin function Mem$memCmpFrom
	.p2align	2
	.type	Mem$memCmpFrom,@function
Mem$memCmpFrom:                         // @"Mem$memCmpFrom"
// %bb.0:
	cmp	x3, x2
	b.ge	.LBB101_5
// %bb.1:                               // %label_3.lr.ph
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
.LBB101_2:                              // %label_3
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x0, x3]
	ldrb	w9, [x1, x3]
	add	x3, x3, #1
	cmp	x3, x2
	sub	x8, x8, x9
	b.ge	.LBB101_4
// %bb.3:                               // %label_3
                                        //   in Loop: Header=BB101_2 Depth=1
	cbz	x8, .LBB101_2
.LBB101_4:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	mov	x0, x8
	ret
.LBB101_5:
	mov	x0, xzr
	ret
.Lfunc_end101:
	.size	Mem$memCmpFrom, .Lfunc_end101-Mem$memCmpFrom
                                        // -- End function
	.globl	Mem$memGetWord                  // -- Begin function Mem$memGetWord
	.p2align	2
	.type	Mem$memGetWord,@function
Mem$memGetWord:                         // @"Mem$memGetWord"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, x1, lsl #3]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end102:
	.size	Mem$memGetWord, .Lfunc_end102-Mem$memGetWord
                                        // -- End function
	.globl	Mem$memGetWordStr               // -- Begin function Mem$memGetWordStr
	.p2align	2
	.type	Mem$memGetWordStr,@function
Mem$memGetWordStr:                      // @"Mem$memGetWordStr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, x1, lsl #3]
	mov	x29, sp
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB103_3
// %bb.1:                               // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB103_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB103_3:                              // %axiom_retain.exit
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end103:
	.size	Mem$memGetWordStr, .Lfunc_end103-Mem$memGetWordStr
                                        // -- End function
	.globl	Mem$memSetWord                  // -- Begin function Mem$memSetWord
	.p2align	2
	.type	Mem$memSetWord,@function
Mem$memSetWord:                         // @"Mem$memSetWord"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	tbz	w3, #0, .LBB104_4
// %bb.1:
	cmp	x2, #1, lsl #12                 // =4096
	b.lt	.LBB104_4
// %bb.2:                               // %chk.i
	ldur	x8, [x2, #-16]
	cmn	x8, #1
	b.eq	.LBB104_4
// %bb.3:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x2, #-16]
.LBB104_4:                              // %label_4
	str	x2, [x0, x1, lsl #3]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end104:
	.size	Mem$memSetWord, .Lfunc_end104-Mem$memSetWord
                                        // -- End function
	.globl	Mem$memGetByte                  // -- Begin function Mem$memGetByte
	.p2align	2
	.type	Mem$memGetByte,@function
Mem$memGetByte:                         // @"Mem$memGetByte"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrb	w0, [x0, x1]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end105:
	.size	Mem$memGetByte, .Lfunc_end105-Mem$memGetByte
                                        // -- End function
	.globl	Mem$memPutByte                  // -- Begin function Mem$memPutByte
	.p2align	2
	.type	Mem$memPutByte,@function
Mem$memPutByte:                         // @"Mem$memPutByte"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	strb	w2, [x0, x1]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end106:
	.size	Mem$memPutByte, .Lfunc_end106-Mem$memPutByte
                                        // -- End function
	.globl	Vec$vecDefaultCap               // -- Begin function Vec$vecDefaultCap
	.p2align	2
	.type	Vec$vecDefaultCap,@function
Vec$vecDefaultCap:                      // @"Vec$vecDefaultCap"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #8                          // =0x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end107:
	.size	Vec$vecDefaultCap, .Lfunc_end107-Vec$vecDefaultCap
                                        // -- End function
	.globl	Vec$vecNew                      // -- Begin function Vec$vecNew
	.p2align	2
	.type	Vec$vecNew,@function
Vec$vecNew:                             // @"Vec$vecNew"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	mov	w0, #32                         // =0x20
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x19, x0
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x0, #-8]
	mov	w0, #64                         // =0x40
	bl	axiom_alloc
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB108_3
// %bb.1:                               // %chk.i.i.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB108_3
// %bb.2:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB108_3:                              // %axiom_retain.exit.i.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB108_6
// %bb.4:                               // %chk.i3.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB108_6
// %bb.5:                               // %bump.i8.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB108_6:                              // %"Vec$vecWithCapacity.exit"
	mov	w8, #8                          // =0x8
	stp	x0, xzr, [x19, #16]
	mov	x0, x19
	stp	xzr, x8, [x19]
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end108:
	.size	Vec$vecNew, .Lfunc_end108-Vec$vecNew
                                        // -- End function
	.globl	Vec$vecWithCapacity             // -- Begin function Vec$vecWithCapacity
	.p2align	2
	.type	Vec$vecWithCapacity,@function
Vec$vecWithCapacity:                    // @"Vec$vecWithCapacity"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	cmp	x0, #1
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	csinc	x20, x0, xzr, gt
	mov	w0, #32                         // =0x20
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x19, x0
	lsl	x0, x20, #3
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x19, #-8]
	bl	axiom_alloc
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB109_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB109_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB109_3:                              // %axiom_retain.exit.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB109_6
// %bb.4:                               // %chk.i3.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB109_6
// %bb.5:                               // %bump.i8.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB109_6:                              // %"Vec$vecBuild.exit"
	stp	xzr, x20, [x19]
	stp	x0, xzr, [x19, #16]
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end109:
	.size	Vec$vecWithCapacity, .Lfunc_end109-Vec$vecWithCapacity
                                        // -- End function
	.globl	Vec$vecWithCapacityRef          // -- Begin function Vec$vecWithCapacityRef
	.p2align	2
	.type	Vec$vecWithCapacityRef,@function
Vec$vecWithCapacityRef:                 // @"Vec$vecWithCapacityRef"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	cmp	x0, #1
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	csinc	x20, x0, xzr, gt
	mov	w0, #32                         // =0x20
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x19, x0
	lsl	x0, x20, #3
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x19, #-8]
	bl	axiom_alloc
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB110_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB110_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB110_3:                              // %axiom_retain.exit.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB110_6
// %bb.4:                               // %chk.i3.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB110_6
// %bb.5:                               // %bump.i8.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB110_6:                              // %"Vec$vecBuild.exit"
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
	mov	w8, #1                          // =0x1
	stp	xzr, x20, [x19]
	stp	x0, x8, [x19, #16]
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end110:
	.size	Vec$vecWithCapacityRef, .Lfunc_end110-Vec$vecWithCapacityRef
                                        // -- End function
	.globl	Vec$vecNewRef                   // -- Begin function Vec$vecNewRef
	.p2align	2
	.type	Vec$vecNewRef,@function
Vec$vecNewRef:                          // @"Vec$vecNewRef"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	mov	w0, #32                         // =0x20
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x19, x0
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x0, #-8]
	mov	w0, #64                         // =0x40
	bl	axiom_alloc
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB111_3
// %bb.1:                               // %chk.i.i.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB111_3
// %bb.2:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB111_3:                              // %axiom_retain.exit.i.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB111_6
// %bb.4:                               // %chk.i3.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB111_6
// %bb.5:                               // %bump.i8.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB111_6:                              // %"Vec$vecWithCapacityRef.exit"
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
	mov	w8, #8                          // =0x8
	stp	xzr, x8, [x19]
	mov	w8, #1                          // =0x1
	stp	x0, x8, [x19, #16]
	mov	x0, x19
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end111:
	.size	Vec$vecNewRef, .Lfunc_end111-Vec$vecNewRef
                                        // -- End function
	.globl	Vec$vecBuild                    // -- Begin function Vec$vecBuild
	.p2align	2
	.type	Vec$vecBuild,@function
Vec$vecBuild:                           // @"Vec$vecBuild"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	cmp	x0, #1
	str	x21, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	csinc	x21, x0, xzr, gt
	mov	w0, #32                         // =0x20
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x1
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x20, x0
	lsl	x0, x21, #3
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x20, #-8]
	bl	axiom_alloc
	cmp	x20, #1, lsl #12                // =4096
	b.lt	.LBB112_3
// %bb.1:                               // %chk.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB112_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB112_3:                              // %axiom_retain.exit
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB112_6
// %bb.4:                               // %chk.i3
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB112_6
// %bb.5:                               // %bump.i8
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB112_6:                              // %axiom_retain.exit10
	cmp	x19, #1
	b.ne	.LBB112_8
// %bb.7:                               // %label_13
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
.LBB112_8:                              // %label_15
	stp	xzr, x21, [x20]
	ldr	x21, [sp, #16]                  // 8-byte Reload
	stp	x0, x19, [x20, #16]
	mov	x0, x20
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end112:
	.size	Vec$vecBuild, .Lfunc_end112-Vec$vecBuild
                                        // -- End function
	.globl	Vec$vecFree                     // -- Begin function Vec$vecFree
	.p2align	2
	.type	Vec$vecFree,@function
Vec$vecFree:                            // @"Vec$vecFree"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	axiom_release
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end113:
	.size	Vec$vecFree, .Lfunc_end113-Vec$vecFree
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecOwnsRefs                 // -- Begin function Vec$vecOwnsRefs
	.p2align	2
	.type	Vec$vecOwnsRefs,@function
Vec$vecOwnsRefs:                        // @"Vec$vecOwnsRefs"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0, #24]
	mov	x29, sp
	cmp	x8, #1
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end114:
	.size	Vec$vecOwnsRefs, .Lfunc_end114-Vec$vecOwnsRefs
                                        // -- End function
	.globl	Vec$vecLen                      // -- Begin function Vec$vecLen
	.p2align	2
	.type	Vec$vecLen,@function
Vec$vecLen:                             // @"Vec$vecLen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end115:
	.size	Vec$vecLen, .Lfunc_end115-Vec$vecLen
                                        // -- End function
	.globl	Vec$vecCap                      // -- Begin function Vec$vecCap
	.p2align	2
	.type	Vec$vecCap,@function
Vec$vecCap:                             // @"Vec$vecCap"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, #8]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end116:
	.size	Vec$vecCap, .Lfunc_end116-Vec$vecCap
                                        // -- End function
	.globl	Vec$vecData                     // -- Begin function Vec$vecData
	.p2align	2
	.type	Vec$vecData,@function
Vec$vecData:                            // @"Vec$vecData"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, #16]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end117:
	.size	Vec$vecData, .Lfunc_end117-Vec$vecData
                                        // -- End function
	.globl	Vec$vecGet                      // -- Begin function Vec$vecGet
	.p2align	2
	.type	Vec$vecGet,@function
Vec$vecGet:                             // @"Vec$vecGet"
// %bb.0:
	tbnz	x1, #63, .LBB118_3
// %bb.1:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x1, x8
	b.ge	.LBB118_4
// %bb.2:                               // %label_11
	ldr	x8, [x0, #16]
	ldr	x0, [x8, x1, lsl #3]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB118_3:
	mov	x0, xzr
	ret
.LBB118_4:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end118:
	.size	Vec$vecGet, .Lfunc_end118-Vec$vecGet
                                        // -- End function
	.globl	Vec$vecTry                      // -- Begin function Vec$vecTry
	.p2align	2
	.type	Vec$vecTry,@function
Vec$vecTry:                             // @"Vec$vecTry"
// %bb.0:
	tbnz	x1, #63, .LBB119_3
// %bb.1:                               // %label_4
	ldr	x8, [x0]
	cmp	x1, x8
	b.ge	.LBB119_3
// %bb.2:                               // %label_11
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x19, x0
	mov	w0, #16                         // =0x10
	mov	x29, sp
	mov	x20, x1
	bl	axiom_alloc
	mov	w8, #4                          // =0x4
	mov	w9, #1                          // =0x1
	stp	x8, xzr, [x0, #-8]
	stur	x9, [x0, #-16]
	ldr	x8, [x19, #16]
	ldr	x8, [x8, x20, lsl #3]
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	str	x8, [x0, #8]
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.LBB119_3:
	mov	w0, #1                          // =0x1
	ret
.Lfunc_end119:
	.size	Vec$vecTry, .Lfunc_end119-Vec$vecTry
                                        // -- End function
	.globl	Vec$vecGetStr                   // -- Begin function Vec$vecGetStr
	.p2align	2
	.type	Vec$vecGetStr,@function
Vec$vecGetStr:                          // @"Vec$vecGetStr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	tbnz	x1, #63, .LBB120_3
// %bb.1:                               // %label_4.i
	ldr	x8, [x0]
	cmp	x1, x8
	b.ge	.LBB120_3
// %bb.2:                               // %label_11.i
	ldr	x8, [x0, #16]
	ldr	x0, [x8, x1, lsl #3]
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB120_6
	b	.LBB120_4
.LBB120_3:
	mov	x0, xzr
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB120_6
.LBB120_4:                              // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB120_6
// %bb.5:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB120_6:                              // %axiom_retain.exit
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end120:
	.size	Vec$vecGetStr, .Lfunc_end120-Vec$vecGetStr
                                        // -- End function
	.globl	Vec$vecSet                      // -- Begin function Vec$vecSet
	.p2align	2
	.type	Vec$vecSet,@function
Vec$vecSet:                             // @"Vec$vecSet"
	.cfi_startproc
// %bb.0:
	tbnz	x1, #63, .LBB121_9
// %bb.1:                               // %label_4
	ldr	x8, [x0]
	cmp	x1, x8
	b.ge	.LBB121_9
// %bb.2:                               // %label_11
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	ldr	x8, [x0, #24]
	cmp	x8, #1
	b.ne	.LBB121_4
// %bb.3:                               // %label_15
	ldr	x9, [x0, #16]
	mov	x19, x0
	mov	x21, x2
	mov	x22, x1
	mov	x20, x3
	ldr	x8, [x9, x1, lsl #3]
	str	xzr, [x9, x1, lsl #3]
	mov	x0, x8
	bl	axiom_release
	mov	x3, x20
	mov	x1, x22
	mov	x2, x21
	mov	x0, x19
.LBB121_4:                              // %label_17
	ldr	x8, [x0, #16]
	tbz	w3, #0, .LBB121_8
// %bb.5:                               // %label_17
	cmp	x2, #1, lsl #12                 // =4096
	b.lt	.LBB121_8
// %bb.6:                               // %chk.i.i
	ldur	x9, [x2, #-16]
	cmn	x9, #1
	b.eq	.LBB121_8
// %bb.7:                               // %bump.i.i
	add	x9, x9, #1
	stur	x9, [x2, #-16]
.LBB121_8:                              // %"Mem$memSetWord.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	str	x2, [x8, x1, lsl #3]
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
.LBB121_9:                              // %label_5
	ret
.Lfunc_end121:
	.size	Vec$vecSet, .Lfunc_end121-Vec$vecSet
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecReserve                  // -- Begin function Vec$vecReserve
	.p2align	2
	.type	Vec$vecReserve,@function
Vec$vecReserve:                         // @"Vec$vecReserve"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	ldr	x8, [x0, #8]
	mov	x19, x0
	cmp	x1, x8
	b.le	.LBB122_11
.LBB122_1:                              // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	mov	x21, x8
	lsl	x8, x8, #1
	cmp	x21, x1
	b.lt	.LBB122_1
// %bb.2:                               // %"Vec$vecGrownCap.exit"
	lsl	x0, x21, #3
	ldr	x20, [x19, #16]
	bl	axiom_alloc
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB122_5
// %bb.3:                               // %chk.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB122_5
// %bb.4:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB122_5:                              // %axiom_retain.exit.i
	ldr	x8, [x19, #24]
	cmp	x8, #1
	b.ne	.LBB122_7
// %bb.6:                               // %label_5.i
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
.LBB122_7:                              // %label_7.i
	ldr	x8, [x19]
	lsl	x8, x8, #3
	cmp	x8, #1
	b.lt	.LBB122_10
// %bb.8:                               // %label_2.lr.ph.i.i.i
	mov	x9, x20
	mov	x10, x0
.LBB122_9:                              // %label_2.i.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x9], #1
	subs	x8, x8, #1
	strb	w11, [x10], #1
	b.ne	.LBB122_9
.LBB122_10:                             // %"Vec$vecReserveExactly.exit"
	stp	x21, x0, [x19, #8]
	mov	x0, x20
	ldur	x8, [x20, #-8]
	and	x8, x8, #0xffffffffffff7fff
	stur	x8, [x20, #-8]
	bl	axiom_release
.LBB122_11:                             // %label_6
	mov	x0, x19
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end122:
	.size	Vec$vecReserve, .Lfunc_end122-Vec$vecReserve
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecGrownCap                 // -- Begin function Vec$vecGrownCap
	.p2align	2
	.type	Vec$vecGrownCap,@function
Vec$vecGrownCap:                        // @"Vec$vecGrownCap"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
.LBB123_1:                              // %label_0
                                        // =>This Inner Loop Header: Depth=1
	mov	x8, x0
	lsl	x0, x0, #1
	cmp	x8, x1
	b.lt	.LBB123_1
// %bb.2:                               // %label_8
	mov	x0, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end123:
	.size	Vec$vecGrownCap, .Lfunc_end123-Vec$vecGrownCap
                                        // -- End function
	.globl	Vec$vecReserveExactly           // -- Begin function Vec$vecReserveExactly
	.p2align	2
	.type	Vec$vecReserveExactly,@function
Vec$vecReserveExactly:                  // @"Vec$vecReserveExactly"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x19, x0
	ldr	x20, [x0, #16]
	lsl	x0, x1, #3
	mov	x21, x1
	bl	axiom_alloc
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB124_3
// %bb.1:                               // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB124_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB124_3:                              // %axiom_retain.exit
	ldr	x8, [x19, #24]
	cmp	x8, #1
	b.ne	.LBB124_5
// %bb.4:                               // %label_5
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
.LBB124_5:                              // %label_7
	ldr	x8, [x19]
	lsl	x8, x8, #3
	cmp	x8, #1
	b.lt	.LBB124_8
// %bb.6:                               // %label_2.lr.ph.i.i
	mov	x9, x20
	mov	x10, x0
.LBB124_7:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x9], #1
	subs	x8, x8, #1
	strb	w11, [x10], #1
	b.ne	.LBB124_7
.LBB124_8:                              // %"Mem$memCopy.exit"
	stp	x21, x0, [x19, #8]
	mov	x0, x20
	ldur	x8, [x20, #-8]
	and	x8, x8, #0xffffffffffff7fff
	stur	x8, [x20, #-8]
	bl	axiom_release
	mov	x0, x19
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end124:
	.size	Vec$vecReserveExactly, .Lfunc_end124-Vec$vecReserveExactly
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecPush                     // -- Begin function Vec$vecPush
	.p2align	2
	.type	Vec$vecPush,@function
Vec$vecPush:                            // @"Vec$vecPush"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	str	x25, [sp, #16]                  // 8-byte Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	ldp	x23, x8, [x0]
	mov	x21, x2
	mov	x19, x0
	mov	x20, x1
	add	x24, x23, #1
	cmp	x24, x8
	b.le	.LBB125_11
.LBB125_1:                              // %label_0.i.i
                                        // =>This Inner Loop Header: Depth=1
	mov	x25, x8
	lsl	x8, x8, #1
	cmp	x25, x24
	b.lt	.LBB125_1
// %bb.2:                               // %"Vec$vecGrownCap.exit.i"
	lsl	x0, x25, #3
	ldr	x22, [x19, #16]
	bl	axiom_alloc
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB125_5
// %bb.3:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB125_5
// %bb.4:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB125_5:                              // %axiom_retain.exit.i.i
	ldr	x8, [x19, #24]
	cmp	x8, #1
	b.ne	.LBB125_7
// %bb.6:                               // %label_5.i.i
	ldur	x8, [x0, #-8]
	orr	x8, x8, #0x8000
	stur	x8, [x0, #-8]
.LBB125_7:                              // %label_7.i.i
	ldr	x8, [x19]
	lsl	x8, x8, #3
	cmp	x8, #1
	b.lt	.LBB125_10
// %bb.8:                               // %label_2.lr.ph.i.i.i.i
	mov	x9, x22
	mov	x10, x0
.LBB125_9:                              // %label_2.i.i.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x9], #1
	subs	x8, x8, #1
	strb	w11, [x10], #1
	b.ne	.LBB125_9
.LBB125_10:                             // %"Vec$vecReserveExactly.exit.i"
	stp	x25, x0, [x19, #8]
	mov	x0, x22
	ldur	x8, [x22, #-8]
	and	x8, x8, #0xffffffffffff7fff
	stur	x8, [x22, #-8]
	bl	axiom_release
.LBB125_11:                             // %"Vec$vecReserve.exit"
	ldr	x8, [x19, #16]
	tbz	w21, #0, .LBB125_15
// %bb.12:                              // %"Vec$vecReserve.exit"
	cmp	x20, #1, lsl #12                // =4096
	b.lt	.LBB125_15
// %bb.13:                              // %chk.i.i
	ldur	x9, [x20, #-16]
	cmn	x9, #1
	b.eq	.LBB125_15
// %bb.14:                              // %bump.i.i
	add	x9, x9, #1
	stur	x9, [x20, #-16]
.LBB125_15:                             // %"Mem$memSetWord.exit"
	str	x20, [x8, x23, lsl #3]
	mov	x0, x19
	ldr	x25, [sp, #16]                  // 8-byte Reload
	str	x24, [x19]
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
	ret
.Lfunc_end125:
	.size	Vec$vecPush, .Lfunc_end125-Vec$vecPush
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecPop                      // -- Begin function Vec$vecPop
	.p2align	2
	.type	Vec$vecPop,@function
Vec$vecPop:                             // @"Vec$vecPop"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cbz	x8, .LBB126_2
// %bb.1:                               // %label_5
	ldr	x9, [x0, #16]
	sub	x10, x8, #1
	ldr	x8, [x9, x10, lsl #3]
	str	xzr, [x9, x10, lsl #3]
	str	x10, [x0]
.LBB126_2:                              // %label_6
	mov	x0, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end126:
	.size	Vec$vecPop, .Lfunc_end126-Vec$vecPop
                                        // -- End function
	.globl	Vec$vecLast                     // -- Begin function Vec$vecLast
	.p2align	2
	.type	Vec$vecLast,@function
Vec$vecLast:                            // @"Vec$vecLast"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x8, #1
	b.lt	.LBB127_2
// %bb.1:                               // %label_11.i
	ldr	x9, [x0, #16]
	add	x8, x9, x8, lsl #3
	ldur	x0, [x8, #-8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB127_2:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end127:
	.size	Vec$vecLast, .Lfunc_end127-Vec$vecLast
                                        // -- End function
	.globl	Vec$vecClear                    // -- Begin function Vec$vecClear
	.p2align	2
	.type	Vec$vecClear,@function
Vec$vecClear:                           // @"Vec$vecClear"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	ldr	x8, [x0, #24]
	mov	x19, x0
	cmp	x8, #1
	b.ne	.LBB128_4
// %bb.1:                               // %label_2
	ldr	x8, [x19]
	cmp	x8, #1
	b.lt	.LBB128_4
// %bb.2:                               // %label_10.lr.ph.i
	mov	x20, xzr
.LBB128_3:                              // %label_10.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x8, [x19, #16]
	ldr	x0, [x8, x20, lsl #3]
	str	xzr, [x8, x20, lsl #3]
	bl	axiom_release
	ldr	x8, [x19]
	add	x20, x20, #1
	cmp	x20, x8
	b.lt	.LBB128_3
.LBB128_4:                              // %label_4
	mov	x0, x19
	str	xzr, [x19]
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end128:
	.size	Vec$vecClear, .Lfunc_end128-Vec$vecClear
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecDropAt                   // -- Begin function Vec$vecDropAt
	.p2align	2
	.type	Vec$vecDropAt,@function
Vec$vecDropAt:                          // @"Vec$vecDropAt"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	ldr	x8, [x0, #16]
	mov	x19, x0
	ldr	x0, [x8, x1, lsl #3]
	str	xzr, [x8, x1, lsl #3]
	bl	axiom_release
	mov	x0, x19
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end129:
	.size	Vec$vecDropAt, .Lfunc_end129-Vec$vecDropAt
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecDropFrom                 // -- Begin function Vec$vecDropFrom
	.p2align	2
	.type	Vec$vecDropFrom,@function
Vec$vecDropFrom:                        // @"Vec$vecDropFrom"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	ldr	x8, [x0]
	mov	x19, x0
	cmp	x1, x8
	b.ge	.LBB130_3
// %bb.1:
	mov	x20, x1
.LBB130_2:                              // %label_10
                                        // =>This Inner Loop Header: Depth=1
	ldr	x8, [x19, #16]
	ldr	x0, [x8, x20, lsl #3]
	str	xzr, [x8, x20, lsl #3]
	bl	axiom_release
	ldr	x8, [x19]
	add	x20, x20, #1
	cmp	x20, x8
	b.lt	.LBB130_2
.LBB130_3:                              // %label_9
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end130:
	.size	Vec$vecDropFrom, .Lfunc_end130-Vec$vecDropFrom
	.cfi_endproc
                                        // -- End function
	.globl	Vec$vecSum                      // -- Begin function Vec$vecSum
	.p2align	2
	.type	Vec$vecSum,@function
Vec$vecSum:                             // @"Vec$vecSum"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x8, #1
	b.lt	.LBB131_4
// %bb.1:                               // %label_11.lr.ph.i
	ldr	x9, [x0, #16]
	mov	x0, xzr
.LBB131_2:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x10, [x9], #8
	subs	x8, x8, #1
	add	x0, x10, x0
	b.ne	.LBB131_2
// %bb.3:                               // %"Vec$vecSumFrom.exit"
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB131_4:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end131:
	.size	Vec$vecSum, .Lfunc_end131-Vec$vecSum
                                        // -- End function
	.globl	Vec$vecSumFrom                  // -- Begin function Vec$vecSumFrom
	.p2align	2
	.type	Vec$vecSumFrom,@function
Vec$vecSumFrom:                         // @"Vec$vecSumFrom"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x9, [x0]
	mov	x8, x0
	mov	x0, x2
	mov	x29, sp
	cmp	x1, x9
	b.lt	.LBB132_4
.LBB132_1:                              // %label_10
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB132_2:                              // %label_11.i
                                        //   in Loop: Header=BB132_4 Depth=1
	ldr	x10, [x8, #16]
	ldr	x10, [x10, x1, lsl #3]
.LBB132_3:                              // %"Vec$vecGet.exit"
                                        //   in Loop: Header=BB132_4 Depth=1
	add	x1, x1, #1
	add	x0, x10, x0
	cmp	x9, x1
	b.eq	.LBB132_1
.LBB132_4:                              // %label_11
                                        // =>This Inner Loop Header: Depth=1
	tbz	x1, #63, .LBB132_2
// %bb.5:                               //   in Loop: Header=BB132_4 Depth=1
	mov	x10, xzr
	b	.LBB132_3
.Lfunc_end132:
	.size	Vec$vecSumFrom, .Lfunc_end132-Vec$vecSumFrom
                                        // -- End function
	.globl	Vec$vecHash                     // -- Begin function Vec$vecHash
	.p2align	2
	.type	Vec$vecHash,@function
Vec$vecHash:                            // @"Vec$vecHash"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x8, #1
	b.lt	.LBB133_4
// %bb.1:                               // %label_11.lr.ph.i
	mov	x10, #36837                     // =0x8fe5
	ldr	x9, [x0, #16]
	mov	w11, #51719                     // =0xca07
	movk	x10, #4770, lsl #16
	mov	w0, #1                          // =0x1
	movk	w11, #15258, lsl #16
	movk	x10, #24369, lsl #32
	movk	x10, #35184, lsl #48
.LBB133_2:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x12, [x9], #8
	subs	x8, x8, #1
	sub	x12, x12, x0
	add	x12, x12, x0, lsl #5
	smulh	x13, x12, x10
	add	x13, x13, x12
	asr	x14, x13, #29
	add	x13, x14, x13, lsr #63
	msub	x0, x13, x11, x12
	b.ne	.LBB133_2
// %bb.3:                               // %"Vec$vecHashFrom.exit"
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB133_4:
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end133:
	.size	Vec$vecHash, .Lfunc_end133-Vec$vecHash
                                        // -- End function
	.globl	Vec$vecHashFrom                 // -- Begin function Vec$vecHashFrom
	.p2align	2
	.type	Vec$vecHashFrom,@function
Vec$vecHashFrom:                        // @"Vec$vecHashFrom"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x1, x8
	b.ge	.LBB134_6
// %bb.1:
	mov	x9, #36837                      // =0x8fe5
	mov	w10, #51719                     // =0xca07
	movk	x9, #4770, lsl #16
	movk	w10, #15258, lsl #16
	movk	x9, #24369, lsl #32
	movk	x9, #35184, lsl #48
	b	.LBB134_4
.LBB134_2:                              // %label_11.i
                                        //   in Loop: Header=BB134_4 Depth=1
	ldr	x11, [x0, #16]
	ldr	x11, [x11, x1, lsl #3]
.LBB134_3:                              // %"Vec$vecGet.exit"
                                        //   in Loop: Header=BB134_4 Depth=1
	sub	x11, x11, x2
	add	x1, x1, #1
	add	x11, x11, x2, lsl #5
	cmp	x8, x1
	smulh	x12, x11, x9
	add	x12, x12, x11
	asr	x13, x12, #29
	add	x12, x13, x12, lsr #63
	msub	x2, x12, x10, x11
	b.eq	.LBB134_6
.LBB134_4:                              // %label_11
                                        // =>This Inner Loop Header: Depth=1
	tbz	x1, #63, .LBB134_2
// %bb.5:                               //   in Loop: Header=BB134_4 Depth=1
	mov	x11, xzr
	b	.LBB134_3
.LBB134_6:                              // %label_10
	mov	x0, x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end134:
	.size	Vec$vecHashFrom, .Lfunc_end134-Vec$vecHashFrom
                                        // -- End function
	.globl	Str$strWrap                     // -- Begin function Str$strWrap
	.p2align	2
	.type	Str$strWrap,@function
Str$strWrap:                            // @"Str$strWrap"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x20, x0
	mov	w0, #24                         // =0x18
	mov	x29, sp
	mov	x19, x1
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x19, [x0, #-8]
	b.lt	.LBB135_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB135_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB135_3:                              // %"Str$strWrapOwned.exit"
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end135:
	.size	Str$strWrap, .Lfunc_end135-Str$strWrap
                                        // -- End function
	.globl	Str$strWrapOwned                // -- Begin function Str$strWrapOwned
	.p2align	2
	.type	Str$strWrapOwned,@function
Str$strWrapOwned:                       // @"Str$strWrapOwned"
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	mov	x21, x0
	mov	w0, #24                         // =0x18
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	mov	x19, x2
	mov	x20, x1
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x21, x19, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x20, [x0, #-8]
	b.lt	.LBB136_3
// %bb.1:                               // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB136_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB136_3:                              // %axiom_retain.exit
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end136:
	.size	Str$strWrapOwned, .Lfunc_end136-Str$strWrapOwned
                                        // -- End function
	.globl	Str$strAlloc                    // -- Begin function Str$strAlloc
	.p2align	2
	.type	Str$strAlloc,@function
Str$strAlloc:                           // @"Str$strAlloc"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x20, x0
	add	x0, x0, #1
	mov	x29, sp
	bl	axiom_alloc
	mov	x19, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB137_3
// %bb.1:                               // %chk.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB137_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB137_3:                              // %axiom_retain.exit
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x19, x19, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x20, [x0, #-8]
	b.lt	.LBB137_6
// %bb.4:                               // %chk.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB137_6
// %bb.5:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB137_6:                              // %"Str$strWrapOwned.exit"
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end137:
	.size	Str$strAlloc, .Lfunc_end137-Str$strAlloc
                                        // -- End function
	.globl	Str$strFromLit                  // -- Begin function Str$strFromLit
	.p2align	2
	.type	Str$strFromLit,@function
Str$strFromLit:                         // @"Str$strFromLit"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x19, x0
	mov	x20, xzr
	mov	x29, sp
.LBB138_1:                              // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x19, x20]
	add	x20, x20, #1
	cbnz	w8, .LBB138_1
// %bb.2:                               // %"Str$cstrLen.exit"
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x19, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	sub	x9, x20, #1
	stp	x8, x9, [x0, #-8]
	b.lt	.LBB138_5
// %bb.3:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB138_5
// %bb.4:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB138_5:                              // %"Str$strWrap.exit"
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end138:
	.size	Str$strFromLit, .Lfunc_end138-Str$strFromLit
                                        // -- End function
	.globl	Str$cstrLen                     // -- Begin function Str$cstrLen
	.p2align	2
	.type	Str$cstrLen,@function
Str$cstrLen:                            // @"Str$cstrLen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
.LBB139_1:                              // %label_0
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x0, x1]
	add	x1, x1, #1
	cbnz	w8, .LBB139_1
// %bb.2:                               // %label_12
	sub	x0, x1, #1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end139:
	.size	Str$cstrLen, .Lfunc_end139-Str$cstrLen
                                        // -- End function
	.globl	Str$strLen                      // -- Begin function Str$strLen
	.p2align	2
	.type	Str$strLen,@function
Str$strLen:                             // @"Str$strLen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end140:
	.size	Str$strLen, .Lfunc_end140-Str$strLen
                                        // -- End function
	.globl	Str$strData                     // -- Begin function Str$strData
	.p2align	2
	.type	Str$strData,@function
Str$strData:                            // @"Str$strData"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, #8]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end141:
	.size	Str$strData, .Lfunc_end141-Str$strData
                                        // -- End function
	.globl	Str$strOwner                    // -- Begin function Str$strOwner
	.p2align	2
	.type	Str$strOwner,@function
Str$strOwner:                           // @"Str$strOwner"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, #16]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end142:
	.size	Str$strOwner, .Lfunc_end142-Str$strOwner
                                        // -- End function
	.globl	Str$strByte                     // -- Begin function Str$strByte
	.p2align	2
	.type	Str$strByte,@function
Str$strByte:                            // @"Str$strByte"
// %bb.0:
	tbnz	x1, #63, .LBB143_3
// %bb.1:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x1, x8
	b.ge	.LBB143_4
// %bb.2:                               // %label_11
	ldr	x8, [x0, #8]
	ldrb	w0, [x8, x1]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB143_3:
	mov	x0, xzr
	ret
.LBB143_4:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end143:
	.size	Str$strByte, .Lfunc_end143-Str$strByte
                                        // -- End function
	.globl	Str$strCStr                     // -- Begin function Str$strCStr
	.p2align	2
	.type	Str$strCStr,@function
Str$strCStr:                            // @"Str$strCStr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x0, [x0, #8]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end144:
	.size	Str$strCStr, .Lfunc_end144-Str$strCStr
                                        // -- End function
	.globl	Str$strIsEmpty                  // -- Begin function Str$strIsEmpty
	.p2align	2
	.type	Str$strIsEmpty,@function
Str$strIsEmpty:                         // @"Str$strIsEmpty"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	mov	x29, sp
	cmp	x8, #0
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end145:
	.size	Str$strIsEmpty, .Lfunc_end145-Str$strIsEmpty
                                        // -- End function
	.globl	Str$strCmp                      // -- Begin function Str$strCmp
	.p2align	2
	.type	Str$strCmp,@function
Str$strCmp:                             // @"Str$strCmp"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x9, [x0]
	ldr	x10, [x1]
	mov	x29, sp
	subs	x8, x9, x10
	csel	x9, x9, x10, lt
	cmp	x9, #1
	b.lt	.LBB146_4
// %bb.1:                               // %label_3.lr.ph.i.i
	ldr	x10, [x1, #8]
	ldr	x11, [x0, #8]
	mov	x12, xzr
.LBB146_2:                              // %label_3.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w13, [x11, x12]
	ldrb	w14, [x10, x12]
	add	x12, x12, #1
	cmp	x12, x9
	sub	x13, x13, x14
	b.ge	.LBB146_5
// %bb.3:                               // %label_3.i.i
                                        //   in Loop: Header=BB146_2 Depth=1
	cbz	x13, .LBB146_2
	b	.LBB146_5
.LBB146_4:
	mov	x13, xzr
.LBB146_5:                              // %"Mem$memCmp.exit"
	cmp	x13, #0
	csel	x0, x8, x13, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end146:
	.size	Str$strCmp, .Lfunc_end146-Str$strCmp
                                        // -- End function
	.globl	Str$strEq                       // -- Begin function Str$strEq
	.p2align	2
	.type	Str$strEq,@function
Str$strEq:                              // @"Str$strEq"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x0]
	ldr	x9, [x1]
	mov	x29, sp
	cmp	x8, x9
	b.ne	.LBB147_6
// %bb.1:                               // %label_6
	cmp	x8, #1
	b.lt	.LBB147_7
// %bb.2:                               // %label_3.lr.ph.i.i
	ldr	x9, [x1, #8]
	ldr	x10, [x0, #8]
	mov	x11, xzr
.LBB147_3:                              // %label_3.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w12, [x10, x11]
	ldrb	w13, [x9, x11]
	add	x11, x11, #1
	cmp	x11, x8
	b.ge	.LBB147_5
// %bb.4:                               // %label_3.i.i
                                        //   in Loop: Header=BB147_3 Depth=1
	cmp	w12, w13
	b.eq	.LBB147_3
.LBB147_5:                              // %"Mem$memCmp.exit.loopexit"
	cmp	w12, w13
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB147_6:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB147_7:
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end147:
	.size	Str$strEq, .Lfunc_end147-Str$strEq
                                        // -- End function
	.globl	Str$strSlice                    // -- Begin function Str$strSlice
	.p2align	2
	.type	Str$strSlice,@function
Str$strSlice:                           // @"Str$strSlice"
// %bb.0:                               // %label_6
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	ldr	x9, [x0]
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	ldr	x19, [x0, #16]
	str	x21, [sp, #16]                  // 8-byte Spill
	cmp	x1, x9
	csel	x8, x1, x9, lt
	cmp	x1, #0
	csel	x8, xzr, x8, mi
	sub	x9, x9, x8
	cmp	x2, x9
	csel	x9, x2, x9, lt
	cmp	x2, #0
	csel	x20, xzr, x9, mi
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB148_3
// %bb.1:                               // %chk.i
	ldur	x9, [x19, #-16]
	cmn	x9, #1
	b.eq	.LBB148_3
// %bb.2:                               // %bump.i
	add	x9, x9, #1
	stur	x9, [x19, #-16]
.LBB148_3:                              // %axiom_retain.exit
	ldr	x9, [x0, #8]
	mov	w0, #24                         // =0x18
	add	x21, x9, x8
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x21, x19, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x20, [x0, #-8]
	b.lt	.LBB148_6
// %bb.4:                               // %chk.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB148_6
// %bb.5:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB148_6:                              // %"Str$strWrapOwned.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end148:
	.size	Str$strSlice, .Lfunc_end148-Str$strSlice
                                        // -- End function
	.globl	Str$strDup                      // -- Begin function Str$strDup
	.p2align	2
	.type	Str$strDup,@function
Str$strDup:                             // @"Str$strDup"
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	ldr	x21, [x0]
	mov	x29, sp
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x0
	add	x0, x21, #1
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB149_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB149_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB149_3:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x21, [x0, #-8]
	b.lt	.LBB149_6
// %bb.4:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB149_6
// %bb.5:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB149_6:                              // %"Str$strAlloc.exit"
	cmp	x21, #1
	b.lt	.LBB149_9
// %bb.7:                               // %label_2.lr.ph.i.i
	ldr	x8, [x19, #8]
	ldr	x9, [x0, #8]
.LBB149_8:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w10, [x8], #1
	subs	x21, x21, #1
	strb	w10, [x9], #1
	b.ne	.LBB149_8
.LBB149_9:                              // %"Mem$memCopy.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end149:
	.size	Str$strDup, .Lfunc_end149-Str$strDup
                                        // -- End function
	.globl	Str$strConcat                   // -- Begin function Str$strConcat
	.p2align	2
	.type	Str$strConcat,@function
Str$strConcat:                          // @"Str$strConcat"
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x24, x23, [sp, #16]             // 16-byte Folded Spill
	ldr	x23, [x0]
	mov	x29, sp
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	ldr	x22, [x1]
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	mov	x20, x0
	mov	x19, x1
	add	x24, x22, x23
	add	x0, x24, #1
	bl	axiom_alloc
	mov	x21, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB150_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB150_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB150_3:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x21, x21, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x24, [x0, #-8]
	b.lt	.LBB150_6
// %bb.4:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB150_6
// %bb.5:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB150_6:                              // %"Str$strAlloc.exit"
	cmp	x23, #1
	b.lt	.LBB150_9
// %bb.7:                               // %label_2.lr.ph.i.i
	ldr	x8, [x20, #8]
	ldr	x9, [x0, #8]
	mov	x10, x23
.LBB150_8:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x8], #1
	subs	x10, x10, #1
	strb	w11, [x9], #1
	b.ne	.LBB150_8
.LBB150_9:                              // %"Mem$memCopy.exit"
	cmp	x22, #1
	b.lt	.LBB150_12
// %bb.10:                              // %label_2.lr.ph.i.i16
	ldr	x9, [x0, #8]
	ldr	x8, [x19, #8]
	add	x9, x9, x23
.LBB150_11:                             // %label_2.i.i19
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w10, [x8], #1
	subs	x22, x22, #1
	strb	w10, [x9], #1
	b.ne	.LBB150_11
.LBB150_12:                             // %"Mem$memCopy.exit26"
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end150:
	.size	Str$strConcat, .Lfunc_end150-Str$strConcat
                                        // -- End function
	.globl	Str$strFindByte                 // -- Begin function Str$strFindByte
	.p2align	2
	.type	Str$strFindByte,@function
Str$strFindByte:                        // @"Str$strFindByte"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	mov	x19, x2
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB151_3
// %bb.1:                               // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB151_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB151_3:                              // %axiom_retain.exit
	ldr	x8, [x0]
	cmp	x19, x8
	b.ge	.LBB151_8
.LBB151_4:                              // %label_11
                                        // =>This Inner Loop Header: Depth=1
	tbnz	x19, #63, .LBB151_6
// %bb.5:                               // %label_11.i
                                        //   in Loop: Header=BB151_4 Depth=1
	ldr	x9, [x0, #8]
	ldrb	w9, [x9, x19]
	cmp	x9, x1
	b.ne	.LBB151_7
	b	.LBB151_9
.LBB151_6:                              //   in Loop: Header=BB151_4 Depth=1
	mov	x9, xzr
	cmp	x9, x1
	b.eq	.LBB151_9
.LBB151_7:                              // %label_22
                                        //   in Loop: Header=BB151_4 Depth=1
	add	x19, x19, #1
	cmp	x8, x19
	b.ne	.LBB151_4
.LBB151_8:
	mov	x19, #-1                        // =0xffffffffffffffff
.LBB151_9:                              // %label_12
	bl	axiom_release
	mov	x0, x19
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end151:
	.size	Str$strFindByte, .Lfunc_end151-Str$strFindByte
	.cfi_endproc
                                        // -- End function
	.globl	Str$strStartsWith               // -- Begin function Str$strStartsWith
	.p2align	2
	.type	Str$strStartsWith,@function
Str$strStartsWith:                      // @"Str$strStartsWith"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x8, [x1]
	ldr	x9, [x0]
	mov	x29, sp
	cmp	x8, x9
	b.le	.LBB152_2
// %bb.1:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB152_2:                              // %label_6
	cmp	x8, #1
	b.lt	.LBB152_7
// %bb.3:                               // %label_3.lr.ph.i.i
	ldr	x9, [x1, #8]
	ldr	x10, [x0, #8]
	mov	x11, xzr
.LBB152_4:                              // %label_3.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w12, [x10, x11]
	ldrb	w13, [x9, x11]
	add	x11, x11, #1
	cmp	x11, x8
	b.ge	.LBB152_6
// %bb.5:                               // %label_3.i.i
                                        //   in Loop: Header=BB152_4 Depth=1
	cmp	w12, w13
	b.eq	.LBB152_4
.LBB152_6:                              // %"Mem$memCmp.exit.loopexit"
	cmp	w12, w13
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB152_7:
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end152:
	.size	Str$strStartsWith, .Lfunc_end152-Str$strStartsWith
                                        // -- End function
	.globl	Str$strIsDigit                  // -- Begin function Str$strIsDigit
	.p2align	2
	.type	Str$strIsDigit,@function
Str$strIsDigit:                         // @"Str$strIsDigit"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	sub	x8, x0, #48
	mov	x29, sp
	cmp	x8, #10
	cset	w0, lo
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end153:
	.size	Str$strIsDigit, .Lfunc_end153-Str$strIsDigit
                                        // -- End function
	.globl	Str$strIsAlpha                  // -- Begin function Str$strIsAlpha
	.p2align	2
	.type	Str$strIsAlpha,@function
Str$strIsAlpha:                         // @"Str$strIsAlpha"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	cmp	x0, #65
	mov	x29, sp
	b.lt	.LBB154_2
// %bb.1:                               // %label_3
	sub	x8, x0, #97
	cmp	x8, #26
	cset	w8, lo
	cmp	x0, #91
	csinc	x0, x8, xzr, ge
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB154_2:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end154:
	.size	Str$strIsAlpha, .Lfunc_end154-Str$strIsAlpha
                                        // -- End function
	.globl	Str$strIsSpace                  // -- Begin function Str$strIsSpace
	.p2align	2
	.type	Str$strIsSpace,@function
Str$strIsSpace:                         // @"Str$strIsSpace"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	and	x8, x0, #0xfffffffffffffffb
	mov	x29, sp
	cmp	x8, #9
	cset	w8, eq
	cmp	x0, #32
	csinc	x8, x8, xzr, ne
	cmp	x0, #10
	csinc	x0, x8, xzr, ne
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end155:
	.size	Str$strIsSpace, .Lfunc_end155-Str$strIsSpace
                                        // -- End function
	.globl	Str$strHexVal                   // -- Begin function Str$strHexVal
	.p2align	2
	.type	Str$strHexVal,@function
Str$strHexVal:                          // @"Str$strHexVal"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	sub	x9, x0, #65
	sub	x10, x0, #97
	sub	x11, x0, #55
	cmp	x9, #6
	sub	x8, x0, #48
	mov	x29, sp
	csinv	x9, x11, xzr, lo
	sub	x11, x0, #87
	cmp	x10, #5
	csel	x9, x9, x11, hi
	cmp	x8, #10
	csel	x0, x8, x9, lo
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end156:
	.size	Str$strHexVal, .Lfunc_end156-Str$strHexVal
                                        // -- End function
	.globl	Str$strIsHexDigit               // -- Begin function Str$strIsHexDigit
	.p2align	2
	.type	Str$strIsHexDigit,@function
Str$strIsHexDigit:                      // @"Str$strIsHexDigit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	sub	x9, x0, #65
	sub	x10, x0, #97
	sub	x11, x0, #55
	cmp	x9, #6
	sub	x8, x0, #48
	mov	x29, sp
	csinv	x9, x11, xzr, lo
	sub	x11, x0, #87
	cmp	x10, #5
	csel	x9, x9, x11, hi
	cmp	x8, #10
	csel	x8, x8, x9, lo
	mvn	x8, x8
	lsr	x0, x8, #63
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end157:
	.size	Str$strIsHexDigit, .Lfunc_end157-Str$strIsHexDigit
                                        // -- End function
	.globl	Str$strSplit                    // -- Begin function Str$strSplit
	.p2align	2
	.type	Str$strSplit,@function
Str$strSplit:                           // @"Str$strSplit"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x20, x0
	mov	w0, #32                         // =0x20
	mov	x19, x1
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x21, x0
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x0, #-8]
	mov	w0, #64                         // =0x40
	bl	axiom_alloc
	cmp	x21, #1, lsl #12                // =4096
	b.lt	.LBB158_3
// %bb.1:                               // %chk.i.i.i.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB158_3
// %bb.2:                               // %bump.i.i.i.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB158_3:                              // %axiom_retain.exit.i.i.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB158_6
// %bb.4:                               // %chk.i3.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB158_6
// %bb.5:                               // %bump.i8.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB158_6:                              // %"Vec$vecNew.exit"
	mov	w8, #8                          // =0x8
	stp	x0, xzr, [x21, #16]
	mov	x0, x20
	mov	x1, x19
	mov	x2, xzr
	mov	x3, x21
	stp	xzr, x8, [x21]
	bl	Str$strSplitFrom
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end158:
	.size	Str$strSplit, .Lfunc_end158-Str$strSplit
	.cfi_endproc
                                        // -- End function
	.globl	Str$strSplitFrom                // -- Begin function Str$strSplitFrom
	.p2align	2
	.type	Str$strSplitFrom,@function
Str$strSplitFrom:                       // @"Str$strSplitFrom"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-96]!           // 16-byte Folded Spill
	stp	x28, x27, [sp, #16]             // 16-byte Folded Spill
	stp	x26, x25, [sp, #32]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #48]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #64]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #80]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 96
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w27, -72
	.cfi_offset w28, -80
	.cfi_offset w30, -88
	.cfi_offset w29, -96
	mov	x19, x3
	mov	x22, x2
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	mov	x21, x1
	b.lt	.LBB159_3
// %bb.1:                               // %chk.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB159_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB159_3:                              // %axiom_retain.exit
	mov	w23, #47                        // =0x2f
	mov	x24, #-65536                    // =0xffffffffffff0000
	b	.LBB159_5
.LBB159_4:                              // %"Str$strSlice.exit"
                                        //   in Loop: Header=BB159_5 Depth=1
	mov	x0, x19
	mov	x2, xzr
	bl	Vec$vecPush
	add	x22, x26, #1
	tbnz	x25, #63, .LBB159_23
.LBB159_5:                              // %label_0
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB159_10 Depth 2
	cmp	x20, #1, lsl #12                // =4096
	b.lt	.LBB159_8
// %bb.6:                               // %chk.i.i
                                        //   in Loop: Header=BB159_5 Depth=1
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB159_8
// %bb.7:                               // %bump.i.i
                                        //   in Loop: Header=BB159_5 Depth=1
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB159_8:                              // %axiom_retain.exit.i
                                        //   in Loop: Header=BB159_5 Depth=1
	ldr	x8, [x20]
	cmp	x22, x8
	b.ge	.LBB159_14
// %bb.9:                               // %label_11.i.preheader
                                        //   in Loop: Header=BB159_5 Depth=1
	mov	x25, x22
.LBB159_10:                             // %label_11.i
                                        //   Parent Loop BB159_5 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	tbnz	x25, #63, .LBB159_12
// %bb.11:                              // %label_11.i.i
                                        //   in Loop: Header=BB159_10 Depth=2
	ldr	x9, [x20, #8]
	ldrb	w9, [x9, x25]
	cmp	x9, x21
	b.ne	.LBB159_13
	b	.LBB159_15
.LBB159_12:                             //   in Loop: Header=BB159_10 Depth=2
	mov	x9, xzr
	cmp	x9, x21
	b.eq	.LBB159_15
.LBB159_13:                             // %label_22.i
                                        //   in Loop: Header=BB159_10 Depth=2
	add	x25, x25, #1
	cmp	x8, x25
	b.ne	.LBB159_10
.LBB159_14:                             //   in Loop: Header=BB159_5 Depth=1
	mov	x25, #-1                        // =0xffffffffffffffff
.LBB159_15:                             // %"Str$strFindByte.exit"
                                        //   in Loop: Header=BB159_5 Depth=1
	mov	x0, x20
	bl	axiom_release
	mov	x26, x25
	tbz	x25, #63, .LBB159_17
// %bb.16:                              // %label_12
                                        //   in Loop: Header=BB159_5 Depth=1
	ldr	x26, [x20]
.LBB159_17:                             // %label_14
                                        //   in Loop: Header=BB159_5 Depth=1
	ldr	x9, [x20]
	sub	x10, x26, x22
	cmp	x22, x9
	csel	x8, x22, x9, lt
	cmp	x22, #0
	ldr	x22, [x20, #16]
	csel	x8, xzr, x8, mi
	sub	x9, x9, x8
	cmp	x10, x9
	csel	x9, x10, x9, lt
	cmp	x10, #0
	csel	x27, xzr, x9, mi
	cmp	x22, #1, lsl #12                // =4096
	b.lt	.LBB159_20
// %bb.18:                              // %chk.i.i13
                                        //   in Loop: Header=BB159_5 Depth=1
	ldur	x9, [x22, #-16]
	cmn	x9, #1
	b.eq	.LBB159_20
// %bb.19:                              // %bump.i.i18
                                        //   in Loop: Header=BB159_5 Depth=1
	add	x9, x9, #1
	stur	x9, [x22, #-16]
.LBB159_20:                             // %axiom_retain.exit.i20
                                        //   in Loop: Header=BB159_5 Depth=1
	ldr	x9, [x20, #8]
	mov	w0, #24                         // =0x18
	add	x28, x9, x8
	bl	axiom_alloc
	ldur	x8, [x0, #-8]
	mov	x1, x0
	stp	x28, x22, [x0, #8]
	ubfx	x9, x8, #1, #14
	cmp	x9, #47
	csel	x9, x9, x23, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x9, x24, x9
	mvn	w9, w9
	and	x9, x9, #0x40000
	orr	x8, x9, x8
	stp	x8, x27, [x0, #-8]
	b.lt	.LBB159_4
// %bb.21:                              // %chk.i.i.i
                                        //   in Loop: Header=BB159_5 Depth=1
	ldur	x8, [x1, #-16]
	cmn	x8, #1
	b.eq	.LBB159_4
// %bb.22:                              // %bump.i.i.i
                                        //   in Loop: Header=BB159_5 Depth=1
	add	x8, x8, #1
	stur	x8, [x1, #-16]
	b	.LBB159_4
.LBB159_23:                             // %label_30
	ldp	x20, x19, [sp, #80]             // 16-byte Folded Reload
	mov	x0, xzr
	ldp	x22, x21, [sp, #64]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #48]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #32]             // 16-byte Folded Reload
	ldp	x28, x27, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #96             // 16-byte Folded Reload
	ret
.Lfunc_end159:
	.size	Str$strSplitFrom, .Lfunc_end159-Str$strSplitFrom
	.cfi_endproc
                                        // -- End function
	.globl	Str$strFromByte                 // -- Begin function Str$strFromByte
	.p2align	2
	.type	Str$strFromByte,@function
Str$strFromByte:                        // @"Str$strFromByte"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x19, x0
	mov	w0, #2                          // =0x2
	mov	x29, sp
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB160_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB160_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB160_3:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	mov	w9, #1                          // =0x1
	stp	x8, x9, [x0, #-8]
	b.lt	.LBB160_6
// %bb.4:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB160_6
// %bb.5:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB160_6:                              // %"Str$strAlloc.exit"
	ldr	x8, [x0, #8]
	strb	w19, [x8]
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end160:
	.size	Str$strFromByte, .Lfunc_end160-Str$strFromByte
                                        // -- End function
	.globl	Fmt$intIsMostNegative           // -- Begin function Fmt$intIsMostNegative
	.p2align	2
	.type	Fmt$intIsMostNegative,@function
Fmt$intIsMostNegative:                  // @"Fmt$intIsMostNegative"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x8, #-9223372036854775808       // =0x8000000000000000
	mov	x29, sp
	cmp	x0, x8
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end161:
	.size	Fmt$intIsMostNegative, .Lfunc_end161-Fmt$intIsMostNegative
                                        // -- End function
	.globl	Fmt$fmtIntWidth                 // -- Begin function Fmt$fmtIntWidth
	.p2align	2
	.type	Fmt$fmtIntWidth,@function
Fmt$fmtIntWidth:                        // @"Fmt$fmtIntWidth"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x11, #-3689348814741910324      // =0xcccccccccccccccc
	mov	x8, xzr
	mov	w9, #20                         // =0x14
	mov	x10, #-9223372036854775808      // =0x8000000000000000
	movk	x11, #52429
	mov	x29, sp
	cmp	x0, x10
	b.ne	.LBB162_2
	b	.LBB162_6
.LBB162_1:                              // %label_8
                                        //   in Loop: Header=BB162_2 Depth=1
	neg	x0, x0
	add	x8, x8, #1
	cmp	x0, x10
	b.eq	.LBB162_6
.LBB162_2:                              // %label_3
                                        // =>This Inner Loop Header: Depth=1
	tbnz	x0, #63, .LBB162_1
// %bb.3:                               // %label_9
                                        //   in Loop: Header=BB162_2 Depth=1
	cmp	x0, #10
	b.lt	.LBB162_5
// %bb.4:                               // %divok_22
                                        //   in Loop: Header=BB162_2 Depth=1
	umulh	x12, x0, x11
	add	x8, x8, #1
	lsr	x0, x12, #3
	cmp	x0, x10
	b.ne	.LBB162_2
	b	.LBB162_6
.LBB162_5:
	mov	w9, #1                          // =0x1
.LBB162_6:                              // %label_4
	add	x0, x9, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end162:
	.size	Fmt$fmtIntWidth, .Lfunc_end162-Fmt$fmtIntWidth
                                        // -- End function
	.globl	Fmt$fmtInt                      // -- Begin function Fmt$fmtInt
	.p2align	2
	.type	Fmt$fmtInt,@function
Fmt$fmtInt:                             // @"Fmt$fmtInt"
	.cfi_startproc
// %bb.0:
	mov	x8, #-9223372036854775808       // =0x8000000000000000
	cmp	x0, x8
	b.ne	.LBB163_2
// %bb.1:                               // %label_4
	adrp	x0, .Lstrhdr_0+16
	add	x0, x0, :lo12:.Lstrhdr_0+16
	ret
.LBB163_2:                              // %label_3
	tbnz	x0, #63, .LBB163_4
// %bb.3:                               // %label_10
	b	Fmt$fmtNat
.LBB163_4:                              // %label_9
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	neg	x0, x0
	bl	Fmt$fmtNat
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end163:
	.size	Fmt$fmtInt, .Lfunc_end163-Fmt$fmtInt
	.cfi_endproc
                                        // -- End function
	.globl	Fmt$fmtNat                      // -- Begin function Fmt$fmtNat
	.p2align	2
	.type	Fmt$fmtNat,@function
Fmt$fmtNat:                             // @"Fmt$fmtNat"
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x0
	bl	Fmt$fmtIntWidth
	mov	x20, x0
	add	x0, x0, #1
	bl	axiom_alloc
	mov	x21, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB164_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB164_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB164_3:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x21, x21, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x20, [x0, #-8]
	b.lt	.LBB164_6
// %bb.4:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB164_6
// %bb.5:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB164_6:                              // %"Str$strAlloc.exit"
	mov	x8, #7378697629483820646        // =0x6666666666666666
	cmp	x19, #10
	movk	x8, #26215
	smulh	x8, x19, x8
	lsr	w9, w8, #2
                                        // kill: def $w9 killed $w9 killed $x9 def $x9
	add	x9, x9, x8, lsr #63
	mov	w8, #10                         // =0xa
	msub	w10, w9, w8, w19
	ldr	x9, [x0, #8]
	add	x9, x20, x9
	add	w10, w10, #48
	sturb	w10, [x9, #-1]
	b.lt	.LBB164_9
// %bb.7:                               // %divok_27.i.preheader
	mov	x10, #-3689348814741910324      // =0xcccccccccccccccc
	mov	x11, #-7378697629483820647      // =0x9999999999999999
	sub	x9, x9, #2
	movk	x10, #52429
	eor	x11, x11, #0x8000000000000003
.LBB164_8:                              // %divok_27.i
                                        // =>This Inner Loop Header: Depth=1
	umulh	x13, x19, x10
	mov	x12, x19
	cmp	x12, #99
	lsr	x19, x13, #3
	umulh	x13, x19, x11
	msub	w13, w13, w8, w19
	orr	w12, w13, #0x30
	strb	w12, [x9], #-1
	b.hi	.LBB164_8
.LBB164_9:                              // %"Fmt$fmtDigits.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end164:
	.size	Fmt$fmtNat, .Lfunc_end164-Fmt$fmtNat
                                        // -- End function
	.globl	Fmt$fmtDigits                   // -- Begin function Fmt$fmtDigits
	.p2align	2
	.type	Fmt$fmtDigits,@function
Fmt$fmtDigits:                          // @"Fmt$fmtDigits"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x8, #7378697629483820646        // =0x6666666666666666
	cmp	x1, #10
	mov	x29, sp
	movk	x8, #26215
	smulh	x8, x1, x8
	lsr	w9, w8, #2
                                        // kill: def $w9 killed $w9 killed $x9 def $x9
	add	x9, x9, x8, lsr #63
	mov	w8, #10                         // =0xa
	msub	w9, w9, w8, w1
	add	w9, w9, #48
	strb	w9, [x0, x2]
	b.lt	.LBB165_3
// %bb.1:                               // %divok_27.preheader
	add	x9, x2, x0
	mov	x10, #-3689348814741910324      // =0xcccccccccccccccc
	mov	x11, #-7378697629483820647      // =0x9999999999999999
	sub	x9, x9, #1
	movk	x10, #52429
	eor	x11, x11, #0x8000000000000003
.LBB165_2:                              // %divok_27
                                        // =>This Inner Loop Header: Depth=1
	umulh	x13, x1, x10
	mov	x12, x1
	cmp	x12, #100
	lsr	x1, x13, #3
	umulh	x13, x1, x11
	msub	w13, w13, w8, w1
	orr	w12, w13, #0x30
	strb	w12, [x9], #-1
	b.hs	.LBB165_2
.LBB165_3:                              // %label_19
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end165:
	.size	Fmt$fmtDigits, .Lfunc_end165-Fmt$fmtDigits
                                        // -- End function
	.globl	Fmt$fmtHexShr4                  // -- Begin function Fmt$fmtHexShr4
	.p2align	2
	.type	Fmt$fmtHexShr4,@function
Fmt$fmtHexShr4:                         // @"Fmt$fmtHexShr4"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	lsr	x0, x0, #4
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end166:
	.size	Fmt$fmtHexShr4, .Lfunc_end166-Fmt$fmtHexShr4
                                        // -- End function
	.globl	Fmt$fmtHex                      // -- Begin function Fmt$fmtHex
	.p2align	2
	.type	Fmt$fmtHex,@function
Fmt$fmtHex:                             // @"Fmt$fmtHex"
// %bb.0:
	cbz	x0, .LBB167_12
// %bb.1:                               // %label_8.i.preheader
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	mov	x21, #-1                        // =0xffffffffffffffff
	mov	x8, x0
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x0
	mov	x29, sp
.LBB167_2:                              // %label_8.i
                                        // =>This Inner Loop Header: Depth=1
	lsr	x8, x8, #4
	add	x21, x21, #1
	cbnz	x8, .LBB167_2
// %bb.3:                               // %"Fmt$fmtHexWidth.exit"
	add	x0, x21, #2
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	add	x22, x21, #1
	b.lt	.LBB167_6
// %bb.4:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB167_6
// %bb.5:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB167_6:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x22, [x0, #-8]
	b.lt	.LBB167_9
// %bb.7:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB167_9
// %bb.8:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB167_9:                              // %"Str$strAlloc.exit"
	ldr	x8, [x0, #8]
	add	x8, x8, x21
.LBB167_10:                             // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	and	x9, x19, #0xf
	lsr	x19, x19, #4
	orr	w10, w9, #0x30
	add	w11, w9, #87
	cmp	x9, #10
	csel	x9, x10, x11, lo
	strb	w9, [x8], #-1
	cbnz	x19, .LBB167_10
// %bb.11:
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB167_12:
	adrp	x0, .Lstrhdr_2+16
	add	x0, x0, :lo12:.Lstrhdr_2+16
	ret
.Lfunc_end167:
	.size	Fmt$fmtHex, .Lfunc_end167-Fmt$fmtHex
                                        // -- End function
	.globl	Fmt$fmtHexWidth                 // -- Begin function Fmt$fmtHexWidth
	.p2align	2
	.type	Fmt$fmtHexWidth,@function
Fmt$fmtHexWidth:                        // @"Fmt$fmtHexWidth"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x8, x0
	mov	x0, x1
	mov	x29, sp
	cbz	x8, .LBB168_2
.LBB168_1:                              // %label_8
                                        // =>This Inner Loop Header: Depth=1
	lsr	x8, x8, #4
	add	x0, x0, #1
	cbnz	x8, .LBB168_1
.LBB168_2:                              // %label_7
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end168:
	.size	Fmt$fmtHexWidth, .Lfunc_end168-Fmt$fmtHexWidth
                                        // -- End function
	.globl	Fmt$fmtHexDigits                // -- Begin function Fmt$fmtHexDigits
	.p2align	2
	.type	Fmt$fmtHexDigits,@function
Fmt$fmtHexDigits:                       // @"Fmt$fmtHexDigits"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x2
	mov	x29, sp
.LBB169_1:                              // %label_0
                                        // =>This Inner Loop Header: Depth=1
	and	x9, x1, #0xf
	lsr	x1, x1, #4
	orr	w10, w9, #0x30
	add	w11, w9, #87
	cmp	x9, #10
	csel	x9, x10, x11, lo
	strb	w9, [x8], #-1
	cbnz	x1, .LBB169_1
// %bb.2:                               // %label_25
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end169:
	.size	Fmt$fmtHexDigits, .Lfunc_end169-Fmt$fmtHexDigits
                                        // -- End function
	.globl	Fmt$fmtPadLeft                  // -- Begin function Fmt$fmtPadLeft
	.p2align	2
	.type	Fmt$fmtPadLeft,@function
Fmt$fmtPadLeft:                         // @"Fmt$fmtPadLeft"
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	ldr	x21, [x0]
	mov	x29, sp
	str	x23, [sp, #16]                  // 8-byte Spill
	subs	x22, x1, x21
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	b.le	.LBB170_13
// %bb.1:                               // %label_5
	mov	x23, x0
	add	x0, x1, #1
	mov	x19, x1
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB170_4
// %bb.2:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB170_4
// %bb.3:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB170_4:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x19, [x0, #-8]
	b.lt	.LBB170_7
// %bb.5:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB170_7
// %bb.6:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB170_7:                              // %"Str$strAlloc.exit"
	cmp	x22, #1
	b.lt	.LBB170_10
// %bb.8:                               // %label_2.lr.ph.i.i
	ldr	x8, [x0, #8]
	mov	w9, #32                         // =0x20
	mov	x10, x22
.LBB170_9:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x10, x10, #1
	strb	w9, [x8], #1
	b.ne	.LBB170_9
.LBB170_10:                             // %"Mem$memSet.exit"
	cmp	x21, #1
	b.lt	.LBB170_16
// %bb.11:                              // %label_2.lr.ph.i.i10
	ldr	x9, [x0, #8]
	ldr	x8, [x23, #8]
	add	x9, x9, x22
.LBB170_12:                             // %label_2.i.i12
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w10, [x8], #1
	subs	x21, x21, #1
	strb	w10, [x9], #1
	b.ne	.LBB170_12
	b	.LBB170_16
.LBB170_13:                             // %label_4
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB170_16
// %bb.14:                              // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB170_16
// %bb.15:                              // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB170_16:                             // %label_6
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldr	x23, [sp, #16]                  // 8-byte Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end170:
	.size	Fmt$fmtPadLeft, .Lfunc_end170-Fmt$fmtPadLeft
                                        // -- End function
	.globl	Fmt$fmtPadRight                 // -- Begin function Fmt$fmtPadRight
	.p2align	2
	.type	Fmt$fmtPadRight,@function
Fmt$fmtPadRight:                        // @"Fmt$fmtPadRight"
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	ldr	x22, [x0]
	mov	x29, sp
	str	x23, [sp, #16]                  // 8-byte Spill
	subs	x21, x1, x22
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	b.le	.LBB171_13
// %bb.1:                               // %label_5
	mov	x23, x0
	add	x0, x1, #1
	mov	x19, x1
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB171_4
// %bb.2:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB171_4
// %bb.3:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB171_4:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x19, [x0, #-8]
	b.lt	.LBB171_7
// %bb.5:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB171_7
// %bb.6:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB171_7:                              // %"Str$strAlloc.exit"
	cmp	x22, #1
	b.lt	.LBB171_10
// %bb.8:                               // %label_2.lr.ph.i.i
	ldr	x8, [x23, #8]
	ldr	x9, [x0, #8]
	mov	x10, x22
.LBB171_9:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x8], #1
	subs	x10, x10, #1
	strb	w11, [x9], #1
	b.ne	.LBB171_9
.LBB171_10:                             // %"Mem$memCopy.exit"
	cmp	x21, #1
	b.lt	.LBB171_16
// %bb.11:                              // %label_2.lr.ph.i.i10
	ldr	x8, [x0, #8]
	mov	w9, #32                         // =0x20
	add	x8, x8, x22
.LBB171_12:                             // %label_2.i.i11
                                        // =>This Inner Loop Header: Depth=1
	subs	x21, x21, #1
	strb	w9, [x8], #1
	b.ne	.LBB171_12
	b	.LBB171_16
.LBB171_13:                             // %label_4
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB171_16
// %bb.14:                              // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB171_16
// %bb.15:                              // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB171_16:                             // %label_6
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldr	x23, [sp, #16]                  // 8-byte Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end171:
	.size	Fmt$fmtPadRight, .Lfunc_end171-Fmt$fmtPadRight
                                        // -- End function
	.globl	Fmt$fmtPadCenter                // -- Begin function Fmt$fmtPadCenter
	.p2align	2
	.type	Fmt$fmtPadCenter,@function
Fmt$fmtPadCenter:                       // @"Fmt$fmtPadCenter"
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	ldr	x21, [x0]
	mov	x29, sp
	stp	x24, x23, [sp, #16]             // 16-byte Folded Spill
	subs	x22, x1, x21
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	b.le	.LBB172_16
// %bb.1:                               // %divok_10
	mov	x23, x0
	add	x0, x1, #1
	mov	x19, x1
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB172_4
// %bb.2:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB172_4
// %bb.3:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB172_4:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	add	x24, x22, x22, lsr #63
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x19, [x0, #-8]
	b.lt	.LBB172_7
// %bb.5:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB172_7
// %bb.6:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB172_7:                              // %"Str$strAlloc.exit"
	asr	x8, x24, #1
	cmp	x22, #1
	b.le	.LBB172_10
// %bb.8:                               // %label_2.lr.ph.i.i
	ldr	x9, [x0, #8]
	mov	w10, #32                        // =0x20
	mov	x11, x8
.LBB172_9:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x11, x11, #1
	strb	w10, [x9], #1
	b.ne	.LBB172_9
.LBB172_10:                             // %"Mem$memSet.exit"
	cmp	x21, #1
	b.lt	.LBB172_13
// %bb.11:                              // %label_2.lr.ph.i.i10
	ldr	x10, [x0, #8]
	ldr	x9, [x23, #8]
	mov	x11, x21
	add	x10, x10, x8
.LBB172_12:                             // %label_2.i.i12
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w12, [x9], #1
	subs	x11, x11, #1
	strb	w12, [x10], #1
	b.ne	.LBB172_12
.LBB172_13:                             // %"Mem$memCopy.exit"
	sub	x9, x22, x8
	cmp	x9, #1
	b.lt	.LBB172_19
// %bb.14:                              // %label_2.lr.ph.i.i18
	ldr	x9, [x0, #8]
	add	x10, x8, x21
	add	x8, x10, x9
	sub	x9, x10, x19
	mov	w10, #32                        // =0x20
.LBB172_15:                             // %label_2.i.i20
                                        // =>This Inner Loop Header: Depth=1
	adds	x9, x9, #1
	strb	w10, [x8], #1
	b.lo	.LBB172_15
	b	.LBB172_19
.LBB172_16:                             // %label_4
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB172_19
// %bb.17:                              // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB172_19
// %bb.18:                              // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB172_19:                             // %label_6
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end172:
	.size	Fmt$fmtPadCenter, .Lfunc_end172-Fmt$fmtPadCenter
                                        // -- End function
	.globl	Fmt$fmtPadZerosLeft             // -- Begin function Fmt$fmtPadZerosLeft
	.p2align	2
	.type	Fmt$fmtPadZerosLeft,@function
Fmt$fmtPadZerosLeft:                    // @"Fmt$fmtPadZerosLeft"
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	ldr	x22, [x0]
	mov	x29, sp
	stp	x24, x23, [sp, #16]             // 16-byte Folded Spill
	subs	x21, x1, x22
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	b.le	.LBB173_3
// %bb.1:                               // %label_5
	mov	x19, x1
	cmp	x22, #1
	b.lt	.LBB173_6
// %bb.2:                               // %label_11.i
	ldr	x8, [x0, #8]
	mov	x24, x0
	ldrb	w8, [x8]
	cmp	w8, #45
	cset	w23, eq
	b	.LBB173_7
.LBB173_3:                              // %label_4
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB173_21
// %bb.4:                               // %chk.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB173_21
// %bb.5:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
	b	.LBB173_21
.LBB173_6:
	mov	x24, x0
	mov	x23, xzr
.LBB173_7:                              // %label_12
	add	x0, x19, #1
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB173_10
// %bb.8:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB173_10
// %bb.9:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB173_10:                             // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x19, [x0, #-8]
	b.lt	.LBB173_13
// %bb.11:                              // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB173_13
// %bb.12:                              // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB173_13:                             // %"Str$strAlloc.exit"
	cbz	x23, .LBB173_15
// %bb.14:                              // %label_26
	ldr	x8, [x0, #8]
	mov	w9, #45                         // =0x2d
	strb	w9, [x8]
.LBB173_15:                             // %label_28
	cmp	x21, #1
	b.lt	.LBB173_18
// %bb.16:                              // %label_2.lr.ph.i.i
	ldr	x8, [x0, #8]
	mov	w9, #48                         // =0x30
	mov	x10, x21
	add	x8, x8, x23
.LBB173_17:                             // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x10, x10, #1
	strb	w9, [x8], #1
	b.ne	.LBB173_17
.LBB173_18:                             // %"Mem$memSet.exit"
	sub	x8, x22, x23
	cmp	x8, #1
	b.lt	.LBB173_21
// %bb.19:                              // %label_2.lr.ph.i.i14
	ldr	x9, [x24, #8]
	ldr	x10, [x0, #8]
	add	x11, x23, x21
	add	x9, x9, x23
	add	x10, x11, x10
.LBB173_20:                             // %label_2.i.i16
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w11, [x9], #1
	subs	x8, x8, #1
	strb	w11, [x10], #1
	b.ne	.LBB173_20
.LBB173_21:                             // %label_6
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end173:
	.size	Fmt$fmtPadZerosLeft, .Lfunc_end173-Fmt$fmtPadZerosLeft
                                        // -- End function
	.globl	Fmt$fmtHexUpper                 // -- Begin function Fmt$fmtHexUpper
	.p2align	2
	.type	Fmt$fmtHexUpper,@function
Fmt$fmtHexUpper:                        // @"Fmt$fmtHexUpper"
// %bb.0:
	cbz	x0, .LBB174_12
// %bb.1:                               // %label_8.i.preheader
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	mov	x21, #-1                        // =0xffffffffffffffff
	mov	x8, x0
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x0
	mov	x29, sp
.LBB174_2:                              // %label_8.i
                                        // =>This Inner Loop Header: Depth=1
	lsr	x8, x8, #4
	add	x21, x21, #1
	cbnz	x8, .LBB174_2
// %bb.3:                               // %"Fmt$fmtHexWidth.exit"
	add	x0, x21, #2
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	add	x22, x21, #1
	b.lt	.LBB174_6
// %bb.4:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB174_6
// %bb.5:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB174_6:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x20, x20, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x22, [x0, #-8]
	b.lt	.LBB174_9
// %bb.7:                               // %chk.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB174_9
// %bb.8:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB174_9:                              // %"Str$strAlloc.exit"
	ldr	x8, [x0, #8]
	add	x8, x8, x21
.LBB174_10:                             // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	and	x9, x19, #0xf
	lsr	x19, x19, #4
	orr	w10, w9, #0x30
	add	w11, w9, #55
	cmp	x9, #10
	csel	x9, x10, x11, lo
	strb	w9, [x8], #-1
	cbnz	x19, .LBB174_10
// %bb.11:
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB174_12:
	adrp	x0, .Lstrhdr_2+16
	add	x0, x0, :lo12:.Lstrhdr_2+16
	ret
.Lfunc_end174:
	.size	Fmt$fmtHexUpper, .Lfunc_end174-Fmt$fmtHexUpper
                                        // -- End function
	.globl	Fmt$fmtHexDigitsUpper           // -- Begin function Fmt$fmtHexDigitsUpper
	.p2align	2
	.type	Fmt$fmtHexDigitsUpper,@function
Fmt$fmtHexDigitsUpper:                  // @"Fmt$fmtHexDigitsUpper"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x2
	mov	x29, sp
.LBB175_1:                              // %label_0
                                        // =>This Inner Loop Header: Depth=1
	and	x9, x1, #0xf
	lsr	x1, x1, #4
	orr	w10, w9, #0x30
	add	w11, w9, #55
	cmp	x9, #10
	csel	x9, x10, x11, lo
	strb	w9, [x8], #-1
	cbnz	x1, .LBB175_1
// %bb.2:                               // %label_25
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end175:
	.size	Fmt$fmtHexDigitsUpper, .Lfunc_end175-Fmt$fmtHexDigitsUpper
                                        // -- End function
	.globl	Fmt$powTen                      // -- Begin function Fmt$powTen
	.p2align	2
	.type	Fmt$powTen,@function
Fmt$powTen:                             // @"Fmt$powTen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #1                          // =0x1
	mov	x29, sp
	subs	x0, x0, #1
	b.lt	.LBB176_2
.LBB176_1:                              // %label_4
                                        // =>This Inner Loop Header: Depth=1
	add	x8, x8, x8, lsl #2
	lsl	x8, x8, #1
	subs	x0, x0, #1
	b.ge	.LBB176_1
.LBB176_2:                              // %label_5
	mov	x0, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end176:
	.size	Fmt$powTen, .Lfunc_end176-Fmt$powTen
                                        // -- End function
	.globl	Fmt$fmtPadZeros                 // -- Begin function Fmt$fmtPadZeros
	.p2align	2
	.type	Fmt$fmtPadZeros,@function
Fmt$fmtPadZeros:                        // @"Fmt$fmtPadZeros"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	mov	x19, x1
	bl	Fmt$fmtNat
	mov	x1, x19
	mov	x20, x0
	bl	Fmt$fmtPadZerosLeft
	mov	x19, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end177:
	.size	Fmt$fmtPadZeros, .Lfunc_end177-Fmt$fmtPadZeros
	.cfi_endproc
                                        // -- End function
	.globl	Fmt$fmtFloat                    // -- Begin function Fmt$fmtFloat
	.p2align	2
	.type	Fmt$fmtFloat,@function
Fmt$fmtFloat:                           // @"Fmt$fmtFloat"
	.cfi_startproc
// %bb.0:
	fmov	d0, x0
	fcmp	d0, #0.0
	b.pl	.LBB178_2
// %bb.1:                               // %label_5.i
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	movi	d1, #0000000000000000
	mov	w1, #6                          // =0x6
	fsub	d0, d1, d0
	fmov	x0, d0
	bl	Fmt$fmtFloatAbs
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB178_2:                              // %label_6.i
	mov	w1, #6                          // =0x6
	b	Fmt$fmtFloatAbs
.Lfunc_end178:
	.size	Fmt$fmtFloat, .Lfunc_end178-Fmt$fmtFloat
	.cfi_endproc
                                        // -- End function
	.globl	Fmt$fmtFloatPrec                // -- Begin function Fmt$fmtFloatPrec
	.p2align	2
	.type	Fmt$fmtFloatPrec,@function
Fmt$fmtFloatPrec:                       // @"Fmt$fmtFloatPrec"
	.cfi_startproc
// %bb.0:
	fmov	d0, x0
	fcmp	d0, #0.0
	b.pl	.LBB179_2
// %bb.1:                               // %label_5
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	movi	d1, #0000000000000000
	fsub	d0, d1, d0
	fmov	x0, d0
	bl	Fmt$fmtFloatAbs
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB179_2:                              // %label_6
	b	Fmt$fmtFloatAbs
.Lfunc_end179:
	.size	Fmt$fmtFloatPrec, .Lfunc_end179-Fmt$fmtFloatPrec
	.cfi_endproc
                                        // -- End function
	.globl	Fmt$fmtFloatAbs                 // -- Begin function Fmt$fmtFloatAbs
	.p2align	2
	.type	Fmt$fmtFloatAbs,@function
Fmt$fmtFloatAbs:                        // @"Fmt$fmtFloatAbs"
	.cfi_startproc
// %bb.0:                               // %label_26
	str	d8, [sp, #-64]!                 // 8-byte Folded Spill
	stp	x29, x30, [sp, #8]              // 16-byte Folded Spill
	str	x23, [sp, #24]                  // 8-byte Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	add	x29, sp, #8
	.cfi_def_cfa w29, 56
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w30, -48
	.cfi_offset w29, -56
	.cfi_offset b8, -64
	fmov	d0, x0
	mov	x0, x1
	mov	x19, x1
	fcvtzs	x20, d0
	scvtf	d1, x20
	fsub	d8, d0, d1
	bl	Fmt$powTen
	scvtf	d0, x0
	fmov	d1, #0.50000000
	mov	x8, x0
	fmul	d0, d8, d0
	fadd	d0, d0, d1
	fcvtzs	x9, d0
	cmp	x0, x9
	cinc	x0, x20, le
	cmp	x19, #0
	b.le	.LBB180_3
// %bb.1:                               // %label_35
	cmp	x8, x9
	mov	x10, #-9223372036854775808      // =0x8000000000000000
	csel	x8, x8, xzr, le
	cmp	x0, x10
	sub	x20, x9, x8
	b.ne	.LBB180_5
// %bb.2:
	adrp	x21, .Lstrhdr_0+16
	add	x21, x21, :lo12:.Lstrhdr_0+16
	b	.LBB180_10
.LBB180_3:                              // %label_34
	mov	x8, #-9223372036854775808       // =0x8000000000000000
	cmp	x0, x8
	b.ne	.LBB180_7
// %bb.4:                               // %label_36
	adrp	x0, .Lstrhdr_0+16
	add	x0, x0, :lo12:.Lstrhdr_0+16
	b	.LBB180_11
.LBB180_5:                              // %label_3.i2
	tbnz	x0, #63, .LBB180_9
// %bb.6:                               // %label_10.i4
	bl	Fmt$fmtNat
	mov	x21, x0
	b	.LBB180_10
.LBB180_7:                              // %label_3.i
	tbnz	x0, #63, .LBB180_12
// %bb.8:                               // %label_10.i
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldr	x23, [sp, #24]                  // 8-byte Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp, #8]              // 16-byte Folded Reload
	ldr	d8, [sp], #64                   // 8-byte Folded Reload
	b	Fmt$fmtNat
.LBB180_9:                              // %label_9.i7
	neg	x0, x0
	bl	Fmt$fmtNat
	mov	x22, x0
	adrp	x23, .Lstrhdr_1+16
	add	x23, x23, :lo12:.Lstrhdr_1+16
	mov	x0, x23
	mov	x1, x22
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x23
	bl	axiom_release
	mov	x0, x22
	bl	axiom_release
.LBB180_10:                             // %"Fmt$fmtInt.exit11"
	adrp	x22, .Lstrhdr_3+16
	add	x22, x22, :lo12:.Lstrhdr_3+16
	mov	x0, x21
	mov	x1, x22
	bl	Str$strConcat
	mov	x23, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x22
	bl	axiom_release
	mov	x0, x20
	bl	Fmt$fmtNat
	mov	x1, x19
	mov	x20, x0
	bl	Fmt$fmtPadZerosLeft
	mov	x19, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x23
	mov	x1, x19
	bl	Str$strConcat
	mov	x20, x0
	mov	x0, x23
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	mov	x0, x20
.LBB180_11:                             // %label_36
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldr	x23, [sp, #24]                  // 8-byte Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp, #8]              // 16-byte Folded Reload
	ldr	d8, [sp], #64                   // 8-byte Folded Reload
	ret
.LBB180_12:                             // %label_9.i
	neg	x0, x0
	bl	Fmt$fmtNat
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	mov	x0, x21
	b	.LBB180_11
.Lfunc_end180:
	.size	Fmt$fmtFloatAbs, .Lfunc_end180-Fmt$fmtFloatAbs
	.cfi_endproc
                                        // -- End function
	.globl	Sys$stdin                       // -- Begin function Sys$stdin
	.p2align	2
	.type	Sys$stdin,@function
Sys$stdin:                              // @"Sys$stdin"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end181:
	.size	Sys$stdin, .Lfunc_end181-Sys$stdin
                                        // -- End function
	.globl	Sys$stdout                      // -- Begin function Sys$stdout
	.p2align	2
	.type	Sys$stdout,@function
Sys$stdout:                             // @"Sys$stdout"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end182:
	.size	Sys$stdout, .Lfunc_end182-Sys$stdout
                                        // -- End function
	.globl	Sys$stderr                      // -- Begin function Sys$stderr
	.p2align	2
	.type	Sys$stderr,@function
Sys$stderr:                             // @"Sys$stderr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #2                          // =0x2
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end183:
	.size	Sys$stderr, .Lfunc_end183-Sys$stderr
                                        // -- End function
	.globl	Sys$sysWriteFd                  // -- Begin function Sys$sysWriteFd
	.p2align	2
	.type	Sys$sysWriteFd,@function
Sys$sysWriteFd:                         // @"Sys$sysWriteFd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #64                         // =0x40
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end184:
	.size	Sys$sysWriteFd, .Lfunc_end184-Sys$sysWriteFd
                                        // -- End function
	.globl	Sys$sysWriteAllFd               // -- Begin function Sys$sysWriteAllFd
	.p2align	2
	.type	Sys$sysWriteAllFd,@function
Sys$sysWriteAllFd:                      // @"Sys$sysWriteAllFd"
// %bb.0:
	mov	x9, x3
	cmp	x3, x2
	b.ge	.LBB185_6
// %bb.1:                               // %label_11.preheader
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x10, x2
	mov	x11, x1
	mov	x12, x0
	mov	x29, sp
.LBB185_2:                              // %label_11
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x9, x11
	sub	x2, x10, x9
	mov	w8, #64                         // =0x40
	mov	x0, x12
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB185_4
// %bb.3:                               // %label_26
                                        //   in Loop: Header=BB185_2 Depth=1
	add	x9, x0, x9
	cmp	x9, x10
	b.lt	.LBB185_2
	b	.LBB185_5
.LBB185_4:                              // %label_25
	csel	x9, x9, x0, eq
.LBB185_5:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB185_6:                              // %label_12
	mov	x0, x9
	ret
.Lfunc_end185:
	.size	Sys$sysWriteAllFd, .Lfunc_end185-Sys$sysWriteAllFd
                                        // -- End function
	.globl	Sys$sysReadFd                   // -- Begin function Sys$sysReadFd
	.p2align	2
	.type	Sys$sysReadFd,@function
Sys$sysReadFd:                          // @"Sys$sysReadFd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #63                         // =0x3f
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end186:
	.size	Sys$sysReadFd, .Lfunc_end186-Sys$sysReadFd
                                        // -- End function
	.globl	Sys$sysOpenPath                 // -- Begin function Sys$sysOpenPath
	.p2align	2
	.type	Sys$sysOpenPath,@function
Sys$sysOpenPath:                        // @"Sys$sysOpenPath"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x2, x1
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end187:
	.size	Sys$sysOpenPath, .Lfunc_end187-Sys$sysOpenPath
                                        // -- End function
	.globl	Sys$sysOpenPathMode             // -- Begin function Sys$sysOpenPathMode
	.p2align	2
	.type	Sys$sysOpenPathMode,@function
Sys$sysOpenPathMode:                    // @"Sys$sysOpenPathMode"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x3, x2
	mov	x2, x1
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end188:
	.size	Sys$sysOpenPathMode, .Lfunc_end188-Sys$sysOpenPathMode
                                        // -- End function
	.globl	Sys$sysCloseFd                  // -- Begin function Sys$sysCloseFd
	.p2align	2
	.type	Sys$sysCloseFd,@function
Sys$sysCloseFd:                         // @"Sys$sysCloseFd"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end189:
	.size	Sys$sysCloseFd, .Lfunc_end189-Sys$sysCloseFd
                                        // -- End function
	.globl	Sys$sysSeek                     // -- Begin function Sys$sysSeek
	.p2align	2
	.type	Sys$sysSeek,@function
Sys$sysSeek:                            // @"Sys$sysSeek"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #62                         // =0x3e
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end190:
	.size	Sys$sysSeek, .Lfunc_end190-Sys$sysSeek
                                        // -- End function
	.globl	Sys$sysExitWith                 // -- Begin function Sys$sysExitWith
	.p2align	2
	.type	Sys$sysExitWith,@function
Sys$sysExitWith:                        // @"Sys$sysExitWith"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #94                         // =0x5e
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end191:
	.size	Sys$sysExitWith, .Lfunc_end191-Sys$sysExitWith
                                        // -- End function
	.globl	Sys$sysFailed                   // -- Begin function Sys$sysFailed
	.p2align	2
	.type	Sys$sysFailed,@function
Sys$sysFailed:                          // @"Sys$sysFailed"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	lsr	x0, x0, #63
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end192:
	.size	Sys$sysFailed, .Lfunc_end192-Sys$sysFailed
                                        // -- End function
	.globl	Sys$sysErrno                    // -- Begin function Sys$sysErrno
	.p2align	2
	.type	Sys$sysErrno,@function
Sys$sysErrno:                           // @"Sys$sysErrno"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	neg	x8, x0
	mov	x29, sp
	and	x0, x8, x0, asr #63
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end193:
	.size	Sys$sysErrno, .Lfunc_end193-Sys$sysErrno
                                        // -- End function
	.globl	Sys$sysReadFile                 // -- Begin function Sys$sysReadFile
	.p2align	2
	.type	Sys$sysReadFile,@function
Sys$sysReadFile:                        // @"Sys$sysReadFile"
	.cfi_startproc
// %bb.0:
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB194_8
// %bb.1:                               // %label_5
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x19, x0
	mov	w0, #65537                      // =0x10001
	bl	axiom_alloc
	mov	x21, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB194_4
// %bb.2:                               // %chk.i.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB194_4
// %bb.3:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB194_4:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x20, x0
	stp	x21, x21, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	mov	w9, #65536                      // =0x10000
	stp	x8, x9, [x0, #-8]
	b.lt	.LBB194_7
// %bb.5:                               // %chk.i.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB194_7
// %bb.6:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB194_7:                              // %"Str$strAlloc.exit"
	mov	x0, x19
	mov	x1, x20
	mov	x2, xzr
	mov	w3, #65536                      // =0x10000
	bl	Sys$sysReadAll
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	w8, #57                         // =0x39
	mov	x0, x19
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB194_8:                              // %label_6
	adrp	x0, .Lstrhdr_4+16
	add	x0, x0, :lo12:.Lstrhdr_4+16
	ret
.Lfunc_end194:
	.size	Sys$sysReadFile, .Lfunc_end194-Sys$sysReadFile
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysReadAll                  // -- Begin function Sys$sysReadAll
	.p2align	2
	.type	Sys$sysReadAll,@function
Sys$sysReadAll:                         // @"Sys$sysReadAll"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-96]!           // 16-byte Folded Spill
	stp	x28, x27, [sp, #16]             // 16-byte Folded Spill
	stp	x26, x25, [sp, #32]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #48]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #64]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #80]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 96
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w27, -72
	.cfi_offset w28, -80
	.cfi_offset w30, -88
	.cfi_offset w29, -96
	mov	x20, x3
	mov	x22, x2
	mov	x23, x1
	cmp	x1, #1, lsl #12                 // =4096
	mov	x21, x0
	b.lt	.LBB195_3
// %bb.1:                               // %chk.i
	ldur	x8, [x23, #-16]
	cmn	x8, #1
	b.eq	.LBB195_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x23, #-16]
.LBB195_3:                              // %label_0.outer.preheader
	mov	w25, #47                        // =0x2f
	mov	x26, #-65536                    // =0xffffffffffff0000
.LBB195_4:                              // %label_0.outer
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB195_5 Depth 2
                                        //     Child Loop BB195_15 Depth 2
	mov	x19, x23
.LBB195_5:                              // %label_0
                                        //   Parent Loop BB195_4 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldr	x8, [x19, #8]
	sub	x2, x20, x22
	mov	x0, x21
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	add	x1, x8, x22
	mov	w8, #63                         // =0x3f
	mov	x27, x22
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB195_20
// %bb.6:                               // %label_18
                                        //   in Loop: Header=BB195_5 Depth=2
	add	x22, x0, x27
	cmp	x22, x20
	b.lt	.LBB195_5
// %bb.7:                               // %label_42
                                        //   in Loop: Header=BB195_4 Depth=1
	mov	x28, x0
	mov	w0, #1                          // =0x1
	bfi	x0, x20, #1, #63
	bl	axiom_alloc
	mov	x24, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB195_10
// %bb.8:                               // %chk.i.i36
                                        //   in Loop: Header=BB195_4 Depth=1
	ldur	x8, [x24, #-16]
	cmn	x8, #1
	b.eq	.LBB195_10
// %bb.9:                               // %bump.i.i41
                                        //   in Loop: Header=BB195_4 Depth=1
	add	x8, x8, #1
	stur	x8, [x24, #-16]
.LBB195_10:                             // %axiom_retain.exit.i
                                        //   in Loop: Header=BB195_4 Depth=1
	mov	w0, #24                         // =0x18
	lsl	x20, x20, #1
	bl	axiom_alloc
	ldur	x8, [x0, #-8]
	mov	x23, x0
	stp	x24, x24, [x0, #8]
	ubfx	x9, x8, #1, #14
	cmp	x9, #47
	csel	x9, x9, x25, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x9, x26, x9
	mvn	w9, w9
	and	x9, x9, #0x40000
	orr	x8, x9, x8
	stp	x8, x20, [x0, #-8]
	b.lt	.LBB195_13
// %bb.11:                              // %chk.i.i.i
                                        //   in Loop: Header=BB195_4 Depth=1
	ldur	x8, [x23, #-16]
	cmn	x8, #1
	b.eq	.LBB195_13
// %bb.12:                              // %bump.i.i.i
                                        //   in Loop: Header=BB195_4 Depth=1
	add	x8, x8, #1
	stur	x8, [x23, #-16]
.LBB195_13:                             // %"Str$strAlloc.exit"
                                        //   in Loop: Header=BB195_4 Depth=1
	cmp	x22, #1
	b.lt	.LBB195_16
// %bb.14:                              // %label_2.lr.ph.i.i
                                        //   in Loop: Header=BB195_4 Depth=1
	ldr	x8, [x19, #8]
	ldr	x9, [x23, #8]
	add	x10, x28, x27
.LBB195_15:                             // %label_2.i.i
                                        //   Parent Loop BB195_4 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldrb	w11, [x8], #1
	subs	x10, x10, #1
	strb	w11, [x9], #1
	b.ne	.LBB195_15
.LBB195_16:                             // %"Mem$memCopy.exit"
                                        //   in Loop: Header=BB195_4 Depth=1
	cmp	x23, #1, lsl #12                // =4096
	b.lt	.LBB195_19
// %bb.17:                              // %chk.i53
                                        //   in Loop: Header=BB195_4 Depth=1
	ldur	x8, [x23, #-16]
	cmn	x8, #1
	b.eq	.LBB195_19
// %bb.18:                              // %bump.i58
                                        //   in Loop: Header=BB195_4 Depth=1
	add	x8, x8, #1
	stur	x8, [x23, #-16]
.LBB195_19:                             // %axiom_retain.exit60
                                        //   in Loop: Header=BB195_4 Depth=1
	mov	x0, x19
	bl	axiom_release
	mov	x0, x23
	bl	axiom_release
	b	.LBB195_4
.LBB195_20:                             // %label_17
	cbz	x27, .LBB195_27
// %bb.21:                              // %label_25
	ldr	x21, [x19, #16]
	cmp	x21, #1, lsl #12                // =4096
	b.lt	.LBB195_24
// %bb.22:                              // %chk.i22
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB195_24
// %bb.23:                              // %bump.i27
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB195_24:                             // %axiom_retain.exit29
	ldr	x22, [x19, #8]
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x20, x0
	stp	x22, x21, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x27, [x0, #-8]
	b.lt	.LBB195_28
// %bb.25:                              // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB195_28
// %bb.26:                              // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
	b	.LBB195_28
.LBB195_27:
	adrp	x20, .Lstrhdr_4+16
	add	x20, x20, :lo12:.Lstrhdr_4+16
.LBB195_28:                             // %label_19
	mov	x0, x19
	bl	axiom_release
	mov	x0, x20
	ldp	x20, x19, [sp, #80]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #64]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #48]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #32]             // 16-byte Folded Reload
	ldp	x28, x27, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #96             // 16-byte Folded Reload
	ret
.Lfunc_end195:
	.size	Sys$sysReadAll, .Lfunc_end195-Sys$sysReadAll
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysArgc                     // -- Begin function Sys$sysArgc
	.p2align	2
	.type	Sys$sysArgc,@function
Sys$sysArgc:                            // @"Sys$sysArgc"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, __axiom_argc
	mov	x29, sp
	ldr	x0, [x8, :lo12:__axiom_argc]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end196:
	.size	Sys$sysArgc, .Lfunc_end196-Sys$sysArgc
                                        // -- End function
	.globl	Sys$sysArg                      // -- Begin function Sys$sysArg
	.p2align	2
	.type	Sys$sysArg,@function
Sys$sysArg:                             // @"Sys$sysArg"
// %bb.0:                               // %label_5
	mov	x8, x0
	adrp	x0, .Lstrhdr_4+16
	add	x0, x0, :lo12:.Lstrhdr_4+16
	tbnz	x8, #63, .LBB197_8
// %bb.1:                               // %label_5
	adrp	x9, __axiom_argc
	ldr	x9, [x9, :lo12:__axiom_argc]
	cmp	x8, x9
	b.ge	.LBB197_8
// %bb.2:                               // %label_14
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	adrp	x9, __axiom_argv
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x20, xzr
	ldr	x9, [x9, :lo12:__axiom_argv]
	mov	x29, sp
	ldr	x19, [x9, x8, lsl #3]
.LBB197_3:                              // %label_0.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x19, x20]
	add	x20, x20, #1
	cbnz	w8, .LBB197_3
// %bb.4:                               // %"Str$cstrLen.exit.i"
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x19, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	sub	x9, x20, #1
	stp	x8, x9, [x0, #-8]
	b.lt	.LBB197_7
// %bb.5:                               // %chk.i.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB197_7
// %bb.6:                               // %bump.i.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB197_7:
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
.LBB197_8:                              // %label_15
	ret
.Lfunc_end197:
	.size	Sys$sysArg, .Lfunc_end197-Sys$sysArg
                                        // -- End function
	.globl	Sys$sysWriteFile                // -- Begin function Sys$sysWriteFile
	.p2align	2
	.type	Sys$sysWriteFile,@function
Sys$sysWriteFile:                       // @"Sys$sysWriteFile"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x10, x1
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #577                        // =0x241
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	mov	x9, x0
	tbnz	x0, #63, .LBB198_8
// %bb.1:                               // %label_5
	ldr	x11, [x10]
	cmp	x11, #1
	b.lt	.LBB198_5
// %bb.2:                               // %label_11.i.preheader
	ldr	x12, [x10, #8]
	mov	x10, xzr
.LBB198_3:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x10, x12
	sub	x2, x11, x10
	mov	w8, #64                         // =0x40
	mov	x0, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB198_6
// %bb.4:                               // %label_26.i
                                        //   in Loop: Header=BB198_3 Depth=1
	add	x10, x0, x10
	cmp	x10, x11
	b.lt	.LBB198_3
	b	.LBB198_7
.LBB198_5:
	mov	x10, xzr
	b	.LBB198_7
.LBB198_6:                              // %label_25.i
	csel	x10, x10, x0, eq
.LBB198_7:                              // %"Sys$sysWriteAllFd.exit"
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x10
	//APP
	svc	#0
	//NO_APP
.LBB198_8:                              // %label_6
	mov	x0, x9
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end198:
	.size	Sys$sysWriteFile, .Lfunc_end198-Sys$sysWriteFile
                                        // -- End function
	.globl	Sys$sysAppendFile               // -- Begin function Sys$sysAppendFile
	.p2align	2
	.type	Sys$sysAppendFile,@function
Sys$sysAppendFile:                      // @"Sys$sysAppendFile"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x10, x1
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #1089                       // =0x441
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	mov	x9, x0
	tbnz	x0, #63, .LBB199_8
// %bb.1:                               // %label_5
	ldr	x11, [x10]
	cmp	x11, #1
	b.lt	.LBB199_5
// %bb.2:                               // %label_11.i.preheader
	ldr	x12, [x10, #8]
	mov	x10, xzr
.LBB199_3:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x10, x12
	sub	x2, x11, x10
	mov	w8, #64                         // =0x40
	mov	x0, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB199_6
// %bb.4:                               // %label_26.i
                                        //   in Loop: Header=BB199_3 Depth=1
	add	x10, x0, x10
	cmp	x10, x11
	b.lt	.LBB199_3
	b	.LBB199_7
.LBB199_5:
	mov	x10, xzr
	b	.LBB199_7
.LBB199_6:                              // %label_25.i
	csel	x10, x10, x0, eq
.LBB199_7:                              // %"Sys$sysWriteAllFd.exit"
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x10
	//APP
	svc	#0
	//NO_APP
.LBB199_8:                              // %label_6
	mov	x0, x9
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end199:
	.size	Sys$sysAppendFile, .Lfunc_end199-Sys$sysAppendFile
                                        // -- End function
	.globl	Sys$sysRename                   // -- Begin function Sys$sysRename
	.p2align	2
	.type	Sys$sysRename,@function
Sys$sysRename:                          // @"Sys$sysRename"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x3, x1
	mov	x1, x0
	mov	w8, #38                         // =0x26
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, #-100                       // =0xffffffffffffff9c
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end200:
	.size	Sys$sysRename, .Lfunc_end200-Sys$sysRename
                                        // -- End function
	.globl	Sys$sysUnlink                   // -- Begin function Sys$sysUnlink
	.p2align	2
	.type	Sys$sysUnlink,@function
Sys$sysUnlink:                          // @"Sys$sysUnlink"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x1, x0
	mov	w8, #35                         // =0x23
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end201:
	.size	Sys$sysUnlink, .Lfunc_end201-Sys$sysUnlink
                                        // -- End function
	.globl	Sys$sysMkdir                    // -- Begin function Sys$sysMkdir
	.p2align	2
	.type	Sys$sysMkdir,@function
Sys$sysMkdir:                           // @"Sys$sysMkdir"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x2, x1
	mov	x1, x0
	mov	w8, #34                         // =0x22
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end202:
	.size	Sys$sysMkdir, .Lfunc_end202-Sys$sysMkdir
                                        // -- End function
	.globl	Sys$sysDirMode                  // -- Begin function Sys$sysDirMode
	.p2align	2
	.type	Sys$sysDirMode,@function
Sys$sysDirMode:                         // @"Sys$sysDirMode"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #493                        // =0x1ed
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end203:
	.size	Sys$sysDirMode, .Lfunc_end203-Sys$sysDirMode
                                        // -- End function
	.globl	Sys$sysRmdir                    // -- Begin function Sys$sysRmdir
	.p2align	2
	.type	Sys$sysRmdir,@function
Sys$sysRmdir:                           // @"Sys$sysRmdir"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x1, x0
	mov	w8, #35                         // =0x23
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #512                        // =0x200
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end204:
	.size	Sys$sysRmdir, .Lfunc_end204-Sys$sysRmdir
                                        // -- End function
	.globl	Sys$sysFileExists               // -- Begin function Sys$sysFileExists
	.p2align	2
	.type	Sys$sysFileExists,@function
Sys$sysFileExists:                      // @"Sys$sysFileExists"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB205_2
// %bb.1:                               // %label_6
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB205_2:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end205:
	.size	Sys$sysFileExists, .Lfunc_end205-Sys$sysFileExists
                                        // -- End function
	.globl	Sys$sysFileSize                 // -- Begin function Sys$sysFileSize
	.p2align	2
	.type	Sys$sysFileSize,@function
Sys$sysFileSize:                        // @"Sys$sysFileSize"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB206_2
// %bb.1:                               // %label_6
	mov	w8, #62                         // =0x3e
	mov	x1, xzr
	mov	w2, #2                          // =0x2
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x0
	//APP
	svc	#0
	//NO_APP
	mov	x6, x0
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x0, x6
.LBB206_2:                              // %label_7
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end206:
	.size	Sys$sysFileSize, .Lfunc_end206-Sys$sysFileSize
                                        // -- End function
	.globl	Sys$sysReadErrno                // -- Begin function Sys$sysReadErrno
	.p2align	2
	.type	Sys$sysReadErrno,@function
Sys$sysReadErrno:                       // @"Sys$sysReadErrno"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	mov	x1, x0
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x19, x0
	tbnz	x0, #63, .LBB207_8
// %bb.1:                               // %label_5
	mov	w0, #2                          // =0x2
	bl	axiom_alloc
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB207_4
// %bb.2:                               // %chk.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB207_4
// %bb.3:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB207_4:                              // %axiom_retain.exit.i
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x10, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x9, x0
	stp	x20, x20, [x0, #8]
	ubfx	x11, x10, #1, #14
	cmp	x11, #47
	csel	x8, x11, x8, lo
	mov	x11, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x11, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x10
	mov	w10, #1                         // =0x1
	stp	x8, x10, [x0, #-8]
	b.lt	.LBB207_7
// %bb.5:                               // %chk.i.i.i
	ldur	x8, [x9, #-16]
	cmn	x8, #1
	b.eq	.LBB207_7
// %bb.6:                               // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x9, #-16]
.LBB207_7:                              // %"Str$strAlloc.exit"
	mov	x0, x19
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	ldr	x1, [x9, #8]
	mov	w8, #63                         // =0x3f
	mov	w2, #1                          // =0x1
	//APP
	svc	#0
	//NO_APP
	mov	x10, x0
	mov	w8, #57                         // =0x39
	mov	x0, x19
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	neg	x8, x10
	mov	x0, x9
	and	x19, x8, x10, asr #63
	bl	axiom_release
	b	.LBB207_9
.LBB207_8:                              // %label_4
	neg	x19, x19
.LBB207_9:                              // %label_6
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end207:
	.size	Sys$sysReadErrno, .Lfunc_end207-Sys$sysReadErrno
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysIsDir                    // -- Begin function Sys$sysIsDir
	.p2align	2
	.type	Sys$sysIsDir,@function
Sys$sysIsDir:                           // @"Sys$sysIsDir"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	Sys$sysReadErrno
	cmp	x0, #21
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end208:
	.size	Sys$sysIsDir, .Lfunc_end208-Sys$sysIsDir
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysDirBufBytes              // -- Begin function Sys$sysDirBufBytes
	.p2align	2
	.type	Sys$sysDirBufBytes,@function
Sys$sysDirBufBytes:                     // @"Sys$sysDirBufBytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #32768                      // =0x8000
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end209:
	.size	Sys$sysDirBufBytes, .Lfunc_end209-Sys$sysDirBufBytes
                                        // -- End function
	.globl	Sys$sysReadDir                  // -- Begin function Sys$sysReadDir
	.p2align	2
	.type	Sys$sysReadDir,@function
Sys$sysReadDir:                         // @"Sys$sysReadDir"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x20, x0
	mov	w0, #32                         // =0x20
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x19, x0
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x0, #-8]
	mov	w0, #64                         // =0x40
	bl	axiom_alloc
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB210_3
// %bb.1:                               // %chk.i.i.i.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB210_3
// %bb.2:                               // %bump.i.i.i.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB210_3:                              // %axiom_retain.exit.i.i.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB210_6
// %bb.4:                               // %chk.i3.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB210_6
// %bb.5:                               // %bump.i8.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB210_6:                              // %"Vec$vecNew.exit"
	mov	w8, #8                          // =0x8
	stp	x0, xzr, [x19, #16]
	mov	x0, #-100                       // =0xffffffffffffff9c
	stp	xzr, x8, [x19]
	mov	w8, #56                         // =0x38
	mov	x1, x20
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB210_11
// %bb.7:                               // %label_6
	mov	x20, x0
	mov	w0, #32768                      // =0x8000
	bl	axiom_alloc
	mov	x21, x0
	mov	w0, #8                          // =0x8
	bl	axiom_alloc
	str	xzr, [x0]
	mov	w8, #61                         // =0x3d
	mov	x0, x20
	mov	x1, x21
	mov	w2, #32768                      // =0x8000
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #1
	b.lt	.LBB210_10
// %bb.8:                               // %label_28.i.preheader
	mov	x2, x0
.LBB210_9:                              // %label_28.i
                                        // =>This Inner Loop Header: Depth=1
	mov	x0, x21
	mov	x1, xzr
	mov	x3, x19
	bl	Sys$sysReadDirDecode
	mov	w8, #61                         // =0x3d
	mov	x0, x20
	mov	x1, x21
	mov	w2, #32768                      // =0x8000
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x2, x0
	cmp	x0, #0
	b.gt	.LBB210_9
.LBB210_10:                             // %"Sys$sysReadDirLoop.exit"
	mov	w8, #57                         // =0x39
	mov	x0, x20
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB210_11:                             // %label_7
	mov	x0, x19
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end210:
	.size	Sys$sysReadDir, .Lfunc_end210-Sys$sysReadDir
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysReadDirLoop              // -- Begin function Sys$sysReadDirLoop
	.p2align	2
	.type	Sys$sysReadDirLoop,@function
Sys$sysReadDirLoop:                     // @"Sys$sysReadDirLoop"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x19, x3
	mov	w8, #61                         // =0x3d
	mov	w2, #32768                      // =0x8000
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x20, x1
	mov	x21, x0
	//APP
	svc	#0
	//NO_APP
	mov	x2, x0
	cmp	x0, #1
	b.lt	.LBB211_2
.LBB211_1:                              // %label_28
                                        // =>This Inner Loop Header: Depth=1
	mov	x0, x20
	mov	x1, xzr
	mov	x3, x19
	bl	Sys$sysReadDirDecode
	mov	w8, #61                         // =0x3d
	mov	x0, x21
	mov	x1, x20
	mov	w2, #32768                      // =0x8000
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x2, x0
	cmp	x0, #0
	b.gt	.LBB211_1
.LBB211_2:                              // %label_29
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x2
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end211:
	.size	Sys$sysReadDirLoop, .Lfunc_end211-Sys$sysReadDirLoop
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysReadDirDecode            // -- Begin function Sys$sysReadDirDecode
	.p2align	2
	.type	Sys$sysReadDirDecode,@function
Sys$sysReadDirDecode:                   // @"Sys$sysReadDirDecode"
	.cfi_startproc
// %bb.0:
	add	x8, x1, #18
	cmp	x8, x2
	b.gt	.LBB212_10
// %bb.1:                               // %label_12.preheader
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	stp	x26, x25, [sp, #16]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	mov	x19, x3
	mov	x20, x2
	mov	x21, x1
	mov	x22, x0
	mov	w25, #47                        // =0x2f
	mov	x26, #-65536                    // =0xffffffffffff0000
	b	.LBB212_3
.LBB212_2:                              // %"Str$strFromLit.exit"
                                        //   in Loop: Header=BB212_3 Depth=1
	mov	x23, x0
	bl	Str$strDup
	mov	x24, x0
	mov	x0, x23
	bl	axiom_release
	mov	x0, x19
	mov	x1, x24
	mov	x2, xzr
	bl	Vec$vecPush
	add	x8, x21, #18
	cmp	x8, x20
	b.gt	.LBB212_9
.LBB212_3:                              // %label_12
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB212_5 Depth 2
	add	x8, x21, x22
	ldrh	w9, [x8, #16]
	add	x21, x9, x21
	cmp	x9, #20
	ccmp	x21, x20, #0, hs
	b.gt	.LBB212_9
// %bb.4:                               // %label_38
                                        //   in Loop: Header=BB212_3 Depth=1
	mov	x24, xzr
	add	x23, x8, #19
.LBB212_5:                              // %label_0.i.i
                                        //   Parent Loop BB212_3 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldrb	w8, [x23, x24]
	add	x24, x24, #1
	cbnz	w8, .LBB212_5
// %bb.6:                               // %"Str$cstrLen.exit.i"
                                        //   in Loop: Header=BB212_3 Depth=1
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	sub	x8, x24, #1
	stp	x23, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x10, x10, x25, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x10, x26, x10
	mvn	w10, w10
	and	x10, x10, #0x40000
	orr	x9, x10, x9
	stp	x9, x8, [x0, #-8]
	b.lt	.LBB212_2
// %bb.7:                               // %chk.i.i.i.i
                                        //   in Loop: Header=BB212_3 Depth=1
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB212_2
// %bb.8:                               // %bump.i.i.i.i
                                        //   in Loop: Header=BB212_3 Depth=1
	add	x8, x8, #1
	stur	x8, [x0, #-16]
	b	.LBB212_2
.LBB212_9:
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
.LBB212_10:                             // %label_13
	mov	x0, xzr
	ret
.Lfunc_end212:
	.size	Sys$sysReadDirDecode, .Lfunc_end212-Sys$sysReadDirDecode
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysGetCwd                   // -- Begin function Sys$sysGetCwd
	.p2align	2
	.type	Sys$sysGetCwd,@function
Sys$sysGetCwd:                          // @"Sys$sysGetCwd"
	.cfi_startproc
// %bb.0:                               // %label_6
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	mov	w0, #4097                       // =0x1001
	bl	axiom_alloc
	mov	x19, x0
	mov	w8, #17                         // =0x11
	mov	w1, #4096                       // =0x1000
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB213_7
// %bb.1:                               // %label_37
	mov	x20, xzr
.LBB213_2:                              // %label_0.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x19, x20]
	add	x20, x20, #1
	cbnz	w8, .LBB213_2
// %bb.3:                               // %"Str$cstrLen.exit.i"
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	stp	x19, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	sub	x9, x20, #1
	stp	x8, x9, [x0, #-8]
	b.lt	.LBB213_6
// %bb.4:                               // %chk.i.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB213_6
// %bb.5:                               // %bump.i.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB213_6:                              // %"Str$strFromLit.exit"
	mov	x19, x0
	bl	Str$strDup
	mov	x20, x0
	mov	x0, x19
	bl	axiom_release
	mov	x0, x20
	b	.LBB213_8
.LBB213_7:                              // %label_7
	adrp	x0, .Lstrhdr_4+16
	add	x0, x0, :lo12:.Lstrhdr_4+16
.LBB213_8:                              // %label_7
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end213:
	.size	Sys$sysGetCwd, .Lfunc_end213-Sys$sysGetCwd
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysEnvSlot                  // -- Begin function Sys$sysEnvSlot
	.p2align	2
	.type	Sys$sysEnvSlot,@function
Sys$sysEnvSlot:                         // @"Sys$sysEnvSlot"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, __axiom_argc
	adrp	x9, __axiom_argv
	mov	x29, sp
	ldr	x8, [x8, :lo12:__axiom_argc]
	ldr	x9, [x9, :lo12:__axiom_argv]
	add	x8, x9, x8, lsl #3
	add	x8, x8, x0, lsl #3
	ldr	x0, [x8, #8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end214:
	.size	Sys$sysEnvSlot, .Lfunc_end214-Sys$sysEnvSlot
                                        // -- End function
	.globl	Sys$sysEnvCount                 // -- Begin function Sys$sysEnvCount
	.p2align	2
	.type	Sys$sysEnvCount,@function
Sys$sysEnvCount:                        // @"Sys$sysEnvCount"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, __axiom_argc
	adrp	x9, __axiom_argv
	mov	x0, #-1                         // =0xffffffffffffffff
	ldr	x8, [x8, :lo12:__axiom_argc]
	ldr	x9, [x9, :lo12:__axiom_argv]
	mov	x29, sp
	add	x8, x9, x8, lsl #3
	add	x8, x8, #8
.LBB215_1:                              // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x9, [x8], #8
	add	x0, x0, #1
	cbnz	x9, .LBB215_1
// %bb.2:                               // %"Sys$sysEnvCountFrom.exit"
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end215:
	.size	Sys$sysEnvCount, .Lfunc_end215-Sys$sysEnvCount
                                        // -- End function
	.globl	Sys$sysEnvCountFrom             // -- Begin function Sys$sysEnvCountFrom
	.p2align	2
	.type	Sys$sysEnvCountFrom,@function
Sys$sysEnvCountFrom:                    // @"Sys$sysEnvCountFrom"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, __axiom_argc
	adrp	x9, __axiom_argv
	mov	x29, sp
	ldr	x8, [x8, :lo12:__axiom_argc]
	ldr	x9, [x9, :lo12:__axiom_argv]
	lsl	x8, x8, #3
	add	x8, x8, x0, lsl #3
	sub	x0, x0, #1
	add	x8, x8, x9
	add	x8, x8, #8
.LBB216_1:                              // %label_0
                                        // =>This Inner Loop Header: Depth=1
	ldr	x9, [x8], #8
	add	x0, x0, #1
	cbnz	x9, .LBB216_1
// %bb.2:                               // %label_7
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end216:
	.size	Sys$sysEnvCountFrom, .Lfunc_end216-Sys$sysEnvCountFrom
                                        // -- End function
	.globl	Sys$sysEnv                      // -- Begin function Sys$sysEnv
	.p2align	2
	.type	Sys$sysEnv,@function
Sys$sysEnv:                             // @"Sys$sysEnv"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	adrp	x19, .Lstrhdr_5+16
	add	x19, x19, :lo12:.Lstrhdr_5+16
	mov	x1, x19
	bl	Str$strConcat
	mov	x20, x0
	mov	x0, x19
	bl	axiom_release
	mov	x0, x20
	mov	x1, xzr
	bl	Sys$sysEnvLookup
	mov	x19, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end217:
	.size	Sys$sysEnv, .Lfunc_end217-Sys$sysEnv
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysEnvLookup                // -- Begin function Sys$sysEnvLookup
	.p2align	2
	.type	Sys$sysEnvLookup,@function
Sys$sysEnvLookup:                       // @"Sys$sysEnvLookup"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-96]!           // 16-byte Folded Spill
	str	x27, [sp, #16]                  // 8-byte Spill
	stp	x26, x25, [sp, #32]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #48]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #64]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #80]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 96
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w27, -80
	.cfi_offset w30, -88
	.cfi_offset w29, -96
	mov	x19, x0
	cmp	x0, #1, lsl #12                 // =4096
	mov	x21, x1
	b.lt	.LBB218_3
// %bb.1:                               // %chk.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB218_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB218_3:                              // %axiom_retain.exit
	adrp	x22, __axiom_argc
	adrp	x23, __axiom_argv
	ldr	x8, [x22, :lo12:__axiom_argc]
	ldr	x9, [x23, :lo12:__axiom_argv]
	add	x8, x9, x8, lsl #3
	add	x8, x8, x21, lsl #3
	ldr	x26, [x8, #8]
	cbz	x26, .LBB218_17
// %bb.4:                               // %label_9.lr.ph
	mov	w24, #47                        // =0x2f
	mov	x25, #-65536                    // =0xffffffffffff0000
	adrp	x20, .Lstrhdr_4+16
	add	x20, x20, :lo12:.Lstrhdr_4+16
	b	.LBB218_7
.LBB218_5:                              // %"Mem$memCmp.exit.loopexit.i"
                                        //   in Loop: Header=BB218_7 Depth=1
	cmp	w13, w14
	b.eq	.LBB218_18
.LBB218_6:                              // %label_17
                                        //   in Loop: Header=BB218_7 Depth=1
	add	x21, x21, #1
	bl	axiom_release
	ldr	x8, [x22, :lo12:__axiom_argc]
	ldr	x9, [x23, :lo12:__axiom_argv]
	add	x8, x9, x8, lsl #3
	add	x8, x8, x21, lsl #3
	ldr	x26, [x8, #8]
	cbz	x26, .LBB218_25
.LBB218_7:                              // %label_9
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB218_8 Depth 2
                                        //     Child Loop BB218_15 Depth 2
	mov	x27, xzr
.LBB218_8:                              // %label_0.i.i
                                        //   Parent Loop BB218_7 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldrb	w8, [x26, x27]
	add	x27, x27, #1
	cbnz	w8, .LBB218_8
// %bb.9:                               // %"Str$cstrLen.exit.i"
                                        //   in Loop: Header=BB218_7 Depth=1
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	sub	x8, x27, #1
	stp	x26, xzr, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x10, x10, x24, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x10, x25, x10
	mvn	w10, w10
	and	x10, x10, #0x40000
	orr	x9, x10, x9
	stp	x9, x8, [x0, #-8]
	b.lt	.LBB218_12
// %bb.10:                              // %chk.i.i.i.i
                                        //   in Loop: Header=BB218_7 Depth=1
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB218_12
// %bb.11:                              // %bump.i.i.i.i
                                        //   in Loop: Header=BB218_7 Depth=1
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB218_12:                             // %"Str$strFromLit.exit"
                                        //   in Loop: Header=BB218_7 Depth=1
	ldr	x9, [x19]
	ldr	x8, [x0]
	cmp	x8, x9
	b.lt	.LBB218_6
// %bb.13:                              // %label_6.i
                                        //   in Loop: Header=BB218_7 Depth=1
	cmp	x9, #1
	b.lt	.LBB218_18
// %bb.14:                              // %label_3.lr.ph.i.i.i
                                        //   in Loop: Header=BB218_7 Depth=1
	ldr	x10, [x19, #8]
	ldr	x11, [x0, #8]
	mov	x12, xzr
.LBB218_15:                             // %label_3.i.i.i
                                        //   Parent Loop BB218_7 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldrb	w13, [x11, x12]
	ldrb	w14, [x10, x12]
	add	x12, x12, #1
	cmp	x12, x9
	b.ge	.LBB218_5
// %bb.16:                              // %label_3.i.i.i
                                        //   in Loop: Header=BB218_15 Depth=2
	cmp	w13, w14
	b.eq	.LBB218_15
	b	.LBB218_5
.LBB218_17:
	adrp	x20, .Lstrhdr_4+16
	add	x20, x20, :lo12:.Lstrhdr_4+16
	b	.LBB218_25
.LBB218_18:                             // %label_16
	subs	x10, x8, x9
	ldr	x22, [x0, #16]
	csel	x11, x9, x8, gt
	cmp	x9, #0
	csel	x9, xzr, x11, mi
	sub	x8, x8, x9
	cmp	x10, x8
	csel	x8, x10, x8, lt
	cmp	x10, #0
	csel	x23, xzr, x8, mi
	cmp	x22, #1, lsl #12                // =4096
	b.lt	.LBB218_21
// %bb.19:                              // %chk.i.i
	ldur	x8, [x22, #-16]
	cmn	x8, #1
	b.eq	.LBB218_21
// %bb.20:                              // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x22, #-16]
.LBB218_21:                             // %axiom_retain.exit.i
	ldr	x8, [x0, #8]
	mov	x21, x0
	mov	w0, #24                         // =0x18
	add	x24, x8, x9
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x20, x0
	stp	x24, x22, [x0, #8]
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stp	x8, x23, [x0, #-8]
	b.lt	.LBB218_24
// %bb.22:                              // %chk.i.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB218_24
// %bb.23:                              // %bump.i.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB218_24:                             // %"Str$strSlice.exit"
	mov	x0, x21
	bl	axiom_release
.LBB218_25:                             // %label_10
	mov	x0, x19
	bl	axiom_release
	mov	x0, x20
	ldp	x20, x19, [sp, #80]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #64]             // 16-byte Folded Reload
	ldr	x27, [sp, #16]                  // 8-byte Reload
	ldp	x24, x23, [sp, #48]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #96             // 16-byte Folded Reload
	ret
.Lfunc_end218:
	.size	Sys$sysEnvLookup, .Lfunc_end218-Sys$sysEnvLookup
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysEnvp                     // -- Begin function Sys$sysEnvp
	.p2align	2
	.type	Sys$sysEnvp,@function
Sys$sysEnvp:                            // @"Sys$sysEnvp"
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	adrp	x19, __axiom_argc
	adrp	x20, __axiom_argv
	ldr	x8, [x19, :lo12:__axiom_argc]
	ldr	x9, [x20, :lo12:__axiom_argv]
	str	x21, [sp, #16]                  // 8-byte Spill
	mov	x0, xzr
	mov	x21, #-1                        // =0xffffffffffffffff
	mov	x29, sp
	add	x8, x9, x8, lsl #3
	add	x8, x8, #8
.LBB219_1:                              // %label_0.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x9, [x8, x0]
	add	x21, x21, #1
	add	x0, x0, #8
	cbnz	x9, .LBB219_1
// %bb.2:                               // %"Sys$sysEnvCount.exit"
	bl	axiom_alloc
	cmp	x21, #1
	b.lt	.LBB219_5
// %bb.3:                               // %label_10.lr.ph.i
	mov	x8, xzr
.LBB219_4:                              // %label_10.i
                                        // =>This Inner Loop Header: Depth=1
	ldr	x9, [x19, :lo12:__axiom_argc]
	ldr	x10, [x20, :lo12:__axiom_argv]
	add	x9, x10, x9, lsl #3
	lsl	x10, x8, #3
	add	x8, x8, #1
	cmp	x21, x8
	add	x9, x9, x10
	ldr	x9, [x9, #8]
	str	x9, [x0, x10]
	b.ne	.LBB219_4
.LBB219_5:                              // %"Sys$sysEnvpFill.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	str	xzr, [x0, x21, lsl #3]
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end219:
	.size	Sys$sysEnvp, .Lfunc_end219-Sys$sysEnvp
                                        // -- End function
	.globl	Sys$sysEnvpFill                 // -- Begin function Sys$sysEnvpFill
	.p2align	2
	.type	Sys$sysEnvpFill,@function
Sys$sysEnvpFill:                        // @"Sys$sysEnvpFill"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	subs	x8, x2, x1
	mov	x29, sp
	b.le	.LBB220_3
// %bb.1:                               // %label_10.lr.ph
	lsl	x10, x1, #3
	adrp	x11, __axiom_argc
	adrp	x12, __axiom_argv
	add	x9, x0, x10
	add	x10, x10, #8
.LBB220_2:                              // %label_10
                                        // =>This Inner Loop Header: Depth=1
	ldr	x13, [x11, :lo12:__axiom_argc]
	ldr	x14, [x12, :lo12:__axiom_argv]
	subs	x8, x8, #1
	add	x13, x14, x13, lsl #3
	ldr	x13, [x13, x10]
	add	x10, x10, #8
	str	x13, [x9], #8
	b.ne	.LBB220_2
.LBB220_3:                              // %label_9
	str	xzr, [x0, x2, lsl #3]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end220:
	.size	Sys$sysEnvpFill, .Lfunc_end220-Sys$sysEnvpFill
                                        // -- End function
	.globl	Sys$sysSpawn                    // -- Begin function Sys$sysSpawn
	.p2align	2
	.type	Sys$sysSpawn,@function
Sys$sysSpawn:                           // @"Sys$sysSpawn"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x11, x0
	mov	x9, x2
	mov	x10, x1
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x1, x11
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	cmn	x0, #2
	b.eq	.LBB221_4
// %bb.1:                               // %label_26
	tbnz	x0, #63, .LBB221_3
// %bb.2:                               // %label_31
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB221_3:                              // %label_33
	mov	w8, #220                        // =0xdc
	mov	w0, #17                         // =0x11
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cbz	x0, .LBB221_5
.LBB221_4:                              // %label_6
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB221_5:                              // %label_46
	mov	w8, #221                        // =0xdd
	mov	x0, x11
	mov	x1, x10
	mov	x2, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	w8, #94                         // =0x5e
	mov	w0, #127                        // =0x7f
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end221:
	.size	Sys$sysSpawn, .Lfunc_end221-Sys$sysSpawn
                                        // -- End function
	.globl	Sys$sysWaitPid                  // -- Begin function Sys$sysWaitPid
	.p2align	2
	.type	Sys$sysWaitPid,@function
Sys$sysWaitPid:                         // @"Sys$sysWaitPid"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x19, x0
	mov	w0, #8                          // =0x8
	mov	x29, sp
	bl	axiom_alloc
	mov	x9, x0
	str	xzr, [x0]
	mov	w8, #260                        // =0x104
	mov	x0, x19
	mov	x2, xzr
	mov	x1, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB222_2
// %bb.1:                               // %label_8
	ldr	x0, [x9]
.LBB222_2:                              // %label_9
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end222:
	.size	Sys$sysWaitPid, .Lfunc_end222-Sys$sysWaitPid
                                        // -- End function
	.globl	Sys$sysExitCode                 // -- Begin function Sys$sysExitCode
	.p2align	2
	.type	Sys$sysExitCode,@function
Sys$sysExitCode:                        // @"Sys$sysExitCode"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	ubfx	x0, x0, #8, #8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end223:
	.size	Sys$sysExitCode, .Lfunc_end223-Sys$sysExitCode
                                        // -- End function
	.globl	Sys$sysTermSignal               // -- Begin function Sys$sysTermSignal
	.p2align	2
	.type	Sys$sysTermSignal,@function
Sys$sysTermSignal:                      // @"Sys$sysTermSignal"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	and	x0, x0, #0x7f
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end224:
	.size	Sys$sysTermSignal, .Lfunc_end224-Sys$sysTermSignal
                                        // -- End function
	.globl	Sys$sysRun                      // -- Begin function Sys$sysRun
	.p2align	2
	.type	Sys$sysRun,@function
Sys$sysRun:                             // @"Sys$sysRun"
// %bb.0:
	mov	x11, x0
	mov	x9, x2
	mov	x10, x1
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x1, x11
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmn	x0, #2
	b.eq	.LBB225_4
// %bb.1:                               // %label_26.i
	tbnz	x0, #63, .LBB225_3
// %bb.2:                               // %label_31.i
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB225_3:                              // %label_33.i
	mov	w8, #220                        // =0xdc
	mov	w0, #17                         // =0x11
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cbz	x0, .LBB225_10
.LBB225_4:                              // %"Sys$sysSpawn.exit"
	tbnz	x0, #63, .LBB225_11
.LBB225_5:                              // %label_5
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x19, x0
	mov	w0, #8                          // =0x8
	mov	x29, sp
	bl	axiom_alloc
	mov	x9, x0
	str	xzr, [x0]
	mov	w8, #260                        // =0x104
	mov	x0, x19
	mov	x2, xzr
	mov	x1, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB225_7
// %bb.6:                               // %label_8.i
	ldr	x0, [x9]
.LBB225_7:                              // %"Sys$sysWaitPid.exit"
	ldr	x19, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	tbnz	x0, #63, .LBB225_11
// %bb.8:                               // %label_12
	ands	x8, x0, #0x7f
	b.eq	.LBB225_12
// %bb.9:                               // %label_18
	orr	x0, x8, #0x80
	ret
.LBB225_10:                             // %label_46.i
	mov	w8, #221                        // =0xdd
	mov	x0, x11
	mov	x1, x10
	mov	x2, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	w8, #94                         // =0x5e
	mov	w0, #127                        // =0x7f
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x0, xzr
	tbz	x0, #63, .LBB225_5
.LBB225_11:                             // %label_6
	ret
.LBB225_12:                             // %label_19
	ubfx	x0, x0, #8, #8
	ret
.Lfunc_end225:
	.size	Sys$sysRun, .Lfunc_end225-Sys$sysRun
                                        // -- End function
	.globl	Sys$sysRunPath                  // -- Begin function Sys$sysRunPath
	.p2align	2
	.type	Sys$sysRunPath,@function
Sys$sysRunPath:                         // @"Sys$sysRunPath"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	stp	x24, x23, [sp, #16]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 64
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w30, -56
	.cfi_offset w29, -64
	mov	x19, x2
	mov	x21, x0
	cmp	x0, #1, lsl #12                 // =4096
	mov	x20, x1
	b.lt	.LBB226_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB226_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB226_3:                              // %axiom_retain.exit.i
	ldr	x8, [x21]
	cmp	x8, #1
	b.lt	.LBB226_10
// %bb.4:                               // %label_11.lr.ph.i
	ldr	x9, [x21, #8]
	mov	x22, xzr
.LBB226_5:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w10, [x9, x22]
	cmp	w10, #47
	b.eq	.LBB226_8
// %bb.6:                               // %label_22.i
                                        //   in Loop: Header=BB226_5 Depth=1
	add	x22, x22, #1
	cmp	x8, x22
	b.ne	.LBB226_5
// %bb.7:
	mov	x22, #-1                        // =0xffffffffffffffff
.LBB226_8:                              // %"Str$strFindByte.exit.loopexit"
	mov	x0, x21
	bl	axiom_release
	tbnz	x22, #63, .LBB226_11
// %bb.9:                               // %label_4
	mov	x0, x21
	bl	Str$strDup
	mov	x1, x20
	mov	x2, x19
	ldr	x0, [x0, #8]
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	b	Sys$sysRun
.LBB226_10:                             // %label_5.critedge
	mov	x0, x21
	bl	axiom_release
.LBB226_11:                             // %label_5
	adrp	x23, .Lstrhdr_6+16
	add	x23, x23, :lo12:.Lstrhdr_6+16
	adrp	x22, .Lstrhdr_5+16
	add	x22, x22, :lo12:.Lstrhdr_5+16
	mov	x0, x23
	mov	x1, x22
	bl	Str$strConcat
	mov	x24, x0
	mov	x0, x22
	bl	axiom_release
	mov	x0, x24
	mov	x1, xzr
	bl	Sys$sysEnvLookup
	mov	x22, x0
	mov	x0, x24
	bl	axiom_release
	mov	x0, x23
	bl	axiom_release
	ldr	x8, [x22]
	cbz	x8, .LBB226_13
// %bb.12:                              // %label_17
	mov	x0, x21
	mov	x1, x20
	mov	x2, x19
	mov	x3, x22
	mov	x4, xzr
	bl	Sys$sysRunSearch
	mov	x19, x0
	b	.LBB226_14
.LBB226_13:
	mov	x19, #-2                        // =0xfffffffffffffffe
.LBB226_14:                             // %label_18
	mov	x0, x22
	bl	axiom_release
	mov	x0, x19
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end226:
	.size	Sys$sysRunPath, .Lfunc_end226-Sys$sysRunPath
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysRunSearch                // -- Begin function Sys$sysRunSearch
	.p2align	2
	.type	Sys$sysRunSearch,@function
Sys$sysRunSearch:                       // @"Sys$sysRunSearch"
	.cfi_startproc
// %bb.0:
	sub	sp, sp, #112
	stp	x29, x30, [sp, #16]             // 16-byte Folded Spill
	stp	x28, x27, [sp, #32]             // 16-byte Folded Spill
	stp	x26, x25, [sp, #48]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #64]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #80]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #96]             // 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 96
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w27, -72
	.cfi_offset w28, -80
	.cfi_offset w30, -88
	.cfi_offset w29, -96
	mov	x25, x4
	mov	x19, x3
	mov	x20, x0
	cmp	x0, #1, lsl #12                 // =4096
	stp	x1, x2, [sp]                    // 16-byte Folded Spill
	b.lt	.LBB227_3
// %bb.1:                               // %chk.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB227_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB227_3:                              // %axiom_retain.exit
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB227_6
// %bb.4:                               // %chk.i28
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB227_6
// %bb.5:                               // %bump.i33
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB227_6:                              // %axiom_retain.exit35
	ldr	x8, [x19]
	cmp	x25, x8
	b.ge	.LBB227_31
// %bb.7:                               // %label_13.lr.ph
	mov	w27, #47                        // =0x2f
	mov	x28, #-65536                    // =0xffffffffffff0000
	adrp	x23, .Lstrhdr_7+16
	add	x23, x23, :lo12:.Lstrhdr_7+16
	b	.LBB227_10
.LBB227_8:                              //   in Loop: Header=BB227_10 Depth=1
	mov	x22, x25
.LBB227_9:                              // %label_0.backedge
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	x0, x22
	bl	axiom_release
	ldr	x8, [x19]
	add	x25, x24, #1
	cmp	x25, x8
	b.ge	.LBB227_31
.LBB227_10:                             // %label_13
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB227_16 Depth 2
	cmp	x19, #1, lsl #12                // =4096
	b.lt	.LBB227_13
// %bb.11:                              // %chk.i.i
                                        //   in Loop: Header=BB227_10 Depth=1
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB227_13
// %bb.12:                              // %bump.i.i
                                        //   in Loop: Header=BB227_10 Depth=1
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB227_13:                             // %axiom_retain.exit.i
                                        //   in Loop: Header=BB227_10 Depth=1
	ldr	x8, [x19]
	cmp	x25, x8
	b.ge	.LBB227_18
// %bb.14:                              // %label_11.i.preheader
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	x24, x25
	b	.LBB227_16
.LBB227_15:                             // %label_22.i
                                        //   in Loop: Header=BB227_16 Depth=2
	add	x24, x24, #1
	cmp	x8, x24
	b.eq	.LBB227_18
.LBB227_16:                             // %label_11.i
                                        //   Parent Loop BB227_10 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	tbnz	x24, #63, .LBB227_15
// %bb.17:                              // %label_11.i.i
                                        //   in Loop: Header=BB227_16 Depth=2
	ldr	x9, [x19, #8]
	ldrb	w9, [x9, x24]
	cmp	w9, #58
	b.ne	.LBB227_15
	b	.LBB227_19
.LBB227_18:                             //   in Loop: Header=BB227_10 Depth=1
	mov	x24, #-1                        // =0xffffffffffffffff
.LBB227_19:                             // %"Str$strFindByte.exit"
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	x0, x19
	bl	axiom_release
	tbz	x24, #63, .LBB227_21
// %bb.20:                              // %label_22
                                        //   in Loop: Header=BB227_10 Depth=1
	ldr	x24, [x19]
.LBB227_21:                             // %label_24
                                        //   in Loop: Header=BB227_10 Depth=1
	ldr	x9, [x19]
	sub	x10, x24, x25
	ldr	x22, [x19, #16]
	cmp	x25, x9
	csel	x8, x25, x9, lt
	cmp	x25, #0
	csel	x8, xzr, x8, mi
	sub	x9, x9, x8
	cmp	x10, x9
	csel	x9, x10, x9, lt
	cmp	x10, #0
	csel	x26, xzr, x9, mi
	cmp	x22, #1, lsl #12                // =4096
	b.lt	.LBB227_24
// %bb.22:                              // %chk.i.i42
                                        //   in Loop: Header=BB227_10 Depth=1
	ldur	x9, [x22, #-16]
	cmn	x9, #1
	b.eq	.LBB227_24
// %bb.23:                              // %bump.i.i47
                                        //   in Loop: Header=BB227_10 Depth=1
	add	x9, x9, #1
	stur	x9, [x22, #-16]
.LBB227_24:                             // %axiom_retain.exit.i49
                                        //   in Loop: Header=BB227_10 Depth=1
	ldr	x9, [x19, #8]
	mov	w0, #24                         // =0x18
	add	x21, x9, x8
	bl	axiom_alloc
	ldur	x8, [x0, #-8]
	mov	x25, x0
	stp	x21, x22, [x0, #8]
	ubfx	x9, x8, #1, #14
	cmp	x9, #47
	csel	x9, x9, x27, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x9, x28, x9
	mvn	w9, w9
	and	x9, x9, #0x40000
	orr	x8, x9, x8
	stp	x8, x26, [x0, #-8]
	b.lt	.LBB227_27
// %bb.25:                              // %chk.i.i.i
                                        //   in Loop: Header=BB227_10 Depth=1
	ldur	x8, [x25, #-16]
	cmn	x8, #1
	b.eq	.LBB227_27
// %bb.26:                              // %bump.i.i.i
                                        //   in Loop: Header=BB227_10 Depth=1
	add	x8, x8, #1
	stur	x8, [x25, #-16]
.LBB227_27:                             // %"Str$strSlice.exit"
                                        //   in Loop: Header=BB227_10 Depth=1
	ldr	x8, [x25]
	cbz	x8, .LBB227_8
// %bb.28:                              // %label_38
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	x0, x25
	mov	x1, x23
	bl	Str$strConcat
	mov	x26, x0
	mov	x0, x23
	bl	axiom_release
	mov	x0, x26
	mov	x1, x20
	bl	Str$strConcat
	mov	x22, x0
	mov	x0, x26
	bl	axiom_release
	ldr	x9, [x22, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x1, x9
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB227_30
// %bb.29:                              // %label_58
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x1, x2, [sp]                    // 16-byte Folded Reload
	mov	x0, x9
	bl	Sys$sysRun
	tbz	x0, #63, .LBB227_33
.LBB227_30:                             // %label_0.backedge.sink.split
                                        //   in Loop: Header=BB227_10 Depth=1
	mov	x0, x25
	bl	axiom_release
	b	.LBB227_9
.LBB227_31:
	mov	x21, #-2                        // =0xfffffffffffffffe
.LBB227_32:                             // %label_14
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	mov	x0, x21
	ldp	x20, x19, [sp, #96]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #80]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #64]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #48]             // 16-byte Folded Reload
	ldp	x28, x27, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp, #16]             // 16-byte Folded Reload
	add	sp, sp, #112
	ret
.LBB227_33:                             // %label_59
	mov	x21, x0
	mov	x0, x22
	bl	axiom_release
	mov	x0, x25
	bl	axiom_release
	b	.LBB227_32
.Lfunc_end227:
	.size	Sys$sysRunSearch, .Lfunc_end227-Sys$sysRunSearch
	.cfi_endproc
                                        // -- End function
	.globl	Sys$sysGetPid                   // -- Begin function Sys$sysGetPid
	.p2align	2
	.type	Sys$sysGetPid,@function
Sys$sysGetPid:                          // @"Sys$sysGetPid"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #172                        // =0xac
	mov	x0, xzr
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end228:
	.size	Sys$sysGetPid, .Lfunc_end228-Sys$sysGetPid
                                        // -- End function
	.globl	Sys$sysNowMicros                // -- Begin function Sys$sysNowMicros
	.p2align	2
	.type	Sys$sysNowMicros,@function
Sys$sysNowMicros:                       // @"Sys$sysNowMicros"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	w8, #113                        // =0x71
	mov	w0, #1                          // =0x1
	mov	x2, xzr
	mov	x1, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB229_2
// %bb.1:                               // %label_27
	mov	x10, #63439                     // =0xf7cf
	ldp	x9, x8, [x9]
	movk	x10, #58195, lsl #16
	mov	w11, #16960                     // =0x4240
	movk	x10, #39845, lsl #32
	movk	w11, #15, lsl #16
	movk	x10, #8388, lsl #48
	smulh	x8, x8, x10
	asr	x10, x8, #7
	add	x8, x10, x8, lsr #63
	madd	x0, x9, x11, x8
.LBB229_2:                              // %label_6
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end229:
	.size	Sys$sysNowMicros, .Lfunc_end229-Sys$sysNowMicros
                                        // -- End function
	.globl	Sys$sysNowMonotonic             // -- Begin function Sys$sysNowMonotonic
	.p2align	2
	.type	Sys$sysNowMonotonic,@function
Sys$sysNowMonotonic:                    // @"Sys$sysNowMonotonic"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	w8, #113                        // =0x71
	mov	w0, #1                          // =0x1
	mov	x2, xzr
	mov	x1, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB230_2
// %bb.1:                               // %label_14
	mov	x10, #63439                     // =0xf7cf
	ldp	x9, x8, [x9]
	movk	x10, #58195, lsl #16
	mov	w11, #16960                     // =0x4240
	movk	x10, #39845, lsl #32
	movk	w11, #15, lsl #16
	movk	x10, #8388, lsl #48
	smulh	x8, x8, x10
	asr	x10, x8, #7
	add	x8, x10, x8, lsr #63
	madd	x0, x9, x11, x8
.LBB230_2:                              // %label_6
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end230:
	.size	Sys$sysNowMonotonic, .Lfunc_end230-Sys$sysNowMonotonic
                                        // -- End function
	.globl	Sys$netSocketTcp                // -- Begin function Sys$netSocketTcp
	.p2align	2
	.type	Sys$netSocketTcp,@function
Sys$netSocketTcp:                       // @"Sys$netSocketTcp"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #198                        // =0xc6
	mov	w0, #2                          // =0x2
	mov	w1, #1                          // =0x1
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end231:
	.size	Sys$netSocketTcp, .Lfunc_end231-Sys$netSocketTcp
                                        // -- End function
	.globl	Sys$netSocketTcp6               // -- Begin function Sys$netSocketTcp6
	.p2align	2
	.type	Sys$netSocketTcp6,@function
Sys$netSocketTcp6:                      // @"Sys$netSocketTcp6"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #198                        // =0xc6
	mov	w0, #10                         // =0xa
	mov	w1, #1                          // =0x1
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end232:
	.size	Sys$netSocketTcp6, .Lfunc_end232-Sys$netSocketTcp6
                                        // -- End function
	.globl	Sys$netAddr4Bytes               // -- Begin function Sys$netAddr4Bytes
	.p2align	2
	.type	Sys$netAddr4Bytes,@function
Sys$netAddr4Bytes:                      // @"Sys$netAddr4Bytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #16                         // =0x10
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end233:
	.size	Sys$netAddr4Bytes, .Lfunc_end233-Sys$netAddr4Bytes
                                        // -- End function
	.globl	Sys$netAddr6Bytes               // -- Begin function Sys$netAddr6Bytes
	.p2align	2
	.type	Sys$netAddr6Bytes,@function
Sys$netAddr6Bytes:                      // @"Sys$netAddr6Bytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #28                         // =0x1c
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end234:
	.size	Sys$netAddr6Bytes, .Lfunc_end234-Sys$netAddr6Bytes
                                        // -- End function
	.globl	Sys$netAddrMaxBytes             // -- Begin function Sys$netAddrMaxBytes
	.p2align	2
	.type	Sys$netAddrMaxBytes,@function
Sys$netAddrMaxBytes:                    // @"Sys$netAddrMaxBytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	w0, #28                         // =0x1c
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end235:
	.size	Sys$netAddrMaxBytes, .Lfunc_end235-Sys$netAddrMaxBytes
                                        // -- End function
	.globl	Sys$netAddr4                    // -- Begin function Sys$netAddr4
	.p2align	2
	.type	Sys$netAddr4,@function
Sys$netAddr4:                           // @"Sys$netAddr4"
// %bb.0:                               // %label_6
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #2                          // =0x2
	mov	x29, sp
	str	xzr, [x0, #8]
	strh	w8, [x0]
	lsr	x8, x1, #8
	strb	w1, [x0, #3]
	strb	w8, [x0, #2]
	strb	w2, [x0, #4]
	strb	w3, [x0, #5]
	strb	w4, [x0, #6]
	strb	w5, [x0, #7]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end236:
	.size	Sys$netAddr4, .Lfunc_end236-Sys$netAddr4
                                        // -- End function
	.globl	Sys$netAddr6                    // -- Begin function Sys$netAddr6
	.p2align	2
	.type	Sys$netAddr6,@function
Sys$netAddr6:                           // @"Sys$netAddr6"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #10                         // =0xa
	sturh	wzr, [x0, #13]
	lsr	x9, x1, #8
	strh	w8, [x0]
	lsr	x8, x2, #8
	mov	x29, sp
	stur	xzr, [x0, #15]
	ldr	x10, [x29, #24]
	strb	w8, [x0, #8]
	lsr	x8, x3, #8
	strb	w9, [x0, #2]
	ldr	x9, [x29, #16]
	strb	w8, [x0, #10]
	lsr	x8, x4, #8
	str	wzr, [x0, #4]
	strb	w8, [x0, #12]
	lsr	x8, x5, #8
	str	wzr, [x0, #24]
	strb	w8, [x0, #14]
	lsr	x8, x6, #8
	strb	w1, [x0, #3]
	strb	w8, [x0, #16]
	lsr	x8, x7, #8
	strb	w2, [x0, #9]
	strb	w8, [x0, #18]
	lsr	x8, x9, #8
	strb	w3, [x0, #11]
	strb	w8, [x0, #20]
	lsr	x8, x10, #8
	strb	w4, [x0, #13]
	strb	w5, [x0, #15]
	strb	w6, [x0, #17]
	strb	w7, [x0, #19]
	strb	w9, [x0, #21]
	strb	w8, [x0, #22]
	strb	w10, [x0, #23]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end237:
	.size	Sys$netAddr6, .Lfunc_end237-Sys$netAddr6
                                        // -- End function
	.globl	Sys$netPutGroup                 // -- Begin function Sys$netPutGroup
	.p2align	2
	.type	Sys$netPutGroup,@function
Sys$netPutGroup:                        // @"Sys$netPutGroup"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	rev	w8, w2
	add	x9, x0, x1, lsl #1
	mov	x29, sp
	lsr	w8, w8, #16
	strh	w8, [x9, #8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end238:
	.size	Sys$netPutGroup, .Lfunc_end238-Sys$netPutGroup
                                        // -- End function
	.globl	Sys$netGetGroup                 // -- Begin function Sys$netGetGroup
	.p2align	2
	.type	Sys$netGetGroup,@function
Sys$netGetGroup:                        // @"Sys$netGetGroup"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x1, lsl #1
	mov	x29, sp
	ldrh	w8, [x8, #8]
	rev16	w0, w8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end239:
	.size	Sys$netGetGroup, .Lfunc_end239-Sys$netGetGroup
                                        // -- End function
	.globl	Sys$netAddrFamily               // -- Begin function Sys$netAddrFamily
	.p2align	2
	.type	Sys$netAddrFamily,@function
Sys$netAddrFamily:                      // @"Sys$netAddrFamily"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrh	w0, [x0]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end240:
	.size	Sys$netAddrFamily, .Lfunc_end240-Sys$netAddrFamily
                                        // -- End function
	.globl	Sys$netAddrPort                 // -- Begin function Sys$netAddrPort
	.p2align	2
	.type	Sys$netAddrPort,@function
Sys$netAddrPort:                        // @"Sys$netAddrPort"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrh	w8, [x0, #2]
	mov	x29, sp
	rev16	w0, w8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end241:
	.size	Sys$netAddrPort, .Lfunc_end241-Sys$netAddrPort
                                        // -- End function
	.globl	Sys$netAddrSize                 // -- Begin function Sys$netAddrSize
	.p2align	2
	.type	Sys$netAddrSize,@function
Sys$netAddrSize:                        // @"Sys$netAddrSize"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrh	w9, [x0]
	mov	w8, #16                         // =0x10
	mov	x29, sp
	cmp	x9, #10
	mov	w9, #28                         // =0x1c
	csel	x0, x9, x8, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end242:
	.size	Sys$netAddrSize, .Lfunc_end242-Sys$netAddrSize
                                        // -- End function
	.globl	Sys$netBind                     // -- Begin function Sys$netBind
	.p2align	2
	.type	Sys$netBind,@function
Sys$netBind:                            // @"Sys$netBind"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrh	w8, [x1]
	mov	w9, #16                         // =0x10
	mov	w10, #28                        // =0x1c
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	cmp	x8, #10
	mov	w8, #200                        // =0xc8
	mov	x29, sp
	csel	x2, x10, x9, eq
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end243:
	.size	Sys$netBind, .Lfunc_end243-Sys$netBind
                                        // -- End function
	.globl	Sys$netListen                   // -- Begin function Sys$netListen
	.p2align	2
	.type	Sys$netListen,@function
Sys$netListen:                          // @"Sys$netListen"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #201                        // =0xc9
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end244:
	.size	Sys$netListen, .Lfunc_end244-Sys$netListen
                                        // -- End function
	.globl	Sys$netAccept                   // -- Begin function Sys$netAccept
	.p2align	2
	.type	Sys$netAccept,@function
Sys$netAccept:                          // @"Sys$netAccept"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #242                        // =0xf2
	mov	x1, xzr
	mov	x2, xzr
	mov	w3, #2048                       // =0x800
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end245:
	.size	Sys$netAccept, .Lfunc_end245-Sys$netAccept
                                        // -- End function
	.globl	Sys$netAcceptFinish             // -- Begin function Sys$netAcceptFinish
	.p2align	2
	.type	Sys$netAcceptFinish,@function
Sys$netAcceptFinish:                    // @"Sys$netAcceptFinish"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end246:
	.size	Sys$netAcceptFinish, .Lfunc_end246-Sys$netAcceptFinish
                                        // -- End function
	.globl	Sys$netAcceptFrom               // -- Begin function Sys$netAcceptFrom
	.p2align	2
	.type	Sys$netAcceptFrom,@function
Sys$netAcceptFrom:                      // @"Sys$netAcceptFrom"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x11, x3
	mov	x9, x2
	mov	x10, x1
	cmp	x2, #1
	mov	x29, sp
	b.lt	.LBB247_3
// %bb.1:                               // %label_2.lr.ph.i.i
	mov	x8, x10
	mov	x12, x9
.LBB247_2:                              // %label_2.i.i
                                        // =>This Inner Loop Header: Depth=1
	subs	x12, x12, #1
	strb	wzr, [x8], #1
	b.ne	.LBB247_2
.LBB247_3:                              // %"Mem$memSet.exit"
	str	w9, [x11]
	mov	w8, #242                        // =0xf2
	mov	x1, x10
	mov	x2, x11
	mov	w3, #2048                       // =0x800
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB247_7
// %bb.4:                               // %label_9
	cmp	x9, #1
	b.lt	.LBB247_7
// %bb.5:                               // %label_9
	ldr	w8, [x11]
	cmp	x8, x9
	b.le	.LBB247_7
.LBB247_6:                              // %label_2.i.i6
                                        // =>This Inner Loop Header: Depth=1
	subs	x9, x9, #1
	strb	wzr, [x10], #1
	b.ne	.LBB247_6
.LBB247_7:                              // %label_21
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end247:
	.size	Sys$netAcceptFrom, .Lfunc_end247-Sys$netAcceptFrom
                                        // -- End function
	.globl	Sys$netAddrLenRead              // -- Begin function Sys$netAddrLenRead
	.p2align	2
	.type	Sys$netAddrLenRead,@function
Sys$netAddrLenRead:                     // @"Sys$netAddrLenRead"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	w0, [x0]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end248:
	.size	Sys$netAddrLenRead, .Lfunc_end248-Sys$netAddrLenRead
                                        // -- End function
	.globl	Sys$netPutInt32                 // -- Begin function Sys$netPutInt32
	.p2align	2
	.type	Sys$netPutInt32,@function
Sys$netPutInt32:                        // @"Sys$netPutInt32"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	str	w2, [x0, x1]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end249:
	.size	Sys$netPutInt32, .Lfunc_end249-Sys$netPutInt32
                                        // -- End function
	.globl	Sys$netGetInt32                 // -- Begin function Sys$netGetInt32
	.p2align	2
	.type	Sys$netGetInt32,@function
Sys$netGetInt32:                        // @"Sys$netGetInt32"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	w0, [x0, x1]
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end250:
	.size	Sys$netGetInt32, .Lfunc_end250-Sys$netGetInt32
                                        // -- End function
	.globl	Sys$netAddrText                 // -- Begin function Sys$netAddrText
	.p2align	2
	.type	Sys$netAddrText,@function
Sys$netAddrText:                        // @"Sys$netAddrText"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x19, x0
	ldrh	w0, [x0]
	cmp	x0, #2
	b.eq	.LBB251_7
// %bb.1:
	cmp	w0, #10
	b.ne	.LBB251_8
// %bb.2:                               // %label_10.lr.ph.i.preheader
	mov	x8, xzr
	mov	x21, #-1                        // =0xffffffffffffffff
	mov	w22, #1                         // =0x1
.LBB251_3:                              // %label_10.lr.ph.i
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB251_4 Depth 2
	mov	x20, x8
.LBB251_4:                              // %label_10.i
                                        //   Parent Loop BB251_3 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	mov	x0, x19
	mov	x1, x20
	bl	Sys$netAddrZeroRun
	cmp	x0, x22
	b.gt	.LBB251_6
// %bb.5:                               // %label_21.i
                                        //   in Loop: Header=BB251_4 Depth=2
	cmp	x0, #1
	csinc	x8, x0, xzr, gt
	add	x20, x8, x20
	cmp	x20, #8
	b.lt	.LBB251_4
	b	.LBB251_9
.LBB251_6:                              // %label_20.i
                                        //   in Loop: Header=BB251_3 Depth=1
	add	x8, x0, x20
	mov	x22, x0
	mov	x21, x20
	cmp	x8, #7
	b.le	.LBB251_3
	b	.LBB251_10
.LBB251_7:                              // %label_16
	mov	x0, x19
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	b	Sys$netAddrText4
.LBB251_8:                              // %label_17
	bl	Fmt$fmtNat
	mov	x19, x0
	adrp	x20, .Lstrhdr_8+16
	add	x20, x20, :lo12:.Lstrhdr_8+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	mov	x0, x21
	b	.LBB251_11
.LBB251_9:
	mov	x20, x21
.LBB251_10:                             // %"Sys$netAddrZeroRunStart.exit"
	adrp	x21, .Lstrhdr_4+16
	add	x21, x21, :lo12:.Lstrhdr_4+16
	mov	x0, x19
	mov	x1, xzr
	mov	x2, x20
	mov	x3, x21
	bl	Sys$netAddrText6
	mov	x19, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x19
.LBB251_11:                             // %"Sys$netAddrZeroRunStart.exit"
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end251:
	.size	Sys$netAddrText, .Lfunc_end251-Sys$netAddrText
	.cfi_endproc
                                        // -- End function
	.globl	Sys$netAddrText4                // -- Begin function Sys$netAddrText4
	.p2align	2
	.type	Sys$netAddrText4,@function
Sys$netAddrText4:                       // @"Sys$netAddrText4"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	str	x23, [sp, #16]                  // 8-byte Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 64
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -48
	.cfi_offset w30, -56
	.cfi_offset w29, -64
	mov	x19, x0
	ldrb	w0, [x0, #4]
	bl	Fmt$fmtNat
	adrp	x20, .Lstrhdr_3+16
	add	x20, x20, :lo12:.Lstrhdr_3+16
	mov	x21, x0
	mov	x1, x20
	bl	Str$strConcat
	mov	x22, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	ldrb	w0, [x19, #5]
	bl	Fmt$fmtNat
	mov	x1, x20
	mov	x21, x0
	bl	Str$strConcat
	mov	x23, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	mov	x0, x22
	mov	x1, x23
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x22
	bl	axiom_release
	mov	x0, x23
	bl	axiom_release
	ldrb	w0, [x19, #6]
	bl	Fmt$fmtNat
	mov	x1, x20
	mov	x22, x0
	bl	Str$strConcat
	mov	x23, x0
	mov	x0, x22
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	ldrb	w0, [x19, #7]
	bl	Fmt$fmtNat
	mov	x19, x0
	mov	x0, x23
	mov	x1, x19
	bl	Str$strConcat
	mov	x20, x0
	mov	x0, x23
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	mov	x0, x21
	mov	x1, x20
	bl	Str$strConcat
	mov	x19, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldr	x23, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
	ret
.Lfunc_end252:
	.size	Sys$netAddrText4, .Lfunc_end252-Sys$netAddrText4
	.cfi_endproc
                                        // -- End function
	.globl	Sys$netAddrZeroRun              // -- Begin function Sys$netAddrZeroRun
	.p2align	2
	.type	Sys$netAddrZeroRun,@function
Sys$netAddrZeroRun:                     // @"Sys$netAddrZeroRun"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	lsl	x9, x1, #1
	mov	x8, xzr
	mov	x29, sp
.LBB253_1:                              // %tailrecurse
                                        // =>This Inner Loop Header: Depth=1
	add	x10, x1, x8
	cmp	x10, #7
	b.gt	.LBB253_4
// %bb.2:                               // %label_4
                                        //   in Loop: Header=BB253_1 Depth=1
	add	x10, x0, x9
	ldrh	w10, [x10, #8]
	rev16	w10, w10
	cbnz	w10, .LBB253_4
// %bb.3:                               // %label_10
                                        //   in Loop: Header=BB253_1 Depth=1
	add	x8, x8, #1
	add	x9, x9, #2
	b	.LBB253_1
.LBB253_4:                              // %label_5
	mov	x0, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end253:
	.size	Sys$netAddrZeroRun, .Lfunc_end253-Sys$netAddrZeroRun
                                        // -- End function
	.globl	Sys$netAddrZeroRunStart         // -- Begin function Sys$netAddrZeroRunStart
	.p2align	2
	.type	Sys$netAddrZeroRunStart,@function
Sys$netAddrZeroRunStart:                // @"Sys$netAddrZeroRunStart"
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x19, x2
	cmp	x1, #7
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	b.le	.LBB254_3
.LBB254_1:
	mov	x22, x19
.LBB254_2:                              // %label_9
	mov	x0, x22
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB254_3:                              // %label_10.lr.ph.preheader
	mov	x21, x3
	mov	x20, x0
.LBB254_4:                              // %label_10.lr.ph
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB254_5 Depth 2
	mov	x22, x1
.LBB254_5:                              // %label_10
                                        //   Parent Loop BB254_4 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	mov	x0, x20
	mov	x1, x22
	bl	Sys$netAddrZeroRun
	cmp	x0, x21
	b.gt	.LBB254_7
// %bb.6:                               // %label_21
                                        //   in Loop: Header=BB254_5 Depth=2
	cmp	x0, #1
	csinc	x8, x0, xzr, gt
	add	x22, x8, x22
	cmp	x22, #7
	b.le	.LBB254_5
	b	.LBB254_1
.LBB254_7:                              // %label_20
                                        //   in Loop: Header=BB254_4 Depth=1
	add	x1, x0, x22
	mov	x21, x0
	mov	x19, x22
	cmp	x1, #7
	b.le	.LBB254_4
	b	.LBB254_2
.Lfunc_end254:
	.size	Sys$netAddrZeroRunStart, .Lfunc_end254-Sys$netAddrZeroRunStart
                                        // -- End function
	.globl	Sys$netAddrText6                // -- Begin function Sys$netAddrText6
	.p2align	2
	.type	Sys$netAddrText6,@function
Sys$netAddrText6:                       // @"Sys$netAddrText6"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	stp	x26, x25, [sp, #16]             // 16-byte Folded Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -56
	.cfi_offset w26, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	mov	x21, x3
	mov	x19, x2
	mov	x24, x1
	cmp	x3, #1, lsl #12                 // =4096
	mov	x20, x0
	b.lt	.LBB255_3
// %bb.1:                               // %chk.i
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB255_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB255_3:                              // %axiom_retain.exit
	cmp	x24, #7
	b.le	.LBB255_9
// %bb.4:
	mov	x23, x21
.LBB255_5:                              // %label_9
	cmp	x23, #1, lsl #12                // =4096
	b.lt	.LBB255_8
// %bb.6:                               // %chk.i20
	ldur	x8, [x23, #-16]
	cmn	x8, #1
	b.eq	.LBB255_8
// %bb.7:                               // %bump.i25
	add	x8, x8, #1
	stur	x8, [x23, #-16]
.LBB255_8:                              // %axiom_retain.exit27
	mov	x0, x23
	bl	axiom_release
	mov	x0, x23
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x26, x25, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
	ret
.LBB255_9:
	adrp	x22, .Lstrhdr_10+16
	add	x22, x22, :lo12:.Lstrhdr_10+16
	adrp	x25, .Lstrhdr_9+16
	add	x25, x25, :lo12:.Lstrhdr_9+16
	b	.LBB255_11
.LBB255_10:                             // %label_0.backedge
                                        //   in Loop: Header=BB255_11 Depth=1
	mov	x0, x21
	bl	axiom_release
	mov	x0, x23
	bl	axiom_release
	cmp	x26, #7
	mov	x21, x23
	mov	x24, x26
	b.gt	.LBB255_5
.LBB255_11:                             // %label_10
                                        // =>This Inner Loop Header: Depth=1
	cmp	x24, x19
	b.ne	.LBB255_13
// %bb.12:                              // %label_18
                                        //   in Loop: Header=BB255_11 Depth=1
	mov	x0, x20
	mov	x1, x24
	bl	Sys$netAddrZeroRun
	add	x26, x0, x24
	mov	x0, x21
	cmp	x26, #8
	csel	x24, x25, x22, eq
	b	.LBB255_16
.LBB255_13:                             // %label_19
                                        //   in Loop: Header=BB255_11 Depth=1
	mov	x23, x21
	cbz	x24, .LBB255_15
// %bb.14:                              // %label_51
                                        //   in Loop: Header=BB255_11 Depth=1
	mov	x0, x21
	mov	x1, x22
	bl	Str$strConcat
	mov	x23, x0
	mov	x0, x22
	bl	axiom_release
.LBB255_15:                             // %label_52
                                        //   in Loop: Header=BB255_11 Depth=1
	add	x8, x20, x24, lsl #1
	add	x26, x24, #1
	ldrh	w8, [x8, #8]
	rev16	w0, w8
	bl	Fmt$fmtHex
	mov	x24, x0
	mov	x0, x23
.LBB255_16:                             // %label_18
                                        //   in Loop: Header=BB255_11 Depth=1
	mov	x1, x24
	bl	Str$strConcat
	mov	x23, x0
	mov	x0, x24
	bl	axiom_release
	cmp	x23, #1, lsl #12                // =4096
	b.lt	.LBB255_10
// %bb.17:                              // %chk.i29
                                        //   in Loop: Header=BB255_11 Depth=1
	ldur	x8, [x23, #-16]
	cmn	x8, #1
	b.eq	.LBB255_10
// %bb.18:                              // %label_0.backedge.sink.split
                                        //   in Loop: Header=BB255_11 Depth=1
	add	x8, x8, #1
	stur	x8, [x23, #-16]
	b	.LBB255_10
.Lfunc_end255:
	.size	Sys$netAddrText6, .Lfunc_end255-Sys$netAddrText6
	.cfi_endproc
                                        // -- End function
	.globl	Sys$netAddrTextPort             // -- Begin function Sys$netAddrTextPort
	.p2align	2
	.type	Sys$netAddrTextPort,@function
Sys$netAddrTextPort:                    // @"Sys$netAddrTextPort"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	ldrh	w19, [x0]
	mov	x20, x0
	bl	Sys$netAddrText
	cmp	x19, #10
	mov	x19, x0
	b.ne	.LBB256_2
// %bb.1:                               // %label_5
	adrp	x21, .Lstrhdr_11+16
	add	x21, x21, :lo12:.Lstrhdr_11+16
	mov	x1, x19
	mov	x0, x21
	bl	Str$strConcat
	mov	x22, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	adrp	x21, .Lstrhdr_12+16
	add	x21, x21, :lo12:.Lstrhdr_12+16
	mov	x19, x22
	b	.LBB256_3
.LBB256_2:
	adrp	x21, .Lstrhdr_10+16
	add	x21, x21, :lo12:.Lstrhdr_10+16
.LBB256_3:                              // %label_7
	ldrh	w8, [x20, #2]
	rev16	w0, w8
	bl	Fmt$fmtNat
	mov	x20, x0
	mov	x0, x21
	mov	x1, x20
	bl	Str$strConcat
	mov	x22, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	mov	x1, x22
	bl	Str$strConcat
	mov	x20, x0
	mov	x0, x19
	bl	axiom_release
	mov	x0, x22
	bl	axiom_release
	mov	x0, x20
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end256:
	.size	Sys$netAddrTextPort, .Lfunc_end256-Sys$netAddrTextPort
	.cfi_endproc
                                        // -- End function
	.globl	Sys$netSetBlocking              // -- Begin function Sys$netSetBlocking
	.p2align	2
	.type	Sys$netSetBlocking,@function
Sys$netSetBlocking:                     // @"Sys$netSetBlocking"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	w8, #25                         // =0x19
	mov	w1, #3                          // =0x3
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB257_2
// %bb.1:                               // %label_7
	and	x8, x0, #0x7fffffffffffffff
	mov	x0, x9
	mov	w1, #4                          // =0x4
	and	x2, x8, #0xfffffffffffff7ff
	mov	w8, #25                         // =0x19
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB257_2:                              // %label_8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end257:
	.size	Sys$netSetBlocking, .Lfunc_end257-Sys$netSetBlocking
                                        // -- End function
	.globl	Sys$netConnect                  // -- Begin function Sys$netConnect
	.p2align	2
	.type	Sys$netConnect,@function
Sys$netConnect:                         // @"Sys$netConnect"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldrh	w8, [x1]
	mov	w9, #16                         // =0x10
	mov	w10, #28                        // =0x1c
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	cmp	x8, #10
	mov	w8, #203                        // =0xcb
	mov	x29, sp
	csel	x2, x10, x9, eq
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end258:
	.size	Sys$netConnect, .Lfunc_end258-Sys$netConnect
                                        // -- End function
	.globl	Sys$netShutdown                 // -- Begin function Sys$netShutdown
	.p2align	2
	.type	Sys$netShutdown,@function
Sys$netShutdown:                        // @"Sys$netShutdown"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #210                        // =0xd2
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end259:
	.size	Sys$netShutdown, .Lfunc_end259-Sys$netShutdown
                                        // -- End function
	.globl	Sys$netSetOptInt                // -- Begin function Sys$netSetOptInt
	.p2align	2
	.type	Sys$netSetOptInt,@function
Sys$netSetOptInt:                       // @"Sys$netSetOptInt"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	str	w3, [x4]
	mov	w8, #208                        // =0xd0
	mov	x3, x4
	mov	w4, #4                          // =0x4
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end260:
	.size	Sys$netSetOptInt, .Lfunc_end260-Sys$netSetOptInt
                                        // -- End function
	.globl	Sys$netSetNonBlocking           // -- Begin function Sys$netSetNonBlocking
	.p2align	2
	.type	Sys$netSetNonBlocking,@function
Sys$netSetNonBlocking:                  // @"Sys$netSetNonBlocking"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	w8, #25                         // =0x19
	mov	w1, #3                          // =0x3
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB261_2
// %bb.1:                               // %label_7
	orr	x2, x0, #0x800
	mov	w8, #25                         // =0x19
	mov	x0, x9
	mov	w1, #4                          // =0x4
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB261_2:                              // %label_8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end261:
	.size	Sys$netSetNonBlocking, .Lfunc_end261-Sys$netSetNonBlocking
                                        // -- End function
	.globl	Sys$netWouldBlock               // -- Begin function Sys$netWouldBlock
	.p2align	2
	.type	Sys$netWouldBlock,@function
Sys$netWouldBlock:                      // @"Sys$netWouldBlock"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	cmn	x0, #11
	mov	x29, sp
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end262:
	.size	Sys$netWouldBlock, .Lfunc_end262-Sys$netWouldBlock
                                        // -- End function
	.globl	Sys$netPutWord                  // -- Begin function Sys$netPutWord
	.p2align	2
	.type	Sys$netPutWord,@function
Sys$netPutWord:                         // @"Sys$netPutWord"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	str	x2, [x0, x1]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end263:
	.size	Sys$netPutWord, .Lfunc_end263-Sys$netPutWord
                                        // -- End function
	.globl	Sys$netGetWord                  // -- Begin function Sys$netGetWord
	.p2align	2
	.type	Sys$netGetWord,@function
Sys$netGetWord:                         // @"Sys$netGetWord"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x1
	mov	x29, sp
	ldrb	w9, [x8, #1]
	ldrb	w10, [x8, #2]
	ldrb	w11, [x8, #3]
	lsl	x9, x9, #8
	orr	x9, x9, x10, lsl #16
	ldrb	w10, [x8, #4]
	orr	x9, x9, x11, lsl #24
	ldrb	w11, [x8, #5]
	orr	x9, x9, x10, lsl #32
	ldrb	w10, [x8, #6]
	orr	x9, x9, x11, lsl #40
	ldrb	w11, [x8, #7]
	ldrb	w8, [x8]
	orr	x9, x9, x10, lsl #48
	orr	x9, x9, x11, lsl #56
	add	x0, x9, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end264:
	.size	Sys$netGetWord, .Lfunc_end264-Sys$netGetWord
                                        // -- End function
	.globl	Sys$netPollBufBytes             // -- Begin function Sys$netPollBufBytes
	.p2align	2
	.type	Sys$netPollBufBytes,@function
Sys$netPollBufBytes:                    // @"Sys$netPollBufBytes"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	lsl	x0, x0, #4
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end265:
	.size	Sys$netPollBufBytes, .Lfunc_end265-Sys$netPollBufBytes
                                        // -- End function
	.globl	Sys$netPollCreate               // -- Begin function Sys$netPollCreate
	.p2align	2
	.type	Sys$netPollCreate,@function
Sys$netPollCreate:                      // @"Sys$netPollCreate"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #20                         // =0x14
	mov	x0, xzr
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end266:
	.size	Sys$netPollCreate, .Lfunc_end266-Sys$netPollCreate
                                        // -- End function
	.globl	Sys$netPollRec                  // -- Begin function Sys$netPollRec
	.p2align	2
	.type	Sys$netPollRec,@function
Sys$netPollRec:                         // @"Sys$netPollRec"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #1                          // =0x1
	lsr	x9, x1, #8
	mov	x29, sp
	strh	w8, [x0]
	lsr	x8, x1, #16
	strb	w9, [x0, #9]
	lsr	x9, x1, #24
	strb	w8, [x0, #10]
	lsr	x8, x1, #32
	strb	w9, [x0, #11]
	lsr	x9, x1, #56
	strb	w8, [x0, #12]
	lsr	x8, x1, #40
	stur	wzr, [x0, #2]
	strb	w8, [x0, #13]
	lsr	x8, x1, #48
	strh	wzr, [x0, #6]
	strb	w1, [x0, #8]
	strb	w8, [x0, #14]
	strb	w9, [x0, #15]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end267:
	.size	Sys$netPollRec, .Lfunc_end267-Sys$netPollRec
                                        // -- End function
	.globl	Sys$netPollAddRead              // -- Begin function Sys$netPollAddRead
	.p2align	2
	.type	Sys$netPollAddRead,@function
Sys$netPollAddRead:                     // @"Sys$netPollAddRead"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x3, x2
	mov	w8, #1                          // =0x1
	lsr	x9, x1, #16
	strh	w8, [x3]
	lsr	x8, x1, #8
	lsr	x10, x1, #24
	strb	w9, [x3, #10]
	lsr	x9, x1, #40
	mov	x2, x1
	strb	w8, [x3, #9]
	lsr	x8, x1, #32
	mov	x4, xzr
	strb	w10, [x3, #11]
	lsr	x10, x1, #48
	mov	x5, xzr
	strb	w8, [x3, #12]
	lsr	x8, x1, #56
	mov	w1, #1                          // =0x1
	stur	wzr, [x3, #2]
	mov	x29, sp
	strh	wzr, [x3, #6]
	strb	w2, [x3, #8]
	strb	w9, [x3, #13]
	strb	w10, [x3, #14]
	strb	w8, [x3, #15]
	mov	w8, #21                         // =0x15
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end268:
	.size	Sys$netPollAddRead, .Lfunc_end268-Sys$netPollAddRead
                                        // -- End function
	.globl	Sys$netPollDelRead              // -- Begin function Sys$netPollDelRead
	.p2align	2
	.type	Sys$netPollDelRead,@function
Sys$netPollDelRead:                     // @"Sys$netPollDelRead"
// %bb.0:                               // %label_7
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x3, x2
	mov	w8, #1                          // =0x1
	lsr	x9, x1, #16
	strh	w8, [x3]
	lsr	x8, x1, #8
	lsr	x10, x1, #24
	strb	w9, [x3, #10]
	lsr	x9, x1, #40
	mov	x2, x1
	strb	w8, [x3, #9]
	lsr	x8, x1, #32
	mov	x4, xzr
	strb	w10, [x3, #11]
	lsr	x10, x1, #48
	mov	x5, xzr
	strb	w8, [x3, #12]
	lsr	x8, x1, #56
	mov	w1, #2                          // =0x2
	stur	wzr, [x3, #2]
	mov	x29, sp
	strh	wzr, [x3, #6]
	strb	w2, [x3, #8]
	strb	w9, [x3, #13]
	strb	w10, [x3, #14]
	strb	w8, [x3, #15]
	mov	w8, #21                         // =0x15
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end269:
	.size	Sys$netPollDelRead, .Lfunc_end269-Sys$netPollDelRead
                                        // -- End function
	.globl	Sys$netPollWait                 // -- Begin function Sys$netPollWait
	.p2align	2
	.type	Sys$netPollWait,@function
Sys$netPollWait:                        // @"Sys$netPollWait"
// %bb.0:                               // %label_5
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #22                         // =0x16
	mov	x4, xzr
	mov	w5, #8                          // =0x8
	//APP
	svc	#0
	//NO_APP
	mov	x29, sp
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end270:
	.size	Sys$netPollWait, .Lfunc_end270-Sys$netPollWait
                                        // -- End function
	.globl	Sys$netPollFdAt                 // -- Begin function Sys$netPollFdAt
	.p2align	2
	.type	Sys$netPollFdAt,@function
Sys$netPollFdAt:                        // @"Sys$netPollFdAt"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x1, lsl #4
	mov	x29, sp
	ldrb	w9, [x8, #9]
	ldrb	w10, [x8, #10]
	ldrb	w11, [x8, #11]
	lsl	x9, x9, #8
	orr	x9, x9, x10, lsl #16
	ldrb	w10, [x8, #12]
	orr	x9, x9, x11, lsl #24
	ldrb	w11, [x8, #13]
	orr	x9, x9, x10, lsl #32
	ldrb	w10, [x8, #14]
	orr	x9, x9, x11, lsl #40
	ldrb	w11, [x8, #15]
	ldrb	w8, [x8, #8]
	orr	x9, x9, x10, lsl #48
	orr	x9, x9, x11, lsl #56
	add	x0, x9, x8
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end271:
	.size	Sys$netPollFdAt, .Lfunc_end271-Sys$netPollFdAt
                                        // -- End function
	.globl	Sys$sysRandomBytes              // -- Begin function Sys$sysRandomBytes
	.p2align	2
	.type	Sys$sysRandomBytes,@function
Sys$sysRandomBytes:                     // @"Sys$sysRandomBytes"
// %bb.0:
	cmp	x1, #1
	b.lt	.LBB272_4
// %bb.1:                               // %label_3.preheader
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x1
	mov	x10, x0
	mov	x12, xzr
	mov	x11, xzr
	mov	w13, #256                       // =0x100
	mov	x29, sp
.LBB272_2:                              // %label_3
                                        // =>This Inner Loop Header: Depth=1
	sub	x8, x9, x11
	mov	x2, xzr
	mov	x3, xzr
	cmp	x8, #256
	mov	x4, xzr
	mov	x5, xzr
	csel	x1, x8, x13, lt
	add	x0, x11, x10
	mov	w8, #278                        // =0x116
	//APP
	svc	#0
	//NO_APP
	bic	x8, x0, x0, asr #63
	cmp	x0, #0
	csinv	x12, x12, xzr, ne
	add	x11, x8, x11
	csel	x12, x0, x12, mi
	cmp	x11, x9
	ccmp	x12, #0, #0, lt
	b.eq	.LBB272_2
// %bb.3:                               // %label_4.loopexit
	and	x0, x12, x12, asr #63
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB272_4:                              // %label_4
	mov	x0, xzr
	ret
.Lfunc_end272:
	.size	Sys$sysRandomBytes, .Lfunc_end272-Sys$sysRandomBytes
                                        // -- End function
	.globl	Sys$sysSigBit                   // -- Begin function Sys$sysSigBit
	.p2align	2
	.type	Sys$sysSigBit,@function
Sys$sysSigBit:                          // @"Sys$sysSigBit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #1                          // =0x1
	sub	x9, x0, #1
	mov	x29, sp
	lsl	x0, x8, x9
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end273:
	.size	Sys$sysSigBit, .Lfunc_end273-Sys$sysSigBit
                                        // -- End function
	.globl	Sys$sysSignalBlock              // -- Begin function Sys$sysSignalBlock
	.p2align	2
	.type	Sys$sysSignalBlock,@function
Sys$sysSignalBlock:                     // @"Sys$sysSignalBlock"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	str	x0, [x1]
	mov	w8, #135                        // =0x87
	mov	x0, xzr
	mov	x2, xzr
	mov	w3, #8                          // =0x8
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end274:
	.size	Sys$sysSignalBlock, .Lfunc_end274-Sys$sysSignalBlock
                                        // -- End function
	.globl	Sys$netSignalOpen               // -- Begin function Sys$netSignalOpen
	.p2align	2
	.type	Sys$netSignalOpen,@function
Sys$netSignalOpen:                      // @"Sys$netSignalOpen"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x2
	mov	x10, x0
	str	x1, [x3]
	mov	w8, #74                         // =0x4a
	mov	x0, #-1                         // =0xffffffffffffffff
	mov	x1, x3
	mov	w2, #8                          // =0x8
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB275_2
// %bb.1:                               // %label_16
	lsr	x11, x0, #8
	mov	w8, #1                          // =0x1
	lsr	x12, x0, #24
	strh	w8, [x9]
	lsr	x8, x0, #16
	mov	w1, #1                          // =0x1
	strb	w11, [x9, #9]
	lsr	x11, x0, #32
	mov	x3, x9
	strb	w8, [x9, #10]
	lsr	x8, x0, #40
	mov	x4, xzr
	strb	w11, [x9, #12]
	lsr	x11, x0, #56
	mov	x5, xzr
	strb	w12, [x9, #11]
	lsr	x12, x0, #48
	strb	w11, [x9, #15]
	mov	x11, x0
	stur	wzr, [x9, #2]
	mov	x2, x11
	strh	wzr, [x9, #6]
	strb	w0, [x9, #8]
	mov	x0, x10
	strb	w8, [x9, #13]
	mov	w8, #21                         // =0x15
	strb	w12, [x9, #14]
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	csel	x0, x0, x11, mi
.LBB275_2:                              // %label_6
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end275:
	.size	Sys$netSignalOpen, .Lfunc_end275-Sys$netSignalOpen
                                        // -- End function
	.globl	Sys$netPollSignalAt             // -- Begin function Sys$netPollSignalAt
	.p2align	2
	.type	Sys$netPollSignalAt,@function
Sys$netPollSignalAt:                    // @"Sys$netPollSignalAt"
// %bb.0:                               // %label_4
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	add	x8, x0, x1, lsl #4
	mov	x29, sp
	ldrb	w9, [x8, #9]
	ldrb	w10, [x8, #10]
	ldrb	w11, [x8, #11]
	lsl	x9, x9, #8
	orr	x9, x9, x10, lsl #16
	ldrb	w10, [x8, #12]
	orr	x9, x9, x11, lsl #24
	ldrb	w11, [x8, #13]
	orr	x9, x9, x10, lsl #32
	ldrb	w10, [x8, #14]
	orr	x9, x9, x11, lsl #40
	ldrb	w11, [x8, #15]
	ldrb	w8, [x8, #8]
	orr	x9, x9, x10, lsl #48
	orr	x9, x9, x11, lsl #56
	add	x8, x9, x8
	cmp	x8, x2
	b.ne	.LBB276_2
// %bb.1:                               // %label_12
	mov	x9, x3
	mov	w8, #63                         // =0x3f
	mov	x0, x2
	mov	x1, x3
	mov	w2, #128                        // =0x80
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #128
	b.ge	.LBB276_3
.LBB276_2:
	mov	x0, #-1                         // =0xffffffffffffffff
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB276_3:                              // %label_23
	ldr	w0, [x9]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end276:
	.size	Sys$netPollSignalAt, .Lfunc_end276-Sys$netPollSignalAt
                                        // -- End function
	.globl	Sys$sysKill                     // -- Begin function Sys$sysKill
	.p2align	2
	.type	Sys$sysKill,@function
Sys$sysKill:                            // @"Sys$sysKill"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #129                        // =0x81
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end277:
	.size	Sys$sysKill, .Lfunc_end277-Sys$sysKill
                                        // -- End function
	.globl	Sys$sysForkProcess              // -- Begin function Sys$sysForkProcess
	.p2align	2
	.type	Sys$sysForkProcess,@function
Sys$sysForkProcess:                     // @"Sys$sysForkProcess"
// %bb.0:                               // %label_8
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #220                        // =0xdc
	mov	w0, #17                         // =0x11
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x29, sp
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end278:
	.size	Sys$sysForkProcess, .Lfunc_end278-Sys$sysForkProcess
                                        // -- End function
	.globl	IO$writeStr                     // -- Begin function IO$writeStr
	.p2align	2
	.type	IO$writeStr,@function
IO$writeStr:                            // @"IO$writeStr"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldr	x11, [x1]
	mov	x29, sp
	cmp	x11, #1
	b.lt	.LBB279_4
// %bb.1:                               // %label_11.i.preheader
	ldr	x12, [x1, #8]
	mov	x10, x0
	mov	x9, xzr
.LBB279_2:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x9, x12
	sub	x2, x11, x9
	mov	w8, #64                         // =0x40
	mov	x0, x10
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB279_5
// %bb.3:                               // %label_26.i
                                        //   in Loop: Header=BB279_2 Depth=1
	add	x9, x0, x9
	cmp	x9, x11
	b.lt	.LBB279_2
	b	.LBB279_6
.LBB279_4:
	mov	x9, xzr
	b	.LBB279_6
.LBB279_5:                              // %label_25.i
	csel	x9, x9, x0, eq
.LBB279_6:                              // %"Sys$sysWriteAllFd.exit"
	mov	x0, x9
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end279:
	.size	IO$writeStr, .Lfunc_end279-IO$writeStr
                                        // -- End function
	.globl	IO$printLit                     // -- Begin function IO$printLit
	.p2align	2
	.type	IO$printLit,@function
IO$printLit:                            // @"IO$printLit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	x11, xzr
	mov	x29, sp
.LBB280_1:                              // %label_0.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x9, x11]
	add	x11, x11, #1
	cbnz	w8, .LBB280_1
// %bb.2:                               // %"Str$cstrLen.exit"
	sub	x12, x11, #1
	cmp	x12, #1
	b.lt	.LBB280_6
// %bb.3:                               // %label_11.i.preheader
	mov	x10, xzr
.LBB280_4:                              // %label_11.i
                                        // =>This Inner Loop Header: Depth=1
	mvn	x8, x10
	add	x1, x10, x9
	mov	w0, #1                          // =0x1
	add	x2, x8, x11
	mov	w8, #64                         // =0x40
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB280_7
// %bb.5:                               // %label_26.i
                                        //   in Loop: Header=BB280_4 Depth=1
	add	x10, x0, x10
	cmp	x10, x12
	b.lt	.LBB280_4
	b	.LBB280_8
.LBB280_6:
	mov	x10, xzr
	b	.LBB280_8
.LBB280_7:                              // %label_25.i
	csel	x10, x10, x0, eq
.LBB280_8:                              // %"Sys$sysWriteAllFd.exit"
	mov	x0, x10
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end280:
	.size	IO$printLit, .Lfunc_end280-IO$printLit
                                        // -- End function
	.globl	IO$printlnLit                   // -- Begin function IO$printlnLit
	.p2align	2
	.type	IO$printlnLit,@function
IO$printlnLit:                          // @"IO$printlnLit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x9, x0
	mov	x10, xzr
	mov	x29, sp
.LBB281_1:                              // %label_0.i.i
                                        // =>This Inner Loop Header: Depth=1
	ldrb	w8, [x9, x10]
	add	x10, x10, #1
	cbnz	w8, .LBB281_1
// %bb.2:                               // %"Str$cstrLen.exit.i"
	sub	x11, x10, #1
	cmp	x11, #1
	b.lt	.LBB281_5
// %bb.3:                               // %label_11.i.i.preheader
	mov	x12, xzr
.LBB281_4:                              // %label_11.i.i
                                        // =>This Inner Loop Header: Depth=1
	mvn	x8, x12
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	add	x1, x12, x9
	add	x2, x8, x10
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	//APP
	svc	#0
	//NO_APP
	add	x12, x0, x12
	cmp	x0, #1
	ccmp	x12, x11, #0, ge
	b.lt	.LBB281_4
.LBB281_5:                              // %label_11.i.i10
	adrp	x1, .Lstr_13
	add	x1, x1, :lo12:.Lstr_13
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	mov	w2, #1                          // =0x1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end281:
	.size	IO$printlnLit, .Lfunc_end281-IO$printlnLit
                                        // -- End function
	.globl	IO$readFileLit                  // -- Begin function IO$readFileLit
	.p2align	2
	.type	IO$readFileLit,@function
IO$readFileLit:                         // @"IO$readFileLit"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	Sys$sysReadFile
.Lfunc_end282:
	.size	IO$readFileLit, .Lfunc_end282-IO$readFileLit
	.cfi_endproc
                                        // -- End function
	.globl	IO$readFile                     // -- Begin function IO$readFile
	.p2align	2
	.type	IO$readFile,@function
IO$readFile:                            // @"IO$readFile"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	Str$strDup
	ldr	x0, [x0, #8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	Sys$sysReadFile
.Lfunc_end283:
	.size	IO$readFile, .Lfunc_end283-IO$readFile
	.cfi_endproc
                                        // -- End function
	.globl	IO$ioPath                       // -- Begin function IO$ioPath
	.p2align	2
	.type	IO$ioPath,@function
IO$ioPath:                              // @"IO$ioPath"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x0, [x0, #8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end284:
	.size	IO$ioPath, .Lfunc_end284-IO$ioPath
                                        // -- End function
	.globl	IO$writeFile                    // -- Begin function IO$writeFile
	.p2align	2
	.type	IO$writeFile,@function
IO$writeFile:                           // @"IO$writeFile"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	mov	x19, x1
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #577                        // =0x241
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x9, x0
	tbnz	x0, #63, .LBB285_8
// %bb.1:                               // %label_5.i
	ldr	x11, [x19]
	cmp	x11, #1
	b.lt	.LBB285_5
// %bb.2:                               // %label_11.i.i.preheader
	ldr	x12, [x19, #8]
	mov	x10, xzr
.LBB285_3:                              // %label_11.i.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x10, x12
	sub	x2, x11, x10
	mov	w8, #64                         // =0x40
	mov	x0, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB285_6
// %bb.4:                               // %label_26.i.i
                                        //   in Loop: Header=BB285_3 Depth=1
	add	x10, x0, x10
	cmp	x10, x11
	b.lt	.LBB285_3
	b	.LBB285_7
.LBB285_5:
	mov	x10, xzr
	b	.LBB285_7
.LBB285_6:                              // %label_25.i.i
	csel	x10, x10, x0, eq
.LBB285_7:                              // %"Sys$sysWriteAllFd.exit.i"
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x10
	//APP
	svc	#0
	//NO_APP
.LBB285_8:                              // %"Sys$sysWriteFile.exit"
	ldr	x19, [sp, #16]                  // 8-byte Reload
	mov	x0, x9
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end285:
	.size	IO$writeFile, .Lfunc_end285-IO$writeFile
                                        // -- End function
	.globl	IO$appendFile                   // -- Begin function IO$appendFile
	.p2align	2
	.type	IO$appendFile,@function
IO$appendFile:                          // @"IO$appendFile"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	str	x19, [sp, #16]                  // 8-byte Spill
	mov	x29, sp
	mov	x19, x1
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #1089                       // =0x441
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x9, x0
	tbnz	x0, #63, .LBB286_8
// %bb.1:                               // %label_5.i
	ldr	x11, [x19]
	cmp	x11, #1
	b.lt	.LBB286_5
// %bb.2:                               // %label_11.i.i.preheader
	ldr	x12, [x19, #8]
	mov	x10, xzr
.LBB286_3:                              // %label_11.i.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x10, x12
	sub	x2, x11, x10
	mov	w8, #64                         // =0x40
	mov	x0, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB286_6
// %bb.4:                               // %label_26.i.i
                                        //   in Loop: Header=BB286_3 Depth=1
	add	x10, x0, x10
	cmp	x10, x11
	b.lt	.LBB286_3
	b	.LBB286_7
.LBB286_5:
	mov	x10, xzr
	b	.LBB286_7
.LBB286_6:                              // %label_25.i.i
	csel	x10, x10, x0, eq
.LBB286_7:                              // %"Sys$sysWriteAllFd.exit.i"
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x10
	//APP
	svc	#0
	//NO_APP
.LBB286_8:                              // %"Sys$sysAppendFile.exit"
	ldr	x19, [sp, #16]                  // 8-byte Reload
	mov	x0, x9
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end286:
	.size	IO$appendFile, .Lfunc_end286-IO$appendFile
                                        // -- End function
	.globl	IO$removeFile                   // -- Begin function IO$removeFile
	.p2align	2
	.type	IO$removeFile,@function
IO$removeFile:                          // @"IO$removeFile"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #35                         // =0x23
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end287:
	.size	IO$removeFile, .Lfunc_end287-IO$removeFile
                                        // -- End function
	.globl	IO$renamePath                   // -- Begin function IO$renamePath
	.p2align	2
	.type	IO$renamePath,@function
IO$renamePath:                          // @"IO$renamePath"
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	mov	x19, x1
	bl	Str$strDup
	ldr	x20, [x0, #8]
	mov	x0, x19
	bl	Str$strDup
	ldr	x3, [x0, #8]
	mov	w8, #38                         // =0x26
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x1, x20
	mov	x2, #-100                       // =0xffffffffffffff9c
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end288:
	.size	IO$renamePath, .Lfunc_end288-IO$renamePath
                                        // -- End function
	.globl	IO$copyFile                     // -- Begin function IO$copyFile
	.p2align	2
	.type	IO$copyFile,@function
IO$copyFile:                            // @"IO$copyFile"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	mov	x20, x1
	mov	x19, x0
	bl	Str$strDup
	ldr	x0, [x0, #8]
	bl	Sys$sysReadErrno
	cbz	x0, .LBB289_2
// %bb.1:                               // %label_4
	neg	x9, x0
	b	.LBB289_10
.LBB289_2:                              // %label_5
	mov	x0, x19
	bl	Str$strDup
	ldr	x0, [x0, #8]
	bl	Sys$sysReadFile
	mov	x19, x0
	mov	x0, x20
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #577                        // =0x241
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x9, x0
	tbnz	x0, #63, .LBB289_10
// %bb.3:                               // %label_5.i.i
	ldr	x11, [x19]
	cmp	x11, #1
	b.lt	.LBB289_7
// %bb.4:                               // %label_11.i.i.i.preheader
	ldr	x12, [x19, #8]
	mov	x10, xzr
.LBB289_5:                              // %label_11.i.i.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x10, x12
	sub	x2, x11, x10
	mov	w8, #64                         // =0x40
	mov	x0, x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #0
	b.le	.LBB289_8
// %bb.6:                               // %label_26.i.i.i
                                        //   in Loop: Header=BB289_5 Depth=1
	add	x10, x0, x10
	cmp	x10, x11
	b.lt	.LBB289_5
	b	.LBB289_9
.LBB289_7:
	mov	x10, xzr
	b	.LBB289_9
.LBB289_8:                              // %label_25.i.i.i
	csel	x10, x10, x0, eq
.LBB289_9:                              // %"Sys$sysWriteAllFd.exit.i.i"
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x10
	//APP
	svc	#0
	//NO_APP
.LBB289_10:                             // %label_6
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	mov	x0, x9
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end289:
	.size	IO$copyFile, .Lfunc_end289-IO$copyFile
	.cfi_endproc
                                        // -- End function
	.globl	IO$fileExists                   // -- Begin function IO$fileExists
	.p2align	2
	.type	IO$fileExists,@function
IO$fileExists:                          // @"IO$fileExists"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB290_2
// %bb.1:                               // %label_6.i
	mov	w8, #57                         // =0x39
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	w0, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.LBB290_2:
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end290:
	.size	IO$fileExists, .Lfunc_end290-IO$fileExists
                                        // -- End function
	.globl	IO$isDir                        // -- Begin function IO$isDir
	.p2align	2
	.type	IO$isDir,@function
IO$isDir:                               // @"IO$isDir"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	Str$strDup
	ldr	x0, [x0, #8]
	bl	Sys$sysReadErrno
	cmp	x0, #21
	cset	w0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end291:
	.size	IO$isDir, .Lfunc_end291-IO$isDir
	.cfi_endproc
                                        // -- End function
	.globl	IO$fileSize                     // -- Begin function IO$fileSize
	.p2align	2
	.type	IO$fileSize,@function
IO$fileSize:                            // @"IO$fileSize"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #56                         // =0x38
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	x2, xzr
	mov	w3, #420                        // =0x1a4
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	tbnz	x0, #63, .LBB292_2
// %bb.1:                               // %label_6.i
	mov	w8, #62                         // =0x3e
	mov	x1, xzr
	mov	w2, #2                          // =0x2
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	mov	x9, x0
	//APP
	svc	#0
	//NO_APP
	mov	x6, x0
	mov	w8, #57                         // =0x39
	mov	x0, x9
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x0, x6
.LBB292_2:                              // %"Sys$sysFileSize.exit"
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end292:
	.size	IO$fileSize, .Lfunc_end292-IO$fileSize
                                        // -- End function
	.globl	IO$readErrno                    // -- Begin function IO$readErrno
	.p2align	2
	.type	IO$readErrno,@function
IO$readErrno:                           // @"IO$readErrno"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	Str$strDup
	ldr	x0, [x0, #8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	Sys$sysReadErrno
.Lfunc_end293:
	.size	IO$readErrno, .Lfunc_end293-IO$readErrno
	.cfi_endproc
                                        // -- End function
	.globl	IO$makeDir                      // -- Begin function IO$makeDir
	.p2align	2
	.type	IO$makeDir,@function
IO$makeDir:                             // @"IO$makeDir"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #34                         // =0x22
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #493                        // =0x1ed
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end294:
	.size	IO$makeDir, .Lfunc_end294-IO$makeDir
                                        // -- End function
	.globl	IO$makeDirAll                   // -- Begin function IO$makeDirAll
	.p2align	2
	.type	IO$makeDirAll,@function
IO$makeDirAll:                          // @"IO$makeDirAll"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	w1, #1                          // =0x1
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	IO$makeDirAllFrom
.Lfunc_end295:
	.size	IO$makeDirAll, .Lfunc_end295-IO$makeDirAll
	.cfi_endproc
                                        // -- End function
	.globl	IO$makeDirAllFrom               // -- Begin function IO$makeDirAllFrom
	.p2align	2
	.type	IO$makeDirAllFrom,@function
IO$makeDirAllFrom:                      // @"IO$makeDirAllFrom"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	str	x25, [sp, #16]                  // 8-byte Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	mov	x19, x0
	cmp	x0, #1, lsl #12                 // =4096
	mov	x20, x1
	b.lt	.LBB296_3
// %bb.1:                               // %chk.i
	ldur	x8, [x19, #-16]
	cmn	x8, #1
	b.eq	.LBB296_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x19, #-16]
.LBB296_3:                              // %axiom_retain.exit
	ldr	x8, [x19]
	cmp	x20, x8
	b.ge	.LBB296_15
// %bb.4:
	mov	w23, #47                        // =0x2f
	mov	x24, #-65536                    // =0xffffffffffff0000
	b	.LBB296_7
.LBB296_5:                              // %"Str$strSlice.exit"
                                        //   in Loop: Header=BB296_7 Depth=1
	mov	x22, x0
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #34                         // =0x22
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #493                        // =0x1ed
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmn	x0, #17
	csel	x21, xzr, x0, eq
	mov	x0, x22
	bl	axiom_release
	tbnz	x21, #63, .LBB296_16
.LBB296_6:                              // %label_0.backedge
                                        //   in Loop: Header=BB296_7 Depth=1
	ldr	x8, [x19]
	add	x20, x20, #1
	cmp	x20, x8
	b.ge	.LBB296_15
.LBB296_7:                              // %label_10
                                        // =>This Inner Loop Header: Depth=1
	tbnz	x20, #63, .LBB296_6
// %bb.8:                               // %label_11.i
                                        //   in Loop: Header=BB296_7 Depth=1
	ldr	x9, [x19, #8]
	ldrb	w9, [x9, x20]
	cmp	w9, #47
	b.ne	.LBB296_6
// %bb.9:                               // %label_20
                                        //   in Loop: Header=BB296_7 Depth=1
	and	x9, x8, x8, asr #63
	ldr	x21, [x19, #16]
	sub	x8, x8, x9
	cmp	x20, x8
	csel	x22, x20, x8, lt
	cmp	x21, #1, lsl #12                // =4096
	b.lt	.LBB296_12
// %bb.10:                              // %chk.i.i
                                        //   in Loop: Header=BB296_7 Depth=1
	ldur	x8, [x21, #-16]
	cmn	x8, #1
	b.eq	.LBB296_12
// %bb.11:                              // %bump.i.i
                                        //   in Loop: Header=BB296_7 Depth=1
	add	x8, x8, #1
	stur	x8, [x21, #-16]
.LBB296_12:                             // %axiom_retain.exit.i
                                        //   in Loop: Header=BB296_7 Depth=1
	ldr	x8, [x19, #8]
	mov	w0, #24                         // =0x18
	add	x25, x8, x9
	bl	axiom_alloc
	ldur	x8, [x0, #-8]
	stp	x25, x21, [x0, #8]
	ubfx	x9, x8, #1, #14
	cmp	x9, #47
	csel	x9, x9, x23, lo
	cmp	x0, #1, lsl #12                 // =4096
	lsl	x9, x24, x9
	mvn	w9, w9
	and	x9, x9, #0x40000
	orr	x8, x9, x8
	stp	x8, x22, [x0, #-8]
	b.lt	.LBB296_5
// %bb.13:                              // %chk.i.i.i
                                        //   in Loop: Header=BB296_7 Depth=1
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB296_5
// %bb.14:                              // %bump.i.i.i
                                        //   in Loop: Header=BB296_7 Depth=1
	add	x8, x8, #1
	stur	x8, [x0, #-16]
	b	.LBB296_5
.LBB296_15:                             // %label_9
	mov	x0, x19
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #34                         // =0x22
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #493                        // =0x1ed
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmn	x0, #17
	csel	x21, xzr, x0, eq
.LBB296_16:                             // %label_11
	mov	x0, x19
	bl	axiom_release
	mov	x0, x21
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldr	x25, [sp, #16]                  // 8-byte Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
	ret
.Lfunc_end296:
	.size	IO$makeDirAllFrom, .Lfunc_end296-IO$makeDirAllFrom
	.cfi_endproc
                                        // -- End function
	.globl	IO$makeDirOk                    // -- Begin function IO$makeDirOk
	.p2align	2
	.type	IO$makeDirOk,@function
IO$makeDirOk:                           // @"IO$makeDirOk"
// %bb.0:                               // %label_8
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #34                         // =0x22
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #493                        // =0x1ed
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmn	x0, #17
	csel	x0, xzr, x0, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end297:
	.size	IO$makeDirOk, .Lfunc_end297-IO$makeDirOk
                                        // -- End function
	.globl	IO$removeDir                    // -- Begin function IO$removeDir
	.p2align	2
	.type	IO$removeDir,@function
IO$removeDir:                           // @"IO$removeDir"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	bl	Str$strDup
	ldr	x1, [x0, #8]
	mov	w8, #35                         // =0x23
	mov	x0, #-100                       // =0xffffffffffffff9c
	mov	w2, #512                        // =0x200
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end298:
	.size	IO$removeDir, .Lfunc_end298-IO$removeDir
                                        // -- End function
	.globl	IO$listDir                      // -- Begin function IO$listDir
	.p2align	2
	.type	IO$listDir,@function
IO$listDir:                             // @"IO$listDir"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	bl	Str$strDup
	ldr	x0, [x0, #8]
	bl	Sys$sysReadDir
	mov	x19, x0
	mov	w0, #32                         // =0x20
	bl	axiom_alloc
	ldur	x9, [x0, #-8]
	mov	w8, #47                         // =0x2f
	mov	x20, x0
	ubfx	x10, x9, #1, #14
	cmp	x10, #47
	csel	x8, x10, x8, lo
	mov	x10, #-65536                    // =0xffffffffffff0000
	lsl	x8, x10, x8
	mvn	w8, w8
	and	x8, x8, #0x40000
	orr	x8, x8, x9
	stur	x8, [x0, #-8]
	mov	w0, #64                         // =0x40
	bl	axiom_alloc
	cmp	x20, #1, lsl #12                // =4096
	b.lt	.LBB299_3
// %bb.1:                               // %chk.i.i.i.i
	ldur	x8, [x20, #-16]
	cmn	x8, #1
	b.eq	.LBB299_3
// %bb.2:                               // %bump.i.i.i.i
	add	x8, x8, #1
	stur	x8, [x20, #-16]
.LBB299_3:                              // %axiom_retain.exit.i.i.i
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB299_6
// %bb.4:                               // %chk.i3.i.i.i
	ldur	x8, [x0, #-16]
	cmn	x8, #1
	b.eq	.LBB299_6
// %bb.5:                               // %bump.i8.i.i.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB299_6:                              // %"Vec$vecNew.exit"
	mov	w8, #8                          // =0x8
	stp	x0, xzr, [x20, #16]
	mov	x0, x19
	mov	x1, xzr
	mov	x2, x20
	stp	xzr, x8, [x20]
	bl	IO$listDirKeep
	mov	x0, x20
	ldp	x20, x19, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	ret
.Lfunc_end299:
	.size	IO$listDir, .Lfunc_end299-IO$listDir
	.cfi_endproc
                                        // -- End function
	.globl	IO$listDirKeep                  // -- Begin function IO$listDirKeep
	.p2align	2
	.type	IO$listDirKeep,@function
IO$listDirKeep:                         // @"IO$listDirKeep"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-80]!           // 16-byte Folded Spill
	str	x25, [sp, #16]                  // 8-byte Spill
	stp	x24, x23, [sp, #32]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #48]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #64]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 80
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -40
	.cfi_offset w24, -48
	.cfi_offset w25, -64
	.cfi_offset w30, -72
	.cfi_offset w29, -80
	ldr	x8, [x0]
	cmp	x1, x8
	b.ge	.LBB300_14
// %bb.1:                               // %label_11.lr.ph
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	adrp	x22, .Lstrhdr_3+16
	add	x22, x22, :lo12:.Lstrhdr_3+16
	adrp	x23, .Lstrhdr_14+16
	add	x23, x23, :lo12:.Lstrhdr_14+16
	b	.LBB300_5
.LBB300_2:                              // %label_29.sink.split
                                        //   in Loop: Header=BB300_5 Depth=1
	mov	x0, x23
	bl	axiom_release
.LBB300_3:                              // %label_29
                                        //   in Loop: Header=BB300_5 Depth=1
	mov	x0, x21
	mov	x1, x24
	mov	x2, xzr
	bl	Vec$vecPush
	ldr	x8, [x21]
	sub	x1, x8, #1
	bl	IO$listDirSift
.LBB300_4:                              // %label_30
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x19]
	add	x20, x20, #1
	cmp	x20, x8
	b.ge	.LBB300_14
.LBB300_5:                              // %label_11
                                        // =>This Inner Loop Header: Depth=1
	tbnz	x20, #63, .LBB300_7
// %bb.6:                               // %label_11.i
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x19, #16]
	ldr	x24, [x8, x20, lsl #3]
	b	.LBB300_8
.LBB300_7:                              //   in Loop: Header=BB300_5 Depth=1
	mov	x24, xzr
.LBB300_8:                              // %"Vec$vecGet.exit"
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x24]
	cmp	x8, #1
	b.ne	.LBB300_10
// %bb.9:                               // %"Mem$memCmp.exit.loopexit.i"
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x24, #8]
	mov	x0, x22
	ldrb	w25, [x8]
	bl	axiom_release
	cmp	w25, #46
	b.eq	.LBB300_4
	b	.LBB300_11
.LBB300_10:                             // %label_19.critedge
                                        //   in Loop: Header=BB300_5 Depth=1
	mov	x0, x22
	bl	axiom_release
.LBB300_11:                             // %label_19
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x24]
	cmp	x8, #2
	b.ne	.LBB300_2
// %bb.12:                              // %label_6.i15
                                        //   in Loop: Header=BB300_5 Depth=1
	ldr	x8, [x24, #8]
	ldrb	w9, [x8]
	cmp	w9, #46
	b.ne	.LBB300_2
// %bb.13:                              // %label_3.i.i.i19.1
                                        //   in Loop: Header=BB300_5 Depth=1
	ldrb	w25, [x8, #1]
	mov	x0, x23
	bl	axiom_release
	cmp	w25, #46
	b.ne	.LBB300_3
	b	.LBB300_4
.LBB300_14:                             // %label_12
	ldp	x20, x19, [sp, #64]             // 16-byte Folded Reload
	mov	x0, xzr
	ldp	x22, x21, [sp, #48]             // 16-byte Folded Reload
	ldr	x25, [sp, #16]                  // 8-byte Reload
	ldp	x24, x23, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #80             // 16-byte Folded Reload
	ret
.Lfunc_end300:
	.size	IO$listDirKeep, .Lfunc_end300-IO$listDirKeep
	.cfi_endproc
                                        // -- End function
	.globl	IO$listDirInsert                // -- Begin function IO$listDirInsert
	.p2align	2
	.type	IO$listDirInsert,@function
IO$listDirInsert:                       // @"IO$listDirInsert"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	x2, xzr
	bl	Vec$vecPush
	ldr	x8, [x0]
	sub	x1, x8, #1
	bl	IO$listDirSift
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end301:
	.size	IO$listDirInsert, .Lfunc_end301-IO$listDirInsert
	.cfi_endproc
                                        // -- End function
	.globl	IO$listDirSift                  // -- Begin function IO$listDirSift
	.p2align	2
	.type	IO$listDirSift,@function
IO$listDirSift:                         // @"IO$listDirSift"
	.cfi_startproc
// %bb.0:
	cmp	x1, #1
	b.lt	.LBB302_24
// %bb.1:                               // %label_8.lr.ph
	stp	x29, x30, [sp, #-64]!           // 16-byte Folded Spill
	str	x23, [sp, #16]                  // 8-byte Spill
	stp	x22, x21, [sp, #32]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #48]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 64
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w23, -48
	.cfi_offset w30, -56
	.cfi_offset w29, -64
	mov	x19, x1
	mov	x20, x0
	b	.LBB302_4
.LBB302_2:                              // %label_17.i44
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	str	x22, [x8, x19, lsl #3]
.LBB302_3:                              // %"Vec$vecSet.exit56"
                                        //   in Loop: Header=BB302_4 Depth=1
	cmp	x19, #1
	mov	x19, x21
	b.le	.LBB302_23
.LBB302_4:                              // %label_8
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB302_12 Depth 2
	ldr	x8, [x20]
	sub	x21, x19, #1
	cmp	x19, x8
	b.le	.LBB302_6
// %bb.5:                               //   in Loop: Header=BB302_4 Depth=1
	mov	x22, xzr
	b	.LBB302_7
.LBB302_6:                              // %label_11.i
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	ldr	x22, [x8, x21, lsl #3]
.LBB302_7:                              // %label_4.i11
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20]
	cmp	x19, x8
	b.ge	.LBB302_9
// %bb.8:                               // %label_11.i16
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	ldr	x23, [x8, x19, lsl #3]
	b	.LBB302_10
.LBB302_9:                              //   in Loop: Header=BB302_4 Depth=1
	mov	x23, xzr
.LBB302_10:                             // %"Vec$vecGet.exit22"
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x9, [x22]
	ldr	x10, [x23]
	subs	x8, x9, x10
	csel	x9, x9, x10, lt
	cmp	x9, #1
	b.lt	.LBB302_14
// %bb.11:                              // %label_3.lr.ph.i.i.i
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x10, [x23, #8]
	ldr	x11, [x22, #8]
	mov	x12, xzr
.LBB302_12:                             // %label_3.i.i.i
                                        //   Parent Loop BB302_4 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldrb	w13, [x11, x12]
	ldrb	w14, [x10, x12]
	add	x12, x12, #1
	cmp	x12, x9
	sub	x13, x13, x14
	b.ge	.LBB302_15
// %bb.13:                              // %label_3.i.i.i
                                        //   in Loop: Header=BB302_12 Depth=2
	cbz	x13, .LBB302_12
	b	.LBB302_15
.LBB302_14:                             //   in Loop: Header=BB302_4 Depth=1
	mov	x13, xzr
.LBB302_15:                             // %"Str$strCmp.exit"
                                        //   in Loop: Header=BB302_4 Depth=1
	cmp	x13, #0
	csel	x8, x8, x13, eq
	cmp	x8, #1
	b.lt	.LBB302_23
// %bb.16:                              // %label_4.i28
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20]
	cmp	x19, x8
	b.gt	.LBB302_20
// %bb.17:                              // %label_11.i32
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #24]
	cmp	x8, #1
	b.ne	.LBB302_19
// %bb.18:                              // %label_15.i
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	ldr	x0, [x8, x21, lsl #3]
	str	xzr, [x8, x21, lsl #3]
	bl	axiom_release
.LBB302_19:                             // %label_17.i
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	str	x23, [x8, x21, lsl #3]
.LBB302_20:                             // %label_4.i36
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20]
	cmp	x19, x8
	b.ge	.LBB302_3
// %bb.21:                              // %label_11.i40
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #24]
	cmp	x8, #1
	b.ne	.LBB302_2
// %bb.22:                              // %label_15.i50
                                        //   in Loop: Header=BB302_4 Depth=1
	ldr	x8, [x20, #16]
	ldr	x0, [x8, x19, lsl #3]
	str	xzr, [x8, x19, lsl #3]
	bl	axiom_release
	b	.LBB302_2
.LBB302_23:
	ldp	x20, x19, [sp, #48]             // 16-byte Folded Reload
	ldr	x23, [sp, #16]                  // 8-byte Reload
	ldp	x22, x21, [sp, #32]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #64             // 16-byte Folded Reload
.LBB302_24:                             // %label_9
	mov	x0, xzr
	ret
.Lfunc_end302:
	.size	IO$listDirSift, .Lfunc_end302-IO$listDirSift
	.cfi_endproc
                                        // -- End function
	.globl	IO$cwd                          // -- Begin function IO$cwd
	.p2align	2
	.type	IO$cwd,@function
IO$cwd:                                 // @"IO$cwd"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	Sys$sysGetCwd
.Lfunc_end303:
	.size	IO$cwd, .Lfunc_end303-IO$cwd
	.cfi_endproc
                                        // -- End function
	.globl	IO$exit                         // -- Begin function IO$exit
	.p2align	2
	.type	IO$exit,@function
IO$exit:                                // @"IO$exit"
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w8, #94                         // =0x5e
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end304:
	.size	IO$exit, .Lfunc_end304-IO$exit
                                        // -- End function
	.globl	IO$die                          // -- Begin function IO$die
	.p2align	2
	.type	IO$die,@function
IO$die:                                 // @"IO$die"
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	stp	x22, x21, [sp, #16]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	mov	x22, x0
	cmp	x0, #1, lsl #12                 // =4096
	mov	x19, x1
	b.lt	.LBB305_3
// %bb.1:                               // %chk.i.i
	ldur	x8, [x22, #-16]
	cmn	x8, #1
	b.eq	.LBB305_3
// %bb.2:                               // %bump.i.i
	add	x8, x8, #1
	stur	x8, [x22, #-16]
.LBB305_3:                              // %"Show#String#show.exit"
	adrp	x21, .Lstrhdr_13+16
	add	x21, x21, :lo12:.Lstrhdr_13+16
	mov	x0, x22
	mov	x1, x21
	bl	Str$strConcat
	mov	x20, x0
	mov	x0, x22
	bl	axiom_release
	mov	x0, x21
	bl	axiom_release
	ldr	x9, [x20]
	cmp	x9, #1
	b.lt	.LBB305_6
// %bb.4:                               // %label_11.i.i.preheader
	ldr	x10, [x20, #8]
	mov	x11, xzr
.LBB305_5:                              // %label_11.i.i
                                        // =>This Inner Loop Header: Depth=1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	add	x1, x11, x10
	sub	x2, x9, x11
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	//APP
	svc	#0
	//NO_APP
	add	x11, x0, x11
	cmp	x0, #1
	ccmp	x11, x9, #0, ge
	b.lt	.LBB305_5
.LBB305_6:                              // %"IO$writeStr.exit"
	mov	w8, #94                         // =0x5e
	mov	x0, x19
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, xzr
	ldp	x22, x21, [sp, #16]             // 16-byte Folded Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end305:
	.size	IO$die, .Lfunc_end305-IO$die
	.cfi_endproc
                                        // -- End function
	.globl	ask                             // -- Begin function ask
	.p2align	2
	.type	ask,@function
ask:                                    // @ask
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, #140737488355328            // =0x800000000000
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	axiom_alloc
.Lfunc_end306:
	.size	ask, .Lfunc_end306-ask
                                        // -- End function
	.globl	usable                          // -- Begin function usable
	.p2align	2
	.type	usable,@function
usable:                                 // @usable
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	w0, #64                         // =0x40
	mov	x29, sp
	bl	axiom_alloc
	mov	x8, x0
	mov	w9, #4242                       // =0x1092
	mov	w0, #4242                       // =0x1092
	str	x9, [x8]
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end307:
	.size	usable, .Lfunc_end307-usable
                                        // -- End function
	.globl	__axiom_user_main               // -- Begin function __axiom_user_main
	.p2align	2
	.type	__axiom_user_main,@function
__axiom_user_main:                      // @__axiom_user_main
	.cfi_startproc
// %bb.0:                               // %label_12
	stp	d15, d14, [sp, #-112]!          // 16-byte Folded Spill
	stp	d13, d12, [sp, #16]             // 16-byte Folded Spill
	stp	d11, d10, [sp, #32]             // 16-byte Folded Spill
	stp	d9, d8, [sp, #48]               // 16-byte Folded Spill
	stp	x29, x30, [sp, #64]             // 16-byte Folded Spill
	stp	x22, x21, [sp, #80]             // 16-byte Folded Spill
	stp	x20, x19, [sp, #96]             // 16-byte Folded Spill
	add	x29, sp, #64
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -24
	.cfi_offset w22, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	.cfi_offset b8, -56
	.cfi_offset b9, -64
	.cfi_offset b10, -72
	.cfi_offset b11, -80
	.cfi_offset b12, -88
	.cfi_offset b13, -96
	.cfi_offset b14, -104
	.cfi_offset b15, -112
	mov	w0, #24                         // =0x18
	bl	axiom_alloc
	adrp	x8, __axiom_bump
	adrp	x9, __axiom_bump_end
	adrp	x10, __axiom_chunk
	ldr	x8, [x8, :lo12:__axiom_bump]
	ldr	x9, [x9, :lo12:__axiom_bump_end]
	ldr	x10, [x10, :lo12:__axiom_chunk]
	mov	x19, x0
	stp	x8, x9, [x0]
	str	x10, [x0, #16]
	mov	w0, #128                        // =0x80
	bl	axiom_alloc
	adrp	x21, __axiom_recover_top
	mov	x20, x0
	ldr	x22, [x21, :lo12:__axiom_recover_top]
	str	x19, [x0, #24]
	stp	x22, xzr, [x0, #32]
	str	x0, [x21, :lo12:__axiom_recover_top]
	//APP
	stp	x19, x20, [x20, #48]
	stp	x21, x22, [x20, #64]
	stp	x23, x24, [x20, #80]
	stp	x25, x26, [x20, #96]
	stp	x27, x28, [x20, #112]
	mov	x9, sp
	str	x9, [x20]
	str	x29, [x20, #8]
	adr	x9, .Ltmp0
	str	x9, [x20, #16]
	b	.Ltmp1
.Ltmp0:
	ldp	x19, x20, [x9, #48]
	ldp	x21, x22, [x9, #64]
	ldp	x23, x24, [x9, #80]
	ldp	x25, x26, [x9, #96]
	ldp	x27, x28, [x9, #112]
.Ltmp1:
	//NO_APP
	ldr	x19, [x20, #40]
	cbnz	x19, .LBB308_2
// %bb.1:                               // %label_13
	mov	w0, #8                          // =0x8
	bl	axiom_alloc
	adrp	x8, :got:_lam_0
	mov	w9, #1                          // =0x1
	mov	w10, #4                         // =0x4
	ldr	x8, [x8, :got_lo12:_lam_0]
	mov	x1, xzr
	mov	x20, x0
	stur	x9, [x0, #-16]
	stp	x10, x8, [x0, #-8]
	blr	x8
	mov	x19, x0
	mov	x0, x20
	bl	axiom_release
.LBB308_2:                              // %label_14
	mov	w0, #64                         // =0x40
	str	x22, [x21, :lo12:__axiom_recover_top]
	bl	axiom_alloc
	mov	x8, #-9223372036854775808       // =0x8000000000000000
	mov	w9, #4242                       // =0x1092
	cmp	x19, x8
	str	x9, [x0]
	b.ne	.LBB308_4
// %bb.3:
	adrp	x19, .Lstrhdr_0+16
	add	x19, x19, :lo12:.Lstrhdr_0+16
	b	.LBB308_7
.LBB308_4:                              // %label_3.i.i
	tbnz	x19, #63, .LBB308_6
// %bb.5:                               // %label_10.i.i
	mov	x0, x19
	bl	Fmt$fmtNat
	mov	x19, x0
	b	.LBB308_7
.LBB308_6:                              // %label_9.i.i
	neg	x0, x19
	bl	Fmt$fmtNat
	mov	x20, x0
	adrp	x21, .Lstrhdr_1+16
	add	x21, x21, :lo12:.Lstrhdr_1+16
	mov	x0, x21
	mov	x1, x20
	bl	Str$strConcat
	mov	x19, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
.LBB308_7:                              // %"Show#Int#show.exit"
	adrp	x20, .Lstrhdr_15+16
	add	x20, x20, :lo12:.Lstrhdr_15+16
	mov	x1, x19
	mov	x0, x20
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	adrp	x20, .Lstrhdr_13+16
	add	x20, x20, :lo12:.Lstrhdr_13+16
	mov	x0, x21
	mov	x1, x20
	bl	Str$strConcat
	mov	x19, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	ldr	x9, [x19]
	cmp	x9, #1
	b.lt	.LBB308_10
// %bb.8:                               // %label_11.i.i.preheader
	ldr	x10, [x19, #8]
	mov	x11, xzr
.LBB308_9:                              // %label_11.i.i
                                        // =>This Inner Loop Header: Depth=1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	add	x1, x11, x10
	sub	x2, x9, x11
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	//APP
	svc	#0
	//NO_APP
	add	x11, x0, x11
	cmp	x0, #1
	ccmp	x11, x9, #0, ge
	b.lt	.LBB308_9
.LBB308_10:                             // %"IO$writeStr.exit"
	mov	w0, #4242                       // =0x1092
	bl	Fmt$fmtNat
	mov	x19, x0
	adrp	x20, .Lstrhdr_16+16
	add	x20, x20, :lo12:.Lstrhdr_16+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	adrp	x20, .Lstrhdr_13+16
	add	x20, x20, :lo12:.Lstrhdr_13+16
	mov	x0, x21
	mov	x1, x20
	bl	Str$strConcat
	mov	x19, x0
	mov	x0, x21
	bl	axiom_release
	mov	x0, x20
	bl	axiom_release
	ldr	x9, [x19]
	cmp	x9, #1
	b.lt	.LBB308_13
// %bb.11:                              // %label_11.i.i11.preheader
	ldr	x10, [x19, #8]
	mov	x11, xzr
.LBB308_12:                             // %label_11.i.i11
                                        // =>This Inner Loop Header: Depth=1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	add	x1, x11, x10
	sub	x2, x9, x11
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	//APP
	svc	#0
	//NO_APP
	add	x11, x0, x11
	cmp	x0, #1
	ccmp	x11, x9, #0, ge
	b.lt	.LBB308_12
.LBB308_13:                             // %"IO$writeStr.exit23"
	mov	x0, #140737488355328            // =0x800000000000
	bl	axiom_alloc
	mov	x9, xzr
	adrp	x10, .Lstr_17
	add	x10, x10, :lo12:.Lstr_17
	mov	w11, #55                        // =0x37
.LBB308_14:                             // %label_11.i.i.i
                                        // =>This Inner Loop Header: Depth=1
	add	x1, x9, x10
	sub	x2, x11, x9
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x0, #1
	b.lt	.LBB308_16
// %bb.15:                              // %label_11.i.i.i
                                        //   in Loop: Header=BB308_14 Depth=1
	add	x9, x0, x9
	cmp	x9, #55
	b.lt	.LBB308_14
.LBB308_16:                             // %"IO$printlnLit.exit"
	adrp	x1, .Lstr_13
	add	x1, x1, :lo12:.Lstr_13
	mov	w8, #64                         // =0x40
	mov	w0, #1                          // =0x1
	mov	w2, #1                          // =0x1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	ldp	x20, x19, [sp, #96]             // 16-byte Folded Reload
	ldp	x22, x21, [sp, #80]             // 16-byte Folded Reload
	ldp	x29, x30, [sp, #64]             // 16-byte Folded Reload
	ldp	d9, d8, [sp, #48]               // 16-byte Folded Reload
	ldp	d11, d10, [sp, #32]             // 16-byte Folded Reload
	ldp	d13, d12, [sp, #16]             // 16-byte Folded Reload
	ldp	d15, d14, [sp], #112            // 16-byte Folded Reload
	ret
.Lfunc_end308:
	.size	__axiom_user_main, .Lfunc_end308-__axiom_user_main
	.cfi_endproc
                                        // -- End function
	.globl	_lam_0                          // -- Begin function _lam_0
	.p2align	2
	.type	_lam_0,@function
_lam_0:                                 // @_lam_0
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, #140737488355328            // =0x800000000000
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	b	axiom_alloc
.Lfunc_end309:
	.size	_lam_0, .Lfunc_end309-_lam_0
                                        // -- End function
	.globl	"Show#String#show"              // -- Begin function Show#String#show
	.p2align	2
	.type	"Show#String#show",@function
"Show#String#show":                     // @"Show#String#show"
// %bb.0:
	cmp	x0, #1, lsl #12                 // =4096
	b.lt	.LBB310_4
// %bb.1:                               // %chk.i
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	ldur	x8, [x0, #-16]
	mov	x29, sp
	cmn	x8, #1
	b.eq	.LBB310_3
// %bb.2:                               // %bump.i
	add	x8, x8, #1
	stur	x8, [x0, #-16]
.LBB310_3:
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
.LBB310_4:                              // %axiom_retain.exit
	ret
.Lfunc_end310:
	.size	"Show#String#show", .Lfunc_end310-"Show#String#show"
                                        // -- End function
	.globl	"Show#Int#show"                 // -- Begin function Show#Int#show
	.p2align	2
	.type	"Show#Int#show",@function
"Show#Int#show":                        // @"Show#Int#show"
	.cfi_startproc
// %bb.0:
	mov	x8, #-9223372036854775808       // =0x8000000000000000
	cmp	x0, x8
	b.ne	.LBB311_2
// %bb.1:                               // %"Fmt$fmtInt.exit"
	adrp	x0, .Lstrhdr_0+16
	add	x0, x0, :lo12:.Lstrhdr_0+16
	ret
.LBB311_2:                              // %label_3.i
	tbnz	x0, #63, .LBB311_4
// %bb.3:                               // %label_10.i
	b	Fmt$fmtNat
.LBB311_4:                              // %label_9.i
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	neg	x0, x0
	bl	Fmt$fmtNat
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.Lfunc_end311:
	.size	"Show#Int#show", .Lfunc_end311-"Show#Int#show"
	.cfi_endproc
                                        // -- End function
	.globl	"Show#Bool#show"                // -- Begin function Show#Bool#show
	.p2align	2
	.type	"Show#Bool#show",@function
"Show#Bool#show":                       // @"Show#Bool#show"
// %bb.0:                               // %label_3
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	adrp	x8, .Lstrhdr_18+16
	add	x8, x8, :lo12:.Lstrhdr_18+16
	cmp	x0, #0
	adrp	x9, .Lstrhdr_19+16
	add	x9, x9, :lo12:.Lstrhdr_19+16
	mov	x29, sp
	csel	x0, x9, x8, eq
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end312:
	.size	"Show#Bool#show", .Lfunc_end312-"Show#Bool#show"
                                        // -- End function
	.globl	"Show#Float#show"               // -- Begin function Show#Float#show
	.p2align	2
	.type	"Show#Float#show",@function
"Show#Float#show":                      // @"Show#Float#show"
	.cfi_startproc
// %bb.0:
	fmov	d0, x0
	fcmp	d0, #0.0
	b.pl	.LBB313_2
// %bb.1:                               // %label_5.i.i
	stp	x29, x30, [sp, #-48]!           // 16-byte Folded Spill
	str	x21, [sp, #16]                  // 8-byte Spill
	stp	x20, x19, [sp, #32]             // 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 48
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	.cfi_offset w21, -32
	.cfi_offset w30, -40
	.cfi_offset w29, -48
	movi	d1, #0000000000000000
	mov	w1, #6                          // =0x6
	fsub	d0, d1, d0
	fmov	x0, d0
	bl	Fmt$fmtFloatAbs
	mov	x19, x0
	adrp	x20, .Lstrhdr_1+16
	add	x20, x20, :lo12:.Lstrhdr_1+16
	mov	x0, x20
	mov	x1, x19
	bl	Str$strConcat
	mov	x21, x0
	mov	x0, x20
	bl	axiom_release
	mov	x0, x19
	bl	axiom_release
	ldp	x20, x19, [sp, #32]             // 16-byte Folded Reload
	mov	x0, x21
	ldr	x21, [sp, #16]                  // 8-byte Reload
	ldp	x29, x30, [sp], #48             // 16-byte Folded Reload
	ret
.LBB313_2:                              // %label_6.i.i
	mov	w1, #6                          // =0x6
	b	Fmt$fmtFloatAbs
.Lfunc_end313:
	.size	"Show#Float#show", .Lfunc_end313-"Show#Float#show"
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_recover_save
	.type	__axiom_recover_save,@function
__axiom_recover_save:                   // @__axiom_recover_save
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end314:
	.size	__axiom_recover_save, .Lfunc_end314-__axiom_recover_save
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_recover_load
	.type	__axiom_recover_load,@function
__axiom_recover_load:                   // @__axiom_recover_load
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x29, sp
	mov	x0, xzr
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end315:
	.size	__axiom_recover_load, .Lfunc_end315-__axiom_recover_load
                                        // -- End function
	.p2align	2                               // -- Begin function __axiom_backtrace
	.type	__axiom_backtrace,@function
__axiom_backtrace:                      // @__axiom_backtrace
// %bb.0:                               // %entry
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	adrp	x1, .L__axiom_bt_hdr
	add	x1, x1, :lo12:.L__axiom_bt_hdr
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	mov	w2, #42                         // =0x2a
	adrp	x16, :got:main
	//APP
	svc	#0
	//NO_APP
	mov	x14, xzr
	adrp	x15, __axiom_symtab+16
	add	x15, x15, :lo12:__axiom_symtab+16
	ldr	x16, [x16, :got_lo12:main]
	adrp	x9, .L__axiom_bt_at
	add	x9, x9, :lo12:.L__axiom_bt_at
	adrp	x10, .L__axiom_bt_unk
	add	x10, x10, :lo12:.L__axiom_bt_unk
	adrp	x11, .L__axiom_bt_nl
	add	x11, x11, :lo12:.L__axiom_bt_nl
	mov	x29, sp
	//APP
	mov	x17, x29
	//NO_APP
.LBB316_1:                              // %loop
                                        // =>This Loop Header: Depth=1
                                        //     Child Loop BB316_6 Depth 2
	tst	x17, #0x7
	b.ne	.LBB316_12
// %bb.2:                               // %loop
                                        //   in Loop: Header=BB316_1 Depth=1
	cbz	x17, .LBB316_12
// %bb.3:                               // %loop
                                        //   in Loop: Header=BB316_1 Depth=1
	cmp	x14, #63
	b.hi	.LBB316_12
// %bb.4:                               // %read
                                        //   in Loop: Header=BB316_1 Depth=1
	ldr	x8, [x17, #8]
	cbz	x8, .LBB316_12
// %bb.5:                               // %frame
                                        //   in Loop: Header=BB316_1 Depth=1
	ldr	x18, [x17]
	mov	x12, xzr
	mov	x13, xzr
	mov	x6, xzr
	sub	x8, x8, #1
	mov	x0, x15
	mov	w1, #316                        // =0x13c
.LBB316_6:                              // %body.i
                                        //   Parent Loop BB316_1 Depth=1
                                        // =>  This Inner Loop Header: Depth=2
	ldp	x2, x3, [x0, #-16]
	ldr	x4, [x0], #24
	cmp	x2, x8
	ccmp	x2, x6, #0, ls
	csel	x6, x2, x6, hi
	csel	x13, x3, x13, hi
	csel	x12, x4, x12, hi
	subs	x1, x1, #1
	b.ne	.LBB316_6
// %bb.7:                               // %emit.i
                                        //   in Loop: Header=BB316_1 Depth=1
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	mov	x1, x9
	mov	w2, #5                          // =0x5
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	cbz	x13, .LBB316_9
// %bb.8:                               // %named.i
                                        //   in Loop: Header=BB316_1 Depth=1
	mov	x1, x13
	mov	x2, x12
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	b	.LBB316_10
.LBB316_9:                              // %unknown.i
                                        //   in Loop: Header=BB316_1 Depth=1
	mov	x1, x10
	mov	w2, #9                          // =0x9
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
.LBB316_10:                             // %__axiom_bt_name.exit
                                        //   in Loop: Header=BB316_1 Depth=1
	mov	w8, #64                         // =0x40
	mov	w0, #2                          // =0x2
	mov	x1, x11
	mov	w2, #1                          // =0x1
	mov	x3, xzr
	mov	x4, xzr
	mov	x5, xzr
	//APP
	svc	#0
	//NO_APP
	cmp	x18, x17
	b.ls	.LBB316_12
// %bb.11:                              // %__axiom_bt_name.exit
                                        //   in Loop: Header=BB316_1 Depth=1
	cmp	x6, x16
	add	x14, x14, #1
	mov	x17, x18
	b.ne	.LBB316_1
.LBB316_12:                             // %done
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	ret
.Lfunc_end316:
	.size	__axiom_backtrace, .Lfunc_end316-__axiom_backtrace
                                        // -- End function
	.type	__axiom_argc,@object            // @__axiom_argc
	.local	__axiom_argc
	.comm	__axiom_argc,8,8
	.type	__axiom_argv,@object            // @__axiom_argv
	.local	__axiom_argv
	.comm	__axiom_argv,8,8
	.type	__axiom_bump,@object            // @__axiom_bump
	.local	__axiom_bump
	.comm	__axiom_bump,8,8
	.type	__axiom_bump_end,@object        // @__axiom_bump_end
	.local	__axiom_bump_end
	.comm	__axiom_bump_end,8,8
	.type	__axiom_chunk,@object           // @__axiom_chunk
	.local	__axiom_chunk
	.comm	__axiom_chunk,8,8
	.type	__axiom_free,@object            // @__axiom_free
	.local	__axiom_free
	.comm	__axiom_free,8,8
	.type	__axiom_high,@object            // @__axiom_high
	.local	__axiom_high
	.comm	__axiom_high,8,8
	.type	__axiom_slabs,@object           // @__axiom_slabs
	.local	__axiom_slabs
	.comm	__axiom_slabs,32776,16
	.type	.L__axiom_divzero_msg,@object   // @__axiom_divzero_msg
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_divzero_msg:
	.ascii	"axiom: division by zero\n"
	.size	.L__axiom_divzero_msg, 24

	.type	.L__axiom_oom_msg,@object       // @__axiom_oom_msg
	.p2align	4, 0x0
.L__axiom_oom_msg:
	.ascii	"axiom: out of memory (mmap failed)\n"
	.size	.L__axiom_oom_msg, 35

	.type	__axiom_recover_top,@object     // @__axiom_recover_top
	.local	__axiom_recover_top
	.comm	__axiom_recover_top,8,8
	.type	.Lstr_0,@object                 // @str_0
	.section	.rodata.str1.16,"aMS",@progbits,1
	.p2align	4, 0x0
.Lstr_0:
	.asciz	"-9223372036854775808"
	.size	.Lstr_0, 21

	.type	.Lstrhdr_0,@object              // @strhdr_0
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_0:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	20                              // 0x14
	.xword	.Lstr_0
	.xword	0                               // 0x0
	.size	.Lstrhdr_0, 40

	.type	.Lstr_1,@object                 // @str_1
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_1:
	.asciz	"-"
	.size	.Lstr_1, 2

	.type	.Lstrhdr_1,@object              // @strhdr_1
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_1:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_1
	.xword	0                               // 0x0
	.size	.Lstrhdr_1, 40

	.type	.Lstr_2,@object                 // @str_2
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_2:
	.asciz	"0"
	.size	.Lstr_2, 2

	.type	.Lstrhdr_2,@object              // @strhdr_2
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_2:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_2
	.xword	0                               // 0x0
	.size	.Lstrhdr_2, 40

	.type	.Lstr_3,@object                 // @str_3
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_3:
	.asciz	"."
	.size	.Lstr_3, 2

	.type	.Lstrhdr_3,@object              // @strhdr_3
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_3:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_3
	.xword	0                               // 0x0
	.size	.Lstrhdr_3, 40

	.type	.Lstr_4,@object                 // @str_4
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_4:
	.zero	1
	.size	.Lstr_4, 1

	.type	.Lstrhdr_4,@object              // @strhdr_4
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_4:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	0                               // 0x0
	.xword	.Lstr_4
	.xword	0                               // 0x0
	.size	.Lstrhdr_4, 40

	.type	.Lstr_5,@object                 // @str_5
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_5:
	.asciz	"="
	.size	.Lstr_5, 2

	.type	.Lstrhdr_5,@object              // @strhdr_5
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_5:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_5
	.xword	0                               // 0x0
	.size	.Lstrhdr_5, 40

	.type	.Lstr_6,@object                 // @str_6
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_6:
	.asciz	"PATH"
	.size	.Lstr_6, 5

	.type	.Lstrhdr_6,@object              // @strhdr_6
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_6:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	4                               // 0x4
	.xword	.Lstr_6
	.xword	0                               // 0x0
	.size	.Lstrhdr_6, 40

	.type	.Lstr_7,@object                 // @str_7
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_7:
	.asciz	"/"
	.size	.Lstr_7, 2

	.type	.Lstrhdr_7,@object              // @strhdr_7
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_7:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_7
	.xword	0                               // 0x0
	.size	.Lstrhdr_7, 40

	.type	.Lstr_8,@object                 // @str_8
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_8:
	.asciz	"af="
	.size	.Lstr_8, 4

	.type	.Lstrhdr_8,@object              // @strhdr_8
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_8:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	3                               // 0x3
	.xword	.Lstr_8
	.xword	0                               // 0x0
	.size	.Lstrhdr_8, 40

	.type	.Lstr_9,@object                 // @str_9
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_9:
	.asciz	"::"
	.size	.Lstr_9, 3

	.type	.Lstrhdr_9,@object              // @strhdr_9
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_9:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	2                               // 0x2
	.xword	.Lstr_9
	.xword	0                               // 0x0
	.size	.Lstrhdr_9, 40

	.type	.Lstr_10,@object                // @str_10
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_10:
	.asciz	":"
	.size	.Lstr_10, 2

	.type	.Lstrhdr_10,@object             // @strhdr_10
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_10:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_10
	.xword	0                               // 0x0
	.size	.Lstrhdr_10, 40

	.type	.Lstr_11,@object                // @str_11
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_11:
	.asciz	"["
	.size	.Lstr_11, 2

	.type	.Lstrhdr_11,@object             // @strhdr_11
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_11:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_11
	.xword	0                               // 0x0
	.size	.Lstrhdr_11, 40

	.type	.Lstr_12,@object                // @str_12
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_12:
	.asciz	"]:"
	.size	.Lstr_12, 3

	.type	.Lstrhdr_12,@object             // @strhdr_12
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_12:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	2                               // 0x2
	.xword	.Lstr_12
	.xword	0                               // 0x0
	.size	.Lstrhdr_12, 40

	.type	.Lstr_13,@object                // @str_13
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_13:
	.asciz	"\n"
	.size	.Lstr_13, 2

	.type	.Lstrhdr_13,@object             // @strhdr_13
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_13:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	1                               // 0x1
	.xword	.Lstr_13
	.xword	0                               // 0x0
	.size	.Lstrhdr_13, 40

	.type	.Lstr_14,@object                // @str_14
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_14:
	.asciz	".."
	.size	.Lstr_14, 3

	.type	.Lstrhdr_14,@object             // @strhdr_14
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_14:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	2                               // 0x2
	.xword	.Lstr_14
	.xword	0                               // 0x0
	.size	.Lstrhdr_14, 40

	.type	.Lstr_15,@object                // @str_15
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_15:
	.asciz	"recovered "
	.size	.Lstr_15, 11

	.type	.Lstrhdr_15,@object             // @strhdr_15
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_15:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	10                              // 0xa
	.xword	.Lstr_15
	.xword	0                               // 0x0
	.size	.Lstrhdr_15, 40

	.type	.Lstr_16,@object                // @str_16
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_16:
	.asciz	"usable "
	.size	.Lstr_16, 8

	.type	.Lstrhdr_16,@object             // @strhdr_16
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_16:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	7                               // 0x7
	.xword	.Lstr_16
	.xword	0                               // 0x0
	.size	.Lstrhdr_16, 40

	.type	.Lstr_17,@object                // @str_17
	.section	.rodata.str1.16,"aMS",@progbits,1
	.p2align	4, 0x0
.Lstr_17:
	.asciz	"UNREACHABLE: the trap outside a recovery point returned"
	.size	.Lstr_17, 56

	.type	.Lstr_18,@object                // @str_18
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_18:
	.asciz	"true"
	.size	.Lstr_18, 5

	.type	.Lstrhdr_18,@object             // @strhdr_18
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_18:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	4                               // 0x4
	.xword	.Lstr_18
	.xword	0                               // 0x0
	.size	.Lstrhdr_18, 40

	.type	.Lstr_19,@object                // @str_19
	.section	.rodata.str1.4,"aMS",@progbits,1
	.p2align	2, 0x0
.Lstr_19:
	.asciz	"false"
	.size	.Lstr_19, 6

	.type	.Lstrhdr_19,@object             // @strhdr_19
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lstrhdr_19:
	.xword	-1                              // 0xffffffffffffffff
	.xword	0                               // 0x0
	.xword	5                               // 0x5
	.xword	.Lstr_19
	.xword	0                               // 0x0
	.size	.Lstrhdr_19, 40

	.type	.L__axiom_symn_0,@object        // @__axiom_symn_0
	.section	.rodata.cst4,"aM",@progbits,4
	.p2align	2, 0x0
.L__axiom_symn_0:
	.ascii	"main"
	.size	.L__axiom_symn_0, 4

	.type	.L__axiom_symn_1,@object        // @__axiom_symn_1
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_1:
	.ascii	"axiom_alloc"
	.size	.L__axiom_symn_1, 11

	.type	.L__axiom_symn_2,@object        // @__axiom_symn_2
	.p2align	2, 0x0
.L__axiom_symn_2:
	.ascii	"axiom_retain"
	.size	.L__axiom_symn_2, 12

	.type	.L__axiom_symn_3,@object        // @__axiom_symn_3
	.p2align	2, 0x0
.L__axiom_symn_3:
	.ascii	"axiom_release"
	.size	.L__axiom_symn_3, 13

	.type	.L__axiom_symn_4,@object        // @__axiom_symn_4
	.p2align	4, 0x0
.L__axiom_symn_4:
	.ascii	"__axiom_arena_mark_fn"
	.size	.L__axiom_symn_4, 21

	.type	.L__axiom_symn_5,@object        // @__axiom_symn_5
	.p2align	4, 0x0
.L__axiom_symn_5:
	.ascii	"__axiom_arena_reset_fn"
	.size	.L__axiom_symn_5, 22

	.type	.L__axiom_symn_6,@object        // @__axiom_symn_6
	.p2align	4, 0x0
.L__axiom_symn_6:
	.ascii	"__axiom_arena_reset_keeping_fn"
	.size	.L__axiom_symn_6, 30

	.type	.L__axiom_symn_7,@object        // @__axiom_symn_7
	.p2align	4, 0x0
.L__axiom_symn_7:
	.ascii	"__axiom_div_by_zero"
	.size	.L__axiom_symn_7, 19

	.type	.L__axiom_symn_8,@object        // @__axiom_symn_8
	.p2align	4, 0x0
.L__axiom_symn_8:
	.ascii	"__axiom_out_of_memory"
	.size	.L__axiom_symn_8, 21

	.type	.L__axiom_symn_9,@object        // @__axiom_symn_9
	.p2align	4, 0x0
.L__axiom_symn_9:
	.ascii	"__axiom_recover_abort"
	.size	.L__axiom_symn_9, 21

	.type	.L__axiom_symn_10,@object       // @__axiom_symn_10
	.p2align	2, 0x0
.L__axiom_symn_10:
	.ascii	"__axiom_str_eq"
	.size	.L__axiom_symn_10, 14

	.type	.L__axiom_symn_11,@object       // @__axiom_symn_11
	.p2align	4, 0x0
.L__axiom_symn_11:
	.ascii	"Sys.Platform$sysRead"
	.size	.L__axiom_symn_11, 20

	.type	.L__axiom_symn_12,@object       // @__axiom_symn_12
	.p2align	4, 0x0
.L__axiom_symn_12:
	.ascii	"Sys.Platform$sysWrite"
	.size	.L__axiom_symn_12, 21

	.type	.L__axiom_symn_13,@object       // @__axiom_symn_13
	.p2align	4, 0x0
.L__axiom_symn_13:
	.ascii	"Sys.Platform$sysOpen"
	.size	.L__axiom_symn_13, 20

	.type	.L__axiom_symn_14,@object       // @__axiom_symn_14
	.p2align	4, 0x0
.L__axiom_symn_14:
	.ascii	"Sys.Platform$sysClose"
	.size	.L__axiom_symn_14, 21

	.type	.L__axiom_symn_15,@object       // @__axiom_symn_15
	.p2align	4, 0x0
.L__axiom_symn_15:
	.ascii	"Sys.Platform$sysExit"
	.size	.L__axiom_symn_15, 20

	.type	.L__axiom_symn_16,@object       // @__axiom_symn_16
	.p2align	4, 0x0
.L__axiom_symn_16:
	.ascii	"Sys.Platform$sysLseek"
	.size	.L__axiom_symn_16, 21

	.type	.L__axiom_symn_17,@object       // @__axiom_symn_17
	.p2align	4, 0x0
.L__axiom_symn_17:
	.ascii	"Sys.Platform$openNeedsDirFd"
	.size	.L__axiom_symn_17, 27

	.type	.L__axiom_symn_18,@object       // @__axiom_symn_18
	.p2align	4, 0x0
.L__axiom_symn_18:
	.ascii	"Sys.Platform$atFdCwd"
	.size	.L__axiom_symn_18, 20

	.type	.L__axiom_symn_19,@object       // @__axiom_symn_19
	.p2align	4, 0x0
.L__axiom_symn_19:
	.ascii	"Sys.Platform$oRdonly"
	.size	.L__axiom_symn_19, 20

	.type	.L__axiom_symn_20,@object       // @__axiom_symn_20
	.p2align	4, 0x0
.L__axiom_symn_20:
	.ascii	"Sys.Platform$oWronlyCreateTrunc"
	.size	.L__axiom_symn_20, 31

	.type	.L__axiom_symn_21,@object       // @__axiom_symn_21
	.section	.rodata.cst32,"aM",@progbits,32
	.p2align	4, 0x0
.L__axiom_symn_21:
	.ascii	"Sys.Platform$oWronlyCreateAppend"
	.size	.L__axiom_symn_21, 32

	.type	.L__axiom_symn_22,@object       // @__axiom_symn_22
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_22:
	.ascii	"Sys.Platform$seekEnd"
	.size	.L__axiom_symn_22, 20

	.type	.L__axiom_symn_23,@object       // @__axiom_symn_23
	.p2align	4, 0x0
.L__axiom_symn_23:
	.ascii	"Sys.Platform$seekSet"
	.size	.L__axiom_symn_23, 20

	.type	.L__axiom_symn_24,@object       // @__axiom_symn_24
	.section	.rodata.cst32,"aM",@progbits,32
	.p2align	4, 0x0
.L__axiom_symn_24:
	.ascii	"Sys.Platform$spawnUsesPosixSpawn"
	.size	.L__axiom_symn_24, 32

	.type	.L__axiom_symn_25,@object       // @__axiom_symn_25
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_25:
	.ascii	"Sys.Platform$sysFork"
	.size	.L__axiom_symn_25, 20

	.type	.L__axiom_symn_26,@object       // @__axiom_symn_26
	.p2align	4, 0x0
.L__axiom_symn_26:
	.ascii	"Sys.Platform$sysForkArg"
	.size	.L__axiom_symn_26, 23

	.type	.L__axiom_symn_27,@object       // @__axiom_symn_27
	.p2align	4, 0x0
.L__axiom_symn_27:
	.ascii	"Sys.Platform$sysExecve"
	.size	.L__axiom_symn_27, 22

	.type	.L__axiom_symn_28,@object       // @__axiom_symn_28
	.p2align	4, 0x0
.L__axiom_symn_28:
	.ascii	"Sys.Platform$sysWait4"
	.size	.L__axiom_symn_28, 21

	.type	.L__axiom_symn_29,@object       // @__axiom_symn_29
	.p2align	4, 0x0
.L__axiom_symn_29:
	.ascii	"Sys.Platform$sysPosixSpawn"
	.size	.L__axiom_symn_29, 26

	.type	.L__axiom_symn_30,@object       // @__axiom_symn_30
	.p2align	4, 0x0
.L__axiom_symn_30:
	.ascii	"Sys.Platform$sysUnlinkNum"
	.size	.L__axiom_symn_30, 25

	.type	.L__axiom_symn_31,@object       // @__axiom_symn_31
	.p2align	4, 0x0
.L__axiom_symn_31:
	.ascii	"Sys.Platform$sysMkdirNum"
	.size	.L__axiom_symn_31, 24

	.type	.L__axiom_symn_32,@object       // @__axiom_symn_32
	.p2align	4, 0x0
.L__axiom_symn_32:
	.ascii	"Sys.Platform$sysRmdirNum"
	.size	.L__axiom_symn_32, 24

	.type	.L__axiom_symn_33,@object       // @__axiom_symn_33
	.p2align	4, 0x0
.L__axiom_symn_33:
	.ascii	"Sys.Platform$sysRenameNum"
	.size	.L__axiom_symn_33, 25

	.type	.L__axiom_symn_34,@object       // @__axiom_symn_34
	.p2align	4, 0x0
.L__axiom_symn_34:
	.ascii	"Sys.Platform$sysGetdentsNum"
	.size	.L__axiom_symn_34, 27

	.type	.L__axiom_symn_35,@object       // @__axiom_symn_35
	.p2align	4, 0x0
.L__axiom_symn_35:
	.ascii	"Sys.Platform$dirReadNeedsPosition"
	.size	.L__axiom_symn_35, 33

	.type	.L__axiom_symn_36,@object       // @__axiom_symn_36
	.p2align	4, 0x0
.L__axiom_symn_36:
	.ascii	"Sys.Platform$direntNameOffset"
	.size	.L__axiom_symn_36, 29

	.type	.L__axiom_symn_37,@object       // @__axiom_symn_37
	.p2align	4, 0x0
.L__axiom_symn_37:
	.ascii	"Sys.Platform$cwdUsesFcntlPath"
	.size	.L__axiom_symn_37, 29

	.type	.L__axiom_symn_38,@object       // @__axiom_symn_38
	.p2align	4, 0x0
.L__axiom_symn_38:
	.ascii	"Sys.Platform$sysCwdNum"
	.size	.L__axiom_symn_38, 22

	.type	.L__axiom_symn_39,@object       // @__axiom_symn_39
	.p2align	4, 0x0
.L__axiom_symn_39:
	.ascii	"Sys.Platform$fGetPath"
	.size	.L__axiom_symn_39, 21

	.type	.L__axiom_symn_40,@object       // @__axiom_symn_40
	.p2align	4, 0x0
.L__axiom_symn_40:
	.ascii	"Sys.Platform$eExist"
	.size	.L__axiom_symn_40, 19

	.type	.L__axiom_symn_41,@object       // @__axiom_symn_41
	.p2align	4, 0x0
.L__axiom_symn_41:
	.ascii	"Sys.Platform$eIsDir"
	.size	.L__axiom_symn_41, 19

	.type	.L__axiom_symn_42,@object       // @__axiom_symn_42
	.p2align	4, 0x0
.L__axiom_symn_42:
	.ascii	"Sys.Platform$sysGetPidNum"
	.size	.L__axiom_symn_42, 25

	.type	.L__axiom_symn_43,@object       // @__axiom_symn_43
	.p2align	4, 0x0
.L__axiom_symn_43:
	.ascii	"Sys.Platform$sysClockNum"
	.size	.L__axiom_symn_43, 24

	.type	.L__axiom_symn_44,@object       // @__axiom_symn_44
	.section	.rodata.cst32,"aM",@progbits,32
	.p2align	4, 0x0
.L__axiom_symn_44:
	.ascii	"Sys.Platform$clockIsGettimeofday"
	.size	.L__axiom_symn_44, 32

	.type	.L__axiom_symn_45,@object       // @__axiom_symn_45
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_45:
	.ascii	"Sys.Platform$clockHasMonotonic"
	.size	.L__axiom_symn_45, 30

	.type	.L__axiom_symn_46,@object       // @__axiom_symn_46
	.p2align	4, 0x0
.L__axiom_symn_46:
	.ascii	"Sys.Platform$sysSocketNum"
	.size	.L__axiom_symn_46, 25

	.type	.L__axiom_symn_47,@object       // @__axiom_symn_47
	.p2align	4, 0x0
.L__axiom_symn_47:
	.ascii	"Sys.Platform$sysBindNum"
	.size	.L__axiom_symn_47, 23

	.type	.L__axiom_symn_48,@object       // @__axiom_symn_48
	.p2align	4, 0x0
.L__axiom_symn_48:
	.ascii	"Sys.Platform$sysListenNum"
	.size	.L__axiom_symn_48, 25

	.type	.L__axiom_symn_49,@object       // @__axiom_symn_49
	.p2align	4, 0x0
.L__axiom_symn_49:
	.ascii	"Sys.Platform$sysAcceptNum"
	.size	.L__axiom_symn_49, 25

	.type	.L__axiom_symn_50,@object       // @__axiom_symn_50
	.p2align	4, 0x0
.L__axiom_symn_50:
	.ascii	"Sys.Platform$sysConnectNum"
	.size	.L__axiom_symn_50, 26

	.type	.L__axiom_symn_51,@object       // @__axiom_symn_51
	.p2align	4, 0x0
.L__axiom_symn_51:
	.ascii	"Sys.Platform$sysSetSockOptNum"
	.size	.L__axiom_symn_51, 29

	.type	.L__axiom_symn_52,@object       // @__axiom_symn_52
	.p2align	4, 0x0
.L__axiom_symn_52:
	.ascii	"Sys.Platform$sysGetSockOptNum"
	.size	.L__axiom_symn_52, 29

	.type	.L__axiom_symn_53,@object       // @__axiom_symn_53
	.p2align	4, 0x0
.L__axiom_symn_53:
	.ascii	"Sys.Platform$sysShutdownNum"
	.size	.L__axiom_symn_53, 27

	.type	.L__axiom_symn_54,@object       // @__axiom_symn_54
	.p2align	4, 0x0
.L__axiom_symn_54:
	.ascii	"Sys.Platform$sysFcntlNum"
	.size	.L__axiom_symn_54, 24

	.type	.L__axiom_symn_55,@object       // @__axiom_symn_55
	.p2align	4, 0x0
.L__axiom_symn_55:
	.ascii	"Sys.Platform$afInet"
	.size	.L__axiom_symn_55, 19

	.type	.L__axiom_symn_56,@object       // @__axiom_symn_56
	.p2align	4, 0x0
.L__axiom_symn_56:
	.ascii	"Sys.Platform$afInet6"
	.size	.L__axiom_symn_56, 20

	.type	.L__axiom_symn_57,@object       // @__axiom_symn_57
	.p2align	4, 0x0
.L__axiom_symn_57:
	.ascii	"Sys.Platform$sockStream"
	.size	.L__axiom_symn_57, 23

	.type	.L__axiom_symn_58,@object       // @__axiom_symn_58
	.p2align	4, 0x0
.L__axiom_symn_58:
	.ascii	"Sys.Platform$solSocket"
	.size	.L__axiom_symn_58, 22

	.type	.L__axiom_symn_59,@object       // @__axiom_symn_59
	.p2align	4, 0x0
.L__axiom_symn_59:
	.ascii	"Sys.Platform$soReuseAddr"
	.size	.L__axiom_symn_59, 24

	.type	.L__axiom_symn_60,@object       // @__axiom_symn_60
	.p2align	4, 0x0
.L__axiom_symn_60:
	.ascii	"Sys.Platform$soReusePort"
	.size	.L__axiom_symn_60, 24

	.type	.L__axiom_symn_61,@object       // @__axiom_symn_61
	.p2align	4, 0x0
.L__axiom_symn_61:
	.ascii	"Sys.Platform$soError"
	.size	.L__axiom_symn_61, 20

	.type	.L__axiom_symn_62,@object       // @__axiom_symn_62
	.p2align	4, 0x0
.L__axiom_symn_62:
	.ascii	"Sys.Platform$fGetFl"
	.size	.L__axiom_symn_62, 19

	.type	.L__axiom_symn_63,@object       // @__axiom_symn_63
	.p2align	4, 0x0
.L__axiom_symn_63:
	.ascii	"Sys.Platform$fSetFl"
	.size	.L__axiom_symn_63, 19

	.type	.L__axiom_symn_64,@object       // @__axiom_symn_64
	.p2align	4, 0x0
.L__axiom_symn_64:
	.ascii	"Sys.Platform$oNonblock"
	.size	.L__axiom_symn_64, 22

	.type	.L__axiom_symn_65,@object       // @__axiom_symn_65
	.p2align	4, 0x0
.L__axiom_symn_65:
	.ascii	"Sys.Platform$eAgain"
	.size	.L__axiom_symn_65, 19

	.type	.L__axiom_symn_66,@object       // @__axiom_symn_66
	.p2align	4, 0x0
.L__axiom_symn_66:
	.ascii	"Sys.Platform$sockaddrHasLenByte"
	.size	.L__axiom_symn_66, 31

	.type	.L__axiom_symn_67,@object       // @__axiom_symn_67
	.p2align	4, 0x0
.L__axiom_symn_67:
	.ascii	"Sys.Platform$pollUsesKqueue"
	.size	.L__axiom_symn_67, 27

	.type	.L__axiom_symn_68,@object       // @__axiom_symn_68
	.p2align	4, 0x0
.L__axiom_symn_68:
	.ascii	"Sys.Platform$sysPollCreateNum"
	.size	.L__axiom_symn_68, 29

	.type	.L__axiom_symn_69,@object       // @__axiom_symn_69
	.p2align	4, 0x0
.L__axiom_symn_69:
	.ascii	"Sys.Platform$sysPollWaitNum"
	.size	.L__axiom_symn_69, 27

	.type	.L__axiom_symn_70,@object       // @__axiom_symn_70
	.p2align	4, 0x0
.L__axiom_symn_70:
	.ascii	"Sys.Platform$sysPollCtlNum"
	.size	.L__axiom_symn_70, 26

	.type	.L__axiom_symn_71,@object       // @__axiom_symn_71
	.p2align	4, 0x0
.L__axiom_symn_71:
	.ascii	"Sys.Platform$pollEventSize"
	.size	.L__axiom_symn_71, 26

	.type	.L__axiom_symn_72,@object       // @__axiom_symn_72
	.p2align	4, 0x0
.L__axiom_symn_72:
	.ascii	"Sys.Platform$pollEventFdOffset"
	.size	.L__axiom_symn_72, 30

	.type	.L__axiom_symn_73,@object       // @__axiom_symn_73
	.p2align	4, 0x0
.L__axiom_symn_73:
	.ascii	"Sys.Platform$pollReadFilter"
	.size	.L__axiom_symn_73, 27

	.type	.L__axiom_symn_74,@object       // @__axiom_symn_74
	.p2align	4, 0x0
.L__axiom_symn_74:
	.ascii	"Sys.Platform$pollAddOp"
	.size	.L__axiom_symn_74, 22

	.type	.L__axiom_symn_75,@object       // @__axiom_symn_75
	.p2align	4, 0x0
.L__axiom_symn_75:
	.ascii	"Sys.Platform$pollDelOp"
	.size	.L__axiom_symn_75, 22

	.type	.L__axiom_symn_76,@object       // @__axiom_symn_76
	.p2align	4, 0x0
.L__axiom_symn_76:
	.ascii	"Sys.Platform$pollSigsetSize"
	.size	.L__axiom_symn_76, 27

	.type	.L__axiom_symn_77,@object       // @__axiom_symn_77
	.p2align	4, 0x0
.L__axiom_symn_77:
	.ascii	"Sys.Platform$sysRandomNum"
	.size	.L__axiom_symn_77, 25

	.type	.L__axiom_symn_78,@object       // @__axiom_symn_78
	.p2align	4, 0x0
.L__axiom_symn_78:
	.ascii	"Sys.Platform$randomIsGetentropy"
	.size	.L__axiom_symn_78, 31

	.type	.L__axiom_symn_79,@object       // @__axiom_symn_79
	.p2align	4, 0x0
.L__axiom_symn_79:
	.ascii	"Sys.Platform$randomMaxChunk"
	.size	.L__axiom_symn_79, 27

	.type	.L__axiom_symn_80,@object       // @__axiom_symn_80
	.p2align	4, 0x0
.L__axiom_symn_80:
	.ascii	"Sys.Platform$signalUsesSignalFd"
	.size	.L__axiom_symn_80, 31

	.type	.L__axiom_symn_81,@object       // @__axiom_symn_81
	.p2align	4, 0x0
.L__axiom_symn_81:
	.ascii	"Sys.Platform$sysSigProcMaskNum"
	.size	.L__axiom_symn_81, 30

	.type	.L__axiom_symn_82,@object       // @__axiom_symn_82
	.p2align	4, 0x0
.L__axiom_symn_82:
	.ascii	"Sys.Platform$sigBlockHow"
	.size	.L__axiom_symn_82, 24

	.type	.L__axiom_symn_83,@object       // @__axiom_symn_83
	.p2align	4, 0x0
.L__axiom_symn_83:
	.ascii	"Sys.Platform$sigsetBytes"
	.size	.L__axiom_symn_83, 24

	.type	.L__axiom_symn_84,@object       // @__axiom_symn_84
	.p2align	4, 0x0
.L__axiom_symn_84:
	.ascii	"Sys.Platform$sysSignalFdNum"
	.size	.L__axiom_symn_84, 27

	.type	.L__axiom_symn_85,@object       // @__axiom_symn_85
	.p2align	4, 0x0
.L__axiom_symn_85:
	.ascii	"Sys.Platform$sigInfoSize"
	.size	.L__axiom_symn_85, 24

	.type	.L__axiom_symn_86,@object       // @__axiom_symn_86
	.p2align	4, 0x0
.L__axiom_symn_86:
	.ascii	"Sys.Platform$pollSignalFilter"
	.size	.L__axiom_symn_86, 29

	.type	.L__axiom_symn_87,@object       // @__axiom_symn_87
	.p2align	4, 0x0
.L__axiom_symn_87:
	.ascii	"Sys.Platform$sysKillNum"
	.size	.L__axiom_symn_87, 23

	.type	.L__axiom_symn_88,@object       // @__axiom_symn_88
	.p2align	4, 0x0
.L__axiom_symn_88:
	.ascii	"Sys.Platform$sigTerm"
	.size	.L__axiom_symn_88, 20

	.type	.L__axiom_symn_89,@object       // @__axiom_symn_89
	.p2align	4, 0x0
.L__axiom_symn_89:
	.ascii	"Sys.Platform$sigInt"
	.size	.L__axiom_symn_89, 19

	.type	.L__axiom_symn_90,@object       // @__axiom_symn_90
	.p2align	4, 0x0
.L__axiom_symn_90:
	.ascii	"Sys.Platform$forkChildIsZero"
	.size	.L__axiom_symn_90, 28

	.type	.L__axiom_symn_91,@object       // @__axiom_symn_91
	.p2align	4, 0x0
.L__axiom_symn_91:
	.ascii	"Sys.Platform$acceptNonblockFlag"
	.size	.L__axiom_symn_91, 31

	.type	.L__axiom_symn_92,@object       // @__axiom_symn_92
	.p2align	2, 0x0
.L__axiom_symn_92:
	.ascii	"Mem$memAlloc"
	.size	.L__axiom_symn_92, 12

	.type	.L__axiom_symn_93,@object       // @__axiom_symn_93
	.p2align	4, 0x0
.L__axiom_symn_93:
	.ascii	"Mem$memAllocMapped"
	.size	.L__axiom_symn_93, 18

	.type	.L__axiom_symn_94,@object       // @__axiom_symn_94
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_94:
	.ascii	"Mem$memMarkArray"
	.size	.L__axiom_symn_94, 16

	.type	.L__axiom_symn_95,@object       // @__axiom_symn_95
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_95:
	.ascii	"Mem$memMarkLeaf"
	.size	.L__axiom_symn_95, 15

	.type	.L__axiom_symn_96,@object       // @__axiom_symn_96
	.p2align	2, 0x0
.L__axiom_symn_96:
	.ascii	"Mem$memCopy"
	.size	.L__axiom_symn_96, 11

	.type	.L__axiom_symn_97,@object       // @__axiom_symn_97
	.p2align	2, 0x0
.L__axiom_symn_97:
	.ascii	"Mem$memCopyFrom"
	.size	.L__axiom_symn_97, 15

	.type	.L__axiom_symn_98,@object       // @__axiom_symn_98
	.p2align	2, 0x0
.L__axiom_symn_98:
	.ascii	"Mem$memSet"
	.size	.L__axiom_symn_98, 10

	.type	.L__axiom_symn_99,@object       // @__axiom_symn_99
	.p2align	2, 0x0
.L__axiom_symn_99:
	.ascii	"Mem$memSetFrom"
	.size	.L__axiom_symn_99, 14

	.type	.L__axiom_symn_100,@object      // @__axiom_symn_100
	.p2align	2, 0x0
.L__axiom_symn_100:
	.ascii	"Mem$memCmp"
	.size	.L__axiom_symn_100, 10

	.type	.L__axiom_symn_101,@object      // @__axiom_symn_101
	.p2align	2, 0x0
.L__axiom_symn_101:
	.ascii	"Mem$memCmpFrom"
	.size	.L__axiom_symn_101, 14

	.type	.L__axiom_symn_102,@object      // @__axiom_symn_102
	.p2align	2, 0x0
.L__axiom_symn_102:
	.ascii	"Mem$memGetWord"
	.size	.L__axiom_symn_102, 14

	.type	.L__axiom_symn_103,@object      // @__axiom_symn_103
	.p2align	4, 0x0
.L__axiom_symn_103:
	.ascii	"Mem$memGetWordStr"
	.size	.L__axiom_symn_103, 17

	.type	.L__axiom_symn_104,@object      // @__axiom_symn_104
	.p2align	2, 0x0
.L__axiom_symn_104:
	.ascii	"Mem$memSetWord"
	.size	.L__axiom_symn_104, 14

	.type	.L__axiom_symn_105,@object      // @__axiom_symn_105
	.p2align	2, 0x0
.L__axiom_symn_105:
	.ascii	"Mem$memGetByte"
	.size	.L__axiom_symn_105, 14

	.type	.L__axiom_symn_106,@object      // @__axiom_symn_106
	.p2align	2, 0x0
.L__axiom_symn_106:
	.ascii	"Mem$memPutByte"
	.size	.L__axiom_symn_106, 14

	.type	.L__axiom_symn_107,@object      // @__axiom_symn_107
	.p2align	4, 0x0
.L__axiom_symn_107:
	.ascii	"Vec$vecDefaultCap"
	.size	.L__axiom_symn_107, 17

	.type	.L__axiom_symn_108,@object      // @__axiom_symn_108
	.p2align	2, 0x0
.L__axiom_symn_108:
	.ascii	"Vec$vecNew"
	.size	.L__axiom_symn_108, 10

	.type	.L__axiom_symn_109,@object      // @__axiom_symn_109
	.p2align	4, 0x0
.L__axiom_symn_109:
	.ascii	"Vec$vecWithCapacity"
	.size	.L__axiom_symn_109, 19

	.type	.L__axiom_symn_110,@object      // @__axiom_symn_110
	.p2align	4, 0x0
.L__axiom_symn_110:
	.ascii	"Vec$vecWithCapacityRef"
	.size	.L__axiom_symn_110, 22

	.type	.L__axiom_symn_111,@object      // @__axiom_symn_111
	.p2align	2, 0x0
.L__axiom_symn_111:
	.ascii	"Vec$vecNewRef"
	.size	.L__axiom_symn_111, 13

	.type	.L__axiom_symn_112,@object      // @__axiom_symn_112
	.p2align	2, 0x0
.L__axiom_symn_112:
	.ascii	"Vec$vecBuild"
	.size	.L__axiom_symn_112, 12

	.type	.L__axiom_symn_113,@object      // @__axiom_symn_113
	.p2align	2, 0x0
.L__axiom_symn_113:
	.ascii	"Vec$vecFree"
	.size	.L__axiom_symn_113, 11

	.type	.L__axiom_symn_114,@object      // @__axiom_symn_114
	.p2align	2, 0x0
.L__axiom_symn_114:
	.ascii	"Vec$vecOwnsRefs"
	.size	.L__axiom_symn_114, 15

	.type	.L__axiom_symn_115,@object      // @__axiom_symn_115
	.p2align	2, 0x0
.L__axiom_symn_115:
	.ascii	"Vec$vecLen"
	.size	.L__axiom_symn_115, 10

	.type	.L__axiom_symn_116,@object      // @__axiom_symn_116
	.p2align	2, 0x0
.L__axiom_symn_116:
	.ascii	"Vec$vecCap"
	.size	.L__axiom_symn_116, 10

	.type	.L__axiom_symn_117,@object      // @__axiom_symn_117
	.p2align	2, 0x0
.L__axiom_symn_117:
	.ascii	"Vec$vecData"
	.size	.L__axiom_symn_117, 11

	.type	.L__axiom_symn_118,@object      // @__axiom_symn_118
	.p2align	2, 0x0
.L__axiom_symn_118:
	.ascii	"Vec$vecGet"
	.size	.L__axiom_symn_118, 10

	.type	.L__axiom_symn_119,@object      // @__axiom_symn_119
	.p2align	2, 0x0
.L__axiom_symn_119:
	.ascii	"Vec$vecTry"
	.size	.L__axiom_symn_119, 10

	.type	.L__axiom_symn_120,@object      // @__axiom_symn_120
	.p2align	2, 0x0
.L__axiom_symn_120:
	.ascii	"Vec$vecGetStr"
	.size	.L__axiom_symn_120, 13

	.type	.L__axiom_symn_121,@object      // @__axiom_symn_121
	.p2align	2, 0x0
.L__axiom_symn_121:
	.ascii	"Vec$vecSet"
	.size	.L__axiom_symn_121, 10

	.type	.L__axiom_symn_122,@object      // @__axiom_symn_122
	.p2align	2, 0x0
.L__axiom_symn_122:
	.ascii	"Vec$vecReserve"
	.size	.L__axiom_symn_122, 14

	.type	.L__axiom_symn_123,@object      // @__axiom_symn_123
	.p2align	2, 0x0
.L__axiom_symn_123:
	.ascii	"Vec$vecGrownCap"
	.size	.L__axiom_symn_123, 15

	.type	.L__axiom_symn_124,@object      // @__axiom_symn_124
	.p2align	4, 0x0
.L__axiom_symn_124:
	.ascii	"Vec$vecReserveExactly"
	.size	.L__axiom_symn_124, 21

	.type	.L__axiom_symn_125,@object      // @__axiom_symn_125
	.p2align	2, 0x0
.L__axiom_symn_125:
	.ascii	"Vec$vecPush"
	.size	.L__axiom_symn_125, 11

	.type	.L__axiom_symn_126,@object      // @__axiom_symn_126
	.p2align	2, 0x0
.L__axiom_symn_126:
	.ascii	"Vec$vecPop"
	.size	.L__axiom_symn_126, 10

	.type	.L__axiom_symn_127,@object      // @__axiom_symn_127
	.p2align	2, 0x0
.L__axiom_symn_127:
	.ascii	"Vec$vecLast"
	.size	.L__axiom_symn_127, 11

	.type	.L__axiom_symn_128,@object      // @__axiom_symn_128
	.p2align	2, 0x0
.L__axiom_symn_128:
	.ascii	"Vec$vecClear"
	.size	.L__axiom_symn_128, 12

	.type	.L__axiom_symn_129,@object      // @__axiom_symn_129
	.p2align	2, 0x0
.L__axiom_symn_129:
	.ascii	"Vec$vecDropAt"
	.size	.L__axiom_symn_129, 13

	.type	.L__axiom_symn_130,@object      // @__axiom_symn_130
	.p2align	2, 0x0
.L__axiom_symn_130:
	.ascii	"Vec$vecDropFrom"
	.size	.L__axiom_symn_130, 15

	.type	.L__axiom_symn_131,@object      // @__axiom_symn_131
	.p2align	2, 0x0
.L__axiom_symn_131:
	.ascii	"Vec$vecSum"
	.size	.L__axiom_symn_131, 10

	.type	.L__axiom_symn_132,@object      // @__axiom_symn_132
	.p2align	2, 0x0
.L__axiom_symn_132:
	.ascii	"Vec$vecSumFrom"
	.size	.L__axiom_symn_132, 14

	.type	.L__axiom_symn_133,@object      // @__axiom_symn_133
	.p2align	2, 0x0
.L__axiom_symn_133:
	.ascii	"Vec$vecHash"
	.size	.L__axiom_symn_133, 11

	.type	.L__axiom_symn_134,@object      // @__axiom_symn_134
	.p2align	2, 0x0
.L__axiom_symn_134:
	.ascii	"Vec$vecHashFrom"
	.size	.L__axiom_symn_134, 15

	.type	.L__axiom_symn_135,@object      // @__axiom_symn_135
	.p2align	2, 0x0
.L__axiom_symn_135:
	.ascii	"Str$strWrap"
	.size	.L__axiom_symn_135, 11

	.type	.L__axiom_symn_136,@object      // @__axiom_symn_136
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_136:
	.ascii	"Str$strWrapOwned"
	.size	.L__axiom_symn_136, 16

	.type	.L__axiom_symn_137,@object      // @__axiom_symn_137
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_137:
	.ascii	"Str$strAlloc"
	.size	.L__axiom_symn_137, 12

	.type	.L__axiom_symn_138,@object      // @__axiom_symn_138
	.p2align	2, 0x0
.L__axiom_symn_138:
	.ascii	"Str$strFromLit"
	.size	.L__axiom_symn_138, 14

	.type	.L__axiom_symn_139,@object      // @__axiom_symn_139
	.p2align	2, 0x0
.L__axiom_symn_139:
	.ascii	"Str$cstrLen"
	.size	.L__axiom_symn_139, 11

	.type	.L__axiom_symn_140,@object      // @__axiom_symn_140
	.p2align	2, 0x0
.L__axiom_symn_140:
	.ascii	"Str$strLen"
	.size	.L__axiom_symn_140, 10

	.type	.L__axiom_symn_141,@object      // @__axiom_symn_141
	.p2align	2, 0x0
.L__axiom_symn_141:
	.ascii	"Str$strData"
	.size	.L__axiom_symn_141, 11

	.type	.L__axiom_symn_142,@object      // @__axiom_symn_142
	.p2align	2, 0x0
.L__axiom_symn_142:
	.ascii	"Str$strOwner"
	.size	.L__axiom_symn_142, 12

	.type	.L__axiom_symn_143,@object      // @__axiom_symn_143
	.p2align	2, 0x0
.L__axiom_symn_143:
	.ascii	"Str$strByte"
	.size	.L__axiom_symn_143, 11

	.type	.L__axiom_symn_144,@object      // @__axiom_symn_144
	.p2align	2, 0x0
.L__axiom_symn_144:
	.ascii	"Str$strCStr"
	.size	.L__axiom_symn_144, 11

	.type	.L__axiom_symn_145,@object      // @__axiom_symn_145
	.p2align	2, 0x0
.L__axiom_symn_145:
	.ascii	"Str$strIsEmpty"
	.size	.L__axiom_symn_145, 14

	.type	.L__axiom_symn_146,@object      // @__axiom_symn_146
	.p2align	2, 0x0
.L__axiom_symn_146:
	.ascii	"Str$strCmp"
	.size	.L__axiom_symn_146, 10

	.type	.L__axiom_symn_147,@object      // @__axiom_symn_147
	.p2align	2, 0x0
.L__axiom_symn_147:
	.ascii	"Str$strEq"
	.size	.L__axiom_symn_147, 9

	.type	.L__axiom_symn_148,@object      // @__axiom_symn_148
	.p2align	2, 0x0
.L__axiom_symn_148:
	.ascii	"Str$strSlice"
	.size	.L__axiom_symn_148, 12

	.type	.L__axiom_symn_149,@object      // @__axiom_symn_149
	.p2align	2, 0x0
.L__axiom_symn_149:
	.ascii	"Str$strDup"
	.size	.L__axiom_symn_149, 10

	.type	.L__axiom_symn_150,@object      // @__axiom_symn_150
	.p2align	2, 0x0
.L__axiom_symn_150:
	.ascii	"Str$strConcat"
	.size	.L__axiom_symn_150, 13

	.type	.L__axiom_symn_151,@object      // @__axiom_symn_151
	.p2align	2, 0x0
.L__axiom_symn_151:
	.ascii	"Str$strFindByte"
	.size	.L__axiom_symn_151, 15

	.type	.L__axiom_symn_152,@object      // @__axiom_symn_152
	.p2align	4, 0x0
.L__axiom_symn_152:
	.ascii	"Str$strStartsWith"
	.size	.L__axiom_symn_152, 17

	.type	.L__axiom_symn_153,@object      // @__axiom_symn_153
	.p2align	2, 0x0
.L__axiom_symn_153:
	.ascii	"Str$strIsDigit"
	.size	.L__axiom_symn_153, 14

	.type	.L__axiom_symn_154,@object      // @__axiom_symn_154
	.p2align	2, 0x0
.L__axiom_symn_154:
	.ascii	"Str$strIsAlpha"
	.size	.L__axiom_symn_154, 14

	.type	.L__axiom_symn_155,@object      // @__axiom_symn_155
	.p2align	2, 0x0
.L__axiom_symn_155:
	.ascii	"Str$strIsSpace"
	.size	.L__axiom_symn_155, 14

	.type	.L__axiom_symn_156,@object      // @__axiom_symn_156
	.p2align	2, 0x0
.L__axiom_symn_156:
	.ascii	"Str$strHexVal"
	.size	.L__axiom_symn_156, 13

	.type	.L__axiom_symn_157,@object      // @__axiom_symn_157
	.p2align	4, 0x0
.L__axiom_symn_157:
	.ascii	"Str$strIsHexDigit"
	.size	.L__axiom_symn_157, 17

	.type	.L__axiom_symn_158,@object      // @__axiom_symn_158
	.p2align	2, 0x0
.L__axiom_symn_158:
	.ascii	"Str$strSplit"
	.size	.L__axiom_symn_158, 12

	.type	.L__axiom_symn_159,@object      // @__axiom_symn_159
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_159:
	.ascii	"Str$strSplitFrom"
	.size	.L__axiom_symn_159, 16

	.type	.L__axiom_symn_160,@object      // @__axiom_symn_160
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_160:
	.ascii	"Str$strFromByte"
	.size	.L__axiom_symn_160, 15

	.type	.L__axiom_symn_161,@object      // @__axiom_symn_161
	.p2align	4, 0x0
.L__axiom_symn_161:
	.ascii	"Fmt$intIsMostNegative"
	.size	.L__axiom_symn_161, 21

	.type	.L__axiom_symn_162,@object      // @__axiom_symn_162
	.p2align	2, 0x0
.L__axiom_symn_162:
	.ascii	"Fmt$fmtIntWidth"
	.size	.L__axiom_symn_162, 15

	.type	.L__axiom_symn_163,@object      // @__axiom_symn_163
	.p2align	2, 0x0
.L__axiom_symn_163:
	.ascii	"Fmt$fmtInt"
	.size	.L__axiom_symn_163, 10

	.type	.L__axiom_symn_164,@object      // @__axiom_symn_164
	.p2align	2, 0x0
.L__axiom_symn_164:
	.ascii	"Fmt$fmtNat"
	.size	.L__axiom_symn_164, 10

	.type	.L__axiom_symn_165,@object      // @__axiom_symn_165
	.p2align	2, 0x0
.L__axiom_symn_165:
	.ascii	"Fmt$fmtDigits"
	.size	.L__axiom_symn_165, 13

	.type	.L__axiom_symn_166,@object      // @__axiom_symn_166
	.p2align	2, 0x0
.L__axiom_symn_166:
	.ascii	"Fmt$fmtHexShr4"
	.size	.L__axiom_symn_166, 14

	.type	.L__axiom_symn_167,@object      // @__axiom_symn_167
	.p2align	2, 0x0
.L__axiom_symn_167:
	.ascii	"Fmt$fmtHex"
	.size	.L__axiom_symn_167, 10

	.type	.L__axiom_symn_168,@object      // @__axiom_symn_168
	.p2align	2, 0x0
.L__axiom_symn_168:
	.ascii	"Fmt$fmtHexWidth"
	.size	.L__axiom_symn_168, 15

	.type	.L__axiom_symn_169,@object      // @__axiom_symn_169
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_169:
	.ascii	"Fmt$fmtHexDigits"
	.size	.L__axiom_symn_169, 16

	.type	.L__axiom_symn_170,@object      // @__axiom_symn_170
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_170:
	.ascii	"Fmt$fmtPadLeft"
	.size	.L__axiom_symn_170, 14

	.type	.L__axiom_symn_171,@object      // @__axiom_symn_171
	.p2align	2, 0x0
.L__axiom_symn_171:
	.ascii	"Fmt$fmtPadRight"
	.size	.L__axiom_symn_171, 15

	.type	.L__axiom_symn_172,@object      // @__axiom_symn_172
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_172:
	.ascii	"Fmt$fmtPadCenter"
	.size	.L__axiom_symn_172, 16

	.type	.L__axiom_symn_173,@object      // @__axiom_symn_173
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_173:
	.ascii	"Fmt$fmtPadZerosLeft"
	.size	.L__axiom_symn_173, 19

	.type	.L__axiom_symn_174,@object      // @__axiom_symn_174
	.p2align	2, 0x0
.L__axiom_symn_174:
	.ascii	"Fmt$fmtHexUpper"
	.size	.L__axiom_symn_174, 15

	.type	.L__axiom_symn_175,@object      // @__axiom_symn_175
	.p2align	4, 0x0
.L__axiom_symn_175:
	.ascii	"Fmt$fmtHexDigitsUpper"
	.size	.L__axiom_symn_175, 21

	.type	.L__axiom_symn_176,@object      // @__axiom_symn_176
	.p2align	2, 0x0
.L__axiom_symn_176:
	.ascii	"Fmt$powTen"
	.size	.L__axiom_symn_176, 10

	.type	.L__axiom_symn_177,@object      // @__axiom_symn_177
	.p2align	2, 0x0
.L__axiom_symn_177:
	.ascii	"Fmt$fmtPadZeros"
	.size	.L__axiom_symn_177, 15

	.type	.L__axiom_symn_178,@object      // @__axiom_symn_178
	.p2align	2, 0x0
.L__axiom_symn_178:
	.ascii	"Fmt$fmtFloat"
	.size	.L__axiom_symn_178, 12

	.type	.L__axiom_symn_179,@object      // @__axiom_symn_179
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_179:
	.ascii	"Fmt$fmtFloatPrec"
	.size	.L__axiom_symn_179, 16

	.type	.L__axiom_symn_180,@object      // @__axiom_symn_180
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_180:
	.ascii	"Fmt$fmtFloatAbs"
	.size	.L__axiom_symn_180, 15

	.type	.L__axiom_symn_181,@object      // @__axiom_symn_181
	.p2align	2, 0x0
.L__axiom_symn_181:
	.ascii	"Sys$stdin"
	.size	.L__axiom_symn_181, 9

	.type	.L__axiom_symn_182,@object      // @__axiom_symn_182
	.p2align	2, 0x0
.L__axiom_symn_182:
	.ascii	"Sys$stdout"
	.size	.L__axiom_symn_182, 10

	.type	.L__axiom_symn_183,@object      // @__axiom_symn_183
	.p2align	2, 0x0
.L__axiom_symn_183:
	.ascii	"Sys$stderr"
	.size	.L__axiom_symn_183, 10

	.type	.L__axiom_symn_184,@object      // @__axiom_symn_184
	.p2align	2, 0x0
.L__axiom_symn_184:
	.ascii	"Sys$sysWriteFd"
	.size	.L__axiom_symn_184, 14

	.type	.L__axiom_symn_185,@object      // @__axiom_symn_185
	.p2align	4, 0x0
.L__axiom_symn_185:
	.ascii	"Sys$sysWriteAllFd"
	.size	.L__axiom_symn_185, 17

	.type	.L__axiom_symn_186,@object      // @__axiom_symn_186
	.p2align	2, 0x0
.L__axiom_symn_186:
	.ascii	"Sys$sysReadFd"
	.size	.L__axiom_symn_186, 13

	.type	.L__axiom_symn_187,@object      // @__axiom_symn_187
	.p2align	2, 0x0
.L__axiom_symn_187:
	.ascii	"Sys$sysOpenPath"
	.size	.L__axiom_symn_187, 15

	.type	.L__axiom_symn_188,@object      // @__axiom_symn_188
	.p2align	4, 0x0
.L__axiom_symn_188:
	.ascii	"Sys$sysOpenPathMode"
	.size	.L__axiom_symn_188, 19

	.type	.L__axiom_symn_189,@object      // @__axiom_symn_189
	.p2align	2, 0x0
.L__axiom_symn_189:
	.ascii	"Sys$sysCloseFd"
	.size	.L__axiom_symn_189, 14

	.type	.L__axiom_symn_190,@object      // @__axiom_symn_190
	.p2align	2, 0x0
.L__axiom_symn_190:
	.ascii	"Sys$sysSeek"
	.size	.L__axiom_symn_190, 11

	.type	.L__axiom_symn_191,@object      // @__axiom_symn_191
	.p2align	2, 0x0
.L__axiom_symn_191:
	.ascii	"Sys$sysExitWith"
	.size	.L__axiom_symn_191, 15

	.type	.L__axiom_symn_192,@object      // @__axiom_symn_192
	.p2align	2, 0x0
.L__axiom_symn_192:
	.ascii	"Sys$sysFailed"
	.size	.L__axiom_symn_192, 13

	.type	.L__axiom_symn_193,@object      // @__axiom_symn_193
	.p2align	2, 0x0
.L__axiom_symn_193:
	.ascii	"Sys$sysErrno"
	.size	.L__axiom_symn_193, 12

	.type	.L__axiom_symn_194,@object      // @__axiom_symn_194
	.p2align	2, 0x0
.L__axiom_symn_194:
	.ascii	"Sys$sysReadFile"
	.size	.L__axiom_symn_194, 15

	.type	.L__axiom_symn_195,@object      // @__axiom_symn_195
	.p2align	2, 0x0
.L__axiom_symn_195:
	.ascii	"Sys$sysReadAll"
	.size	.L__axiom_symn_195, 14

	.type	.L__axiom_symn_196,@object      // @__axiom_symn_196
	.p2align	2, 0x0
.L__axiom_symn_196:
	.ascii	"Sys$sysArgc"
	.size	.L__axiom_symn_196, 11

	.type	.L__axiom_symn_197,@object      // @__axiom_symn_197
	.p2align	2, 0x0
.L__axiom_symn_197:
	.ascii	"Sys$sysArg"
	.size	.L__axiom_symn_197, 10

	.type	.L__axiom_symn_198,@object      // @__axiom_symn_198
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_198:
	.ascii	"Sys$sysWriteFile"
	.size	.L__axiom_symn_198, 16

	.type	.L__axiom_symn_199,@object      // @__axiom_symn_199
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_199:
	.ascii	"Sys$sysAppendFile"
	.size	.L__axiom_symn_199, 17

	.type	.L__axiom_symn_200,@object      // @__axiom_symn_200
	.p2align	2, 0x0
.L__axiom_symn_200:
	.ascii	"Sys$sysRename"
	.size	.L__axiom_symn_200, 13

	.type	.L__axiom_symn_201,@object      // @__axiom_symn_201
	.p2align	2, 0x0
.L__axiom_symn_201:
	.ascii	"Sys$sysUnlink"
	.size	.L__axiom_symn_201, 13

	.type	.L__axiom_symn_202,@object      // @__axiom_symn_202
	.p2align	2, 0x0
.L__axiom_symn_202:
	.ascii	"Sys$sysMkdir"
	.size	.L__axiom_symn_202, 12

	.type	.L__axiom_symn_203,@object      // @__axiom_symn_203
	.p2align	2, 0x0
.L__axiom_symn_203:
	.ascii	"Sys$sysDirMode"
	.size	.L__axiom_symn_203, 14

	.type	.L__axiom_symn_204,@object      // @__axiom_symn_204
	.p2align	2, 0x0
.L__axiom_symn_204:
	.ascii	"Sys$sysRmdir"
	.size	.L__axiom_symn_204, 12

	.type	.L__axiom_symn_205,@object      // @__axiom_symn_205
	.p2align	4, 0x0
.L__axiom_symn_205:
	.ascii	"Sys$sysFileExists"
	.size	.L__axiom_symn_205, 17

	.type	.L__axiom_symn_206,@object      // @__axiom_symn_206
	.p2align	2, 0x0
.L__axiom_symn_206:
	.ascii	"Sys$sysFileSize"
	.size	.L__axiom_symn_206, 15

	.type	.L__axiom_symn_207,@object      // @__axiom_symn_207
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_207:
	.ascii	"Sys$sysReadErrno"
	.size	.L__axiom_symn_207, 16

	.type	.L__axiom_symn_208,@object      // @__axiom_symn_208
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_208:
	.ascii	"Sys$sysIsDir"
	.size	.L__axiom_symn_208, 12

	.type	.L__axiom_symn_209,@object      // @__axiom_symn_209
	.p2align	4, 0x0
.L__axiom_symn_209:
	.ascii	"Sys$sysDirBufBytes"
	.size	.L__axiom_symn_209, 18

	.type	.L__axiom_symn_210,@object      // @__axiom_symn_210
	.p2align	2, 0x0
.L__axiom_symn_210:
	.ascii	"Sys$sysReadDir"
	.size	.L__axiom_symn_210, 14

	.type	.L__axiom_symn_211,@object      // @__axiom_symn_211
	.p2align	4, 0x0
.L__axiom_symn_211:
	.ascii	"Sys$sysReadDirLoop"
	.size	.L__axiom_symn_211, 18

	.type	.L__axiom_symn_212,@object      // @__axiom_symn_212
	.p2align	4, 0x0
.L__axiom_symn_212:
	.ascii	"Sys$sysReadDirDecode"
	.size	.L__axiom_symn_212, 20

	.type	.L__axiom_symn_213,@object      // @__axiom_symn_213
	.p2align	2, 0x0
.L__axiom_symn_213:
	.ascii	"Sys$sysGetCwd"
	.size	.L__axiom_symn_213, 13

	.type	.L__axiom_symn_214,@object      // @__axiom_symn_214
	.p2align	2, 0x0
.L__axiom_symn_214:
	.ascii	"Sys$sysEnvSlot"
	.size	.L__axiom_symn_214, 14

	.type	.L__axiom_symn_215,@object      // @__axiom_symn_215
	.p2align	2, 0x0
.L__axiom_symn_215:
	.ascii	"Sys$sysEnvCount"
	.size	.L__axiom_symn_215, 15

	.type	.L__axiom_symn_216,@object      // @__axiom_symn_216
	.p2align	4, 0x0
.L__axiom_symn_216:
	.ascii	"Sys$sysEnvCountFrom"
	.size	.L__axiom_symn_216, 19

	.type	.L__axiom_symn_217,@object      // @__axiom_symn_217
	.p2align	2, 0x0
.L__axiom_symn_217:
	.ascii	"Sys$sysEnv"
	.size	.L__axiom_symn_217, 10

	.type	.L__axiom_symn_218,@object      // @__axiom_symn_218
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_218:
	.ascii	"Sys$sysEnvLookup"
	.size	.L__axiom_symn_218, 16

	.type	.L__axiom_symn_219,@object      // @__axiom_symn_219
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_219:
	.ascii	"Sys$sysEnvp"
	.size	.L__axiom_symn_219, 11

	.type	.L__axiom_symn_220,@object      // @__axiom_symn_220
	.p2align	2, 0x0
.L__axiom_symn_220:
	.ascii	"Sys$sysEnvpFill"
	.size	.L__axiom_symn_220, 15

	.type	.L__axiom_symn_221,@object      // @__axiom_symn_221
	.p2align	2, 0x0
.L__axiom_symn_221:
	.ascii	"Sys$sysSpawn"
	.size	.L__axiom_symn_221, 12

	.type	.L__axiom_symn_222,@object      // @__axiom_symn_222
	.p2align	2, 0x0
.L__axiom_symn_222:
	.ascii	"Sys$sysWaitPid"
	.size	.L__axiom_symn_222, 14

	.type	.L__axiom_symn_223,@object      // @__axiom_symn_223
	.p2align	2, 0x0
.L__axiom_symn_223:
	.ascii	"Sys$sysExitCode"
	.size	.L__axiom_symn_223, 15

	.type	.L__axiom_symn_224,@object      // @__axiom_symn_224
	.p2align	4, 0x0
.L__axiom_symn_224:
	.ascii	"Sys$sysTermSignal"
	.size	.L__axiom_symn_224, 17

	.type	.L__axiom_symn_225,@object      // @__axiom_symn_225
	.p2align	2, 0x0
.L__axiom_symn_225:
	.ascii	"Sys$sysRun"
	.size	.L__axiom_symn_225, 10

	.type	.L__axiom_symn_226,@object      // @__axiom_symn_226
	.p2align	2, 0x0
.L__axiom_symn_226:
	.ascii	"Sys$sysRunPath"
	.size	.L__axiom_symn_226, 14

	.type	.L__axiom_symn_227,@object      // @__axiom_symn_227
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_227:
	.ascii	"Sys$sysRunSearch"
	.size	.L__axiom_symn_227, 16

	.type	.L__axiom_symn_228,@object      // @__axiom_symn_228
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_228:
	.ascii	"Sys$sysGetPid"
	.size	.L__axiom_symn_228, 13

	.type	.L__axiom_symn_229,@object      // @__axiom_symn_229
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_229:
	.ascii	"Sys$sysNowMicros"
	.size	.L__axiom_symn_229, 16

	.type	.L__axiom_symn_230,@object      // @__axiom_symn_230
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_230:
	.ascii	"Sys$sysNowMonotonic"
	.size	.L__axiom_symn_230, 19

	.type	.L__axiom_symn_231,@object      // @__axiom_symn_231
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_231:
	.ascii	"Sys$netSocketTcp"
	.size	.L__axiom_symn_231, 16

	.type	.L__axiom_symn_232,@object      // @__axiom_symn_232
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_232:
	.ascii	"Sys$netSocketTcp6"
	.size	.L__axiom_symn_232, 17

	.type	.L__axiom_symn_233,@object      // @__axiom_symn_233
	.p2align	4, 0x0
.L__axiom_symn_233:
	.ascii	"Sys$netAddr4Bytes"
	.size	.L__axiom_symn_233, 17

	.type	.L__axiom_symn_234,@object      // @__axiom_symn_234
	.p2align	4, 0x0
.L__axiom_symn_234:
	.ascii	"Sys$netAddr6Bytes"
	.size	.L__axiom_symn_234, 17

	.type	.L__axiom_symn_235,@object      // @__axiom_symn_235
	.p2align	4, 0x0
.L__axiom_symn_235:
	.ascii	"Sys$netAddrMaxBytes"
	.size	.L__axiom_symn_235, 19

	.type	.L__axiom_symn_236,@object      // @__axiom_symn_236
	.p2align	2, 0x0
.L__axiom_symn_236:
	.ascii	"Sys$netAddr4"
	.size	.L__axiom_symn_236, 12

	.type	.L__axiom_symn_237,@object      // @__axiom_symn_237
	.p2align	2, 0x0
.L__axiom_symn_237:
	.ascii	"Sys$netAddr6"
	.size	.L__axiom_symn_237, 12

	.type	.L__axiom_symn_238,@object      // @__axiom_symn_238
	.p2align	2, 0x0
.L__axiom_symn_238:
	.ascii	"Sys$netPutGroup"
	.size	.L__axiom_symn_238, 15

	.type	.L__axiom_symn_239,@object      // @__axiom_symn_239
	.p2align	2, 0x0
.L__axiom_symn_239:
	.ascii	"Sys$netGetGroup"
	.size	.L__axiom_symn_239, 15

	.type	.L__axiom_symn_240,@object      // @__axiom_symn_240
	.p2align	4, 0x0
.L__axiom_symn_240:
	.ascii	"Sys$netAddrFamily"
	.size	.L__axiom_symn_240, 17

	.type	.L__axiom_symn_241,@object      // @__axiom_symn_241
	.p2align	2, 0x0
.L__axiom_symn_241:
	.ascii	"Sys$netAddrPort"
	.size	.L__axiom_symn_241, 15

	.type	.L__axiom_symn_242,@object      // @__axiom_symn_242
	.p2align	2, 0x0
.L__axiom_symn_242:
	.ascii	"Sys$netAddrSize"
	.size	.L__axiom_symn_242, 15

	.type	.L__axiom_symn_243,@object      // @__axiom_symn_243
	.p2align	2, 0x0
.L__axiom_symn_243:
	.ascii	"Sys$netBind"
	.size	.L__axiom_symn_243, 11

	.type	.L__axiom_symn_244,@object      // @__axiom_symn_244
	.p2align	2, 0x0
.L__axiom_symn_244:
	.ascii	"Sys$netListen"
	.size	.L__axiom_symn_244, 13

	.type	.L__axiom_symn_245,@object      // @__axiom_symn_245
	.p2align	2, 0x0
.L__axiom_symn_245:
	.ascii	"Sys$netAccept"
	.size	.L__axiom_symn_245, 13

	.type	.L__axiom_symn_246,@object      // @__axiom_symn_246
	.p2align	4, 0x0
.L__axiom_symn_246:
	.ascii	"Sys$netAcceptFinish"
	.size	.L__axiom_symn_246, 19

	.type	.L__axiom_symn_247,@object      // @__axiom_symn_247
	.p2align	4, 0x0
.L__axiom_symn_247:
	.ascii	"Sys$netAcceptFrom"
	.size	.L__axiom_symn_247, 17

	.type	.L__axiom_symn_248,@object      // @__axiom_symn_248
	.p2align	4, 0x0
.L__axiom_symn_248:
	.ascii	"Sys$netAddrLenRead"
	.size	.L__axiom_symn_248, 18

	.type	.L__axiom_symn_249,@object      // @__axiom_symn_249
	.p2align	2, 0x0
.L__axiom_symn_249:
	.ascii	"Sys$netPutInt32"
	.size	.L__axiom_symn_249, 15

	.type	.L__axiom_symn_250,@object      // @__axiom_symn_250
	.p2align	2, 0x0
.L__axiom_symn_250:
	.ascii	"Sys$netGetInt32"
	.size	.L__axiom_symn_250, 15

	.type	.L__axiom_symn_251,@object      // @__axiom_symn_251
	.p2align	2, 0x0
.L__axiom_symn_251:
	.ascii	"Sys$netAddrText"
	.size	.L__axiom_symn_251, 15

	.type	.L__axiom_symn_252,@object      // @__axiom_symn_252
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_252:
	.ascii	"Sys$netAddrText4"
	.size	.L__axiom_symn_252, 16

	.type	.L__axiom_symn_253,@object      // @__axiom_symn_253
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_253:
	.ascii	"Sys$netAddrZeroRun"
	.size	.L__axiom_symn_253, 18

	.type	.L__axiom_symn_254,@object      // @__axiom_symn_254
	.p2align	4, 0x0
.L__axiom_symn_254:
	.ascii	"Sys$netAddrZeroRunStart"
	.size	.L__axiom_symn_254, 23

	.type	.L__axiom_symn_255,@object      // @__axiom_symn_255
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_255:
	.ascii	"Sys$netAddrText6"
	.size	.L__axiom_symn_255, 16

	.type	.L__axiom_symn_256,@object      // @__axiom_symn_256
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_256:
	.ascii	"Sys$netAddrTextPort"
	.size	.L__axiom_symn_256, 19

	.type	.L__axiom_symn_257,@object      // @__axiom_symn_257
	.p2align	4, 0x0
.L__axiom_symn_257:
	.ascii	"Sys$netSetBlocking"
	.size	.L__axiom_symn_257, 18

	.type	.L__axiom_symn_258,@object      // @__axiom_symn_258
	.p2align	2, 0x0
.L__axiom_symn_258:
	.ascii	"Sys$netConnect"
	.size	.L__axiom_symn_258, 14

	.type	.L__axiom_symn_259,@object      // @__axiom_symn_259
	.p2align	2, 0x0
.L__axiom_symn_259:
	.ascii	"Sys$netShutdown"
	.size	.L__axiom_symn_259, 15

	.type	.L__axiom_symn_260,@object      // @__axiom_symn_260
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_260:
	.ascii	"Sys$netSetOptInt"
	.size	.L__axiom_symn_260, 16

	.type	.L__axiom_symn_261,@object      // @__axiom_symn_261
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_symn_261:
	.ascii	"Sys$netSetNonBlocking"
	.size	.L__axiom_symn_261, 21

	.type	.L__axiom_symn_262,@object      // @__axiom_symn_262
	.p2align	4, 0x0
.L__axiom_symn_262:
	.ascii	"Sys$netWouldBlock"
	.size	.L__axiom_symn_262, 17

	.type	.L__axiom_symn_263,@object      // @__axiom_symn_263
	.p2align	2, 0x0
.L__axiom_symn_263:
	.ascii	"Sys$netPutWord"
	.size	.L__axiom_symn_263, 14

	.type	.L__axiom_symn_264,@object      // @__axiom_symn_264
	.p2align	2, 0x0
.L__axiom_symn_264:
	.ascii	"Sys$netGetWord"
	.size	.L__axiom_symn_264, 14

	.type	.L__axiom_symn_265,@object      // @__axiom_symn_265
	.p2align	4, 0x0
.L__axiom_symn_265:
	.ascii	"Sys$netPollBufBytes"
	.size	.L__axiom_symn_265, 19

	.type	.L__axiom_symn_266,@object      // @__axiom_symn_266
	.p2align	4, 0x0
.L__axiom_symn_266:
	.ascii	"Sys$netPollCreate"
	.size	.L__axiom_symn_266, 17

	.type	.L__axiom_symn_267,@object      // @__axiom_symn_267
	.p2align	2, 0x0
.L__axiom_symn_267:
	.ascii	"Sys$netPollRec"
	.size	.L__axiom_symn_267, 14

	.type	.L__axiom_symn_268,@object      // @__axiom_symn_268
	.p2align	4, 0x0
.L__axiom_symn_268:
	.ascii	"Sys$netPollAddRead"
	.size	.L__axiom_symn_268, 18

	.type	.L__axiom_symn_269,@object      // @__axiom_symn_269
	.p2align	4, 0x0
.L__axiom_symn_269:
	.ascii	"Sys$netPollDelRead"
	.size	.L__axiom_symn_269, 18

	.type	.L__axiom_symn_270,@object      // @__axiom_symn_270
	.p2align	2, 0x0
.L__axiom_symn_270:
	.ascii	"Sys$netPollWait"
	.size	.L__axiom_symn_270, 15

	.type	.L__axiom_symn_271,@object      // @__axiom_symn_271
	.p2align	2, 0x0
.L__axiom_symn_271:
	.ascii	"Sys$netPollFdAt"
	.size	.L__axiom_symn_271, 15

	.type	.L__axiom_symn_272,@object      // @__axiom_symn_272
	.p2align	4, 0x0
.L__axiom_symn_272:
	.ascii	"Sys$sysRandomBytes"
	.size	.L__axiom_symn_272, 18

	.type	.L__axiom_symn_273,@object      // @__axiom_symn_273
	.p2align	2, 0x0
.L__axiom_symn_273:
	.ascii	"Sys$sysSigBit"
	.size	.L__axiom_symn_273, 13

	.type	.L__axiom_symn_274,@object      // @__axiom_symn_274
	.p2align	4, 0x0
.L__axiom_symn_274:
	.ascii	"Sys$sysSignalBlock"
	.size	.L__axiom_symn_274, 18

	.type	.L__axiom_symn_275,@object      // @__axiom_symn_275
	.p2align	4, 0x0
.L__axiom_symn_275:
	.ascii	"Sys$netSignalOpen"
	.size	.L__axiom_symn_275, 17

	.type	.L__axiom_symn_276,@object      // @__axiom_symn_276
	.p2align	4, 0x0
.L__axiom_symn_276:
	.ascii	"Sys$netPollSignalAt"
	.size	.L__axiom_symn_276, 19

	.type	.L__axiom_symn_277,@object      // @__axiom_symn_277
	.p2align	2, 0x0
.L__axiom_symn_277:
	.ascii	"Sys$sysKill"
	.size	.L__axiom_symn_277, 11

	.type	.L__axiom_symn_278,@object      // @__axiom_symn_278
	.p2align	4, 0x0
.L__axiom_symn_278:
	.ascii	"Sys$sysForkProcess"
	.size	.L__axiom_symn_278, 18

	.type	.L__axiom_symn_279,@object      // @__axiom_symn_279
	.p2align	2, 0x0
.L__axiom_symn_279:
	.ascii	"IO$writeStr"
	.size	.L__axiom_symn_279, 11

	.type	.L__axiom_symn_280,@object      // @__axiom_symn_280
	.p2align	2, 0x0
.L__axiom_symn_280:
	.ascii	"IO$printLit"
	.size	.L__axiom_symn_280, 11

	.type	.L__axiom_symn_281,@object      // @__axiom_symn_281
	.p2align	2, 0x0
.L__axiom_symn_281:
	.ascii	"IO$printlnLit"
	.size	.L__axiom_symn_281, 13

	.type	.L__axiom_symn_282,@object      // @__axiom_symn_282
	.p2align	2, 0x0
.L__axiom_symn_282:
	.ascii	"IO$readFileLit"
	.size	.L__axiom_symn_282, 14

	.type	.L__axiom_symn_283,@object      // @__axiom_symn_283
	.p2align	2, 0x0
.L__axiom_symn_283:
	.ascii	"IO$readFile"
	.size	.L__axiom_symn_283, 11

	.type	.L__axiom_symn_284,@object      // @__axiom_symn_284
	.p2align	2, 0x0
.L__axiom_symn_284:
	.ascii	"IO$ioPath"
	.size	.L__axiom_symn_284, 9

	.type	.L__axiom_symn_285,@object      // @__axiom_symn_285
	.p2align	2, 0x0
.L__axiom_symn_285:
	.ascii	"IO$writeFile"
	.size	.L__axiom_symn_285, 12

	.type	.L__axiom_symn_286,@object      // @__axiom_symn_286
	.p2align	2, 0x0
.L__axiom_symn_286:
	.ascii	"IO$appendFile"
	.size	.L__axiom_symn_286, 13

	.type	.L__axiom_symn_287,@object      // @__axiom_symn_287
	.p2align	2, 0x0
.L__axiom_symn_287:
	.ascii	"IO$removeFile"
	.size	.L__axiom_symn_287, 13

	.type	.L__axiom_symn_288,@object      // @__axiom_symn_288
	.p2align	2, 0x0
.L__axiom_symn_288:
	.ascii	"IO$renamePath"
	.size	.L__axiom_symn_288, 13

	.type	.L__axiom_symn_289,@object      // @__axiom_symn_289
	.p2align	2, 0x0
.L__axiom_symn_289:
	.ascii	"IO$copyFile"
	.size	.L__axiom_symn_289, 11

	.type	.L__axiom_symn_290,@object      // @__axiom_symn_290
	.p2align	2, 0x0
.L__axiom_symn_290:
	.ascii	"IO$fileExists"
	.size	.L__axiom_symn_290, 13

	.type	.L__axiom_symn_291,@object      // @__axiom_symn_291
	.section	.rodata.cst8,"aM",@progbits,8
	.p2align	2, 0x0
.L__axiom_symn_291:
	.ascii	"IO$isDir"
	.size	.L__axiom_symn_291, 8

	.type	.L__axiom_symn_292,@object      // @__axiom_symn_292
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_292:
	.ascii	"IO$fileSize"
	.size	.L__axiom_symn_292, 11

	.type	.L__axiom_symn_293,@object      // @__axiom_symn_293
	.p2align	2, 0x0
.L__axiom_symn_293:
	.ascii	"IO$readErrno"
	.size	.L__axiom_symn_293, 12

	.type	.L__axiom_symn_294,@object      // @__axiom_symn_294
	.p2align	2, 0x0
.L__axiom_symn_294:
	.ascii	"IO$makeDir"
	.size	.L__axiom_symn_294, 10

	.type	.L__axiom_symn_295,@object      // @__axiom_symn_295
	.p2align	2, 0x0
.L__axiom_symn_295:
	.ascii	"IO$makeDirAll"
	.size	.L__axiom_symn_295, 13

	.type	.L__axiom_symn_296,@object      // @__axiom_symn_296
	.p2align	4, 0x0
.L__axiom_symn_296:
	.ascii	"IO$makeDirAllFrom"
	.size	.L__axiom_symn_296, 17

	.type	.L__axiom_symn_297,@object      // @__axiom_symn_297
	.p2align	2, 0x0
.L__axiom_symn_297:
	.ascii	"IO$makeDirOk"
	.size	.L__axiom_symn_297, 12

	.type	.L__axiom_symn_298,@object      // @__axiom_symn_298
	.p2align	2, 0x0
.L__axiom_symn_298:
	.ascii	"IO$removeDir"
	.size	.L__axiom_symn_298, 12

	.type	.L__axiom_symn_299,@object      // @__axiom_symn_299
	.p2align	2, 0x0
.L__axiom_symn_299:
	.ascii	"IO$listDir"
	.size	.L__axiom_symn_299, 10

	.type	.L__axiom_symn_300,@object      // @__axiom_symn_300
	.p2align	2, 0x0
.L__axiom_symn_300:
	.ascii	"IO$listDirKeep"
	.size	.L__axiom_symn_300, 14

	.type	.L__axiom_symn_301,@object      // @__axiom_symn_301
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_301:
	.ascii	"IO$listDirInsert"
	.size	.L__axiom_symn_301, 16

	.type	.L__axiom_symn_302,@object      // @__axiom_symn_302
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_302:
	.ascii	"IO$listDirSift"
	.size	.L__axiom_symn_302, 14

	.type	.L__axiom_symn_303,@object      // @__axiom_symn_303
	.p2align	2, 0x0
.L__axiom_symn_303:
	.ascii	"IO$cwd"
	.size	.L__axiom_symn_303, 6

	.type	.L__axiom_symn_304,@object      // @__axiom_symn_304
	.p2align	2, 0x0
.L__axiom_symn_304:
	.ascii	"IO$exit"
	.size	.L__axiom_symn_304, 7

	.type	.L__axiom_symn_305,@object      // @__axiom_symn_305
	.p2align	2, 0x0
.L__axiom_symn_305:
	.ascii	"IO$die"
	.size	.L__axiom_symn_305, 6

	.type	.L__axiom_symn_306,@object      // @__axiom_symn_306
	.p2align	2, 0x0
.L__axiom_symn_306:
	.ascii	"ask"
	.size	.L__axiom_symn_306, 3

	.type	.L__axiom_symn_307,@object      // @__axiom_symn_307
	.p2align	2, 0x0
.L__axiom_symn_307:
	.ascii	"usable"
	.size	.L__axiom_symn_307, 6

	.type	.L__axiom_symn_308,@object      // @__axiom_symn_308
	.p2align	4, 0x0
.L__axiom_symn_308:
	.ascii	"__axiom_user_main"
	.size	.L__axiom_symn_308, 17

	.type	.L__axiom_symn_309,@object      // @__axiom_symn_309
	.p2align	2, 0x0
.L__axiom_symn_309:
	.ascii	"_lam_0"
	.size	.L__axiom_symn_309, 6

	.type	.L__axiom_symn_310,@object      // @__axiom_symn_310
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	2, 0x0
.L__axiom_symn_310:
	.ascii	"Show#String#show"
	.size	.L__axiom_symn_310, 16

	.type	.L__axiom_symn_311,@object      // @__axiom_symn_311
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.L__axiom_symn_311:
	.ascii	"Show#Int#show"
	.size	.L__axiom_symn_311, 13

	.type	.L__axiom_symn_312,@object      // @__axiom_symn_312
	.p2align	2, 0x0
.L__axiom_symn_312:
	.ascii	"Show#Bool#show"
	.size	.L__axiom_symn_312, 14

	.type	.L__axiom_symn_313,@object      // @__axiom_symn_313
	.p2align	2, 0x0
.L__axiom_symn_313:
	.ascii	"Show#Float#show"
	.size	.L__axiom_symn_313, 15

	.type	.L__axiom_symn_314,@object      // @__axiom_symn_314
	.p2align	4, 0x0
.L__axiom_symn_314:
	.ascii	"__axiom_recover_save"
	.size	.L__axiom_symn_314, 20

	.type	.L__axiom_symn_315,@object      // @__axiom_symn_315
	.p2align	4, 0x0
.L__axiom_symn_315:
	.ascii	"__axiom_recover_load"
	.size	.L__axiom_symn_315, 20

	.type	__axiom_symtab,@object          // @__axiom_symtab
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
__axiom_symtab:
	.xword	main
	.xword	.L__axiom_symn_0
	.xword	4                               // 0x4
	.xword	axiom_alloc
	.xword	.L__axiom_symn_1
	.xword	11                              // 0xb
	.xword	axiom_retain
	.xword	.L__axiom_symn_2
	.xword	12                              // 0xc
	.xword	axiom_release
	.xword	.L__axiom_symn_3
	.xword	13                              // 0xd
	.xword	__axiom_arena_mark_fn
	.xword	.L__axiom_symn_4
	.xword	21                              // 0x15
	.xword	__axiom_arena_reset_fn
	.xword	.L__axiom_symn_5
	.xword	22                              // 0x16
	.xword	__axiom_arena_reset_keeping_fn
	.xword	.L__axiom_symn_6
	.xword	30                              // 0x1e
	.xword	__axiom_div_by_zero
	.xword	.L__axiom_symn_7
	.xword	19                              // 0x13
	.xword	__axiom_out_of_memory
	.xword	.L__axiom_symn_8
	.xword	21                              // 0x15
	.xword	__axiom_recover_abort
	.xword	.L__axiom_symn_9
	.xword	21                              // 0x15
	.xword	__axiom_str_eq
	.xword	.L__axiom_symn_10
	.xword	14                              // 0xe
	.xword	Sys.Platform$sysRead
	.xword	.L__axiom_symn_11
	.xword	20                              // 0x14
	.xword	Sys.Platform$sysWrite
	.xword	.L__axiom_symn_12
	.xword	21                              // 0x15
	.xword	Sys.Platform$sysOpen
	.xword	.L__axiom_symn_13
	.xword	20                              // 0x14
	.xword	Sys.Platform$sysClose
	.xword	.L__axiom_symn_14
	.xword	21                              // 0x15
	.xword	Sys.Platform$sysExit
	.xword	.L__axiom_symn_15
	.xword	20                              // 0x14
	.xword	Sys.Platform$sysLseek
	.xword	.L__axiom_symn_16
	.xword	21                              // 0x15
	.xword	Sys.Platform$openNeedsDirFd
	.xword	.L__axiom_symn_17
	.xword	27                              // 0x1b
	.xword	Sys.Platform$atFdCwd
	.xword	.L__axiom_symn_18
	.xword	20                              // 0x14
	.xword	Sys.Platform$oRdonly
	.xword	.L__axiom_symn_19
	.xword	20                              // 0x14
	.xword	Sys.Platform$oWronlyCreateTrunc
	.xword	.L__axiom_symn_20
	.xword	31                              // 0x1f
	.xword	Sys.Platform$oWronlyCreateAppend
	.xword	.L__axiom_symn_21
	.xword	32                              // 0x20
	.xword	Sys.Platform$seekEnd
	.xword	.L__axiom_symn_22
	.xword	20                              // 0x14
	.xword	Sys.Platform$seekSet
	.xword	.L__axiom_symn_23
	.xword	20                              // 0x14
	.xword	Sys.Platform$spawnUsesPosixSpawn
	.xword	.L__axiom_symn_24
	.xword	32                              // 0x20
	.xword	Sys.Platform$sysFork
	.xword	.L__axiom_symn_25
	.xword	20                              // 0x14
	.xword	Sys.Platform$sysForkArg
	.xword	.L__axiom_symn_26
	.xword	23                              // 0x17
	.xword	Sys.Platform$sysExecve
	.xword	.L__axiom_symn_27
	.xword	22                              // 0x16
	.xword	Sys.Platform$sysWait4
	.xword	.L__axiom_symn_28
	.xword	21                              // 0x15
	.xword	Sys.Platform$sysPosixSpawn
	.xword	.L__axiom_symn_29
	.xword	26                              // 0x1a
	.xword	Sys.Platform$sysUnlinkNum
	.xword	.L__axiom_symn_30
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysMkdirNum
	.xword	.L__axiom_symn_31
	.xword	24                              // 0x18
	.xword	Sys.Platform$sysRmdirNum
	.xword	.L__axiom_symn_32
	.xword	24                              // 0x18
	.xword	Sys.Platform$sysRenameNum
	.xword	.L__axiom_symn_33
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysGetdentsNum
	.xword	.L__axiom_symn_34
	.xword	27                              // 0x1b
	.xword	Sys.Platform$dirReadNeedsPosition
	.xword	.L__axiom_symn_35
	.xword	33                              // 0x21
	.xword	Sys.Platform$direntNameOffset
	.xword	.L__axiom_symn_36
	.xword	29                              // 0x1d
	.xword	Sys.Platform$cwdUsesFcntlPath
	.xword	.L__axiom_symn_37
	.xword	29                              // 0x1d
	.xword	Sys.Platform$sysCwdNum
	.xword	.L__axiom_symn_38
	.xword	22                              // 0x16
	.xword	Sys.Platform$fGetPath
	.xword	.L__axiom_symn_39
	.xword	21                              // 0x15
	.xword	Sys.Platform$eExist
	.xword	.L__axiom_symn_40
	.xword	19                              // 0x13
	.xword	Sys.Platform$eIsDir
	.xword	.L__axiom_symn_41
	.xword	19                              // 0x13
	.xword	Sys.Platform$sysGetPidNum
	.xword	.L__axiom_symn_42
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysClockNum
	.xword	.L__axiom_symn_43
	.xword	24                              // 0x18
	.xword	Sys.Platform$clockIsGettimeofday
	.xword	.L__axiom_symn_44
	.xword	32                              // 0x20
	.xword	Sys.Platform$clockHasMonotonic
	.xword	.L__axiom_symn_45
	.xword	30                              // 0x1e
	.xword	Sys.Platform$sysSocketNum
	.xword	.L__axiom_symn_46
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysBindNum
	.xword	.L__axiom_symn_47
	.xword	23                              // 0x17
	.xword	Sys.Platform$sysListenNum
	.xword	.L__axiom_symn_48
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysAcceptNum
	.xword	.L__axiom_symn_49
	.xword	25                              // 0x19
	.xword	Sys.Platform$sysConnectNum
	.xword	.L__axiom_symn_50
	.xword	26                              // 0x1a
	.xword	Sys.Platform$sysSetSockOptNum
	.xword	.L__axiom_symn_51
	.xword	29                              // 0x1d
	.xword	Sys.Platform$sysGetSockOptNum
	.xword	.L__axiom_symn_52
	.xword	29                              // 0x1d
	.xword	Sys.Platform$sysShutdownNum
	.xword	.L__axiom_symn_53
	.xword	27                              // 0x1b
	.xword	Sys.Platform$sysFcntlNum
	.xword	.L__axiom_symn_54
	.xword	24                              // 0x18
	.xword	Sys.Platform$afInet
	.xword	.L__axiom_symn_55
	.xword	19                              // 0x13
	.xword	Sys.Platform$afInet6
	.xword	.L__axiom_symn_56
	.xword	20                              // 0x14
	.xword	Sys.Platform$sockStream
	.xword	.L__axiom_symn_57
	.xword	23                              // 0x17
	.xword	Sys.Platform$solSocket
	.xword	.L__axiom_symn_58
	.xword	22                              // 0x16
	.xword	Sys.Platform$soReuseAddr
	.xword	.L__axiom_symn_59
	.xword	24                              // 0x18
	.xword	Sys.Platform$soReusePort
	.xword	.L__axiom_symn_60
	.xword	24                              // 0x18
	.xword	Sys.Platform$soError
	.xword	.L__axiom_symn_61
	.xword	20                              // 0x14
	.xword	Sys.Platform$fGetFl
	.xword	.L__axiom_symn_62
	.xword	19                              // 0x13
	.xword	Sys.Platform$fSetFl
	.xword	.L__axiom_symn_63
	.xword	19                              // 0x13
	.xword	Sys.Platform$oNonblock
	.xword	.L__axiom_symn_64
	.xword	22                              // 0x16
	.xword	Sys.Platform$eAgain
	.xword	.L__axiom_symn_65
	.xword	19                              // 0x13
	.xword	Sys.Platform$sockaddrHasLenByte
	.xword	.L__axiom_symn_66
	.xword	31                              // 0x1f
	.xword	Sys.Platform$pollUsesKqueue
	.xword	.L__axiom_symn_67
	.xword	27                              // 0x1b
	.xword	Sys.Platform$sysPollCreateNum
	.xword	.L__axiom_symn_68
	.xword	29                              // 0x1d
	.xword	Sys.Platform$sysPollWaitNum
	.xword	.L__axiom_symn_69
	.xword	27                              // 0x1b
	.xword	Sys.Platform$sysPollCtlNum
	.xword	.L__axiom_symn_70
	.xword	26                              // 0x1a
	.xword	Sys.Platform$pollEventSize
	.xword	.L__axiom_symn_71
	.xword	26                              // 0x1a
	.xword	Sys.Platform$pollEventFdOffset
	.xword	.L__axiom_symn_72
	.xword	30                              // 0x1e
	.xword	Sys.Platform$pollReadFilter
	.xword	.L__axiom_symn_73
	.xword	27                              // 0x1b
	.xword	Sys.Platform$pollAddOp
	.xword	.L__axiom_symn_74
	.xword	22                              // 0x16
	.xword	Sys.Platform$pollDelOp
	.xword	.L__axiom_symn_75
	.xword	22                              // 0x16
	.xword	Sys.Platform$pollSigsetSize
	.xword	.L__axiom_symn_76
	.xword	27                              // 0x1b
	.xword	Sys.Platform$sysRandomNum
	.xword	.L__axiom_symn_77
	.xword	25                              // 0x19
	.xword	Sys.Platform$randomIsGetentropy
	.xword	.L__axiom_symn_78
	.xword	31                              // 0x1f
	.xword	Sys.Platform$randomMaxChunk
	.xword	.L__axiom_symn_79
	.xword	27                              // 0x1b
	.xword	Sys.Platform$signalUsesSignalFd
	.xword	.L__axiom_symn_80
	.xword	31                              // 0x1f
	.xword	Sys.Platform$sysSigProcMaskNum
	.xword	.L__axiom_symn_81
	.xword	30                              // 0x1e
	.xword	Sys.Platform$sigBlockHow
	.xword	.L__axiom_symn_82
	.xword	24                              // 0x18
	.xword	Sys.Platform$sigsetBytes
	.xword	.L__axiom_symn_83
	.xword	24                              // 0x18
	.xword	Sys.Platform$sysSignalFdNum
	.xword	.L__axiom_symn_84
	.xword	27                              // 0x1b
	.xword	Sys.Platform$sigInfoSize
	.xword	.L__axiom_symn_85
	.xword	24                              // 0x18
	.xword	Sys.Platform$pollSignalFilter
	.xword	.L__axiom_symn_86
	.xword	29                              // 0x1d
	.xword	Sys.Platform$sysKillNum
	.xword	.L__axiom_symn_87
	.xword	23                              // 0x17
	.xword	Sys.Platform$sigTerm
	.xword	.L__axiom_symn_88
	.xword	20                              // 0x14
	.xword	Sys.Platform$sigInt
	.xword	.L__axiom_symn_89
	.xword	19                              // 0x13
	.xword	Sys.Platform$forkChildIsZero
	.xword	.L__axiom_symn_90
	.xword	28                              // 0x1c
	.xword	Sys.Platform$acceptNonblockFlag
	.xword	.L__axiom_symn_91
	.xword	31                              // 0x1f
	.xword	Mem$memAlloc
	.xword	.L__axiom_symn_92
	.xword	12                              // 0xc
	.xword	Mem$memAllocMapped
	.xword	.L__axiom_symn_93
	.xword	18                              // 0x12
	.xword	Mem$memMarkArray
	.xword	.L__axiom_symn_94
	.xword	16                              // 0x10
	.xword	Mem$memMarkLeaf
	.xword	.L__axiom_symn_95
	.xword	15                              // 0xf
	.xword	Mem$memCopy
	.xword	.L__axiom_symn_96
	.xword	11                              // 0xb
	.xword	Mem$memCopyFrom
	.xword	.L__axiom_symn_97
	.xword	15                              // 0xf
	.xword	Mem$memSet
	.xword	.L__axiom_symn_98
	.xword	10                              // 0xa
	.xword	Mem$memSetFrom
	.xword	.L__axiom_symn_99
	.xword	14                              // 0xe
	.xword	Mem$memCmp
	.xword	.L__axiom_symn_100
	.xword	10                              // 0xa
	.xword	Mem$memCmpFrom
	.xword	.L__axiom_symn_101
	.xword	14                              // 0xe
	.xword	Mem$memGetWord
	.xword	.L__axiom_symn_102
	.xword	14                              // 0xe
	.xword	Mem$memGetWordStr
	.xword	.L__axiom_symn_103
	.xword	17                              // 0x11
	.xword	Mem$memSetWord
	.xword	.L__axiom_symn_104
	.xword	14                              // 0xe
	.xword	Mem$memGetByte
	.xword	.L__axiom_symn_105
	.xword	14                              // 0xe
	.xword	Mem$memPutByte
	.xword	.L__axiom_symn_106
	.xword	14                              // 0xe
	.xword	Vec$vecDefaultCap
	.xword	.L__axiom_symn_107
	.xword	17                              // 0x11
	.xword	Vec$vecNew
	.xword	.L__axiom_symn_108
	.xword	10                              // 0xa
	.xword	Vec$vecWithCapacity
	.xword	.L__axiom_symn_109
	.xword	19                              // 0x13
	.xword	Vec$vecWithCapacityRef
	.xword	.L__axiom_symn_110
	.xword	22                              // 0x16
	.xword	Vec$vecNewRef
	.xword	.L__axiom_symn_111
	.xword	13                              // 0xd
	.xword	Vec$vecBuild
	.xword	.L__axiom_symn_112
	.xword	12                              // 0xc
	.xword	Vec$vecFree
	.xword	.L__axiom_symn_113
	.xword	11                              // 0xb
	.xword	Vec$vecOwnsRefs
	.xword	.L__axiom_symn_114
	.xword	15                              // 0xf
	.xword	Vec$vecLen
	.xword	.L__axiom_symn_115
	.xword	10                              // 0xa
	.xword	Vec$vecCap
	.xword	.L__axiom_symn_116
	.xword	10                              // 0xa
	.xword	Vec$vecData
	.xword	.L__axiom_symn_117
	.xword	11                              // 0xb
	.xword	Vec$vecGet
	.xword	.L__axiom_symn_118
	.xword	10                              // 0xa
	.xword	Vec$vecTry
	.xword	.L__axiom_symn_119
	.xword	10                              // 0xa
	.xword	Vec$vecGetStr
	.xword	.L__axiom_symn_120
	.xword	13                              // 0xd
	.xword	Vec$vecSet
	.xword	.L__axiom_symn_121
	.xword	10                              // 0xa
	.xword	Vec$vecReserve
	.xword	.L__axiom_symn_122
	.xword	14                              // 0xe
	.xword	Vec$vecGrownCap
	.xword	.L__axiom_symn_123
	.xword	15                              // 0xf
	.xword	Vec$vecReserveExactly
	.xword	.L__axiom_symn_124
	.xword	21                              // 0x15
	.xword	Vec$vecPush
	.xword	.L__axiom_symn_125
	.xword	11                              // 0xb
	.xword	Vec$vecPop
	.xword	.L__axiom_symn_126
	.xword	10                              // 0xa
	.xword	Vec$vecLast
	.xword	.L__axiom_symn_127
	.xword	11                              // 0xb
	.xword	Vec$vecClear
	.xword	.L__axiom_symn_128
	.xword	12                              // 0xc
	.xword	Vec$vecDropAt
	.xword	.L__axiom_symn_129
	.xword	13                              // 0xd
	.xword	Vec$vecDropFrom
	.xword	.L__axiom_symn_130
	.xword	15                              // 0xf
	.xword	Vec$vecSum
	.xword	.L__axiom_symn_131
	.xword	10                              // 0xa
	.xword	Vec$vecSumFrom
	.xword	.L__axiom_symn_132
	.xword	14                              // 0xe
	.xword	Vec$vecHash
	.xword	.L__axiom_symn_133
	.xword	11                              // 0xb
	.xword	Vec$vecHashFrom
	.xword	.L__axiom_symn_134
	.xword	15                              // 0xf
	.xword	Str$strWrap
	.xword	.L__axiom_symn_135
	.xword	11                              // 0xb
	.xword	Str$strWrapOwned
	.xword	.L__axiom_symn_136
	.xword	16                              // 0x10
	.xword	Str$strAlloc
	.xword	.L__axiom_symn_137
	.xword	12                              // 0xc
	.xword	Str$strFromLit
	.xword	.L__axiom_symn_138
	.xword	14                              // 0xe
	.xword	Str$cstrLen
	.xword	.L__axiom_symn_139
	.xword	11                              // 0xb
	.xword	Str$strLen
	.xword	.L__axiom_symn_140
	.xword	10                              // 0xa
	.xword	Str$strData
	.xword	.L__axiom_symn_141
	.xword	11                              // 0xb
	.xword	Str$strOwner
	.xword	.L__axiom_symn_142
	.xword	12                              // 0xc
	.xword	Str$strByte
	.xword	.L__axiom_symn_143
	.xword	11                              // 0xb
	.xword	Str$strCStr
	.xword	.L__axiom_symn_144
	.xword	11                              // 0xb
	.xword	Str$strIsEmpty
	.xword	.L__axiom_symn_145
	.xword	14                              // 0xe
	.xword	Str$strCmp
	.xword	.L__axiom_symn_146
	.xword	10                              // 0xa
	.xword	Str$strEq
	.xword	.L__axiom_symn_147
	.xword	9                               // 0x9
	.xword	Str$strSlice
	.xword	.L__axiom_symn_148
	.xword	12                              // 0xc
	.xword	Str$strDup
	.xword	.L__axiom_symn_149
	.xword	10                              // 0xa
	.xword	Str$strConcat
	.xword	.L__axiom_symn_150
	.xword	13                              // 0xd
	.xword	Str$strFindByte
	.xword	.L__axiom_symn_151
	.xword	15                              // 0xf
	.xword	Str$strStartsWith
	.xword	.L__axiom_symn_152
	.xword	17                              // 0x11
	.xword	Str$strIsDigit
	.xword	.L__axiom_symn_153
	.xword	14                              // 0xe
	.xword	Str$strIsAlpha
	.xword	.L__axiom_symn_154
	.xword	14                              // 0xe
	.xword	Str$strIsSpace
	.xword	.L__axiom_symn_155
	.xword	14                              // 0xe
	.xword	Str$strHexVal
	.xword	.L__axiom_symn_156
	.xword	13                              // 0xd
	.xword	Str$strIsHexDigit
	.xword	.L__axiom_symn_157
	.xword	17                              // 0x11
	.xword	Str$strSplit
	.xword	.L__axiom_symn_158
	.xword	12                              // 0xc
	.xword	Str$strSplitFrom
	.xword	.L__axiom_symn_159
	.xword	16                              // 0x10
	.xword	Str$strFromByte
	.xword	.L__axiom_symn_160
	.xword	15                              // 0xf
	.xword	Fmt$intIsMostNegative
	.xword	.L__axiom_symn_161
	.xword	21                              // 0x15
	.xword	Fmt$fmtIntWidth
	.xword	.L__axiom_symn_162
	.xword	15                              // 0xf
	.xword	Fmt$fmtInt
	.xword	.L__axiom_symn_163
	.xword	10                              // 0xa
	.xword	Fmt$fmtNat
	.xword	.L__axiom_symn_164
	.xword	10                              // 0xa
	.xword	Fmt$fmtDigits
	.xword	.L__axiom_symn_165
	.xword	13                              // 0xd
	.xword	Fmt$fmtHexShr4
	.xword	.L__axiom_symn_166
	.xword	14                              // 0xe
	.xword	Fmt$fmtHex
	.xword	.L__axiom_symn_167
	.xword	10                              // 0xa
	.xword	Fmt$fmtHexWidth
	.xword	.L__axiom_symn_168
	.xword	15                              // 0xf
	.xword	Fmt$fmtHexDigits
	.xword	.L__axiom_symn_169
	.xword	16                              // 0x10
	.xword	Fmt$fmtPadLeft
	.xword	.L__axiom_symn_170
	.xword	14                              // 0xe
	.xword	Fmt$fmtPadRight
	.xword	.L__axiom_symn_171
	.xword	15                              // 0xf
	.xword	Fmt$fmtPadCenter
	.xword	.L__axiom_symn_172
	.xword	16                              // 0x10
	.xword	Fmt$fmtPadZerosLeft
	.xword	.L__axiom_symn_173
	.xword	19                              // 0x13
	.xword	Fmt$fmtHexUpper
	.xword	.L__axiom_symn_174
	.xword	15                              // 0xf
	.xword	Fmt$fmtHexDigitsUpper
	.xword	.L__axiom_symn_175
	.xword	21                              // 0x15
	.xword	Fmt$powTen
	.xword	.L__axiom_symn_176
	.xword	10                              // 0xa
	.xword	Fmt$fmtPadZeros
	.xword	.L__axiom_symn_177
	.xword	15                              // 0xf
	.xword	Fmt$fmtFloat
	.xword	.L__axiom_symn_178
	.xword	12                              // 0xc
	.xword	Fmt$fmtFloatPrec
	.xword	.L__axiom_symn_179
	.xword	16                              // 0x10
	.xword	Fmt$fmtFloatAbs
	.xword	.L__axiom_symn_180
	.xword	15                              // 0xf
	.xword	Sys$stdin
	.xword	.L__axiom_symn_181
	.xword	9                               // 0x9
	.xword	Sys$stdout
	.xword	.L__axiom_symn_182
	.xword	10                              // 0xa
	.xword	Sys$stderr
	.xword	.L__axiom_symn_183
	.xword	10                              // 0xa
	.xword	Sys$sysWriteFd
	.xword	.L__axiom_symn_184
	.xword	14                              // 0xe
	.xword	Sys$sysWriteAllFd
	.xword	.L__axiom_symn_185
	.xword	17                              // 0x11
	.xword	Sys$sysReadFd
	.xword	.L__axiom_symn_186
	.xword	13                              // 0xd
	.xword	Sys$sysOpenPath
	.xword	.L__axiom_symn_187
	.xword	15                              // 0xf
	.xword	Sys$sysOpenPathMode
	.xword	.L__axiom_symn_188
	.xword	19                              // 0x13
	.xword	Sys$sysCloseFd
	.xword	.L__axiom_symn_189
	.xword	14                              // 0xe
	.xword	Sys$sysSeek
	.xword	.L__axiom_symn_190
	.xword	11                              // 0xb
	.xword	Sys$sysExitWith
	.xword	.L__axiom_symn_191
	.xword	15                              // 0xf
	.xword	Sys$sysFailed
	.xword	.L__axiom_symn_192
	.xword	13                              // 0xd
	.xword	Sys$sysErrno
	.xword	.L__axiom_symn_193
	.xword	12                              // 0xc
	.xword	Sys$sysReadFile
	.xword	.L__axiom_symn_194
	.xword	15                              // 0xf
	.xword	Sys$sysReadAll
	.xword	.L__axiom_symn_195
	.xword	14                              // 0xe
	.xword	Sys$sysArgc
	.xword	.L__axiom_symn_196
	.xword	11                              // 0xb
	.xword	Sys$sysArg
	.xword	.L__axiom_symn_197
	.xword	10                              // 0xa
	.xword	Sys$sysWriteFile
	.xword	.L__axiom_symn_198
	.xword	16                              // 0x10
	.xword	Sys$sysAppendFile
	.xword	.L__axiom_symn_199
	.xword	17                              // 0x11
	.xword	Sys$sysRename
	.xword	.L__axiom_symn_200
	.xword	13                              // 0xd
	.xword	Sys$sysUnlink
	.xword	.L__axiom_symn_201
	.xword	13                              // 0xd
	.xword	Sys$sysMkdir
	.xword	.L__axiom_symn_202
	.xword	12                              // 0xc
	.xword	Sys$sysDirMode
	.xword	.L__axiom_symn_203
	.xword	14                              // 0xe
	.xword	Sys$sysRmdir
	.xword	.L__axiom_symn_204
	.xword	12                              // 0xc
	.xword	Sys$sysFileExists
	.xword	.L__axiom_symn_205
	.xword	17                              // 0x11
	.xword	Sys$sysFileSize
	.xword	.L__axiom_symn_206
	.xword	15                              // 0xf
	.xword	Sys$sysReadErrno
	.xword	.L__axiom_symn_207
	.xword	16                              // 0x10
	.xword	Sys$sysIsDir
	.xword	.L__axiom_symn_208
	.xword	12                              // 0xc
	.xword	Sys$sysDirBufBytes
	.xword	.L__axiom_symn_209
	.xword	18                              // 0x12
	.xword	Sys$sysReadDir
	.xword	.L__axiom_symn_210
	.xword	14                              // 0xe
	.xword	Sys$sysReadDirLoop
	.xword	.L__axiom_symn_211
	.xword	18                              // 0x12
	.xword	Sys$sysReadDirDecode
	.xword	.L__axiom_symn_212
	.xword	20                              // 0x14
	.xword	Sys$sysGetCwd
	.xword	.L__axiom_symn_213
	.xword	13                              // 0xd
	.xword	Sys$sysEnvSlot
	.xword	.L__axiom_symn_214
	.xword	14                              // 0xe
	.xword	Sys$sysEnvCount
	.xword	.L__axiom_symn_215
	.xword	15                              // 0xf
	.xword	Sys$sysEnvCountFrom
	.xword	.L__axiom_symn_216
	.xword	19                              // 0x13
	.xword	Sys$sysEnv
	.xword	.L__axiom_symn_217
	.xword	10                              // 0xa
	.xword	Sys$sysEnvLookup
	.xword	.L__axiom_symn_218
	.xword	16                              // 0x10
	.xword	Sys$sysEnvp
	.xword	.L__axiom_symn_219
	.xword	11                              // 0xb
	.xword	Sys$sysEnvpFill
	.xword	.L__axiom_symn_220
	.xword	15                              // 0xf
	.xword	Sys$sysSpawn
	.xword	.L__axiom_symn_221
	.xword	12                              // 0xc
	.xword	Sys$sysWaitPid
	.xword	.L__axiom_symn_222
	.xword	14                              // 0xe
	.xword	Sys$sysExitCode
	.xword	.L__axiom_symn_223
	.xword	15                              // 0xf
	.xword	Sys$sysTermSignal
	.xword	.L__axiom_symn_224
	.xword	17                              // 0x11
	.xword	Sys$sysRun
	.xword	.L__axiom_symn_225
	.xword	10                              // 0xa
	.xword	Sys$sysRunPath
	.xword	.L__axiom_symn_226
	.xword	14                              // 0xe
	.xword	Sys$sysRunSearch
	.xword	.L__axiom_symn_227
	.xword	16                              // 0x10
	.xword	Sys$sysGetPid
	.xword	.L__axiom_symn_228
	.xword	13                              // 0xd
	.xword	Sys$sysNowMicros
	.xword	.L__axiom_symn_229
	.xword	16                              // 0x10
	.xword	Sys$sysNowMonotonic
	.xword	.L__axiom_symn_230
	.xword	19                              // 0x13
	.xword	Sys$netSocketTcp
	.xword	.L__axiom_symn_231
	.xword	16                              // 0x10
	.xword	Sys$netSocketTcp6
	.xword	.L__axiom_symn_232
	.xword	17                              // 0x11
	.xword	Sys$netAddr4Bytes
	.xword	.L__axiom_symn_233
	.xword	17                              // 0x11
	.xword	Sys$netAddr6Bytes
	.xword	.L__axiom_symn_234
	.xword	17                              // 0x11
	.xword	Sys$netAddrMaxBytes
	.xword	.L__axiom_symn_235
	.xword	19                              // 0x13
	.xword	Sys$netAddr4
	.xword	.L__axiom_symn_236
	.xword	12                              // 0xc
	.xword	Sys$netAddr6
	.xword	.L__axiom_symn_237
	.xword	12                              // 0xc
	.xword	Sys$netPutGroup
	.xword	.L__axiom_symn_238
	.xword	15                              // 0xf
	.xword	Sys$netGetGroup
	.xword	.L__axiom_symn_239
	.xword	15                              // 0xf
	.xword	Sys$netAddrFamily
	.xword	.L__axiom_symn_240
	.xword	17                              // 0x11
	.xword	Sys$netAddrPort
	.xword	.L__axiom_symn_241
	.xword	15                              // 0xf
	.xword	Sys$netAddrSize
	.xword	.L__axiom_symn_242
	.xword	15                              // 0xf
	.xword	Sys$netBind
	.xword	.L__axiom_symn_243
	.xword	11                              // 0xb
	.xword	Sys$netListen
	.xword	.L__axiom_symn_244
	.xword	13                              // 0xd
	.xword	Sys$netAccept
	.xword	.L__axiom_symn_245
	.xword	13                              // 0xd
	.xword	Sys$netAcceptFinish
	.xword	.L__axiom_symn_246
	.xword	19                              // 0x13
	.xword	Sys$netAcceptFrom
	.xword	.L__axiom_symn_247
	.xword	17                              // 0x11
	.xword	Sys$netAddrLenRead
	.xword	.L__axiom_symn_248
	.xword	18                              // 0x12
	.xword	Sys$netPutInt32
	.xword	.L__axiom_symn_249
	.xword	15                              // 0xf
	.xword	Sys$netGetInt32
	.xword	.L__axiom_symn_250
	.xword	15                              // 0xf
	.xword	Sys$netAddrText
	.xword	.L__axiom_symn_251
	.xword	15                              // 0xf
	.xword	Sys$netAddrText4
	.xword	.L__axiom_symn_252
	.xword	16                              // 0x10
	.xword	Sys$netAddrZeroRun
	.xword	.L__axiom_symn_253
	.xword	18                              // 0x12
	.xword	Sys$netAddrZeroRunStart
	.xword	.L__axiom_symn_254
	.xword	23                              // 0x17
	.xword	Sys$netAddrText6
	.xword	.L__axiom_symn_255
	.xword	16                              // 0x10
	.xword	Sys$netAddrTextPort
	.xword	.L__axiom_symn_256
	.xword	19                              // 0x13
	.xword	Sys$netSetBlocking
	.xword	.L__axiom_symn_257
	.xword	18                              // 0x12
	.xword	Sys$netConnect
	.xword	.L__axiom_symn_258
	.xword	14                              // 0xe
	.xword	Sys$netShutdown
	.xword	.L__axiom_symn_259
	.xword	15                              // 0xf
	.xword	Sys$netSetOptInt
	.xword	.L__axiom_symn_260
	.xword	16                              // 0x10
	.xword	Sys$netSetNonBlocking
	.xword	.L__axiom_symn_261
	.xword	21                              // 0x15
	.xword	Sys$netWouldBlock
	.xword	.L__axiom_symn_262
	.xword	17                              // 0x11
	.xword	Sys$netPutWord
	.xword	.L__axiom_symn_263
	.xword	14                              // 0xe
	.xword	Sys$netGetWord
	.xword	.L__axiom_symn_264
	.xword	14                              // 0xe
	.xword	Sys$netPollBufBytes
	.xword	.L__axiom_symn_265
	.xword	19                              // 0x13
	.xword	Sys$netPollCreate
	.xword	.L__axiom_symn_266
	.xword	17                              // 0x11
	.xword	Sys$netPollRec
	.xword	.L__axiom_symn_267
	.xword	14                              // 0xe
	.xword	Sys$netPollAddRead
	.xword	.L__axiom_symn_268
	.xword	18                              // 0x12
	.xword	Sys$netPollDelRead
	.xword	.L__axiom_symn_269
	.xword	18                              // 0x12
	.xword	Sys$netPollWait
	.xword	.L__axiom_symn_270
	.xword	15                              // 0xf
	.xword	Sys$netPollFdAt
	.xword	.L__axiom_symn_271
	.xword	15                              // 0xf
	.xword	Sys$sysRandomBytes
	.xword	.L__axiom_symn_272
	.xword	18                              // 0x12
	.xword	Sys$sysSigBit
	.xword	.L__axiom_symn_273
	.xword	13                              // 0xd
	.xword	Sys$sysSignalBlock
	.xword	.L__axiom_symn_274
	.xword	18                              // 0x12
	.xword	Sys$netSignalOpen
	.xword	.L__axiom_symn_275
	.xword	17                              // 0x11
	.xword	Sys$netPollSignalAt
	.xword	.L__axiom_symn_276
	.xword	19                              // 0x13
	.xword	Sys$sysKill
	.xword	.L__axiom_symn_277
	.xword	11                              // 0xb
	.xword	Sys$sysForkProcess
	.xword	.L__axiom_symn_278
	.xword	18                              // 0x12
	.xword	IO$writeStr
	.xword	.L__axiom_symn_279
	.xword	11                              // 0xb
	.xword	IO$printLit
	.xword	.L__axiom_symn_280
	.xword	11                              // 0xb
	.xword	IO$printlnLit
	.xword	.L__axiom_symn_281
	.xword	13                              // 0xd
	.xword	IO$readFileLit
	.xword	.L__axiom_symn_282
	.xword	14                              // 0xe
	.xword	IO$readFile
	.xword	.L__axiom_symn_283
	.xword	11                              // 0xb
	.xword	IO$ioPath
	.xword	.L__axiom_symn_284
	.xword	9                               // 0x9
	.xword	IO$writeFile
	.xword	.L__axiom_symn_285
	.xword	12                              // 0xc
	.xword	IO$appendFile
	.xword	.L__axiom_symn_286
	.xword	13                              // 0xd
	.xword	IO$removeFile
	.xword	.L__axiom_symn_287
	.xword	13                              // 0xd
	.xword	IO$renamePath
	.xword	.L__axiom_symn_288
	.xword	13                              // 0xd
	.xword	IO$copyFile
	.xword	.L__axiom_symn_289
	.xword	11                              // 0xb
	.xword	IO$fileExists
	.xword	.L__axiom_symn_290
	.xword	13                              // 0xd
	.xword	IO$isDir
	.xword	.L__axiom_symn_291
	.xword	8                               // 0x8
	.xword	IO$fileSize
	.xword	.L__axiom_symn_292
	.xword	11                              // 0xb
	.xword	IO$readErrno
	.xword	.L__axiom_symn_293
	.xword	12                              // 0xc
	.xword	IO$makeDir
	.xword	.L__axiom_symn_294
	.xword	10                              // 0xa
	.xword	IO$makeDirAll
	.xword	.L__axiom_symn_295
	.xword	13                              // 0xd
	.xword	IO$makeDirAllFrom
	.xword	.L__axiom_symn_296
	.xword	17                              // 0x11
	.xword	IO$makeDirOk
	.xword	.L__axiom_symn_297
	.xword	12                              // 0xc
	.xword	IO$removeDir
	.xword	.L__axiom_symn_298
	.xword	12                              // 0xc
	.xword	IO$listDir
	.xword	.L__axiom_symn_299
	.xword	10                              // 0xa
	.xword	IO$listDirKeep
	.xword	.L__axiom_symn_300
	.xword	14                              // 0xe
	.xword	IO$listDirInsert
	.xword	.L__axiom_symn_301
	.xword	16                              // 0x10
	.xword	IO$listDirSift
	.xword	.L__axiom_symn_302
	.xword	14                              // 0xe
	.xword	IO$cwd
	.xword	.L__axiom_symn_303
	.xword	6                               // 0x6
	.xword	IO$exit
	.xword	.L__axiom_symn_304
	.xword	7                               // 0x7
	.xword	IO$die
	.xword	.L__axiom_symn_305
	.xword	6                               // 0x6
	.xword	ask
	.xword	.L__axiom_symn_306
	.xword	3                               // 0x3
	.xword	usable
	.xword	.L__axiom_symn_307
	.xword	6                               // 0x6
	.xword	__axiom_user_main
	.xword	.L__axiom_symn_308
	.xword	17                              // 0x11
	.xword	_lam_0
	.xword	.L__axiom_symn_309
	.xword	6                               // 0x6
	.xword	"Show#String#show"
	.xword	.L__axiom_symn_310
	.xword	16                              // 0x10
	.xword	"Show#Int#show"
	.xword	.L__axiom_symn_311
	.xword	13                              // 0xd
	.xword	"Show#Bool#show"
	.xword	.L__axiom_symn_312
	.xword	14                              // 0xe
	.xword	"Show#Float#show"
	.xword	.L__axiom_symn_313
	.xword	15                              // 0xf
	.xword	__axiom_recover_save
	.xword	.L__axiom_symn_314
	.xword	20                              // 0x14
	.xword	__axiom_recover_load
	.xword	.L__axiom_symn_315
	.xword	20                              // 0x14
	.size	__axiom_symtab, 7584

	.type	.L__axiom_bt_hdr,@object        // @__axiom_bt_hdr
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.L__axiom_bt_hdr:
	.ascii	"axiom: backtrace (most recent call first)\n"
	.size	.L__axiom_bt_hdr, 42

	.type	.L__axiom_bt_at,@object         // @__axiom_bt_at
	.p2align	2, 0x0
.L__axiom_bt_at:
	.ascii	"  at "
	.size	.L__axiom_bt_at, 5

	.type	.L__axiom_bt_nl,@object         // @__axiom_bt_nl
	.p2align	2, 0x0
.L__axiom_bt_nl:
	.byte	10
	.size	.L__axiom_bt_nl, 1

	.type	.L__axiom_bt_unk,@object        // @__axiom_bt_unk
	.p2align	2, 0x0
.L__axiom_bt_unk:
	.ascii	"<unknown>"
	.size	.L__axiom_bt_unk, 9

	.section	".note.GNU-stack","",@progbits
