//! Standalone Cargo and binding orchestration for Axiom's Rust FFI.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{exit, Command, Stdio};

mod host;

const USAGE: &str = "\
axiom-oxide - build both directions of Axiom's Rust FFI

usage: axiom-oxide prepare --crate <dir> [--release]
       axiom-oxide host --input <file.ax> --rust <file.rs> --archive <file.a>
                        [--axiom <path>] [--keep-source <file.ax>] [--no-build]

prepare refreshes a crate's Axiom module with axiom-bindgen and builds its
static archive with Cargo. host generates Axiom record accessors and Rust
host wrappers, then builds a static archive with the ordinary Axiom compiler.
";

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 || matches!(args[1].as_str(), "--help" | "-h" | "help") {
        print!("{USAGE}");
        return;
    }
    let result = match args[1].as_str() {
        "prepare" => prepare(&args[2..]),
        "host" => host::run(&args[2..]),
        other => Err(format!("unknown command `{other}`\n\n{USAGE}")),
    };
    if let Err(message) = result {
        eprintln!("axiom-oxide: {message}");
        exit(1);
    }
}

fn prepare(args: &[String]) -> Result<(), String> {
    let mut crate_dir = None;
    let mut release = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--crate" => {
                i += 1;
                crate_dir = Some(PathBuf::from(
                    args.get(i).ok_or("--crate needs a directory")?,
                ));
            }
            "--release" => release = true,
            other => return Err(format!("unknown prepare flag `{other}`")),
        }
        i += 1;
    }
    let dir = crate_dir.ok_or("prepare requires --crate <dir>")?;
    let manifest = dir.join("Cargo.toml");
    let text = fs::read_to_string(&manifest)
        .map_err(|e| format!("cannot read {}: {e}", manifest.display()))?;
    let package = package_name(&text).ok_or("Cargo.toml has no package name")?;
    let stem = package.replace('-', "_");
    let module = module_name(&dir, &package)?;
    let output = dir.join("axiom").join(format!("{module}.ax"));
    run(
        Command::new(sibling_tool("axiom-bindgen"))
            .arg("--src")
            .arg(dir.join("src"))
            .arg("--lib")
            .arg(&stem)
            .arg("--module")
            .arg(&module)
            .arg("-o")
            .arg(&output),
        "axiom-bindgen",
    )?;
    let mut cargo = Command::new("cargo");
    cargo.arg("build").arg("--manifest-path").arg(&manifest);
    if release {
        cargo.arg("--release");
    }
    run(&mut cargo, "cargo")?;
    eprintln!("axiom-oxide: prepared {package}");
    Ok(())
}

fn run(command: &mut Command, name: &str) -> Result<(), String> {
    eprintln!("axiom-oxide: running {name}");
    let status = command
        .stdin(Stdio::null())
        .status()
        .map_err(|e| format!("could not run {name}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{name} exited with {status}"))
    }
}

fn sibling_tool(name: &str) -> PathBuf {
    env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.join(name)))
        .filter(|p| p.is_file())
        .unwrap_or_else(|| PathBuf::from(name))
}

fn package_name(text: &str) -> Option<String> {
    let mut in_package = false;
    for raw in text.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.starts_with('[') {
            in_package = line == "[package]";
        } else if in_package && line.starts_with("name") {
            let (key, value) = line.split_once('=')?;
            if key.trim() == "name" {
                return Some(value.trim().trim_matches('"').to_owned());
            }
        }
    }
    None
}

fn module_name(dir: &Path, package: &str) -> Result<String, String> {
    let axiom = dir.join("axiom");
    let mut modules = fs::read_dir(&axiom)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("ax"))
        .collect::<Vec<_>>();
    modules.sort();
    if modules.len() == 1 {
        return Ok(modules[0]
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .split('.')
            .next()
            .unwrap_or_default()
            .to_owned());
    }
    if modules.len() > 1 {
        return Err(format!(
            "{} contains more than one Axiom module",
            axiom.display()
        ));
    }
    let stripped = package.strip_prefix("axiom-").unwrap_or(package);
    let mut chars = stripped.chars();
    Ok(chars
        .next()
        .map(|c| c.to_uppercase().collect::<String>() + chars.as_str())
        .unwrap_or_default())
}
