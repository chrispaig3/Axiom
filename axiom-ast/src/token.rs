use crate::span::Span;
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum TokenKind {
    // Literals
    IntLiteral(i64),
    FloatLiteral(f64),
    BoolLiteral(bool),
    StringLiteral(String),
    CharLiteral(char),

    // Identifiers
    Ident(String),

    // Keywords
    Define,   // (define name body) or (define (name args...) body)
    Lambda,   // (lambda (args...) body)
    Let,      // (let ((x val)...) body)
    If,       // (if cond then else)
    Cond,     // (cond (test body)... (else body))
    Match,    // (match expr (pattern body)...)
    Fn,       // (fn (name args...) body) - modern alias for define
    Data,     // (data Name (tyvars...) (constructor...))
    Struct,   // (struct Name (field...) )
    Union,    // (union Name (field...))
    Type,     // (type Name (tyvars...) alias)
    Newtype,  // (newtype Name (tyvars...) ctor inner)
    Class,    // (class (Name tv) (super...) (method...))
    Instance, // (instance (Class Type) (method...))
    Import,   // (import module (names...))
    Foreign,  // (foreign name type "symbol")
    Pub,      // (pub decl)
    Deriving, // (deriving Class...)
    Where,    // for class/instance method bodies
    Effect,   // (effect Name (op...))
    Handle,   // (handle body (handler...))
    Region,   // (region name body)
    Linear,   // linear type marker
    Consume,  // (consume expr)
    Packed,   // packed struct modifier
    Repr,     // repr(C) struct modifier
    Align,    // align(N) struct modifier
    Alloc,    // (alloc Type) or (alloc Type count)
    Sizeof,   // (sizeof Type)
    Alignof,  // (alignof Type)
    Cast,     // (cast Type expr)

    // Type keywords
    Int,
    Integer,
    Float,
    Double,
    Bool,
    Char,
    String,
    Unit,
    Any,
    I8,
    I16,
    I32,
    I64,
    I128,
    Isize,
    U8,
    U16,
    U32,
    U64,
    U128,
    Usize,
    F32,
    F64,
    Void,
    Pure,
    IO,
    Mut,
    Div,

    // Operators
    RArrow,      // ->
    DoubleArrow, // =>
    DoubleColon, // ::
    Colon,       // :
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Caret,
    Bang,
    Eq,
    EqEq,
    Neq,
    Lt,
    Gt,
    Le,
    Ge,
    Dot,
    Comma,
    Underscore,
    Quote,    // '
    At,       // @
    Amp,      // &
    Pipe,     // |
    AndAnd,   // &&
    PipePipe, // ||

    // Delimiters
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,

    // Special
    Comment,
    /// A source-embedded agent metadata tag: `;@axiom:<key>(<value>)`.
    /// Unlike ordinary line comments that the lexer discards, AXTAG
    /// tokens are preserved as trivia so the parser can attach them
    /// to the declaration that follows.
    Axtag(String),
    Eof,
}

impl fmt::Display for TokenKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TokenKind::IntLiteral(n) => write!(f, "{}", n),
            TokenKind::FloatLiteral(n) => write!(f, "{}", n),
            TokenKind::BoolLiteral(b) => write!(f, "{}", b),
            TokenKind::StringLiteral(s) => write!(f, "\"{}\"", s),
            TokenKind::CharLiteral(c) => write!(f, "'{}'", c),
            TokenKind::Ident(s) => write!(f, "{}", s),
            TokenKind::Define => write!(f, "define"),
            TokenKind::Lambda => write!(f, "lambda"),
            TokenKind::Let => write!(f, "let"),
            TokenKind::If => write!(f, "if"),
            TokenKind::Cond => write!(f, "cond"),
            TokenKind::Match => write!(f, "match"),
            TokenKind::Fn => write!(f, "fn"),
            TokenKind::Data => write!(f, "data"),
            TokenKind::Struct => write!(f, "struct"),
            TokenKind::Union => write!(f, "union"),
            TokenKind::Type => write!(f, "type"),
            TokenKind::Newtype => write!(f, "newtype"),
            TokenKind::Class => write!(f, "class"),
            TokenKind::Instance => write!(f, "instance"),
            TokenKind::Import => write!(f, "import"),
            TokenKind::Foreign => write!(f, "foreign"),
            TokenKind::Pub => write!(f, "pub"),
            TokenKind::Deriving => write!(f, "deriving"),
            TokenKind::Where => write!(f, "where"),
            TokenKind::Effect => write!(f, "effect"),
            TokenKind::Handle => write!(f, "handle"),
            TokenKind::Region => write!(f, "region"),
            TokenKind::Linear => write!(f, "linear"),
            TokenKind::Consume => write!(f, "consume"),
            TokenKind::Packed => write!(f, "packed"),
            TokenKind::Repr => write!(f, "repr"),
            TokenKind::Align => write!(f, "align"),
            TokenKind::Alloc => write!(f, "alloc"),
            TokenKind::Sizeof => write!(f, "sizeof"),
            TokenKind::Alignof => write!(f, "alignof"),
            TokenKind::Cast => write!(f, "cast"),
            TokenKind::Int => write!(f, "Int"),
            TokenKind::Integer => write!(f, "Integer"),
            TokenKind::Float => write!(f, "Float"),
            TokenKind::Double => write!(f, "Double"),
            TokenKind::Bool => write!(f, "Bool"),
            TokenKind::Char => write!(f, "Char"),
            TokenKind::String => write!(f, "String"),
            TokenKind::Unit => write!(f, "()"),
            TokenKind::Any => write!(f, "Any"),
            TokenKind::I8 => write!(f, "I8"),
            TokenKind::I16 => write!(f, "I16"),
            TokenKind::I32 => write!(f, "I32"),
            TokenKind::I64 => write!(f, "I64"),
            TokenKind::I128 => write!(f, "I128"),
            TokenKind::Isize => write!(f, "Isize"),
            TokenKind::U8 => write!(f, "U8"),
            TokenKind::U16 => write!(f, "U16"),
            TokenKind::U32 => write!(f, "U32"),
            TokenKind::U64 => write!(f, "U64"),
            TokenKind::U128 => write!(f, "U128"),
            TokenKind::Usize => write!(f, "Usize"),
            TokenKind::F32 => write!(f, "F32"),
            TokenKind::F64 => write!(f, "F64"),
            TokenKind::Void => write!(f, "Void"),
            TokenKind::Pure => write!(f, "Pure"),
            TokenKind::IO => write!(f, "IO"),
            TokenKind::Mut => write!(f, "Mut"),
            TokenKind::Div => write!(f, "Div"),
            TokenKind::RArrow => write!(f, "->"),
            TokenKind::DoubleArrow => write!(f, "=>"),
            TokenKind::DoubleColon => write!(f, "::"),
            TokenKind::Colon => write!(f, ":"),
            TokenKind::Plus => write!(f, "+"),
            TokenKind::Minus => write!(f, "-"),
            TokenKind::Star => write!(f, "*"),
            TokenKind::Slash => write!(f, "/"),
            TokenKind::Percent => write!(f, "%"),
            TokenKind::Caret => write!(f, "^"),
            TokenKind::Bang => write!(f, "!"),
            TokenKind::Eq => write!(f, "="),
            TokenKind::EqEq => write!(f, "=="),
            TokenKind::Neq => write!(f, "!="),
            TokenKind::Lt => write!(f, "<"),
            TokenKind::Gt => write!(f, ">"),
            TokenKind::Le => write!(f, "<="),
            TokenKind::Ge => write!(f, ">="),
            TokenKind::Dot => write!(f, "."),
            TokenKind::Comma => write!(f, ","),
            TokenKind::Underscore => write!(f, "_"),
            TokenKind::Quote => write!(f, "'"),
            TokenKind::At => write!(f, "@"),
            TokenKind::Amp => write!(f, "&"),
            TokenKind::Pipe => write!(f, "|"),
            TokenKind::AndAnd => write!(f, "&&"),
            TokenKind::PipePipe => write!(f, "||"),
            TokenKind::LParen => write!(f, "("),
            TokenKind::RParen => write!(f, ")"),
            TokenKind::LBracket => write!(f, "["),
            TokenKind::RBracket => write!(f, "]"),
            TokenKind::LBrace => write!(f, "{{"),
            TokenKind::RBrace => write!(f, "}}"),
            TokenKind::Comment => write!(f, "; comment"),
            TokenKind::Axtag(s) => write!(f, ";@axiom:{}", s),
            TokenKind::Eof => write!(f, "EOF"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
}

impl Token {
    pub fn new(kind: TokenKind, span: Span) -> Self {
        Self { kind, span }
    }
}
