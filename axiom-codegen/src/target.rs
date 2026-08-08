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
    /// The argument registers are listed as CLOBBERS as well as
    /// inputs, and on arm64 that is not belt-and-braces: Darwin's
    /// `svc` destroys them. Probed directly - a C program that puts
    /// 0x100000 in x1, issues the `mmap` syscall and reads x1 back
    /// gets 0.
    ///
    /// Without the clobbers LLVM believes an argument register still
    /// holds its value afterwards, and at `-O1` and above it acts on
    /// that belief. The bump allocator is where it showed: `%chunk`
    /// lived in x1 across the `svc`, so `@__axiom_bump_end` was set to
    /// `addr + 0` rather than `addr + chunk`, every subsequent
    /// allocation failed the fast path and mapped a fresh megabyte,
    /// and two consecutive `memAlloc 64` calls came back 1 MiB apart.
    /// At `-O0` the same IR is correct, because LLVM spills and
    /// reloads across the asm and never trusts the register.
    ///
    /// It shipped: a missing `opt` is a warning rather than an error,
    /// so `axiom build` at its default `--opt 1` handed raw IR to
    /// `llc -O1` on any machine without `opt` installed.
    ///
    /// The x86-64 entries always had this right - `syscall` clobbers
    /// `rcx` and `r11` and they are declared - which is why only the
    /// arm64 targets were affected.
    pub fn syscall_asm(self) -> (&'static str, &'static str) {
        match self {
            // Darwin/arm64: number in x16, args in x0-x5, `svc #0x80`.
            // `b.cc 1f` skips the negation when carry is clear
            // (success); `1:` is a local numeric label, which the
            // integrated assembler allows inside inline asm and which
            // cannot collide with a label from another expansion.
            Target::DarwinAarch64 => (
                "svc #0x80\\0Ab.cc 1f\\0Aneg x0, x0\\0A1:",
                "={x0},{x16},{x0},{x1},{x2},{x3},{x4},{x5},\
                 ~{x1},~{x2},~{x3},~{x4},~{x5},~{x16},~{cc},~{memory}",
            ),
            // Linux/arm64: number in x8, args in x0-x5, `svc #0`.
            // Already returns `-errno`.
            Target::LinuxAarch64 => (
                "svc #0",
                "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},\
                 ~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}",
            ),
            // System V/x86-64: number in rax, args in
            // rdi/rsi/rdx/r10/r8/r9. `syscall` clobbers rcx and r11.
            Target::LinuxX86_64 => (
                "syscall",
                "={ax},{ax},{di},{si},{dx},{r10},{r8},{r9},\
                 ~{rdi},~{rsi},~{rdx},~{r10},~{r8},~{r9},~{rcx},~{r11},~{cc},~{memory}",
            ),
            // Darwin/x86-64 uses the same registers as Linux but the
            // same carry-flag error convention as Darwin/arm64 - and,
            // for the same reason, the same argument-register clobbers.
            //
            // Linux documents that its kernel preserves everything
            // except `rax`, `rcx` and `r11` - but the entry above
            // declares the argument registers clobbered anyway (this
            // comment once claimed otherwise while the string had
            // already been widened; the string is the truth). Darwin documents no such
            // thing, and on arm64 it demonstrably does NOT preserve the
            // argument registers - probed, and the resulting bump
            // allocator bug shipped. `rdx` is the strongest case: it is
            // Darwin's SECOND RETURN register (`fork` and `pipe` answer
            // through it), so the kernel writes it, while this template
            // lists `{dx}` as a live input and nothing tells LLVM it
            // was destroyed.
            //
            // Declaring the arguments clobbered costs a few spills and
            // removes a whole class of miscompile on the one target no
            // CI runner executes - it is assembled on every run and
            // never run on any.
            Target::DarwinX86_64 => (
                "syscall\\0Ajnc 1f\\0Anegq %rax\\0A1:",
                "={ax},{ax},{di},{si},{dx},{r10},{r8},{r9},\
                 ~{rdi},~{rsi},~{rdx},~{r10},~{r8},~{r9},~{rcx},~{r11},~{cc},~{memory}",
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
    fn condition_flags_are_declared_clobbered_everywhere() {
        // The kernel eats the flags, and two of the four templates
        // READ them: Darwin signals syscall failure in the carry bit,
        // which is why the arm64 template says `b.cc` and the x86-64
        // one says `jnc`. Nothing told LLVM. At -O1+ the optimiser is
        // entitled to keep a comparison's flags live across the whole
        // asm block, and it did: a countdown loop with a syscall in
        // its body scheduled the `adds` before the `svc` and the
        // flag-consuming `b.lo` after it, and ran FOREVER - measured
        // 2026-08-07 on darwin-aarch64 at every opt level, found by a
        // clock probe, invisible to every existing test because their
        // loop conditions happened to be scheduled entirely after the
        // syscall. The Linux templates get `~{cc}` too: their kernels
        // preserve the flags, but a clobber that costs a rare spill is
        // cheaper than an ABI assumption this project has already
        // watched fail once per architecture.
        for t in Target::all() {
            let (_, constraints) = t.syscall_asm();
            assert!(
                constraints.contains("~{cc}"),
                "{} syscall template does not clobber the condition flags",
                t.name()
            );
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
    fn darwin_argument_registers_are_declared_clobbered() {
        // Darwin's kernel destroys the syscall argument registers -
        // probed on arm64, where a C program that puts 0x100000 in x1,
        // issues `mmap` and reads x1 back gets 0. Nothing tells LLVM
        // that except the clobber list, and when it was missing the
        // optimiser kept a live value in x1 across the `svc`: the bump
        // allocator set `@__axiom_bump_end` to `addr + 0`, every
        // allocation mapped a fresh megabyte, and it SHIPPED.
        //
        // The same hazard exists on Darwin x86-64, where `rdx` is the
        // second return register, and that target is assembled by CI
        // but executed by no runner - so this assertion is the only
        // thing standing between it and the identical bug.
        //
        // Linux is deliberately exempt: its ABI documents that the
        // kernel preserves every register but rax/rcx/r11, so the
        // narrower list there is correct rather than an oversight.
        for t in [Target::DarwinAarch64, Target::DarwinX86_64] {
            let (_, constraints) = t.syscall_asm();
            let parts: Vec<&str> = constraints.split(',').map(|p| p.trim()).collect();
            let mut written: Vec<String> = parts
                .iter()
                .filter(|c| c.starts_with('~'))
                .map(|c| normalise_reg(c.trim_start_matches("~{").trim_end_matches('}')))
                .collect();
            // The output register is written by construction, so an
            // input that shares it needs no clobber. Both Darwin
            // templates do share one: arm64 passes argument 1 in x0 and
            // takes the result there, x86-64 the same with rax.
            written.extend(
                parts
                    .iter()
                    .filter(|c| c.starts_with('='))
                    .map(|c| normalise_reg(c.trim_start_matches("={").trim_end_matches('}'))),
            );
            for input in parts
                .iter()
                .filter(|c| !c.starts_with('=') && !c.starts_with('~'))
            {
                let reg = normalise_reg(input.trim_start_matches('{').trim_end_matches('}'));
                assert!(
                    written.contains(&reg),
                    "{}: register {} is a live input, is not the output, and is not declared \
                     clobbered; Darwin's kernel does not preserve it",
                    t.name(),
                    reg
                );
            }
        }
    }

    /// `{di}` and `~{rdi}` name one register in two spellings, so a
    /// textual comparison of the two lists would pass while the
    /// clobber was absent.
    fn normalise_reg(r: &str) -> String {
        let r = r.trim_start_matches('r').trim_start_matches('e');
        match r {
            "ax" | "di" | "si" | "dx" | "cx" => r.to_string(),
            other => other.to_string(),
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
