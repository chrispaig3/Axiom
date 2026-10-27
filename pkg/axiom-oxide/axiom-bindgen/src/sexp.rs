//! A tiny Axiom expression tree and a printer that writes it exactly as
//! `axiom fmt` would, so a generated module is formatter-clean without
//! shelling out to the formatter.
//!
//! Applications fit on one line within 100 columns. Longer calls pack
//! complete arguments into rows; multiline arguments retain their own
//! layout. Bindings, branches and matches keep their structural layout.
//! Explicit conversions print as `(as value Type)`.
//!
//! `scripts/check-fmt.sh` checks generated bindings against the Axiom
//! formatter, while `scripts/check-ffi.sh` checks fresh generation.

/// An Axiom expression.
#[derive(Clone, Debug)]
pub enum Ex {
    /// A leaf, pushed to the output as the string stands: a name, a
    /// literal, an operator. It is the only form that is
    /// unconditionally simple, so an atom is never broken or wrapped
    /// and its string must already be one token.
    Atom(String),
    /// `(head args...)`.
    App(Vec<Ex>),
    /// `(as e Type)`.
    Cast(String, Box<Ex>),
    /// A lexical brace block with sequential `(let name init)` declarations.
    Let(Vec<(String, Ex)>, Box<Ex>),
    /// `(if cond then else)`. Never simple, so it always breaks: the
    /// condition stays on the `if` line and each branch takes its own
    /// (`fpIf`).
    If(Box<Ex>, Box<Ex>, Box<Ex>),
    /// `(match scrutinee (pattern body)...)`; a pattern is an `App`.
    Match(Box<Ex>, Vec<(Ex, Ex)>),
    /// `{ statements... }` with at least two statements.
    Block(Vec<Ex>),
}

/// An [`Ex::Atom`] over a borrowed name. The tree owns its strings,
/// so this is the one place the copy is made.
pub fn atom(s: &str) -> Ex {
    Ex::Atom(s.to_string())
}

/// `(head args...)`. A head with no arguments is the bare head: the
/// formatter unwraps `(x)` to `x`, and a nullary extern is called by
/// naming it.
pub fn app(mut elems: Vec<Ex>) -> Ex {
    if elems.len() == 1 {
        elems.pop().unwrap()
    } else {
        Ex::App(elems)
    }
}

impl Ex {
    /// `isSimpleForm`.
    pub fn is_simple(&self) -> bool {
        match self {
            Ex::Atom(_) => true,
            Ex::App(elems) => elems.iter().all(Ex::is_simple),
            Ex::Block(stmts) => stmts.len() == 1 && stmts[0].is_simple(),
            Ex::Cast(..) | Ex::Let(..) | Ex::If(..) | Ex::Match(..) => false,
        }
    }
}

/// `col` spaces: the indent is a column, as `foIndent` is.
fn ind(col: usize) -> String {
    " ".repeat(col)
}

/// The widest line a form is laid out on: `fmtWidth` in
/// `core/format.ax`.
const WIDTH: usize = 100;

/// The column the next byte of `out` lands at.
fn column(out: &str) -> usize {
    match out.rfind('\n') {
        Some(i) => out.len() - i - 1,
        None => out.len(),
    }
}

/// `elems` as one application on one line, printed into a fresh buffer
/// the way `fpAppFlat` prints its trial, or `None` when an element
/// breaks across lines.
fn app_flat(elems: &[Ex]) -> Option<String> {
    let mut s = String::from("(");
    for (i, e) in elems.iter().enumerate() {
        if i > 0 {
            s.push(' ');
        }
        if !print_flat(e, &mut s) {
            return None;
        }
    }
    s.push(')');
    (s.len() <= WIDTH).then_some(s)
}

// A width trial visits a node once and stops as soon as it cannot fit.
// Calling the ordinary printer here would recursively start more trials.
fn print_flat(e: &Ex, out: &mut String) -> bool {
    if out.len() > WIDTH {
        return false;
    }
    match e {
        Ex::Atom(s) => out.push_str(s),
        Ex::Cast(ty, inner) => {
            out.push_str("(as ");
            if !print_flat(inner, out) {
                return false;
            }
            out.push(' ');
            out.push_str(ty);
            out.push(')');
        }
        Ex::App(elems) => {
            out.push('(');
            for (i, arg) in elems.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                if !print_flat(arg, out) {
                    return false;
                }
            }
            out.push(')');
        }
        _ => return false,
    }
    out.len() <= WIDTH
}

/// Print `e` at `level`, assuming the cursor already sits at the
/// column where the expression starts.
pub fn print(e: &Ex, level: usize, out: &mut String) {
    print_shape(e, level, 0, out);
}

// Reserve the structural suffix appended to the final line. Non-final
// children end their own shape; final children inherit their parent's suffix.
fn print_shape(e: &Ex, level: usize, suffix: usize, out: &mut String) {
    match e {
        Ex::Atom(s) => out.push_str(s),
        Ex::Cast(ty, inner) => {
            out.push_str("(as ");
            print_shape(inner, level, suffix + ty.len() + 2, out);
            out.push(' ');
            out.push_str(ty);
            out.push(')');
        }
        Ex::App(elems) => {
            if let Some(flat) = app_flat(elems)
                && column(out) + flat.len() + suffix <= WIDTH
            {
                out.push_str(&flat);
                return;
            }
            let col = column(out);
            out.push('(');
            let head_start = out.len();
            print_shape(&elems[0], level, 0, out);
            let mut previous_broken = out[head_start..].contains('\n');
            for (index, arg) in elems[1..].iter().enumerate() {
                let tail = if index + 2 == elems.len() { suffix } else { 0 };
                let mut flat = String::new();
                if print_flat(arg, &mut flat) && col + 2 + flat.len() + 1 + tail <= WIDTH {
                    if previous_broken || column(out) + flat.len() + 2 + tail > WIDTH {
                        out.push('\n');
                        out.push_str(&ind(col + 2));
                    } else {
                        out.push(' ');
                    }
                    out.push_str(&flat);
                    previous_broken = false;
                } else {
                    out.push('\n');
                    out.push_str(&ind(col + 2));
                    print_shape(
                        arg,
                        col + 2,
                        if index + 2 == elems.len() {
                            suffix + 1
                        } else {
                            0
                        },
                        out,
                    );
                    previous_broken = true;
                }
            }
            out.push(')');
        }
        Ex::Let(binds, body) => {
            out.push_str("{\n");
            for (name, init) in binds {
                out.push_str(&ind(level + 2));
                out.push_str("(let ");
                out.push_str(name);
                let mut flat = String::new();
                if print_flat(init, &mut flat) && column(out) + flat.len() + 2 <= WIDTH {
                    out.push(' ');
                    out.push_str(&flat);
                } else {
                    out.push('\n');
                    out.push_str(&ind(level + 4));
                    print_shape(init, level + 4, 1, out);
                }
                out.push_str(")\n");
            }
            out.push_str(&ind(level + 2));
            print_shape(body, level + 2, 0, out);
            out.push('\n');
            out.push_str(&ind(level));
            out.push('}');
        }
        Ex::If(c, t, f) => {
            out.push_str("(if ");
            print_shape(c, level, 0, out);
            out.push('\n');
            out.push_str(&ind(level + 2));
            print_shape(t, level + 2, 0, out);
            out.push('\n');
            out.push_str(&ind(level + 2));
            print_shape(f, level + 2, suffix + 1, out);
            out.push(')');
        }
        Ex::Match(scrut, arms) => {
            out.push_str("(match ");
            print_shape(scrut, level, 0, out);
            out.push('\n');
            for (i, (pat, body)) in arms.iter().enumerate() {
                if i > 0 {
                    out.push('\n');
                }
                out.push_str(&ind(level + 2));
                out.push('(');
                print_shape(pat, level + 2, 0, out);
                tail_body(
                    body,
                    level + 2,
                    if i + 1 == arms.len() { suffix + 1 } else { 0 },
                    out,
                );
                out.push(')');
            }
            out.push(')');
        }
        Ex::Block(stmts) => {
            out.push_str("{\n");
            for (i, s) in stmts.iter().enumerate() {
                if i > 0 {
                    out.push('\n');
                }
                out.push_str(&ind(level + 2));
                print(s, level + 2, out);
            }
            out.push('\n');
            out.push_str(&ind(level));
            out.push('}');
        }
    }
}

/// `fpTailBody`: a space and the body inline when simple, else the body
/// alone on the next line with the closing paren's indent restored.
fn tail_body(body: &Ex, level: usize, suffix: usize, out: &mut String) {
    if body.is_simple() {
        out.push(' ');
        print_shape(body, level, suffix + 1, out);
    } else {
        out.push('\n');
        out.push_str(&ind(level + 2));
        print(body, level + 2, out);
        out.push('\n');
        out.push_str(&ind(level));
    }
}

/// A type after a declaration prefix, moving to a fresh line when needed.
fn type_after(ty: &Ex, level: usize, suffix: usize, out: &mut String) {
    let mut flat = String::new();
    if print_flat(ty, &mut flat) && column(out) + 1 + flat.len() + suffix <= WIDTH {
        out.push(' ');
        out.push_str(&flat);
    } else {
        out.push('\n');
        out.push_str(&ind(level + 2));
        print_shape(ty, level + 2, suffix, out);
    }
}

/// A typed function signature, using the canonical declaration layout.
pub fn decl_sig(public: bool, name: &str, ty: &Ex) -> String {
    let mut out = String::from(if public { "(pub :: " } else { "(:: " });
    out.push_str(name);
    type_after(ty, 0, 1, &mut out);
    out.push(')');
    out
}

/// A positional record declaration with a bounded constructor type list.
pub fn decl_data(name: &str, fields: Vec<Ex>) -> String {
    let mut out = format!("(pub data {name}\n  ");
    let mut constructor = vec![atom(name)];
    constructor.extend(fields);
    print_shape(&Ex::App(constructor), 2, 1, &mut out);
    out.push(')');
    out
}

/// A raw extern block. A broken item keeps its symbol on its own line.
pub fn decl_extern(lib: &str, items: &[(String, Ex, String)]) -> String {
    let mut out = format!("(pub extern \"{lib}\"");
    for (i, (name, ty, symbol)) in items.iter().enumerate() {
        out.push_str(&format!("\n  ({name} ::"));
        let suffix = if i + 1 == items.len() { 2 } else { 1 };
        let clause = app(vec![atom("symbol"), atom(&format!("\"{symbol}\""))]);
        let mut flat = String::new();
        let type_fits = print_flat(ty, &mut flat);
        flat.push(' ');
        let tail_fits = print_flat(&clause, &mut flat);
        if type_fits && tail_fits && column(&out) + 1 + flat.len() + suffix <= WIDTH {
            out.push(' ');
            out.push_str(&flat);
        } else {
            type_after(ty, 2, 0, &mut out);
            out.push_str("\n    ");
            print_shape(&clause, 4, suffix, &mut out);
        }
        out.push(')');
    }
    out.push(')');
    out
}

/// `(pub fn (name params...) body)` as the formatter lays it out.
pub fn decl_fn(name: &str, params: &[String], body: &Ex) -> String {
    decl_fn_vis(true, name, params, body)
}

/// `(fn (name params...) body)`: a module-private function, laid out
/// the same way.
pub fn decl_private_fn(name: &str, params: &[String], body: &Ex) -> String {
    decl_fn_vis(false, name, params, body)
}

fn decl_fn_vis(public: bool, name: &str, params: &[String], body: &Ex) -> String {
    let mut out = String::new();
    out.push_str(if public { "(pub fn " } else { "(fn " });
    let mut header = vec![atom(name)];
    header.extend(params.iter().map(|parameter| atom(parameter)));
    // A header is a complete pattern list, including the nullary case.
    print_shape(&Ex::App(header), 0, 0, &mut out);
    out.push_str("\n  ");
    print_shape(body, 2, 1, &mut out);
    out.push(')');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nested_width_trials_finish() {
        let mut e = atom("0");
        for _ in 0..96 {
            e = app(vec![atom("f"), e]);
        }
        let mut out = String::new();
        print(&e, 0, &mut out);
        assert_eq!(out.matches('(').count(), 96);
        assert_eq!(out.matches(')').count(), 96);
        assert!(out.contains('0'));
    }

    #[test]
    fn inline_and_broken_applications() {
        let mut s = String::new();
        print(&app(vec![atom("f"), atom("a"), atom("b")]), 0, &mut s);
        assert_eq!(s, "(f a b)");
        let mut s = String::new();
        print(
            &app(vec![
                atom("f"),
                atom("a"),
                atom("b"),
                atom("c"),
                atom("d"),
                atom("e"),
            ]),
            2,
            &mut s,
        );
        assert_eq!(s, "(f a b c d e)");
        // Long calls wrap complete arguments into bounded rows.
        let long: Vec<Ex> = std::iter::once(atom("f"))
            .chain((0..12).map(|i| atom(&format!("argument{i}"))))
            .collect();
        let mut s = String::new();
        print(&app(long), 2, &mut s);
        assert_eq!(s, "(f argument0 argument1 argument2 argument3 argument4 argument5 argument6 argument7 argument8\n  argument9 argument10 argument11)");
        assert!(s.lines().all(|line| line.len() <= WIDTH));
    }

    #[test]
    fn enclosing_closers_fit_within_width() {
        let body = app(vec![
            atom("call"),
            app(vec![
                atom("call"),
                app(vec![
                    atom("call"),
                    app(vec![atom("call"), atom("argument17"), atom("argument31")]),
                    app(vec![
                        atom("call"),
                        atom("argument56"),
                        atom("argument6"),
                        atom("argument75"),
                    ]),
                    app(vec![atom("call"), atom("argument65"), atom("argument92")]),
                    app(vec![
                        atom("call"),
                        atom("argument86"),
                        atom("argument99"),
                        atom("argument31"),
                        atom("argument42"),
                        atom("argument48"),
                    ]),
                ]),
            ]),
        ]);
        let output = decl_private_fn("main", &[], &body);
        assert!(output.lines().all(|line| line.len() <= WIDTH), "{}", output);
    }

    #[test]
    fn conversion_is_value_first() {
        let mut output = String::new();
        print(
            &Ex::Cast("Foreign".into(), Box::new(atom("value"))),
            0,
            &mut output,
        );
        assert_eq!(output, "(as value Foreign)");
    }

    #[test]
    fn let_forms() {
        let mut s = String::new();
        print(
            &Ex::Let(vec![("x".into(), atom("1"))], Box::new(atom("x"))),
            0,
            &mut s,
        );
        assert_eq!(s, "{\n  (let x 1)\n  x\n}");
        let mut s = String::new();
        print(
            &Ex::Let(
                vec![("x".into(), atom("1")), ("y".into(), atom("2"))],
                Box::new(atom("x")),
            ),
            2,
            &mut s,
        );
        assert_eq!(s, "{\n    (let x 1)\n    (let y 2)\n    x\n  }");
    }

    #[test]
    fn long_parameter_headers_wrap() {
        let parameters = [
            "requestIdentifier",
            "responseIdentifier",
            "retryLimit",
            "timeoutMilliseconds",
            "bufferCapacity",
            "workerCount",
            "queueCapacity",
            "maximumPayloadBytes",
            "statusCode",
        ]
        .map(str::to_string);
        let output = decl_fn("requestStatus", &parameters, &atom("statusCode"));
        assert!(output.lines().all(|line| line.len() <= WIDTH), "{}", output);
        assert!(output.lines().count() > 2, "{}", output);
        for parameter in parameters {
            assert_eq!(
                output.matches(&parameter).count(),
                if parameter == "statusCode" { 2 } else { 1 }
            );
        }
    }

    #[test]
    fn fn_decl() {
        let body = Ex::Match(
            Box::new(atom("c")),
            vec![(
                app(vec![atom("Counter"), atom("__h")]),
                app(vec![atom("ffiHandleClose"), atom("__h")]),
            )],
        );
        assert_eq!(
            decl_fn("counterClose", &["c".into()], &body),
            "(pub fn (counterClose c)\n  (match c\n    ((Counter __h) (ffiHandleClose __h))))"
        );
    }
}
