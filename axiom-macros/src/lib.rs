use axiom_ast::ast::*;
use std::collections::HashMap;

pub struct MacroExpander {
    macros: HashMap<String, MacroDef>,
}

impl MacroExpander {
    pub fn new() -> Self {
        Self {
            macros: HashMap::new(),
        }
    }

    pub fn register_macros(&mut self, decls: &[Decl]) {
        for decl in decls {
            if let Decl::DMacro { name, def } = decl {
                self.macros.insert(name.name.clone(), def.clone());
            }
        }
    }

    pub fn expand_expr(&self, expr: &Expr) -> Expr {
        match expr {
            Expr::EBacktick(sub) => self.expand_quasiquote(sub, 1),
            Expr::EUnquote(sub) => self.expand_expr(sub),
            Expr::EUnquoteSplicing(sub) => Expr::EError(
                "unquote-splicing not allowed at top level".to_string(),
                sub.span(),
            ),
            Expr::EApp(func, arg) => Expr::EApp(
                Box::new(self.expand_expr(func)),
                Box::new(self.expand_expr(arg)),
            ),
            Expr::ELam(params, body) => Expr::ELam(
                params.clone(),
                Box::new(self.expand_expr(body)),
            ),
            Expr::ELet(bindings, body) => Expr::ELet(
                bindings
                    .iter()
                    .map(|(pat, e)| (pat.clone(), self.expand_expr(e)))
                    .collect(),
                Box::new(self.expand_expr(body)),
            ),
            Expr::EIf(cond, then_br, else_br) => Expr::EIf(
                Box::new(self.expand_expr(cond)),
                Box::new(self.expand_expr(then_br)),
                Box::new(self.expand_expr(else_br)),
            ),
            Expr::EMatch(target, arms) => Expr::EMatch(
                Box::new(self.expand_expr(target)),
                arms.iter()
                    .map(|(pat, body)| (pat.clone(), self.expand_expr(body)))
                    .collect(),
            ),
            Expr::ECond(branches, else_) => Expr::ECond(
                branches
                    .iter()
                    .map(|(c, t)| (self.expand_expr(c), self.expand_expr(t)))
                    .collect(),
                else_.as_ref().map(|e| Box::new(self.expand_expr(e))),
            ),
            Expr::EHandle(body, effects, handler) => Expr::EHandle(
                Box::new(self.expand_expr(body)),
                effects.clone(),
                Box::new(self.expand_expr(handler)),
            ),
            Expr::ERegion(name, body) => {
                Expr::ERegion(name.clone(), Box::new(self.expand_expr(body)))
            }
            Expr::EConsume(expr) => Expr::EConsume(Box::new(self.expand_expr(expr))),
            Expr::EField(base, field) => {
                Expr::EField(Box::new(self.expand_expr(base)), field.clone())
            }
            Expr::ESetField(base, field, value) => Expr::ESetField(
                Box::new(self.expand_expr(base)),
                field.clone(),
                Box::new(self.expand_expr(value)),
            ),
            Expr::EStructCon(name, args) => Expr::EStructCon(
                name.clone(),
                args.iter().map(|e| self.expand_expr(e)).collect(),
            ),
            Expr::ETypeSig(expr, ty) => {
                Expr::ETypeSig(Box::new(self.expand_expr(expr)), ty.clone())
            }
            Expr::ECast(expr, ty) => {
                Expr::ECast(Box::new(self.expand_expr(expr)), ty.clone())
            }
            Expr::EAlloc(ty, count, span) => Expr::EAlloc(
                ty.clone(),
                count.as_ref().map(|e| Box::new(self.expand_expr(e))),
                *span,
            ),
            Expr::ESizeof(ty, span) => Expr::ESizeof(ty.clone(), *span),
            Expr::EAlignof(ty, span) => Expr::EAlignof(ty.clone(), *span),
            Expr::EGrouped(expr) => {
                Expr::EGrouped(Box::new(self.expand_expr(expr)))
            }
            Expr::EBegin(exprs) => Expr::EBegin(
                exprs.iter().map(|e| self.expand_expr(e)).collect(),
            ),
            Expr::ETuple(exprs) => Expr::ETuple(
                exprs.iter().map(|e| self.expand_expr(e)).collect(),
            ),
            Expr::EList(exprs) => Expr::EList(
                exprs.iter().map(|e| self.expand_expr(e)).collect(),
            ),
            Expr::EInfix(left, op, right) => Expr::EInfix(
                Box::new(self.expand_expr(left)),
                op.clone(),
                Box::new(self.expand_expr(right)),
            ),
            Expr::ELit(lit, span) => Expr::ELit(lit.clone(), *span),
            Expr::EVar(ident) => {
                if let Some(macro_def) = self.macros.get(&ident.name) {
                    self.expand_macro_call(macro_def)
                } else {
                    expr.clone()
                }
            }
            Expr::EError(msg, span) => Expr::EError(msg.clone(), *span),
        }
    }

    fn expand_quasiquote(&self, expr: &Expr, level: i32) -> Expr {
        if level == 0 {
            return match expr {
                Expr::EUnquote(sub) => self.expand_expr(sub),
                Expr::EUnquoteSplicing(sub) => Expr::EError(
                    "unquote-splicing cannot be evaluated directly".to_string(),
                    sub.span(),
                ),
                _ => self.expand_expr(expr),
            };
        }

        match expr {
            Expr::EBacktick(sub) => Expr::EBacktick(Box::new(self.expand_quasiquote(
                sub,
                level + 1,
            ))),
            Expr::EUnquote(sub) => Expr::EUnquote(Box::new(self.expand_quasiquote(
                sub,
                level - 1,
            ))),
            Expr::EUnquoteSplicing(sub) => Expr::EUnquoteSplicing(Box::new(
                self.expand_quasiquote(sub, level - 1),
            )),
            Expr::EList(elems) => {
                let expanded: Vec<Expr> = elems
                    .iter()
                    .map(|e| self.expand_quasiquote(e, level))
                    .collect();
                self.process_list(expanded)
            }
            Expr::EApp(func, arg) => Expr::EApp(
                Box::new(self.expand_quasiquote(func, level)),
                Box::new(self.expand_quasiquote(arg, level)),
            ),
            Expr::EBegin(exprs) => Expr::EBegin(
                exprs
                    .iter()
                    .map(|e| self.expand_quasiquote(e, level))
                    .collect(),
            ),
            Expr::ETuple(exprs) => Expr::ETuple(
                exprs
                    .iter()
                    .map(|e| self.expand_quasiquote(e, level))
                    .collect(),
            ),
            Expr::ELam(params, body) => Expr::ELam(
                params.clone(),
                Box::new(self.expand_quasiquote(body, level)),
            ),
            Expr::ELet(bindings, body) => Expr::ELet(
                bindings
                    .iter()
                    .map(|(pat, e)| (pat.clone(), self.expand_quasiquote(e, level)))
                    .collect(),
                Box::new(self.expand_quasiquote(body, level)),
            ),
            Expr::EIf(cond, then_br, else_br) => Expr::EIf(
                Box::new(self.expand_quasiquote(cond, level)),
                Box::new(self.expand_quasiquote(then_br, level)),
                Box::new(self.expand_quasiquote(else_br, level)),
            ),
            Expr::EMatch(target, arms) => Expr::EMatch(
                Box::new(self.expand_quasiquote(target, level)),
                arms.iter()
                    .map(|(pat, body)| {
                        (pat.clone(), self.expand_quasiquote(body, level))
                    })
                    .collect(),
            ),
            Expr::ECond(branches, else_) => Expr::ECond(
                branches
                    .iter()
                    .map(|(c, t)| {
                        (self.expand_quasiquote(c, level), self.expand_quasiquote(t, level))
                    })
                    .collect(),
                else_.as_ref().map(|e| Box::new(self.expand_quasiquote(e, level))),
            ),
            Expr::EHandle(body, effects, handler) => Expr::EHandle(
                Box::new(self.expand_quasiquote(body, level)),
                effects.clone(),
                Box::new(self.expand_quasiquote(handler, level)),
            ),
            Expr::ERegion(name, body) => Expr::ERegion(
                name.clone(),
                Box::new(self.expand_quasiquote(body, level)),
            ),
            Expr::EConsume(expr) => Expr::EConsume(Box::new(self.expand_quasiquote(expr, level))),
            Expr::EField(base, field) => Expr::EField(
                Box::new(self.expand_quasiquote(base, level)),
                field.clone(),
            ),
            Expr::ESetField(base, field, value) => Expr::ESetField(
                Box::new(self.expand_quasiquote(base, level)),
                field.clone(),
                Box::new(self.expand_quasiquote(value, level)),
            ),
            Expr::EStructCon(name, args) => Expr::EStructCon(
                name.clone(),
                args.iter()
                    .map(|e| self.expand_quasiquote(e, level))
                    .collect(),
            ),
            Expr::ETypeSig(expr, ty) => Expr::ETypeSig(
                Box::new(self.expand_quasiquote(expr, level)),
                ty.clone(),
            ),
            Expr::ECast(expr, ty) => Expr::ECast(
                Box::new(self.expand_quasiquote(expr, level)),
                ty.clone(),
            ),
            Expr::EAlloc(ty, count, span) => Expr::EAlloc(
                ty.clone(),
                count.as_ref().map(|e| Box::new(self.expand_quasiquote(e, level))),
                *span,
            ),
            Expr::ESizeof(ty, span) => Expr::ESizeof(ty.clone(), *span),
            Expr::EAlignof(ty, span) => Expr::EAlignof(ty.clone(), *span),
            Expr::EGrouped(expr) => Expr::EGrouped(Box::new(self.expand_quasiquote(
                expr,
                level,
            ))),
            Expr::EVar(ident) => {
                if let Some(macro_def) = self.macros.get(&ident.name) {
                    self.expand_macro_call(macro_def)
                } else {
                    expr.clone()
                }
            }
            other => other.clone(),
        }
    }

    fn process_list(&self, elems: Vec<Expr>) -> Expr {
        if let Some(idx) = elems.iter().position(|e| matches!(e, Expr::EUnquoteSplicing(_))) {
            let spliced = self.expand_expr(
                match &elems[idx] {
                    Expr::EUnquoteSplicing(sub) => sub.as_ref(),
                    _ => unreachable!(),
                },
            );
            let before: Vec<Expr> = elems[..idx].to_vec();
            let rest: Vec<Expr> = elems[idx + 1..].to_vec();
            if before.is_empty() && rest.is_empty() {
                spliced
            } else if before.is_empty() {
                Expr::EList(rest)
            } else if rest.is_empty() {
                Expr::EList(before)
            } else {
                Expr::EList(before)
            }
        } else {
            Expr::EList(elems)
        }
    }

    fn expand_macro_call(&self, macro_def: &MacroDef) -> Expr {
        self.expand_expr(&macro_def.body)
    }
}