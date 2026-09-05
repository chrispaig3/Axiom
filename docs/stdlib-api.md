# Axiom standard library — API reference

GENERATED. `examples/axdoc/axdoc.ax` writes this file from the
standard library's own source and from `axiom symbols`; do not edit it
by hand. `scripts/check-stdlib-api.sh` regenerates it and requires the
result to be byte-identical, so an edit here is a failing gate rather
than a document that quietly disagrees with the library.

The **public surface** is read from the source, because visibility is
only written there — AXSYM cannot say whether a name is `pub` and emits
no row for a macro at all. The **effects** column is the compiler's
own answer, derived by a fixpoint over every body rather than claimed
by a comment: `Alloc` is the heap machinery — allocation, the arena
primitives, installing handler evidence; `IO` reaches the outside
world, a syscall or an `extern` or the command line; `Mut` writes
heap state something else can see, a field store or the primitive it
lowers to. A blank cell means the checker derived no effect (or, for
a macro, that AXSYM has no row to derive one from) — and it is a
LOWER bound: `docs/memory-model.md` MM-EXEC-9a lists what inference
still does not see, of which the one that can surprise a reader here
is that a constructor allocates and contributes nothing.

The **type** column is the source spelling, `(-> Int Int)`, not AXSYM's
curried rendering, because it is the spelling you will have to write.

See [reference.md](reference.md) for the language, and
[README](../README.md#standard-library) for what each module is for.

## `Agent.Tags`

`stdlib/Agent/Tags.ax` — 32 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Meta` | struct |  |  | One `#key` or `#key=value`. A bare flag - `#pure` - has `val` empty, which `symHasTag` distinguishes from an absent key. |
| `Sym` | struct |  |  | One AXSYM line, parsed. |
| `axsymSpace` | value | `Int` |  |  |
| `axsymQuote` | value | `Int` |  |  |
| `axsymHash` | value | `Int` |  |  |
| `axsymAt` | value | `Int` |  |  |
| `axsymEquals` | value | `Int` |  |  |
| `axsymNewline` | value | `Int` |  |  |
| `axsymPercent` | value | `Int` |  |  |
| `axsymIsKind` | value | `(-> Int Bool)` |  | The six KIND letters, and deliberately only those: they are disjoint from AXDL's `E`/`W`/`N`/`H` severity sigils, so a line's first byte says which notation produced it even in a concatenated stream. A seventh kind added to the compiler must be added here, and a line whose first byte is unknown is answered `None` rather than guessed at - a reader that guesses turns a compiler change into silently wrong data. |
| `axsymTrimEnd` | value | `(-> String String)` | `Alloc,Mut` | Trailing spaces off the end of a slice. The head field is taken as the bytes before the opening quote, which includes the space that separated the location from it. |
| `axsymEscapable` | value | `(-> Int Bool)` |  | The bytes `saAxMeta` escapes on the way out, restated here because this is the other end of the same wire: space and every control byte (`< 33`), `"`, `#`, `%` and DEL. Anything else is left alone, so a UTF-8 tag value survives. |
| `axsymHexVal` | value | `(-> Int (Option Int))` |  | One hex digit's value, or `None`. Both cases are accepted: the emitter writes upper, and a reader that took only what one emitter happens to write is pinned to that emitter rather than to the notation. Absence, not failure - `docs/error-model.md` ERR-REC-3 - and `Option` is built in, so this costs the module no import. |
| `axsymPctAt` | value | `(-> String Int (Option Int))` | `Alloc` | The byte a `%XX` at `i` stands for, or `None` where there is no complete escape. STRICT, and that is the point: only the bytes `saAxSafe` escapes decode, so a literal `%` standing in a value the COMPILER built - a rendered type, a generated `Trait#Type#method` name - is never mistaken for an escape. `%41` stays `%41`. |
| `axsymUnpct` | value | `(-> String String)` | `Alloc,Mut` | A meta key or value with its escapes undone. The `strFindByte` guard is not an optimisation for its own sake: no AXTAG in this repository contains a byte that is escaped, so every token on every line in the corpus takes the first arm and is returned as it arrived, allocating nothing and copying nothing. |
| `axsymUnpctFrom` | value | `(-> String Int String String)` | `Alloc,Mut` |  |
| `axsymMeta` | value | `(-> String Meta)` | `Alloc,Mut` | `#key=value` or a bare `#key`, with the leading `#` already dropped. Both halves are unescaped, because `saAxMeta` escapes both: an AXTAG key is everything from `;@axiom:` to the newline, so a key can carry a space or a `#` just as a value can. |
| `axsymMetaScan` | value | `(-> String Int Int (Vec Meta) (Vec Meta))` | `Alloc,Mut` | The metadata section, from `at` to the end of the line. A token opens at a `#` whose previous byte is a space, and runs to the byte before the next such `#`. `i` walks; `start` is the open token's first byte, or -1 before the first `#` is seen. |
| `axsymLine` | value | `(-> String (Option Sym))` | `Alloc,Mut` | One line. `None` for a blank line, for a line whose first byte is not a KIND letter, and for a line with no quoted type - which together are every non-AXSYM line a caller might feed in, including the `compilation failed` trailer and AXDL diagnostics on the same stream. |
| `axsymBuild` | value | `(-> String Int Int (Option Sym))` | `Alloc,Mut` | The three fields either side of the quoted type, once its bounds are known. Split out because the arms above are a refusal ladder and this is the one path that answers a symbol. |
| `axsymNid` | value | `(-> String String)` | `Alloc,Mut` | The `@<nid>` between the type and the metadata, empty when absent. It is bounded by the next space rather than by the end, because the metadata follows it on the same line. |
| `axsymParse` | value | `(-> String (Vec Sym))` | `Alloc,Mut` | A whole AXSYM stream. Lines that are not AXSYM are skipped, so the caller may pass the compiler's output unfiltered. |
| `axsymParseFrom` | value | `(-> (Vec Int) Int (Vec Sym) (Vec Sym))` | `Alloc,Mut` |  |
| `symTag` | value | `(-> Sym String String)` |  | The value of the LAST `#key` on the line, or empty. Empty is also what a bare flag answers, so a caller distinguishing "absent" from "present with no value" wants `symHasTag`. |
| `symTagFrom` | value | `(-> (Vec Meta) String Int String)` |  |  |
| `symTagLastIdx` | value | `(-> (Vec Meta) String Int Int Int)` |  | The index of the last `#key` at or after `i`, or -1. Carried in an accumulator rather than compared on the way out of the recursion, because a bare flag's value is empty and "" cannot tell a later match from no match at all. |
| `symHasTag` | value | `(-> Sym String Bool)` |  |  |
| `symHasTagFrom` | value | `(-> (Vec Meta) String Int Bool)` |  |  |
| `symEffects` | value | `(-> Sym String)` |  | The effect row the CHECKER derived - not what the author claimed. Empty when the declaration performs none. |
| `symDerivedPure` | value | `(-> Sym Bool)` |  | True when the checker derived no effects at all. This is a statement about the ANALYSIS, not a guarantee about the program: an effect reached through a function value in memory is not in the row, and a built-in effect named by an enclosing `handle` is subtracted from it. A policy that treats this as proof of purity is reading a lower bound as an upper one. |
| `symAgentTag` | value | `(-> Sym String String)` | `Alloc,Mut` | The `agent:*` namespace, which the compiler records and does not check. `(symAgentTag s "rewrite")` reads `#agent:rewrite`. |
| `symHasAgentTag` | value | `(-> Sym String Bool)` | `Alloc,Mut` |  |

## `Err`

`stdlib/Err.ax` — 36 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Result` | data |  |  |  |
| `Error` | struct |  |  |  |
| `errDivideByZero` | value | `Int` |  | The codes this module raises itself. A program's own codes live in its own space; these are the ones `ERR-REC-2` needs. |
| `errOverflow` | value | `Int` |  |  |
| `errShiftTooWide` | value | `Int` |  |  |
| `errShortWrite` | value | `Int` |  | A descriptor accepted some bytes and then accepted none, without an errno to say why. It is NOT a syscall error - `write` returned 0, which is a legal answer - so it cannot borrow an errno, and it is not success either, which is exactly why `Sys.sysWriteAllFd` could not express it while it answered an Int. `ERR-REC-3` calls a short write a failure and not an absence: the bytes were meant to go and did not. |
| `mkError` | value | `(-> Int String Error)` | `Alloc` |  |
| `errCode` | value | `(-> Error Int)` |  |  |
| `errMessage` | value | `(-> Error String)` |  |  |
| `errContext` | value | `(-> Error String)` |  |  |
| `errorText` | value | `(-> Error String)` | `Alloc,Mut` | The rendering `main` writes to fd 2 (ERR-REC-4), and the one a program builds a longer report out of. A plain function rather than a format hole: a rendering is chosen from a concrete type, so a value reached through a type variable is AX3025, and every caller here has a concrete `Error` in hand anyway. |
| `isOk` | value | `(-> (Result a e) Bool)` |  |  |
| `isErr` | value | `(-> (Result a e) Bool)` |  |  |
| `unwrapOr` | value | `(-> (Result a e) a a)` |  |  |
| `mapOk` | value | `(-> (Result a e) (-> a b) (Result b e))` | `Alloc` |  |
| `mapErr` | value | `(-> (Result a e) (-> e f) (Result a f))` | `Alloc` |  |
| `andThen` | value | `(-> (Result a e) (-> a (Result b e)) (Result b e))` | `Alloc` |  |
| `errContextOf` | value | `(-> Error String Error)` | `Alloc` | Attach what the caller was doing to an error in flight, passing `Ok` through untouched. It needs no binder, so it is a function and not a form. |
| `withContext` | value | `(-> (Result a Error) String (Result a Error))` | `Alloc` |  |
| `okOr` | value | `(-> (Option a) e (Result a e))` | `Alloc` |  |
| `toOption` | value | `(-> (Result a e) (Option a))` | `Alloc` |  |
| `isSome` | value | `(-> (Option a) Bool)` |  | Whether the `Option` holds a value. The `Option` half of `isOk`. |
| `isNone` | value | `(-> (Option a) Bool)` |  | Whether the `Option` is empty. Exactly `isSome` negated, spelled out because a caller reads for the case it cares about. |
| `optUnwrapOr` | value | `(-> (Option a) a a)` |  | The value, or `fallback` when there is none. The one combinator that ends the `Option` rather than passing it on, and the reason most call sites need no `match` at all. |
| `optMap` | value | `(-> (Option a) (-> a b) (Option b))` | `Alloc` | Apply `f` to the value if there is one, leaving an absence alone. The result type is `f`'s, so this is how an `(Option Int)` becomes an `(Option String)`. |
| `optAndThen` | value | `(-> (Option a) (-> a (Option b)) (Option b))` |  | Chain a step that may itself be absent, without nesting two `Option`s. `optMap` with a function answering `(Option b)` would give `(Option (Option b))`; this is that flattened. |
| `optOr` | value | `(-> (Option a) (Option a) (Option a))` | `Alloc` | The first of two that is present. `alt` is EVALUATED at the call, so this is not a short-circuit: a caller whose alternative is expensive should write the `match`. Said here because the name is borrowed from languages where it is lazy. |
| `intMin` | value | `Int` |  |  |
| `addChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` | The three that WRAP. |
| `subChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `mulChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `divChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `remChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `shlChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` | A shift amount of 64 or more, and a negative one, are undefined and no masking is emitted - `(<< 1 100)` answers 68719476736 at `--opt 0` and 1 at `--opt 1`. |
| `shrChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `try!` | macro |  |  | ERR-SUGAR-2: the propagation form. |

## `Fallible`

`stdlib/Fallible.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Fallible` | effect |  |  | Fallible - the effect a batch loop's deep callee performs on a malformed record, and the handlers that answer it without unwinding. |
| `fallibleSkipped` | value | `Int` |  | The value a handler answers to mean "skip this record": the most negative `Int`. A loop compares the value it got against this, or asks `fallibleIsSkipped`. |
| `fallibleIsSkipped` | value | `(-> Int Bool)` |  | Whether a value is the skip sentinel. The comparison a batch loop makes once per record; it allocates nothing. |
| `fallibleSkip` | value | `(-> String Int)` |  | Skip every malformed record: answer `fallibleSkipped`, whatever the message. A one-parameter top-level function is a value, so it is passed bare. |
| `fallibleDefault` | value | `(-> Int String Int)` |  | Use `d` in place of every malformed record. Built ONCE, at the `handle`, which is why the fallback is here and not an argument of the operation: the closure holding `d` is allocated when the handler is installed, not when a record is bad. One parameter, answering the handler - the type is spelled flat because every function type is curried and that is the formatter's normal form; `mkAdder` in `280-function-application.ax` is the precedent. |
| `FallibleTally` | struct |  |  | How many records were malformed. A struct rather than a bare `Int` because the handler has to write it from inside a closure, and a field store is the one mutation visible through every holder of the value (reference.md, Built-in Effects: `Mut`). |
| `fallibleTally` | value | `FallibleTally` | `Alloc` | A fresh tally at zero. |
| `fallibleCount` | value | `(-> FallibleTally Int)` |  | What a tally holds. |
| `fallibleCounting` | value | `(-> FallibleTally (-> String Int) String Int)` | `Mut` | Count every malformed record in `tally`, then answer as `next` would: `(fallibleCounting t fallibleSkip)` skips and counts, `(fallibleCounting t (fallibleDefault 0))` substitutes and counts. The `handle` installing it lists `Mut` beside `Fallible`, because a handler's own effects count at the site that installs it. |

## `Ffi`

`stdlib/Ffi.ax` — 16 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ffiStatusOk` | value | `Int` |  |  |
| `ffiStatusErr` | value | `Int` |  |  |
| `ffiStatusNone` | value | `Int` |  |  |
| `ffiHandleNew` | value | `(-> Int Int Handle)` | `Alloc,Mut` | A fresh Handle over `ptr`, to be destroyed by the C function at `dropFn` (`i64 (i64)`). The block is born free-floating and adopted by this function's own answer (event 2), exactly as `strWrapOwned` adopts a header - so the caller holds one share. |
| `ffiHandlePtr` | value | `(-> Handle Int)` |  | The Rust pointer, 0 once the handle is closed. |
| `ffiHandleLive` | value | `(-> Handle Bool)` |  |  |
| `ffiHandleClose` | value | `(-> Handle Int)` | `Mut` | Destroy the Rust value NOW, once: the destructor runs and the pointer is zeroed, so a second close and the handle's own death do nothing. |
| `ffiCellNew` | value | `Int` | `Alloc` | A two-word out-cell, zeroed, held by one share the wrapper gives back with `ffiCellFree`. |
| `ffiCellNewN` | value | `(-> Int Int)` | `Alloc` | An out-cell of `n` words (at least two: a status' message is `{ptr, len}`), for a record that crosses as its fields (one word each, in declaration order) or any payload wider than two words. |
| `ffiWordAt` | value | `(-> Int Int Int)` |  | Word `i` of a Rust-owned word buffer: what a generated wrapper reads a record's fields or a list's lengths through before freeing it. The same read as `ffiCellWord`, kept under its own name because the two describe different things to a reader of the generated module - one is Rust's buffer, one is the cell the wrapper allocated - and written in terms of it so there is one load. |
| `ffiCellFree` | value | `(-> Int Int)` |  |  |
| `ffiCellWord` | value | `(-> Int Int Int)` |  |  |
| `ffiBytesToStr` | value | `(-> Int Int String)` | `Alloc,Mut` | Rust-owned bytes copied into a fresh Axiom `String`. `strAlloc` reserves len+1 and zeroes it, so the NUL terminator is already there. Does NOT free the Rust side: the wrapper calls `ffiFreeBytes` after. |
| `ffiWordsToVec` | value | `(-> Int Int (Vec Int))` | `Alloc,Mut` | A Rust `Vec<i64>` copied into an Axiom `Vec`: `p` points at `n` words. Does NOT free the Rust side: the wrapper calls `ffiFreeWords`. |
| `ffiStrsToVec` | value | `(-> Int Int (Vec String))` | `Alloc,Mut` | A Rust `Vec<String>` copied into an Axiom `Vec` of Strings: `p` points at `2n` words, `{bytesPtr, byteLen}` per element. Does NOT free the Rust side: the wrapper calls `ffiFreeStrList`. |
| `ffiWordListsToVec` | value | `(-> Int Int (Vec (Vec Int)))` | `Alloc,Mut` | A Rust `Vec<Vec<T>>` of word scalars copied into an Axiom `Vec` of `Vec`s: `p` points at `2n` words, `{wordsPtr, len}` per inner list. Does NOT free the Rust side: the wrapper calls `ffiFreeWordLists`. |

## `Fmt`

`stdlib/Fmt.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `fmtIntWidth` | value | `(-> Int Int)` |  | Decimal digits in `n`, counting a leading `-` and treating 0 as one digit. |
| `fmtInt` | value | `(-> Int String)` | `Alloc,Mut` | `n` in base 10 as a `Str`. |
| `fmtHex` | value | `(-> Int String)` | `Alloc,Mut` |  |
| `fmtPadLeft` | value | `(-> String Int String)` | `Alloc,Mut` | `s` padded on the left with spaces to at least `width` bytes. |
| `fmtPadRight` | value | `(-> String Int String)` | `Alloc,Mut` | `s` padded on the right with spaces to at least `width` bytes. |
| `fmtPadCenter` | value | `(-> String Int String)` | `Alloc,Mut` | `s` centred in `width` bytes. An odd remainder goes to the RIGHT, which is the convention Rust's `{:^}` uses and the one that makes a column of centred labels line up with a left-aligned header. |
| `fmtPadZerosLeft` | value | `(-> String Int String)` | `Alloc,Mut` | `s` padded on the left with ZEROS to at least `width` bytes, with a leading sign kept in front of them: `-7` at width 4 is `-007` and not `00-7`. That is the whole reason this is not `fmtPadLeft` with a different byte, and it is why the format specifier `{n:04}` can be one call rather than a sign test at every call site. |
| `fmtHexUpper` | value | `(-> Int String)` | `Alloc,Mut` | Uppercase hexadecimal, for the `{n:X}` specifier. Same digits as `fmtHex`, and deliberately a separate function rather than a flag: the specifier picks one at expansion time, so a branch would be a runtime test of a compile-time constant. |
| `fmtFloat` | value | `(-> Float String)` | `Alloc,Mut` | `x` with six decimal places. |
| `fmtFloatPrec` | value | `(-> Float Int String)` | `Alloc,Mut` | `x` with `places` decimal places, rounded half away from zero. |

## `Html`

`stdlib/Html.ax` — 118 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `HtmlBuf` | struct |  |  | A document under construction: a `Vec` of pieces and the running byte total, so that `hFinish` allocates the whole document once. Built by `hNew`, written through `hPut` and everything above it, finished once by `hFinish`. |
| `hNew` | value | `HtmlBuf` | `Alloc,Mut` | A fresh builder. The piece vector is a leaf vector, as `Json.ax`'s serialiser keeps its pieces: the pieces are string literals and escaped copies, the document copies out of them once, and the arena scope around a request is what reclaims them (MM-ALLOC-22). |
| `hPut` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | Append one piece, verbatim. Every writer in this module ends here; nothing is copied until `hFinish`. Answers 0, as every builder call does, so a `{ ... }` of them is an `Int` whatever it ends on. |
| `hLen` | value | `(-> HtmlBuf Int)` |  | The bytes written so far. |
| `hFinish` | value | `(-> HtmlBuf String)` | `Alloc,Mut` | The document: one allocation of `hLen` bytes, one `memCopy` per piece. The builder is spent afterwards - its pieces are garbage, and a second call copies them again into a second document. |
| `hEscText` | value | `(-> String String)` | `Alloc,Mut` | Text-context escaping: `&` `<` `>` become `&amp;` `&lt;` `&gt;`. Quotes pass through, because text is not inside quotes. |
| `hEscAttr` | value | `(-> String String)` | `Alloc,Mut` | Attribute-value escaping: the three above plus `"` as `&quot;` and `'` as `&#39;`. What `hAttr` applies to every value it writes. |
| `hEscTagEnd` | value | `(-> String String)` | `Alloc,Mut` | `s` with every `</` rewritten `<\/`, or `s` itself when it holds none. The transform inline CSS and JS go through: a `</style` or `</script` inside either would end the element early and hand the rest of the string to the HTML parser as markup, and `<\/` means the same thing inside a JS string, a regex, a comment and a CSS string. A run-time rewrite, not a compile-time refusal (see the header). |
| `hText` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | Escaped text: what `(text b s)` expands to. |
| `hRaw` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | UNESCAPED bytes: what `(raw b s)` expands to. The only writer here that escapes nothing. |
| `hCss` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | CSS, verbatim except `</` -> `<\/`. What `(style b css)` wraps. |
| `hJs` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | JS, verbatim except `</` -> `<\/`. What `(script b js)` wraps. |
| `hOpen` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | `<tag`, left open for attributes. |
| `hOpenEnd` | value | `(-> HtmlBuf Int)` | `Alloc,Mut` | The `>` that ends an open tag. |
| `hOpenSolo` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | `<tag>` in one step, for an element with no attributes. |
| `hClose` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | `</tag>`. |
| `hAttr` | value | `(-> HtmlBuf String String Int)` | `Alloc,Mut` | ` name="value"`, the value escaped for the attribute context. |
| `hFlag` | value | `(-> HtmlBuf String Int)` | `Alloc,Mut` | ` name` alone - a boolean attribute such as `disabled`. |
| `el` | macro |  |  | `(el b "tag" { children })` - an element with children and no attributes. The builder and the tag are bound first (MAC-SAFE-1): each is mentioned twice in the template. |
| `elA` | macro |  |  | `(elA b "tag" { attributes } { children })` - an element with an attribute block, written between `<tag` and `>`, then its children. |
| `elVoid` | macro |  |  | `(elVoid b "tag")` - a void element, `<br>`, with nothing inside and no closing tag. |
| `elVoidA` | macro |  |  | `(elVoidA b "tag" { attributes })` - a void element with attributes, `<img src="..." alt="...">`. |
| `html` | macro |  |  | `<html>` |
| `htmlA` | macro |  |  | `<html ...>` |
| `head` | macro |  |  | `<head>` |
| `headA` | macro |  |  | `<head ...>` |
| `title` | macro |  |  | `<title>` |
| `titleA` | macro |  |  | `<title ...>` |
| `body` | macro |  |  | `<body>` |
| `bodyA` | macro |  |  | `<body ...>` |
| `div` | macro |  |  | `<div>` |
| `divA` | macro |  |  | `<div ...>` |
| `p` | macro |  |  | `<p>` |
| `pA` | macro |  |  | `<p ...>` |
| `span` | macro |  |  | `<span>` |
| `spanA` | macro |  |  | `<span ...>` |
| `anchor` | macro |  |  | `<a>` - spelled `anchor`, because `a` is a type variable in the standard library's own signatures (the header's list). |
| `anchorA` | macro |  |  | `<a href="...">` |
| `ul` | macro |  |  | `<ul>` |
| `ulA` | macro |  |  | `<ul ...>` |
| `ol` | macro |  |  | `<ol>` |
| `olA` | macro |  |  | `<ol ...>` |
| `li` | macro |  |  | `<li>` |
| `liA` | macro |  |  | `<li ...>` |
| `h1` | macro |  |  | `<h1>` |
| `h1A` | macro |  |  | `<h1 ...>` |
| `h2` | macro |  |  | `<h2>` |
| `h2A` | macro |  |  | `<h2 ...>` |
| `h3` | macro |  |  | `<h3>` |
| `h3A` | macro |  |  | `<h3 ...>` |
| `strong` | macro |  |  | `<strong>` |
| `strongA` | macro |  |  | `<strong ...>` |
| `em` | macro |  |  | `<em>` |
| `emA` | macro |  |  | `<em ...>` |
| `pre` | macro |  |  | `<pre>` |
| `preA` | macro |  |  | `<pre ...>` |
| `code` | macro |  |  | `<code>` |
| `codeA` | macro |  |  | `<code ...>` |
| `table` | macro |  |  | `<table>` |
| `tableA` | macro |  |  | `<table ...>` |
| `tr` | macro |  |  | `<tr>` |
| `trA` | macro |  |  | `<tr ...>` |
| `td` | macro |  |  | `<td>` |
| `tdA` | macro |  |  | `<td ...>` |
| `th` | macro |  |  | `<th>` |
| `thA` | macro |  |  | `<th ...>` |
| `form` | macro |  |  | `<form>` |
| `formA` | macro |  |  | `<form action="..." method="...">` |
| `label` | macro |  |  | `<label>` |
| `labelA` | macro |  |  | `<label ...>` - the `for` attribute is `(attr b "for" v)`. |
| `select` | macro |  |  | `<select>` |
| `selectA` | macro |  |  | `<select ...>` |
| `option` | macro |  |  | `<option>` |
| `optionA` | macro |  |  | `<option value="...">` |
| `button` | macro |  |  | `<button>` |
| `buttonA` | macro |  |  | `<button ...>` - the `type` attribute is `(attr b "type" v)`. |
| `textarea` | macro |  |  | `<textarea>` |
| `textareaA` | macro |  |  | `<textarea ...>` |
| `nav` | macro |  |  | `<nav>` |
| `navA` | macro |  |  | `<nav ...>` |
| `header` | macro |  |  | `<header>` |
| `headerA` | macro |  |  | `<header ...>` |
| `footer` | macro |  |  | `<footer>` |
| `footerA` | macro |  |  | `<footer ...>` |
| `section` | macro |  |  | `<section>` |
| `sectionA` | macro |  |  | `<section ...>` |
| `article` | macro |  |  | `<article>` |
| `articleA` | macro |  |  | `<article ...>` |
| `br` | macro |  |  | `<br>` |
| `hr` | macro |  |  | `<hr>` |
| `img` | macro |  |  | `<img src="..." alt="...">` |
| `input` | macro |  |  | `<input name="..." value="...">` - `type` is `(attr b "type" v)`. |
| `link` | macro |  |  | `<link rel="stylesheet" href="...">` |
| `meta` | macro |  |  | `<meta charset="utf-8">` |
| `style` | macro |  |  | `<style>css</style>`, the CSS verbatim with `</` neutralised. |
| `script` | macro |  |  | `<script>js</script>`, the JS verbatim with `</` neutralised. |
| `scriptA` | macro |  |  | `<script src="..."></script>` - an external script, attributes only. |
| `text` | macro |  |  | Escaped text: `(text b "5 < 6")` writes `5 &lt; 6`. The default, and the form every string a peer supplied goes through. |
| `raw` | macro |  |  | UNESCAPED BYTES. THIS IS THE ONLY FORM THAT WRITES A STRING WITHOUT ESCAPING IT: `(raw b "<hr>")` writes `<hr>`, and `(raw b q)` with `q` from a request writes whatever the peer sent, markup and script included. Use it for markup the program itself wrote, never for data. |
| `attr` | macro |  |  | ` name="value"` for any attribute name - the escape hatch for a name with no macro of its own (`type`, `for`, `title`, `style`, `data-*`, `aria-*`). The NAME is the author's literal and is written as it is. |
| `flag` | macro |  |  | ` name` alone: a boolean attribute, `(flag b "disabled")`. |
| `class` | macro |  |  | ` class="..."` |
| `id` | macro |  |  | ` id="..."` |
| `href` | macro |  |  | ` href="..."` |
| `src` | macro |  |  | ` src="..."` |
| `alt` | macro |  |  | ` alt="..."` |
| `name` | macro |  |  | ` name="..."` |
| `value` | macro |  |  | ` value="..."` |
| `rel` | macro |  |  | ` rel="..."` |
| `action` | macro |  |  | ` action="..."` |
| `method` | macro |  |  | ` method="..."` |
| `placeholder` | macro |  |  | ` placeholder="..."` |
| `lang` | macro |  |  | ` lang="..."` |
| `charset` | macro |  |  | ` charset="..."` |
| `content` | macro |  |  | ` content="..."` |
| `width` | macro |  |  | ` width="..."` |
| `height` | macro |  |  | ` height="..."` |
| `target` | macro |  |  | ` target="..."` |

## `Http`

`stdlib/Http.ax` — 27 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `httpMaxHead` | value | `Int` |  | The largest request head - request line plus headers plus the blank line - `httpRead` will buffer, in bytes: 16 KiB. A head that has not ended by then is refused as 431. |
| `httpMaxBody` | value | `Int` |  | The largest `Content-Length` `httpRead` accepts, in bytes: 8 MiB. Larger is 413, and so is a value the parser cannot represent. |
| `httpReadCap` | value | `Int` |  | The reader's initial buffer, in bytes: 2 KiB, which holds a browser's request head with a few cookies in one read (measured in the header); the buffer doubles up to `httpMaxHead` when a head does not fit. |
| `HttpReader` | struct |  |  | A buffered reader over a socket: the descriptor, a buffer whose `strLen` is its capacity, how much of it holds data, and how far the parser has consumed. Bytes between `consumed` and `filled` are the request in progress. |
| `httpReaderNew` | value | `(-> Int HttpReader)` | `Alloc,Mut` | A reader over `fd` with the default buffer. |
| `httpReaderWith` | value | `(-> Int Int HttpReader)` | `Alloc,Mut` | A reader over `fd` whose buffer starts at `cap` bytes (at least 1). A capacity of 1 makes every `read` answer one byte, which is how tests/stdlib/430-http-parse.ax drives the refill loop through every boundary a slow peer could put a read on, deterministically and in one process. |
| `HttpReq` | struct |  |  | One parsed request. `path` is percent-decoded with the query stripped; `query` is the raw bytes after `?` (empty when there were none); `hnames` and `hvals` are parallel `Vec`s of Strings, the names ASCII-lowercased, so `httpHeader` needs one spelling; `body` is exactly `Content-Length` bytes, or empty. Every String here is a COPY, never a slice of the reader's buffer, which a later fill may move. |
| `httpHeader` | value | `(-> HttpReq String String String)` | `Alloc,Mut` | The value of header `name` (any case; compared lowercased), or `dflt` when the request did not carry it. A header sent twice answers its first value. |
| `httpHasHeader` | value | `(-> HttpReq String Bool)` | `Alloc,Mut` | Whether the request carried header `name`, in any case. |
| `httpDecode` | value | `(-> String Bool String)` | `Alloc,Mut` | `s` percent-decoded: every `%XX` with two hex digits becomes the byte `XX`, and when `plusSpace` is set every `+` becomes a space - the rule for a query string, and not for a path. A `%` that does not start a valid escape is kept as it is rather than refused, so a caller that must refuse one compares the answer with the input. Also answers `s` itself when there is nothing to decode. |
| `httpQueryParam` | value | `(-> HttpReq String String String)` | `Alloc,Mut` | The value of query parameter `name`, decoded (`%XX` and `+`), or `dflt` when the query does not carry it. `?q=a%20b&x=1` answers `a b` for `q` and `1` for `x`; a pair with no `=` has the empty value. |
| `httpRead` | value | `(-> HttpReader (Result HttpReq Error))` | `Alloc,IO,Mut` | Read one whole request from the reader: refill until the head has ended, parse it, then read exactly `Content-Length` bytes of body. The refusals answer an `Error` whose CODE is the HTTP status to write back: 400 for a malformed head or a peer that closed early, 413 for a body above `httpMaxBody` or a length the parser cannot hold, 431 for a head above `httpMaxHead`, 501 for `Transfer-Encoding` (chunked bodies are not read), 505 for a version that is not HTTP/1.x. |
| `httpStatusText` | value | `(-> Int String)` |  | The reason phrase for a status, or `Unknown` for one this module does not name. |
| `httpContentType` | value | `(-> String String)` | `Alloc,Mut` | The `Content-Type` for a file name, by its extension: `.html`, `.css`, `.js`, `.svg`, `.png`, `.ico`, `.txt` and `.json` are named, and everything else is `application/octet-stream` - deliberately not `text/html`, which is the stored-XSS route for an unknown file. |
| `httpRespondRaw` | value | `(-> Int Int String Int Int Int)` | `Alloc,IO,Mut` | Write a whole response to `fd`: the head for `status` and `ctype` with `Content-Length: len`, then the `len` bytes at `addr`. Every write goes through `sysWriteAllFd`. Takes an address and a length rather than a String so that a body holding a NUL byte - a PNG - is written whole; `strCStr` would stop at the NUL. Answers what the body's `sysWriteAllFd` answered, the head's when that one failed. |
| `httpRespond` | value | `(-> Int Int String String Int)` | `Alloc,IO,Mut` | Write a whole response whose body is the String `body`: `httpRespondRaw` over its bytes and its byte count. |
| `httpFail` | value | `(-> Int Int String Int)` | `Alloc,IO,Mut` | A plain-text refusal or error page: `status` with its reason phrase and `why` as the body, so a curl user reads the reason on the terminal. Answers `status`. |
| `HttpHandler` | struct |  |  | A handler: a function of the socket and the request, answering an Int the dispatcher passes back. Held in a struct because the router keeps handlers in a `Vec` of words. Written as `(HttpHandler (lambda (fd r) (page fd r)))` around a signed `fn`. |
| `HttpRouter` | struct |  |  | The routing table: exact routes as three parallel `Vec`s (method, path, handler cell), static prefixes as two (URL prefix, directory), and the handler for a path nothing matched. |
| `routerNew` | value | `HttpRouter` | `Alloc,IO,Mut` | An empty router whose not-found handler writes a plain-text 404. `IO`, because the checker charges a function with the effects of the lambda it builds, and the default handler writes. |
| `routeAdd` | value | `(-> HttpRouter String String HttpHandler Int)` | `Alloc,Mut` | Route `method` (`GET`, `POST`, ...) at exactly `path` to `h`. Routes are tried in the order they were added. Answers the route's index. |
| `routeStatic` | value | `(-> HttpRouter String String Int)` | `Alloc,Mut` | Serve GET requests under URL `prefix` (write it with its trailing slash: `/static/`) from the files under directory `dir`. Answers the mapping's index. |
| `routeNotFound` | value | `(-> HttpRouter HttpHandler Int)` | `Mut` | Replace the not-found handler. |
| `httpPathSafe` | value | `(-> String Bool)` |  | Whether a request path may reach the filesystem or a route at all: it starts with `/`, holds no NUL and no `\`, and has no empty segment (`//`) and no `..` segment. Decided on the DECODED path, so `%2e%2e` is `..` here. |
| `httpServeFile` | value | `(-> Int HttpReq String String Int)` | `Alloc,IO,Mut` | Serve the file that `req`'s path names under `prefix` out of `dir` to `fd`: 400 when the path is unsafe, 404 when the rest of the path is empty or names nothing or a directory, otherwise 200 with the content type of its extension and its bytes written whole. The path is checked before the filesystem is touched. |
| `routeDispatch` | value | `(-> HttpRouter Int HttpReq Int)` | `Alloc,IO,Mut` | Answer `req` on `fd`: an unsafe path is 400 before anything else is consulted; then the exact routes, in order; then the static prefixes, for GET (405 otherwise); then 405 when the path has a route for another method; then the not-found handler. Answers what the handler answered. |
| `httpServeOne` | value | `(-> HttpRouter Int Int)` | `Alloc,IO,Mut` | One connection, start to finish: read the request off `fd`, and either dispatch it or write the parser's refusal back with the status the error carries. Answers the handler's answer, or the status written for a refusal. The caller owns the socket - it set it blocking, and it closes it - and the arena scope around this call is the caller's too. |

## `IO`

`stdlib/IO.ax` — 24 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `writeStr` | value | `(-> Int String Int)` | `Alloc,IO` | Write all of `s` to `fd`, returning the number of bytes written or a negative errno. |
| `printlnLit` | value | `(-> Int Int)` | `Alloc,IO` |  |
| `println` | macro |  |  |  |
| `eprintln` | macro |  |  |  |
| `readFileLit` | value | `(-> Int String)` | `Alloc,IO,Mut` | The whole contents of the file at NUL-terminated path `cstr`, or an empty `Str` if it cannot be opened. |
| `readFile` | value | `(-> String String)` | `Alloc,IO,Mut` |  |
| `ioResult` | value | `(-> (Result Int Error) String String (Result Int Error))` | `Alloc,Mut` | A `Sys` answer re-wrapped with the path this layer knows. |
| `writeFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` | Write `s` to `path`, creating it or TRUNCATING what is there. Answers `(Ok bytes)`, or `(Err e)` whose code is the errno. |
| `appendFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` | Add `s` to the end of `path`, creating it if absent. Answers the `(Ok bytes)`, or `(Err e)` whose code is the errno. |
| `removeFile` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | Remove the file `path`. Answers 0, or a negative errno. |
| `renamePath` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` | Move `old` to `new`, answering 0 or a negative errno. |
| `copyFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` | Copy `src` onto `dst`, answering `(Ok bytes)` or `(Err e)`. `dst` is created or truncated. |
| `fileExists` | value | `(-> String Bool)` | `Alloc,IO,Mut` | True when `path` names something that can be opened for reading - a directory included. `isDir` separates them. |
| `isDir` | value | `(-> String Bool)` | `Alloc,IO,Mut` | True when `path` names a directory. |
| `fileSize` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | The size of `path` in bytes, or a negative errno. |
| `readErrno` | value | `(-> String Int)` | `Alloc,IO,Mut` | 0 when `path` can be read as a file, otherwise the errno saying why not: 2 missing, 13 not permitted, 21 a directory. |
| `makeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | Create the directory `path`, mode 0755. Answers 0, or a negative errno - `-17` (EEXIST) when it is already there. |
| `makeDirAll` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | Create `path` and every missing directory above it. Answers 0, or the negative errno of the first component that could not be made. |
| `removeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | Remove the EMPTY directory `path`. Answers 0, or a negative errno - `-66`/`-39` (ENOTEMPTY) when it still holds entries. Nothing here removes a tree: that is a loop over `listDir`, and it is the caller's to write, because a library that deletes recursively on one call is a library that deletes the wrong subtree once. |
| `listDir` | value | `(-> String (Vec Int))` | `Alloc,IO,Mut` | The entries of the directory `path`, as a Vec of `Str` - sorted by byte, with `.` and `..` removed. |
| `cwd` | value | `(Result String Error)` | `Alloc,IO,Mut` | The process's working directory as an absolute path: `(Ok path)`, or `(Err e)` whose code is the errno. See `Sys.sysGetCwd` for why this is two different syscalls underneath, and why it stopped answering `""` for every distinct reason it can fail. |
| `exit` | value | `(-> Int Int)` | `IO` |  |
| `die` | value | `(-> String Int Int)` | `Alloc,IO,Mut` | Print `s` to standard error and exit with `code`. Never returns. |
| `todo` | value | `(-> String a)` | `Alloc,IO,Mut` | Exit 70 with `todo: <what>` on standard error; types as any result and never returns. |

## `Intern`

`stdlib/Intern.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `internSlotOf` | value | `(-> String Int Int)` |  | The slot `s` probes first, in [0, cap). |
| `internNew` | value | `Int` | `Alloc,Mut` | `internDefaultCap` is a *slot* count, so it is passed straight to `internAllocTable` and not through `internWithCapacity`, which takes a *string* count and doubles it. Routing it through the latter would make a fresh interner 128 slots while its own documentation said 64. |
| `internWithCapacity` | value | `(-> Int Int)` | `Alloc,Mut` | An interner sized so `want` distinct strings fit without rehashing. |
| `internFree` | value | `(-> Int Int)` |  | Hand `it` back: the slot table, the `Vec`, and one share of every string in it. Answers 0, as `Vec.vecFree` and `Map.mapFree` do. |
| `internCap` | value | `(-> Int Int)` |  |  |
| `internCount` | value | `(-> Int Int)` |  | How many distinct strings have been interned. Ids are exactly 0..internCount-1, with no gaps - that is what "dense" means here, and it is what lets a caller size a side table by `internCount` and index it by id. |
| `internLookup` | value | `(-> Int Int String)` | `Alloc,Mut` | The string with id `id`, or an empty `Str` if `id` was never handed out. |
| `internFind` | value | `(-> Int String (Option Int))` |  | The id of a string equal in content to `s`, or `None`. |
| `internIntern` | value | `(-> Int String Int)` | `Alloc,Mut` | The id for `s`, interning it if its content is new. |

## `Json`

`stdlib/Json.ax` — 21 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `jsonNull` | value | `Int` | `Alloc,Mut` |  |
| `jsonBool` | value | `(-> Int Int)` | `Alloc,Mut` |  |
| `jsonNum` | value | `(-> Int Int)` | `Alloc,Mut` | A number from an integer. The raw text is rendered from the value, so `jsonNumText` is total for constructed values as well as parsed ones. |
| `jsonStr` | value | `(-> String Int)` | `Alloc,Mut` |  |
| `jsonArr` | value | `Int` | `Alloc,Mut` |  |
| `jsonObj` | value | `Int` | `Alloc,Mut` |  |
| `jsonIsNull` | value | `(-> Int Bool)` |  |  |
| `jsonBoolVal` | value | `(-> Int Int)` |  |  |
| `jsonInt` | value | `(-> Int Int)` |  | The integer value of a number, 0 for anything else. 0 is a real number, so a caller that must distinguish absence tests `jsonTag` first - the same contract `Utf8`'s -1 sentinel documents. |
| `jsonNumText` | value | `(-> Int String)` |  |  |
| `jsonStrVal` | value | `(-> Int String)` |  |  |
| `jsonArrLen` | value | `(-> Int Int)` |  |  |
| `jsonArrGet` | value | `(-> Int Int Int)` |  |  |
| `jsonArrPush` | value | `(-> Int Int Int)` | `Alloc,Mut` |  |
| `jsonObjLen` | value | `(-> Int Int)` |  |  |
| `jsonObjPut` | value | `(-> Int String Int Int)` | `Alloc,Mut` | The ONLY writer of the two parallel vecs, so they cannot desync. A repeated key appends rather than replacing, which is what a JSON reader that preserves what it was sent should do; `jsonGet` answers the first, matching the usual last-writer-loses reading being avoided here deliberately - LSP never sends duplicates, and inventing a replacement policy would be inventing behaviour no test can pin. |
| `jsonGet` | value | `(-> Int String Int)` |  | The value for `key`, or 0 when there is none. 0 is not a valid value pointer, so it is an unambiguous absence marker AT THIS LAYER - but `jsonTag` reports 0 as `JNULL`, so `jsonIsNull` cannot tell an absent member from one explicitly set to null. A caller that must distinguish the two tests against 0 directly, which is what `lsp.ax`'s dispatch does to tell a request from a notification: an absent `id` means notification, and a null `id` is a different thing the protocol does not let you answer the same way. |
| `jsonGetInt` | value | `(-> Int String Int)` |  |  |
| `jsonGetStr` | value | `(-> Int String String)` |  |  |
| `jsonWrite` | value | `(-> Int String)` | `Alloc,Mut` |  |
| `jsonParse` | value | `(-> String Int)` | `Alloc,Mut` | Parse a whole document: one value, then nothing but whitespace. Answers 0 on any error, which is why every accessor tolerates 0. |

## `Map`

`stdlib/Map.ax` — 26 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `mapHashPrime` | value | `Int` |  | 2^31 - 1, a Mersenne prime. No longer used by `mapHash` itself; kept because `Intern`'s polynomial string hash reduces modulo it, and a prime modulus is what makes that polynomial hash sound. |
| `mapHash` | value | `(-> Int Int)` |  | Hash `key` to a value in [0, 2^63). |
| `mapSlotOf` | value | `(-> Int Int Int)` |  | The slot `key` probes first, in [0, cap). |
| `mapNew` | value | `Map` | `Alloc,Mut` | An empty `Map` with `mapDefaultCap` slots. |
| `mapNewRefVals` | value | `Map` | `Alloc,Mut` | An empty `Map` whose VALUES it owns a share of: the value array carries the array form, so `mapFree` releases every value in it. Keys stay `Int`s and stay a leaf, which is what they are - `mapInsert`'s key parameter is `Int`, not a type variable. |
| `mapWithCapacity` | value | `(-> Int Map)` | `Alloc,Mut` | An empty `Map` sized so that `want` entries fit without rehashing. |
| `mapWithCapacityRefVals` | value | `(-> Int Map)` | `Alloc,Mut` | `mapWithCapacity`'s owning twin. See `mapNewRefVals`. |
| `mapRoundUpPow2` | value | `(-> Int Int)` |  | `n` rounded up to a power of two, at least `mapDefaultCap`. |
| `mapFree` | value | `(-> Map Int)` |  | Hand `m` back: the three arrays go with it, and on a `mapNewRefVals` table so does one share of every value still in it. Answers 0, as `Vec.vecFree` does and for the same reason. |
| `mapLen` | value | `(-> Map Int)` |  |  |
| `mapCap` | value | `(-> Map Int)` |  |  |
| `mapUsed` | value | `(-> Map Int)` |  | Slots that are live or tombstoned. Exposed because it is the number that explains a rehash, and a test that could not see it would have to infer growth from timing. |
| `mapOwnsVals` | value | `(-> Map Bool)` |  | Whether this table owns a share of every value it holds - the `mapNewRefVals` half. Word 6 of the header, and not a test of the value array's shape word: see `mapAllocTable`. |
| `mapKeyAt` | value | `(-> Map Int Int)` |  | Read the key, or the value, out of slot `i`. |
| `mapValAt` | value | `(-> Map Int Int)` |  | The value in slot `i`. See `mapKeyAt` above for the bounds rule and why `mapStateAt` is not exported beside these two. |
| `mapNextSlot` | value | `(-> Int Int Int)` |  | The next slot after `i`. |
| `mapHas` | value | `(-> Map Int Bool)` |  |  |
| `mapGet` | value | `(-> Map Int Int Int)` |  | The value for `key`, or `dflt` if `key` is absent. |
| `mapGetStr` | value | `(-> Map Int String String)` |  | The value for `key` read as a `String`, or `dflt` if `key` is absent. |
| `mapInsert` | value | `(-> Map Int a Int)` | `Alloc,Mut` | Insert or overwrite, growing first if the load factor demands it. |
| `mapRemove` | value | `(-> Map Int Int)` | `Mut` | Delete `key`. Answers 0; see `mapInsert` for why no mutator here answers the handle. |
| `mapLiveFrom` | value | `(-> Map Int (Option Int))` | `Alloc` | The first live slot at or after `i`, or `None` when the table has no live slot from there on. `(mapLiveFrom m 0)` starts an iteration; `(mapLiveFrom m (+ prev 1))` continues one. |
| `mapKeys` | value | `(-> Map (Vec Int))` | `Alloc,Mut` | Every live key, and every live value, in one shared slot order: the `j`th key and the `j`th value came out of the same slot, so the two vectors zip. Both are freshly allocated and the caller owns them. |
| `mapValues` | value | `(-> Map (Vec Int))` | `Alloc,Mut` | Every live value, in the same slot order `mapKeys` uses, so the two vectors zip element for element. |
| `mapSumVals` | value | `(-> Map Int)` |  | The sum of every live value. |
| `mapSumKeys` | value | `(-> Map Int)` |  | The sum of every live key. Together with `mapSumVals` and `mapLen` this pins down a small map's contents well enough to test with. |

## `Mem`

`stdlib/Mem.ax` — 13 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `memAlloc` | value | `(-> Int Int)` | `Alloc` | Mem - raw memory operations, in Axiom. |
| `memAllocMapped` | value | `(-> Int Int Int)` | `Alloc,Mut` | The same allocation, declaring which of the block's words hold REFERENCES: bit i of `map` says payload word i is a handle to another counted block, so releasing this block releases that one too (docs/memory-model.md MM-LIFE-2d, the record form). |
| `memMarkArray` | value | `(-> Int Int Int)` | `Mut` | The ARRAY FORM: payload words 0..n-1 of this block are handles to other counted blocks, so releasing it releases all of them, and `n` is the caller's ELEMENT count (docs/memory-model.md MM-LIFE-2d names the two forms; the array form landed 2026-08-24 and took its own length 2026-09-03). |
| `memMarkLeaf` | value | `(-> Int Int)` | `Mut` | The inverse, and it is not symmetry for its own sake: it is what a container's GROWTH needs. Doubling a buffer copies the elements to a new block WITHOUT retaining them - the shares move - so releasing the old block while it still reads as an array would spend every share twice. Clearing the bit first makes the old block a leaf, and its release then reclaims the block and touches nothing it used to hold. |
| `memCopy` | value | `(-> Int Int Int Int)` | `Mut` | THERE IS NO `memIsArray`, AND THE REASON IS A MEASURED CRASH. |
| `memSet` | value | `(-> Int Int Int Int)` | `Mut` | Set `count` bytes at `addr` to `value` (low 8 bits). Returns `addr`. |
| `memCmp` | value | `(-> Int Int Int Int)` |  | Compare `count` bytes. 0 if equal, otherwise the signed difference of the first differing byte pair (so the result orders like `memcmp`). |
| `memGetWord` | value | `(-> Int Int Int)` |  | The word at `index`. A word is what it is: an integer, or a handle, or a reference whose type this layer does not know. It answers `Int` because that is the truth about a machine word - it used to answer a type variable, which let the CALLER name any type at all and get it, including a reference, which then dereferenced. See `AX3040`. |
| `memGetWordStr` | value | `(-> Int Int String)` |  | The String view, for the typed accessors built on this layer - `tokenLexeme`, `diagCode`, and the several dozen others whose own signature says `String` and whose body is one word read. |
| `memGetWordVec` | value | `(-> Int Int (Vec a))` |  | The `Vec` view of the word at `index`. A `Vec` is a handle - one word, exactly what `memGetWord` answers - so this reinterprets and converts nothing. The cast is HERE, at a return inside a signature that carries the type, for the reason `memGetWordStr` gives: a cast at an argument root classifies that value's evidence 0 and drops its retain or its release (docs/memory-model.md MM-VAL-22, measured). |
| `memSetWord` | value | `(-> Int Int a Int)` | `Mut` | Storing a word here is the moment a value can leave the type system's sight: `(cast Int value)` erases whatever `value` was, and the machine word that lands in `addr` is indistinguishable from an integer forever after. That is the whole of MM-LIFE-2c's co-ownership blocker, and the fix is one line - the store takes a SHARE of what it is about to hide. |
| `memGetByte` | value | `(-> Int Int Int)` |  |  |
| `memPutByte` | value | `(-> Int Int Int Int)` | `Mut` |  |

## `Par`

`stdlib/Par.ax` — 4 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `parMapWords` | value | `(-> (-> Int Int) Int Int (Vec Int))` | `Alloc,IO,Mut` | Run `f i` for every `i` in `0 .. n`, at most `width` at once, answering the results in SUBMIT order. |
| `parArgvVector` | value | `(-> (Vec String) Int)` | `Alloc,Mut` | A NULL-terminated array of char* from a Vec of `String`, which is the shape `execve` and `posix_spawn` both take. |
| `parRunOne` | value | `(-> (Vec String) (Result Int Error))` | `Alloc,IO,Mut` | Run one argv - element 0 is the program, looked up on `PATH` the way `sysRunPath` does it. |
| `parRunAll` | value | `(-> (Vec (Vec String)) Int (Vec Int))` | `Alloc,IO,Mut` | Run every command in `cmds` at up to `width` at once, answering their exit codes in the order they appear in `cmds`. |

## `Path`

`stdlib/Path.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `pathLastSlash` | value | `(-> String (Option Int))` |  | The last `/` in `p`, or `None`. Everything below is a decision about this one index. `compat/SENTINELS`'s direction rule is "absence wants `Option`", and this is the primitive every caller in this file goes through - `pathExtIndex` is the one exception, and it goes straight to the raw `-1` helper below because it needs the sentinel back in arithmetic (`(+ slash 1)` is 0, correctly, when there is no slash at all), not a value to branch on. |
| `pathDir` | value | `(-> String String)` | `Alloc,Mut` | Everything up to and INCLUDING the last `/`, or "" when `p` names something in the working directory. |
| `pathBase` | value | `(-> String String)` | `Alloc,Mut` | Everything after the last `/` - the file name on its own, or `p` entire when there is no separator. |
| `pathWithSlash` | value | `(-> String String)` | `Alloc,Mut` | A directory name that ends in `/`, so concatenation forms a path. |
| `pathJoin` | value | `(-> String String String)` | `Alloc,Mut` | `dir` and `name` as one path, with exactly one `/` between them. |
| `pathExtIndex` | value | `(-> String (Option Int))` |  | The index of the extension's `.` within `p`, or `None`. |
| `pathExt` | value | `(-> String String)` | `Alloc,Mut` | The extension INCLUDING its dot (`".ax"`), or "" when there is none. |
| `pathStem` | value | `(-> String String)` | `Alloc,Mut` | The base name with its extension removed: `"src/main.ax"` is `"main"`. What a driver names an output after. |
| `pathReplaceExt` | value | `(-> String String String)` | `Alloc,Mut` | `p` with its extension replaced by `ext`, which carries its own dot. `(pathReplaceExt "build/main.ax" ".ll")` is `"build/main.ll"`, and a path with no extension simply gains one. |
| `pathIsAbsolute` | value | `(-> String Bool)` |  | True when `p` starts at the root. A relative path is resolved against the working directory, which is why `Sys.sysGetCwd` exists. |

## `Pre`

`stdlib/Pre.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `when` | macro |  |  | Axiom standard prelude — macros and utilities. |
| `unless` | macro |  |  | ;; unless — evaluate body unless test is true ;; (unless test body) -> (if test 0 body) |
| `range` | macro |  |  | ;; range — the counted loop: `(range i 0 n body)` is `0..n` ;; (range i lo hi body) -> `body` once per `i` in [lo, hi), ascending, ;; with both ends read ONCE. |
| `cond2` | macro |  |  | ;; cond2 — two-condition branching plus else ;; (cond2 t1 b1 t2 b2 els) -> (if t1 b1 (if t2 b2 els)) |
| `cond3` | macro |  |  | ;; cond3 — three-condition branching plus else ;; (cond3 t1 b1 t2 b2 t3 b3 els) -> (if t1 b1 (if t2 b2 (if t3 b3 els))) |
| `deriveEq` | macro |  |  | ;; deriveEq — structural equality for a data type, derived at the ;; point of use: `(deriveEq Color)` generates `eqColor : Color -> ;; Color -> Bool`, one match arm per constructor, answered from the ;; declaration list at expansion time (macro-system.md MAC-CAP-5/9). ;; The nullary form: works for any sum of nullary constructors, which ;; is the enum case. Fieldful sums want the impl form written where ;; the Eq trait is in scope — see macro-system.md section 10.2. |
| `deriveShow` | macro |  |  | ;; deriveShow — the constructor's own name, as a String, for any ;; `data` type: `(deriveShow Shape)` generates `showShape : Shape -> ;; String`. This is what `syntax/name` exists for (macro-system.md ;; MAC-CAP-5), and the only way to get a constructor's spelling into ;; a running program: a tag is an integer at run time and the name ;; lives only in the declaration list the expander reads. ;; ;; Fieldful constructors are matched and their fields ignored - ;; `(syntax/binders C f)` supplies exactly arity-of-C binders, so one ;; template covers arities 0, 1 and n without an arity test. Rendering ;; the FIELDS would need each field's type to pick a printer, and a ;; macro cannot see a type (MAC-CAP-7); a program that wants that ;; writes the arm itself. |
| `deriveArity` | macro |  |  | ;; deriveArity — how many fields the value's constructor carries: ;; `(deriveArity Shape)` generates `arityShape : Shape -> Int`. The ;; count is `syntax/arity`'s answer, folded to a literal per arm, and ;; it is not derivable any other way at run time: a heap block records ;; its tag, never its field count (memory-model.md MM-VAL-6). |
| `showOr` | macro |  |  | ;; showOr — `(showOr T x fallback)` renders `x` with the type's ;; derived `showT` when the program has one, and answers `fallback` ;; when it does not. `syntax/defined` decides that at expansion time ;; and the losing branch is DELETED rather than compiled, which is ;; the whole point: the branch that names `showT` is only well-typed ;; in a program that derived it, so a runtime `if` over both arms ;; would be AX3001 in every program that did not. |

## `Rpc`

`stdlib/Rpc.ax` — 7 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `rdNew` | value | `(-> Int Int)` | `Alloc,Mut` |  |
| `rdBuf` | value | `(-> Int String)` |  |  |
| `rdFilled` | value | `(-> Int Int)` |  |  |
| `rdConsumed` | value | `(-> Int Int)` |  |  |
| `rdReseat` | value | `(-> Int Int Int Int)` | `Alloc,Mut` | Re-seat a reader on freshly allocated storage, carrying `u` bytes of not-yet-consumed input from `addr`. |
| `rpcRead` | value | `(-> Int String)` | `Alloc,IO,Mut` | Read one whole message and answer its body. An empty Str means the stream ended or broke - the caller stops, which is what an LSP does when its client goes away without saying `exit`. |
| `rpcWrite` | value | `(-> Int String Int)` | `Alloc,IO,Mut` | Frame `body` and write it. |

## `Str`

`stdlib/Str.ax` — 31 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `strWrap` | value | `(-> Int Int String)` | `Alloc,Mut` | Wrap `len` bytes at `bytes` as a `Str` without copying. |
| `strWrapOwned` | value | `(-> Int Int Int String)` | `Alloc,Mut` | The same, naming the block that OWNS the bytes (MM-LIFE-2d's `Str` half): word 2 holds the handle whose death should free them, or 0 when no such block exists - a literal's bytes are loader-resident, a syscall's are the kernel's, and an interior wrap over an arena keep block belongs to the arena. A slice inherits its parent's owner rather than naming the parent, so the chain is one hop deep however many times a slice is sliced, and the address counted is never interior. |
| `strAlloc` | value | `(-> Int String)` | `Alloc,Mut` | A `Str` over freshly allocated, zeroed space for `len` bytes. |
| `strFromLit` | value | `(-> Int String)` | `Alloc,Mut` | A `Str` sharing the bytes at a NUL-terminated address. |
| `cstrLen` | value | `(-> Int Int Int)` |  | Length of NUL-terminated bytes at `addr`, scanning from `i`. |
| `strLen` | value | `(-> String Int)` |  |  |
| `strData` | value | `(-> String Int)` |  |  |
| `strOwner` | value | `(-> String Int)` |  | The block owning this string's bytes, or 0 for bytes no block owns (a literal's, a syscall buffer's, an arena keep block's interior). |
| `strByte` | value | `(-> String Int Int)` |  | The byte at `i`, or 0 when `i` is out of range. |
| `strCStr` | value | `(-> String Int)` |  | The bytes of `s` as a NUL-terminated address, for handing to a syscall. |
| `strIsEmpty` | value | `(-> String Bool)` |  |  |
| `strCmp` | value | `(-> String String Int)` |  | 0 when equal; otherwise negative if `a` sorts before `b`, positive if after - lexicographic by unsigned byte, with a shorter prefix sorting first. |
| `strEq` | value | `(-> String String Bool)` |  | Equality, which is NOT `strCmp a b == 0` even though it answers the same thing. `strCmp` must produce an ORDERING, so it memcmps the shared prefix before it ever looks at the lengths - and equality does not need the ordering. Two strings of different lengths are unequal whatever their bytes say, so checking the length first turns the commonest case, a miss, into two word loads and a compare. |
| `strSlice` | value | `(-> String Int Int String)` | `Alloc,Mut` | The `count` bytes of `s` starting at `start`, sharing `s`'s storage. |
| `strDup` | value | `(-> String String)` | `Alloc,Mut` | An owned, NUL-terminated copy of `s`. |
| `strConcat` | value | `(-> String String String)` | `Alloc,Mut` |  |
| `strFindByte` | value | `(-> String Int Int (Option Int))` |  | Index of the first `byte` at or after `from`, or `None`. |
| `strStartsWith` | value | `(-> String String Bool)` |  |  |
| `strIsDigit` | value | `(-> Int Bool)` |  |  |
| `strIsAlpha` | value | `(-> Int Bool)` |  |  |
| `strIsSpace` | value | `(-> Int Bool)` |  | Space, tab, LF, CR - and nothing else. Not `char::is_whitespace`: VT and FF are AX1001 to this language's lexer, and a formatter that skipped them turned a refused file into an accepted one. |
| `strHexVal` | value | `(-> Int (Option Int))` |  | The value of a hex digit, or `None`. Stated as the VALUE and not as a predicate because the value is what every caller needed: the JSON parser's `\uXXXX` escape and the language server's percent-decoding each carried a byte-identical copy of this ladder under its own name, while the predicate here had no caller at all. |
| `strIsHexDigit` | value | `(-> Int Bool)` |  |  |
| `strSplit` | value | `(-> String Int (Vec Int))` | `Alloc,Mut` | Every segment of `s` between occurrences of `byte`, in order, as a Vec of Str handles. Empty segments are KEPT: a `PATH` entry of "" means the working directory, and a caller that wants them dropped can drop them, while a caller that needs them cannot get them back. `strSplit "" 58` answers one empty segment, and `strSplit "a:" 58` answers two - the same rule as splitting on a separator anywhere else, and the one that makes the segment count equal the separator count plus one. |
| `strSplitFrom` | value | `(-> String Int Int (Vec Int) Int)` | `Alloc,Mut` |  |
| `strFromByte` | value | `(-> Int String)` | `Alloc,Mut` | A one-byte `Str` holding `b`. The compiler driver and the JSON encoder each had this three-line allocate-and-store under a private name; it is a `Str` constructor, so it lives with the others. |
| `strLower` | value | `(-> String String)` | `Alloc,Mut` | `s` with every ASCII upper-case byte lowered, or `s` itself when it has none - so a header name already in the form a table wants is not copied. Bytes above 127 pass through untouched: this is the ASCII fold a case-insensitive header table needs, not a Unicode case mapping. |
| `strFind` | value | `(-> String String Int (Option Int))` |  | The index of the first occurrence of `needle` in `s` at or after `from`, or `None`. An empty needle is found at `from` whenever `from` is inside `s` or at its end, which is the rule that makes `(strFind s "" (strLen s))` answer `(Some (strLen s))` rather than nothing. `no-alloc` came off on 2026-08-31: the `(Some found)` answer allocates. Accepted until then because a constructor contributed nothing to the effect row (`MM-EXEC-9a`). `no-io` and `no-foreign` are unchanged. |
| `strTrim` | value | `(-> String String)` | `Alloc,Mut` | `s` without the `strIsSpace` bytes at either end, as a SLICE that shares `s`'s storage - so it is not NUL-terminated unless it ends where `s` does, exactly as `strSlice` says. A string that is all space trims to "". |
| `strParseInt` | value | `(-> String (Option Int))` |  | The decimal integer `s` spells - an optional `-`, then one or more ASCII digits and nothing else - or `None`: for an empty string, a sign alone, any other byte, and any value outside the 64-bit range. |
| `format` | macro |  |  | `format` — a String, built at compile time from a literal's runs and holes, or the hole lowering applied to anything else. |

## `Sys`

`stdlib/Sys.ax` — 84 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sysResult` | value | `(-> String Int (Result Int Error))` | `Alloc` | write(fd, buf, count) -> bytes written, or a negative/errno result. A raw syscall answer turned into a `Result`. |
| `stdin` | value | `Int` |  |  |
| `stdout` | value | `Int` |  |  |
| `stderr` | value | `Int` |  |  |
| `sysWriteFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO` | write(2): `Ok` bytes written - possibly fewer than asked, which is what `sysWriteAllFd` below exists to retry - or `Err` carrying the errno. `(Result Int Error)` since 2026-09-03; the sentinel it replaced is recorded in `sysWriteAllFd`'s header, with why it stood and what let it go. |
| `sysWriteAllFd` | value | `(-> Int Int Int Int Int)` | `Alloc,IO` | THREE OUTCOMES, AND THE Int CHANNEL HELD TWO. Until 2026-08-30 this answered `done` when `write` returned exactly 0 - a short, NON-NEGATIVE count, indistinguishable from the complete one. The comment above calls treating a short write as success "the classic way to truncate output", and that is what this did in the one case it cannot retry. |
| `sysReadFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO` | read(2): `Ok` bytes read, `Ok 0` at end of input, or `Err` carrying the errno. `(Result Int Error)` since 2026-09-03, on the same terms as `sysWriteFd`: every reader in the tree matches the call directly and pays for no block on the bytes-arrived path. |
| `sysOpenPath` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | ANSWERS `(Result Int Error)` - the descriptor, or the errno `open` refused with. This is the port `docs/error-model.md` ERR-ADOPT-1 calls the canonical one: a failed open is what a reader checks first when deciding whether the error model is real, and ENOENT, EACCES and EISDIR are three different things a caller does three different things about. As an `Int` they were all "negative". |
| `sysCloseFd` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Close a descriptor. |
| `sysExitWith` | value | `(-> Int Int)` | `IO` |  |
| `sysFailed` | value | `(-> Int Bool)` |  |  |
| `sysErrno` | value | `(-> Int Int)` |  |  |
| `sysReadFile` | value | `(-> Int String)` | `Alloc,IO,Mut` | Open, read entire contents, close.  Returns an empty string on any error (missing file, permission, etc.). |
| `sysArgc` | value | `Int` | `IO` | How many arguments the process received, including the program name. |
| `sysArg` | value | `(-> Int String)` | `Alloc,IO,Mut` | The i-th argument as a Str (0 is the program name), or "" when `i` is out of range. The bytes are the process's own argv storage - NUL-terminated, alive for the whole run, never freed or moved - so wrapping them without copying is sound. |
| `sysWriteFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO` | Write `s` to `path`, creating or truncating it. Answers the number of bytes written, or a negative errno from whichever step failed. |
| `sysAppendFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO` | Append `s` to `path`, creating it if it is not there. Answers the number of bytes written, or a negative errno. |
| `sysRename` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Rename `old` to `new`, answering 0 or `-errno`. Both are NUL-terminated char* - `strCStr`. |
| `sysUnlink` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Remove `path`. Answers 0, or `-errno`. |
| `sysMkdir` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Create directory `path` with `mode`. Answers 0, or `-errno` - which is `-17` (EEXIST) when it is already there, and callers usually want to treat that as success. |
| `sysDirMode` | value | `Int` |  | 0755, the mode a directory usually wants. A nullary function because that is how this language spells a constant. |
| `sysRmdir` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Remove the empty directory `path`. Answers 0, or `-errno`. |
| `sysFileExists` | value | `(-> Int Bool)` | `Alloc,IO` | 1 when `path` names something that can be opened for reading. |
| `sysFileSize` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | The size of `path` in bytes, or `-errno`. Seeks to the end, which is what the size IS - no struct, no layout, no per-target record. |
| `sysReadErrno` | value | `(-> Int Int)` | `Alloc,IO,Mut` | 0 when `path` can be opened AND read as a file, otherwise the errno saying why not. |
| `sysIsDir` | value | `(-> Int Bool)` | `Alloc,IO,Mut` | True when `path` names a directory. |
| `sysReadDir` | value | `(-> Int (Vec Int))` | `Alloc,IO,Mut` | Every name in the directory `path`, as a Vec of owned `Str` - `.` and `..` INCLUDED, in whatever order the filesystem gives them. |
| `sysGetCwd` | value | `(Result String Error)` | `Alloc,IO,Mut` | The process's working directory as an absolute path: `(Ok path)`, or `(Err e)` whose code is the errno the kernel refused with. |
| `sysEnv` | value | `(-> String String)` | `Alloc,IO,Mut` | The value of the environment variable `name`, or "" when it is unset. |
| `sysEnvp` | value | `Int` | `Alloc,IO,Mut` | A NULL-terminated copy of the process's own environment vector, in the form a child expects. |
| `sysSpawn` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Start `path` with argument vector `argv` and environment `envp`. `(Ok pid)`, or `(Err e)` whose code is the errno - and `Err` means no child exists, which is what a caller must not confuse with a child that started and failed. |
| `sysWaitPid` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` | Wait for `pid`. `(Ok status)` is the raw wait status; `(Err e)` carries the errno of a wait that could not be performed. |
| `sysExitCode` | value | `(-> Int Int)` |  | The exit code carried by a wait status, for a child that exited normally. |
| `sysTermSignal` | value | `(-> Int Int)` |  | The signal that killed a child, or 0 if it exited normally. |
| `sysRun` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Run `path` to completion and answer its exit code. |
| `sysRunPath` | value | `(-> String Int Int (Result Int Error))` | `Alloc,IO,Mut` | Run `name`, searching `PATH` for it when it contains no slash. |
| `sysGetPid` | value | `Int` | `IO` | The calling process's own id - the per-session suffix scratch files need so two concurrent processes cannot collide. The syscall takes no arguments; the unused ones are simply zero. |
| `sysNowMicros` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Microseconds now, from the platform's cheapest correct clock: Darwin answers gettimeofday's timeval (realtime; Darwin's syscall table has no clock_gettime), Linux and FreeBSD answer CLOCK_MONOTONIC via clock_gettime - under the id `clockMonotonicId` names, because the id is not portable: 1 on Linux, and on FreeBSD 4, where 1 is CLOCK_VIRTUAL, the process's CPU time. That one was a literal here until 2026-08-29, and a clock that measures CPU time never runs backwards either, so nothing would have caught it. |
| `sysNowMonotonic` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Microseconds from a clock that NEVER steps backwards, or `Err` when this platform has none. The 16-byte buffer is the caller's, as above, so a timing loop allocates nothing on the path that answers. |
| `netSocketTcp` | value | `(Result Int Error)` | `Alloc,IO` | A TCP socket, as `(Result Int Error)`. |
| `netSocketTcp6` | value | `(Result Int Error)` | `Alloc,IO` | The same over IPv6. Its own name rather than a family parameter, because the family is not a runtime choice at this layer: a caller already picked a builder when it made the address, and a socket whose family disagrees with the address it is given fails at `bind` and not here. |
| `netAddr4Bytes` | value | `Int` |  | How many bytes an address of each family occupies, and how big a buffer that must take either has to be. |
| `netAddr6Bytes` | value | `Int` |  |  |
| `netAddrMaxBytes` | value | `Int` |  | What `netAcceptFrom` wants, which is the larger of the two: a caller does not get to know the peer's family until it has the peer. |
| `netAddr4` | value | `(-> Int Int Int Int Int Int Int)` | `Mut` | Write an IPv4 `sockaddr_in` into `buf`, which must hold 16 bytes, and answer `buf`. The four octets are given in reading order, so 127.0.0.1 is `127 0 0 1`. |
| `netAddr6` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int)` | `Mut` | Write an IPv6 `sockaddr_in6` into `buf`, which must hold `netAddr6Bytes`, and answer `buf`. |
| `netAddrFamily` | value | `(-> Int Int)` |  | The address family in a `sockaddr` - `afInet`, `afInet6`, or whatever else the kernel wrote there. |
| `netAddrPort` | value | `(-> Int Int)` |  | The port in a `sockaddr`, decoded from network order. This one does NOT branch on the platform or the family: both layouts diverge in the four bytes before it and agree from byte 2 on, so `sin_port` and `sin6_port` are the same two bytes in the same place. |
| `netAddrSize` | value | `(-> Int Int)` |  | How many bytes of `addr` a syscall must be given, read off the family the buffer carries. This is what `netBind` and `netConnect` pass, and the reason neither of them takes a length. |
| `netBind` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Bind a socket to an address built by `netAddr4` or `netAddr6`. |
| `netListen` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netAccept` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Accept a connection, answering `Ok` the new socket or `Err` the errno - `(Result Int Error)` since 2026-09-03; a would-block answer is `Err` carrying EAGAIN, which `netWouldBlock` still recognises from the negated code - and throw the peer's address away. `netAcceptFrom` below keeps it; this is the form for a caller that does not want the buffer, and it passes NULL for both of `accept`'s out-parameters. |
| `netAcceptFrom` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Accept a connection AND KEEP THE PEER'S ADDRESS. Answers the new socket or a negative errno, exactly as `netAccept` does, and fills `addr` with the peer's `sockaddr`, which `netAddrFamily`, `netAddrPort` and `netAddrText` read. |
| `netAddrLenRead` | value | `(-> Int Int)` |  | The length the kernel wrote back into a `netAcceptFrom` cell - 16 for a v4 peer, 28 for a v6 one - as normalised by `netAcceptFrom`. It is the REAL length of the peer's address, which is not necessarily how much of it arrived: Linux and Darwin copy what fits and report the whole size, FreeBSD reports the copied size and `netAcceptFrom` reads the whole one back off the BSD length byte, so a value larger than the `cap` that went in means the address was cut short on every target. `netAcceptFrom` acts on that itself; a caller reads this to log the family it could not store. |
| `netAddrText` | value | `(-> Int String)` | `Alloc,Mut` | Render an address as text: a dotted quad for `afInet`, RFC 5952 form for `afInet6`. |
| `netAddrTextPort` | value | `(-> Int String)` | `Alloc,Mut` | The same, with the port, in the form a URL authority uses: `127.0.0.1:80` and `[::1]:80`. |
| `netSetBlocking` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Take a descriptor OUT of non-blocking mode, preserving the other flags it carries. The counterpart of `netSetNonBlocking`, and what a caller that handles one connection synchronously wants from `netAccept`'s result. |
| `netConnect` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Connect to an address built by `netAddr4` or `netAddr6`. The length comes off the family in the buffer for the same reason `netBind`'s does, and was the same literal 16. |
| `netShutdown` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netSetOptInt` | value | `(-> Int Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Set an integer-valued socket option. The value crosses as four bytes in the host's own order, which is what the kernel reads an `int` option as - unlike an address, this one is NOT network order. That is `netPutInt32`, which `netAcceptFrom`'s `socklen_t` cell needs for the same reason. |
| `netSetNonBlocking` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Put a descriptor into non-blocking mode, preserving the flags it already carries - a bare `F_SETFL` of the one flag would clear the access mode with it. |
| `netWouldBlock` | value | `(-> Int Bool)` |  | Whether a negative answer means "nothing to take yet" rather than a broken socket. This is the whole reason `eAgain` is a capability: the number is 35 on Darwin and 11 on Linux, so an event loop written against a literal runs correctly on the machine it was written on. |
| `netPollBufBytes` | value | `(-> Int Int)` |  | How many bytes an event buffer for `n` events needs on this platform. |
| `netPollCreate` | value | `(Result Int Error)` | `Alloc,IO` | A readiness descriptor, as `(Result Int Error)`. |
| `netPollAddRead` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Watch `fd` for readability. `rec` is scratch of `pollEventSize` bytes. |
| `netPollDelRead` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netPollWait` | value | `(-> Int Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Wait for readiness, answering `Ok` how many events landed in `buf` or `Err` the errno - `(Result Int Error)` since 2026-09-03, matched directly by every wake loop so the wake itself builds no block. A NEGATIVE `timeoutMs` BLOCKS INDEFINITELY, which is what a server's accept loop wants; zero polls and returns at once. |
| `netPollFdAt` | value | `(-> Int Int Int)` |  | The descriptor named by event `i` of a buffer `netPollWait` filled. |
| `sysRandomBytes` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Fill `n` bytes at `buf` with kernel entropy. `(Ok 0)`, or `(Err e)` whose code is the errno - and on `Err` the buffer's contents are unspecified, so a caller must not read them. |
| `sysSigBit` | value | `(-> Int Int)` |  | The `sigset_t` bit for a signal. SIGNAL N IS BIT N-1, an off-by-one that is easy to write the other way and yields the neighbouring signal's mask rather than an error. |
| `sysSignalBlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut` | Block the signals in `mask` so they become observable instead of fatal. `setbuf` is caller scratch of at least 16 bytes: the mask is written as one 64-bit word, and the kernel then copies ITS OWN `sigset_t` width out of the buffer - `sigsetBytes`, which is 4 on Darwin, 8 on Linux and 16 on FreeBSD. Sixteen covers every target, and the bytes between the word and that width are zeroed here rather than left to whatever the caller's buffer held, because on FreeBSD they are signals 65 through 128 and a stale byte there blocks one. Answers `(Result Int Error)`; `Ok 0` on success. Runs once, before a server forks, so that every worker inherits the mask. |
| `netSignalOpen` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Watch the signals in `mask` on the readiness descriptor `pfd`, and answer a HANDLE to pass back to `netPollSignalAt` - the signal descriptor on Linux, and 0 on the BSDs, which need none. |
| `netPollSignalAt` | value | `(-> Int Int Int Int (Option Int))` | `IO` | The signal named by event `i`, or `None` when that event is not a signal at all. `sigHandle` is what `netSignalOpen` answered and `scratch` is caller scratch of at least `sigInfoSize` bytes. |
| `sysKill` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO` | Send a signal, which is how a test raises one against itself. |
| `sysForkProcess` | value | `Int` | `IO` | Duplicating this process |
| `sysTermStateBytes` | value | `Int` |  | How many bytes a saved terminal state occupies, which is how large the buffer a caller hands `sysTermSave`, `sysTermRaw` and `sysTermRestore` must be. 72, 36 or 44 depending on the target; 0 where there is no `termios` at all. |
| `sysTermSizeBytes` | value | `Int` |  | The bytes `sysTermSize` writes. 8 on every target that has one; see the section header for why this number is here and not in `Sys.Platform`. |
| `sysIsatty` | value | `(-> Int Bool)` | `Alloc,IO` | True when `fd` is a terminal. |
| `sysTermSave` | value | `(-> Int Int Int)` | `IO` | Read `fd`'s current terminal attributes into `save`, which must hold `sysTermStateBytes` bytes. 0 on success, or a negative result. |
| `sysTermRestore` | value | `(-> Int Int Int)` | `IO` | Write `state` back to `fd` as its terminal attributes: 0, or a negative result. |
| `sysTermRaw` | value | `(-> Int Int Int Int)` | `Alloc,IO,Mut` | Put `fd` into raw mode, having first saved its current state into `save` (`sysTermStateBytes` bytes, owned by the caller). 0, or a negative result. |
| `sysTermSize` | value | `(-> Int Int Int)` | `IO` | Read `fd`'s window size into `buf` (`sysTermSizeBytes` bytes): 0, or a negative result. `sysTermRows` and `sysTermCols` read the answer back out. |
| `sysTermRows` | value | `(-> Int Int)` |  | Rows out of a buffer `sysTermSize` filled. `ws_row` is an `unsigned short` at offset 0 on every target, little-endian. |
| `sysTermCols` | value | `(-> Int Int)` |  | Columns: `ws_col`, the second `unsigned short`. |

## `Sys.Platform`

`stdlib/Sys/Platform.darwin.ax` — 105 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sysRead` | value | `Int` |  | Sys.Platform - Darwin (macOS) syscall numbers and flags. |
| `sysWrite` | value | `Int` |  | write(fd, buf, count) - BSD 4 |
| `sysOpen` | value | `Int` |  | open(path, flags, mode) - BSD 5 |
| `sysClose` | value | `Int` |  | close(fd) - BSD 6 |
| `sysExit` | value | `Int` |  | exit(status) - BSD 1 |
| `sysLseek` | value | `Int` |  | lseek(fd, offset, whence) - BSD 199 |
| `openNeedsDirFd` | value | `Int` |  | Darwin has a real `open`, so no `openat` indirection is needed. `Sys.ax` branches on this rather than on an OS name, so adding a platform never means editing portable code. |
| `atFdCwd` | value | `Int` |  | Unused on Darwin (see `openNeedsDirFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `oRdonly` | value | `Int` |  |  |
| `oWronlyCreateTrunc` | value | `Int` |  | O_WRONLY \| O_CREAT \| O_TRUNC = 0x0001 \| 0x0200 \| 0x0400 |
| `oWronlyCreateAppend` | value | `Int` |  | O_WRONLY \| O_CREAT \| O_APPEND = 0x0001 \| 0x0200 \| 0x0008 |
| `seekEnd` | value | `Int` |  |  |
| `seekSet` | value | `Int` |  |  |
| `spawnUsesPosixSpawn` | value | `Int` |  | Starting a child process. |
| `sysPosixSpawn` | value | `Int` |  | posix_spawn - BSD 244. |
| `sysWait4` | value | `Int` |  | wait4(pid, status, options, rusage) - BSD 7. |
| `sysFork` | value | `Int` |  | fork() - BSD 2. `sysSpawn` does not reach it, because `spawnUsesPosixSpawn` selects `posix_spawn` here - but `sysForkProcess` does, and this used to be a placeholder 0 for that reason. |
| `sysForkArg` | value | `Int` |  |  |
| `sysExecve` | value | `Int` |  |  |
| `sysUnlinkNum` | value | `Int` |  | unlink(path) - BSD 10. |
| `sysMkdirNum` | value | `Int` |  | mkdir(path, mode) - BSD 136. Darwin has the plain call, so `openNeedsDirFd` is 0 here and `sysMkdir` uses the two-argument form. |
| `sysRmdirNum` | value | `Int` |  | rmdir(path) - BSD 137. |
| `sysRenameNum` | value | `Int` |  | rename(from, to) - BSD 128. Darwin has the plain two-argument call, so `openNeedsDirFd` is 0 here and `sysRename` uses it directly. |
| `sysGetdentsNum` | value | `Int` |  | Reading a directory. |
| `dirReadNeedsPosition` | value | `Int` |  |  |
| `direntNameOffset` | value | `Int` |  | Where the name starts inside one record. Darwin's 64-bit `dirent` is |
| `cwdUsesFcntlPath` | value | `Int` |  | The working directory. |
| `sysCwdNum` | value | `Int` |  | fcntl(fd, cmd, arg) - BSD 92. |
| `fGetPath` | value | `Int` |  |  |
| `eExist` | value | `Int` |  | The two errno values portable code above compares against. |
| `eIsDir` | value | `Int` |  |  |
| `sysGetPidNum` | value | `Int` |  | getpid() - BSD 20 |
| `sysClockNum` | value | `Int` |  | gettimeofday(tv, tz) - BSD 116. Writes {tv_sec i64, tv_usec i32+pad} to its 16-byte buffer; the register-return interpretation was probed WRONG on arm64 (x0 is 0 on success, never seconds). Verified against the shell clock, 400,000 reads, zero backwards steps, ~200ns/call. |
| `clockIsGettimeofday` | value | `Int` |  |  |
| `clockHasMonotonic` | value | `Int` |  | Whether this platform can answer a MONOTONIC clock - one that never steps backwards - through a syscall. Darwin cannot, and that is the whole reason this capability exists rather than being assumed. |
| `clockMonotonicId` | value | `Int` |  | The id `clock_gettime` is asked for the monotonic clock, where there is one. Unused here - `clockIsGettimeofday` sends both readers to `gettimeofday`, and `clockHasMonotonic` above says why - and 0 so that nobody reads a Linux number out of this file. The constant exists because the id is NOT portable: 1 is CLOCK_MONOTONIC on Linux and CLOCK_VIRTUAL, process CPU time, on FreeBSD, and `Sys.ax` carried the 1 as a literal until 2026-08-29. |
| `sysSocketNum` | value | `Int` |  | socket(domain, type, protocol) - BSD 97. |
| `sysBindNum` | value | `Int` |  | bind(fd, addr, addrlen) - BSD 104. THE ADDRLEN IS EXACT: 0, 4, 8, 12, 20, 24 and 28 were each probed and every one answered -22 EINVAL; only 16 - the size of `sockaddr_in` - returned 0. |
| `sysListenNum` | value | `Int` |  | listen(fd, backlog) - BSD 106. |
| `sysAcceptNum` | value | `Int` |  | accept(fd, addr, addrlen) - BSD 30. |
| `sysConnectNum` | value | `Int` |  | connect(fd, addr, addrlen) - BSD 98. On a non-blocking socket this answers -36 EINPROGRESS rather than failing; probed. |
| `sysSetSockOptNum` | value | `Int` |  | setsockopt(fd, level, name, val, len) - BSD 105. |
| `sysGetSockOptNum` | value | `Int` |  | getsockopt(fd, level, name, val, lenptr) - BSD 118. |
| `sysShutdownNum` | value | `Int` |  | shutdown(fd, how) - BSD 134. |
| `sysFcntlNum` | value | `Int` |  | fcntl(fd, cmd, arg) - BSD 92, and the number `sysCwdNum` above also holds. They are NOT merged: `sysCwdNum` names "the call that answers the working directory", which is `fcntl(F_GETPATH)` here and `getcwd` on Linux, and a socket has no business reading that name. |
| `afInet` | value | `Int` |  | The address family and socket type. `AF_INET` is 2 on both systems - and that agreement is a trap, because `AF_INET6` is 30 here against Linux's 10, so nothing else in this group may be assumed to match. |
| `afInet6` | value | `Int` |  | AF_INET6, AND THIS IS THE DIVERGENCE THE PARAGRAPH ABOVE WARNED ABOUT: 30 here against Linux's 10. |
| `sockStream` | value | `Int` |  |  |
| `solSocket` | value | `Int` |  | THE SOCKET-OPTION NUMBERS ARE WHERE DARWIN AND LINUX PART COMPANY, and they part completely. `SOL_SOCKET` is 0xffff here and 1 on Linux; Darwin's `SO_*` are BSD bitmask-style constants where Linux's are small sequential integers. Not one of the four below shares a value with its Linux twin, so reusing a Linux number here does not fail - it sets some other option. |
| `soReuseAddr` | value | `Int` |  |  |
| `soReusePort` | value | `Int` |  |  |
| `soError` | value | `Int` |  |  |
| `fGetFl` | value | `Int` |  | fcntl's file-status commands, and the flag a non-blocking socket sets. `O_NONBLOCK` is 4 here and 2048 on Linux. |
| `fSetFl` | value | `Int` |  |  |
| `oNonblock` | value | `Int` |  |  |
| `eAgain` | value | `Int` |  | EAGAIN, which a non-blocking `accept` or `read` answers negated when there is nothing to take yet. 35 here, 11 on Linux - so a caller that compares against a literal is correct on one target and silently wrong on the other, which is the reason this is a name. |
| `sockaddrHasLenByte` | value | `Int` |  | WHETHER `sockaddr_in` OPENS WITH A LENGTH BYTE. It does here and does not on Linux, and the two layouts cannot share a builder: |
| `pollUsesKqueue` | value | `Int` |  |  |
| `sysPollCreateNum` | value | `Int` |  | kqueue() - BSD 362. Takes no arguments. |
| `sysPollWaitNum` | value | `Int` |  | kevent(kq, changelist, nchanges, eventlist, nevents, timeout) - BSD 363, and it is BOTH of epoll's calls: `sysPollCtlNum` names the same number because registering is this call with an eventlist of nothing. |
| `sysPollCtlNum` | value | `Int` |  |  |
| `pollEventSize` | value | `Int` |  | `struct kevent` is 32 bytes on both 64-bit Darwin arches: |
| `pollEventFdOffset` | value | `Int` |  |  |
| `pollReadFilter` | value | `Int` |  | EVFILT_READ. THE ONE VALUE THAT GENUINELY DIVERGES: kqueue's filters are NEGATIVE small integers naming a kind of event, where epoll's are a positive bitmask. -1 here, EPOLLIN = 1 there. It is written into a SIGNED 16-BIT field, so `Sys.ax` masks it to two bytes rather than storing a word. |
| `pollAddOp` | value | `Int` |  | EV_ADD and EV_DELETE, which coincide with EPOLL_CTL_ADD and EPOLL_CTL_DEL at 1 and 2. The agreement is luck rather than design, so both are named on both platforms instead of being assumed. |
| `pollDelOp` | value | `Int` |  |  |
| `pollSigsetSize` | value | `Int` |  | The size of the mask argument epoll_pwait takes and kevent does not. Zero here because nothing reads it; see the Linux files for why it must be exactly 8 there. |
| `sysRandomNum` | value | `Int` |  |  |
| `randomIsGetentropy` | value | `Int` |  |  |
| `randomMaxChunk` | value | `Int` |  |  |
| `signalUsesSignalFd` | value | `Int` |  |  |
| `sysSigProcMaskNum` | value | `Int` |  | sigprocmask(how, set, oset) - BSD 48. |
| `sigBlockHow` | value | `Int` |  | SIG_BLOCK, which is 1 HERE AND 0 ON LINUX. The values are not shared and the wrong one is `SIG_UNBLOCK` on Darwin - it would unblock the signal it was asked to block, and the process would take the default disposition and die. |
| `sigsetBytes` | value | `Int` |  | Darwin's `sigset_t` is a single `__uint32_t` - FOUR bytes, against Linux's kernel `sigset_t` of eight. Nothing reads a size argument here, but the buffer's width is what the kernel copies. |
| `pollSignalFilter` | value | `Int` |  | EVFILT_SIGNAL, the filter that marks an event as a signal rather than a readable socket. Unused on Linux, where the distinction is which descriptor woke instead. |
| `sysSignalFdNum` | value | `Int` |  | Unused on Darwin (see `signalUsesSignalFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `sigInfoSize` | value | `Int` |  |  |
| `sysKillNum` | value | `Int` |  | kill(pid, sig) - BSD 37. |
| `sigTerm` | value | `Int` |  | SIGTERM and SIGINT AGREE on all four targets, which is worth naming rather than assuming because most of their neighbours do not - SIGUSR1 is 30 here and 10 on Linux. |
| `sigInt` | value | `Int` |  |  |
| `forkChildIsZero` | value | `Int` |  | Whether `fork` answers 0 in the child, which is the POSIX convention and what Linux does. Darwin answers the child's pid to both, so `sysForkProcess` normalises; see `sysFork` above for the measurement. |
| `acceptNonblockFlag` | value | `Int` |  | The flag `netAccept` passes to make the accepted socket non-blocking. Darwin's `accept` HAS no such flag - it has no `accept4` at all - so this is 0 and `Sys.ax` reaches for `fcntl` afterwards instead. |
| `usesSyscallAbi` | value | `Int` |  |  |
| `platformWriteFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  |
| `platformReadFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  |
| `platformExitWith` | value | `(-> Int Int)` |  |  |
| `ttyUsesTermios` | value | `Int` |  | Whether this platform's terminal control is the POSIX `termios` trio - read the attributes, edit them, write them back - reached through `ioctl`. Windows answers 0: its mechanism is `GetConsoleMode`/`SetConsoleMode` against a HANDLE, which shares no part of this shape. |
| `sysIoctlNum` | value | `Int` |  | ioctl(fd, request, arg) - BSD 54, encoded the way every number in this file is: `0x2000000 \| 54` = 33554486. Probe: `SYS_ioctl = 54 (0x36)`, `SYS_ioctl encoded = 33554486`. |
| `tcGetAttrReq` | value | `Int` |  | TIOCGETA - read the terminal attributes into a `struct termios`. |
| `tcSetAttrReq` | value | `Int` |  | TIOCSETAF - write the attributes back, after draining pending output and DISCARDING pending input. |
| `tcWinSizeReq` | value | `Int` |  | TIOCGWINSZ - read `struct winsize`. |
| `termiosBytes` | value | `Int` |  | How many bytes the kernel exchanges through the two requests above, and therefore how large a buffer a caller must hand `Sys.ax` to save a terminal's state in. |
| `termiosFlagBytes` | value | `Int` |  | The width of one flag word, which is also the STRIDE of the four of them: `c_iflag` at 0, `c_oflag` at 8, `c_cflag` at 16, `c_lflag` at 24. Probe: `c_iflag@0 c_oflag@8 c_cflag@16 c_lflag@24`, each of `size 8`. The four offsets are `n * termiosFlagBytes` on every platform this library targets, so `Sys.ax` carries one multiplication rather than four constants per module. |
| `termiosCcOff` | value | `Int` |  | Where the control-character array `c_cc` begins. Probe: `offsetof c_cc = 32 (size 20, NCCS 20)`. |
| `termiosVminIdx` | value | `Int` |  | The two `c_cc` slots that mean something once ICANON is off: how many bytes a `read` must collect before it returns, and how long it waits in tenths of a second. Probe: `VMIN = 16`, `VTIME = 17`. |
| `termiosVtimeIdx` | value | `Int` |  |  |
| `tiosEcho` | value | `Int` |  | c_lflag bits. Probe: `ECHO = 0x8 (8)`, `ICANON = 0x100 (256)`, `ISIG = 0x80 (128)`, `IEXTEN = 0x400 (1024)`. |
| `tiosIcanon` | value | `Int` |  |  |
| `tiosIsig` | value | `Int` |  |  |
| `tiosIexten` | value | `Int` |  |  |
| `tiosBrkint` | value | `Int` |  | c_iflag bits. Probe: `BRKINT = 0x2`, `ICRNL = 0x100`, `ISTRIP = 0x20`, `IXON = 0x200`. |
| `tiosIcrnl` | value | `Int` |  |  |
| `tiosIstrip` | value | `Int` |  |  |
| `tiosIxon` | value | `Int` |  |  |
| `tiosOpost` | value | `Int` |  | The one c_oflag bit raw mode touches. Probe: `OPOST = 0x1`, and it is 0x1 on Linux and FreeBSD too. |

## `Test`

`stdlib/Test.ax` — 7 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Assert` | effect |  |  | The effect a failed assertion performs. |
| `assertEq` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` | Two `Int`s are equal. |
| `assertNe` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` | Two `Int`s are not equal - for the property that a value CHANGED, where naming what it changed to would pin something the test does not mean to pin. |
| `assertStrEq` | value | `(-> String String String Int)` | `Alloc,Assert,IO,Mut` | Two `String`s are equal, by bytes. |
| `assertTrue` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` | A `Bool` is true. |
| `assertFalse` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` | A `Bool` is false. Not `(assertTrue label (! b))`, because Axiom has no `!` and `(== b false)` at the call site is what this exists to keep out of the test. |
| `testFail` | value | `(-> String Int)` | `Alloc,Assert,IO,Mut` | Fail unconditionally: the branch that must not be reached, and the case a test has not written yet. `(testFail "todo: the empty input")` reads as a failure rather than as a passing test with nothing in it, which is what an empty test body is. |

## `Tui.Edit`

`stdlib/Tui/Edit.ax` — 62 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `LED_GO` | value | `Int` |  | Keep editing. |
| `LED_DONE` | value | `Int` |  | Enter: the caller takes `ledSnapshot`. |
| `LED_EOF` | value | `Int` |  | Ctrl-D on an EMPTY buffer: end of input, the same answer the piped reader gives at EOF, so `replMain`'s farewell path is shared. |
| `LED_ABORT` | value | `Int` |  | Ctrl-C: abandon this line. NOT end of session - see the header of `term.ax` for why, and for why it cannot leave the terminal raw. |
| `LED_RING_MAX` | value | `Int` |  | How many kills the ring remembers. |
| `LineEd` | struct |  |  |  |
| `ledRingNew` | value | `(Vec String)` | `Alloc,Mut` | The kill ring, created once per session and outliving every line. |
| `ledNew` | value | `(-> (Vec String) String LineEd)` | `Alloc,Mut` | One editor over a session's ring, with the caller's word set. The gap vectors are `vecNew` (leaf) because their elements are CODE POINTS: Vec.ax's comment says a leaf block is exactly right for Ints and costs nothing. |
| `ledReset` | value | `(-> LineEd String Int Int Int)` | `Mut` | Prepare for the next physical line. Keeps both vectors' capacity. |
| `ledFree` | value | `(-> LineEd Int)` |  | Hand the two gap vectors back. For session end and for a test harness, which builds hundreds; see the struct's comment for why nothing else needs it. |
| `ledLen` | value | `(-> LineEd Int)` |  |  |
| `ledCursor` | value | `(-> LineEd Int)` |  | The cursor, as a code-point index. It IS `(vecLen left)`. |
| `ledCpAt` | value | `(-> LineEd Int Int)` |  | Code point `i` of the logical buffer, or 0 out of range. |
| `ledRangeStr` | value | `(-> LineEd Int Int String)` | `Alloc,Mut` | `cnt` code points from `s`, as a String. |
| `ledSnapshot` | value | `(-> LineEd String)` | `Alloc,Mut` | The whole buffer. This is the value handed to `replMain`, and it is the ONLY place the gap representation becomes a String - which is what keeps `replTrim`, `replParenDepth` and `replDispatch` taking exactly what they take today. |
| `ledInsert` | value | `(-> LineEd Int Int)` | `Alloc,Mut` | Insert one code point before the cursor. 1 if it went in. |
| `ledInsertStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` | Decode a String and insert every code point; answers how many went in. Steps with `utf8Next`, never `utf8CharAt` in a rising loop - Utf8.ax's own comment records that as the quadratic mistake. |
| `ledSetStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` | Replace the buffer, cursor at the end. What history and completion need: one call to put a whole line in. |
| `ledBackspace` | value | `(-> LineEd Int)` | `Mut` |  |
| `ledDelete` | value | `(-> LineEd Int)` | `Mut` |  |
| `ledLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | Every motion is one code point moved from one gap vector to the other. O(1) per character; nothing re-derives the cursor. |
| `ledRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledHome` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledIsWord` | value | `(-> LineEd Int Bool)` |  |  |
| `ledNotWord` | value | `(-> LineEd Int Bool)` |  | The complement, as a function because Axiom has no `!` - stdlib's `assertFalse` carries the same note for the same reason. |
| `ledWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | readline's rule: skip a run of non-word characters, then a run of word characters. Answers how many code points were crossed. |
| `ledWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledWordRightSpan` | value | `(-> LineEd Int)` |  | How many code points a forward word kill would take, WITHOUT moving the cursor - the backward kills can move and then pop, because a leftward motion pushes exactly what it crossed onto `right`, but a forward one has nowhere to put it back. |
| `ledKillPush` | value | `(-> LineEd String Int Int)` | `Alloc,Mut` |  |
| `ledRingIdx` | value | `(-> LineEd Int)` |  | Which ring entry a yank would take. Read by the test harness, and by whatever eventually shows the kill ring; the ring itself is the session's `Vec` and is already reachable. |
| `ledKillToEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledKillToStart` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledKillWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | Move left over the word, then pop what the motion pushed onto `right` - the run the cursor just crossed is exactly the top `moved` entries of that vector. |
| `ledKillWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledYank` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledYankPop` | value | `(-> LineEd Int)` | `Alloc,Mut` | Alt-y. Valid only immediately after a yank or another yank-pop, which `yankLen > 0` is exactly: every other key zeroes it in `ledApply`, so pressed cold this is a refusal that changes nothing. |
| `tuiVisLen` | value | `(-> String Int)` |  | The DISPLAY WIDTH of a string: no `ESC [ ... m` sequence counted, and no UTF-8 continuation byte counted. |
| `tuiCat` | value | `(-> (Vec String) String)` | `Alloc,Mut` | Every fragment in `v`, concatenated, in ONE allocation. |
| `ledCharCols` | value | `(-> Int Int)` |  | The display width of one code point. 1 for everything - see the header. The single place a wcwidth table would land. |
| `ledColsBefore` | value | `(-> LineEd Int Int)` |  | The columns the first `k` code points occupy. O(k), and it is the only reason `ledCharCols` is a function rather than a `1` written in four formulas: with a wcwidth table this stays correct and nothing else changes. |
| `ledCols` | value | `(-> LineEd Int)` |  | The width to compute with: the terminal's, or 80 when it answered something a division cannot use. A pty that has never been sized reports 0 columns with a SUCCESSFUL ioctl (Sys.ax says so), and dividing by it is the bug that report cannot make. |
| `ledContentCols` | value | `(-> LineEd Int)` |  |  |
| `ledRowOf` | value | `(-> LineEd Int Int)` |  |  |
| `ledColOf` | value | `(-> LineEd Int Int)` |  |  |
| `ledRowsUsed` | value | `(-> LineEd Int)` |  |  |
| `ledCup` | value | `(-> Int Int String)` | `Alloc,Mut` | `ESC [ n <final>`, or "" when n < 1 so a zero-distance move costs no bytes. 65 A up, 66 B down, 67 C forward, 68 D back. |
| `ledClearScreen` | value | `(-> Int String)` | `Alloc,Mut` | `ESC [ H ESC [ 2 J` - cursor home, erase the whole screen. Ctrl-L. |
| `ledEraseRow` | value | `(-> Int String)` | `Alloc,Mut` | `ESC [ 0 K` - erase from the cursor to the end of the row. Spelled out rather than routed through `ledCup`, which refuses n < 1 and would answer "" - an erase that emits nothing is a redraw that leaves the old line's tail on the screen. |
| `ledEraseOld` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` | Erase what the previous refresh drew and leave the cursor at column 0 of the first row. |
| `ledRefreshFull` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` | The multi-row repaint. |
| `ledRefreshWindow` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` |  |
| `ledRefresh` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` | The one dispatcher, so the choice between the two repaints lives in exactly one place. |
| `ledResize` | value | `(-> LineEd Int Int Int)` | `Mut` | Called with the terminal's current size before every refresh. When the width changed we cannot know how the terminal reflowed the text it already holds, so `rows` and `curRow` are reset rather than used: refusing to compute motions from a stale width beats computing them wrongly, and one more keystroke fully repairs the line. 1 when it changed. |
| `ledApply` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  |
| `ledIsKillKey` | value | `(-> KeyEv Bool)` |  |  |
| `ledIsYankKey` | value | `(-> KeyEv Bool)` |  |  |
| `ledByWord` | value | `(-> KeyEv Bool)` |  | A motion key carrying Ctrl or Alt is the WORD variant. Terminals disagree about which modifier they send for Ctrl-Left - xterm sends MOD_CTRL, several send MOD_ALT, and Alt-b is the same motion by another name - so both are accepted rather than one being picked. |
| `ledDispatch` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  |
| `ledNavKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` | Arrows, Home and End - and the keys this effort deliberately leaves alone. Up and Down belong to the HISTORY effort and Tab to COMPLETION; they are decoded, they arrive here, and they do nothing. Adding them is a branch beside these, not a change to the decoder. |
| `ledCharKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` | A printable key, or an Alt-<letter> word command. Alt-b/f/d/y are the bindings every terminal can produce, where Ctrl-Left and Alt-Delete are the ones only some can. |
| `ledCtrlKey` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` | The control keys. readline's letters, and only the ones this effort owns: Ctrl-N and Ctrl-P are history's and are left unbound so that effort can take them without moving anything here. |

## `Tui.Keys`

`stdlib/Tui/Keys.ax` — 43 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `KEY_NONE` | value | `Int` |  | The event was consumed and means nothing to the editor - a mouse report, a device reply, a stray byte. It is NOT "nothing happened": `used` is still the bytes to advance by. |
| `KEY_MORE` | value | `Int` |  | A strict prefix. Read more, or resolve it with `keyResolve`. This kind never leaves `term.ax`. |
| `KEY_EOF` | value | `Int` |  |  |
| `KEY_CHAR` | value | `Int` |  | `cp` is the code point. |
| `KEY_CTRL` | value | `Int` |  | `cp` is the LETTER, 64..95: Ctrl-A is 65, Ctrl-@ is 64, Ctrl-_ is 95. Storing the letter rather than the control byte is what lets the binding table read as `(== ev.cp 65)` beside a comment saying A. |
| `KEY_ENTER` | value | `Int` |  |  |
| `KEY_TAB` | value | `Int` |  |  |
| `KEY_BACKSPACE` | value | `Int` |  |  |
| `KEY_ESCAPE` | value | `Int` |  |  |
| `KEY_UP` | value | `Int` |  |  |
| `KEY_DOWN` | value | `Int` |  |  |
| `KEY_RIGHT` | value | `Int` |  |  |
| `KEY_LEFT` | value | `Int` |  |  |
| `KEY_HOME` | value | `Int` |  |  |
| `KEY_END` | value | `Int` |  |  |
| `KEY_DELETE` | value | `Int` |  |  |
| `KEY_INSERT` | value | `Int` |  |  |
| `KEY_PGUP` | value | `Int` |  |  |
| `KEY_PGDN` | value | `Int` |  |  |
| `KEY_FN` | value | `Int` |  | `cp` is the function-key number: KEY_FN with cp 5 is F5. |
| `MOD_SHIFT` | value | `Int` |  |  |
| `MOD_ALT` | value | `Int` |  |  |
| `MOD_CTRL` | value | `Int` |  |  |
| `keyCsiMax` | value | `Int` |  | How many bytes of a well-formed CSI this decoder will tolerate before calling it line noise. A wedged terminal spewing digits cannot otherwise grow the pending prefix without bound. |
| `keyStrMax` | value | `Int` |  | And of an OSC/DCS string body. |
| `KeyEv` | struct |  |  |  |
| `keyScanCtrl` | value | `(-> Int KeyEv)` | `Alloc` |  |
| `keyCsiEnd` | value | `(-> String Int Int Int)` |  |  |
| `keyCsiParam` | value | `(-> String Int Int Int Int)` |  |  |
| `keyCsiPrivate` | value | `(-> String Int Int Bool)` |  | A CSI whose first parameter byte is `<`, `=`, `>` or `?` is a private form: a mouse report, a device-attributes reply, a mode report. None of them is a keystroke. |
| `keyTildeKind` | value | `(-> Int Int)` |  | The key a `~`-final CSI names, from its first parameter. |
| `keyTildeFn` | value | `(-> Int Int)` |  | F1..F12 out of a `~`-final parameter, or 0 for one that names none. |
| `keyFinalKind` | value | `(-> Int Int)` |  | The key a letter-final CSI or SS3 names. |
| `keyFromCsi` | value | `(-> String Int Int Int KeyEv)` | `Alloc` |  |
| `keyFromSs3` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyStrEnd` | value | `(-> String Int Int Int)` |  |  |
| `keyScanUtf8` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  |
| `keyScan` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  |
| `keyScanEsc` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` | The escape path. See the header for the case list. |
| `keyScanCsi` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyScanStr` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyScanAlt` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` | ESC <anything else> is Alt-that-key: decode the key at off+1 and OR MOD_ALT into it. `used` grows by the ESC. |
| `keyResolve` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |

## `Tui.Term`

`stdlib/Tui/Term.ax` — 14 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `termBufBytes` | value | `Int` |  | One `read` takes up to this much. Large enough that a pasted line arrives in one syscall, which is what makes the redraw coalescing below turn a paste into roughly one repaint. |
| `keyEscTimeoutMs` | value | `Int` |  | How long to wait for the rest of an escape sequence before deciding there is no rest. |
| `KeyIn` | struct |  |  |  |
| `mkKeyIn` | value | `(-> Int Int KeyIn)` | `Alloc,IO,Mut` | A reader over `fd`. `active` 0 builds the inert shape: no poll descriptor, a one-byte buffer, and nothing ever read - which is what the piped path gets, so that the byte-identical surface pays for none of this. |
| `keyInPending` | value | `(-> KeyIn Int)` |  | Bytes read but not yet consumed. The redraw coalescing asks this. |
| `keyInFill` | value | `(-> KeyIn Int Int)` | `Alloc,IO,Mut` |  |
| `keyNext` | value | `(-> KeyIn KeyEv)` | `Alloc,IO,Mut` |  |
| `termReadSize` | value | `(-> KeyIn Int)` | `IO,Mut` | Refresh `kin.ws` from the terminal. One ioctl; there is no SIGWINCH handling anywhere in this tree, so the size is asked for rather than delivered. |
| `termWsCols` | value | `(-> KeyIn Int)` |  | Columns, or 80. A pty that has never been sized answers 0 with a SUCCESSFUL ioctl - Sys.ax states it - so the fallback is on the VALUE and not only on the return code. |
| `termWsRows` | value | `(-> KeyIn Int)` |  |  |
| `termRawEnter` | value | `(-> KeyIn Int)` | `Alloc,IO,Mut` | Enter raw mode on fd 0, saving into `kin.save`. 0, or negative. `keepSignals` 0: see the header. |
| `termRawLeave` | value | `(-> KeyIn Int)` | `IO` |  |
| `termFlush` | value | `(-> (Vec String) Int)` | `Alloc,IO,Mut` |  |
| `termEditLoop` | value | `(-> KeyIn LineEd String (Option String))` | `Alloc,IO,Mut` |  |

## `Utf8`

`stdlib/Utf8.ax` — 12 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `utf8IsCont` | value | `(-> Int Bool)` |  | Is `b` a continuation byte, `10xxxxxx`? |
| `utf8SeqLen` | value | `(-> Int Int)` |  | How many bytes the sequence beginning with lead byte `b` occupies. |
| `utf8DecodeAt` | value | `(-> String Int (Option Int))` |  | The code point whose encoding begins at byte offset `i`, or `None` when there is none there. |
| `utf8Next` | value | `(-> String Int Int)` |  | The byte offset of the character after the one beginning at `i`, clamped to the byte length - `utf8Offset` clamps, and two stepping functions that disagree about the end of a string is a trap. |
| `utf8Len` | value | `(-> String Int)` |  | The number of code points in `s`. |
| `utf8Offset` | value | `(-> String Int Int)` |  | The byte offset at which character `n` begins, or the byte length of `s` when there are fewer than `n` characters. |
| `utf8CharAt` | value | `(-> String Int (Option Int))` |  | Character `n` of `s`, counting from 0. `None` past the end, the same answer `utf8DecodeAt` gives a byte it cannot decode and for the same reason. The tail call FORWARDS `utf8DecodeAt`'s two registers as they arrive (`pairFwdOK`), so this keeps `no-alloc` on the same terms. |
| `utf8Slice` | value | `(-> String Int Int String)` | `Alloc,Mut` | `count` characters of `s` beginning at character `start`, as a `Str` sharing the original's bytes - the character-indexed counterpart of `strSlice`. |
| `utf8Replacement` | value | `Int` |  | U+FFFD REPLACEMENT CHARACTER, what a code point that cannot be encoded becomes. |
| `utf8Width` | value | `(-> Int Int)` |  | How many bytes code point `cp` occupies when encoded - counting what `utf8FromChar` will actually write, so the two never disagree. |
| `utf8FromChar` | value | `(-> Int String)` | `Alloc,Mut` | A freshly allocated `Str` holding `cp` alone. |
| `utf8Valid` | value | `(-> String Bool)` |  | Is every byte of `s` part of a well-formed UTF-8 sequence? |

## `Vec`

`stdlib/Vec.ax` — 23 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `vecNew` | value | `(Vec a)` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity. |
| `vecWithCapacity` | value | `(-> Int (Vec a))` | `Alloc,Mut` | An empty `Vec` that can hold at least `cap` elements without growing. |
| `vecWithCapacityRef` | value | `(-> Int (Vec a))` | `Alloc,Mut` | The same, with an ARRAY-FORM data block: every element is a handle this vector owns a share of. See the module comment. |
| `vecNewRef` | value | `(Vec a)` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity, owning its elements. |
| `vecFree` | value | `(-> (Vec a) Int)` |  | Hand `v` back. Its data block goes with it - the header's reference map names word 2 - and, for a `vecNewRef` vector, so does one share of every element. |
| `vecOwnsRefs` | value | `(-> (Vec a) Bool)` |  | Whether this vector owns a share of every element it holds - the `vecNewRef` half of the module comment. It is word 3 of the header and not a test of the data block's shape word: see `vecBuild`. |
| `vecLen` | value | `(-> (Vec a) Int)` |  |  |
| `vecCap` | value | `(-> (Vec a) Int)` |  |  |
| `vecGet` | value | `(-> (Vec a) Int a)` |  | The element at `i`. REFUSES an index outside `0 .. (vecLen v) - 1`. |
| `vecTry` | value | `(-> (Vec a) Int (Option a))` | `Alloc` | The element at `i`, or `None` when there is no element at `i`. |
| `vecGetStr` | value | `(-> (Vec a) Int String)` |  |  |
| `vecGetVec` | value | `(-> (Vec a) Int (Vec b))` |  | The element at `i` read back as a CONTAINER. |
| `vecPushStr` | value | `(-> (Vec a) String (Vec a))` | `Alloc,Mut` | Append a `String` to a vector of WORDS, keeping the share. |
| `vecPushVec` | value | `(-> (Vec a) (Vec b) (Vec a))` | `Alloc,Mut` | The same for a nested container. A `Vec` handle is a counted block too, so it needs the same explicit share for the same reason. |
| `vecSet` | value | `(-> (Vec a) Int a (Vec a))` | `Mut` | Overwrite the element at `i`. Returns the handle. |
| `vecPush` | value | `(-> (Vec a) a (Vec a))` | `Alloc,Mut` | Append `x`. Returns the handle - the same one, with this representation; see the module comment for why it is returned anyway. |
| `vecPop` | value | `(-> (Vec a) a)` | `Mut` | Remove and return the last element. REFUSES an empty vector. |
| `vecLast` | value | `(-> (Vec a) a)` |  | The last element without removing it. REFUSES an empty vector. |
| `vecClear` | value | `(-> (Vec a) (Vec a))` | `Mut` | Drop every element, keeping the capacity. Returns the handle. |
| `vecSum` | value | `(-> (Vec Int) Int)` |  | The sum of every element. |
| `vecHash` | value | `(-> (Vec Int) Int)` |  | A position-sensitive digest of the whole vector. |
| `vecSort` | value | `(-> (Vec a) (Vec a))` | `Mut` | Sort ascending, in place, by machine word. Answers the vector. |
| `vecSortBy` | value | `(-> (Vec a) (-> Int Int Int) (Vec a))` | `Mut` | The same, ordered by a caller's comparison rather than by the word. |

