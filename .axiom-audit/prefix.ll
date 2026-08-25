target triple = "aarch64-unknown-linux-gnu"

@__axiom_argc = internal global i64 0
@__axiom_argv = internal global i64 0

define i64 @main(i64 %argc, i64 %argv) #0 {
entry:
  store i64 %argc, ptr @__axiom_argc
  store i64 %argv, ptr @__axiom_argv
  %r = call i64 @__axiom_user_main()
  ret i64 %r
}

@__axiom_bump = internal global i64 0
@__axiom_bump_end = internal global i64 0
@__axiom_chunk = internal global i64 0
@__axiom_free = internal global i64 0
@__axiom_high = internal global i64 0
@__axiom_slabs = internal global [4097 x i64] zeroinitializer

define i64 @axiom_alloc(i64 %size) #0 {
entry:
  %iszero = icmp eq i64 %size, 0
  br i1 %iszero, label %zero, label %sized
zero:
  %zb = load i64, ptr @__axiom_bump
  ret i64 %zb
sized:
  %padded = add i64 %size, 15
  %sz0 = and i64 %padded, -16
  %sz = add i64 %sz0, 16
  %small = icmp ule i64 %sz0, 65536
  br i1 %small, label %try_pop, label %bump_path
try_pop:
  %cls = lshr i64 %sz0, 4
  %slotp = getelementptr [4097 x i64], ptr @__axiom_slabs, i64 0, i64 %cls
  %shead = load i64, ptr %slotp
  %sempty = icmp eq i64 %shead, 0
  br i1 %sempty, label %bump_path, label %pop
pop:
  %pnextp = inttoptr i64 %shead to ptr
  %pnext = load i64, ptr %pnextp
  store i64 %pnext, ptr %slotp
  %pe = add i64 %shead, %sz
  %ph = load i64, ptr @__axiom_high
  br label %handout
bump_path:
  %cur = load i64, ptr @__axiom_bump
  %next = add i64 %cur, %sz
  %end = load i64, ptr @__axiom_bump_end
  %fits = icmp ule i64 %next, %end
  br i1 %fits, label %fast, label %refill
fast:
  store i64 %next, ptr @__axiom_bump
  %high = load i64, ptr @__axiom_high
  br label %handout
refill:
  %need = add i64 %sz, 16
  %big = icmp ugt i64 %need, 1048576
  %rounded0 = add i64 %need, 65535
  %rounded = and i64 %rounded0, -65536
  %chunk = select i1 %big, i64 %rounded, i64 1048576
  %fhead = load i64, ptr @__axiom_free
  br label %scan
scan:
  %cand = phi i64 [ %fhead, %refill ], [ %cnext, %scan_next ]
  %prev = phi i64 [ 0, %refill ], [ %cand, %scan_next ]
  %exhausted = icmp eq i64 %cand, 0
  br i1 %exhausted, label %map, label %scan_test
scan_test:
  %candp = inttoptr i64 %cand to ptr
  %candsz = load i64, ptr %candp
  %candlink = add i64 %cand, 8
  %candlinkp = inttoptr i64 %candlink to ptr
  %cnext = load i64, ptr %candlinkp
  %roomy = icmp uge i64 %candsz, %chunk
  br i1 %roomy, label %unlink, label %scan_next
scan_next:
  br label %scan
unlink:
  %cand_end = add i64 %cand, %candsz
  %at_head = icmp eq i64 %prev, 0
  br i1 %at_head, label %unlink_head, label %unlink_mid
unlink_head:
  store i64 %cnext, ptr @__axiom_free
  br label %install
unlink_mid:
  %prevlink = add i64 %prev, 8
  %prevlinkp = inttoptr i64 %prevlink to ptr
  store i64 %cnext, ptr %prevlinkp
  br label %install
map:
  %addr = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 222, i64 0, i64 %chunk, i64 3, i64 34, i64 -1, i64 0)
  %failed_low = icmp ult i64 %addr, 4096
  %failed_neg = icmp ugt i64 %addr, -4096
  %failed = or i1 %failed_low, %failed_neg
  br i1 %failed, label %oom, label %mapped
mapped:
  %virgin_high = add i64 %addr, 16
  br label %install
install:
  %base = phi i64 [ %addr, %mapped ], [ %cand, %unlink_head ], [ %cand, %unlink_mid ]
  %bsize = phi i64 [ %chunk, %mapped ], [ %candsz, %unlink_head ], [ %candsz, %unlink_mid ]
  %chunk_high = phi i64 [ %virgin_high, %mapped ], [ %cand_end, %unlink_head ], [ %cand_end, %unlink_mid ]
  %basep = inttoptr i64 %base to ptr
  store i64 %bsize, ptr %basep
  %baselink = add i64 %base, 8
  %baselinkp = inttoptr i64 %baselink to ptr
  %chead = load i64, ptr @__axiom_chunk
  store i64 %chead, ptr %baselinkp
  store i64 %base, ptr @__axiom_chunk
  %data = add i64 %base, 16
  %new_bump = add i64 %data, %sz
  store i64 %new_bump, ptr @__axiom_bump
  %new_end = add i64 %base, %bsize
  store i64 %new_end, ptr @__axiom_bump_end
  br label %handout
handout:
  %hb = phi i64 [ %cur, %fast ], [ %data, %install ], [ %shead, %pop ]
  %he = phi i64 [ %next, %fast ], [ %new_bump, %install ], [ %pe, %pop ]
  %hh = phi i64 [ %high, %fast ], [ %chunk_high, %install ], [ %ph, %pop ]
  %recyc = phi i1 [ false, %fast ], [ false, %install ], [ true, %pop ]
  %past = icmp ugt i64 %he, %hh
  %bstop = select i1 %past, i64 %hh, i64 %he
  %stop = select i1 %recyc, i64 %he, i64 %bstop
  %nh = select i1 %past, i64 %he, i64 %hh
  %newhigh = select i1 %recyc, i64 %hh, i64 %nh
  store i64 %newhigh, ptr @__axiom_high
  br label %wipe
wipe:
  %wi = phi i64 [ %hb, %handout ], [ %wnext, %wipe_body ]
  %wmore = icmp ult i64 %wi, %stop
  br i1 %wmore, label %wipe_body, label %wiped
wipe_body:
  %wp = inttoptr i64 %wi to ptr
  store i64 0, ptr %wp
  %wnext = add i64 %wi, 8
  br label %wipe
wiped:
  %cwp = inttoptr i64 %hb to ptr
  store i64 0, ptr %cwp
  %shpw = add i64 %hb, 8
  %shpwp = inttoptr i64 %shpw to ptr
  %wcnt = lshr i64 %sz0, 3
  %wbig = icmp ugt i64 %wcnt, 16383
  %wleaf = select i1 %wbig, i64 0, i64 %wcnt
  %wshp = shl i64 %wleaf, 1
  store i64 %wshp, ptr %shpwp
  %user = add i64 %hb, 16
  ret i64 %user
oom:
  call i64 @__axiom_out_of_memory()
  unreachable
}

define void @axiom_retain(i64 %h) #0 {
entry:
  %imm = icmp slt i64 %h, 4096
  br i1 %imm, label %done, label %chk
chk:
  %hoff = add i64 %h, -16
  %cp = inttoptr i64 %hoff to ptr
  %c = load i64, ptr %cp
  %stat = icmp eq i64 %c, -1
  br i1 %stat, label %done, label %bump
bump:
  %c1 = add i64 %c, 1
  store i64 %c1, ptr %cp
  br label %done
done:
  ret void
}

define void @axiom_release(i64 %h0) #0 {
start:
  %dead = alloca i64
  %cur = alloca i64
  %D = alloca i64
  %wi = alloca i64
  %wm = alloca i64
  %warr = alloca i64
  store i64 0, ptr %dead
  store i64 0, ptr %warr
  store i64 0, ptr %D
  store i64 %h0, ptr %cur
  br label %relone
relone:
  %h = load i64, ptr %cur
  %imm = icmp slt i64 %h, 4096
  br i1 %imm, label %after, label %chk
chk:
  %hoff = add i64 %h, -16
  %cp = inttoptr i64 %hoff to ptr
  %c = load i64, ptr %cp
  %stat = icmp eq i64 %c, -1
  br i1 %stat, label %after, label %live
live:
  %zero = icmp eq i64 %c, 0
  br i1 %zero, label %after, label %dec
dec:
  %c1 = add i64 %c, -1
  store i64 %c1, ptr %cp
  %isdead = icmp eq i64 %c1, 0
  br i1 %isdead, label %dead0, label %after
dead0:
  %shq = add i64 %h, -8
  %shqp = inttoptr i64 %shq to ptr
  %shw = load i64, ptr %shqp
  %formb = and i64 %shw, 1
  %isrec = icmp eq i64 %formb, 0
  %map0 = lshr i64 %shw, 16
  %hasmap = icmp ne i64 %map0, 0
  %aform = and i64 %shw, 32768
  %isarr = icmp ne i64 %aform, 0
  %needw = or i1 %hasmap, %isarr
  %dowalk = and i1 %isrec, %needw
  br i1 %dowalk, label %defer, label %notrec
notrec:
  br i1 %isrec, label %filev, label %foreign
foreign:
  %fdp = inttoptr i64 %h to ptr
  %fdrop = load i64, ptr %fdp
  %fa1 = add i64 %h, 8
  %fap = inttoptr i64 %fa1 to ptr
  %farg = load i64, ptr %fap
  %fhas = icmp ne i64 %fdrop, 0
  %fliv = icmp ne i64 %farg, 0
  %fdo = and i1 %fhas, %fliv
  br i1 %fdo, label %fcall, label %filev
fcall:
  store i64 0, ptr %fap
  %ffp = inttoptr i64 %fdrop to ptr
  %fres = call i64 %ffp(i64 %farg)
  br label %filev
defer:
  %dh = load i64, ptr %dead
  store i64 %dh, ptr %cp
  store i64 %h, ptr %dead
  br label %after
filev:
  %bcnt0 = lshr i64 %shw, 1
  %bcnt = and i64 %bcnt0, 16383
  %ok1 = icmp ne i64 %bcnt, 0
  %ok2 = icmp ule i64 %bcnt, 8192
  %ok = and i1 %ok1, %ok2
  br i1 %ok, label %push, label %after
push:
  %pcls = lshr i64 %bcnt, 1
  %pslotp = getelementptr [4097 x i64], ptr @__axiom_slabs, i64 0, i64 %pcls
  %ohead = load i64, ptr %pslotp
  store i64 %ohead, ptr %cp
  store i64 %hoff, ptr %pslotp
  br label %after
after:
  %D0 = load i64, ptr %D
  %hasD = icmp ne i64 %D0, 0
  br i1 %hasD, label %walk, label %drain
walk:
  %Dw = load i64, ptr %D
  %m = load i64, ptr %wm
  %warrf = load i64, ptr %warr
  %wisarr = icmp ne i64 %warrf, 0
  %mzero = icmp eq i64 %m, 0
  br i1 %mzero, label %fileD, label %stepone
stepone:
  br i1 %wisarr, label %arrstep, label %testbit
arrstep:
  %ai = load i64, ptr %wi
  %am1 = add i64 %m, -1
  %ai1 = add i64 %ai, 1
  store i64 %am1, ptr %wm
  store i64 %ai1, ptr %wi
  br label %relchild
testbit:
  %i = load i64, ptr %wi
  %bit = and i64 %m, 1
  %m1 = lshr i64 %m, 1
  %i1 = add i64 %i, 1
  store i64 %m1, ptr %wm
  store i64 %i1, ptr %wi
  %isset = icmp ne i64 %bit, 0
  br i1 %isset, label %relchild, label %walk
relchild:
  %ri = phi i64 [ %i, %testbit ], [ %ai, %arrstep ]
  %woff = shl i64 %ri, 3
  %waddr = add i64 %Dw, %woff
  %waddrp = inttoptr i64 %waddr to ptr
  %wval = load i64, ptr %waddrp
  store i64 %wval, ptr %cur
  br label %relone
fileD:
  %dq = add i64 %Dw, -8
  %dqp = inttoptr i64 %dq to ptr
  %dshw = load i64, ptr %dqp
  %dcnt0 = lshr i64 %dshw, 1
  %dcnt = and i64 %dcnt0, 16383
  %dok1 = icmp ne i64 %dcnt, 0
  %dok2 = icmp ule i64 %dcnt, 8192
  %dok = and i1 %dok1, %dok2
  store i64 0, ptr %D
  br i1 %dok, label %pushD, label %drain
pushD:
  %dcls = lshr i64 %dcnt, 1
  %dslotp = getelementptr [4097 x i64], ptr @__axiom_slabs, i64 0, i64 %dcls
  %dohead = load i64, ptr %dslotp
  %dbase = add i64 %Dw, -16
  %dbasep = inttoptr i64 %dbase to ptr
  store i64 %dohead, ptr %dbasep
  store i64 %dbase, ptr %dslotp
  br label %drain
drain:
  %dl = load i64, ptr %dead
  %empty = icmp eq i64 %dl, 0
  br i1 %empty, label %done, label %popD
popD:
  %lp0 = add i64 %dl, -16
  %lpp = inttoptr i64 %lp0 to ptr
  %nxt = load i64, ptr %lpp
  store i64 %nxt, ptr %dead
  store i64 %dl, ptr %D
  store i64 0, ptr %wi
  %pq = add i64 %dl, -8
  %pqp = inttoptr i64 %pq to ptr
  %pshw = load i64, ptr %pqp
  %pmap = lshr i64 %pshw, 16
  %parr = and i64 %pshw, 32768
  %pisarr = icmp ne i64 %parr, 0
  %pcnt0 = lshr i64 %pshw, 1
  %pcnt = and i64 %pcnt0, 16383
  %pwm = select i1 %pisarr, i64 %pcnt, i64 %pmap
  %pflg = select i1 %pisarr, i64 1, i64 0
  store i64 %pwm, ptr %wm
  store i64 %pflg, ptr %warr
  br label %walk
done:
  ret void
}

define internal i64 @__axiom_arena_mark_fn() #0 {
entry:
  %cell = call i64 @axiom_alloc(i64 24)
  %bump = load i64, ptr @__axiom_bump
  %end = load i64, ptr @__axiom_bump_end
  %chunk = load i64, ptr @__axiom_chunk
  %p0 = inttoptr i64 %cell to ptr
  store i64 %bump, ptr %p0
  %a1 = add i64 %cell, 8
  %p1 = inttoptr i64 %a1 to ptr
  store i64 %end, ptr %p1
  %a2 = add i64 %cell, 16
  %p2 = inttoptr i64 %a2 to ptr
  store i64 %chunk, ptr %p2
  ret i64 %cell
}

define internal i64 @__axiom_arena_reset_fn(i64 %cell) #0 {
entry:
  br label %slabclear
slabclear:
  %si = phi i64 [ 0, %entry ], [ %si1, %slabclear ]
  %sp = getelementptr [4097 x i64], ptr @__axiom_slabs, i64 0, i64 %si
  store i64 0, ptr %sp
  %si1 = add i64 %si, 1
  %sdone = icmp eq i64 %si1, 4097
  br i1 %sdone, label %resetbody, label %slabclear
resetbody:
  %p0 = inttoptr i64 %cell to ptr
  %sbump = load i64, ptr %p0
  %a1 = add i64 %cell, 8
  %p1 = inttoptr i64 %a1 to ptr
  %send = load i64, ptr %p1
  %a2 = add i64 %cell, 16
  %p2 = inttoptr i64 %a2 to ptr
  %schunk = load i64, ptr %p2
  %chead = load i64, ptr @__axiom_chunk
  %same = icmp eq i64 %chead, %schunk
  br i1 %same, label %restore, label %unwind
unwind:
  %c = phi i64 [ %chead, %resetbody ], [ %cnext, %unwind_body ]
  %reached = icmp eq i64 %c, %schunk
  %ranout = icmp eq i64 %c, 0
  %stop = or i1 %reached, %ranout
  br i1 %stop, label %tail, label %unwind_body
unwind_body:
  %clink = add i64 %c, 8
  %clinkp = inttoptr i64 %clink to ptr
  %cnext = load i64, ptr %clinkp
  %fhead = load i64, ptr @__axiom_free
  store i64 %fhead, ptr %clinkp
  store i64 %c, ptr @__axiom_free
  br label %unwind
tail:
  store i64 %send, ptr @__axiom_high
  br label %restore
restore:
  store i64 %sbump, ptr @__axiom_bump
  store i64 %send, ptr @__axiom_bump_end
  store i64 %schunk, ptr @__axiom_chunk
  ret i64 0
}

define internal i64 @__axiom_arena_reset_keeping_fn(i64 %cell, i64 %src, i64 %bytes) #0 {
entry:
  %r = call i64 @__axiom_arena_reset_fn(i64 %cell)
  %sz0 = add i64 %bytes, 15
  %szr = and i64 %sz0, -16
  %sz = add i64 %szr, 16
  %bump = load i64, ptr @__axiom_bump
  %end = load i64, ptr @__axiom_bump_end
  %stop = add i64 %bump, %sz
  %fits = icmp ule i64 %stop, %end
  br i1 %fits, label %inplace, label %fresh
inplace:
  store i64 %stop, ptr @__axiom_bump
  br label %copy
fresh:
  %need = add i64 %sz, 16
  %rounded0 = add i64 %need, 65535
  %want = and i64 %rounded0, -65536
  %addr = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 222, i64 0, i64 %want, i64 3, i64 34, i64 -1, i64 0)
  %failed_low = icmp ult i64 %addr, 4096
  %failed_neg = icmp ugt i64 %addr, -4096
  %failed = or i1 %failed_low, %failed_neg
  br i1 %failed, label %oom, label %adopt
adopt:
  %basep = inttoptr i64 %addr to ptr
  store i64 %want, ptr %basep
  %baselink = add i64 %addr, 8
  %baselinkp = inttoptr i64 %baselink to ptr
  %chead = load i64, ptr @__axiom_chunk
  store i64 %chead, ptr %baselinkp
  store i64 %addr, ptr @__axiom_chunk
  %fdata = add i64 %addr, 16
  %fbump = add i64 %fdata, %sz
  store i64 %fbump, ptr @__axiom_bump
  %fend = add i64 %addr, %want
  store i64 %fend, ptr @__axiom_bump_end
  store i64 %fbump, ptr @__axiom_high
  br label %copy
copy:
  %dstbase = phi i64 [ %bump, %inplace ], [ %fdata, %adopt ]
  %dcp = inttoptr i64 %dstbase to ptr
  store i64 0, ptr %dcp
  %dsh = add i64 %dstbase, 8
  %dshp = inttoptr i64 %dsh to ptr
  %kcnt = lshr i64 %szr, 3
  %kbig = icmp ugt i64 %kcnt, 16383
  %kleaf = select i1 %kbig, i64 0, i64 %kcnt
  %kshp = shl i64 %kleaf, 1
  store i64 %kshp, ptr %dshp
  %dst = add i64 %dstbase, 16
  br label %loop
loop:
  %i = phi i64 [ 0, %copy ], [ %i2, %loop_body ]
  %more = icmp ult i64 %i, %bytes
  br i1 %more, label %loop_body, label %done
loop_body:
  %sa = add i64 %src, %i
  %sp = inttoptr i64 %sa to ptr
  %b = load i8, ptr %sp
  %da = add i64 %dst, %i
  %dp = inttoptr i64 %da to ptr
  store i8 %b, ptr %dp
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret i64 %dst
oom:
  call i64 @__axiom_out_of_memory()
  unreachable
}

@__axiom_divzero_msg = private unnamed_addr constant [24 x i8] c"axiom: division by zero\0A"
define internal i64 @__axiom_div_by_zero() #0 {
entry:
  call i64 @__axiom_recover_abort(i64 72)
  %dzp = ptrtoint ptr @__axiom_divzero_msg to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %dzp, i64 24, i64 0, i64 0, i64 0)
  call void @__axiom_backtrace()
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 72, i64 0, i64 0, i64 0, i64 0, i64 0)
  unreachable
}
@__axiom_oom_msg = private unnamed_addr constant [35 x i8] c"axiom: out of memory (mmap failed)\0A"
define internal i64 @__axiom_out_of_memory() #0 {
entry:
  call i64 @__axiom_recover_abort(i64 70)
  %oomp = ptrtoint ptr @__axiom_oom_msg to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %oomp, i64 35, i64 0, i64 0, i64 0)
  call void @__axiom_backtrace()
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 70, i64 0, i64 0, i64 0, i64 0, i64 0)
  unreachable
}

@__axiom_recover_top = internal global i64 0
define internal i64 @__axiom_recover_abort(i64 %code) #0 {
entry:
  %top = load i64, ptr @__axiom_recover_top
  %armed = icmp ne i64 %top, 0
  br i1 %armed, label %jump, label %none
none:
  ret i64 0
jump:
  %recp = inttoptr i64 %top to ptr
  %sp = load i64, ptr %recp
  %a1 = add i64 %top, 8
  %p1 = inttoptr i64 %a1 to ptr
  %fp = load i64, ptr %p1
  %a2 = add i64 %top, 16
  %p2 = inttoptr i64 %a2 to ptr
  %pc = load i64, ptr %p2
  %a3 = add i64 %top, 24
  %p3 = inttoptr i64 %a3 to ptr
  %mark = load i64, ptr %p3
  %a5 = add i64 %top, 40
  %p5 = inttoptr i64 %a5 to ptr
  store i64 %code, ptr %p5
  call i64 @__axiom_recover_load(i64 %top)
  call i64 @__axiom_arena_reset_fn(i64 %mark)
  call void asm sideeffect "mov x9, $0\0Amov sp, $1\0Amov x29, $2\0Abr $3", "r,r,r,r,~{x9},~{memory}"(i64 %top, i64 %sp, i64 %fp, i64 %pc)
  unreachable
}
define internal i64 @__axiom_str_eq(i64 %a, i64 %b) #0 {
entry:
  %same = icmp eq i64 %a, %b
  br i1 %same, label %yes, label %chk
chk:
  %anull = icmp eq i64 %a, 0
  %bnull = icmp eq i64 %b, 0
  %null = or i1 %anull, %bnull
  br i1 %null, label %no, label %lens
lens:
  %ap = inttoptr i64 %a to ptr
  %la = load i64, ptr %ap
  %bp = inttoptr i64 %b to ptr
  %lb = load i64, ptr %bp
  %lne = icmp ne i64 %la, %lb
  br i1 %lne, label %no, label %data
data:
  %aa = add i64 %a, 8
  %aap = inttoptr i64 %aa to ptr
  %da = load i64, ptr %aap
  %ba = add i64 %b, 8
  %bap = inttoptr i64 %ba to ptr
  %db = load i64, ptr %bap
  br label %loop
loop:
  %i = phi i64 [ 0, %data ], [ %i2, %body ]
  %more = icmp ult i64 %i, %la
  br i1 %more, label %body, label %yes
body:
  %sa = add i64 %da, %i
  %sap = inttoptr i64 %sa to ptr
  %ca = load i8, ptr %sap
  %sb = add i64 %db, %i
  %sbp = inttoptr i64 %sb to ptr
  %cb = load i8, ptr %sbp
  %cne = icmp ne i8 %ca, %cb
  %i2 = add i64 %i, 1
  br i1 %cne, label %no, label %loop
yes:
  ret i64 1
no:
  ret i64 0
}


define i64 @Sys.Platform$sysRead() #0 {

  ret i64 63
}
define i64 @Sys.Platform$sysWrite() #0 {

  ret i64 64
}
define i64 @Sys.Platform$sysOpen() #0 {

  ret i64 56
}
define i64 @Sys.Platform$sysClose() #0 {

  ret i64 57
}
define i64 @Sys.Platform$sysExit() #0 {

  ret i64 94
}
define i64 @Sys.Platform$sysLseek() #0 {

  ret i64 62
}
define i64 @Sys.Platform$openNeedsDirFd() #0 {

  ret i64 1
}
define i64 @Sys.Platform$atFdCwd() #0 {

  %t0 = sub i64 0, 100
  ret i64 %t0
}
define i64 @Sys.Platform$oRdonly() #0 {

  ret i64 0
}
define i64 @Sys.Platform$oWronlyCreateTrunc() #0 {

  ret i64 577
}
define i64 @Sys.Platform$oWronlyCreateAppend() #0 {

  ret i64 1089
}
define i64 @Sys.Platform$seekEnd() #0 {

  ret i64 2
}
define i64 @Sys.Platform$seekSet() #0 {

  ret i64 0
}
define i64 @Sys.Platform$spawnUsesPosixSpawn() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sysFork() #0 {

  ret i64 220
}
define i64 @Sys.Platform$sysForkArg() #0 {

  ret i64 17
}
define i64 @Sys.Platform$sysExecve() #0 {

  ret i64 221
}
define i64 @Sys.Platform$sysWait4() #0 {

  ret i64 260
}
define i64 @Sys.Platform$sysPosixSpawn() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sysUnlinkNum() #0 {

  ret i64 35
}
define i64 @Sys.Platform$sysMkdirNum() #0 {

  ret i64 34
}
define i64 @Sys.Platform$sysRmdirNum() #0 {

  ret i64 35
}
define i64 @Sys.Platform$sysRenameNum() #0 {

  ret i64 38
}
define i64 @Sys.Platform$sysGetdentsNum() #0 {

  ret i64 61
}
define i64 @Sys.Platform$dirReadNeedsPosition() #0 {

  ret i64 0
}
define i64 @Sys.Platform$direntNameOffset() #0 {

  ret i64 19
}
define i64 @Sys.Platform$cwdUsesFcntlPath() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sysCwdNum() #0 {

  ret i64 17
}
define i64 @Sys.Platform$fGetPath() #0 {

  ret i64 0
}
define i64 @Sys.Platform$eExist() #0 {

  ret i64 17
}
define i64 @Sys.Platform$eIsDir() #0 {

  ret i64 21
}
define i64 @Sys.Platform$sysGetPidNum() #0 {

  ret i64 172
}
define i64 @Sys.Platform$sysClockNum() #0 {

  ret i64 113
}
define i64 @Sys.Platform$clockIsGettimeofday() #0 {

  ret i64 0
}
define i64 @Sys.Platform$clockHasMonotonic() #0 {

  ret i64 1
}
define i64 @Sys.Platform$sysSocketNum() #0 {

  ret i64 198
}
define i64 @Sys.Platform$sysBindNum() #0 {

  ret i64 200
}
define i64 @Sys.Platform$sysListenNum() #0 {

  ret i64 201
}
define i64 @Sys.Platform$sysAcceptNum() #0 {

  ret i64 242
}
define i64 @Sys.Platform$sysConnectNum() #0 {

  ret i64 203
}
define i64 @Sys.Platform$sysSetSockOptNum() #0 {

  ret i64 208
}
define i64 @Sys.Platform$sysGetSockOptNum() #0 {

  ret i64 209
}
define i64 @Sys.Platform$sysShutdownNum() #0 {

  ret i64 210
}
define i64 @Sys.Platform$sysFcntlNum() #0 {

  ret i64 25
}
define i64 @Sys.Platform$afInet() #0 {

  ret i64 2
}
define i64 @Sys.Platform$afInet6() #0 {

  ret i64 10
}
define i64 @Sys.Platform$sockStream() #0 {

  ret i64 1
}
define i64 @Sys.Platform$solSocket() #0 {

  ret i64 1
}
define i64 @Sys.Platform$soReuseAddr() #0 {

  ret i64 2
}
define i64 @Sys.Platform$soReusePort() #0 {

  ret i64 15
}
define i64 @Sys.Platform$soError() #0 {

  ret i64 4
}
define i64 @Sys.Platform$fGetFl() #0 {

  ret i64 3
}
define i64 @Sys.Platform$fSetFl() #0 {

  ret i64 4
}
define i64 @Sys.Platform$oNonblock() #0 {

  ret i64 2048
}
define i64 @Sys.Platform$eAgain() #0 {

  ret i64 11
}
define i64 @Sys.Platform$sockaddrHasLenByte() #0 {

  ret i64 0
}
define i64 @Sys.Platform$pollUsesKqueue() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sysPollCreateNum() #0 {

  ret i64 20
}
define i64 @Sys.Platform$sysPollWaitNum() #0 {

  ret i64 22
}
define i64 @Sys.Platform$sysPollCtlNum() #0 {

  ret i64 21
}
define i64 @Sys.Platform$pollEventSize() #0 {

  ret i64 16
}
define i64 @Sys.Platform$pollEventFdOffset() #0 {

  ret i64 8
}
define i64 @Sys.Platform$pollReadFilter() #0 {

  ret i64 1
}
define i64 @Sys.Platform$pollAddOp() #0 {

  ret i64 1
}
define i64 @Sys.Platform$pollDelOp() #0 {

  ret i64 2
}
define i64 @Sys.Platform$pollSigsetSize() #0 {

  ret i64 8
}
define i64 @Sys.Platform$sysRandomNum() #0 {

  ret i64 278
}
define i64 @Sys.Platform$randomIsGetentropy() #0 {

  ret i64 0
}
define i64 @Sys.Platform$randomMaxChunk() #0 {

  ret i64 256
}
define i64 @Sys.Platform$signalUsesSignalFd() #0 {

  ret i64 1
}
define i64 @Sys.Platform$sysSigProcMaskNum() #0 {

  ret i64 135
}
define i64 @Sys.Platform$sigBlockHow() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sigsetBytes() #0 {

  ret i64 8
}
define i64 @Sys.Platform$sysSignalFdNum() #0 {

  ret i64 74
}
define i64 @Sys.Platform$sigInfoSize() #0 {

  ret i64 128
}
define i64 @Sys.Platform$pollSignalFilter() #0 {

  ret i64 0
}
define i64 @Sys.Platform$sysKillNum() #0 {

  ret i64 129
}
define i64 @Sys.Platform$sigTerm() #0 {

  ret i64 15
}
define i64 @Sys.Platform$sigInt() #0 {

  ret i64 2
}
define i64 @Sys.Platform$forkChildIsZero() #0 {

  ret i64 1
}
define i64 @Sys.Platform$acceptNonblockFlag() #0 {

  ret i64 2048
}
define i64 @Mem$memAlloc(i64 %bytes) #0 {

  %t0 = call i64 @axiom_alloc(i64 %bytes)
  ret i64 %t0
}
define i64 @Mem$memAllocMapped(i64 %bytes, i64 %map) #0 {

  %t0 = call i64 @axiom_alloc(i64 %bytes)
  %c1 = icmp eq i64 %bytes, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = sub i64 %t0, 8
  %t8 = inttoptr i64 %t7 to ptr
  %t9 = getelementptr i64, ptr %t8, i64 0
  %t10 = load i64, ptr %t9
  %t11 = ashr i64 %t10, 1
  %t12 = and i64 %t11, 16383
  %c13 = icmp sgt i64 %t12, 47
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  br i1 %t15, label %label_16, label %label_17
label_16:
  br label %label_18
label_17:
  br label %label_18
label_18:
  %t19 = phi i64 [ 47, %label_16 ], [ %t12, %label_17 ]
  %t20 = sub i64 %t0, 8
  %t21 = shl i64 1, %t19
  %t22 = sub i64 %t21, 1
  %t23 = and i64 %map, %t22
  %t24 = shl i64 %t23, 16
  %t25 = or i64 %t10, %t24
  %t26 = inttoptr i64 %t20 to ptr
  %t27 = getelementptr i64, ptr %t26, i64 0
  store i64 %t25, ptr %t27
  br label %label_6
label_6:
  %t28 = phi i64 [ %t0, %label_4 ], [ %t0, %label_18 ]
  ret i64 %t28
}
define i64 @Mem$memMarkArray(i64 %h) #0 {

  %t0 = sub i64 %h, 8
  %t1 = sub i64 %h, 8
  %t2 = inttoptr i64 %t1 to ptr
  %t3 = getelementptr i64, ptr %t2, i64 0
  %t4 = load i64, ptr %t3
  %t5 = or i64 %t4, 32768
  %t6 = inttoptr i64 %t0 to ptr
  %t7 = getelementptr i64, ptr %t6, i64 0
  store i64 %t5, ptr %t7
  ret i64 %h
}
define i64 @Mem$memMarkLeaf(i64 %h) #0 {

  %t0 = sub i64 %h, 8
  %t1 = sub i64 %h, 8
  %t2 = inttoptr i64 %t1 to ptr
  %t3 = getelementptr i64, ptr %t2, i64 0
  %t4 = load i64, ptr %t3
  %t5 = sub i64 0, 1
  %t6 = sub i64 %t5, 32768
  %t7 = and i64 %t4, %t6
  %t8 = inttoptr i64 %t0 to ptr
  %t9 = getelementptr i64, ptr %t8, i64 0
  store i64 %t7, ptr %t9
  ret i64 %h
}
define i64 @Mem$memCopy(i64 %dst, i64 %src, i64 %count) #0 {

  %t0 = call i64 @Mem$memCopyFrom(i64 %dst, i64 %src, i64 %count, i64 0)
  ret i64 %t0
}
define i64 @Mem$memCopyFrom(i64 %dst, i64 %src, i64 %count, i64 %start) #0 {
  %s.0 = alloca i64
  store i64 %start, ptr %s.0
  br label %label_1
label_1:
  %t4 = load i64, ptr %s.0
  %c5 = icmp slt i64 %t4, %count
  %t6 = zext i1 %c5 to i64
  %t7 = icmp ne i64 %t6, 0
  br i1 %t7, label %label_2, label %label_3
label_2:
  %t8 = load i64, ptr %s.0
  %t9 = load i64, ptr %s.0
  %t10 = inttoptr i64 %src to ptr
  %t11 = getelementptr i8, ptr %t10, i64 %t9
  %t12 = load i8, ptr %t11
  %t13 = zext i8 %t12 to i64
  %t14 = inttoptr i64 %dst to ptr
  %t15 = getelementptr i8, ptr %t14, i64 %t8
  %t16 = trunc i64 %t13 to i8
  store i8 %t16, ptr %t15
  %t17 = load i64, ptr %s.0
  %t18 = add i64 %t17, 1
  store i64 %t18, ptr %s.0
  br label %label_1
label_3:
  ret i64 %dst
}
define i64 @Mem$memSet(i64 %addr, i64 %value, i64 %count) #0 {

  %t0 = call i64 @Mem$memSetFrom(i64 %addr, i64 %value, i64 %count, i64 0)
  ret i64 %t0
}
define i64 @Mem$memSetFrom(i64 %addr, i64 %value, i64 %count, i64 %start) #0 {
  %s.0 = alloca i64
  store i64 %start, ptr %s.0
  br label %label_1
label_1:
  %t4 = load i64, ptr %s.0
  %c5 = icmp slt i64 %t4, %count
  %t6 = zext i1 %c5 to i64
  %t7 = icmp ne i64 %t6, 0
  br i1 %t7, label %label_2, label %label_3
label_2:
  %t8 = load i64, ptr %s.0
  %t9 = inttoptr i64 %addr to ptr
  %t10 = getelementptr i8, ptr %t9, i64 %t8
  %t11 = trunc i64 %value to i8
  store i8 %t11, ptr %t10
  %t12 = load i64, ptr %s.0
  %t13 = add i64 %t12, 1
  store i64 %t13, ptr %s.0
  br label %label_1
label_3:
  ret i64 %addr
}
define i64 @Mem$memCmp(i64 %a, i64 %b, i64 %count) #0 {

  %t0 = call i64 @Mem$memCmpFrom(i64 %a, i64 %b, i64 %count, i64 0)
  ret i64 %t0
}
define i64 @Mem$memCmpFrom(i64 %a, i64 %b, i64 %count, i64 %start) #0 {
  %s.0 = alloca i64
  %s.1 = alloca i64
  store i64 %start, ptr %s.0
  store i64 0, ptr %s.1
  br label %label_2
label_2:
  %t5 = load i64, ptr %s.0
  %c6 = icmp slt i64 %t5, %count
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  %c13 = icmp eq i64 %t12, 0
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  %t16 = zext i1 %t15 to i64
  br label %label_11
label_10:
  br label %label_11
label_11:
  %t17 = phi i64 [ %t16, %label_9 ], [ 0, %label_10 ]
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_3, label %label_4
label_3:
  %t19 = load i64, ptr %s.0
  %t20 = inttoptr i64 %a to ptr
  %t21 = getelementptr i8, ptr %t20, i64 %t19
  %t22 = load i8, ptr %t21
  %t23 = zext i8 %t22 to i64
  %t24 = load i64, ptr %s.0
  %t25 = inttoptr i64 %b to ptr
  %t26 = getelementptr i8, ptr %t25, i64 %t24
  %t27 = load i8, ptr %t26
  %t28 = zext i8 %t27 to i64
  %t29 = sub i64 %t23, %t28
  store i64 %t29, ptr %s.1
  %t30 = load i64, ptr %s.0
  %t31 = add i64 %t30, 1
  store i64 %t31, ptr %s.0
  br label %label_2
label_4:
  %t32 = load i64, ptr %s.1
  ret i64 %t32
}
define i64 @Mem$memGetWord(i64 %addr, i64 %index) #0 {

  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i64, ptr %t0, i64 %index
  %t2 = load i64, ptr %t1
  ret i64 %t2
}
define i64 @Mem$memGetWordStr(i64 %addr, i64 %index) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %addr, i64 %index)
  call void @axiom_retain(i64 %t0)
  ret i64 %t0
}
define i64 @Mem$memSetWord(i64 %addr, i64 %index, i64 %value, i64 %__evw.h) #0 {

  %t0 = lshr i64 %__evw.h, 0
  %t1 = and i64 %t0, 1
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  call void @axiom_retain(i64 %value)
  br label %label_4
label_4:
  %t5 = inttoptr i64 %addr to ptr
  %t6 = getelementptr i64, ptr %t5, i64 %index
  store i64 %value, ptr %t6
  ret i64 %addr
}
define i64 @Mem$memGetByte(i64 %addr, i64 %index) #0 {

  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i8, ptr %t0, i64 %index
  %t2 = load i8, ptr %t1
  %t3 = zext i8 %t2 to i64
  ret i64 %t3
}
define i64 @Mem$memPutByte(i64 %addr, i64 %index, i64 %value) #0 {

  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i8, ptr %t0, i64 %index
  %t2 = trunc i64 %value to i8
  store i8 %t2, ptr %t1
  ret i64 %addr
}
define i64 @Vec$vecDefaultCap() #0 {

  ret i64 8
}
define i64 @Vec$vecNew() #0 {

  %t0 = call i64 @Vec$vecDefaultCap()
  %t1 = call i64 @Vec$vecWithCapacity(i64 %t0)
  ret i64 %t1
}
define i64 @Vec$vecWithCapacity(i64 %cap) #0 {

  %t0 = call i64 @Vec$vecBuild(i64 %cap, i64 0)
  ret i64 %t0
}
define i64 @Vec$vecWithCapacityRef(i64 %cap) #0 {

  %t0 = call i64 @Vec$vecBuild(i64 %cap, i64 1)
  ret i64 %t0
}
define i64 @Vec$vecNewRef() #0 {

  %t0 = call i64 @Vec$vecDefaultCap()
  %t1 = call i64 @Vec$vecWithCapacityRef(i64 %t0)
  ret i64 %t1
}
define i64 @Vec$vecBuild(i64 %cap, i64 %refs) #0 {

  %c0 = icmp slt i64 %cap, 1
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t6 = phi i64 [ 1, %label_3 ], [ %cap, %label_4 ]
  %t7 = call i64 @Mem$memAllocMapped(i64 32, i64 4)
  %t8 = mul i64 %t6, 8
  %t9 = call i64 @Mem$memAlloc(i64 %t8)
  call void @axiom_retain(i64 %t7)
  call void @axiom_retain(i64 %t9)
  %c10 = icmp eq i64 %refs, 1
  %t11 = zext i1 %c10 to i64
  %t12 = icmp ne i64 %t11, 0
  br i1 %t12, label %label_13, label %label_14
label_13:
  %t16 = call i64 @Mem$memMarkArray(i64 %t9)
  br label %label_15
label_14:
  br label %label_15
label_15:
  %t17 = phi i64 [ %t16, %label_13 ], [ %t9, %label_14 ]
  %t18 = call i64 @Mem$memSetWord(i64 %t7, i64 0, i64 0, i64 0)
  %t19 = call i64 @Mem$memSetWord(i64 %t7, i64 1, i64 %t6, i64 0)
  %t20 = call i64 @Mem$memSetWord(i64 %t7, i64 2, i64 %t9, i64 0)
  %t21 = call i64 @Mem$memSetWord(i64 %t7, i64 3, i64 %refs, i64 0)
  ret i64 %t7
}
define i64 @Vec$vecFree(i64 %v) #0 {

  call void @axiom_release(i64 %v)
  ret i64 0
}
define i64 @Vec$vecOwnsRefs(i64 %v) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %v, i64 3)
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}
define i64 @Vec$vecLen(i64 %v) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %v, i64 0)
  ret i64 %t0
}
define i64 @Vec$vecCap(i64 %v) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %v, i64 1)
  ret i64 %t0
}
define i64 @Vec$vecData(i64 %v) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %v, i64 2)
  ret i64 %t0
}
define i64 @Vec$vecGet(i64 %v, i64 %i) #0 {

  %c0 = icmp slt i64 %i, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Vec$vecLen(i64 %v)
  %c7 = icmp sge i64 %i, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = call i64 @Vec$vecData(i64 %v)
  %t14 = call i64 @Mem$memGetWord(i64 %t13, i64 %i)
  br label %label_12
label_12:
  %t15 = phi i64 [ 0, %label_10 ], [ %t14, %label_11 ]
  br label %label_5
label_5:
  %t16 = phi i64 [ 0, %label_3 ], [ %t15, %label_12 ]
  ret i64 %t16
}
define i64 @Vec$vecTry(i64 %v, i64 %i) #0 {

  %c0 = icmp slt i64 %i, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Vec$vecLen(i64 %v)
  %c7 = icmp sge i64 %i, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = call i64 @axiom_alloc(i64 16)
  %t14 = add i64 %t13, -8
  %t15 = inttoptr i64 %t14 to ptr
  store i64 4, ptr %t15
  %t16 = inttoptr i64 %t13 to ptr
  %t17 = getelementptr i64, ptr %t16, i64 0
  store i64 0, ptr %t17
  %t18 = add i64 %t13, -16
  %t19 = inttoptr i64 %t18 to ptr
  store i64 1, ptr %t19
  %t20 = call i64 @Vec$vecData(i64 %v)
  %t21 = call i64 @Mem$memGetWord(i64 %t20, i64 %i)
  %t22 = inttoptr i64 %t13 to ptr
  %t23 = getelementptr i64, ptr %t22, i64 1
  store i64 %t21, ptr %t23
  br label %label_12
label_12:
  %t24 = phi i64 [ 1, %label_10 ], [ %t13, %label_11 ]
  br label %label_5
label_5:
  %t25 = phi i64 [ 1, %label_3 ], [ %t24, %label_12 ]
  ret i64 %t25
}
define i64 @Vec$vecGetStr(i64 %v, i64 %i) #0 {

  %t0 = call i64 @Vec$vecGet(i64 %v, i64 %i)
  call void @axiom_retain(i64 %t0)
  ret i64 %t0
}
define i64 @Vec$vecSet(i64 %v, i64 %i, i64 %x, i64 %__evw.h) #0 {

  %c0 = icmp slt i64 %i, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Vec$vecLen(i64 %v)
  %c7 = icmp sge i64 %i, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = call i64 @Vec$vecOwnsRefs(i64 %v)
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  %t18 = call i64 @Vec$vecDropAt(i64 %v, i64 %i)
  br label %label_17
label_16:
  br label %label_17
label_17:
  %t19 = phi i64 [ %t18, %label_15 ], [ %v, %label_16 ]
  %t20 = call i64 @Vec$vecData(i64 %v)
  %t21 = lshr i64 %__evw.h, 0
  %t22 = and i64 %t21, 1
  %t23 = shl i64 %t22, 0
  %t24 = or i64 0, %t23
  %t25 = call i64 @Mem$memSetWord(i64 %t20, i64 %i, i64 %x, i64 %t24)
  br label %label_12
label_12:
  %t26 = phi i64 [ %v, %label_10 ], [ %v, %label_17 ]
  br label %label_5
label_5:
  %t27 = phi i64 [ %v, %label_3 ], [ %t26, %label_12 ]
  ret i64 %t27
}
define i64 @Vec$vecReserve(i64 %v, i64 %need) #0 {

  %t0 = call i64 @Vec$vecCap(i64 %v)
  %c1 = icmp sle i64 %need, %t0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = call i64 @Vec$vecCap(i64 %v)
  %t8 = call i64 @Vec$vecGrownCap(i64 %t7, i64 %need)
  %t9 = call i64 @Vec$vecReserveExactly(i64 %v, i64 %t8)
  br label %label_6
label_6:
  %t10 = phi i64 [ %v, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t10
}
define i64 @Vec$vecGrownCap(i64 %cap, i64 %need) #0 {

  %s.1 = alloca i64
  store i64 %cap, ptr %s.1
  %s.2 = alloca i64
  store i64 %need, ptr %s.2
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.1
  %t4 = load i64, ptr %s.2
  %c5 = icmp sge i64 %t3, %t4
  %t6 = zext i1 %c5 to i64
  %t7 = icmp ne i64 %t6, 0
  br i1 %t7, label %label_8, label %label_9
label_8:
  %t11 = load i64, ptr %s.1
  br label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  %t13 = mul i64 %t12, 2
  %t14 = load i64, ptr %s.2
  store i64 %t13, ptr %s.1
  store i64 %t14, ptr %s.2
  br label %label_0
label_10:
  ret i64 %t11
}
define i64 @Vec$vecReserveExactly(i64 %v, i64 %newCap) #0 {

  %t0 = call i64 @Vec$vecData(i64 %v)
  %t1 = mul i64 %newCap, 8
  %t2 = call i64 @Mem$memAlloc(i64 %t1)
  call void @axiom_retain(i64 %t2)
  %t3 = call i64 @Vec$vecOwnsRefs(i64 %v)
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = call i64 @Mem$memMarkArray(i64 %t2)
  br label %label_7
label_6:
  br label %label_7
label_7:
  %t9 = phi i64 [ %t8, %label_5 ], [ %t2, %label_6 ]
  %t10 = call i64 @Vec$vecLen(i64 %v)
  %t11 = mul i64 %t10, 8
  %t12 = call i64 @Mem$memCopy(i64 %t2, i64 %t0, i64 %t11)
  %t13 = call i64 @Mem$memSetWord(i64 %v, i64 2, i64 %t2, i64 0)
  %t14 = call i64 @Mem$memSetWord(i64 %v, i64 1, i64 %newCap, i64 0)
  %t15 = call i64 @Mem$memMarkLeaf(i64 %t0)
  call void @axiom_release(i64 %t0)
  ret i64 %v
}
define i64 @Vec$vecPush(i64 %v, i64 %x, i64 %__evw.h) #0 {

  %t0 = call i64 @Vec$vecLen(i64 %v)
  %t1 = add i64 %t0, 1
  %t2 = call i64 @Vec$vecReserve(i64 %v, i64 %t1)
  %t3 = call i64 @Vec$vecData(i64 %v)
  %t4 = lshr i64 %__evw.h, 0
  %t5 = and i64 %t4, 1
  %t6 = shl i64 %t5, 0
  %t7 = or i64 0, %t6
  %t8 = call i64 @Mem$memSetWord(i64 %t3, i64 %t0, i64 %x, i64 %t7)
  %t9 = add i64 %t0, 1
  %t10 = call i64 @Mem$memSetWord(i64 %v, i64 0, i64 %t9, i64 0)
  ret i64 %v
}
define i64 @Vec$vecPop(i64 %v) #0 {

  %t0 = call i64 @Vec$vecLen(i64 %v)
  %c1 = icmp eq i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = call i64 @Vec$vecData(i64 %v)
  %t8 = sub i64 %t0, 1
  %t9 = call i64 @Mem$memGetWord(i64 %t7, i64 %t8)
  %t10 = call i64 @Vec$vecData(i64 %v)
  %t11 = sub i64 %t0, 1
  %t12 = call i64 @Mem$memSetWord(i64 %t10, i64 %t11, i64 0, i64 0)
  %t13 = sub i64 %t0, 1
  %t14 = call i64 @Mem$memSetWord(i64 %v, i64 0, i64 %t13, i64 0)
  br label %label_6
label_6:
  %t15 = phi i64 [ 0, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t15
}
define i64 @Vec$vecLast(i64 %v) #0 {

  %t0 = call i64 @Vec$vecLen(i64 %v)
  %t1 = sub i64 %t0, 1
  %t2 = call i64 @Vec$vecGet(i64 %v, i64 %t1)
  ret i64 %t2
}
define i64 @Vec$vecClear(i64 %v) #0 {

  %t0 = call i64 @Vec$vecOwnsRefs(i64 %v)
  %t1 = icmp ne i64 %t0, 0
  br i1 %t1, label %label_2, label %label_3
label_2:
  %t5 = call i64 @Vec$vecDropFrom(i64 %v, i64 0)
  br label %label_4
label_3:
  br label %label_4
label_4:
  %t6 = phi i64 [ %t5, %label_2 ], [ %v, %label_3 ]
  %t7 = call i64 @Mem$memSetWord(i64 %v, i64 0, i64 0, i64 0)
  ret i64 %t7
}
define i64 @Vec$vecDropAt(i64 %v, i64 %i) #0 {

  %t0 = call i64 @Vec$vecData(i64 %v)
  %t1 = call i64 @Mem$memGetWord(i64 %t0, i64 %i)
  %t2 = call i64 @Vec$vecData(i64 %v)
  %t3 = call i64 @Mem$memSetWord(i64 %t2, i64 %i, i64 0, i64 0)
  call void @axiom_release(i64 %t1)
  ret i64 %v
}
define i64 @Vec$vecDropFrom(i64 %v, i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %v, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.2
  %t4 = load i64, ptr %s.1
  %t5 = call i64 @Vec$vecLen(i64 %t4)
  %c6 = icmp sge i64 %t3, %t5
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  br label %label_11
label_10:
  %t13 = load i64, ptr %s.1
  %t14 = load i64, ptr %s.2
  %t15 = call i64 @Vec$vecDropAt(i64 %t13, i64 %t14)
  %t16 = load i64, ptr %s.1
  %t17 = load i64, ptr %s.2
  %t18 = add i64 %t17, 1
  store i64 %t16, ptr %s.1
  store i64 %t18, ptr %s.2
  br label %label_0
label_11:
  ret i64 %t12
}
define i64 @Vec$vecSum(i64 %v) #0 {

  %t0 = call i64 @Vec$vecSumFrom(i64 %v, i64 0, i64 0)
  ret i64 %t0
}
define i64 @Vec$vecSumFrom(i64 %v, i64 %i, i64 %acc) #0 {

  %s.1 = alloca i64
  store i64 %v, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %acc, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = load i64, ptr %s.1
  %t6 = call i64 @Vec$vecLen(i64 %t5)
  %c7 = icmp sge i64 %t4, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = load i64, ptr %s.3
  br label %label_12
label_11:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = add i64 %t15, 1
  %t17 = load i64, ptr %s.3
  %t18 = load i64, ptr %s.1
  %t19 = load i64, ptr %s.2
  %t20 = call i64 @Vec$vecGet(i64 %t18, i64 %t19)
  %t21 = add i64 %t17, %t20
  store i64 %t14, ptr %s.1
  store i64 %t16, ptr %s.2
  store i64 %t21, ptr %s.3
  br label %label_0
label_12:
  ret i64 %t13
}
define i64 @Vec$vecHash(i64 %v) #0 {

  %t0 = call i64 @Vec$vecHashFrom(i64 %v, i64 0, i64 1)
  ret i64 %t0
}
define i64 @Vec$vecHashFrom(i64 %v, i64 %i, i64 %h) #0 {

  %s.1 = alloca i64
  store i64 %v, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %h, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = load i64, ptr %s.1
  %t6 = call i64 @Vec$vecLen(i64 %t5)
  %c7 = icmp sge i64 %t4, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = load i64, ptr %s.3
  br label %label_12
label_11:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = add i64 %t15, 1
  %t17 = load i64, ptr %s.3
  %t18 = mul i64 %t17, 31
  %t19 = load i64, ptr %s.1
  %t20 = load i64, ptr %s.2
  %t21 = call i64 @Vec$vecGet(i64 %t19, i64 %t20)
  %t22 = add i64 %t18, %t21
  %t23 = icmp eq i64 1000000007, 0
  br i1 %t23, label %divzero_24, label %divok_25
divzero_24:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_25:
  %t26 = srem i64 %t22, 1000000007
  store i64 %t14, ptr %s.1
  store i64 %t16, ptr %s.2
  store i64 %t26, ptr %s.3
  br label %label_0
label_12:
  ret i64 %t13
}
define i64 @Str$strWrap(i64 %bytes, i64 %len) #0 {

  %t0 = call i64 @Str$strWrapOwned(i64 %bytes, i64 %len, i64 0)
  ret i64 %t0
}
define i64 @Str$strWrapOwned(i64 %bytes, i64 %len, i64 %owner) #0 {

  %t0 = call i64 @Mem$memAllocMapped(i64 24, i64 4)
  %t1 = call i64 @Mem$memSetWord(i64 %t0, i64 0, i64 %len, i64 0)
  %t2 = call i64 @Mem$memSetWord(i64 %t0, i64 1, i64 %bytes, i64 0)
  %t3 = call i64 @Mem$memSetWord(i64 %t0, i64 2, i64 %owner, i64 0)
  call void @axiom_retain(i64 %t0)
  ret i64 %t0
}
define i64 @Str$strAlloc(i64 %len) #0 {

  %t0 = add i64 %len, 1
  %t1 = call i64 @Mem$memAlloc(i64 %t0)
  call void @axiom_retain(i64 %t1)
  %t2 = call i64 @Str$strWrapOwned(i64 %t1, i64 %len, i64 %t1)
  ret i64 %t2
}
define i64 @Str$strFromLit(i64 %cstr) #0 {

  %t0 = call i64 @Str$cstrLen(i64 %cstr, i64 0)
  %t1 = call i64 @Str$strWrap(i64 %cstr, i64 %t0)
  ret i64 %t1
}
define i64 @Str$cstrLen(i64 %addr, i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %addr, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.1
  %t4 = load i64, ptr %s.2
  %t5 = inttoptr i64 %t3 to ptr
  %t6 = getelementptr i8, ptr %t5, i64 %t4
  %t7 = load i8, ptr %t6
  %t8 = zext i8 %t7 to i64
  %c9 = icmp eq i64 %t8, 0
  %t10 = zext i1 %c9 to i64
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  %t15 = load i64, ptr %s.2
  br label %label_14
label_13:
  %t16 = load i64, ptr %s.1
  %t17 = load i64, ptr %s.2
  %t18 = add i64 %t17, 1
  store i64 %t16, ptr %s.1
  store i64 %t18, ptr %s.2
  br label %label_0
label_14:
  ret i64 %t15
}
define i64 @Str$strLen(i64 %s) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %s, i64 0)
  ret i64 %t0
}
define i64 @Str$strData(i64 %s) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %s, i64 1)
  ret i64 %t0
}
define i64 @Str$strOwner(i64 %s) #0 {

  %t0 = call i64 @Mem$memGetWord(i64 %s, i64 2)
  ret i64 %t0
}
define i64 @Str$strByte(i64 %s, i64 %i) #0 {

  %c0 = icmp slt i64 %i, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Str$strLen(i64 %s)
  %c7 = icmp sge i64 %i, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = call i64 @Str$strData(i64 %s)
  %t14 = inttoptr i64 %t13 to ptr
  %t15 = getelementptr i8, ptr %t14, i64 %i
  %t16 = load i8, ptr %t15
  %t17 = zext i8 %t16 to i64
  br label %label_12
label_12:
  %t18 = phi i64 [ 0, %label_10 ], [ %t17, %label_11 ]
  br label %label_5
label_5:
  %t19 = phi i64 [ 0, %label_3 ], [ %t18, %label_12 ]
  ret i64 %t19
}
define i64 @Str$strCStr(i64 %s) #0 {

  %t0 = call i64 @Str$strData(i64 %s)
  ret i64 %t0
}
define i64 @Str$strIsEmpty(i64 %s) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp eq i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}
define i64 @Str$strCmp(i64 %a, i64 %b) #0 {

  %t0 = call i64 @Str$strLen(i64 %a)
  %t1 = call i64 @Str$strLen(i64 %b)
  %c2 = icmp slt i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  br label %label_7
label_7:
  %t8 = phi i64 [ %t0, %label_5 ], [ %t1, %label_6 ]
  %t9 = call i64 @Str$strData(i64 %a)
  %t10 = call i64 @Str$strData(i64 %b)
  %t11 = call i64 @Mem$memCmp(i64 %t9, i64 %t10, i64 %t8)
  %c12 = icmp ne i64 %t11, 0
  %t13 = zext i1 %c12 to i64
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  br label %label_17
label_16:
  %t18 = sub i64 %t0, %t1
  br label %label_17
label_17:
  %t19 = phi i64 [ %t11, %label_15 ], [ %t18, %label_16 ]
  ret i64 %t19
}
define i64 @Str$strEq(i64 %a, i64 %b) #0 {

  %t0 = call i64 @Str$strLen(i64 %a)
  %t1 = call i64 @Str$strLen(i64 %b)
  %c2 = icmp ne i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  %t8 = call i64 @Str$strData(i64 %a)
  %t9 = call i64 @Str$strData(i64 %b)
  %t10 = call i64 @Mem$memCmp(i64 %t8, i64 %t9, i64 %t0)
  %c11 = icmp eq i64 %t10, 0
  %t12 = zext i1 %c11 to i64
  br label %label_7
label_7:
  %t13 = phi i64 [ 0, %label_5 ], [ %t12, %label_6 ]
  ret i64 %t13
}
define i64 @Str$strSlice(i64 %s, i64 %start, i64 %count) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp slt i64 %start, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %c7 = icmp sgt i64 %start, %t0
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  br label %label_12
label_12:
  %t13 = phi i64 [ %t0, %label_10 ], [ %start, %label_11 ]
  br label %label_6
label_6:
  %t14 = phi i64 [ 0, %label_4 ], [ %t13, %label_12 ]
  %t15 = sub i64 %t0, %t14
  %c16 = icmp slt i64 %count, 0
  %t17 = zext i1 %c16 to i64
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_19, label %label_20
label_19:
  br label %label_21
label_20:
  %c22 = icmp sgt i64 %count, %t15
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  br label %label_27
label_26:
  br label %label_27
label_27:
  %t28 = phi i64 [ %t15, %label_25 ], [ %count, %label_26 ]
  br label %label_21
label_21:
  %t29 = phi i64 [ 0, %label_19 ], [ %t28, %label_27 ]
  %t30 = call i64 @Str$strOwner(i64 %s)
  call void @axiom_retain(i64 %t30)
  %t31 = call i64 @Str$strData(i64 %s)
  %t32 = add i64 %t31, %t14
  %t33 = call i64 @Str$strWrapOwned(i64 %t32, i64 %t29, i64 %t30)
  ret i64 %t33
}
define i64 @Str$strDup(i64 %s) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %t1 = call i64 @Str$strAlloc(i64 %t0)
  %t2 = call i64 @Str$strData(i64 %t1)
  %t3 = call i64 @Str$strData(i64 %s)
  %t4 = call i64 @Mem$memCopy(i64 %t2, i64 %t3, i64 %t0)
  ret i64 %t1
}
define i64 @Str$strConcat(i64 %a, i64 %b) #0 {

  %t0 = call i64 @Str$strLen(i64 %a)
  %t1 = call i64 @Str$strLen(i64 %b)
  %t2 = add i64 %t0, %t1
  %t3 = call i64 @Str$strAlloc(i64 %t2)
  %t4 = call i64 @Str$strData(i64 %t3)
  %t5 = call i64 @Str$strData(i64 %a)
  %t6 = call i64 @Mem$memCopy(i64 %t4, i64 %t5, i64 %t0)
  %t7 = call i64 @Str$strData(i64 %t3)
  %t8 = add i64 %t7, %t0
  %t9 = call i64 @Str$strData(i64 %b)
  %t10 = call i64 @Mem$memCopy(i64 %t8, i64 %t9, i64 %t1)
  ret i64 %t3
}
define i64 @Str$strFindByte(i64 %s, i64 %byte, i64 %from) #0 {

  %s.1 = alloca i64
  store i64 %s, ptr %s.1
  %s.2 = alloca i64
  store i64 %byte, ptr %s.2
  %s.3 = alloca i64
  store i64 %from, ptr %s.3
  call void @axiom_retain(i64 %s)
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.3
  %t5 = load i64, ptr %s.1
  %t6 = call i64 @Str$strLen(i64 %t5)
  %c7 = icmp sge i64 %t4, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = sub i64 0, 1
  br label %label_12
label_11:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.3
  %t16 = call i64 @Str$strByte(i64 %t14, i64 %t15)
  %t17 = load i64, ptr %s.2
  %c18 = icmp eq i64 %t16, %t17
  %t19 = zext i1 %c18 to i64
  %t20 = icmp ne i64 %t19, 0
  br i1 %t20, label %label_21, label %label_22
label_21:
  %t24 = load i64, ptr %s.3
  br label %label_23
label_22:
  %t25 = load i64, ptr %s.1
  %t26 = load i64, ptr %s.2
  %t27 = load i64, ptr %s.3
  %t28 = add i64 %t27, 1
  %t29 = load i64, ptr %s.1
  store i64 %t25, ptr %s.1
  store i64 %t26, ptr %s.2
  store i64 %t28, ptr %s.3
  br label %label_0
label_23:
  br label %label_12
label_12:
  %t30 = phi i64 [ %t13, %label_10 ], [ %t24, %label_23 ]
  %t31 = load i64, ptr %s.1
  call void @axiom_release(i64 %t31)
  ret i64 %t30
}
define i64 @Str$strStartsWith(i64 %s, i64 %prefix) #0 {

  %t0 = call i64 @Str$strLen(i64 %prefix)
  %t1 = call i64 @Str$strLen(i64 %s)
  %c2 = icmp sgt i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  %t8 = call i64 @Str$strData(i64 %s)
  %t9 = call i64 @Str$strData(i64 %prefix)
  %t10 = call i64 @Mem$memCmp(i64 %t8, i64 %t9, i64 %t0)
  %c11 = icmp eq i64 %t10, 0
  %t12 = zext i1 %c11 to i64
  br label %label_7
label_7:
  %t13 = phi i64 [ 0, %label_5 ], [ %t12, %label_6 ]
  ret i64 %t13
}
define i64 @Str$strIsDigit(i64 %ch) #0 {

  %c0 = icmp sge i64 %ch, 48
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %c6 = icmp sle i64 %ch, 57
  %t7 = zext i1 %c6 to i64
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t8 = phi i64 [ %t7, %label_3 ], [ 0, %label_4 ]
  ret i64 %t8
}
define i64 @Str$strIsAlpha(i64 %ch) #0 {

  %c0 = icmp sge i64 %ch, 65
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %c6 = icmp sle i64 %ch, 90
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  br label %label_11
label_10:
  %c12 = icmp sge i64 %ch, 97
  %t13 = zext i1 %c12 to i64
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  %c18 = icmp sle i64 %ch, 122
  %t19 = zext i1 %c18 to i64
  br label %label_17
label_16:
  br label %label_17
label_17:
  %t20 = phi i64 [ %t19, %label_15 ], [ 0, %label_16 ]
  br label %label_11
label_11:
  %t21 = phi i64 [ 1, %label_9 ], [ %t20, %label_17 ]
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t22 = phi i64 [ %t21, %label_11 ], [ 0, %label_4 ]
  ret i64 %t22
}
define i64 @Str$strIsSpace(i64 %ch) #0 {

  %c0 = icmp eq i64 %ch, 32
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %c6 = icmp eq i64 %ch, 10
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  br label %label_11
label_10:
  %c12 = icmp eq i64 %ch, 13
  %t13 = zext i1 %c12 to i64
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  br label %label_17
label_16:
  %c18 = icmp eq i64 %ch, 9
  %t19 = zext i1 %c18 to i64
  %t20 = icmp ne i64 %t19, 0
  br i1 %t20, label %label_21, label %label_22
label_21:
  br label %label_23
label_22:
  br label %label_23
label_23:
  %t24 = phi i64 [ 1, %label_21 ], [ 0, %label_22 ]
  br label %label_17
label_17:
  %t25 = phi i64 [ 1, %label_15 ], [ %t24, %label_23 ]
  br label %label_11
label_11:
  %t26 = phi i64 [ 1, %label_9 ], [ %t25, %label_17 ]
  br label %label_5
label_5:
  %t27 = phi i64 [ 1, %label_3 ], [ %t26, %label_11 ]
  ret i64 %t27
}
define i64 @Str$strHexVal(i64 %ch) #0 {

  %c0 = icmp sge i64 %ch, 48
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %c6 = icmp sle i64 %ch, 57
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  %t9 = zext i1 %t8 to i64
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t10 = phi i64 [ %t9, %label_3 ], [ 0, %label_4 ]
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  %t15 = sub i64 %ch, 48
  br label %label_14
label_13:
  %c16 = icmp sge i64 %ch, 97
  %t17 = zext i1 %c16 to i64
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_19, label %label_20
label_19:
  %c22 = icmp sle i64 %ch, 102
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  %t25 = zext i1 %t24 to i64
  br label %label_21
label_20:
  br label %label_21
label_21:
  %t26 = phi i64 [ %t25, %label_19 ], [ 0, %label_20 ]
  %t27 = icmp ne i64 %t26, 0
  br i1 %t27, label %label_28, label %label_29
label_28:
  %t31 = sub i64 %ch, 97
  %t32 = add i64 10, %t31
  br label %label_30
label_29:
  %c33 = icmp sge i64 %ch, 65
  %t34 = zext i1 %c33 to i64
  %t35 = icmp ne i64 %t34, 0
  br i1 %t35, label %label_36, label %label_37
label_36:
  %c39 = icmp sle i64 %ch, 70
  %t40 = zext i1 %c39 to i64
  %t41 = icmp ne i64 %t40, 0
  %t42 = zext i1 %t41 to i64
  br label %label_38
label_37:
  br label %label_38
label_38:
  %t43 = phi i64 [ %t42, %label_36 ], [ 0, %label_37 ]
  %t44 = icmp ne i64 %t43, 0
  br i1 %t44, label %label_45, label %label_46
label_45:
  %t48 = sub i64 %ch, 65
  %t49 = add i64 10, %t48
  br label %label_47
label_46:
  %t50 = sub i64 0, 1
  br label %label_47
label_47:
  %t51 = phi i64 [ %t49, %label_45 ], [ %t50, %label_46 ]
  br label %label_30
label_30:
  %t52 = phi i64 [ %t32, %label_28 ], [ %t51, %label_47 ]
  br label %label_14
label_14:
  %t53 = phi i64 [ %t15, %label_12 ], [ %t52, %label_30 ]
  ret i64 %t53
}
define i64 @Str$strIsHexDigit(i64 %ch) #0 {

  %t0 = call i64 @Str$strHexVal(i64 %ch)
  %c1 = icmp sge i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}
define i64 @Str$strSplit(i64 %s, i64 %byte) #0 {

  %t0 = call i64 @Vec$vecNew()
  %t1 = call i64 @Str$strSplitFrom(i64 %s, i64 %byte, i64 0, i64 %t0)
  ret i64 %t0
}
define i64 @Str$strSplitFrom(i64 %s, i64 %byte, i64 %from, i64 %out) #0 {

  %s.1 = alloca i64
  store i64 %s, ptr %s.1
  %s.2 = alloca i64
  store i64 %byte, ptr %s.2
  %s.3 = alloca i64
  store i64 %from, ptr %s.3
  %s.4 = alloca i64
  store i64 %out, ptr %s.4
  call void @axiom_retain(i64 %s)
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.1
  %t6 = load i64, ptr %s.2
  %t7 = load i64, ptr %s.3
  %t8 = call i64 @Str$strFindByte(i64 %t5, i64 %t6, i64 %t7)
  %c9 = icmp slt i64 %t8, 0
  %t10 = zext i1 %c9 to i64
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  %t15 = load i64, ptr %s.1
  %t16 = call i64 @Str$strLen(i64 %t15)
  br label %label_14
label_13:
  br label %label_14
label_14:
  %t17 = phi i64 [ %t16, %label_12 ], [ %t8, %label_13 ]
  %t18 = load i64, ptr %s.4
  %t19 = load i64, ptr %s.1
  %t20 = load i64, ptr %s.3
  %t21 = load i64, ptr %s.3
  %t22 = sub i64 %t17, %t21
  %t23 = call i64 @Str$strSlice(i64 %t19, i64 %t20, i64 %t22)
  %t24 = call i64 @Vec$vecPush(i64 %t18, i64 %t23, i64 0)
  %c25 = icmp slt i64 %t8, 0
  %t26 = zext i1 %c25 to i64
  %t27 = icmp ne i64 %t26, 0
  br i1 %t27, label %label_28, label %label_29
label_28:
  br label %label_30
label_29:
  %t31 = load i64, ptr %s.1
  %t32 = load i64, ptr %s.2
  %t33 = add i64 %t17, 1
  %t34 = load i64, ptr %s.4
  %t35 = load i64, ptr %s.1
  store i64 %t31, ptr %s.1
  store i64 %t32, ptr %s.2
  store i64 %t33, ptr %s.3
  store i64 %t34, ptr %s.4
  br label %label_0
label_30:
  ret i64 0
}
define i64 @Str$strFromByte(i64 %b) #0 {

  %t0 = call i64 @Str$strAlloc(i64 1)
  %t1 = call i64 @Str$strData(i64 %t0)
  %t2 = inttoptr i64 %t1 to ptr
  %t3 = getelementptr i8, ptr %t2, i64 0
  %t4 = trunc i64 %b to i8
  store i8 %t4, ptr %t3
  ret i64 %t0
}
define i64 @Fmt$intIsMostNegative(i64 %n) #0 {

  %c0 = icmp slt i64 %n, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %t6 = sub i64 0, %n
  %c7 = icmp eq i64 %t6, %n
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  %t10 = zext i1 %t9 to i64
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t11 = phi i64 [ %t10, %label_3 ], [ 0, %label_4 ]
  ret i64 %t11
}
define i64 @Fmt$fmtIntWidth(i64 %n) #0 {

  %t0 = call i64 @Fmt$intIsMostNegative(i64 %n)
  %t1 = icmp ne i64 %t0, 0
  br i1 %t1, label %label_2, label %label_3
label_2:
  br label %label_4
label_3:
  %c5 = icmp slt i64 %n, 0
  %t6 = zext i1 %c5 to i64
  %t7 = icmp ne i64 %t6, 0
  br i1 %t7, label %label_8, label %label_9
label_8:
  %t11 = sub i64 0, %n
  %t12 = call i64 @Fmt$fmtIntWidth(i64 %t11)
  %t13 = add i64 1, %t12
  br label %label_10
label_9:
  %c14 = icmp slt i64 %n, 10
  %t15 = zext i1 %c14 to i64
  %t16 = icmp ne i64 %t15, 0
  br i1 %t16, label %label_17, label %label_18
label_17:
  br label %label_19
label_18:
  %t20 = icmp eq i64 10, 0
  br i1 %t20, label %divzero_21, label %divok_22
divzero_21:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_22:
  %t23 = sdiv i64 %n, 10
  %t24 = call i64 @Fmt$fmtIntWidth(i64 %t23)
  %t25 = add i64 1, %t24
  br label %label_19
label_19:
  %t26 = phi i64 [ 1, %label_17 ], [ %t25, %divok_22 ]
  br label %label_10
label_10:
  %t27 = phi i64 [ %t13, %label_8 ], [ %t26, %label_19 ]
  br label %label_4
label_4:
  %t28 = phi i64 [ 20, %label_2 ], [ %t27, %label_10 ]
  ret i64 %t28
}
define i64 @Fmt$fmtInt(i64 %n) #0 {

  %t0 = call i64 @Fmt$intIsMostNegative(i64 %n)
  %t1 = icmp ne i64 %t0, 0
  br i1 %t1, label %label_2, label %label_3
label_2:
  %t5 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_0, i64 0, i32 2) to i64
  br label %label_4
label_3:
  %c6 = icmp slt i64 %n, 0
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_1, i64 0, i32 2) to i64
  %t13 = sub i64 0, %n
  %t14 = call i64 @Fmt$fmtNat(i64 %t13)
  %t15 = call i64 @Str$strConcat(i64 %t12, i64 %t14)
  call void @axiom_release(i64 %t12)
  call void @axiom_release(i64 %t14)
  br label %label_11
label_10:
  %t16 = call i64 @Fmt$fmtNat(i64 %n)
  br label %label_11
label_11:
  %t17 = phi i64 [ %t15, %label_9 ], [ %t16, %label_10 ]
  br label %label_4
label_4:
  %t18 = phi i64 [ %t5, %label_2 ], [ %t17, %label_11 ]
  ret i64 %t18
}
define i64 @Fmt$fmtNat(i64 %n) #0 {

  %t0 = call i64 @Fmt$fmtIntWidth(i64 %n)
  %t1 = call i64 @Str$strAlloc(i64 %t0)
  %t2 = call i64 @Str$strData(i64 %t1)
  %t3 = sub i64 %t0, 1
  %t4 = call i64 @Fmt$fmtDigits(i64 %t2, i64 %n, i64 %t3)
  ret i64 %t1
}
define i64 @Fmt$fmtDigits(i64 %buf, i64 %n, i64 %at) #0 {

  %s.1 = alloca i64
  store i64 %buf, ptr %s.1
  %s.2 = alloca i64
  store i64 %n, ptr %s.2
  %s.3 = alloca i64
  store i64 %at, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = icmp eq i64 10, 0
  br i1 %t5, label %divzero_6, label %divok_7
divzero_6:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_7:
  %t8 = srem i64 %t4, 10
  %t9 = add i64 48, %t8
  %t10 = load i64, ptr %s.1
  %t11 = load i64, ptr %s.3
  %t12 = inttoptr i64 %t10 to ptr
  %t13 = getelementptr i8, ptr %t12, i64 %t11
  %t14 = trunc i64 %t9 to i8
  store i8 %t14, ptr %t13
  %t15 = load i64, ptr %s.2
  %c16 = icmp slt i64 %t15, 10
  %t17 = zext i1 %c16 to i64
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_19, label %label_20
label_19:
  %t22 = load i64, ptr %s.1
  br label %label_21
label_20:
  %t23 = load i64, ptr %s.1
  %t24 = load i64, ptr %s.2
  %t25 = icmp eq i64 10, 0
  br i1 %t25, label %divzero_26, label %divok_27
divzero_26:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_27:
  %t28 = sdiv i64 %t24, 10
  %t29 = load i64, ptr %s.3
  %t30 = sub i64 %t29, 1
  store i64 %t23, ptr %s.1
  store i64 %t28, ptr %s.2
  store i64 %t30, ptr %s.3
  br label %label_0
label_21:
  ret i64 %t22
}
define i64 @Fmt$fmtHexShr4(i64 %n) #0 {

  %t0 = ashr i64 %n, 4
  %t1 = and i64 %t0, 1152921504606846975
  ret i64 %t1
}
define i64 @Fmt$fmtHex(i64 %n) #0 {

  %c0 = icmp eq i64 %n, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %t6 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_2, i64 0, i32 2) to i64
  br label %label_5
label_4:
  %t7 = call i64 @Fmt$fmtHexWidth(i64 %n, i64 0)
  %t8 = call i64 @Str$strAlloc(i64 %t7)
  %t9 = call i64 @Str$strData(i64 %t8)
  %t10 = sub i64 %t7, 1
  %t11 = call i64 @Fmt$fmtHexDigits(i64 %t9, i64 %n, i64 %t10)
  br label %label_5
label_5:
  %t12 = phi i64 [ %t6, %label_3 ], [ %t8, %label_4 ]
  ret i64 %t12
}
define i64 @Fmt$fmtHexWidth(i64 %n, i64 %acc) #0 {

  %s.1 = alloca i64
  store i64 %n, ptr %s.1
  %s.2 = alloca i64
  store i64 %acc, ptr %s.2
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.1
  %c4 = icmp eq i64 %t3, 0
  %t5 = zext i1 %c4 to i64
  %t6 = icmp ne i64 %t5, 0
  br i1 %t6, label %label_7, label %label_8
label_7:
  %t10 = load i64, ptr %s.2
  br label %label_9
label_8:
  %t11 = load i64, ptr %s.1
  %t12 = call i64 @Fmt$fmtHexShr4(i64 %t11)
  %t13 = load i64, ptr %s.2
  %t14 = add i64 %t13, 1
  store i64 %t12, ptr %s.1
  store i64 %t14, ptr %s.2
  br label %label_0
label_9:
  ret i64 %t10
}
define i64 @Fmt$fmtHexDigits(i64 %buf, i64 %n, i64 %at) #0 {

  %s.1 = alloca i64
  store i64 %buf, ptr %s.1
  %s.2 = alloca i64
  store i64 %n, ptr %s.2
  %s.3 = alloca i64
  store i64 %at, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = and i64 %t4, 15
  %c6 = icmp slt i64 %t5, 10
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = add i64 48, %t5
  br label %label_11
label_10:
  %t13 = add i64 87, %t5
  br label %label_11
label_11:
  %t14 = phi i64 [ %t12, %label_9 ], [ %t13, %label_10 ]
  %t15 = load i64, ptr %s.1
  %t16 = load i64, ptr %s.3
  %t17 = inttoptr i64 %t15 to ptr
  %t18 = getelementptr i8, ptr %t17, i64 %t16
  %t19 = trunc i64 %t14 to i8
  store i8 %t19, ptr %t18
  %t20 = load i64, ptr %s.2
  %t21 = call i64 @Fmt$fmtHexShr4(i64 %t20)
  %c22 = icmp eq i64 %t21, 0
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  %t28 = load i64, ptr %s.1
  br label %label_27
label_26:
  %t29 = load i64, ptr %s.1
  %t30 = load i64, ptr %s.3
  %t31 = sub i64 %t30, 1
  store i64 %t29, ptr %s.1
  store i64 %t21, ptr %s.2
  store i64 %t31, ptr %s.3
  br label %label_0
label_27:
  ret i64 %t28
}
define i64 @Fmt$fmtPadLeft(i64 %s, i64 %width) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp sge i64 %t0, %width
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  call void @axiom_retain(i64 %s)
  br label %label_6
label_5:
  %t7 = call i64 @Str$strAlloc(i64 %width)
  %t8 = call i64 @Str$strData(i64 %t7)
  %t9 = sub i64 %width, %t0
  %t10 = call i64 @Mem$memSet(i64 %t8, i64 32, i64 %t9)
  %t11 = call i64 @Str$strData(i64 %t7)
  %t12 = sub i64 %width, %t0
  %t13 = add i64 %t11, %t12
  %t14 = call i64 @Str$strData(i64 %s)
  %t15 = call i64 @Mem$memCopy(i64 %t13, i64 %t14, i64 %t0)
  br label %label_6
label_6:
  %t16 = phi i64 [ %s, %label_4 ], [ %t7, %label_5 ]
  ret i64 %t16
}
define i64 @Fmt$fmtPadRight(i64 %s, i64 %width) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp sge i64 %t0, %width
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  call void @axiom_retain(i64 %s)
  br label %label_6
label_5:
  %t7 = call i64 @Str$strAlloc(i64 %width)
  %t8 = call i64 @Str$strData(i64 %t7)
  %t9 = call i64 @Str$strData(i64 %s)
  %t10 = call i64 @Mem$memCopy(i64 %t8, i64 %t9, i64 %t0)
  %t11 = call i64 @Str$strData(i64 %t7)
  %t12 = add i64 %t11, %t0
  %t13 = sub i64 %width, %t0
  %t14 = call i64 @Mem$memSet(i64 %t12, i64 32, i64 %t13)
  br label %label_6
label_6:
  %t15 = phi i64 [ %s, %label_4 ], [ %t7, %label_5 ]
  ret i64 %t15
}
define i64 @Fmt$fmtPadCenter(i64 %s, i64 %width) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp sge i64 %t0, %width
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  call void @axiom_retain(i64 %s)
  br label %label_6
label_5:
  %t7 = sub i64 %width, %t0
  %t8 = icmp eq i64 2, 0
  br i1 %t8, label %divzero_9, label %divok_10
divzero_9:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_10:
  %t11 = sdiv i64 %t7, 2
  %t12 = call i64 @Str$strAlloc(i64 %width)
  %t13 = call i64 @Str$strData(i64 %t12)
  %t14 = call i64 @Mem$memSet(i64 %t13, i64 32, i64 %t11)
  %t15 = call i64 @Str$strData(i64 %t12)
  %t16 = add i64 %t15, %t11
  %t17 = call i64 @Str$strData(i64 %s)
  %t18 = call i64 @Mem$memCopy(i64 %t16, i64 %t17, i64 %t0)
  %t19 = call i64 @Str$strData(i64 %t12)
  %t20 = add i64 %t11, %t0
  %t21 = add i64 %t19, %t20
  %t22 = sub i64 %t7, %t11
  %t23 = call i64 @Mem$memSet(i64 %t21, i64 32, i64 %t22)
  br label %label_6
label_6:
  %t24 = phi i64 [ %s, %label_4 ], [ %t12, %divok_10 ]
  ret i64 %t24
}
define i64 @Fmt$fmtPadZerosLeft(i64 %s, i64 %width) #0 {

  %t0 = call i64 @Str$strLen(i64 %s)
  %c1 = icmp sge i64 %t0, %width
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  call void @axiom_retain(i64 %s)
  br label %label_6
label_5:
  %c7 = icmp eq i64 %t0, 0
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = call i64 @Str$strByte(i64 %s, i64 0)
  %c14 = icmp eq i64 %t13, 45
  %t15 = zext i1 %c14 to i64
  %t16 = icmp ne i64 %t15, 0
  br i1 %t16, label %label_17, label %label_18
label_17:
  br label %label_19
label_18:
  br label %label_19
label_19:
  %t20 = phi i64 [ 1, %label_17 ], [ 0, %label_18 ]
  br label %label_12
label_12:
  %t21 = phi i64 [ 0, %label_10 ], [ %t20, %label_19 ]
  %t22 = call i64 @Str$strAlloc(i64 %width)
  %c23 = icmp eq i64 %t21, 1
  %t24 = zext i1 %c23 to i64
  %t25 = icmp ne i64 %t24, 0
  br i1 %t25, label %label_26, label %label_27
label_26:
  %t29 = call i64 @Str$strData(i64 %t22)
  %t30 = inttoptr i64 %t29 to ptr
  %t31 = getelementptr i8, ptr %t30, i64 0
  %t32 = trunc i64 45 to i8
  store i8 %t32, ptr %t31
  br label %label_28
label_27:
  br label %label_28
label_28:
  %t33 = phi i64 [ 0, %label_26 ], [ 0, %label_27 ]
  %t34 = call i64 @Str$strData(i64 %t22)
  %t35 = add i64 %t34, %t21
  %t36 = sub i64 %width, %t0
  %t37 = call i64 @Mem$memSet(i64 %t35, i64 48, i64 %t36)
  %t38 = call i64 @Str$strData(i64 %t22)
  %t39 = sub i64 %width, %t0
  %t40 = add i64 %t21, %t39
  %t41 = add i64 %t38, %t40
  %t42 = call i64 @Str$strData(i64 %s)
  %t43 = add i64 %t42, %t21
  %t44 = sub i64 %t0, %t21
  %t45 = call i64 @Mem$memCopy(i64 %t41, i64 %t43, i64 %t44)
  br label %label_6
label_6:
  %t46 = phi i64 [ %s, %label_4 ], [ %t22, %label_28 ]
  ret i64 %t46
}
define i64 @Fmt$fmtHexUpper(i64 %n) #0 {

  %c0 = icmp eq i64 %n, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %t6 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_2, i64 0, i32 2) to i64
  br label %label_5
label_4:
  %t7 = call i64 @Fmt$fmtHexWidth(i64 %n, i64 0)
  %t8 = call i64 @Str$strAlloc(i64 %t7)
  %t9 = call i64 @Str$strData(i64 %t8)
  %t10 = sub i64 %t7, 1
  %t11 = call i64 @Fmt$fmtHexDigitsUpper(i64 %t9, i64 %n, i64 %t10)
  br label %label_5
label_5:
  %t12 = phi i64 [ %t6, %label_3 ], [ %t8, %label_4 ]
  ret i64 %t12
}
define i64 @Fmt$fmtHexDigitsUpper(i64 %buf, i64 %n, i64 %at) #0 {

  %s.1 = alloca i64
  store i64 %buf, ptr %s.1
  %s.2 = alloca i64
  store i64 %n, ptr %s.2
  %s.3 = alloca i64
  store i64 %at, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = and i64 %t4, 15
  %c6 = icmp slt i64 %t5, 10
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = add i64 48, %t5
  br label %label_11
label_10:
  %t13 = add i64 55, %t5
  br label %label_11
label_11:
  %t14 = phi i64 [ %t12, %label_9 ], [ %t13, %label_10 ]
  %t15 = load i64, ptr %s.1
  %t16 = load i64, ptr %s.3
  %t17 = inttoptr i64 %t15 to ptr
  %t18 = getelementptr i8, ptr %t17, i64 %t16
  %t19 = trunc i64 %t14 to i8
  store i8 %t19, ptr %t18
  %t20 = load i64, ptr %s.2
  %t21 = call i64 @Fmt$fmtHexShr4(i64 %t20)
  %c22 = icmp eq i64 %t21, 0
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  %t28 = load i64, ptr %s.1
  br label %label_27
label_26:
  %t29 = load i64, ptr %s.1
  %t30 = load i64, ptr %s.3
  %t31 = sub i64 %t30, 1
  store i64 %t29, ptr %s.1
  store i64 %t21, ptr %s.2
  store i64 %t31, ptr %s.3
  br label %label_0
label_27:
  ret i64 %t28
}
define i64 @Fmt$powTen(i64 %n) #0 {

  %c0 = icmp sle i64 %n, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = sub i64 %n, 1
  %t7 = call i64 @Fmt$powTen(i64 %t6)
  %t8 = mul i64 10, %t7
  br label %label_5
label_5:
  %t9 = phi i64 [ 1, %label_3 ], [ %t8, %label_4 ]
  ret i64 %t9
}
define i64 @Fmt$fmtPadZeros(i64 %n, i64 %width) #0 {

  %t0 = call i64 @Fmt$fmtNat(i64 %n)
  %t1 = call i64 @Fmt$fmtPadZerosLeft(i64 %t0, i64 %width)
  call void @axiom_release(i64 %t0)
  ret i64 %t1
}
define i64 @Fmt$fmtFloat(i64 %x) #0 {

  %t0 = call i64 @Fmt$fmtFloatPrec(i64 %x, i64 6)
  ret i64 %t0
}
define i64 @Fmt$fmtFloatPrec(i64 %x, i64 %places) #0 {

  %d0 = bitcast i64 %x to double
  %d1 = bitcast i64 0 to double
  %c2 = fcmp olt double %d0, %d1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_1, i64 0, i32 2) to i64
  %d9 = bitcast i64 0 to double
  %d10 = bitcast i64 %x to double
  %d11 = fsub double %d9, %d10
  %t12 = bitcast double %d11 to i64
  %t13 = call i64 @Fmt$fmtFloatAbs(i64 %t12, i64 %places)
  %t14 = call i64 @Str$strConcat(i64 %t8, i64 %t13)
  call void @axiom_release(i64 %t8)
  call void @axiom_release(i64 %t13)
  br label %label_7
label_6:
  %t15 = call i64 @Fmt$fmtFloatAbs(i64 %x, i64 %places)
  br label %label_7
label_7:
  %t16 = phi i64 [ %t14, %label_5 ], [ %t15, %label_6 ]
  ret i64 %t16
}
define i64 @Fmt$fmtFloatAbs(i64 %x, i64 %places) #0 {

  %d0 = bitcast i64 %x to double
  %t1 = fptosi double %d0 to i64
  %d2 = sitofp i64 %t1 to double
  %t3 = bitcast double %d2 to i64
  %d4 = bitcast i64 %x to double
  %d5 = bitcast i64 %t3 to double
  %d6 = fsub double %d4, %d5
  %t7 = bitcast double %d6 to i64
  %t8 = call i64 @Fmt$powTen(i64 %places)
  %d9 = sitofp i64 %t8 to double
  %t10 = bitcast double %d9 to i64
  %d11 = bitcast i64 %t7 to double
  %d12 = bitcast i64 %t10 to double
  %d13 = fmul double %d11, %d12
  %t14 = bitcast double %d13 to i64
  %d15 = bitcast i64 %t14 to double
  %d16 = bitcast i64 4602678819172646912 to double
  %d17 = fadd double %d15, %d16
  %t18 = bitcast double %d17 to i64
  %d19 = bitcast i64 %t18 to double
  %t20 = fptosi double %d19 to i64
  %c21 = icmp sge i64 %t20, %t8
  %t22 = zext i1 %c21 to i64
  %t23 = icmp ne i64 %t22, 0
  br i1 %t23, label %label_24, label %label_25
label_24:
  br label %label_26
label_25:
  br label %label_26
label_26:
  %t27 = phi i64 [ 1, %label_24 ], [ 0, %label_25 ]
  %t28 = add i64 %t1, %t27
  %t29 = mul i64 %t27, %t8
  %t30 = sub i64 %t20, %t29
  %c31 = icmp sle i64 %places, 0
  %t32 = zext i1 %c31 to i64
  %t33 = icmp ne i64 %t32, 0
  br i1 %t33, label %label_34, label %label_35
label_34:
  %t37 = call i64 @Fmt$fmtInt(i64 %t28)
  br label %label_36
label_35:
  %t38 = call i64 @Fmt$fmtInt(i64 %t28)
  %t39 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_3, i64 0, i32 2) to i64
  %t40 = call i64 @Str$strConcat(i64 %t38, i64 %t39)
  call void @axiom_release(i64 %t38)
  call void @axiom_release(i64 %t39)
  %t41 = call i64 @Fmt$fmtPadZeros(i64 %t30, i64 %places)
  %t42 = call i64 @Str$strConcat(i64 %t40, i64 %t41)
  call void @axiom_release(i64 %t40)
  call void @axiom_release(i64 %t41)
  br label %label_36
label_36:
  %t43 = phi i64 [ %t37, %label_34 ], [ %t42, %label_35 ]
  ret i64 %t43
}
define i64 @Sys$stdin() #0 {

  ret i64 0
}
define i64 @Sys$stdout() #0 {

  ret i64 1
}
define i64 @Sys$stderr() #0 {

  ret i64 2
}
define i64 @Sys$sysWriteFd(i64 %fd, i64 %buf, i64 %count) #0 {

  %t0 = call i64 @Sys.Platform$sysWrite()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %buf, i64 %count, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysWriteAllFd(i64 %fd, i64 %buf, i64 %count, i64 %done) #0 {

  %s.1 = alloca i64
  store i64 %fd, ptr %s.1
  %s.2 = alloca i64
  store i64 %buf, ptr %s.2
  %s.3 = alloca i64
  store i64 %count, ptr %s.3
  %s.4 = alloca i64
  store i64 %done, ptr %s.4
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.4
  %t6 = load i64, ptr %s.3
  %c7 = icmp sge i64 %t5, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = load i64, ptr %s.4
  br label %label_12
label_11:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = load i64, ptr %s.4
  %t17 = add i64 %t15, %t16
  %t18 = load i64, ptr %s.3
  %t19 = load i64, ptr %s.4
  %t20 = sub i64 %t18, %t19
  %t21 = call i64 @Sys$sysWriteFd(i64 %t14, i64 %t17, i64 %t20)
  %c22 = icmp slt i64 %t21, 1
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  %c28 = icmp slt i64 %t21, 0
  %t29 = zext i1 %c28 to i64
  %t30 = icmp ne i64 %t29, 0
  br i1 %t30, label %label_31, label %label_32
label_31:
  br label %label_33
label_32:
  %t34 = load i64, ptr %s.4
  br label %label_33
label_33:
  %t35 = phi i64 [ %t21, %label_31 ], [ %t34, %label_32 ]
  br label %label_27
label_26:
  %t36 = load i64, ptr %s.1
  %t37 = load i64, ptr %s.2
  %t38 = load i64, ptr %s.3
  %t39 = load i64, ptr %s.4
  %t40 = add i64 %t39, %t21
  store i64 %t36, ptr %s.1
  store i64 %t37, ptr %s.2
  store i64 %t38, ptr %s.3
  store i64 %t40, ptr %s.4
  br label %label_0
label_27:
  br label %label_12
label_12:
  %t41 = phi i64 [ %t13, %label_10 ], [ %t35, %label_27 ]
  ret i64 %t41
}
define i64 @Sys$sysReadFd(i64 %fd, i64 %buf, i64 %count) #0 {

  %t0 = call i64 @Sys.Platform$sysRead()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %buf, i64 %count, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysOpenPath(i64 %path, i64 %flags) #0 {

  %t0 = call i64 @Sys$sysOpenPathMode(i64 %path, i64 %flags, i64 420)
  ret i64 %t0
}
define i64 @Sys$sysOpenPathMode(i64 %path, i64 %flags, i64 %mode) #0 {

  %t0 = call i64 @Sys.Platform$openNeedsDirFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysOpen()
  %t8 = call i64 @Sys.Platform$atFdCwd()
  %t9 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %t8, i64 %path, i64 %flags, i64 %mode, i64 0, i64 0)
  br label %label_6
label_5:
  %t10 = call i64 @Sys.Platform$sysOpen()
  %t11 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t10, i64 %path, i64 %flags, i64 %mode, i64 0, i64 0, i64 0)
  br label %label_6
label_6:
  %t12 = phi i64 [ %t9, %label_4 ], [ %t11, %label_5 ]
  ret i64 %t12
}
define i64 @Sys$sysCloseFd(i64 %fd) #0 {

  %t0 = call i64 @Sys.Platform$sysClose()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 0, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysSeek(i64 %fd, i64 %offset, i64 %whence) #0 {

  %t0 = call i64 @Sys.Platform$sysLseek()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %offset, i64 %whence, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysExitWith(i64 %code) #0 {

  %t0 = call i64 @Sys.Platform$sysExit()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %code, i64 0, i64 0, i64 0, i64 0, i64 0)
  ret i64 0
}
define i64 @Sys$sysFailed(i64 %result) #0 {

  %c0 = icmp slt i64 %result, 0
  %t1 = zext i1 %c0 to i64
  ret i64 %t1
}
define i64 @Sys$sysErrno(i64 %result) #0 {

  %c0 = icmp slt i64 %result, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  %t6 = sub i64 0, %result
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t7 = phi i64 [ %t6, %label_3 ], [ 0, %label_4 ]
  ret i64 %t7
}
define i64 @Sys$sysReadFile(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$oRdonly()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %t2 = call i64 @Sys$sysFailed(i64 %t1)
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_6
label_5:
  %t8 = call i64 @Str$strAlloc(i64 65536)
  %t9 = call i64 @Sys$sysReadAll(i64 %t1, i64 %t8, i64 0, i64 65536)
  call void @axiom_release(i64 %t8)
  %t10 = call i64 @Sys$sysCloseFd(i64 %t1)
  br label %label_6
label_6:
  %t11 = phi i64 [ %t7, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t11
}
define i64 @Sys$sysReadAll(i64 %fd, i64 %buf, i64 %used, i64 %cap) #0 {

  %s.1 = alloca i64
  store i64 %fd, ptr %s.1
  %s.2 = alloca i64
  store i64 %buf, ptr %s.2
  %s.3 = alloca i64
  store i64 %used, ptr %s.3
  %s.4 = alloca i64
  store i64 %cap, ptr %s.4
  call void @axiom_retain(i64 %buf)
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.1
  %t6 = load i64, ptr %s.2
  %t7 = call i64 @Str$strData(i64 %t6)
  %t8 = load i64, ptr %s.3
  %t9 = add i64 %t7, %t8
  %t10 = load i64, ptr %s.4
  %t11 = load i64, ptr %s.3
  %t12 = sub i64 %t10, %t11
  %t13 = call i64 @Sys$sysReadFd(i64 %t5, i64 %t9, i64 %t12)
  %c14 = icmp sle i64 %t13, 0
  %t15 = zext i1 %c14 to i64
  %t16 = icmp ne i64 %t15, 0
  br i1 %t16, label %label_17, label %label_18
label_17:
  %t20 = load i64, ptr %s.3
  %c21 = icmp eq i64 %t20, 0
  %t22 = zext i1 %c21 to i64
  %t23 = icmp ne i64 %t22, 0
  br i1 %t23, label %label_24, label %label_25
label_24:
  %t27 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_26
label_25:
  %t28 = load i64, ptr %s.2
  %t29 = call i64 @Str$strOwner(i64 %t28)
  call void @axiom_retain(i64 %t29)
  %t30 = load i64, ptr %s.2
  %t31 = call i64 @Str$strData(i64 %t30)
  %t32 = load i64, ptr %s.3
  %t33 = call i64 @Str$strWrapOwned(i64 %t31, i64 %t32, i64 %t29)
  br label %label_26
label_26:
  %t34 = phi i64 [ %t27, %label_24 ], [ %t33, %label_25 ]
  br label %label_19
label_18:
  %t35 = load i64, ptr %s.3
  %t36 = add i64 %t35, %t13
  %t37 = load i64, ptr %s.4
  %c38 = icmp slt i64 %t36, %t37
  %t39 = zext i1 %c38 to i64
  %t40 = icmp ne i64 %t39, 0
  br i1 %t40, label %label_41, label %label_42
label_41:
  %t44 = load i64, ptr %s.1
  %t45 = load i64, ptr %s.2
  %t46 = load i64, ptr %s.4
  %t47 = load i64, ptr %s.2
  store i64 %t44, ptr %s.1
  store i64 %t45, ptr %s.2
  store i64 %t36, ptr %s.3
  store i64 %t46, ptr %s.4
  br label %label_0
label_42:
  %t48 = load i64, ptr %s.4
  %t49 = mul i64 %t48, 2
  %t50 = call i64 @Str$strAlloc(i64 %t49)
  %t51 = call i64 @Str$strData(i64 %t50)
  %t52 = load i64, ptr %s.2
  %t53 = call i64 @Str$strData(i64 %t52)
  %t54 = call i64 @Mem$memCopy(i64 %t51, i64 %t53, i64 %t36)
  %t55 = load i64, ptr %s.1
  %t56 = load i64, ptr %s.4
  %t57 = mul i64 %t56, 2
  call void @axiom_retain(i64 %t50)
  %t58 = load i64, ptr %s.2
  store i64 %t55, ptr %s.1
  store i64 %t50, ptr %s.2
  store i64 %t36, ptr %s.3
  store i64 %t57, ptr %s.4
  call void @axiom_release(i64 %t58)
  call void @axiom_release(i64 %t50)
  br label %label_0
label_19:
  %t59 = load i64, ptr %s.2
  call void @axiom_release(i64 %t59)
  ret i64 %t34
}
define i64 @Sys$sysArgc() #0 {

  %t0 = load i64, ptr @__axiom_argc
  ret i64 %t0
}
define i64 @Sys$sysArg(i64 %i) #0 {

  %c0 = icmp slt i64 %i, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_4, label %label_3
label_3:
  %t6 = load i64, ptr @__axiom_argc
  %c7 = icmp sge i64 %i, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  %t10 = zext i1 %t9 to i64
  br label %label_5
label_4:
  br label %label_5
label_5:
  %t11 = phi i64 [ %t10, %label_3 ], [ 1, %label_4 ]
  %t12 = icmp ne i64 %t11, 0
  br i1 %t12, label %label_13, label %label_14
label_13:
  %t16 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_15
label_14:
  %t17 = load i64, ptr @__axiom_argv
  %p18 = inttoptr i64 %t17 to ptr
  %g19 = getelementptr i64, ptr %p18, i64 %i
  %t20 = load i64, ptr %g19
  %t21 = call i64 @Str$strFromLit(i64 %t20)
  br label %label_15
label_15:
  %t22 = phi i64 [ %t16, %label_13 ], [ %t21, %label_14 ]
  ret i64 %t22
}
define i64 @Sys$sysWriteFile(i64 %path, i64 %s) #0 {

  %t0 = call i64 @Sys.Platform$oWronlyCreateTrunc()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %t2 = call i64 @Sys$sysFailed(i64 %t1)
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = call i64 @Str$strData(i64 %s)
  %t8 = call i64 @Str$strLen(i64 %s)
  %t9 = call i64 @Sys$sysWriteAllFd(i64 %t1, i64 %t7, i64 %t8, i64 0)
  %t10 = call i64 @Sys$sysCloseFd(i64 %t1)
  br label %label_6
label_6:
  %t11 = phi i64 [ %t1, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t11
}
define i64 @Sys$sysAppendFile(i64 %path, i64 %s) #0 {

  %t0 = call i64 @Sys.Platform$oWronlyCreateAppend()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %t2 = call i64 @Sys$sysFailed(i64 %t1)
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = call i64 @Str$strData(i64 %s)
  %t8 = call i64 @Str$strLen(i64 %s)
  %t9 = call i64 @Sys$sysWriteAllFd(i64 %t1, i64 %t7, i64 %t8, i64 0)
  %t10 = call i64 @Sys$sysCloseFd(i64 %t1)
  br label %label_6
label_6:
  %t11 = phi i64 [ %t1, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t11
}
define i64 @Sys$sysRename(i64 %old, i64 %new) #0 {

  %t0 = call i64 @Sys.Platform$openNeedsDirFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysRenameNum()
  %t8 = call i64 @Sys.Platform$atFdCwd()
  %t9 = call i64 @Sys.Platform$atFdCwd()
  %t10 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %t8, i64 %old, i64 %t9, i64 %new, i64 0, i64 0)
  br label %label_6
label_5:
  %t11 = call i64 @Sys.Platform$sysRenameNum()
  %t12 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t11, i64 %old, i64 %new, i64 0, i64 0, i64 0, i64 0)
  br label %label_6
label_6:
  %t13 = phi i64 [ %t10, %label_4 ], [ %t12, %label_5 ]
  ret i64 %t13
}
define i64 @Sys$sysUnlink(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$openNeedsDirFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysUnlinkNum()
  %t8 = call i64 @Sys.Platform$atFdCwd()
  %t9 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %t8, i64 %path, i64 0, i64 0, i64 0, i64 0)
  br label %label_6
label_5:
  %t10 = call i64 @Sys.Platform$sysUnlinkNum()
  %t11 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t10, i64 %path, i64 0, i64 0, i64 0, i64 0, i64 0)
  br label %label_6
label_6:
  %t12 = phi i64 [ %t9, %label_4 ], [ %t11, %label_5 ]
  ret i64 %t12
}
define i64 @Sys$sysMkdir(i64 %path, i64 %mode) #0 {

  %t0 = call i64 @Sys.Platform$openNeedsDirFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysMkdirNum()
  %t8 = call i64 @Sys.Platform$atFdCwd()
  %t9 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %t8, i64 %path, i64 %mode, i64 0, i64 0, i64 0)
  br label %label_6
label_5:
  %t10 = call i64 @Sys.Platform$sysMkdirNum()
  %t11 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t10, i64 %path, i64 %mode, i64 0, i64 0, i64 0, i64 0)
  br label %label_6
label_6:
  %t12 = phi i64 [ %t9, %label_4 ], [ %t11, %label_5 ]
  ret i64 %t12
}
define i64 @Sys$sysDirMode() #0 {

  ret i64 493
}
define i64 @Sys$sysRmdir(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$openNeedsDirFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysRmdirNum()
  %t8 = call i64 @Sys.Platform$atFdCwd()
  %t9 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %t8, i64 %path, i64 512, i64 0, i64 0, i64 0)
  br label %label_6
label_5:
  %t10 = call i64 @Sys.Platform$sysRmdirNum()
  %t11 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t10, i64 %path, i64 0, i64 0, i64 0, i64 0, i64 0)
  br label %label_6
label_6:
  %t12 = phi i64 [ %t9, %label_4 ], [ %t11, %label_5 ]
  ret i64 %t12
}
define i64 @Sys$sysFileExists(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$oRdonly()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %c2 = icmp slt i64 %t1, 0
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  %t8 = call i64 @Sys$sysCloseFd(i64 %t1)
  br label %label_7
label_7:
  %t9 = phi i64 [ 0, %label_5 ], [ 1, %label_6 ]
  ret i64 %t9
}
define i64 @Sys$sysFileSize(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$oRdonly()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %c2 = icmp slt i64 %t1, 0
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  %t8 = call i64 @Sys.Platform$seekEnd()
  %t9 = call i64 @Sys$sysSeek(i64 %t1, i64 0, i64 %t8)
  %t10 = call i64 @Sys$sysCloseFd(i64 %t1)
  br label %label_7
label_7:
  %t11 = phi i64 [ %t1, %label_5 ], [ %t9, %label_6 ]
  ret i64 %t11
}
define i64 @Sys$sysReadErrno(i64 %path) #0 {

  %t0 = call i64 @Sys.Platform$oRdonly()
  %t1 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t0)
  %t2 = call i64 @Sys$sysFailed(i64 %t1)
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys$sysErrno(i64 %t1)
  br label %label_6
label_5:
  %t8 = call i64 @Str$strAlloc(i64 1)
  %t9 = call i64 @Str$strData(i64 %t8)
  %t10 = call i64 @Sys$sysReadFd(i64 %t1, i64 %t9, i64 1)
  %t11 = call i64 @Sys$sysCloseFd(i64 %t1)
  %c12 = icmp slt i64 %t10, 0
  %t13 = zext i1 %c12 to i64
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  %t18 = call i64 @Sys$sysErrno(i64 %t10)
  br label %label_17
label_16:
  br label %label_17
label_17:
  %t19 = phi i64 [ %t18, %label_15 ], [ 0, %label_16 ]
  call void @axiom_release(i64 %t8)
  br label %label_6
label_6:
  %t20 = phi i64 [ %t7, %label_4 ], [ %t19, %label_17 ]
  ret i64 %t20
}
define i64 @Sys$sysIsDir(i64 %path) #0 {

  %t0 = call i64 @Sys$sysReadErrno(i64 %path)
  %t1 = call i64 @Sys.Platform$eIsDir()
  %c2 = icmp eq i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  ret i64 %t3
}
define i64 @Sys$sysDirBufBytes() #0 {

  ret i64 32768
}
define i64 @Sys$sysReadDir(i64 %path) #0 {

  %t0 = call i64 @Vec$vecNew()
  %t1 = call i64 @Sys.Platform$oRdonly()
  %t2 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t1)
  %t3 = call i64 @Sys$sysFailed(i64 %t2)
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  br label %label_7
label_6:
  %t8 = call i64 @Sys$sysDirBufBytes()
  %t9 = call i64 @Mem$memAlloc(i64 %t8)
  %t10 = call i64 @Mem$memAlloc(i64 8)
  %t11 = call i64 @Mem$memSetWord(i64 %t10, i64 0, i64 0, i64 0)
  %t12 = call i64 @Sys$sysReadDirLoop(i64 %t2, i64 %t9, i64 %t10, i64 %t0)
  %t13 = call i64 @Sys$sysCloseFd(i64 %t2)
  br label %label_7
label_7:
  %t14 = phi i64 [ %t0, %label_5 ], [ %t0, %label_6 ]
  ret i64 %t14
}
define i64 @Sys$sysReadDirLoop(i64 %fd, i64 %buf, i64 %pos, i64 %out) #0 {

  %s.1 = alloca i64
  store i64 %fd, ptr %s.1
  %s.2 = alloca i64
  store i64 %buf, ptr %s.2
  %s.3 = alloca i64
  store i64 %pos, ptr %s.3
  %s.4 = alloca i64
  store i64 %out, ptr %s.4
  br label %label_0
label_0:
  %t5 = call i64 @Sys.Platform$dirReadNeedsPosition()
  %c6 = icmp eq i64 %t5, 1
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = call i64 @Sys.Platform$sysGetdentsNum()
  %t13 = load i64, ptr %s.1
  %t14 = load i64, ptr %s.2
  %t15 = call i64 @Sys$sysDirBufBytes()
  %t16 = load i64, ptr %s.3
  %t17 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t12, i64 %t13, i64 %t14, i64 %t15, i64 %t16, i64 0, i64 0)
  br label %label_11
label_10:
  %t18 = call i64 @Sys.Platform$sysGetdentsNum()
  %t19 = load i64, ptr %s.1
  %t20 = load i64, ptr %s.2
  %t21 = call i64 @Sys$sysDirBufBytes()
  %t22 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t18, i64 %t19, i64 %t20, i64 %t21, i64 0, i64 0, i64 0)
  br label %label_11
label_11:
  %t23 = phi i64 [ %t17, %label_9 ], [ %t22, %label_10 ]
  %c24 = icmp sle i64 %t23, 0
  %t25 = zext i1 %c24 to i64
  %t26 = icmp ne i64 %t25, 0
  br i1 %t26, label %label_27, label %label_28
label_27:
  br label %label_29
label_28:
  %t30 = load i64, ptr %s.2
  %t31 = load i64, ptr %s.4
  %t32 = call i64 @Sys$sysReadDirDecode(i64 %t30, i64 0, i64 %t23, i64 %t31)
  %t33 = load i64, ptr %s.1
  %t34 = load i64, ptr %s.2
  %t35 = load i64, ptr %s.3
  %t36 = load i64, ptr %s.4
  store i64 %t33, ptr %s.1
  store i64 %t34, ptr %s.2
  store i64 %t35, ptr %s.3
  store i64 %t36, ptr %s.4
  br label %label_0
label_29:
  ret i64 %t23
}
define i64 @Sys$sysReadDirDecode(i64 %buf, i64 %off, i64 %n, i64 %out) #0 {

  %s.1 = alloca i64
  store i64 %buf, ptr %s.1
  %s.2 = alloca i64
  store i64 %off, ptr %s.2
  %s.3 = alloca i64
  store i64 %n, ptr %s.3
  %s.4 = alloca i64
  store i64 %out, ptr %s.4
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.2
  %t6 = add i64 %t5, 18
  %t7 = load i64, ptr %s.3
  %c8 = icmp sgt i64 %t6, %t7
  %t9 = zext i1 %c8 to i64
  %t10 = icmp ne i64 %t9, 0
  br i1 %t10, label %label_11, label %label_12
label_11:
  br label %label_13
label_12:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = add i64 %t14, %t15
  %t17 = call i64 @Mem$memGetByte(i64 %t16, i64 16)
  %t18 = call i64 @Mem$memGetByte(i64 %t16, i64 17)
  %t19 = mul i64 %t18, 256
  %t20 = add i64 %t17, %t19
  %t21 = call i64 @Sys.Platform$direntNameOffset()
  %c22 = icmp sle i64 %t20, %t21
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_26, label %label_25
label_25:
  %t28 = load i64, ptr %s.2
  %t29 = add i64 %t28, %t20
  %t30 = load i64, ptr %s.3
  %c31 = icmp sgt i64 %t29, %t30
  %t32 = zext i1 %c31 to i64
  %t33 = icmp ne i64 %t32, 0
  %t34 = zext i1 %t33 to i64
  br label %label_27
label_26:
  br label %label_27
label_27:
  %t35 = phi i64 [ %t34, %label_25 ], [ 1, %label_26 ]
  %t36 = icmp ne i64 %t35, 0
  br i1 %t36, label %label_37, label %label_38
label_37:
  br label %label_39
label_38:
  %t40 = load i64, ptr %s.4
  %t41 = call i64 @Sys.Platform$direntNameOffset()
  %t42 = add i64 %t16, %t41
  %t43 = call i64 @Str$strFromLit(i64 %t42)
  %t44 = call i64 @Str$strDup(i64 %t43)
  call void @axiom_release(i64 %t43)
  %t45 = call i64 @Vec$vecPush(i64 %t40, i64 %t44, i64 0)
  %t46 = load i64, ptr %s.1
  %t47 = load i64, ptr %s.2
  %t48 = add i64 %t47, %t20
  %t49 = load i64, ptr %s.3
  %t50 = load i64, ptr %s.4
  store i64 %t46, ptr %s.1
  store i64 %t48, ptr %s.2
  store i64 %t49, ptr %s.3
  store i64 %t50, ptr %s.4
  br label %label_0
label_39:
  br label %label_13
label_13:
  %t51 = phi i64 [ 0, %label_11 ], [ 0, %label_39 ]
  ret i64 %t51
}
define i64 @Sys$sysGetCwd() #0 {

  %t0 = call i64 @Mem$memAlloc(i64 4097)
  %t1 = call i64 @Sys.Platform$cwdUsesFcntlPath()
  %c2 = icmp eq i64 %t1, 1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = ptrtoint ptr @str_3 to i64
  %t9 = call i64 @Sys$sysOpenPath(i64 %t8, i64 0)
  %t10 = call i64 @Sys$sysFailed(i64 %t9)
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  %t15 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_14
label_13:
  %t16 = call i64 @Sys.Platform$sysCwdNum()
  %t17 = call i64 @Sys.Platform$fGetPath()
  %t18 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t16, i64 %t9, i64 %t17, i64 %t0, i64 0, i64 0, i64 0)
  %t19 = call i64 @Sys$sysCloseFd(i64 %t9)
  %c20 = icmp slt i64 %t18, 0
  %t21 = zext i1 %c20 to i64
  %t22 = icmp ne i64 %t21, 0
  br i1 %t22, label %label_23, label %label_24
label_23:
  %t26 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_25
label_24:
  %t27 = call i64 @Str$strFromLit(i64 %t0)
  %t28 = call i64 @Str$strDup(i64 %t27)
  call void @axiom_release(i64 %t27)
  br label %label_25
label_25:
  %t29 = phi i64 [ %t26, %label_23 ], [ %t28, %label_24 ]
  br label %label_14
label_14:
  %t30 = phi i64 [ %t15, %label_12 ], [ %t29, %label_25 ]
  br label %label_7
label_6:
  %t31 = call i64 @Sys.Platform$sysCwdNum()
  %t32 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t31, i64 %t0, i64 4096, i64 0, i64 0, i64 0, i64 0)
  %c33 = icmp slt i64 %t32, 0
  %t34 = zext i1 %c33 to i64
  %t35 = icmp ne i64 %t34, 0
  br i1 %t35, label %label_36, label %label_37
label_36:
  %t39 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_38
label_37:
  %t40 = call i64 @Str$strFromLit(i64 %t0)
  %t41 = call i64 @Str$strDup(i64 %t40)
  call void @axiom_release(i64 %t40)
  br label %label_38
label_38:
  %t42 = phi i64 [ %t39, %label_36 ], [ %t41, %label_37 ]
  br label %label_7
label_7:
  %t43 = phi i64 [ %t30, %label_14 ], [ %t42, %label_38 ]
  ret i64 %t43
}
define i64 @Sys$sysEnvSlot(i64 %i) #0 {

  %t0 = load i64, ptr @__axiom_argc
  %t1 = add i64 %t0, 1
  %t2 = add i64 %t1, %i
  %t3 = load i64, ptr @__axiom_argv
  %p4 = inttoptr i64 %t3 to ptr
  %g5 = getelementptr i64, ptr %p4, i64 %t2
  %t6 = load i64, ptr %g5
  ret i64 %t6
}
define i64 @Sys$sysEnvCount() #0 {

  %t0 = call i64 @Sys$sysEnvCountFrom(i64 0)
  ret i64 %t0
}
define i64 @Sys$sysEnvCountFrom(i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %i, ptr %s.1
  br label %label_0
label_0:
  %t2 = load i64, ptr %s.1
  %t3 = call i64 @Sys$sysEnvSlot(i64 %t2)
  %c4 = icmp eq i64 %t3, 0
  %t5 = zext i1 %c4 to i64
  %t6 = icmp ne i64 %t5, 0
  br i1 %t6, label %label_7, label %label_8
label_7:
  %t10 = load i64, ptr %s.1
  br label %label_9
label_8:
  %t11 = load i64, ptr %s.1
  %t12 = add i64 %t11, 1
  store i64 %t12, ptr %s.1
  br label %label_0
label_9:
  ret i64 %t10
}
define i64 @Sys$sysEnv(i64 %name) #0 {

  %t0 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_5, i64 0, i32 2) to i64
  %t1 = call i64 @Str$strConcat(i64 %name, i64 %t0)
  call void @axiom_release(i64 %t0)
  %t2 = call i64 @Sys$sysEnvLookup(i64 %t1, i64 0)
  call void @axiom_release(i64 %t1)
  ret i64 %t2
}
define i64 @Sys$sysEnvLookup(i64 %prefix, i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %prefix, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  call void @axiom_retain(i64 %prefix)
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.2
  %t4 = call i64 @Sys$sysEnvSlot(i64 %t3)
  %c5 = icmp eq i64 %t4, 0
  %t6 = zext i1 %c5 to i64
  %t7 = icmp ne i64 %t6, 0
  br i1 %t7, label %label_8, label %label_9
label_8:
  %t11 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  br label %label_10
label_9:
  %t12 = call i64 @Str$strFromLit(i64 %t4)
  %t13 = load i64, ptr %s.1
  %t14 = call i64 @Str$strStartsWith(i64 %t12, i64 %t13)
  %t15 = icmp ne i64 %t14, 0
  br i1 %t15, label %label_16, label %label_17
label_16:
  %t19 = load i64, ptr %s.1
  %t20 = call i64 @Str$strLen(i64 %t19)
  %t21 = call i64 @Str$strLen(i64 %t12)
  %t22 = load i64, ptr %s.1
  %t23 = call i64 @Str$strLen(i64 %t22)
  %t24 = sub i64 %t21, %t23
  %t25 = call i64 @Str$strSlice(i64 %t12, i64 %t20, i64 %t24)
  br label %label_18
label_17:
  %t26 = load i64, ptr %s.1
  %t27 = load i64, ptr %s.2
  %t28 = add i64 %t27, 1
  %t29 = load i64, ptr %s.1
  store i64 %t26, ptr %s.1
  store i64 %t28, ptr %s.2
  call void @axiom_release(i64 %t12)
  br label %label_0
label_18:
  call void @axiom_release(i64 %t12)
  br label %label_10
label_10:
  %t30 = phi i64 [ %t11, %label_8 ], [ %t25, %label_18 ]
  %t31 = load i64, ptr %s.1
  call void @axiom_release(i64 %t31)
  ret i64 %t30
}
define i64 @Sys$sysEnvp() #0 {

  %t0 = call i64 @Sys$sysEnvCount()
  %t1 = add i64 %t0, 1
  %t2 = mul i64 %t1, 8
  %t3 = call i64 @Mem$memAlloc(i64 %t2)
  %t4 = call i64 @Sys$sysEnvpFill(i64 %t3, i64 0, i64 %t0)
  ret i64 %t3
}
define i64 @Sys$sysEnvpFill(i64 %v, i64 %i, i64 %n) #0 {

  %s.1 = alloca i64
  store i64 %v, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %n, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = load i64, ptr %s.3
  %c6 = icmp sge i64 %t4, %t5
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  %t13 = load i64, ptr %s.3
  %t14 = call i64 @Mem$memSetWord(i64 %t12, i64 %t13, i64 0, i64 0)
  br label %label_11
label_10:
  %t15 = load i64, ptr %s.1
  %t16 = load i64, ptr %s.2
  %t17 = load i64, ptr %s.2
  %t18 = call i64 @Sys$sysEnvSlot(i64 %t17)
  %t19 = call i64 @Mem$memSetWord(i64 %t15, i64 %t16, i64 %t18, i64 0)
  %t20 = load i64, ptr %s.1
  %t21 = load i64, ptr %s.2
  %t22 = add i64 %t21, 1
  %t23 = load i64, ptr %s.3
  store i64 %t20, ptr %s.1
  store i64 %t22, ptr %s.2
  store i64 %t23, ptr %s.3
  br label %label_0
label_11:
  ret i64 %t14
}
define i64 @Sys$sysSpawn(i64 %path, i64 %argv, i64 %envp) #0 {

  %t0 = call i64 @Sys.Platform$spawnUsesPosixSpawn()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Mem$memAlloc(i64 8)
  %t8 = call i64 @Mem$memSetWord(i64 %t7, i64 0, i64 0, i64 0)
  %t9 = call i64 @Sys.Platform$sysPosixSpawn()
  %t10 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t9, i64 %t7, i64 %path, i64 0, i64 %argv, i64 %envp, i64 0)
  %c11 = icmp slt i64 %t10, 0
  %t12 = zext i1 %c11 to i64
  %t13 = icmp ne i64 %t12, 0
  br i1 %t13, label %label_14, label %label_15
label_14:
  br label %label_16
label_15:
  %t17 = call i64 @Mem$memGetWord(i64 %t7, i64 0)
  br label %label_16
label_16:
  %t18 = phi i64 [ %t10, %label_14 ], [ %t17, %label_15 ]
  br label %label_6
label_5:
  %t19 = call i64 @Sys.Platform$oRdonly()
  %t20 = call i64 @Sys$sysOpenPath(i64 %path, i64 %t19)
  %t21 = sub i64 0, 2
  %c22 = icmp eq i64 %t20, %t21
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  br label %label_27
label_26:
  %c28 = icmp sge i64 %t20, 0
  %t29 = zext i1 %c28 to i64
  %t30 = icmp ne i64 %t29, 0
  br i1 %t30, label %label_31, label %label_32
label_31:
  %t34 = call i64 @Sys$sysCloseFd(i64 %t20)
  br label %label_33
label_32:
  br label %label_33
label_33:
  %t35 = phi i64 [ %t34, %label_31 ], [ 0, %label_32 ]
  %t36 = call i64 @Sys$sysForkProcess()
  %c37 = icmp slt i64 %t36, 0
  %t38 = zext i1 %c37 to i64
  %t39 = icmp ne i64 %t38, 0
  br i1 %t39, label %label_40, label %label_41
label_40:
  br label %label_42
label_41:
  %c43 = icmp eq i64 %t36, 0
  %t44 = zext i1 %c43 to i64
  %t45 = icmp ne i64 %t44, 0
  br i1 %t45, label %label_46, label %label_47
label_46:
  %t49 = call i64 @Sys.Platform$sysExecve()
  %t50 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t49, i64 %path, i64 %argv, i64 %envp, i64 0, i64 0, i64 0)
  %t51 = call i64 @Sys.Platform$sysExit()
  %t52 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t51, i64 127, i64 0, i64 0, i64 0, i64 0, i64 0)
  br label %label_48
label_47:
  br label %label_48
label_48:
  %t53 = phi i64 [ 0, %label_46 ], [ %t36, %label_47 ]
  br label %label_42
label_42:
  %t54 = phi i64 [ %t36, %label_40 ], [ %t53, %label_48 ]
  br label %label_27
label_27:
  %t55 = phi i64 [ %t20, %label_25 ], [ %t54, %label_42 ]
  br label %label_6
label_6:
  %t56 = phi i64 [ %t18, %label_16 ], [ %t55, %label_27 ]
  ret i64 %t56
}
define i64 @Sys$sysWaitPid(i64 %pid) #0 {

  %t0 = call i64 @Mem$memAlloc(i64 8)
  %t1 = call i64 @Mem$memSetWord(i64 %t0, i64 0, i64 0, i64 0)
  %t2 = call i64 @Sys.Platform$sysWait4()
  %t3 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t2, i64 %pid, i64 %t0, i64 0, i64 0, i64 0, i64 0)
  %c4 = icmp slt i64 %t3, 0
  %t5 = zext i1 %c4 to i64
  %t6 = icmp ne i64 %t5, 0
  br i1 %t6, label %label_7, label %label_8
label_7:
  br label %label_9
label_8:
  %t10 = call i64 @Mem$memGetWord(i64 %t0, i64 0)
  br label %label_9
label_9:
  %t11 = phi i64 [ %t3, %label_7 ], [ %t10, %label_8 ]
  ret i64 %t11
}
define i64 @Sys$sysExitCode(i64 %status) #0 {

  %t0 = ashr i64 %status, 8
  %t1 = and i64 %t0, 255
  ret i64 %t1
}
define i64 @Sys$sysTermSignal(i64 %status) #0 {

  %t0 = and i64 %status, 127
  ret i64 %t0
}
define i64 @Sys$sysRun(i64 %path, i64 %argv, i64 %envp) #0 {

  %t0 = call i64 @Sys$sysSpawn(i64 %path, i64 %argv, i64 %envp)
  %c1 = icmp slt i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  br label %label_6
label_5:
  %t7 = call i64 @Sys$sysWaitPid(i64 %t0)
  %c8 = icmp slt i64 %t7, 0
  %t9 = zext i1 %c8 to i64
  %t10 = icmp ne i64 %t9, 0
  br i1 %t10, label %label_11, label %label_12
label_11:
  br label %label_13
label_12:
  %t14 = call i64 @Sys$sysTermSignal(i64 %t7)
  %c15 = icmp ne i64 %t14, 0
  %t16 = zext i1 %c15 to i64
  %t17 = icmp ne i64 %t16, 0
  br i1 %t17, label %label_18, label %label_19
label_18:
  %t21 = call i64 @Sys$sysTermSignal(i64 %t7)
  %t22 = add i64 128, %t21
  br label %label_20
label_19:
  %t23 = call i64 @Sys$sysExitCode(i64 %t7)
  br label %label_20
label_20:
  %t24 = phi i64 [ %t22, %label_18 ], [ %t23, %label_19 ]
  br label %label_13
label_13:
  %t25 = phi i64 [ %t7, %label_11 ], [ %t24, %label_20 ]
  br label %label_6
label_6:
  %t26 = phi i64 [ %t0, %label_4 ], [ %t25, %label_13 ]
  ret i64 %t26
}
define i64 @Sys$sysRunPath(i64 %name, i64 %argv, i64 %envp) #0 {

  %t0 = call i64 @Str$strFindByte(i64 %name, i64 47, i64 0)
  %c1 = icmp sge i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Str$strDup(i64 %name)
  %t8 = call i64 @Str$strCStr(i64 %t7)
  %t9 = call i64 @Sys$sysRun(i64 %t8, i64 %argv, i64 %envp)
  br label %label_6
label_5:
  %t10 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_6, i64 0, i32 2) to i64
  %t11 = call i64 @Sys$sysEnv(i64 %t10)
  call void @axiom_release(i64 %t10)
  %t12 = call i64 @Str$strLen(i64 %t11)
  %c13 = icmp eq i64 %t12, 0
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  br i1 %t15, label %label_16, label %label_17
label_16:
  %t19 = sub i64 0, 2
  br label %label_18
label_17:
  %t20 = call i64 @Sys$sysRunSearch(i64 %name, i64 %argv, i64 %envp, i64 %t11, i64 0)
  br label %label_18
label_18:
  %t21 = phi i64 [ %t19, %label_16 ], [ %t20, %label_17 ]
  call void @axiom_release(i64 %t11)
  br label %label_6
label_6:
  %t22 = phi i64 [ %t9, %label_4 ], [ %t21, %label_18 ]
  ret i64 %t22
}
define i64 @Sys$sysRunSearch(i64 %name, i64 %argv, i64 %envp, i64 %path, i64 %from) #0 {

  %s.1 = alloca i64
  store i64 %name, ptr %s.1
  %s.2 = alloca i64
  store i64 %argv, ptr %s.2
  %s.3 = alloca i64
  store i64 %envp, ptr %s.3
  %s.4 = alloca i64
  store i64 %path, ptr %s.4
  %s.5 = alloca i64
  store i64 %from, ptr %s.5
  call void @axiom_retain(i64 %name)
  call void @axiom_retain(i64 %path)
  br label %label_0
label_0:
  %t6 = load i64, ptr %s.5
  %t7 = load i64, ptr %s.4
  %t8 = call i64 @Str$strLen(i64 %t7)
  %c9 = icmp sge i64 %t6, %t8
  %t10 = zext i1 %c9 to i64
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  %t15 = sub i64 0, 2
  br label %label_14
label_13:
  %t16 = load i64, ptr %s.4
  %t17 = load i64, ptr %s.5
  %t18 = call i64 @Str$strFindByte(i64 %t16, i64 58, i64 %t17)
  %c19 = icmp slt i64 %t18, 0
  %t20 = zext i1 %c19 to i64
  %t21 = icmp ne i64 %t20, 0
  br i1 %t21, label %label_22, label %label_23
label_22:
  %t25 = load i64, ptr %s.4
  %t26 = call i64 @Str$strLen(i64 %t25)
  br label %label_24
label_23:
  br label %label_24
label_24:
  %t27 = phi i64 [ %t26, %label_22 ], [ %t18, %label_23 ]
  %t28 = load i64, ptr %s.4
  %t29 = load i64, ptr %s.5
  %t30 = load i64, ptr %s.5
  %t31 = sub i64 %t27, %t30
  %t32 = call i64 @Str$strSlice(i64 %t28, i64 %t29, i64 %t31)
  %t33 = call i64 @Str$strLen(i64 %t32)
  %c34 = icmp eq i64 %t33, 0
  %t35 = zext i1 %c34 to i64
  %t36 = icmp ne i64 %t35, 0
  br i1 %t36, label %label_37, label %label_38
label_37:
  %t40 = load i64, ptr %s.1
  %t41 = load i64, ptr %s.2
  %t42 = load i64, ptr %s.3
  %t43 = load i64, ptr %s.4
  %t44 = add i64 %t27, 1
  %t45 = load i64, ptr %s.1
  %t46 = load i64, ptr %s.4
  store i64 %t40, ptr %s.1
  store i64 %t41, ptr %s.2
  store i64 %t42, ptr %s.3
  store i64 %t43, ptr %s.4
  store i64 %t44, ptr %s.5
  call void @axiom_release(i64 %t32)
  br label %label_0
label_38:
  %t47 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_7, i64 0, i32 2) to i64
  %t48 = call i64 @Str$strConcat(i64 %t32, i64 %t47)
  call void @axiom_release(i64 %t47)
  %t49 = load i64, ptr %s.1
  %t50 = call i64 @Str$strConcat(i64 %t48, i64 %t49)
  call void @axiom_release(i64 %t48)
  %t51 = call i64 @Str$strCStr(i64 %t50)
  %t52 = call i64 @Sys.Platform$oRdonly()
  %t53 = call i64 @Sys$sysOpenPath(i64 %t51, i64 %t52)
  %c54 = icmp slt i64 %t53, 0
  %t55 = zext i1 %c54 to i64
  %t56 = icmp ne i64 %t55, 0
  br i1 %t56, label %label_57, label %label_58
label_57:
  %t60 = load i64, ptr %s.1
  %t61 = load i64, ptr %s.2
  %t62 = load i64, ptr %s.3
  %t63 = load i64, ptr %s.4
  %t64 = add i64 %t27, 1
  %t65 = load i64, ptr %s.1
  %t66 = load i64, ptr %s.4
  store i64 %t60, ptr %s.1
  store i64 %t61, ptr %s.2
  store i64 %t62, ptr %s.3
  store i64 %t63, ptr %s.4
  store i64 %t64, ptr %s.5
  call void @axiom_release(i64 %t32)
  call void @axiom_release(i64 %t50)
  br label %label_0
label_58:
  %t67 = call i64 @Sys$sysCloseFd(i64 %t53)
  %t68 = load i64, ptr %s.2
  %t69 = load i64, ptr %s.3
  %t70 = call i64 @Sys$sysRun(i64 %t51, i64 %t68, i64 %t69)
  %c71 = icmp sge i64 %t70, 0
  %t72 = zext i1 %c71 to i64
  %t73 = icmp ne i64 %t72, 0
  br i1 %t73, label %label_74, label %label_75
label_74:
  br label %label_76
label_75:
  %t77 = load i64, ptr %s.1
  %t78 = load i64, ptr %s.2
  %t79 = load i64, ptr %s.3
  %t80 = load i64, ptr %s.4
  %t81 = add i64 %t27, 1
  %t82 = load i64, ptr %s.1
  %t83 = load i64, ptr %s.4
  store i64 %t77, ptr %s.1
  store i64 %t78, ptr %s.2
  store i64 %t79, ptr %s.3
  store i64 %t80, ptr %s.4
  store i64 %t81, ptr %s.5
  call void @axiom_release(i64 %t32)
  call void @axiom_release(i64 %t50)
  br label %label_0
label_76:
  br label %label_59
label_59:
  call void @axiom_release(i64 %t50)
  br label %label_39
label_39:
  call void @axiom_release(i64 %t32)
  br label %label_14
label_14:
  %t84 = phi i64 [ %t15, %label_12 ], [ %t70, %label_39 ]
  %t85 = load i64, ptr %s.1
  call void @axiom_release(i64 %t85)
  %t86 = load i64, ptr %s.4
  call void @axiom_release(i64 %t86)
  ret i64 %t84
}
define i64 @Sys$sysGetPid() #0 {

  %t0 = call i64 @Sys.Platform$sysGetPidNum()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysNowMicros(i64 %buf) #0 {

  %t0 = call i64 @Sys.Platform$clockIsGettimeofday()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys.Platform$sysClockNum()
  %t8 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t7, i64 %buf, i64 0, i64 0, i64 0, i64 0, i64 0)
  %c9 = icmp slt i64 %t8, 0
  %t10 = zext i1 %c9 to i64
  %t11 = icmp ne i64 %t10, 0
  br i1 %t11, label %label_12, label %label_13
label_12:
  br label %label_14
label_13:
  %t15 = call i64 @Mem$memGetWord(i64 %buf, i64 0)
  %t16 = mul i64 %t15, 1000000
  %t17 = call i64 @Mem$memGetWord(i64 %buf, i64 1)
  %t18 = and i64 %t17, 4294967295
  %t19 = add i64 %t16, %t18
  br label %label_14
label_14:
  %t20 = phi i64 [ %t8, %label_12 ], [ %t19, %label_13 ]
  br label %label_6
label_5:
  %t21 = call i64 @Sys.Platform$sysClockNum()
  %t22 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t21, i64 1, i64 %buf, i64 0, i64 0, i64 0, i64 0)
  %c23 = icmp slt i64 %t22, 0
  %t24 = zext i1 %c23 to i64
  %t25 = icmp ne i64 %t24, 0
  br i1 %t25, label %label_26, label %label_27
label_26:
  br label %label_28
label_27:
  %t29 = call i64 @Mem$memGetWord(i64 %buf, i64 0)
  %t30 = mul i64 %t29, 1000000
  %t31 = call i64 @Mem$memGetWord(i64 %buf, i64 1)
  %t32 = icmp eq i64 1000, 0
  br i1 %t32, label %divzero_33, label %divok_34
divzero_33:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_34:
  %t35 = sdiv i64 %t31, 1000
  %t36 = add i64 %t30, %t35
  br label %label_28
label_28:
  %t37 = phi i64 [ %t22, %label_26 ], [ %t36, %divok_34 ]
  br label %label_6
label_6:
  %t38 = phi i64 [ %t20, %label_14 ], [ %t37, %label_28 ]
  ret i64 %t38
}
define i64 @Sys$sysNowMonotonic(i64 %buf) #0 {

  %t0 = call i64 @Sys.Platform$clockHasMonotonic()
  %c1 = icmp eq i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = sub i64 0, 78
  br label %label_6
label_5:
  %t8 = call i64 @Sys.Platform$sysClockNum()
  %t9 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t8, i64 1, i64 %buf, i64 0, i64 0, i64 0, i64 0)
  %c10 = icmp slt i64 %t9, 0
  %t11 = zext i1 %c10 to i64
  %t12 = icmp ne i64 %t11, 0
  br i1 %t12, label %label_13, label %label_14
label_13:
  br label %label_15
label_14:
  %t16 = call i64 @Mem$memGetWord(i64 %buf, i64 0)
  %t17 = mul i64 %t16, 1000000
  %t18 = call i64 @Mem$memGetWord(i64 %buf, i64 1)
  %t19 = icmp eq i64 1000, 0
  br i1 %t19, label %divzero_20, label %divok_21
divzero_20:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_21:
  %t22 = sdiv i64 %t18, 1000
  %t23 = add i64 %t17, %t22
  br label %label_15
label_15:
  %t24 = phi i64 [ %t9, %label_13 ], [ %t23, %divok_21 ]
  br label %label_6
label_6:
  %t25 = phi i64 [ %t7, %label_4 ], [ %t24, %label_15 ]
  ret i64 %t25
}
define i64 @Sys$netSocketTcp() #0 {

  %t0 = call i64 @Sys.Platform$sysSocketNum()
  %t1 = call i64 @Sys.Platform$afInet()
  %t2 = call i64 @Sys.Platform$sockStream()
  %t3 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %t1, i64 %t2, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t3
}
define i64 @Sys$netSocketTcp6() #0 {

  %t0 = call i64 @Sys.Platform$sysSocketNum()
  %t1 = call i64 @Sys.Platform$afInet6()
  %t2 = call i64 @Sys.Platform$sockStream()
  %t3 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %t1, i64 %t2, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t3
}
define i64 @Sys$netAddr4Bytes() #0 {

  ret i64 16
}
define i64 @Sys$netAddr6Bytes() #0 {

  ret i64 28
}
define i64 @Sys$netAddrMaxBytes() #0 {

  ret i64 28
}
define i64 @Sys$netAddr4(i64 %buf, i64 %port, i64 %a, i64 %b, i64 %c, i64 %d) #0 {

  %t0 = call i64 @Mem$memSet(i64 %buf, i64 0, i64 16)
  %t1 = call i64 @Sys.Platform$sockaddrHasLenByte()
  %c2 = icmp eq i64 %t1, 1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = call i64 @Mem$memPutByte(i64 %buf, i64 0, i64 16)
  %t9 = call i64 @Sys.Platform$afInet()
  %t10 = call i64 @Mem$memPutByte(i64 %buf, i64 1, i64 %t9)
  br label %label_7
label_6:
  %t11 = call i64 @Sys.Platform$afInet()
  %t12 = call i64 @Mem$memPutByte(i64 %buf, i64 0, i64 %t11)
  %t13 = call i64 @Mem$memPutByte(i64 %buf, i64 1, i64 0)
  br label %label_7
label_7:
  %t14 = phi i64 [ %t10, %label_5 ], [ %t13, %label_6 ]
  %t15 = ashr i64 %port, 8
  %t16 = and i64 %t15, 255
  %t17 = call i64 @Mem$memPutByte(i64 %buf, i64 2, i64 %t16)
  %t18 = and i64 %port, 255
  %t19 = call i64 @Mem$memPutByte(i64 %buf, i64 3, i64 %t18)
  %t20 = call i64 @Mem$memPutByte(i64 %buf, i64 4, i64 %a)
  %t21 = call i64 @Mem$memPutByte(i64 %buf, i64 5, i64 %b)
  %t22 = call i64 @Mem$memPutByte(i64 %buf, i64 6, i64 %c)
  %t23 = call i64 @Mem$memPutByte(i64 %buf, i64 7, i64 %d)
  ret i64 %buf
}
define i64 @Sys$netAddr6(i64 %buf, i64 %port, i64 %g0, i64 %g1, i64 %g2, i64 %g3, i64 %g4, i64 %g5, i64 %g6, i64 %g7) #0 {

  %t0 = call i64 @Sys$netAddr6Bytes()
  %t1 = call i64 @Mem$memSet(i64 %buf, i64 0, i64 %t0)
  %t2 = call i64 @Sys.Platform$sockaddrHasLenByte()
  %c3 = icmp eq i64 %t2, 1
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  %t9 = call i64 @Sys$netAddr6Bytes()
  %t10 = call i64 @Mem$memPutByte(i64 %buf, i64 0, i64 %t9)
  %t11 = call i64 @Sys.Platform$afInet6()
  %t12 = call i64 @Mem$memPutByte(i64 %buf, i64 1, i64 %t11)
  br label %label_8
label_7:
  %t13 = call i64 @Sys.Platform$afInet6()
  %t14 = and i64 %t13, 255
  %t15 = call i64 @Mem$memPutByte(i64 %buf, i64 0, i64 %t14)
  %t16 = call i64 @Sys.Platform$afInet6()
  %t17 = ashr i64 %t16, 8
  %t18 = and i64 %t17, 255
  %t19 = call i64 @Mem$memPutByte(i64 %buf, i64 1, i64 %t18)
  br label %label_8
label_8:
  %t20 = phi i64 [ %t12, %label_6 ], [ %t19, %label_7 ]
  %t21 = ashr i64 %port, 8
  %t22 = and i64 %t21, 255
  %t23 = call i64 @Mem$memPutByte(i64 %buf, i64 2, i64 %t22)
  %t24 = and i64 %port, 255
  %t25 = call i64 @Mem$memPutByte(i64 %buf, i64 3, i64 %t24)
  %t26 = call i64 @Sys$netPutGroup(i64 %buf, i64 0, i64 %g0)
  %t27 = call i64 @Sys$netPutGroup(i64 %buf, i64 1, i64 %g1)
  %t28 = call i64 @Sys$netPutGroup(i64 %buf, i64 2, i64 %g2)
  %t29 = call i64 @Sys$netPutGroup(i64 %buf, i64 3, i64 %g3)
  %t30 = call i64 @Sys$netPutGroup(i64 %buf, i64 4, i64 %g4)
  %t31 = call i64 @Sys$netPutGroup(i64 %buf, i64 5, i64 %g5)
  %t32 = call i64 @Sys$netPutGroup(i64 %buf, i64 6, i64 %g6)
  %t33 = call i64 @Sys$netPutGroup(i64 %buf, i64 7, i64 %g7)
  ret i64 %buf
}
define i64 @Sys$netPutGroup(i64 %buf, i64 %i, i64 %g) #0 {

  %t0 = mul i64 %i, 2
  %t1 = add i64 8, %t0
  %t2 = ashr i64 %g, 8
  %t3 = and i64 %t2, 255
  %t4 = call i64 @Mem$memPutByte(i64 %buf, i64 %t1, i64 %t3)
  %t5 = mul i64 %i, 2
  %t6 = add i64 9, %t5
  %t7 = and i64 %g, 255
  %t8 = call i64 @Mem$memPutByte(i64 %buf, i64 %t6, i64 %t7)
  ret i64 %buf
}
define i64 @Sys$netGetGroup(i64 %addr, i64 %i) #0 {

  %t0 = mul i64 %i, 2
  %t1 = add i64 8, %t0
  %t2 = call i64 @Mem$memGetByte(i64 %addr, i64 %t1)
  %t3 = shl i64 %t2, 8
  %t4 = mul i64 %i, 2
  %t5 = add i64 9, %t4
  %t6 = call i64 @Mem$memGetByte(i64 %addr, i64 %t5)
  %t7 = add i64 %t3, %t6
  ret i64 %t7
}
define i64 @Sys$netAddrFamily(i64 %addr) #0 {

  %t0 = call i64 @Sys.Platform$sockaddrHasLenByte()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Mem$memGetByte(i64 %addr, i64 1)
  br label %label_6
label_5:
  %t8 = call i64 @Mem$memGetByte(i64 %addr, i64 0)
  %t9 = call i64 @Mem$memGetByte(i64 %addr, i64 1)
  %t10 = shl i64 %t9, 8
  %t11 = add i64 %t8, %t10
  br label %label_6
label_6:
  %t12 = phi i64 [ %t7, %label_4 ], [ %t11, %label_5 ]
  ret i64 %t12
}
define i64 @Sys$netAddrPort(i64 %addr) #0 {

  %t0 = call i64 @Mem$memGetByte(i64 %addr, i64 2)
  %t1 = shl i64 %t0, 8
  %t2 = call i64 @Mem$memGetByte(i64 %addr, i64 3)
  %t3 = add i64 %t1, %t2
  ret i64 %t3
}
define i64 @Sys$netAddrSize(i64 %addr) #0 {

  %t0 = call i64 @Sys$netAddrFamily(i64 %addr)
  %t1 = call i64 @Sys.Platform$afInet6()
  %c2 = icmp eq i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = call i64 @Sys$netAddr6Bytes()
  br label %label_7
label_6:
  %t9 = call i64 @Sys$netAddr4Bytes()
  br label %label_7
label_7:
  %t10 = phi i64 [ %t8, %label_5 ], [ %t9, %label_6 ]
  ret i64 %t10
}
define i64 @Sys$netBind(i64 %fd, i64 %addr) #0 {

  %t0 = call i64 @Sys.Platform$sysBindNum()
  %t1 = call i64 @Sys$netAddrSize(i64 %addr)
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %addr, i64 %t1, i64 0, i64 0, i64 0)
  ret i64 %t2
}
define i64 @Sys$netListen(i64 %fd, i64 %backlog) #0 {

  %t0 = call i64 @Sys.Platform$sysListenNum()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %backlog, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$netAccept(i64 %fd) #0 {

  %t0 = call i64 @Sys.Platform$sysAcceptNum()
  %t1 = call i64 @Sys.Platform$acceptNonblockFlag()
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 0, i64 0, i64 %t1, i64 0, i64 0)
  %t3 = call i64 @Sys$netAcceptFinish(i64 %t2)
  ret i64 %t3
}
define i64 @Sys$netAcceptFinish(i64 %c) #0 {

  %c0 = icmp slt i64 %c, 0
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Sys.Platform$acceptNonblockFlag()
  %c7 = icmp eq i64 %t6, 0
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = call i64 @Sys$netSetNonBlocking(i64 %c)
  br label %label_12
label_11:
  br label %label_12
label_12:
  %t14 = phi i64 [ %c, %label_10 ], [ %c, %label_11 ]
  br label %label_5
label_5:
  %t15 = phi i64 [ %c, %label_3 ], [ %t14, %label_12 ]
  ret i64 %t15
}
define i64 @Sys$netAcceptFrom(i64 %fd, i64 %addr, i64 %cap, i64 %lenbuf) #0 {

  %t0 = call i64 @Mem$memSet(i64 %addr, i64 0, i64 %cap)
  %t1 = call i64 @Sys$netPutInt32(i64 %lenbuf, i64 0, i64 %cap)
  %t2 = call i64 @Sys.Platform$sysAcceptNum()
  %t3 = call i64 @Sys.Platform$acceptNonblockFlag()
  %t4 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t2, i64 %fd, i64 %addr, i64 %lenbuf, i64 %t3, i64 0, i64 0)
  %t5 = call i64 @Sys$netAcceptFinish(i64 %t4)
  %c6 = icmp sge i64 %t5, 0
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = call i64 @Sys$netAddrLenRead(i64 %lenbuf)
  %c13 = icmp sgt i64 %t12, %cap
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  %t16 = zext i1 %t15 to i64
  br label %label_11
label_10:
  br label %label_11
label_11:
  %t17 = phi i64 [ %t16, %label_9 ], [ 0, %label_10 ]
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_19, label %label_20
label_19:
  %t22 = call i64 @Mem$memSet(i64 %addr, i64 0, i64 %cap)
  br label %label_21
label_20:
  br label %label_21
label_21:
  %t23 = phi i64 [ %t22, %label_19 ], [ 0, %label_20 ]
  ret i64 %t5
}
define i64 @Sys$netAddrLenRead(i64 %lenbuf) #0 {

  %t0 = call i64 @Sys$netGetInt32(i64 %lenbuf, i64 0)
  ret i64 %t0
}
define i64 @Sys$netPutInt32(i64 %buf, i64 %off, i64 %v) #0 {

  %t0 = and i64 %v, 255
  %t1 = call i64 @Mem$memPutByte(i64 %buf, i64 %off, i64 %t0)
  %t2 = add i64 %off, 1
  %t3 = ashr i64 %v, 8
  %t4 = and i64 %t3, 255
  %t5 = call i64 @Mem$memPutByte(i64 %buf, i64 %t2, i64 %t4)
  %t6 = add i64 %off, 2
  %t7 = ashr i64 %v, 16
  %t8 = and i64 %t7, 255
  %t9 = call i64 @Mem$memPutByte(i64 %buf, i64 %t6, i64 %t8)
  %t10 = add i64 %off, 3
  %t11 = ashr i64 %v, 24
  %t12 = and i64 %t11, 255
  %t13 = call i64 @Mem$memPutByte(i64 %buf, i64 %t10, i64 %t12)
  ret i64 %buf
}
define i64 @Sys$netGetInt32(i64 %buf, i64 %off) #0 {

  %t0 = call i64 @Mem$memGetByte(i64 %buf, i64 %off)
  %t1 = add i64 %off, 1
  %t2 = call i64 @Mem$memGetByte(i64 %buf, i64 %t1)
  %t3 = shl i64 %t2, 8
  %t4 = add i64 %off, 2
  %t5 = call i64 @Mem$memGetByte(i64 %buf, i64 %t4)
  %t6 = shl i64 %t5, 16
  %t7 = add i64 %off, 3
  %t8 = call i64 @Mem$memGetByte(i64 %buf, i64 %t7)
  %t9 = shl i64 %t8, 24
  %t10 = add i64 %t6, %t9
  %t11 = add i64 %t3, %t10
  %t12 = add i64 %t0, %t11
  ret i64 %t12
}
define i64 @Sys$netAddrText(i64 %addr) #0 {

  %t0 = call i64 @Sys$netAddrFamily(i64 %addr)
  %t1 = call i64 @Sys.Platform$afInet6()
  %c2 = icmp eq i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = sub i64 0, 1
  %t9 = call i64 @Sys$netAddrZeroRunStart(i64 %addr, i64 0, i64 %t8, i64 1)
  %t10 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_4, i64 0, i32 2) to i64
  %t11 = call i64 @Sys$netAddrText6(i64 %addr, i64 0, i64 %t9, i64 %t10)
  call void @axiom_release(i64 %t10)
  br label %label_7
label_6:
  %t12 = call i64 @Sys.Platform$afInet()
  %c13 = icmp eq i64 %t0, %t12
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  br i1 %t15, label %label_16, label %label_17
label_16:
  %t19 = call i64 @Sys$netAddrText4(i64 %addr)
  br label %label_18
label_17:
  %t20 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_8, i64 0, i32 2) to i64
  %t21 = call i64 @Fmt$fmtInt(i64 %t0)
  %t22 = call i64 @Str$strConcat(i64 %t20, i64 %t21)
  call void @axiom_release(i64 %t20)
  call void @axiom_release(i64 %t21)
  br label %label_18
label_18:
  %t23 = phi i64 [ %t19, %label_16 ], [ %t22, %label_17 ]
  br label %label_7
label_7:
  %t24 = phi i64 [ %t11, %label_5 ], [ %t23, %label_18 ]
  ret i64 %t24
}
define i64 @Sys$netAddrText4(i64 %addr) #0 {

  %t0 = call i64 @Mem$memGetByte(i64 %addr, i64 4)
  %t1 = call i64 @Fmt$fmtInt(i64 %t0)
  %t2 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_3, i64 0, i32 2) to i64
  %t3 = call i64 @Str$strConcat(i64 %t1, i64 %t2)
  call void @axiom_release(i64 %t1)
  call void @axiom_release(i64 %t2)
  %t4 = call i64 @Mem$memGetByte(i64 %addr, i64 5)
  %t5 = call i64 @Fmt$fmtInt(i64 %t4)
  %t6 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_3, i64 0, i32 2) to i64
  %t7 = call i64 @Str$strConcat(i64 %t5, i64 %t6)
  call void @axiom_release(i64 %t5)
  call void @axiom_release(i64 %t6)
  %t8 = call i64 @Str$strConcat(i64 %t3, i64 %t7)
  call void @axiom_release(i64 %t3)
  call void @axiom_release(i64 %t7)
  %t9 = call i64 @Mem$memGetByte(i64 %addr, i64 6)
  %t10 = call i64 @Fmt$fmtInt(i64 %t9)
  %t11 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_3, i64 0, i32 2) to i64
  %t12 = call i64 @Str$strConcat(i64 %t10, i64 %t11)
  call void @axiom_release(i64 %t10)
  call void @axiom_release(i64 %t11)
  %t13 = call i64 @Mem$memGetByte(i64 %addr, i64 7)
  %t14 = call i64 @Fmt$fmtInt(i64 %t13)
  %t15 = call i64 @Str$strConcat(i64 %t12, i64 %t14)
  call void @axiom_release(i64 %t12)
  call void @axiom_release(i64 %t14)
  %t16 = call i64 @Str$strConcat(i64 %t8, i64 %t15)
  call void @axiom_release(i64 %t8)
  call void @axiom_release(i64 %t15)
  ret i64 %t16
}
define i64 @Sys$netAddrZeroRun(i64 %addr, i64 %i) #0 {

  %c0 = icmp sge i64 %i, 8
  %t1 = zext i1 %c0 to i64
  %t2 = icmp ne i64 %t1, 0
  br i1 %t2, label %label_3, label %label_4
label_3:
  br label %label_5
label_4:
  %t6 = call i64 @Sys$netGetGroup(i64 %addr, i64 %i)
  %c7 = icmp eq i64 %t6, 0
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = add i64 %i, 1
  %t14 = call i64 @Sys$netAddrZeroRun(i64 %addr, i64 %t13)
  %t15 = add i64 1, %t14
  br label %label_12
label_11:
  br label %label_12
label_12:
  %t16 = phi i64 [ %t15, %label_10 ], [ 0, %label_11 ]
  br label %label_5
label_5:
  %t17 = phi i64 [ 0, %label_3 ], [ %t16, %label_12 ]
  ret i64 %t17
}
define i64 @Sys$netAddrZeroRunStart(i64 %addr, i64 %i, i64 %best, i64 %bestLen) #0 {

  %s.1 = alloca i64
  store i64 %addr, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %best, ptr %s.3
  %s.4 = alloca i64
  store i64 %bestLen, ptr %s.4
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.2
  %c6 = icmp sge i64 %t5, 8
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.3
  br label %label_11
label_10:
  %t13 = load i64, ptr %s.1
  %t14 = load i64, ptr %s.2
  %t15 = call i64 @Sys$netAddrZeroRun(i64 %t13, i64 %t14)
  %t16 = load i64, ptr %s.4
  %c17 = icmp sgt i64 %t15, %t16
  %t18 = zext i1 %c17 to i64
  %t19 = icmp ne i64 %t18, 0
  br i1 %t19, label %label_20, label %label_21
label_20:
  %t23 = load i64, ptr %s.1
  %t24 = load i64, ptr %s.2
  %t25 = add i64 %t24, %t15
  %t26 = load i64, ptr %s.2
  store i64 %t23, ptr %s.1
  store i64 %t25, ptr %s.2
  store i64 %t26, ptr %s.3
  store i64 %t15, ptr %s.4
  br label %label_0
label_21:
  %t27 = load i64, ptr %s.1
  %t28 = load i64, ptr %s.2
  %c29 = icmp sgt i64 %t15, 0
  %t30 = zext i1 %c29 to i64
  %t31 = icmp ne i64 %t30, 0
  br i1 %t31, label %label_32, label %label_33
label_32:
  br label %label_34
label_33:
  br label %label_34
label_34:
  %t35 = phi i64 [ %t15, %label_32 ], [ 1, %label_33 ]
  %t36 = add i64 %t28, %t35
  %t37 = load i64, ptr %s.3
  %t38 = load i64, ptr %s.4
  store i64 %t27, ptr %s.1
  store i64 %t36, ptr %s.2
  store i64 %t37, ptr %s.3
  store i64 %t38, ptr %s.4
  br label %label_0
label_11:
  ret i64 %t12
}
define i64 @Sys$netAddrText6(i64 %addr, i64 %i, i64 %zs, i64 %acc) #0 {

  %s.1 = alloca i64
  store i64 %addr, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %zs, ptr %s.3
  %s.4 = alloca i64
  store i64 %acc, ptr %s.4
  call void @axiom_retain(i64 %acc)
  br label %label_0
label_0:
  %t5 = load i64, ptr %s.2
  %c6 = icmp sge i64 %t5, 8
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.4
  call void @axiom_retain(i64 %t12)
  br label %label_11
label_10:
  %t13 = load i64, ptr %s.2
  %t14 = load i64, ptr %s.3
  %c15 = icmp eq i64 %t13, %t14
  %t16 = zext i1 %c15 to i64
  %t17 = icmp ne i64 %t16, 0
  br i1 %t17, label %label_18, label %label_19
label_18:
  %t21 = load i64, ptr %s.1
  %t22 = load i64, ptr %s.2
  %t23 = call i64 @Sys$netAddrZeroRun(i64 %t21, i64 %t22)
  %t24 = load i64, ptr %s.1
  %t25 = load i64, ptr %s.2
  %t26 = add i64 %t25, %t23
  %t27 = load i64, ptr %s.3
  %t28 = load i64, ptr %s.4
  %t29 = load i64, ptr %s.2
  %t30 = add i64 %t29, %t23
  %c31 = icmp eq i64 %t30, 8
  %t32 = zext i1 %c31 to i64
  %t33 = icmp ne i64 %t32, 0
  br i1 %t33, label %label_34, label %label_35
label_34:
  %t37 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_9, i64 0, i32 2) to i64
  br label %label_36
label_35:
  %t38 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_10, i64 0, i32 2) to i64
  br label %label_36
label_36:
  %t39 = phi i64 [ %t37, %label_34 ], [ %t38, %label_35 ]
  %t40 = call i64 @Str$strConcat(i64 %t28, i64 %t39)
  call void @axiom_release(i64 %t39)
  call void @axiom_retain(i64 %t40)
  %t41 = load i64, ptr %s.4
  store i64 %t24, ptr %s.1
  store i64 %t26, ptr %s.2
  store i64 %t27, ptr %s.3
  store i64 %t40, ptr %s.4
  call void @axiom_release(i64 %t41)
  call void @axiom_release(i64 %t40)
  br label %label_0
label_19:
  %t42 = load i64, ptr %s.1
  %t43 = load i64, ptr %s.2
  %t44 = add i64 %t43, 1
  %t45 = load i64, ptr %s.3
  %t46 = load i64, ptr %s.2
  %c47 = icmp eq i64 %t46, 0
  %t48 = zext i1 %c47 to i64
  %t49 = icmp ne i64 %t48, 0
  br i1 %t49, label %label_50, label %label_51
label_50:
  %t53 = load i64, ptr %s.4
  br label %label_52
label_51:
  %t54 = load i64, ptr %s.4
  %t55 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_10, i64 0, i32 2) to i64
  %t56 = call i64 @Str$strConcat(i64 %t54, i64 %t55)
  call void @axiom_release(i64 %t55)
  br label %label_52
label_52:
  %t57 = phi i64 [ %t53, %label_50 ], [ %t56, %label_51 ]
  %t58 = load i64, ptr %s.1
  %t59 = load i64, ptr %s.2
  %t60 = call i64 @Sys$netGetGroup(i64 %t58, i64 %t59)
  %t61 = call i64 @Fmt$fmtHex(i64 %t60)
  %t62 = call i64 @Str$strConcat(i64 %t57, i64 %t61)
  call void @axiom_release(i64 %t61)
  call void @axiom_retain(i64 %t62)
  %t63 = load i64, ptr %s.4
  store i64 %t42, ptr %s.1
  store i64 %t44, ptr %s.2
  store i64 %t45, ptr %s.3
  store i64 %t62, ptr %s.4
  call void @axiom_release(i64 %t63)
  call void @axiom_release(i64 %t62)
  br label %label_0
label_11:
  %t64 = load i64, ptr %s.4
  call void @axiom_release(i64 %t64)
  ret i64 %t12
}
define i64 @Sys$netAddrTextPort(i64 %addr) #0 {

  %t0 = call i64 @Sys$netAddrFamily(i64 %addr)
  %t1 = call i64 @Sys.Platform$afInet6()
  %c2 = icmp eq i64 %t0, %t1
  %t3 = zext i1 %c2 to i64
  %t4 = icmp ne i64 %t3, 0
  br i1 %t4, label %label_5, label %label_6
label_5:
  %t8 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_11, i64 0, i32 2) to i64
  %t9 = call i64 @Sys$netAddrText(i64 %addr)
  %t10 = call i64 @Str$strConcat(i64 %t8, i64 %t9)
  call void @axiom_release(i64 %t8)
  call void @axiom_release(i64 %t9)
  %t11 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_12, i64 0, i32 2) to i64
  %t12 = call i64 @Sys$netAddrPort(i64 %addr)
  %t13 = call i64 @Fmt$fmtInt(i64 %t12)
  %t14 = call i64 @Str$strConcat(i64 %t11, i64 %t13)
  call void @axiom_release(i64 %t11)
  call void @axiom_release(i64 %t13)
  %t15 = call i64 @Str$strConcat(i64 %t10, i64 %t14)
  call void @axiom_release(i64 %t10)
  call void @axiom_release(i64 %t14)
  br label %label_7
label_6:
  %t16 = call i64 @Sys$netAddrText(i64 %addr)
  %t17 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_10, i64 0, i32 2) to i64
  %t18 = call i64 @Sys$netAddrPort(i64 %addr)
  %t19 = call i64 @Fmt$fmtInt(i64 %t18)
  %t20 = call i64 @Str$strConcat(i64 %t17, i64 %t19)
  call void @axiom_release(i64 %t17)
  call void @axiom_release(i64 %t19)
  %t21 = call i64 @Str$strConcat(i64 %t16, i64 %t20)
  call void @axiom_release(i64 %t16)
  call void @axiom_release(i64 %t20)
  br label %label_7
label_7:
  %t22 = phi i64 [ %t15, %label_5 ], [ %t21, %label_6 ]
  ret i64 %t22
}
define i64 @Sys$netSetBlocking(i64 %fd) #0 {

  %t0 = call i64 @Sys.Platform$sysFcntlNum()
  %t1 = call i64 @Sys.Platform$fGetFl()
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %t1, i64 0, i64 0, i64 0, i64 0)
  %c3 = icmp slt i64 %t2, 0
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  br label %label_8
label_7:
  %t9 = call i64 @Sys.Platform$sysFcntlNum()
  %t10 = call i64 @Sys.Platform$fSetFl()
  %t11 = call i64 @Sys.Platform$oNonblock()
  %t12 = sub i64 0, 1
  %t13 = xor i64 %t11, %t12
  %t14 = and i64 %t2, %t13
  %t15 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t9, i64 %fd, i64 %t10, i64 %t14, i64 0, i64 0, i64 0)
  br label %label_8
label_8:
  %t16 = phi i64 [ %t2, %label_6 ], [ %t15, %label_7 ]
  ret i64 %t16
}
define i64 @Sys$netConnect(i64 %fd, i64 %addr) #0 {

  %t0 = call i64 @Sys.Platform$sysConnectNum()
  %t1 = call i64 @Sys$netAddrSize(i64 %addr)
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %addr, i64 %t1, i64 0, i64 0, i64 0)
  ret i64 %t2
}
define i64 @Sys$netShutdown(i64 %fd, i64 %how) #0 {

  %t0 = call i64 @Sys.Platform$sysShutdownNum()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %how, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$netSetOptInt(i64 %fd, i64 %level, i64 %name, i64 %value, i64 %v) #0 {

  %t0 = call i64 @Sys$netPutInt32(i64 %v, i64 0, i64 %value)
  %t1 = call i64 @Sys.Platform$sysSetSockOptNum()
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t1, i64 %fd, i64 %level, i64 %name, i64 %v, i64 4, i64 0)
  ret i64 %t2
}
define i64 @Sys$netSetNonBlocking(i64 %fd) #0 {

  %t0 = call i64 @Sys.Platform$sysFcntlNum()
  %t1 = call i64 @Sys.Platform$fGetFl()
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %fd, i64 %t1, i64 0, i64 0, i64 0, i64 0)
  %c3 = icmp slt i64 %t2, 0
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  br label %label_8
label_7:
  %t9 = call i64 @Sys.Platform$sysFcntlNum()
  %t10 = call i64 @Sys.Platform$fSetFl()
  %t11 = call i64 @Sys.Platform$oNonblock()
  %t12 = or i64 %t2, %t11
  %t13 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t9, i64 %fd, i64 %t10, i64 %t12, i64 0, i64 0, i64 0)
  br label %label_8
label_8:
  %t14 = phi i64 [ %t2, %label_6 ], [ %t13, %label_7 ]
  ret i64 %t14
}
define i64 @Sys$netWouldBlock(i64 %r) #0 {

  %t0 = call i64 @Sys.Platform$eAgain()
  %t1 = sub i64 0, %t0
  %c2 = icmp eq i64 %r, %t1
  %t3 = zext i1 %c2 to i64
  ret i64 %t3
}
define i64 @Sys$netPutWord(i64 %buf, i64 %off, i64 %v) #0 {

  %t0 = and i64 %v, 255
  %t1 = call i64 @Mem$memPutByte(i64 %buf, i64 %off, i64 %t0)
  %t2 = add i64 %off, 1
  %t3 = ashr i64 %v, 8
  %t4 = and i64 %t3, 255
  %t5 = call i64 @Mem$memPutByte(i64 %buf, i64 %t2, i64 %t4)
  %t6 = add i64 %off, 2
  %t7 = ashr i64 %v, 16
  %t8 = and i64 %t7, 255
  %t9 = call i64 @Mem$memPutByte(i64 %buf, i64 %t6, i64 %t8)
  %t10 = add i64 %off, 3
  %t11 = ashr i64 %v, 24
  %t12 = and i64 %t11, 255
  %t13 = call i64 @Mem$memPutByte(i64 %buf, i64 %t10, i64 %t12)
  %t14 = add i64 %off, 4
  %t15 = ashr i64 %v, 32
  %t16 = and i64 %t15, 255
  %t17 = call i64 @Mem$memPutByte(i64 %buf, i64 %t14, i64 %t16)
  %t18 = add i64 %off, 5
  %t19 = ashr i64 %v, 40
  %t20 = and i64 %t19, 255
  %t21 = call i64 @Mem$memPutByte(i64 %buf, i64 %t18, i64 %t20)
  %t22 = add i64 %off, 6
  %t23 = ashr i64 %v, 48
  %t24 = and i64 %t23, 255
  %t25 = call i64 @Mem$memPutByte(i64 %buf, i64 %t22, i64 %t24)
  %t26 = add i64 %off, 7
  %t27 = ashr i64 %v, 56
  %t28 = and i64 %t27, 255
  %t29 = call i64 @Mem$memPutByte(i64 %buf, i64 %t26, i64 %t28)
  ret i64 %buf
}
define i64 @Sys$netGetWord(i64 %buf, i64 %off) #0 {

  %t0 = call i64 @Mem$memGetByte(i64 %buf, i64 %off)
  %t1 = add i64 %off, 1
  %t2 = call i64 @Mem$memGetByte(i64 %buf, i64 %t1)
  %t3 = shl i64 %t2, 8
  %t4 = add i64 %off, 2
  %t5 = call i64 @Mem$memGetByte(i64 %buf, i64 %t4)
  %t6 = shl i64 %t5, 16
  %t7 = add i64 %off, 3
  %t8 = call i64 @Mem$memGetByte(i64 %buf, i64 %t7)
  %t9 = shl i64 %t8, 24
  %t10 = add i64 %off, 4
  %t11 = call i64 @Mem$memGetByte(i64 %buf, i64 %t10)
  %t12 = shl i64 %t11, 32
  %t13 = add i64 %off, 5
  %t14 = call i64 @Mem$memGetByte(i64 %buf, i64 %t13)
  %t15 = shl i64 %t14, 40
  %t16 = add i64 %off, 6
  %t17 = call i64 @Mem$memGetByte(i64 %buf, i64 %t16)
  %t18 = shl i64 %t17, 48
  %t19 = add i64 %off, 7
  %t20 = call i64 @Mem$memGetByte(i64 %buf, i64 %t19)
  %t21 = shl i64 %t20, 56
  %t22 = add i64 %t18, %t21
  %t23 = add i64 %t15, %t22
  %t24 = add i64 %t12, %t23
  %t25 = add i64 %t9, %t24
  %t26 = add i64 %t6, %t25
  %t27 = add i64 %t3, %t26
  %t28 = add i64 %t0, %t27
  ret i64 %t28
}
define i64 @Sys$netPollBufBytes(i64 %n) #0 {

  %t0 = call i64 @Sys.Platform$pollEventSize()
  %t1 = mul i64 %n, %t0
  ret i64 %t1
}
define i64 @Sys$netPollCreate() #0 {

  %t0 = call i64 @Sys.Platform$sysPollCreateNum()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$netPollRec(i64 %rec, i64 %fd, i64 %op) #0 {

  %t0 = call i64 @Sys.Platform$pollEventSize()
  %t1 = call i64 @Mem$memSet(i64 %rec, i64 0, i64 %t0)
  %t2 = call i64 @Sys.Platform$pollUsesKqueue()
  %c3 = icmp eq i64 %t2, 1
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  %t9 = call i64 @Sys$netPutWord(i64 %rec, i64 0, i64 %fd)
  %t10 = call i64 @Sys.Platform$pollReadFilter()
  %t11 = and i64 %t10, 255
  %t12 = call i64 @Mem$memPutByte(i64 %rec, i64 8, i64 %t11)
  %t13 = call i64 @Sys.Platform$pollReadFilter()
  %t14 = ashr i64 %t13, 8
  %t15 = and i64 %t14, 255
  %t16 = call i64 @Mem$memPutByte(i64 %rec, i64 9, i64 %t15)
  %t17 = and i64 %op, 255
  %t18 = call i64 @Mem$memPutByte(i64 %rec, i64 10, i64 %t17)
  %t19 = ashr i64 %op, 8
  %t20 = and i64 %t19, 255
  %t21 = call i64 @Mem$memPutByte(i64 %rec, i64 11, i64 %t20)
  br label %label_8
label_7:
  %t22 = call i64 @Sys.Platform$pollReadFilter()
  %t23 = call i64 @Sys$netPutWord(i64 %rec, i64 0, i64 %t22)
  %t24 = call i64 @Sys.Platform$pollEventFdOffset()
  %t25 = call i64 @Sys$netPutWord(i64 %rec, i64 %t24, i64 %fd)
  br label %label_8
label_8:
  %t26 = phi i64 [ %t21, %label_6 ], [ %t25, %label_7 ]
  ret i64 %rec
}
define i64 @Sys$netPollAddRead(i64 %pfd, i64 %fd, i64 %rec) #0 {

  %t0 = call i64 @Sys.Platform$pollAddOp()
  %t1 = call i64 @Sys$netPollRec(i64 %rec, i64 %fd, i64 %t0)
  %t2 = call i64 @Sys.Platform$pollUsesKqueue()
  %c3 = icmp eq i64 %t2, 1
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  %t9 = call i64 @Sys.Platform$sysPollWaitNum()
  %t10 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t9, i64 %pfd, i64 %rec, i64 1, i64 0, i64 0, i64 0)
  br label %label_8
label_7:
  %t11 = call i64 @Sys.Platform$sysPollCtlNum()
  %t12 = call i64 @Sys.Platform$pollAddOp()
  %t13 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t11, i64 %pfd, i64 %t12, i64 %fd, i64 %rec, i64 0, i64 0)
  br label %label_8
label_8:
  %t14 = phi i64 [ %t10, %label_6 ], [ %t13, %label_7 ]
  ret i64 %t14
}
define i64 @Sys$netPollDelRead(i64 %pfd, i64 %fd, i64 %rec) #0 {

  %t0 = call i64 @Sys.Platform$pollDelOp()
  %t1 = call i64 @Sys$netPollRec(i64 %rec, i64 %fd, i64 %t0)
  %t2 = call i64 @Sys.Platform$pollUsesKqueue()
  %c3 = icmp eq i64 %t2, 1
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  %t9 = call i64 @Sys.Platform$sysPollWaitNum()
  %t10 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t9, i64 %pfd, i64 %rec, i64 1, i64 0, i64 0, i64 0)
  br label %label_8
label_7:
  %t11 = call i64 @Sys.Platform$sysPollCtlNum()
  %t12 = call i64 @Sys.Platform$pollDelOp()
  %t13 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t11, i64 %pfd, i64 %t12, i64 %fd, i64 %rec, i64 0, i64 0)
  br label %label_8
label_8:
  %t14 = phi i64 [ %t10, %label_6 ], [ %t13, %label_7 ]
  ret i64 %t14
}
define i64 @Sys$netPollWait(i64 %pfd, i64 %buf, i64 %maxEvents, i64 %timeoutMs, i64 %ts) #0 {

  %t0 = call i64 @Sys.Platform$pollUsesKqueue()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %c7 = icmp slt i64 %timeoutMs, 0
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  %t13 = call i64 @Sys.Platform$sysPollWaitNum()
  %t14 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t13, i64 %pfd, i64 0, i64 0, i64 %buf, i64 %maxEvents, i64 0)
  br label %label_12
label_11:
  %t15 = icmp eq i64 1000, 0
  br i1 %t15, label %divzero_16, label %divok_17
divzero_16:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_17:
  %t18 = sdiv i64 %timeoutMs, 1000
  %t19 = call i64 @Sys$netPutWord(i64 %ts, i64 0, i64 %t18)
  %t20 = icmp eq i64 1000, 0
  br i1 %t20, label %divzero_21, label %divok_22
divzero_21:
  call i64 @__axiom_div_by_zero()
  unreachable
divok_22:
  %t23 = srem i64 %timeoutMs, 1000
  %t24 = mul i64 %t23, 1000000
  %t25 = call i64 @Sys$netPutWord(i64 %ts, i64 8, i64 %t24)
  %t26 = call i64 @Sys.Platform$sysPollWaitNum()
  %t27 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t26, i64 %pfd, i64 0, i64 0, i64 %buf, i64 %maxEvents, i64 %ts)
  br label %label_12
label_12:
  %t28 = phi i64 [ %t14, %label_10 ], [ %t27, %divok_22 ]
  br label %label_6
label_5:
  %t29 = call i64 @Sys.Platform$sysPollWaitNum()
  %t30 = call i64 @Sys.Platform$pollSigsetSize()
  %t31 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t29, i64 %pfd, i64 %buf, i64 %maxEvents, i64 %timeoutMs, i64 0, i64 %t30)
  br label %label_6
label_6:
  %t32 = phi i64 [ %t28, %label_12 ], [ %t31, %label_5 ]
  ret i64 %t32
}
define i64 @Sys$netPollFdAt(i64 %buf, i64 %i) #0 {

  %t0 = call i64 @Sys.Platform$pollEventSize()
  %t1 = mul i64 %i, %t0
  %t2 = call i64 @Sys.Platform$pollEventFdOffset()
  %t3 = add i64 %t1, %t2
  %t4 = call i64 @Sys$netGetWord(i64 %buf, i64 %t3)
  ret i64 %t4
}
define i64 @Sys$sysRandomBytes(i64 %buf, i64 %n) #0 {
  %s.0 = alloca i64
  %s.1 = alloca i64
  store i64 0, ptr %s.0
  store i64 0, ptr %s.1
  br label %label_2
label_2:
  %t5 = load i64, ptr %s.0
  %c6 = icmp slt i64 %t5, %n
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  %c13 = icmp eq i64 %t12, 0
  %t14 = zext i1 %c13 to i64
  %t15 = icmp ne i64 %t14, 0
  %t16 = zext i1 %t15 to i64
  br label %label_11
label_10:
  br label %label_11
label_11:
  %t17 = phi i64 [ %t16, %label_9 ], [ 0, %label_10 ]
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_3, label %label_4
label_3:
  %t19 = load i64, ptr %s.0
  %t20 = sub i64 %n, %t19
  %t21 = call i64 @Sys.Platform$randomMaxChunk()
  %c22 = icmp sgt i64 %t20, %t21
  %t23 = zext i1 %c22 to i64
  %t24 = icmp ne i64 %t23, 0
  br i1 %t24, label %label_25, label %label_26
label_25:
  %t28 = call i64 @Sys.Platform$randomMaxChunk()
  br label %label_27
label_26:
  %t29 = load i64, ptr %s.0
  %t30 = sub i64 %n, %t29
  br label %label_27
label_27:
  %t31 = phi i64 [ %t28, %label_25 ], [ %t30, %label_26 ]
  %t32 = call i64 @Sys.Platform$sysRandomNum()
  %t33 = load i64, ptr %s.0
  %t34 = add i64 %buf, %t33
  %t35 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t32, i64 %t34, i64 %t31, i64 0, i64 0, i64 0, i64 0)
  %c36 = icmp slt i64 %t35, 0
  %t37 = zext i1 %c36 to i64
  %t38 = icmp ne i64 %t37, 0
  br i1 %t38, label %label_39, label %label_40
label_39:
  store i64 %t35, ptr %s.1
  br label %label_41
label_40:
  %t42 = call i64 @Sys.Platform$randomIsGetentropy()
  %c43 = icmp eq i64 %t42, 1
  %t44 = zext i1 %c43 to i64
  %t45 = icmp ne i64 %t44, 0
  br i1 %t45, label %label_46, label %label_47
label_46:
  %t49 = load i64, ptr %s.0
  %t50 = add i64 %t49, %t31
  store i64 %t50, ptr %s.0
  br label %label_48
label_47:
  %c51 = icmp eq i64 %t35, 0
  %t52 = zext i1 %c51 to i64
  %t53 = icmp ne i64 %t52, 0
  br i1 %t53, label %label_54, label %label_55
label_54:
  %t57 = sub i64 0, 1
  store i64 %t57, ptr %s.1
  br label %label_56
label_55:
  %t58 = load i64, ptr %s.0
  %t59 = add i64 %t58, %t35
  store i64 %t59, ptr %s.0
  br label %label_56
label_56:
  %t60 = phi i64 [ %t57, %label_54 ], [ %t59, %label_55 ]
  br label %label_48
label_48:
  %t61 = phi i64 [ %t50, %label_46 ], [ %t60, %label_56 ]
  br label %label_41
label_41:
  %t62 = phi i64 [ %t35, %label_39 ], [ %t61, %label_48 ]
  br label %label_2
label_4:
  %t63 = load i64, ptr %s.1
  %c64 = icmp slt i64 %t63, 0
  %t65 = zext i1 %c64 to i64
  %t66 = icmp ne i64 %t65, 0
  br i1 %t66, label %label_67, label %label_68
label_67:
  %t70 = load i64, ptr %s.1
  br label %label_69
label_68:
  br label %label_69
label_69:
  %t71 = phi i64 [ %t70, %label_67 ], [ 0, %label_68 ]
  ret i64 %t71
}
define i64 @Sys$sysSigBit(i64 %signo) #0 {

  %t0 = sub i64 %signo, 1
  %t1 = shl i64 1, %t0
  ret i64 %t1
}
define i64 @Sys$sysSignalBlock(i64 %mask, i64 %setbuf) #0 {

  %t0 = call i64 @Sys$netPutWord(i64 %setbuf, i64 0, i64 %mask)
  %t1 = call i64 @Sys.Platform$sysSigProcMaskNum()
  %t2 = call i64 @Sys.Platform$sigBlockHow()
  %t3 = call i64 @Sys.Platform$sigsetBytes()
  %t4 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t1, i64 %t2, i64 %setbuf, i64 0, i64 %t3, i64 0, i64 0)
  ret i64 %t4
}
define i64 @Sys$netSignalOpen(i64 %pfd, i64 %mask, i64 %rec, i64 %setbuf) #0 {
  %s.31 = alloca i64
  %s.32 = alloca i64
  %t0 = call i64 @Sys.Platform$signalUsesSignalFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys$netPutWord(i64 %setbuf, i64 0, i64 %mask)
  %t8 = call i64 @Sys.Platform$sysSignalFdNum()
  %t9 = sub i64 0, 1
  %t10 = call i64 @Sys.Platform$sigsetBytes()
  %t11 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t8, i64 %t9, i64 %setbuf, i64 %t10, i64 0, i64 0, i64 0)
  %c12 = icmp slt i64 %t11, 0
  %t13 = zext i1 %c12 to i64
  %t14 = icmp ne i64 %t13, 0
  br i1 %t14, label %label_15, label %label_16
label_15:
  br label %label_17
label_16:
  %t18 = call i64 @Sys.Platform$pollAddOp()
  %t19 = call i64 @Sys$netPollRec(i64 %rec, i64 %t11, i64 %t18)
  %t20 = call i64 @Sys.Platform$sysPollCtlNum()
  %t21 = call i64 @Sys.Platform$pollAddOp()
  %t22 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t20, i64 %pfd, i64 %t21, i64 %t11, i64 %rec, i64 0, i64 0)
  %c23 = icmp slt i64 %t22, 0
  %t24 = zext i1 %c23 to i64
  %t25 = icmp ne i64 %t24, 0
  br i1 %t25, label %label_26, label %label_27
label_26:
  br label %label_28
label_27:
  br label %label_28
label_28:
  %t29 = phi i64 [ %t22, %label_26 ], [ %t11, %label_27 ]
  br label %label_17
label_17:
  %t30 = phi i64 [ %t11, %label_15 ], [ %t29, %label_28 ]
  br label %label_6
label_5:
  store i64 1, ptr %s.31
  store i64 0, ptr %s.32
  br label %label_33
label_33:
  %t36 = load i64, ptr %s.31
  %c37 = icmp slt i64 %t36, 32
  %t38 = zext i1 %c37 to i64
  %t39 = icmp ne i64 %t38, 0
  br i1 %t39, label %label_34, label %label_35
label_34:
  %t40 = load i64, ptr %s.31
  %t41 = call i64 @Sys$sysSigBit(i64 %t40)
  %t42 = and i64 %mask, %t41
  %c43 = icmp ne i64 %t42, 0
  %t44 = zext i1 %c43 to i64
  %t45 = icmp ne i64 %t44, 0
  br i1 %t45, label %label_46, label %label_47
label_46:
  %t49 = call i64 @Sys.Platform$pollEventSize()
  %t50 = call i64 @Mem$memSet(i64 %rec, i64 0, i64 %t49)
  %t51 = load i64, ptr %s.31
  %t52 = call i64 @Sys$netPutWord(i64 %rec, i64 0, i64 %t51)
  %t53 = call i64 @Sys.Platform$pollSignalFilter()
  %t54 = and i64 %t53, 255
  %t55 = call i64 @Mem$memPutByte(i64 %rec, i64 8, i64 %t54)
  %t56 = call i64 @Sys.Platform$pollSignalFilter()
  %t57 = ashr i64 %t56, 8
  %t58 = and i64 %t57, 255
  %t59 = call i64 @Mem$memPutByte(i64 %rec, i64 9, i64 %t58)
  %t60 = call i64 @Sys.Platform$pollAddOp()
  %t61 = and i64 %t60, 255
  %t62 = call i64 @Mem$memPutByte(i64 %rec, i64 10, i64 %t61)
  %t63 = call i64 @Mem$memPutByte(i64 %rec, i64 11, i64 0)
  %t64 = call i64 @Sys.Platform$sysPollWaitNum()
  %t65 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t64, i64 %pfd, i64 %rec, i64 1, i64 0, i64 0, i64 0)
  %c66 = icmp slt i64 %t65, 0
  %t67 = zext i1 %c66 to i64
  %t68 = icmp ne i64 %t67, 0
  br i1 %t68, label %label_69, label %label_70
label_69:
  store i64 %t65, ptr %s.32
  br label %label_71
label_70:
  br label %label_71
label_71:
  %t72 = phi i64 [ %t65, %label_69 ], [ 0, %label_70 ]
  br label %label_48
label_47:
  br label %label_48
label_48:
  %t73 = phi i64 [ %t72, %label_71 ], [ 0, %label_47 ]
  %t74 = load i64, ptr %s.31
  %t75 = add i64 %t74, 1
  store i64 %t75, ptr %s.31
  br label %label_33
label_35:
  %t76 = load i64, ptr %s.32
  br label %label_6
label_6:
  %t77 = phi i64 [ %t30, %label_17 ], [ %t76, %label_35 ]
  ret i64 %t77
}
define i64 @Sys$netPollSignalAt(i64 %buf, i64 %i, i64 %sigHandle, i64 %scratch) #0 {

  %t0 = call i64 @Sys.Platform$signalUsesSignalFd()
  %c1 = icmp eq i64 %t0, 1
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = call i64 @Sys$netPollFdAt(i64 %buf, i64 %i)
  %c8 = icmp ne i64 %t7, %sigHandle
  %t9 = zext i1 %c8 to i64
  %t10 = icmp ne i64 %t9, 0
  br i1 %t10, label %label_11, label %label_12
label_11:
  %t14 = sub i64 0, 1
  br label %label_13
label_12:
  %t15 = call i64 @Sys.Platform$sysRead()
  %t16 = call i64 @Sys.Platform$sigInfoSize()
  %t17 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t15, i64 %sigHandle, i64 %scratch, i64 %t16, i64 0, i64 0, i64 0)
  %t18 = call i64 @Sys.Platform$sigInfoSize()
  %c19 = icmp slt i64 %t17, %t18
  %t20 = zext i1 %c19 to i64
  %t21 = icmp ne i64 %t20, 0
  br i1 %t21, label %label_22, label %label_23
label_22:
  %t25 = sub i64 0, 1
  br label %label_24
label_23:
  %t26 = call i64 @Mem$memGetByte(i64 %scratch, i64 0)
  %t27 = call i64 @Mem$memGetByte(i64 %scratch, i64 1)
  %t28 = shl i64 %t27, 8
  %t29 = call i64 @Mem$memGetByte(i64 %scratch, i64 2)
  %t30 = shl i64 %t29, 16
  %t31 = call i64 @Mem$memGetByte(i64 %scratch, i64 3)
  %t32 = shl i64 %t31, 24
  %t33 = add i64 %t30, %t32
  %t34 = add i64 %t28, %t33
  %t35 = add i64 %t26, %t34
  br label %label_24
label_24:
  %t36 = phi i64 [ %t25, %label_22 ], [ %t35, %label_23 ]
  br label %label_13
label_13:
  %t37 = phi i64 [ %t14, %label_11 ], [ %t36, %label_24 ]
  br label %label_6
label_5:
  %t38 = call i64 @Sys.Platform$pollEventSize()
  %t39 = mul i64 %i, %t38
  %t40 = add i64 %t39, 8
  %t41 = call i64 @Mem$memGetByte(i64 %buf, i64 %t40)
  %t42 = call i64 @Sys.Platform$pollSignalFilter()
  %t43 = and i64 %t42, 255
  %c44 = icmp eq i64 %t41, %t43
  %t45 = zext i1 %c44 to i64
  %t46 = icmp ne i64 %t45, 0
  br i1 %t46, label %label_47, label %label_48
label_47:
  %t50 = add i64 %t39, 9
  %t51 = call i64 @Mem$memGetByte(i64 %buf, i64 %t50)
  %t52 = call i64 @Sys.Platform$pollSignalFilter()
  %t53 = ashr i64 %t52, 8
  %t54 = and i64 %t53, 255
  %c55 = icmp eq i64 %t51, %t54
  %t56 = zext i1 %c55 to i64
  %t57 = icmp ne i64 %t56, 0
  br i1 %t57, label %label_58, label %label_59
label_58:
  %t61 = call i64 @Sys$netPollFdAt(i64 %buf, i64 %i)
  br label %label_60
label_59:
  %t62 = sub i64 0, 1
  br label %label_60
label_60:
  %t63 = phi i64 [ %t61, %label_58 ], [ %t62, %label_59 ]
  br label %label_49
label_48:
  %t64 = sub i64 0, 1
  br label %label_49
label_49:
  %t65 = phi i64 [ %t63, %label_60 ], [ %t64, %label_48 ]
  br label %label_6
label_6:
  %t66 = phi i64 [ %t37, %label_13 ], [ %t65, %label_49 ]
  ret i64 %t66
}
define i64 @Sys$sysKill(i64 %pid, i64 %signo) #0 {

  %t0 = call i64 @Sys.Platform$sysKillNum()
  %t1 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %pid, i64 %signo, i64 0, i64 0, i64 0, i64 0)
  ret i64 %t1
}
define i64 @Sys$sysForkProcess() #0 {

  %t0 = call i64 @Sys.Platform$sysFork()
  %t1 = call i64 @Sys.Platform$sysForkArg()
  %t2 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t0, i64 %t1, i64 0, i64 0, i64 0, i64 0, i64 0)
  %c3 = icmp slt i64 %t2, 0
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  br label %label_8
label_7:
  %t9 = call i64 @Sys.Platform$forkChildIsZero()
  %c10 = icmp eq i64 %t9, 1
  %t11 = zext i1 %c10 to i64
  %t12 = icmp ne i64 %t11, 0
  br i1 %t12, label %label_13, label %label_14
label_13:
  br label %label_15
label_14:
  %t16 = call i64 @Sys.Platform$sysGetPidNum()
  %t17 = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 %t16, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0)
  %c18 = icmp eq i64 %t2, %t17
  %t19 = zext i1 %c18 to i64
  %t20 = icmp ne i64 %t19, 0
  br i1 %t20, label %label_21, label %label_22
label_21:
  br label %label_23
label_22:
  br label %label_23
label_23:
  %t24 = phi i64 [ 0, %label_21 ], [ %t2, %label_22 ]
  br label %label_15
label_15:
  %t25 = phi i64 [ %t2, %label_13 ], [ %t24, %label_23 ]
  br label %label_8
label_8:
  %t26 = phi i64 [ %t2, %label_6 ], [ %t25, %label_15 ]
  ret i64 %t26
}
define i64 @IO$writeStr(i64 %fd, i64 %s) #0 {

  %t0 = call i64 @Str$strData(i64 %s)
  %t1 = call i64 @Str$strLen(i64 %s)
  %t2 = call i64 @Sys$sysWriteAllFd(i64 %fd, i64 %t0, i64 %t1, i64 0)
  ret i64 %t2
}
define i64 @IO$printLit(i64 %cstr) #0 {

  %t0 = call i64 @Sys$stdout()
  %t1 = call i64 @Str$cstrLen(i64 %cstr, i64 0)
  %t2 = call i64 @Sys$sysWriteAllFd(i64 %t0, i64 %cstr, i64 %t1, i64 0)
  ret i64 %t2
}
define i64 @IO$printlnLit(i64 %cstr) #0 {

  %t0 = call i64 @IO$printLit(i64 %cstr)
  %t1 = ptrtoint ptr @str_13 to i64
  %t2 = call i64 @IO$printLit(i64 %t1)
  ret i64 %t2
}
define i64 @IO$readFileLit(i64 %cstr) #0 {

  %t0 = call i64 @Sys$sysReadFile(i64 %cstr)
  ret i64 %t0
}
define i64 @IO$readFile(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @IO$readFileLit(i64 %t0)
  ret i64 %t1
}
define i64 @IO$ioPath(i64 %path) #0 {

  %t0 = call i64 @Str$strDup(i64 %path)
  %t1 = call i64 @Str$strCStr(i64 %t0)
  ret i64 %t1
}
define i64 @IO$writeFile(i64 %path, i64 %s) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysWriteFile(i64 %t0, i64 %s)
  ret i64 %t1
}
define i64 @IO$appendFile(i64 %path, i64 %s) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysAppendFile(i64 %t0, i64 %s)
  ret i64 %t1
}
define i64 @IO$removeFile(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysUnlink(i64 %t0)
  ret i64 %t1
}
define i64 @IO$renamePath(i64 %old, i64 %new) #0 {

  %t0 = call i64 @IO$ioPath(i64 %old)
  %t1 = call i64 @IO$ioPath(i64 %new)
  %t2 = call i64 @Sys$sysRename(i64 %t0, i64 %t1)
  ret i64 %t2
}
define i64 @IO$copyFile(i64 %src, i64 %dst) #0 {

  %t0 = call i64 @IO$readErrno(i64 %src)
  %c1 = icmp ne i64 %t0, 0
  %t2 = zext i1 %c1 to i64
  %t3 = icmp ne i64 %t2, 0
  br i1 %t3, label %label_4, label %label_5
label_4:
  %t7 = sub i64 0, %t0
  br label %label_6
label_5:
  %t8 = call i64 @IO$readFile(i64 %src)
  %t9 = call i64 @IO$writeFile(i64 %dst, i64 %t8)
  br label %label_6
label_6:
  %t10 = phi i64 [ %t7, %label_4 ], [ %t9, %label_5 ]
  ret i64 %t10
}
define i64 @IO$fileExists(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysFileExists(i64 %t0)
  ret i64 %t1
}
define i64 @IO$isDir(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysIsDir(i64 %t0)
  ret i64 %t1
}
define i64 @IO$fileSize(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysFileSize(i64 %t0)
  ret i64 %t1
}
define i64 @IO$readErrno(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysReadErrno(i64 %t0)
  ret i64 %t1
}
define i64 @IO$makeDir(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysDirMode()
  %t2 = call i64 @Sys$sysMkdir(i64 %t0, i64 %t1)
  ret i64 %t2
}
define i64 @IO$makeDirAll(i64 %path) #0 {

  %t0 = call i64 @IO$makeDirAllFrom(i64 %path, i64 1)
  ret i64 %t0
}
define i64 @IO$makeDirAllFrom(i64 %path, i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %path, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  call void @axiom_retain(i64 %path)
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.2
  %t4 = load i64, ptr %s.1
  %t5 = call i64 @Str$strLen(i64 %t4)
  %c6 = icmp sge i64 %t3, %t5
  %t7 = zext i1 %c6 to i64
  %t8 = icmp ne i64 %t7, 0
  br i1 %t8, label %label_9, label %label_10
label_9:
  %t12 = load i64, ptr %s.1
  %t13 = call i64 @IO$makeDirOk(i64 %t12)
  br label %label_11
label_10:
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = call i64 @Str$strByte(i64 %t14, i64 %t15)
  %c17 = icmp eq i64 %t16, 47
  %t18 = zext i1 %c17 to i64
  %t19 = icmp ne i64 %t18, 0
  br i1 %t19, label %label_20, label %label_21
label_20:
  %t23 = load i64, ptr %s.1
  %t24 = load i64, ptr %s.2
  %t25 = call i64 @Str$strSlice(i64 %t23, i64 0, i64 %t24)
  %t26 = call i64 @IO$makeDirOk(i64 %t25)
  call void @axiom_release(i64 %t25)
  %c27 = icmp slt i64 %t26, 0
  %t28 = zext i1 %c27 to i64
  %t29 = icmp ne i64 %t28, 0
  br i1 %t29, label %label_30, label %label_31
label_30:
  br label %label_32
label_31:
  %t33 = load i64, ptr %s.1
  %t34 = load i64, ptr %s.2
  %t35 = add i64 %t34, 1
  %t36 = load i64, ptr %s.1
  store i64 %t33, ptr %s.1
  store i64 %t35, ptr %s.2
  br label %label_0
label_32:
  br label %label_22
label_21:
  %t37 = load i64, ptr %s.1
  %t38 = load i64, ptr %s.2
  %t39 = add i64 %t38, 1
  %t40 = load i64, ptr %s.1
  store i64 %t37, ptr %s.1
  store i64 %t39, ptr %s.2
  br label %label_0
label_22:
  br label %label_11
label_11:
  %t41 = phi i64 [ %t13, %label_9 ], [ %t26, %label_22 ]
  %t42 = load i64, ptr %s.1
  call void @axiom_release(i64 %t42)
  ret i64 %t41
}
define i64 @IO$makeDirOk(i64 %p) #0 {

  %t0 = call i64 @IO$makeDir(i64 %p)
  %t1 = call i64 @Sys$sysErrno(i64 %t0)
  %t2 = call i64 @Sys.Platform$eExist()
  %c3 = icmp eq i64 %t1, %t2
  %t4 = zext i1 %c3 to i64
  %t5 = icmp ne i64 %t4, 0
  br i1 %t5, label %label_6, label %label_7
label_6:
  br label %label_8
label_7:
  br label %label_8
label_8:
  %t9 = phi i64 [ 0, %label_6 ], [ %t0, %label_7 ]
  ret i64 %t9
}
define i64 @IO$removeDir(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysRmdir(i64 %t0)
  ret i64 %t1
}
define i64 @IO$listDir(i64 %path) #0 {

  %t0 = call i64 @IO$ioPath(i64 %path)
  %t1 = call i64 @Sys$sysReadDir(i64 %t0)
  %t2 = call i64 @Vec$vecNew()
  %t3 = call i64 @IO$listDirKeep(i64 %t1, i64 0, i64 %t2)
  ret i64 %t2
}
define i64 @IO$listDirKeep(i64 %raw, i64 %i, i64 %out) #0 {

  %s.1 = alloca i64
  store i64 %raw, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  %s.3 = alloca i64
  store i64 %out, ptr %s.3
  br label %label_0
label_0:
  %t4 = load i64, ptr %s.2
  %t5 = load i64, ptr %s.1
  %t6 = call i64 @Vec$vecLen(i64 %t5)
  %c7 = icmp sge i64 %t4, %t6
  %t8 = zext i1 %c7 to i64
  %t9 = icmp ne i64 %t8, 0
  br i1 %t9, label %label_10, label %label_11
label_10:
  br label %label_12
label_11:
  %t13 = load i64, ptr %s.1
  %t14 = load i64, ptr %s.2
  %t15 = call i64 @Vec$vecGet(i64 %t13, i64 %t14)
  %t16 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_3, i64 0, i32 2) to i64
  %t17 = call i64 @Str$strEq(i64 %t15, i64 %t16)
  call void @axiom_release(i64 %t16)
  %t18 = icmp ne i64 %t17, 0
  br i1 %t18, label %label_20, label %label_19
label_19:
  %t22 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_14, i64 0, i32 2) to i64
  %t23 = call i64 @Str$strEq(i64 %t15, i64 %t22)
  call void @axiom_release(i64 %t22)
  %t24 = icmp ne i64 %t23, 0
  %t25 = zext i1 %t24 to i64
  br label %label_21
label_20:
  br label %label_21
label_21:
  %t26 = phi i64 [ %t25, %label_19 ], [ 1, %label_20 ]
  %t27 = icmp ne i64 %t26, 0
  br i1 %t27, label %label_28, label %label_29
label_28:
  br label %label_30
label_29:
  %t31 = load i64, ptr %s.3
  %t32 = call i64 @IO$listDirInsert(i64 %t31, i64 %t15)
  br label %label_30
label_30:
  %t33 = phi i64 [ 0, %label_28 ], [ %t32, %label_29 ]
  %t34 = load i64, ptr %s.1
  %t35 = load i64, ptr %s.2
  %t36 = add i64 %t35, 1
  %t37 = load i64, ptr %s.3
  store i64 %t34, ptr %s.1
  store i64 %t36, ptr %s.2
  store i64 %t37, ptr %s.3
  br label %label_0
label_12:
  ret i64 0
}
define i64 @IO$listDirInsert(i64 %v, i64 %s) #0 {

  %t0 = call i64 @Vec$vecPush(i64 %v, i64 %s, i64 0)
  %t1 = call i64 @Vec$vecLen(i64 %v)
  %t2 = sub i64 %t1, 1
  %t3 = call i64 @IO$listDirSift(i64 %v, i64 %t2)
  ret i64 %t3
}
define i64 @IO$listDirSift(i64 %v, i64 %i) #0 {

  %s.1 = alloca i64
  store i64 %v, ptr %s.1
  %s.2 = alloca i64
  store i64 %i, ptr %s.2
  br label %label_0
label_0:
  %t3 = load i64, ptr %s.2
  %c4 = icmp sle i64 %t3, 0
  %t5 = zext i1 %c4 to i64
  %t6 = icmp ne i64 %t5, 0
  br i1 %t6, label %label_7, label %label_8
label_7:
  br label %label_9
label_8:
  %t10 = load i64, ptr %s.1
  %t11 = load i64, ptr %s.2
  %t12 = sub i64 %t11, 1
  %t13 = call i64 @Vec$vecGet(i64 %t10, i64 %t12)
  %t14 = load i64, ptr %s.1
  %t15 = load i64, ptr %s.2
  %t16 = call i64 @Vec$vecGet(i64 %t14, i64 %t15)
  %t17 = call i64 @Str$strCmp(i64 %t13, i64 %t16)
  %c18 = icmp sle i64 %t17, 0
  %t19 = zext i1 %c18 to i64
  %t20 = icmp ne i64 %t19, 0
  br i1 %t20, label %label_21, label %label_22
label_21:
  br label %label_23
label_22:
  %t24 = load i64, ptr %s.1
  %t25 = load i64, ptr %s.2
  %t26 = sub i64 %t25, 1
  %t27 = call i64 @Vec$vecSet(i64 %t24, i64 %t26, i64 %t16, i64 0)
  %t28 = load i64, ptr %s.1
  %t29 = load i64, ptr %s.2
  %t30 = call i64 @Vec$vecSet(i64 %t28, i64 %t29, i64 %t13, i64 0)
  %t31 = load i64, ptr %s.1
  %t32 = load i64, ptr %s.2
  %t33 = sub i64 %t32, 1
  store i64 %t31, ptr %s.1
  store i64 %t33, ptr %s.2
  br label %label_0
label_23:
  br label %label_9
label_9:
  %t34 = phi i64 [ 0, %label_7 ], [ 0, %label_23 ]
  ret i64 %t34
}
define i64 @IO$cwd() #0 {

  %t0 = call i64 @Sys$sysGetCwd()
  ret i64 %t0
}
define i64 @IO$exit(i64 %code) #0 {

  %t0 = call i64 @Sys$sysExitWith(i64 %code)
  ret i64 %t0
}
define i64 @IO$die(i64 %s, i64 %code) #0 {

  %t0 = call i64 @Sys$stderr()
  %t1 = call i64 @"Show#String#show"(i64 %s)
  %t2 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_13, i64 0, i32 2) to i64
  %t3 = call i64 @Str$strConcat(i64 %t1, i64 %t2)
  call void @axiom_release(i64 %t1)
  call void @axiom_release(i64 %t2)
  %t4 = call i64 @IO$writeStr(i64 %t0, i64 %t3)
  %t5 = call i64 @IO$exit(i64 %code)
  ret i64 %t5
}
define i64 @ask(i64 %x) #0 {

  %t0 = call i64 @Mem$memAlloc(i64 140737488355328)
  ret i64 %t0
}
define i64 @usable(i64 %x) #0 {

  %t0 = call i64 @Mem$memAlloc(i64 64)
  %t1 = call i64 @Mem$memSetWord(i64 %t0, i64 0, i64 4242, i64 0)
  %t2 = call i64 @Mem$memGetWord(i64 %t0, i64 0)
  ret i64 %t2
}
define i64 @__axiom_user_main() #0 {

  %t0 = call i64 @__axiom_arena_mark_fn()
  br label %label_12
label_12:
  %t1 = call i64 @axiom_alloc(i64 128)
  %t2 = load i64, ptr @__axiom_recover_top
  %t3 = add i64 %t1, 24
  %t4 = inttoptr i64 %t3 to ptr
  store i64 %t0, ptr %t4
  %t5 = add i64 %t1, 32
  %t6 = inttoptr i64 %t5 to ptr
  store i64 %t2, ptr %t6
  %t7 = add i64 %t1, 40
  %t8 = inttoptr i64 %t7 to ptr
  store i64 0, ptr %t8
  call i64 @__axiom_recover_save(i64 %t1)
  store i64 %t1, ptr @__axiom_recover_top
  call void asm sideeffect "stp x19, x20, [$0, #48]\0Astp x21, x22, [$0, #64]\0Astp x23, x24, [$0, #80]\0Astp x25, x26, [$0, #96]\0Astp x27, x28, [$0, #112]\0Amov x9, sp\0Astr x9, [$0]\0Astr x29, [$0, #8]\0Aadr x9, 1f\0Astr x9, [$0, #16]\0Ab 2f\0A1:\0Aldp x19, x20, [x9, #48]\0Aldp x21, x22, [x9, #64]\0Aldp x23, x24, [x9, #80]\0Aldp x25, x26, [x9, #96]\0Aldp x27, x28, [x9, #112]\0A2:", "r,~{x0},~{x1},~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{lr},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{v22},~{v23},~{v24},~{v25},~{v26},~{v27},~{v28},~{v29},~{v30},~{v31},~{memory},~{cc}"(i64 %t1)
  %t9 = load i64, ptr %t8
  %t10 = icmp eq i64 %t9, 0
  br i1 %t10, label %label_13, label %label_14
label_13:
  %t15 = call i64 @axiom_alloc(i64 8)
  %f16 = ptrtoint ptr @_lam_0 to i64
  %t17 = inttoptr i64 %t15 to ptr
  %t18 = getelementptr i64, ptr %t17, i64 0
  store i64 %f16, ptr %t18
  %t19 = add i64 %t15, -16
  %t20 = inttoptr i64 %t19 to ptr
  store i64 1, ptr %t20
  %t21 = add i64 %t15, -8
  %t22 = inttoptr i64 %t21 to ptr
  store i64 4, ptr %t22
  %t23 = inttoptr i64 %t15 to ptr
  %t24 = getelementptr i64, ptr %t23, i64 0
  %t25 = load i64, ptr %t24
  %f26 = inttoptr i64 %t25 to ptr
  %t27 = call i64 %f26(i64 %t15, i64 0)
  call void @axiom_release(i64 %t15)
  br label %label_14
label_14:
  %t11 = phi i64 [ %t9, %label_12 ], [ %t27, %label_13 ]
  store i64 %t2, ptr @__axiom_recover_top
  %t28 = call i64 @usable(i64 0)
  %t29 = call i64 @Sys$stdout()
  %t30 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_15, i64 0, i32 2) to i64
  %t31 = call i64 @"Show#Int#show"(i64 %t11)
  %t32 = call i64 @Str$strConcat(i64 %t30, i64 %t31)
  call void @axiom_release(i64 %t30)
  call void @axiom_release(i64 %t31)
  %t33 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_13, i64 0, i32 2) to i64
  %t34 = call i64 @Str$strConcat(i64 %t32, i64 %t33)
  call void @axiom_release(i64 %t32)
  call void @axiom_release(i64 %t33)
  %t35 = call i64 @IO$writeStr(i64 %t29, i64 %t34)
  %t36 = call i64 @Sys$stdout()
  %t37 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_16, i64 0, i32 2) to i64
  %t38 = call i64 @"Show#Int#show"(i64 %t28)
  %t39 = call i64 @Str$strConcat(i64 %t37, i64 %t38)
  call void @axiom_release(i64 %t37)
  call void @axiom_release(i64 %t38)
  %t40 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_13, i64 0, i32 2) to i64
  %t41 = call i64 @Str$strConcat(i64 %t39, i64 %t40)
  call void @axiom_release(i64 %t39)
  call void @axiom_release(i64 %t40)
  %t42 = call i64 @IO$writeStr(i64 %t36, i64 %t41)
  %t43 = call i64 @ask(i64 0)
  %t44 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_17, i64 0, i32 2) to i64
  %t45 = call i64 @Str$strCStr(i64 %t44)
  %t46 = call i64 @IO$printlnLit(i64 %t45)
  ret i64 %t46
}
define i64 @_lam_0(i64 %_env, i64 %x) #0 {

  %t0 = call i64 @ask(i64 %x)
  ret i64 %t0
}
define i64 @"Show#String#show"(i64 %s) #0 {

  call void @axiom_retain(i64 %s)
  ret i64 %s
}
define i64 @"Show#Int#show"(i64 %n) #0 {

  %t0 = call i64 @Fmt$fmtInt(i64 %n)
  ret i64 %t0
}
define i64 @"Show#Bool#show"(i64 %b) #0 {

  %t0 = icmp ne i64 %b, 0
  br i1 %t0, label %label_1, label %label_2
label_1:
  %t4 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_18, i64 0, i32 2) to i64
  br label %label_3
label_2:
  %t5 = ptrtoint ptr getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_19, i64 0, i32 2) to i64
  br label %label_3
label_3:
  %t6 = phi i64 [ %t4, %label_1 ], [ %t5, %label_2 ]
  ret i64 %t6
}
define i64 @"Show#Float#show"(i64 %x) #0 {

  %t0 = call i64 @Fmt$fmtFloat(i64 %x)
  ret i64 %t0
}
@str_0 = private unnamed_addr constant [21 x i8]  c"\2D\39\32\32\33\33\37\32\30\33\36\38\35\34\37\37\35\38\30\38\00"
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 20, ptr @str_0, i64 0 }, align 16
@str_1 = private unnamed_addr constant [2 x i8]  c"\2D\00"
@strhdr_1 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_1, i64 0 }, align 16
@str_2 = private unnamed_addr constant [2 x i8]  c"\30\00"
@strhdr_2 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_2, i64 0 }, align 16
@str_3 = private unnamed_addr constant [2 x i8]  c"\2E\00"
@strhdr_3 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_3, i64 0 }, align 16
@str_4 = private unnamed_addr constant [1 x i8]  c"\00"
@strhdr_4 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 0, ptr @str_4, i64 0 }, align 16
@str_5 = private unnamed_addr constant [2 x i8]  c"\3D\00"
@strhdr_5 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_5, i64 0 }, align 16
@str_6 = private unnamed_addr constant [5 x i8]  c"\50\41\54\48\00"
@strhdr_6 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 4, ptr @str_6, i64 0 }, align 16
@str_7 = private unnamed_addr constant [2 x i8]  c"\2F\00"
@strhdr_7 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_7, i64 0 }, align 16
@str_8 = private unnamed_addr constant [4 x i8]  c"\61\66\3D\00"
@strhdr_8 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 3, ptr @str_8, i64 0 }, align 16
@str_9 = private unnamed_addr constant [3 x i8]  c"\3A\3A\00"
@strhdr_9 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_9, i64 0 }, align 16
@str_10 = private unnamed_addr constant [2 x i8]  c"\3A\00"
@strhdr_10 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_10, i64 0 }, align 16
@str_11 = private unnamed_addr constant [2 x i8]  c"\5B\00"
@strhdr_11 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_11, i64 0 }, align 16
@str_12 = private unnamed_addr constant [3 x i8]  c"\5D\3A\00"
@strhdr_12 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_12, i64 0 }, align 16
@str_13 = private unnamed_addr constant [2 x i8]  c"\0A\00"
@strhdr_13 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_13, i64 0 }, align 16
@str_14 = private unnamed_addr constant [3 x i8]  c"\2E\2E\00"
@strhdr_14 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_14, i64 0 }, align 16
@str_15 = private unnamed_addr constant [11 x i8]  c"\72\65\63\6F\76\65\72\65\64\20\00"
@strhdr_15 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 10, ptr @str_15, i64 0 }, align 16
@str_16 = private unnamed_addr constant [8 x i8]  c"\75\73\61\62\6C\65\20\00"
@strhdr_16 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 7, ptr @str_16, i64 0 }, align 16
@str_17 = private unnamed_addr constant [56 x i8]  c"\55\4E\52\45\41\43\48\41\42\4C\45\3A\20\74\68\65\20\74\72\61\70\20\6F\75\74\73\69\64\65\20\61\20\72\65\63\6F\76\65\72\79\20\70\6F\69\6E\74\20\72\65\74\75\72\6E\65\64\00"
@strhdr_17 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 55, ptr @str_17, i64 0 }, align 16
@str_18 = private unnamed_addr constant [5 x i8]  c"\74\72\75\65\00"
@strhdr_18 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 4, ptr @str_18, i64 0 }, align 16
@str_19 = private unnamed_addr constant [6 x i8]  c"\66\61\6C\73\65\00"
@strhdr_19 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 5, ptr @str_19, i64 0 }, align 16

define internal i64 @__axiom_recover_save(i64 %rec) #0 {
entry:
  ret i64 0
}
define internal i64 @__axiom_recover_load(i64 %rec) #0 {
entry:
  ret i64 0
}

@__axiom_symn_0 = private unnamed_addr constant [4 x i8] c"main"
@__axiom_symn_1 = private unnamed_addr constant [11 x i8] c"axiom_alloc"
@__axiom_symn_2 = private unnamed_addr constant [12 x i8] c"axiom_retain"
@__axiom_symn_3 = private unnamed_addr constant [13 x i8] c"axiom_release"
@__axiom_symn_4 = private unnamed_addr constant [21 x i8] c"__axiom_arena_mark_fn"
@__axiom_symn_5 = private unnamed_addr constant [22 x i8] c"__axiom_arena_reset_fn"
@__axiom_symn_6 = private unnamed_addr constant [30 x i8] c"__axiom_arena_reset_keeping_fn"
@__axiom_symn_7 = private unnamed_addr constant [19 x i8] c"__axiom_div_by_zero"
@__axiom_symn_8 = private unnamed_addr constant [21 x i8] c"__axiom_out_of_memory"
@__axiom_symn_9 = private unnamed_addr constant [21 x i8] c"__axiom_recover_abort"
@__axiom_symn_10 = private unnamed_addr constant [14 x i8] c"__axiom_str_eq"
@__axiom_symn_11 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysRead"
@__axiom_symn_12 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysWrite"
@__axiom_symn_13 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysOpen"
@__axiom_symn_14 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysClose"
@__axiom_symn_15 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysExit"
@__axiom_symn_16 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysLseek"
@__axiom_symn_17 = private unnamed_addr constant [27 x i8] c"Sys.Platform$openNeedsDirFd"
@__axiom_symn_18 = private unnamed_addr constant [20 x i8] c"Sys.Platform$atFdCwd"
@__axiom_symn_19 = private unnamed_addr constant [20 x i8] c"Sys.Platform$oRdonly"
@__axiom_symn_20 = private unnamed_addr constant [31 x i8] c"Sys.Platform$oWronlyCreateTrunc"
@__axiom_symn_21 = private unnamed_addr constant [32 x i8] c"Sys.Platform$oWronlyCreateAppend"
@__axiom_symn_22 = private unnamed_addr constant [20 x i8] c"Sys.Platform$seekEnd"
@__axiom_symn_23 = private unnamed_addr constant [20 x i8] c"Sys.Platform$seekSet"
@__axiom_symn_24 = private unnamed_addr constant [32 x i8] c"Sys.Platform$spawnUsesPosixSpawn"
@__axiom_symn_25 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysFork"
@__axiom_symn_26 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysForkArg"
@__axiom_symn_27 = private unnamed_addr constant [22 x i8] c"Sys.Platform$sysExecve"
@__axiom_symn_28 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysWait4"
@__axiom_symn_29 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysPosixSpawn"
@__axiom_symn_30 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysUnlinkNum"
@__axiom_symn_31 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysMkdirNum"
@__axiom_symn_32 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysRmdirNum"
@__axiom_symn_33 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysRenameNum"
@__axiom_symn_34 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysGetdentsNum"
@__axiom_symn_35 = private unnamed_addr constant [33 x i8] c"Sys.Platform$dirReadNeedsPosition"
@__axiom_symn_36 = private unnamed_addr constant [29 x i8] c"Sys.Platform$direntNameOffset"
@__axiom_symn_37 = private unnamed_addr constant [29 x i8] c"Sys.Platform$cwdUsesFcntlPath"
@__axiom_symn_38 = private unnamed_addr constant [22 x i8] c"Sys.Platform$sysCwdNum"
@__axiom_symn_39 = private unnamed_addr constant [21 x i8] c"Sys.Platform$fGetPath"
@__axiom_symn_40 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eExist"
@__axiom_symn_41 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eIsDir"
@__axiom_symn_42 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysGetPidNum"
@__axiom_symn_43 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysClockNum"
@__axiom_symn_44 = private unnamed_addr constant [32 x i8] c"Sys.Platform$clockIsGettimeofday"
@__axiom_symn_45 = private unnamed_addr constant [30 x i8] c"Sys.Platform$clockHasMonotonic"
@__axiom_symn_46 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysSocketNum"
@__axiom_symn_47 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysBindNum"
@__axiom_symn_48 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysListenNum"
@__axiom_symn_49 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysAcceptNum"
@__axiom_symn_50 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysConnectNum"
@__axiom_symn_51 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysSetSockOptNum"
@__axiom_symn_52 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysGetSockOptNum"
@__axiom_symn_53 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysShutdownNum"
@__axiom_symn_54 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysFcntlNum"
@__axiom_symn_55 = private unnamed_addr constant [19 x i8] c"Sys.Platform$afInet"
@__axiom_symn_56 = private unnamed_addr constant [20 x i8] c"Sys.Platform$afInet6"
@__axiom_symn_57 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sockStream"
@__axiom_symn_58 = private unnamed_addr constant [22 x i8] c"Sys.Platform$solSocket"
@__axiom_symn_59 = private unnamed_addr constant [24 x i8] c"Sys.Platform$soReuseAddr"
@__axiom_symn_60 = private unnamed_addr constant [24 x i8] c"Sys.Platform$soReusePort"
@__axiom_symn_61 = private unnamed_addr constant [20 x i8] c"Sys.Platform$soError"
@__axiom_symn_62 = private unnamed_addr constant [19 x i8] c"Sys.Platform$fGetFl"
@__axiom_symn_63 = private unnamed_addr constant [19 x i8] c"Sys.Platform$fSetFl"
@__axiom_symn_64 = private unnamed_addr constant [22 x i8] c"Sys.Platform$oNonblock"
@__axiom_symn_65 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eAgain"
@__axiom_symn_66 = private unnamed_addr constant [31 x i8] c"Sys.Platform$sockaddrHasLenByte"
@__axiom_symn_67 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollUsesKqueue"
@__axiom_symn_68 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysPollCreateNum"
@__axiom_symn_69 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysPollWaitNum"
@__axiom_symn_70 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysPollCtlNum"
@__axiom_symn_71 = private unnamed_addr constant [26 x i8] c"Sys.Platform$pollEventSize"
@__axiom_symn_72 = private unnamed_addr constant [30 x i8] c"Sys.Platform$pollEventFdOffset"
@__axiom_symn_73 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollReadFilter"
@__axiom_symn_74 = private unnamed_addr constant [22 x i8] c"Sys.Platform$pollAddOp"
@__axiom_symn_75 = private unnamed_addr constant [22 x i8] c"Sys.Platform$pollDelOp"
@__axiom_symn_76 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollSigsetSize"
@__axiom_symn_77 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysRandomNum"
@__axiom_symn_78 = private unnamed_addr constant [31 x i8] c"Sys.Platform$randomIsGetentropy"
@__axiom_symn_79 = private unnamed_addr constant [27 x i8] c"Sys.Platform$randomMaxChunk"
@__axiom_symn_80 = private unnamed_addr constant [31 x i8] c"Sys.Platform$signalUsesSignalFd"
@__axiom_symn_81 = private unnamed_addr constant [30 x i8] c"Sys.Platform$sysSigProcMaskNum"
@__axiom_symn_82 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigBlockHow"
@__axiom_symn_83 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigsetBytes"
@__axiom_symn_84 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysSignalFdNum"
@__axiom_symn_85 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigInfoSize"
@__axiom_symn_86 = private unnamed_addr constant [29 x i8] c"Sys.Platform$pollSignalFilter"
@__axiom_symn_87 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysKillNum"
@__axiom_symn_88 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sigTerm"
@__axiom_symn_89 = private unnamed_addr constant [19 x i8] c"Sys.Platform$sigInt"
@__axiom_symn_90 = private unnamed_addr constant [28 x i8] c"Sys.Platform$forkChildIsZero"
@__axiom_symn_91 = private unnamed_addr constant [31 x i8] c"Sys.Platform$acceptNonblockFlag"
@__axiom_symn_92 = private unnamed_addr constant [12 x i8] c"Mem$memAlloc"
@__axiom_symn_93 = private unnamed_addr constant [18 x i8] c"Mem$memAllocMapped"
@__axiom_symn_94 = private unnamed_addr constant [16 x i8] c"Mem$memMarkArray"
@__axiom_symn_95 = private unnamed_addr constant [15 x i8] c"Mem$memMarkLeaf"
@__axiom_symn_96 = private unnamed_addr constant [11 x i8] c"Mem$memCopy"
@__axiom_symn_97 = private unnamed_addr constant [15 x i8] c"Mem$memCopyFrom"
@__axiom_symn_98 = private unnamed_addr constant [10 x i8] c"Mem$memSet"
@__axiom_symn_99 = private unnamed_addr constant [14 x i8] c"Mem$memSetFrom"
@__axiom_symn_100 = private unnamed_addr constant [10 x i8] c"Mem$memCmp"
@__axiom_symn_101 = private unnamed_addr constant [14 x i8] c"Mem$memCmpFrom"
@__axiom_symn_102 = private unnamed_addr constant [14 x i8] c"Mem$memGetWord"
@__axiom_symn_103 = private unnamed_addr constant [17 x i8] c"Mem$memGetWordStr"
@__axiom_symn_104 = private unnamed_addr constant [14 x i8] c"Mem$memSetWord"
@__axiom_symn_105 = private unnamed_addr constant [14 x i8] c"Mem$memGetByte"
@__axiom_symn_106 = private unnamed_addr constant [14 x i8] c"Mem$memPutByte"
@__axiom_symn_107 = private unnamed_addr constant [17 x i8] c"Vec$vecDefaultCap"
@__axiom_symn_108 = private unnamed_addr constant [10 x i8] c"Vec$vecNew"
@__axiom_symn_109 = private unnamed_addr constant [19 x i8] c"Vec$vecWithCapacity"
@__axiom_symn_110 = private unnamed_addr constant [22 x i8] c"Vec$vecWithCapacityRef"
@__axiom_symn_111 = private unnamed_addr constant [13 x i8] c"Vec$vecNewRef"
@__axiom_symn_112 = private unnamed_addr constant [12 x i8] c"Vec$vecBuild"
@__axiom_symn_113 = private unnamed_addr constant [11 x i8] c"Vec$vecFree"
@__axiom_symn_114 = private unnamed_addr constant [15 x i8] c"Vec$vecOwnsRefs"
@__axiom_symn_115 = private unnamed_addr constant [10 x i8] c"Vec$vecLen"
@__axiom_symn_116 = private unnamed_addr constant [10 x i8] c"Vec$vecCap"
@__axiom_symn_117 = private unnamed_addr constant [11 x i8] c"Vec$vecData"
@__axiom_symn_118 = private unnamed_addr constant [10 x i8] c"Vec$vecGet"
@__axiom_symn_119 = private unnamed_addr constant [10 x i8] c"Vec$vecTry"
@__axiom_symn_120 = private unnamed_addr constant [13 x i8] c"Vec$vecGetStr"
@__axiom_symn_121 = private unnamed_addr constant [10 x i8] c"Vec$vecSet"
@__axiom_symn_122 = private unnamed_addr constant [14 x i8] c"Vec$vecReserve"
@__axiom_symn_123 = private unnamed_addr constant [15 x i8] c"Vec$vecGrownCap"
@__axiom_symn_124 = private unnamed_addr constant [21 x i8] c"Vec$vecReserveExactly"
@__axiom_symn_125 = private unnamed_addr constant [11 x i8] c"Vec$vecPush"
@__axiom_symn_126 = private unnamed_addr constant [10 x i8] c"Vec$vecPop"
@__axiom_symn_127 = private unnamed_addr constant [11 x i8] c"Vec$vecLast"
@__axiom_symn_128 = private unnamed_addr constant [12 x i8] c"Vec$vecClear"
@__axiom_symn_129 = private unnamed_addr constant [13 x i8] c"Vec$vecDropAt"
@__axiom_symn_130 = private unnamed_addr constant [15 x i8] c"Vec$vecDropFrom"
@__axiom_symn_131 = private unnamed_addr constant [10 x i8] c"Vec$vecSum"
@__axiom_symn_132 = private unnamed_addr constant [14 x i8] c"Vec$vecSumFrom"
@__axiom_symn_133 = private unnamed_addr constant [11 x i8] c"Vec$vecHash"
@__axiom_symn_134 = private unnamed_addr constant [15 x i8] c"Vec$vecHashFrom"
@__axiom_symn_135 = private unnamed_addr constant [11 x i8] c"Str$strWrap"
@__axiom_symn_136 = private unnamed_addr constant [16 x i8] c"Str$strWrapOwned"
@__axiom_symn_137 = private unnamed_addr constant [12 x i8] c"Str$strAlloc"
@__axiom_symn_138 = private unnamed_addr constant [14 x i8] c"Str$strFromLit"
@__axiom_symn_139 = private unnamed_addr constant [11 x i8] c"Str$cstrLen"
@__axiom_symn_140 = private unnamed_addr constant [10 x i8] c"Str$strLen"
@__axiom_symn_141 = private unnamed_addr constant [11 x i8] c"Str$strData"
@__axiom_symn_142 = private unnamed_addr constant [12 x i8] c"Str$strOwner"
@__axiom_symn_143 = private unnamed_addr constant [11 x i8] c"Str$strByte"
@__axiom_symn_144 = private unnamed_addr constant [11 x i8] c"Str$strCStr"
@__axiom_symn_145 = private unnamed_addr constant [14 x i8] c"Str$strIsEmpty"
@__axiom_symn_146 = private unnamed_addr constant [10 x i8] c"Str$strCmp"
@__axiom_symn_147 = private unnamed_addr constant [9 x i8] c"Str$strEq"
@__axiom_symn_148 = private unnamed_addr constant [12 x i8] c"Str$strSlice"
@__axiom_symn_149 = private unnamed_addr constant [10 x i8] c"Str$strDup"
@__axiom_symn_150 = private unnamed_addr constant [13 x i8] c"Str$strConcat"
@__axiom_symn_151 = private unnamed_addr constant [15 x i8] c"Str$strFindByte"
@__axiom_symn_152 = private unnamed_addr constant [17 x i8] c"Str$strStartsWith"
@__axiom_symn_153 = private unnamed_addr constant [14 x i8] c"Str$strIsDigit"
@__axiom_symn_154 = private unnamed_addr constant [14 x i8] c"Str$strIsAlpha"
@__axiom_symn_155 = private unnamed_addr constant [14 x i8] c"Str$strIsSpace"
@__axiom_symn_156 = private unnamed_addr constant [13 x i8] c"Str$strHexVal"
@__axiom_symn_157 = private unnamed_addr constant [17 x i8] c"Str$strIsHexDigit"
@__axiom_symn_158 = private unnamed_addr constant [12 x i8] c"Str$strSplit"
@__axiom_symn_159 = private unnamed_addr constant [16 x i8] c"Str$strSplitFrom"
@__axiom_symn_160 = private unnamed_addr constant [15 x i8] c"Str$strFromByte"
@__axiom_symn_161 = private unnamed_addr constant [21 x i8] c"Fmt$intIsMostNegative"
@__axiom_symn_162 = private unnamed_addr constant [15 x i8] c"Fmt$fmtIntWidth"
@__axiom_symn_163 = private unnamed_addr constant [10 x i8] c"Fmt$fmtInt"
@__axiom_symn_164 = private unnamed_addr constant [10 x i8] c"Fmt$fmtNat"
@__axiom_symn_165 = private unnamed_addr constant [13 x i8] c"Fmt$fmtDigits"
@__axiom_symn_166 = private unnamed_addr constant [14 x i8] c"Fmt$fmtHexShr4"
@__axiom_symn_167 = private unnamed_addr constant [10 x i8] c"Fmt$fmtHex"
@__axiom_symn_168 = private unnamed_addr constant [15 x i8] c"Fmt$fmtHexWidth"
@__axiom_symn_169 = private unnamed_addr constant [16 x i8] c"Fmt$fmtHexDigits"
@__axiom_symn_170 = private unnamed_addr constant [14 x i8] c"Fmt$fmtPadLeft"
@__axiom_symn_171 = private unnamed_addr constant [15 x i8] c"Fmt$fmtPadRight"
@__axiom_symn_172 = private unnamed_addr constant [16 x i8] c"Fmt$fmtPadCenter"
@__axiom_symn_173 = private unnamed_addr constant [19 x i8] c"Fmt$fmtPadZerosLeft"
@__axiom_symn_174 = private unnamed_addr constant [15 x i8] c"Fmt$fmtHexUpper"
@__axiom_symn_175 = private unnamed_addr constant [21 x i8] c"Fmt$fmtHexDigitsUpper"
@__axiom_symn_176 = private unnamed_addr constant [10 x i8] c"Fmt$powTen"
@__axiom_symn_177 = private unnamed_addr constant [15 x i8] c"Fmt$fmtPadZeros"
@__axiom_symn_178 = private unnamed_addr constant [12 x i8] c"Fmt$fmtFloat"
@__axiom_symn_179 = private unnamed_addr constant [16 x i8] c"Fmt$fmtFloatPrec"
@__axiom_symn_180 = private unnamed_addr constant [15 x i8] c"Fmt$fmtFloatAbs"
@__axiom_symn_181 = private unnamed_addr constant [9 x i8] c"Sys$stdin"
@__axiom_symn_182 = private unnamed_addr constant [10 x i8] c"Sys$stdout"
@__axiom_symn_183 = private unnamed_addr constant [10 x i8] c"Sys$stderr"
@__axiom_symn_184 = private unnamed_addr constant [14 x i8] c"Sys$sysWriteFd"
@__axiom_symn_185 = private unnamed_addr constant [17 x i8] c"Sys$sysWriteAllFd"
@__axiom_symn_186 = private unnamed_addr constant [13 x i8] c"Sys$sysReadFd"
@__axiom_symn_187 = private unnamed_addr constant [15 x i8] c"Sys$sysOpenPath"
@__axiom_symn_188 = private unnamed_addr constant [19 x i8] c"Sys$sysOpenPathMode"
@__axiom_symn_189 = private unnamed_addr constant [14 x i8] c"Sys$sysCloseFd"
@__axiom_symn_190 = private unnamed_addr constant [11 x i8] c"Sys$sysSeek"
@__axiom_symn_191 = private unnamed_addr constant [15 x i8] c"Sys$sysExitWith"
@__axiom_symn_192 = private unnamed_addr constant [13 x i8] c"Sys$sysFailed"
@__axiom_symn_193 = private unnamed_addr constant [12 x i8] c"Sys$sysErrno"
@__axiom_symn_194 = private unnamed_addr constant [15 x i8] c"Sys$sysReadFile"
@__axiom_symn_195 = private unnamed_addr constant [14 x i8] c"Sys$sysReadAll"
@__axiom_symn_196 = private unnamed_addr constant [11 x i8] c"Sys$sysArgc"
@__axiom_symn_197 = private unnamed_addr constant [10 x i8] c"Sys$sysArg"
@__axiom_symn_198 = private unnamed_addr constant [16 x i8] c"Sys$sysWriteFile"
@__axiom_symn_199 = private unnamed_addr constant [17 x i8] c"Sys$sysAppendFile"
@__axiom_symn_200 = private unnamed_addr constant [13 x i8] c"Sys$sysRename"
@__axiom_symn_201 = private unnamed_addr constant [13 x i8] c"Sys$sysUnlink"
@__axiom_symn_202 = private unnamed_addr constant [12 x i8] c"Sys$sysMkdir"
@__axiom_symn_203 = private unnamed_addr constant [14 x i8] c"Sys$sysDirMode"
@__axiom_symn_204 = private unnamed_addr constant [12 x i8] c"Sys$sysRmdir"
@__axiom_symn_205 = private unnamed_addr constant [17 x i8] c"Sys$sysFileExists"
@__axiom_symn_206 = private unnamed_addr constant [15 x i8] c"Sys$sysFileSize"
@__axiom_symn_207 = private unnamed_addr constant [16 x i8] c"Sys$sysReadErrno"
@__axiom_symn_208 = private unnamed_addr constant [12 x i8] c"Sys$sysIsDir"
@__axiom_symn_209 = private unnamed_addr constant [18 x i8] c"Sys$sysDirBufBytes"
@__axiom_symn_210 = private unnamed_addr constant [14 x i8] c"Sys$sysReadDir"
@__axiom_symn_211 = private unnamed_addr constant [18 x i8] c"Sys$sysReadDirLoop"
@__axiom_symn_212 = private unnamed_addr constant [20 x i8] c"Sys$sysReadDirDecode"
@__axiom_symn_213 = private unnamed_addr constant [13 x i8] c"Sys$sysGetCwd"
@__axiom_symn_214 = private unnamed_addr constant [14 x i8] c"Sys$sysEnvSlot"
@__axiom_symn_215 = private unnamed_addr constant [15 x i8] c"Sys$sysEnvCount"
@__axiom_symn_216 = private unnamed_addr constant [19 x i8] c"Sys$sysEnvCountFrom"
@__axiom_symn_217 = private unnamed_addr constant [10 x i8] c"Sys$sysEnv"
@__axiom_symn_218 = private unnamed_addr constant [16 x i8] c"Sys$sysEnvLookup"
@__axiom_symn_219 = private unnamed_addr constant [11 x i8] c"Sys$sysEnvp"
@__axiom_symn_220 = private unnamed_addr constant [15 x i8] c"Sys$sysEnvpFill"
@__axiom_symn_221 = private unnamed_addr constant [12 x i8] c"Sys$sysSpawn"
@__axiom_symn_222 = private unnamed_addr constant [14 x i8] c"Sys$sysWaitPid"
@__axiom_symn_223 = private unnamed_addr constant [15 x i8] c"Sys$sysExitCode"
@__axiom_symn_224 = private unnamed_addr constant [17 x i8] c"Sys$sysTermSignal"
@__axiom_symn_225 = private unnamed_addr constant [10 x i8] c"Sys$sysRun"
@__axiom_symn_226 = private unnamed_addr constant [14 x i8] c"Sys$sysRunPath"
@__axiom_symn_227 = private unnamed_addr constant [16 x i8] c"Sys$sysRunSearch"
@__axiom_symn_228 = private unnamed_addr constant [13 x i8] c"Sys$sysGetPid"
@__axiom_symn_229 = private unnamed_addr constant [16 x i8] c"Sys$sysNowMicros"
@__axiom_symn_230 = private unnamed_addr constant [19 x i8] c"Sys$sysNowMonotonic"
@__axiom_symn_231 = private unnamed_addr constant [16 x i8] c"Sys$netSocketTcp"
@__axiom_symn_232 = private unnamed_addr constant [17 x i8] c"Sys$netSocketTcp6"
@__axiom_symn_233 = private unnamed_addr constant [17 x i8] c"Sys$netAddr4Bytes"
@__axiom_symn_234 = private unnamed_addr constant [17 x i8] c"Sys$netAddr6Bytes"
@__axiom_symn_235 = private unnamed_addr constant [19 x i8] c"Sys$netAddrMaxBytes"
@__axiom_symn_236 = private unnamed_addr constant [12 x i8] c"Sys$netAddr4"
@__axiom_symn_237 = private unnamed_addr constant [12 x i8] c"Sys$netAddr6"
@__axiom_symn_238 = private unnamed_addr constant [15 x i8] c"Sys$netPutGroup"
@__axiom_symn_239 = private unnamed_addr constant [15 x i8] c"Sys$netGetGroup"
@__axiom_symn_240 = private unnamed_addr constant [17 x i8] c"Sys$netAddrFamily"
@__axiom_symn_241 = private unnamed_addr constant [15 x i8] c"Sys$netAddrPort"
@__axiom_symn_242 = private unnamed_addr constant [15 x i8] c"Sys$netAddrSize"
@__axiom_symn_243 = private unnamed_addr constant [11 x i8] c"Sys$netBind"
@__axiom_symn_244 = private unnamed_addr constant [13 x i8] c"Sys$netListen"
@__axiom_symn_245 = private unnamed_addr constant [13 x i8] c"Sys$netAccept"
@__axiom_symn_246 = private unnamed_addr constant [19 x i8] c"Sys$netAcceptFinish"
@__axiom_symn_247 = private unnamed_addr constant [17 x i8] c"Sys$netAcceptFrom"
@__axiom_symn_248 = private unnamed_addr constant [18 x i8] c"Sys$netAddrLenRead"
@__axiom_symn_249 = private unnamed_addr constant [15 x i8] c"Sys$netPutInt32"
@__axiom_symn_250 = private unnamed_addr constant [15 x i8] c"Sys$netGetInt32"
@__axiom_symn_251 = private unnamed_addr constant [15 x i8] c"Sys$netAddrText"
@__axiom_symn_252 = private unnamed_addr constant [16 x i8] c"Sys$netAddrText4"
@__axiom_symn_253 = private unnamed_addr constant [18 x i8] c"Sys$netAddrZeroRun"
@__axiom_symn_254 = private unnamed_addr constant [23 x i8] c"Sys$netAddrZeroRunStart"
@__axiom_symn_255 = private unnamed_addr constant [16 x i8] c"Sys$netAddrText6"
@__axiom_symn_256 = private unnamed_addr constant [19 x i8] c"Sys$netAddrTextPort"
@__axiom_symn_257 = private unnamed_addr constant [18 x i8] c"Sys$netSetBlocking"
@__axiom_symn_258 = private unnamed_addr constant [14 x i8] c"Sys$netConnect"
@__axiom_symn_259 = private unnamed_addr constant [15 x i8] c"Sys$netShutdown"
@__axiom_symn_260 = private unnamed_addr constant [16 x i8] c"Sys$netSetOptInt"
@__axiom_symn_261 = private unnamed_addr constant [21 x i8] c"Sys$netSetNonBlocking"
@__axiom_symn_262 = private unnamed_addr constant [17 x i8] c"Sys$netWouldBlock"
@__axiom_symn_263 = private unnamed_addr constant [14 x i8] c"Sys$netPutWord"
@__axiom_symn_264 = private unnamed_addr constant [14 x i8] c"Sys$netGetWord"
@__axiom_symn_265 = private unnamed_addr constant [19 x i8] c"Sys$netPollBufBytes"
@__axiom_symn_266 = private unnamed_addr constant [17 x i8] c"Sys$netPollCreate"
@__axiom_symn_267 = private unnamed_addr constant [14 x i8] c"Sys$netPollRec"
@__axiom_symn_268 = private unnamed_addr constant [18 x i8] c"Sys$netPollAddRead"
@__axiom_symn_269 = private unnamed_addr constant [18 x i8] c"Sys$netPollDelRead"
@__axiom_symn_270 = private unnamed_addr constant [15 x i8] c"Sys$netPollWait"
@__axiom_symn_271 = private unnamed_addr constant [15 x i8] c"Sys$netPollFdAt"
@__axiom_symn_272 = private unnamed_addr constant [18 x i8] c"Sys$sysRandomBytes"
@__axiom_symn_273 = private unnamed_addr constant [13 x i8] c"Sys$sysSigBit"
@__axiom_symn_274 = private unnamed_addr constant [18 x i8] c"Sys$sysSignalBlock"
@__axiom_symn_275 = private unnamed_addr constant [17 x i8] c"Sys$netSignalOpen"
@__axiom_symn_276 = private unnamed_addr constant [19 x i8] c"Sys$netPollSignalAt"
@__axiom_symn_277 = private unnamed_addr constant [11 x i8] c"Sys$sysKill"
@__axiom_symn_278 = private unnamed_addr constant [18 x i8] c"Sys$sysForkProcess"
@__axiom_symn_279 = private unnamed_addr constant [11 x i8] c"IO$writeStr"
@__axiom_symn_280 = private unnamed_addr constant [11 x i8] c"IO$printLit"
@__axiom_symn_281 = private unnamed_addr constant [13 x i8] c"IO$printlnLit"
@__axiom_symn_282 = private unnamed_addr constant [14 x i8] c"IO$readFileLit"
@__axiom_symn_283 = private unnamed_addr constant [11 x i8] c"IO$readFile"
@__axiom_symn_284 = private unnamed_addr constant [9 x i8] c"IO$ioPath"
@__axiom_symn_285 = private unnamed_addr constant [12 x i8] c"IO$writeFile"
@__axiom_symn_286 = private unnamed_addr constant [13 x i8] c"IO$appendFile"
@__axiom_symn_287 = private unnamed_addr constant [13 x i8] c"IO$removeFile"
@__axiom_symn_288 = private unnamed_addr constant [13 x i8] c"IO$renamePath"
@__axiom_symn_289 = private unnamed_addr constant [11 x i8] c"IO$copyFile"
@__axiom_symn_290 = private unnamed_addr constant [13 x i8] c"IO$fileExists"
@__axiom_symn_291 = private unnamed_addr constant [8 x i8] c"IO$isDir"
@__axiom_symn_292 = private unnamed_addr constant [11 x i8] c"IO$fileSize"
@__axiom_symn_293 = private unnamed_addr constant [12 x i8] c"IO$readErrno"
@__axiom_symn_294 = private unnamed_addr constant [10 x i8] c"IO$makeDir"
@__axiom_symn_295 = private unnamed_addr constant [13 x i8] c"IO$makeDirAll"
@__axiom_symn_296 = private unnamed_addr constant [17 x i8] c"IO$makeDirAllFrom"
@__axiom_symn_297 = private unnamed_addr constant [12 x i8] c"IO$makeDirOk"
@__axiom_symn_298 = private unnamed_addr constant [12 x i8] c"IO$removeDir"
@__axiom_symn_299 = private unnamed_addr constant [10 x i8] c"IO$listDir"
@__axiom_symn_300 = private unnamed_addr constant [14 x i8] c"IO$listDirKeep"
@__axiom_symn_301 = private unnamed_addr constant [16 x i8] c"IO$listDirInsert"
@__axiom_symn_302 = private unnamed_addr constant [14 x i8] c"IO$listDirSift"
@__axiom_symn_303 = private unnamed_addr constant [6 x i8] c"IO$cwd"
@__axiom_symn_304 = private unnamed_addr constant [7 x i8] c"IO$exit"
@__axiom_symn_305 = private unnamed_addr constant [6 x i8] c"IO$die"
@__axiom_symn_306 = private unnamed_addr constant [3 x i8] c"ask"
@__axiom_symn_307 = private unnamed_addr constant [6 x i8] c"usable"
@__axiom_symn_308 = private unnamed_addr constant [17 x i8] c"__axiom_user_main"
@__axiom_symn_309 = private unnamed_addr constant [6 x i8] c"_lam_0"
@__axiom_symn_310 = private unnamed_addr constant [16 x i8] c"Show#String#show"
@__axiom_symn_311 = private unnamed_addr constant [13 x i8] c"Show#Int#show"
@__axiom_symn_312 = private unnamed_addr constant [14 x i8] c"Show#Bool#show"
@__axiom_symn_313 = private unnamed_addr constant [15 x i8] c"Show#Float#show"
@__axiom_symn_314 = private unnamed_addr constant [20 x i8] c"__axiom_recover_save"
@__axiom_symn_315 = private unnamed_addr constant [20 x i8] c"__axiom_recover_load"
@__axiom_symtab = internal constant [948 x i64] [
  i64 ptrtoint (ptr @main to i64), i64 ptrtoint (ptr @__axiom_symn_0 to i64), i64 4,
  i64 ptrtoint (ptr @axiom_alloc to i64), i64 ptrtoint (ptr @__axiom_symn_1 to i64), i64 11,
  i64 ptrtoint (ptr @axiom_retain to i64), i64 ptrtoint (ptr @__axiom_symn_2 to i64), i64 12,
  i64 ptrtoint (ptr @axiom_release to i64), i64 ptrtoint (ptr @__axiom_symn_3 to i64), i64 13,
  i64 ptrtoint (ptr @__axiom_arena_mark_fn to i64), i64 ptrtoint (ptr @__axiom_symn_4 to i64), i64 21,
  i64 ptrtoint (ptr @__axiom_arena_reset_fn to i64), i64 ptrtoint (ptr @__axiom_symn_5 to i64), i64 22,
  i64 ptrtoint (ptr @__axiom_arena_reset_keeping_fn to i64), i64 ptrtoint (ptr @__axiom_symn_6 to i64), i64 30,
  i64 ptrtoint (ptr @__axiom_div_by_zero to i64), i64 ptrtoint (ptr @__axiom_symn_7 to i64), i64 19,
  i64 ptrtoint (ptr @__axiom_out_of_memory to i64), i64 ptrtoint (ptr @__axiom_symn_8 to i64), i64 21,
  i64 ptrtoint (ptr @__axiom_recover_abort to i64), i64 ptrtoint (ptr @__axiom_symn_9 to i64), i64 21,
  i64 ptrtoint (ptr @__axiom_str_eq to i64), i64 ptrtoint (ptr @__axiom_symn_10 to i64), i64 14,
  i64 ptrtoint (ptr @Sys.Platform$sysRead to i64), i64 ptrtoint (ptr @__axiom_symn_11 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sysWrite to i64), i64 ptrtoint (ptr @__axiom_symn_12 to i64), i64 21,
  i64 ptrtoint (ptr @Sys.Platform$sysOpen to i64), i64 ptrtoint (ptr @__axiom_symn_13 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sysClose to i64), i64 ptrtoint (ptr @__axiom_symn_14 to i64), i64 21,
  i64 ptrtoint (ptr @Sys.Platform$sysExit to i64), i64 ptrtoint (ptr @__axiom_symn_15 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sysLseek to i64), i64 ptrtoint (ptr @__axiom_symn_16 to i64), i64 21,
  i64 ptrtoint (ptr @Sys.Platform$openNeedsDirFd to i64), i64 ptrtoint (ptr @__axiom_symn_17 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$atFdCwd to i64), i64 ptrtoint (ptr @__axiom_symn_18 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$oRdonly to i64), i64 ptrtoint (ptr @__axiom_symn_19 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$oWronlyCreateTrunc to i64), i64 ptrtoint (ptr @__axiom_symn_20 to i64), i64 31,
  i64 ptrtoint (ptr @Sys.Platform$oWronlyCreateAppend to i64), i64 ptrtoint (ptr @__axiom_symn_21 to i64), i64 32,
  i64 ptrtoint (ptr @Sys.Platform$seekEnd to i64), i64 ptrtoint (ptr @__axiom_symn_22 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$seekSet to i64), i64 ptrtoint (ptr @__axiom_symn_23 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$spawnUsesPosixSpawn to i64), i64 ptrtoint (ptr @__axiom_symn_24 to i64), i64 32,
  i64 ptrtoint (ptr @Sys.Platform$sysFork to i64), i64 ptrtoint (ptr @__axiom_symn_25 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sysForkArg to i64), i64 ptrtoint (ptr @__axiom_symn_26 to i64), i64 23,
  i64 ptrtoint (ptr @Sys.Platform$sysExecve to i64), i64 ptrtoint (ptr @__axiom_symn_27 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$sysWait4 to i64), i64 ptrtoint (ptr @__axiom_symn_28 to i64), i64 21,
  i64 ptrtoint (ptr @Sys.Platform$sysPosixSpawn to i64), i64 ptrtoint (ptr @__axiom_symn_29 to i64), i64 26,
  i64 ptrtoint (ptr @Sys.Platform$sysUnlinkNum to i64), i64 ptrtoint (ptr @__axiom_symn_30 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysMkdirNum to i64), i64 ptrtoint (ptr @__axiom_symn_31 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$sysRmdirNum to i64), i64 ptrtoint (ptr @__axiom_symn_32 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$sysRenameNum to i64), i64 ptrtoint (ptr @__axiom_symn_33 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysGetdentsNum to i64), i64 ptrtoint (ptr @__axiom_symn_34 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$dirReadNeedsPosition to i64), i64 ptrtoint (ptr @__axiom_symn_35 to i64), i64 33,
  i64 ptrtoint (ptr @Sys.Platform$direntNameOffset to i64), i64 ptrtoint (ptr @__axiom_symn_36 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$cwdUsesFcntlPath to i64), i64 ptrtoint (ptr @__axiom_symn_37 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$sysCwdNum to i64), i64 ptrtoint (ptr @__axiom_symn_38 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$fGetPath to i64), i64 ptrtoint (ptr @__axiom_symn_39 to i64), i64 21,
  i64 ptrtoint (ptr @Sys.Platform$eExist to i64), i64 ptrtoint (ptr @__axiom_symn_40 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$eIsDir to i64), i64 ptrtoint (ptr @__axiom_symn_41 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$sysGetPidNum to i64), i64 ptrtoint (ptr @__axiom_symn_42 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysClockNum to i64), i64 ptrtoint (ptr @__axiom_symn_43 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$clockIsGettimeofday to i64), i64 ptrtoint (ptr @__axiom_symn_44 to i64), i64 32,
  i64 ptrtoint (ptr @Sys.Platform$clockHasMonotonic to i64), i64 ptrtoint (ptr @__axiom_symn_45 to i64), i64 30,
  i64 ptrtoint (ptr @Sys.Platform$sysSocketNum to i64), i64 ptrtoint (ptr @__axiom_symn_46 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysBindNum to i64), i64 ptrtoint (ptr @__axiom_symn_47 to i64), i64 23,
  i64 ptrtoint (ptr @Sys.Platform$sysListenNum to i64), i64 ptrtoint (ptr @__axiom_symn_48 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysAcceptNum to i64), i64 ptrtoint (ptr @__axiom_symn_49 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$sysConnectNum to i64), i64 ptrtoint (ptr @__axiom_symn_50 to i64), i64 26,
  i64 ptrtoint (ptr @Sys.Platform$sysSetSockOptNum to i64), i64 ptrtoint (ptr @__axiom_symn_51 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$sysGetSockOptNum to i64), i64 ptrtoint (ptr @__axiom_symn_52 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$sysShutdownNum to i64), i64 ptrtoint (ptr @__axiom_symn_53 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$sysFcntlNum to i64), i64 ptrtoint (ptr @__axiom_symn_54 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$afInet to i64), i64 ptrtoint (ptr @__axiom_symn_55 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$afInet6 to i64), i64 ptrtoint (ptr @__axiom_symn_56 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sockStream to i64), i64 ptrtoint (ptr @__axiom_symn_57 to i64), i64 23,
  i64 ptrtoint (ptr @Sys.Platform$solSocket to i64), i64 ptrtoint (ptr @__axiom_symn_58 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$soReuseAddr to i64), i64 ptrtoint (ptr @__axiom_symn_59 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$soReusePort to i64), i64 ptrtoint (ptr @__axiom_symn_60 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$soError to i64), i64 ptrtoint (ptr @__axiom_symn_61 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$fGetFl to i64), i64 ptrtoint (ptr @__axiom_symn_62 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$fSetFl to i64), i64 ptrtoint (ptr @__axiom_symn_63 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$oNonblock to i64), i64 ptrtoint (ptr @__axiom_symn_64 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$eAgain to i64), i64 ptrtoint (ptr @__axiom_symn_65 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$sockaddrHasLenByte to i64), i64 ptrtoint (ptr @__axiom_symn_66 to i64), i64 31,
  i64 ptrtoint (ptr @Sys.Platform$pollUsesKqueue to i64), i64 ptrtoint (ptr @__axiom_symn_67 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$sysPollCreateNum to i64), i64 ptrtoint (ptr @__axiom_symn_68 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$sysPollWaitNum to i64), i64 ptrtoint (ptr @__axiom_symn_69 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$sysPollCtlNum to i64), i64 ptrtoint (ptr @__axiom_symn_70 to i64), i64 26,
  i64 ptrtoint (ptr @Sys.Platform$pollEventSize to i64), i64 ptrtoint (ptr @__axiom_symn_71 to i64), i64 26,
  i64 ptrtoint (ptr @Sys.Platform$pollEventFdOffset to i64), i64 ptrtoint (ptr @__axiom_symn_72 to i64), i64 30,
  i64 ptrtoint (ptr @Sys.Platform$pollReadFilter to i64), i64 ptrtoint (ptr @__axiom_symn_73 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$pollAddOp to i64), i64 ptrtoint (ptr @__axiom_symn_74 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$pollDelOp to i64), i64 ptrtoint (ptr @__axiom_symn_75 to i64), i64 22,
  i64 ptrtoint (ptr @Sys.Platform$pollSigsetSize to i64), i64 ptrtoint (ptr @__axiom_symn_76 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$sysRandomNum to i64), i64 ptrtoint (ptr @__axiom_symn_77 to i64), i64 25,
  i64 ptrtoint (ptr @Sys.Platform$randomIsGetentropy to i64), i64 ptrtoint (ptr @__axiom_symn_78 to i64), i64 31,
  i64 ptrtoint (ptr @Sys.Platform$randomMaxChunk to i64), i64 ptrtoint (ptr @__axiom_symn_79 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$signalUsesSignalFd to i64), i64 ptrtoint (ptr @__axiom_symn_80 to i64), i64 31,
  i64 ptrtoint (ptr @Sys.Platform$sysSigProcMaskNum to i64), i64 ptrtoint (ptr @__axiom_symn_81 to i64), i64 30,
  i64 ptrtoint (ptr @Sys.Platform$sigBlockHow to i64), i64 ptrtoint (ptr @__axiom_symn_82 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$sigsetBytes to i64), i64 ptrtoint (ptr @__axiom_symn_83 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$sysSignalFdNum to i64), i64 ptrtoint (ptr @__axiom_symn_84 to i64), i64 27,
  i64 ptrtoint (ptr @Sys.Platform$sigInfoSize to i64), i64 ptrtoint (ptr @__axiom_symn_85 to i64), i64 24,
  i64 ptrtoint (ptr @Sys.Platform$pollSignalFilter to i64), i64 ptrtoint (ptr @__axiom_symn_86 to i64), i64 29,
  i64 ptrtoint (ptr @Sys.Platform$sysKillNum to i64), i64 ptrtoint (ptr @__axiom_symn_87 to i64), i64 23,
  i64 ptrtoint (ptr @Sys.Platform$sigTerm to i64), i64 ptrtoint (ptr @__axiom_symn_88 to i64), i64 20,
  i64 ptrtoint (ptr @Sys.Platform$sigInt to i64), i64 ptrtoint (ptr @__axiom_symn_89 to i64), i64 19,
  i64 ptrtoint (ptr @Sys.Platform$forkChildIsZero to i64), i64 ptrtoint (ptr @__axiom_symn_90 to i64), i64 28,
  i64 ptrtoint (ptr @Sys.Platform$acceptNonblockFlag to i64), i64 ptrtoint (ptr @__axiom_symn_91 to i64), i64 31,
  i64 ptrtoint (ptr @Mem$memAlloc to i64), i64 ptrtoint (ptr @__axiom_symn_92 to i64), i64 12,
  i64 ptrtoint (ptr @Mem$memAllocMapped to i64), i64 ptrtoint (ptr @__axiom_symn_93 to i64), i64 18,
  i64 ptrtoint (ptr @Mem$memMarkArray to i64), i64 ptrtoint (ptr @__axiom_symn_94 to i64), i64 16,
  i64 ptrtoint (ptr @Mem$memMarkLeaf to i64), i64 ptrtoint (ptr @__axiom_symn_95 to i64), i64 15,
  i64 ptrtoint (ptr @Mem$memCopy to i64), i64 ptrtoint (ptr @__axiom_symn_96 to i64), i64 11,
  i64 ptrtoint (ptr @Mem$memCopyFrom to i64), i64 ptrtoint (ptr @__axiom_symn_97 to i64), i64 15,
  i64 ptrtoint (ptr @Mem$memSet to i64), i64 ptrtoint (ptr @__axiom_symn_98 to i64), i64 10,
  i64 ptrtoint (ptr @Mem$memSetFrom to i64), i64 ptrtoint (ptr @__axiom_symn_99 to i64), i64 14,
  i64 ptrtoint (ptr @Mem$memCmp to i64), i64 ptrtoint (ptr @__axiom_symn_100 to i64), i64 10,
  i64 ptrtoint (ptr @Mem$memCmpFrom to i64), i64 ptrtoint (ptr @__axiom_symn_101 to i64), i64 14,
  i64 ptrtoint (ptr @Mem$memGetWord to i64), i64 ptrtoint (ptr @__axiom_symn_102 to i64), i64 14,
  i64 ptrtoint (ptr @Mem$memGetWordStr to i64), i64 ptrtoint (ptr @__axiom_symn_103 to i64), i64 17,
  i64 ptrtoint (ptr @Mem$memSetWord to i64), i64 ptrtoint (ptr @__axiom_symn_104 to i64), i64 14,
  i64 ptrtoint (ptr @Mem$memGetByte to i64), i64 ptrtoint (ptr @__axiom_symn_105 to i64), i64 14,
  i64 ptrtoint (ptr @Mem$memPutByte to i64), i64 ptrtoint (ptr @__axiom_symn_106 to i64), i64 14,
  i64 ptrtoint (ptr @Vec$vecDefaultCap to i64), i64 ptrtoint (ptr @__axiom_symn_107 to i64), i64 17,
  i64 ptrtoint (ptr @Vec$vecNew to i64), i64 ptrtoint (ptr @__axiom_symn_108 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecWithCapacity to i64), i64 ptrtoint (ptr @__axiom_symn_109 to i64), i64 19,
  i64 ptrtoint (ptr @Vec$vecWithCapacityRef to i64), i64 ptrtoint (ptr @__axiom_symn_110 to i64), i64 22,
  i64 ptrtoint (ptr @Vec$vecNewRef to i64), i64 ptrtoint (ptr @__axiom_symn_111 to i64), i64 13,
  i64 ptrtoint (ptr @Vec$vecBuild to i64), i64 ptrtoint (ptr @__axiom_symn_112 to i64), i64 12,
  i64 ptrtoint (ptr @Vec$vecFree to i64), i64 ptrtoint (ptr @__axiom_symn_113 to i64), i64 11,
  i64 ptrtoint (ptr @Vec$vecOwnsRefs to i64), i64 ptrtoint (ptr @__axiom_symn_114 to i64), i64 15,
  i64 ptrtoint (ptr @Vec$vecLen to i64), i64 ptrtoint (ptr @__axiom_symn_115 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecCap to i64), i64 ptrtoint (ptr @__axiom_symn_116 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecData to i64), i64 ptrtoint (ptr @__axiom_symn_117 to i64), i64 11,
  i64 ptrtoint (ptr @Vec$vecGet to i64), i64 ptrtoint (ptr @__axiom_symn_118 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecTry to i64), i64 ptrtoint (ptr @__axiom_symn_119 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecGetStr to i64), i64 ptrtoint (ptr @__axiom_symn_120 to i64), i64 13,
  i64 ptrtoint (ptr @Vec$vecSet to i64), i64 ptrtoint (ptr @__axiom_symn_121 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecReserve to i64), i64 ptrtoint (ptr @__axiom_symn_122 to i64), i64 14,
  i64 ptrtoint (ptr @Vec$vecGrownCap to i64), i64 ptrtoint (ptr @__axiom_symn_123 to i64), i64 15,
  i64 ptrtoint (ptr @Vec$vecReserveExactly to i64), i64 ptrtoint (ptr @__axiom_symn_124 to i64), i64 21,
  i64 ptrtoint (ptr @Vec$vecPush to i64), i64 ptrtoint (ptr @__axiom_symn_125 to i64), i64 11,
  i64 ptrtoint (ptr @Vec$vecPop to i64), i64 ptrtoint (ptr @__axiom_symn_126 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecLast to i64), i64 ptrtoint (ptr @__axiom_symn_127 to i64), i64 11,
  i64 ptrtoint (ptr @Vec$vecClear to i64), i64 ptrtoint (ptr @__axiom_symn_128 to i64), i64 12,
  i64 ptrtoint (ptr @Vec$vecDropAt to i64), i64 ptrtoint (ptr @__axiom_symn_129 to i64), i64 13,
  i64 ptrtoint (ptr @Vec$vecDropFrom to i64), i64 ptrtoint (ptr @__axiom_symn_130 to i64), i64 15,
  i64 ptrtoint (ptr @Vec$vecSum to i64), i64 ptrtoint (ptr @__axiom_symn_131 to i64), i64 10,
  i64 ptrtoint (ptr @Vec$vecSumFrom to i64), i64 ptrtoint (ptr @__axiom_symn_132 to i64), i64 14,
  i64 ptrtoint (ptr @Vec$vecHash to i64), i64 ptrtoint (ptr @__axiom_symn_133 to i64), i64 11,
  i64 ptrtoint (ptr @Vec$vecHashFrom to i64), i64 ptrtoint (ptr @__axiom_symn_134 to i64), i64 15,
  i64 ptrtoint (ptr @Str$strWrap to i64), i64 ptrtoint (ptr @__axiom_symn_135 to i64), i64 11,
  i64 ptrtoint (ptr @Str$strWrapOwned to i64), i64 ptrtoint (ptr @__axiom_symn_136 to i64), i64 16,
  i64 ptrtoint (ptr @Str$strAlloc to i64), i64 ptrtoint (ptr @__axiom_symn_137 to i64), i64 12,
  i64 ptrtoint (ptr @Str$strFromLit to i64), i64 ptrtoint (ptr @__axiom_symn_138 to i64), i64 14,
  i64 ptrtoint (ptr @Str$cstrLen to i64), i64 ptrtoint (ptr @__axiom_symn_139 to i64), i64 11,
  i64 ptrtoint (ptr @Str$strLen to i64), i64 ptrtoint (ptr @__axiom_symn_140 to i64), i64 10,
  i64 ptrtoint (ptr @Str$strData to i64), i64 ptrtoint (ptr @__axiom_symn_141 to i64), i64 11,
  i64 ptrtoint (ptr @Str$strOwner to i64), i64 ptrtoint (ptr @__axiom_symn_142 to i64), i64 12,
  i64 ptrtoint (ptr @Str$strByte to i64), i64 ptrtoint (ptr @__axiom_symn_143 to i64), i64 11,
  i64 ptrtoint (ptr @Str$strCStr to i64), i64 ptrtoint (ptr @__axiom_symn_144 to i64), i64 11,
  i64 ptrtoint (ptr @Str$strIsEmpty to i64), i64 ptrtoint (ptr @__axiom_symn_145 to i64), i64 14,
  i64 ptrtoint (ptr @Str$strCmp to i64), i64 ptrtoint (ptr @__axiom_symn_146 to i64), i64 10,
  i64 ptrtoint (ptr @Str$strEq to i64), i64 ptrtoint (ptr @__axiom_symn_147 to i64), i64 9,
  i64 ptrtoint (ptr @Str$strSlice to i64), i64 ptrtoint (ptr @__axiom_symn_148 to i64), i64 12,
  i64 ptrtoint (ptr @Str$strDup to i64), i64 ptrtoint (ptr @__axiom_symn_149 to i64), i64 10,
  i64 ptrtoint (ptr @Str$strConcat to i64), i64 ptrtoint (ptr @__axiom_symn_150 to i64), i64 13,
  i64 ptrtoint (ptr @Str$strFindByte to i64), i64 ptrtoint (ptr @__axiom_symn_151 to i64), i64 15,
  i64 ptrtoint (ptr @Str$strStartsWith to i64), i64 ptrtoint (ptr @__axiom_symn_152 to i64), i64 17,
  i64 ptrtoint (ptr @Str$strIsDigit to i64), i64 ptrtoint (ptr @__axiom_symn_153 to i64), i64 14,
  i64 ptrtoint (ptr @Str$strIsAlpha to i64), i64 ptrtoint (ptr @__axiom_symn_154 to i64), i64 14,
  i64 ptrtoint (ptr @Str$strIsSpace to i64), i64 ptrtoint (ptr @__axiom_symn_155 to i64), i64 14,
  i64 ptrtoint (ptr @Str$strHexVal to i64), i64 ptrtoint (ptr @__axiom_symn_156 to i64), i64 13,
  i64 ptrtoint (ptr @Str$strIsHexDigit to i64), i64 ptrtoint (ptr @__axiom_symn_157 to i64), i64 17,
  i64 ptrtoint (ptr @Str$strSplit to i64), i64 ptrtoint (ptr @__axiom_symn_158 to i64), i64 12,
  i64 ptrtoint (ptr @Str$strSplitFrom to i64), i64 ptrtoint (ptr @__axiom_symn_159 to i64), i64 16,
  i64 ptrtoint (ptr @Str$strFromByte to i64), i64 ptrtoint (ptr @__axiom_symn_160 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$intIsMostNegative to i64), i64 ptrtoint (ptr @__axiom_symn_161 to i64), i64 21,
  i64 ptrtoint (ptr @Fmt$fmtIntWidth to i64), i64 ptrtoint (ptr @__axiom_symn_162 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$fmtInt to i64), i64 ptrtoint (ptr @__axiom_symn_163 to i64), i64 10,
  i64 ptrtoint (ptr @Fmt$fmtNat to i64), i64 ptrtoint (ptr @__axiom_symn_164 to i64), i64 10,
  i64 ptrtoint (ptr @Fmt$fmtDigits to i64), i64 ptrtoint (ptr @__axiom_symn_165 to i64), i64 13,
  i64 ptrtoint (ptr @Fmt$fmtHexShr4 to i64), i64 ptrtoint (ptr @__axiom_symn_166 to i64), i64 14,
  i64 ptrtoint (ptr @Fmt$fmtHex to i64), i64 ptrtoint (ptr @__axiom_symn_167 to i64), i64 10,
  i64 ptrtoint (ptr @Fmt$fmtHexWidth to i64), i64 ptrtoint (ptr @__axiom_symn_168 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$fmtHexDigits to i64), i64 ptrtoint (ptr @__axiom_symn_169 to i64), i64 16,
  i64 ptrtoint (ptr @Fmt$fmtPadLeft to i64), i64 ptrtoint (ptr @__axiom_symn_170 to i64), i64 14,
  i64 ptrtoint (ptr @Fmt$fmtPadRight to i64), i64 ptrtoint (ptr @__axiom_symn_171 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$fmtPadCenter to i64), i64 ptrtoint (ptr @__axiom_symn_172 to i64), i64 16,
  i64 ptrtoint (ptr @Fmt$fmtPadZerosLeft to i64), i64 ptrtoint (ptr @__axiom_symn_173 to i64), i64 19,
  i64 ptrtoint (ptr @Fmt$fmtHexUpper to i64), i64 ptrtoint (ptr @__axiom_symn_174 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$fmtHexDigitsUpper to i64), i64 ptrtoint (ptr @__axiom_symn_175 to i64), i64 21,
  i64 ptrtoint (ptr @Fmt$powTen to i64), i64 ptrtoint (ptr @__axiom_symn_176 to i64), i64 10,
  i64 ptrtoint (ptr @Fmt$fmtPadZeros to i64), i64 ptrtoint (ptr @__axiom_symn_177 to i64), i64 15,
  i64 ptrtoint (ptr @Fmt$fmtFloat to i64), i64 ptrtoint (ptr @__axiom_symn_178 to i64), i64 12,
  i64 ptrtoint (ptr @Fmt$fmtFloatPrec to i64), i64 ptrtoint (ptr @__axiom_symn_179 to i64), i64 16,
  i64 ptrtoint (ptr @Fmt$fmtFloatAbs to i64), i64 ptrtoint (ptr @__axiom_symn_180 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$stdin to i64), i64 ptrtoint (ptr @__axiom_symn_181 to i64), i64 9,
  i64 ptrtoint (ptr @Sys$stdout to i64), i64 ptrtoint (ptr @__axiom_symn_182 to i64), i64 10,
  i64 ptrtoint (ptr @Sys$stderr to i64), i64 ptrtoint (ptr @__axiom_symn_183 to i64), i64 10,
  i64 ptrtoint (ptr @Sys$sysWriteFd to i64), i64 ptrtoint (ptr @__axiom_symn_184 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysWriteAllFd to i64), i64 ptrtoint (ptr @__axiom_symn_185 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$sysReadFd to i64), i64 ptrtoint (ptr @__axiom_symn_186 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysOpenPath to i64), i64 ptrtoint (ptr @__axiom_symn_187 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysOpenPathMode to i64), i64 ptrtoint (ptr @__axiom_symn_188 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$sysCloseFd to i64), i64 ptrtoint (ptr @__axiom_symn_189 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysSeek to i64), i64 ptrtoint (ptr @__axiom_symn_190 to i64), i64 11,
  i64 ptrtoint (ptr @Sys$sysExitWith to i64), i64 ptrtoint (ptr @__axiom_symn_191 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysFailed to i64), i64 ptrtoint (ptr @__axiom_symn_192 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysErrno to i64), i64 ptrtoint (ptr @__axiom_symn_193 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$sysReadFile to i64), i64 ptrtoint (ptr @__axiom_symn_194 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysReadAll to i64), i64 ptrtoint (ptr @__axiom_symn_195 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysArgc to i64), i64 ptrtoint (ptr @__axiom_symn_196 to i64), i64 11,
  i64 ptrtoint (ptr @Sys$sysArg to i64), i64 ptrtoint (ptr @__axiom_symn_197 to i64), i64 10,
  i64 ptrtoint (ptr @Sys$sysWriteFile to i64), i64 ptrtoint (ptr @__axiom_symn_198 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$sysAppendFile to i64), i64 ptrtoint (ptr @__axiom_symn_199 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$sysRename to i64), i64 ptrtoint (ptr @__axiom_symn_200 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysUnlink to i64), i64 ptrtoint (ptr @__axiom_symn_201 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysMkdir to i64), i64 ptrtoint (ptr @__axiom_symn_202 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$sysDirMode to i64), i64 ptrtoint (ptr @__axiom_symn_203 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysRmdir to i64), i64 ptrtoint (ptr @__axiom_symn_204 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$sysFileExists to i64), i64 ptrtoint (ptr @__axiom_symn_205 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$sysFileSize to i64), i64 ptrtoint (ptr @__axiom_symn_206 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysReadErrno to i64), i64 ptrtoint (ptr @__axiom_symn_207 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$sysIsDir to i64), i64 ptrtoint (ptr @__axiom_symn_208 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$sysDirBufBytes to i64), i64 ptrtoint (ptr @__axiom_symn_209 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$sysReadDir to i64), i64 ptrtoint (ptr @__axiom_symn_210 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysReadDirLoop to i64), i64 ptrtoint (ptr @__axiom_symn_211 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$sysReadDirDecode to i64), i64 ptrtoint (ptr @__axiom_symn_212 to i64), i64 20,
  i64 ptrtoint (ptr @Sys$sysGetCwd to i64), i64 ptrtoint (ptr @__axiom_symn_213 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysEnvSlot to i64), i64 ptrtoint (ptr @__axiom_symn_214 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysEnvCount to i64), i64 ptrtoint (ptr @__axiom_symn_215 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysEnvCountFrom to i64), i64 ptrtoint (ptr @__axiom_symn_216 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$sysEnv to i64), i64 ptrtoint (ptr @__axiom_symn_217 to i64), i64 10,
  i64 ptrtoint (ptr @Sys$sysEnvLookup to i64), i64 ptrtoint (ptr @__axiom_symn_218 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$sysEnvp to i64), i64 ptrtoint (ptr @__axiom_symn_219 to i64), i64 11,
  i64 ptrtoint (ptr @Sys$sysEnvpFill to i64), i64 ptrtoint (ptr @__axiom_symn_220 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysSpawn to i64), i64 ptrtoint (ptr @__axiom_symn_221 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$sysWaitPid to i64), i64 ptrtoint (ptr @__axiom_symn_222 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysExitCode to i64), i64 ptrtoint (ptr @__axiom_symn_223 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysTermSignal to i64), i64 ptrtoint (ptr @__axiom_symn_224 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$sysRun to i64), i64 ptrtoint (ptr @__axiom_symn_225 to i64), i64 10,
  i64 ptrtoint (ptr @Sys$sysRunPath to i64), i64 ptrtoint (ptr @__axiom_symn_226 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$sysRunSearch to i64), i64 ptrtoint (ptr @__axiom_symn_227 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$sysGetPid to i64), i64 ptrtoint (ptr @__axiom_symn_228 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysNowMicros to i64), i64 ptrtoint (ptr @__axiom_symn_229 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$sysNowMonotonic to i64), i64 ptrtoint (ptr @__axiom_symn_230 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$netSocketTcp to i64), i64 ptrtoint (ptr @__axiom_symn_231 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$netSocketTcp6 to i64), i64 ptrtoint (ptr @__axiom_symn_232 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netAddr4Bytes to i64), i64 ptrtoint (ptr @__axiom_symn_233 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netAddr6Bytes to i64), i64 ptrtoint (ptr @__axiom_symn_234 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netAddrMaxBytes to i64), i64 ptrtoint (ptr @__axiom_symn_235 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$netAddr4 to i64), i64 ptrtoint (ptr @__axiom_symn_236 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$netAddr6 to i64), i64 ptrtoint (ptr @__axiom_symn_237 to i64), i64 12,
  i64 ptrtoint (ptr @Sys$netPutGroup to i64), i64 ptrtoint (ptr @__axiom_symn_238 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netGetGroup to i64), i64 ptrtoint (ptr @__axiom_symn_239 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netAddrFamily to i64), i64 ptrtoint (ptr @__axiom_symn_240 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netAddrPort to i64), i64 ptrtoint (ptr @__axiom_symn_241 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netAddrSize to i64), i64 ptrtoint (ptr @__axiom_symn_242 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netBind to i64), i64 ptrtoint (ptr @__axiom_symn_243 to i64), i64 11,
  i64 ptrtoint (ptr @Sys$netListen to i64), i64 ptrtoint (ptr @__axiom_symn_244 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$netAccept to i64), i64 ptrtoint (ptr @__axiom_symn_245 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$netAcceptFinish to i64), i64 ptrtoint (ptr @__axiom_symn_246 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$netAcceptFrom to i64), i64 ptrtoint (ptr @__axiom_symn_247 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netAddrLenRead to i64), i64 ptrtoint (ptr @__axiom_symn_248 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netPutInt32 to i64), i64 ptrtoint (ptr @__axiom_symn_249 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netGetInt32 to i64), i64 ptrtoint (ptr @__axiom_symn_250 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netAddrText to i64), i64 ptrtoint (ptr @__axiom_symn_251 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netAddrText4 to i64), i64 ptrtoint (ptr @__axiom_symn_252 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$netAddrZeroRun to i64), i64 ptrtoint (ptr @__axiom_symn_253 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netAddrZeroRunStart to i64), i64 ptrtoint (ptr @__axiom_symn_254 to i64), i64 23,
  i64 ptrtoint (ptr @Sys$netAddrText6 to i64), i64 ptrtoint (ptr @__axiom_symn_255 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$netAddrTextPort to i64), i64 ptrtoint (ptr @__axiom_symn_256 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$netSetBlocking to i64), i64 ptrtoint (ptr @__axiom_symn_257 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netConnect to i64), i64 ptrtoint (ptr @__axiom_symn_258 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$netShutdown to i64), i64 ptrtoint (ptr @__axiom_symn_259 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netSetOptInt to i64), i64 ptrtoint (ptr @__axiom_symn_260 to i64), i64 16,
  i64 ptrtoint (ptr @Sys$netSetNonBlocking to i64), i64 ptrtoint (ptr @__axiom_symn_261 to i64), i64 21,
  i64 ptrtoint (ptr @Sys$netWouldBlock to i64), i64 ptrtoint (ptr @__axiom_symn_262 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netPutWord to i64), i64 ptrtoint (ptr @__axiom_symn_263 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$netGetWord to i64), i64 ptrtoint (ptr @__axiom_symn_264 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$netPollBufBytes to i64), i64 ptrtoint (ptr @__axiom_symn_265 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$netPollCreate to i64), i64 ptrtoint (ptr @__axiom_symn_266 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netPollRec to i64), i64 ptrtoint (ptr @__axiom_symn_267 to i64), i64 14,
  i64 ptrtoint (ptr @Sys$netPollAddRead to i64), i64 ptrtoint (ptr @__axiom_symn_268 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netPollDelRead to i64), i64 ptrtoint (ptr @__axiom_symn_269 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netPollWait to i64), i64 ptrtoint (ptr @__axiom_symn_270 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$netPollFdAt to i64), i64 ptrtoint (ptr @__axiom_symn_271 to i64), i64 15,
  i64 ptrtoint (ptr @Sys$sysRandomBytes to i64), i64 ptrtoint (ptr @__axiom_symn_272 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$sysSigBit to i64), i64 ptrtoint (ptr @__axiom_symn_273 to i64), i64 13,
  i64 ptrtoint (ptr @Sys$sysSignalBlock to i64), i64 ptrtoint (ptr @__axiom_symn_274 to i64), i64 18,
  i64 ptrtoint (ptr @Sys$netSignalOpen to i64), i64 ptrtoint (ptr @__axiom_symn_275 to i64), i64 17,
  i64 ptrtoint (ptr @Sys$netPollSignalAt to i64), i64 ptrtoint (ptr @__axiom_symn_276 to i64), i64 19,
  i64 ptrtoint (ptr @Sys$sysKill to i64), i64 ptrtoint (ptr @__axiom_symn_277 to i64), i64 11,
  i64 ptrtoint (ptr @Sys$sysForkProcess to i64), i64 ptrtoint (ptr @__axiom_symn_278 to i64), i64 18,
  i64 ptrtoint (ptr @IO$writeStr to i64), i64 ptrtoint (ptr @__axiom_symn_279 to i64), i64 11,
  i64 ptrtoint (ptr @IO$printLit to i64), i64 ptrtoint (ptr @__axiom_symn_280 to i64), i64 11,
  i64 ptrtoint (ptr @IO$printlnLit to i64), i64 ptrtoint (ptr @__axiom_symn_281 to i64), i64 13,
  i64 ptrtoint (ptr @IO$readFileLit to i64), i64 ptrtoint (ptr @__axiom_symn_282 to i64), i64 14,
  i64 ptrtoint (ptr @IO$readFile to i64), i64 ptrtoint (ptr @__axiom_symn_283 to i64), i64 11,
  i64 ptrtoint (ptr @IO$ioPath to i64), i64 ptrtoint (ptr @__axiom_symn_284 to i64), i64 9,
  i64 ptrtoint (ptr @IO$writeFile to i64), i64 ptrtoint (ptr @__axiom_symn_285 to i64), i64 12,
  i64 ptrtoint (ptr @IO$appendFile to i64), i64 ptrtoint (ptr @__axiom_symn_286 to i64), i64 13,
  i64 ptrtoint (ptr @IO$removeFile to i64), i64 ptrtoint (ptr @__axiom_symn_287 to i64), i64 13,
  i64 ptrtoint (ptr @IO$renamePath to i64), i64 ptrtoint (ptr @__axiom_symn_288 to i64), i64 13,
  i64 ptrtoint (ptr @IO$copyFile to i64), i64 ptrtoint (ptr @__axiom_symn_289 to i64), i64 11,
  i64 ptrtoint (ptr @IO$fileExists to i64), i64 ptrtoint (ptr @__axiom_symn_290 to i64), i64 13,
  i64 ptrtoint (ptr @IO$isDir to i64), i64 ptrtoint (ptr @__axiom_symn_291 to i64), i64 8,
  i64 ptrtoint (ptr @IO$fileSize to i64), i64 ptrtoint (ptr @__axiom_symn_292 to i64), i64 11,
  i64 ptrtoint (ptr @IO$readErrno to i64), i64 ptrtoint (ptr @__axiom_symn_293 to i64), i64 12,
  i64 ptrtoint (ptr @IO$makeDir to i64), i64 ptrtoint (ptr @__axiom_symn_294 to i64), i64 10,
  i64 ptrtoint (ptr @IO$makeDirAll to i64), i64 ptrtoint (ptr @__axiom_symn_295 to i64), i64 13,
  i64 ptrtoint (ptr @IO$makeDirAllFrom to i64), i64 ptrtoint (ptr @__axiom_symn_296 to i64), i64 17,
  i64 ptrtoint (ptr @IO$makeDirOk to i64), i64 ptrtoint (ptr @__axiom_symn_297 to i64), i64 12,
  i64 ptrtoint (ptr @IO$removeDir to i64), i64 ptrtoint (ptr @__axiom_symn_298 to i64), i64 12,
  i64 ptrtoint (ptr @IO$listDir to i64), i64 ptrtoint (ptr @__axiom_symn_299 to i64), i64 10,
  i64 ptrtoint (ptr @IO$listDirKeep to i64), i64 ptrtoint (ptr @__axiom_symn_300 to i64), i64 14,
  i64 ptrtoint (ptr @IO$listDirInsert to i64), i64 ptrtoint (ptr @__axiom_symn_301 to i64), i64 16,
  i64 ptrtoint (ptr @IO$listDirSift to i64), i64 ptrtoint (ptr @__axiom_symn_302 to i64), i64 14,
  i64 ptrtoint (ptr @IO$cwd to i64), i64 ptrtoint (ptr @__axiom_symn_303 to i64), i64 6,
  i64 ptrtoint (ptr @IO$exit to i64), i64 ptrtoint (ptr @__axiom_symn_304 to i64), i64 7,
  i64 ptrtoint (ptr @IO$die to i64), i64 ptrtoint (ptr @__axiom_symn_305 to i64), i64 6,
  i64 ptrtoint (ptr @ask to i64), i64 ptrtoint (ptr @__axiom_symn_306 to i64), i64 3,
  i64 ptrtoint (ptr @usable to i64), i64 ptrtoint (ptr @__axiom_symn_307 to i64), i64 6,
  i64 ptrtoint (ptr @__axiom_user_main to i64), i64 ptrtoint (ptr @__axiom_symn_308 to i64), i64 17,
  i64 ptrtoint (ptr @_lam_0 to i64), i64 ptrtoint (ptr @__axiom_symn_309 to i64), i64 6,
  i64 ptrtoint (ptr @"Show#String#show" to i64), i64 ptrtoint (ptr @__axiom_symn_310 to i64), i64 16,
  i64 ptrtoint (ptr @"Show#Int#show" to i64), i64 ptrtoint (ptr @__axiom_symn_311 to i64), i64 13,
  i64 ptrtoint (ptr @"Show#Bool#show" to i64), i64 ptrtoint (ptr @__axiom_symn_312 to i64), i64 14,
  i64 ptrtoint (ptr @"Show#Float#show" to i64), i64 ptrtoint (ptr @__axiom_symn_313 to i64), i64 15,
  i64 ptrtoint (ptr @__axiom_recover_save to i64), i64 ptrtoint (ptr @__axiom_symn_314 to i64), i64 20,
  i64 ptrtoint (ptr @__axiom_recover_load to i64), i64 ptrtoint (ptr @__axiom_symn_315 to i64), i64 20
]
@__axiom_symtab_n = internal constant i64 316
@__axiom_bt_hdr = private unnamed_addr constant [42 x i8] c"axiom: backtrace (most recent call first)\0A"
@__axiom_bt_at = private unnamed_addr constant [5 x i8] c"  at "
@__axiom_bt_nl = private unnamed_addr constant [1 x i8] c"\0A"
@__axiom_bt_unk = private unnamed_addr constant [9 x i8] c"<unknown>"
@__axiom_bt_mainaddr = internal constant i64 ptrtoint (ptr @main to i64)

define internal i64 @__axiom_bt_name(i64 %ra) #0 {
entry:
  %pc = sub i64 %ra, 1
  br label %scan
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %ba = phi i64 [ 0, %entry ], [ %ba1, %next ]
  %bn = phi i64 [ 0, %entry ], [ %bn1, %next ]
  %bl = phi i64 [ 0, %entry ], [ %bl1, %next ]
  %fin = icmp uge i64 %i, 316
  br i1 %fin, label %emit, label %body
body:
  %i3 = mul i64 %i, 3
  %pa = getelementptr [948 x i64], ptr @__axiom_symtab, i64 0, i64 %i3
  %a = load i64, ptr %pa
  %j1 = add i64 %i3, 1
  %pn = getelementptr [948 x i64], ptr @__axiom_symtab, i64 0, i64 %j1
  %nm = load i64, ptr %pn
  %j2 = add i64 %i3, 2
  %pl = getelementptr [948 x i64], ptr @__axiom_symtab, i64 0, i64 %j2
  %ln = load i64, ptr %pl
  %le = icmp ule i64 %a, %pc
  %gt = icmp ugt i64 %a, %ba
  %take = and i1 %le, %gt
  br label %next
next:
  %ba1 = select i1 %take, i64 %a, i64 %ba
  %bn1 = select i1 %take, i64 %nm, i64 %bn
  %bl1 = select i1 %take, i64 %ln, i64 %bl
  %i1 = add i64 %i, 1
  br label %scan
emit:
  %atp = ptrtoint ptr @__axiom_bt_at to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %atp, i64 5, i64 0, i64 0, i64 0)
  %found = icmp ne i64 %bn, 0
  br i1 %found, label %named, label %unknown
named:
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %bn, i64 %bl, i64 0, i64 0, i64 0)
  br label %eol
unknown:
  %unp = ptrtoint ptr @__axiom_bt_unk to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %unp, i64 9, i64 0, i64 0, i64 0)
  br label %eol
eol:
  %nlp = ptrtoint ptr @__axiom_bt_nl to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %nlp, i64 1, i64 0, i64 0, i64 0)
  ret i64 %ba
}

define internal void @__axiom_backtrace() #0 {
entry:
  %hp = ptrtoint ptr @__axiom_bt_hdr to i64
  call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %hp, i64 42, i64 0, i64 0, i64 0)
  %fpi = call i64 asm sideeffect "mov $0, x29", "=r"()
  br label %loop
loop:
  %fp = phi i64 [ %fpi, %entry ], [ %nx, %frame ]
  %d = phi i64 [ 0, %entry ], [ %d1, %frame ]
  %deep = icmp uge i64 %d, 64
  %fpz = icmp eq i64 %fp, 0
  %mis = and i64 %fp, 7
  %misb = icmp ne i64 %mis, 0
  %s0 = or i1 %deep, %fpz
  %stop = or i1 %s0, %misb
  br i1 %stop, label %done, label %read
read:
  %fpp = inttoptr i64 %fp to ptr
  %nx = load i64, ptr %fpp
  %raa = add i64 %fp, 8
  %rap = inttoptr i64 %raa to ptr
  %ra = load i64, ptr %rap
  %raz = icmp eq i64 %ra, 0
  br i1 %raz, label %done, label %frame
frame:
  %at = call i64 @__axiom_bt_name(i64 %ra)
  %ma = load i64, ptr @__axiom_bt_mainaddr
  %ismain = icmp eq i64 %at, %ma
  %ismain0 = xor i1 %ismain, true
  %d1 = add i64 %d, 1
  %up = icmp ugt i64 %nx, %fp
  %go = and i1 %up, %ismain0
  br i1 %go, label %loop, label %done
done:
  ret void
}

attributes #0 = { "no-builtins" "frame-pointer"="all" }
