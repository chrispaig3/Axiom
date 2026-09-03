//! A tiny Axiom expression tree and a printer that writes it exactly as
//! `axiom fmt` would, so a generated module is formatter-clean without
//! shelling out to the formatter.
//!
//! The formatter (`self_host/format.ax`) has no line-width rule; its
//! layout is STRUCTURAL, and the rules for the forms this generator
//! emits are:
//!
//! - an atom is simple; an application is simple iff every element is
//!   simple; `cast`, `let`, `if`, `match` and a multi-statement `{}`
//!   block are never simple (`isSimpleForm`);
//! - an application prints on one line iff its head is simple, it has
//!   at most four arguments and every argument is simple; otherwise
//!   the head ends the line and the arguments follow at one deeper
//!   indent WITH NO NEWLINE BETWEEN THEM (stage0's quirk, kept for
//!   byte-identity), then `)` on its own line (`fpApp`);
//! - `let` with one binding keeps the binding on the `let` line (the
//!   init breaks onto its own line if it is not simple); with several,
//!   each binding sits on its own line under `(let (` and the list
//!   closes with `)` at the `let`'s indent; the body is always on its
//!   own line at one deeper indent, and the `let` closes on its own
//!   line (`fpLet`, `fpLetBinding`, `fpLetBindingBroken`);
//! - `if` puts the condition on the `if` line and each branch on its
//!   own line, `)` alone (`fpIf`);
//! - `match` puts every arm on its own line; an arm's body sits beside
//!   the pattern if simple, else below it (`fpMatch`, `fpTailBody`);
//! - a block prints `{`, one statement per line, `}` (`fpBeginVec`);
//! - a `fn` body sits beside the head if simple, else below it, and
//!   the `fn` closes on its own line (`fpDeclFn`).
//!
//! Indent is two spaces per level.

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
    /// `(cast Type e)`.
    Cast(String, Box<Ex>),
    /// `(let (bindings...) body)`; bindings are `(name init)`.
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

fn ind(level: usize) -> String {
    "  ".repeat(level)
}

/// Print `e` at `level`, assuming the cursor already sits at the
/// column where the expression starts.
pub fn print(e: &Ex, level: usize, out: &mut String) {
    match e {
        Ex::Atom(s) => out.push_str(s),
        Ex::Cast(ty, inner) => {
            out.push_str("(cast ");
            out.push_str(ty);
            out.push(' ');
            print(inner, level, out);
            out.push(')');
        }
        Ex::App(elems) => {
            let head = &elems[0];
            let args = &elems[1..];
            let inline = head.is_simple() && args.len() <= 4 && args.iter().all(Ex::is_simple);
            out.push('(');
            print(head, level, out);
            if inline {
                for a in args {
                    out.push(' ');
                    print(a, level, out);
                }
                out.push(')');
            } else {
                out.push('\n');
                for a in args {
                    out.push_str(&ind(level + 1));
                    print(a, level + 1, out);
                }
                out.push('\n');
                out.push_str(&ind(level));
                out.push(')');
            }
        }
        Ex::Let(binds, body) => {
            out.push_str("(let (");
            if binds.len() == 1 {
                let (name, init) = &binds[0];
                out.push('(');
                out.push_str(name);
                out.push(' ');
                if init.is_simple() {
                    print(init, level, out);
                } else {
                    out.push('\n');
                    out.push_str(&ind(level + 1));
                    print(init, level + 1, out);
                    out.push('\n');
                    out.push_str(&ind(level));
                }
                out.push(')');
            } else {
                out.push('\n');
                for (name, init) in binds {
                    out.push_str(&ind(level + 1));
                    out.push('(');
                    out.push_str(name);
                    out.push(' ');
                    print(init, level + 1, out);
                    out.push_str(")\n");
                }
                out.push_str(&ind(level));
            }
            out.push_str(")\n");
            out.push_str(&ind(level + 1));
            print(body, level + 1, out);
            out.push('\n');
            out.push_str(&ind(level));
            out.push(')');
        }
        Ex::If(c, t, f) => {
            out.push_str("(if ");
            print(c, level, out);
            out.push('\n');
            out.push_str(&ind(level + 1));
            print(t, level + 1, out);
            out.push('\n');
            out.push_str(&ind(level + 1));
            print(f, level + 1, out);
            out.push('\n');
            out.push_str(&ind(level));
            out.push(')');
        }
        Ex::Match(scrut, arms) => {
            out.push_str("(match ");
            print(scrut, level, out);
            out.push('\n');
            for (pat, body) in arms {
                out.push_str(&ind(level + 1));
                out.push('(');
                print(pat, level + 1, out);
                tail_body(body, level + 1, out);
                out.push_str(")\n");
            }
            out.push_str(&ind(level));
            out.push(')');
        }
        Ex::Block(stmts) => {
            out.push_str("{\n");
            for (i, s) in stmts.iter().enumerate() {
                if i > 0 {
                    out.push('\n');
                }
                out.push_str(&ind(level + 1));
                print(s, level + 1, out);
            }
            out.push('\n');
            out.push_str(&ind(level));
            out.push('}');
        }
    }
}

/// `fpTailBody`: a space and the body inline when simple, else the body
/// alone on the next line with the closing paren's indent restored.
fn tail_body(body: &Ex, level: usize, out: &mut String) {
    if body.is_simple() {
        out.push(' ');
        print(body, level, out);
    } else {
        out.push('\n');
        out.push_str(&ind(level + 1));
        print(body, level + 1, out);
        out.push('\n');
        out.push_str(&ind(level));
    }
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
    out.push_str(if public { "(pub fn (" } else { "(fn (" });
    out.push_str(name);
    for p in params {
        out.push(' ');
        out.push_str(p);
    }
    out.push(')');
    tail_body(body, 0, &mut out);
    out.push(')');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

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
            1,
            &mut s,
        );
        assert_eq!(s, "(f\n    a    b    c    d    e\n  )");
    }

    #[test]
    fn let_forms() {
        let mut s = String::new();
        print(
            &Ex::Let(vec![("x".into(), atom("1"))], Box::new(atom("x"))),
            0,
            &mut s,
        );
        assert_eq!(s, "(let ((x 1))\n  x\n)");
        let mut s = String::new();
        print(
            &Ex::Let(
                vec![("x".into(), atom("1")), ("y".into(), atom("2"))],
                Box::new(atom("x")),
            ),
            1,
            &mut s,
        );
        assert_eq!(s, "(let (\n    (x 1)\n    (y 2)\n  )\n    x\n  )");
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
            "(pub fn (counterClose c)\n  (match c\n    ((Counter __h) (ffiHandleClose __h))\n  )\n)"
        );
    }
}
