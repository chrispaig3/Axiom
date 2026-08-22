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
//!   exits 72, the status Axiom's own runtime traps use;
//! - `rust_eh_personality` and `_Unwind_Resume`, which the precompiled
//!   sysroot `alloc` rlib references even under `panic = "abort"`
//!   (the profile governs *our* crates, not the sysroot's);
//! - `memcpy`, `memmove`, `memset`, `memcmp`, `bzero`, `strlen`, which
//!   LLVM assumes exist on every target and `check-freestanding.sh`
//!   forbids importing from libc;
//! - raw `write` and `exit` syscalls for the four targets Axiom emits
//!   for, so an abort can say why before it ends the process.
//!
//! A crate that wants a different allocator or panic policy does not
//! enable the feature and supplies its own.

use core::alloc::{GlobalAlloc, Layout};

// ---------------------------------------------------------------------
// Raw syscalls. The numbers and the calling sequences are the ones
// `self_host/codegen.ax` (`targetSyscallAsm`, `targetWriteNum`,
// `targetExitNum`) emits for the runtime's own traps.
// ---------------------------------------------------------------------

#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
mod sys {
    pub const WRITE: usize = 4;
    pub const EXIT: usize = 1;
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        core::arch::asm!(
            "svc #0x80",
            inlateout("x0") a as isize => ret,
            in("x1") b, in("x2") c, in("x16") num,
            lateout("x1") _, lateout("x2") _,
            options(nostack)
        );
        ret
    }
}

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
mod sys {
    pub const WRITE: usize = 0x200_0004;
    pub const EXIT: usize = 0x200_0001;
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        core::arch::asm!(
            "syscall",
            inlateout("rax") num as isize => ret,
            in("rdi") a, in("rsi") b, in("rdx") c,
            lateout("rcx") _, lateout("r11") _,
            options(nostack)
        );
        ret
    }
}

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
mod sys {
    pub const WRITE: usize = 64;
    pub const EXIT: usize = 94; // exit_group
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        core::arch::asm!(
            "svc #0",
            inlateout("x0") a as isize => ret,
            in("x1") b, in("x2") c, in("x8") num,
            options(nostack)
        );
        ret
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod sys {
    pub const WRITE: usize = 1;
    pub const EXIT: usize = 231; // exit_group
    #[inline(always)]
    pub unsafe fn call3(num: usize, a: usize, b: usize, c: usize) -> isize {
        let ret: isize;
        core::arch::asm!(
            "syscall",
            inlateout("rax") num as isize => ret,
            in("rdi") a, in("rsi") b, in("rdx") c,
            lateout("rcx") _, lateout("r11") _,
            options(nostack)
        );
        ret
    }
}

#[cfg(not(any(
    all(target_os = "macos", any(target_arch = "aarch64", target_arch = "x86_64")),
    all(target_os = "linux", any(target_arch = "aarch64", target_arch = "x86_64")),
)))]
mod sys {
    // A target Axiom does not emit for. Nothing can be written and the
    // only exit is to stop making progress; documented, not hidden.
    pub const WRITE: usize = 0;
    pub const EXIT: usize = 0;
    #[inline(always)]
    pub unsafe fn call3(_num: usize, _a: usize, _b: usize, _c: usize) -> isize {
        -1
    }
}

/// Write all of `bytes` to fd 2, retrying short writes.
pub fn write_stderr(bytes: &[u8]) {
    let mut off = 0;
    while off < bytes.len() {
        // SAFETY: a plain write(2) of memory we own.
        let n = unsafe {
            sys::call3(sys::WRITE, 2, bytes.as_ptr() as usize + off, bytes.len() - off)
        };
        if n <= 0 {
            return;
        }
        off += n as usize;
    }
}

/// End the process with `code`.
pub fn exit(code: i32) -> ! {
    // SAFETY: exit(2) / exit_group(2) never return.
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

unsafe impl GlobalAlloc for AxiomAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // Every axiom_alloc block is 16-byte aligned (invariant I5) and
        // reads as zero (I6). A stricter alignment request cannot be
        // served, so refuse rather than return a misaligned block.
        if layout.align() > 16 {
            return core::ptr::null_mut();
        }
        axiom_abi::axiom_alloc(layout.size() as i64) as *mut u8
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // I6: a fresh block already reads as zero.
        self.alloc(layout)
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
    let mut out = Stderr { buf: [0; 256], len: 0 };
    let _ = write!(out, "axiom-ffi: panic: {info}\n");
    out.flush();
    exit(72)
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
#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

/// Unreachable: nothing unwinds. See [`rust_eh_personality`].
#[no_mangle]
pub extern "C" fn _Unwind_Resume() -> ! {
    exit(72)
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
// ---------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dst.add(i) = *src.add(i);
        i += 1;
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memmove(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    if (dst as usize) < (src as usize) {
        return memcpy(dst, src, n);
    }
    let mut i = n;
    while i > 0 {
        i -= 1;
        *dst.add(i) = *src.add(i);
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memset(dst: *mut u8, c: i32, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dst.add(i) = c as u8;
        i += 1;
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    let mut i = 0;
    while i < n {
        let (x, y) = (*a.add(i), *b.add(i));
        if x != y {
            return x as i32 - y as i32;
        }
        i += 1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn bzero(dst: *mut u8, n: usize) {
    memset(dst, 0, n);
}

#[no_mangle]
pub unsafe extern "C" fn strlen(s: *const u8) -> usize {
    let mut n = 0;
    while *s.add(n) != 0 {
        n += 1;
    }
    n
}
