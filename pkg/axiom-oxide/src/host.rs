//! Generate Axiom accessors and the safe Rust view of an Axiom archive.

use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug)]
enum Sexp {
    Atom(String),
    List(Vec<Sexp>),
}
impl Sexp {
    fn atom(&self) -> Option<&str> {
        if let Sexp::Atom(s) = self {
            Some(s)
        } else {
            None
        }
    }
    fn list(&self) -> Option<&[Sexp]> {
        if let Sexp::List(v) = self {
            Some(v)
        } else {
            None
        }
    }
}

fn parse(source: &str) -> Result<Vec<Sexp>, String> {
    let bytes = source.as_bytes();
    let mut at = 0;
    let mut out = Vec::new();
    while at < bytes.len() {
        skip_space(bytes, &mut at);
        if at < bytes.len() {
            out.push(parse_one(bytes, &mut at)?);
        }
    }
    Ok(out)
}
fn skip_space(bytes: &[u8], at: &mut usize) {
    loop {
        while *at < bytes.len() && bytes[*at].is_ascii_whitespace() {
            *at += 1;
        }
        if *at < bytes.len() && bytes[*at] == b';' {
            while *at < bytes.len() && bytes[*at] != b'\n' {
                *at += 1;
            }
        } else {
            break;
        }
    }
}
fn parse_one(bytes: &[u8], at: &mut usize) -> Result<Sexp, String> {
    skip_space(bytes, at);
    match bytes.get(*at) {
        Some(b'(') | Some(b'[') | Some(b'{') => {
            let close = match bytes[*at] {
                b'(' => b')',
                b'[' => b']',
                _ => b'}',
            };
            *at += 1;
            let mut items = Vec::new();
            loop {
                skip_space(bytes, at);
                match bytes.get(*at) {
                    Some(c) if *c == close => {
                        *at += 1;
                        return Ok(Sexp::List(items));
                    }
                    None => return Err("unclosed form in Axiom source".into()),
                    _ => items.push(parse_one(bytes, at)?),
                }
            }
        }
        Some(b'"') => {
            *at += 1;
            let mut value = String::from("\"");
            while let Some(b) = bytes.get(*at) {
                *at += 1;
                value.push(char::from(*b));
                if *b == b'\\' {
                    if let Some(next) = bytes.get(*at) {
                        value.push(char::from(*next));
                        *at += 1;
                    }
                } else if *b == b'"' {
                    break;
                }
            }
            Ok(Sexp::Atom(value))
        }
        Some(_) => {
            let start = *at;
            while *at < bytes.len()
                && !bytes[*at].is_ascii_whitespace()
                && !b"()[]{};".contains(&bytes[*at])
            {
                *at += 1;
            }
            Ok(Sexp::Atom(
                String::from_utf8_lossy(&bytes[start..*at]).into_owned(),
            ))
        }
        None => Err("unexpected end of Axiom source".into()),
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Ty {
    Con(String, Vec<Ty>),
    Var(String),
    Arr(Box<Ty>, Box<Ty>),
    Tuple(Vec<Ty>),
}
impl Ty {
    fn name(&self) -> &str {
        if let Ty::Con(n, _) = self {
            n
        } else {
            ""
        }
    }
    fn source(&self) -> String {
        match self {
            Ty::Con(n, a) if a.is_empty() => source_name(n),
            Ty::Con(n, a) => format!(
                "({}{})",
                source_name(n),
                a.iter()
                    .map(|t| format!(" {}", t.source()))
                    .collect::<String>()
            ),
            Ty::Var(n) => n.clone(),
            Ty::Arr(_, _) => {
                let mut parts = Vec::new();
                let mut cur = self;
                while let Ty::Arr(a, b) = cur {
                    parts.push(a.source());
                    cur = b;
                }
                parts.push(cur.source());
                format!("(-> {})", parts.join(" "))
            }
            Ty::Tuple(v) if v.is_empty() => "()".into(),
            Ty::Tuple(v) => format!(
                "(Tuple{})",
                v.iter()
                    .map(|t| format!(" {}", t.source()))
                    .collect::<String>()
            ),
        }
    }
    fn mangle(&self) -> String {
        match self {
            Ty::Con(n, a) => format!(
                "{}{}",
                carrier_name(n),
                a.iter()
                    .map(|t| format!("_{}", t.mangle()))
                    .collect::<String>()
            ),
            _ => "_".into(),
        }
    }
    fn subst(&self, vars: &[String], args: &[Ty]) -> Ty {
        match self {
            Ty::Var(n) => vars
                .iter()
                .position(|v| v == n)
                .and_then(|i| args.get(i))
                .cloned()
                .unwrap_or_else(|| self.clone()),
            Ty::Con(n, a) => Ty::Con(n.clone(), a.iter().map(|t| t.subst(vars, args)).collect()),
            Ty::Arr(a, b) => Ty::Arr(Box::new(a.subst(vars, args)), Box::new(b.subst(vars, args))),
            Ty::Tuple(v) => Ty::Tuple(v.iter().map(|t| t.subst(vars, args)).collect()),
        }
    }
}
fn source_name(name: &str) -> String {
    name.replace('$', "::")
}
fn carrier_name(name: &str) -> String {
    if name == "Err$Result" {
        "Err_Result".into()
    } else {
        name.into()
    }
}
fn type_name(name: &str) -> String {
    name.replace("::", "$")
}
fn standard_result(ty: &Ty) -> Ty {
    match ty {
        Ty::Con(name, args) if name == "Result" => Ty::Con(
            "Err$Result".into(),
            args.iter().map(standard_result).collect(),
        ),
        Ty::Con(name, args) => Ty::Con(name.clone(), args.iter().map(standard_result).collect()),
        Ty::Arr(from, to) => Ty::Arr(
            Box::new(standard_result(from)),
            Box::new(standard_result(to)),
        ),
        Ty::Tuple(items) => Ty::Tuple(items.iter().map(standard_result).collect()),
        Ty::Var(_) => ty.clone(),
    }
}
fn ty(sexp: &Sexp) -> Result<Ty, String> {
    match sexp {
        Sexp::Atom(n) => Ok(if n.chars().next().is_some_and(|c| c.is_lowercase()) {
            Ty::Var(n.clone())
        } else {
            Ty::Con(type_name(n), vec![])
        }),
        Sexp::List(v) => {
            if v.is_empty() {
                return Ok(Ty::Tuple(vec![]));
            }
            match v[0].atom() {
                Some("->") if v.len() >= 3 => {
                    let mut result = ty(v.last().unwrap())?;
                    for item in v[1..v.len() - 1].iter().rev() {
                        result = Ty::Arr(Box::new(ty(item)?), Box::new(result));
                    }
                    Ok(result)
                }
                Some("Tuple") => Ok(Ty::Tuple(v[1..].iter().map(ty).collect::<Result<_, _>>()?)),
                Some(name) => Ok(Ty::Con(
                    type_name(name),
                    v[1..].iter().map(ty).collect::<Result<_, _>>()?,
                )),
                None => Err("invalid Axiom type".into()),
            }
        }
    }
}

#[derive(Clone, Debug)]
struct Ctor {
    name: String,
    tys: Vec<Ty>,
    fields: Option<Vec<String>>,
}
#[derive(Clone, Debug)]
struct Data {
    name: String,
    vars: Vec<String>,
    ctors: Vec<Ctor>,
    structure: bool,
}
#[derive(Clone, Debug)]
struct Function {
    name: String,
    params: Vec<String>,
}
#[derive(Default)]
struct Surface {
    data: Vec<Data>,
    aliases: Vec<(String, Ty)>,
    sigs: Vec<(String, Ty)>,
    functions: Vec<Function>,
}

impl Surface {
    fn read(forms: &[Sexp]) -> Result<Self, String> {
        let mut surface = Self::default();
        for form in forms {
            let Sexp::List(v) = form else { continue };
            if v.first().and_then(Sexp::atom) != Some("pub") || v.len() < 2 {
                continue;
            }
            match v[1].atom() {
                Some("::") if v.len() >= 4 => {
                    if let Some(n) = v[2].atom() {
                        surface.sigs.push((n.into(), ty(&v[3])?));
                    }
                }
                Some("fn") if v.len() >= 3 => {
                    if let Some(head) = v[2].list()
                        && let Some(n) = head.first().and_then(Sexp::atom)
                    {
                        surface.functions.push(Function {
                            name: n.into(),
                            params: head[1..]
                                .iter()
                                .filter_map(Sexp::atom)
                                .map(str::to_owned)
                                .collect(),
                        });
                    }
                }
                Some("data") | Some("struct") if v.len() >= 3 => {
                    let structure = v[1].atom() == Some("struct");
                    let Some(name) = v[2].atom() else { continue };
                    let (vars, ctor_at) = if structure {
                        (vec![], 3)
                    } else if let Some(parameters) = v.get(3).and_then(Sexp::list)
                        && parameters.iter().all(|parameter| {
                            parameter.atom().is_some_and(|name| {
                                name.chars().next().is_some_and(|c| c.is_lowercase())
                            })
                        })
                    {
                        (
                            parameters
                                .iter()
                                .filter_map(Sexp::atom)
                                .map(str::to_owned)
                                .collect(),
                            4,
                        )
                    } else {
                        let ctor_at = 3 + v[3..].iter().take_while(|x| x.atom().is_some()).count();
                        (
                            v[3..ctor_at]
                                .iter()
                                .filter_map(Sexp::atom)
                                .map(str::to_owned)
                                .collect(),
                            ctor_at,
                        )
                    };
                    let mut ctors = Vec::new();
                    if structure {
                        let mut tys = vec![];
                        let mut fields = vec![];
                        for field in &v[ctor_at..] {
                            if let Some(f) = field.list()
                                && let (Some(n), Some(t)) =
                                    (f.first().and_then(Sexp::atom), f.last())
                            {
                                fields.push(n.into());
                                tys.push(ty(t)?);
                            }
                        }
                        ctors.push(Ctor {
                            name: name.into(),
                            tys,
                            fields: Some(fields),
                        });
                    } else {
                        for ctor in &v[ctor_at..] {
                            if let Some(c) = ctor.list()
                                && let Some(n) = c.first().and_then(Sexp::atom)
                            {
                                let named = c.iter().skip(1).any(|x| x.atom() == Some(":"));
                                let mut tys = vec![];
                                let mut fields = vec![];
                                let mut i = 1;
                                while i < c.len() {
                                    if named && i + 2 < c.len() {
                                        fields.push(c[i].atom().unwrap_or_default().into());
                                        tys.push(ty(&c[i + 2])?);
                                        i += 3;
                                    } else {
                                        tys.push(ty(&c[i])?);
                                        i += 1;
                                    }
                                }
                                ctors.push(Ctor {
                                    name: n.into(),
                                    tys,
                                    fields: named.then_some(fields),
                                });
                            }
                        }
                    }
                    surface.data.push(Data {
                        name: name.into(),
                        vars,
                        ctors,
                        structure,
                    });
                }
                Some("type") if v.len() >= 4 => {
                    if let Some(n) = v[2].atom() {
                        surface.aliases.push((n.into(), ty(&v[3])?));
                    }
                }
                _ => {}
            }
        }
        if !surface.data.iter().any(|data| data.name == "Result") {
            for data in &mut surface.data {
                for ctor in &mut data.ctors {
                    for ty in &mut ctor.tys {
                        *ty = standard_result(ty);
                    }
                }
            }
            for (_, ty) in &mut surface.aliases {
                *ty = standard_result(ty);
            }
            for (_, ty) in &mut surface.sigs {
                *ty = standard_result(ty);
            }
        }
        Ok(surface)
    }
    fn resolve(&self, ty: &Ty) -> Ty {
        self.resolve_seen(ty, &mut vec![])
    }
    fn resolve_seen(&self, ty: &Ty, seen: &mut Vec<String>) -> Ty {
        match ty {
            Ty::Con(n, a) if a.is_empty() && !seen.contains(n) => {
                if let Some((_, target)) = self.aliases.iter().rev().find(|(name, _)| name == n) {
                    seen.push(n.clone());
                    return self.resolve_seen(target, seen);
                }
                ty.clone()
            }
            Ty::Con(n, a) => Ty::Con(
                n.clone(),
                a.iter().map(|t| self.resolve_seen(t, seen)).collect(),
            ),
            Ty::Arr(a, b) => Ty::Arr(
                Box::new(self.resolve_seen(a, seen)),
                Box::new(self.resolve_seen(b, seen)),
            ),
            Ty::Tuple(v) => Ty::Tuple(v.iter().map(|t| self.resolve_seen(t, seen)).collect()),
            _ => ty.clone(),
        }
    }
    fn signature(&self, name: &str) -> Option<Ty> {
        self.sigs
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, t)| self.resolve(t))
    }
    fn data(&self, name: &str) -> Option<&Data> {
        self.data.iter().rev().find(|d| d.name == name)
    }
    fn is_data(&self, ty: &Ty) -> bool {
        matches!(ty, Ty::Con(n, _) if n == "Option" || n == "Err$Result" || self.data(n).is_some())
    }
    fn ctors(&self, ty: &Ty) -> Vec<Ctor> {
        let Ty::Con(name, args) = ty else {
            return vec![];
        };
        match name.as_str() {
            "Option" => vec![
                Ctor {
                    name: "None".into(),
                    tys: vec![],
                    fields: None,
                },
                Ctor {
                    name: "Some".into(),
                    tys: vec![args[0].clone()],
                    fields: None,
                },
            ],
            "Err$Result" => vec![
                Ctor {
                    name: "Ok".into(),
                    tys: vec![args[0].clone()],
                    fields: None,
                },
                Ctor {
                    name: "Err".into(),
                    tys: vec![args[1].clone()],
                    fields: None,
                },
            ],
            _ => self
                .data(name)
                .map(|d| {
                    d.ctors
                        .iter()
                        .map(|c| Ctor {
                            name: c.name.clone(),
                            tys: c.tys.iter().map(|t| t.subst(&d.vars, args)).collect(),
                            fields: c.fields.clone(),
                        })
                        .collect()
                })
                .unwrap_or_default(),
        }
    }
}

static TEMPORARY_SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct GeneratedSource {
    path: PathBuf,
    temporary_directory: Option<PathBuf>,
}

impl GeneratedSource {
    fn automatic(input: &Path, contents: &str) -> Result<Self, String> {
        let parent = input
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        Self::automatic_in(parent, contents)
    }

    fn automatic_in(parent: &Path, contents: &str) -> Result<Self, String> {
        for _ in 0..128 {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let sequence = TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let directory = parent.join(format!(
                ".axiom-oxide-{}-{stamp}-{sequence}",
                std::process::id()
            ));
            match create_private_directory(&directory) {
                Ok(()) => {
                    let path = directory.join("source.ax");
                    if let Err(error) = write_new_source(&path, contents) {
                        let _ = fs::remove_file(&path);
                        let _ = fs::remove_dir(&directory);
                        return Err(format!("cannot write {}: {error}", path.display()));
                    }
                    return Ok(Self {
                        path,
                        temporary_directory: Some(directory),
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => {
                    return Err(format!(
                        "cannot create temporary directory {}: {error}",
                        directory.display()
                    ));
                }
            }
        }
        Err(format!(
            "cannot create a unique temporary directory in {}",
            parent.display()
        ))
    }

    fn explicit(path: PathBuf, contents: &str) -> Result<Self, String> {
        fs::write(&path, contents).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
        Ok(Self {
            path,
            temporary_directory: None,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn is_automatic(&self) -> bool {
        self.temporary_directory.is_some()
    }
}

impl Drop for GeneratedSource {
    fn drop(&mut self) {
        if let Some(directory) = &self.temporary_directory {
            let _ = fs::remove_file(&self.path);
            let _ = fs::remove_dir(directory);
        }
    }
}

fn create_private_directory(path: &Path) -> std::io::Result<()> {
    let mut builder = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(0o700);
    }
    builder.create(path)
}

fn write_new_source(path: &Path, contents: &str) -> std::io::Result<()> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(contents.as_bytes())
}

// The automatic source sits one directory below the input. Put the input's
// directory back in the search path so sibling imports resolve as they did before.
fn compiler_module_path(input: &Path) -> Result<std::ffi::OsString, String> {
    let original = input
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let mut paths = vec![original.to_path_buf()];
    if let Some(existing) = std::env::var_os("AXIOM_PATH") {
        paths.extend(std::env::split_paths(&existing));
    }
    std::env::join_paths(paths).map_err(|error| {
        format!(
            "cannot construct AXIOM_PATH for {}: {error}",
            original.display()
        )
    })
}

pub fn run(args: &[String]) -> Result<(), String> {
    let (mut input, mut rust, mut archive, mut keep) = (None, None, None, None);
    let mut axiom = "axiom".to_owned();
    let mut build = true;
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--no-build" {
            build = false;
            i += 1;
            continue;
        }
        if args[i] == "--axiom" {
            i += 1;
            axiom = args.get(i).ok_or("--axiom needs a path")?.clone();
            i += 1;
            continue;
        }
        let slot = match args[i].as_str() {
            "--input" => &mut input,
            "--rust" => &mut rust,
            "--archive" => &mut archive,
            "--keep-source" => &mut keep,
            other => return Err(format!("unknown host flag `{other}`")),
        };
        i += 1;
        *slot = Some(PathBuf::from(args.get(i).ok_or("host flag needs a path")?));
        i += 1;
    }
    let input = input.ok_or("host requires --input <file.ax>")?;
    let rust = rust.ok_or("host requires --rust <file.rs>")?;
    let archive = archive.ok_or("host requires --archive <file.a>")?;
    let source =
        fs::read_to_string(&input).map_err(|e| format!("cannot read {}: {e}", input.display()))?;
    let surface = Surface::read(&parse(&source)?)?;
    let instances = surface.instances();
    if let Some(name) = surface.collision(&instances) {
        return Err(format!(
            "generated accessor names collide for `{name}`; rename one source type"
        ));
    }
    let generated = format!("(import Vec)\n{source}\n{}", surface.shims(&instances));
    let temporary = match keep {
        Some(path) => GeneratedSource::explicit(path, &generated)?,
        None => GeneratedSource::automatic(&input, &generated)?,
    };
    fs::write(&rust, surface.rust_bindings(&input, &instances))
        .map_err(|e| format!("cannot write {}: {e}", rust.display()))?;
    let _ = Command::new("rustfmt")
        .args(["--edition", "2021", "--quiet"])
        .arg(&rust)
        .status();
    if build {
        let mut command = Command::new(&axiom);
        command
            .arg("build")
            .arg("--input")
            .arg(temporary.path())
            .arg("--output")
            .arg(&archive)
            .arg("--emit-staticlib");
        if temporary.is_automatic() {
            command.env("AXIOM_PATH", compiler_module_path(&input)?);
        }
        let status = command
            .status()
            .map_err(|e| format!("could not run {axiom}: {e}"))?;
        if !status.success() {
            return Err(format!(
                "Axiom archive build exited with {status}; generated source is {}",
                temporary.path().display()
            ));
        }
    }
    eprintln!(
        "axiom-oxide: wrote {} and {}",
        rust.display(),
        archive.display()
    );
    Ok(())
}

fn rust_ident(name: &str) -> bool {
    let mut chars = name.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}
fn snake(name: &str) -> String {
    let mut out = String::new();
    for (i, c) in name.chars().enumerate() {
        if c.is_ascii_uppercase() {
            if i > 0 {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    const WORDS: &[&str] = &[
        "as", "box", "fn", "impl", "in", "loop", "match", "mod", "move", "mut", "ref", "self",
        "type", "use", "where", "let", "if", "else", "for", "while", "return", "struct", "enum",
        "trait", "pub", "crate", "super", "static", "const", "true", "false", "unsafe", "extern",
        "dyn", "async", "await", "break", "continue", "yield",
    ];
    if WORDS.contains(&out.as_str()) {
        out.push('_');
    }
    out
}

fn is_word(ty: &Ty) -> bool {
    matches!(ty, Ty::Con(n, a) if a.is_empty() && matches!(n.as_str(), "Int" | "Float" | "Bool" | "Char" | "Handle" | "Foreign"))
}
fn is_string(ty: &Ty) -> bool {
    matches!(ty, Ty::Con(n, a) if n == "String" && a.is_empty())
}
fn is_vec(ty: &Ty) -> bool {
    matches!(ty, Ty::Con(n, _) if n == "Vec")
}
fn is_int_vec(ty: &Ty) -> bool {
    matches!(ty, Ty::Con(n, a) if n == "Vec" && matches!(a.as_slice(), [Ty::Con(e, x)] if e == "Int" && x.is_empty()))
}
fn arrow_parts(ty: &Ty) -> (Vec<Ty>, Ty) {
    let mut params = vec![];
    let mut cur = ty;
    while let Ty::Arr(a, b) = cur {
        params.push((**a).clone());
        cur = b;
    }
    (params, cur.clone())
}
impl Surface {
    fn type_names_spellable(&self, ty: &Ty) -> bool {
        rust_ident(&carrier_name(ty.name()))
            && self.ctors(ty).iter().all(|c| {
                rust_ident(&c.name)
                    && c.fields
                        .as_ref()
                        .is_none_or(|f| f.iter().all(|n| rust_ident(n)))
            })
    }
    fn carried_seen(&self, ty: &Ty, visiting: &mut Vec<String>) -> bool {
        if is_word(ty) || is_string(ty) || is_vec(ty) {
            return true;
        }
        if !self.is_data(ty) || !self.type_names_spellable(ty) {
            return false;
        }
        let m = ty.mangle();
        if visiting.contains(&m) {
            return true;
        }
        visiting.push(m);
        let answer = self
            .ctors(ty)
            .iter()
            .flat_map(|c| c.tys.iter())
            .all(|t| self.carried_seen(t, visiting));
        visiting.pop();
        answer
    }
    fn carried(&self, ty: &Ty) -> bool {
        self.carried_seen(ty, &mut vec![])
    }
    fn raw_in_seen(&self, ty: &Ty, visiting: &mut Vec<String>) -> bool {
        if matches!(ty, Ty::Con(n, _) if n == "Handle" || n == "Foreign") {
            return true;
        }
        if is_vec(ty) {
            return !is_int_vec(ty);
        }
        if !self.is_data(ty) {
            return false;
        }
        let m = ty.source();
        if visiting.contains(&m) {
            return false;
        }
        visiting.push(m);
        let answer = self
            .ctors(ty)
            .iter()
            .flat_map(|c| c.tys.iter())
            .any(|t| self.raw_in_seen(t, visiting));
        visiting.pop();
        answer
    }
    fn raw_in(&self, ty: &Ty) -> bool {
        self.raw_in_seen(ty, &mut vec![])
    }
    fn rust_type(&self, ty: &Ty, position: u8) -> String {
        if let Ty::Con(n, a) = ty
            && a.is_empty()
        {
            match n.as_str() {
                "Int" => return "i64".into(),
                "Float" => return "f64".into(),
                "Bool" => return "bool".into(),
                "Char" => return "char".into(),
                "Handle" | "Foreign" => return "AxWord".into(),
                "String" => return if position == 0 { "&str" } else { "AxString" }.into(),
                _ => {}
            }
        }
        if is_int_vec(ty) {
            return if position == 0 {
                "&AxVecBuf"
            } else {
                "AxVecBuf"
            }
            .into();
        }
        if is_vec(ty) {
            return "AxWord".into();
        }
        if self.is_data(ty) {
            if !self.carried(ty) {
                return String::new();
            }
            let own = self.rust_data_name(ty);
            return if position == 0 {
                format!("&{own}")
            } else {
                own
            };
        }
        if matches!(ty, Ty::Tuple(v) if v.is_empty() && position == 1) {
            return "()".into();
        }
        String::new()
    }
    fn rust_data_name(&self, ty: &Ty) -> String {
        match ty {
            Ty::Con(n, a) if n == "Option" => format!("Option<{}>", self.rust_type(&a[0], 2)),
            Ty::Con(n, a) if n == "Err$Result" => format!(
                "Result<{}, {}>",
                self.rust_type(&a[0], 2),
                self.rust_type(&a[1], 2)
            ),
            _ => ty.mangle(),
        }
    }
    fn collect_instance(&self, ty: &Ty, out: &mut Vec<Ty>, seen: &mut HashSet<String>) {
        match ty {
            Ty::Arr(a, b) => {
                self.collect_instance(a, out, seen);
                self.collect_instance(b, out, seen);
            }
            Ty::Con(_, _) if self.is_data(ty) && self.carried(ty) && seen.insert(ty.source()) => {
                out.push(ty.clone());
                for field in self.ctors(ty).iter().flat_map(|c| c.tys.iter()) {
                    self.collect_instance(field, out, seen);
                }
            }
            _ => {}
        }
    }
    fn instances(&self) -> Vec<Ty> {
        let mut out = vec![];
        let mut seen = HashSet::new();
        for function in &self.functions {
            if let Some(sig) = self.signature(&function.name) {
                self.collect_instance(&sig, &mut out, &mut seen);
            }
        }
        out
    }
    fn collision(&self, instances: &[Ty]) -> Option<String> {
        let mut names = HashSet::new();
        for ty in instances {
            let name = ty.mangle();
            if names.contains(&name) {
                return Some(name);
            }
            names.insert(name);
        }
        None
    }
    fn reaches_seen(&self, ty: &Ty, target: &str, visiting: &mut Vec<String>) -> bool {
        if !self.is_data(ty) {
            return false;
        }
        let m = ty.mangle();
        if m == target {
            return true;
        }
        if visiting.contains(&m) {
            return false;
        }
        visiting.push(m);
        let answer = self
            .ctors(ty)
            .iter()
            .flat_map(|c| c.tys.iter())
            .any(|t| self.reaches_seen(t, target, visiting));
        visiting.pop();
        answer
    }
    fn reaches(&self, ty: &Ty, target: &str) -> bool {
        self.reaches_seen(ty, target, &mut vec![])
    }
    fn shims(&self, instances: &[Ty]) -> String {
        let mut out = String::from("(pub :: axh_vec_new (Vec Int))\n(pub fn (axh_vec_new) vecNew)\n(pub :: axh_vec_push (-> (Vec Int) Int (Vec Int)))\n(pub fn (axh_vec_push v w) (vecPush v w))\n(pub :: axh_vec_len (-> (Vec Int) Int))\n(pub fn (axh_vec_len v) (vecLen v))\n(pub :: axh_vec_get (-> (Vec Int) Int Int))\n(pub fn (axh_vec_get v i) (vecGet v i))\n");
        for ty in instances {
            out.push_str(&self.shims_for(ty));
        }
        out
    }
    fn shims_for(&self, ty: &Ty) -> String {
        let m = ty.mangle();
        let ts = ty.source();
        let ctors = self.ctors(ty);
        let structure = self.data(ty.name()).is_some_and(|d| d.structure);
        let mut out = format!("(pub :: axh_{m}_tag (-> {ts} Int))\n");
        if structure {
            out.push_str(&format!("(pub fn (axh_{m}_tag v) 0)\n"));
        } else {
            out.push_str(&format!("(pub fn (axh_{m}_tag v) (match v"));
            for (j, ctor) in ctors.iter().enumerate() {
                let name = if ty.name() == "Err$Result" {
                    format!("Err::{}", ctor.name)
                } else {
                    ctor.name.clone()
                };
                out.push_str(&format!(" (({name}{}) {j})", binders(ctor.tys.len())));
            }
            out.push_str("))\n");
        }
        for ctor in ctors {
            let source_ctor = if ty.name() == "Err$Result" {
                format!("Err::{}", ctor.name)
            } else {
                ctor.name.clone()
            };
            if ctor.tys.is_empty() {
                out.push_str(&format!(
                    "(pub :: axh_{m}_{} {ts})\n(pub fn (axh_{m}_{}) {source_ctor})\n",
                    ctor.name, ctor.name
                ));
            } else {
                let args = if structure {
                    ctor.fields
                        .as_ref()
                        .unwrap()
                        .iter()
                        .enumerate()
                        .map(|(i, field)| format!(" :{field} a{i}"))
                        .collect::<String>()
                } else {
                    binders(ctor.tys.len())
                };
                out.push_str(&format!("(pub :: axh_{m}_{} (-> {}{ts}))\n(pub fn (axh_{m}_{}{}) ({source_ctor}{args}))\n", ctor.name, ctor.tys.iter().map(|t| format!("{} ", t.source())).collect::<String>(), ctor.name, binders(ctor.tys.len())));
            }
            for (k, field_ty) in ctor.tys.iter().enumerate() {
                out.push_str(&format!(
                    "(pub :: axh_{m}_{}_{k} (-> {ts} {}))\n",
                    ctor.name,
                    field_ty.source()
                ));
                if structure {
                    let field = ctor.fields.as_ref().and_then(|f| f.get(k)).unwrap();
                    out.push_str(&format!(
                        "(pub fn (axh_{m}_{}_{k} v) v.{field})\n",
                        ctor.name
                    ));
                } else {
                    out.push_str(&format!("(pub fn (axh_{m}_{}_{k} v) (match v (({source_ctor}{}) a{k}) (_ __indexTrap)))\n", ctor.name, binders(ctor.tys.len())));
                }
            }
        }
        out
    }
}
fn binders(n: usize) -> String {
    (0..n).map(|i| format!(" a{i}")).collect()
}
fn field_name(ctor: &Ctor, index: usize) -> String {
    ctor.fields
        .as_ref()
        .and_then(|f| f.get(index))
        .map(|f| snake(f))
        .unwrap_or_else(|| format!("f{index}"))
}
fn to_word(ty: &Ty, expr: &str, reference: bool) -> String {
    let deref = if reference { "*" } else { "" };
    if is_word(ty) {
        match ty.name() {
            "Float" => return format!("({deref}{expr}).to_bits() as i64"),
            "Bool" | "Char" => return format!("({deref}{expr}) as i64"),
            _ => return format!("{deref}{expr}"),
        }
    }
    if is_string(ty) || is_int_vec(ty) {
        return format!("{expr}.as_word()");
    }
    if is_vec(ty) {
        return format!("{deref}{expr}");
    }
    format!(
        "__to_{}({}{expr})",
        ty.mangle(),
        if reference { "" } else { "&" }
    )
}
fn from_word(ty: &Ty, word: &str) -> String {
    if is_word(ty) {
        return match ty.name() {
            "Float" => format!("f64::from_bits({word} as u64)"),
            "Bool" => format!("{word} != 0"),
            "Char" => format!("char::from_u32({word} as u32).unwrap_or('\\u{{FFFD}}')"),
            _ => word.into(),
        };
    }
    if is_string(ty) {
        return format!("unsafe {{ AxString::from_owned({word}) }}");
    }
    if is_int_vec(ty) {
        return format!("unsafe {{ AxVecBuf::from_owned({word}) }}");
    }
    if is_vec(ty) {
        return word.into();
    }
    format!("unsafe {{ __from_{}({word}) }}", ty.mangle())
}

impl Surface {
    fn rust_bindings(&self, input: &Path, instances: &[Ty]) -> String {
        let filename = input
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("library.ax")
            .chars()
            .map(|c| if c.is_control() { '?' } else { c })
            .collect::<String>();
        let mut out = format!(
            "//! GENERATED by `axiom-oxide host` from {filename}. Do not edit.\n\
             //!\n//! Link the archive produced beside this file. Arguments are borrowed;\n\
             //! results are owned shares. Every call takes the runtime's thread token.\n\
             #![allow(non_snake_case, non_camel_case_types, dead_code, unused_imports, unused_unsafe, unused_variables, clippy::all)]\n\n\
             use axiom_ffi::host::{{AxRuntime, AxString}};\nuse axiom_ffi::{{axiom_release, AxWord}};\n\n"
        );
        let mut raw = String::from("mod raw {\n    unsafe extern \"C\" {\n");
        let mut wrappers = String::new();
        let mut notes = Vec::new();
        for function in &self.functions {
            self.rust_function(function, &mut raw, &mut wrappers, &mut notes);
        }
        raw.push_str(&raw_vec_decls());
        for ty in instances {
            raw.push_str(&self.raw_type_decls(ty));
        }
        raw.push_str("    }\n}\n\n");
        out.push_str(&raw);
        out.push_str(VEC_BUF);
        for ty in instances {
            out.push_str(&self.rust_type_for(ty));
        }
        out.push_str(&wrappers);
        if !notes.is_empty() {
            out.push_str(
                "// Not bound - call these through the archive by hand, or change the type:\n",
            );
            for note in notes {
                out.push_str(&note);
            }
        }
        out
    }

    fn rust_function(
        &self,
        function: &Function,
        raw: &mut String,
        wrappers: &mut String,
        notes: &mut Vec<String>,
    ) {
        let name = &function.name;
        if !rust_ident(name) {
            notes.push(format!("// `{name}`: not a Rust identifier, so no `extern \"C\"` declaration can name it\n"));
            return;
        }
        let Some(signature) = self.signature(name) else {
            notes.push(format!(
                "// `{name}`: no `(pub :: name Type)` signature to bind it by\n"
            ));
            return;
        };
        let (params, result) = arrow_parts(&signature);
        if params.len() != function.params.len() {
            notes.push(format!(
                "// `{name}`: the signature and the definition disagree on arity\n"
            ));
            return;
        }
        if let Some(bad) = function.params.iter().find(|p| !rust_ident(p)) {
            notes.push(format!(
                "// `{name}`: its parameter `{bad}` is not a Rust identifier\n"
            ));
            return;
        }
        let unsupported = params
            .iter()
            .chain(std::iter::once(&result))
            .find(|t| self.rust_type(t, 0).is_empty() && self.rust_type(t, 1).is_empty());
        if let Some(bad) = unsupported {
            let reason = if self.is_data(bad) && !self.type_names_spellable(bad) {
                "whose name is not a Rust identifier"
            } else {
                "which the binding does not carry"
            };
            notes.push(format!(
                "// `{name}`: `{}` names `{}`, {reason}\n",
                signature.source(),
                bad.source()
            ));
            return;
        }
        raw.push_str(&format!(
            "        pub fn {name}({}) -> i64;\n",
            raw_params(params.len())
        ));
        let rty = self.rust_type(&result, 1);
        let unsafe_fn = params.iter().any(|t| self.raw_in(t));
        wrappers.push_str(&format!("/// `(pub :: {name} {})`\n", signature.source()));
        if unsafe_fn {
            wrappers.push_str("///\n/// # Safety\n/// Every `AxWord` argument, including one reachable through a field, must be a live Axiom value of its declared type.\n");
        }
        wrappers.push_str(&format!(
            "pub {}fn {}(rt: AxRuntime{}) {} {{\n",
            if unsafe_fn { "unsafe " } else { "" },
            param_name(name),
            params
                .iter()
                .zip(&function.params)
                .map(|(t, n)| format!(", {}: {}", param_name(n), self.rust_type(t, 0)))
                .collect::<String>(),
            if rty == "()" {
                String::new()
            } else {
                format!("-> {rty}")
            }
        ));
        for (i, (ty, name)) in params.iter().zip(&function.params).enumerate() {
            let name = param_name(name);
            if is_string(ty) {
                wrappers.push_str(&format!(
                    "    let __a{i} = AxString::from_str(rt, {name});\n"
                ));
            } else if self.is_data(ty) {
                wrappers.push_str(&format!("    let __a{i} = {};\n", to_word(ty, &name, true)));
            }
        }
        let args = params
            .iter()
            .zip(&function.params)
            .enumerate()
            .map(|(i, (ty, name))| {
                if is_string(ty) || self.is_data(ty) {
                    if is_string(ty) {
                        format!("__a{i}.as_word()")
                    } else {
                        format!("__a{i}")
                    }
                } else {
                    to_word(ty, &param_name(name), false)
                }
            })
            .collect::<Vec<_>>()
            .join(", ");
        wrappers.push_str(&format!("    // SAFETY: the archive defines this symbol with one word per argument and result.\n    let __r = unsafe {{ raw::{name}({args}) }};\n"));
        for (i, ty) in params.iter().enumerate() {
            if self.is_data(ty) {
                wrappers.push_str(&format!("    unsafe {{ axiom_release(__a{i}) }};\n"));
            }
        }
        if rty == "()" {
            wrappers.push_str("    let _ = __r;\n");
        } else if is_string(&result) {
            wrappers.push_str("    // SAFETY: a returned String is an owned share.\n    unsafe { AxString::from_owned(__r) }\n");
        } else {
            wrappers.push_str(&format!("    {}\n", from_word(&result, "__r")));
        }
        wrappers.push_str("}\n\n");
    }

    fn raw_type_decls(&self, ty: &Ty) -> String {
        let m = ty.mangle();
        let mut out = format!("        pub fn axh_{m}_tag(a0: i64) -> i64;\n");
        for ctor in self.ctors(ty) {
            out.push_str(&format!(
                "        pub fn axh_{m}_{}({}) -> i64;\n",
                ctor.name,
                raw_params(ctor.tys.len())
            ));
            for k in 0..ctor.tys.len() {
                out.push_str(&format!(
                    "        pub fn axh_{m}_{}_{k}(a0: i64) -> i64;\n",
                    ctor.name
                ));
            }
        }
        out
    }

    fn rust_type_for(&self, ty: &Ty) -> String {
        let m = ty.mangle();
        let rn = self.rust_data_name(ty);
        let ctors = self.ctors(ty);
        let builtin = matches!(ty.name(), "Option" | "Err$Result");
        let mut out = String::new();
        if !builtin {
            if ctors.len() == 1 {
                out.push_str(&format!(
                    "/// `{}`, one constructor\n#[derive(Debug)]\npub struct {rn} {{\n",
                    ty.source()
                ));
                for (k, field_ty) in ctors[0].tys.iter().enumerate() {
                    out.push_str(&format!(
                        "    pub {}: {},\n",
                        field_name(&ctors[0], k),
                        self.field_type(&m, field_ty)
                    ));
                }
                out.push_str("}\n\n");
            } else {
                out.push_str(&format!(
                    "/// `{}`, one variant per constructor\n#[derive(Debug)]\npub enum {rn} {{\n",
                    ty.source()
                ));
                for ctor in &ctors {
                    if ctor.tys.is_empty() {
                        out.push_str(&format!("    {},\n", ctor.name));
                    } else {
                        out.push_str(&format!(
                            "    {}({}),\n",
                            ctor.name,
                            ctor.tys
                                .iter()
                                .map(|t| self.field_type(&m, t))
                                .collect::<Vec<_>>()
                                .join(", ")
                        ));
                    }
                }
                out.push_str("}\n\n");
            }
        }
        out.push_str(&self.decode_fn(ty, &ctors, &rn));
        out.push_str(&self.to_fn(ty, &ctors, &rn));
        if !builtin {
            out.push_str(&format!(
                "impl {rn} {{\n    /// Adopt an Axiom value, consuming its owned share.\n    ///\n    /// # Safety\n    /// `word` must be a live Axiom `{}` the caller owns once.\n    pub unsafe fn from_axiom(rt: AxRuntime, word: AxWord) -> {rn} {{\n        unsafe {{ __from_{m}(word) }}\n    }}\n\n",
                ty.source()
            ));
            if self.raw_in(ty) {
                out.push_str(&format!("    /// Convert to an owned Axiom share.\n    ///\n    /// # Safety\n    /// Every reachable `AxWord` must be a live value of its declared Axiom type.\n    pub unsafe fn to_axiom(&self, rt: AxRuntime) -> AxWord {{ __to_{m}(self) }}\n}}\n\n"));
            } else {
                out.push_str(&format!("    /// Convert to an owned Axiom share.\n    pub fn to_axiom(&self, rt: AxRuntime) -> AxWord {{ __to_{m}(self) }}\n}}\n\n"));
            }
        }
        out
    }

    fn field_type(&self, parent: &str, ty: &Ty) -> String {
        let rt = self.rust_type(ty, 2);
        if self.reaches(ty, parent) {
            format!("Box<{rt}>")
        } else {
            rt
        }
    }

    fn decode_fn(&self, ty: &Ty, ctors: &[Ctor], rn: &str) -> String {
        let m = ty.mangle();
        let mut out = format!("unsafe fn __from_{m}(word: AxWord) -> {rn} {{\n    // SAFETY: the caller owns a live value of this type; accessors return owned shares.\n    let __tag = unsafe {{ raw::axh_{m}_tag(word) }};\n    let __v = match __tag {{\n");
        for (j, ctor) in ctors.iter().enumerate() {
            if ctor.tys.is_empty() {
                out.push_str(&format!(
                    "        {j} => {},\n",
                    ctor_expr(ty, ctor, rn, ctors.len(), "")
                ));
                continue;
            }
            out.push_str(&format!("        {j} => {{\n"));
            let mut args = Vec::new();
            for (k, field_ty) in ctor.tys.iter().enumerate() {
                out.push_str(&format!(
                    "            let __f{k} = unsafe {{ raw::axh_{m}_{}_{k}(word) }};\n",
                    ctor.name
                ));
                let value = from_word(field_ty, &format!("__f{k}"));
                let value = if self.reaches(field_ty, &m) {
                    format!("Box::new({value})")
                } else {
                    value
                };
                args.push(if ctors.len() == 1 {
                    format!("{}: {value}", field_name(ctor, k))
                } else {
                    value
                });
            }
            out.push_str(&format!(
                "            {}\n        }}\n",
                ctor_expr(ty, ctor, rn, ctors.len(), &args.join(", "))
            ));
        }
        out.push_str("        _ => unreachable!(\"a constructor index the type does not have\"),\n    };\n    unsafe { axiom_release(word) };\n    __v\n}\n\n");
        out
    }

    fn to_fn(&self, ty: &Ty, ctors: &[Ctor], rn: &str) -> String {
        let m = ty.mangle();
        let mut out = format!("fn __to_{m}(v: &{rn}) -> AxWord {{\n    match v {{\n");
        for ctor in ctors {
            let names = (0..ctor.tys.len())
                .map(|k| format!("a{k}"))
                .collect::<Vec<_>>();
            let pattern = names
                .iter()
                .enumerate()
                .map(|(k, n)| {
                    if ctors.len() == 1 {
                        format!("{}: {n}", field_name(ctor, k))
                    } else {
                        n.clone()
                    }
                })
                .collect::<Vec<_>>()
                .join(", ");
            out.push_str(&format!(
                "        {} => {{\n",
                ctor_pat(ty, ctor, rn, ctors.len(), &pattern)
            ));
            let mut args = Vec::new();
            for (k, field_ty) in ctor.tys.iter().enumerate() {
                let source = if self.reaches(field_ty, &m) {
                    format!("&**a{k}")
                } else {
                    format!("a{k}")
                };
                if self.is_data(field_ty) {
                    out.push_str(&format!(
                        "            let __w{k} = {};\n",
                        to_word(field_ty, &source, true)
                    ));
                    args.push(format!("__w{k}"));
                } else {
                    args.push(to_word(field_ty, &source, true));
                }
            }
            out.push_str(&format!(
                "            let __w = unsafe {{ raw::axh_{m}_{}({}) }};\n",
                ctor.name,
                args.join(", ")
            ));
            for (k, field_ty) in ctor.tys.iter().enumerate() {
                if self.is_data(field_ty) {
                    out.push_str(&format!(
                        "            unsafe {{ axiom_release(__w{k}) }};\n"
                    ));
                }
            }
            out.push_str("            __w\n        }\n");
        }
        out.push_str("    }\n}\n\n");
        out
    }
}

fn raw_params(n: usize) -> String {
    (0..n)
        .map(|i| format!("a{i}: i64"))
        .collect::<Vec<_>>()
        .join(", ")
}
fn raw_vec_decls() -> String {
    "        pub fn axh_vec_new() -> i64;\n        pub fn axh_vec_push(a0: i64, a1: i64) -> i64;\n        pub fn axh_vec_len(a0: i64) -> i64;\n        pub fn axh_vec_get(a0: i64, a1: i64) -> i64;\n".into()
}
fn param_name(name: &str) -> String {
    let name = snake(name);
    if name == "rt" {
        "rt_".into()
    } else {
        name
    }
}
fn ctor_expr(ty: &Ty, ctor: &Ctor, rn: &str, count: usize, args: &str) -> String {
    if matches!(ty.name(), "Option" | "Err$Result") {
        if ctor.tys.is_empty() {
            ctor.name.clone()
        } else {
            format!("{}({args})", ctor.name)
        }
    } else if count == 1 {
        format!("{rn} {{ {args} }}")
    } else if ctor.tys.is_empty() {
        format!("{rn}::{}", ctor.name)
    } else {
        format!("{rn}::{}({args})", ctor.name)
    }
}
fn ctor_pat(ty: &Ty, ctor: &Ctor, rn: &str, count: usize, args: &str) -> String {
    ctor_expr(ty, ctor, rn, count, args)
}

const VEC_BUF: &str = r#"/// An Axiom `(Vec Int)`, built and read through the archive's own `Vec`.
#[derive(Debug)]
pub struct AxVecBuf {
    word: AxWord,
    _thread: core::marker::PhantomData<*const ()>,
}

impl AxVecBuf {
    pub fn from_words(rt: AxRuntime, words: &[i64]) -> AxVecBuf {
        // SAFETY: these accessors return owned shares on the runtime's thread.
        let v = unsafe { raw::axh_vec_new() };
        for w in words {
            unsafe { raw::axh_vec_push(v, *w) };
        }
        AxVecBuf { word: v, _thread: core::marker::PhantomData }
    }

    /// Adopt an owned `(Vec Int)` word.
    ///
    /// # Safety
    /// `word` must be a live Axiom `(Vec Int)` owned once by the caller.
    pub unsafe fn from_owned(word: AxWord) -> AxVecBuf {
        AxVecBuf { word, _thread: core::marker::PhantomData }
    }

    pub fn as_word(&self) -> AxWord { self.word }
    pub fn len(&self) -> usize { unsafe { raw::axh_vec_len(self.word) as usize } }
    pub fn words(&self) -> Vec<i64> {
        (0..self.len()).map(|i| unsafe { raw::axh_vec_get(self.word, i as AxWord) }).collect()
    }
}

impl Drop for AxVecBuf {
    fn drop(&mut self) { unsafe { axiom_release(self.word) } }
}

"#;

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct TestDir(PathBuf);

    impl TestDir {
        fn new(name: &str) -> Self {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let sequence = TEST_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "axiom-oxide-host-{name}-{}-{stamp}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn args(input: &Path, rust: &Path, archive: &Path) -> Vec<String> {
        vec![
            "--input".into(),
            input.to_string_lossy().into_owned(),
            "--rust".into(),
            rust.to_string_lossy().into_owned(),
            "--archive".into(),
            archive.to_string_lossy().into_owned(),
        ]
    }

    fn write_input(dir: &Path) -> PathBuf {
        let input = dir.join("input.ax");
        fs::write(&input, "(pub :: answer Int)\n(pub fn (answer) 42)\n").unwrap();
        input
    }

    fn assert_no_automatic_artifacts(dir: &Path) {
        let artifacts = fs::read_dir(dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .filter(|name| name.to_string_lossy().starts_with(".axiom-oxide-"))
            .collect::<Vec<_>>();
        assert!(
            artifacts.is_empty(),
            "left temporary artifacts: {artifacts:?}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn automatic_source_does_not_follow_legacy_symlink() {
        let dir = TestDir::new("symlink");
        let input = write_input(dir.path());
        let rust = dir.path().join("binding.rs");
        let archive = dir.path().join("library.a");
        let victim = dir.path().join("victim");
        fs::write(&victim, "do not truncate").unwrap();
        let legacy = input.with_file_name(format!(".axiom-oxide-{}.ax", std::process::id()));
        std::os::unix::fs::symlink(&victim, &legacy).unwrap();

        let mut host_args = args(&input, &rust, &archive);
        host_args.push("--no-build".into());
        run(&host_args).unwrap();

        assert_eq!(fs::read_to_string(&victim).unwrap(), "do not truncate");
        assert!(fs::symlink_metadata(&legacy)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_no_automatic_artifacts_except(dir.path(), &legacy);

        let exclusive = dir.path().join("exclusive.ax");
        std::os::unix::fs::symlink(&victim, &exclusive).unwrap();
        let error = write_new_source(&exclusive, "must not follow").unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::AlreadyExists);
        assert_eq!(fs::read_to_string(&victim).unwrap(), "do not truncate");
    }

    #[cfg(unix)]
    fn assert_no_automatic_artifacts_except(dir: &Path, exception: &Path) {
        let artifacts = fs::read_dir(dir)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with(".axiom-oxide-"))
                    && path != exception
            })
            .collect::<Vec<_>>();
        assert!(
            artifacts.is_empty(),
            "left temporary artifacts: {artifacts:?}"
        );
    }

    #[test]
    fn keep_source_with_internal_prefix_survives_success_and_error() {
        let dir = TestDir::new("keep");
        let input = write_input(dir.path());
        let rust = dir.path().join("binding.rs");
        let archive = dir.path().join("library.a");
        let keep = dir.path().join(".axiom-oxide-kept.ax");
        let mut host_args = args(&input, &rust, &archive);
        host_args.extend(["--keep-source".into(), keep.to_string_lossy().into_owned()]);
        host_args.push("--no-build".into());

        run(&host_args).unwrap();
        let generated = fs::read_to_string(&keep).unwrap();
        assert!(generated.starts_with("(import Vec)\n(pub :: answer Int)"));

        fs::remove_file(&rust).unwrap();
        fs::create_dir(&rust).unwrap();
        assert!(run(&host_args).is_err());
        assert_eq!(fs::read_to_string(&keep).unwrap(), generated);
    }

    #[test]
    fn automatic_sources_are_private_and_do_not_collide() {
        let dir = TestDir::new("concurrent");
        let workers = (0..8)
            .map(|index| {
                let parent = dir.path().to_path_buf();
                std::thread::spawn(move || {
                    GeneratedSource::automatic_in(&parent, &format!("source {index}")).unwrap()
                })
            })
            .collect::<Vec<_>>();
        let sources = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect::<Vec<_>>();

        let mut paths = HashSet::new();
        let mut contents = HashSet::new();
        for source in &sources {
            assert!(paths.insert(source.path()));
            contents.insert(fs::read_to_string(source.path()).unwrap());
            let temporary = source.temporary_directory.as_ref().unwrap();
            assert!(source.path().starts_with(temporary));
            assert_eq!(temporary.parent(), Some(dir.path()));
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mode = fs::metadata(temporary).unwrap().permissions().mode();
                assert_eq!(mode & 0o077, 0, "temporary directory is not private");
            }
        }
        assert_eq!(contents.len(), sources.len());

        drop(sources);
        assert_no_automatic_artifacts(dir.path());
    }

    #[test]
    fn automatic_source_is_cleaned_up_after_errors() {
        let dir = TestDir::new("errors");
        let input = write_input(dir.path());
        let rust = dir.path().join("binding.rs");
        let archive = dir.path().join("library.a");
        fs::create_dir(&rust).unwrap();
        let host_args = args(&input, &rust, &archive);

        assert!(run(&host_args).is_err());
        assert_no_automatic_artifacts(dir.path());

        fs::remove_dir(&rust).unwrap();
        let mut host_args = args(&input, &rust, &archive);
        host_args.extend([
            "--axiom".into(),
            dir.path()
                .join("missing-compiler")
                .to_string_lossy()
                .into_owned(),
        ]);
        assert!(run(&host_args).is_err());
        assert_no_automatic_artifacts(dir.path());
    }
}
