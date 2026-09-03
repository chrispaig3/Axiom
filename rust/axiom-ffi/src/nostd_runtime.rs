//! The runtime a `no_std` crate needs to link into an Axiom executable
//! with an EMPTY `nm -u`. Enabled by the `nostd-runtime` feature.
//!
//! Measured on darwin-aarch64: an Axiom executable linked against a
//! `no_std` staticlib that uses this module imports nothing, the same
//! answer a program with no `extern` at all gives. That is the mode
//! `scripts/check-ffi.sh` holds to its strictest tier, and before this
//! module existed every such crate pasted these ~120 lines by hand.
//!
//! What is here, and why each piece is needed:
//!
//! - a [`GlobalAlloc`] that forwards to `axiom_alloc`, so `alloc`
//!   (`Box`, `Vec`, `String`) works without `malloc`;
//! - the `#[panic_handler]`, which writes the panic message to fd 2 and
//!   exits 73 - the status for "the Rust side gave up", kept distinct
//!   from `MM-EXEC-16`'s 70/71/72, which belong to traps the Axiom
//!   compiler emitted (see `ffi::abort`);
//! - `rust_eh_personality` and `_Unwind_Resume`, which the precompiled
//!   sysroot `alloc` rlib references even under `panic = "abort"`
//!   (the profile governs *our* crates, not the sysroot's);
//! - `memcpy`, `memmove`, `memset`, `memcmp`, `bcmp`, `bzero`, `strlen`,
//!   which LLVM assumes exist on every target and
//!   `check-freestanding.sh` forbids importing from libc. `bcmp` is the
//!   one that is target-shaped: LLVM lowers a small `memcmp` compared
//!   only against zero straight to it on linux-x86_64 and not on
//!   darwin-aarch64, so the tier's "imports nothing" promise held on
//!   one platform and not the other until it was defined here;
//! - raw `write` and `exit` syscalls for the four targets Axiom emits
//!   for, so an abort can say why before it ends the process.
//!
//! A crate that wants a different allocator or panic policy does not
//! enable the feature and supplies its own.

use core::alloc::{GlobalAlloc, Layout};
// The C spellings, not Rust's byte pointers. The memory intrinsics
// below are the symbols LLVM assumes every target defines, and rustc's
// `suspicious_runtime_symbol_definitions` checks the definition against
// the C prototype it will generate calls to: `void *` is `c_void`, not
// `u8`, and `strlen` takes `c_char`. Layout-compatible either way; this
// module exists so LLVM's assumptions hold, so it uses the spelling
// LLVM recognises.
use core::ffi::{c_char, c_int, c_void};

// ---------------------------------------------------------------------
// Raw syscalls. The numbers and the calling sequences are the ones
// `self_host/codegen.ax` (`targetSyscallAsm`, `targetWriteNum`,
// `targetExitNum`) emits for the runtime's own traps.
// ---------------------------------------------------------------------

#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
mod sys {
    pub const WRITE: usize = 4;
    pub const EXIT: usize = 1;

    /// # Safety
    /// `num` must name a syscall this kernel implements taking three or
    /// fewer arguments, and `a`/`b`/`c` must be what that syscall's own
    /// contract asks of them: for `WRITE`, `b` must be readable for `c`
    /// bytes for the duration of the call.
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        // SAFETY: the Darwin arm64 syscall ABI, the sequence
        // `targetSyscallAsm` emits for this target - which until
        // 2026-09-03 this said and was not. The `b.cc`/`neg` epilogue
        // was missing, and it is not decoration: a BSD kernel reports
        // failure by setting the CARRY FLAG and answering the POSITIVE
        // errno, so without it `write` failing with `EBADF` came back
        // as 9 and `write_stderr`'s `if n <= 0` read it as nine bytes
        // written. The branch negates on failure, which is what gives
        // the `result < 0` contract every caller here assumes. Linux's
        // two templates deliberately have no epilogue: that kernel
        // answers `-errno` directly. `x16` carries the BSD syscall
        // number, `x0`-`x2` the three arguments, `svc #0x80` traps, and
        // the kernel answers in `x0` - which is why
        // `x0` is `inlateout` and `x1`/`x2` are also marked `lateout`,
        // Darwin being free to clobber the argument registers. Whether
        // the call means anything is the caller's, from the `# Safety`
        // above; this block itself only moves integers into registers.
        // `nostack` asserts the trap pushes nothing - it does not claim
        // `nomem`, so the compiler still assumes the kernel may read or
        // write memory, which is exactly what `write(2)` does.
        unsafe {
            core::arch::asm!(
                "svc #0x80",
                "b.cc 2f",
                "neg x0, x0",
                "2:",
                inlateout("x0") a as isize => ret,
                in("x1") b, in("x2") c, in("x16") num,
                lateout("x1") _, lateout("x2") _,
                options(nostack)
            );
        }
        ret
    }
}

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
mod sys {
    pub const WRITE: usize = 0x200_0004;
    pub const EXIT: usize = 0x200_0001;

    /// # Safety
    /// As the arm64 `call3`: `num` must name a syscall this kernel
    /// implements taking three or fewer arguments - here including the
    /// `0x200_0000` BSD class bits - and `a`/`b`/`c` must satisfy that
    /// syscall's own contract.
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        // SAFETY: the Darwin x86-64 syscall ABI: `rax` carries the
        // syscall number - on this target the BSD class bits are part
        // of the constant, which is why `WRITE` is `0x200_0004` and not
        // `4` - `rdi`/`rsi`/`rdx` the arguments in the System V order,
        // and the answer comes back in `rax`, hence `inlateout("rax")`.
        // The `jnc`/`neg` epilogue is the same correction the arm64
        // module above records: Darwin signals failure through the
        // carry flag with a positive errno, so without it a failed
        // syscall was indistinguishable from a short success.
        // The `syscall` instruction itself destroys `rcx` and `r11`
        // (the saved `rip` and `rflags`), which the two `lateout(_)`
        // entries declare so the compiler holds nothing live there.
        // Argument validity is the caller's, from the `# Safety` above;
        // `nostack` asserts only that the trap pushes nothing.
        unsafe {
            core::arch::asm!(
                "syscall",
                "jnc 2f",
                "neg rax",
                "2:",
                inlateout("rax") num as isize => ret,
                in("rdi") a, in("rsi") b, in("rdx") c,
                lateout("rcx") _, lateout("r11") _,
                options(nostack)
            );
        }
        ret
    }
}

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
mod sys {
    pub const WRITE: usize = 64;
    pub const EXIT: usize = 94; // exit_group

    /// # Safety
    /// As the darwin-aarch64 `call3`: `num` must name a syscall this
    /// kernel implements taking three or fewer arguments, and
    /// `a`/`b`/`c` must satisfy that syscall's own contract.
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        // SAFETY: the Linux arm64 syscall ABI, which differs from
        // Darwin's on the same architecture in both places this block
        // names: the number goes in `x8` rather than `x16`, and the
        // trap is `svc #0` rather than `svc #0x80`. Arguments are
        // `x0`-`x2` and the result returns in `x0`, hence `inlateout`.
        // There is no `lateout` on `x1`/`x2` here because Linux
        // guarantees `x1`-`x7` come back unchanged, where Darwin does
        // not - the constraints are target-specific, not stylistic.
        // Argument validity is the caller's, from the `# Safety` above.
        unsafe {
            core::arch::asm!(
                "svc #0",
                inlateout("x0") a as isize => ret,
                in("x1") b, in("x2") c, in("x8") num,
                options(nostack)
            );
        }
        ret
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod sys {
    pub const WRITE: usize = 1;
    pub const EXIT: usize = 231; // exit_group

    /// # Safety
    /// As the other three `call3`s: `num` must name a syscall this
    /// kernel implements taking three or fewer arguments, and
    /// `a`/`b`/`c` must satisfy that syscall's own contract.
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        // SAFETY: the Linux x86-64 syscall ABI: the number in `rax`
        // with no class bits (`write` is 1, not `0x200_0001`), the
        // arguments in `rdi`/`rsi`/`rdx`, and the result back in `rax`
        // - `inlateout("rax")`. As on Darwin x86-64 the `syscall`
        // instruction destroys `rcx` and `r11`, which the two
        // `lateout(_)` entries declare. Argument validity is the
        // caller's, from the `# Safety` above; `nostack` asserts only
        // that the trap pushes nothing onto the stack.
        unsafe {
            core::arch::asm!(
                "syscall",
                inlateout("rax") num as isize => ret,
                in("rdi") a, in("rsi") b, in("rdx") c,
                lateout("rcx") _, lateout("r11") _,
                options(nostack)
            );
        }
        ret
    }
}

#[cfg(not(any(
    all(
        target_os = "macos",
        any(target_arch = "aarch64", target_arch = "x86_64")
    ),
    all(
        target_os = "linux",
        any(target_arch = "aarch64", target_arch = "x86_64")
    ),
)))]
mod sys {
    // A target Axiom does not emit for. Nothing can be written and the
    // only exit is to stop making progress; documented, not hidden.
    pub const WRITE: usize = 0;
    pub const EXIT: usize = 0;

    /// # Safety
    /// None: this stub performs no operation and reads none of its
    /// arguments. It is `unsafe` only so the five `sys` modules present
    /// one signature to their callers.
    #[inline(always)]
    pub unsafe fn call3(_num: usize, _a: usize, _b: usize, _c: usize) -> isize {
        -1
    }
}

/// Write all of `bytes` to fd 2, retrying short writes.
pub fn write_stderr(bytes: &[u8]) {
    let mut off = 0;
    while off < bytes.len() {
        // SAFETY: a plain write(2) of memory we own. `off < bytes.len()`
        // is the loop condition, so `as_ptr() + off` points inside the
        // slice and `len() - off` is exactly the bytes still live there
        // - which is what `call3`'s `# Safety` asks of a WRITE - and the
        // `&[u8]` borrow keeps them alive across the call. `WRITE` is
        // this target's own number, chosen by the `cfg` on `sys`.
        let n = unsafe {
            sys::call3(
                sys::WRITE,
                2,
                bytes.as_ptr() as usize + off,
                bytes.len() - off,
            )
        };
        if n <= 0 {
            return;
        }
        off += n as usize;
    }
}

/// End the process with `code`.
pub fn exit(code: i32) -> ! {
    // SAFETY: exit(2) / exit_group(2) never return. `call3`'s `# Safety`
    // asks about pointer arguments and this call passes none - the only
    // argument is a status word - so the constant `sys::EXIT` for this
    // target is the whole obligation. The spin below is what keeps the
    // `!` honest on the stub target, whose `call3` returns instead.
    unsafe {
        sys::call3(sys::EXIT, code as usize, 0, 0);
    }
    loop {
        core::hint::spin_loop();
    }
}

// ---------------------------------------------------------------------
// The allocator.
// ---------------------------------------------------------------------

/// Forward Rust's allocations to Axiom's bump allocator.
///
/// `dealloc` is deliberately a no-op. Axiom's allocator has no
/// per-block free — reclamation is by arena reset (`MM-ALLOC-13`), and
/// `axiom_release` is ARC bookkeeping over blocks with Axiom headers,
/// which a Rust allocation does not have. So Rust memory here lives
/// until the enclosing arena is reset. That is a real constraint,
/// stated rather than hidden: a no_std shim that allocates in an
/// unbounded loop grows the arena. For a shim that computes and
/// returns, which is the shape the FFI is for, it is exactly right.
///
/// It is also what makes `MM-FFI-3` ("memory that did not come from
/// `axiom_alloc` is outside the arena") vacuous for a no_std crate: its
/// allocations are inside the arena, counted by the high-water mark and
/// reclaimed by a reset along with everything else.
pub struct AxiomAlloc;

// SAFETY: `GlobalAlloc`'s requirements on an implementation, taken in
// order. A block stays valid until it is deallocated - and `dealloc`
// here does nothing, so a block stays valid until the arena is reset,
// which is the constraint the doc above states rather than hides.
// Moving or copying the allocator cannot invalidate a block:
// `AxiomAlloc` is a unit struct and the bump pointer lives in the
// runtime's globals, not in `self`. `alloc` never answers a short or
// misaligned block, only a correct one or null; see its own comment.
// The impl is usable from more than one thread because there is no
// shared bump pointer to race - the allocator's five globals are
// process-wide in a single-threaded program and `thread_local`
// (localexec) in one that spawns, one arena per thread with no lock
// anywhere (`docs/memory-model.md`, MM-ALLOC-2 under the thread
// lowering). The matching constraint that buys it: a block belongs to
// the arena of the thread that asked for it, and `dealloc` doing
// nothing is what keeps a cross-thread free from existing at all.
unsafe impl GlobalAlloc for AxiomAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // Every axiom_alloc block is 16-byte aligned (invariant I5) and
        // reads as zero (I6). A stricter alignment request cannot be
        // served, so refuse rather than return a misaligned block.
        if layout.align() > 16 {
            return core::ptr::null_mut();
        }
        // SAFETY: `axiom_alloc` is one of the four runtime symbols
        // `axiom_abi` declares, emitted with external linkage into every
        // module the compiler writes, and it asks nothing of its caller
        // but a size; `Layout` caps that at `isize::MAX`, so the `as
        // i64` cannot truncate or go negative. What comes back is what
        // `GlobalAlloc` requires of this method: `MM-ALLOC-3` rounds
        // every size up to a multiple of 16, which is at once at least
        // `layout.size()` usable bytes and the 16-byte alignment of I5
        // - covering every `layout.align()` the branch above let
        // through - and no live allocation overlaps it because the bump
        // pointer only moves forward. A 0 answer becomes the null
        // pointer `GlobalAlloc` reads as failure.
        unsafe { axiom_abi::axiom_alloc(layout.size() as i64) as *mut u8 }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // SAFETY: I6: a fresh block already reads as zero, so `alloc` on
        // its own already satisfies the one thing this method promises
        // over `alloc`. The forwarding call's own obligations on
        // `layout` are `alloc`'s, and they are identical to this
        // method's, which our caller has already met.
        unsafe { self.alloc(layout) }
    }

    unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {}
}

#[global_allocator]
static ALLOC: AxiomAlloc = AxiomAlloc;

// ---------------------------------------------------------------------
// Panics and unwinding.
// ---------------------------------------------------------------------

/// A fixed buffer that flushes to fd 2, so a panic message can be
/// formatted without allocating (the allocator may be what panicked).
struct Stderr {
    buf: [u8; 256],
    len: usize,
}

impl Stderr {
    fn flush(&mut self) {
        write_stderr(&self.buf[..self.len]);
        self.len = 0;
    }
}

impl core::fmt::Write for Stderr {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for chunk in s.as_bytes().chunks(self.buf.len()) {
            if self.len + chunk.len() > self.buf.len() {
                self.flush();
            }
            self.buf[self.len..self.len + chunk.len()].copy_from_slice(chunk);
            self.len += chunk.len();
        }
        Ok(())
    }
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    use core::fmt::Write;
    let mut out = Stderr {
        buf: [0; 256],
        len: 0,
    };
    let _ = writeln!(out, "axiom-ffi: panic: {info}");
    out.flush();
    exit(73)
}

/// The personality routine the precompiled `alloc` rlib references.
///
/// Even with `panic = "abort"` in the profile, the `alloc` crate shipped
/// in the Rust sysroot was itself built with unwinding, so its object
/// files carry a reference to `rust_eh_personality`. An empty function
/// is sound precisely because nothing can unwind: Axiom emits no
/// `invoke` and no landing pad, and every shim is `extern "C"`, which
/// aborts on unwind. (`-Z build-std` would remove the reference
/// entirely, but needs nightly.)
#[unsafe(no_mangle)]
pub extern "C" fn rust_eh_personality() {}

/// Unreachable: nothing unwinds. See [`rust_eh_personality`].
#[unsafe(no_mangle)]
pub extern "C" fn _Unwind_Resume() -> ! {
    exit(73)
}

// ---------------------------------------------------------------------
// The memory intrinsics `alloc` needs.
//
// Measured: a core-only `no_std` staticlib links into an Axiom
// executable with an EMPTY `nm -u`. Adding `extern crate alloc` pulls in
// these because the precompiled sysroot `alloc` rlib calls the C memory
// intrinsics LLVM assumes exist on every target. Axiom cannot import
// them - `check-freestanding.sh` forbids exactly these names - so the
// runtime DEFINES them: byte loops, the same thing `compiler_builtins`'
// `mem` feature supplies when the sysroot is rebuilt.
//
// `#[no_mangle]` here is safe precisely because this is the no_std
// mode: nothing else in the link defines them.
//
// NOTHING IN RUST CALLS THESE. The callers are LLVM's lowering of a
// copy, a fill or a comparison, and the precompiled `alloc` rlib. So
// the guarantee behind every `unsafe` block below is the C contract for
// that symbol, restated in each function's `# Safety` - there is no
// Rust caller to hold to anything else, and the contract is the only
// thing a generated caller has ever been told.
// ---------------------------------------------------------------------

/// The C `memcpy`: copy `n` bytes from `src` to `dst`.
///
/// # Safety
/// The C contract for the symbol, which is all a generated caller has
/// agreed to: `n` bytes must be readable at `src` and writable at
/// `dst`, each range inside one live allocation, and the two ranges
/// must NOT overlap. Use [`memmove`] when they may.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memcpy(dst: *mut c_void, src: *const c_void, n: usize) -> *mut c_void {
    let mut i = 0;
    while i < n {
        // SAFETY: `# Safety` above puts `n` bytes at both pointers, so
        // every offset with `i < n` is in bounds of its own allocation
        // and neither `add` can run past the end or wrap `isize`. `u8`
        // is the byte view the C contract is written in: no alignment
        // requirement and no invalid bit pattern. Non-overlap - the
        // clause that separates this from `memmove` - is what stops the
        // store at `i` disturbing a byte the loop has yet to read. One
        // place this reading is STRICTER than C: a `*const u8` load
        // wants an initialised byte, so a caller copying padding is
        // outside it. That is the same assumption `compiler_builtins`'
        // byte-loop `mem` makes. (The loop is hand-written rather than
        // a `copy_nonoverlapping` for a different reason: that lowers
        // to `@llvm.memcpy`, which lowers back to a call to this very
        // symbol.)
        unsafe { *dst.cast::<u8>().add(i) = *src.cast::<u8>().add(i) };
        i += 1;
    }
    dst
}

/// The C `memmove`: [`memcpy`] that tolerates overlapping ranges.
///
/// # Safety
/// As [`memcpy`], minus the non-overlap clause: `n` bytes must be
/// readable at `src` and writable at `dst`, each range inside one live
/// allocation. The ranges MAY overlap.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memmove(dst: *mut c_void, src: *const c_void, n: usize) -> *mut c_void {
    if (dst as usize) < (src as usize) {
        // SAFETY: the bounds half of `memcpy`'s `# Safety` is this
        // function's, passed through unchanged. Its non-overlap clause
        // is NOT met - our caller was never asked for it - and what
        // makes the call sound anyway is the branch: with `dst < src`
        // an ascending copy reads each byte before any store can reach
        // it, so overlap is harmless. That leans on the definition
        // directly above being an ascending byte loop, not on the C
        // contract, which would forbid this call. The two must stay in
        // step: give `memcpy` a descending or vectorised body and this
        // branch goes wrong before anything else does.
        return unsafe { memcpy(dst, src, n) };
    }
    let mut i = n;
    while i > 0 {
        i -= 1;
        // SAFETY: bounds as `memcpy`'s loop - `# Safety` promises `n`
        // bytes at both pointers and `i < n` holds after the decrement
        // - and the descending order is what covers the overlap this
        // branch kept: `dst >= src`, so the store at `i` can only land
        // on a byte at an index the loop has already read past.
        unsafe { *dst.cast::<u8>().add(i) = *src.cast::<u8>().add(i) };
    }
    dst
}

/// The C `memset`: write the low byte of `c` to `n` bytes at `dst`.
///
/// # Safety
/// The C contract for the symbol: `n` bytes must be writable at `dst`,
/// inside one live allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memset(dst: *mut c_void, c: c_int, n: usize) -> *mut c_void {
    let mut i = 0;
    while i < n {
        // SAFETY: `# Safety` above promises `n` writable bytes at
        // `dst`, which puts every offset with `i < n` in bounds of that
        // one allocation and stops `add` wrapping. `c as u8` is C's own
        // conversion of the `int` to `unsigned char`, and a `u8` store
        // needs no alignment and can leave no invalid bit pattern
        // behind. Nothing is read, so the caller need not have
        // initialised the range.
        unsafe { *dst.cast::<u8>().add(i) = c as u8 };
        i += 1;
    }
    dst
}

/// The C `memcmp`: order the first `n` bytes at `a` and `b`.
///
/// # Safety
/// The C contract for the symbol: `n` bytes must be readable at both
/// `a` and `b`, each range inside one live allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memcmp(a: *const c_void, b: *const c_void, n: usize) -> c_int {
    let mut i = 0;
    while i < n {
        // SAFETY: `# Safety` above promises `n` readable bytes at each
        // pointer, so every offset with `i < n` is in bounds of its own
        // allocation and neither `add` wraps. Both reads are `u8` - no
        // alignment requirement, no invalid bit pattern, and the
        // unsigned byte comparison C specifies rather than `c_char`'s
        // signed one. Nothing is written, so `a` and `b` are free to
        // alias or to be the same pointer.
        let (x, y) = unsafe { (*a.cast::<u8>().add(i), *b.cast::<u8>().add(i)) };
        if x != y {
            return x as c_int - y as c_int;
        }
        i += 1;
    }
    0
}

/// `bcmp` is `memcmp`'s "equal or not" half: it may answer any non-zero
/// value for a difference, so it needs no ordering and LLVM lowers a
/// small `memcmp` whose result is only compared against zero straight
/// to it. That lowering fires on linux-x86_64 and not on
/// darwin-aarch64, which is why the freestanding tier imported exactly
/// one symbol there and nothing here: `check-ffi.sh` tier 2 says a
/// program bound to a no_std crate imports NOTHING, and one platform
/// was quietly failing to keep that promise.
///
/// # Safety
/// The C contract for the symbol, identical to [`memcmp`]'s on the
/// arguments: `n` bytes must be readable at both `a` and `b`, each
/// range inside one live allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bcmp(a: *const c_void, b: *const c_void, n: usize) -> c_int {
    // SAFETY: `bcmp`'s contract and `memcmp`'s differ only in what the
    // RESULT may be - any non-zero value versus an ordering - and this
    // function's `# Safety` restates `memcmp`'s requirement on the
    // arguments word for word, so the caller has already granted
    // everything the callee asks. Weakening the result contract cannot
    // make a call unsound: an ordering is one of the answers `bcmp` is
    // allowed to give.
    unsafe { memcmp(a, b, n) }
}

/// The C `bzero`: zero `n` bytes at `dst`. Defined for the same reason
/// as [`bcmp`] - LLVM emits it on some targets and not others.
///
/// # Safety
/// The C contract for the symbol, identical to [`memset`]'s: `n` bytes
/// must be writable at `dst`, inside one live allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bzero(dst: *mut c_void, n: usize) {
    // SAFETY: `bzero` is `memset` with the fill byte fixed at zero, and
    // its requirement on `dst`/`n` is `memset`'s word for word - this
    // function's `# Safety` restates it, so the caller has granted
    // exactly what the callee asks. The returned `dst` is discarded
    // because `bzero` answers nothing.
    unsafe { memset(dst, 0, n) };
}

/// The C `strlen`: the number of bytes before the NUL at `s`.
///
/// # Safety
/// The C contract for the symbol: `s` must point at a NUL-terminated
/// byte string, with every byte from `s` up to and including that NUL
/// readable and inside one live allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn strlen(s: *const c_char) -> usize {
    let mut n = 0;
    // SAFETY: NUL-termination, which `# Safety` above requires of the
    // generated caller, is the only thing bounding this loop: the read
    // at `n` happens only after every earlier byte tested non-zero, so
    // `n` cannot walk past the terminator and `add` stays inside the
    // one allocation the string occupies. `c_char` is a one-byte
    // integer - no alignment requirement, no invalid bit pattern - and
    // the terminator is compared as that same type, so a `0xFF` byte
    // reads as -1 and not as a terminator, which is correct.
    while unsafe { *s.add(n) } != 0 {
        n += 1;
    }
    n
}
