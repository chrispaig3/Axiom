//! A conservative, non-moving mark-sweep collector, emitted as LLVM
//! text alongside the program.
//!
//! # Why conservative, and why non-moving
//!
//! Axiom has one runtime representation: every value is a machine word.
//! A word holding `8` is the integer 8, or the address of a heap block,
//! and nothing at runtime distinguishes them. Only `data` cells carry a
//! tag, and even there a *field* is just a word. Everything else -
//! `Str`, `Vec`, `Map`, every `struct`, every buffer - comes from
//! `__alloc`, which is untyped by contract.
//!
//! A precise collector needs a pointer map per object, which that model
//! cannot supply without changing what `__alloc` means. A conservative
//! one needs no such thing: it treats any word that *could* be a pointer
//! to a live object as if it were one. The cost is false retention - an
//! integer that happens to equal a live object's address keeps it alive.
//! The benefit is that it is sound without a single change to how values
//! are represented.
//!
//! Conservatism forces non-moving. A collector that relocates has to
//! rewrite the pointers it found, and rewriting a word that was actually
//! an integer is silent corruption. Marking in place never touches a
//! value it guessed wrong about. Non-moving also preserves pointer
//! identity, which the standard library depends on: `vecPush` returns
//! the same handle it was given, and `memSetWord` mutates through it.
//!
//! An earlier attempt (`ArenaCompact`) went the other way - it moved
//! objects, identified them by reading word 0 and hoping it was a tag,
//! and could not see `Str` or `Vec` at all. It corrupted memory, and no
//! amount of repair would have fixed the premise.
//!
//! # Heap layout
//!
//! Chunks come from `mmap` and are linked through word 0. Each carries a
//! bitmap with one bit per 16-byte granule of its payload, set at the
//! granule where an object's *payload* begins. That bitmap is what makes
//! a candidate word checkable: a pointer is real only if it lands in
//! some chunk's allocated range, is 16-byte aligned relative to that
//! chunk's payload, and has its bit set. Interior pointers are not
//! recognised, which is fine because Axiom never stores one - `strData`
//! and `vecData` both yield block starts.
//!
//! ```text
//! chunk:  [next][bitmap][payload][bump][end]  (5 words, 64-byte header)
//!         [ bitmap bytes ]
//!         [ object ][ object ]...        object: [header(16)][payload]
//! ```
//!
//! An object header is two words; only the first is used, so that a
//! payload stays 16-byte aligned. It packs the payload size with three
//! flags: `size << 3 | scanned << 2 | free << 1 | mark`.
//!
//! # Roots
//!
//! The machine stack between the current stack pointer and the frame
//! address recorded on entry to `main`, scanned word by word, plus the
//! callee-saved registers - which are spilled into that range first by
//! an empty `asm` that clobbers them. Registers matter: a pointer whose
//! only copy is in a callee-saved register is invisible to a memory
//! scan, and the object would be freed under it.
//!
//! Axiom emits no mutable globals today, so there is no global root set.
//! If it gains them, they have to be scanned here.

use crate::target::Target;
use std::fmt::Write;

/// Bytes per chunk. Large enough that the slow path is rare, small
/// enough that a trivial program does not commit a lot of address
/// space.
const CHUNK: i64 = 1024 * 1024;
/// Bytes of chunk header, before the bitmap.
const CHUNK_HDR: i64 = 64;
/// Bytes per bitmap granule; also the payload alignment and the
/// allocation quantum.
const GRAIN: i64 = 16;
/// Bytes of object header. Two words, so the payload stays aligned.
const OBJ_HDR: i64 = 16;
/// Exact-fit free-list classes. Index `n / 16` for `n` up to
/// `(SMALL_CLASSES - 1) * 16` bytes; everything larger shares the last
/// list and is first-fit.
const SMALL_CLASSES: i64 = 64;
/// Entries in the mark stack. Overflow abandons the collection rather
/// than dropping a reachable object.
const MARK_SLOTS: i64 = 1 << 17;

pub struct GcEmitter {
    out: String,
    n: u64,
    target: Target,
    /// Mutable globals to mark from during the root phase, beyond the
    /// machine stack and registers. Today these are the effect
    /// evidence slots: an installed handler chain's only reference is
    /// its slot, so a collector blind to them frees a live handler.
    global_roots: Vec<String>,
}

impl GcEmitter {
    pub fn new(target: Target) -> Self {
        Self {
            out: String::new(),
            n: 0,
            target,
            global_roots: Vec::new(),
        }
    }

    pub fn with_global_roots(mut self, roots: Vec<String>) -> Self {
        self.global_roots = roots;
        self
    }

    fn r(&mut self) -> String {
        self.n += 1;
        format!("%g{}", self.n)
    }

    fn l(&mut self, s: &str) {
        self.out.push_str(s);
        self.out.push('\n');
    }

    fn lf(&mut self, args: std::fmt::Arguments) {
        writeln!(self.out, "{}", args).unwrap();
    }

    /// Load the word at `addr` (a register holding an integer address).
    fn ld(&mut self, addr: &str) -> String {
        let p = self.r();
        self.lf(format_args!("  {} = inttoptr i64 {} to ptr", p, addr));
        let v = self.r();
        self.lf(format_args!("  {} = load i64, ptr {}", v, p));
        v
    }

    /// Load the word at `base + index * 8`.
    fn ldi(&mut self, base: &str, index: i64) -> String {
        let a = self.r();
        self.lf(format_args!("  {} = add i64 {}, {}", a, base, index * 8));
        self.ld(&a)
    }

    fn st(&mut self, addr: &str, val: &str) {
        let p = self.r();
        self.lf(format_args!("  {} = inttoptr i64 {} to ptr", p, addr));
        self.lf(format_args!("  store i64 {}, ptr {}", val, p));
    }

    fn sti(&mut self, base: &str, index: i64, val: &str) {
        let a = self.r();
        self.lf(format_args!("  {} = add i64 {}, {}", a, base, index * 8));
        self.st(&a, val);
    }

    pub fn emit(mut self) -> String {
        self.globals();
        self.map();
        self.new_chunk();
        self.bitmap_ops();
        self.chunk_of();
        self.find_object();
        self.emit_from_bump();
        self.emit_from_free();
        self.mark_ops();
        self.flush_run();
        self.sweep();
        self.collect();
        self.alloc();

        // The collector is hand-written machine-level code. Its
        // correctness rests on reading and writing exact addresses in an
        // exact order, through pointers conjured from integers that
        // `mmap` returned via inline assembly - memory LLVM has no
        // provenance information for and is entitled to reason about
        // however it likes. It duly does: at `-O1` and above the
        // optimised form stopped seeing its own chunk header, and a
        // freshly mapped megabyte reported itself full.
        //
        // Rather than guess which transform to placate, the collector
        // opts out. `optnone` costs nothing that matters - the fast path
        // is a free-list pop, dwarfed by the mark phase it exists to
        // postpone - and it buys the guarantee that what runs is what is
        // written here. Compiled Axiom code around it is optimised
        // normally.
        self.out
            .lines()
            .map(|line| {
                if line.starts_with("define") && line.ends_with(") {") {
                    format!("{} noinline optnone {{", &line[..line.len() - 2])
                } else {
                    line.to_string()
                }
            })
            .collect::<Vec<_>>()
            .join("\n")
            + "\n"
    }

    fn globals(&mut self) {
        self.l("; ---- conservative mark-sweep collector ----");
        self.l("declare i64 @llvm.ctlz.i64(i64, i1)");
        self.l("declare i64 @llvm.umin.i64(i64, i64)");
        self.l("@__axiom_gc_chunks = internal global i64 0");
        self.l("@__axiom_gc_lo = internal global i64 -1");
        self.l("@__axiom_gc_hi = internal global i64 0");
        self.lf(format_args!(
            "@__axiom_gc_free = internal global [{} x i64] zeroinitializer",
            SMALL_CLASSES + 1
        ));
        self.l("@__axiom_stack_base = internal global i64 0");
        self.l("@__axiom_gc_mark_base = internal global i64 0");
        self.l("@__axiom_gc_mark_top = internal global i64 0");
        self.l("@__axiom_gc_mark_end = internal global i64 0");
        self.l("@__axiom_gc_overflow = internal global i64 0");
        self.l("");
    }

    fn map(&mut self) {
        let (body, cons) = self.target.syscall_asm();
        let mmap = self.target.sys_mmap();
        let flags = self.target.map_private_anon();
        self.l("define internal i64 @__axiom_gc_map(i64 %len) {");
        self.l("entry:");
        self.lf(format_args!(
            "  %a = call i64 asm sideeffect \"{}\", \"{}\"(i64 {}, i64 0, i64 %len, i64 3, i64 {}, i64 -1, i64 0)",
            body, cons, mmap, flags
        ));
        // Linux answers -errno, Darwin a small positive errno with the
        // carry flag set, which inline asm cannot read. Neither is a
        // usable mapping, and both are caught by rejecting the extremes.
        self.l("  %lo = icmp ult i64 %a, 4096");
        self.l("  %hi = icmp ugt i64 %a, -4096");
        self.l("  %bad = or i1 %lo, %hi");
        self.l("  br i1 %bad, label %fail, label %ok");
        self.l("ok:");
        self.l("  ret i64 %a");
        self.l("fail:");
        self.l("  ret i64 0");
        self.l("}");
        self.l("");
    }

    /// Map a chunk able to hold one object of `n` payload bytes and link
    /// it in. Answers 1, or 0 when the mapping fails.
    fn new_chunk(&mut self) {
        self.l("define internal i64 @__axiom_gc_new_chunk(i64 %n) {");
        self.l("entry:");
        // A chunk must fit its own header, its bitmap, and the object.
        // The bitmap is sized from the whole chunk (size/128 bytes
        // covers size/16 granules), which over-provisions by the header
        // and bitmap's own share - simpler than solving for the exact
        // split, and the waste is under 1%.
        self.lf(format_args!(
            "  %need0 = add i64 %n, {}",
            OBJ_HDR + CHUNK_HDR
        ));
        self.l("  %need1 = add i64 %need0, 65535");
        self.l("  %need = and i64 %need1, -65536");
        // Reserve room for the bitmap too, then round again.
        self.l("  %bm0 = lshr i64 %need, 7");
        self.l("  %need2 = add i64 %need, %bm0");
        self.l("  %need3 = add i64 %need2, 65535");
        self.l("  %needr = and i64 %need3, -65536");
        self.lf(format_args!("  %big = icmp ugt i64 %needr, {}", CHUNK));
        self.lf(format_args!(
            "  %size = select i1 %big, i64 %needr, i64 {}",
            CHUNK
        ));
        self.l("  %base = call i64 @__axiom_gc_map(i64 %size)");
        self.l("  %failed = icmp eq i64 %base, 0");
        self.l("  br i1 %failed, label %oom, label %init");
        self.l("oom:");
        self.l("  ret i64 0");
        self.l("init:");
        self.l("  %bmbytes0 = lshr i64 %size, 7");
        self.l("  %bmbytes1 = add i64 %bmbytes0, 15");
        self.l("  %bmbytes = and i64 %bmbytes1, -16");
        self.lf(format_args!("  %bmstart = add i64 %base, {}", CHUNK_HDR));
        self.l("  %pstart = add i64 %bmstart, %bmbytes");
        self.l("  %pend = add i64 %base, %size");
        let head = {
            let h = self.r();
            self.lf(format_args!("  {} = load i64, ptr @__axiom_gc_chunks", h));
            h
        };
        self.sti("%base", 0, &head);
        self.sti("%base", 1, "%bmstart");
        self.sti("%base", 2, "%pstart");
        self.sti("%base", 3, "%pstart");
        self.sti("%base", 4, "%pend");
        // Largest object this chunk has held. Interior-pointer lookup
        // walks the bitmap backwards to the nearest object start, and
        // nothing in this chunk can span further than this, so it is
        // also the bound on that walk.
        self.sti("%base", 5, "0");
        self.l("  store i64 %base, ptr @__axiom_gc_chunks");
        // Coarse heap bounds, so a candidate word that is nowhere near
        // the heap - which is nearly all of them - is rejected without
        // walking the chunk list.
        self.l("  %lo = load i64, ptr @__axiom_gc_lo");
        self.l("  %lower = icmp ult i64 %pstart, %lo");
        self.l("  %nlo = select i1 %lower, i64 %pstart, i64 %lo");
        self.l("  store i64 %nlo, ptr @__axiom_gc_lo");
        self.l("  %hi = load i64, ptr @__axiom_gc_hi");
        self.l("  %higher = icmp ugt i64 %pend, %hi");
        self.l("  %nhi = select i1 %higher, i64 %pend, i64 %hi");
        self.l("  store i64 %nhi, ptr @__axiom_gc_hi");
        self.l("  ret i64 1");
        self.l("}");
        self.l("");
    }

    fn bitmap_ops(&mut self) {
        // granule -> (byte address, bit mask)
        for (name, op) in [("set", "or"), ("clear", "and")] {
            self.lf(format_args!(
                "define internal void @__axiom_gc_bit_{}(i64 %c, i64 %p) {{",
                name
            ));
            self.l("entry:");
            let pstart = self.ldi("%c", 2);
            let bm = self.ldi("%c", 1);
            self.lf(format_args!("  %off = sub i64 %p, {}", pstart));
            self.l("  %gr = lshr i64 %off, 4");
            self.l("  %byi = lshr i64 %gr, 3");
            self.lf(format_args!("  %bya = add i64 {}, %byi", bm));
            self.l("  %byp = inttoptr i64 %bya to ptr");
            self.l("  %bit = and i64 %gr, 7");
            self.l("  %one = shl i64 1, %bit");
            self.l("  %cur = load i8, ptr %byp");
            self.l("  %cur64 = zext i8 %cur to i64");
            if op == "or" {
                self.l("  %new64 = or i64 %cur64, %one");
            } else {
                self.l("  %inv = xor i64 %one, -1");
                self.l("  %new64 = and i64 %cur64, %inv");
            }
            self.l("  %new = trunc i64 %new64 to i8");
            self.l("  store i8 %new, ptr %byp");
            self.l("  ret void");
            self.l("}");
            self.l("");
        }

        self.l("define internal i64 @__axiom_gc_bit_byte(i64 %c, i64 %bi) {");
        self.l("entry:");
        self.l("  %bm = add i64 %c, 8");
        self.l("  %bmp = inttoptr i64 %bm to ptr");
        self.l("  %bms = load i64, ptr %bmp");
        self.l("  %bya = add i64 %bms, %bi");
        self.l("  %byp = inttoptr i64 %bya to ptr");
        self.l("  %cur = load i8, ptr %byp");
        self.l("  %r = zext i8 %cur to i64");
        self.l("  ret i64 %r");
        self.l("}");
        self.l("");

        self.l("define internal i64 @__axiom_gc_bit_test(i64 %c, i64 %p) {");
        self.l("entry:");
        let pstart = self.ldi("%c", 2);
        let bm = self.ldi("%c", 1);
        self.lf(format_args!("  %off = sub i64 %p, {}", pstart));
        self.l("  %gr = lshr i64 %off, 4");
        self.l("  %byi = lshr i64 %gr, 3");
        self.lf(format_args!("  %bya = add i64 {}, %byi", bm));
        self.l("  %byp = inttoptr i64 %bya to ptr");
        self.l("  %bit = and i64 %gr, 7");
        self.l("  %one = shl i64 1, %bit");
        self.l("  %cur = load i8, ptr %byp");
        self.l("  %cur64 = zext i8 %cur to i64");
        self.l("  %hit = and i64 %cur64, %one");
        self.l("  %nz = icmp ne i64 %hit, 0");
        self.l("  %r = zext i1 %nz to i64");
        self.l("  ret i64 %r");
        self.l("}");
        self.l("");
    }

    /// The chunk whose *allocated* payload range contains `w`, or 0.
    fn chunk_of(&mut self) {
        self.l("define internal i64 @__axiom_gc_chunk_of(i64 %w) {");
        self.l("entry:");
        self.l("  %cv = alloca i64");
        self.l("  %lo = load i64, ptr @__axiom_gc_lo");
        self.l("  %hi = load i64, ptr @__axiom_gc_hi");
        self.l("  %below = icmp ult i64 %w, %lo");
        self.l("  %above = icmp uge i64 %w, %hi");
        self.l("  %outside = or i1 %below, %above");
        self.l("  br i1 %outside, label %miss, label %walk");
        self.l("walk:");
        self.l("  %h = load i64, ptr @__axiom_gc_chunks");
        self.l("  store i64 %h, ptr %cv");
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %c = load i64, ptr %cv");
        self.l("  %end = icmp eq i64 %c, 0");
        self.l("  br i1 %end, label %miss, label %test");
        self.l("test:");
        let pstart = self.ldi("%c", 2);
        let bump = self.ldi("%c", 3);
        self.lf(format_args!("  %ge = icmp uge i64 %w, {}", pstart));
        self.lf(format_args!("  %lt = icmp ult i64 %w, {}", bump));
        self.l("  %in = and i1 %ge, %lt");
        self.l("  br i1 %in, label %hit, label %next");
        self.l("hit:");
        self.l("  ret i64 %c");
        self.l("next:");
        let nx = self.ldi("%c", 0);
        self.lf(format_args!("  store i64 {}, ptr %cv", nx));
        self.l("  br label %loop");
        self.l("miss:");
        self.l("  ret i64 0");
        self.l("}");
        self.l("");
    }

    /// The payload address of the live object *containing* `w`, or 0.
    ///
    /// Interior pointers have to resolve, not just exact block starts.
    /// `Str.strSlice` shares storage rather than copying - which is the
    /// point of it, since a tokenizer that copied every lexeme would
    /// allocate once per token - so a token's text is a `Str` header
    /// whose data pointer aims into the *middle* of the module source
    /// buffer. Once the source handle goes out of scope, those interior
    /// pointers are the only references that buffer has. Accepting only
    /// block starts freed it under them, and the self-hosted compiler
    /// emitted functions with garbage for names.
    ///
    /// The object is found by walking the object-start bitmap backwards
    /// from `w`'s granule to the nearest set bit, then checking that `w`
    /// falls inside that object's extent. The walk is byte-at-a-time and
    /// skips eight granules whenever a bitmap byte is empty, so the
    /// common case - a pointer that *is* a block start - stops
    /// immediately.
    fn find_object(&mut self) {
        self.l("define internal i64 @__axiom_gc_find_object(i64 %w) {");
        self.l("entry:");
        self.l("  %biv = alloca i64");
        self.l("  %firstv = alloca i64");
        self.l("  %c = call i64 @__axiom_gc_chunk_of(i64 %w)");
        self.l("  %none = icmp eq i64 %c, 0");
        self.l("  br i1 %none, label %no, label %start");
        self.l("start:");
        let pstart = self.ldi("%c", 2);
        let maxobj = self.ldi("%c", 5);
        self.lf(format_args!("  %off = sub i64 %w, {}", pstart));
        self.l("  %gr = lshr i64 %off, 4");
        self.l("  %bi0 = lshr i64 %gr, 3");
        // Nothing in this chunk spans further back than its largest
        // object, so a start beyond that cannot be the one containing
        // `%w`. `maxobj / GRAIN / 8` is that distance in bitmap bytes.
        self.lf(format_args!("  %spanb = lshr i64 {}, 7", maxobj));
        self.l("  %span = add i64 %spanb, 1");
        self.l("  %uflow = icmp ult i64 %bi0, %span");
        self.l("  %floor = sub i64 %bi0, %span");
        self.l("  %stop = select i1 %uflow, i64 0, i64 %floor");
        self.l("  %bit = and i64 %gr, 7");
        // bits at or below %bit within the first byte
        self.l("  %m0 = shl i64 2, %bit");
        self.l("  %mask0 = sub i64 %m0, 1");
        self.l("  store i64 %bi0, ptr %biv");
        self.l("  store i64 1, ptr %firstv");
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %bi = load i64, ptr %biv");
        self.l("  %raw = call i64 @__axiom_gc_bit_byte(i64 %c, i64 %bi)");
        self.l("  %first = load i64, ptr %firstv");
        self.l("  %isfirst = icmp ne i64 %first, 0");
        self.l("  %masked = and i64 %raw, %mask0");
        self.l("  %b = select i1 %isfirst, i64 %masked, i64 %raw");
        self.l("  %hit = icmp ne i64 %b, 0");
        self.l("  br i1 %hit, label %found, label %down");
        self.l("down:");
        self.l("  %atzero = icmp ule i64 %bi, %stop");
        self.l("  br i1 %atzero, label %no, label %step");
        self.l("step:");
        self.l("  %nbi = sub i64 %bi, 1");
        self.l("  store i64 %nbi, ptr %biv");
        self.l("  store i64 0, ptr %firstv");
        self.l("  br label %loop");
        self.l("found:");
        self.l("  %lz = call i64 @llvm.ctlz.i64(i64 %b, i1 false)");
        self.l("  %hb = sub i64 63, %lz");
        self.l("  %gbase = shl i64 %bi, 3");
        self.l("  %g = add i64 %gbase, %hb");
        self.l("  %goff = shl i64 %g, 4");
        self.lf(format_args!("  %p = add i64 {}, %goff", pstart));
        self.lf(format_args!("  %ha = sub i64 %p, {}", OBJ_HDR));
        self.l("  %hp = inttoptr i64 %ha to ptr");
        self.l("  %hv = load i64, ptr %hp");
        self.l("  %sz = lshr i64 %hv, 3");
        self.l("  %lim = add i64 %p, %sz");
        self.l("  %inside = icmp ult i64 %w, %lim");
        self.l("  br i1 %inside, label %yes, label %no");
        self.l("yes:");
        self.l("  ret i64 %p");
        self.l("no:");
        self.l("  ret i64 0");
        self.l("}");
        self.l("");
    }

    /// Carve `n` payload bytes off some chunk's bump region, or 0.
    ///
    /// Bump memory is always fresh mapping, never recycled - the bump
    /// pointer only moves forward - so it is already zero and needs no
    /// clearing. Recycled memory does; see `emit_from_free`.
    fn emit_from_bump(&mut self) {
        let (body, cons) = self.target.syscall_asm();
        let exit = self.target.sys_exit();
        let _ = (body, cons, exit);
        self.l("define internal i64 @__axiom_gc_from_bump(i64 %n) {");
        self.l("entry:");
        self.l("  %cv = alloca i64");
        self.l("  %h = load i64, ptr @__axiom_gc_chunks");
        self.l("  store i64 %h, ptr %cv");
        self.lf(format_args!("  %need = add i64 %n, {}", OBJ_HDR));
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %c = load i64, ptr %cv");
        self.l("  %end = icmp eq i64 %c, 0");
        self.l("  br i1 %end, label %miss, label %test");
        self.l("test:");
        let bump = self.ldi("%c", 3);
        let pend = self.ldi("%c", 4);
        self.lf(format_args!("  %after = add i64 {}, %need", bump));
        self.lf(format_args!("  %fits = icmp ule i64 %after, {}", pend));
        self.l("  br i1 %fits, label %take, label %next");
        self.l("take:");
        self.l("  %hdr = shl i64 %n, 3");
        self.st(&bump.clone(), "%hdr");
        self.sti("%c", 3, "%after");
        self.lf(format_args!("  %p = add i64 {}, {}", bump, OBJ_HDR));
        self.l("  call void @__axiom_gc_bit_set(i64 %c, i64 %p)");
        let mx = self.ldi("%c", 5);
        self.lf(format_args!("  %bigger = icmp ugt i64 %n, {}", mx));
        self.lf(format_args!(
            "  %nmax = select i1 %bigger, i64 %n, i64 {}",
            mx
        ));
        self.sti("%c", 5, "%nmax");
        self.l("  ret i64 %p");
        self.l("next:");
        let nx = self.ldi("%c", 0);
        self.lf(format_args!("  store i64 {}, ptr %cv", nx));
        self.l("  br label %loop");
        self.l("miss:");
        self.l("  ret i64 0");
        self.l("}");
        self.l("");
    }

    /// Take a block of at least `n` payload bytes off the free lists, or
    /// 0.
    ///
    /// The payload is zeroed before it is handed back. The standard
    /// library relies on it: `strAlloc` reserves `len + 1` bytes and
    /// takes the NUL terminator on trust, and `vecReserveExactly`
    /// documents the tail past `len` reading as 0 rather than as
    /// whatever the arena last held.
    fn emit_from_free(&mut self) {
        self.l("define internal i64 @__axiom_gc_from_free(i64 %n) {");
        self.l("entry:");
        self.l("  %pv = alloca i64");
        self.l("  %prevv = alloca i64");
        self.l("  %iv = alloca i64");
        self.l("  %usedv = alloca i64");
        self.l("  %idxv = alloca i64");
        self.l("  %passv = alloca i64");
        self.l("  %cls = lshr i64 %n, 4");
        self.lf(format_args!(
            "  %small = icmp ult i64 %cls, {}",
            SMALL_CLASSES
        ));
        self.lf(format_args!(
            "  %idx0 = select i1 %small, i64 %cls, i64 {}",
            SMALL_CLASSES
        ));
        self.l("  store i64 %idx0, ptr %idxv");
        self.l("  store i64 0, ptr %passv");
        self.l("  br label %pass");
        // Two passes: the exact size class, then the shared list of
        // everything larger. Without the second, a request that fits a
        // small class could never touch the big block a sweep leaves
        // behind - it would sit on the large list while the allocator
        // mapped fresh chunks around it.
        self.l("pass:");
        self.l("  %idx = load i64, ptr %idxv");
        self.lf(format_args!(
            "  %slot = getelementptr [{} x i64], ptr @__axiom_gc_free, i64 0, i64 %idx",
            SMALL_CLASSES + 1
        ));
        self.l("  %head = load i64, ptr %slot");
        self.l("  store i64 %head, ptr %pv");
        self.l("  store i64 0, ptr %prevv");
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %p = load i64, ptr %pv");
        self.l("  %done = icmp eq i64 %p, 0");
        self.l("  br i1 %done, label %miss, label %check");
        // Exact classes always fit; the shared large list is first-fit.
        self.l("check:");
        self.lf(format_args!("  %ha = sub i64 %p, {}", OBJ_HDR));
        self.l("  %hp = inttoptr i64 %ha to ptr");
        self.l("  %hv = load i64, ptr %hp");
        self.l("  %sz = lshr i64 %hv, 3");
        self.l("  %fits2 = icmp uge i64 %sz, %n");
        self.l("  br i1 %fits2, label %take, label %advance");
        self.l("advance:");
        self.l("  %pp = inttoptr i64 %p to ptr");
        self.l("  %nxt = load i64, ptr %pp");
        self.l("  store i64 %p, ptr %prevv");
        self.l("  store i64 %nxt, ptr %pv");
        self.l("  br label %loop");
        self.l("take:");
        self.l("  %pp2 = inttoptr i64 %p to ptr");
        self.l("  %nxt2 = load i64, ptr %pp2");
        self.l("  %prev = load i64, ptr %prevv");
        self.l("  %first = icmp eq i64 %prev, 0");
        self.l("  br i1 %first, label %unlink_head, label %unlink_mid");
        self.l("unlink_head:");
        self.l("  store i64 %nxt2, ptr %slot");
        self.l("  br label %reuse");
        self.l("unlink_mid:");
        self.l("  %prevp = inttoptr i64 %prev to ptr");
        self.l("  store i64 %nxt2, ptr %prevp");
        self.l("  br label %reuse");
        self.l("reuse:");
        // A coalesced block is usually far bigger than the request. Hand
        // back only what was asked for and return the tail to the free
        // lists, otherwise the first small allocation after a sweep
        // would swallow a whole chunk.
        self.l("  %extra = sub i64 %sz, %n");
        self.lf(format_args!(
            "  %cansplit = icmp uge i64 %extra, {}",
            OBJ_HDR + GRAIN
        ));
        self.l("  br i1 %cansplit, label %split, label %whole");
        self.l("split:");
        self.l("  %usedhdr = shl i64 %n, 3");
        self.l("  store i64 %usedhdr, ptr %hp");
        self.l("  %rh = add i64 %p, %n");
        self.lf(format_args!("  %rsz = sub i64 %extra, {}", OBJ_HDR));
        self.l("  %rshift = shl i64 %rsz, 3");
        self.l("  %rhdr = or i64 %rshift, 2");
        self.l("  %rhp = inttoptr i64 %rh to ptr");
        self.l("  store i64 %rhdr, ptr %rhp");
        self.lf(format_args!("  %rp = add i64 %rh, {}", OBJ_HDR));
        self.l("  %rcls = lshr i64 %rsz, 4");
        self.lf(format_args!(
            "  %ridx = call i64 @llvm.umin.i64(i64 %rcls, i64 {})",
            SMALL_CLASSES
        ));
        self.lf(format_args!(
            "  %rslot = getelementptr [{} x i64], ptr @__axiom_gc_free, i64 0, i64 %ridx",
            SMALL_CLASSES + 1
        ));
        self.l("  %rold = load i64, ptr %rslot");
        self.l("  %rpp = inttoptr i64 %rp to ptr");
        self.l("  store i64 %rold, ptr %rpp");
        self.l("  store i64 %rp, ptr %rslot");
        self.l("  store i64 %n, ptr %usedv");
        self.l("  br label %claim");
        self.l("whole:");
        self.l("  %keep = shl i64 %sz, 3");
        self.l("  store i64 %keep, ptr %hp");
        self.l("  store i64 %sz, ptr %usedv");
        self.l("  br label %claim");
        self.l("claim:");
        self.l("  %c = call i64 @__axiom_gc_chunk_of(i64 %p)");
        self.l("  %hasc = icmp ne i64 %c, 0");
        self.l("  br i1 %hasc, label %setbit, label %zero");
        self.l("setbit:");
        self.l("  call void @__axiom_gc_bit_set(i64 %c, i64 %p)");
        self.l("  br label %zero");
        self.l("zero:");
        self.l("  store i64 0, ptr %iv");
        self.l("  br label %zloop");
        self.l("zloop:");
        self.l("  %i = load i64, ptr %iv");
        self.l("  %used = load i64, ptr %usedv");
        self.l("  %zdone = icmp uge i64 %i, %used");
        self.l("  br i1 %zdone, label %ret, label %zbody");
        self.l("zbody:");
        self.l("  %za = add i64 %p, %i");
        self.l("  %zp = inttoptr i64 %za to ptr");
        self.l("  store i64 0, ptr %zp");
        self.l("  %ni = add i64 %i, 8");
        self.l("  store i64 %ni, ptr %iv");
        self.l("  br label %zloop");
        self.l("ret:");
        self.l("  ret i64 %p");
        self.l("miss:");
        self.l("  %passno = load i64, ptr %passv");
        self.l("  %firstpass = icmp eq i64 %passno, 0");
        self.l("  %idxnow = load i64, ptr %idxv");
        self.lf(format_args!(
            "  %notlarge = icmp ne i64 %idxnow, {}",
            SMALL_CLASSES
        ));
        self.l("  %retry = and i1 %firstpass, %notlarge");
        self.l("  br i1 %retry, label %second, label %fail");
        self.l("second:");
        self.lf(format_args!("  store i64 {}, ptr %idxv", SMALL_CLASSES));
        self.l("  store i64 1, ptr %passv");
        self.l("  br label %pass");
        self.l("fail:");
        self.l("  ret i64 0");
        self.l("}");
        self.l("");
    }

    fn mark_ops(&mut self) {
        // push
        self.l("define internal void @__axiom_gc_push(i64 %p) {");
        self.l("entry:");
        self.l("  %top = load i64, ptr @__axiom_gc_mark_top");
        self.l("  %end = load i64, ptr @__axiom_gc_mark_end");
        self.l("  %full = icmp uge i64 %top, %end");
        self.l("  br i1 %full, label %over, label %ok");
        self.l("over:");
        self.l("  store i64 1, ptr @__axiom_gc_overflow");
        self.l("  ret void");
        self.l("ok:");
        self.l("  %tp = inttoptr i64 %top to ptr");
        self.l("  store i64 %p, ptr %tp");
        self.l("  %nt = add i64 %top, 8");
        self.l("  store i64 %nt, ptr @__axiom_gc_mark_top");
        self.l("  ret void");
        self.l("}");
        self.l("");

        // mark one candidate word
        self.l("define internal void @__axiom_gc_mark_word(i64 %w) {");
        self.l("entry:");
        self.l("  %p = call i64 @__axiom_gc_find_object(i64 %w)");
        self.l("  %no = icmp eq i64 %p, 0");
        self.l("  br i1 %no, label %out, label %hdr");
        self.l("hdr:");
        self.lf(format_args!("  %ha = sub i64 %p, {}", OBJ_HDR));
        self.l("  %hp = inttoptr i64 %ha to ptr");
        self.l("  %hv = load i64, ptr %hp");
        self.l("  %m = and i64 %hv, 1");
        self.l("  %seen = icmp ne i64 %m, 0");
        self.l("  br i1 %seen, label %out, label %mark");
        self.l("mark:");
        self.l("  %nv = or i64 %hv, 1");
        self.l("  store i64 %nv, ptr %hp");
        self.l("  call void @__axiom_gc_push(i64 %p)");
        self.l("  ret void");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");

        // scan a half-open address range, word at a time
        self.l("define internal void @__axiom_gc_scan_range(i64 %lo, i64 %hi) {");
        self.l("entry:");
        self.l("  %av = alloca i64");
        self.l("  store i64 %lo, ptr %av");
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %a = load i64, ptr %av");
        self.l("  %done = icmp uge i64 %a, %hi");
        self.l("  br i1 %done, label %out, label %body");
        self.l("body:");
        self.l("  %p = inttoptr i64 %a to ptr");
        self.l("  %w = load i64, ptr %p");
        self.l("  call void @__axiom_gc_mark_word(i64 %w)");
        self.l("  %na = add i64 %a, 8");
        self.l("  store i64 %na, ptr %av");
        self.l("  br label %loop");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");

        // drain the mark stack
        self.l("define internal void @__axiom_gc_drain() {");
        self.l("entry:");
        self.l("  br label %loop");
        self.l("loop:");
        self.l("  %top = load i64, ptr @__axiom_gc_mark_top");
        self.l("  %base = load i64, ptr @__axiom_gc_mark_base");
        self.l("  %empty = icmp ule i64 %top, %base");
        self.l("  br i1 %empty, label %out, label %pop");
        self.l("pop:");
        self.l("  %nt = sub i64 %top, 8");
        self.l("  store i64 %nt, ptr @__axiom_gc_mark_top");
        self.l("  %tp = inttoptr i64 %nt to ptr");
        self.l("  %p = load i64, ptr %tp");
        self.lf(format_args!("  %ha = sub i64 %p, {}", OBJ_HDR));
        self.l("  %hp = inttoptr i64 %ha to ptr");
        self.l("  %hv = load i64, ptr %hp");
        self.l("  %sz = lshr i64 %hv, 3");
        self.l("  %hi = add i64 %p, %sz");
        self.l("  call void @__axiom_gc_scan_range(i64 %p, i64 %hi)");
        self.l("  br label %loop");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");
    }

    /// Turn a run of consecutive free blocks into one free block.
    ///
    /// Coalescing is what makes reuse work for a program whose
    /// allocation sizes grow. Without it every freed block keeps the
    /// size it had, so a request larger than anything previously freed
    /// can only come from fresh mapping - and a loop that builds a
    /// string by repeated concatenation asks for a slightly larger block
    /// every time, so it never reuses anything and the heap grows with
    /// the total, not the live set. Merging neighbours turns a swept
    /// chunk back into one large block that can serve any request.
    fn flush_run(&mut self) {
        self.l("define internal void @__axiom_gc_flush_run(i64 %rs, i64 %rb) {");
        self.l("entry:");
        self.l("  %none = icmp eq i64 %rb, 0");
        self.l("  br i1 %none, label %out, label %make");
        self.l("make:");
        self.lf(format_args!("  %newsz = sub i64 %rb, {}", OBJ_HDR));
        self.l("  %shifted = shl i64 %newsz, 3");
        self.l("  %hdr = or i64 %shifted, 2");
        self.l("  %hp = inttoptr i64 %rs to ptr");
        self.l("  store i64 %hdr, ptr %hp");
        self.lf(format_args!("  %p = add i64 %rs, {}", OBJ_HDR));
        self.l("  %cls = lshr i64 %newsz, 4");
        self.lf(format_args!(
            "  %idx = call i64 @llvm.umin.i64(i64 %cls, i64 {})",
            SMALL_CLASSES
        ));
        self.lf(format_args!(
            "  %slot = getelementptr [{} x i64], ptr @__axiom_gc_free, i64 0, i64 %idx",
            SMALL_CLASSES + 1
        ));
        self.l("  %old = load i64, ptr %slot");
        self.l("  %pp = inttoptr i64 %p to ptr");
        self.l("  store i64 %old, ptr %pp");
        self.l("  store i64 %p, ptr %slot");
        self.l("  ret void");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");
    }

    /// Walk every chunk linearly. `mode` 0 clears mark bits, 1 rebuilds
    /// the free lists from what survived.
    ///
    /// A linear walk is possible because every block - live or free -
    /// keeps its header and its size, so the next header is always at a
    /// computable offset.
    fn sweep(&mut self) {
        self.l("define internal void @__axiom_gc_sweep(i64 %mode) {");
        self.l("entry:");
        self.l("  %cv = alloca i64");
        self.l("  %hv2 = alloca i64");
        self.l("  %fv = alloca i64");
        self.l("  %rsv = alloca i64");
        self.l("  %rbv = alloca i64");
        self.l("  %h0 = load i64, ptr @__axiom_gc_chunks");
        self.l("  store i64 %h0, ptr %cv");
        self.l("  %rebuild = icmp eq i64 %mode, 1");
        self.l("  br i1 %rebuild, label %clearlists, label %chunks");
        self.l("clearlists:");
        self.l("  store i64 0, ptr %fv");
        self.l("  br label %floop");
        self.l("floop:");
        self.l("  %fi = load i64, ptr %fv");
        self.lf(format_args!(
            "  %fdone = icmp ugt i64 %fi, {}",
            SMALL_CLASSES
        ));
        self.l("  br i1 %fdone, label %chunks, label %fbody");
        self.l("fbody:");
        self.lf(format_args!(
            "  %fs = getelementptr [{} x i64], ptr @__axiom_gc_free, i64 0, i64 %fi",
            SMALL_CLASSES + 1
        ));
        self.l("  store i64 0, ptr %fs");
        self.l("  %fn = add i64 %fi, 1");
        self.l("  store i64 %fn, ptr %fv");
        self.l("  br label %floop");
        self.l("chunks:");
        self.l("  %c = load i64, ptr %cv");
        self.l("  %noc = icmp eq i64 %c, 0");
        self.l("  br i1 %noc, label %out, label %startchunk");
        self.l("startchunk:");
        let pstart = self.ldi("%c", 2);
        self.lf(format_args!("  store i64 {}, ptr %hv2", pstart));
        // A free run never spans chunks.
        self.l("  store i64 0, ptr %rsv");
        self.l("  store i64 0, ptr %rbv");
        self.l("  br label %objs");
        self.l("objs:");
        self.l("  %h = load i64, ptr %hv2");
        let bump = self.ldi("%c", 3);
        self.lf(format_args!("  %atend = icmp uge i64 %h, {}", bump));
        self.l("  br i1 %atend, label %endchunk, label %obj");
        self.l("obj:");
        self.l("  %hp = inttoptr i64 %h to ptr");
        self.l("  %hval = load i64, ptr %hp");
        self.l("  %sz = lshr i64 %hval, 3");
        self.lf(format_args!("  %p = add i64 %h, {}", OBJ_HDR));
        self.lf(format_args!("  %step = add i64 %sz, {}", OBJ_HDR));
        self.l("  %nh = add i64 %h, %step");
        self.l("  store i64 %nh, ptr %hv2");
        self.l("  br i1 %rebuild, label %reap, label %clearmark");
        self.l("clearmark:");
        self.l("  %cleared = and i64 %hval, -2");
        self.l("  store i64 %cleared, ptr %hp");
        self.l("  br label %objs");
        self.l("reap:");
        self.l("  %mk = and i64 %hval, 1");
        self.l("  %live = icmp ne i64 %mk, 0");
        self.l("  br i1 %live, label %keep, label %free");
        self.l("keep:");
        // A live block ends the run before it.
        self.l("  %krs = load i64, ptr %rsv");
        self.l("  %krb = load i64, ptr %rbv");
        self.l("  call void @__axiom_gc_flush_run(i64 %krs, i64 %krb)");
        self.l("  store i64 0, ptr %rsv");
        self.l("  store i64 0, ptr %rbv");
        self.l("  %unmarked = and i64 %hval, -2");
        self.l("  store i64 %unmarked, ptr %hp");
        self.l("  br label %objs");
        self.l("free:");
        // Drop the object-start bit so a stale pointer cannot resurrect
        // it, and extend the current run rather than listing it alone.
        self.l("  call void @__axiom_gc_bit_clear(i64 %c, i64 %p)");
        self.l("  %rs = load i64, ptr %rsv");
        self.l("  %rb = load i64, ptr %rbv");
        self.l("  %fresh = icmp eq i64 %rb, 0");
        self.l("  %nrs = select i1 %fresh, i64 %h, i64 %rs");
        self.l("  %nrb = add i64 %rb, %step");
        self.l("  store i64 %nrs, ptr %rsv");
        self.l("  store i64 %nrb, ptr %rbv");
        self.l("  br label %objs");
        self.l("endchunk:");
        self.l("  %ers = load i64, ptr %rsv");
        self.l("  %erb = load i64, ptr %rbv");
        self.l("  br i1 %rebuild, label %flush, label %nextchunk");
        self.l("flush:");
        self.l("  call void @__axiom_gc_flush_run(i64 %ers, i64 %erb)");
        self.l("  br label %nextchunk");
        self.l("nextchunk:");
        let nx = self.ldi("%c", 0);
        self.lf(format_args!("  store i64 {}, ptr %cv", nx));
        self.l("  br label %chunks");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");
    }

    fn collect(&mut self) {
        let (spb, spc) = self.target.stack_ptr_asm();
        let clob = self.target.callee_saved_clobbers();
        self.l("define internal void @__axiom_gc_collect() {");
        self.l("entry:");
        // Without a stack base there is no bounded root set, so there is
        // nothing safe to do but decline. That happens only before
        // `main` has run its first instruction.
        self.l("  %sb = load i64, ptr @__axiom_stack_base");
        self.l("  %noroots = icmp eq i64 %sb, 0");
        self.l("  br i1 %noroots, label %out, label %ready");
        self.l("ready:");
        self.l("  call void @__axiom_gc_sweep(i64 0)");
        self.l("  %mb = load i64, ptr @__axiom_gc_mark_base");
        self.l("  store i64 %mb, ptr @__axiom_gc_mark_top");
        self.l("  store i64 0, ptr @__axiom_gc_overflow");
        // Spill callee-saved registers into this frame so the scan below
        // can see any pointer that lives only in one.
        self.lf(format_args!(
            "  call void asm sideeffect \"\", \"{}\"()",
            clob
        ));
        self.lf(format_args!(
            "  %sp = call i64 asm sideeffect \"{}\", \"{}\"()",
            spb, spc
        ));
        self.l("  call void @__axiom_gc_scan_range(i64 %sp, i64 %sb)");
        for (i, root) in std::mem::take(&mut self.global_roots)
            .into_iter()
            .enumerate()
        {
            self.lf(format_args!("  %root{} = load i64, ptr @{}", i, root));
            self.lf(format_args!(
                "  call void @__axiom_gc_mark_word(i64 %root{})",
                i
            ));
        }
        self.l("  call void @__axiom_gc_drain()");
        self.l("  %ov = load i64, ptr @__axiom_gc_overflow");
        self.l("  %lost = icmp ne i64 %ov, 0");
        // An overflowed mark stack means the mark is incomplete. Sweeping
        // on an incomplete mark would free reachable objects, so the
        // collection is abandoned instead - no memory is recovered, and
        // nothing is corrupted. Marks were already cleared on the way in,
        // so the next attempt starts clean.
        self.l("  br i1 %lost, label %abandon, label %reap");
        self.l("abandon:");
        self.l("  call void @__axiom_gc_sweep(i64 0)");
        self.l("  ret void");
        self.l("reap:");
        self.l("  call void @__axiom_gc_sweep(i64 1)");
        self.l("  ret void");
        self.l("out:");
        self.l("  ret void");
        self.l("}");
        self.l("");
    }

    fn alloc(&mut self) {
        let (body, cons) = self.target.syscall_asm();
        let exit = self.target.sys_exit();
        self.l("define i64 @axiom_alloc(i64 %size) {");
        self.l("entry:");
        // One quantum minimum: a free block stores its successor in its
        // own payload, so a zero-byte payload would have nowhere to put
        // it.
        self.lf(format_args!("  %s0 = add i64 %size, {}", GRAIN - 1));
        self.lf(format_args!("  %s1 = and i64 %s0, {}", -GRAIN));
        self.lf(format_args!("  %tiny = icmp ult i64 %s1, {}", GRAIN));
        self.lf(format_args!(
            "  %n = select i1 %tiny, i64 {}, i64 %s1",
            GRAIN
        ));
        self.l("  %chunks = load i64, ptr @__axiom_gc_chunks");
        self.l("  %fresh = icmp eq i64 %chunks, 0");
        self.l("  br i1 %fresh, label %init, label %try1");
        self.l("init:");
        self.lf(format_args!(
            "  %ms = call i64 @__axiom_gc_map(i64 {})",
            MARK_SLOTS * 8
        ));
        self.l("  store i64 %ms, ptr @__axiom_gc_mark_base");
        self.l("  store i64 %ms, ptr @__axiom_gc_mark_top");
        self.lf(format_args!(
            "  %me = add i64 %ms, {}",
            (MARK_SLOTS - 1) * 8
        ));
        self.l("  store i64 %me, ptr @__axiom_gc_mark_end");
        self.l("  %c0 = call i64 @__axiom_gc_new_chunk(i64 %n)");
        self.l("  %c0bad = icmp eq i64 %c0, 0");
        self.l("  br i1 %c0bad, label %oom, label %try1");
        // Free list, then bump, then collect, then free/bump again, then
        // grow. Collection happens only when the current mapping is
        // exhausted, so a program whose live set fits never pays for one.
        self.l("try1:");
        self.l("  %a1 = call i64 @__axiom_gc_from_free(i64 %n)");
        self.l("  %ok1 = icmp ne i64 %a1, 0");
        self.l("  br i1 %ok1, label %done1, label %try2");
        self.l("done1:");
        self.l("  ret i64 %a1");
        self.l("try2:");
        self.l("  %a2 = call i64 @__axiom_gc_from_bump(i64 %n)");
        self.l("  %ok2 = icmp ne i64 %a2, 0");
        self.l("  br i1 %ok2, label %done2, label %gc");
        self.l("done2:");
        self.l("  ret i64 %a2");
        self.l("gc:");
        self.l("  call void @__axiom_gc_collect()");
        self.l("  %a3 = call i64 @__axiom_gc_from_free(i64 %n)");
        self.l("  %ok3 = icmp ne i64 %a3, 0");
        self.l("  br i1 %ok3, label %done3, label %try4");
        self.l("done3:");
        self.l("  ret i64 %a3");
        self.l("try4:");
        self.l("  %a4 = call i64 @__axiom_gc_from_bump(i64 %n)");
        self.l("  %ok4 = icmp ne i64 %a4, 0");
        self.l("  br i1 %ok4, label %done4, label %grow");
        self.l("done4:");
        self.l("  ret i64 %a4");
        self.l("grow:");
        self.l("  %g = call i64 @__axiom_gc_new_chunk(i64 %n)");
        self.l("  %gbad = icmp eq i64 %g, 0");
        self.l("  br i1 %gbad, label %oom, label %try5");
        self.l("try5:");
        self.l("  %a5 = call i64 @__axiom_gc_from_bump(i64 %n)");
        self.l("  %ok5 = icmp ne i64 %a5, 0");
        self.l("  br i1 %ok5, label %done5, label %oom");
        self.l("done5:");
        self.l("  ret i64 %a5");
        // The same status the bump allocator uses, so a program that
        // runs out of memory reports it the same way whichever allocator
        // it was built with.
        self.l("oom:");
        self.lf(format_args!(
            "  call i64 asm sideeffect \"{}\", \"{}\"(i64 {}, i64 70, i64 0, i64 0, i64 0, i64 0, i64 0)",
            body, cons, exit
        ));
        self.l("  unreachable");
        self.l("}");
        self.l("");
    }
}
