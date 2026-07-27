use axiom_ast::ast::*;
use axiom_ast::span::{Ident, Span};
use axiom_ast::token::{Token, TokenKind};
use axiom_errors::{code, Diagnostic};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("expected {expected}, found `{found}`")]
    UnexpectedToken {
        expected: String,
        found: String,
        span: Span,
    },
    /// `span` points at the last token before end-of-file, so the report
    /// still lands on real source text instead of nowhere (previously this
    /// variant carried no span at all and rendered as a zero-width
    /// `Span::dummy()` at byte 0).
    #[error("unexpected end of file")]
    UnexpectedEof { span: Span },
    #[error("{message}")]
    Message { message: String, span: Span },
}

impl ParseError {
    pub fn span(&self) -> Span {
        match self {
            ParseError::UnexpectedToken { span, .. } => *span,
            ParseError::UnexpectedEof { span } => *span,
            ParseError::Message { span, .. } => *span,
        }
    }

    /// Convert into a renderer-agnostic [`Diagnostic`].
    pub fn to_diagnostic(&self) -> Diagnostic {
        let span = self.span();
        match self {
            ParseError::UnexpectedToken {
                expected, found, ..
            } => Diagnostic::error(&code::UNEXPECTED_TOKEN, self.to_string())
                .with_primary(span, format!("found `{}` here", found))
                .with_help(format!("Axiom expected {} at this position", expected)),
            ParseError::UnexpectedEof { .. } => Diagnostic::error(
                &code::UNEXPECTED_EOF,
                self.to_string(),
            )
            .with_primary(span, "file ends here while a form is still open")
            .with_help(
                "count `(`/`[`/`{` against `)`/`]`/`}` working backward from the end of the file",
            ),
            ParseError::Message { message, .. } => {
                Diagnostic::error(&code::PARSE_MESSAGE, message.clone())
                    .with_primary(span, message.clone())
            }
        }
    }
}

type ParseResult<T> = Result<T, ParseError>;

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self { tokens, pos: 0 }
    }

    /// Collect any AXTAG tokens (`TokenKind::Axtag`) that immediately
    /// precede the current position in the token stream.  AXTAGs must
    /// appear directly above a declaration with no intervening
    /// non-AXTAG tokens or blank lines.  Collection stops at the first
    /// non-AXTAG token.
    fn collect_axtags(&mut self) -> Vec<Token> {
        let mut axtags = Vec::new();
        while let Some(token) = self.tokens.get(self.pos) {
            match &token.kind {
                TokenKind::Axtag(_) => {
                    axtags.push(token.clone());
                    self.pos += 1;
                }
                TokenKind::Eof => break,
                _ => break,
            }
        }
        axtags
    }

    /// Generate a stable content-derived node ID for a declaration.
    /// The ID is a short hex hash of the declaration's kind and
    /// name, making it stable across formatting-only edits but
    /// sensitive to renames.
    fn generate_nid(decl: &Decl) -> String {
        let mut s = String::new();
        decl.nid_key(&mut s);
        let mut hasher = DefaultHasher::new();
        s.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    }

    /// Parse raw AXTAG tokens into structured [`Axtag`] values.
    fn parse_axtag_tokens(tokens: &[Token]) -> Vec<Axtag> {
        tokens
            .iter()
            .filter_map(|t| {
                if let TokenKind::Axtag(content) = &t.kind {
                    let (key, value) = if let Some(parens_start) = content.find('(') {
                        let key = content[..parens_start].to_string();
                        let close = content.rfind(')').unwrap_or(content.len());
                        let val = content[parens_start + 1..close].to_string();
                        (key, Some(val))
                    } else {
                        (content.to_string(), None)
                    };
                    Some(Axtag { key, value })
                } else {
                    None
                }
            })
            .collect()
    }

    /// Attach a content-derived NID and parsed AXTAGs to a mutable
    /// declaration reference.  The caller is responsible for not
    /// calling this on `DImport` declarations.
    fn attach_nid_and_axtags(decl: &mut Decl, nid: String, axtags: Vec<Axtag>) {
        match decl {
            Decl::DStruct {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DUnion {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DType {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DTrait {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DImpl {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DSig {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DFn {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DForeign {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DEffect {
                nid: n, axtags: a, ..
            } => {
                *n = Some(nid);
                *a = axtags;
            }
            Decl::DImport { .. } => {}
        }
    }

    pub fn parse_module(&mut self) -> ParseResult<Module> {
        let start = self.current_span();
        let mut imports = Vec::new();
        let mut decls = Vec::new();

        while !self.at_eof() {
            if self.check(TokenKind::LParen) {
                let saved_pos = self.pos;
                self.advance();
                if self.check(TokenKind::RParen) {
                    self.advance();
                    continue;
                }
                self.pos = saved_pos;
            }
            let decl = self.parse_decl()?;
            if matches!(decl, Decl::DImport { .. }) {
                imports.push(decl);
            } else {
                decls.push(decl);
            }
        }

        Ok(Module {
            imports,
            decls,
            span: start,
        })
    }

    pub fn parse_decl(&mut self) -> ParseResult<Decl> {
        let axtags = self.collect_axtags();

        self.expect(TokenKind::LParen)?;

        let mut decl = if self.check(TokenKind::Define) || self.check(TokenKind::Fn) {
            self.parse_define()?
        } else if self.check(TokenKind::Struct) {
            self.parse_struct()?
        } else if self.check(TokenKind::Union) {
            self.parse_union()?
        } else if self.check(TokenKind::Type) {
            self.parse_type_alias()?
        } else if self.check(TokenKind::Newtype) {
            self.parse_newtype()?
        } else if self.check(TokenKind::Trait) {
            self.parse_trait()?
        } else if self.check(TokenKind::Impl) {
            self.parse_impl()?
        } else if self.check(TokenKind::Import) {
            self.parse_import()?
        } else if self.check(TokenKind::Foreign) {
            self.parse_foreign()?
        } else if self.check(TokenKind::Effect) {
            self.parse_effect()?
        } else if self.check(TokenKind::Pub) {
            self.advance();
            let inner = self.parse_decl()?;
            self.expect(TokenKind::RParen)?;
            return Ok(inner);
        } else if self.check(TokenKind::DoubleColon) {
            self.parse_sig()?
        } else {
            return Err(ParseError::UnexpectedToken {
                expected: "declaration keyword".to_string(),
                found: self.current_kind_str(),
                span: self.current_span(),
            });
        };

        self.expect(TokenKind::RParen)?;

        // Imports don't get NIDs or AXTAGS.
        if !matches!(decl, Decl::DImport { .. }) {
            let nid = Self::generate_nid(&decl);
            let parsed_axtags = Self::parse_axtag_tokens(&axtags);
            Self::attach_nid_and_axtags(&mut decl, nid, parsed_axtags);
        }

        Ok(decl)
    }

    fn parse_define(&mut self) -> ParseResult<Decl> {
        self.eat(TokenKind::Define);
        self.eat(TokenKind::Fn);

        if self.check(TokenKind::LParen) {
            self.advance();
            let name = self.parse_ident()?;
            let mut params = Vec::new();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                params.push(self.parse_pattern()?);
            }
            self.expect(TokenKind::RParen)?;
            let body = self.parse_body_exprs()?;
            Ok(Decl::DFn {
                name,
                params,
                body,
                nid: None,
                axtags: Vec::new(),
            })
        } else {
            let name = self.parse_ident()?;
            self.eat(TokenKind::Eq);
            let body = self.parse_body_exprs()?;
            Ok(Decl::DFn {
                name,
                params: vec![],
                body,
                nid: None,
                axtags: Vec::new(),
            })
        }
    }

    fn parse_sig(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::DoubleColon)?;
        let name = self.parse_ident()?;
        let ty = self.parse_type()?;
        Ok(Decl::DSig {
            name,
            ty,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_struct(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Struct)?;
        let name = self.parse_ident()?;
        let tyvars = self.parse_tyvars();

        let mut repr = None;
        if self.check(TokenKind::Packed)
            || self.check(TokenKind::Repr)
            || self.check(TokenKind::Align)
        {
            if self.eat(TokenKind::Packed) {
                repr = Some(TypeRepr::Packed);
            } else if self.eat(TokenKind::Repr) {
                self.expect(TokenKind::LParen)?;
                self.expect(TokenKind::Ident("C".to_string()))?;
                self.expect(TokenKind::RParen)?;
                repr = Some(TypeRepr::C);
            } else if self.eat(TokenKind::Align) {
                self.expect(TokenKind::LParen)?;
                let n = self.parse_int_literal()?;
                self.expect(TokenKind::RParen)?;
                repr = Some(TypeRepr::Align(n as usize));
            }
        }

        // Determine if this is single-variant (fields) or multi-variant (struct/enum-like).
        // Peek at the first LParen group: if it contains a colon at the top level,
        // it's a field definition (single-variant); otherwise it's a variant definition.
        let mut variants = Vec::new();
        if self.check(TokenKind::LParen) {
            let saved_pos = self.pos;
            self.advance(); // consume LParen
            let is_field = if !self.check(TokenKind::RParen) {
                // Check if first token is an ident followed by a colon
                if matches!(
                    self.tokens.get(self.pos).map(|t| &t.kind),
                    Some(TokenKind::Ident(_))
                ) {
                    self.advance(); // consume ident
                    self.check(TokenKind::Colon)
                } else {
                    false
                }
            } else {
                false
            };
            self.pos = saved_pos; // backtrack

            if is_field {
                // Single-variant struct: all groups are (name : type) fields
                let mut fields = Vec::new();
                while self.check(TokenKind::LParen) {
                    self.advance();
                    let mutable = self.eat(TokenKind::Mut);
                    let field_name = self.parse_ident()?;
                    self.expect(TokenKind::Colon)?;
                    let field_ty = self.parse_type()?;
                    fields.push(Field {
                        name: field_name,
                        ty: field_ty,
                        mutable,
                    });
                    self.expect(TokenKind::RParen)?;
                }
                variants.push(StructVariant {
                    name: name.clone(),
                    fields,
                });
            } else {
                // Multi-variant struct: each group is a variant (VariantName [fields...])
                while self.check(TokenKind::LParen) {
                    self.advance();
                    let variant_name = self.parse_ident()?;
                    let mut fields = Vec::new();
                    while !self.check(TokenKind::RParen) && !self.at_eof() {
                        if self.check(TokenKind::LParen) {
                            // Peek inside to determine if this is a named field
                            // (name : type) or a positional type.
                            let saved_pos = self.pos;
                            self.advance(); // consume LParen
                            let is_named_field = if !self.check(TokenKind::RParen)
                                && matches!(
                                    self.tokens.get(self.pos).map(|t| &t.kind),
                                    Some(TokenKind::Ident(_))
                                ) {
                                self.advance(); // consume ident
                                self.check(TokenKind::Colon)
                            } else {
                                false
                            };
                            self.pos = saved_pos; // backtrack

                            if is_named_field {
                                self.advance(); // consume LParen
                                let field_name = self.parse_ident()?;
                                self.expect(TokenKind::Colon)?;
                                let field_ty = self.parse_type()?;
                                fields.push(Field {
                                    name: field_name,
                                    ty: field_ty,
                                    mutable: false,
                                });
                                self.expect(TokenKind::RParen)?;
                            } else {
                                // Positional field type
                                let field_ty = self.parse_type()?;
                                fields.push(Field {
                                    name: Ident::new(
                                        &format!("_field_{}", fields.len()),
                                        Span::dummy(),
                                    ),
                                    ty: field_ty,
                                    mutable: false,
                                });
                            }
                        } else {
                            // Positional field type (bare identifier or type)
                            let field_ty = self.parse_type()?;
                            fields.push(Field {
                                name: Ident::new(
                                    &format!("_field_{}", fields.len()),
                                    Span::dummy(),
                                ),
                                ty: field_ty,
                                mutable: false,
                            });
                        }
                    }
                    self.expect(TokenKind::RParen)?;
                    variants.push(StructVariant {
                        name: variant_name,
                        fields,
                    });
                }
            }
        }

        Ok(Decl::DStruct {
            name,
            tyvars,
            variants,
            repr,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_union(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Union)?;
        let name = self.parse_ident()?;
        let tyvars = self.parse_tyvars();

        let mut fields = Vec::new();
        while self.check(TokenKind::LParen) {
            self.advance();
            let mutable = self.eat(TokenKind::Mut);
            let field_name = self.parse_ident()?;
            self.expect(TokenKind::Colon)?;
            let field_ty = self.parse_type()?;
            fields.push(Field {
                name: field_name,
                ty: field_ty,
                mutable,
            });
            self.expect(TokenKind::RParen)?;
        }

        Ok(Decl::DUnion {
            name,
            tyvars,
            fields,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_type_alias(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Type)?;
        let name = self.parse_ident()?;
        let tyvars = self.parse_tyvars();
        self.expect(TokenKind::Eq)?;
        let alias = self.parse_type()?;
        Ok(Decl::DType {
            name,
            tyvars,
            alias,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_newtype(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Newtype)?;
        let name = self.parse_ident()?;
        let tyvars = self.parse_tyvars();
        self.expect(TokenKind::Eq)?;
        let constructor = self.parse_ident()?;
        let inner_type = self.parse_type()?;
        Ok(Decl::DStruct {
            name,
            tyvars,
            variants: vec![StructVariant {
                name: constructor,
                fields: vec![Field {
                    name: Ident::new("value", Span::dummy()),
                    ty: inner_type,
                    mutable: false,
                }],
            }],
            repr: None,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_trait(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Trait)?;
        self.expect(TokenKind::LParen)?;
        let name = self.parse_ident()?;
        let tyvar = self.parse_tyvar()?;
        self.expect(TokenKind::RParen)?;

        let mut supertraits = Vec::new();
        if self.check(TokenKind::LParen) {
            self.advance();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                supertraits.push(self.parse_type()?);
            }
            self.expect(TokenKind::RParen)?;
        }

        let mut effects = Vec::new();
        if self.check(TokenKind::LParen) {
            self.advance();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                if self.check(TokenKind::IO) {
                    self.advance();
                    effects.push(Effect::IO);
                } else if self.check(TokenKind::Pure) {
                    self.advance();
                    effects.push(Effect::Pure);
                } else if self.check(TokenKind::Mut) {
                    self.advance();
                    effects.push(Effect::Mut);
                } else if self.check(TokenKind::Div) {
                    self.advance();
                    effects.push(Effect::Div);
                } else if self.is_ident() {
                    effects.push(Effect::Custom(self.parse_ident()?));
                }
            }
            self.expect(TokenKind::RParen)?;
        }

        let mut methods = Vec::new();
        if self.check(TokenKind::Where) {
            self.advance();
            self.expect(TokenKind::LParen)?;
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                let method_name = self.parse_ident()?;
                self.expect(TokenKind::DoubleColon)?;
                let method_ty = self.parse_type()?;
                let default = if self.eat(TokenKind::Eq) {
                    Some(self.parse_expr()?)
                } else {
                    None
                };
                let mut method_effects = Vec::new();
                if self.check(TokenKind::LParen) {
                    self.advance();
                    while !self.check(TokenKind::RParen) && !self.at_eof() {
                        if self.check(TokenKind::IO) {
                            self.advance();
                            method_effects.push(Effect::IO);
                        } else if self.check(TokenKind::Pure) {
                            self.advance();
                            method_effects.push(Effect::Pure);
                        } else if self.check(TokenKind::Mut) {
                            self.advance();
                            method_effects.push(Effect::Mut);
                        } else if self.check(TokenKind::Div) {
                            self.advance();
                            method_effects.push(Effect::Div);
                        } else if self.is_ident() {
                            method_effects.push(Effect::Custom(self.parse_ident()?));
                        }
                    }
                    self.expect(TokenKind::RParen)?;
                }
                methods.push(TraitMethod {
                    name: method_name,
                    ty: method_ty,
                    default,
                    effects: method_effects,
                });
            }
            self.expect(TokenKind::RParen)?;
        }

        Ok(Decl::DTrait {
            name,
            tyvar,
            supertraits,
            methods,
            effects,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_impl(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Impl)?;
        self.expect(TokenKind::LParen)?;
        let trait_name = self.parse_ident()?;
        let ty = self.parse_type()?;
        self.expect(TokenKind::RParen)?;

        let mut effects = Vec::new();
        if self.check(TokenKind::LParen) {
            self.advance();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                if self.check(TokenKind::IO) {
                    self.advance();
                    effects.push(Effect::IO);
                } else if self.check(TokenKind::Pure) {
                    self.advance();
                    effects.push(Effect::Pure);
                } else if self.check(TokenKind::Mut) {
                    self.advance();
                    effects.push(Effect::Mut);
                } else if self.check(TokenKind::Div) {
                    self.advance();
                    effects.push(Effect::Div);
                } else if self.is_ident() {
                    effects.push(Effect::Custom(self.parse_ident()?));
                }
            }
            self.expect(TokenKind::RParen)?;
        }

        let mut methods = Vec::new();
        if self.check(TokenKind::Where) {
            self.advance();
            self.expect(TokenKind::LParen)?;
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                self.expect(TokenKind::LParen)?;
                let name = self.parse_ident()?;
                let body = self.parse_expr()?;
                self.expect(TokenKind::RParen)?;
                methods.push((name, body));
            }
            self.expect(TokenKind::RParen)?;
        }

        Ok(Decl::DImpl {
            trait_name,
            ty,
            methods,
            effects,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_import(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Import)?;
        let mut module = vec![self.parse_ident()?];
        while self.eat(TokenKind::Dot) {
            module.push(self.parse_ident()?);
        }

        let names = if self.check(TokenKind::LParen) {
            self.advance();
            let mut items = Vec::new();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                items.push(self.parse_ident()?);
            }
            self.expect(TokenKind::RParen)?;
            items
        } else {
            Vec::new()
        };

        Ok(Decl::DImport { module, names })
    }

    fn parse_foreign(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Foreign)?;
        let name = self.parse_ident()?;
        self.expect(TokenKind::DoubleColon)?;
        let ty = self.parse_type()?;
        self.expect(TokenKind::Eq)?;
        let source = self.parse_string_literal()?;
        Ok(Decl::DForeign {
            name,
            ty,
            source,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn parse_effect(&mut self) -> ParseResult<Decl> {
        self.expect(TokenKind::Effect)?;
        let name = self.parse_ident()?;

        let mut operations = Vec::new();
        self.expect(TokenKind::LParen)?;
        while !self.check(TokenKind::RParen) && !self.at_eof() {
            self.expect(TokenKind::LParen)?;
            let op_name = self.parse_ident()?;
            self.expect(TokenKind::DoubleColon)?;
            let op_ty = self.parse_type()?;
            self.expect(TokenKind::RParen)?;
            let (params, return_type) = Self::flatten_arrow_type(op_ty);
            operations.push(EffectOp {
                name: op_name,
                params,
                return_type,
            });
        }
        self.expect(TokenKind::RParen)?;

        Ok(Decl::DEffect {
            name,
            operations,
            nid: None,
            axtags: Vec::new(),
        })
    }

    fn flatten_arrow_type(ty: Type) -> (Vec<Type>, Type) {
        let mut params = Vec::new();
        let mut current = ty;
        while let Type::TArr(param, ret) = current {
            params.push(*param);
            current = *ret;
        }
        (params, current)
    }

    fn parse_pattern(&mut self) -> ParseResult<Pattern> {
        if self.check(TokenKind::Underscore) {
            self.advance();
            return Ok(Pattern::PWildcard);
        }

        if self.check(TokenKind::LParen) {
            self.advance();

            // A constructor pattern is written exactly like a constructor
            // *application* expression - `(Some x)`, `(Node a b)` -
            // with the constructor name as the very first thing inside the
            // parens. Without this check, falling straight through to the
            // generic "N patterns in parens => tuple" reading below turns
            // `(Some x)` into a 2-tuple of two *variable* patterns named
            // `Some` and `x` - `PCon` never gets produced at all for the
            // s-expression constructor-pattern syntax every `match` example
            // in the language actually uses. This mirrors the constructor-name
            // convention `looks_like_tyvar_list` also relies on: a real
            // Axiom identifier used as a constructor is always
            // capitalized, so `is_constructor_ident` alone is enough to
            // disambiguate from a tuple pattern's first element.
            if self.is_constructor_ident() {
                let ident = self.parse_ident()?;
                let mut args = Vec::new();
                while !self.check(TokenKind::RParen) && !self.at_eof() {
                    args.push(self.parse_pattern()?);
                }
                self.expect(TokenKind::RParen)?;
                return Ok(Pattern::PCon(ident, args));
            }

            let mut patterns = Vec::new();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                patterns.push(self.parse_pattern()?);
            }
            self.expect(TokenKind::RParen)?;
            if patterns.len() == 1 {
                return Ok(patterns.into_iter().next().unwrap());
            }
            return Ok(Pattern::PTuple(patterns));
        }

        if self.check(TokenKind::LBracket) {
            self.advance();
            let mut patterns = Vec::new();
            while !self.check(TokenKind::RBracket) && !self.at_eof() {
                patterns.push(self.parse_pattern()?);
            }
            self.expect(TokenKind::RBracket)?;
            return Ok(Pattern::PList(patterns));
        }

        if self.check(TokenKind::IntLiteral(0)) {
            let token = self.advance();
            if let TokenKind::IntLiteral(n) = token.kind {
                return Ok(Pattern::PLit(Literal::LInt(n)));
            }
        }

        if self.check(TokenKind::FloatLiteral(0.0)) {
            let token = self.advance();
            if let TokenKind::FloatLiteral(n) = token.kind {
                return Ok(Pattern::PLit(Literal::LFloat(n)));
            }
        }

        if self.check(TokenKind::BoolLiteral(true)) || self.check(TokenKind::BoolLiteral(false)) {
            let token = self.advance();
            if let TokenKind::BoolLiteral(b) = token.kind {
                return Ok(Pattern::PLit(Literal::LBool(b)));
            }
        }

        if self.check(TokenKind::StringLiteral(String::new())) {
            let token = self.advance();
            if let TokenKind::StringLiteral(s) = token.kind {
                return Ok(Pattern::PLit(Literal::LStr(s)));
            }
        }

        if self.check(TokenKind::CharLiteral('\0')) {
            let token = self.advance();
            if let TokenKind::CharLiteral(c) = token.kind {
                return Ok(Pattern::PLit(Literal::LChar(c)));
            }
        }

        if self.is_ident() {
            let ident = self.parse_ident()?;
            if self.check(TokenKind::LParen) {
                self.advance();
                let mut args = Vec::new();
                while !self.check(TokenKind::RParen) && !self.at_eof() {
                    args.push(self.parse_pattern()?);
                }
                self.expect(TokenKind::RParen)?;
                return Ok(Pattern::PCon(ident, args));
            }
            return Ok(Pattern::PVar(ident));
        }

        Err(ParseError::UnexpectedToken {
            expected: "pattern".to_string(),
            found: self.current_kind_str(),
            span: self.current_span(),
        })
    }

    fn parse_type(&mut self) -> ParseResult<Type> {
        if self.check(TokenKind::LParen) {
            self.advance();

            if self.check(TokenKind::RArrow) {
                self.advance();
                let mut types = Vec::new();
                while !self.check(TokenKind::RParen) && !self.at_eof() {
                    types.push(self.parse_type_atom()?);
                }
                self.expect(TokenKind::RParen)?;
                if types.len() < 2 {
                    return Err(ParseError::Message {
                        message: "-> requires at least two types".to_string(),
                        span: self.current_span(),
                    });
                }
                let mut result = types.pop().unwrap();
                for ty in types.into_iter().rev() {
                    result = Type::arr(ty, result);
                }
                return Ok(result);
            }

            if self.check(TokenKind::RParen) {
                self.advance();
                return Ok(Type::unit());
            }

            // A parenthesized group headed by a capitalized type name is a
            // type *application* - `(Maybe Int)`, `(List a)`, `(Tree a)` -
            // with the name as the head and everything else in the parens
            // as its arguments, exactly like a constructor application
            // expression parses (head first, args after) rather than
            // "N sibling types in parens = a tuple". This is checked once,
            // here, rather than by having the bare-ident case in
            // `parse_type_atom` greedily gather trailing types as its own
            // arguments (the previous approach): that made a
            // bare, *unparenthesized* custom type name anywhere in a
            // sibling-type list - an arrow's parameter list (`(->
            // Ordering Int)`), a tuple, a constructor's field list -
            // silently swallow the *next* sibling slot as if it were an
            // argument to the first, e.g. `(-> Ordering Int)` parsed as a
            // single type `Ordering applied to Int` instead of two types,
            // which then tripped "-> requires at least two types" even
            // though two types were written. Requiring an application's
            // own parens (as every such type already is written
            // throughout the language) means a bare name in a sibling
            // list is always exactly one complete type slot.
            if self.is_constructor_ident() {
                let ident = self.parse_ident()?;
                let mut args = Vec::new();
                while !self.check(TokenKind::RParen) && !self.at_eof() {
                    args.push(self.parse_type_atom()?);
                }
                self.expect(TokenKind::RParen)?;
                return Ok(Type::TCon(ident, args));
            }

            let mut types = Vec::new();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                types.push(self.parse_type_atom()?);
            }
            self.expect(TokenKind::RParen)?;
            if types.len() == 1 {
                return Ok(types.into_iter().next().unwrap());
            }
            return Ok(Type::TTuple(types));
        }

        self.parse_type_atom()
    }

    /// Parse exactly one standalone type "slot": a fully self-delimited
    /// type that never reaches past its own tokens to swallow a sibling
    /// slot in whatever list is calling this (an arrow's parameter list,
    /// a tuple, a constructor's field list, a type application's
    /// argument list, ...). A bare, capitalized type name here always has
    /// zero arguments - applying it to arguments requires wrapping the
    /// whole application in its own parens (see `parse_type`'s
    /// constructor-application branch above), which is how every such
    /// type is actually written in practice (`(Maybe Int)`, never bare
    /// `Maybe Int`).
    fn parse_type_atom(&mut self) -> ParseResult<Type> {
        if self.check(TokenKind::LParen) {
            return self.parse_type();
        }

        if self.check(TokenKind::LBracket) {
            self.advance();
            let inner = self.parse_type()?;
            self.expect(TokenKind::RBracket)?;
            return Ok(Type::list(inner));
        }

        if self.check(TokenKind::Star) {
            self.advance();
            let inner = self.parse_type_atom()?;
            return Ok(Type::ptr(inner, false));
        }

        if self.check(TokenKind::Linear) {
            self.advance();
            let inner = self.parse_type_atom()?;
            return Ok(Type::linear(inner));
        }

        if self.is_ident() {
            let ident = self.parse_ident()?;

            if self.eat(TokenKind::At) {
                let region_name = self.parse_ident()?;
                return Ok(Type::region(Type::TCon(ident, vec![]), region_name));
            }

            if ident.name.chars().next().is_some_and(|c| c.is_lowercase()) {
                return Ok(Type::TVar(ident.name));
            }

            return Ok(Type::TCon(ident, vec![]));
        }

        self.parse_primitive_type()
    }

    fn parse_primitive_type(&mut self) -> ParseResult<Type> {
        let ty = if self.check(TokenKind::Int) || self.check(TokenKind::Integer) {
            Type::int()
        } else if self.check(TokenKind::Float) {
            Type::float()
        } else if self.check(TokenKind::Double) {
            Type::double()
        } else if self.check(TokenKind::Bool) {
            Type::bool()
        } else if self.check(TokenKind::Char) {
            Type::char()
        } else if self.check(TokenKind::String) {
            Type::string()
        } else if self.check(TokenKind::Void) {
            Type::void()
        } else if self.check(TokenKind::Any) {
            Type::any()
        } else if self.check(TokenKind::I8) {
            Type::TCon(Ident::new("I8", Span::dummy()), vec![])
        } else if self.check(TokenKind::I16) {
            Type::TCon(Ident::new("I16", Span::dummy()), vec![])
        } else if self.check(TokenKind::I32) {
            Type::TCon(Ident::new("I32", Span::dummy()), vec![])
        } else if self.check(TokenKind::I64) {
            Type::TCon(Ident::new("I64", Span::dummy()), vec![])
        } else if self.check(TokenKind::I128) {
            Type::TCon(Ident::new("I128", Span::dummy()), vec![])
        } else if self.check(TokenKind::Isize) {
            Type::TCon(Ident::new("Isize", Span::dummy()), vec![])
        } else if self.check(TokenKind::U8) {
            Type::TCon(Ident::new("U8", Span::dummy()), vec![])
        } else if self.check(TokenKind::U16) {
            Type::TCon(Ident::new("U16", Span::dummy()), vec![])
        } else if self.check(TokenKind::U32) {
            Type::TCon(Ident::new("U32", Span::dummy()), vec![])
        } else if self.check(TokenKind::U64) {
            Type::TCon(Ident::new("U64", Span::dummy()), vec![])
        } else if self.check(TokenKind::U128) {
            Type::TCon(Ident::new("U128", Span::dummy()), vec![])
        } else if self.check(TokenKind::Usize) {
            Type::TCon(Ident::new("Usize", Span::dummy()), vec![])
        } else if self.check(TokenKind::F32) {
            Type::TCon(Ident::new("F32", Span::dummy()), vec![])
        } else if self.check(TokenKind::F64) {
            Type::TCon(Ident::new("F64", Span::dummy()), vec![])
        } else {
            return Err(ParseError::UnexpectedToken {
                expected: "type".to_string(),
                found: self.current_kind_str(),
                span: self.current_span(),
            });
        };
        self.advance();
        Ok(ty)
    }

    pub fn parse_expr(&mut self) -> ParseResult<Expr> {
        self.parse_expr_inner(false)
    }

    fn parse_expr_inner(&mut self, in_parens: bool) -> ParseResult<Expr> {
        if self.check(TokenKind::LParen) {
            self.advance();

            if self.check(TokenKind::Lambda) {
                return self.parse_lambda();
            }

            if self.check(TokenKind::Let) {
                return self.parse_let();
            }

            if self.check(TokenKind::If) {
                return self.parse_if();
            }

            if self.check(TokenKind::Match) {
                return self.parse_match();
            }

            if self.check(TokenKind::Handle) {
                return self.parse_handle();
            }

            if self.check(TokenKind::Region) {
                return self.parse_region();
            }

            if self.check(TokenKind::Consume) {
                return self.parse_consume();
            }

            if self.check(TokenKind::Alloc) {
                return self.parse_alloc();
            }

            if self.check(TokenKind::Sizeof) {
                return self.parse_sizeof();
            }

            if self.check(TokenKind::Alignof) {
                return self.parse_alignof();
            }

            if self.check(TokenKind::Cast) {
                return self.parse_cast();
            }

            if self.check(TokenKind::DoubleColon) {
                return self.parse_type_sig_expr();
            }

            if self.check(TokenKind::Struct) {
                return self.parse_struct_con();
            }

            if self.check(TokenKind::Union) {
                return self.parse_union_con();
            }

            if self.check(TokenKind::RParen) {
                self.advance();
                return Ok(Expr::ETuple(vec![]));
            }

            let first = self.parse_expr_inner(true)?;

            if self.check(TokenKind::Comma) {
                let mut elements = vec![first];
                while self.eat(TokenKind::Comma) {
                    if self.check(TokenKind::RParen) {
                        break;
                    }
                    elements.push(self.parse_expr()?);
                }
                self.expect(TokenKind::RParen)?;
                return Ok(Expr::ETuple(elements));
            }

            let mut args = Vec::new();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                args.push(self.parse_expr_inner(true)?);
            }
            self.expect(TokenKind::RParen)?;

            if let Expr::EVar(ident) = &first {
                if ident.name == "-" && args.len() == 1 {
                    return Ok(Expr::EInfix(
                        Box::new(Expr::ELit(Literal::LInt(0), ident.span)),
                        "-".to_string(),
                        Box::new(args.into_iter().next().unwrap()),
                    ));
                }
            }

            let mut result = first;
            for arg in args {
                result = Expr::EApp(Box::new(result), Box::new(arg));
            }
            Ok(result)
        } else if self.check(TokenKind::LBracket) {
            self.advance();
            if self.check(TokenKind::RBracket) {
                self.advance();
                return Ok(Expr::EList(vec![]));
            }
            let mut elements = Vec::new();
            while !self.check(TokenKind::RBracket) && !self.at_eof() {
                elements.push(self.parse_expr_inner(true)?);
            }
            self.expect(TokenKind::RBracket)?;
            Ok(Expr::EList(elements))
        } else if self.check(TokenKind::LBrace) {
            self.advance();
            let mut exprs = Vec::new();
            while !self.check(TokenKind::RBrace) && !self.at_eof() {
                exprs.push(self.parse_expr()?);
            }
            self.expect(TokenKind::RBrace)?;
            if exprs.len() == 1 {
                Ok(exprs.into_iter().next().unwrap())
            } else {
                Ok(Expr::EBegin(exprs))
            }
        } else if self.check(TokenKind::Quote) {
            self.advance();
            let expr = self.parse_expr()?;
            Ok(Expr::EGrouped(Box::new(expr)))
        } else if self.check(TokenKind::Underscore) {
            let token = self.advance();
            Ok(Expr::ELam(
                vec![Pattern::PWildcard],
                Box::new(Expr::EError("hole".to_string(), token.span)),
            ))
        } else if self.check(TokenKind::Minus) && !in_parens {
            let token = self.advance();
            let expr = self.parse_expr()?;
            Ok(Expr::EInfix(
                Box::new(Expr::ELit(Literal::LInt(0), token.span)),
                "-".to_string(),
                Box::new(expr),
            ))
        } else if self.check(TokenKind::Minus) {
            let token = self.advance();
            Ok(Expr::EVar(Ident::new("-", token.span)))
        } else if self.check(TokenKind::IntLiteral(0)) {
            let token = self.advance();
            if let TokenKind::IntLiteral(n) = token.kind {
                Ok(Expr::ELit(Literal::LInt(n), token.span))
            } else {
                unreachable!()
            }
        } else if self.check(TokenKind::FloatLiteral(0.0)) {
            let token = self.advance();
            if let TokenKind::FloatLiteral(n) = token.kind {
                Ok(Expr::ELit(Literal::LFloat(n), token.span))
            } else {
                unreachable!()
            }
        } else if self.check(TokenKind::BoolLiteral(true))
            || self.check(TokenKind::BoolLiteral(false))
        {
            let token = self.advance();
            if let TokenKind::BoolLiteral(b) = token.kind {
                Ok(Expr::ELit(Literal::LBool(b), token.span))
            } else {
                unreachable!()
            }
        } else if self.check(TokenKind::StringLiteral(String::new())) {
            let token = self.advance();
            if let TokenKind::StringLiteral(s) = token.kind {
                Ok(Expr::ELit(Literal::LStr(s), token.span))
            } else {
                unreachable!()
            }
        } else if self.check(TokenKind::CharLiteral('\0')) {
            let token = self.advance();
            if let TokenKind::CharLiteral(c) = token.kind {
                Ok(Expr::ELit(Literal::LChar(c), token.span))
            } else {
                unreachable!()
            }
        } else if self.is_ident() {
            let ident = self.parse_ident()?;
            let mut expr = Expr::EVar(ident);
            while self.eat(TokenKind::Dot) {
                let field_name = self.parse_ident()?;
                expr = Expr::EField(Box::new(expr), field_name);
            }
            Ok(expr)
        } else if self.check(TokenKind::Plus)
            || self.check(TokenKind::Star)
            || self.check(TokenKind::Slash)
            || self.check(TokenKind::Percent)
            || self.check(TokenKind::Caret)
            || self.check(TokenKind::EqEq)
            || self.check(TokenKind::Neq)
            || self.check(TokenKind::Lt)
            || self.check(TokenKind::Gt)
            || self.check(TokenKind::Le)
            || self.check(TokenKind::Ge)
            || self.check(TokenKind::Bang)
            || self.check(TokenKind::AndAnd)
            || self.check(TokenKind::PipePipe)
        {
            let token = self.advance();
            Ok(Expr::EVar(Ident::new(
                &format!("{}", token.kind),
                token.span,
            )))
        } else {
            Err(ParseError::UnexpectedToken {
                expected: "expression".to_string(),
                found: self.current_kind_str(),
                span: self.current_span(),
            })
        }
    }

    fn parse_lambda(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Lambda)?;
        self.expect(TokenKind::LParen)?;
        let mut params = Vec::new();
        while !self.check(TokenKind::RParen) && !self.at_eof() {
            params.push(self.parse_pattern()?);
        }
        self.expect(TokenKind::RParen)?;
        let body = self.parse_body_exprs()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ELam(params, Box::new(body)))
    }

    fn parse_let(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Let)?;
        self.expect(TokenKind::LParen)?;

        let mut bindings = Vec::new();
        while self.check(TokenKind::LParen) {
            self.advance();
            let pattern = if self.is_ident() {
                let ident = self.parse_ident()?;
                Pattern::PVar(ident)
            } else if self.check(TokenKind::Underscore) {
                self.advance();
                Pattern::PWildcard
            } else {
                self.parse_pattern()?
            };
            self.eat(TokenKind::Eq);
            let expr = self.parse_expr()?;
            self.expect(TokenKind::RParen)?;
            bindings.push((pattern, expr));
        }
        self.expect(TokenKind::RParen)?;

        let body = self.parse_body_exprs()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ELet(bindings, Box::new(body)))
    }

    fn parse_if(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::If)?;
        let cond = self.parse_expr()?;
        let then_expr = self.parse_expr()?;
        let else_expr = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EIf(
            Box::new(cond),
            Box::new(then_expr),
            Box::new(else_expr),
        ))
    }

    fn parse_match(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Match)?;
        let target = self.parse_expr()?;

        let mut arms = Vec::new();
        while self.check(TokenKind::LParen) {
            self.advance();
            let pattern = self.parse_pattern()?;
            let body = self.parse_body_exprs()?;
            self.expect(TokenKind::RParen)?;
            arms.push((pattern, body));
        }
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EMatch(Box::new(target), arms))
    }

    fn parse_body_exprs(&mut self) -> ParseResult<Expr> {
        let first = self.parse_expr()?;
        let mut exprs = vec![first];
        while !self.check(TokenKind::RParen) && !self.at_eof() {
            exprs.push(self.parse_expr()?);
        }
        if exprs.len() == 1 {
            Ok(exprs.into_iter().next().unwrap())
        } else {
            Ok(Expr::EBegin(exprs))
        }
    }

    fn parse_handle(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Handle)?;
        let body = self.parse_expr()?;
        let mut effects = Vec::new();
        if self.check(TokenKind::LParen) {
            self.advance();
            while !self.check(TokenKind::RParen) && !self.at_eof() {
                if self.check(TokenKind::IO) {
                    self.advance();
                    effects.push(Effect::IO);
                } else if self.check(TokenKind::Pure) {
                    self.advance();
                    effects.push(Effect::Pure);
                } else if self.check(TokenKind::Mut) {
                    self.advance();
                    effects.push(Effect::Mut);
                } else if self.check(TokenKind::Div) {
                    self.advance();
                    effects.push(Effect::Div);
                } else if self.is_ident() {
                    effects.push(Effect::Custom(self.parse_ident()?));
                }
            }
            self.expect(TokenKind::RParen)?;
        }
        let handler = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EHandle(Box::new(body), effects, Box::new(handler)))
    }

    fn parse_region(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Region)?;
        let name = self.parse_ident()?;
        let body = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ERegion(name, Box::new(body)))
    }

    fn parse_consume(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Consume)?;
        let expr = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EConsume(Box::new(expr)))
    }

    fn parse_alloc(&mut self) -> ParseResult<Expr> {
        let start = self.expect(TokenKind::Alloc)?.span;
        let ty = self.parse_type()?;
        let count = if !self.check(TokenKind::RParen) {
            Some(Box::new(self.parse_expr()?))
        } else {
            None
        };
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EAlloc(ty, count, start))
    }

    fn parse_sizeof(&mut self) -> ParseResult<Expr> {
        let start = self.expect(TokenKind::Sizeof)?.span;
        let ty = self.parse_type()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ESizeof(ty, start))
    }

    fn parse_alignof(&mut self) -> ParseResult<Expr> {
        let start = self.expect(TokenKind::Alignof)?.span;
        let ty = self.parse_type()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EAlignof(ty, start))
    }

    fn parse_cast(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Cast)?;
        let target_ty = self.parse_type()?;
        let expr = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ECast(Box::new(expr), target_ty))
    }

    fn parse_type_sig_expr(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::DoubleColon)?;
        let expr = self.parse_expr()?;
        let ty = self.parse_type()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::ETypeSig(Box::new(expr), ty))
    }

    fn parse_struct_con(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Struct)?;
        let name = self.parse_ident()?;
        let mut args = Vec::new();
        while !self.check(TokenKind::RParen) && !self.at_eof() {
            args.push(self.parse_expr()?);
        }
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EStructCon(name, args))
    }

    fn parse_union_con(&mut self) -> ParseResult<Expr> {
        self.expect(TokenKind::Union)?;
        let name = self.parse_ident()?;
        let field_name = self.parse_ident()?;
        let value = self.parse_expr()?;
        self.expect(TokenKind::RParen)?;
        Ok(Expr::EUnionCon(name, field_name, Box::new(value)))
    }

    fn parse_string_literal(&mut self) -> ParseResult<String> {
        let token = self.expect(TokenKind::StringLiteral(String::new()))?;
        if let TokenKind::StringLiteral(s) = token.kind {
            Ok(s)
        } else {
            Err(ParseError::UnexpectedToken {
                expected: "string literal".to_string(),
                found: self.current_kind_str(),
                span: token.span,
            })
        }
    }

    /// Parse a type-parameter list. Axiom's own documented syntax always
    /// wraps it in parens right after the type/struct/union/alias name -
    /// `()` for none, `(a)` for one, `(a b)` for several (see the README's
    /// `Maybe`/`List`/`Tree`/`type StringList () = ...` examples) - but
    /// that immediately following `(` is *also* how the very next thing
    /// after it (the first constructor of a `data`, or the first field of
    /// a `struct`/`union`) begins, e.g. `(struct Ordering (LT) (EQ) (GT))`
    /// has *no* type parameters at all before its first nullary
    /// constructor `(LT)`.
    ///
    /// [`looks_like_tyvar_list`](Self::looks_like_tyvar_list) disambiguates
    /// by scanning past the `(`: a real tyvar list is zero or more
    /// lowercase identifiers followed immediately by `)`, with nothing
    /// else in between. A constructor name is conventionally capitalized
    /// (`None`, `Some`, `LT`, ...) so it never matches the "all
    /// lowercase" scan, and a struct/union field like `(x : Int)` fails
    /// the scan the moment it hits `:` instead of `)`. Without this,
    /// every parenthesized-tyvar example in the README - which is all of
    /// them - either silently dropped its type parameters (turning the
    /// first constructor into a bogus extra one) or, for `type`
    /// aliases, failed to parse at all.
    fn parse_tyvars(&mut self) -> Vec<String> {
        if self.check(TokenKind::LParen) && self.looks_like_tyvar_list() {
            self.advance(); // consume '('
            let mut tyvars = Vec::new();
            while self.is_tyvar() {
                if let TokenKind::Ident(name) = &self.tokens[self.pos].kind {
                    tyvars.push(name.clone());
                }
                self.advance();
            }
            if self.check(TokenKind::RParen) {
                self.advance(); // consume ')' - guaranteed present by the lookahead above
            }
            return tyvars;
        }

        // Defensive fallback for bare, unparenthesized tyvars with no
        // surrounding `(...)` at all (not part of Axiom's documented
        // syntax, but harmless to keep accepting if it ever shows up).
        let mut tyvars = Vec::new();
        while self.is_tyvar() {
            if let TokenKind::Ident(name) = &self.tokens[self.pos].kind {
                tyvars.push(name.clone());
            }
            self.advance();
        }
        tyvars
    }

    /// Lookahead-only check: does the `(...)` starting at the current
    /// token (which must be `LParen`) contain *only* zero or more
    /// lowercase identifiers before the matching `)`? See
    /// [`parse_tyvars`](Self::parse_tyvars) for why this is exactly the
    /// condition that distinguishes a type-parameter list from the first
    /// constructor/field group. Does not consume any tokens.
    fn looks_like_tyvar_list(&self) -> bool {
        let mut i = self.pos + 1;
        loop {
            match self.tokens.get(i).map(|t| &t.kind) {
                Some(TokenKind::RParen) => return true,
                Some(TokenKind::Ident(name))
                    if name.chars().next().is_some_and(|c| c.is_lowercase()) =>
                {
                    i += 1;
                }
                _ => return false,
            }
        }
    }

    fn parse_tyvar(&mut self) -> ParseResult<String> {
        if let TokenKind::Ident(name) = &self.tokens[self.pos].kind {
            let name = name.clone();
            self.advance();
            Ok(name)
        } else {
            Err(ParseError::UnexpectedToken {
                expected: "type variable".to_string(),
                found: self.current_kind_str(),
                span: self.current_span(),
            })
        }
    }

    fn parse_int_literal(&mut self) -> ParseResult<i64> {
        let token = self.advance();
        match token.kind {
            TokenKind::IntLiteral(n) => Ok(n),
            _ => Err(ParseError::UnexpectedToken {
                expected: "integer literal".to_string(),
                found: format!("{}", token.kind),
                span: token.span,
            }),
        }
    }

    fn parse_ident(&mut self) -> ParseResult<Ident> {
        let token = self.advance();
        let name = match &token.kind {
            TokenKind::Ident(name) => name.clone(),
            TokenKind::Int => "Int".to_string(),
            TokenKind::Integer => "Integer".to_string(),
            TokenKind::Float => "Float".to_string(),
            TokenKind::Double => "Double".to_string(),
            TokenKind::Bool => "Bool".to_string(),
            TokenKind::Char => "Char".to_string(),
            TokenKind::String => "String".to_string(),
            TokenKind::Unit => "Unit".to_string(),
            TokenKind::Any => "Any".to_string(),
            TokenKind::Void => "Void".to_string(),
            TokenKind::I8 => "I8".to_string(),
            TokenKind::I16 => "I16".to_string(),
            TokenKind::I32 => "I32".to_string(),
            TokenKind::I64 => "I64".to_string(),
            TokenKind::I128 => "I128".to_string(),
            TokenKind::Isize => "Isize".to_string(),
            TokenKind::U8 => "U8".to_string(),
            TokenKind::U16 => "U16".to_string(),
            TokenKind::U32 => "U32".to_string(),
            TokenKind::U64 => "U64".to_string(),
            TokenKind::U128 => "U128".to_string(),
            TokenKind::Usize => "Usize".to_string(),
            TokenKind::F32 => "F32".to_string(),
            TokenKind::F64 => "F64".to_string(),
            TokenKind::Pure => "Pure".to_string(),
            TokenKind::IO => "IO".to_string(),
            TokenKind::Mut => "Mut".to_string(),
            TokenKind::Div => "Div".to_string(),
            TokenKind::Fn => "fn".to_string(),
            _ => {
                return Err(ParseError::UnexpectedToken {
                    expected: "identifier".to_string(),
                    found: format!("{}", token.kind),
                    span: token.span,
                })
            }
        };
        Ok(Ident::new(&name, token.span))
    }

    fn is_ident(&self) -> bool {
        if let Some(token) = self.tokens.get(self.pos) {
            matches!(token.kind, TokenKind::Ident(_))
        } else {
            false
        }
    }

    fn is_tyvar(&self) -> bool {
        if let Some(token) = self.tokens.get(self.pos) {
            if let TokenKind::Ident(name) = &token.kind {
                name.chars().next().is_some_and(|c| c.is_lowercase())
            } else {
                false
            }
        } else {
            false
        }
    }

    /// Is the current token an identifier written in the constructor-name
    /// convention (capitalized), e.g. `Some`, `None`, `Leaf`? Used by
    /// [`parse_pattern`](Self::parse_pattern) to tell a constructor
    /// pattern's head apart from a tuple pattern's first element.
    fn is_constructor_ident(&self) -> bool {
        if let Some(token) = self.tokens.get(self.pos) {
            if let TokenKind::Ident(name) = &token.kind {
                return name.chars().next().is_some_and(|c| c.is_uppercase());
            }
        }
        false
    }

    fn check(&self, kind: TokenKind) -> bool {
        if let Some(token) = self.tokens.get(self.pos) {
            match (&token.kind, &kind) {
                (TokenKind::Ident(a), TokenKind::Ident(b)) => a == b,
                (TokenKind::IntLiteral(_), TokenKind::IntLiteral(_)) => true,
                (TokenKind::FloatLiteral(_), TokenKind::FloatLiteral(_)) => true,
                (TokenKind::StringLiteral(_), TokenKind::StringLiteral(_)) => true,
                (TokenKind::CharLiteral(_), TokenKind::CharLiteral(_)) => true,
                (TokenKind::BoolLiteral(_), TokenKind::BoolLiteral(_)) => true,
                _ => std::mem::discriminant(&token.kind) == std::mem::discriminant(&kind),
            }
        } else {
            false
        }
    }

    fn eat(&mut self, kind: TokenKind) -> bool {
        if self.check(kind) {
            self.advance();
            true
        } else {
            false
        }
    }

    fn expect(&mut self, kind: TokenKind) -> ParseResult<Token> {
        let kind_str = format!("{}", kind);
        if self.check(kind) {
            Ok(self.advance())
        } else if self.at_eof() {
            // Distinguish "ran out of tokens entirely" (AX2002, e.g. an
            // unbalanced `(`) from "found a real, but wrong, token"
            // (AX2001). Previously every EOF-while-expecting-a-token case
            // was folded into `UnexpectedToken { found: "EOF", .. }`,
            // which left `ParseError::UnexpectedEof`/`AX2002` completely
            // dead code that could never actually be emitted.
            Err(ParseError::UnexpectedEof {
                span: self.current_span(),
            })
        } else {
            Err(ParseError::UnexpectedToken {
                expected: kind_str,
                found: self.current_kind_str(),
                span: self.current_span(),
            })
        }
    }

    fn advance(&mut self) -> Token {
        let token = self.tokens[self.pos].clone();
        if self.pos < self.tokens.len() - 1 {
            self.pos += 1;
        }
        token
    }

    fn current_span(&self) -> Span {
        if let Some(token) = self.tokens.get(self.pos) {
            token.span
        } else {
            Span::dummy()
        }
    }

    fn current_kind_str(&self) -> String {
        if let Some(token) = self.tokens.get(self.pos) {
            format!("{}", token.kind)
        } else {
            "EOF".to_string()
        }
    }

    fn at_eof(&self) -> bool {
        self.pos >= self.tokens.len() - 1
            || matches!(
                self.tokens.get(self.pos),
                Some(Token {
                    kind: TokenKind::Eof,
                    ..
                })
            )
    }

    pub fn is_decl_start(&self) -> bool {
        if let Some(token) = self.tokens.get(self.pos) {
            if matches!(
                token.kind,
                TokenKind::Define
                    | TokenKind::Fn
                    | TokenKind::Struct
                    | TokenKind::Union
                    | TokenKind::Type
                    | TokenKind::Newtype
                    | TokenKind::Trait
                    | TokenKind::Impl
                    | TokenKind::Import
                    | TokenKind::Foreign
                    | TokenKind::Effect
                    | TokenKind::DoubleColon
            ) {
                return true;
            }
            // Check for parenthesized declarations like (:: ...) or (define ...)
            if token.kind == TokenKind::LParen {
                if let Some(next) = self.tokens.get(self.pos + 1) {
                    return matches!(
                        next.kind,
                        TokenKind::Define
                            | TokenKind::Fn
                            | TokenKind::Struct
                            | TokenKind::Union
                            | TokenKind::Type
                            | TokenKind::Newtype
                            | TokenKind::Trait
                            | TokenKind::Impl
                            | TokenKind::Import
                            | TokenKind::Foreign
                            | TokenKind::Effect
                            | TokenKind::DoubleColon
                    );
                }
            }
        }
        false
    }

    pub fn parse_decl_or_expr(&mut self) -> Result<DeclOrExpr, ParseError> {
        if self.is_decl_start() {
            let decl = self.parse_decl()?;
            Ok(DeclOrExpr::Decl(decl))
        } else {
            let expr = self.parse_expr()?;
            Ok(DeclOrExpr::Expr(expr))
        }
    }
}

pub enum DeclOrExpr {
    Decl(Decl),
    Expr(Expr),
}

#[cfg(test)]
mod tests {
    use super::*;
    use axiom_ast::ast::Pattern;
    use axiom_lexer::Lexer;

    fn parse_ok(source: &str) -> Module {
        let mut lexer = Lexer::new(source, 0);
        let tokens = lexer.tokenize().expect("lex failed");
        Parser::new(tokens).parse_module().expect("parse failed")
    }

    fn parse_pattern_ok(source: &str) -> Pattern {
        // A pattern only ever appears nested inside some other
        // construct, never as a standalone top-level form - `match` is
        // the simplest one that puts a pattern in an easily-extracted
        // position.
        let module = parse_ok(&format!(
            "(:: main Int)\n(fn main (match 0 (({}) 1)))",
            source
        ));
        match &module.decls[1] {
            Decl::DFn { body, .. } => match body {
                Expr::EMatch(_, arms) => arms[0].0.clone(),
                other => panic!("expected EMatch, got {:?}", other),
            },
            other => panic!("expected DFn, got {:?}", other),
        }
    }

    /// Regression test for the bug where constructor patterns like
    /// `(Some x)` parsed as `PTuple([PVar("Some"), PVar("x")])` (two bare
    /// variables) instead of `PCon("Some", [PVar("x")])`, because the
    /// parenthesized-pattern branch never special-cased a
    /// capitalized head the way constructor *expressions* already did.
    /// See `parse_pattern`'s constructor-application-shaped branch.
    #[test]
    fn constructor_pattern_with_args_parses_as_pcon_not_ptuple() {
        match parse_pattern_ok("Some x") {
            Pattern::PCon(ident, args) => {
                assert_eq!(ident.name, "Some");
                assert_eq!(args.len(), 1);
                assert!(matches!(&args[0], Pattern::PVar(v) if v.name == "x"));
            }
            other => panic!("expected PCon, got {:?}", other),
        }
    }

    /// Regression test for the companion bug: a *nullary* constructor
    /// pattern like `(None)` degenerated to a bare `PVar("None")`
    /// (the parenthesized-pattern branch's "exactly one sub-pattern ->
    /// unwrap it" rule), which happened to limp along in codegen (which
    /// matched constructors by name for both `PCon` and `PVar`) but broke
    /// outright once `axiom-sema` started distinguishing "matches a real
    /// constructor" from "catch-all variable binding" for exhaustiveness
    /// checking.
    #[test]
    fn nullary_constructor_pattern_parses_as_pcon_with_no_args() {
        match parse_pattern_ok("None") {
            Pattern::PCon(ident, args) => {
                assert_eq!(ident.name, "None");
                assert!(args.is_empty());
            }
            other => panic!("expected PCon, got {:?}", other),
        }
    }

    /// A genuine tuple pattern (lowercase elements, no constructor-name
    /// head) must still parse as `PTuple`, not get swept into the new
    /// constructor-pattern branch.
    #[test]
    fn tuple_pattern_of_variables_still_parses_as_ptuple() {
        match parse_pattern_ok("x y") {
            Pattern::PTuple(pats) => assert_eq!(pats.len(), 2),
            other => panic!("expected PTuple, got {:?}", other),
        }
    }

    /// Regression test for the bug where a bare (unparenthesized) custom
    /// type name inside a sibling-type list - most visibly an arrow
    /// type's parameter list - greedily consumed the *next* sibling slot
    /// as if it were its own type argument: `(-> Ordering Int)` parsed as
    /// one type (`Ordering` applied to `Int`) instead of two, which then
    /// tripped "-> requires at least two types" even though two types
    /// were written. See `parse_type`'s constructor-application branch
    /// and `parse_type_atom`'s doc comment.
    #[test]
    fn bare_custom_type_in_arrow_list_does_not_swallow_its_sibling() {
        let module = parse_ok("(:: describe (-> Ordering Int))\n(:: main Int)\n(fn main 0)");
        match &module.decls[0] {
            Decl::DSig { ty, .. } => match ty {
                Type::TArr(from, to) => {
                    assert!(
                        matches!(from.as_ref(), Type::TCon(name, args) if name.name == "Ordering" && args.is_empty())
                    );
                    assert!(
                        matches!(to.as_ref(), Type::TCon(name, args) if name.name == "Int" && args.is_empty())
                    );
                }
                other => panic!("expected TArr, got {:?}", other),
            },
            other => panic!("expected DSig, got {:?}", other),
        }
    }

    /// A parenthesized type application (`(Option Int)`) must still parse
    /// as one applied type, not as a 2-tuple of two standalone types -
    /// the fix for the bug above must not regress this, much more common,
    /// `match`.
    #[test]
    fn parenthesized_type_application_parses_as_tcon_with_args() {
        let module = parse_ok("(:: main (Option Int))\n(fn main 0)");
        match &module.decls[0] {
            Decl::DSig { ty, .. } => match ty {
                Type::TCon(name, args) => {
                    assert_eq!(name.name, "Option");
                    assert_eq!(args.len(), 1);
                    assert!(matches!(&args[0], Type::TCon(inner, _) if inner.name == "Int"));
                }
                other => panic!("expected TCon, got {:?}", other),
            },
            other => panic!("expected DSig, got {:?}", other),
        }
    }

    /// Regression test for the sibling bug in `parse_tyvars`: a `struct`
    /// type's parenthesized type-parameter list (`(a)`, `()`, `(a b)`)
    /// was previously indistinguishable from its first constructor/field
    /// group, since both start with a bare `(`. See `looks_like_tyvar_list`.
    #[test]
    fn data_type_parameter_list_is_not_mistaken_for_a_constructor() {
        let module = parse_ok(
            "(struct Tree (Leaf) (Node Int (Tree Int) (Tree Int)))\n(:: main Int)\n(fn main 0)",
        );
        match &module.decls[0] {
            Decl::DStruct {
                tyvars, variants, ..
            } => {
                assert!(tyvars.is_empty());
                assert_eq!(variants.len(), 2);
                assert_eq!(variants[0].name.name, "Leaf");
                assert_eq!(variants[1].name.name, "Node");
            }
            other => panic!("expected DStruct, got {:?}", other),
        }
    }

    /// A `struct` type with *no* type parameters must not have its first
    /// nullary variant mistaken for an (empty) type-parameter list -
    /// the disambiguation in `looks_like_tyvar_list` has to fail
    /// gracefully for a capitalized variant name too.
    #[test]
    fn data_type_with_no_parameters_and_nullary_constructors() {
        let module =
            parse_ok("(struct Ordering\n  (LT)\n  (EQ)\n  (GT))\n(:: main Int)\n(fn main 0)");
        match &module.decls[0] {
            Decl::DStruct {
                tyvars, variants, ..
            } => {
                assert!(tyvars.is_empty());
                assert_eq!(variants.len(), 3);
            }
            other => panic!("expected DStruct, got {:?}", other),
        }
    }

    #[test]
    fn type_alias_with_empty_parameter_list_parses() {
        let module = parse_ok("(type StringList () = [String])\n(:: main Int)\n(fn main 0)");
        match &module.decls[0] {
            Decl::DType { tyvars, .. } => assert!(tyvars.is_empty()),
            other => panic!("expected DType, got {:?}", other),
        }
    }

    #[test]
    fn import_with_and_without_name_filter_parses() {
        let module = parse_ok(
            "(import Math.Ops (square cube))\n(import Data.List)\n(:: main Int)\n(fn main 0)",
        );
        match &module.imports[0] {
            Decl::DImport {
                module: path,
                names,
            } => {
                assert_eq!(
                    path.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(),
                    ["Math", "Ops"]
                );
                assert_eq!(
                    names.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(),
                    ["square", "cube"]
                );
            }
            other => panic!("expected DImport, got {:?}", other),
        }
        match &module.imports[1] {
            Decl::DImport {
                module: path,
                names,
            } => {
                assert_eq!(
                    path.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(),
                    ["Data", "List"]
                );
                assert!(names.is_empty());
            }
            other => panic!("expected DImport, got {:?}", other),
        }
    }

    #[test]
    fn struct_with_packed_attribute_parses() {
        let module =
            parse_ok("(struct Point packed\n  (x : Int)\n  (y : Int))\n(:: main Int)\n(fn main 0)");
        match &module.decls[0] {
            Decl::DStruct { variants, repr, .. } => {
                assert_eq!(variants.len(), 1);
                assert_eq!(variants[0].fields.len(), 2);
                assert!(matches!(repr, Some(TypeRepr::Packed)));
            }
            other => panic!("expected DStruct, got {:?}", other),
        }
    }
}
