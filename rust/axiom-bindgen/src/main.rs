//! The `axiom-bindgen` command. The generator itself is the library
//! (`axiom_bindgen::generate`); this file is argument handling.

use std::path::{Path, PathBuf};
use std::process::exit;

const USAGE: &str = "\
axiom-bindgen - write the Axiom module that binds a crate's #[axiom_export] surface

usage: axiom-bindgen --src <dir> --lib <name> [--module <Name>] [-o <file.ax>]
       axiom-bindgen --src <dir> --lib <name> --check <file.ax>
       axiom-bindgen --help

  --src <dir>       the crate's source root (every .rs under it is read)
  --lib <name>      the archive stem: `--lib axiom_demo` binds libaxiom_demo.a
                    and is the string the extern block carries
  --module <Name>   the Axiom module name; with -o it must match the output
                    file's stem (an Axiom module IS its file name), and when
                    -o names a directory the file is <dir>/<Name>.ax
  -o, --output <f>  where to write; omitted, the module goes to stdout
  --check <file>    regenerate and compare with <file>; exit 1 if it differs

The module imports Ffi (and Err when a Result wrapper exists), binds every
pub #[axiom_export] fn and every hand-written `pub extern \"C\" fn axffi_*`,
and declares one `data` type per #[axiom_opaque] type.
";

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut src_root: Option<PathBuf> = None;
    let mut lib: Option<String> = None;
    let mut module: Option<String> = None;
    let mut out: Option<PathBuf> = None;
    let mut check: Option<PathBuf> = None;

    let mut i = 1;
    let value = |i: &mut usize, flag: &str| -> String {
        *i += 1;
        match args.get(*i) {
            Some(v) => v.clone(),
            None => {
                eprintln!("axiom-bindgen: {flag} needs a value\n\n{USAGE}");
                exit(2)
            }
        }
    };
    while i < args.len() {
        match args[i].as_str() {
            "--help" | "-h" => {
                print!("{USAGE}");
                return;
            }
            "--src" => src_root = Some(PathBuf::from(value(&mut i, "--src"))),
            "--lib" => lib = Some(value(&mut i, "--lib")),
            "--module" => module = Some(value(&mut i, "--module")),
            "-o" | "--output" => out = Some(PathBuf::from(value(&mut i, "-o"))),
            "--check" => check = Some(PathBuf::from(value(&mut i, "--check"))),
            other => {
                eprintln!("axiom-bindgen: unknown flag `{other}`\n\n{USAGE}");
                exit(2)
            }
        }
        i += 1;
    }

    let Some(src_root) = src_root else {
        eprintln!("axiom-bindgen: --src <dir> is required\n\n{USAGE}");
        exit(2)
    };
    let Some(lib) = lib else {
        eprintln!("axiom-bindgen: --lib <name> is required (the archive stem, e.g. axiom_demo)\n\n{USAGE}");
        exit(2)
    };
    if check.is_some() && out.is_some() {
        eprintln!("axiom-bindgen: --check and -o are exclusive (one compares, the other writes)");
        exit(2)
    }

    // `--module` and the output file must agree: an Axiom module's name
    // IS its file name - the part before the first `.`, so that
    // `Demo.ax`, `Demo.darwin-aarch64.ax` and a scratch `Demo.regen.ax`
    // all name `Demo` - and a mismatch would bind the module under a
    // name nothing can import.
    let out = match (&module, out) {
        (Some(m), Some(p)) if p.is_dir() => Some(p.join(format!("{m}.ax"))),
        // A path with no `.ax` extension is a DIRECTORY the caller
        // means to create: `-o crate/axiom` on a fresh crate, which
        // is the first thing a developer types.
        (Some(m), Some(p)) if p.extension().is_none() => {
            if let Err(e) = std::fs::create_dir_all(&p) {
                eprintln!("axiom-bindgen: cannot create `{}`: {e}", p.display());
                exit(2)
            }
            Some(p.join(format!("{m}.ax")))
        }
        (Some(m), Some(p)) => {
            if module_of(&p) != *m {
                eprintln!(
                    "axiom-bindgen: --module {m} but the output file is `{}`: an Axiom \
                     module's name is its file name, so write it to {m}.ax",
                    p.display()
                );
                exit(2)
            }
            Some(p)
        }
        (_, p) => p,
    };
    if let (Some(m), Some(c)) = (&module, &check) {
        if module_of(c) != *m {
            eprintln!(
                "axiom-bindgen: --module {m} but --check names `{}`: the module's name is \
                 its file name",
                c.display()
            );
            exit(2)
        }
    }

    let text = match axiom_bindgen::generate(&src_root, &lib) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("axiom-bindgen: {e}");
            exit(1)
        }
    };

    if let Some(c) = check {
        exit(check_against(&c, &text))
    }
    match out {
        Some(p) => {
            if let Some(parent) = p.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            if let Err(e) = std::fs::write(&p, &text) {
                eprintln!("axiom-bindgen: {}: {e}", p.display());
                exit(1)
            }
            eprintln!("axiom-bindgen: wrote {}", p.display());
        }
        None => print!("{text}"),
    }
}

/// The module a file names: its file name up to the first `.`.
fn module_of(p: &Path) -> String {
    p.file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default()
        .split('.')
        .next()
        .unwrap_or_default()
        .to_string()
}

/// Compare the fresh module with a checked-in one. Answers the exit
/// status: 0 when identical, 1 otherwise (missing counts as differing).
fn check_against(path: &Path, fresh: &str) -> i32 {
    let committed = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("axiom-bindgen: --check {}: {e}", path.display());
            return 1;
        }
    };
    if committed == fresh {
        eprintln!("axiom-bindgen: {} is what a fresh generation produces", path.display());
        return 0;
    }
    eprintln!(
        "axiom-bindgen: {} differs from a fresh generation; regenerate it with -o",
        path.display()
    );
    let old: Vec<&str> = committed.lines().collect();
    let new: Vec<&str> = fresh.lines().collect();
    let mut shown = 0;
    for (n, (a, b)) in old.iter().zip(new.iter()).enumerate() {
        if a != b {
            eprintln!("  line {}:\n    - {a}\n    + {b}", n + 1);
            shown += 1;
            if shown == 5 {
                break;
            }
        }
    }
    if old.len() != new.len() {
        eprintln!("  ({} lines checked in, {} generated)", old.len(), new.len());
    }
    1
}
