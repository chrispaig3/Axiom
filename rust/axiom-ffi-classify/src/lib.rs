//! The Rust -> Axiom boundary, classified ONCE.
//!
//! Two tools read a `#[axiom_export]` annotation: the proc macro, which
//! generates the C-ABI shim, and `axiom-bindgen`, which generates the
//! Axiom module that calls it. They used to carry two copies of the
//! type table and the two had already drifted (`Vec<T>` refused by one
//! and mapped to `String` by the other). This crate is the single
//! table both consult, plus the naming rules (`axffi_` symbols,
//! camelCase Axiom names, snake_case opaque stems) and the attribute
//! grammar, so a name or a message is spelled in exactly one place.
//!
//! The classifier is CLOSED: every accepted type is enumerated and
//! anything else is refused with a message that lists what is
//! accepted. The old `_ => Opaque` fallback is what let `u128`,
//! `Option<T>` and a bare `Vec<T>` become leaked boxes with no
//! diagnostic.

use syn::{GenericArgument, Meta, PathArguments, Type};

/// The word scalars, as the messages list them: every type that is one
/// word with a meaning both sides agree on.
pub const WORD_SCALARS: &str = "i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char f64 f32";

/// The parameter types the boundary accepts, as the refusal messages
/// list them.
pub const PARAM_TYPES: &str = "i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char f64 f32 \
                               &str &[u8] &[&str] &[T] &[&[T]] (T a word scalar) \
                               &mut [i64] &mut [f64] &mut [u64] AxFn1 AxFn2 AxFn3 \
                               &T &mut T (T marked `#[axiom_opaque]`) \
                               T &[T] (T marked `#[axiom_record]`)";

/// The return types the boundary accepts, as the refusal messages list
/// them.
pub const RETURN_TYPES: &str = "i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char f64 f32 () \
                                String Vec<u8> Vec<T> Vec<Vec<T>> (T a word scalar) Vec<String> \
                                Option<T> Result<T, E> Result<Option<T>, E> Option<Result<T, E>> \
                                T (T marked `#[axiom_opaque]` or `#[axiom_record]`) \
                                Vec<T> (T marked `#[axiom_record]`; E: Display)";

/// The field types an `#[axiom_record]` accepts: the word scalars.
pub const RECORD_FIELD_TYPES: &str = WORD_SCALARS;

/// The keys `#[axiom_export(...)]` accepts, as the refusal lists them.
pub const EXPORT_KEYS: &str = "`symbol = \"name\"` and `utf8 = \"lossy\"`";

/// The keys `#[axiom_opaque(...)]` accepts.
pub const OPAQUE_KEYS: &str = "`symbol = \"stem\"`";

/// A value that crosses as one word without any protocol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scalar {
    I64,
    I32,
    I16,
    I8,
    /// The word's 64 bits read unsigned, both ways, with no range
    /// check: nothing is lost, and Axiom sees a value >= 2^63 as
    /// negative.
    U64,
    U32,
    U16,
    U8,
    Usize,
    Isize,
    Bool,
    /// A Unicode scalar value in the word: Axiom `Char`. A word that
    /// is not one aborts on the way in, as a narrow integer out of
    /// range does.
    Char,
    F64,
    F32,
    /// `()` or no return type. Crosses as the word 0 and binds as `Int`.
    Unit,
}

impl Scalar {
    fn from_name(name: &str) -> Option<Scalar> {
        Some(match name {
            "i64" => Scalar::I64,
            "i32" => Scalar::I32,
            "i16" => Scalar::I16,
            "i8" => Scalar::I8,
            "u64" => Scalar::U64,
            "u32" => Scalar::U32,
            "u16" => Scalar::U16,
            "u8" => Scalar::U8,
            "usize" => Scalar::Usize,
            "isize" => Scalar::Isize,
            "bool" => Scalar::Bool,
            "char" => Scalar::Char,
            "f64" => Scalar::F64,
            "f32" => Scalar::F32,
            _ => return None,
        })
    }

    /// The Rust spelling.
    pub fn rust_name(self) -> &'static str {
        match self {
            Scalar::I64 => "i64",
            Scalar::I32 => "i32",
            Scalar::I16 => "i16",
            Scalar::I8 => "i8",
            Scalar::U64 => "u64",
            Scalar::U32 => "u32",
            Scalar::U16 => "u16",
            Scalar::U8 => "u8",
            Scalar::Usize => "usize",
            Scalar::Isize => "isize",
            Scalar::Bool => "bool",
            Scalar::Char => "char",
            Scalar::F64 => "f64",
            Scalar::F32 => "f32",
            Scalar::Unit => "()",
        }
    }

    /// The Axiom type the word binds as.
    pub fn axiom_type(self) -> &'static str {
        match self {
            Scalar::F64 | Scalar::F32 => "Float",
            Scalar::Bool => "Bool",
            Scalar::Char => "Char",
            _ => "Int",
        }
    }

    /// An integer narrower than the word: the shim range-checks it on
    /// the way in (and widens losslessly on the way out).
    pub fn is_narrow_int(self) -> bool {
        matches!(
            self,
            Scalar::I32
                | Scalar::I16
                | Scalar::I8
                | Scalar::U32
                | Scalar::U16
                | Scalar::U8
                | Scalar::Usize
                | Scalar::Isize
        )
    }

    pub fn is_float(self) -> bool {
        matches!(self, Scalar::F64 | Scalar::F32)
    }

    /// A word whose every bit pattern is a value of the type, at the
    /// word's own size and alignment: an Axiom `Vec` of them is read
    /// (and written) in place, never through a converted copy.
    pub fn is_word_sized(self) -> bool {
        matches!(self, Scalar::I64 | Scalar::U64 | Scalar::F64)
    }
}

/// A named Rust type Axiom holds as a handle.
#[derive(Clone, Debug)]
pub struct OpaqueTy {
    /// The type as written (possibly path-qualified), for the shim.
    pub ty: Type,
    /// The bare type name, for the Axiom `data` and the drop symbol.
    pub name: String,
}

/// One field of an `#[axiom_record]` struct: a word scalar.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RecordField {
    pub name: String,
    pub scalar: Scalar,
}

/// A struct marked `#[axiom_record]`: it crosses AS ITS FIELDS, one
/// word each in declaration order.
///
/// `fields` is empty while the record is UNRESOLVED: the classifier
/// sees only the type's name, and the field list comes from a
/// [`Registry`] (bindgen's table of every `#[axiom_record]` under the
/// source root; the macro's answer from the type's companion macro).
#[derive(Clone, Debug)]
pub struct RecordTy {
    /// The type as written (possibly path-qualified), for the shim.
    pub ty: Type,
    /// The bare type name, for the Axiom `data` and the companion.
    pub name: String,
    pub fields: Vec<RecordField>,
}

impl RecordTy {
    /// The number of words the record crosses as.
    pub fn arity(&self) -> usize {
        self.fields.len()
    }

    /// Whether the field list has been filled in.
    pub fn is_resolved(&self) -> bool {
        !self.fields.is_empty()
    }
}

/// What a [`Registry`] knows about a named type.
#[derive(Clone, Debug)]
pub enum Named {
    /// Marked `#[axiom_record]`, with its fields.
    Record(Vec<RecordField>),
    /// Marked `#[axiom_opaque]`.
    Opaque,
}

/// The named types a classification can consult. A bare type name in
/// parameter position is always a record; in return position it is an
/// opaque handle unless the registry says it is a record.
pub trait Registry {
    fn lookup(&self, name: &str) -> Option<Named>;
}

/// Knows nothing: every bare return type is opaque and every bare
/// parameter type is an unresolved record.
pub struct NoRecords;

impl Registry for NoRecords {
    fn lookup(&self, _name: &str) -> Option<Named> {
        None
    }
}

/// How one parameter crosses.
#[derive(Clone, Debug)]
pub enum Param {
    Scalar(Scalar),
    /// `&str`: a borrowed view, validated (or lossily converted) UTF-8.
    Str,
    /// `&[u8]`: a borrowed view of the bytes.
    Bytes,
    /// `&T` / `&mut T`: a borrowed opaque handle.
    Opaque { ty: OpaqueTy, mutable: bool },
    /// `&[T]` for a word scalar `T`: an Axiom `Vec` handle whose words
    /// are read as `T` for the call. `&[i64]`, `&[u64]` and `&[f64]`
    /// are read in place, every other `T` converted (and checked) into
    /// a temporary.
    Words(Scalar),
    /// `&mut [i64]` / `&mut [f64]` / `&mut [u64]`: the Axiom `Vec`'s
    /// live elements, written in place for the call.
    MutWords(Scalar),
    /// `&[&[T]]` for a word scalar `T`: an Axiom `Vec` of `Vec`
    /// handles, each inner `Vec` read as `&[T]` for the call.
    WordLists(Scalar),
    /// `&[&str]`: an Axiom `Vec` of Strings, each borrowed as `&str`
    /// for the call.
    Strs,
    /// `AxFn1` / `AxFn2` / `AxFn3`: an Axiom closure record, borrowed
    /// for the call. The arity is 1, 2 or 3.
    Callback(u8),
    /// A by-value `#[axiom_record]`: one word per field.
    Record(RecordTy),
    /// `&[T]` for an `#[axiom_record]` `T`: an Axiom `Vec` of `ARITY`
    /// words per element (the wrapper flattens the records on the
    /// Axiom side), chunked into a temporary `Vec<T>` for the call.
    Records(RecordTy),
}

/// What a fallible or optional return carries on success.
#[derive(Clone, Debug)]
pub enum Payload {
    Scalar(Scalar),
    /// `String` / `Vec<u8>`: owned bytes, handed over through the cell.
    Bytes,
    /// `Vec<T>` for a word scalar `T`: owned words `(ptr, len)`, one
    /// per element (ints widened, bool 0/1, floats as f64 bits), handed
    /// over through the cell.
    Words(Scalar),
    /// `Vec<Vec<T>>` for a word scalar `T`: `(ptr, n)` where `ptr`
    /// holds `2n` words of `(wordsPtr, len)` pairs, one owned word
    /// buffer per inner `Vec`, handed over through the cell.
    WordLists(Scalar),
    /// `Vec<String>`: `(ptr, n)` where `ptr` holds `2n` words of
    /// `(bytesPtr, byteLen)` pairs, handed over through the cell.
    Strs,
    /// An owned opaque value, boxed, handed over as its address.
    Opaque(OpaqueTy),
    /// An `#[axiom_record]` value: its field words, written at the
    /// start of a cell of `arity` words.
    Record(RecordTy),
    /// `Vec<T>` for an `#[axiom_record]` `T`: `(ptr, n)` where `ptr`
    /// holds `n * ARITY` owned words, element-major in field order,
    /// freed as `n * ARITY` words.
    Records(RecordTy),
}

/// How the return crosses.
#[derive(Clone, Debug)]
pub enum Ret {
    /// The shim returns the value itself.
    Scalar(Scalar),
    /// The shim returns the boxed value's address.
    Opaque(OpaqueTy),
    /// The shim takes an out-cell, writes `(ptr, len)`, returns 0.
    Bytes,
    /// The shim takes an out-cell, writes `(ptr, len)` of words, returns 0.
    Words(Scalar),
    /// The shim takes an out-cell, writes `(ptr, n)` of word-buffer
    /// pairs, returns 0.
    WordLists(Scalar),
    /// The shim takes an out-cell, writes `(ptr, n)` of string pairs,
    /// returns 0.
    Strs,
    /// The shim takes an out-cell of `arity` words, writes the field
    /// words, returns 0.
    Record(RecordTy),
    /// The shim takes an out-cell, writes `(ptr, n)` of `n * arity`
    /// record words, returns 0.
    Records(RecordTy),
    /// The shim takes an out-cell; 0 = payload in the cell, 1 = an
    /// error message's `(ptr, len)` in the cell.
    Result(Payload),
    /// The shim takes an out-cell; 0 = payload in the cell, 2 = None.
    Option(Payload),
    /// `Result<Option<T>, E>`: 0 = `Ok(Some(payload))`, 2 = `Ok(None)`,
    /// 1 = `Err(message)`.
    ResultOption(Payload),
    /// `Option<Result<T, E>>`: 0 = `Some(Ok(payload))`, 1 =
    /// `Some(Err(message))`, 2 = `None`.
    OptionResult(Payload),
}

impl Ret {
    /// Whether the shim takes a trailing out-cell word.
    pub fn needs_cell(&self) -> bool {
        !matches!(self, Ret::Scalar(_) | Ret::Opaque(_))
    }

    /// Whether an `Err` can come back (so an invalid `&str` argument is
    /// reported rather than aborting).
    pub fn is_result(&self) -> bool {
        matches!(self, Ret::Result(_) | Ret::ResultOption(_) | Ret::OptionResult(_))
    }

    /// The payload behind the status word of a fallible or optional
    /// return, whatever the nesting.
    pub fn status_payload(&self) -> Option<&Payload> {
        match self {
            Ret::Result(p) | Ret::Option(p) | Ret::ResultOption(p) | Ret::OptionResult(p) => {
                Some(p)
            }
            _ => None,
        }
    }

    /// The number of words the out-cell must hold: two for every
    /// protocol (a `(ptr, len)` pair, a message), a record's arity when
    /// that is more.
    pub fn cell_words(&self) -> usize {
        let arity = match self {
            Ret::Record(r) => r.arity(),
            _ => match self.status_payload() {
                Some(Payload::Record(r)) => r.arity(),
                _ => 0,
            },
        };
        arity.max(2)
    }
}

fn type_text(ty: &Type) -> String {
    quote_type(ty)
}

fn quote_type(ty: &Type) -> String {
    // `syn` prints with spaces between every token; tidy the common
    // shapes so the message reads as the user wrote it.
    use quote::ToTokens;
    let raw = ty.to_token_stream().to_string();
    raw.replace(" < ", "<")
        .replace(" >", ">")
        .replace("& ", "&")
        .replace(" ,", ",")
        .replace(" :: ", "::")
        .replace(" ]", "]")
        .replace("( ", "(")
        .replace(" )", ")")
}

fn path_last(ty: &Type) -> Option<(&syn::PathSegment, String)> {
    if let Type::Path(p) = ty {
        if p.qself.is_some() {
            return None;
        }
        let seg = p.path.segments.last()?;
        return Some((seg, seg.ident.to_string()));
    }
    None
}

/// The single generic argument of `Seg<T>`, if that is the shape.
fn single_generic(seg: &syn::PathSegment) -> Option<&Type> {
    if let PathArguments::AngleBracketed(a) = &seg.arguments {
        if a.args.len() >= 1 {
            if let GenericArgument::Type(t) = &a.args[0] {
                return Some(t);
            }
        }
    }
    None
}

fn is_u8(ty: &Type) -> bool {
    matches!(path_last(ty), Some((seg, name)) if name == "u8" && seg.arguments.is_none())
}

fn refuse_param(spelling: &str, why: &str) -> String {
    format!(
        "`{spelling}` is not supported as an `#[axiom_export]` parameter{why}; \
         the supported parameter types are: {PARAM_TYPES}"
    )
}

fn refuse_return(spelling: &str, why: &str) -> String {
    format!(
        "`{spelling}` is not supported as an `#[axiom_export]` return type{why}; \
         the supported return types are: {RETURN_TYPES}"
    )
}

/// Classify one parameter type with no knowledge of named types: a
/// by-value named type is an unresolved record.
pub fn classify_param(ty: &Type) -> Result<Param, String> {
    classify_param_with(ty, &NoRecords)
}

/// Classify one parameter type, consulting `registry` for a by-value
/// named type (a record's fields; an opaque type, which is refused by
/// value).
pub fn classify_param_with(ty: &Type, registry: &dyn Registry) -> Result<Param, String> {
    let text = type_text(ty);
    match ty {
        Type::Reference(r) => {
            let mutable = r.mutability.is_some();
            match &*r.elem {
                Type::Path(_) if is_str(&r.elem) => {
                    if mutable {
                        return Err(refuse_param(
                            &text,
                            " (Axiom strings are immutable through the FFI; take `&str`)",
                        ));
                    }
                    Ok(Param::Str)
                }
                Type::Slice(s) => {
                    if mutable {
                        return match scalar_of(&s.elem) {
                            Some(sc) if sc.is_word_sized() => Ok(Param::MutWords(sc)),
                            _ => Err(refuse_param(
                                &text,
                                " (only `&mut [i64]`, `&mut [f64]` and `&mut [u64]` are written \
                                 in place: an Axiom `Vec` holds words, and a converted copy \
                                 could not be written back as the same words; take `&[T]` \
                                 and return a `Vec<T>`)",
                            )),
                        };
                    }
                    if is_u8(&s.elem) {
                        return Ok(Param::Bytes);
                    }
                    if let Some((seg, name)) = path_last(&s.elem) {
                        if seg.arguments.is_none() {
                            if let Some(sc) = Scalar::from_name(&name) {
                                return Ok(Param::Words(sc));
                            }
                        }
                        if name == "String" {
                            return Err(refuse_param(
                                &text,
                                " (an Axiom `Vec` of Strings is borrowed: take `&[&str]`)",
                            ));
                        }
                        if is_two_words(&name) {
                            return Err(refuse_param(&text, TWO_WORDS));
                        }
                        if seg.arguments.is_none() && !is_refused_name(&name) {
                            return match registry.lookup(&name) {
                                Some(Named::Opaque) => Err(refuse_param(
                                    &text,
                                    " (a slice of handles does not cross: an Axiom `Vec` \
                                     holds words; hold the collection in a type marked \
                                     `#[axiom_opaque]`, or take the handles one at a time)",
                                )),
                                Some(Named::Record(fields)) => Ok(Param::Records(RecordTy {
                                    ty: (*s.elem).clone(),
                                    name,
                                    fields,
                                })),
                                None => Ok(Param::Records(RecordTy {
                                    ty: (*s.elem).clone(),
                                    name,
                                    fields: Vec::new(),
                                })),
                            };
                        }
                    }
                    if let Type::Reference(inner) = &*s.elem {
                        if is_str(&inner.elem) {
                            return Ok(Param::Strs);
                        }
                        if let Type::Slice(inner_slice) = &*inner.elem {
                            if inner.mutability.is_some() {
                                return Err(refuse_param(
                                    &text,
                                    " (the inner slices of a nested `Vec` are borrowed: take \
                                     `&[&[T]]`)",
                                ));
                            }
                            return match scalar_of(&inner_slice.elem) {
                                Some(sc) => Ok(Param::WordLists(sc)),
                                None => Err(refuse_param(&text, ONE_LEVEL_PARAM)),
                            };
                        }
                    }
                    Err(refuse_param(
                        &text,
                        " (only `&[u8]`, `&[&str]`, `&[T]` and `&[&[T]]` over a word scalar, \
                         and `&[T]` over an `#[axiom_record]` cross; an Axiom `Vec` holds \
                         words)",
                    ))
                }
                Type::Path(_) => {
                    let (seg, name) = path_last(&r.elem).ok_or_else(|| {
                        refuse_param(&text, "")
                    })?;
                    if Scalar::from_name(&name).is_some() && seg.arguments.is_none() {
                        return Err(refuse_param(&text, " (scalars pass by value)"));
                    }
                    match name.as_str() {
                        "String" | "Vec" | "Option" | "Result" | "Box" | "Rc" | "Arc" => {
                            return Err(refuse_param(
                                &text,
                                " (borrow the bytes as `&str`/`&[u8]`, the words as `&[T]`, \
                                 or hold the value in a type marked `#[axiom_opaque]`)",
                            ));
                        }
                        "u128" | "i128" => {
                            return Err(refuse_param(&text, TWO_WORDS));
                        }
                        "AxFn1" | "AxFn2" | "AxFn3" => {
                            return Err(refuse_param(
                                &text,
                                " (a callback is one word and `Copy`; take it by value)",
                            ));
                        }
                        _ => {}
                    }
                    if let Some(Named::Record(_)) = registry.lookup(&name) {
                        return Err(refuse_param(
                            &text,
                            " (a record crosses as its fields; take it by value)",
                        ));
                    }
                    Ok(Param::Opaque {
                        ty: OpaqueTy { ty: (*r.elem).clone(), name },
                        mutable,
                    })
                }
                _ => Err(refuse_param(&text, "")),
            }
        }
        Type::Tuple(t) if t.elems.is_empty() => {
            Err(refuse_param(&text, " (`()` carries nothing; drop the parameter)"))
        }
        Type::Path(_) => {
            let (seg, name) = path_last(ty).ok_or_else(|| refuse_param(&text, ""))?;
            if let Some(s) = Scalar::from_name(&name) {
                if seg.arguments.is_none() {
                    return Ok(Param::Scalar(s));
                }
            }
            if let Some(arity) = callback_arity(&name) {
                if seg.arguments.is_none() {
                    return Ok(Param::Callback(arity));
                }
            }
            match name.as_str() {
                "u128" | "i128" => Err(refuse_param(&text, TWO_WORDS)),
                "String" => Err(refuse_param(&text, " (borrow it: take `&str`)")),
                "Vec" => Err(refuse_param(
                    &text,
                    " (borrow it: take `&[u8]`, `&[&str]`, `&[T]` or `&[&[T]]` over a word \
                     scalar, or `&[T]` over an `#[axiom_record]`)",
                )),
                "Option" | "Result" => Err(refuse_param(
                    &text,
                    " (`Option` and `Result` may only be returned)",
                )),
                "Box" | "Rc" | "Arc" => Err(refuse_param(
                    &text,
                    " (hold the value in a type marked `#[axiom_opaque]` and take `&T`)",
                )),
                _ if !seg.arguments.is_none() => Err(refuse_param(
                    &text,
                    " (a type with generic arguments cannot cross: a shim is one symbol)",
                )),
                _ => match registry.lookup(&name) {
                    Some(Named::Opaque) => Err(refuse_param(
                        &text,
                        " (Axiom holds a handle, so take `&T` or `&mut T`, or return it)",
                    )),
                    Some(Named::Record(fields)) => {
                        Ok(Param::Record(RecordTy { ty: ty.clone(), name, fields }))
                    }
                    None => Ok(Param::Record(RecordTy { ty: ty.clone(), name, fields: Vec::new() })),
                },
            }
        }
        _ => Err(refuse_param(&text, "")),
    }
}

/// A bare name the boundary refuses everywhere, so a slice of it gets
/// the generic message rather than the records-and-handles one.
fn is_refused_name(name: &str) -> bool {
    matches!(
        name,
        "u128" | "i128" | "str" | "Vec" | "Option" | "Result" | "Box" | "Rc" | "Arc" | "AxFn1"
            | "AxFn2" | "AxFn3"
    )
}

/// `u128` / `i128`: two words, which no slot of the boundary holds.
fn is_two_words(name: &str) -> bool {
    matches!(name, "u128" | "i128")
}

/// Why a 128-bit integer is refused, wherever it appears.
const TWO_WORDS: &str = " (a 128-bit integer is two words and every slot of the boundary is one; \
                         split it into two `u64`s - the high and low halves each cross as a \
                         word's bits)";

/// Why a nested `Vec` parameter over anything but a word scalar is refused.
const ONE_LEVEL_PARAM: &str = " (a nested `Vec` crosses as one level of word scalars: `&[&[T]]` \
                               with T one of i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char \
                               f64 f32; strings and records do not nest, so take a flat `&[&str]` \
                               or `&[T]` with a `&[i64]` of row lengths)";

/// Why a nested `Vec` result over anything but a word scalar is refused.
const ONE_LEVEL_RETURN: &str = " (a nested `Vec` crosses as one level of word scalars: \
                                `Vec<Vec<T>>` with T one of i64 i32 i16 i8 u64 u32 u16 u8 usize \
                                isize bool char f64 f32; strings and records do not nest, so \
                                return a flat `Vec<String>` or `Vec<T>` with a `Vec<i64>` of row \
                                lengths)";

/// Classify the fields of an `#[axiom_record]` struct: every one a
/// word scalar, refused otherwise with the accepted set.
pub fn classify_record_fields<'a, I>(fields: I) -> Result<Vec<RecordField>, String>
where
    I: IntoIterator<Item = (&'a str, &'a Type)>,
{
    let mut out = Vec::new();
    for (name, ty) in fields {
        let text = type_text(ty);
        let scalar = match path_last(ty) {
            Some((seg, tn)) if seg.arguments.is_none() => Scalar::from_name(&tn),
            _ => None,
        };
        let Some(scalar) = scalar else {
            let why = match path_last(ty).map(|(_, n)| n).as_deref() {
                Some("String") | Some("str") => " (a record is its words; put the String beside \
                                                 it as a separate `&str` parameter, or hold it \
                                                 in an `#[axiom_opaque]` type)",
                Some("Vec") => " (a collection is not a word; pass it as a `&[T]` parameter \
                                 or hold it in an `#[axiom_opaque]` type)",
                Some("u128") | Some("i128") => TWO_WORDS,
                _ if matches!(ty, Type::Reference(_)) => " (a record owns its words; a borrow \
                                                          cannot cross as a field)",
                _ if matches!(ty, Type::Path(_)) => " (a nested record or an opaque handle does \
                                                     not cross as a field: flatten the words \
                                                     into this record, or hold the value in an \
                                                     `#[axiom_opaque]` type)",
                _ => "",
            };
            return Err(format!(
                "field `{name}: {text}` is not a word scalar{why}; an `#[axiom_record]` field \
                 must be one of: {RECORD_FIELD_TYPES}"
            ));
        };
        out.push(RecordField { name: name.to_string(), scalar });
    }
    if out.is_empty() {
        return Err("an `#[axiom_record]` needs at least one field: it crosses as its words, \
                    and a record of no words carries nothing"
            .to_string());
    }
    Ok(out)
}

fn is_str(ty: &Type) -> bool {
    is_named(ty, "str")
}

/// `ty` is the bare path `name` (its last segment, with no generics).
fn is_named(ty: &Type, wanted: &str) -> bool {
    matches!(path_last(ty), Some((seg, name)) if name == wanted && seg.arguments.is_none())
}

/// `AxFn1` -> 1, `AxFn2` -> 2, `AxFn3` -> 3.
fn callback_arity(name: &str) -> Option<u8> {
    match name {
        "AxFn1" => Some(1),
        "AxFn2" => Some(2),
        "AxFn3" => Some(3),
        _ => None,
    }
}

/// Classify the payload of `Result<T, _>` / `Option<T>`, or a direct
/// return. `nested` names the wrapper for the message when one applies.
fn classify_payload(
    ty: &Type,
    outer: &str,
    whole: &str,
    registry: &dyn Registry,
) -> Result<Payload, String> {
    let text = type_text(ty);
    match ty {
        Type::Tuple(t) if t.elems.is_empty() => Ok(Payload::Scalar(Scalar::Unit)),
        Type::Reference(_) => Err(refuse_return(
            whole,
            " (a borrow cannot outlive the call; return an owned `String`, `Vec<u8>` \
             or an `#[axiom_opaque]` value)",
        )),
        Type::Path(_) => {
            let (seg, name) = path_last(ty).ok_or_else(|| refuse_return(whole, ""))?;
            if let Some(s) = Scalar::from_name(&name) {
                if seg.arguments.is_none() {
                    return Ok(Payload::Scalar(s));
                }
            }
            match name.as_str() {
                "String" => Ok(Payload::Bytes),
                "Vec" => match single_generic(seg) {
                    Some(elem) if is_u8(elem) => Ok(Payload::Bytes),
                    Some(elem) if is_named(elem, "String") => Ok(Payload::Strs),
                    Some(elem) if scalar_of(elem).is_some() => {
                        Ok(Payload::Words(scalar_of(elem).unwrap()))
                    }
                    Some(elem) if is_named_vec(elem) => {
                        let (inner_seg, _) = path_last(elem).unwrap();
                        match single_generic(inner_seg).and_then(scalar_of) {
                            Some(sc) => Ok(Payload::WordLists(sc)),
                            None => Err(refuse_return(whole, ONE_LEVEL_RETURN)),
                        }
                    }
                    Some(elem) if matches!(path_last(elem), Some((_, n)) if is_two_words(&n)) => {
                        Err(refuse_return(whole, TWO_WORDS))
                    }
                    Some(elem) if is_bare_named(elem) => {
                        let (_, elem_name) = path_last(elem).unwrap();
                        match registry.lookup(&elem_name) {
                            Some(Named::Opaque) => Err(refuse_return(
                                whole,
                                " (a `Vec` of handles does not cross: an Axiom `Vec` holds \
                                 words; hold the collection in an `#[axiom_opaque]` type, \
                                 or hand the values back one at a time)",
                            )),
                            Some(Named::Record(fields)) => Ok(Payload::Records(RecordTy {
                                ty: elem.clone(),
                                name: elem_name,
                                fields,
                            })),
                            None => Ok(Payload::Records(RecordTy {
                                ty: elem.clone(),
                                name: elem_name,
                                fields: Vec::new(),
                            })),
                        }
                    }
                    _ => Err(refuse_return(
                        whole,
                        " (only `Vec<u8>`, `Vec<String>`, `Vec<T>` and `Vec<Vec<T>>` over a \
                         word scalar (i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char \
                         f64 f32), and `Vec<T>` over an `#[axiom_record]` cross directly; \
                         other collections must be serialised or held in an \
                         `#[axiom_opaque]` type)",
                    )),
                },
                "AxFn1" | "AxFn2" | "AxFn3" => Err(refuse_return(
                    whole,
                    " (a callback is borrowed from the Axiom caller for the call and \
                     cannot be handed back; answer a word)",
                )),
                "Option" | "Result" => {
                    if outer.is_empty() {
                        unreachable!("the outer classifier handles Option/Result")
                    }
                    Err(refuse_return(
                        whole,
                        &format!(
                            " (`{name}` cannot nest inside `{outer}`: the status word has \
                             three states, which `Result<Option<T>, E>` and \
                             `Option<Result<T, E>>` use up)"
                        ),
                    ))
                }
                "u128" | "i128" => Err(refuse_return(whole, TWO_WORDS)),
                "Box" | "Rc" | "Arc" => Err(refuse_return(
                    whole,
                    " (return the value itself, held in a type marked `#[axiom_opaque]`)",
                )),
                _ if !seg.arguments.is_none() => Err(refuse_return(
                    whole,
                    " (a type with generic arguments cannot cross: a shim is one symbol)",
                )),
                _ => match registry.lookup(&name) {
                    Some(Named::Record(fields)) => {
                        Ok(Payload::Record(RecordTy { ty: ty.clone(), name, fields }))
                    }
                    _ => Ok(Payload::Opaque(OpaqueTy { ty: ty.clone(), name })),
                },
            }
        }
        _ => Err(refuse_return(&text, "")),
    }
}

/// The word scalar `ty` names, if it is one (`()` excluded).
fn scalar_of(ty: &Type) -> Option<Scalar> {
    match path_last(ty) {
        Some((seg, name)) if seg.arguments.is_none() => Scalar::from_name(&name),
        _ => None,
    }
}

/// A bare path with no generic arguments that is not a word scalar or
/// a name the boundary refuses: a user type (record or handle).
fn is_bare_named(ty: &Type) -> bool {
    match path_last(ty) {
        Some((seg, name)) => {
            seg.arguments.is_none()
                && Scalar::from_name(&name).is_none()
                && name != "String"
                && !is_refused_name(&name)
        }
        None => false,
    }
}

/// `Vec<..>`, whatever the element.
fn is_named_vec(ty: &Type) -> bool {
    matches!(path_last(ty), Some((seg, name)) if name == "Vec" && single_generic(seg).is_some())
}

/// `Option<T>` / `Result<T, E>` at the top of a return type: the
/// wrapper's name and its payload type.
fn status_wrapper(ty: &Type) -> Option<(&'static str, Option<&Type>)> {
    let (seg, name) = path_last(ty)?;
    match name.as_str() {
        "Result" => Some(("Result", single_generic(seg))),
        "Option" => Some(("Option", single_generic(seg))),
        _ => None,
    }
}

/// Classify the return type (`None` = no `->`) with no knowledge of
/// named types: every bare named type is an opaque handle.
pub fn classify_return(ty: Option<&Type>) -> Result<Ret, String> {
    classify_return_with(ty, &NoRecords)
}

/// Classify the return type, consulting `registry` for a bare named
/// type (a record's fields, else an opaque handle).
pub fn classify_return_with(ty: Option<&Type>, registry: &dyn Registry) -> Result<Ret, String> {
    let Some(ty) = ty else { return Ok(Ret::Scalar(Scalar::Unit)) };
    let whole = type_text(ty);
    if let Some((outer, inner)) = status_wrapper(ty) {
        let inner = inner.ok_or_else(|| {
            refuse_return(
                &whole,
                if outer == "Result" {
                    " (`Result` needs its `Ok` type written out)"
                } else {
                    " (`Option` needs its payload type written out)"
                },
            )
        })?;
        // One level of nesting: `Result<Option<T>, E>` and
        // `Option<Result<T, E>>` are the three states the status word
        // has (0, 1, 2); the same wrapper twice, or a third level, is
        // refused by `classify_payload` with the reason.
        let (ret, payload_ty, wrapper) = match status_wrapper(inner) {
            Some((mid, Some(payload))) if mid != outer => {
                let wrapper = format!("{outer}<{mid}<..>>");
                (if outer == "Result" { "ResultOption" } else { "OptionResult" }, payload, wrapper)
            }
            Some((mid, None)) => {
                return Err(refuse_return(
                    &whole,
                    &format!(" (`{mid}` needs its payload type written out)"),
                ))
            }
            _ => (outer, inner, outer.to_string()),
        };
        let p = classify_payload(payload_ty, &wrapper, &whole, registry)?;
        if matches!(p, Payload::Scalar(Scalar::Unit)) && matches!(ret, "Option" | "ResultOption") {
            return Err(refuse_return(&whole, " (`Option<()>` is a `bool`; return one)"));
        }
        return Ok(match ret {
            "Result" => Ret::Result(p),
            "Option" => Ret::Option(p),
            "ResultOption" => Ret::ResultOption(p),
            _ => Ret::OptionResult(p),
        });
    }
    Ok(match classify_payload(ty, "", &whole, registry)? {
        Payload::Scalar(s) => Ret::Scalar(s),
        Payload::Bytes => Ret::Bytes,
        Payload::Words(s) => Ret::Words(s),
        Payload::WordLists(s) => Ret::WordLists(s),
        Payload::Strs => Ret::Strs,
        Payload::Opaque(o) => Ret::Opaque(o),
        Payload::Record(r) => Ret::Record(r),
        Payload::Records(r) => Ret::Records(r),
    })
}

/// The bare named types a signature crosses by value, in a slice or a
/// `Vec`, or hands back: the ones whose kind (record or handle) the
/// macro learns from their companion macros. Each name once, in order
/// of first use.
pub fn named_types(params: &[Param], ret: &Ret) -> Vec<Type> {
    let mut out: Vec<Type> = Vec::new();
    let mut push = |ty: &Type| {
        if !out.iter().any(|t| t == ty) {
            out.push(ty.clone());
        }
    };
    for p in params {
        if let Param::Record(r) | Param::Records(r) = p {
            push(&r.ty);
        }
    }
    let payload = match ret {
        Ret::Opaque(o) => Some(Payload::Opaque(o.clone())),
        Ret::Record(r) => Some(Payload::Record(r.clone())),
        Ret::Records(r) => Some(Payload::Records(r.clone())),
        other => other.status_payload().cloned(),
    };
    match payload {
        Some(Payload::Opaque(o)) => push(&o.ty),
        Some(Payload::Record(r)) | Some(Payload::Records(r)) => push(&r.ty),
        _ => {}
    }
    out
}

/// The record types a signature crosses without their field lists
/// filled in (the macro's first pass, or a bindgen source root with no
/// `#[axiom_record]` of that name): each such name once.
pub fn unresolved_records(params: &[Param], ret: &Ret) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut note = |r: &RecordTy| {
        if !r.is_resolved() && !out.contains(&r.name) {
            out.push(r.name.clone());
        }
    };
    for p in params {
        if let Param::Record(r) | Param::Records(r) = p {
            note(r);
        }
    }
    match ret {
        Ret::Record(r) | Ret::Records(r) => note(r),
        other => {
            if let Some(Payload::Record(r)) | Some(Payload::Records(r)) = other.status_payload() {
                note(r);
            }
        }
    }
    out
}

// ---------------------------------------------------------------------
// Signature descriptors
// ---------------------------------------------------------------------
//
// Beside every shim `axffi_x` the macro exports a no-op function whose
// NAME encodes the shim's shape: `axffi_x__sig_<params>_<ret>`. The
// driver derives the same string from the Axiom `extern` item's
// declared type and refuses a mismatch (AX4005) before the link, where
// a wrong arity used to be a silent wrong answer. One character per
// word the shim takes, in order - the out-cell word included - then
// `_`, then one for the word it answers.

/// The descriptor tag of one scalar word.
fn scalar_tag(s: Scalar) -> char {
    if s.is_float() { 'f' } else { 'i' }
}

/// The descriptor tags of a parameter: one character per word it
/// crosses as (a record: one per field).
pub fn param_tags(p: &Param) -> String {
    match p {
        Param::Scalar(s) => scalar_tag(*s).to_string(),
        Param::Opaque { .. }
        | Param::Words(_)
        | Param::MutWords(_)
        | Param::WordLists(_)
        | Param::Strs
        | Param::Records(_) => "i".to_string(),
        Param::Str | Param::Bytes => "s".to_string(),
        Param::Callback(_) => "c".to_string(),
        Param::Record(r) => r.fields.iter().map(|f| scalar_tag(f.scalar)).collect(),
    }
}

/// The descriptor tag of the word the shim answers. Every protocol
/// return (bytes, a status, a boxed address) is a plain word; only a
/// float answers its bits.
pub fn return_tag(r: &Ret) -> char {
    match r {
        Ret::Scalar(s) if s.is_float() => 'f',
        _ => 'i',
    }
}

/// `<params>_<ret>`: the tags of the shim's words in order, the
/// out-cell word included when the return takes one.
///
/// ```
/// # use axiom_ffi_classify::*;
/// assert_eq!(sig_tags(&[Param::Str], &Ret::Bytes), "si_i");
/// assert_eq!(sig_tags(&[], &Ret::Scalar(Scalar::I64)), "_i");
/// ```
pub fn sig_tags(params: &[Param], ret: &Ret) -> String {
    let mut out = String::with_capacity(params.len() + 3);
    for p in params {
        out.push_str(&param_tags(p));
    }
    if ret.needs_cell() {
        out.push('i');
    }
    out.push('_');
    out.push(return_tag(ret));
    out
}

/// The descriptor symbol of the shim `symbol`: `axffi_add__sig_ii_i`,
/// `axffi_abi_probe__sig__i` for a nullary shim.
pub fn sig_symbol(symbol: &str, params: &[Param], ret: &Ret) -> String {
    format!("{symbol}__sig_{}", sig_tags(params, ret))
}

// ---------------------------------------------------------------------
// Attributes
// ---------------------------------------------------------------------

/// The UTF-8 policy for `&str` parameters.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Utf8 {
    /// Invalid bytes abort an infallible shim and `Err` a fallible one.
    Strict,
    /// `String::from_utf8_lossy`.
    Lossy,
}

/// `#[axiom_export(symbol = "...", utf8 = "lossy")]`, parsed.
#[derive(Clone, Debug, Default)]
pub struct ExportAttr {
    pub symbol: Option<String>,
    pub utf8: Option<Utf8>,
}

impl ExportAttr {
    pub fn utf8(&self) -> Utf8 {
        self.utf8.unwrap_or(Utf8::Strict)
    }
}

/// `#[axiom_opaque(symbol = "...")]`, parsed.
#[derive(Clone, Debug, Default)]
pub struct OpaqueAttr {
    pub symbol: Option<String>,
}

/// A refused attribute: the offending meta (for a span) and the message.
pub struct AttrError {
    pub meta: Option<Meta>,
    pub message: String,
}

fn string_value(m: &Meta, key: &str, what: &str) -> Result<String, AttrError> {
    let Meta::NameValue(nv) = m else {
        return Err(AttrError {
            meta: Some(m.clone()),
            message: format!("`{key}` takes a value: `{key} = \"{what}\"`"),
        });
    };
    if let syn::Expr::Lit(syn::ExprLit { lit: syn::Lit::Str(s), .. }) = &nv.value {
        Ok(s.value())
    } else {
        Err(AttrError {
            meta: Some(m.clone()),
            message: format!("`{key}` must be a string literal: `{key} = \"{what}\"`"),
        })
    }
}

fn is_c_ident(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c == '_' || c.is_ascii_alphabetic() => {}
        _ => return false,
    }
    chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
}

/// Parse the `key = "value"` list of `#[axiom_export(...)]`.
pub fn parse_export_attr<'a, I>(metas: I) -> Result<ExportAttr, AttrError>
where
    I: IntoIterator<Item = &'a Meta>,
{
    let mut out = ExportAttr::default();
    for m in metas {
        let key = m.path().get_ident().map(|i| i.to_string()).unwrap_or_default();
        match key.as_str() {
            "symbol" => {
                let v = string_value(m, "symbol", "axffi_name")?;
                if !is_c_ident(&v) {
                    return Err(AttrError {
                        meta: Some(m.clone()),
                        message: format!(
                            "`symbol = \"{v}\"` is not a linker symbol: use letters, digits \
                             and `_`, not starting with a digit"
                        ),
                    });
                }
                out.symbol = Some(v);
            }
            "utf8" => {
                let v = string_value(m, "utf8", "lossy")?;
                out.utf8 = Some(match v.as_str() {
                    "lossy" => Utf8::Lossy,
                    "strict" => Utf8::Strict,
                    other => {
                        return Err(AttrError {
                            meta: Some(m.clone()),
                            message: format!(
                                "`utf8 = \"{other}\"` is not a policy; the policies are \
                                 `\"lossy\"` (replace invalid sequences) and `\"strict\"` \
                                 (the default: abort, or `Err` from a `Result` function)"
                            ),
                        })
                    }
                });
            }
            other => {
                let shown = if other.is_empty() { "<non-identifier>".to_string() } else { other.to_string() };
                return Err(AttrError {
                    meta: Some(m.clone()),
                    message: format!(
                        "unknown `axiom_export` key `{shown}`; the keys are {EXPORT_KEYS}"
                    ),
                });
            }
        }
    }
    Ok(out)
}

/// Parse the `key = "value"` list of `#[axiom_opaque(...)]`.
pub fn parse_opaque_attr<'a, I>(metas: I) -> Result<OpaqueAttr, AttrError>
where
    I: IntoIterator<Item = &'a Meta>,
{
    let mut out = OpaqueAttr::default();
    for m in metas {
        let key = m.path().get_ident().map(|i| i.to_string()).unwrap_or_default();
        match key.as_str() {
            "symbol" => {
                let v = string_value(m, "symbol", "stem")?;
                if !is_c_ident(&v) {
                    return Err(AttrError {
                        meta: Some(m.clone()),
                        message: format!(
                            "`symbol = \"{v}\"` is not a symbol stem: use letters, digits \
                             and `_`, not starting with a digit"
                        ),
                    });
                }
                out.symbol = Some(v);
            }
            other => {
                let shown = if other.is_empty() { "<non-identifier>".to_string() } else { other.to_string() };
                return Err(AttrError {
                    meta: Some(m.clone()),
                    message: format!(
                        "unknown `axiom_opaque` key `{shown}`; the only key is {OPAQUE_KEYS}"
                    ),
                });
            }
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------
// Names
// ---------------------------------------------------------------------

/// The linker symbol of an exported function's shim.
pub fn export_symbol(rust_name: &str, attr: &ExportAttr) -> String {
    attr.symbol.clone().unwrap_or_else(|| format!("axffi_{rust_name}"))
}

/// The symbol stem of an opaque type: `HttpClient` -> `http_client`.
pub fn opaque_stem(type_name: &str, attr: &OpaqueAttr) -> String {
    attr.symbol.clone().unwrap_or_else(|| snake_case(type_name))
}

/// `axffi_<stem>_drop`: the null-checked destructor.
pub fn drop_symbol(stem: &str) -> String {
    format!("axffi_{stem}_drop")
}

/// `axffi_<stem>_drop_fn`: answers the destructor's address.
pub fn drop_fn_symbol(stem: &str) -> String {
    format!("axffi_{stem}_drop_fn")
}

/// `__axiom_type_<Name>`: the hidden module `#[axiom_opaque]` and
/// `#[axiom_record]` declare beside the type, holding its COMPANION
/// MACRO - a `macro_rules!` named exactly like the type that appends
/// `@opaque Name` / `@record Name { field: T, .. }` to a callback
/// invocation. `#[axiom_export]` cannot see another item's fields, so
/// a shim that takes a record by value, or answers a bare named type,
/// expands through the companion (re-exported into the type's module
/// with `pub(crate) use`, so a `use` of the type imports it too).
pub fn companion_module(type_name: &str) -> String {
    format!("__axiom_type_{type_name}")
}

/// `HttpClient` -> `http_client`, `SHA256` -> `sha256`, `Counter` -> `counter`.
pub fn snake_case(name: &str) -> String {
    let chars: Vec<char> = name.chars().collect();
    let mut out = String::with_capacity(name.len() + 4);
    for (i, &c) in chars.iter().enumerate() {
        if c.is_uppercase() {
            let prev_lower = i > 0 && (chars[i - 1].is_lowercase() || chars[i - 1].is_ascii_digit());
            let next_lower = i + 1 < chars.len() && chars[i + 1].is_lowercase();
            let prev_upper = i > 0 && chars[i - 1].is_uppercase();
            if i > 0 && (prev_lower || (prev_upper && next_lower)) {
                out.push('_');
            }
            out.extend(c.to_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

/// `sha256_hex` -> `sha256Hex`. Axiom's stdlib is camelCase throughout.
pub fn camel_case(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut up = false;
    for c in s.chars() {
        if c == '_' {
            up = true
        } else if up {
            out.extend(c.to_uppercase());
            up = false
        } else {
            out.push(c)
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ty(s: &str) -> Type {
        syn::parse_str(s).unwrap()
    }

    #[test]
    fn scalars_and_borrows() {
        assert!(matches!(classify_param(&ty("i64")), Ok(Param::Scalar(Scalar::I64))));
        assert!(matches!(classify_param(&ty("u8")), Ok(Param::Scalar(Scalar::U8))));
        assert!(matches!(classify_param(&ty("&str")), Ok(Param::Str)));
        assert!(matches!(classify_param(&ty("&[u8]")), Ok(Param::Bytes)));
        assert!(matches!(classify_param(&ty("&Counter")), Ok(Param::Opaque { mutable: false, .. })));
        assert!(matches!(classify_param(&ty("&mut Counter")), Ok(Param::Opaque { mutable: true, .. })));
        assert!(matches!(classify_param(&ty("&[i64]")), Ok(Param::Words(Scalar::I64))));
        assert!(matches!(classify_param(&ty("AxFn1")), Ok(Param::Callback(1))));
        assert!(matches!(classify_param(&ty("axiom_ffi::AxFn2")), Ok(Param::Callback(2))));
        assert!(matches!(classify_param(&ty("AxFn3")), Ok(Param::Callback(3))));
    }

    #[test]
    fn slices_over_every_word_scalar() {
        for (t, s) in [
            ("&[i32]", Scalar::I32),
            ("&[i16]", Scalar::I16),
            ("&[i8]", Scalar::I8),
            ("&[u32]", Scalar::U32),
            ("&[u16]", Scalar::U16),
            ("&[usize]", Scalar::Usize),
            ("&[isize]", Scalar::Isize),
            ("&[bool]", Scalar::Bool),
            ("&[f64]", Scalar::F64),
            ("&[f32]", Scalar::F32),
        ] {
            assert!(matches!(classify_param(&ty(t)), Ok(Param::Words(x)) if x == s), "{t}");
        }
        // `&[u8]` stays the byte view of a String, not a Vec of words.
        assert!(matches!(classify_param(&ty("&[u8]")), Ok(Param::Bytes)));
        assert!(matches!(classify_param(&ty("&[&str]")), Ok(Param::Strs)));
        for (t, s) in [("Vec<f64>", Scalar::F64), ("Vec<bool>", Scalar::Bool), ("Vec<u16>", Scalar::U16), ("Vec<f32>", Scalar::F32)] {
            assert!(matches!(classify_return(Some(&ty(t))), Ok(Ret::Words(x)) if x == s), "{t}");
        }
        assert!(matches!(classify_return(Some(&ty("Result<Vec<f32>, String>"))), Ok(Ret::Result(Payload::Words(Scalar::F32)))));
        assert!(matches!(classify_return(Some(&ty("Option<Vec<i8>>"))), Ok(Ret::Option(Payload::Words(Scalar::I8)))));
    }

    #[test]
    fn refused_slices_and_callbacks_say_why() {
        let e = classify_param(&ty("&[String]")).err().unwrap();
        assert!(e.contains("take `&[&str]`"), "{e}");
        let e = classify_param(&ty("Vec<String>")).err().unwrap();
        assert!(e.contains("`&[&str]`"), "{e}");
        let e = classify_param(&ty("&[u128]")).err().unwrap();
        assert!(e.contains("split it into two `u64`s"), "{e}");
        let e = classify_param(&ty("&[Vec<i64>]")).err().unwrap();
        assert!(e.contains("only `&[u8]`, `&[&str]`, `&[T]` and `&[&[T]]`"), "{e}");
        let e = classify_param_with(&ty("&[Counter]"), &Table).err().unwrap();
        assert!(e.contains("a slice of handles does not cross"), "{e}");
        let e = classify_param(&ty("&AxFn1")).err().unwrap();
        assert!(e.contains("take it by value"), "{e}");
        let e = classify_return(Some(&ty("AxFn1"))).err().unwrap();
        assert!(e.contains("cannot be handed back"), "{e}");
        let e = classify_return(Some(&ty("Option<AxFn2>"))).err().unwrap();
        assert!(e.contains("cannot be handed back"), "{e}");
        let e = classify_return(Some(&ty("Vec<u128>"))).err().unwrap();
        assert!(e.contains("split it into two `u64`s"), "{e}");
        let e = classify_return(Some(&ty("Vec<(i64, i64)>"))).err().unwrap();
        assert!(e.contains("`Vec<T>` over an `#[axiom_record]` cross directly"), "{e}");
        let e = classify_return_with(Some(&ty("Vec<Counter>")), &Table).err().unwrap();
        assert!(e.contains("a `Vec` of handles does not cross"), "{e}");
        let e = classify_return_with(Some(&ty("Option<Vec<Counter>>")), &Table).err().unwrap();
        assert!(e.contains("a `Vec` of handles does not cross"), "{e}");
    }

    #[test]
    fn char_and_u64_are_words() {
        assert!(matches!(classify_param(&ty("char")), Ok(Param::Scalar(Scalar::Char))));
        assert!(matches!(classify_param(&ty("u64")), Ok(Param::Scalar(Scalar::U64))));
        assert!(matches!(classify_return(Some(&ty("char"))), Ok(Ret::Scalar(Scalar::Char))));
        assert!(matches!(classify_return(Some(&ty("u64"))), Ok(Ret::Scalar(Scalar::U64))));
        assert!(matches!(classify_param(&ty("&[char]")), Ok(Param::Words(Scalar::Char))));
        assert!(matches!(classify_param(&ty("&[u64]")), Ok(Param::Words(Scalar::U64))));
        assert!(matches!(classify_return(Some(&ty("Vec<char>"))), Ok(Ret::Words(Scalar::Char))));
        assert!(matches!(classify_return(Some(&ty("Option<Vec<u64>>"))), Ok(Ret::Option(Payload::Words(Scalar::U64)))));
        assert!(matches!(classify_return(Some(&ty("Result<char, String>"))), Ok(Ret::Result(Payload::Scalar(Scalar::Char)))));
        assert_eq!(Scalar::Char.axiom_type(), "Char");
        assert_eq!(Scalar::U64.axiom_type(), "Int");
        assert!(!Scalar::U64.is_narrow_int());
        assert!(Scalar::U64.is_word_sized() && Scalar::F64.is_word_sized() && Scalar::I64.is_word_sized());
        assert!(!Scalar::Char.is_word_sized() && !Scalar::U32.is_word_sized());
        // Two words fit nowhere, and the message says what to do.
        for bad in ["u128", "i128"] {
            let e = classify_param(&ty(bad)).err().unwrap();
            assert!(e.contains("split it into two `u64`s"), "{e}");
            let e = classify_return(Some(&ty(bad))).err().unwrap();
            assert!(e.contains("split it into two `u64`s"), "{e}");
        }
    }

    #[test]
    fn records_in_vecs() {
        // `&[Point]` and `Vec<Point>` resolve through the registry, and
        // are unresolved records without one (the macro's first pass).
        match classify_param_with(&ty("&[Point]"), &Table).unwrap() {
            Param::Records(r) => {
                assert_eq!(r.name, "Point");
                assert_eq!(r.arity(), 2);
            }
            other => panic!("{other:?}"),
        }
        match classify_param(&ty("&[geom::Point]")).unwrap() {
            Param::Records(r) => assert!(!r.is_resolved()),
            other => panic!("{other:?}"),
        }
        match classify_return_with(Some(&ty("Vec<Point>")), &Table).unwrap() {
            Ret::Records(r) => assert_eq!(r.arity(), 2),
            other => panic!("{other:?}"),
        }
        match classify_return(Some(&ty("Vec<Point>"))).unwrap() {
            Ret::Records(r) => assert!(!r.is_resolved()),
            other => panic!("{other:?}"),
        }
        assert!(matches!(classify_return_with(Some(&ty("Result<Vec<Point>, String>")), &Table), Ok(Ret::Result(Payload::Records(_)))));
        assert!(matches!(classify_return_with(Some(&ty("Option<Vec<Point>>")), &Table), Ok(Ret::Option(Payload::Records(_)))));
        // The cell of a record list is the two-word (ptr, n) pair.
        assert_eq!(classify_return_with(Some(&ty("Vec<Point>")), &Table).unwrap().cell_words(), 2);
        // Named types and unresolved ones are reported from every position.
        let ps = classify_param(&ty("&[Point]")).unwrap();
        let ret = classify_return(Some(&ty("Option<Vec<Line>>"))).unwrap();
        let names: Vec<String> = named_types(&[ps.clone()], &ret).iter().map(type_text).collect();
        assert_eq!(names, vec!["Point", "Line"]);
        assert_eq!(unresolved_records(&[ps], &ret), vec!["Point", "Line"]);
        let resolved = classify_param_with(&ty("&[Point]"), &Table).unwrap();
        assert!(unresolved_records(&[resolved], &Ret::Bytes).is_empty());
    }

    #[test]
    fn nested_vecs() {
        assert!(matches!(classify_return(Some(&ty("Vec<Vec<i64>>"))), Ok(Ret::WordLists(Scalar::I64))));
        assert!(matches!(classify_return(Some(&ty("Vec<Vec<f32>>"))), Ok(Ret::WordLists(Scalar::F32))));
        assert!(matches!(classify_return(Some(&ty("Vec<Vec<char>>"))), Ok(Ret::WordLists(Scalar::Char))));
        assert!(matches!(classify_return(Some(&ty("Result<Vec<Vec<u64>>, String>"))), Ok(Ret::Result(Payload::WordLists(Scalar::U64)))));
        assert!(matches!(classify_param(&ty("&[&[i64]]")), Ok(Param::WordLists(Scalar::I64))));
        assert!(matches!(classify_param(&ty("&[&[bool]]")), Ok(Param::WordLists(Scalar::Bool))));
        for bad in ["Vec<Vec<String>>", "Vec<Vec<Point>>", "Vec<Vec<Vec<i64>>>", "Option<Vec<Vec<String>>>"] {
            let e = classify_return(Some(&ty(bad))).err().expect(bad);
            assert!(e.contains("one level of word scalars"), "{bad}: {e}");
            assert!(e.contains(RETURN_TYPES), "{e}");
        }
        for bad in ["&[&[&str]]", "&[&[Point]]", "&[&[&[i64]]]"] {
            let e = classify_param(&ty(bad)).err().expect(bad);
            assert!(e.contains("one level of word scalars"), "{bad}: {e}");
            assert!(e.contains(PARAM_TYPES), "{e}");
        }
        let e = classify_param(&ty("&[&mut [i64]]")).err().unwrap();
        assert!(e.contains("take `&[&[T]]`"), "{e}");
    }

    #[test]
    fn mutable_slices() {
        assert!(matches!(classify_param(&ty("&mut [i64]")), Ok(Param::MutWords(Scalar::I64))));
        assert!(matches!(classify_param(&ty("&mut [f64]")), Ok(Param::MutWords(Scalar::F64))));
        assert!(matches!(classify_param(&ty("&mut [u64]")), Ok(Param::MutWords(Scalar::U64))));
        for bad in ["&mut [i32]", "&mut [u8]", "&mut [bool]", "&mut [char]", "&mut [f32]", "&mut [Point]", "&mut [&str]"] {
            let e = classify_param(&ty(bad)).err().expect(bad);
            assert!(e.contains("take `&[T]` and return a `Vec<T>`"), "{bad}: {e}");
            assert!(e.contains("could not be written back as the same words"), "{e}");
        }
        assert_eq!(sig_tags(&[Param::MutWords(Scalar::F64)], &Ret::Scalar(Scalar::Unit)), "i_i");
    }

    #[test]
    fn nested_fallible() {
        assert!(matches!(classify_return(Some(&ty("Result<Option<i64>, String>"))), Ok(Ret::ResultOption(Payload::Scalar(Scalar::I64)))));
        assert!(matches!(classify_return(Some(&ty("Option<Result<String, E>>"))), Ok(Ret::OptionResult(Payload::Bytes))));
        assert!(matches!(classify_return_with(Some(&ty("Result<Option<Point>, E>")), &Table), Ok(Ret::ResultOption(Payload::Record(_)))));
        assert!(matches!(classify_return_with(Some(&ty("Option<Result<Counter, E>>")), &Table), Ok(Ret::OptionResult(Payload::Opaque(_)))));
        assert!(matches!(classify_return(Some(&ty("Option<Result<(), E>>"))), Ok(Ret::OptionResult(Payload::Scalar(Scalar::Unit)))));
        let r = classify_return_with(Some(&ty("Result<Option<Point>, E>")), &Table).unwrap();
        assert!(r.is_result() && r.needs_cell());
        assert_eq!(r.cell_words(), 2);
        assert_eq!(sig_tags(&[], &r), "i_i");
        // Deeper nesting, and the same wrapper twice, are refused: the
        // status word has three states.
        for bad in [
            "Result<Option<Option<i64>>, E>",
            "Option<Result<Option<i64>, E>>",
            "Result<Result<i64, E>, E>",
            "Option<Option<i64>>",
            "Result<Option<Result<i64, E>>, E>",
        ] {
            let e = classify_return(Some(&ty(bad))).err().expect(bad);
            assert!(e.contains("three states"), "{bad}: {e}");
            assert!(e.contains(RETURN_TYPES), "{e}");
        }
        let e = classify_return(Some(&ty("Result<Option<()>, E>"))).err().unwrap();
        assert!(e.contains("`Option<()>` is a `bool`"), "{e}");
    }

    #[test]
    fn refusals_list_the_set() {
        for bad in ["u128", "String", "Option<i64>", "&mut str", "&i64", "(i64, i64)", "&[String]", "&mut [i32]", "&[&[&str]]", "&AxFn1", "Wrapper<i64>"] {
            let e = classify_param(&ty(bad)).err().expect(bad);
            assert!(e.contains(PARAM_TYPES), "{e}");
        }
        for bad in ["i128", "Vec<u128>", "Vec<Vec<String>>", "Result<Option<Option<i64>>, String>", "&str", "Option<()>", "AxFn1"] {
            let e = classify_return(Some(&ty(bad))).err().expect(bad);
            assert!(e.contains(RETURN_TYPES), "{e}");
        }
    }

    /// A registry with one record `Point { x: i64, y: f64 }` and one
    /// opaque `Counter`.
    struct Table;

    impl Registry for Table {
        fn lookup(&self, name: &str) -> Option<Named> {
            match name {
                "Point" => Some(Named::Record(vec![
                    RecordField { name: "x".into(), scalar: Scalar::I64 },
                    RecordField { name: "y".into(), scalar: Scalar::F64 },
                ])),
                "Counter" => Some(Named::Opaque),
                _ => None,
            }
        }
    }

    #[test]
    fn records() {
        // Unresolved without a registry: a by-value name is a record
        // whose fields are not yet known; a returned name is opaque.
        match classify_param(&ty("Point")).unwrap() {
            Param::Record(r) => {
                assert_eq!(r.name, "Point");
                assert!(!r.is_resolved());
            }
            other => panic!("{other:?}"),
        }
        assert!(matches!(classify_return(Some(&ty("Point"))), Ok(Ret::Opaque(_))));
        // Resolved through the registry.
        match classify_param_with(&ty("geom::Point"), &Table).unwrap() {
            Param::Record(r) => {
                assert_eq!(r.arity(), 2);
                assert_eq!(r.fields[1].name, "y");
                assert_eq!(r.fields[1].scalar, Scalar::F64);
            }
            other => panic!("{other:?}"),
        }
        assert!(matches!(classify_return_with(Some(&ty("Point")), &Table), Ok(Ret::Record(_))));
        assert!(matches!(classify_return_with(Some(&ty("Result<Point, String>")), &Table), Ok(Ret::Result(Payload::Record(_)))));
        assert!(matches!(classify_return_with(Some(&ty("Option<Point>")), &Table), Ok(Ret::Option(Payload::Record(_)))));
        assert!(matches!(classify_return_with(Some(&ty("Counter")), &Table), Ok(Ret::Opaque(_))));
        assert!(matches!(classify_param_with(&ty("&Counter"), &Table), Ok(Param::Opaque { .. })));
        // An opaque type by value, a record by reference: each says
        // which way to take it.
        let e = classify_param_with(&ty("Counter"), &Table).err().unwrap();
        assert!(e.contains("take `&T` or `&mut T`"), "{e}");
        let e = classify_param_with(&ty("&Point"), &Table).err().unwrap();
        assert!(e.contains("take it by value"), "{e}");
        // The cell of a record result holds its arity, never fewer than two.
        let one = Ret::Record(RecordTy { ty: ty("One"), name: "One".into(), fields: vec![RecordField { name: "a".into(), scalar: Scalar::I64 }] });
        assert_eq!(one.cell_words(), 2);
        let three = classify_return_with(Some(&ty("Point")), &Table).unwrap();
        assert_eq!(three.cell_words(), 2);
        assert_eq!(Ret::Bytes.cell_words(), 2);
        assert!(three.needs_cell());
        assert!(!Ret::Opaque(classify_opaque()).needs_cell());
    }

    #[test]
    fn record_fields() {
        let fields = |src: &str| -> Result<Vec<RecordField>, String> {
            let s: syn::ItemStruct = syn::parse_str(src).unwrap();
            let named: Vec<(String, Type)> = s
                .fields
                .iter()
                .map(|f| (f.ident.as_ref().unwrap().to_string(), f.ty.clone()))
                .collect();
            classify_record_fields(named.iter().map(|(n, t)| (n.as_str(), t)))
        };
        let ok = fields("struct P { a: i64, b: f32, c: bool, d: u8, e: usize, f: char, g: u64 }").unwrap();
        assert_eq!(ok.len(), 7);
        assert_eq!(ok[1].scalar, Scalar::F32);
        assert_eq!(ok[3].name, "d");
        assert_eq!(ok[5].scalar, Scalar::Char);
        assert_eq!(ok[6].scalar, Scalar::U64);
        for (src, why) in [
            ("struct P { s: String }", "is not a word scalar (a record is its words"),
            ("struct P { p: Inner }", "a nested record or an opaque handle does not cross as a field"),
            ("struct P { v: Vec<i64> }", "a collection is not a word"),
            ("struct P { r: &'static str }", "a borrow cannot cross as a field"),
            ("struct P { n: u128 }", "split it into two `u64`s"),
            ("struct P { }", "at least one field"),
        ] {
            let e = fields(src).err().expect(src);
            assert!(e.contains(why), "{src}: {e}");
            if !src.ends_with("{ }") {
                assert!(e.contains(RECORD_FIELD_TYPES), "{e}");
            }
        }
    }

    #[test]
    fn named_types_once_each() {
        let point = classify_param(&ty("Point")).unwrap();
        let line = classify_param(&ty("Line")).unwrap();
        let ret = classify_return(Some(&ty("Option<Point>"))).unwrap();
        let names: Vec<String> = named_types(&[point.clone(), line, point], &ret)
            .iter()
            .map(type_text)
            .collect();
        assert_eq!(names, vec!["Point", "Line"]);
        assert!(named_types(&[Param::Str], &Ret::Bytes).is_empty());
        assert_eq!(companion_module("Point"), "__axiom_type_Point");
    }

    #[test]
    fn returns() {
        assert!(matches!(classify_return(None), Ok(Ret::Scalar(Scalar::Unit))));
        assert!(matches!(classify_return(Some(&ty("()"))), Ok(Ret::Scalar(Scalar::Unit))));
        assert!(matches!(classify_return(Some(&ty("String"))), Ok(Ret::Bytes)));
        assert!(matches!(classify_return(Some(&ty("Vec<u8>"))), Ok(Ret::Bytes)));
        assert!(matches!(classify_return(Some(&ty("Counter"))), Ok(Ret::Opaque(_))));
        assert!(matches!(
            classify_return(Some(&ty("Result<Counter, String>"))),
            Ok(Ret::Result(Payload::Opaque(_)))
        ));
        assert!(matches!(classify_return(Some(&ty("Option<i64>"))), Ok(Ret::Option(Payload::Scalar(Scalar::I64)))));
        assert!(matches!(classify_return(Some(&ty("Result<(), E>"))), Ok(Ret::Result(Payload::Scalar(Scalar::Unit)))));
        assert!(matches!(classify_return(Some(&ty("Vec<i64>"))), Ok(Ret::Words(Scalar::I64))));
        assert!(matches!(classify_return(Some(&ty("Vec<String>"))), Ok(Ret::Strs)));
        assert!(matches!(classify_return(Some(&ty("Result<Vec<i64>, String>"))), Ok(Ret::Result(Payload::Words(Scalar::I64)))));
        assert!(matches!(classify_return(Some(&ty("Option<Vec<String>>"))), Ok(Ret::Option(Payload::Strs))));
    }

    #[test]
    fn descriptors() {
        let i = Param::Scalar(Scalar::I64);
        let f = Param::Scalar(Scalar::F64);
        let b = Param::Scalar(Scalar::Bool);
        let narrow = Param::Scalar(Scalar::U8);
        let opaque = classify_param(&ty("&Counter")).unwrap();
        assert_eq!(sig_symbol("axffi_add", &[i.clone(), i.clone()], &Ret::Scalar(Scalar::I64)), "axffi_add__sig_ii_i");
        assert_eq!(sig_symbol("axffi_abi_probe", &[], &Ret::Scalar(Scalar::I64)), "axffi_abi_probe__sig__i");
        // The out-cell word of a bytes/fallible shim is an `i` parameter;
        // a unit, String, Result or Option result answers `i`.
        assert_eq!(sig_symbol("axffi_shout", &[Param::Str], &Ret::Bytes), "axffi_shout__sig_si_i");
        assert_eq!(sig_tags(&[Param::Bytes], &Ret::Result(Payload::Scalar(Scalar::F64))), "si_i");
        assert_eq!(sig_tags(&[i.clone()], &Ret::Option(Payload::Opaque(classify_opaque()))), "ii_i");
        assert_eq!(sig_tags(&[i.clone()], &Ret::Scalar(Scalar::Unit)), "i_i");
        // Floats carry their bits; everything else is a word.
        assert_eq!(sig_tags(&[f.clone(), f], &Ret::Scalar(Scalar::F64)), "ff_f");
        assert_eq!(sig_tags(&[b, narrow, opaque], &Ret::Scalar(Scalar::F32)), "iii_f");
        // Handles answer their address: a word. Callbacks are `c`, a
        // `Vec` parameter is its handle word.
        assert_eq!(sig_tags(&[i.clone()], &Ret::Opaque(classify_opaque())), "i_i");
        assert_eq!(sig_tags(&[Param::Callback(1), i.clone()], &Ret::Scalar(Scalar::I64)), "ci_i");
        assert_eq!(sig_tags(&[Param::Callback(2), i.clone(), i.clone(), i.clone()], &Ret::Scalar(Scalar::I64)), "ciii_i");
        assert_eq!(sig_tags(&[Param::Words(Scalar::I64)], &Ret::Scalar(Scalar::I64)), "i_i");
        assert_eq!(sig_tags(&[Param::Words(Scalar::F64), Param::Strs], &Ret::Words(Scalar::Bool)), "iii_i");
        assert_eq!(sig_tags(&[i.clone()], &Ret::Words(Scalar::I64)), "ii_i");
        assert_eq!(sig_tags(&[Param::Str], &Ret::Strs), "si_i");
        // A record parameter is one tag per field (`f` for a float
        // field); a record result is a cell word and a unit answer.
        let point = match classify_param_with(&ty("Point"), &Table).unwrap() {
            Param::Record(r) => r,
            _ => unreachable!(),
        };
        assert_eq!(sig_tags(&[Param::Record(point.clone()), i.clone()], &Ret::Scalar(Scalar::F64)), "ifi_f");
        assert_eq!(sig_tags(&[], &Ret::Record(point.clone())), "i_i");
        assert_eq!(sig_tags(&[b2()], &Ret::Result(Payload::Record(point.clone()))), "ii_i");
        assert_eq!(sig_symbol("axffi_point_scale", &[Param::Record(point), i], &Ret::Option(Payload::Record(classify_point()))), "axffi_point_scale__sig_ifii_i");
        // A char or u64 is a word; a record slice, a nested Vec and a
        // mutable slice are each a Vec handle; a nested fallible result
        // is a cell and a status.
        let c = Param::Scalar(Scalar::Char);
        let u = Param::Scalar(Scalar::U64);
        assert_eq!(sig_tags(&[c, u], &Ret::Scalar(Scalar::Char)), "ii_i");
        assert_eq!(sig_tags(&[Param::Records(classify_point()), b2()], &Ret::Records(classify_point())), "iii_i");
        assert_eq!(sig_tags(&[Param::WordLists(Scalar::F64)], &Ret::WordLists(Scalar::I64)), "ii_i");
        assert_eq!(sig_tags(&[Param::MutWords(Scalar::I64)], &Ret::Scalar(Scalar::I64)), "i_i");
        assert_eq!(sig_tags(&[Param::Str], &Ret::ResultOption(Payload::Scalar(Scalar::I64))), "si_i");
        assert_eq!(sig_tags(&[], &Ret::OptionResult(Payload::Bytes)), "i_i");
    }

    fn b2() -> Param {
        Param::Scalar(Scalar::Bool)
    }

    fn classify_point() -> RecordTy {
        match classify_param_with(&ty("Point"), &Table).unwrap() {
            Param::Record(r) => r,
            _ => unreachable!(),
        }
    }

    fn classify_opaque() -> OpaqueTy {
        match classify_return(Some(&ty("Counter"))).unwrap() {
            Ret::Opaque(o) => o,
            _ => unreachable!(),
        }
    }

    #[test]
    fn names() {
        assert_eq!(snake_case("Counter"), "counter");
        assert_eq!(snake_case("HttpClient"), "http_client");
        assert_eq!(snake_case("SHA256Hasher"), "sha256_hasher");
        assert_eq!(snake_case("JSONValue"), "json_value");
        assert_eq!(camel_case("counter_try_new"), "counterTryNew");
    }

    #[test]
    fn attrs() {
        let metas: syn::punctuated::Punctuated<Meta, syn::Token![,]> =
            syn::parse_quote!(symbol = "axffi_x", utf8 = "lossy");
        let a = parse_export_attr(metas.iter()).ok().unwrap();
        assert_eq!(a.symbol.as_deref(), Some("axffi_x"));
        assert_eq!(a.utf8(), Utf8::Lossy);
        let bad: syn::punctuated::Punctuated<Meta, syn::Token![,]> = syn::parse_quote!(name = "x");
        let e = parse_export_attr(bad.iter()).err().unwrap();
        assert!(e.message.contains("unknown `axiom_export` key `name`"), "{}", e.message);
    }
}
