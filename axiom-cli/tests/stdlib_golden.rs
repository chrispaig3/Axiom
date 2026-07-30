//! Golden tests for the Axiom-native standard library.
//!
//! Each `tests/stdlib/NAME.ax` is compiled with the real compiler
//! binary, run, and checked against `NAME.out` (expected stdout) and
//! optionally `NAME.exit` (expected exit status, default 0). The point
//! of testing through the binary rather than through the library crates
//! is that these tests are about the *whole* pipeline - module
//! resolution finding the standard library, the syscall lowering in the
//! backend, the linker producing something runnable - and any of those
//! can break without a single unit test noticing.
//!
//! Every case also asserts the generated LLVM IR calls no libc
//! function. That is the property that makes the standard library
//! Axiom-native rather than a C wrapper, and it is invisible in the
//! program's output: a `printf`-based `println` would pass every
//! output assertion here.

use std::path::{Path, PathBuf};
use std::process::Command;

/// libc functions the backend used to emit calls to. A call to any of
/// them from generated code means a stdlib operation regressed back to
/// a C implementation.
///
/// Deliberately limited to names that only ever belong to C: Axiom's own
/// standard library defines `exit`, `write`, and friends, and those
/// compile to `call @exit`/`call @write` on *Axiom* functions, so
/// listing them here would flag the very code that replaced libc.
const FORBIDDEN_LIBC_CALLS: &[&str] = &["@printf", "@puts", "@malloc", "@free", "@strlen"];

fn repo_root() -> PathBuf {
    // `axiom-cli/` -> repository root.
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("axiom-cli has a parent directory")
        .to_path_buf()
}

fn cases() -> Vec<PathBuf> {
    let dir = repo_root().join("tests/stdlib");
    let mut cases: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", dir.display(), e))
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "ax"))
        .collect();
    cases.sort();
    assert!(!cases.is_empty(), "no .ax cases in {}", dir.display());
    cases
}

/// A scratch directory per case, so cases that create files (the
/// file-I/O case) cannot see each other's leftovers and can run in any
/// order.
fn scratch_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("axiom-stdlib-golden-{}", name));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}

fn axiom() -> Command {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_axiom"));
    // The compiler locates the standard library relative to its own
    // binary; `CARGO_BIN_EXE_axiom` lives in `target/<profile>/`, which
    // is exactly the layout the default search path expects. Setting it
    // explicitly anyway keeps the test honest about what it depends on
    // and immune to a change in profile directory depth.
    cmd.env("AXIOM_STDLIB", repo_root().join("stdlib"));
    cmd
}

#[test]
fn stdlib_cases_produce_expected_output() {
    for case in cases() {
        let name = case.file_stem().unwrap().to_string_lossy().to_string();
        let expected_out = std::fs::read_to_string(case.with_extension("out"))
            .unwrap_or_else(|e| panic!("{}: missing .out file: {}", name, e));
        let expected_code: i32 = match std::fs::read_to_string(case.with_extension("exit")) {
            Ok(s) => s.trim().parse().expect("exit file holds an integer"),
            Err(_) => 0,
        };

        let dir = scratch_dir(&name);
        let exe = dir.join(&name);

        let build = axiom()
            .arg("build")
            .arg("--input")
            .arg(&case)
            .arg("--output")
            .arg(&exe)
            .current_dir(&dir)
            .output()
            .expect("run axiom build");
        assert!(
            build.status.success(),
            "{}: build failed\nstdout:\n{}\nstderr:\n{}",
            name,
            String::from_utf8_lossy(&build.stdout),
            String::from_utf8_lossy(&build.stderr),
        );

        let run = Command::new(&exe)
            .current_dir(&dir)
            .output()
            .unwrap_or_else(|e| panic!("{}: cannot run {}: {}", name, exe.display(), e));

        assert_eq!(
            String::from_utf8_lossy(&run.stdout),
            expected_out,
            "{}: stdout mismatch",
            name
        );
        assert_eq!(
            run.status.code(),
            Some(expected_code),
            "{}: exit code mismatch (stderr: {})",
            name,
            String::from_utf8_lossy(&run.stderr)
        );
    }
}

#[test]
fn stdlib_cases_call_no_libc() {
    for case in cases() {
        let name = case.file_stem().unwrap().to_string_lossy().to_string();
        let out = axiom()
            .arg("emit-llvm")
            .arg(&case)
            .output()
            .expect("run axiom emit-llvm");
        assert!(out.status.success(), "{}: emit-llvm failed", name);
        let ir = String::from_utf8_lossy(&out.stdout);

        for line in ir.lines() {
            let trimmed = line.trim_start();
            if !trimmed.contains("call") {
                continue;
            }
            for forbidden in FORBIDDEN_LIBC_CALLS {
                assert!(
                    !trimmed.contains(&format!("{}(", forbidden)),
                    "{}: generated code calls libc's {}:\n  {}",
                    name,
                    forbidden,
                    trimmed
                );
            }
        }
    }
}

#[test]
fn stdlib_cross_compiles_to_every_target() {
    // The standard library selects per-platform syscall numbers by
    // filename suffix, so a missing or malformed platform module only
    // shows up when compiling *for* that platform. Emitting IR for all
    // four targets from one host catches that without needing four
    // machines; actually running the result is the CI matrix's job.
    let targets = [
        "darwin-aarch64",
        "darwin-x86_64",
        "linux-aarch64",
        "linux-x86_64",
    ];
    for case in cases() {
        let name = case.file_stem().unwrap().to_string_lossy().to_string();
        for target in targets {
            let out = axiom()
                .arg(format!("--target={}", target))
                .arg("emit-llvm")
                .arg(&case)
                .output()
                .expect("run axiom emit-llvm");
            assert!(
                out.status.success(),
                "{}: emit-llvm for {} failed:\n{}",
                name,
                target,
                String::from_utf8_lossy(&out.stderr)
            );
            let ir = String::from_utf8_lossy(&out.stdout);
            assert!(
                ir.contains("asm sideeffect"),
                "{}: IR for {} contains no syscall - did the platform module resolve?",
                name,
                target
            );
        }
    }
}

#[test]
fn optimised_builds_turn_tail_recursion_into_a_loop() {
    // Axiom has no loop construct: every stdlib iteration - scanning a
    // string, copying memory, draining a file descriptor - is written as
    // tail recursion. At `-O0` each iteration costs a stack frame, so a
    // scan of a few hundred thousand bytes dies on an 8 MiB stack; `opt`
    // is what collapses those frames into a loop. This test pins that
    // the optimiser is actually wired into the pipeline, because the
    // symptom of it not being is a crash only on large inputs.
    let dir = scratch_dir("deep-loop");
    let src = dir.join("deep.ax");
    std::fs::write(
        &src,
        "(import IO)\n\
         (:: main Int)\n\
         ;@axiom:effect(io)\n\
         (fn (main)\n\
           (let ((s (strAlloc 500000)))\n\
             {\n\
               (memSet (strData s) 65 500000)\n\
               (printlnInt (cstrLen (strData s) 0))\n\
               0\n\
             }))\n",
    )
    .expect("write source");

    let exe = dir.join("deep");
    let build = axiom()
        .arg("build")
        .arg("--input")
        .arg(&src)
        .arg("--output")
        .arg(&exe)
        .arg("--opt")
        .arg("2")
        .current_dir(&dir)
        .output()
        .expect("run axiom build");
    assert!(
        build.status.success(),
        "build failed:\n{}",
        String::from_utf8_lossy(&build.stderr)
    );

    let run = Command::new(&exe).output().expect("run program");
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        "500000\n",
        "a 500k-iteration tail-recursive scan did not complete (exit {:?})",
        run.status.code()
    );
}
