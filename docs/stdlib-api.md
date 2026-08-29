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
| `axsymHexVal` | value | `(-> Int Int)` |  | One hex digit's value, or -1. Both cases are accepted: the emitter writes upper, and a reader that took only what one emitter happens to write is pinned to that emitter rather than to the notation. |
| `axsymPctAt` | value | `(-> String Int Int)` |  | The byte a `%XX` at `i` stands for, or -1 where there is no complete escape. STRICT, and that is the point: only the bytes `saAxSafe` escapes decode, so a literal `%` standing in a value the COMPILER built - a rendered type, a generated `Trait#Type#method` name - is never mistaken for an escape. `%41` stays `%41`. |
| `axsymUnpct` | value | `(-> String String)` | `Alloc,Mut` | A meta key or value with its escapes undone. The `strFindByte` guard is not an optimisation for its own sake: no AXTAG in this repository contains a byte that is escaped, so every token on every line in the corpus takes the first arm and is returned as it arrived, allocating nothing and copying nothing. |
| `axsymUnpctFrom` | value | `(-> String Int String String)` | `Alloc,Mut` |  |
| `axsymMeta` | value | `(-> String Meta)` | `Alloc,Mut` | `#key=value` or a bare `#key`, with the leading `#` already dropped. Both halves are unescaped, because `saAxMeta` escapes both: an AXTAG key is everything from `;@axiom:` to the newline, so a key can carry a space or a `#` just as a value can. |
| `axsymMetaScan` | value | `(-> String Int Int Int Int)` | `Alloc,Mut` | The metadata section, from `at` to the end of the line. A token opens at a `#` whose previous byte is a space, and runs to the byte before the next such `#`. `i` walks; `start` is the open token's first byte, or -1 before the first `#` is seen. |
| `axsymLine` | value | `(-> String (Option Sym))` | `Alloc,Mut` | One line. `None` for a blank line, for a line whose first byte is not a KIND letter, and for a line with no quoted type - which together are every non-AXSYM line a caller might feed in, including the `compilation failed` trailer and AXDL diagnostics on the same stream. |
| `axsymBuild` | value | `(-> String Int Int (Option Sym))` | `Alloc,Mut` | The three fields either side of the quoted type, once its bounds are known. Split out because the arms above are a refusal ladder and this is the one path that answers a symbol. |
| `axsymNid` | value | `(-> String String)` | `Alloc,Mut` | The `@<nid>` between the type and the metadata, empty when absent. It is bounded by the next space rather than by the end, because the metadata follows it on the same line. |
| `axsymParse` | value | `(-> String Int)` | `Alloc,Mut` | A whole AXSYM stream. Lines that are not AXSYM are skipped, so the caller may pass the compiler's output unfiltered. |
| `axsymParseFrom` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  |
| `symTag` | value | `(-> Sym String String)` |  | The value of the LAST `#key` on the line, or empty. Empty is also what a bare flag answers, so a caller distinguishing "absent" from "present with no value" wants `symHasTag`. |
| `symTagFrom` | value | `(-> Int String Int String)` |  |  |
| `symTagLastIdx` | value | `(-> Int String Int Int Int)` |  | The index of the last `#key` at or after `i`, or -1. Carried in an accumulator rather than compared on the way out of the recursion, because a bare flag's value is empty and "" cannot tell a later match from no match at all. |
| `symHasTag` | value | `(-> Sym String Bool)` |  |  |
| `symHasTagFrom` | value | `(-> Int String Int Bool)` |  |  |
| `symEffects` | value | `(-> Sym String)` |  | The effect row the CHECKER derived - not what the author claimed. Empty when the declaration performs none. |
| `symDerivedPure` | value | `(-> Sym Bool)` |  | True when the checker derived no effects at all. This is a statement about the ANALYSIS, not a guarantee about the program: an effect reached through a function value in memory is not in the row, and a built-in effect named by an enclosing `handle` is subtracted from it. A policy that treats this as proof of purity is reading a lower bound as an upper one. |
| `symAgentTag` | value | `(-> Sym String String)` | `Alloc,Mut` | The `agent:*` namespace, which the compiler records and does not check. `(symAgentTag s "rewrite")` reads `#agent:rewrite`. |
| `symHasAgentTag` | value | `(-> Sym String Bool)` | `Alloc,Mut` |  |

## `Err`

`stdlib/Err.ax` — 29 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Result` | data |  |  |  |
| `Error` | struct |  |  |  |
| `errDivideByZero` | value | `Int` |  | The codes this module raises itself. A program's own codes live in its own space; these are the ones `ERR-REC-2` needs. |
| `errOverflow` | value | `Int` |  |  |
| `errShiftTooWide` | value | `Int` |  |  |
| `mkError` | value | `(-> Int String Error)` |  |  |
| `errCode` | value | `(-> Error Int)` |  |  |
| `errMessage` | value | `(-> Error String)` |  |  |
| `errContext` | value | `(-> Error String)` |  |  |
| `errorText` | value | `(-> Error String)` | `Alloc,Mut` | The rendering `main` writes to fd 2 (ERR-REC-4), and the one a program builds a longer report out of. A plain function rather than a `Show` instance: dispatch is keyed on a type NAME, so an instance reached through a type variable is AX3025, and every caller here has a concrete `Error` in hand anyway. |
| `isOk` | value | `(-> (Result a e) Bool)` |  |  |
| `isErr` | value | `(-> (Result a e) Bool)` |  |  |
| `unwrapOr` | value | `(-> (Result a e) a a)` |  |  |
| `mapOk` | value | `(-> (Result a e) (-> a b) (Result b e))` |  |  |
| `mapErr` | value | `(-> (Result a e) (-> e f) (Result a f))` |  |  |
| `andThen` | value | `(-> (Result a e) (-> a (Result b e)) (Result b e))` |  |  |
| `errContextOf` | value | `(-> Error String Error)` |  | Attach what the caller was doing to an error in flight, passing `Ok` through untouched. It needs no binder, so it is a function and not a form. |
| `withContext` | value | `(-> (Result a Error) String (Result a Error))` |  |  |
| `okOr` | value | `(-> (Option a) e (Result a e))` |  |  |
| `toOption` | value | `(-> (Result a e) (Option a))` |  |  |
| `intMin` | value | `Int` |  |  |
| `addChecked` | value | `(-> Int Int (Result Int Error))` |  | The three that WRAP. |
| `subChecked` | value | `(-> Int Int (Result Int Error))` |  |  |
| `mulChecked` | value | `(-> Int Int (Result Int Error))` |  |  |
| `divChecked` | value | `(-> Int Int (Result Int Error))` |  |  |
| `remChecked` | value | `(-> Int Int (Result Int Error))` |  |  |
| `shlChecked` | value | `(-> Int Int (Result Int Error))` |  | A shift amount of 64 or more, and a negative one, are undefined and no masking is emitted - `(<< 1 100)` answers 68719476736 at `--opt 0` and 1 at `--opt 1`. |
| `shrChecked` | value | `(-> Int Int (Result Int Error))` |  |  |
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
| `fallibleTally` | value | `FallibleTally` |  | A fresh tally at zero. |
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
| `ffiWordsToVec` | value | `(-> Int Int Int)` | `Alloc,Mut` | A Rust `Vec<i64>` copied into an Axiom `Vec`: `p` points at `n` words. Does NOT free the Rust side: the wrapper calls `ffiFreeWords`. |
| `ffiStrsToVec` | value | `(-> Int Int Int)` | `Alloc,Mut` | A Rust `Vec<String>` copied into an Axiom `Vec` of Strings: `p` points at `2n` words, `{bytesPtr, byteLen}` per element. Does NOT free the Rust side: the wrapper calls `ffiFreeStrList`. |
| `ffiWordListsToVec` | value | `(-> Int Int Int)` | `Alloc,Mut` | A Rust `Vec<Vec<T>>` of word scalars copied into an Axiom `Vec` of `Vec`s: `p` points at `2n` words, `{wordsPtr, len}` per inner list. Does NOT free the Rust side: the wrapper calls `ffiFreeWordLists`. |

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

## `IO`

`stdlib/IO.ax` — 24 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `writeStr` | value | `(-> Int String Int)` | `IO` | Write all of `s` to `fd`, returning the number of bytes written or a negative errno. |
| `printlnLit` | value | `(-> Int Int)` | `IO` |  |
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
| `listDir` | value | `(-> String Int)` | `Alloc,IO,Mut` | The entries of the directory `path`, as a Vec of `Str` - sorted by byte, with `.` and `..` removed. |
| `cwd` | value | `String` | `Alloc,IO,Mut` | The process's working directory as an absolute path, or "" if it cannot be determined. See `Sys.sysGetCwd` for why this is two different syscalls underneath. |
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
| `internFind` | value | `(-> Int String Int)` |  | The id of a string equal in content to `s`, or -1 if none. |
| `internIntern` | value | `(-> Int String Int)` | `Alloc,Mut` | The id for `s`, interning it if its content is new. |

## `Job`

`stdlib/Job.ax` — 1 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `jobRunAll` | value | `(-> Int Int Int)` | `Alloc,IO,Mut` | Run every command in `cmds` at up to `width` at once, answering their exit codes in the order they appear in `cmds`. |

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

`stdlib/Map.ax` — 21 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `mapHashPrime` | value | `Int` |  | 2^31 - 1, a Mersenne prime. No longer used by `mapHash` itself; kept because `Intern`'s polynomial string hash reduces modulo it, and a prime modulus is what makes that polynomial hash sound. |
| `mapHash` | value | `(-> Int Int)` |  | Hash `key` to a value in [0, 2^63). |
| `mapSlotOf` | value | `(-> Int Int Int)` |  | The slot `key` probes first, in [0, cap). |
| `mapNew` | value | `Int` | `Alloc,Mut` | An empty `Map` with `mapDefaultCap` slots. |
| `mapNewRefVals` | value | `Int` | `Alloc,Mut` | An empty `Map` whose VALUES it owns a share of: the value array carries the array form, so `mapFree` releases every value in it. Keys stay `Int`s and stay a leaf, which is what they are - `mapInsert`'s key parameter is `Int`, not a type variable. |
| `mapWithCapacity` | value | `(-> Int Int)` | `Alloc,Mut` | An empty `Map` sized so that `want` entries fit without rehashing. |
| `mapWithCapacityRefVals` | value | `(-> Int Int)` | `Alloc,Mut` | `mapWithCapacity`'s owning twin. See `mapNewRefVals`. |
| `mapRoundUpPow2` | value | `(-> Int Int)` |  | `n` rounded up to a power of two, at least `mapDefaultCap`. |
| `mapFree` | value | `(-> Int Int)` |  | Hand `m` back: the three arrays go with it, and on a `mapNewRefVals` table so does one share of every value still in it. Answers 0, as `Vec.vecFree` does and for the same reason. |
| `mapLen` | value | `(-> Int Int)` |  |  |
| `mapCap` | value | `(-> Int Int)` |  |  |
| `mapUsed` | value | `(-> Int Int)` |  | Slots that are live or tombstoned. Exposed because it is the number that explains a rehash, and a test that could not see it would have to infer growth from timing. |
| `mapOwnsVals` | value | `(-> Int Bool)` |  | Whether this table owns a share of every value it holds - the `mapNewRefVals` half. Word 6 of the header, and not a test of the value array's shape word: see `mapAllocTable`. |
| `mapNextSlot` | value | `(-> Int Int Int)` |  | The next slot after `i`. |
| `mapHas` | value | `(-> Int Int Bool)` |  |  |
| `mapGet` | value | `(-> Int Int Int Int)` |  | The value for `key`, or `dflt` if `key` is absent. |
| `mapGetStr` | value | `(-> Int Int String String)` |  | The value for `key` read as a `String`, or `dflt` if `key` is absent. |
| `mapInsert` | value | `(-> Int Int a Int)` | `Alloc,Mut` | Insert or overwrite, growing first if the load factor demands it. Returns the handle - the same one, since the header is mutated in place; see `Vec`'s module comment for why it is returned anyway. |
| `mapRemove` | value | `(-> Int Int Int)` | `Mut` | Delete `key`. Returns the handle. |
| `mapSumVals` | value | `(-> Int Int)` |  | The sum of every live value. |
| `mapSumKeys` | value | `(-> Int Int)` |  | The sum of every live key. Together with `mapSumVals` and `mapLen` this pins down a small map's contents well enough to test with. |

## `Mem`

`stdlib/Mem.ax` — 12 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `memAlloc` | value | `(-> Int Int)` | `Alloc` | Mem - raw memory operations, in Axiom. |
| `memAllocMapped` | value | `(-> Int Int Int)` | `Alloc,Mut` | The same allocation, declaring which of the block's words hold REFERENCES: bit i of `map` says payload word i is a handle to another counted block, so releasing this block releases that one too (docs/memory-model.md MM-LIFE-2d, the record form). |
| `memMarkArray` | value | `(-> Int Int)` | `Mut` | The ARRAY FORM: every payload word of this block is a handle to another counted block, so releasing it releases all of them (docs/memory-model.md MM-LIFE-2d names the two forms; the array form landed 2026-08-24). |
| `memMarkLeaf` | value | `(-> Int Int)` | `Mut` | The inverse, and it is not symmetry for its own sake: it is what a container's GROWTH needs. Doubling a buffer copies the elements to a new block WITHOUT retaining them - the shares move - so releasing the old block while it still reads as an array would spend every share twice. Clearing the bit first makes the old block a leaf, and its release then reclaims the block and touches nothing it used to hold. |
| `memCopy` | value | `(-> Int Int Int Int)` | `Mut` | THERE IS NO `memIsArray`, AND THE REASON IS A MEASURED CRASH. |
| `memSet` | value | `(-> Int Int Int Int)` | `Mut` | Set `count` bytes at `addr` to `value` (low 8 bits). Returns `addr`. |
| `memCmp` | value | `(-> Int Int Int Int)` |  | Compare `count` bytes. 0 if equal, otherwise the signed difference of the first differing byte pair (so the result orders like `memcmp`). |
| `memGetWord` | value | `(-> Int Int Int)` |  | The word at `index`. A word is what it is: an integer, or a handle, or a reference whose type this layer does not know. It answers `Int` because that is the truth about a machine word - it used to answer a type variable, which let the CALLER name any type at all and get it, including a reference, which then dereferenced. See `AX3040`. |
| `memGetWordStr` | value | `(-> Int Int String)` |  | The String view, for the typed accessors built on this layer - `tokenLexeme`, `diagCode`, and the several dozen others whose own signature says `String` and whose body is one word read. |
| `memSetWord` | value | `(-> Int Int a Int)` | `Mut` | Storing a word here is the moment a value can leave the type system's sight: `(cast Int value)` erases whatever `value` was, and the machine word that lands in `addr` is indistinguishable from an integer forever after. That is the whole of MM-LIFE-2c's co-ownership blocker, and the fix is one line - the store takes a SHARE of what it is about to hide. |
| `memGetByte` | value | `(-> Int Int Int)` |  |  |
| `memPutByte` | value | `(-> Int Int Int Int)` | `Mut` |  |

## `Path`

`stdlib/Path.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `pathLastSlash` | value | `(-> String Int)` |  | The last `/` in `p`, or -1. Everything below is a decision about this one index. |
| `pathDir` | value | `(-> String String)` | `Alloc,Mut` | Everything up to and INCLUDING the last `/`, or "" when `p` names something in the working directory. |
| `pathBase` | value | `(-> String String)` | `Alloc,Mut` | Everything after the last `/` - the file name on its own, or `p` entire when there is no separator. |
| `pathWithSlash` | value | `(-> String String)` | `Alloc,Mut` | A directory name that ends in `/`, so concatenation forms a path. |
| `pathJoin` | value | `(-> String String String)` | `Alloc,Mut` | `dir` and `name` as one path, with exactly one `/` between them. |
| `pathExtIndex` | value | `(-> String Int)` |  | The index of the extension's `.` within `p`, or -1. |
| `pathExt` | value | `(-> String String)` | `Alloc,Mut` | The extension INCLUDING its dot (`".ax"`), or "" when there is none. |
| `pathStem` | value | `(-> String String)` | `Alloc,Mut` | The base name with its extension removed: `"src/main.ax"` is `"main"`. What a driver names an output after. |
| `pathReplaceExt` | value | `(-> String String String)` | `Alloc,Mut` | `p` with its extension replaced by `ext`, which carries its own dot. `(pathReplaceExt "build/main.ax" ".ll")` is `"build/main.ll"`, and a path with no extension simply gains one. |
| `pathIsAbsolute` | value | `(-> String Bool)` |  | True when `p` starts at the root. A relative path is resolved against the working directory, which is why `Sys.sysGetCwd` exists. |

## `Pre`

`stdlib/Pre.ax` — 8 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `when` | macro |  |  | Axiom standard prelude — macros and utilities. |
| `unless` | macro |  |  | ;; unless — evaluate body unless test is true ;; (unless test body) -> (if test 0 body) |
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

## `Show`

`stdlib/Show.ax` — 2 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Show` | trait |  |  |  |
| `format` | macro |  |  | `format` — a String, built at compile time from a literal's runs and holes, or `show` applied to anything else. |

## `Str`

`stdlib/Str.ax` — 26 public names

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
| `strFindByte` | value | `(-> String Int Int Int)` |  | Index of the first `byte` at or after `from`, or -1. |
| `strStartsWith` | value | `(-> String String Bool)` |  |  |
| `strIsDigit` | value | `(-> Int Bool)` |  |  |
| `strIsAlpha` | value | `(-> Int Bool)` |  |  |
| `strIsSpace` | value | `(-> Int Bool)` |  | Space, tab, LF, CR - and nothing else. Not `char::is_whitespace`: VT and FF are AX1001 to this language's lexer, and a formatter that skipped them turned a refused file into an accepted one. |
| `strHexVal` | value | `(-> Int Int)` |  | The value of a hex digit, or -1. Stated as the VALUE and not as a predicate because the value is what every caller needed: the JSON parser's `\uXXXX` escape and the language server's percent-decoding each carried a byte-identical copy of this ladder under its own name, while the predicate here had no caller at all. |
| `strIsHexDigit` | value | `(-> Int Bool)` |  |  |
| `strSplit` | value | `(-> String Int Int)` | `Alloc,Mut` | Every segment of `s` between occurrences of `byte`, in order, as a Vec of Str handles. Empty segments are KEPT: a `PATH` entry of "" means the working directory, and a caller that wants them dropped can drop them, while a caller that needs them cannot get them back. `strSplit "" 58` answers one empty segment, and `strSplit "a:" 58` answers two - the same rule as splitting on a separator anywhere else, and the one that makes the segment count equal the separator count plus one. |
| `strSplitFrom` | value | `(-> String Int Int Int Int)` | `Alloc,Mut` |  |
| `strFromByte` | value | `(-> Int String)` | `Alloc,Mut` | A one-byte `Str` holding `b`. The compiler driver and the JSON encoder each had this three-line allocate-and-store under a private name; it is a `Str` constructor, so it lives with the others. |

## `Sys`

`stdlib/Sys.ax` — 75 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sysResult` | value | `(-> String Int (Result Int Error))` | `Alloc,Mut` | write(fd, buf, count) -> bytes written, or a negative/errno result. A raw syscall answer turned into a `Result`. |
| `stdin` | value | `Int` |  |  |
| `stdout` | value | `Int` |  |  |
| `stderr` | value | `Int` |  |  |
| `sysWriteFd` | value | `(-> Int Int Int Int)` | `IO` |  |
| `sysWriteAllFd` | value | `(-> Int Int Int Int Int)` | `IO` |  |
| `sysReadFd` | value | `(-> Int Int Int Int)` | `IO` |  |
| `sysOpenPath` | value | `(-> Int Int Int)` | `IO` |  |
| `sysCloseFd` | value | `(-> Int Int)` | `IO` |  |
| `sysExitWith` | value | `(-> Int Int)` | `IO` |  |
| `sysFailed` | value | `(-> Int Bool)` |  |  |
| `sysErrno` | value | `(-> Int Int)` |  |  |
| `sysReadFile` | value | `(-> Int String)` | `Alloc,IO,Mut` | Open, read entire contents, close.  Returns an empty string on any error (missing file, permission, etc.). |
| `sysArgc` | value | `Int` | `IO` | How many arguments the process received, including the program name. |
| `sysArg` | value | `(-> Int String)` | `Alloc,IO,Mut` | The i-th argument as a Str (0 is the program name), or "" when `i` is out of range. The bytes are the process's own argv storage - NUL-terminated, alive for the whole run, never freed or moved - so wrapping them without copying is sound. |
| `sysWriteFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO,Mut` | Write `s` to `path`, creating or truncating it. Answers the number of bytes written, or a negative errno from whichever step failed. |
| `sysAppendFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO,Mut` | Append `s` to `path`, creating it if it is not there. Answers the number of bytes written, or a negative errno. |
| `sysRename` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut` | Rename `old` to `new`, answering 0 or `-errno`. Both are NUL-terminated char* - `strCStr`. |
| `sysUnlink` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` | Remove `path`. Answers 0, or `-errno`. |
| `sysMkdir` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut` | Create directory `path` with `mode`. Answers 0, or `-errno` - which is `-17` (EEXIST) when it is already there, and callers usually want to treat that as success. |
| `sysDirMode` | value | `Int` |  | 0755, the mode a directory usually wants. A nullary function because that is how this language spells a constant. |
| `sysRmdir` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` | Remove the empty directory `path`. Answers 0, or `-errno`. |
| `sysFileExists` | value | `(-> Int Bool)` | `IO` | 1 when `path` names something that can be opened for reading. |
| `sysFileSize` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` | The size of `path` in bytes, or `-errno`. Seeks to the end, which is what the size IS - no struct, no layout, no per-target record. |
| `sysReadErrno` | value | `(-> Int Int)` | `Alloc,IO,Mut` | 0 when `path` can be opened AND read as a file, otherwise the errno saying why not. |
| `sysIsDir` | value | `(-> Int Bool)` | `Alloc,IO,Mut` | True when `path` names a directory. |
| `sysReadDir` | value | `(-> Int Int)` | `Alloc,IO,Mut` | Every name in the directory `path`, as a Vec of owned `Str` - `.` and `..` INCLUDED, in whatever order the filesystem gives them. |
| `sysGetCwd` | value | `String` | `Alloc,IO,Mut` | The process's working directory as an absolute path, or "" if it cannot be determined. |
| `sysEnv` | value | `(-> String String)` | `Alloc,IO,Mut` | The value of the environment variable `name`, or "" when it is unset. |
| `sysEnvp` | value | `Int` | `Alloc,IO,Mut` | A NULL-terminated copy of the process's own environment vector, in the form a child expects. |
| `sysSpawn` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Start `path` with argument vector `argv` and environment `envp`. `(Ok pid)`, or `(Err e)` whose code is the errno - and `Err` means no child exists, which is what a caller must not confuse with a child that started and failed. |
| `sysWaitPid` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` | Wait for `pid`. `(Ok status)` is the raw wait status; `(Err e)` carries the errno of a wait that could not be performed. |
| `sysExitCode` | value | `(-> Int Int)` |  | The exit code carried by a wait status, for a child that exited normally. |
| `sysTermSignal` | value | `(-> Int Int)` |  | The signal that killed a child, or 0 if it exited normally. |
| `sysRun` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` | Run `path` to completion and answer its exit code. |
| `sysRunPath` | value | `(-> String Int Int (Result Int Error))` | `Alloc,IO,Mut` | Run `name`, searching `PATH` for it when it contains no slash. |
| `sysGetPid` | value | `Int` | `IO` | The calling process's own id - the per-session suffix scratch files need so two concurrent processes cannot collide. The syscall takes no arguments; the unused ones are simply zero. |
| `sysNowMicros` | value | `(-> Int Int)` | `IO` | Microseconds now, from the platform's cheapest correct clock: Darwin answers gettimeofday's timeval (realtime; Darwin's syscall table has no clock_gettime), Linux and FreeBSD answer CLOCK_MONOTONIC via clock_gettime - under the id `clockMonotonicId` names, because the id is not portable: 1 on Linux, and on FreeBSD 4, where 1 is CLOCK_VIRTUAL, the process's CPU time. That one was a literal here until 2026-08-29, and a clock that measures CPU time never runs backwards either, so nothing would have caught it. |
| `sysNowMonotonic` | value | `(-> Int Int)` | `IO` | Microseconds from a clock that NEVER steps backwards, or a negative when this platform has none. The 16-byte buffer is the caller's, as above, so a timing loop allocates nothing. |
| `netSocketTcp` | value | `Int` | `IO` | A TCP socket, or a negative errno. |
| `netSocketTcp6` | value | `Int` | `IO` | The same over IPv6. Its own name rather than a family parameter, because the family is not a runtime choice at this layer: a caller already picked a builder when it made the address, and a socket whose family disagrees with the address it is given fails at `bind` and not here. |
| `netAddr4Bytes` | value | `Int` |  | How many bytes an address of each family occupies, and how big a buffer that must take either has to be. |
| `netAddr6Bytes` | value | `Int` |  |  |
| `netAddrMaxBytes` | value | `Int` |  | What `netAcceptFrom` wants, which is the larger of the two: a caller does not get to know the peer's family until it has the peer. |
| `netAddr4` | value | `(-> Int Int Int Int Int Int Int)` | `Mut` | Write an IPv4 `sockaddr_in` into `buf`, which must hold 16 bytes, and answer `buf`. The four octets are given in reading order, so 127.0.0.1 is `127 0 0 1`. |
| `netAddr6` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int)` | `Mut` | Write an IPv6 `sockaddr_in6` into `buf`, which must hold `netAddr6Bytes`, and answer `buf`. |
| `netAddrFamily` | value | `(-> Int Int)` |  | The address family in a `sockaddr` - `afInet`, `afInet6`, or whatever else the kernel wrote there. |
| `netAddrPort` | value | `(-> Int Int)` |  | The port in a `sockaddr`, decoded from network order. This one does NOT branch on the platform or the family: both layouts diverge in the four bytes before it and agree from byte 2 on, so `sin_port` and `sin6_port` are the same two bytes in the same place. |
| `netAddrSize` | value | `(-> Int Int)` |  | How many bytes of `addr` a syscall must be given, read off the family the buffer carries. This is what `netBind` and `netConnect` pass, and the reason neither of them takes a length. |
| `netBind` | value | `(-> Int Int Int)` | `IO` | Bind a socket to an address built by `netAddr4` or `netAddr6`. |
| `netListen` | value | `(-> Int Int Int)` | `IO` |  |
| `netAccept` | value | `(-> Int Int)` | `IO` | Accept a connection, answering the new socket or a negative errno, and throw the peer's address away. `netAcceptFrom` below keeps it; this is the form for a caller that does not want the buffer, and it passes NULL for both of `accept`'s out-parameters. |
| `netAcceptFrom` | value | `(-> Int Int Int Int Int)` | `IO,Mut` | Accept a connection AND KEEP THE PEER'S ADDRESS. Answers the new socket or a negative errno, exactly as `netAccept` does, and fills `addr` with the peer's `sockaddr`, which `netAddrFamily`, `netAddrPort` and `netAddrText` read. |
| `netAddrLenRead` | value | `(-> Int Int)` |  | The length the kernel wrote back into a `netAcceptFrom` cell - 16 for a v4 peer, 28 for a v6 one. It is the REAL length of the peer's address, which is not necessarily how much of it arrived: the kernel copies what fits and reports the whole size either way, so a value larger than the `cap` that went in means the address was cut short. `netAcceptFrom` acts on that itself; a caller reads this to log the family it could not store. |
| `netAddrText` | value | `(-> Int String)` | `Alloc,Mut` | Render an address as text: a dotted quad for `afInet`, RFC 5952 form for `afInet6`. |
| `netAddrTextPort` | value | `(-> Int String)` | `Alloc,Mut` | The same, with the port, in the form a URL authority uses: `127.0.0.1:80` and `[::1]:80`. |
| `netSetBlocking` | value | `(-> Int Int)` | `IO` | Take a descriptor OUT of non-blocking mode, preserving the other flags it carries. The counterpart of `netSetNonBlocking`, and what a caller that handles one connection synchronously wants from `netAccept`'s result. |
| `netConnect` | value | `(-> Int Int Int)` | `IO` | Connect to an address built by `netAddr4` or `netAddr6`. The length comes off the family in the buffer for the same reason `netBind`'s does, and was the same literal 16. |
| `netShutdown` | value | `(-> Int Int Int)` | `IO` |  |
| `netSetOptInt` | value | `(-> Int Int Int Int Int Int)` | `IO,Mut` | Set an integer-valued socket option. The value crosses as four bytes in the host's own order, which is what the kernel reads an `int` option as - unlike an address, this one is NOT network order. That is `netPutInt32`, which `netAcceptFrom`'s `socklen_t` cell needs for the same reason. |
| `netSetNonBlocking` | value | `(-> Int Int)` | `IO` | Put a descriptor into non-blocking mode, preserving the flags it already carries - a bare `F_SETFL` of the one flag would clear the access mode with it. |
| `netWouldBlock` | value | `(-> Int Bool)` |  | Whether a negative answer means "nothing to take yet" rather than a broken socket. This is the whole reason `eAgain` is a capability: the number is 35 on Darwin and 11 on Linux, so an event loop written against a literal runs correctly on the machine it was written on. |
| `netPollBufBytes` | value | `(-> Int Int)` |  | How many bytes an event buffer for `n` events needs on this platform. |
| `netPollCreate` | value | `Int` | `IO` | A readiness descriptor, or a negative errno. |
| `netPollAddRead` | value | `(-> Int Int Int Int)` | `IO,Mut` | Watch `fd` for readability. `rec` is scratch of `pollEventSize` bytes. |
| `netPollDelRead` | value | `(-> Int Int Int Int)` | `IO,Mut` |  |
| `netPollWait` | value | `(-> Int Int Int Int Int Int)` | `IO,Mut` | Wait for readiness, answering how many events landed in `buf` or a negative errno. A NEGATIVE `timeoutMs` BLOCKS INDEFINITELY, which is what a server's accept loop wants; zero polls and returns at once. |
| `netPollFdAt` | value | `(-> Int Int Int)` |  | The descriptor named by event `i` of a buffer `netPollWait` filled. |
| `sysRandomBytes` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut` | Fill `n` bytes at `buf` with kernel entropy. `(Ok 0)`, or `(Err e)` whose code is the errno - and on `Err` the buffer's contents are unspecified, so a caller must not read them. |
| `sysSigBit` | value | `(-> Int Int)` |  | The `sigset_t` bit for a signal. SIGNAL N IS BIT N-1, an off-by-one that is easy to write the other way and yields the neighbouring signal's mask rather than an error. |
| `sysSignalBlock` | value | `(-> Int Int Int)` | `IO,Mut` | Block the signals in `mask` so they become observable instead of fatal. `setbuf` is caller scratch of at least 16 bytes: the mask is written as one 64-bit word, and the kernel then copies ITS OWN `sigset_t` width out of the buffer - `sigsetBytes`, which is 4 on Darwin, 8 on Linux and 16 on FreeBSD. Sixteen covers every target, and the bytes between the word and that width are zeroed here rather than left to whatever the caller's buffer held, because on FreeBSD they are signals 65 through 128 and a stale byte there blocks one. |
| `netSignalOpen` | value | `(-> Int Int Int Int Int)` | `IO,Mut` | Watch the signals in `mask` on the readiness descriptor `pfd`, and answer a HANDLE to pass back to `netPollSignalAt` - the signal descriptor on Linux, and 0 on the BSDs, which need none. |
| `netPollSignalAt` | value | `(-> Int Int Int Int Int)` | `IO` | The signal named by event `i`, or a negative when that event is not a signal at all. `sigHandle` is what `netSignalOpen` answered and `scratch` is caller scratch of at least `sigInfoSize` bytes. |
| `sysKill` | value | `(-> Int Int Int)` | `IO` | Send a signal, which is how a test raises one against itself. |
| `sysForkProcess` | value | `Int` | `IO` | Duplicating this process |

## `Sys.Platform`

`stdlib/Sys/Platform.darwin.ax` — 82 public names

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

## `Utf8`

`stdlib/Utf8.ax` — 12 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `utf8IsCont` | value | `(-> Int Bool)` |  | Is `b` a continuation byte, `10xxxxxx`? |
| `utf8SeqLen` | value | `(-> Int Int)` |  | How many bytes the sequence beginning with lead byte `b` occupies. |
| `utf8DecodeAt` | value | `(-> String Int Int)` |  | The code point whose encoding begins at byte offset `i`, or -1 when there is none there. |
| `utf8Next` | value | `(-> String Int Int)` |  | The byte offset of the character after the one beginning at `i`, clamped to the byte length - `utf8Offset` clamps, and two stepping functions that disagree about the end of a string is a trap. |
| `utf8Len` | value | `(-> String Int)` |  | The number of code points in `s`. |
| `utf8Offset` | value | `(-> String Int Int)` |  | The byte offset at which character `n` begins, or the byte length of `s` when there are fewer than `n` characters. |
| `utf8CharAt` | value | `(-> String Int Int)` |  | Character `n` of `s`, counting from 0. -1 past the end, the same sentinel `utf8DecodeAt` uses and for the same reason. |
| `utf8Slice` | value | `(-> String Int Int String)` | `Alloc,Mut` | `count` characters of `s` beginning at character `start`, as a `Str` sharing the original's bytes - the character-indexed counterpart of `strSlice`. |
| `utf8Replacement` | value | `Int` |  | U+FFFD REPLACEMENT CHARACTER, what a code point that cannot be encoded becomes. |
| `utf8Width` | value | `(-> Int Int)` |  | How many bytes code point `cp` occupies when encoded - counting what `utf8FromChar` will actually write, so the two never disagree. |
| `utf8FromChar` | value | `(-> Int String)` | `Alloc,Mut` | A freshly allocated `Str` holding `cp` alone. |
| `utf8Valid` | value | `(-> String Bool)` |  | Is every byte of `s` part of a well-formed UTF-8 sequence? |

## `Vec`

`stdlib/Vec.ax` — 20 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `vecNew` | value | `Int` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity. |
| `vecWithCapacity` | value | `(-> Int Int)` | `Alloc,Mut` | An empty `Vec` that can hold at least `cap` elements without growing. |
| `vecWithCapacityRef` | value | `(-> Int Int)` | `Alloc,Mut` | The same, with an ARRAY-FORM data block: every element is a handle this vector owns a share of. See the module comment. |
| `vecNewRef` | value | `Int` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity, owning its elements. |
| `vecFree` | value | `(-> Int Int)` |  | Hand `v` back. Its data block goes with it - the header's reference map names word 2 - and, for a `vecNewRef` vector, so does one share of every element. |
| `vecOwnsRefs` | value | `(-> Int Bool)` |  | Whether this vector owns a share of every element it holds - the `vecNewRef` half of the module comment. It is word 3 of the header and not a test of the data block's shape word: see `vecBuild`. |
| `vecLen` | value | `(-> Int Int)` |  |  |
| `vecCap` | value | `(-> Int Int)` |  |  |
| `vecGet` | value | `(-> Int Int Int)` |  | The element at `i`, or 0 when `i` is out of range. |
| `vecTry` | value | `(-> Int Int (Option Int))` |  | The element at `i`, or `None` when there is no element at `i`. |
| `vecGetStr` | value | `(-> Int Int String)` |  |  |
| `vecSet` | value | `(-> Int Int a Int)` | `Mut` | Overwrite the element at `i`. Returns the handle. |
| `vecPush` | value | `(-> Int a Int)` | `Alloc,Mut` | Append `x`. Returns the handle - the same one, with this representation; see the module comment for why it is returned anyway. |
| `vecPop` | value | `(-> Int Int)` | `Mut` | Remove and return the last element, or 0 if `v` is empty. |
| `vecLast` | value | `(-> Int Int)` |  | The last element without removing it, or 0 if `v` is empty. |
| `vecClear` | value | `(-> Int Int)` | `Mut` | Drop every element, keeping the capacity. Returns the handle. |
| `vecSum` | value | `(-> Int Int)` |  | The sum of every element. |
| `vecHash` | value | `(-> Int Int)` |  | A position-sensitive digest of the whole vector. |
| `vecSort` | value | `(-> Int Int)` | `Mut` | Sort ascending, in place, by machine word. Answers the vector. |
| `vecSortBy` | value | `(-> Int (-> Int Int Int) Int)` | `Mut` | The same, ordered by a caller's comparison rather than by the word. |

