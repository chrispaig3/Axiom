use axiom_ast::token::{Token, TokenKind};
use axiom_ast::span::Span;
use axiom_errors::{code, Diagnostic};

/// Every variant now carries the [`Span`] where it occurred; previously the
/// CLI reported all lexer errors at a hardcoded byte offset of `0`, which
/// meant the location shown to the user was almost always wrong.
#[derive(Debug, thiserror::Error)]
pub enum LexerError {
    #[error("unexpected character `{ch}`")]
    UnexpectedChar { ch: char, span: Span },
    #[error("unterminated string literal")]
    UnterminatedString { span: Span },
    #[error("unterminated char literal")]
    UnterminatedChar { span: Span },
    #[error("invalid number literal `{text}`")]
    InvalidNumber { text: String, span: Span },
    #[error("invalid escape sequence `\\{ch}`")]
    InvalidEscape { ch: char, span: Span },
}

impl LexerError {
    pub fn span(&self) -> Span {
        match self {
            LexerError::UnexpectedChar { span, .. } => *span,
            LexerError::UnterminatedString { span, .. } => *span,
            LexerError::UnterminatedChar { span, .. } => *span,
            LexerError::InvalidNumber { span, .. } => *span,
            LexerError::InvalidEscape { span, .. } => *span,
        }
    }

    /// Convert into a renderer-agnostic [`Diagnostic`], with a code and a
    /// tailored help message for each lexical failure mode.
    pub fn to_diagnostic(&self) -> Diagnostic {
        let span = self.span();
        match self {
            LexerError::UnexpectedChar { ch, .. } => {
                Diagnostic::error(&code::UNEXPECTED_CHAR, self.to_string())
                    .with_primary(span, format!("`{}` is not valid here", ch))
                    .with_help(
                        "identifiers may contain letters, digits, `_`, and `'`; \
                         operators are built from `+ - * / % ^ = < > ! & | . ? ~ @`",
                    )
            }
            LexerError::UnterminatedString { .. } => {
                Diagnostic::error(&code::UNTERMINATED_STRING, self.to_string())
                    .with_primary(span, "string literal starts here but is never closed")
                    .with_help("add a closing `\"`, or escape an embedded quote as `\\\"`")
            }
            LexerError::UnterminatedChar { .. } => {
                Diagnostic::error(&code::UNTERMINATED_CHAR, self.to_string())
                    .with_primary(span, "character literal starts here but is never closed")
                    .with_help("character literals must contain exactly one character, e.g. `'a'` or `'\\n'`")
            }
            LexerError::InvalidNumber { text, .. } => {
                Diagnostic::error(&code::INVALID_NUMBER, self.to_string())
                    .with_primary(span, format!("`{}` cannot be parsed as Int or Float", text))
                    .with_help("check for a value that overflows i64/f64 or a malformed exponent")
            }
            LexerError::InvalidEscape { .. } => {
                Diagnostic::error(&code::INVALID_ESCAPE, self.to_string())
                    .with_primary(span, "unrecognized escape sequence")
                    .with_help("valid escapes are \\n \\t \\r \\\\ \\\" \\' \\0")
            }
        }
    }
}

fn is_operator_char(ch: char) -> bool {
    matches!(ch, '+' | '-' | '*' | '/' | '%' | '^' | '=' | '<' | '>' | '!' | '&' | '|' | '.' | '?' | '~' | '@')
}

pub struct Lexer {
    source: Vec<char>,
    source_str: String,
    pos: usize,
    file_id: usize,
}

impl Lexer {
    pub fn new(source: &str, file_id: usize) -> Self {
        Self {
            source: source.chars().collect(),
            source_str: source.to_string(),
            pos: 0,
            file_id,
        }
    }

    pub fn tokenize(&mut self) -> Result<Vec<Token>, LexerError> {
        let mut tokens = Vec::new();

        while self.pos < self.source.len() {
            let ch = self.source[self.pos];

            if ch.is_whitespace() {
                self.pos += 1;
                continue;
            }

            if ch == ';' {
                self.consume_line_comment();
                continue;
            }

            if ch == '#' && self.peek() == Some('|') {
                self.consume_block_comment()?;
                continue;
            }

            if ch == ':' && self.peek() == Some(':') {
                let start = self.pos;
                self.pos += 2;
                tokens.push(Token::new(TokenKind::DoubleColon, self.span(start)));
                continue;
            }

            if ch == '\'' {
                if self.peek().map_or(false, |c| c != ' ' && c != '(' && c != '[') {
                    tokens.push(self.consume_char()?);
                } else {
                    self.push_token(&mut tokens, TokenKind::Quote);
                }
                continue;
            }

            if ch.is_alphabetic() || ch == '_' {
                tokens.push(self.consume_identifier());
                continue;
            }

            if ch.is_ascii_digit() || (ch == '.' && self.peek().map_or(false, |c| c.is_ascii_digit())) {
                tokens.push(self.consume_number()?);
                continue;
            }

            match ch {
                '"' => tokens.push(self.consume_string()?),
                '`' => self.push_token(&mut tokens, TokenKind::Quote),
                '$' => self.push_token(&mut tokens, TokenKind::Bang),
                '+' => self.push_token(&mut tokens, TokenKind::Plus),
                '%' => self.push_token(&mut tokens, TokenKind::Percent),
                '^' => self.push_token(&mut tokens, TokenKind::Caret),
                '@' => self.push_token(&mut tokens, TokenKind::At),
                ',' => self.push_token(&mut tokens, TokenKind::Comma),
                '_' => self.push_token(&mut tokens, TokenKind::Underscore),
                '(' => self.push_token(&mut tokens, TokenKind::LParen),
                ')' => self.push_token(&mut tokens, TokenKind::RParen),
                '[' => self.push_token(&mut tokens, TokenKind::LBracket),
                ']' => self.push_token(&mut tokens, TokenKind::RBracket),
                '{' => self.push_token(&mut tokens, TokenKind::LBrace),
                '}' => self.push_token(&mut tokens, TokenKind::RBrace),
                ':' => {
                    if self.peek() == Some(':') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::DoubleColon, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Colon);
                    }
                }
                '-' => {
                    if self.peek() == Some('>') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::RArrow, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Minus);
                    }
                }
                '=' => {
                    if self.peek() == Some('>') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::DoubleArrow, self.span(start)));
                    } else if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::EqEq, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Eq);
                    }
                }
                '<' => {
                    if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::Le, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Lt);
                    }
                }
                '>' => {
                    if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::Ge, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Gt);
                    }
                }
                '!' => {
                    if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::Neq, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Bang);
                    }
                }
                '.' => {
                    if self.peek().map_or(false, |c| c.is_ascii_digit()) {
                        tokens.push(self.consume_number()?);
                    } else {
                        self.push_token(&mut tokens, TokenKind::Dot);
                    }
                }
                '*' => {
                    if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::Eq, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Star);
                    }
                }
                '/' => {
                    if self.peek() == Some('=') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::Eq, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Slash);
                    }
                }
                '&' => {
                    if self.peek() == Some('&') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::AndAnd, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Amp);
                    }
                }
                '|' => {
                    if self.peek() == Some('|') {
                        let start = self.pos;
                        self.pos += 2;
                        tokens.push(Token::new(TokenKind::PipePipe, self.span(start)));
                    } else {
                        self.push_token(&mut tokens, TokenKind::Pipe);
                    }
                }
                _ => return Err(LexerError::UnexpectedChar {
                    ch,
                    span: Span::new(self.pos, self.pos + 1, self.file_id),
                }),
            }
        }

        tokens.push(Token::new(TokenKind::Eof, self.span(self.pos)));
        Ok(tokens)
    }

    pub fn source_str(&self) -> &str {
        &self.source_str
    }

    fn peek(&self) -> Option<char> {
        self.source.get(self.pos + 1).copied()
    }

    fn span(&self, start: usize) -> Span {
        Span::new(start, self.pos, self.file_id)
    }

    fn push_token(&mut self, tokens: &mut Vec<Token>, kind: TokenKind) {
        let start = self.pos;
        self.pos += 1;
        tokens.push(Token::new(kind, self.span(start)));
    }

    fn consume_identifier(&mut self) -> Token {
        let start = self.pos;
        while self.pos < self.source.len() {
            let ch = self.source[self.pos];
            if ch.is_alphanumeric() || ch == '_' || ch == '\'' {
                self.pos += 1;
            } else if is_operator_char(ch) && self.pos == start {
                self.pos += 1;
            } else if is_operator_char(ch) && is_operator_char(self.source[self.pos - 1]) {
                self.pos += 1;
            } else {
                break;
            }
        }
        let name: String = self.source[start..self.pos].iter().collect();
        let kind = match name.as_str() {
            "define" => TokenKind::Define,
            "lambda" => TokenKind::Lambda,
            "let" => TokenKind::Let,
            "if" => TokenKind::If,
            "cond" => TokenKind::Cond,
            "case" => TokenKind::Case,
            "fn" => TokenKind::Fn,
            "data" => TokenKind::Data,
            "struct" => TokenKind::Struct,
            "union" => TokenKind::Union,
            "type" => TokenKind::Type,
            "newtype" => TokenKind::Newtype,
            "class" => TokenKind::Class,
            "instance" => TokenKind::Instance,
            "import" => TokenKind::Import,
            "foreign" => TokenKind::Foreign,
            "pub" => TokenKind::Pub,
            "deriving" => TokenKind::Deriving,
            "where" => TokenKind::Where,
            "effect" => TokenKind::Effect,
            "handle" => TokenKind::Handle,
            "region" => TokenKind::Region,
            "linear" => TokenKind::Linear,
            "consume" => TokenKind::Consume,
            "packed" => TokenKind::Packed,
            "repr" => TokenKind::Repr,
            "align" => TokenKind::Align,
            "alloc" => TokenKind::Alloc,
            "sizeof" => TokenKind::Sizeof,
            "alignof" => TokenKind::Alignof,
            "cast" => TokenKind::Cast,
            "true" => TokenKind::BoolLiteral(true),
            "false" => TokenKind::BoolLiteral(false),
            "Int" => TokenKind::Int,
            "Integer" => TokenKind::Integer,
            "Float" => TokenKind::Float,
            "Double" => TokenKind::Double,
            "Bool" => TokenKind::Bool,
            "Char" => TokenKind::Char,
            "String" => TokenKind::String,
            "Any" => TokenKind::Any,
            "Void" => TokenKind::Void,
            "Pure" => TokenKind::Pure,
            "IO" => TokenKind::IO,
            "Mut" => TokenKind::Mut,
            "Div" => TokenKind::Div,
            "I8" => TokenKind::I8,
            "I16" => TokenKind::I16,
            "I32" => TokenKind::I32,
            "I64" => TokenKind::I64,
            "I128" => TokenKind::I128,
            "Isize" => TokenKind::Isize,
            "U8" => TokenKind::U8,
            "U16" => TokenKind::U16,
            "U32" => TokenKind::U32,
            "U64" => TokenKind::U64,
            "U128" => TokenKind::U128,
            "Usize" => TokenKind::Usize,
            "F32" => TokenKind::F32,
            "F64" => TokenKind::F64,
            _ => TokenKind::Ident(name),
        };
        Token::new(kind, self.span(start))
    }

    fn consume_number(&mut self) -> Result<Token, LexerError> {
        let start = self.pos;
        let mut is_float = false;

        while self.pos < self.source.len() {
            let ch = self.source[self.pos];
            if ch.is_ascii_digit() || ch == '_' {
                self.pos += 1;
            } else if ch == '.' && !is_float {
                if self.peek().map_or(false, |c| c.is_ascii_digit()) {
                    is_float = true;
                    self.pos += 1;
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        let num_str: String = self.source[start..self.pos].iter().filter(|&&c| c != '_').collect();

        if is_float {
            match num_str.parse::<f64>() {
                Ok(n) => Ok(Token::new(TokenKind::FloatLiteral(n), self.span(start))),
                Err(_) => Err(LexerError::InvalidNumber { text: num_str, span: self.span(start) }),
            }
        } else {
            match num_str.parse::<i64>() {
                Ok(n) => Ok(Token::new(TokenKind::IntLiteral(n), self.span(start))),
                Err(_) => Err(LexerError::InvalidNumber { text: num_str, span: self.span(start) }),
            }
        }
    }

    fn consume_string(&mut self) -> Result<Token, LexerError> {
        let start = self.pos;
        self.pos += 1;
        let mut value = String::new();

        while self.pos < self.source.len() {
            let ch = self.source[self.pos];
            if ch == '\\' {
                self.pos += 1;
                if self.pos >= self.source.len() {
                    return Err(LexerError::UnterminatedString { span: self.span(start) });
                }
                let esc = self.source[self.pos];
                match esc {
                    'n' => value.push('\n'),
                    't' => value.push('\t'),
                    'r' => value.push('\r'),
                    '\\' => value.push('\\'),
                    '"' => value.push('"'),
                    '\'' => value.push('\''),
                    '0' => value.push('\0'),
                    _ => return Err(LexerError::InvalidEscape {
                        ch: esc,
                        span: Span::new(self.pos - 1, self.pos + 1, self.file_id),
                    }),
                }
                self.pos += 1;
            } else if ch == '"' {
                self.pos += 1;
                return Ok(Token::new(TokenKind::StringLiteral(value), self.span(start)));
            } else {
                value.push(ch);
                self.pos += 1;
            }
        }

        Err(LexerError::UnterminatedString { span: self.span(start) })
    }

    fn consume_char(&mut self) -> Result<Token, LexerError> {
        let start = self.pos;
        self.pos += 1;

        if self.pos >= self.source.len() {
            return Err(LexerError::UnterminatedChar { span: self.span(start) });
        }

        let ch = if self.source[self.pos] == '\\' {
            self.pos += 1;
            if self.pos >= self.source.len() {
                return Err(LexerError::UnterminatedChar { span: self.span(start) });
            }
            match self.source[self.pos] {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '\'' => '\'',
                '"' => '"',
                '0' => '\0',
                _ => return Err(LexerError::InvalidEscape {
                    ch: self.source[self.pos],
                    span: Span::new(self.pos - 1, self.pos + 1, self.file_id),
                }),
            }
        } else {
            self.source[self.pos]
        };

        self.pos += 1;

        if self.pos >= self.source.len() || self.source[self.pos] != '\'' {
            return Err(LexerError::UnterminatedChar { span: self.span(start) });
        }
        self.pos += 1;

        Ok(Token::new(TokenKind::CharLiteral(ch), self.span(start)))
    }

    fn consume_line_comment(&mut self) {
        self.pos += 1;
        while self.pos < self.source.len() && self.source[self.pos] != '\n' {
            self.pos += 1;
        }
    }

    fn consume_block_comment(&mut self) -> Result<(), LexerError> {
        self.pos += 2;
        let mut depth = 1;
        while self.pos < self.source.len() && depth > 0 {
            if self.source[self.pos] == '#' && self.peek() == Some('|') {
                self.pos += 2;
                depth += 1;
            } else if self.source[self.pos] == '|' && self.peek() == Some('#') {
                self.pos += 2;
                depth -= 1;
            } else {
                self.pos += 1;
            }
        }
        Ok(())
    }
}
