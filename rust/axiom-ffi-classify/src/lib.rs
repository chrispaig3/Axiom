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
//! accepted. The old `_ => Opaque` fallback is what let `u64`,
//! `Option<T>` and `char` become leaked boxes with no diagnostic.

use syn::{GenericArgument, Meta, PathArguments, Type};

/// The parameter types the boundary accepts, as the refusal messages
/// list them.
pub const PARAM_TYPES: &str = "i64 i32 i16 i8 u32 u16 u8 usize isize bool f64 f32 \
                               &str &[u8] &T &mut T (T marked `#[axiom_opaque]`)";

/// The return types the boundary accepts, as the refusal messages list
/// them.
pub const RETURN_TYPES: &str = "i64 i32 i16 i8 u32 u16 u8 usize isize bool f64 f32 () \
                                String Vec<u8> Option<T> Result<T, E> \
                                T (T marked `#[axiom_opaque]`; E: Display)";

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
    U32,
    U16,
    U8,
    Usize,
    Isize,
    Bool,
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
            "u32" => Scalar::U32,
            "u16" => Scalar::U16,
            "u8" => Scalar::U8,
            "usize" => Scalar::Usize,
            "isize" => Scalar::Isize,
            "bool" => Scalar::Bool,
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
            Scalar::U32 => "u32",
            Scalar::U16 => "u16",
            Scalar::U8 => "u8",
            Scalar::Usize => "usize",
            Scalar::Isize => "isize",
            Scalar::Bool => "bool",
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
}

/// A named Rust type Axiom holds as a handle.
#[derive(Clone, Debug)]
pub struct OpaqueTy {
    /// The type as written (possibly path-qualified), for the shim.
    pub ty: Type,
    /// The bare type name, for the Axiom `data` and the drop symbol.
    pub name: String,
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
}

/// What a fallible or optional return carries on success.
#[derive(Clone, Debug)]
pub enum Payload {
    Scalar(Scalar),
    /// `String` / `Vec<u8>`: owned bytes, handed over through the cell.
    Bytes,
    /// An owned opaque value, boxed, handed over as its address.
    Opaque(OpaqueTy),
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
    /// The shim takes an out-cell; 0 = payload in the cell, 1 = an
    /// error message's `(ptr, len)` in the cell.
    Result(Payload),
    /// The shim takes an out-cell; 0 = payload in the cell, 2 = None.
    Option(Payload),
}

impl Ret {
    /// Whether the shim takes a trailing out-cell word.
    pub fn needs_cell(&self) -> bool {
        matches!(self, Ret::Bytes | Ret::Result(_) | Ret::Option(_))
    }

    /// Whether an `Err` can come back (so an invalid `&str` argument is
    /// reported rather than aborting).
    pub fn is_result(&self) -> bool {
        matches!(self, Ret::Result(_))
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

/// Classify one parameter type.
pub fn classify_param(ty: &Type) -> Result<Param, String> {
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
                    if !is_u8(&s.elem) {
                        return Err(refuse_param(&text, " (only `&[u8]` slices cross)"));
                    }
                    if mutable {
                        return Err(refuse_param(
                            &text,
                            " (Axiom strings are immutable through the FFI; take `&[u8]`)",
                        ));
                    }
                    Ok(Param::Bytes)
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
                                " (borrow the bytes as `&str`/`&[u8]`, or hold the value \
                                 in a type marked `#[axiom_opaque]`)",
                            ));
                        }
                        "u64" | "u128" | "i128" | "char" => {
                            return Err(refuse_param(&text, ""));
                        }
                        _ => {}
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
            match name.as_str() {
                "u64" | "u128" | "i128" => Err(refuse_param(
                    &text,
                    " (an Axiom `Int` is an i64 and cannot hold every value; take an \
                     `i64`, or a `&[u8]` of its bytes)",
                )),
                "char" => Err(refuse_param(
                    &text,
                    " (take an `i64` code point, or a `&str`)",
                )),
                "String" => Err(refuse_param(&text, " (borrow it: take `&str`)")),
                "Vec" => Err(refuse_param(&text, " (borrow it: take `&[u8]`)")),
                "Option" | "Result" => Err(refuse_param(
                    &text,
                    " (`Option` and `Result` may only be returned)",
                )),
                _ => Err(refuse_param(
                    &text,
                    " (Axiom holds a handle, so take `&T` or `&mut T`, or return it)",
                )),
            }
        }
        _ => Err(refuse_param(&text, "")),
    }
}

fn is_str(ty: &Type) -> bool {
    matches!(path_last(ty), Some((seg, name)) if name == "str" && seg.arguments.is_none())
}

/// Classify the payload of `Result<T, _>` / `Option<T>`, or a direct
/// return. `nested` names the wrapper for the message when one applies.
fn classify_payload(ty: &Type, outer: &str, whole: &str) -> Result<Payload, String> {
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
                "Vec" => {
                    if single_generic(seg).map(is_u8).unwrap_or(false) {
                        Ok(Payload::Bytes)
                    } else {
                        Err(refuse_return(
                            whole,
                            " (only `Vec<u8>` crosses directly; other collections must be \
                             serialised or held in an `#[axiom_opaque]` type)",
                        ))
                    }
                }
                "Option" | "Result" => {
                    if outer.is_empty() {
                        unreachable!("the outer classifier handles Option/Result")
                    }
                    Err(refuse_return(
                        whole,
                        &format!(" (`{name}` cannot nest inside `{outer}`: the status word \
                                  has one slot)"),
                    ))
                }
                "u64" | "u128" | "i128" => Err(refuse_return(
                    whole,
                    " (an Axiom `Int` is an i64 and cannot hold every value; return an \
                     `i64`, or a `Vec<u8>` of its bytes)",
                )),
                "char" => Err(refuse_return(
                    whole,
                    " (return an `i64` code point, or a `String`)",
                )),
                "Box" | "Rc" | "Arc" => Err(refuse_return(
                    whole,
                    " (return the value itself, held in a type marked `#[axiom_opaque]`)",
                )),
                _ => Ok(Payload::Opaque(OpaqueTy { ty: ty.clone(), name })),
            }
        }
        _ => Err(refuse_return(&text, "")),
    }
}

/// Classify the return type (`None` = no `->`).
pub fn classify_return(ty: Option<&Type>) -> Result<Ret, String> {
    let Some(ty) = ty else { return Ok(Ret::Scalar(Scalar::Unit)) };
    let whole = type_text(ty);
    if let Some((seg, name)) = path_last(ty) {
        match name.as_str() {
            "Result" => {
                let ok = single_generic(seg).ok_or_else(|| {
                    refuse_return(&whole, " (`Result` needs its `Ok` type written out)")
                })?;
                return Ok(Ret::Result(classify_payload(ok, "Result", &whole)?));
            }
            "Option" => {
                let some = single_generic(seg).ok_or_else(|| {
                    refuse_return(&whole, " (`Option` needs its payload type written out)")
                })?;
                let p = classify_payload(some, "Option", &whole)?;
                if matches!(p, Payload::Scalar(Scalar::Unit)) {
                    return Err(refuse_return(
                        &whole,
                        " (`Option<()>` is a `bool`; return one)",
                    ));
                }
                return Ok(Ret::Option(p));
            }
            _ => {}
        }
    }
    Ok(match classify_payload(ty, "", &whole)? {
        Payload::Scalar(s) => Ret::Scalar(s),
        Payload::Bytes => Ret::Bytes,
        Payload::Opaque(o) => Ret::Opaque(o),
    })
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
    }

    #[test]
    fn refusals_list_the_set() {
        for bad in ["u64", "char", "Counter", "String", "Option<i64>", "&mut str", "&i64", "(i64, i64)"] {
            let e = classify_param(&ty(bad)).err().expect(bad);
            assert!(e.contains(PARAM_TYPES), "{e}");
        }
        for bad in ["u64", "char", "Vec<i64>", "Result<Option<i64>, String>", "&str", "Option<()>"] {
            let e = classify_return(Some(&ty(bad))).err().expect(bad);
            assert!(e.contains(RETURN_TYPES), "{e}");
        }
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
