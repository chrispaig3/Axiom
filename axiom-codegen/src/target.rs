//! Per-platform code generation facts.
//!
//! Everything in this module exists because Axiom generates
//! *freestanding* code: the standard library reaches the operating
//! system through raw syscalls rather than through libc, so the
//! backend - not a C header - has to know each platform's syscall
//! ABI, its LLVM target triple, and the handful of syscall numbers
//! the compiler-emitted runtime itself needs (`mmap` for the
//! allocator, `exit` for the abort path).
//!
//! Syscall *numbers* used by ordinary standard-library code are
//! deliberately **not** listed here - they belong in Axiom source
//! (`stdlib/Sys/<platform>.ax`), so adding a new syscall is a
//! stdlib change, not a compiler change. Only the two numbers the
//! backend-emitted runtime cannot express in Axiom live here.

/// A compilation target: an OS/architecture pair with a known
/// syscall ABI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    DarwinAarch64,
    DarwinX86_64,
    LinuxAarch64,
    LinuxX86_64,
}

impl Target {
    /// The target the compiler is itself running on. Used as the
    /// default when no explicit `--target` is given.
    pub fn host() -> Self {
        #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
        {
            Target::DarwinAarch64
        }
        #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
        {
            Target::DarwinX86_64
        }
        #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
        {
            Target::LinuxAarch64
        }
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            Target::LinuxX86_64
        }
        #[cfg(not(any(
            all(target_os = "macos", target_arch = "aarch64"),
            all(target_os = "macos", target_arch = "x86_64"),
            all(target_os = "linux", target_arch = "aarch64"),
            all(target_os = "linux", target_arch = "x86_64"),
        )))]
        {
            compile_error!("axiom-codegen: unsupported host platform; add it to Target::host()")
        }
    }

    /// Parse a target name as accepted by `axiom --target=<name>`.
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "darwin-aarch64" | "aarch64-apple-darwin" | "arm64-apple-darwin" => {
                Some(Target::DarwinAarch64)
            }
            "darwin-x86_64" | "x86_64-apple-darwin" => Some(Target::DarwinX86_64),
            "linux-aarch64" | "aarch64-unknown-linux-gnu" => Some(Target::LinuxAarch64),
            "linux-x86_64" | "x86_64-unknown-linux-gnu" => Some(Target::LinuxX86_64),
            _ => None,
        }
    }

    /// The canonical short name, i.e. the inverse of [`Target::parse`].
    pub fn name(self) -> &'static str {
        match self {
            Target::DarwinAarch64 => "darwin-aarch64",
            Target::DarwinX86_64 => "darwin-x86_64",
            Target::LinuxAarch64 => "linux-aarch64",
            Target::LinuxX86_64 => "linux-x86_64",
        }
    }

    /// Every target name `--target` accepts, for `--help` text and
    /// for the error message on an unknown target.
    pub fn all() -> &'static [Target] {
        &[
            Target::DarwinAarch64,
            Target::DarwinX86_64,
            Target::LinuxAarch64,
            Target::LinuxX86_64,
        ]
    }

    /// The LLVM target triple to put in the module header.
    pub fn triple(self) -> &'static str {
        match self {
            Target::DarwinAarch64 => "arm64-apple-macosx14.0.0",
            Target::DarwinX86_64 => "x86_64-apple-macosx14.0.0",
            Target::LinuxAarch64 => "aarch64-unknown-linux-gnu",
            Target::LinuxX86_64 => "x86_64-unknown-linux-gnu",
        }
    }

    /// Whether this target uses BSD-style syscall numbering, where
    /// the number carries a class bit (`0x2000000` for the Unix
    /// class). Stdlib platform modules need to agree with this, and
    /// it is why `Sys/Darwin.ax` and `Sys/Linux.ax` are separate
    /// files rather than one table.
    pub fn bsd_syscall_numbering(self) -> bool {
        matches!(self, Target::DarwinAarch64 | Target::DarwinX86_64)
    }

    /// `mmap`'s syscall number on this target.
    pub fn sys_mmap(self) -> i64 {
        match self {
            // 197 | Unix class bit
            Target::DarwinAarch64 | Target::DarwinX86_64 => 0x2000000 + 197,
            Target::LinuxAarch64 => 222,
            Target::LinuxX86_64 => 9,
        }
    }

    /// `exit`'s syscall number on this target.
    pub fn sys_exit(self) -> i64 {
        match self {
            Target::DarwinAarch64 | Target::DarwinX86_64 => 0x2000000 + 1,
            Target::LinuxAarch64 => 93,
            Target::LinuxX86_64 => 60,
        }
    }

    /// `MAP_PRIVATE | MAP_ANONYMOUS` for this target's `mmap`.
    ///
    /// The anonymous-mapping flag is one of the few constants that
    /// genuinely differs between the two OSes (`0x1000` on Darwin,
    /// `0x20` on Linux) and getting it wrong makes `mmap` fail with
    /// `EINVAL` rather than misbehave subtly, so it is kept next to
    /// the syscall numbers it is passed with.
    pub fn map_private_anon(self) -> i64 {
        match self {
            Target::DarwinAarch64 | Target::DarwinX86_64 => 0x1000 | 0x0002,
            Target::LinuxAarch64 | Target::LinuxX86_64 => 0x0020 | 0x0002,
        }
    }

    /// Inline asm reading the current stack pointer, as
    /// `(body, constraints)`.
    ///
    /// A conservative root scan needs the live end of the machine
    /// stack. There is no portable LLVM intrinsic for "the stack
    /// pointer right now" - `llvm.stacksave` is close but is defined in
    /// terms of dynamic allocas - so it is read directly, which is one
    /// instruction on both architectures.
    pub fn stack_ptr_asm(self) -> (&'static str, &'static str) {
        match self {
            Target::DarwinAarch64 | Target::LinuxAarch64 => ("mov $0, sp", "=r"),
            // AT&T order: source first.
            Target::DarwinX86_64 | Target::LinuxX86_64 => ("movq %rsp, $0", "=r"),
        }
    }

    /// A clobber list naming every callee-saved integer register.
    ///
    /// Used as the constraint of an empty `asm sideeffect`, which forces
    /// the compiler to spill those registers into the current frame
    /// before it. That matters because a conservative scan can only see
    /// what is in memory: a heap pointer whose only copy is in a
    /// callee-saved register is invisible to it, and the object would be
    /// collected while still live. Spilling them into the frame - which
    /// is inside the scanned range - is what makes the scan complete.
    pub fn callee_saved_clobbers(self) -> &'static str {
        match self {
            Target::DarwinAarch64 | Target::LinuxAarch64 => {
                "~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{x27},~{x28},~{memory}"
            }
            Target::DarwinX86_64 | Target::LinuxX86_64 => {
                "~{rbx},~{r12},~{r13},~{r14},~{r15},~{memory}"
            }
        }
    }

    /// The LLVM inline-assembly body and constraint string that
    /// performs a syscall on this target.
    ///
    /// The constraint string always takes seven inputs - the
    /// syscall number followed by six arguments - and unused
    /// arguments are passed as zero by the caller. Taking a fixed
    /// arity keeps a single asm template per target instead of one
    /// per argument count, at the cost of a few `mov`s that the
    /// register allocator mostly elides.
    /// Every target's syscall result follows the *Linux* convention
    /// after lowering: a successful result as-is, or `-errno` on
    /// failure.
    ///
    /// That is free on Linux, which already returns `-errno`, but
    /// Darwin instead returns a *positive* errno and signals failure
    /// through the carry flag - which inline assembly cannot expose as
    /// a value. Rather than leaking that difference into every stdlib
    /// caller (where a returned `2` would be indistinguishable from a
    /// valid fd 2), the Darwin templates below branch on the carry flag
    /// and negate the errno themselves, so `result < 0` is a correct
    /// and complete failure test on all four targets.
    pub fn syscall_asm(self) -> (&'static str, &'static str) {
        match self {
            // Darwin/arm64: number in x16, args in x0-x5, `svc #0x80`.
            // `b.cc 1f` skips the negation when carry is clear
            // (success); `1:` is a local numeric label, which the
            // integrated assembler allows inside inline asm and which
            // cannot collide with a label from another expansion.
            Target::DarwinAarch64 => (
                "svc #0x80\\0Ab.cc 1f\\0Aneg x0, x0\\0A1:",
                "={x0},{x16},{x0},{x1},{x2},{x3},{x4},{x5},~{memory}",
            ),
            // Linux/arm64: number in x8, args in x0-x5, `svc #0`.
            // Already returns `-errno`.
            Target::LinuxAarch64 => (
                "svc #0",
                "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{memory}",
            ),
            // System V/x86-64: number in rax, args in
            // rdi/rsi/rdx/r10/r8/r9. `syscall` clobbers rcx and r11.
            Target::LinuxX86_64 => (
                "syscall",
                "={ax},{ax},{di},{si},{dx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}",
            ),
            // Darwin/x86-64 uses the same registers as Linux but the
            // same carry-flag error convention as Darwin/arm64.
            Target::DarwinX86_64 => (
                "syscall\\0Ajnc 1f\\0Anegq %rax\\0A1:",
                "={ax},{ax},{di},{si},{dx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}",
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_target_name_round_trips() {
        for t in Target::all() {
            assert_eq!(Target::parse(t.name()), Some(*t), "{}", t.name());
        }
    }

    #[test]
    fn unknown_target_is_rejected() {
        assert_eq!(Target::parse("wasm32-unknown-unknown"), None);
        assert_eq!(Target::parse(""), None);
    }

    #[test]
    fn darwin_syscall_numbers_carry_the_unix_class_bit() {
        // A Darwin syscall number without the class bit silently
        // dispatches to the wrong table, so assert the bit is set
        // for Darwin and clear for Linux rather than trusting the
        // literals to be eyeballed correctly.
        for t in [Target::DarwinAarch64, Target::DarwinX86_64] {
            assert!(t.bsd_syscall_numbering());
            assert_eq!(t.sys_mmap() & 0x2000000, 0x2000000);
            assert_eq!(t.sys_exit() & 0x2000000, 0x2000000);
        }
        for t in [Target::LinuxAarch64, Target::LinuxX86_64] {
            assert!(!t.bsd_syscall_numbering());
            assert_eq!(t.sys_mmap() & 0x2000000, 0);
            assert_eq!(t.sys_exit() & 0x2000000, 0);
        }
    }

    #[test]
    fn syscall_constraints_take_number_plus_six_args() {
        for t in Target::all() {
            let (_, constraints) = t.syscall_asm();
            let inputs = constraints
                .split(',')
                .filter(|c| !c.starts_with('=') && !c.starts_with('~'))
                .count();
            assert_eq!(inputs, 7, "{}", t.name());
        }
    }

    #[test]
    fn darwin_templates_normalise_errors_to_negative() {
        // The stdlib's entire error story is "result < 0 means
        // failure", which is only true on Darwin because these
        // templates negate the errno on the carry-set path. Losing
        // that branch would turn every Darwin error into a plausible
        // success value, so assert it is present.
        for t in [Target::DarwinAarch64, Target::DarwinX86_64] {
            let (body, _) = t.syscall_asm();
            assert!(body.contains("1f"), "{}: no carry-flag branch", t.name());
            assert!(
                body.to_lowercase().contains("neg"),
                "{}: no errno negation",
                t.name()
            );
        }
        for t in [Target::LinuxAarch64, Target::LinuxX86_64] {
            let (body, _) = t.syscall_asm();
            assert!(
                !body.contains("neg"),
                "{}: Linux already returns -errno; negating would double-invert",
                t.name()
            );
        }
    }

    #[test]
    fn anon_mapping_flag_matches_the_os() {
        assert_eq!(Target::DarwinAarch64.map_private_anon(), 0x1002);
        assert_eq!(Target::LinuxX86_64.map_private_anon(), 0x22);
    }
}
