# The Axiom Rust FFI

**Status:** complete. `extern` is in the language, `Foreign` is a
builtin type kept out of the ARC reference map, the bytes and fallible
return protocols work through generated Axiom glue, and **all four of
`MM-FFI-5`'s requirements are discharged**. The bootstrap fixpoint holds
and the gates are green.

This document specifies a foreign-function interface between Axiom and
Rust in both directions, over one shared marshalling layer. It exists
because Axiom's ecosystem is young and Rust's is not: the point is to let
an Axiom program reach `sha2`, `serde_json` or `ureq` without Axiom
having to grow its own.

---

## 0. What this reverses, and on whose authority

Axiom removed its FFI deliberately, and the removal is load-bearing:

- `docs/memory-model.md` **MM-FFI-1 (R)** states "Axiom has no FFI" as a
  spec *Requirement*, and says so as the property that "makes
  `MM-PAR-3`, `MM-ALLOC-1` and the whole of §3 true".
- `foreign` is a reserved word reporting `AX2004`
  (`self_host/parser.ax:376`, `:1103`).
- `scripts/check-freestanding.sh` gates it, ending in a negative probe
  that asserts a `foreign` binding is *still* refused as `AX2004`.
- `.claude/skills/axiom-helper/SKILL.md` tells agents "There is no FFI…
  Do not write `foreign` bindings and do not suggest them."

So this is not a gap being filled; it is a decision being revisited. The
authority to revisit it is in the same file that made it.
**MM-FFI-5 (P)** already specifies what a future FFI *SHALL* require at
minimum, and this design is built to those four clauses:

| MM-FFI-5 requires | Status |
|---|---|
| foreign memory is a **distinct type** from `Int` | **done** - `Foreign` is a builtin (`typeKeywordCanon`), and `tyCompat` matches named constructors by name, so it is distinct everywhere a type is compared |
| **no arena primitive** applies to it | **done** - `scalarTyName` keeps it out of MM-LIFE-2d's reference map. Measured: `(String, Foreign, String)` maps payload words `[0, 2]` - the `Foreign` is skipped, not truncated at |
| a foreign call is an **inferred effect** like a syscall | **done** - the `FnEnt` effect seed at registration; the existing monotone fixpoint propagates it transitively |
| `check-freestanding.sh` **replaced by an allowlist gate** | **done** - `scripts/check-ffi.sh`, reading each crate's `axiom-allow.txt` |

`foreign` itself stays retired at `AX2004` forever. The new keyword is
`extern`. Old source keeps getting migration advice rather than being
silently reinterpreted, and `check-ffi.sh`'s fourth negative probe
asserts exactly that.

---

## 1. The result, measured

Everything below was run on this machine — Darwin arm64, rustc 1.97.1,
LLVM 22.1.8, Apple clang 21 — against the real compiler at `9d5b508`,
before any compiler change was written. The mechanism is not a proposal.

**Both directions work.**

| Direction | How it was proved | Result |
|---|---|---|
| Axiom → Rust | real emitted Axiom IR + `declare` + `call`, linked against a Rust `staticlib` | correct results |
| Rust → Axiom | Axiom IR with `@main` renamed, `ar`'d into a `.a`, called from a Rust binary | `axiom_rt_init` and `addTwo(20,22) → 42`; Axiom's syscall `println` printed from inside the Rust process |

**The marshalling layer is correct**, checked against the real runtime
rather than against the docs:

| Call | Result | What it proves |
|---|---|---|
| `ffiAdd 20 22` | `42` | scalars are a direct native `call` |
| `ffiCountVowels "hello world"` | `3` | Rust reads Axiom's `{len, ptr, owner}` string **zero-copy** |
| `ffiCountVowels ""` | `0` | the empty-string edge |
| `ffiHypot 3.0 4.0` | `5.000000` | `Float` ↔ IEEE-754 bits round trip |
| `ffiFnv1a "axiom"` | `7929549642058804759` | byte slices, checked against an independent implementation |

**And the freestanding property survives.** This is the result that
mattered most, and it is better than expected:

| program | `nm -u` | forbidden libc names |
|---|---|---|
| no FFI at all | **0** | 0 |
| FFI → `no_std` + `alloc` Rust crate | **0** | 0 |
| FFI → `std` Rust crate | 188 | 14 |

A `no_std` crate whose `alloc` is wired to `axiom_alloc` links into an
Axiom executable that imports **nothing at all**. `MM-FFI-1`'s property
is not traded away for the FFI; it is traded away only for `std`, only
by the programs that ask for it, and `scripts/check-ffi.sh` is what
prices it.

Two findings came out of getting there, both of which a
design-on-paper would have missed:

- A `no_std` crate that uses `alloc` still needs `rust_eh_personality`
  and seven memory intrinsics (`memcpy`, `memset`, `memmove`, `memcmp`,
  `bzero`, `strlen`, `_Unwind_Resume`), because the *precompiled sysroot*
  `alloc` rlib was built with unwinding and calls the C memory
  intrinsics. `panic = "abort"` governs your crates, not the sysroot.
  Defining them inside the crate — a dozen lines of byte loops — is what
  gets `nm -u` back to zero on stable.
- The two modes **cannot share a cargo workspace**. Cargo unifies
  features across members built together, so with the `no_std` crate as a
  member a plain `cargo build` enables `axiom-ffi/std` — because the
  `std` example asks for it — and std's `panic_impl` then collides with
  the `no_std` crate's `#[panic_handler]`
  (`error[E0152]: found duplicate lang item`). `default-features = false`
  on the dependency edge does not prevent it: unification is a property
  of the graph, not of one edge. The `no_std` crate is therefore its own
  workspace, and `check-ffi.sh` builds it by `--manifest-path`.

- Rust's `alloc` can be wired straight to `axiom_alloc`, which puts
  Rust's allocations **inside Axiom's arena**, counted by the high-water
  mark and reclaimed by an arena reset. `MM-FFI-3`'s "outside the arena"
  clause becomes vacuous for a `no_std` crate, which is the strongest
  position available. The cost is that `dealloc` is a no-op, stated
  rather than hidden.

---

## 2. The three facts that shaped the design

Conventional FFI designs assume a runtime to marshal through, a GC to
inform, and a type checker to trust. Axiom offers none of the three, and
each absence changed a decision.

**There is no VM, so there is no trampoline.** The emitted module is
closed — `grep -c '^declare' bootstrap/axiom-darwin-aarch64.ll` is `0`
against 1897 `define`s — and every function is already
`define i64 @sym(i64, …)` with no calling convention and no parameter
attributes (`codegen.ax:3014-3018`, `:3658`). **The C ABI for `i64`
arguments is the ABI Axiom already uses.** So an FFI call compiles to the
same instruction sequence as an internal call, and the entire codegen
change is emitting a `declare`. That is also precisely the bug that
killed `foreign`: it emitted `call i64 @putchar(i64 65)` into a module
that declared no `@putchar`, and LLVM textual IR *requires* a declare for
an undeclared callee, so `check` passed and `opt` then died
(`docs/self-hosting.md:4247-4260`).

**There is no unifier, so the checker cannot police the boundary.**
`tyCompat` (`typecheck.ax:188-235`) is the entire type relation: a type
variable on either side matches anything. Real inference was attempted
and withdrawn three times (`5f2a616`→`053c525`, `6ff9e2c`→`9d5b508`)
because a statically resolved argument type feeds MM-LIFE-2d's ARC
evidence word, and the containers are deliberately untyped `Int`
handles, so resolution claims pointerhood for scalars and segfaults.
**Boundary type safety therefore lives in `axiom-bindgen`**, on the Rust
side, where real types exist — not in the Axiom declaration, which cannot
enforce it.

**There is no GC, so nothing can be taught to ignore a foreign word.**
`@axiom_release` does not ask whether an address is Axiom's; it subtracts
16 from the word it was handed and reads a header. Whether it walks a
word at all is decided at *compile time* by `fldClass` consulting
`scalarTyName` (`codegen.ax:6133-6178`). So `Foreign` is safe only if it
is registered there — and `tyIsReprScalar` (`typecheck.ax:7051-7096`),
which is about declared-return checking and has one call site, is **not**
the mechanism, a distinction this design got wrong before the review
caught it.

---

## 3. What exists today

Implemented, building, and validated:

```
rust/                          cargo workspace; NOT required to build the compiler
  axiom-abi/                   #![no_std] value layouts + retain/release protocol
  axiom-ffi/                   facade; std (default) or no_std
  axiom-ffi-macros/            #[axiom_export] -> the C-ABI shim
  axiom-bindgen/               Rust source -> Axiom `extern` declarations
  examples/demo/               std: scalars, strings, Result, opaque handles
  examples/nostd/              no_std + alloc over axiom_alloc; nm -u == 0
scripts/check-ffi.sh           the MM-FFI-5 allowlist gate, with negative probes
tests/ffi/no-extern/           tier-1 controls: build, run, import nothing
```

Applied to the compiler — six files, detailed in §11:

| File | What it gained |
|---|---|
| `self_host/parser.ax` | `TAG_D_EXTERN` (tag 53), `parseExternDecl`, the `parseTopForm` hook, and `foreign`'s migration advice retargeted at `extern` |
| `self_host/typecheck.ax` | `tcAddExtern` (seeds `IO`), the `tcCollect` arm, and four tables taught the tag: `declNamespace`, `defIdxBuild`, `ambBuildDecl` |
| `self_host/codegen.ax` | `emitExternDeclares`, symbol resolution through `mangleRecord`, and `isNullaryFnIn` taught the zero-arity case |
| `self_host/driver.ax` | `--link-lib` / `--link-search`, threaded to the `cc` argument vector |
| `self_host/format.ax` | `fpDeclExtern`, so a generated binding module is formattable |
| `tree-sitter-axiom/grammar.js` | `extern_declaration` / `extern_item` / `extern_clause`, plus a corpus case |

**The bootstrap fixpoint holds**: seed → stage1 → stage2 == stage3,
byte-identical, with every one of those files changed.

`Foreign` is a builtin type name, distinct from `Int` and excluded from
MM-LIFE-2d's reference map. `self_host/namespace.ax` also learned to
record an **imported** block's items - a path the entry-file fixtures
could not reach, where an imported binding module emitted its calls
against the Axiom name beside a `declare` for the linker symbol and died
in `opt`: the `foreign` bug arriving from the one direction still open.

`Slice` and `Outcome` turned out not to be types at all. A shim
returning bytes, or one that can fail, needs two words back; those take
a trailing out-cell, their raw binding carries a `Raw` suffix, and
`axiom-bindgen` emits an **Axiom wrapper** that allocates the cell,
calls, decodes and frees. No compiler feature was needed, and the rule
that only Axiom's emitter writes an Axiom block header is preserved.
The compiler found this itself: extern signatures are now validated
against the type registry, and `Slice`/`Outcome` came back `AX3002`.

`axiom symbols` already reports an extern with its full type and its
inferred effects, as an `F` line; a distinct `E` kind and a `#symbol=`
field would need `SymMaps` widened and are cosmetic against what is
already there.

---

## 4. FFI Architecture and Call Flow

### 1. What the architecture has to accommodate

Three measured properties of the current compiler determine every choice below, and they are unusual enough that conventional FFI designs do not apply.

1. **The emitted module is closed and has no runtime.** `grep -c '^declare' bootstrap/axiom-darwin-aarch64.ll` is `0` against 1897 `define`s; the same file contains no `personality`, `invoke`, or `landingpad`. There is no VM, no dispatcher, no init hook, no metadata section. `emitResolved` (`self_host/codegen.ax:2763-2778`) writes a `target triple` line, the allocator, then every function, then one attribute group (`codegen.ax:2805`).
2. **Every value is already one machine word in a native frame.** `emitFnDef` emits `define i64 @sym(i64 %p, …) #0` with no calling convention, no `dso_local`, no parameter attributes (`codegen.ax:2980-3021`, `emitParams` at `codegen.ax:3658`). The C ABI for `i64` arguments is *the ABI Axiom already uses*.
3. **The type checker cannot police the boundary.** `tyCompat` (`typecheck.ax:188-235`) is the whole "unifier": a `TAG_T_VAR` on either side matches anything, `TAG_T_ERR` matches anything, constructors match by name and arity. `tyReprClash`/`tyIsReprScalar` (`typecheck.ax:7051-7096`) is the single surviving representational check, it names exactly three types, and it has exactly one call site (`typecheck.ax:7020`, inside `checkDeclaredReturn`). Any type safety at the boundary must be established where real types exist — on the Rust side, at binding-generation time.

Property 1 says the marshalling cannot live in a runtime. Property 2 says almost none is needed. Property 3 says what remains must be generated, not hand-written.

---

### 2. Components and responsibilities

#### 2.1 Axiom compiler side

| File | Change | Responsibility |
|---|---|---|
| `self_host/parser.ax` | new `TAG_D_EXTERN = 53` and `TAG_D_EXPORT = 54` (53 and 54 are the next free; 29 is retired at `parser.ax:100-104`, 52 is the highest live at `parser.ax:161`; **next free after this change is 55**); two arms in `parseTopForm` (`parser.ax:1089-1130`); `Foreign` added to `typeKeywordCanon` (`parser.ax:1621-1630`); the extern arm calls `sigFloatFlags` (`parser.ax:1821-1836`) at its signature's token position and stores the vector in slot 9 | Produce one AST node per boundary declaration. Nothing else. |
| `self_host/namespace.ax` | `TAG_D_EXTERN` and `TAG_D_EXPORT` arms in `mangleDecl` (`namespace.ax:126-166`) | **Rename the Axiom-side name (word 1) only.** Without this the two-arm dispatch (`TAG_D_FN`, `TAG_D_SIG`, then `0`) falls through and an imported extern keeps its bare name — see §5 step 2. |
| `self_host/typecheck.ax` | `tcAddExtern` beside `tcAddEffectOp` (`typecheck.ax:1866-1876`); arms in `tcCollect` (`typecheck.ax:1670`); `TAG_D_EXTERN` (only) added to `defIdxBuild` (`typecheck.ax:1114-1132`), `declNamespace` (`typecheck.ax:790-796`), `ambBuildDecl` (`typecheck.ax:3658`); `Foreign` added to `tyIsReprScalar` (`typecheck.ax:7094-7096`); `"FFI"` added to `isBuiltinEffect` (`typecheck.ax:3088-3092`); an `ffi` arm added to `axtagEffectOf` (`typecheck.ax:6844-6850`); new `checkExternSig` and `checkExportTarget` | Register the `FnEnt`, seed its effect set, refuse polymorphic and non-ABI signatures, make the `FFI` effect spellable, keep AX3014/AX3015 honest. |
| `self_host/codegen.ax` | arms in `emitDecl` (`codegen.ax:2817-2836`); two new `CG` words — extern symbol table (37) and export alias list (38) — on a struct that is 37 wide today (`codegen.ax:261`); `declare`/`alias` block written in `emitModuleTail` beside the attribute group (`codegen.ax:2780-2808`); `isNullaryFnIn` (`codegen.ax:1048-1057`) taught `TAG_D_EXTERN`; `recordEntryFns` (`codegen.ax:1721-1731`) taught `TAG_D_EXTERN`; `scanFloatSigs` (`codegen.ax:338-349`) taught `TAG_D_EXTERN`; **`scalarTyName` (`codegen.ax:6133-6148`) gains `Foreign`**; `emitAllocator` (`codegen.ax:1983-2001`) gains the staticlib entry shape | Emit `declare`/`alias` lines, keep float returns honest, keep `Foreign` out of the reference map. **No marshalling code.** |
| `self_host/driver.ax` | `--ffi <path>` and `--staticlib` in `flagArity` (`driver.ax:407-427`); `assembleAndLink` (`driver.ax:205-236`) appends archive paths to `ccArgs`; an `ar` path for staticlib output | Manifest ingestion, link line, fingerprint pre-check. |

`scalarTyName` is not optional garnish: it is the half of the `Foreign` design that keeps a `Foreign` field out of MM-LIFE-2d's reference map, and therefore the half that prevents `@axiom_release` dereferencing a foreign pointer. `fldClass` (`codegen.ax:6159-6178`) consults it for every `TAG_T_CON`; the block comment that states the rule is `codegen.ax:6117-6132`, immediately above `scalarTyName` itself. (The earlier draft cited `codegen.ax:6119-6131` as `fldClass`; that range is the comment, and `fldClass` begins at `:6159`.)

#### 2.2 Rust side — `rust/`, a cargo workspace

```
rust/
  Cargo.toml                    # [workspace]
  Cargo.lock                    # THE pin (see §10)
  axiom-abi/                    # #![no_std] + optional "std" feature
    src/word.rs                 #   AxWord, FromWord/IntoWord
    src/str.rs                  #   AxStr: READ a {len,ptr} handle (v0)
    src/rc.rs                   #   axiom_retain/axiom_release externs (C7)
    src/shape.rs                #   GENERATED header/shape constants (§12 gap 1)
  axiom-macros/                 # #[axiom_export] / #[axiom_import] proc macros
  axiom-bindgen/                # crate -> {.ax module, shim.rs, ffi.manifest.json}
  axiom-gate/                   # allowlist + fingerprint checker (MM-FFI-5 req 4)
  <binding crates>/             # one per Rust library exposed to Axiom
```

`axiom-abi` is `#![no_std]` by default and is the *only* place that knows Axiom's value representation. It is shared by both directions — that is the "one shared marshalling layer" the owner mandated. `std` is a feature, not the default, because experiment 1 (no_std) produced an executable with an empty `nm -u` and experiment 2 (std) produced 188 undefined symbols including 14 forbidden names. The default must be the one that keeps the freestanding property.

#### 2.3 The binding layer — generated, committed, checked

`axiom-bindgen` reads a binding crate's `#[axiom_export]`-annotated functions and emits three artifacts:

- `<crate>/axiom/<Module>.ax` — the Axiom-visible module, nothing but `extern` declarations and doc comments.
- `<crate>/src/shim.rs` — `#[no_mangle] pub extern "C"` wrappers that decode words into Rust types, call the real function, and encode back. `include!`d from `lib.rs`.
- `<crate>/ffi.manifest.json` — link inputs, module directories, symbol allowlist, ABI fingerprint.

The `.ax` and the manifest are **committed**. `axiom check` and `axiom fmt` must work on a checkout with no cargo, because `scripts/bootstrap-from-seed.sh` is cargo-free by design (`scripts/bootstrap-from-seed.sh:36`) and that property is non-negotiable. Only the `.a` requires cargo.

---

### 3. Surface syntax and its AST nodes

**Decision: two declaration tags, one per direction, not one tag with a direction word.** The provider *language* stays a token — a future `(extern c …)` still costs no tag — but the *direction* cannot, because `declNamespace` (`typecheck.ax:790-796`) keys on the tag alone and the two directions need opposite answers:

- `(extern rust …)` — `TAG_D_EXTERN` = 53 — **introduces a new value name**. `declNamespace` must answer `NS_VALUE`, and the declaration must appear in `defIdxBuild`, `dupIdxBuild` and `ambBuildDecl`.
- `(export axiom …)` — `TAG_D_EXPORT` = 54 — **introduces nothing**. It aliases a name that a `TAG_D_FN` in the same file already defines. `declNamespace` must answer `NS_NONE`, and the declaration must appear in *none* of those indexes.

With one tag this is unrepresentable, and the cost is not theoretical: the earlier draft's own Rust→Axiom example put `(pub fn (hashBlock s) …)` and `(pub extern axiom hashBlock …)` in one entry file, so `dupIdxAddDecl` (`typecheck.ax:859-867`) would record two `NS_VALUE` definers and `checkDuplicates` (`typecheck.ax:947-968`) would report a duplicate definition on the section's own example. The same collision reaches the checker: two `FnEnt`s for `hashBlock` means `inferEffectsPass`'s `findFnEnt tc (nodeA d)` (`typecheck.ax:5215-5241`) resolves one of them and strands the other's effect seed. `TAG_D_EXPORT` therefore pushes **no** `FnEnt` at all.

```scheme
; rust/blake3-axiom/axiom/Blake3.ax  -- GENERATED by axiom-bindgen, do not edit.
; abi-fingerprint: 9f3c1ad2e7b4560f

;@axiom:effect(ffi)
(pub extern rust blake3Hash (-> Foreign Int Foreign Int) "ax_blake3_hash")

; Foreign memory is allocated and freed by RUST, never by Axiom.
;@axiom:effect(ffi)
(pub extern rust blake3NewBuf (-> Int Foreign) "ax_blake3_new_buf")

;@axiom:effect(ffi)
(pub extern rust blake3FreeBuf (-> Foreign Int) "ax_blake3_free_buf")
```

```scheme
; src/lib.ax -- the Rust->Axiom direction
(pub :: hashBlock (-> Int Int))
(pub fn (hashBlock w) (* w 2654435761))

(pub export axiom hashBlock "ax_hash_block")
```

**Node layout** reuses `ASTNode`'s existing positional slots (`parser.ax:32`, whose comment records that "every existing reader indexes by position, so appending is the only change that is free"):

| slot | accessor | `TAG_D_EXTERN` | `TAG_D_EXPORT` |
|---|---|---|---|
| 0 | `nodeTag` | 53 | 54 |
| 1 | `nodeA` | the Axiom-side name (`String`) | the name of the `pub fn` being exported |
| 2 | `nodeB` | the link symbol (`String`) | the link symbol (`String`) |
| 3 | `nodeC` | provider language: 0 = rust | provider language of the *consumer*: 0 = rust |
| 5 | `nodeVis` | set by `markPub` through the existing `pub` wrapper (`parser.ax:1104-1107`, `parser.ax:43`) | same |
| 6 | `nodeTy` | the signature type node — the same slot `TAG_D_SIG` uses (`parser.ax:47-50`) | 0; the signature is the target's `TAG_D_SIG` |
| 7 | `nodeAxtags` | effect claims, from `scanAxtags` (`lexer.ax:532-586`) | 0 |
| 9 | `fieldNames` slot | the `sigFloatFlags` vector for this signature (§4, float note) | 0 |

**Decision: the link symbol is required, never derived from the Axiom name.** Alternative considered: default the symbol to the bare name. Rejected because imported declarations are renamed in place to `Mod$name` by `mangleDecl` (`namespace.ax:126-166`, driven from `resolveDecls`, `codegen.ax:1741-1770`) while the link symbol must not move; a reader who believes renaming the Axiom declaration renames the symbol will be wrong, and a required string makes the two-name split visible at every site.

**Decision: `Foreign` is a new nullary built-in type constructor, not a reuse of `(* T)`.** `(* T)` already parses to `TAG_T_PTR` (`parser.ax:178`, `parser.ax:1653-1657`), but the MM-LIFE-2d comment at `codegen.ax:6117-6132` records that a `Ptr` is *unclassifiable* and forces the whole enclosing block to the leaf shape — under-reclaiming every sibling field. `Foreign` as a `TAG_T_CON` with zero arguments buys three distinct things, and it is worth being exact about which mechanism buys which, because the earlier draft attributed all of them to one:

- **`typeKeywordCanon` (`parser.ax:1621-1630`)** → `Foreign` is a recognised built-in spelling rather than an unknown constructor drawing AX3002 at every signature that names it.
- **`tyCompat` (`typecheck.ax:188-235`), used at the argument check `typecheck.ax:4053`** → this is what makes `Foreign` distinct from `Int` at every call site, including `__axiom_arena_reset_keeping` (registered `(mkIntArrow 3)` at `typecheck.ax:1514`). `tyCompat` matches `TAG_T_CON` by name and arity, so **any** new nullary constructor gets this for free, with no `tyIsReprScalar` entry at all. That is MM-FFI-5 requirements 1 and 2's *static* half.
- **`tyIsReprScalar` (`typecheck.ax:7094-7096`)** → this buys exactly one further case and it is worth naming precisely: `tyReprClash` has a single call site, `checkDeclaredReturn` (`typecheck.ax:6987-7022`, the clash test at `:7020`), so the entry makes a declared `Foreign` return over an `Int`-producing body a mismatch instead of a silent representation lie. It does nothing at argument positions; nothing else calls it.
- **`scalarTyName` (`codegen.ax:6133-6148`)** → a `Foreign` field is a machine scalar, never enters the MM-LIFE-2d reference map, so `@axiom_release` never dereferences it. That is MM-FFI-5 requirement 2's ARC half, obtained by construction rather than by a guard.

Alternatives considered: (a) a new type tag — costs a wire-format number and four readers, buys nothing over a reserved constructor name; (b) `Int` with a naming convention — violates C4 and MM-FFI-5 outright.

**`Foreign` values originate only from Rust.** There is no Axiom primitive that mints one: not `axiom_alloc` (its blocks are arena memory with a 16-byte header, and MM-FFI-3 says foreign memory is precisely the memory that is *not* that), and not `__syscall0..6` (they return an `Int`). An Axiom program obtains a `Foreign` by receiving one from an extern — either as a return value or written into a buffer a previous extern returned — and it disposes of one by handing it back to an extern. That is why the generated `Blake3.ax` above declares `blake3NewBuf`/`blake3FreeBuf` as ordinary externs: **Rust owns foreign allocation, in full, and says so in the manifest.**

**Admissible extern signature types (v0):**

| Axiom | LLVM | Rust in the generated shim | Note |
|---|---|---|---|
| `Int` | `i64` | `i64` | |
| `Bool` | `i64` | `i64`, 0/1 | **not** Rust `bool`: Axiom's Bool is a full word |
| `Char` | `i64` | `i64` | |
| `Float` | `i64` | `i64` + `f64::from_bits` | **not** `f64` — see below |
| `Foreign` | `i64` | `*mut c_void` via `usize` | opaque, ARC-invisible, Rust-owned |
| `String` | `i64` | `axiom_abi::AxStr` (read-only in v0) | **direction-dependent — see the table below** |
| `a` (tyvar) | — | — | refused, **AX3036** |
| `(-> …)`, data, struct, list, tuple | — | — | refused, **AX3037** |

**`String` admissibility is per direction, because the directions invert the positions.** The v0 rule is one sentence: *`String` is permitted exactly where Rust READS a handle Axiom built, and refused exactly where Rust would have to BUILD one*, because building one means writing a five-word header whose count and shape words ARC will act on (§12 gap 1).

| Position | direction 0 — `extern rust` (Rust provides the code) | direction 1 — `export axiom` (Axiom provides the code) |
|---|---|---|
| parameter | permitted: Axiom built the handle, Rust reads it | **AX3038**: the Rust caller would have to build it |
| return | **AX3038**: the Rust callee would have to build it | permitted: Axiom built the handle, Rust reads it |

`checkExternSig` therefore takes the direction as an argument; a rule that reads positions absolutely gets direction 1 exactly backwards and lets the one case through that §12 gap 1 exists to defer. A `String` parameter of an *exported* function is refused for a second, independent reason as well — see §12 gap 7.

The `Float` row is the highest-probability boundary bug in the whole design and the reason hand-written externs are a bad idea. Floats travel as their IEEE-754 *bits* in an i64 and are bitcast only at operators; a Rust `extern "C" fn(f64)` would read `v0`/`xmm0` while Axiom wrote `x0`/`rdi`, and the result is garbage with no diagnostic on either side. The generated shim removes the opportunity to write it. **The Axiom side of the same bug is fixed in §4's float note, not by the shim.**

Diagnostic codes: `AX3036`–`AX3040` and `AX4004` are free (`AX3035` is the highest 3xxx in the tree; `AX4003` the highest 4xxx).

---

### 4. Where the marshalling physically lives — and why

| Value class | Converted by | Physical location |
|---|---|---|
| `Int`, `Bool`, `Char`, `Foreign` | nobody | nothing is emitted; the word is already correct |
| `Float` | Rust, **plus one compiler-side table entry** | `axiom-abi`, `f64::from_bits`/`to_bits` inside the generated shim; `FSig` on the Axiom side (below) |
| `String` in (direction 0) / out (direction 1) | Rust | `AxStr::from_handle` in `axiom-abi`, reading `len` at +0 and `ptr` at +8 |
| `String` where Rust would construct one | **nobody — refused, AX3038** | §12 gap 1 |
| ARC ownership across the call | Rust only | arguments cross as **borrows**; `axiom-abi`'s `AxRc` calls the externally-linked `axiom_retain`/`axiom_release` (`codegen.ax:2274`, `codegen.ax:2292`) when Rust keeps a value past the call |
| Panic containment | Rust | `catch_unwind` in the shim (std) or `panic="abort"` (no_std) |

**The float note (compiler-side, and it is not optional).** `fnRetIsFloat` (`codegen.ax:610-622`) answers 0 for any name absent from the `FSig` table, and `scanFloatSigs` (`codegen.ax:338-349`) pushes an `FSig` only for `TAG_D_SIG` nodes. Because an extern carries its signature in its own slot 6 rather than in a separate `::`, an extern would never be in that table, `emitPlainCall` would set `resultIsFloat` to 0 at `codegen.ax:5938` for a `Float`-returning extern, and downstream float arithmetic would emit integer `add` over double bit patterns — the exact MM-VAL-3c failure the tree removed `Double` for. `scanFloatSigs` therefore gains a `TAG_D_EXTERN` arm pushing

```
FSig(name = <the MANGLED Axiom name>, nameLen, flags = slot 9, sigTy = nodeTy, takesEv = 0)
```

keyed on the mangled name because that is the key `emitPlainCall` looks up (`fnRetIsFloat cgE full`). `takesEv` is 0 by construction (C3, enforced by AX3036). Direction 1 needs nothing here: an exported function has a real `TAG_D_SIG`, so `scanFloatSigs` already holds it — but the generated Rust must still declare the return as `i64` and call `f64::from_bits`, because the alias does not change the ABI. If this arm is judged too costly to land in v0, the alternative is to refuse `Float` in extern signatures outright and say so in §3's table; what is *not* available is §3's table as written with no compiler-side change.

**Decision: no marshalling code is ever emitted into Axiom IR, and none is written in Axiom source.** Alternatives:

- *Emit conversion sequences in the IR.* Rejected: there is nothing to convert. Property 2 means the register-level work is zero for every admissible type except `String`, and `String` conversion needs structure knowledge the emitter would have to restate.
- *Write marshalling helpers in Axiom source (a `Ffi.ax` stdlib module).* Rejected on two counts. First, such helpers would be polymorphic, and a type variable in a parameter position silently grows the hidden trailing `i64 %__evw.h` (`codegen.ax:3008-3021`, passed at `codegen.ax:5921-5926`) — C3 exists precisely to keep that word away from Rust, and a marshalling layer written in Axiom would reintroduce it one level up. Second, `tyCompat` cannot check any of it, so the layer would be unverifiable exactly where verification matters.
- *A hand-written C shim.* Rejected: it reintroduces a C toolchain dependency into the middle of the boundary and adds a third representation nobody's type system checks.

Rust is the only side of the boundary with a real type system, a real `f64`, and a real notion of ownership. All structure-aware code goes there, and it is *generated* so that the Axiom declaration and the Rust decoding cannot disagree — they are two outputs of one `axiom-bindgen` run over one input.

---

### 5. Call flow: Axiom → Rust

Source:

```scheme
(import Blake3 (blake3Hash blake3NewBuf blake3FreeBuf))

(pub :: digest (-> Foreign Int Foreign))
;@axiom:effect(ffi)
(pub fn (digest buf n)
  (let ((out (blake3NewBuf 32)))          ; Foreign comes back FROM Rust
    { (blake3Hash buf n out) out }))      ; caller later calls blake3FreeBuf
```

Rust:

```rust
// rust/blake3-axiom/src/shim.rs  -- GENERATED
use core::ffi::c_void;

// A no_std binding has no allocator, so foreign storage is CRATE-OWNED.
// Calling malloc here would be legal but would appear in the manifest's
// imports.platform list, where the gate would show it (§9, §11).
const SLOTS: usize = 4;
static mut DIGESTS: [[u8; 32]; SLOTS] = [[0u8; 32]; SLOTS];
static mut TAKEN: usize = 0;

#[no_mangle]
pub extern "C" fn ax_blake3_new_buf(n: i64) -> i64 {
    unsafe {
        if n != 32 || TAKEN >= SLOTS { return 0; }
        let p = DIGESTS[TAKEN].as_mut_ptr();
        TAKEN += 1;
        p as i64
    }
}

#[no_mangle]
pub extern "C" fn ax_blake3_free_buf(p: i64) -> i64 { let _ = p as *mut c_void; 0 }

#[no_mangle]
pub extern "C" fn ax_blake3_hash(buf: i64, len: i64, out: i64) -> i64 {
    if buf == 0 || out == 0 || len < 0 { return -1; }
    let input = unsafe { core::slice::from_raw_parts(buf as *const u8, len as usize) };
    let dst   = unsafe { core::slice::from_raw_parts_mut(out as *mut u8, 32) };
    dst.copy_from_slice(crate::hash(input).as_bytes());
    0
}

#[no_mangle]
pub extern "C" fn __axiom_abi_v0_9f3c1ad2e7b4560f() {}
```

**Numbered flow:**

1. **Parse.** `parseTopForm` (`parser.ax:1089-1130`) meets `extern`, builds the `TAG_D_EXTERN` node, and records `sigFloatFlags` into slot 9. The `pub` wrapper at `parser.ax:1104-1107` sets `nodeVis` through `markPub`. The reserved-word arm for `union`/`region`/`foreign` (`parser.ax:1099-1103`) is untouched and still reports AX2004 — `extern` is a *new* door, and the old one stays visibly shut.
2. **Import resolution.** `resolveImports` → `resolveDecls` (`codegen.ax:1733-1770`) splices `Blake3.ax`, and the actual renaming is done by **`mangleDecl` (`namespace.ax:126-166`), which today is a two-arm dispatch on `TAG_D_FN` and `TAG_D_SIG` that falls through to `0` for every other tag.** It therefore needs a `TAG_D_EXTERN` arm that does exactly what the `TAG_D_FN` arm does — rewrite **word 1** to `Blake3$blake3Hash` and call `mangleRecord` (`namespace.ax:27-60`) when `exported` is 1, `mangleRecordSelf` (`namespace.ax:175-190`) otherwise — and **must leave word 2, the link symbol, untouched.** Omitting the arm is not a soft failure: the declaration keeps its bare name, never enters `bares`/`fulls`, never gets the exported/private split, and `mangledForIn` (`codegen.ax:1711-1717`) answers the name *unchanged* on a miss, so the `FnEnt` registered under the mangled name in step 3 and the extern-symbol lookup keyed on the mangled name in step 7 both miss silently. `recordEntryFns` (`codegen.ax:1721-1731`) must learn `TAG_D_EXTERN` too, or an extern declared in the *entry file* loses its bare-name claim. (`TAG_D_EXPORT` gets a `mangleDecl` arm as well — it must rewrite word 1 so the alias's aliasee matches the emitted `define` — but it records **nothing** in `bares`/`fulls`, because it defines no name.)
3. **Collection.** `tcCollect` (`typecheck.ax:1670`) dispatches `TAG_D_EXTERN` to `tcAddExtern`, which pushes through `tcPushFn` (`typecheck.ax:1980-1982`) — the single push point that keeps the exact-name hash index in step:

   ```
   FnEnt name=Blake3$blake3Hash  ty=<sig>  paramCount=3
         isBuiltin=0  isEffectOp=0  effects=["b:FFI"]  eparams=[]  declared=1
   ```

   `paramCount` is the **real arity, never -1**. `repArity` (`typecheck.ax:2728-2733`) answers `paramCount` when `>= 0`; a `-1` answer silently disables the AX3013 bare-value refusal and the AX3009/AX3013 saturation check — which is exactly what the old `foreign` did, and exactly why an unsaturated `foreign` call used to reach `opt` as a broken module.
4. **Signature admission.** `checkExternSig` walks `nodeTy` **with the direction in hand**: any `TAG_T_VAR` → **AX3036** (C3: a polymorphic Axiom function grows `%__evw.h` and that word must never reach Rust); any arrow, list, tuple, or user constructor → **AX3037**; a `String` in the position Rust would have to construct → **AX3038** in v0 (§3's direction table, §12 gap 1).
5. **Effects.** The `["b:FFI"]` seed is the model `tcAddEffectOp` already uses (`typecheck.ax:1866-1876`), where an operation's effects are pre-seeded at registration so the collector needs no special case. `inferEffects` (`typecheck.ax:5199-5241`) then runs its monotone fixpoint once over the merged declaration list and propagates `b:FFI` to `digest`, to `digest`'s callers, and so on, transitively and for free. This is MM-FFI-5 requirement 3.

   **Decision: a dedicated `FFI` effect, not `IO` — and it costs two more one-line edits than the earlier draft claimed.** C5 permits either. `FFI` is chosen because `isSyscallPrim` (`typecheck.ax:5029-5034`) is the sole `IO` classifier and is a literal 7-way match on `__syscall0`..`__syscall6`; folding externs into `IO` would make "this function touches the kernel directly" and "this function calls out of the module" indistinguishable in every handler list, and the allowlist gate wants to name the second set precisely. But **the compiler cannot spell `FFI` as it stands**, and both gaps are real:

   - `axtagEffectOf` (`typecheck.ax:6844-6850`) maps only `io`/`mut`/`div`/`alloc` to builtins and sends everything else to `customEff`. So `;@axiom:effect(ffi)` yields `"c:ffi"`, which `axtagUnsupported` (`typecheck.ax:6813-6830`) compares against the seeded `"b:FFI"`, fails; and since `axtagCouldExist` answers 0 for a custom effect no declaration introduces, the suppression does not apply and **every generated extern and the `digest` example above would draw an AX3010 warning**. Fix: `(if (strEq val "ffi") (builtinEff "FFI")` in `axtagEffectOf`.
   - `isBuiltinEffect` (`typecheck.ax:3088-3092`) knows only `IO`, `Pure`, `Mut`, `Div`, `Alloc`, `alloc`, `Err`. So `(handle body (FFI) …)` reports AX3016 unknown-effect, and `effHandledBy` (`typecheck.ax:4838-4848`) would build `"c:FFI"`, which never equals `"b:FFI"` — i.e. **no handle could ever discharge the effect**. Fix: add `"FFI"` to `isBuiltinEffect`.

   With both edits in place, AX3011 fires at a `handle` site that does not cover `FFI`, a handle naming `FFI` discharges it, and a mismatched `;@axiom:effect` AXTAG is AX3010, a warning. Without both, the dedicated effect is not implementable and the fallback is to seed `builtinEff "IO"` and delete this decision.
6. **Emission — the `declare`.** `emitDecl` (`codegen.ax:2817-2836`) currently emits `TAG_D_FN` and drops everything else silently. Its `TAG_D_EXTERN` arm emits *nothing into the body stream* and instead records `("ax_blake3_hash", 3)` into `CG` word 37. `emitModuleTail` (`codegen.ax:2780-2808`) writes the accumulated block immediately before the `attributes #0` line:

   ```llvm
   declare i64 @ax_blake3_hash(i64, i64, i64) #0
   declare i64 @ax_blake3_new_buf(i64) #0
   declare i64 @ax_blake3_free_buf(i64) #0

   @__axiom_abi_guard = constant ptr @__axiom_abi_v0_9f3c1ad2e7b4560f
   declare void @__axiom_abi_v0_9f3c1ad2e7b4560f() #0

   attributes #0 = { "no-builtins" }
   ```

   The same `#0` group, per C2 — `"no-builtins"` on a `declare` is harmless and keeps the module's one attribute group its only one. **A module with no extern and no export emits no `declare` block, no alias and no guard**, so the IR for every existing program is byte-identical to today's, which is the owner's opt-in condition.
7. **Emission — the call.** The body's call site goes through `emitPlainCall` (`codegen.ax:5907-5940`) unchanged except for the symbol lookup: `mangledFor` (`codegen.ax:1696-1709`) resolves `blake3Hash` → `Blake3$blake3Hash` (which requires step 2's `mangleDecl` arm), and the `CG` word 37 lookup maps that to `ax_blake3_hash`. `fnTakesEvw` (`codegen.ax:464-467`) answers 0 for an extern by construction (step 4 guarantees no tyvar), so no evidence word is appended. The emitted instruction is:

   ```llvm
   %t7 = call i64 @ax_blake3_hash(i64 %buf, i64 %n, i64 %t6)
   ```

   which is the *identical instruction shape* `emitPlainCall` emits for a call to any Axiom function. `llvmSym` (`codegen.ax:981-986`) leaves it unquoted because `ax_blake3_hash` is entirely in `[-A-Za-z0-9$._]`.

   A **zero-argument** extern must be routed through the nullary path at `codegen.ax:4887-4899`, which emits `call i64 @name()`; `emitPlainCall` prefixes `"(i64 "` unconditionally and would produce `(i64 )`. `isNullaryFnIn` (`codegen.ax:1048-1057`) filters on `TAG_D_FN` and reads `(vecLen (nodeB d))` — for an extern, `nodeB` holds a `String`, so `vecLen` would read a header word that is not a length. It must gain a `TAG_D_EXTERN` arm taking the arity from the signature's arrow depth rather than inherit the `TAG_D_FN` one.
8. **ARC at the boundary (C7): arguments cross as borrows, and the emitter emits nothing.** Axiom's convention is **callee-retains-on-entry**: `retainRefParams` (`codegen.ax:3210-3221`) takes one `axiom_retain` per reference parameter at function entry, and its comment states the rule — "It converts the caller's BORROW (event 1) into a share this frame owns". `emitPlainCall` (`codegen.ax:5908-5941`) emits no argument ARC at any call site, in any code path; `emitRetainOf`/`emitReleaseOf` (`codegen.ax:6274-6284`) are just the two one-line emitters, not a call-site discipline. So an extern call site emits **no retain and no release** — that keeps §7's "literally the same instruction" claim and step 7's "unchanged except for the symbol lookup" true, and a retain/release pair around the call would in any case be a net no-op. A `Foreign` and every scalar are classified out by `scalarTyName` regardless. **Everything past the call is Rust's obligation:** an argument is valid for the duration of the call and no longer; if Rust keeps a counted handle it calls `axiom_retain` itself and pairs it with `axiom_release`, which is what `axiom-abi`'s `AxRc` guard type exists to make hard to get wrong. (The earlier draft's rule also covered "a data or struct type" — unreachable, since step 4 refuses those with AX3037.)
9. **Link.** `assembleAndLink` (`driver.ax:205-236`) appends `rust/target/release/libblake3_axiom.a` to `ccArgs` after `objPath`. The `declare`s are resolved by the archive; `@__axiom_abi_guard`'s relocation forces the fingerprint symbol.

---

### 6. Call flow: Rust → Axiom

This direction needs *less* compiler work than the first, because Axiom functions are already C-ABI-shaped externally-linked `define i64 @sym(i64, …)` (`codegen.ax:2980-3021`). Experiment 3 worked with nothing but a rename.

```rust
// GENERATED by axiom-bindgen from `ffi.manifest.json`'s "exports"
extern "C" {
    fn axiom_rt_init(argc: i64, argv: i64) -> i64;
    #[link_name = "ax_hash_block"] fn ax_hash_block(w: i64) -> i64;
}
```

1. **Export declaration.** `(pub export axiom hashBlock "ax_hash_block")` parses to `TAG_D_EXPORT`. `checkExportTarget` resolves `hashBlock` against the exact-name index and reports **AX3039** if it names no `pub` `TAG_D_FN` *with a declared `TAG_D_SIG`* — a function with no signature is one whose parameters all default to `Int` (`typecheck.ax:2734-2760`), which the manifest cannot record honestly — **AX3036** if that signature carries a tyvar (it would take `%__evw.h`, which no Rust caller can supply), **AX3038** if it carries a `String` in *parameter* position (§3's direction table, and §12 gaps 1 and 7), and **AX3040** if two exports claim one symbol. `TAG_D_EXPORT` pushes no `FnEnt` and enters no definer index (§3).
2. **Symbol emission.** `emitFnDef` (`codegen.ax:2980-3021`) emits the function under its *Axiom* symbol as it does today. The export adds one alias line to the same block as the `declare`s, from `CG` word 38:

   ```llvm
   @ax_hash_block = alias i64 (i64), ptr @hashBlock
   ```

   **Decision: an alias, not a rename.** Renaming would break every intra-module call and `mangledFor`'s map. An alias costs one line, keeps recursion and internal references intact, and gives the linker exactly one extra global symbol per export — which is what the allowlist gate counts.

   **The generated Rust always binds the manifest's export symbol, never the aliasee.** `#[link_name = "ax_hash_block"]`, in every case. The aliasee is an implementation detail that is not stable across module layout: for a function reached through an imported module it is `Mod$name`, and while `$` is legal in an LLVM identifier and in both Mach-O and ELF, a Rust identifier cannot contain it — which is one reason the alias is *necessary* rather than cosmetic. The other reason is the gate: `Mod$name` does not match §8's `ax_` symbol prefix, so a Rust binding that bound the aliasee directly would fail the very check the manifest exists to pass.
3. **Archive output.** `axiom build --staticlib --input src/lib.ax --output libmylib.a`:
   - `emitAllocator` (`codegen.ax:1983-2001`) emits `define i64 @axiom_rt_init(i64 %argc, i64 %argv)` in place of `@main`, with the same two stores into `@__axiom_argc`/`@__axiom_argv` and the same `call i64 @__axiom_user_main()` — or `ret i64 0` when the entry file declares no `main`, which is legal in this mode only.
   - `assembleAndLink` (`driver.ax:205-236`) runs `llc -filetype=obj -relocation-model=pic` as today, then `ar rcs <out> <obj>` instead of `cc`. A missing `ar` reports through the existing `toolFailDiag`/AX4003 path (`driver.ax:189-203`), which `check-driver.sh` already greps for the tool's name.
4. **Rust calls in.** `axiom_rt_init(argc, argv)` once, then `ax_hash_block(w)`. Init is required only for code that reads `sysArg`/`sysEnv`, because `@__axiom_argc`/`@__axiom_argv` are `internal` globals (`codegen.ax:1991-1992`). Allocation does *not* depend on it: `@__axiom_bump` and `@__axiom_bump_end` both start at 0 and `axiom_alloc` (`codegen.ax:2046`) takes the refill path on the first sized request. That reads as lazy from the emitted allocator and **must be pinned by a fixture before anything relies on it.**
5. **Argument construction.** Every v0 argument is a scalar or a `Foreign`, so Rust passes the `i64` and there is no construction step, no boxing and no handle table. `Str` arguments are refused in v0 (AX3038) for two independent reasons — Rust cannot build a header safely (§12 gap 1) and the export path would leak a count on every call (§12 gap 7).
6. **Return.** The `i64` comes back in the ordinary return register; a `Float` return is bits and needs `f64::from_bits`. A `String` return is permitted in this direction and is read through `AxStr::from_handle`; if Rust intends to keep it past the call it calls `axiom_retain` and later `axiom_release` (C7).

**The hard constraint on this direction: one thread, forever.** MM-PAR-1 has no atomics and no TLS, and I11 makes all allocator state process-private. `@__axiom_bump`, `@__axiom_slabs` and every reference count are plain non-atomic globals. Two Rust threads calling into Axiom concurrently corrupt the heap silently. The generated binding therefore hands out a `!Send + !Sync` `AxiomRuntime` token obtained from a `OnceLock`, with a debug-build thread-id assert on every entry point. This is convention plus a debug check, **not** an enforced property — see §12 gap 2.

---

### 7. Why there is no trampoline, and what that buys

A VM-hosted FFI (JNI, CPython, LuaJIT's `ffi`, wasm imports) needs a dispatcher because three conditions hold simultaneously, and **none of them holds here**:

| VM condition | Axiom |
|---|---|
| Arguments live in an interpreter stack or a boxed object, not in machine registers, so something must move them | Every value is one 64-bit word in a native frame (I1, I10). `emitParams` (`codegen.ax:3658`) already emits the C ABI |
| A tracing GC needs a safepoint transition and root pinning around the foreign call | ARC, not GC (MM-LIFE-2f). There are no safepoints, no shadow stack, no roots to pin. Arguments are borrows (§5 step 8), so there is nothing to pin them *with* either |
| An exception/unwind boundary must be installed | The module has zero `personality`, `invoke`, `landingpad` (measured on the seed IR). There is nothing to install |

So the Axiom→Rust call is *literally the same instruction* `emitPlainCall` emits for a call to another Axiom function. The only differences in the whole module are: the callee is `declare`d rather than `define`d, and `fnTakesEvw` answers 0. Symmetrically, Rust→Axiom needs no Axiom-side work at all beyond an alias, because the functions were already externally-linked C-ABI `define`s.

What that buys:

- **Zero call overhead.** No argument packing, no per-call allocation, no per-call ARC traffic, no state machine. An extern call is indistinguishable in cost from an internal one, and `opt` schedules around it as a normal opaque call.
- **Byte-identical output for non-FFI programs.** The `declare`/`alias` block is written only when a boundary declaration exists; `check-freestanding.sh` on `tests/stdlib/*.ax` sees exactly the IR it sees today, and `check-reproducible.sh` (I12) is untouched.
- **No new failure mode.** A trampoline is code, and code that runs on every boundary crossing is code whose bugs are boundary-shaped and hard to attribute. There is none to get wrong.
- **The reverse direction for free**, which is why experiment 3 needed only a rename.

The cost, stated plainly: **there is no dynamic FFI.** You cannot `dlopen` a library and call a symbol whose name is a runtime string, because the emitted module is closed and every callee is fixed at compile time. A VM can do that; this design cannot and should not try. Every foreign symbol is named in source, appears in a `declare`, and appears in the allowlist manifest — which is precisely what makes MM-FFI-5 requirement 4's *enumerating* gate writable at all.

---

### 8. A Rust crate as an Axiom module

Axiom has no package manager and v1 does not add one (`docs/v1-roadmap.md:1153`). The FFI does not add one either. It reuses the existing external-package pattern verbatim: a directory of `.ax` files, dotted module paths, found by `moduleSearchDirs` (`codegen.ax:1330-1345`).

```
rust/blake3-axiom/
  Cargo.toml
  src/lib.rs            # `include!("shim.rs");`
  src/shim.rs           # GENERATED
  axiom/Blake3.ax       # GENERATED, committed
  ffi.manifest.json     # GENERATED, committed
```

```scheme
(import Blake3 (blake3Hash blake3NewBuf blake3FreeBuf))
```

```bash
axiom build --ffi rust/blake3-axiom/ffi.manifest.json \
            --input src/main.ax --output prog
```

- **Module naming is declared, never derived.** `modPathToFile` (`codegen.ax:1250-1256`) maps `.` to `/`, and a crate named `blake3-axiom` has no legal module spelling. The manifest states `{"name":"Blake3","dir":"rust/blake3-axiom/axiom"}`; the crate name and the module name are independent.
- **Search order.** `--ffi` module directories are inserted into `moduleSearchDirs` immediately after `entryDir` and before `AXIOM_PATH`. Rationale: the entry directory must keep its shadowing power (`codegen.ax:1308-1320` records why), and an explicit per-invocation argument must not lose to an ambient environment variable.
- **Nothing about a binding module is second-class.** It is checked, formatted and symbol-indexed by `axiom check`, `axiom fmt --check`, `axiom symbols` like any other module — which matters, because that is how a stale generated `.ax` gets noticed by a human.
- **Symbol prefix.** The manifest declares `"symbolPrefix"` (default `"ax_"`) and the gate enforces it on **`imports.axiom` and `exports` only** — the symbols this design creates. It is not enforced on `imports.platform`, which is whatever the crate's own runtime drags in and is reviewed rather than legislated (§9, §11). Rationale: the allowlist gate needs a rule as cheap to state as `libc_names` is today (`scripts/check-freestanding.sh:56-71`), and a prefix makes "an unexpected FFI symbol appeared" a single grep.

---

### 9. Build, link and manifest

```json
{
  "ffiAbi": 0,
  "fingerprint": "9f3c1ad2e7b4560f",
  "symbolPrefix": "ax_",
  "panic": "abort",
  "rustStd": false,
  "modules": [ { "name": "Blake3", "dir": "rust/blake3-axiom/axiom" } ],
  "link":    [ { "kind": "static", "path": "rust/target/release/libblake3_axiom.a" } ],
  "imports": {
    "axiom":    [ "ax_blake3_hash", "ax_blake3_new_buf", "ax_blake3_free_buf",
                  "__axiom_abi_v0_9f3c1ad2e7b4560f" ],
    "platform": [ ]
  },
  "exports": [ "axiom_alloc", "axiom_retain", "axiom_release", "ax_hash_block" ]
}
```

**Decision: `imports` is split into `axiom` and `platform`.** They are checked by different rules and conflating them makes the gate self-contradictory (§11). `imports.axiom` is the set this design creates — the FFI entry points plus the ABI guard — and is prefix-checked. `imports.platform` is everything the crate's runtime pulls in on its own: empty for a `no_std` + `panic="abort"` binding (experiment 1 measured `nm -u` as completely empty), and roughly 190 entries including `malloc`, `memcpy`, `_Unwind_Resume` and `_tlv_bootstrap` for a std one (experiment 2). It is enumerated and reviewed, not prefix-checked and not forbidden.

**Decision: the manifest is JSON, not TOML.** `stdlib/Json.ax` exists; no TOML parser does. The compiler must not grow a parser to read its own build input, and the driver must stay cargo-free (`scripts/bootstrap-from-seed.sh:36`). Cargo *writes* it; the compiler *reads* it.

**Link line.** `assembleAndLink` (`driver.ax:205-236`) builds `ccArgs` as `[objPath, "-o", outPath]`. Each `link[].path` is appended verbatim after `objPath`.

**Decision: absolute or repo-relative archive paths, never `-l`/`-L`.** A `-l` search depends on the machine's library layout and on argument order, and I12 ("compilation is deterministic and reproducible", gated by `check-reproducible.sh`) is a stated invariant. A named `.a` either exists or the link fails loudly with the path in the message. If a future need forces `-l`, it belongs in a separate manifest key that the gate reports on, not silently mixed in.

**Failure mapping.** A missing archive is an `AX4003` toolchain failure through `toolFailDiag` (`driver.ax:189-203`), whose help text names the manifest key that produced the path.

---

### 10. Versioning, pinning, and ABI drift

**Pinning is cargo's job.** An Axiom project pins a Rust crate by committing `rust/Cargo.lock`. Axiom resolves nothing, computes no version constraints, and has no lockfile of its own. The Axiom-visible surface is the *generated triple* — `.ax` module, `.a`, manifest — and its identity is one 64-bit fingerprint.

**The fingerprint** is FNV-1a-64 over a canonical newline-delimited text, one line per boundary entity, sorted by symbol:

```
abi=0
prefix=ax_
extern rust ax_blake3_free_buf (Foreign)->Int
extern rust ax_blake3_hash (Foreign,Int,Foreign)->Int
extern rust ax_blake3_new_buf (Int)->Foreign
export axiom ax_hash_block (Int)->Int
shape.header=16 shape.mapbase=16 shape.mapbits=47 shape.strhdr=5 shape.strowner=16
```

The last line pins the *representation* constants, not just the signatures — a change to the 16-byte block header, to MM-LIFE-2d's bit layout (`docs/memory-model.md`, and the 47-mappable-word limit behind AX3029), to the five-word `Str` header, or to the **offset of the `Str` owner word** must invalidate every binding, because `axiom-abi` encodes all of those constants. The owner offset is on this line specifically because it is the field a Rust implementer is most likely to leave at whatever `axiom_alloc` zeroed (§12 gap 1), so a silent change to it must not survive into a binding built against the old layout.

**Three layers of drift detection**, deliberately redundant because each catches what the others cannot:

1. **Generated-file freshness (CI, cargo present).** `cargo run -p axiom-bindgen -- --check` regenerates into a temp dir and diffs. Catches: someone edited the `.ax` or `shim.rs` by hand, or bumped the crate without regenerating. Does not run for a user who only has the committed checkout.
2. **Driver pre-check (every build, no cargo).** The compiler computes the fingerprint from the `extern`/`export` declarations it actually parsed plus its own shape constants, compares against `manifest.fingerprint`, and on mismatch reports **AX4004** naming both hex values and the first differing canonical line. This is the layer that produces a *readable* diagnostic. It cannot detect a stale `.a` that no longer matches its own manifest.
3. **Link-time symbol (backstop, catches the stale `.a`).** The compiler emits, only when at least one extern exists:

   ```llvm
   @__axiom_abi_guard = constant ptr @__axiom_abi_v0_9f3c1ad2e7b4560f
   declare void @__axiom_abi_v0_9f3c1ad2e7b4560f() #0
   ```

   and `axiom-macros` emits the matching `#[no_mangle] pub extern "C" fn __axiom_abi_v0_9f3c1ad2e7b4560f() {}` into the crate. An external-linkage global cannot be dropped by `opt`, so the relocation always survives to the linker. A rebuilt-but-not-recopied archive produces `undefined symbol: ___axiom_abi_v0_…` — an ugly message, but a *hard failure* at exactly the point where layer 2 has already been satisfied by a stale manifest. `axiom-gate` translates that message on request.

**`ffiAbi`** is the version of the *contract in this document* (C1–C8), bumped only when the contract changes; it is a manifest field so that a compiler meeting a future manifest refuses it by number rather than by fingerprint mismatch.

---

### 11. Gates, and what stays green

**`scripts/check-freestanding.sh` stays, unchanged, and must stay green.** It runs on `tests/stdlib/*.ax`, none of which uses FFI, so its IR sweep, its `nm` sweep, its stage1 pass (`scripts/check-freestanding.sh:121-170`) and all its negative probes are unaffected. Notably, its last probe (`scripts/check-freestanding.sh:271-290`) asserts that `(foreign posix_spawn …)` is refused as AX2004 — that probe keeps passing verbatim, and its continued green is the evidence that `extern` is a new door rather than the old one reopened.

**`scripts/check-ffi-allowlist.sh` is new** and implements MM-FFI-5 requirement 4 for `tests/ffi/*.ax`:

1. every `^declare` in the emitted IR names a symbol in `manifest.imports.axiom`;
2. `nm -u` on the linked executable ⊆ `manifest.imports.axiom` ∪ `manifest.imports.platform`, **with no platform escape hatch**. The measured baseline is that this set is *empty* for a no-FFI program and for a `no_std` + `panic="abort"` FFI program (experiment 1: `nm -u` completely empty). Note that `check-freestanding.sh` tolerates nothing today either — its darwin branch (`scripts/check-freestanding.sh:107-112`) is a bare `nm -u "$exe" | sed 's/^_//'` whose only test is a grep against `libc_names`, and there is no allowance list anywhere in the file. If a real darwin startup stub ever does appear, it is added to `imports.platform` **by name, with the measurement that found it**, never as an unnamed "unavoidable set" — an unspecified tolerance in the strictest gate in the design is a hole an implementer will fill by guessing;
3. every symbol in `manifest.imports.axiom` matches `^<symbolPrefix>` or is the ABI guard. This rule governs `imports.axiom` **only** — applying it to platform symbols would reject every std manifest on `malloc` alone;
4. `nm -u` on the `.a` ⊆ `manifest.exports` ∪ `manifest.imports.platform`. (`nm -u` and not `nm -g`: `-g` lists the archive's *defined* globals, which is a different question. What the gate wants to know is what the archive *references* — the Axiom-provided symbols it may legitimately call, plus whatever its own runtime needs.);
5. the negative probes: a symbol added to the binary but not the manifest fails; a manifest entry with a typo fails; a fingerprint edited by one nibble fails at link.

`manifest.rustStd` is not forbidden. A std crate simply produces an `imports.platform` list of ~190 entries including `malloc`, `memcpy`, `_Unwind_Resume` and `_tlv_bootstrap` — exactly what experiment 2 measured, 14 of them on `check-freestanding.sh`'s forbidden list. The gate's job is to make that list *visible and reviewed*, not to legislate it, which is why items 2 and 4 admit it by name and item 3 does not touch it. That is the difference between a blanket ban and an enumeration, and it is the whole content of MM-FFI-5 requirement 4.

---

### 12. Known gaps and unresolved problems

State these in the spec rather than discovering them in review.

1. **A `Str` that Rust would have to CONSTRUCT is refused in v0 (AX3038)** — that is a `String` return from an extern and a `String` parameter of an export (§3's direction table). Constructing an Axiom `Str` means calling `axiom_alloc` and writing a **five-word** header, and all five matter. The static form (`codegen.ax:1019-1023`) is `{ i64 -1, i64 0, i64 len, ptr @str_i, i64 0 }`, and the circulating handle is element 2, so relative to the handle the words sit at:

   | offset | word | meaning |
   |---|---|---|
   | −16 | count | reference count; `-1` is the never-reclaimed static sentinel that retain/release read and stop on (`codegen.ax:2274-2300`) |
   | −8 | shape | MM-LIFE-2d form bit, padded payload word count, and the per-word reference map |
   | +0 | len | byte length, excluding the NUL that MM-VAL-7 maintains |
   | +8 | ptr | the bytes |
   | +16 | **owner** | MM-LIFE-2d's `Str` half. `0` means the bytes belong to no counted block, so nothing is freed on the handle's death; a literal's owner is 0 because its bytes are loader-resident, and a slice of a literal inherits that zero and retains nothing (`codegen.ax:1005-1017`) |

   Getting the shape word wrong is a silent double-free or a wild read, not a crash at the boundary — and the **owner** word is the one a Rust implementer of `AxStr::new_owned` is most likely to leave at whatever `axiom_alloc` zeroed without knowing that zero is a *claim*, not a default. The fix is real but must be built in the stated order: the compiler grows a `--emit-abi-constants` mode that writes `rust/axiom-abi/src/shape.rs`, the fingerprint covers those constants including `shape.strowner` (§10), and only then does `AxStr::new_owned` ship. Until that exists, `axiom-abi` can read a `Str` and cannot build one.
2. **The single-thread rule is a convention, not an invariant.** MM-PAR-1 and I11 make concurrent entry into Axiom from Rust heap-corrupting, and nothing in the type system or the linker prevents a Rust program from spawning a thread and calling an export. The `!Send`/`!Sync` token plus a debug thread-id assert is the best available enforcement and it disappears in release builds. A `#[cfg(not(debug_assertions))]` program that violates it fails silently and non-deterministically. This is the single worst residual hazard in the design and it should be stated in the generated binding's own documentation, not just here.
3. **`Foreign` cannot be enforced once laundered.** MM-FFI-5 requirement 2 says no arena primitive applies to foreign memory. What actually enforces that is `tyCompat` at the argument check (`typecheck.ax:4053`): `__axiom_arena_reset_keeping` is registered as `(mkIntArrow 3)` (`typecheck.ax:1514`), and `TAG_T_CON` matching by name and arity refuses a declared `Foreign` there. (`tyReprClash` does *not* do this — its one call site is `checkDeclaredReturn`, so it never sees an argument.) But the tree's deliberate untyped-handle convention means a `Foreign` passed through an `Int`-typed container is invisible to the checker, and `tyCompat` will never say otherwise, since three attempts to make it say otherwise were merged and withdrawn (`053c525`, `9d5b508`). The check is best-effort by construction. A dynamic guard is possible (`axiom_alloc`'s chunk list could answer "is this address mine?"), costs a walk per arena call, and is not proposed for v0.
4. **`catch_unwind` needs `std`, and `std` costs the allowlist.** C6 offers two routes; they are not equivalent. `panic="abort"` keeps `nm -u` empty (experiment 1) but turns a Rust bug into process death with no Axiom-side diagnostic. `catch_unwind` gives a returnable error value but drags in `std` and its 188 symbols into `imports.platform`. The manifest's `"panic"` field records which was chosen; there is no way to have both, and the spec should not pretend otherwise.
5. **The fingerprint does not cover Rust-side semantics.** Two crate versions with identical exported signatures produce identical fingerprints. Only `Cargo.lock` distinguishes them, and `Cargo.lock` is not consulted at Axiom build time. A semantic regression in a pinned crate is invisible to every layer in §10 — correctly so, since ABI drift and behaviour drift are different problems, but it should not be mistaken for coverage.
6. **`ar` is a new hard dependency for `--staticlib` only.** It joins `llc`, `opt` and `cc`. `bootstrap-from-seed.sh` never invokes it, so the cargo-free/`ar`-free bootstrap path is unaffected, but `check-driver.sh` will need an arm asserting the AX4003 message names `ar` and not `cc`.
7. **An exported Axiom function takes one UNBALANCED count on every reference parameter.** `retainRefParams` (`codegen.ax:3210-3221`) emits one `axiom_retain` per reference parameter at entry — that is the callee-retains convention §5 step 8 relies on — and the only balancing release in the emitter is `releaseTailOlds` (`codegen.ax:3345-3352`), which runs on a **tail-loop rebind** and nowhere else. The ordinary `ret` path (`codegen.ax:3134`, `codegen.ax:3895`) emits no parameter release at all. Inside Axiom this is consistent, because the count a frame took is the count its caller's own bookkeeping accounts for; across the boundary it is not. A Rust caller that dutifully pairs `axiom_retain`/`axiom_release` per C7 **can never drive a handle it built back to zero through the export path** — every call adds one count that nothing removes. This is the second, independent reason `String` is refused in an exported function's parameter position (§3, §6 step 1), and it is why closing gap 1 alone does not make that position safe: the ownership rule has to change too, or exports need a release-on-return path that intra-module calls do not get. In v0 the restriction makes the leak unreachable — no admissible export parameter is reference-class — but the rule must be stated before the restriction is lifted.
8. **Foreign memory has no allocator, by design, and that is a real constraint on `no_std` bindings.** `Foreign` values originate only from Rust (§3), and a `no_std` binding has no allocator to originate them from — §5's shim uses crate-owned `static mut` storage with a fixed slot count, which is honest but does not scale. The alternatives are a `#[global_allocator]` in the binding crate or plain `malloc`, and both put entries into `imports.platform` where the gate shows them (§9, §11). MM-FFI-3 applies to all of it: this memory is outside the arena — not scrubbed, not reclaimed, not counted — so its lifetime is entirely the binding author's problem and the `.ax` module must declare a free function for every allocate function it declares.
---

## 5. Type Mapping and Data Representation

### 0. The premise this section is built on

Every rule below exists because of one fact and one absence.

The fact: **every Axiom value is exactly one 64-bit machine word** (`docs/memory-model.md:431` MM-VAL-1; `emitParams` `self_host/codegen.ax:3657-3665` renders every parameter as `i64 %name` with no attribute, and every function returns `i64`). There is no aggregate ABI, no sret, no byval, no varargs — **and no `signext`/`zeroext` on anything**, which §2.1 turns into a hard rule about return types.

The absence: **the Axiom type checker cannot enforce most of this section, and the part it does enforce is not the part an earlier draft of this document claimed.** `tyCompat` (`self_host/typecheck.ax:188-235`) is the whole of the "unifier": a `TAG_T_VAR` on either side matches anything (`:200-201`), poison matches anything (`:198-199`), and constructors match by name and arity alone. There is no substitution and no solving; `tyInst` only freshens.

Two corrections to the folklore, both measured, because the design of §3 and §6 turns on them:

- **`tyReprClash` never runs at a boundary.** It has exactly one call site in the tree — `typecheck.ax:7020`, inside `checkDeclaredReturn` (`:6987-7022`) — where `want` is a function's *declared return* and `got` is the type *inferred from its body*. It never inspects an argument. An `extern` declaration has no body, so `tyReprClash` cannot fire on one at all. What it does buy is real but narrow: it catches a **wrapper function** whose declared return disagrees with its body, which matters for §6's generated wrappers and for nothing else here.
- **`tyCompat` is the boundary check, and it is stronger than "matches anything".** Its `TAG_T_CON` arm (`typecheck.ax:216-220`) requires `strEq` on the names **and** equal argument counts **and** pairwise compatibility of the arguments via `tyCompatVec`. It runs at every application site (`typecheck.ax:4053`), every struct-field position (`:5443`), and every `let`/`set` position (`:5615`, `:5679`). So `Bool` against `Int`, and `Foreign` against `Int`, are already caught on the name alone, with no help from `tyIsReprScalar` — and, as §3 shows, so is `(Foreign File)` against `(Foreign Socket)`.

So the mapping is still enforced primarily where both a Rust type and an Axiom type are simultaneously visible: the binding generator. But the Axiom-side check is a genuine second line, not a rounding error, provided it is aimed at the check that actually runs.

**Enforcement legend**, used in every rule below:

| Tag | Layer | What it can catch |
|---|---|---|
| **[R]** | Rust's own type system | the shim's signature is wrong on the Rust side |
| **[P]** | proc-macro (`#[axiom_extern]`) compile error | a Rust signature that has no Axiom spelling at all |
| **[B]** | bindgen check, at binding-generation time | Axiom declaration ≠ Rust signature; the only place both exist |
| **[C]** | Axiom compiler diagnostic | a rule expressible in the tag-and-name vocabulary the checker actually has |
| **[T]** | runtime assert in the generated shim | value-range facts no type can express (surrogates, non-0/1 Bools, UTF-8) |
| **[G]** | the MM-FFI-5 allowlist gate | a symbol crossing that no binding declared |

**[C] is narrow, not weak, and it is never used alone.** It means precisely one thing in this document: `tyCompat` reported a constructor-name or arity disagreement at an argument, field, or binding position. It never means a representational check, because the only representational predicate in the tree does not run where externs live.

---

### 1. Master mapping table

`Foreign` is the new opaque foreign-pointer built-in specified in §3, spelled `(Foreign T)` in its recommended form. "Wire" is always the i64 that actually travels.

**Read row 2 and the return-type column together with §2.1: a Rust shim's declared return type is ALWAYS `i64`, in every row of this table, without exception.** Narrow widths appear only in parameter position.

| # | Axiom type | Rust type (param position) | Wire (i64) | Copy? | Owner | Enforced |
|---|---|---|---|---|---|---|
| 1 | `Int` | `i64` | the value | zero-copy | n/a | [B] |
| 2a | `Int` | `i8 i16 i32 u8 u16 u32` **as a parameter only** | low bits; callee ignores the high half | zero-copy | n/a | [B][T] narrowing check in body |
| 2b | `Int` | the same widths **as a return type** | — | **refused [P]** | — | widen in the body: `(x as i32) as i64` |
| 3 | `Int` | `u64 usize isize` | bit-identical, **reinterpreted** | zero-copy | n/a | [B] opt-in only |
| 4 | `Float` | `f64` — **never in the signature**, only `f64::from_bits` in the body | `f64::to_bits()` | zero-copy | n/a | [B] + [C] float flags |
| 5 | `Bool` | `bool` param; **`i64` return** | 0 or 1 | zero-copy | n/a | [T] `v != 0`; [P] on a `bool` return |
| 6 | `Char` | `char` param; **`i64` return** | Unicode scalar as integer | zero-copy | n/a | [T] `char::from_u32`; [P] on a `char` return |
| 7 | `Char` | `u32` param | code point, unvalidated | zero-copy | n/a | [B] |
| 8 | `Unit` / `Void` | `()` | fixed at 0; shims write 0 | n/a | n/a | [B] |
| 9 | `String` (borrowed) | `&[u8]` (as `ptr`,`len`) | header address | zero-copy | Axiom arena | [B][T] lifetime = call |
| 10 | `String` (borrowed) | `&str` | header address | zero-copy | Axiom arena | [T] UTF-8 validate |
| 11 | `String` (borrowed) | `&CStr` | header address | zero-copy | Axiom arena | [T] terminator probe (§4.4) |
| 12 | `String` (produced) | `&[u8]` / `&str` out of Rust | new Axiom `Str` | **copies** | Axiom arena | [B] via `axiom_str_new` |
| 13 | `(Foreign T)` | `*mut c_void`, `NonNull<T>`, `Box<T>`-as-raw | the raw address | zero-copy | **Rust** | [B][C] name+arity via `tyCompat` |
| 14 | `Int` (a `Vec` handle) | `&[i64]` | header address | zero-copy | Axiom arena | [B][T] borrow = call; no push during borrow |
| 15 | `Int` (a `Vec` handle) | `Vec<i64>` out of Rust | new Axiom `Vec` | **copies** | Axiom arena | [B] |
| 16 | `struct P` | *exploded* to N scalars | N separate i64 params | zero-copy | Axiom arena | [B] |
| 17 | `struct P` | **`Int` handle in a Rust newtype** + accessors | block address | zero-copy | Axiom arena | [B] |
| 18 | `data T` | **refused as a wire type** | — | — | — | [B] refusal |
| 19 | `(Option a)` | `Option<T>` | out-cell protocol (§6.1), cell crosses as **`Int`** | one 16-byte cell | Axiom arena | [B] |
| 20 | `(Result a e)` | `Result<T, E>` | out-cell protocol (§6.2), cell crosses as **`Int`** | one 16-byte cell | Axiom arena | [B] |
| 21 | closure / `(-> a b)` | `extern "C" fn(i64, i64) -> i64` | closure-record address, crosses as **`Int`** | zero-copy | Axiom arena | [B][P] arity 1 only |
| 22 | tuple type `(a, b)` | — | **not expressible** | — | — | [B] refusal |
| 23 | list type `[T]` | — | **not expressible** | — | — | [B] refusal |
| 24 | `*T` / `*mut T` | — | **not expressible** | — | — | [B] refusal |
| 25 | any type variable | — | **not expressible** (C3) | — | — | [B][C] |

**Rows 13, 17, 19, 20 and 21 encode one rule, stated once here and enforced in §3:** `Foreign` means memory that did **not** come from `axiom_alloc`. Anything Rust merely borrows out of the arena — an out-cell, a closure record, a struct block, a `Vec`, a `Str` — crosses as an `Int` handle wrapped in a Rust newtype, never as `Foreign`. An earlier draft used `Foreign` for both and made MM-FFI-5(2) unenforceable.

---

### 2. Primitives

#### 2.1 `Int` ↔ `i64`, and the return-width rule

Wire: identity. `Int` is signed 64-bit throughout — `Bool` and `Char` and every handle share the representation (MM-VAL-1). Zero-copy, no owner.

**Rust widths narrower than 64 bits are permitted in PARAMETER position only.** The callee is free to ignore the high half of an argument register, so an Axiom `Int` arriving at a shim declared `(x: i32)` is well-defined: Rust reads the low 32 bits, which is exactly what the binding asked for. The bindgen still emits the range check described below.

**A shim's declared RETURN type must always be `i64`. Refused at [P] otherwise.** This is not a style rule; it is the same ABI-register hazard §2.2 identifies for `f64`, and it is live on this very host.

Measured, rustc 1.97.1 / Apple clang 21, darwin-arm64:

```rust
// WRONG - and it compiles, links, and returns garbage.
#[unsafe(no_mangle)]
pub extern "C" fn ax_narrow(x: i64) -> i32 { (x as i32).wrapping_mul(3) }
```

lowers to `add w0, w0, w0, lsl #1 ; ret` — it writes **only `w0`**, leaving the top half of `x0` as whatever was there. A caller declaring `extern long ax_narrow(long)` — which is Axiom's exact and only view, since `emitParams` (`codegen.ax:3657-3665`) emits `i64 %name` with no attribute and the header at `codegen.ax:3016-3018` is `define i64 @...` — calls `ax_narrow(-1)` and prints **4294967293**, not `-3`. Reproduced on this machine.

The correct form widens inside the body, where Rust's own type system supervises the conversion:

```rust
#[unsafe(no_mangle)]
pub extern "C" fn ax_narrow(x: i64) -> i64 { (x as i32).wrapping_mul(3) as i64 }
```

**Rows 5 and 6 fall under the same rule.** A `bool` or `char` return happens to work on AArch64 because the ISA zero-extends every write to a W-register, which is an accident of this target and not a promise of the C ABI; it does not hold on x86-64 SysV, where the upper bits of `eax` are simply undefined after a byte-sized write. Both are refused as return types at **[P]**; return `i64` and write `b as i64` / `c as u32 as i64`.

**Narrowing back is where the parameter case bites** — an Axiom `Int` of `1 << 40` handed to a Rust shim declared `u32` must not silently truncate. The generated shim performs `i64::try_into()` and, on failure, takes the extern's declared failure path (§6.2) or aborts; it never wraps **[T]**.

`u64`/`usize`/`isize` are permitted only under an explicit `#[axiom_extern(reinterpret)]` opt-in **[P]**, because the round trip is bit-exact but the *ordering* is not: `0xFFFF_FFFF_FFFF_FFFF` is `u64::MAX` in Rust and `-1` in Axiom, and Axiom's `<` is a signed compare. A program that passes a Rust `u64` hash through Axiom and compares it against 0 gets the wrong answer with no diagnostic anywhere.

**Edge case that bites:** Axiom's multiply wraps and its divide traps (`emitDivTrap`, `codegen.ax:2460-2490`). A Rust shim that returns a value Axiom then divides by must not assume Rust's panic-on-overflow discipline carries across; it does not.

#### 2.2 `Float` ↔ `f64`

Wire: the IEEE-754 bit pattern in an i64. A `Float` is bitcast to `double` only at operators (`codegen.ax:5847` is the sole `bitcast double … to i64` site, at the operator's result). The Rust shim therefore takes `i64` on the wire and does `f64::from_bits(x)` / `y.to_bits()`; it must **not** be declared `extern "C" fn(f64) -> f64`, because that would place the value in a *floating-point register* under the AArch64/SysV C ABI while Axiom passes it in a general-purpose one. This is the single most likely silent-garbage mistake in the whole mapping, and §2.1's return-width rule is its integer twin.

```rust
// CORRECT: the wire is i64 in a GPR, exactly as Axiom emits it.
#[unsafe(no_mangle)]
pub extern "C" fn ax_rust_scale(x_bits: i64, k_bits: i64) -> i64 {
    (f64::from_bits(x_bits as u64) * f64::from_bits(k_bits as u64)).to_bits() as i64
}
```

**Decision — an extern's signature MUST go through the ordinary `::` / `TAG_D_SIG` path.** `scanFloatSigs` (`codegen.ax:338-349`) builds the emitter's float table *only* from `TAG_D_SIG` nodes, reading `nodeB d` (the flag vector `sigFloatFlags` produced) and `nodeTy d`. `fnRetIsFloat` (`codegen.ax:613-623`) answers **0 for any name with no FSig entry**, with the explicit comment "a function with no signature cannot traffic in floats". An extern that registers a `FnEnt` but no `D_SIG` is therefore invisible to the float table, and every use of its result is emitted as an integer operation.

**The motivating example must be chosen with care, because the obvious one does not fail.** `emitBinop2` (`codegen.ax:5767-5777`) takes the float path when **either** operand's flag is 1 — "Either operand being a float makes the operation a float operation" — and `emitFlt` (`codegen.ax:4793-4799`) sets `(memSetWord cg 14 1)` for a float literal, with the comment "the flag is what routes `(+ x 1.5)` to `fadd`". So `(+ 1.0 (rustScale x k))` emits `fadd` whether or not `rustScale` has a signature, and a fixture written that way passes while proving nothing. An earlier draft of this section used exactly that expression and was wrong.

The failing shapes are the ones where **no operand carries a float flag from anywhere else**:

- `(+ (rustScale x k) (rustScale p q))` — both flags 0, so `emitIBinop` emits `add` on two `double` bit patterns. Silent wrong answer, `check: OK`.
- `(:: outer (-> Float Float))` `(fn (outer x) (rustScale x half))` — the enclosing function's return flag comes from `fnRetIsFloat`, which answers 0 for the unsigned extern, so the result is handed back as an integer-flagged word and the *caller's* arithmetic is mis-routed one level up.

Either is a valid fixture; the first is the shorter one. The **decision stands unchanged** — only the evidence for it needed correcting.

Alternatives considered: a parallel float table for externs (rejected: two tables drift, and `findFSig` is already the single reader at `codegen.ax:466`, `615`, `3000`); teaching `emitPlainCall` to consult the extern table directly (rejected: same drift, and `fnTakesEvw` reads the same entry).

**Two compiler changes ride along with this decision, and neither is inferable from it.** Routing externs through `TAG_D_SIG` puts them in front of two checks that assume every signature is answered by a `TAG_D_FN`:

1. **AX3015 fires falsely on every extern.** `checkMissingDefs` (`typecheck.ax:1242-1262`) reports every entry-file `TAG_D_SIG` whose name is absent from `defIdxBuild`'s index, and that index admits only `TAG_D_FN` nodes with `nodeVis == 1` (`typecheck.ax:1114-1132`). A new extern tag is not a `TAG_D_FN`, so **every extern declared in the entry file draws a false "`ax_rust_add` has a signature but no definition"** — the first compile of the first FFI program is red. `defIdxBuild` must index the extern tag alongside `TAG_D_FN`.
2. **`repArity` must not answer -1.** `repArity` (`typecheck.ax:2728-2733`) answers `paramCount` when `>= 0`, else `arrowDepth` when `isBuiltin`, else -1 — and a -1 answer *silently disables* the AX3013 bare-value refusal and the AX3009/AX3013 saturation check. The retired `foreign` used `paramCount` -1, which is why none of §8's arity refusals had a compiler backstop. The extern's `FnEnt` must be registered with a real non-negative `paramCount` — the arrow depth of its declared signature — so those checks stay alive.

Both are one-line changes. Neither is optional.

The float flag itself comes from `identIsFloat` (`parser.ax:1838-1840`), which is a literal token compare against `"Float"`. **`Float` must be spelled bare in an extern signature.** `(Vec Float)`, `(-> Float Float)` in a nested position, or any parenthesised position is flagged 0 by construction (`parser.ax:1816-1820`).

`f32` is **refused [B]**. `F32`/`F64` survive in `scalarTyName`/`evScalarName` (`codegen.ax:6133-6148`, `typecheck.ax:542-557`) but are not surface types — `typeKeywordCanon` (`parser.ax:1620-1628`) does not know them, so a signature naming `F32` draws AX3002 (`typecheck.ax:2641-2656`). Widening `f32`→`f64` in the shim is permitted and is the recommended workaround.

**Edge case that bites:** `(!= NaN NaN)` is `false` in Axiom (`memory-model.md:530`), where IEEE-754 says true, and `Fmt.fmtFloat` renders `+inf` as `-9223372036854775808.92…`. A Rust shim that can produce NaN or ±inf must document it; the Axiom side has no way to test for either.

#### 2.3 `Bool` ↔ `bool`

Wire: 0 or 1. Axiom produces Bools by `zext i1 … to i64` (`codegen.ax:5876`), and MM-VAL-5 (`memory-model.md:533`) states `Bool` is 0 or 1.

**Rust→Axiom** is `b as i64`, returned through an `i64` signature (§2.1, row 5).

**Axiom→Rust must never `transmute`.** A Rust `bool` whose byte is not 0 or 1 is immediate UB, and Axiom can forge one: `(cast Bool 42)` type-checks, because `cast` is unchecked and `tyCompat` accepts a cast's claimed type. The generated shim does `let b = wire != 0;` **[T]**, unconditionally, in release builds too.

**What the Axiom checker actually catches here, corrected.** An earlier draft credited `tyReprClash` with catching a declared `Bool` against a declared `Int` "at an extern boundary". It does not and cannot: `tyReprClash` has one call site, inside `checkDeclaredReturn` (`typecheck.ax:7020`), comparing a declared return against a *body's* inferred type — and an extern has no body.

The check that does run is **`tyCompat`, and it is enough**: `Bool` and `Int` are two `TAG_T_CON`s with different names, and `tyCompat`'s constructor arm (`typecheck.ax:216-220`) requires `strEq` on the names before anything else. So passing a `Bool` where an extern declared `Int` is reported at the application site (`typecheck.ax:4053`) as AX3004, with no involvement from `tyIsReprScalar` at all. The same is true in struct-field (`:5443`) and `let`/`set` (`:5615`, `:5679`) positions.

`tyReprClash` still earns its place in this design, but somewhere else: it is what catches a **§6 generated wrapper** whose declared return disagrees with the body bindgen emitted for it — `(:: rustLookup (-> String (Option Int)))` over a body that answers an `Int`. That is a real check on generated code and it is worth keeping green; it is simply not a boundary check.

**Edge case that bites:** because the boundary check is name-based rather than representation-based, it is *stricter* than the folklore expected, not looser — `Span`, `JobPool` and every other named handle the tree returns through `Int` on purpose will collide with a `Foreign`- or `Bool`-typed extern parameter and be reported. That is correct, and bindgen should emit the `cast` at the wrapper, not widen the extern's declared type to `Int` to silence it.

#### 2.4 `Char` ↔ `char`

Wire: the Unicode code point as an integer. MM-VAL-5 (`memory-model.md:533-534`): "`Char` is a Unicode code point as an integer. Both are ordinary words." `stdlib/Utf8.ax:14-17` confirms and corrects the older "8-bit" claim: `'é'` is 233, `'😀'` is 128512.

Rust's `char` is a *Unicode scalar value*: `0..=0x10FFFF` minus the surrogate range `0xD800..=0xDFFF`. Axiom's `Char` has no such restriction and `Char` is in `scalarTyName`, so nothing anywhere checks it.

**Axiom→Rust:** `char::from_u32(w as u32)` **[T]**. On `None` the shim takes the declared failure path, or substitutes `utf8Replacement` (65533, `stdlib/Utf8.ax:196-197`) if the binding opted into lenient mode. It must never `char::from_u32_unchecked`.

**Rust→Axiom:** `c as u32 as i64`, **returned through an `i64` signature** — a bare `-> char` is refused at [P] under §2.1's rule (row 6), for the same W-register reason as `bool`.

**Edge case that bites:** Axiom's `Char` is a code point but Axiom's `String` is *bytes* (`stdlib/Str.ax:1-19`) — `strLen` is a byte count and `strByte` is a byte. A binding that maps `Char` to `char` and `String` to `&str` has silently mixed two indexing spaces; `strSlice` cuts at byte offsets and will happily bisect a multi-byte sequence. Bindings that index must use `Utf8.utf8Offset`/`utf8Slice` (`stdlib/Utf8.ax:151-152, 174-175`) on the Axiom side.

#### 2.5 `Unit` / `Void` ↔ `()`

**There is no unit value in Axiom.** `docs/reference.md:292` — `()` in expression position is `AX2001 expected expression`, and "nothing in the language produces or consumes one". `Unit` and `Void` are distinct type constructors, both known to `typeKeywordCanon` (`parser.ax:1626-1627`), and `Unit` is *not* a synonym for `()` (`reference.md:293`).

But every function still returns an `i64` (`codegen.ax:3014-3018`). **Decision: the FFI fixes the wire value of a `Unit`/`Void` return at 0, and the Axiom side is forbidden to read it.** The generated Rust shim ends `…; 0` — and note that this is an `i64` 0, not a Rust `()`, which §2.1's rule already required. The alternative — leaving it genuinely unspecified — was rejected because the value lands in a register the optimiser is free to fill with the last computed thing, and someone will eventually `cast Int` it and find it stable on one target.

**Edge case that bites:** a `Unit`-returning extern used in statement position inside a block still produces a register; if it is the block's last form, that 0 becomes the enclosing function's return value. This is correct but surprising.

---

### 3. `Foreign` — the opaque foreign pointer

MM-FFI-5 requirement (1) is that foreign memory be a distinct type from `Int`, and (2) that no arena primitive apply to it (`memory-model.md:2369-2375`).

**Decision: one new built-in type constructor, spelled `Foreign`, whose recommended form is PARAMETERISED — `(Foreign File)`, `(Foreign Socket)` — with bare `Foreign` retained as an untyped escape hatch.**

**Decision: `Foreign` means, strictly, memory that did not come from `axiom_alloc`.** MM-FFI-3 (`memory-model.md:2352-2362`) defines foreign memory as precisely that, and this section adopts the definition without widening it. An out-cell (§6), a closure record (§7), a struct block (§5.1), a `Vec` (§5.3) and a `Str` (§4) are all arena memory; when Rust borrows one it crosses as an **`Int` handle wrapped in a Rust newtype**, never as `Foreign`. An earlier draft passed `(cast Foreign cell)` for an out-cell allocated by `memAlloc` while simultaneously asserting that a `Foreign` word is never arena memory; that made MM-FFI-5(2)'s "no arena primitive applies" unenforceable, because the compiler could no longer tell which words the rule covered. One meaning, held everywhere.

**Why parameterised — decided on the check that actually runs.** The earlier argument for a nullary `Foreign` was that `tyReprClash` returns 0 the moment either side has a non-empty argument vector (`typecheck.ax:7055-7057`), so a parameterised type would throw away the only surviving representational check. That argument is void: `tyReprClash` never runs at a boundary (§0), so a boundary type cannot lose anything by being invisible to it.

The check that does run is `tyCompat`, and it *rewards* parameterisation. Its constructor arm compares names, compares arity, and then recurses into the argument vector via `tyCompatVec` (`typecheck.ax:216-220`). Measured on this tree with the committed compiler:

```
(data Handle (a) (MkHandle a))  (data File (MkFile))  (data Socket (MkSocket))
(:: takesFile (-> (Handle File) Int))
(:: mkSock (-> Int (Handle Socket)))
(fn (main) (takesFile (mkSock 1)))

error[AX3004]: type mismatch: expected Handle File, found Handle Socket
```

So `(Foreign File)` against `(Foreign Socket)` is a reported error, and `(Foreign File)` against bare `Foreign` is an arity mismatch. **Per-handle-type distinctness is expressible in Axiom today, at every argument, field and binding position.** Handing a `File*` to a Rust shim expecting a `Socket*` is the characteristic FFI bug and it dereferences a wrong-typed pointer in Rust; getting a compiler diagnostic for it is worth more than anything the nullary form offered.

`Foreign` against `Int` is caught either way — the names differ, and `tyCompat` tests `strEq` first.

**The cost, stated.** `tyUnknownCon` (`typecheck.ax:2430-2432`) reports an unknown **argument**, not just an unknown head: "A known head with an unknown ARGUMENT is still a miss, so `(Box Nope)` reports `Nope`." Measured:

```
(:: takesFile (-> (Handle File) Int))     ; with no declaration of File
error[AX3002]: undefined type `File` — no type named `File` is visible here
```

So every phantom tag must be a declared type. This is cheap and bindgen does it automatically: `(data File (MkFile))` is one line and compiles (verified). It costs one tag from the global counter per handle type, which is counter pressure toward MM-VAL-8b's 4096-tag cliff and nothing more, since §5.2 guarantees no tag is ever serialised.

Also verified: keyword type constructors accept arguments with no arity validation (`(Bool File)` checks OK), so adding `Foreign` to `typeKeywordCanon` makes both `Foreign` and `(Foreign T)` spellable, and `tyConKnown` resolves the head by name alone.

**Why not `*T` / `TAG_T_PTR`.** The type system already has a pointer type (MM-VAL-20, `memory-model.md:756-758`), and it is unusable: MM-VAL-21 (`:760-790`) records that `(alloc T)` allocates nothing and evaluates to the constant 0, that `*mut` is **unspellable in any signature**, that `alloc`'s type operand is never resolved, and that the form nonetheless contributes an `Alloc` effect. The specification explicitly refuses to bless it. Worse, at the codegen level `fldClass` (`codegen.ax:6159-6178`) has no `TAG_T_PTR` arm and falls through to `1` — *unclassifiable* — and `shapeBits` (`codegen.ax:6188-6207`) turns a single unclassifiable field into `-1`, which `ctorShapeConst` (`:6208-6224`) converts to an **empty map for the whole block**. A record with one `*T` field would silently lose ARC on every sibling `String` field. Reusing `*T` is the worst option available.

**Exactly which tables must learn the name.** Five sites, every one load-bearing. **All five key on the HEAD name only, which is why parameterisation costs nothing here** — `fldClass` does `(let ((n (cast String (nodeA tn)))) …)` and `evClassOf` does `(let ((n (nodeA t))) …)`; neither ever consults the argument vector.

| Site | Change | What breaks without it |
|---|---|---|
| `parser.ax:1620-1628` `typeKeywordCanon` | add `Foreign` | AX3002 on every signature naming it (`typecheck.ax:2415-2427` `tyConKnown` consults only `typeKeywordCanon`, `"Linear"`, datas, structs, aliases) |
| `typecheck.ax:7094-7096` `tyIsReprScalar` | add `Foreign` | a §6 **wrapper** declaring a bare `Foreign` return over an `Int` body goes unreported. (This no longer delivers MM-FFI-5(1) — `tyCompat` does that, at boundaries — and it is inert for the parameterised form, since `tyReprClash` skips anything applied.) |
| `typecheck.ax:542-557` `evScalarName` | add `Foreign` | a tyvar instantiated at `Foreign` is classified by `evDataTyKnown` (`:606-612`); a name that is *also* a data or struct name would stamp bit 1 and `axiom_release` would dereference a foreign pointer |
| `codegen.ax:6133-6148` `scalarTyName` | add `Foreign` | `fldClass` answers 1 for a `Foreign` field → the entire enclosing record becomes a LEAF → every sibling `String` field leaks |
| `codegen.ax:6159-6178` `fldClass` | (covered by the above) | — |

`typecheck.ax:539-541` states outright that `evScalarName` and `scalarTyName` "must agree, and the evidence fixture is what notices a drift." Adding the name to one and not the other is a wrong-free generator.

**Ownership.** A `Foreign` word is **always owned by Rust.** Axiom never frees it, never counts it, never scrubs it — MM-FFI-3 (`memory-model.md:2354-2362`). This statement is now true without exception, because arena-backed borrows no longer travel as `Foreign`. C8's registered destructor is an ordinary extern the Axiom side calls; there is no implicit drop, because there is no ARC hook for a scalar.

**No arena primitive applies [B][C].** `__axiom_arena_reset_keeping` on a `Foreign` is explicitly undefined (MM-FFI-3, `:2358-2362`). The bindgen refuses a `Foreign` argument to any of the three arena primitives; the compiler check is now a real one — those primitives declare `Int` parameters, and `tyCompat` reports a `(Foreign T)` argument against `Int` on the name.

**Known gap, stated plainly.** `(cast Int f)` erases the type and there is no check on `cast` anywhere. After the cast the word is an `Int` and `memGetWord`/`memSetWord`/the arena primitives all accept it. `Str.strLen` itself is written as `(memGetWord (cast Int s) 0)` (`stdlib/Str.ax:126`), so the idiom is endemic and cannot be banned. **The `Foreign`/`Int` distinction holds at signature boundaries and nowhere else.** A `type FileHandle = Foreign` alias buys nothing at check time either, because `tyExpandSigAliases` rewrites it back to `Foreign` before any check runs (`typecheck.ax:2628-2639`) — which is exactly why the phantom argument is a `data` declaration and not a `type` alias.

---

### 4. `String` — the long case

#### 4.1 What an Axiom `String` actually is

Two shapes, one address convention.

**Heap.** `strWrapOwned` (`stdlib/Str.ax:69-83`) allocates a three-word header with `memAllocMapped 24 4`:

| word | contents |
|---|---|
| 0 | `len` — byte count, **not** counting the NUL |
| 1 | `bytes` — address of the byte storage (may be **interior** to a parent buffer) |
| 2 | `owner` — handle of the block owning those bytes, or 0 |

The value of type `String` is the address of word 0. Behind it, at `handle-16` and `handle-8`, sit the allocator's count and shape words (`codegen.ax` `wiped:` block, `:2243-2252`). The `4` passed to `memAllocMapped` sets reference-map bit 2, so word 2 — and only word 2 — is followed by `axiom_release` (`stdlib/Mem.ax:74-87`; the walk is `codegen.ax:2333-2350`). Word 1 is deliberately unmapped because a slice's byte pointer is interior (`Str.ax:61-67`).

**Static literal.** `emitStringGlobals` (`codegen.ax:991-1031`) emits two private globals: a hex-escaped `[n x i8]` with an explicit `\00`, and

```llvm
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 }
            { i64 -1, i64 0, i64 5, ptr @str_0, i64 0 }, align 16
```

The value is `ptrtoint` of **element 2** (`codegen.ax:7238` emits exactly `getelementptr inbounds ({ i64, i64, i64, ptr, i64 }, ptr @strhdr_N, i64 0, i32 2)`), so `handle-16` is the count `-1` and `handle-8` is the shape `0`. `-1` is the **static sentinel**: `axiom_retain` and `axiom_release` both load it and return without writing (`codegen.ax:2280-2286`, `2300-2306`).

**Consequence for Rust:** the reader code is *identical* for both shapes. `len` at `+0`, `bytes` at `+8`, `owner` at `+16`. Nothing needs to know whether a `String` is static.

#### 4.2 Axiom `String` → Rust, borrowed (rows 9-11)

Zero-copy. The shim receives the header address and reads two words:

```rust
/// SAFETY: `h` is a live Axiom `String` handle; the borrow may not
/// outlive this call (C7).
#[inline]
unsafe fn ax_str_bytes<'a>(h: i64) -> &'a [u8] {
    unsafe {
        let p = h as *const i64;
        let len = *p as usize;
        let data = *p.add(1) as *const u8;
        core::slice::from_raw_parts(data, len)
    }
}
```

(The inner `unsafe { }` is required, not decorative: `unsafe_op_in_unsafe_fn` is warn-by-default from edition 2024 and this workspace denies it. See §9.)

Owner: the Axiom arena. **The borrow's lifetime is the call and nothing longer.** Retaining it past the call requires `axiom_retain(h)` **and** `axiom_retain(owner)` — the header's map releases the owner, but Rust holding only the `&[u8]` holds neither — and a matching `axiom_release` pair (C7).

**Do not call `axiom_release` on a handle you did not `axiom_retain`.** The counting rules make this asymmetric and dangerous: `strWrapOwned` births the header at count **0** (raw `__alloc`/`strWrap` stay birth-0 by design; `codegen.ax:6250-6255` reserves birth-1 for compiler-emitted constructor sites). `axiom_release` at count 0 is a no-op (`codegen.ax:2308-2312`, "0 - 1 IS the statics sentinel, so an unbalanced release must not be able to forge one"), but at count 1 it decrements to 0 and **files the block into a size-class freelist** (`codegen.ax:2354-2368`), after which the next `axiom_alloc` of that class hands the same bytes out scrubbed. A bare release from Rust on a value the Axiom side is still holding at count 1 is a use-after-free that reads as zeros.

#### 4.3 UTF-8 validity — who validates, and what happens

**Axiom `Str` is bytes and is not validated anywhere.** `stdlib/Str.ax:1-19` is explicit that it stays bytes; `strLen` is a byte count, `strSlice` cuts at byte offsets, `strAlloc` hands back zeroed bytes with no content constraint, and `strWrap` accepts anything a syscall wrote. `Utf8.utf8DecodeAt` (`stdlib/Utf8.ax:91`) decodes **leniently by policy** — `Utf8.ax:30-37`: "MALFORMED INPUT is decoded leniently rather than refused… A byte that begins no valid sequence decodes as itself and advances by one." The only *question* is `utf8Valid` (`stdlib/Utf8.ax:270`), which is an O(n) scan a program must choose to run.

**Decision: the Rust side validates, at the boundary, and the binding declares the policy.** Three modes, chosen per binding [B]:

| Mode | Rust view | Behaviour on invalid bytes |
|---|---|---|
| `bytes` (default) | `&[u8]` | nothing to validate; the shim never assumes UTF-8 |
| `utf8_strict` | `&str` | `core::str::from_utf8` → on `Err`, take the declared failure path (§6.2), or abort if the binding declared none **[T]** |
| `utf8_lossy` | `&str` | requires `alloc`; copies with U+FFFD substitution |

`core::str::from_utf8_unchecked` is **forbidden [P]** — the proc-macro refuses a shim body containing it in a boundary position — because an invalid `&str` is instant UB and Axiom is a plausible source of one (every `strSlice` can bisect a sequence; `Str.ax:205-215`).

Cost, stated honestly: `utf8_strict` is O(n) *per call*, on top of Axiom having already paid nothing for validity. A hot loop passing a large `String` to a `&str` shim per iteration will be dominated by validation. `bytes` is the default for exactly this reason.

**Rust→Axiom needs no validation.** Rust's `&str` is valid UTF-8 by construction, and Axiom accepts any bytes.

#### 4.4 NUL termination — `&str` or `CStr`?

MM-VAL-7 (`memory-model.md:545`) and MM-FFI-4 (`:2363-2368`) make termination a **program obligation, not a compiler guarantee**: "A program that builds a `Str` by any route other than the `Str` module … MUST maintain that terminator." And the `Str` module itself breaks it on purpose — `strSlice` (`stdlib/Str.ax:205-215`): "A slice is *not* NUL-terminated unless it happens to end where `s` does, so `strCStr` must not be called on one."

So: **`&CStr` is the wrong default view.** `CStr::from_ptr` scans to the first NUL; on a slice that means reading past `len` into the parent's bytes — in bounds, but the wrong string — or past the parent entirely for a `strWrap` over kernel memory.

**Decision: `&[u8]`/`&str` (pointer + length) is the canonical view. `&CStr` is available only behind an O(1) probe.**

The probe is sound and cheap. For any `Str` built by the `Str` module the byte at `data[len]` is readable: `strAlloc` reserves `len+1` and the allocator zeroes (`stdlib/Str.ax:89-97`; MM-ALLOC-6, and the allocator's `wipe` loop at `codegen.ax:2225-2240` is what makes the promise hold after a reset — the comment records `cstrLen` measuring 17 on a 3-byte string when it did not); a slice's `data+len` is an interior byte of a parent that its `owner` share keeps alive; a literal's terminator is the explicit `\00` in `@str_N`.

```rust
/// O(1). Returns None when the Str is not NUL-terminated at `len`
/// (the `strSlice` case). Never scans.
#[inline]
unsafe fn ax_str_cstr<'a>(h: i64) -> Option<&'a core::ffi::CStr> {
    unsafe {
        let p = h as *const i64;
        let len = *p as usize;
        let data = *p.add(1) as *const u8;
        if *data.add(len) != 0 { return None; }              // [T]
        Some(core::ffi::CStr::from_bytes_with_nul_unchecked(
            core::slice::from_raw_parts(data, len + 1)))
    }
}
```

**Edge case that bites:** an Axiom `Str` may contain an **interior** NUL — `Str.ax:12-16` says carrying the length "makes a `Str` able to contain a NUL", and `codegen.ax`'s emitted `strEq` helper compares over `len` rather than stopping at a NUL. So a `Str` can pass the terminator probe and still truncate when a C API reads it. `CStr::from_bytes_with_nul` (the *checked* form) rejects interior NULs and is what a strict binding should use, at O(n). A binding that wants O(1) and correctness must use `&[u8]` and pass a length.

#### 4.5 Rust → Axiom `String` (row 12): how it is allocated

MM-FFI-3 is the constraint: memory that did not come from `axiom_alloc` is outside the arena — not scrubbed, not reclaimed, not counted (`memory-model.md:2354-2357`). A `String` handed to Axiom must therefore be a real arena `Str`, with the right header, the right shape bits, and a NUL.

Three ways to get one:

**(a) Rust builds the whole thing.** Two `axiom_alloc` calls, write three header words, OR reference-map bit 2 into the shape word at `h-8`, `axiom_retain` the byte block, write the NUL. Rejected as the default: it pins MM-VAL-7's layout, the `memAllocMapped` clamp arithmetic (`stdlib/Mem.ax:75-87`), and the birth-count convention into a second codebase in a second language, where the "must agree" comment can't reach it.

**(b) Rust returns `(ptr, len)` of Rust-owned memory; Axiom copies.** Needs two words out of one, so it needs §6's out-cell, plus a destructor call for the Rust buffer. Correct, but it makes every string return a fallible-shaped call.

**(c) The emitted runtime gains a string constructor. — CHOSEN.**

```
axiom_str_new(bytes: i64, len: i64) -> i64
```

emitted into the preamble beside `axiom_alloc`/`axiom_retain`/`axiom_release`, with external linkage, doing exactly what `strAlloc` + `memCopy` do (`stdlib/Str.ax:89-97`, `237-243`): allocate `len+1` zeroed bytes, copy `len` in, `axiom_retain` the buffer, allocate the 24-byte header via the `memAllocMapped 24 4` path so the owner bit is set, store `{len, bytes, bytes}`. The NUL is free — the allocator zeroes and the last byte is never written.

Why (c): MM-VAL-7 stays in one codebase, the copy is unavoidable anyway (Rust's bytes are not arena bytes), and Rust never learns the header. Cost: two new emitted symbols and roughly forty lines of IR. **This is the same argument §7 uses to reject a Rust-built closure record, and the same one that makes `axiom_vec_from_words` (§5.3) and `axiom_closure_new` (§7) runtime helpers rather than Rust functions.** Every place the header layout or the birth-count convention would have to be restated in Rust, it becomes an emitted symbol instead.

**Crucially, `axiom_str_new` and its siblings are emitted ONLY when the module declares an extern or an export.** The owner's constraint — "a program using no FFI must be byte-identical to today" — is a hard gate, and the preamble is where it would first be violated.

```rust
extern "C" { fn axiom_str_new(bytes: i64, len: i64) -> i64; }

#[unsafe(no_mangle)]
pub extern "C" fn ax_rust_upper(s: i64) -> i64 {
    let src = unsafe { ax_str_bytes(s) };          // borrow, no retain
    let mut buf = [0u8; 256];
    let n = src.len().min(buf.len());
    for i in 0..n { buf[i] = src[i].to_ascii_uppercase(); }
    unsafe { axiom_str_new(buf.as_ptr() as i64, n as i64) }
}
```

Owner of the result: the Axiom arena. Rust's `buf` is irrelevant after the call. The returned header is birth-0, matching every other `Str` the `Str` module produces, so the Axiom side's existing ARC events treat it identically to a `strDup` result.

**Edge case that bites:** `axiom_alloc(0)` returns the unadvanced bump pointer with **no header written** (`codegen.ax:2051-2057`, MM-ALLOC-8b: "a 0-byte block is not a counted block"). `axiom_str_new` with `len == 0` must still allocate 1 byte for the terminator, or the returned `Str` points at a headerless address that `axiom_release` will read a count word in front of. The runtime helper must special-case it; a Rust-side (a)-style constructor almost certainly would not have.

---

### 5. Composites

#### 5.1 Structs (rows 16-17)

MM-VAL-10 (`memory-model.md:677-680`): a `struct` is a heap block of `fields * 8` bytes, field *i* at word *i*, no tag. In front of it sits the 16-byte count/shape header, and the shape word carries the per-field reference bitmap computed from **declared field types** by `ctorShapeConst` (`codegen.ax:6208-6224`) via `fldClass` (`:6159-6178`).

There is no `#[repr(C)]` Rust struct that mirrors this. The header is not part of the value, the fields are all `i64` regardless of declared type, and a `String` field is an address whose block the release path will follow.

**Decision: two mappings, both explicit, no implicit third.**

**(16) Explode.** A struct of N scalar fields crosses as N separate `i64` parameters, in declaration order. Bindgen generates the Axiom-side wrapper that projects the fields and the Rust-side shim taking N arguments. Zero-copy, no ownership transfer. Refused **[B]** when any field is itself a struct, a `data`, or a `String` — because exploding a `String` field means deciding its lifetime, which is §4's problem and must be stated, not inferred.

**(17) Opaque handle.** The struct crosses as an **`Int` handle wrapped in a Rust newtype**, with generated getter/setter externs. **Not as `Foreign`** — a struct block came from `axiom_alloc` and is arena memory, and §3 reserves `Foreign` for memory that did not. (Row 17 of the master table now says this; an earlier draft's table said `Foreign` and this paragraph contradicted it two sections later, which is exactly the sort of disagreement an implementer codes from.) The Axiom side keeps ownership; Rust holds the address for the duration of the call only, or retains it (C7). Rust reads word *i* with a plain load; **writing** word *i* is where it bites — see below.

**Edge case that bites (both mappings):** a Rust shim that stores a handle into an Axiom block must take a share. Axiom's own `memSetWord` does this — `stdlib/Mem.ax:203-208` calls `__retainref` before the store, and its comment explains why: "`(cast Int value)` erases whatever `value` was… the store takes a SHARE of what it is about to hide." A raw store from Rust takes no share, and if the field's reference bit is set, the enclosing block's death releases a value nobody retained. **Rule [B][T]: a Rust shim writing into an Axiom block must `axiom_retain` the stored handle first, and must not release the overwritten one** (event 5's release/retain pairing is the Axiom side's job and doubling it double-frees).

**Capacity:** AX3029 caps a struct at 47 fields and a `data` constructor at 46 beside its tag (`typecheck.ax:1586-1610`; the bitmap is bits 16..62, bit 63 reserved so shape constants stay non-negative, `codegen.ax:6188-6196`). Bindgen refuses a wider explode **[B]** rather than letting the Axiom compiler refuse it later, so the error names the Rust type.

#### 5.2 `data` / enums (row 18) — refused as a wire type

Three facts make a direct mapping unsound.

1. **Tags are globally unique and order-dependent.** MM-VAL-8a (`memory-model.md:614-620`): "Tags are drawn from one global counter starting at 2, spanning the whole compilation unit including imported modules, whose constructors are numbered first. A type's tag values therefore depend on the import graph and on declaration order — which is … why **nothing may serialise a tag**." I4 (`:2388`) makes global uniqueness an invariant. Adding one `import` to an unrelated file renumbers every constructor.

2. **The representation itself can change.** MM-VAL-8b (`:621-628`): at 4096 tags a type falls back to representation 0 and its *nullary* constructors stop being immediates and become 8-byte heap blocks. "The same type, declared later in a larger program, has a different machine representation. Nothing in the language exposes which one is in force, and nothing may depend on it."

3. **A mixed-representation value is not a pointer.** MM-VAL-9 (`:629-638`): `icmp slt i64 %v, 4096` distinguishes an immediate tag from an address. A Rust shim receiving a `data` value and dereferencing it segfaults on every nullary constructor.

**Decision: a Rust `enum` never crosses as an Axiom `data` value. It crosses as a discriminant index in the *Rust crate's own* numbering, 0..n-1, declared once in the binding, plus its payload words; the Axiom-side generated wrapper does all `match`ing and all constructing.** No Axiom tag is ever read or written by Rust, so MM-VAL-8a's prohibition is honoured literally. This is also what keeps §3's phantom `(data File (MkFile))` declarations free: they consume tags, but no tag they consume is ever observable.

The alternative — bindgen bakes the real tags into the generated Rust, since bindgen runs inside the build and knows them — was seriously considered and **rejected**. Cargo compiles the Rust crate on its own schedule; the Axiom tags are a function of the Axiom import graph. Nothing in the two build systems forces them to agree, so a stale `libaxffi.a` links cleanly and dispatches to the wrong arm. Detecting it would need a build-id manifest and a startup check, which costs more than the wrapper.

**Edge case that bites:** `Result` is *not* built in. `stdlib/Err.ax:30-32` declares `(pub data Result (a e) (Ok a) (Err e))` as an ordinary declaration, for stated reasons (ERR-TYPE-2). Its tags therefore move with the import graph like any user type. `Option` *is* built in and is seeded first — `Some` is 0, `None` is 1, representation 2 (`codegen.ax:296-320`, probed against stage0; `typecheck.ax:1527-1538`) — so its tags happen to be stable. **Do not spend that.** A binding that hardcodes 0/1 for `Option` teaches the next reader that hardcoding tags is acceptable, and the next type they try it on is `Result`.

#### 5.3 `Vec` (rows 14-15)

`stdlib/Vec.ax:1-30`: a `Vec` is the address of a three-word header — `len`, `cap`, `data` — allocated with a plain `memAlloc 24` (`Vec.ax:62-70`), i.e. **LEAF shape, empty reference map**. Elements are machine words with no type: the module comment states the element type is `Int` on purpose, because "a parameter would buy type safety the caller does not get anyway once it puts a `Str` handle (also an `Int`) in."

**Axiom `Vec` → Rust (14):** zero-copy `&[i64]` over `data` (word 2) and `len` (word 0). The elements are raw words; Rust learns their meaning from the binding, not from Axiom.

```rust
unsafe fn ax_vec_words<'a>(v: i64) -> &'a [i64] {
    unsafe {
        let p = v as *const i64;
        core::slice::from_raw_parts(*p.add(2) as *const i64, *p as usize)
    }
}
```

**The borrow's lifetime is the call and nothing longer, exactly as for a borrowed `String` (§4.2). Any element handle Rust keeps past the call needs its own `axiom_retain`/`axiom_release` pair (C7).**

This rule is not a formality, and an earlier draft got it exactly backwards by claiming `Vec` elements are "immortal by construction" and that Rust reading handles out of a `Vec` "never races a free." Both claims are false, and the reason is the handle convention this branch is named for. `memSetWord`'s `__retainref` is **evidence-gated, not unconditional**: `emitPrimRetainRef` (`codegen.ax:5319-5345`) emits nothing at all when the call's stamp witness is 0 — "0 → `v` is not a reference here - NOTHING is emitted, which is why this is affordable on `memSetWord`". `Vec`'s element type is declared `Int` on purpose, `evClassOf` answers 0 for `Int` (`typecheck.ax:542-557`, `604-612`), so `(vecPush v x)` on an `Int`-typed handle emits **no retain**. The element is not immortal, and a Rust `&[i64]` over `Vec` data can hold a handle that Axiom frees and recycles during the call.

**What survives of the second edge case is a leak claim, not a liveness guarantee:** because the `Vec` header is a leaf, releasing a `Vec` releases nothing, so the header's death never reclaims its elements. That is a leak in the safe direction. It says nothing about whether some *other* owner can free an element, and something else usually can.

**Edge case that bites:** `vecPush` reallocates. `vecReserveExactly` (`Vec.ax:163-171`) allocates a fresh block, copies, and rewrites word 2 — and `vecPush` (`Vec.ax:185-192`) reads `vecData` *after* the reserve, with a comment explaining that reading it before "would write the element into the abandoned block, and the bug would be invisible until the vector happened to grow." A Rust slice held across a callback that pushes is dangling. **Rule [T]: the borrow may not outlive the call, and a shim that takes both a `Vec` borrow and a callback is refused [B].**

**Second edge case:** Rust *writing* a handle into a `Vec` must still `axiom_retain` it (§5.1), because Axiom's own `memSetWord` would have — when the evidence said to. Since the evidence for an `Int`-typed container says not to, Rust cannot infer the answer from the Axiom side's behaviour and must retain unconditionally or document that it does not.

**Rust `Vec<T>` → Axiom (15):** copies. `T` must itself be a row-1..7 primitive **[B]**; `Vec<MyStruct>` is refused. The shim hands `(ptr, len)` to a generated `axiom_vec_from_words(ptr, len)` runtime helper — same emitted-only-in-FFI-mode rule as `axiom_str_new`, same reason: the header shape stays in one codebase.

#### 5.4 Tuples and lists (rows 22-23) — not expressible

MM-VAL-13 (`memory-model.md:698-702`): "There are **no list or tuple values.** `[T]` and tuple types are type-level constructions only; `[` in expression position is `AX2001`." `tyCompat` has arms for `TAG_T_TUP` and `TAG_T_LIST` (`typecheck.ax:224-229`) and `fldClass` classifies a non-empty tuple as a reference (`codegen.ax:6166`), but nothing constructs one. A signature may name them; no value inhabits them. **Refused at binding-generation time [B]**, with the message pointing at a `struct` or a `Vec`.

---

### 6. Option-like and Result-like

One word out means one value out. Both of these need two.

#### 6.1 `Option<T>` (row 19)

**Decision: an out-cell allocated by the generated Axiom-side wrapper, crossing as an `Int` handle.** The cell comes from `memAlloc`, so it is arena memory and §3 forbids spelling it `Foreign`.

```scheme
;; hand-written by the author
(:: rustLookup (-> String (Option Int)))

;; generated: the extern, monomorphic, no tyvars (C3)
(extern "ax_rust_lookup"
  (:: ax_rust_lookup (-> String Int Int)))

;; generated: one TYPED ACCESSOR per payload type - see below, this is load-bearing
(:: cellInt (-> Int Int))
(fn (cellInt c) (memGetWord c 0))

;; generated: the Axiom-side wrapper
(fn (rustLookup key)
  (let ((cell (memAlloc 16)))
    (if (== (ax_rust_lookup key cell) 0)
        (None)
        (Some (cellInt cell)))))
```

Rust writes the payload into the cell and returns 0 for absent / 1 for present. No Axiom tag crosses. `(None)` allocates nothing (MM-ALLOC-10, `memory-model.md:965-968`) and is the immediate 1, which `axiom_retain`/`axiom_release` skip on the `< 4096` guard (`codegen.ax:2276-2280`, I3 at `:2387`).

**The typed accessor is what makes the reference bit correct, and neither a bare `memGetWord` nor a `cast` will do it.** This is subtle, it is the difference between a released `String` and a leaked one, and it was measured on this tree rather than reasoned about.

`ctorShapeEmit` (`codegen.ax:6384-6404`) derives a constructor's reference bits from the **evidence stamp** computed at the call site. For a constructor field that is a type variable — and `(Some a)`'s field is one — it reads the stamp entry: `wv == 1` sets a static bit, `wv >= 2` queues a run-time evidence read, and `wv == 0` does neither. The stamp entry comes from `evStampFill` → `evWalk` → `evWalkVar` (`typecheck.ax:668-745`), which meets in `evClassOf` of the argument's inferred type.

Two ways to get `wv == 0` by accident:

- `(Some (memGetWord cell 0))` — `memGetWord` is declared `(-> Int Int a)` (`stdlib/Mem.ax:174-176`), so the argument's type is a freshened tyvar, and `evClassOf` answers 0 for a non-source variable (`typecheck.ax:589-596`).
- `(Some (cast String (memGetWord cell 0)))` — **the cast does not help, it actively suppresses.** `evStampFill` detects a cast-rooted argument (`isCastLike`, `typecheck.ax:681-686`) and `evWalkVar` then meets in a hard `0` instead of `evClassOf`: `(if (== castArg 1) 0 (evClassOf tc at))`. The comment says why, and it is deliberate: *"An argument whose root is a `cast` classifies 0 outright — the cast launders a word past the checker, and evidence must not trust it."*

Measured with the committed compiler, reading the emitted shape word for `(Option String)`:

| wrapper body | shape word at `h-8` | retain emitted? |
|---|---|---|
| `(Some (memGetWord cell 0))` | `4` — payload count only, **no reference bit** | no |
| `(Some (cast String (memGetWord cell 0)))` | `4` — **still no reference bit** | no |
| `(Some (cellStr cell))` via `(:: cellStr (-> Int String))` | `131076` = `4 + 2^17` — **bit 17 set** | `call void @axiom_retain` |

`2^17` is exactly `(pow2 (+ 17 j))` at `j = 0`, the first payload field's map bit.

**Rule: the generated wrapper must route every out-cell payload through a per-binding accessor function whose DECLARED RETURN is the binding's Axiom type.** The `cast` lives inside that accessor, where it is a declared-return function body — the same shape `stdlib/Str.ax`'s `strWrapOwned` uses as "the one site in the tree entitled to say it" — and the constructor site then sees an ordinary call with a concrete `String` return type. The same rule applies to `(Ok …)` and `(Err …)` in §6.2.

With that in place, the guarantee this section wants to make is true of the code it prints: `(Some someString)` really does release the string at death, and `(Some someInt)` really does not. This is also precisely why C3 forbids tyvars in an extern signature: the bit is a *static claim of pointerhood*, and the three withdrawn inference attempts (commits `5f2a616`→`053c525`, `6ff9e2c`→`9d5b508`) were withdrawn because a wrong claim segfaults. Under-claiming leaks; over-claiming crashes; the accessor is how the generator claims exactly once, on purpose.

Alternatives considered: a sentinel return value (rejected — `Int` has no free bit pattern; every i64 is a legal `Int`), and a process-global result slot (rejected — MM-PAR-1 makes it *thread*-safe, since there are no threads and all allocator state is process-private, I11 at `memory-model.md:2395`, but it is not **reentrancy**-safe once a callback re-enters the same extern).

Cost: one 16-byte arena block per fallible call. Measurable, and the honest price of a one-word ABI.

#### 6.2 `Result<T, E>` (row 20)

Same cell, wider protocol. The extern returns `0` on success or a nonzero **error code**; the cell carries the payload on success and, on failure, a code and an Axiom `String` message built with `axiom_str_new`.

```scheme
(:: rustParse (-> String (Result Int Error)))

(extern "ax_rust_parse"
  (:: ax_rust_parse (-> String Int Int)))

;; generated typed accessors (§6.1): the cast lives HERE, not at the constructor
(:: cellInt (-> Int Int))
(fn (cellInt c) (memGetWord c 0))
(:: cellMsg (-> Int String))
(fn (cellMsg c) (cast String (memGetWord c 1)))

(fn (rustParse text)
  (let ((cell (memAlloc 16)))
    (let ((rc (ax_rust_parse text cell)))
      (if (== rc 0)
          (Ok (cellInt cell))
          (Err (mkError rc (cellMsg cell)))))))
```

**`mkError` takes exactly two arguments.** `stdlib/Err.ax:52-54` is `(pub :: mkError (-> Int String Error))` / `(pub fn (mkError code message) (Error code message ""))` — it supplies the empty `context` itself. An earlier draft passed three and would not have compiled. A wrapper that wants to carry real context must construct the struct directly: `(Error rc msg ctx)`, where `Error` is `(pub struct Error (code : Int) (message : String) (context : String))` at `Err.ax:43-46`.

`Err.ax:16-18` records why the declared types matter: "the reference map is built from declared types, so a `String` behind an `Int` field is invisible to release and leaks." The generated wrapper must build a real `Error`, not stash a raw address in an `Int` field — and `Error` being a struct is enough for `(Err …)` to get its own bit, since `evDataTyKnown` (`typecheck.ax:606-612`) searches structs after datas and answers 1 for either.

C6 lives here too: a Rust `panic` crossing this boundary is UB. Either `panic = "abort"` in the profile, or every shim body is wrapped in `catch_unwind` and a caught panic becomes a reserved error code. **[B]** verifies the workspace profile actually sets `panic = "abort"` when the `catch_unwind` form is not used; **[G]** verifies no `_Unwind_*` symbol reached the link (experiment 2 measured 188 undefined symbols including `_Unwind_*` from a std staticlib — that configuration must fail the gate, not merely warn).

---

### 7. Functions and closures (row 21)

**A callback can cross, in both directions, and the mechanism already exists.**

`applyOneArg` (`codegen.ax:5213-5236`) is Axiom's entire indirect-call convention:

```llvm
%c  = load i64, ptr %recp        ; word 0 of the closure record
%f0 = inttoptr i64 %c to ptr
%r  = call i64 %f0(i64 %rec, i64 %a)
```

That is *byte for byte* `extern "C" fn(i64, i64) -> i64`. MM-VAL-14 (`memory-model.md:712-716`) gives the record: word 0 the code pointer, words 1.. the captures. MM-VAL-17a (`:745-750`): a lifted lambda is `@_lam_N(i64 %_env, i64 %p)` — environment first, **exactly one** user parameter.

A closure record is arena memory, so it crosses as an **`Int` handle**, not as `Foreign` (§3).

**Rust → Axiom callback.** Build a two-word block, put the Rust `extern "C" fn(i64, i64) -> i64` in word 0 and a Rust context word in word 1, and hand the block's address to Axiom as an ordinary function value. Axiom calls it through `applyOneArg` with no new primitive, no `declare`, and no new symbol — the call is indirect, so `nm -u` stays empty and the freestanding gate is untouched. The env word Axiom passes is the record itself, so Rust reads its context at `env + 8`.

```rust
#[unsafe(no_mangle)]
pub extern "C" fn ax_rust_cb(env: i64, arg: i64) -> i64 {
    let ctx = unsafe { *((env + 8) as *const i64) };
    arg.wrapping_add(ctx)
}
```

**The record must be birthed at count 1, and `axiom_alloc` does not do that.** This is a use-after-free if it is skipped, and it is easy to skip because the block looks inert. `axiom_alloc`'s `wiped:` block stores `i64 0` into the count word (`codegen.ax:2242-2244`), while every Axiom-built closure record is stamped **1** by `storeCountOneAt` (`codegen.ax:6251-6255`) — "a compiler-emitted OWNERSHIP-CREATING site births its block at count 1 … Raw `__alloc`/`memAlloc` and `strWrap` stay birth-0". Lambda emission does `(storeCountOneAt cg pr)` at `codegen.ax:3793` before retaining captures at `:3812`.

The birth count is what stops an ordinary retain/release pair from reaching zero. A closure-typed value is a **reference** — `evClassOf` gives `TAG_T_ARR` class 1 (`typecheck.ax:597-598`) — so an Axiom function that captures a Rust-supplied callback parameter inside a lambda takes a share (0→1) and the boundary release hands it back (1→0), at which point `axiom_release` files the 16-byte block into size class 1 (`codegen.ax:2354-2368` files any block with `0 < bcnt <= 8192`; a 16-byte block has `bcnt` 2). The next `axiom_alloc` of that class hands the same bytes out scrubbed, while Rust still holds the pointer and Axiom may still call through word 0.

**Decision: emit an `axiom_closure_new(code, ctx) -> i64` runtime helper**, under the same FFI-mode-only rule as `axiom_str_new` (§4.5) and `axiom_vec_from_words` (§5.3). It does `axiom_alloc(16)`, stores the two words, and stamps the count at 1 exactly as `storeCountOneAt` does. The argument is verbatim §4.5's: the birth-count convention is a compiler invariant with a comment attached, and restating it in Rust puts it somewhere that comment cannot reach. A Rust-side `axiom_retain` immediately after `axiom_alloc(16)` is the minimum acceptable fallback and must be documented as load-bearing if it is used.

Note that `axiom_alloc` stamps the block a **leaf** (`codegen.ax:2243-2250`: "the allocator leaves EMPTY, because it cannot know a field from an int"), which is correct here — neither word is an Axiom reference — and matches Axiom's own records, which carry no map either.

**Axiom → Rust callback.** Rust receives the closure-record address as an `Int` handle and calls word 0 the same way. It must not assume the code pointer is a plain function: MM-VAL-17 (`:731-735`) says a record built from a *bare top-level function* points at a forwarding thunk `_thunk_N`, which is fine and transparent — but it means Rust must always pass the record as the first argument, never omit it.

**Arity is capped at 1 [P][B].** MM-VAL-17a and MM-VAL-18 (`:748-753`): "A multi-parameter lambda is curried into a chain of one-parameter lambdas, **each allocating its own record**", and a call applies one argument per step, treating each result as the next record. A two-argument Rust callback would have to *allocate and return an intermediate Axiom closure record* from inside Rust, which means Rust building an Axiom heap object with a code pointer in it — precisely the layout-in-two-codebases problem §4.5 and this section's own helper decision both reject. **Arity > 1 crosses as arity 1 over a `struct`/`Vec`, or not at all.**

**Ownership.** An Axiom closure record **carries no reference map** — `codegen.ax:3796-3806` states it outright: "The share is unbalanced - a closure record still carries no map - so it leaks, which is the safe direction." So an Axiom closure held by Rust across calls never has its captures freed underneath it by the record's own death. That is a leak, and it is the correct trade here; it also means Rust does not need to retain the captures individually. It does **not** exempt Rust from the birth-count rule above, which is about the record block itself, not its captures.

**What is NOT expressible:**
- A Rust closure that captures by value and is `FnMut`. Only a bare `extern "C" fn` plus an explicit context word. `Box<dyn Fn>` is refused **[P]**; the workaround is a `(Foreign Ctx)` context handle plus a destructor extern (C8).
- An Axiom effect operation as a callback. Effects install evidence in a dynamic-extent record (`memory-model.md:700-704`) saved and restored around a `handle` body; a callback invoked from Rust *inside* that extent is fine, but one stored by Rust and invoked after the `handle` returns reads a popped evidence record. **Refused [B]:** the bindgen rejects a callback whose Axiom-side function has any inferred effect other than the FFI effect itself, which it can ask because effects are already inferred by a monotone fixpoint over the whole merged declaration list before any body is checked (`typecheck.ax:5199-5241`).
- Re-entrancy from Rust into Axiom while Axiom is mid-allocation. There is no reentrancy guard on `axiom_alloc`; MM-PAR-1 makes the process single-threaded so this can only happen through a callback, and a callback that allocates during a shim that is itself between `axiom_alloc` and its header store is a real hazard. **Stated as a program obligation**, not a checked rule; see §10.

---

### 8. What is refused at binding-generation time

Each refusal, with the check that implements it. All are **[B]** unless marked.

1. **Any type variable anywhere in an extern signature.** C3. The check is `cgTakesEvidence`'s walk (`codegen.ax:440-455`, `cgParamPosVars`/`cgSigVarsInto`) run over the extern's `TAG_D_SIG` type — but extended to *return* positions too, which `cgTakesEvidence` deliberately exempts (`:452-458`: "a signature whose every variable is return-only takes no word"). The exemption is right for Axiom-internal functions and wrong here: a return-position tyvar means the caller stamps pointerhood it cannot know, and the bindgen has real Rust types and no reason to allow it. Also **[C]**, because a polymorphic extern would grow the hidden trailing `i64 %__evw.h` (`codegen.ax:3008-3021`, passed at `:5921-5926`) and that word must never reach Rust.
2. **Any non-`i64` return type on a Rust shim** — `i8`/`i16`/`i32`/`u8`/`u16`/`u32`/`bool`/`char`/`f32`/`f64`/`()`. **[P]**, at the proc-macro, where the Rust signature is in hand. §2.1, measured: a `-> i32` shim writes only `w0` and Axiom reads `x0`, printing 4294967293 for -3. This is the refusal most likely to save an afternoon, and it is cheap because the fix is always the same — widen in the body.
3. **`data` types as wire types.** §5.2.
4. **Tuple types and `[T]`.** §5.4, MM-VAL-13.
5. **`*T` / `*mut T`.** MM-VAL-21 declares the form unusable and unspellable in a signature.
6. **`f32`, `F32`, `F64`, `I8`..`U64` in an Axiom signature.** Not surface types; `typeKeywordCanon` does not know them and AX3002 follows.
7. **A struct explode wider than 47 fields, or a `data` constructor wider than 46.** AX3029's cliff (`typecheck.ax:1586-1610`), refused earlier so the message names the Rust type.
8. **`Vec<T>` where `T` is not a primitive.**
9. **A callback of arity ≠ 1**, or one whose Axiom function has a non-FFI inferred effect.
10. **`Box<dyn Fn…>`, `&mut` aliasing an Axiom block held elsewhere, any Rust type with `align > 16`** (the arena guarantees 16-byte alignment, I5 at `memory-model.md:2389`, and nothing more).
11. **Reserved runtime names, as extern names AND as definitions — a larger set than AX3026's, and `main` is not in AX3026's set at all.** Correcting an earlier draft: `checkReservedNames` (`typecheck.ax:996-1021`) tests exactly `"axiom_alloc"`, `"axiom_retain"`, `"axiom_release"`, and only for `TAG_D_FN`. A user `main` is perfectly legal and is *renamed* to `__axiom_user_main` (`codegen.ax:2980-2982`, `declSpellingOf` at `:1042-1043`), so AX3026 has nothing to say about it. The FFI needs a wider set for a new reason:
    - `axiom_alloc`, `axiom_retain`, `axiom_release` — already refused as definitions; must now also be refused as extern **names**.
    - `axiom_str_new` (§4.5), `axiom_vec_from_words` (§5.3), `axiom_closure_new` (§7) — **new**, and they get external linkage in FFI mode. A program that defines or externs one passes `check` and dies in `opt` as a duplicate symbol, which is verbatim the failure AX3026's own note says it exists to prevent: "the build died in `opt` as a duplicate symbol after `check` said OK."
    - `main` and `__axiom_user_main` — **new hazards of a different kind.** An extern named `main` collides with the emitted `@main` entry point (`codegen.ax:1994-2001`), not with a user definition, so AX3026's existing logic would not have caught it even if `main` were in its set.

    `checkReservedNames` must be extended to all of these when FFI mode is on, and taught to test the extern tag as well as `TAG_D_FN`.
12. **An extern name that is not entirely `[-A-Za-z0-9$._]`** unless the binding accepts `llvmSym`'s quoting (`codegen.ax:982-988`). Rust `#[unsafe(no_mangle)]` names are a subset of this, so the check is cheap insurance against a `#[link_name]` with something exotic in it.
13. **A Rust signature declaring `f64`/`f32` parameters directly** (rather than `i64` bit patterns). §2.2 — the ABI-register mismatch, and the parameter-side twin of refusal 2.

**Note on what has a compiler backstop and what does not.** Refusals 1, 7 and 11 have one. Refusals about *arity* only have one if §2.2's second compiler change lands: `repArity` (`typecheck.ax:2728-2733`) answers -1 for a definer it does not know, and a -1 answer silently disables the AX3013 bare-value refusal and the AX3009/AX3013 saturation check. Register the extern's `FnEnt` with a real `paramCount` and those checks work on externs for free; leave it at -1, as the retired `foreign` did, and every arity rule in this section is [B]-only.

---

### 9. Rust edition and the shape of the workspace

**Decision: the `rust/` workspace pins `edition = "2024"`, and every snippet in this section is written for it.**

This is not cosmetic. Measured with the project's toolchain (rustc 1.97.1), compiling the earlier draft's snippets verbatim under `--edition 2024`:

```
error: unsafe attribute used without unsafe
 --> #[no_mangle]
  |   ^^^^^^^^^ usage of unsafe attribute
help: wrap the attribute in `unsafe(...)`
  |   #[unsafe(no_mangle)]
```

`cargo new` produces an edition-2024 crate, so the default path is the failing one. Two consequences run through every example above:

1. **`#[no_mangle]` is written `#[unsafe(no_mangle)]`.** This includes **C1 of the ABI contract**, which spells it the old way; C1's wording needs the same edit, since it is the sentence implementers will copy.
2. **A raw-pointer dereference inside an `unsafe fn` needs its own `unsafe { }` block.** `unsafe_op_in_unsafe_fn` is warn-by-default in edition 2024 and this workspace denies it, so `ax_str_bytes`, `ax_str_cstr` and `ax_vec_words` all carry an inner block. This is a readability gain as well as a lint fix: it marks which operations are the unchecked ones.

Pinning `edition = "2021"` instead is a supportable choice and would let the older spelling stand, but it was rejected: the workspace is new, has no legacy to preserve, and 2024's stricter `unsafe` discipline is worth more at an FFI boundary than anywhere else in a Rust program.

---

### 10. Known gaps, stated plainly

- **`cast` defeats the `Foreign`/`Int` distinction completely.** There is no check on `cast` and the stdlib's own idiom depends on there being none (`stdlib/Str.ax:126`). MM-FFI-5(1) is delivered *at signature boundaries only*. I do not have a proposal that keeps `Str.strLen` compiling.
- **`cast` also suppresses ARC evidence, which is the same mechanism pointing the other way.** `evStampFill` classifies a cast-rooted argument as 0 outright (`typecheck.ax:681-686`), deliberately. That is why §6's wrappers need typed accessor functions rather than inline casts, and it means any hand-written wrapper that inlines a cast at a constructor site silently leaks its payload. Bindgen generates the accessors; a human writing a wrapper by hand has no diagnostic warning them. **A lint for `(Ctor (cast T …))` at a constructor position with a type-variable field would catch it and does not exist.**
- **`type` aliases over `Foreign` buy nothing.** `tyExpandSigAliases` (`typecheck.ax:2628-2639`) rewrites them away before any check. Per-handle distinctness comes from parameterising `Foreign` (§3), not from aliasing it.
- **Per-handle distinctness costs a declared phantom type per handle.** `tyUnknownCon` reports an unknown argument, so `(Foreign File)` requires a real `File` declaration (`(data File (MkFile))`, verified). Bindgen emits these, but they consume global tags and appear in the user's namespace, and there is no way to declare a type that exists only as a phantom.
- **The Rust global allocator over `axiom_alloc` is attractive and partly broken.** Implementing `GlobalAlloc::alloc` as `axiom_alloc` + `axiom_retain` (0→1) and `dealloc` as `axiom_release` (1→0, which files the block into its size class, `codegen.ax:2354-2368`) gives real reuse and puts Rust's `alloc` types inside the arena, satisfying MM-FFI-3. But `axiom_release` only files blocks whose padded word count is in `1..=8192` (`:2354-2358`) — above 64 KiB it is skipped rather than misfiled, so large Rust buffers leak; `realloc` must copy because the allocator has none; alignment above 16 must return null; and `alloc(0)` must be special-cased against MM-ALLOC-8b's headerless block. This is a real design and it has four sharp edges. It is not v0.
- **Callback reentrancy into `axiom_alloc` is unguarded.** MM-PAR-1 removes the concurrency case, so this only arises when a Rust shim invokes an Axiom callback that allocates. Nothing detects it. Recorded as a program obligation.
- **There is no cheap, total answer to "is this `Str` NUL-terminated?"** The O(1) probe in §4.4 is sound for every `Str` the `Str` module produces, and MM-FFI-4 makes any other route a program obligation — so a hand-built `Str` from `__store8` into a raw buffer can make the probe read one byte past a mapping. I know of no fix that does not add a word to the header.
- **Tag/representation drift between the cargo build and the Axiom build is designed around, not solved.** §5.2 keeps tags off the wire entirely, which removes the hazard for enums. It does *not* remove it for a struct **explode** (row 16), whose field count and order are baked into the Rust shim's arity. A build-id manifest emitted by bindgen and diffed by the gate **[G]** is the mitigation; it is not written yet.
- **`Char`↔`char` and `String`↔`&str` index in different spaces.** §2.4. Bindgen can warn when a binding uses both, but it cannot tell a correct use from an incorrect one.
- **Nothing checks that a Rust shim's declared return type is `i64` except the proc-macro.** A hand-written `extern "C"` shim that bypasses `#[axiom_extern]` gets no diagnostic from either side, and the failure mode is a silently wrong high half (§2.1). The [G] allowlist gate sees the symbol but not its signature. A `nm`-plus-DWARF check could close this and is not written.
---

## 6. User-Facing API and Surface Syntax

### 1. The Axiom keyword

**Decision: `extern`.** The block form is

```scheme
(extern "axiom_sha2"
  (opaque Sha256 (drop sha256Free))
  (sha256New       :: Sha256                     (symbol "ax_sha2_new"))
  (sha256UpdateRaw :: (-> Sha256 Int Int Int)    (symbol "ax_sha2_update"))
  (sha256Finish    :: (-> Sha256 Slice)          (symbol "ax_sha2_finish"))
  (sha256Free      :: (-> Sha256 Int)            (symbol "ax_sha2_free")))

```

`foreign` is unavailable and must stay unavailable: it is one of three arms in `parseTopForm` that route to `pErrRemoved` ahead of the `TAG_D_MACROCALL` fallthrough (`self_host/parser.ax:1096-1103`), carrying hand-written migration prose in `removedRationale`/`removedHelp` (`self_host/parser.ax:582-604`) that `docs/reference.md:269-280` and the `foreign`-is-AX2004 negative probe at the end of `scripts/check-freestanding.sh` both pin. Reviving it would delete the message that tells a 2024-vintage source file what happened to it.

**But that prose becomes false the day `extern` ships, and retargeting it is part of this work, not a follow-up.** `removedRationale` currently says "`foreign` was removed: C interoperability is no longer a goal, and generated code links no C library to call into" (`self_host/parser.ax:584-586`) and `removedHelp` says "use the standard library, which reaches the kernel through `__syscall0`-`__syscall6` rather than through libc" (`self_host/parser.ax:595-597`); `docs/reference.md:275` repeats the second as `| foreign | Use the standard library; generated code links no C |`. After this section lands, all three misdirect exactly the reader they exist to serve. The probe can stay — `foreign` is still `AX2004` — but the strings behind it must be rewritten to point at `extern`, and they are on §10's same-commit list.

Candidates considered and rejected:

| Candidate | Rejected because |
|---|---|
| `link` | Names the *link step*, not the *language boundary*; and the boundary is what the checker enforces. Also collides conceptually with the archive-path resolution, which is a driver concern, not a declaration. |
| `native` | Suggests "compiled" as against "interpreted", which is already false of all Axiom (`self_host/driver.ax:205-235` is AOT `llc`+`cc`). |
| `ffi` | An initialism; nothing else in the grammar is one. |
| `bridge` | Accurate for the Rust crate but wrong for the declaration — the declaration names symbols, and a symbol is not a bridge. |
| `import` (overloaded, `(import Rust "crate" (names))`) | `parseImportDecl` (`self_host/parser.ax:1887-1910`) maps a dotted path to a file relative to the entry file; overloading it would make `AX5001` mean two different failures. |

`extern` is free in this tree: `grep -rn extern --include='*.ax' .` hits only two prose strings in `explain.ax` (the AX4003 text) and no identifier, and `fpIsReservedWord` (`self_host/format.ax:1292+`) does not list it. It is also the word every Rust programmer writing the other half of this already types.

The reverse direction takes a second keyword, `export` (§9). The two are deliberately not one form with a direction flag: `extern` names symbols the compiler must *declare*, `export` names Axiom functions the compiler must *define an alias for*, and those are different emitter arms with different failure modes.

**Cost, stated:** adding `extern` (and `export`) to `parseTopForm` removes them from the `TAG_D_MACROCALL` fallthrough (`self_host/parser.ax:1139-1149`), so a program that today defines a *declaration macro* named `extern` silently changes meaning. No such macro exists in this tree, but the bindgen must refuse to emit a module that also defines one, and `expCheckDeclNames` should refuse a `(macro (extern ...))` or `(macro (export ...))` outright.

### 2. Grammar

```
extern-decl  := "(" ["pub"] "extern" STRING item+ ")"
item         := opaque-item | symbol-item
opaque-item  := "(" "opaque" UpperName [ "(" "drop" lowerName ")" ] ")"
symbol-item  := "(" lowerName "::" type clause* ")"
clause       := "(" "symbol"  STRING ")"
              | "(" "effects" "(" EffectName* ")" ")"

export-decl  := "(" "export" STRING export-item+ ")"
export-item  := "(" lowerName [ "(" "symbol" STRING ")" ] ")"
```

The `symbol-item` shape is deliberately byte-for-byte the shape `parseEffectOps` already reads — `(` ident, optional `::` and a type, then everything up to the item's `)` (`self_host/parser.ax:1252-1285`) — because `(effect Console (log :: (-> String Int)))` is the only existing declaration in the language whose body is *a list of typed callables*, and an extern block is the same thing with a linker behind it instead of a handler. The clause tail is where `parseEffectOps` calls `skipParens` and throws the rest away; `parseExternDecl` keeps it.

**Decision: a block, not one symbol per declaration.** Alternatives:

- *One declaration per symbol* (`(extern "lib" name :: Type)`). Rejected: the library string repeats on every line, and MM-FFI-5's fourth requirement — "a gate that **enumerates permitted external symbols**" — wants a unit of enumeration. The block is that unit; `ffi.lock` keys on it (§11).
- *Signature separate from binding*, i.e. `(:: name Type)` beside `(extern "lib" name)`. **Rejected on measured grounds:** `defIdxBuild` (`self_host/typecheck.ax:1114-1132`) indexes only `TAG_D_FN` nodes with `nodeVis == 1`, so `checkMissingDefs` (`self_host/typecheck.ax:1242-1262`) would draw a false `AX3015` on every single `::` written over an extern. Carrying the type inline makes that failure structurally impossible instead of requiring a fix that a later refactor can undo.

**Decision: `pub` is per-block.** `markPub` writes word 5 of the node the recursion returns (`self_host/parser.ax:42-43`, `1105-1108`), and there is exactly one node per block, so per-item visibility is not expressible without a second mechanism. Mixed visibility is written as two blocks naming the same library. The bindgen exploits this deliberately (§11): it emits one `(pub extern …)` block for items usable as-is and one private `(extern …)` block for items that need an Axiom-side wrapper.

### 3. What each clause means

**`(symbol "s")`** — the linker symbol. Default is the Axiom item name verbatim, which is the rule the language already follows for entry-file declarations (`llvmSym`, `self_host/codegen.ax:982-990`, emits `@addTwo` for `addTwo`). The clause exists because a static link is one flat namespace and `parse` is a name three crates will claim.

**The default is a footgun and the spec says so.** Two modules that each bind an item named `parse` and each omit `(symbol …)` produce two `declare i64 @parse(i64) #0` lines that dedup to one, two Axiom names that both resolve to `@parse`, and one link-time winner — with no diagnostic at any stage, because the checker never sees a linker namespace. Therefore: **bindgen always emits `(symbol …)` explicitly with a crate prefix**, and `check-ffi-allowlist.sh` fails a program in which two `ffi.lock` libraries export the same symbol name. Hand-written blocks may omit the clause and are on their own.

Refusals on this string: a symbol matching `axiom_alloc`, `axiom_retain`, `axiom_release`, `axiom_rt_init`, `main`, `__axiom_*` or `__syscall*` is `AX3026 reserved-runtime-name` — the code already exists for exactly this class of mistake, and those symbols are the ones with external linkage (`self_host/codegen.ax:2046`, `2274`, `2292`, `1994-2001`, plus §9's `axiom_rt_init`) that a bridge crate could otherwise shadow at link time.

**`(effects (E ...))`** — widens the seeded effect set. Absent, an item seeds `{Foreign, IO}`. Present, it seeds `{Foreign} ∪ {E ...}`; `(effects ())` therefore means "Foreign and nothing else", which is how a genuinely pure hash function is spelled. **`Foreign` is not suppressible** — MM-FFI-5's third requirement is that a foreign call *be* an inferred effect, so a clause that could erase it would erase the requirement. Note what `(effects ())` does *not* mean: it constrains what the item itself contributes to the fixpoint, not what its callers infer (see example 1).

**`(opaque T)`** and **`(opaque T (drop f))`** — §5.

**Decision: there is no `(unsafe)` clause.** Every extern item is exactly as unsafe as every other one; a marker present on all of them carries zero bits. The *block* is the unsafety boundary, and its presence in a module is what flips that program from `check-freestanding.sh` to the allowlist gate (§11). An `unsafe` keyword would imply a safe extern exists, and none does.

**Decision: there is no `(fallible)` clause.** Fallibility is not an ABI property; it is a *protocol* over the one word C2 allows, and the protocol is spelled in the type — an item that can fail returns the built-in `Outcome` (§6). Putting it in an attribute would mean the declaration no longer describes the symbol it names, and the whole value of this form is that it describes the symbol and nothing else.

### 4. Type discipline at the boundary

**Decision: an extern signature admits exactly `Int`, `Float`, `Bool`, `Char`, `String`, the two compiler-owned ABI opaques `Slice` and `Outcome` (§6), and opaque types declared in the same block. Everything else is `AX3036`.**

This is narrower than it looks, and it is narrow on purpose. The measured facts that force it:

- **C3 / type variables.** A type variable in any parameter position makes the emitter grow the hidden trailing `i64 %__evw.h` (`self_host/codegen.ax:3008-3021`, passed at `5925`). That word must never reach a Rust `extern "C"` signature. Refusing tyvars in an extern is the only way to guarantee it, and `tyCompat` (`self_host/typecheck.ax:188-235`) cannot help — a type variable on *either* side matches anything, so the checker would happily accept `(-> a Int)` and then hand Rust an extra argument.
- **`()`.** `docs/reference.md:281-296` records that `()` is a type with no value: "There is no unit *value*: `()` in expression position is `AX2001 expected expression`". An extern parameter typed `()` has no ABI meaning; an extern result typed `()` cannot be bound. Both are `AX3036`. A void Rust function's shim returns `0i64` and the Axiom side declares `Int`. **The same rule binds this section's own prose:** a nullary Axiom signature is written with a bare result type, `(pub :: sha2AbiDigestOk Bool)`, never `(-> () Bool)`.
- **Aggregates.** A tuple, a list, an arrow, a `Ptr`, or a declared `data`/`struct` type crossing by value would require Rust to author an Axiom heap block — 16-byte header, count word, and a shape word packing MM-LIFE-2d's per-payload-word reference bitmap. **The rule that keeps this sound is: only Axiom's own emitter ever writes an Axiom shape word** (`shapeBits`, `self_host/codegen.ax:6190-6200`). Aggregates therefore cross as words plus accessors, marshalled by generated Axiom wrappers on one side and generated Rust glue on the other (examples 5 and 6).
- **`String` is permitted in parameter position only.** In that direction Rust *reads* the layout `strWrapOwned` builds (`stdlib/Str.ax:68-88`): the handle addresses a three-word `{len, ptr, owner}` cell, with count at handle−16 and shape at handle−8, which is the same shape the static literal header emits (`self_host/codegen.ax:1030-1040`). Reading is free and layout-stable. In the *return* direction it would mean Rust allocating an Axiom `Str`, which is the rule above. A returned string is a `Slice` plus a conversion through `strAlloc` + `memCopy` (`stdlib/Str.ax:89-100`, `stdlib/Mem.ax:93-95`), spelled once as `sliceToStr` in `stdlib/ffi/Abi.ax` (§6).

`Float` crosses as its IEEE-754 bits in an i64, per the measured ABI; the generated Rust shim does `f64::from_bits` on the way in and `to_bits` on the way out. `Bool` crosses as 1/0 — `true` and `false` lower to the integer constants 1 and 0 (`self_host/codegen.ax:4852-4862`).

#### 4a. The word-count table

The previous draft never stated how many i64 words a Rust type occupies, and its own examples disagreed — `&[i64]` was said to cross as two words while `&[u8]` was declared as one. **An arity disagreement between the emitted `declare` and the real symbol is the one failure nothing in this design can catch:** the checker enforces nothing across the boundary, LLVM emits the call against whatever the `declare` said, and the shim reads a register nobody set. So the mapping is fixed here, and the rule that keeps it honest is stated first.

> **One Axiom declared parameter per shim word, always.** The macro computes the word count for each Rust parameter and writes it into the ABI record; bindgen emits the `.ax` declaration *from that record*, never from the Rust source text. The two arities therefore come from one source and cannot drift. Bindgen additionally asserts `sum(words) == arrowDepth(declared type)` before writing the file and fails the build if it does not hold.

| Rust type (parameter) | Words | What each word holds | Axiom-side declaration |
|---|---|---|---|
| `i8 i16 i32 i64 isize u8 u16 u32 u64 usize` | 1 | the value, sign- or zero-extended to 64 | `Int` |
| `f64` (and `f32`, widened) | 1 | IEEE-754 bits | `Float` |
| `bool` | 1 | 1 or 0 | `Bool` |
| `char` | 1 | Unicode scalar value | `Char` |
| `&str` | 1 | an Axiom `String` handle — the address of `{len, ptr, owner}` | `String` |
| `axiom_abi::AxBytes<'_>` | 1 | the same handle, no UTF-8 obligation | `String` |
| `&[T]`, `&mut [T]` — **including `&[u8]`** | 2 | word 0 = base pointer, word 1 = length **in elements** | `Int Int` |
| `&T`, `&mut T`, `T` where `T` is `#[axiom::opaque]` | 1 | the `Box::into_raw` pointer | that opaque's name |

| Rust type (return) | Words | What it holds | Axiom-side declaration |
|---|---|---|---|
| `()` | 1 | constant `0` | `Int` |
| any scalar above | 1 | as above | `Int`/`Float`/`Bool`/`Char` |
| `String`, `Vec<u8>`, `Vec<T>`, `[u8; N]` | 1 | a `Slice` handle | `Slice` |
| `Result<T, String>`, `Option<T>` | 1 | an `Outcome` handle | `Outcome` |
| `T` where `T` is `#[axiom::opaque]` | 1 | the `Box::into_raw` pointer | that opaque's name |

`&str` and `&[u8]` differ deliberately, and the difference is the whole reason the table exists: `&str` is *bound to an Axiom `String`*, so one handle suffices and Rust reads the cell; `&[u8]` is *bound to a raw region*, so it needs a pointer and a length like every other slice. A bridge that wants to hash the bytes of an Axiom `Str` writes `&[u8]` on the Rust side and passes `(strData s)` and `(strLen s)` from an Axiom wrapper — which is what example 4 now does.

#### 4b. UTF-8 is a boundary obligation only Rust can discharge

An Axiom `Str` is a byte string with **no UTF-8 invariant**. `strWrapOwned` wraps three raw words and says `(cast String s)` with no validation (`stdlib/Str.ax:68-83`); `strAlloc` hands back zeroed bytes a caller fills with `memCopy` (`stdlib/Str.ax:89-98`, `stdlib/Mem.ax:93-95`); example 2's own wrapper builds a `Str` that way out of bytes Rust returned. Handing those bytes to `core::str::from_utf8_unchecked` — as the previous draft's shim did — is undefined behaviour reachable from ordinary, non-`unsafe`-looking Axiom source, and it flows straight into `to_uppercase` and `serde_json`.

The rule:

- A `&str` parameter is marshalled with **`core::str::from_utf8`**, never the unchecked form.
- `#[axiom::export(utf8 = "checked")]` is the default. On invalid input the shim produces an `Err` `Outcome`; if the item's declared return is not already `Outcome`, **the macro promotes it to `Outcome`**, and bindgen declares `Outcome` on the Axiom side. The promotion is visible in the generated `.ax`, so it is never a surprise.
- `#[axiom::export(utf8 = "lossy")]` uses `String::from_utf8_lossy`, which cannot fail and therefore does not promote the return type. It allocates and it silently substitutes U+FFFD; that is the cost, and it is the author's to accept.
- `axiom_abi::AxBytes<'_>` and `&[u8]` carry no obligation at all and are the right choice for anything that is not text.

The checker cannot help here: `String` is `String` to `tyCompat` whatever bytes are behind it. This is boundary type safety of exactly the kind the ground truth says must live on the Rust side, "where real types exist, checked at binding-generation time".

### 5. The opaque foreign type

**Decision: `(opaque T)` declares a nominal, arity-zero type constructor registered in a dedicated opaque-name table.** This is the single highest-leverage decision in the section, and it is worth the space — including correcting what the previous draft claimed it bought.

#### 5a. What buys MM-FFI-5 requirements 1 and 2: nominality, through `tyCompat`

The previous draft attributed the arena protection to repr-scalar registration. **That was wrong**, and the correction matters because it changes which table the implementation must touch.

`tyReprClash` has **exactly one call site in the whole tree** — `checkDeclaredReturn` at `self_host/typecheck.ax:7020`, the declared-return-versus-body check. Argument checking does not go anywhere near it; it goes through `tyCompat` (`self_host/typecheck.ax:4053`), whose `TAG_T_CON` arm is:

```scheme
(if (&& (strEq (nodeA a) (nodeA b))
        (== (vecLen (nodeB a)) (vecLen (nodeB b))))
    (tyCompatVec (nodeB a) (nodeB b) 0)
    0)
```

— `self_host/typecheck.ax:216-219`. Two argument-free constructors with different names are **already incompatible, by name.** The file measures this itself at `2455-2461`: `(type Count = Int)` with `(:: h (-> Count Int))` gives `(h 42)` → `AX3004: expected Count, found Int`, "because argument checking compares constructor NAMES through `tyCompat` while the declared-return check names only `Bool` and `Float`."

So, correctly derived:

- `(memGetWord h 0)` where `h : Sha256` is `AX3004` because `memGetWord`'s declared parameter is `Int` (`stdlib/Mem.ax:174`) and `tyCompat` compares `Sha256` against `Int` and answers 0 on the name. Same for `memSetWord`, `memCopy`, `__axiom_arena_mark`, `__axiom_arena_reset_keeping`, `strLen`, `__load64`. **No new arena rule is needed, and no repr-scalar registration is needed for this.** It follows from the type being *nominal* and from `tyCompat` having been de-fiated on 2026-08-15.
- `Sha256` and `JsonDoc` are mutually incompatible for the same reason, so a bridge's handles cannot be confused with each other.

MM-FFI-5's first two requirements are therefore discharged by declaring a new *name*. That is a much cheaper claim than the one the draft made, and it is the true one.

#### 5b. What repr-scalar registration actually buys: `checkDeclaredReturn`, and only that

Registering the opaque name in `tyIsReprScalar` (`self_host/typecheck.ax:7095-7096`) reaches exactly one check — `checkDeclaredReturn` (`7017-7021`) — and what it buys there is precise and worth having:

> An Axiom function declared to *return* an opaque whose body answers something else is refused. In particular `(:: jsonDocOf (-> Int JsonDoc)) (fn (jsonDocOf d) d)` — the identity launderer that would turn any integer into a foreign handle — is `AX3004`.

That is the *definition-side* half of the same hole `AX3037` closes on the *cast* side. Without it, `cast` is refused and a one-line wrapper is not, which would be a rule anyone can walk around. With it, there is no Axiom expression that produces a value of an opaque type except the sanctioned producer in §5d.

**Re-derived cost (gap 3).** The old text priced this against the `String` sweep — 145 diagnostics across 117 of 261 files. That number is not a predictor and citing it was misleading: it came from adding an *existing, universally imported* name to the predicate, and all 145 traced to three declarations. Adding *new* names reaches only declared-return sites whose declared type is an argument-free constructor spelled with an opaque name, and no program in the corpus names one, so the expected report count is **zero**. It must still be **run and counted**, not assumed — the predicate becomes dynamic (§5c) and a dynamic predicate can misfire in ways a three-literal one cannot.

#### 5c. Which table — the part that corrupts the Rust heap if you get it wrong

The draft never said where an opaque name is registered, and the two obvious choices are both wrong in ways that do not announce themselves.

`tyConKnown` (`self_host/typecheck.ax:2415-2427`) is the only thing that makes a type name resolvable at all, and it knows five sources: `typeKeywordCanon`, the literal `"Linear"`, `tcDatas`, `tcStructs`, `tcAliases`. An unregistered opaque is `AX3002 undefined type`, so registration somewhere is mandatory. But:

- **`tcDatas`/`tcStructs` corrupts the Rust heap.** `evDataTyKnown` (`559-580`) scans exactly those two vectors, and `evClassOf`'s `TAG_T_CON` arm (`594-613`) ends `(evDataTyKnown tc n)` — so the name classifies as **1 = reference**. Then every polymorphic container in the examples — `(Ok d)`, `(Some s)`, `vecPush` — stamps a set reference bit into MM-LIFE-2d's evidence word for a Rust `Box` pointer, and the release path does `add i64 %h, -16` / `inttoptr` / `load` / `store %c-1` (`self_host/codegen.ax:2292-2310`) behind nothing but an `icmp slt i64 %h, 4096` guard, which a `Box` pointer passes. The file's own comment at `583-585` states the stakes: "The 0 default is the safe direction everywhere - a missed bit under-reclaims, a wrong bit is a use-after-free."
- **`tcAliases` destroys the type.** `tcExpandSigAliases` rewrites the alias away, including the per-arrow float flags, so `Sha256` becomes whatever it aliases and the distinctness the whole section rests on evaporates before any check runs.

Note the asymmetry in the two unknown-name defaults, because it is why "just leave it unregistered" is not a strategy either. `fldClass`'s unknown default is **1 = unclassifiable → LEAF shape**, which leaks and is survivable. `evClassOf`'s unknown default is **0 = scalar**, which is *correct* — but it is correct only while the name is unknown to `tcDatas`/`tcStructs`, which is the same condition under which `tyConKnown` answers `AX3002`. There is no registration among the existing five sources that gets both answers right.

> **Therefore: a sixth, dedicated table — `tcOpaques` — holding every `(opaque T)` name of the merged declaration list, plus the two compiler-owned ABI names of §6. It MUST NOT be `tcDatas`, `tcStructs` or `tcAliases`.** Four predicates consult it:
>
> | Predicate | Site | Must answer | Consequence if it does not |
> |---|---|---|---|
> | `tyConKnown` | `self_host/typecheck.ax:2415-2427` | known | `AX3002` on every use of the name |
> | `evScalarName` | `self_host/typecheck.ax:542-558` | 1 (scalar) | `evClassOf` says reference; ARC frees a Rust `Box` |
> | `scalarTyName` | `self_host/codegen.ax:6133-6147` | 1 (scalar) | `fldClass` says 1; the enclosing record collapses to LEAF and leaks every other field |
> | `tyIsReprScalar` | `self_host/typecheck.ax:7095-7096` | true | `(-> Int T)` identity launderers are accepted (§5b) |
>
> `evScalarName` and `scalarTyName` are the same list spelled twice, and the tree says so at `self_host/typecheck.ax:539-541`: "the two lists must agree, and the evidence fixture is what notices a drift." The opaque set must be threaded into both from the same declaration list, in the same commit, or the evidence fixture is the thing that finds out.

#### 5d. The sanctioned producer, and the only one

A value acquires an opaque type by exactly one route:

> **An extern item whose declared RESULT is an opaque type.** Nothing else.

`cast` is `AX3037`. An Axiom-side identity wrapper is `AX3004` by §5b. A tyvar-typed accessor is illegal by C3. This is what makes §6's per-result-type accessors necessary rather than stylistic: `(jsonOutcomeDoc :: (-> Outcome JsonDoc) (symbol "ax_abi_outcome_value"))` is a *legal producer* of a `JsonDoc`, while `(outcomeValue :: (-> Outcome Int))` followed by any Axiom-side re-typing is not, and the previous draft's `jsonDocOf` — called in example 6, defined nowhere, unwritable in principle — was the visible symptom.

Declaring several items over one symbol is free at the ABI: every such `declare` is `i64 @ax_abi_outcome_value(i64) #0`, byte-identical, so §10's dedup rule holds without a special case.

#### 5e. Alternatives considered

- *One built-in `Foreign` type, arity 0.* Rejected: every handle in every crate would be interchangeable, and confusing a `Sha256` with a `JsonDoc` is the exact failure a distinct type is supposed to prevent.
- *A parameterised `Foreign a`.* The previous draft rejected this by claiming `(Foreign Sha256)` against `Int` "would be **accepted**" because `tyReprClash` bails on applied constructors. **That reasoning was wrong for the same reason §5a corrects:** argument positions go through `tyCompat`, whose `TAG_T_CON` arm compares the head names `Foreign` and `Int` and answers 0. `(Foreign Sha256)` is refused against `Int` today. The real reasons to reject it are different and still sufficient: it introduces an argument position that `tyCompat` recurses into, so `(Foreign a)` re-opens C3's evidence-word hole inside a type that *looks* concrete and would need a second rule to forbid; the payload names have to be declared somewhere regardless, so the parameter buys no distinctness that arity zero does not already give; and `tyConKnown` would have to learn an arity as well as a name. Arity zero is the smaller change with the same guarantee.

#### 5f. `(drop f)` and lifetime

C8 requires an explicitly registered destructor. `(opaque T (drop f))` names another item of the same block, whose signature must be `(-> T Int)`; `AX3038 extern-drop-missing` fires when any item in the block *returns* `T` and no `(drop …)` was given. The two compiler-owned ABI opaques satisfy `AX3038` by construction — the compiler knows their destructors are `ax_abi_slice_free` and `ax_abi_outcome_free` — so no block ever writes `(opaque Slice …)`.

**Known gap, stated plainly: the destructor is not automatic.** An opaque handle is repr-scalar and is registered as such in both evidence tables, so it is never in a reference map and `axiom_release` (`self_host/codegen.ax:2292`) will never see it; Axiom has no destructors and no `free`. `(drop f)` therefore records the destructor for the gate, for the bindgen, and for the reader — it does not run it. Calling `f` is manual, and a double call is the programmer's mistake in exactly the way a doubled `__axiom_arena_reset_keeping` is. The fix, when someone wants it, is structural and costs a runtime feature: box the foreign pointer in a one-word *mapped* Axiom block carrying a finalizer id, and teach `axiom_release`'s dead-block path to dispatch on it. That is a finalizer table in the emitted runtime and it is out of scope for v0. Saying so is better than shipping an `(opaque …)` that looks like RAII and is not.

#### 5g. Casts

`(cast Int h)` would defeat all of the above in one token. **`AX3037 foreign-opaque-escape`** refuses a `cast` into or out of an opaque type. The only sanctioned exit is a bridge-exported accessor with a declared `Int` result — `(slicePtr :: (-> Slice Int))` — so that every crossing is a named symbol the allowlist gate can see, rather than a syntax anyone can write.

### 6. `Slice` and `Outcome` are compiler-owned, not per-block

The previous draft had every generated module write its own `(opaque Slice …)` and `(opaque Outcome …)`. Under §8's per-module mangling that produces `Text$Slice`, `Json$Slice` and `Stats$Slice` — three mutually incompatible types by `tyCompat`'s name rule — so `sliceToStr` cannot be written once, and the draft's examples called `sliceToStr` and `hexOf` without either existing anywhere. Example 3 also used `Slice` in a signature without declaring it in that block, which its own §4 rule makes `AX3036`.

**Decision: `Slice` and `Outcome` are built-in ABI type names owned by the compiler.** They are pre-seeded into `tcOpaques` at checker start, the way `tyConKnown` already hard-codes `"Linear"` (`self_host/typecheck.ax:2417`). They are in scope everywhere, need no import and no declaration, and `(opaque Slice …)` in a user block is `AX3036`. Their layouts are `axiom-abi`'s, fixed by this specification:

```rust
#[repr(C)] pub struct Slice   { pub ptr: *const u8, pub len: i64 }
#[repr(C)] pub struct Outcome { pub ok: i64, pub value: Word, pub err: Slice }
```

One checked-in, **never-regenerated** module declares the accessors and the conversions once:

```scheme
; stdlib/ffi/Abi.ax  -- checked in by hand; axiom-bindgen never rewrites this file.
(import Str) (import Mem)

(pub extern "axiom_abi"
  (slicePtr      :: (-> Slice Int)      (symbol "ax_abi_slice_ptr")      (effects ()))
  (sliceLen      :: (-> Slice Int)      (symbol "ax_abi_slice_len")      (effects ()))
  (sliceFree     :: (-> Slice Int)      (symbol "ax_abi_slice_free")     (effects ()))
  (outcomeIsOk   :: (-> Outcome Bool)   (symbol "ax_abi_outcome_is_ok")  (effects ()))
  (outcomeInt    :: (-> Outcome Int)    (symbol "ax_abi_outcome_value")  (effects ()))
  (outcomeSlice  :: (-> Outcome Slice)  (symbol "ax_abi_outcome_value")  (effects ()))
  (outcomeErr    :: (-> Outcome Slice)  (symbol "ax_abi_outcome_err")    (effects ()))
  (outcomeFree   :: (-> Outcome Int)    (symbol "ax_abi_outcome_free")   (effects ())))

; A copy out of Rust-owned bytes into an Axiom `Str`. Does NOT free the
; slice: the caller owns it and calls `sliceFree` when it is done, which
; is the one ownership rule this module has.
(pub :: sliceToStr (-> Slice String))
;@axiom:effect(foreign)
(pub fn (sliceToStr sl)
  (let ((n (sliceLen sl))
        (out (strAlloc n)))
    { (memCopy (strData out) (slicePtr sl) n) out }))

; Lowercase hex of `n` bytes at `p`. Axiom-side only; no symbol.
(pub :: bytesToHex (-> Int Int String))
(pub fn (bytesToHex p n) ...)
```

`outcomeInt` and `outcomeSlice` bind the same symbol under two Axiom names because the *declared result type* is what makes each one a legal producer (§5d); a bridge that returns an opaque adds a third, e.g. `(jsonOutcomeDoc :: (-> Outcome JsonDoc) (symbol "ax_abi_outcome_value"))`, in its own generated block. All of them emit the identical `declare i64 @ax_abi_outcome_value(i64) #0`, which is what makes §10's dedup rule sufficient.

**Ownership rule for `Outcome.value`, stated once:** an `Outcome` **never owns** its `value` word. On the ok side `value` is either a scalar or an already-transferred handle — a `Slice`, or an opaque — whose destructor the Axiom side calls. `ax_abi_outcome_free` therefore frees the `Outcome` box and the `err` message and nothing else. Getting this wrong in either direction is a double free or a leak, and MM-FFI-3 guarantees nothing on the Axiom side will notice either.

### 7. Effects

**Decision: a new built-in effect `Foreign`, seeded at registration.**

The model is `tcAddEffectOp` (`self_host/typecheck.ax:1866-1876`): an effect operation's `FnEnt` is pushed with word 5 — the effects Vec — **pre-seeded**, so the monotone fixpoint `inferEffects` (`self_host/typecheck.ax:5199-5241`) propagates it transitively for free with no special case anywhere in the walk. An extern item does the same: `tcPushFn` (`self_host/typecheck.ax:1980-1982`) with `(vecPush v (builtinEff "Foreign"))` and, unless `(effects …)` says otherwise, `(builtinEff "IO")`.

`Foreign` rather than reusing `IO`: the whole point of the allowlist gate is telling "reaches the kernel through a `__syscallN` we wrote" apart from "reaches arbitrary Rust", and `isSyscallPrim` (`self_host/typecheck.ax:5029-5034`) is the *sole* classifier for the former. Two different capabilities want two different names. But a foreign call can also do I/O, so `Foreign` implies `IO` by default rather than replacing it — effects are a plain Vec of tagged strings (`self_host/typecheck.ax:1884-1888`) unioned by `effUnion`, so seeding two costs nothing.

Three tables learn the name:

| Site | Change |
|---|---|
| `self_host/typecheck.ax:2959-2960` | the `handle`-list built-in name set, so `(handle body (Foreign) 0)` parses as a static scope |
| `self_host/typecheck.ax:3088-3092` `isBuiltinEffect` | so `Foreign` is not treated as a `Custom` effect and is exempt from `AX3016`/`AX3017` |
| `self_host/typecheck.ax:6846-6850` `axtagEffectOf` | `"foreign"` → `(builtinEff "Foreign")`, so `;@axiom:effect(foreign)` validates |

`AX3011` then fires at a `handle` site whose list omits `Foreign`, and `AX3010` warns on an AXTAG mismatch — both unchanged, both free.

**What `(effects ())` does and does not constrain.** It sets what *that item* contributes to the fixpoint. It says nothing about the caller, because `walkCallHead` unions the callee's whole `FnEnt` word 5 into the caller's accumulator (`self_host/typecheck.ax:4935-4937`) for *every* callee. A function that calls a pure extern and also calls `println` infers `{Foreign, IO}`, because `println` reaches `__syscallN` and `isSyscallPrim` classifies that as `IO`. And `AX3010` never fires on the surplus: `axtagUnsupported` (`self_host/typecheck.ax:6807-6831`) reports only when `(effIn eff want)` is 0 — a *claim the body does not support* — never when the body performs more than the claim. Example 1 is written against this and the previous draft's version of it was written against an inference result the compiler will not produce.

### 8. Visibility, modules and mangling

`(pub extern …)` exports every item and every opaque type of the block; a bare `(extern …)` keeps them module-private. This is the rule `docs/reference.md:1136-1163` states for everything else, and it is what lets a generated binding module expose only safe wrappers.

Mangling is the one place the two names must not be confused, and the previous draft's "call sites are unchanged" was false — it produced an undefined symbol. `emitPlainCall` emits `@` + `(llvmSym (mangledFor cg fnName))` (`self_host/codegen.ax:5915`, `5931-5934`), which is the Axiom-level name after the emitter's rename map, not the link symbol. §8 requires the item name to be mangled to `Sha2$sha256Update`; nothing in the emit path would ever read the link symbol out of the node. The call would say `@Sha2$sha256Update` while the `declare` said `@ax_sha2_update`.

Two facts constrain the fix, and both are measured:

1. `mangleDecl` (`self_host/namespace.ax:126-170`) rewrites `nodeA` **in place** for `TAG_D_FN` and `TAG_D_SIG` because `emitFnDef` re-reads the same node later. An extern item's Axiom name must be mangled the same way — `Sha2$sha256Update` — so imports, `Mod::name` qualified access and `AX3023` all work unchanged. Its **linker symbol must never be mangled**. Therefore the extern item node carries the link symbol in a **new word**, not in `a`. `ASTNode` is eleven words today (`self_host/parser.ax:33`) and has been extended by appending three times for exactly this reason — `axtags` eighth, `module` ninth, `fieldNames` tenth, each time because "every existing reader indexes by position, so appending is the only change that is free". The link symbol is the twelfth.
2. **Reusing `bares`/`fulls` (cg words 12/13) does not work as-is**, which is worth stating because it is the obvious cheap answer. `mangledFor` (`self_host/codegen.ax:1695-1708`) checks the module-local shortcut first and, when `Mod$name` is present in `bares`, returns **`local` verbatim** rather than the mapped `full`:

   ```scheme
   (if (mangleHasIn (memGetWord cg 12) local 0)
       local
       (mangledForIn (memGetWord cg 12) (memGetWord cg 13) name 0))
   ```

   So a `Sha2$sha256Update → ax_sha2_update` pair in those vectors is shadowed by the very shortcut that makes module-local resolution work. And `mangleRecordSelf` (`self_host/namespace.ax:172-185`), the private half, records `full → full` identity, which is precisely the wrong answer for an extern.

> **Therefore: a dedicated extern link map** — a new `cg` word holding two parallel vectors, resolved Axiom name → link symbol, populated by `mangleDecl`'s extern arm (which walks the block's item Vec, mangles item names, and leaves the link slot alone). `mangledFor` consults it **first**, ahead of the module-local shortcut, and returns the link symbol when it hits. `mangleRecordSelf` is not used for extern items in either visibility. **stage0's `mangled_name_for` gains the identical arm** — the two "have to agree symbol for symbol or the fixpoint is comparing different programs" (`self_host/codegen.ax:1690-1694`).

Two modules binding the same symbol under different Axiom names is normal and correct: one deduped `declare`, two entries in the link map. Two modules binding the *same* item name with the `(symbol …)` clause omitted is the silent collision of §3, caught by the gate and not by the compiler.

### 9. The other direction: Rust calls Axiom

The owner's decision is "support BOTH directions with ONE shared marshalling layer", and experiment 3 already established the mechanism. The previous draft specified only Axiom-calls-Rust, which left the export half, the entry-point contract, and C7 undesigned even though `axiom_retain`/`axiom_release` appeared in `axiom-abi` with no rule for their use. This section closes that.

#### 9a. The `export` block

```scheme
(export "axiom_demo"
  (addTwo (symbol "ax_demo_add_two"))
  (greet  (symbol "ax_demo_greet")))
```

Every item names a function **already defined in the program**; `export` declares nothing and defines nothing in the value namespace, so it is invisible to `declNamespace`, `defIdxBuild` and `ambBuildDecl` by construction. Rules:

- `AX3001` if the named function is not defined in the merged declaration list.
- **C3 applies in reverse.** A polymorphic Axiom function carries the hidden trailing `i64 %__evw.h` (`self_host/codegen.ax:3008-3021`), and no `extern "C"` caller can supply it. Exporting one is `AX3036`.
- The symbol string obeys §3's reserved-name refusal (`AX3026`), including `axiom_rt_init`.
- Arity is `repArity` of the named function — never −1, for the same reason as §10.

**Emission: a forwarding definition, not an LLVM alias.** The emitter has never written an `@alias` and does not learn to here; it writes what it already writes:

```llvm
define i64 @ax_demo_add_two(i64 %p0, i64 %p1) #0 {
  %t0 = call i64 @Demo$addTwo(i64 %p0, i64 %p1)
  ret i64 %t0
}
```

Same `#0` group, same universal-word ABI, no new IR construct, and the callee spelling comes from the same `mangledFor` every other call uses. A nullary export forwards `call i64 @Demo$f()`.

#### 9b. The runtime-initialisation contract

`axiom build --emit-staticlib` renames `@main` to **`@axiom_rt_init`** and runs `ar rcs` over the object. The rename rides the path that already exists for `main`: `mangledFor` special-cases the name at `self_host/codegen.ax:1695-1701`, and `declSpellingOf` (`1041-1043`) is the lookup that keeps the declaration tables honest across it.

```rust
extern "C" {
    fn axiom_rt_init(argc: i64, argv: i64) -> i64;
    fn ax_demo_add_two(a: i64, b: i64) -> i64;
}
```

`axiom_rt_init(argc, argv)` **must be called exactly once, before any exported symbol.** It is what stores argc/argv into the internal globals (`self_host/codegen.ax:1994-2001`) — `sysArg` reads garbage otherwise — and it is what runs the user `main`. A host that does not want a user `main` to run writes `(fn (main) 0)`; there is no way to have the globals without the call, and inventing one would mean a second entry point to keep in step.

The allocator is process-private (I11) and MM-PAR-1 admits no threads, so a Rust host **must not** call exported symbols from more than one thread. That is a hard rule, not a caution: the bump allocator has no lock and none is planned.

#### 9c. C7, worked

Rust may hold an Axiom heap value past the call **only** by calling `axiom_retain`, paired with exactly one `axiom_release`. Both are externally linked (`self_host/codegen.ax:2274`, `2292`).

```scheme
; demo.ax
(export "axiom_demo"
  (greet (symbol "ax_demo_greet")))

(pub :: greet (-> String String))
(pub fn (greet who) (strConcat "hello, " who))
```

```rust
use axiom_abi::{Word, AxStr, ax_bytes, axiom_retain, axiom_release};

extern "C" { fn ax_demo_greet(who: Word) -> Word; }

/// Holds an Axiom `Str` across calls. `axiom_retain` on the way in,
/// `axiom_release` in `Drop`; between them the handle is stable and
/// `ax_bytes` may be re-read as often as we like.
pub struct Held(Word);

impl Held {
    /// # Safety
    /// `h` must be a live Axiom handle produced by this process.
    pub unsafe fn new(h: Word) -> Self { axiom_retain(h); Held(h) }
    pub fn bytes(&self) -> &[u8] { unsafe { ax_bytes(self.0) } }
}
impl Drop for Held {
    fn drop(&mut self) { unsafe { axiom_release(self.0) } }
}

fn main() {
    unsafe { axiom_rt_init(0, 0) };
    let greeting = unsafe { Held::new(ax_demo_greet(ax_str_literal(b"axiom"))) };
    println!("{}", core::str::from_utf8(greeting.bytes()).unwrap());
    // `greeting` releases here; nothing else in Rust may touch that word after.
}
```

The rule the example encodes: **a `Word` that Rust did not retain is borrowed for the duration of one call and for nothing longer.** Every shim `#[axiom::export]` generates obeys it without retaining — which is why example 2's `to_upper` needs no `axiom_retain` — and `Held` is the only shape in which Rust is allowed to break it.

**Scope note.** v0 exports functions, not types: there is no way to hand Rust an Axiom `data` value and have Rust pattern-match it, because that would mean Rust reading a tag word and a shape word, and §4's aggregate rule forbids exactly that. Field-wise accessors, generated by `#[derive(AxiomRecord)]` in the other direction, are the sanctioned equivalent.

### 10. What the rest of the compiler must learn

The tags: **not 53.** The brief's ground truth says the next free declaration tag is 53, and 53 is taken — `TAG_EVSTAMP` (`self_host/parser.ax:186`). The free numbers are 18, 19, 44, 45, 46 and 54+; 29 is permanently retired (`self_host/parser.ax:100-104`). **Take 54 for `extern` and 55 for `export`**, leaving the interior gaps alone, since a gap whose vacancy is not documented is a gap someone else may be relying on.

Every dispatch that keys on a declaration tag falls through silently for an unknown one, so each of these is a *silent* wrong answer, not a crash:

| Site | Without the arm |
|---|---|
| `emitDecl` `self_host/codegen.ax:2817-2846` | emits only `TAG_D_FN`; an extern block emits no `declare` and an export block no forwarder, so calls reference an undefined symbol and `opt` refuses generated code with no span into the source |
| `isNullaryFn`/`isNullaryFnIn` `self_host/codegen.ax:1044-1056` | requires `(nodeTag d) == TAG_D_FN` over the top-level list, and an extern item is not one. So `(sha256New :: Sha256)` referenced bare misses the nullary arm at `4888` and falls into the bare-reference arm — **the exact MM-EXEC-15a failure the file documents twenty lines above**: "Emitting `%answer` names a value nothing defines … `check` said OK and `opt` refused". It must look inside extern blocks (and export blocks). The emitted call is `call i64 @sym()`, empty argument list. |
| `tcCollect` `self_host/typecheck.ax:1669-1782` | falls through to 0; every extern item is `AX3001 undefined variable` |
| `defIdxBuild` `self_host/typecheck.ax:1114-1132` | indexes only `TAG_D_FN` with `nodeVis == 1`; any `::` written over an extern item draws a false `AX3015` |
| `ambBuildDecl` `self_host/typecheck.ax:3657-3669` | knows only fns, effect ops and data constructors; two modules exporting the same extern name collide with no `AX3014` |
| `declNamespace` `self_host/typecheck.ax:790-796` | keys on tag alone and returns one namespace — **a block defines N value names and M type names, which this function cannot express.** Duplicate detection for extern items must run in `tcCollect`'s own arm against the exact-name hash index `tcPushFn` maintains, reporting `AX3006` there. This is a deliberate divergence and should be commented as one. |
| `tyConKnown` `self_host/typecheck.ax:2415-2427` | knows five sources, none of them opaque names; every use of `Sha256` is `AX3002`. Gains `tcOpaques` as a sixth (§5c) |
| `evScalarName` `self_host/typecheck.ax:542-558` | opaque name falls to `evDataTyKnown`; if the name ever reaches `tcDatas`/`tcStructs` the evidence word claims **reference** and the release walk does `load`/`store` at `h-16` on a Rust `Box` (`self_host/codegen.ax:2292-2310`) — a use-after-free, not a leak |
| `scalarTyName` `self_host/codegen.ax:6133-6147` | `fldClass` answers 1; the enclosing record collapses to LEAF and every reference field leaks, with no diagnostic at any stage |
| `tyIsReprScalar` `self_host/typecheck.ax:7095-7096` | `(-> Int Sha256)` identity launderers are accepted, so `AX3037` is a rule anyone can walk around |
| `mangledFor` `self_host/codegen.ax:1695-1708` **and stage0's `mangled_name_for`** | the call emits the mangled Axiom name, the `declare` names the link symbol, and they never meet (§8) |
| `fpDecl` `self_host/format.ax:3297-3319`, `fpIsDeclHead` `2523`, `fpIsReservedWord` `1292` | the formatter routes an unknown head through the *expression* printer, so `check-fmt.sh` will reformat an extern block into call shape |
| `tree-sitter-axiom/grammar.js` `_declaration` | editor highlighting and `check-tree-sitter.sh` |

Arity: **set `paramCount` from the declared type, never −1.** `repArity` (`self_host/typecheck.ax:2728-2733`) answers −1 for a signature-only name, and a −1 answer silently disables the `AX3013` bare-value refusal and the `AX3009`/`AX3013` saturation check. The old `foreign` used −1 and thereby turned both checks off for every binding it made. An extern's arity is `arrowDepth` of its declared type; a no-parameter item is declared with a bare result type — `(sha256New :: Sha256)` — matching `(pub :: vecNew Int)` (`stdlib/Vec.ax:50-52`).

Emission: an extern item emits `declare i64 @<symbol>(i64, …) #0` — the **first `declare` this emitter has ever written** (`grep -c '^declare' bootstrap/axiom-darwin-aarch64.ll` = 0). It carries the same `#0` group as everything else (`self_host/codegen.ax:2805`); the string `"no-builtins"` attribute is what stops `opt -O1` rewriting byte loops into `strlen`/`memset`, and there is no reason for a declared symbol to differ. Declares are emitted after the `target triple` line, before any definition, and **de-duplicated across the merged declaration list** by symbol — two items binding one symbol is normal (§6) and LLVM refuses a repeated `declare` with a conflicting type. Because C3 forbids tyvars, the evidence-word branch at `self_host/codegen.ax:5916` never fires for an extern.

New diagnostics — the next free code is **AX3036** (`explain.ax:22` lists through AX3035; AX3032 is burned, `self_host/expand.ax:3321`):

| Code | Slug | Condition |
|---|---|---|
| `AX3036` | `extern-signature` | a type an extern signature may not name: a type variable (C3), `()`, a tuple/list/arrow/`Ptr`, a `data`/`struct` type, an undeclared constructor, a user `(opaque Slice …)`/`(opaque Outcome …)` shadowing a built-in ABI name; also an `(export …)` item naming a polymorphic function |
| `AX3037` | `foreign-opaque-escape` | `cast` into or out of an opaque foreign type |
| `AX3038` | `extern-drop-missing` | an `(opaque T)` returned by an item of the block with no `(drop …)` |
| `AX5002` | `extern-library-unresolved` | the block's library string has no `ffi.lock` entry — the sibling of `AX5001` |

Reused: `AX3026` for a reserved link symbol, `AX3006` for a duplicate item name, `AX3001` for an `export` item naming nothing, `AX3010`/`AX3011` for the `Foreign` effect.

**Same-commit documentation obligations** — the previous draft named only two of these, and the rest are load-bearing prose that this design makes false:

1. `explain.ax`'s registry, plus its `explainListText` line, for AX3036/3037/3038/AX5002.
2. `check-doc-drift.sh`'s "every listed code has a construction site, both ways" sweep — **it counts 47/47 today** and must count 51/51 after.
3. `removedRationale` and `removedHelp` (`self_host/parser.ax:584-586`, `595-597`) retargeted at `extern`: `foreign` was removed *and replaced*, and the help must say so.
4. `docs/reference.md:275`'s Removed Keywords row, currently `| foreign | Use the standard library; generated code links no C |`.
5. **`docs/memory-model.md` MM-FFI-1 (R)**, currently the normative sentence "**Axiom has no FFI.**" with "The language has **no way to name an external symbol**". It must be amended, not quietly outlived — it is the invariant this whole design is a controlled exception to, and MM-FFI-1's own next paragraph says "any FFI design must be evaluated against what it costs" MM-PAR-3, MM-ALLOC-1 and §3.
6. **MM-FFI-2's five-boundary table** gains a sixth row for `(opaque T)`: owner is the bridge crate; outside every arena (MM-FFI-3 applies unchanged); valid until the registered `(drop …)` item is called by hand; **MUST NOT** be passed to any arena primitive, which `tyCompat` now enforces by name.

The `foreign`-is-`AX2004` probe at the end of `check-freestanding.sh` stays exactly as it is. The prose behind it cannot.

### 11. Rust side and the bindgen

Workspace at `rust/`, cargo required only for the FFI gates and never for `scripts/bootstrap-from-seed.sh`:

```
rust/
  Cargo.toml            # [workspace]
  axiom/                # facade: pub use axiom_abi::*; pub use axiom_macros::*;
  axiom-abi/            # #![no_std] + extern crate alloc; AxStr, AxBytes, Slice, Outcome, Word
  axiom-macros/         # proc-macro: export, opaque, AxiomRecord
  bindgen/              # bin: axiom-bindgen
  bridges/sha2/  json/  # per-library bridge crates, crate-type = ["staticlib"]
```

#### 11a. `axiom-abi`

The no_std tier is the one that carries the measured zero-undefined-symbols result, so **every path in this crate and in every macro expansion must resolve under `#![no_std]`.** The previous draft's listings did not: they spelled `::std::boxed::Box` and `::std::panic::catch_unwind` into expansions dropped inside a `#![no_std] extern crate alloc;` bridge, and `axiom-abi` itself called a bare `Box::from_raw` under `cfg_attr(not(feature = "std"), no_std)`. Those are unresolved paths, not style.

```rust
#![no_std]
extern crate alloc;

/// The single allocation path both tiers share. Macro expansions spell
/// `$crate::__rt::Box`; nothing anywhere spells `::std::boxed::Box`.
pub mod __rt {
    pub use alloc::boxed::Box;
    pub use alloc::vec::Vec;
    pub use alloc::string::String;
}
use __rt::Box;

pub type Word = i64;

/// The three-word cell an Axiom `String` handle addresses.
/// Layout is `strWrapOwned` (stdlib/Str.ax:68-88); count and shape sit
/// at handle-16 and handle-8 and are never touched from Rust.
#[repr(C)]
pub struct AxStr { pub len: i64, pub ptr: *const u8, pub owner: i64 }

/// A borrowed Axiom byte string with no UTF-8 obligation (§4b).
pub struct AxBytes<'a>(pub &'a [u8]);

/// # Safety
/// `h` must be a live Axiom `String` handle, borrowed for the call only.
pub unsafe fn ax_bytes<'a>(h: Word) -> &'a [u8] {
    let s = h as *const AxStr;
    core::slice::from_raw_parts((*s).ptr, (*s).len as usize)
}

/// Rust-owned bytes handed to Axiom. The header box and the payload are
/// two allocations and `ax_abi_slice_free` reclaims BOTH.
#[repr(C)]
pub struct Slice { pub ptr: *const u8, pub len: i64 }

impl Slice {
    pub fn from_vec(v: __rt::Vec<u8>) -> Word {
        let b = v.into_boxed_slice();
        let len = b.len() as i64;
        let ptr = Box::into_raw(b) as *const u8;
        Box::into_raw(Box::new(Slice { ptr, len })) as Word
    }
}

/// `value` is NEVER owned by the Outcome (§6). `err` is.
#[repr(C)]
pub struct Outcome { pub ok: i64, pub value: Word, pub err: Slice }

extern "C" { pub fn axiom_retain(h: Word); pub fn axiom_release(h: Word); }

/// No-return trap for a boundary that has no error channel (C6).
pub fn abort_boundary(_sym: &str) -> ! { core::intrinsics::abort() }
```

The fixed accessor symbols every bridge shares, so no Axiom `cast` is ever required to open a `Slice` or an `Outcome`. **The frees reclaim the payload, which the previous draft's did not** — its `ax_abi_slice_free` dropped a 16-byte header and leaked the bytes on every single call, and MM-FFI-3 guarantees nothing on the Axiom side would ever notice:

```rust
#[no_mangle] pub extern "C" fn ax_abi_slice_ptr(s: Word) -> i64 {
    unsafe { (*(s as *const Slice)).ptr as i64 }
}
#[no_mangle] pub extern "C" fn ax_abi_slice_len(s: Word) -> i64 {
    unsafe { (*(s as *const Slice)).len }
}
#[no_mangle] pub extern "C" fn ax_abi_slice_free(s: Word) -> i64 {
    if s == 0 { return 0; }
    unsafe {
        let hdr = Box::from_raw(s as *mut Slice);          // the header
        if !hdr.ptr.is_null() && hdr.len > 0 {
            let payload = core::slice::from_raw_parts_mut(
                hdr.ptr as *mut u8, hdr.len as usize);
            drop(Box::from_raw(payload as *mut [u8]));     // the bytes
        }
        drop(hdr);
    }
    0
}
#[no_mangle] pub extern "C" fn ax_abi_outcome_is_ok(o: Word) -> i64 {
    unsafe { (*(o as *const Outcome)).ok }
}
#[no_mangle] pub extern "C" fn ax_abi_outcome_value(o: Word) -> i64 {
    unsafe { (*(o as *const Outcome)).value }
}
#[no_mangle] pub extern "C" fn ax_abi_outcome_err(o: Word) -> i64 {
    unsafe { &(*(o as *const Outcome)).err as *const Slice as i64 }
}
#[no_mangle] pub extern "C" fn ax_abi_outcome_free(o: Word) -> i64 {
    if o == 0 { return 0; }
    unsafe {
        let b = Box::from_raw(o as *mut Outcome);
        if !b.err.ptr.is_null() && b.err.len > 0 {
            let msg = core::slice::from_raw_parts_mut(
                b.err.ptr as *mut u8, b.err.len as usize);
            drop(Box::from_raw(msg as *mut [u8]));
        }
        // b.value is not owned here (§6). Do not touch it.
        drop(b);
    }
    0
}
```

#### 11b. `#[axiom::export]`

Generates the `extern "C"` shim, the marshalling, the C6 panic barrier, and one ABI record. Given

```rust
#[axiom::export(symbol = "ax_text_to_upper", utf8 = "lossy")]
pub fn to_upper(s: &str) -> String { s.to_uppercase() }
```

it emits, in shape:

```rust
#[no_mangle]
pub extern "C" fn ax_text_to_upper(a0: axiom_abi::Word) -> axiom_abi::Word {
    let call = || {
        let __b = unsafe { axiom_abi::ax_bytes(a0) };
        let a0 = ::alloc::string::String::from_utf8_lossy(__b);
        to_upper(&a0)
    };
    #[cfg(all(feature = "std", not(panic = "abort")))]
    let r = ::std::panic::catch_unwind(::core::panic::AssertUnwindSafe(call));
    #[cfg(not(all(feature = "std", not(panic = "abort"))))]
    let r: ::core::result::Result<_, ()> = ::core::result::Result::Ok(call());

    match r {
        Ok(v)  => axiom_abi::Slice::from_vec(v.into_bytes()),
        Err(_) => axiom_abi::abort_boundary("ax_text_to_upper"),
    }
}
```

Three corrections to the previous draft's expansion, each of which stopped it compiling or working:

- **Paths.** `$crate::__rt::Box` / `::alloc::…` throughout, never `::std::…` — otherwise the expansion cannot appear in a `#![no_std]` bridge, which is the tier example 4 uses and the tier the zero-undefined-symbols measurement belongs to.
- **The panic gate.** `#[cfg(panic = "abort")]` is a real, per-profile-correct predicate. `CARGO_CFG_PANIC` is set for **build scripts**, not for proc-macro expansion, so a macro reading it reads nothing and takes the wrong branch — emitting `catch_unwind` into a no_std bridge, where it does not resolve. `catch_unwind` also needs std, hence the conjunction. Both branches satisfy C6: one converts the unwind, the other cannot unwind at all.
- **UTF-8.** `from_utf8_lossy` here because the attribute asked for it; the default `checked` emits `core::str::from_utf8` and promotes the return to `Outcome` (§4b).

The ABI record. A fixed array length is not something a proc-macro can write for a variable-length JSON record — the draft's `[u8; 96]` held an 83-byte literal and is `expected [u8; 96], found [u8; 83]`. The macro emits a const-length copy instead, which is const-evaluable and cannot be wrong:

```rust
const __AXIOM_ABI_REC_0: &[u8] =
    br#"{"sym":"ax_text_to_upper","params":[{"ty":"String","words":1}],"ret":"Slice","eff":["Foreign","IO"]}"#;

#[used]
#[cfg_attr(target_vendor = "apple", link_section = "__DATA,__axiom_abi")]
#[cfg_attr(not(target_vendor = "apple"), link_section = ".axiom_abi")]
static __AXIOM_ABI_0: [u8; __AXIOM_ABI_REC_0.len()] = {
    let mut out = [0u8; __AXIOM_ABI_REC_0.len()];
    let mut i = 0;
    while i < out.len() { out[i] = __AXIOM_ABI_REC_0[i]; i += 1; }
    out
};
```

Note `"words"` in the record: §4a's word count is written here by the side that computed it, and bindgen reads it rather than re-deriving it. That is what makes the arity of the emitted `declare` and the arity of the real symbol the same fact rather than two agreeing guesses.

#### 11c. `#[axiom::opaque]` and `#[derive(AxiomRecord)]`

```rust
#[axiom::opaque(name = "Sha256", free = "ax_sha2_free")]
pub struct Hasher(sha2::Sha256);
```

emits an `impl` of a private `IntoHandle`/`FromHandle` pair over `Box::into_raw`/`Box::from_raw` — spelled `$crate::__rt::Box` — plus

```rust
#[no_mangle]
pub extern "C" fn ax_sha2_free(h: axiom_abi::Word) -> axiom_abi::Word {
    if h != 0 { unsafe { drop(axiom_abi::__rt::Box::from_raw(h as *mut Hasher)); } }
    0
}
```

and an ABI record with `"opaque":"Sha256"`.

`#[derive(AxiomRecord)]` maps a Rust struct to an Axiom `struct` **field-wise, never wholesale**: one `ax_<ty>_<field>` accessor export per field and one `ax_<ty>_new` taking the fields as words. The Axiom side's generated wrapper builds the record with the ordinary `(Name f1 f2)` constructor so that `shapeBits` (`self_host/codegen.ax:6190-6200`) computes the reference map exactly as it does for any other construction site. Rust never writes a shape word.

#### 11d. Bindgen and drift

`axiom-bindgen --bridge rust/bridges/sha2 --out stdlib/ffi/Sha2.ax` builds the bridge with cargo, reads the `__axiom_abi` section out of the resulting archive with the `object` crate, and emits a checked-in `.ax`. Reading the *compiled archive* rather than parsing sources is the point: what the linker will see is what the binding describes, and `cfg`-gated exports cannot drift out from under it. It never rewrites `stdlib/ffi/Abi.ax` (§6).

Drift is caught in three independent places, because each catches something the others cannot:

1. **Source drift** — `scripts/check-ffi-bindings.sh` regenerates every binding into a temp dir and diffs. Catches a hand-edited `.ax`.
2. **Binary drift** — every bridge exports `ax_abi_digest_<lib>() -> i64`, FNV-1a 64 over the sorted ABI record set, using the same hash `symbols.ax:57-70` already computes for AXSYM `@nid`. The generated `.ax` bakes the digest in as a literal and exposes `(pub :: sha2AbiDigestOk Bool)` — a **bare result type**, per §4's `()` rule and `(pub :: vecNew Int)`, not `(-> () Bool)`, which would name a type with no value in argument position. Catches a stale `.a` that a source diff cannot see. **Known gap: it is not automatic.** Axiom has no module initializer, so nothing calls it unless a program or a gate does. The natural hook is `@main` before `@__axiom_user_main` (`self_host/codegen.ax:1994-2001`); adding it costs one foreign call ahead of user code, which is acceptable *only* for programs that already have an extern block — a program with none must stay byte-identical.
3. **Allowlist drift** — `ffi.lock`, below.

#### 11e. `ffi.lock`, and why it has two symbol lists

The previous draft had a single `symbols` list used for two contradictory jobs, and neither worked:

- "`nm -g` on the archive must **equal** `symbols`" cannot pass. Measured on this machine, `nm -g rust/target/release/libaxiom_demo.a` is 1795 lines and 562 defined globals for **8** intended exports; the rest are `__RNv…` Rust manglings plus `addr2line` and `alloc` internals. Mach-O also prefixes every symbol with `_`, which the lock file omitted.
- `symbols` lists what the bridge *exports*, and exports are **defined** in the linked executable — they never appear in `nm -u`. So "`nm -u` minus the union of `symbols`" subtracted nothing, and the std tier's 188 undefined symbols were governed by a `std = true` boolean alone. A boolean is blanket permission, which is the shape MM-FFI-5's fourth requirement exists to replace.

So the lock file carries **two** lists, checked two different ways:

```toml
[[library]]
name          = "axiom_sha2"
crate         = "rust/bridges/sha2"
archive       = "rust/target/release/libaxiom_sha2.a"
digest        = -6172840193882641077
symbol_prefix = "_"            # Mach-O; empty on ELF

# What Axiom may call. Checked by CONTAINMENT against `nm -g <archive>`
# after stripping `symbol_prefix` -- never equality; the archive has
# hundreds of Rust-internal globals and always will.
exports = ["ax_sha2_new", "ax_sha2_update", "ax_sha2_finish", "ax_sha2_free",
           "ax_abi_slice_ptr", "ax_abi_slice_len", "ax_abi_slice_free",
           "ax_abi_digest_axiom_sha2"]

# The permitted external symbols -- MM-FFI-5 requirement 4, enumerated.
# Empty here: this bridge is no_std with panic="abort" and imports nothing.
imports = []
```

`scripts/check-ffi-allowlist.sh`, for a program whose module set contains at least one `extern` or `export` block:

1. Every symbol named by a `(symbol …)` clause is in some reachable library's `exports`, else `AX5002`.
2. `exports ⊆ nm -g archive`, prefix-stripped. Containment, because 562 ≫ 8.
3. `nm -u executable  ⊆  ⋃ imports  ∪  platform-unavoidable`. This is the enumeration MM-FFI-5 asks for, and it is the check the boolean was standing in for.
4. A library whose `imports` is empty must have an archive whose own `nm -u` is empty. That is the no_std tier, and it is now *derived and verified* rather than asserted.

The tier is therefore a consequence, not a declaration: `std = true` is gone. The measured numbers make both tiers real — a `no_std` bridge gives an executable with **zero** undefined symbols, so its allowlist run is as strict as freestanding; a std bridge gives 188, fourteen of them on `check-freestanding.sh`'s own forbidden list (`scripts/check-freestanding.sh:53-71`). A std bridge must **enumerate all 188**, generated by bindgen from `nm -u` of the archive and checked in, so that the 189th shows up in a diff with a name on it.

The driver appends `archive` **as a path**, not as `-l`, to the existing `cc obj -o out` argument vector (`self_host/driver.ax:222-231`), so no `-L` is needed and the link stays hermetic — which is what keeps `check-reproducible.sh` and invariant I12 honest.

`check-freestanding.sh` runs unchanged, including its final `foreign`-is-`AX2004` probe, over every program whose module set contains no `extern` and no `export` block. A program with none must be byte-identical to today.

---

### Worked examples

#### 1 — Pure scalar

```rust
// rust/bridges/num/src/lib.rs
#![no_std]
use axiom::export;

#[axiom::export(symbol = "ax_num_isqrt", effects = [])]
pub fn isqrt(n: i64) -> i64 {
    if n < 0 { return -1; }
    let mut x = n as u64; let mut y = (x + 1) / 2;
    while y < x { x = y; y = (x + n as u64 / x) / 2; }
    x as i64
}
```

```scheme
; stdlib/ffi/Num.ax  -- GENERATED by axiom-bindgen; do not edit.
; library axiom_num  digest 0x1f0c2ab4d7e95531
(pub extern "axiom_num"
  (isqrt :: (-> Int Int) (symbol "ax_num_isqrt") (effects ())))
```

Direct-usable, so bindgen emits the block `pub` with no wrapper at all. Use site:

```scheme
(import ffi.Num (isqrt))

(:: main Int)
;@axiom:effect(foreign)
(fn (main) { (println (show (isqrt 2000000))) 0 })
```

**What the fixpoint actually produces.** `isqrt`'s own `FnEnt` carries `{Foreign}` and nothing else, which is what `(effects ())` bought. `main` infers `{Foreign, IO}`: `println` reaches `__syscallN`, `isSyscallPrim` (`self_host/typecheck.ax:5029-5034`) classifies that as `IO`, and `walkCallHead` unions the whole callee `FnEnt` word 5 into the caller (`4935-4937`). The `;@axiom:effect(foreign)` claim validates anyway, because `axtagUnsupported` (`6807-6831`) reports only a claim the body does **not** support — never a body that performs more than it claims. A fixture written against "`main` infers `Foreign` and not `IO`" would fail; this one does not.

Emitted IR gains exactly one line, `declare i64 @ax_num_isqrt(i64) #0`, and one call.

#### 2 — String in, bytes out

```rust
#[axiom::export(symbol = "ax_text_to_upper", utf8 = "lossy")]
pub fn to_upper(s: &str) -> String { s.to_uppercase() }
```

`utf8 = "lossy"` is chosen deliberately and costs something: invalid bytes become U+FFFD instead of an error. The default, `checked`, would promote the return type to `Outcome` (§4b) and the Axiom declaration with it. Either is legal; the generated file records which.

```scheme
; stdlib/ffi/Text.ax  -- GENERATED
(import Str)
(import ffi.Abi (sliceFree sliceToStr))     ; `Slice` itself needs no import: it is built in

(extern "axiom_text"
  (toUpperRaw :: (-> String Slice) (symbol "ax_text_to_upper")))

(pub :: toUpper (-> String String))
;@axiom:effect(foreign)
(pub fn (toUpper s)
  (let ((sl (toUpperRaw s)))
    (let ((out (sliceToStr sl)))
      { (sliceFree sl) out })))
```

The extern block is private and only `toUpper` is `pub`, so no caller can reach a raw handle. `sliceToStr` is `ffi.Abi`'s single definition (§6) — under the previous draft it was called here and in two other examples and existed nowhere, and could not have been written once, because each module's `(opaque Slice …)` was a different type by `tyCompat`'s name rule.

`strAlloc` inside `sliceToStr` reserves `n + 1` and the allocator zeroes, so MM-VAL-7's NUL terminator is already in place after the copy — nothing here maintains it by hand. Rust borrows the Axiom string for the duration of the call only and does not retain it, satisfying C7 with no `axiom_retain`.

#### 3 — Fallible

```rust
#[axiom::export(symbol = "ax_num_parse")]
pub fn parse(s: &str) -> Result<i64, String> {
    s.trim().parse::<i64>().map_err(|e| e.to_string())
}
```

The macro sees `Result<_, String>` and emits an `Outcome`-returning shim. Because the parameter is `&str` with the default `checked` policy, an invalid-UTF-8 input lands on the same `Err` side rather than being undefined behaviour.

```scheme
; stdlib/ffi/Num.ax (continued)  -- GENERATED
(import Err)
(import ffi.Abi (outcomeIsOk outcomeInt outcomeErr outcomeFree sliceToStr))

(extern "axiom_num"
  (parseRaw :: (-> String Outcome) (symbol "ax_num_parse")))

(:: errForeign Int) (fn (errForeign) 90)

(pub :: parseInt (-> String (Result Int Error)))
;@axiom:effect(foreign)
(pub fn (parseInt s)
  (let ((o (parseRaw s)))
    (if (outcomeIsOk o)
        (let ((v (outcomeInt o))) { (outcomeFree o) (Ok v) })
        (let ((m (sliceToStr (outcomeErr o))))
          { (outcomeFree o) (Err (mkError errForeign m)) }))))
```

The block declares no opaques at all now — `Outcome` and `Slice` are built in, and their accessors come from `ffi.Abi`. The previous draft's version of this example named `Slice` in a signature without declaring it in the block (its own `AX3036` rule), gave that `Slice` no `(drop …)` for `AX3038`, and passed `outcomeValue`'s `Int` to a `sliceToStr` that elsewhere took a `Slice` — a mismatch `tyCompat` refuses on the name. `outcomeErr` returns `Slice` and `outcomeInt` returns `Int`, from two items over one symbol, which is exactly what §5d's producer rule is for.

**Stated cost:** one Rust `Box` for the `Outcome` and one for the message per fallible call, even on the success path — and `ax_abi_outcome_free` reclaims both, which the previous draft's did not. Where that matters, declare the raw symbol yourself with a sentinel discipline you choose; the extern form describes symbols and will not stop you.

#### 4 — Opaque handle with constructor and destructor

```rust
// rust/bridges/sha2/src/lib.rs   crate-type = ["staticlib"], panic = "abort"
#![no_std]
extern crate alloc;
use sha2::{Digest, Sha256};

#[axiom::opaque(name = "Sha256", free = "ax_sha2_free")]
pub struct Hasher(Sha256);

#[axiom::export(symbol = "ax_sha2_new", effects = [])]
pub fn new() -> Hasher { Hasher(Sha256::new()) }

#[axiom::export(symbol = "ax_sha2_update", effects = [])]
pub fn update(h: &mut Hasher, data: &[u8]) -> i64 { h.0.update(data); 0 }

#[axiom::export(symbol = "ax_sha2_finish", effects = [])]
pub fn finish(h: Hasher) -> [u8; 32] { h.0.finalize().into() }
```

**`&[u8]` is two words** by §4a — base pointer, then length in elements — so `ax_sha2_update` is a **three**-word symbol and the Axiom declaration says so. The previous draft declared it `(-> Sha256 String Int)`, two words against a three-word symbol; nothing in the compiler, the linker or LLVM would have caught that, and the shim would have read a length register nobody set.

```scheme
; stdlib/ffi/Sha2.ax  -- GENERATED
(import Str)
(import ffi.Abi (slicePtr sliceLen sliceFree bytesToHex))

(extern "axiom_sha2"
  (opaque Sha256 (drop sha256Free))
  (sha256New       :: Sha256                  (symbol "ax_sha2_new")    (effects ()))
  (sha256UpdateRaw :: (-> Sha256 Int Int Int) (symbol "ax_sha2_update") (effects ()))
  (sha256Finish    :: (-> Sha256 Slice)       (symbol "ax_sha2_finish") (effects ()))
  (sha256Free      :: (-> Sha256 Int)         (symbol "ax_sha2_free")   (effects ())))

(pub :: sha256Hex (-> String String))
;@axiom:effect(foreign)
(pub fn (sha256Hex s)
  (let ((h sha256New))
    {
      (sha256UpdateRaw h (strData s) (strLen s))
      (let ((d (sha256Finish h)))
        (let ((hex (bytesToHex (slicePtr d) (sliceLen d))))
          { (sliceFree d) hex }))
    }))
```

`sha256New` is nullary and therefore declared with a bare result type and referenced bare, exactly as `vecNew` is — and §10's `isNullaryFn` row is what makes that reference lower to `call i64 @ax_sha2_new()` instead of the bare register `%sha256New` that `opt` refuses (MM-EXEC-15a). The declared result `Sha256` is also the sanctioned producer of §5d: this is the only construct in the language that can make a value of an opaque type.

`sha256Finish` consumes the handle on the Rust side (`h: Hasher` by value, so the shim reclaims the Box), which is why no `sha256Free` appears in the wrapper — and which is the sharpest illustration of the known gap in §5f: nothing in Axiom knows that `h` is dead after that line, and using it again is a use-after-free that the checker will not catch. Bindgen therefore emits a `pub fn` that never lets a handle escape, and a hand-written block that does so is on its own.

This bridge is `no_std` with `panic = "abort"`, so the linked executable has zero undefined symbols, `imports = []` in `ffi.lock`, and its allowlist run is as strict as `check-freestanding.sh`.

#### 5 — A collection crossing the boundary

Axiom→Rust by pointer and length; Rust→Axiom by `Slice` plus an Axiom-side rebuild. Neither direction moves an aggregate by value.

```rust
#[axiom::export(symbol = "ax_stats_sum", effects = [])]
pub fn sum(xs: &[i64]) -> i64 { xs.iter().fold(0i64, |a, b| a.wrapping_add(*b)) }

#[axiom::export(symbol = "ax_stats_sorted")]
pub fn sorted(xs: &[i64]) -> Vec<i64> { let mut v = xs.to_vec(); v.sort_unstable(); v }
```

`&[i64]` is two words by §4a — the same rule `&[u8]` follows in example 4, which is the point of having written the rule down — so the shims are `ax_stats_sum(i64 ptr, i64 len) -> i64` and `ax_stats_sorted(i64 ptr, i64 len) -> i64`, with `len` in **elements**.

```scheme
; stdlib/ffi/Stats.ax  -- GENERATED
(import Vec) (import Mem)
(import ffi.Abi (slicePtr sliceLen sliceFree))

(extern "axiom_stats"
  (sumRaw    :: (-> Int Int Int)   (symbol "ax_stats_sum")    (effects ()))
  (sortedRaw :: (-> Int Int Slice) (symbol "ax_stats_sorted")))

; word 2 of a Vec is the element block (stdlib/Vec.ax:61-75); the
; module's own comment says a caller entitled to the pointer reads it.
(:: vecWords (-> Int Int))
(fn (vecWords v) (memGetWord v 2))

(pub :: intVecSum (-> Int Int))
;@axiom:effect(foreign)
(pub fn (intVecSum v) (sumRaw (vecWords v) (vecLen v)))

(pub :: intVecSorted (-> Int Int))
;@axiom:effect(foreign)
(pub fn (intVecSorted v)
  (let ((sl (sortedRaw (vecWords v) (vecLen v))))
    (let ((n (/ (sliceLen sl) 8))
          (p (slicePtr sl))
          (out (vecWithCapacity (vecLen v))))
      {
        (intVecFill out p n 0)
        (sliceFree sl)
        out
      })))

(:: intVecFill (-> Int Int Int Int Int))
(fn (intVecFill out p n i)
  (if (>= i n) out
      { (vecPush out (__load64 p i)) (intVecFill out p n (+ i 1)) }))
```

`sliceLen` answers **bytes** for a `Slice` — the ABI struct's `len` is a byte count — so the `/ 8` is the element count and is not decoration.

The `Vec` handle itself never crosses. That is the design, not a limitation being worked around: a `Vec` is an Axiom heap block with a count and a shape word, and letting Rust hold one would put C7's retain/release obligation on every element. Passing `(ptr, len)` puts the borrow inside one call, where it cannot outlive anything.

**Honest limit:** this works because `Vec` elements are untyped `Int` handles (`vecGet :: (-> Int Int a)`, `stdlib/Vec.ax:104`). A `Vec` of `String` handed to `sumRaw` type-checks — `tyCompat` sees `Int` against `Int` — and adds pointers. Nothing in this design fixes that, because nothing in this design can: the container is untyped by decision, and three attempts to change that were withdrawn. The generated wrapper's name is the only documentation.

#### 6 — A real crate: `serde_json`

```rust
// rust/bridges/json/src/lib.rs   crate-type = ["staticlib"]
// std bridge: serde_json needs an allocator and formatting.
use serde_json::Value;

#[axiom::opaque(name = "JsonDoc", free = "ax_json_free")]
pub struct Doc(Value);

#[axiom::export(symbol = "ax_json_parse")]
pub fn parse(src: &str) -> Result<Doc, String> {
    serde_json::from_str::<Value>(src).map(Doc).map_err(|e| e.to_string())
}

#[axiom::export(symbol = "ax_json_get_str")]
pub fn get_str(d: &Doc, key: &str) -> Option<String> {
    d.0.get(key)?.as_str().map(|s| s.to_owned())
}

#[axiom::export(symbol = "ax_json_get_i64")]
pub fn get_i64(d: &Doc, key: &str) -> Option<i64> {
    d.0.get(key)?.as_i64()
}
```

`Option<T>` lands on the same `Outcome` protocol as `Result<T, String>`, with `ok = 0` for `None` and a zero-length error slice. In both, `Outcome.value` is a transferred handle the Axiom side owns, and `ax_abi_outcome_free` does not touch it (§6).

```scheme
; stdlib/ffi/Json.ax  -- GENERATED by axiom-bindgen
; library axiom_json  digest 0x7bd41c02e9a6f118
(import Err)
(import ffi.Abi (outcomeIsOk outcomeInt outcomeSlice outcomeErr outcomeFree sliceToStr))

(extern "axiom_json"
  (opaque JsonDoc (drop jsonFree))
  (jsonParseRaw  :: (-> String Outcome)         (symbol "ax_json_parse"))
  (jsonGetStrRaw :: (-> JsonDoc String Outcome) (symbol "ax_json_get_str"))
  (jsonGetIntRaw :: (-> JsonDoc String Outcome) (symbol "ax_json_get_i64"))
  (jsonFree      :: (-> JsonDoc Int)            (symbol "ax_json_free"))
  ; The producer of §5d: same symbol as `outcomeInt`, different declared
  ; RESULT, therefore the one legal route from an Outcome to a JsonDoc.
  ; Emits a `declare` byte-identical to ffi.Abi's, so dedup holds.
  (jsonOutcomeDoc :: (-> Outcome JsonDoc) (symbol "ax_abi_outcome_value") (effects ())))

(pub :: jsonParse (-> String (Result JsonDoc Error)))
;@axiom:effect(foreign)
(pub fn (jsonParse src)
  (let ((o (jsonParseRaw src)))
    (if (outcomeIsOk o)
        (let ((d (jsonOutcomeDoc o))) { (outcomeFree o) (Ok d) })
        (let ((m (sliceToStr (outcomeErr o))))
          { (outcomeFree o) (Err (mkError errJsonParse m)) }))))

(pub :: jsonGetStr (-> JsonDoc String (Option String)))
;@axiom:effect(foreign)
(pub fn (jsonGetStr d key)
  (let ((o (jsonGetStrRaw d key)))
    (if (outcomeIsOk o)
        (let ((sl (outcomeSlice o)))
          (let ((s (sliceToStr sl)))
            { (sliceFree sl) (outcomeFree o) (Some s) }))
        { (outcomeFree o) None })))
```

**Two things this rewrite fixes, and they were not cosmetic.** The previous draft called `jsonDocOf` — a helper that is called in the example, defined nowhere, and *cannot be written*: `(cast JsonDoc d)` is `AX3037`, an identity `(:: jsonDocOf (-> Int JsonDoc))` is `AX3004` by `checkDeclaredReturn` once `JsonDoc` is repr-scalar (§5b), and a tyvar-typed accessor is illegal by C3. `jsonOutcomeDoc` is the sanctioned producer instead. And it wrote `(sliceToStr (outcomeValue o))`, handing an `Int` to a function taking a `Slice`; `tyCompat` refuses that on the name (`self_host/typecheck.ax:216-219`), so one of the two spellings had to go — `outcomeSlice` is the one that survives, and the slice it returns is freed before the `Outcome` is.

Use site:

```scheme
(import ffi.Json (jsonParse jsonGetStr jsonFree JsonDoc))
(import Err)

(:: main Int)
;@axiom:effect(foreign)
(fn (main)
  (match (jsonParse "{\"name\":\"axiom\",\"v\":1}")
    ((Err e) { (println (errorText e)) 1 })
    ((Ok d)
     {
       (match (jsonGetStr d "name")
         ((Some n) (println n))
         ((None)   (println "no name")))
       (jsonFree d)
       0
     })))
```

**What this example is really showing.** `serde_json` is a std crate, so the linked executable carries 188 undefined symbols, fourteen of them on `check-freestanding.sh`'s forbidden list — `malloc`, `free`, `memcpy`, `strlen` and the rest — plus `_Unwind_*`, `_tlv_bootstrap` and dyld's Mach-O machinery. That is exactly the trade the opt-in relaxation is for and exactly why the relaxation cannot be silent. Under §11e those 188 are **enumerated** in this library's `imports` array, generated from `nm -u` of the archive and checked in, so the 189th arrives as a named line in a diff. There is no `std = true` boolean any more, because a boolean is the blanket permission MM-FFI-5 requirement 4 exists to replace. The `no_std` sha2 bridge in example 4 has `imports = []` and stays at zero undefined symbols; both are legal, and the file records which one you chose and what it cost.

`jsonParse` returns an opaque in a `Result`, so `AX3038` requires the `(drop jsonFree)` clause, and `jsonFree` must be called by hand. There is no way to forget it that the compiler will catch. That is the gap of §5f landing in the most realistic example in the set, which is where it belongs.

#### 7 — The other direction, with C7

See §9c for the full listing. The shape, condensed:

```scheme
; demo.ax
(export "axiom_demo" (greet (symbol "ax_demo_greet")))

(pub :: greet (-> String String))
(pub fn (greet who) (strConcat "hello, " who))
```

emits, alongside everything else the module already emits:

```llvm
define i64 @ax_demo_greet(i64 %p0) #0 {
  %t0 = call i64 @greet(i64 %p0)
  ret i64 %t0
}
```

and `axiom build --emit-staticlib` renames `@main` to `@axiom_rt_init` and `ar rcs`es the object. The Rust host calls `axiom_rt_init(argc, argv)` once, on one thread (MM-PAR-1), and any handle it keeps past a call is wrapped in `Held` — `axiom_retain` on construction, `axiom_release` in `Drop`. A handle it does not wrap is borrowed for one call and no longer.

---

### Known gaps, stated rather than papered over

1. **No automatic destructor.** `(drop f)` records; it does not run. A foreign handle is repr-scalar in both evidence tables and so is invisible to `axiom_release`. Closing this needs a finalizer table in the emitted runtime and a mapped one-word box per handle — a runtime feature, not a syntax feature.
2. **`cast` is the narrower hole it was, and closing it is a checker change of unknown corpus cost.** `AX3037` is specified; whether `cast` is checkable at every site it appears has not been probed here. It is less load-bearing than the previous draft implied, because §5b's `checkDeclaredReturn` rule independently closes the identity-wrapper route, so a weak `AX3037` degrades the opaque type from "cannot be punned" to "is not punned by accident, and cannot be laundered through a declaration" — still MM-FFI-5 requirement 1, still weaker than a full refusal.
3. **`tyIsReprScalar` becomes dynamic, and it buys less than was claimed.** It is a three-literal predicate today (`self_host/typecheck.ax:7095-7096`) and must consult `tcOpaques`. Its single call site is `checkDeclaredReturn` (`7020`), so the sweep can only report at declared-return sites naming an opaque, and no corpus program names one — expected cost **zero**. The `String` sweep's 145 diagnostics across 117 of 261 files is **not** a predictor and citing it was misleading: that was an existing, universally imported name, and all 145 traced to three declarations. The sweep must still be **run and counted** before the change lands, because a dynamic predicate can misfire in ways a three-literal one cannot.
4. **`fldClass` and `evClassOf` are the silent ones, and `evClassOf` is the dangerous one.** An opaque name missing from `scalarTyName` collapses the enclosing record's reference map to leaf and leaks every other field, with no diagnostic at any stage — survivable. An opaque name that *reaches* `tcDatas`/`tcStructs` makes `evClassOf` answer **reference**, and the release walk then does `load i64 [h-16]` and `store [h-16], c-1` on a Rust `Box` pointer, which clears the `< 4096` immediates guard (`self_host/codegen.ax:2292-2310`) — a use-after-free in the Rust heap, silent until it is not. The dedicated `tcOpaques` table of §5c exists for exactly this, and `self_host/typecheck.ax:583-585` states the asymmetry: "a missed bit under-reclaims, a wrong bit is a use-after-free."
5. **`(effects ())` is unverifiable.** Nothing checks that a Rust function claiming no I/O performs none. The claim is documentation with linker consequences, and the drift check compares the Rust attribute against the `.ax` clause — which catches disagreement between the two files, not disagreement between the clause and the truth.
6. **UTF-8 validity is a Rust-side obligation with no Axiom-side enforcement.** §4b routes `&str` through `core::str::from_utf8`, which is sound; but nothing stops a hand-written extern block declaring `String` against a symbol whose shim uses the unchecked form. The checker cannot see inside the archive. The macro is the only place this is enforced, and only for symbols the macro generated.
7. **Container element types are still unchecked.** Example 5's `intVecSum` will happily sum a `Vec` of `String` handles. This is inherited from the deliberate untypedness of containers, and no FFI design can fix it from this side.
8. **The digest check has no automatic trigger.** Axiom has no module initializer; catching a stale `.a` at run time requires a hook in `@main`, which has a cost and has not been agreed.
9. **The export direction has no type export.** §9 exports functions only. Handing Rust an Axiom `data` value to match on would mean Rust reading a tag word and a shape word, which §4's aggregate rule forbids; `#[derive(AxiomRecord)]`'s field-wise accessors are the sanctioned substitute, and there is no equivalent going the other way in v0.
10. **One thread, and the compiler will not say so.** MM-PAR-1 admits no threads and the bump allocator has no lock (I11). A Rust host that calls exported symbols from two threads corrupts allocator state, and nothing in the type system, the gates, or the linker will notice. It is a sentence in this specification and a comment in the generated header, and that is all the enforcement there is.
---

## 7. Ownership, Lifetimes, and Memory Safety Across the Boundary

### 0. What this section is actually deciding

Axiom's reclamation is not a tracing collector that can be taught to ignore foreign words. It is a **write**, emitted inline, driven by a bitmap that a *compile-time* classifier fills in. `@axiom_release` does not ask whether an address is one of ours; it subtracts 16 from the word it was handed and stores. Every soundness question below reduces to two:

1. **Can a Rust-owned address ever reach `@axiom_retain` or `@axiom_release`?** If yes, Axiom writes into Rust's heap and can file Rust's memory onto its own free list.
2. **Can an Axiom-owned address outlive the share that keeps it alive, while Rust still holds it?** If yes, Rust reads a block that `axiom_alloc` has already re-issued.

There is a third question that the first draft of this section got wrong, and it deserves equal billing because it is the one that turns *correct-looking* code into a use-after-free:

3. **Can any FFI-side operation drive a count to zero?** Under today's partial ARC most live values sit at count **0**, so a `+1` followed by a `−1` is not the identity — it is a `free`. Any FFI protocol that ends in a decrement reaching zero is unsound no matter how carefully balanced it is (§5.2, §5.3).

Everything else — borrow views, RAII, destructors, arenas, cycles, threads — is machinery for keeping those three answers "no". This section is written so that an implementer can check each rule against emitted IR rather than against intent.

The rules continue the repo's existing `MM-FFI-*` series (docs/memory-model.md §7). `MM-FFI-5 (P)` is the promise these discharge; `MM-FFI-1 (R)`'s blanket refusal becomes conditional on the allowlist gate, exactly as `MM-FFI-5` requirement 4 anticipates. Status letters follow the repo's convention: every rule here is **(P)** — none is implemented — and each additionally carries its enforcement class.

**A note on the Axiom examples.** Every Axiom snippet below writes an extern as `(extern name (-> ...))`. That keyword is a placeholder: the actual surface syntax belongs to the declaration-forms section, and only the *semantics* are fixed here. What is **not** optional is that some declaration form exists. A bare `(:: rustAdd (-> Int Int Int))` with an AXTAG comment and no `fn` is **`AX3015` today** — verified: `error[AX3015]: 'rustAdd' has a signature but no definition ... no 'fn' defines 'rustAdd'`, exit 1 — because `defIdxBuild` (typecheck.ax:1114-1132) indexes only `TAG_D_FN` nodes with `nodeVis == 1`. Two consequences the examples silently assume:

- The extern's definer must be visible to `defIdxBuild`, or every `::` over it draws a false `AX3015`.
- The extern's `FnEnt` **MUST** register with `paramCount >= 0`. `repArity` (typecheck.ax:2728-2733) answers `-1` for a non-`fn` definer, and a `-1` answer *silently disables* the `AX3013` bare-value refusal and the `AX3009`/`AX3013` saturation check. The retired `foreign` used `paramCount -1`; repeating that is how an extern becomes callable with the wrong arity and no diagnostic.

---

### 1. Three populations, one word

Every value at the boundary is one i64 (C2, `I1`). The word carries no tag (`MM-VAL-2`), so *population membership is a static fact about the declared type and nothing else*. There are three:

| Population | Produced by | Header at −16/−8? | `axiom_retain`/`release` behaviour | Reclaimed by |
|---|---|---|---|---|
| **Counted** | `axiom_alloc` (codegen.ax:2046), i.e. every constructor cell, struct block, closure record, evidence record, `Str` header, container buffer | yes — count word written 0 at handout (codegen.ax:2242-2243), leaf shape word (codegen.ax:2245-2251) | correct *arithmetically*, but see §5.2: most of these are alive at count 0 | ARC at count 0 (codegen.ax:2353-2366), or an arena reset, or process exit |
| **Static** | string-literal globals: `@str_N` a `private unnamed_addr constant [n x i8]`, `@strhdr_N` a 5-word `private unnamed_addr constant` whose count word is `-1` (codegen.ax:1002-1023) | yes, but read-only | no-op — both read the count first and stop on the `-1` sentinel (codegen.ax:2280-2282, 2298-2299) | never; loader-resident |
| **Foreign** | Rust (`Box::into_raw`, a static slot table), the kernel (`argv`, syscall buffers), `mmap` the program made itself (`MM-FFI-2`) | **no** — there is nothing at −16 | **catastrophic** (see §2) | Rust, or the kernel, or never (`MM-FFI-3`) |

> **MM-FFI-6 (P, compiler-enforced).** Every word crossing the boundary **SHALL** belong to exactly one population, and the population **SHALL** be recoverable from the declared type alone at every site that can retain, release, or write a reference-map bit.
> *Rationale.* `MM-VAL-2` means no runtime discrimination is available; `fldClass` (codegen.ax:6159-6180) and `evClassOf` (typecheck.ax:587-613) are already the two places the compiler answers this question, and both answer from a type node.
> *Failure mode.* A population the classifiers cannot name falls to `fldClass`'s answer `1` (unclassifiable), which collapses the **entire block** to a leaf map (codegen.ax:6202-6206) — every *other* reference field in that block then leaks, permanently. Under-classification is not free; it is a leak proportional to the block's honest fields.

---

### 2. The sharpest hazard, executed line by line

This is the rule everything else exists to protect, so it is worth watching the emitted code do the damage. Suppose a Rust address `p` (say `0x600001a04020`) lands in a payload word whose map bit is set. The block dies; `@axiom_release`'s dead path (codegen.ax:2325-2352) walks the map and calls itself on `p`:

```llvm
entry:  %imm  = icmp slt i64 %h, 4096      ; p is not < 4096 → no skip
chk:    %hoff = add i64 %h, -16            ; 0x600001a04010 — inside Rust's heap
        %c    = load i64, ptr %cp          ; reads a Rust field as a refcount
        %stat = icmp eq i64 %c, -1         ; only -1 saves us, by accident
live:   %zero = icmp eq i64 %c, 0
dec:    %c1   = add i64 %c, -1
        store i64 %c1, ptr %cp             ; ← WRITES into Rust memory
```

If that stolen "count" happened to be 1, the walk continues:

```llvm
dead:   %shw  = load i64, ptr (h-8)        ; another Rust field, read as a shape word
        %map0 = lshr i64 %shw, 16          ; Rust data reinterpreted as a bitmap
walk:   ... %wval = load i64, ptr (h + 8*i)
        call void @axiom_release(i64 %wval) ; recurses into arbitrary Rust words
filechk:%bcnt = and i64 (lshr %shw, 1), 32767
push:   %pcls = lshr i64 %bcnt, 1
        store i64 %pbase, ptr @__axiom_slabs[%pcls]   ; ← Rust memory is now
                                                      ;   an Axiom free block
```

The last store is the end of the world: the next `axiom_alloc` of that size class pops it (codegen.ax:2093-2105) and hands **Rust's live allocation** to an Axiom constructor, after scrubbing it to zero on the handout path. There is no diagnostic, no crash at the point of error, and the symptom appears in unrelated code an arbitrary time later.

`@axiom_retain` is the same shape one step quieter: it always stores `c+1` at `p-16` unless those eight bytes read exactly `-1`.

> **MM-FFI-7 (P, compiler-enforced). The bitmap rule.** A payload word whose declared type is a foreign type **MUST** have its reference-map bit **clear** in the containing block's shape word, and **MUST NOT** be the argument of any emitted `@axiom_retain` or `@axiom_release` call.
> *Rationale.* Bit 16+base+i of the shape word (base 1 for data cells, 0 for structs — codegen.ax:6193-6199) is a *licence to dereference*. A foreign address has no header to dereference.
> *Failure mode.* Exactly §2: a write 16 bytes below a Rust object, followed by that object's memory entering `@__axiom_slabs` and being re-issued as an Axiom block. Memory-unsafe in both directions simultaneously.
> *Enforcement — stated as an invariant, not a site list.* **The implementation obligation is to register the foreign name in `scalarTyName` (codegen.ax:6133-6148) and `evScalarName` (typecheck.ax:542-557), because `fldClass` takes `cg` and `evClassOf` takes `tc` and every consumer routes through one of the two.** An earlier draft of this section named "four writers that must agree" and that enumeration was materially short — patching four call sites and missing the rest is exactly the failure this framing prevents. For orientation only, the *known* consumers are: `ctorShapeConst`/`shapeBits` (codegen.ax:6193-6222); the **second**, stamped/polymorphic shape writer that calls `fldClass` and `storeShapeAt` directly (codegen.ax:6404, 6413-6415); event 5's field store `emitSetF`, which emits **both** a retain on the new value and a release on the old, gated on `(== (fldClass cgB (nodeC fi)) 2)` (codegen.ax:4676, 4682, 4685); event 6's construction-time field retains via `fieldRetainCode` (codegen.ax:6601) consumed by `emitFieldStores` (codegen.ax:6613, 6615); the closure-capture retains (`retainParamCaps`, codegen.ax:3838); the handle/evidence-record retains and release (codegen.ax:4455, 4458, 4478); event 4's tail-boundary parameter retains (codegen.ax:3206); and `Mem.memSetWord`'s `__retainref` through `evClassOf` (stdlib/Mem.ax:203-207). This list is *not* the contract. The classifier registration is.

---

### 3. The foreign type and its classifiers

#### 3.1 What the type is

C4 requires a distinct opaque built-in. The design decision has three candidates, and the measured code eliminates two of them:

- **Reuse `TAG_T_PTR`** (`mkTPtr`, parser.ax:295, tag 37). **Rejected.** `fldClass` deliberately falls through to `1` for `TAG_T_PTR` (codegen.ax:6179, and the comment at codegen.ax:6128-6131 names `Ptr` as unclassifiable on purpose). Reusing it makes every block containing a foreign pointer a leaf — sound, but it silently leaks every honest reference sibling. `MM-FFI-6`'s failure mode, by construction.
- **Declare it in Axiom as `(data Foreign (MkForeign Int))`.** **Rejected, and this is the sharpest trap in the design.** `fldClass` asks `dataTyKnown` (codegen.ax:6150-6157) and answers **`2` — reference** — for *any* declared data or struct name; `evClassOf` does the same through `evDataTyKnown` (typecheck.ax:559-581). A foreign address in a field of a user-declared type would get its map bit **set**. This is §2 verbatim, reached by writing ordinary-looking Axiom.
- **A built-in nullary type constructor**, known to the scalar tables. **Chosen.**

> **MM-FFI-8 (P, compiler-enforced).** A foreign type **SHALL** be a **nullary** `TAG_T_CON` whose name is registered in a compiler-owned foreign-type set. It **MUST NOT** be a `data`, `struct`, alias, or applied type. The unnamed fallback spelling is `Foreign`; a binding generator **SHOULD** mint one distinct nullary name per Rust type it exposes (`(extern-type SqliteDb)`).
> *Rationale for nullary rather than `(Foreign a)` phantom parameters:* `tyReprClash` returns 0 outright when either side's argument vector is non-empty (typecheck.ax:7055-7056). A parameterised foreign type forfeits the only representational check the language has. Nullary minted names keep it: `SqliteDb` against `SqliteStmt` is two nullary cons with different names, and `tyCompat` (typecheck.ax:212-219, names must be equal) refuses the confusion in argument position for free.
> *Failure mode of getting this wrong.* As above — a set map bit, or a whole-block leaf.
> *Implementation note.* `scalarTyName` (codegen.ax:6133-6148) and `evScalarName` (typecheck.ax:542-557) are today hardcoded string chains. They must become "hardcoded chain **or** member of the foreign-type set", which means threading that set through `cg` and `tc`. `CG` is a 37-field record and `AX3029`'s bitmap cliff is 47 payload words (docs/memory-model.md, `MM-LIFE-2d`), so one more field is affordable. `tyIsReprScalar` is `(-> String Bool)` (typecheck.ax:7094) with no access to the environment; it needs the set threaded too, and its single caller `tyReprClash` (typecheck.ax:7059) is the only signature to change.

#### 3.2 Scalar, not unclassifiable — and the two `1`s mean opposite things

`fldClass` and `evClassOf` have **different codomains**, and the value `1` is the leak direction in one and the use-after-free direction in the other. Stating this precisely matters, because an implementer who carries `fldClass`'s intuition into `evClassOf` will read a hazard as a nuisance.

| classifier | `0` | `1` | `2` / `2+k` | default for an unregistered `TAG_T_CON` |
|---|---|---|---|---|
| `fldClass` (codegen.ax:6158-6180) | machine scalar | **unclassifiable** → whole-block leaf → **leak** | reference | falls to `lookupType`, then **`1`** — *unsafe-by-default (leak)* |
| `evClassOf` (typecheck.ax:583-613) | scalar-or-unknowable | **reference** → a retain/release on the word → **§2** | `2+k`, the signature's own variable *k* | falls to `evDataTyKnown`, which answers **`0`** — *safe-by-default* |

> **MM-FFI-9 (P, compiler-enforced).** A foreign type **SHALL** classify as `0` in `fldClass` (codegen.ax:6159) and `0` in `evClassOf` (typecheck.ax:587). In `fldClass` it **MUST NOT** classify as `1` (whole-block leaf); in `evClassOf` it **MUST NOT** classify as `1` (reference — a retain on a Rust pointer, i.e. §2).
> *Rationale, `fldClass` half.* `0` clears one bit and leaves the block's other bits honest. `1` propagates through `shapeBits` (codegen.ax:6203-6206) as `-1` and zeroes the whole map.
> *Rationale, `evClassOf` half.* `1` is what makes `__retainref` and the evidence-driven field retains fire on the word. The runtime comment at typecheck.ax:583-585 states the asymmetry itself: *"The 0 default is the safe direction everywhere — a missed bit under-reclaims, a wrong bit is a use-after-free."*
> *The practical asymmetry, worth stating because it sizes the work.* The evidence half is already **safe by default**: an unregistered nullary `TAG_T_CON` reaches `evDataTyKnown` and answers `0`. The `fldClass` half is **not**: an unregistered name reaches `lookupType` and answers `1`. So `scalarTyName` **MUST** be changed for *safety*; `evScalarName` need only be changed for *precision* (to stop the foreign name being merely "unknowable" and make the intent explicit at the source).
> *Failure mode, `fldClass` = 1.* `(struct Conn (db Foreign) (name String))` writes a leaf shape, and the `name` string is never released — a leak per connection, invisible, and only in blocks that mix foreign and reference fields.
> *Failure mode, `evClassOf` = 1.* `emitPrimRetainRef` emits a `@axiom_retain` on a Rust address. §2, first instruction.

#### 3.3 The evidence word

> **MM-FFI-10 (P, compiler-enforced).** The witness class of a foreign type in the pointerhood evidence word (`MM-LIFE-2d`) **SHALL** be 0. A polymorphic position instantiated at a foreign type in one occurrence and a reference type in another **SHALL** meet to 0.
> *Rationale.* `evMeet` (typecheck.ax:621-625) already collapses any disagreement to 0, which is the safe direction: under-retain and leak, never free early.
> *Failure mode if the meet were `1` instead.* A `Vec` holding a mix of `Foreign` and `String` gets element bit 1; when the array form's writers land (`MM-LIFE-2d`, still **P**), the buffer's release walks every element and hands each foreign address to §2.
> *Stated cost.* Such a `Vec` leaks its `String`s. Accepted, and it is the same bargain `evMeet` already makes.

#### 3.4 What the type system actually buys, and what it does not

Two levers exist and they cover different positions. Both are needed; neither is complete.

- **Argument positions are covered for free.** `checkApp` compares the argument's inferred type against the parameter type with `tyCompat` (typecheck.ax:4053). For two nullary `TAG_T_CON`s, `tyCompat` requires **equal names** (typecheck.ax:216-219) — the `String`/`Int` fiat that used to defeat this was deleted on 2026-08-15. So `(__axiom_arena_reset_keeping mark p n)` with `p : Foreign` against `mkIntArrow 3` (typecheck.ax:1515) is **already a reported mismatch** with no new code. That is `MM-FFI-5` requirement 2 satisfied against all three arena primitives, plus `__retain`, `__release`, `__alloc`, `__load64`, `__store64` (typecheck.ax:1490-1515), by one string in a set.
- **Declared-return positions need `tyIsReprScalar`.** `checkDeclaredReturn` uses `tyReprClash` (typecheck.ax:7020), which fires only if `tyIsReprScalar` names one of the two types (typecheck.ax:7059). Without adding the foreign names, `(extern rustOpen (-> String Foreign))` implemented by a body that returns an `Int` passes silently — and the value then flows everywhere as a foreign pointer while actually being an arena handle. Add them.

And the honest limits, which no amount of care removes:

- **`cast` launders everything.** `(cast Foreign h)` and `(cast Int p)` are both accepted and both erase the distinction. `MM-LIFE-2g` already records that `cast` is the marker for leaving the type system.
- **A type variable on either side matches anything** (typecheck.ax:200-201, `tyVarCompat`). Every container position is a type variable by design, so a `Foreign` in a `Vec` is checked by nothing.
- **`checkDeclaredReturn` is `Int`-blind on purpose** — 21 files return a `Span` or a `JobPool` through an `Int` signature (typecheck.ax:7033).

> **MM-FFI-11 (P, generator-enforced).** Boundary type safety **SHALL** be established at binding-generation time on the Rust side, where types are real. The Axiom checker's contribution is a **backstop against honest mistakes**, not a guarantee: a program that reaches the boundary through `cast` or a container is outside every check the language can make.
> *Rationale.* Three attempts at real inference were merged and withdrawn (5f2a616→053c525, 6ff9e2c→9d5b508) precisely because resolved argument types feed the ARC evidence word and the corpus's `Int`-handle convention then claims pointerhood for scalars. That road is closed; the generator is the only place left with ground truth.
> *Failure mode.* Believing the checker: an `extern` whose Axiom signature says `Foreign` and whose call sites pass a `Vec` handle compiles clean and hands an arena address to Rust as a pointer.

---

### 4. Direction A — Axiom calls Rust: the borrow

#### 4.1 Why a call-duration borrow is exactly the right lifetime

`MM-LIFE-2c` event 1 is the whole guarantee: *"A call borrows its arguments. No retain at the call boundary: the caller's frame outlives the callee's."* For an `extern`, "the callee" is the Rust shim, and the same frame nesting holds — the shim is an ordinary `call i64 @sym(i64, ...)` from Axiom's frame (C2). So:

**The caller's share covers the call and nothing beyond it.** Not one instruction beyond. There is no post-call retain, no deferred release, no grace period. The moment the shim returns, the Axiom caller may pass its last reference to a tail boundary (event 4 releases owned parameters dead across the call — `MM-LIFE-2c` item 4), may hit a scope end (event 3), or may overwrite the field it came from (event 5, which releases the old value). Any of the three can drop the count to zero and file the block onto `@__axiom_slabs`.

> **MM-FFI-12 (P, generator-enforced + rustc-enforced). The borrow window.** Every Axiom value passed to Rust is **borrowed for exactly the dynamic extent of the call**. Rust **MUST NOT** read it, write it, or retain its address after the shim returns.
> *Rationale.* Event 1 is the only thing keeping it alive, and event 1 ends at the return.
> *Failure mode.* Read-after-return sees whatever the next `axiom_alloc` of that size class put there, after the handout scrub zeroed the block (codegen.ax:2218-2226). The measured shape of this bug already exists in the repo: **`tests/stdlib/362-arc-tail-boundary.ax` (term 16, line 27) records a `Vec` element read back as length 2 after 300 tail boundaries** — *"a parameter STASHED into a Vec survives 300 boundaries"* — and docs/memory-model.md:1535 states the pre-fix reading: *"a `Vec` element pushed 300 boundaries ago reads a length of **2** — freed, re-issued."* (The first draft cited `tests/stdlib/365-escape-analysis.ax`; that is the event-3 escape-walk fixture and contains no such term.)
> *Enforcement.* The generator emits the borrow *inside* the shim body and hands the user function a Rust reference with an elided lifetime tied to the shim's own frame. rustc then refuses the stash.

#### 4.2 Bytes cross as (ptr, len). Never as a C string.

`strCStr` is literally `strData` (stdlib/Str.ax:161-162) — no copy, relying on `MM-VAL-7`'s terminator. But **a slice is not terminated**: `strSlice` wraps an interior address with a clamped length (stdlib/Str.ax:223-233) and the module says so in its own comment. A `Str` is a three-word block — `len` at word 0, `bytes` at word 1, `owner` at word 2 (stdlib/Str.ax:69-83) — and the value Axiom passes is the header address, not the bytes.

> **MM-FFI-13 (P, generator-enforced).** A `String` parameter **SHALL** cross as the header address, and the shim **SHALL** reconstruct a `&[u8]` from word 0 and word 1. `CStr::from_ptr` and any other NUL-scanning construction **MUST NOT** appear in a generated shim.
> *Rationale.* `MM-FFI-4` makes termination a *program* obligation, and `strSlice` is a supported operation that breaks it. A generator that trusts termination is trusting something the standard library documents as false for one of its most-used functions.
> *Failure mode.* `strlen` past the end of a slice: a length that runs to the next zero byte in the arena, i.e. into an adjacent live block. Silent, data-dependent, and it reads correct in every test whose slice happens to end at its parent's end.

```rust
// Generated shim. Edition 2024 (MM-FFI-26 pins it).
// Axiom passes the Str header address as one i64.
#[unsafe(no_mangle)]
pub extern "C" fn ax_rust_sha256(s: i64) -> i64 {
    // SAFETY: `s` is an Axiom Str header, live for this call by MM-FFI-12.
    // Word 0 is the byte length, word 1 the data pointer (stdlib/Str.ax:69-83).
    let (len, data) = unsafe {
        let h = s as *const i64;
        (*h.offset(0) as usize, *h.offset(1) as *const u8)
    };
    // SAFETY: (data, len) describes a live Axiom byte buffer for this call.
    let bytes: &[u8] = unsafe { core::slice::from_raw_parts(data, len) };
    user::sha256_prefix(bytes) as i64      // fn sha256_prefix(&[u8]) -> u64
}
```

The user-visible function takes `&[u8]`. Its elided lifetime is the call's. `user::sha256_prefix` cannot put that slice in a `static`, cannot return it, cannot send it to a channel — rustc refuses, and that refusal *is* the enforcement of `MM-FFI-12`.

> **MM-FFI-14 (P, generator-enforced).** A generated shim's **public** signature **MUST NOT** expose a raw pointer, a `&'static` borrow, or any type with a lifetime the caller chooses. Slices and `&str` with elided lifetimes only.
> *Rationale.* `*const u8` carries no lifetime, so rustc has nothing to refuse. The borrow rule is only enforceable if the borrow is expressed as a borrow.
> *Failure mode.* A crate author writes `fn handle(p: *const u8, n: usize)` and stores `p` in a `static mut` cache. Compiles, passes tests, corrupts under allocation pressure.

> **MM-FFI-15 (P, programmer-obligation). Copy is the v0 discipline.** Anything Rust keeps past the call **MUST** be a **copy** in Rust-owned memory, not a borrow and not an Axiom handle.
> *Rationale.* Copy is the only discipline that needs no cooperation from the Axiom side's incomplete count discipline (§5.2), and §5.3 concludes that it is the *only* sound discipline available in v0. It is also what `MM-PAR-4` already requires of process boundaries — values cross as bytes.
> *Failure mode.* As `MM-FFI-12`.

#### 4.3 Mutable out-parameters

> **MM-FFI-16 (P, programmer-obligation).** An Axiom buffer passed for Rust to **write** **MUST** come from `memAlloc`/`__alloc`. Rust **MUST NOT** write through the data pointer of a string **literal**.
> *Rationale.* Literals emit `private unnamed_addr constant` globals (codegen.ax:1005, 1015) — read-only sections — and the literal's header is *shared by every occurrence in the module*. `MM-FFI-2` already states that loader-resident bytes must not be written.
> *Failure mode.* Best case a fault in `__TEXT`; worst case, on a platform that permits the write, every other use of that literal in the program sees the mutation.
> *What checks it.* Nothing in the language. `strData` of a literal and of a `strAlloc` buffer are the same type and the same shape. This is a real, unclosable gap in v0 — see §11.

---

### 5. `axiom_retain` / `axiom_release`: the protocol and its landmine

#### 5.1 The exact symbols

Measured from the emitter, these are the runtime entry points with external linkage:

```llvm
define i64  @axiom_alloc(i64 %size)  #0    ; codegen.ax:2046
define void @axiom_retain(i64 %h)    #0    ; codegen.ax:2274
define void @axiom_release(i64 %h)   #0    ; codegen.ax:2292
define i64  @main(i64 %argc, i64 %argv) #0 ; codegen.ax:1994  — Rust-host only, §6b
define i64  @__axiom_user_main()     #0    ; codegen.ax:2980  — Rust-host only, §6b
```

Note the **void** returns on retain/release — this is the second most common way to get the FFI declaration wrong.

```rust
// Edition 2024: an extern block that is not `unsafe extern` is an error.
unsafe extern "C" {
    pub fn axiom_alloc(size: i64) -> i64;
    pub fn axiom_retain(h: i64);
    pub fn axiom_release(h: i64);
}
```

> **MM-FFI-17 (P, generator-enforced). The nameable runtime surface, by direction.** Rust **SHALL** declare only from this enumerated set and nothing else from the Axiom runtime:
> - **Both directions:** `axiom_alloc`, `axiom_retain`, `axiom_release`.
> - **Rust-host direction only (§6b):** `main` (normally renamed at link time, see `MM-FFI-36`) and `__axiom_user_main`, which are the Axiom runtime's *entry points*, not part of its allocator surface.
> - **If and when the pin protocol of §5.3 ships:** `axiom_ffi_release`. Until then it does not exist and **MUST NOT** be declared.
>
> `@__axiom_bump`, `@__axiom_bump_end`, `@__axiom_chunk`, `@__axiom_free`, `@__axiom_high`, `@__axiom_slabs` and every other allocator global is `internal` (codegen.ax:2007-2028, 2044) and **MUST NOT** be named.
> *Rationale.* The earlier draft said "exactly these three signatures and no others", which contradicted `MM-FFI-30`'s own text requiring Rust to call `@main`/`@__axiom_user_main`; both are externally linked in the measured bootstrap IR (`bootstrap/axiom-darwin-aarch64.ll` lines 6, 21, 153, 171, 83177 — 5 `internal` defines, 0 `declare`s in the whole module). Enumerating by direction resolves it. The globals stay unnameable because `MM-PAR-3`/`I11` rests on them being process-private and untouched.
> *Failure mode.* Any direct manipulation of the bump pointer or the slab heads breaks `I11` and every rule in §3 of the memory model at once.

#### 5.2 The landmine: a *balanced* pair frees birth-0 blocks

This is the finding that shapes the rest of this section, and it is not obvious from the rules as written.

`axiom_alloc` writes the count word **explicitly zero** at handout (codegen.ax:2242-2243). `MM-LIFE-2c` records that "raw `__alloc`/`memAlloc` and `strWrap` stay birth-0: a second birth would double-count every String". `strWrapOwned` — through which *every* `Str` in the language is built — allocates with `memAllocMapped 24 4` (stdlib/Str.ax:70), which is `__alloc` (stdlib/Mem.ax:76). **Every `Str` header therefore has count 0 while its owner is using it.** docs/memory-model.md:1685 records the same thing from the probe side: *"a `String` whose header count reads 0"*. Only compiler-built ownership-creating blocks (constructor cells, struct blocks, closure records, evidence records) are born at 1.

Measured on this machine, `/tmp/axtest/t7.ax`:

```scheme
(let ((s (strDup "hello world")))
  { (println (fmtInt (strLen s)))
    (__retain (cast Int s))
    (__release (cast Int s))
    (let ((junk (strDup "AB")))
      (println (fmtInt (strLen s)))) })
```

prints `11`, then `2`, then `2`. **The balanced pair freed a live `Str`, and `strLen s` read the re-issued block** — the same `length of 2` signature docs/memory-model.md:1535 records for the tail-boundary fixture.

Now trace a naive RAII shim over a borrowed `Str`:

| step | count | note |
|---|---|---|
| Axiom builds `s`, holds it in a frame slot | 0 | frame ownership is informal; event 3 is type-directed and does not fire on this shape |
| Rust shim: `axiom_retain(s)` | 1 | |
| Rust shim returns; `AxRef` drops: `axiom_release(s)` | 0 | `%c1 = 0` → `%isdead` **true** |
| release's dead path | — | walks bit 2 → releases the byte buffer; files the header onto `@__axiom_slabs[1]` |
| Axiom's next `(strLen s)` | — | reads a re-issued, scrubbed block |

The floor at `%zero = icmp eq i64 %c, 0` (codegen.ax:2300-2302) does not help — it protects against an *extra* release, not against a pair that starts from zero. There is **no floor below 1** anywhere in `@axiom_release`: codegen.ax:2320-2323 decrements 1→0 and takes `%isdead`; codegen.ax:2359-2366 files the block.

> **MM-FFI-18 (P, generator-enforced). Rust MUST NOT retain a borrowed argument.** A shim **SHALL NOT** call `axiom_retain` on any value it received as a parameter.
> *Rationale.* The reference count is a count of *shares taken*, and today's partial ARC leaves most live values at zero shares: events 2 and 3 for call results are implemented, measured, and deliberately **not shipped** (285 new retains bought 8 new releases and reclaimed nothing — docs/memory-model.md:1660-1670). There is no invariant "a value visible to a callee has count ≥ 1", so `+1` then `−1` is not the identity; it is a `free`.
> *Failure mode.* Exactly the table and the measured transcript above: a use-after-free of the *caller's* value, caused by code that looks perfectly balanced.

#### 5.3 The zero-floor rule, and why v0 ships without a rooting protocol

An earlier draft of this section proposed a "root protocol": `__ffi_root` (+1) to establish a share before Rust retains, and `__ffi_unroot` (−1) when Axiom is done. **That protocol was `MM-FFI-18`'s landmine one hop removed, and both of its prescribed disciplines were use-after-frees.** Traced on a birth-0 block:

| discipline | sequence | end state |
|---|---|---|
| **Transfer** (as drafted) | root 0→1; Rust `adopt` (no retain); Rust `Drop` → release 1→0 | **DEAD** while Axiom still holds it |
| **Share** (as drafted) | root 0→1; `AxRef::retain` 1→2; Rust `Drop` 2→1; Axiom `__ffi_unroot` 1→0 | **DEAD** |

Rooting never established "someone else holds a share" — it *manufactured* the single share that the eventual release then consumed. The drafted `putDoc` example, `(rustCacheStore cache (cast String (__ffi_root body)))`, rooted a parameter the **caller** still owned; when the Rust cache dropped, the caller's string was freed and re-issued. And the drafted failure mode was inverted: it claimed that *forgetting* `__ffi_unroot` leaks ("the safe direction"), when in fact **performing** `__ffi_unroot` is the use-after-free.

The rule that survives contact with the measured runtime is not about balance. It is about zero.

> **MM-FFI-19 (P, compiler-enforced + programmer-obligation). The zero floor: the FFI side never drives a count to zero.** The reference count of any block shared across the boundary **MUST NEVER** be decremented to zero by an FFI-side operation. Concretely:
>
> **(a) v0 ships no rooting protocol at all.** `__ffi_root`/`__ffi_unroot` are **not in v0**. The v0 discipline is borrow-plus-copy: `MM-FFI-12` for the call window, `MM-FFI-15` for anything kept. This is the option §11.6 already suspected was the practical v0, and it is now the specified one.
>
> **(b) If a pin protocol ships later, it pins — it does not root.** The primitive is a **pin**: a `+1` that is *never given back*.
>
> ```scheme
> (:: __ffi_pin   (-> a Int))   ; +1, answers the same word. Permanent.
> (:: __ffi_unpin (-> Int Int)) ; lowers to @axiom_ffi_release, FLOORED AT 1
> ```
>
> `__ffi_pin` lowers to `call void @axiom_retain` exactly as `emitRetainOf` does (codegen.ax:6274-6278). `__ffi_unpin`, if it exists at all, **MUST NOT** lower to `@axiom_release`. It lowers to a **new** runtime symbol `@axiom_ffi_release` that decrements only when the count is strictly greater than 1 and **never enters the dead path** — no map walk, no `@__axiom_slabs` push. On a birth-1 block (constructor cell, struct block, closure record, evidence record) it restores the count exactly. On a birth-0 block it is a no-op and the block **leaks**, which is the direction `MM-FFI-29` and `MM-LIFE-2f` already price in.
>
> **(c) `AxRef::drop` releases only the share `AxRef::retain` itself took — never the pin.** `AxRef::adopt` (take ownership without retaining, release at drop) is **deleted from the design**: its `Drop` consumes the pin, which is exactly (a)'s transfer row.
>
> *Rationale for refusing witness 0 and symbolic witnesses on `__ffi_pin`.* `__retainref` treats a missing or unknown stamp as 0 and emits nothing (codegen.ax:5340-5348) — the right default for a store, and exactly wrong here: a pin that silently does not pin leaves the block at its original count, and the Rust-side `AxRef::retain`/`Drop` pair then runs against a birth-0 block, which is §5.2. Under-pinning is a *use-after-free*, so it must be a refusal, not a default.
> *Diagnostic code.* Reserve **`AX3039`** (`ffi-pin-unclassifiable`). **Not `AX3036`**: `AX3036` (`recursion-in-scrutinee`, `ERR-PROP-4`), `AX3037` (`discarded-result`) and `AX3038` (`error-payload-untyped`) are already allocated in docs/error-model.md:478-480 and tracked at :636 and :649, and `AX3032` is **retired and MUST NOT be reused** (docs/error-model.md:474). `AX3035` is the highest code *constructed*, which is what misled the earlier draft; allocation runs ahead of construction. **Later sections must allocate from AX3040 up.**
> *Why not reuse `__retain`.* `__retain` is `(-> Int Int)` (typecheck.ax:1494) and its own registration comment warns that "retaining an Int above 4096 dereferences it". A polymorphic, type-directed pin is the only shape that is safe on a `String` and refused on an `Int`.
> *Stated cost.* One leaked block per pinned birth-0 value. Accepted; §11.3 explains when it goes away.

Under (a), the correct v0 spelling of the drafted `putDoc` example is a **copy**, and it needs no new primitive:

```scheme
;; v0: the Rust cache keeps its own bytes. Nothing is rooted, pinned,
;; retained, or released. `body` is borrowed for the call and no longer
;; (MM-FFI-12); the shim memcpy's into its slot table (MM-FFI-15).
(extern rustCacheStore (-> Foreign String Int))
;@axiom:effect(io)

(:: putDoc (-> Foreign String Int))
;@axiom:effect(io)
(fn (putDoc cache body)
  (rustCacheStore cache body))
```

And the Rust side of the boundary, if and when (b) ships, holds shares like this — note there is no `adopt`, no `Clone`, and the `Drop` unwinds only the `retain` it performed:

```rust
/// A second share of an Axiom heap value that the Axiom side has PINNED.
/// Exactly one `axiom_release` per `AxRef`, at drop, and it can never be
/// the decrement that reaches zero, because the pin's +1 is never returned.
#[repr(transparent)]
pub struct AxRef {
    h: i64,
    // Not Send, not Sync: the count update in @axiom_retain is a plain
    // load/add/store (codegen.ax:2283-2287), never atomic, and the
    // allocator has no lock (MM-PAR-3, I11).
    _not_send: core::marker::PhantomData<*const ()>,
}

impl AxRef {
    /// Take a second share of a PINNED handle.
    ///
    /// # Safety
    /// `h` must be an Axiom handle pinned with `__ffi_pin`, and the pin
    /// must outlive this value. There is no `adopt`: a share that is not
    /// backed by a live pin is a use-after-free at drop.
    pub unsafe fn retain(h: i64) -> Self {
        // Edition 2024: `unsafe_op_in_unsafe_fn` is deny-by-default, so the
        // call needs its own block even inside an `unsafe fn`.
        unsafe { axiom_retain(h) };
        AxRef { h, _not_send: core::marker::PhantomData }
    }

    pub fn raw(&self) -> i64 { self.h }
}

impl Drop for AxRef {
    fn drop(&mut self) {
        // Immediates (< 4096) and statics (count -1) are no-ops in the
        // runtime itself (codegen.ax:2296-2299), so no guard is needed here.
        // This decrement can only ever take N+1 -> N, N >= 1, because the
        // pin holds the floor (MM-FFI-19).
        unsafe { axiom_release(self.h) }
    }
}

// Deliberately no Clone, no Copy. Duplicating a share must go through
// AxRef::retain so the +1 is visible at the call site.
```

> **MM-FFI-20 (P, programmer-obligation). Exactly one release per share.** Each `AxRef` **SHALL** correspond to exactly one `axiom_release`. `AxRef` **MUST NOT** implement `Clone` or `Copy`.
> *Rationale.* A derived `Clone` would duplicate the word without the retain — the classic C++ shared-pointer bug, made silent by `#[repr(transparent)]`.
> *Failure mode — corrected.* The earlier draft said a second release "sees the re-issued block's fresh count and decrements that, corrupting an unrelated live object's count". That cannot happen: re-issue writes count **0** explicitly (codegen.ax:2242-2243) and a release on a count-0 block is skipped at codegen.ax:2300-2302. The real hazard is the opposite and worse. **The dead-path push writes the old free-list head into the block's count word** — codegen.ax:2363-2366: `%pbase = add i64 %h, -16` / `store i64 %ohead, ptr %pbasep` / `store i64 %pbase, ptr %pslotp`, and the emitter says so itself at codegen.ax:2317-2319: *"The dead block's count word doubles as the free-list link."* So a second release **before re-issue** loads that link, decrements it, and stores it back: `@__axiom_slabs`'s chain now points one byte below a real block base. The next pop of that size class hands out `link − 1 + 16`, a **misaligned interior address** inside a live block, violating `I5`/`MM-ALLOC-3`.
> *Why it is intermittent.* If the size class's list was empty, the stored link is `0`, the second release hits the `c == 0` skip, and nothing happens. The bug therefore appears only when the class already had a free block — i.e. under allocation churn, and never in a small test.

> **MM-FFI-21 (P, programmer-obligation). Release depth is graph depth.** `@axiom_release` recurses through its map walk (codegen.ax:2345). Dropping an `AxRef` to a deep Axiom graph consumes Rust stack proportional to graph depth.
> *Rationale.* The runtime's own comment accepts this — "recursion depth is object-graph depth — acceptable for the compiler's own shapes" — but the compiler runs on the main thread's 8 MiB stack.
> *Failure mode.* A `Drop` on a Rust worker thread with a 2 MiB default stack overflows on a graph the Axiom side handles fine. Compounds with `MM-FFI-30`'s thread confinement: this is a second, independent reason not to drop Axiom values off the Axiom thread.

---

### 6. Direction A, extended — Rust values held by Axiom: the opaque handle

This is still *Axiom calls Rust*; it is the long-lifetime case. The genuine second direction — a Rust binary linking Axiom's object and calling in — is §6b.

#### 6.1 The handle is an index, not a pointer

> **MM-FFI-22 (P, generator-enforced).** A Rust value held by Axiom across calls **SHALL** be addressed by a **generation-tagged slot index**, not a raw pointer: low bits the slot, high bits a generation counter incremented on every close.
> *Rationale.* `MM-FFI-11` establishes that Axiom cannot guarantee the word it hands back is the word it was given — `cast` launders, containers are untyped, and `memGetWord` returns whatever is in the slot. With a raw pointer, a stale or forged i64 is immediate UB in Rust. With a tagged index, `slots[i].gen != h.gen` is a **detected error** the shim can turn into an error return.
> *Cost.* One bounds check and one generation compare per call. Measured cost is not available; the design accepts it on the grounds that the alternative is unbounded UB.
> *Failure mode without it.* Axiom stores a `Foreign` in a `Vec` (untyped, `MM-FFI-10`), the `Vec` is reset by an arena (§7), the slot is re-issued with a different `Vec`'s contents, and Rust dereferences an integer.

```rust
// no_std-compatible, edition 2024: a fixed slot table, no allocator,
// `nm -u` stays empty.
const AX_FFI_SLOTS: usize = 1024;

struct Slot { gen: u32, val: Option<Db> }

// Sound only under MM-FFI-30 (single-threaded).
static mut SLOTS: [Slot; AX_FFI_SLOTS] =
    [const { Slot { gen: 0, val: None } }; AX_FFI_SLOTS];

/// Edition 2024 denies `static_mut_refs` (E0796), so never form `&mut SLOTS[i]`.
/// Take a raw pointer to the static and index through it.
#[inline]
fn slot(idx: usize) -> *mut Slot {
    // SAFETY: idx < AX_FFI_SLOTS, checked by every caller.
    unsafe { (&raw mut SLOTS).cast::<Slot>().add(idx) }
}

#[inline]
fn pack(idx: usize, gen: u32) -> i64 { ((gen as i64) << 32) | (idx as i64 + 1) }

#[unsafe(no_mangle)]
pub extern "C" fn ax_db_close(h: i64) -> i64 {
    let (idx, gen) = ((h & 0xffff_ffff) as usize, (h >> 32) as u32);
    if idx == 0 || idx > AX_FFI_SLOTS { return -1; }            // forged
    let s = slot(idx - 1);
    // SAFETY: single-threaded (MM-FFI-30); idx bounds-checked above.
    unsafe {
        if (*s).gen != gen { return -2; }                        // stale: closed
        (*s).val = None;                                         // Drop runs HERE
        (*s).gen = (*s).gen.wrapping_add(1);                     // invalidate
    }
    0
}
```

#### 6.2 No finalizers. Explicit close. Decision and alternatives.

Axiom is ARC with **no destructors** — `MM-LIFE-1` says so in as many words, and `@axiom_release`'s dead path (codegen.ax:2325-2366) contains exactly two actions: walk the map, file the block. There is no hook. And by `MM-FFI-7` a foreign word's bit is *clear*, so release never even looks at it.

Consequence: **an automatic destructor cannot happen by accident, and cannot be made to happen cheaply.** The alternatives:

- **(a) Add a finalizer form to the shape word.** Rejected on two independent grounds. *Encoding:* the word is fully spent — bit 0 form, bits 1..15 count, bits 16..62 map, bit 63 reserved so every constant stays non-negative (`MM-LIFE-2d`, codegen.ax:6193-6207). A third form costs a bit that only exists by shrinking the 47-word map capacity, and `AX3029` is already a cliff the compiler's own 37-field `CG` record sits just under. *Re-entrancy:* the dead path would have to make an **indirect call into Rust from inside `@axiom_release`**, potentially while `@__axiom_slabs` is mid-update (the push at codegen.ax:2358-2365). Rust that allocates would re-enter `axiom_alloc` and pop the very block being filed. The one function in the runtime that must not be re-entered would become the one that calls arbitrary foreign code.
- **(b) Tie the destructor to a `handle` extent.** Rejected: `handle` extents are control-flow scopes, not object lifetimes, and `MM-ALLOC-16b` already records that an evidence record is an ordinary arena object with no protection. Binding foreign lifetimes to effect scopes would put the same footgun one level deeper.
- **(c) Explicit close, with a scope macro for ergonomics.** **Chosen.**

> **MM-FFI-23 (P, programmer-obligation). Explicit close.** Every foreign resource **SHALL** be released by an explicit call. Axiom emits no finalizer, ever.
> *Rationale.* The three grounds above, plus symmetry: `MM-LIFE-1`'s default is already "the lifetime of every heap value is the process". A foreign value that leaks behaves exactly like an Axiom value that leaks, which is a model the language's users already have.
> *Failure mode.* A forgotten close leaks the Rust value for the process's life. **Stated cost, not a bug** — the same posture `MM-LIFE-2f` takes on cycles.

> **MM-FFI-24 (P, generator-enforced). Close is idempotent; use-after-close is detected.** A second close of a handle **SHALL** answer an error, and any operation on a stale handle **SHALL** answer an error. Neither is UB.
> *Rationale.* `MM-FFI-22`'s generation tag makes both a compare. Without them, `Box::from_raw` twice is a double free in Rust's allocator, which is not a failure Axiom can even observe.
> *Failure mode without it.* Double free in the Rust allocator, or a `&mut` alias to a reused slot.

**The ergonomic wrapper, in a spelling the macro system actually accepts.** The earlier draft showed `(with-foreign (db (dbOpen path)) body...)`. **That does not parse.** A macro's parameters are "a flat positional list of distinct identifiers" (docs/macro-system.md:44-50, `MAC-LANG-1`); `(macro (with-foreign (v e) body) ...)` gives `error[AX2001]: expected identifier, found '('`. The pattern-capable rule form parses but is a **declaration** macro, refused in expression position with `error[AX3027]: declaration macro 'with-foreign' invoked in expression position ... the two template kinds are disjoint (macro-system.md MAC-CAP-8)`. The flat spelling below was verified against `.axiom-bin/axiom check` — **exit 0, `OK`** — including passing the closer as an identifier parameter:

```scheme
(macro (with-foreign v e close body ...)
  (let ((v e))
    (let ((r { body ... }))
      { (close v) r })))

;; use:
(with-foreign db (dbOpen "app.db") dbClose
  (dbQuery db "select 1")
  0)
```

It is sound *because* Axiom has no exceptions and no unwinding, so a block has exactly one normal exit. The binding-group spelling would require a macro-system change and is **not v0**.

> **MM-FFI-25 (P, programmer-obligation).** A `with-foreign` body **MUST NOT** tail-call out of itself and **MUST NOT** let the handle escape the scope.
> *Rationale.* `MM-EXEC-6b` replaces a self tail call with a branch to the loop header; a tail call from inside the body jumps past the close. And nothing in the language checks escape for a `Foreign` — `paramKept`'s interprocedural walk (`MM-LIFE-2c`, event 3) is about *reference* escape and answers ESCAPE for `cast`, which is how a `Foreign` most often leaves.
> *Failure mode.* Leak (tail call out), or use-after-close (escape).

#### 6.3 The Rust allocator question

> **MM-FFI-26 (P, generator-enforced, link-gate). Crate configuration, pinned.** A crate on the Axiom-host side **SHALL** be `#![no_std]`, built with `panic = "abort"`, and **SHALL** pin `edition = "2024"` in its `Cargo.toml`. It **MAY** use `alloc` only with a `GlobalAlloc` whose `alloc` calls `axiom_alloc`, whose `dealloc` is a **no-op**, and which **returns null whenever `layout.align() > 16`**.
> *Rationale, `no_std` + abort.* Measured on this machine: a `no_std` staticlib links and leaves `nm -u` **completely empty** — the freestanding property survives intact. A `std` staticlib links too, but the executable gains 188 undefined symbols, 14 of them on `check-freestanding.sh`'s forbidden list (`malloc`, `free`, `memcpy`, `memset`, `strlen`, …) plus `_Unwind_*`, `_tlv_bootstrap`, and dyld machinery.
> *Rationale, the edition pin.* rustc/cargo here is **1.97.1**, whose default for a new workspace is edition 2024, and every snippet in an unpinned 2021-era design hits four deny-by-default hard errors: `#[no_mangle]` must be `#[unsafe(no_mangle)]`; `extern "C" { … }` must be `unsafe extern "C" { … }`; `&mut SLOTS[i]` on a `static mut` is E0796 (`static_mut_refs`); and a bare call inside an `unsafe fn` violates `unsafe_op_in_unsafe_fn`. Pinning the edition alongside `no_std` and `panic="abort"` is what makes the generated code reproducible; every snippet in this section is written in 2024 spelling.
> *Rationale, the alignment floor.* `axiom_alloc` guarantees **16-byte alignment only** — codegen.ax:2058-2062: `%padded = add i64 %size, 15` / `%sz0 = and i64 %padded, -16` / `%sz = add i64 %sz0, 16`, handout `%user = add i64 %hb, 16` — and nothing in the allocator consults, or *can* consult, a requested alignment. `I5`/`MM-ALLOC-3` state the guarantee as 16, not "at least what you asked for". `GlobalAlloc::alloc` is contractually required to return a pointer aligned to `layout.align()`, which `#[repr(align(32))]`, `#[repr(align(64))]` and SIMD types exceed. A shim that forwards those to `axiom_alloc` is a **UB allocator**; it must return null (or over-allocate and align up, which forfeits the header relationship and therefore forfeits any hope of `axiom_release` ever understanding the block). `axiom_alloc` is **not** a drop-in for the Rust allocator and the rule must not imply that it is.
> *Rationale, the no-op `dealloc`.* There is no `axiom_free`: release *files* a block onto a size class (codegen.ax:2353-2366) and reads a header the Rust allocator never wrote, so a real `dealloc` is not implementable.
> *Failure mode.* A no-op `dealloc` means Rust-side `alloc` usage leaks into the Axiom arena and is reclaimable only by an arena reset — which §7 forbids while a `Foreign` is outstanding. In practice: use the fixed slot table and avoid `alloc`.
> *Enforcement.* The allowlist gate (`MM-FFI-5` requirement 4) enumerates permitted undefined symbols; `malloc` is not on it.

---

### 6b. Direction B — Rust hosts Axiom

The measured experiment 3 is the real second direction: rename the emitted `@main` to `@axiom_rt_init`, compile to `.o`, `ar rcs` it into a static lib, link it into an ordinary Rust binary declaring `extern "C" { fn axiom_rt_init(i64, i64) -> i64; fn addTwo(i64, i64) -> i64; }`. It works: Axiom's syscall-based `println` printed from inside the Rust process and `addTwo(20, 22)` returned 42. It also has **no ownership rules at all** in the first draft of this section, and every rule it needs is different from §4–§6.

Recall the naming facts from the ABI contract: **entry-file declarations keep their bare name**, so `addTwo` is emitted literally as `@addTwo`; imported declarations are renamed `Mod$name` and `llvmSym` (codegen.ax:982-990) quotes only outside `[-A-Za-z0-9$._]`. A Rust host therefore names Axiom functions by their bare entry-file names, which is convenient and fragile in equal measure.

#### 6b.1 What a Rust host owns when Axiom returns a value

`MM-LIFE-2c` **event 2** — *"a function returns its result owned"* — is **not shipped**. docs/memory-model.md:1660-1670 records why: 285 new retains to enable 8 new releases, 9.5% of a self-compile, *"and not one byte reclaimed. So the pair is not shipped."* So an Axiom function returning a heap value returns it at whatever count it had, which for every `Str` and every `memAlloc` block is **0**.

> **MM-FFI-34 (P, generator-enforced + programmer-obligation). An Axiom return value is BORROWED, not owned.** In the Rust-host direction, a value returned from an Axiom function is valid only **until the next call into Axiom and until the next arena operation**, whichever comes first. Rust **MUST** copy anything it needs beyond that point into Rust-owned memory. Rust **MUST NOT** call `axiom_release` on a returned value.
> *Rationale.* Event 2 is unshipped, so the returned block is typically count 0. A release on it is `MM-FFI-18`'s landmine with no retain even needed: the count-0 skip (codegen.ax:2300-2302) saves it *this* time, but a returned block that happens to be a birth-1 constructor cell goes 1→0 and is filed while the Axiom side still names it. Meanwhile any subsequent Axiom call may allocate over a freed block, and any `__axiom_arena_reset*` reclaims it outright — `MM-ALLOC-14` guarantees the reset writes no byte of what it reclaims, so the read keeps *working* until something allocates, which is the worst possible diagnostic behaviour (§7).
> *Failure mode.* A Rust host stashes a returned `Str` header, calls back into Axiom, and reads a re-issued block — the `length of 2` signature again (docs/memory-model.md:1535, tests/stdlib/362-arc-tail-boundary.ax:27).
> *When this rule changes.* The day events 2 and 3 ship for call results, a returned value is owned and the rule becomes "Rust owns it and must release it exactly once". §11.3 says when that day arrives. Until then, copy.

#### 6b.2 What a Rust shim owns when it *builds* an Axiom value

`axiom_alloc` is externally linked and Rust may call it. What comes back is not a usable Axiom block until Rust finishes the job the allocator deliberately cannot do. The emitter's own comment at codegen.ax:2231-2237 is the specification: the shape word packs *"bits 16..62 the reference bitmap — **which the allocator leaves EMPTY, because it cannot know a field from an int**. memAlloc'd memory is therefore a leaf by construction, the unsafe layer's own rule."*

> **MM-FFI-35 (P, programmer-obligation). A Rust-built Axiom block is a birth-0 leaf until its builder stamps a map.** A block obtained from `axiom_alloc` on the Rust side comes back with **count 0** (codegen.ax:2242-2243) and a **leaf shape word** — payload word count in bits 1..15, map bits **empty** (codegen.ax:2245-2251). Rust **MUST** treat this exactly as `Mem.memAllocMapped`'s programmer obligation (stdlib/Mem.ax:75-86, `MM-LIFE-2g`): if any payload word holds an Axiom **reference**, the builder **MUST** write the corresponding map bit into the shape word at `handle − 8` before the block can be released correctly, and **MUST NOT** set a bit for any word holding a foreign address (`MM-FFI-7`).
> *Rationale.* The obligation is stated for the Axiom unsafe layer and nowhere for the Rust side, which is the gap. A leaf block whose payload holds a `Str` handle leaks that string permanently and silently, and it is exactly `MM-FFI-6`'s under-classification failure mode reached from outside the compiler.
> *Second obligation: the count.* A birth-0 block handed to Axiom behaves like every other birth-0 block — it is subject to §5.2. Rust **MUST NOT** retain-then-release it, and **SHOULD** hand it to Axiom immediately and forget it.
> *Third obligation: the size field.* A payload past 32,767 words overflows the count field and stores 0, the unknown-size sentinel that release refuses to file (codegen.ax:2245-2251, and the comment there notes 262 KB read buffers exist). A Rust builder of a large buffer gets a block that is permanently unreclaimable, which is safe and is a leak.
> *Failure mode.* Silent permanent leak of every reference the block holds (missing bits), or §2 (a bit set over a foreign word).

#### 6b.3 Initialisation and entry

> **MM-FFI-36 (P, generator-enforced). The Rust-host entry contract.** Before any Axiom function is called, the host **MUST** call the Axiom runtime entry exactly once, on the thread that will own Axiom for the process's life (`MM-FFI-30`). That entry is `@main` — renamed at link time to something like `@axiom_rt_init` to avoid colliding with the Rust host's own `main`, which is what the measured experiment did — and it takes `(argc, argv)`, stores them into `@__axiom_argc`/`@__axiom_argv`, and calls `@__axiom_user_main()` (codegen.ax:1994-2001, 2980-2982).
> *What the entry actually establishes.* Only two things: the argc/argv globals, and whatever the user's `main` does. It does **not** initialise the allocator — see `MM-FFI-31`'s corrected rationale; the allocator's globals are `internal global i64 0` and the bump path handles the all-zero state by falling into `refill`.
> *Consequences the host must accept.* (1) `@__axiom_user_main` runs the whole user program, so a library-shaped Axiom module should keep its `main` trivial and expose its real surface as separate entry-file functions with bare names. (2) The argc/argv the host passes are what `sysArg`/`__argc`/`__argv` will report for the process's life; passing the host's own is usually right and passing `(0, 0)` makes every argument query answer nothing.
> *Failure mode.* Calling an Axiom function before the entry: any code path reaching `sysArg` reads 0. Calling the entry twice: `__axiom_user_main` runs twice.
> *Reconciliation with `MM-FFI-17`.* `@main` and `@__axiom_user_main` are nameable **in this direction only**, as entry points. They are not part of the allocator surface and the `internal` globals remain unnameable in both directions.

#### 6b.4 What is *not* different

`MM-FFI-7` through `MM-FFI-11` (classification), `MM-FFI-13` (bytes as ptr+len), `MM-FFI-19` (the zero floor), `MM-FFI-20`, `MM-FFI-21`, `MM-FFI-27`, `MM-FFI-28` and `MM-FFI-29` apply unchanged — they are properties of the runtime, not of who called whom. The rules that *are* direction-specific are `MM-FFI-26` (`no_std`, which does not apply to a std host), `MM-FFI-30`'s token (§9), `MM-FFI-33` (panics), and `MM-FFI-38` (fork).

---

### 7. Arenas

Two directions, and they fail differently.

**Foreign address into an arena primitive.** `__axiom_arena_reset_keeping(mark, addr, n)` copies `n` bytes from `addr` into arena memory and answers where they landed (codegen.ax:2615, `MM-ALLOC-15`). `MM-FFI-3` already calls a foreign `addr` **undefined**. All three primitives are registered `mkIntArrow` (typecheck.ax:1512-1515), so `tyCompat`'s name equality (typecheck.ax:216-219, checked at typecheck.ax:4053) refuses a `Foreign` argument outright.

> **MM-FFI-27 (P, compiler-enforced).** No arena primitive **SHALL** accept a foreign type. This is `MM-FFI-5` requirement 2 and it is satisfied by `MM-FFI-8`'s distinct nullary name plus the existing argument check — no new machinery.
> *Rationale.* The kept block is copied *from*, and the copy runs after the reset has already moved chunks to the free list; a foreign source is outside every extent the primitive reasons about (`MM-FFI-3`, `I7`, `I9`).
> *Failure mode.* Reading foreign memory as an arena block — and, for a `mark` argument, restoring `@__axiom_bump`/`@__axiom_bump_end`/`@__axiom_chunk` from three Rust words, which puts the allocator's position inside Rust's heap.
> *Residual gap.* `(cast Int p)` defeats this. See §11.

**Arena reset while a `Foreign` is outstanding.** This is the more likely accident and it has no check at all.

> **MM-FFI-28 (P, programmer-obligation).** A program **MUST NOT** reset past a mark taken before a `Foreign` was obtained, unless it closes the resource first.
> *Rationale.* The reset reclaims the Axiom block that held the handle. The Rust value stays alive — `MM-FFI-3`: foreign memory is not scrubbed, not reclaimed, not counted — but the only word naming it is gone. Nobody can ever call the closer.
> *Failure mode, and it is the nastiest kind.* `MM-ALLOC-14` guarantees a reset **writes no byte of what it reclaims**, so reading the handle after the reset *works* — until an allocation overwrites it. The program leaks one Rust resource per loop iteration and behaves correctly the whole time. RSS grows on the Rust side while the Axiom arena stays flat, which points the investigation in exactly the wrong direction.
> *What checks it.* Nothing. `MM-ALLOC-16` is explicit that the compiler cannot check reset contracts and never inserts these calls itself.
> *Direction-B corollary.* The same rule binds a Rust host, and it is easier to violate there because the reset and the handle live in different languages. See `MM-FFI-34`.

**Scheduling note.** `MM-LIFE-2e` states that when ARC lands, all three arena primitives **MUST** be refused under it, because a reset reclaims without releasing and a later compiler-emitted release would walk a re-issued header. The FFI design **MUST NOT** acquire a dependency on arenas surviving. Practically: `with-foreign` is a `let`/close pair, never a mark/reset pair.

One implementation detail worth knowing: `@__axiom_arena_reset_fn` zeroes all 4097 slab heads before restoring (codegen.ax:2523-2540), precisely so a release-to-zero inside a reset extent cannot leave a dangling free-list head. A reset therefore also discards every block ARC has freed — which is correct, and which means a `Foreign` stored in a freed-then-reset block is doubly unreachable.

---

### 8. Cycles across the boundary

Axiom block `A` holds a `Foreign` naming Rust slot `f`; slot `f` holds an `AxRef` to `A`.

- Axiom's release walk **never follows** the `Foreign` word — its map bit is clear by `MM-FFI-7`. So `A`'s death would not close `f`.
- But `A` never dies: `f`'s `AxRef` holds a share (and, under `MM-FFI-19`(b), a pin holds a further permanent one).
- And `f` is closed only by explicit call (`MM-FFI-23`), from code reachable through... `A`.

> **MM-FFI-29 (P, programmer-obligation). A boundary-spanning cycle leaks, and that is the accepted cost.** It is the same bargain `MM-LIFE-2f` and `I14` already make for intra-Axiom cycles, extended one hop.
> *Rationale.* Making it not leak requires tracing, and a tracer would have to trace *through Rust*, which means either a Rust-side trace callback (rejected for the same re-entrancy reason as finalizers, §6.2) or conservative scanning of Rust memory (rejected: `MM-VAL-2` gives no way to tell a handle from an integer, which is the same reason the deleted collector was "conservative and wrong").
> *Failure mode.* Unbounded growth, **stable and safe** — no object is ever freed early. This is strictly the better half of the two failure modes, and under `MM-FFI-19`'s zero floor it is the *only* half the design admits.
> *Mitigations, in order of preference.*
> 1. **Prefer the unowned edge.** When Rust can prove its slot does not outlive the Axiom object — the common case for a handle whose lifetime is a `with-foreign` scope — the slot **SHOULD** hold the bare `i64` with no share taken, not an `AxRef`. This breaks the cycle by construction. It is Swift's `unowned`, and it carries Swift's obligation: a stale read is a use-after-free, so it is legal only inside a scope that dominates the Rust value's life. In v0, where `MM-FFI-19`(a) forbids taking a share at all, this is not merely preferred — it is the only option.
> 2. **Audit.** `ax_ffi_report_open()` **SHOULD** be generated for every registry, walking the slot table and reporting index, generation, and type name for every occupied slot. Called at exit under a debug flag, it turns "leaks somewhere" into a list. It costs a loop over a static array and no allocation, so it is `no_std`-compatible.

---

### 9. Process, threads, and fork

`MM-PAR-1` is not a missing feature the FFI can quietly supply. `MM-PAR-3`/`I11` — *every* process-wide mutable global is private after `fork` and fresh after `exec` — is what lets the allocator have **no atomics, no lock, and no TLS**. Read the retain path again with that in mind (codegen.ax:2283-2287): `load`, `add`, `store`. Non-atomic. And `axiom_alloc`'s fast path (codegen.ax:2088-2093): `load @__axiom_bump`, `add`, compare, `store`. Non-atomic.

> **MM-FFI-30 (P, programmer-obligation, partly backed by types). One Axiom thread, for the process's life.** Every call into `@main`, `@__axiom_user_main`, any Axiom function, `axiom_alloc`, `axiom_retain`, or `axiom_release` **SHALL** occur on a single thread, fixed at initialisation.
> *Rationale.* Two threads in `axiom_alloc`'s fast path can both observe `%fits` and both store `%next` — two live values at the same address, with the loser's block never accounted. Two threads decrementing a count can both read 1 and both take the dead path — the block is pushed onto `@__axiom_slabs` **twice**, and the next two allocations of that class get the same memory.
> *Failure mode.* Silent aliasing of unrelated objects, appearing under load only.
> *Enforcement, by direction — and the earlier draft's token was not implementable.*
> - **Axiom-host direction (`MM-FFI-26`: `#![no_std]`).** The mechanism is `!Send` + `!Sync` on `AxRef` and on every generated handle wrapper, via `PhantomData<*const ()>`, **plus** the link gate of `MM-FFI-31`/`MM-FFI-37`. There is **no thread-id assertion**: a `no_std` crate has no thread-id API, and every route to one — `pthread_self`, `thread_*`, `_tlv_bootstrap` — is a symbol `MM-FFI-31`'s allowlist forbids by design. The earlier draft required a token that "records the initialising thread id and in debug builds asserts the thread id on every call"; that is self-contradictory under `no_std` and is withdrawn here.
> - **Rust-host direction (§6b, std present).** The generator **SHALL** emit an `AxiomRt` token, obtained once at `MM-FFI-36`'s entry, non-`Send`, required *by type* to reach any Axiom entry point, recording the initialising `ThreadId` and asserting it on every call in debug builds. Here it is implementable, because std exists.
> - **The deliberate exception.** `impl Drop for AxRef { fn drop(&mut self) { … } }` receives only `&mut self` and by Rust's signature **cannot** take a token. `Drop` is therefore outside the token discipline in both directions; `!Send`/`!Sync` on `AxRef` is what confines it, and `MM-FFI-21` is the second reason not to drop Axiom values off the Axiom thread. Naming this exception is better than pretending the token covers everything, because an implementer who discovers it alone will assume the whole rule is decorative.

> **MM-FFI-31 (P, generator-enforced, link-gate). The link allowlist forbids the *named* routes to a thread — and is necessary, not sufficient.**
> `MM-FFI-5` requirement 4 replaces the blanket ban with a gate that **enumerates permitted external symbols**. That gate catches every *conventional* way to make a thread: `pthread_create` on both supported platforms, and `bsdthread_register` plus `tlv_get_addr` on Darwin, all of which `MM-PAR-2` already names as living in libSystem. A `no_std` crate cannot reach `std::thread` at all; a crate that declares `pthread_create` itself puts it in `nm -u`, where the allowlist refuses it. The gate is transitive over the whole dependency graph for free, which is its real value.
> **It does not, however, decide the question, and an earlier draft's claim that it does — "Thread creation is not expressible without an external symbol", "Static analysis of the crate source is not required and should not be attempted" — is false, with Axiom's own runtime as the counterexample.** `__syscall0..__syscall6` lower to `call i64 asm sideeffect` (codegen.ax:1887-1919); `bootstrap/axiom-darwin-aarch64.ll` has **0** `declare`s and `nm -u` on a built executable is **empty**, and yet that program calls the kernel freely. The identical mechanism is available verbatim to a `#![no_std]` Rust crate: `core::arch::asm!` issuing `clone`/`clone3` on Linux or `bsdthread_create` on Darwin appears in `nm -u` as **nothing at all**. A gate that only enumerates undefined symbols therefore does not enforce `MM-FFI-30`, and `MM-FFI-30` is the rule that keeps the non-atomic refcount and the non-atomic bump pointer sound.
> *Gate obligations, concretely:* the allowlist **MUST** exclude `pthread_*`, `bsdthread_*`, `_tlv_bootstrap`, `thread_*`; and the gate **MUST** additionally assert that `__mod_init_func` / `.init_array` are **empty**.
> *Corrected rationale for the constructor ban.* The earlier draft justified it with "a Rust static constructor would allocate before the allocator's globals are meaningful". **That is false and an implementer will disprove it in five minutes.** The allocator's globals are `internal global i64 0` (codegen.ax:2007-2028: `@__axiom_bump`, `@__axiom_bump_end`, `@__axiom_chunk`, `@__axiom_free`, `@__axiom_high`, and `@__axiom_slabs` `zeroinitializer`), and the fast path (codegen.ax:2088-2093) computes `%fits = icmp ule %next, %end` against `end = 0`, fails it, and falls into `refill`, which mmaps a chunk. **Allocation before `main` works.** The real pre-`main` hazard is the *other* half: `@main` stores **only** argc and argv (codegen.ax:1994-2001), so a constructor that calls into Axiom code touching `__argc`/`__argv`/`sysArg` reads **0**. That is a narrower failure than the draft claimed, and stating it accurately is what keeps the rest of the rule trusted.

> **MM-FFI-37 (P, generator-enforced, source-gate). No inline assembly in bound crates.** Because `MM-FFI-31`'s undefined-symbol allowlist is necessary and not sufficient, the gate **MUST** be paired with a source-level restriction over the whole bound dependency graph: `core::arch::asm!` and `global_asm!` **MUST NOT** appear in any crate linked into an Axiom-host program.
> *Mechanism.* `#![forbid(asm)]` does not exist, so this is enforced by one of: (a) a `RUSTFLAGS`-driven lint/deny configuration applied across the graph, (b) a source scan of the vendored graph for `asm!`/`global_asm!`/`#[naked]`, or (c) restricting bound crates to a **vetted set** — which is the only option that is actually robust, since a macro can spell `asm!` indirectly and a build script can emit an object file the scan never sees.
> *Rationale.* Without it, `MM-FFI-30`, `MM-FFI-32` and `MM-FFI-38` are conventions rather than checks. With it, they are as enforced as the vetting is careful, which is an honest statement of the guarantee's strength.
> *Failure mode.* Everything in `MM-FFI-30`: a Rust-spawned thread racing the non-atomic bump pointer and the non-atomic refcount, with `nm -u` still clean and the gate still green.
> *Stated limit.* This is a **process** control, not a proof. Do not describe the FFI's thread-freedom as decidable.

> **MM-FFI-32 (P, structural — Axiom-host fork/exec window).** In the Axiom-host direction there is **no call site for Rust between `fork` and `execve`**, and the design **MUST** keep it that way.
> *Rationale, measured per platform.* On Darwin, `sysSpawn` uses the `posix_spawn` **syscall** (stdlib/Sys.ax:709-721) — there is no in-process fork and the question does not arise. On Linux it is a raw `fork` (stdlib/Sys.ax:744) and the child executes exactly two syscalls — `execve`, then `exit(127)` if that fails (stdlib/Sys.ax:755-756). **The window is Rust-free by construction, not by allowlist.** The earlier draft credited the allowlist ("forbids `pthread_atfork` and `pthread_create`, which is what makes the window Rust-free"); that inherits `MM-FFI-31`'s hole — a raw `fork` or a registered `atfork` handler reached through `asm!` is equally invisible — and it also understates the actual guarantee, which is stronger: there is no code in that window to be foreign.
> *What preservation requires.* `MM-PAR-3` and `I11` hold exactly: the allocator's five words, the argc/argv pair, the effect slots, and the 4097 slab heads are all still process-private, and a Rust slot table in `.bss` inherits by copy like everything else — correct, because it is not shared with the parent after fork and the child immediately execs. The obligation is simply that `sysSpawn`'s child path **MUST NOT** grow a call into Rust.
> *Failure mode if it did.* The classic one: a Rust runtime holding an internal lock on another thread at fork time deadlocks the child, which then neither execs nor exits, and `sysWaitPid` blocks forever.

> **MM-FFI-38 (P, programmer-obligation — Rust-host fork). A std Rust host MUST NOT `fork` while Axiom state is live.** In the direction §6b describes, the host is an ordinary std binary that may have threads, and `fork` from such a process is the hazard `MM-FFI-32` does *not* cover: the child inherits a copy of the Axiom allocator's globals mid-mutation if any thread was inside `axiom_alloc` or `axiom_release` at fork time, and inherits every Rust lock in whatever state its holder left it.
> *Rationale.* `MM-PAR-3`'s by-construction safety is a statement about *Axiom's* globals in *Axiom's* process. It says nothing about a foreign host's, and nothing about a fork the host initiates. This rule is the one the first draft was reaching for and stated against the wrong direction.
> *Obligation.* If a Rust host must fork, it **SHALL** do so before `MM-FFI-36`'s entry, or **SHALL** guarantee the child does nothing but `exec`. Calling any Axiom entry point in a forked child of a multithreaded host is undefined.
> *Failure mode.* A child that allocates from a bump pointer copied mid-update, or deadlocks on a lock whose owner does not exist.

> **MM-FFI-33 (P, generator-enforced). Panics and ownership.** In the Axiom-host direction, `panic = "abort"` is **required** (C6, `MM-FFI-26`) and `catch_unwind` is **forbidden**. In the Rust-host direction, where std is already present, a shim **MAY** use `catch_unwind`, but **MUST NOT** hold an `AxRef` or any live Axiom handle across the caught region.
> *Rationale.* `catch_unwind` requires std, and std forfeits the freestanding property (measured: 188 undefined symbols, `_Unwind_*` among them). Where it is available, unwinding runs `Drop`, so an `AxRef` held across the boundary would call `axiom_release` *during* a panic — reclamation ordered by unwind rather than by program text, which is the one thing `MM-EXEC-11`'s determinism argument for ARC does not cover.
> *Failure mode.* With `abort`: none, the process dies (a retain leaks; irrelevant). With `catch_unwind` and a held `AxRef`: a release at an arbitrary point, potentially filing a block that a half-completed Axiom operation still names.

---

### 10. Consolidated rule index

| # | § | Rule | Enforcement |
|---|---|---|---|
| MM-FFI-6 | 1 | Three populations; membership is static and recoverable from the declared type | compiler |
| MM-FFI-7 | 2 | **A foreign word's map bit is clear; it never reaches retain/release.** The obligation is classifier registration, not a call-site list | compiler |
| MM-FFI-8 | 3.1 | Foreign types are built-in nullary cons — never `data`, `struct`, alias, or applied | compiler |
| MM-FFI-9 | 3.2 | `fldClass` 0 (its `1` = leaf/leak, unsafe default); `evClassOf` 0 (its `1` = reference/UAF, safe default) | compiler |
| MM-FFI-10 | 3.3 | Foreign witnesses `0` in the evidence word; mixed positions meet to `0` | compiler |
| MM-FFI-11 | 3.4 | Boundary type safety is established by the generator; the checker is a backstop | generator |
| MM-FFI-12 | 4.1 | Axiom values are borrowed for exactly the call | generator (+ rustc) |
| MM-FFI-13 | 4.2 | Bytes cross as (ptr, len); never as a C string | generator |
| MM-FFI-14 | 4.2 | Public shim signatures expose no raw pointers and no `'static` borrows | generator |
| MM-FFI-15 | 4.2 | Rust copies anything it keeps — the v0 discipline | programmer |
| MM-FFI-16 | 4.3 | Rust-written buffers come from `memAlloc`, never from a literal | programmer |
| MM-FFI-17 | 5.1 | Nameable runtime surface, enumerated **by direction**; allocator globals stay `internal` | generator |
| MM-FFI-18 | 5.2 | **Rust must not retain a borrowed argument** (birth-0 blocks; measured) | generator |
| MM-FFI-19 | 5.3 | **The zero floor: no FFI-side operation drives a count to zero.** v0 ships no rooting; a later pin protocol pins permanently and unpins through a floored `@axiom_ffi_release`. `AX3039` | compiler + programmer |
| MM-FFI-20 | 5.3 | One release per share; `AxRef` is not `Clone`/`Copy`; a double release corrupts the free-list **link** | programmer |
| MM-FFI-21 | 5.3 | Release recursion depth is graph depth | programmer |
| MM-FFI-22 | 6.1 | Opaque handles are generation-tagged slot indices, not raw pointers | generator |
| MM-FFI-23 | 6.2 | No finalizers; explicit close | programmer |
| MM-FFI-24 | 6.2 | Close is idempotent; use-after-close is detected, not UB | generator |
| MM-FFI-25 | 6.2 | `with-foreign` (flat spelling) bodies do not tail-call out and do not let the handle escape | programmer |
| MM-FFI-26 | 6.3 | `no_std` + `panic="abort"` + **`edition = "2024"`**; `alloc` only over `axiom_alloc`, no-op `dealloc`, **null above align 16** | generator (link gate) |
| MM-FFI-27 | 7 | No arena primitive accepts a foreign type | compiler |
| MM-FFI-28 | 7 | No reset past a mark taken before an outstanding `Foreign` | programmer |
| MM-FFI-29 | 8 | A boundary-spanning cycle leaks; prefer unowned edges; audit the registry | programmer |
| MM-FFI-30 | 9 | One Axiom thread for the process's life; token is **Rust-host only**; `Drop` is the stated exception | programmer (+ `!Send`) |
| MM-FFI-31 | 9 | The link allowlist is **necessary, not sufficient**; empty `.init_array` (real reason: argc/argv unset) | generator (link gate) |
| MM-FFI-32 | 9 | The Axiom-host fork/exec window is Rust-free **by construction**; keep it so | structural |
| MM-FFI-33 | 9 | `panic="abort"` when Axiom hosts; no Axiom handles across `catch_unwind` | generator |
| MM-FFI-34 | 6b.1 | **An Axiom return value is borrowed**, valid until the next Axiom call or arena op; copy it; never release it | generator + programmer |
| MM-FFI-35 | 6b.2 | A Rust-built `axiom_alloc` block is **birth-0 and a leaf**; the builder must stamp the map, per `memAllocMapped` | programmer |
| MM-FFI-36 | 6b.3 | The Rust-host entry contract: call the renamed `@main` once, on the owning thread, before anything else | generator |
| MM-FFI-37 | 9 | **No inline assembly** in bound crates; vetting is the only robust form | generator (source gate) |
| MM-FFI-38 | 9 | A std Rust host must not `fork` while Axiom state is live | programmer |

---

### 11. What is genuinely unresolved

Stated plainly, because each of these is a place a confident sentence would be a lie.

1. **`cast` is a hole in every compiler-enforced rule here.** `MM-FFI-27` and `MM-FFI-9` both rest on `tyCompat`'s name equality, and `(cast Int p)` produces an `Int` that satisfies every arena primitive. `MM-LIFE-2g` already records `cast` as "the marker for leaving the type system", and its own §10 position is that keeping such a value alive is the program's obligation. The FFI inherits that position and cannot improve on it without a real effect or capability system. **No mitigation is proposed; the gap is named.**

2. **`MM-FFI-16` has no enforcement at all.** `strData` of a literal and of a `strAlloc` buffer have the same type and the same shape, and the checker's only representational lever is the *declared-return* check (`checkDeclaredReturn`, typecheck.ax:7020). Distinguishing a writable buffer from a loader-resident one needs a mutability distinction the language does not have and `TAG_T_PTR`'s `mut` word does not reach. A convention (a distinct `Buf` foreign type minted per `MM-FFI-8`, obtainable only from `memAlloc`) would work but is unproven, and it does not stop `(cast Buf (strData "x"))`.

3. **The zero floor is a workaround for incomplete ARC, and it should be deleted.** `MM-FFI-19` exists only because there is no invariant "a value visible to a callee has count ≥ 1" — birth-0 blocks (`axiom_alloc` at codegen.ax:2242, every `Str` header at stdlib/Str.ax:70) make a balanced retain/release pair a *free*, and the measured transcript in §5.2 shows it costing a live string in three lines of Axiom. The day events 2 and 3 ship for call results, that invariant becomes true; `MM-FFI-19`'s pin degenerates into an ordinary retain, `MM-FFI-34`'s "returns are borrowed" flips to "returns are owned", and `@axiom_ffi_release` can be retired. `MM-LIFE-2a`'s measurement (docs/memory-model.md:1660-1676) says that day arrives **when the corpus's containers name their element types, not when the compiler changes**. **This spec should be revisited then, not before.**

4. **The array-form element bit is still `P`.** `MM-LIFE-2d` lists the array form's writers and the container buffer migration as unimplemented. `MM-FFI-10` is written against a mechanism (`evMeet` collapsing to 0) that today has no consumer for containers. When the migration lands, a `Vec` holding foreign words must be re-checked against this rule; the safe answer is already the default, but "safe by absence of the feature" is not the same as "safe by design", and this section claims only the former.

5. **A `Foreign` inside an untyped container is unchecked, end to end.** `Vec`, `Map` and every AST node word take type variables and `cast` at the machine boundary. Nothing prevents `(vecPush v p)` for a foreign `p`, and nothing distinguishes it later from a `String` handle at the point of retrieval. `MM-FFI-22`'s generation tag is what converts this from UB into a detected error — which is the entire argument for paying for the indirection, and it is why the raw-pointer alternative should be refused even when it looks obviously faster.

6. **`__ffi_pin`'s `AX3039` refusal has no measured false-positive rate, and v0 sidesteps rather than solves it.** `evClassOf` answers `1` only for `TAG_T_ARR`, non-empty `TAG_T_TUP`, `TAG_T_LIST`, `String`, and declared data/struct names (typecheck.ax:596-612). Every value this repository holds behind an `Int`-declared handle — which is most of them — would be **refused**. `MM-FFI-19`(a) resolves this for now by not shipping the protocol at all; if it ever ships, the diagnostic's practical usability **MUST** be measured against a real corpus before the message is written, not assumed.

7. **`MM-FFI-37` is a process control, not a proof, and it is the weakest link in the thread story.** The undefined-symbol allowlist is decidable and transitive; the inline-assembly restriction is neither. A `build.rs` that emits an object file, a proc macro that spells `asm!` after expansion, or a vendored crate updated without re-vetting all defeat it. Since `MM-FFI-30` is what keeps the non-atomic refcount and the non-atomic bump pointer sound, **the FFI's thread-freedom guarantee is exactly as strong as the crate-vetting process and no stronger.** Say that out loud in the gate's documentation rather than implying the linker settles it.

8. **The Rust-host direction (§6b) has been designed but not measured beyond the smoke test.** Experiment 3 proved linkage, entry, and one scalar call. Nothing has yet measured a returned heap value's count in that configuration, a Rust-built mapped block surviving an Axiom release walk, or `MM-FFI-36`'s entry being called from a thread that later spawns others. `MM-FFI-34` and `MM-FFI-35` are derived from the emitter, which is the right way to derive them, but they should be confirmed against a running binary before the generator commits to them.
---

## 8. Safety Model, Unsafe Boundaries, and Error Propagation

This section is normative for the v0 FFI. Rules are identified `FFI-SAFE-n`, `FFI-PANIC-n`, `FFI-ERR-n`, `FFI-LINK-n`, following the discipline of `docs/memory-model.md` and `docs/error-model.md`: never renamed, never reused, and marked **H** (holds against a measured fact), **P** (planned), or **R** (refused).

### 0. Relationship to the shipped `rust/` workspace

**This section was drafted as if the Rust side did not exist. It does**, and it already fixes a wire contract. `rust/` is a populated cargo workspace — `rust/Cargo.toml`, `axiom-abi`, `axiom-ffi`, `axiom-ffi-macros`, `axiom-bindgen`, `examples/demo` — with a gate (`scripts/check-ffi.sh`) that builds it. Every rule below is now written against that code. Where this section **supersedes** it, the change is named, the file is named, and `ABI_VERSION` is bumped.

**FFI-ABI-0 (P). The shipped contract is adopted; four things are superseded, and `ABI_VERSION` goes 1 → 2.**

Adopted unchanged from the shipped crates:

| Adopted | Site |
|---|---|
| **Positive status encoding** `AX_OK = 0`, `AX_ERR = 1`, `AX_PANIC = 2` | `rust/axiom-abi/src/lib.rs:48-52` |
| **`AxBytes` message transport** — Rust hands out owned bytes, Axiom copies, Axiom calls back to free | `rust/axiom-ffi/src/lib.rs:60-90` |
| **`axffi_free_bytes`** as the free callback | `rust/axiom-ffi/src/lib.rs:98-108` |
| **`axffi_abi_version` / `ABI_VERSION`** as the wire fingerprint | `rust/axiom-ffi/src/lib.rs:110-121` |
| **`#[axiom_export]`** as the attribute; fallibility inferred from a `Result` return | `rust/axiom-ffi-macros/src/lib.rs:128-129`, `:240-241` |
| **`(pub extern (name (p : T) …) Ret #:symbol … #:lib … #:effect io)`** as the declaration syntax | `rust/axiom-bindgen/src/main.rs:151-172` |
| **`f64::from_bits` / `to_bits` in the shim** — U14's defence, already implemented | `rust/axiom-ffi-macros/src/lib.rs:186`, `:304`, `:315` |

Superseded, with the full change list:

1. **The out-cell gains a third word.** `AxOutCell` (`rust/axiom-abi/src/lib.rs:308-313`) becomes `#[repr(C)] { payload, extra, code }`. This is **additive**: offsets 0 and 1 are unchanged, so every shim that writes `payload`/`extra` today stays correct. The third word is what lets an FFI domain code reach `Error.code` without colliding with `stdlib/Err.ax`'s own codes (`FFI-ERR-2`). *Changes:* `rust/axiom-abi/src/lib.rs:308-313`; the Axiom glue's cell allocation becomes `(memAlloc 24)`.
2. **A fourth status, `AX_POISONED = 3`.** Required by `FFI-PANIC-4`; there is no free encoding for "the shim was never entered" in `{0,1,2}`. *Changes:* `rust/axiom-abi/src/lib.rs:48-52`, re-exported at `rust/axiom-ffi/src/lib.rs:48-51`.
3. **The Axiom surface error type is `Error`, not `String`.** `rust/examples/demo/src/lib.rs:40-41` and `rust/axiom-bindgen/src/main.rs:158-160` produce `(Result T String)`. That discards the code and the context word, and `docs/error-model.md`'s propagation rules (`withContext`, `try!`, `ERR-TYPE-3a`) are all written against `Error`. *Changes:* `rust/axiom-bindgen/src/main.rs:159` `format!("(Result {} String)")` → `format!("(Result {} Error)")`; the generated glue gains `(import Err)`; the demo's comment at `rust/examples/demo/src/lib.rs:40-41` is restated.
4. **The attribute's argument list is refused rather than discarded.** `pub fn axiom_export(_attr: TokenStream, …)` (`rust/axiom-ffi-macros/src/lib.rs:128-129`) silently throws away anything written inside the parentheses. In ABI v0 the attribute **takes no arguments**: `_attr` becomes `attr`, and a non-empty `attr` is a `syn::Error` reading *"`#[axiom_export]` takes no arguments in ABI v0; fallibility is inferred from a `Result` return type, and the module and library names come from `axiom-bindgen --module` / `--lib`."* A discarded argument is how a `#[axiom_export(fallible)]` that the author believed was load-bearing becomes a silently infallible shim. *Changes:* `rust/axiom-ffi-macros/src/lib.rs:128-134`. Earlier drafts of this section wrote `#[ax_ffi(module = "Fs", fallible, message)]`; that macro does not exist and every one of those arguments would have been discarded. All examples below use `#[axiom_export]`.

`ABI_VERSION` (`rust/axiom-ffi/src/lib.rs:121`) goes to **2**, which its own doc comment already requires: it says to bump on any change to "the out-cell shape, or the status encoding", and this changes both. `axffi_abi_version` is the wire fingerprint; **the manifest content hash proposed by `FFI-SAFE-2` is a different object with a different job** — it fingerprints *which bindings* exist, not *how a word is shaped* — and both are checked, the version at link, the hash at regenerate-and-diff.

Three things the shipped code has that the earlier draft did not account for at all, and which are now normative:

- **`axffi_free_bytes` is an extern in the Axiom → Rust direction.** The generated glue must declare it, it must appear in the manifest, and it is subject to every rule here.
- **The `axffi_*` prefix is owned by the runtime facade** (`axffi_free_bytes`, `axffi_abi_version`, and every generated shim, plus hand-written destructors like `axffi_counter_close` at `rust/examples/demo/src/lib.rs:66-75`). It joins `AX3042`'s reserved set (§9).
- **`AX_PANIC` is currently dead.** There is no `catch_unwind` anywhere in `rust/`, so no shim can ever produce it. `FFI-PANIC-3` is what makes it reachable, and only in the hosted profile.

---

### 1. The trust boundary has three parties, and only one of them can check anything

The single most important fact about this design is negative, and every rule below is downstream of it.

**The Axiom type checker cannot enforce the boundary.** `tyCompat` (`self_host/typecheck.ax:188-235`) is the entire relation. It refuses two *known, differently-named, argument-free* constructors — the `String`/`Int` fiat was deleted 2026-08-15 and the constructor arm now compares `nodeA` for equality — but a type variable on either side matches anything (`tyVarCompat`, reached at `typecheck.ax:200`), poison matches anything (`typecheck.ax:197-199`), and `mkSilentWild` is `(mkTVar "")` (`typecheck.ax:136`), which is what the checker mints for every expression form it has no case for (`typecheck.ax:3198`), for a signature-less effect op (`typecheck.ax:1869`), and for a struct field with an unparsed type (`typecheck.ax:2719`). There is no unification and no substitution; `tyInst` freshens without solving. On top of that, `(cast T e)` type-checks `e` not at all — `checkCastForm` (`self_host/typecheck.ax:4405-4457`) checks arguments from index 1 and hands back `T` — and the tree uses it constantly.

> *Citation corrected.* Earlier drafts placed `checkCastForm` at `:4537`/`:4552+`. Lines 4533-4570 are `checkSaturation`, which this section separately and correctly cites at `:4534-4570` — so the two functions were being given the same address. The claim itself holds exactly as stated.

So a declared `Foreign` parameter will refuse a *statically known* `Int` argument, and will silently accept a `(cast Foreign anInt)`, a container read, a polymorphic `match` binder (`ERR-TYPE-3a`/B5), or anything returned by a signature-only name.

**FFI-SAFE-1 (H). The compiler guarantees exactly four things, and no more.**

1. **Shape.** Every extern crosses as `i64` per parameter and `i64` returned, in the module's one attribute group `#0 = { "no-builtins" }` (`self_host/codegen.ax:2805`). No varargs, no calling-convention marker, no parameter attributes — therefore no `noalias`, `nonnull`, or `zeroext` promise is made *or* required by the emitted IR.
2. **Monomorphism.** No extern carries the hidden trailing `i64 %__evw.h` (`codegen.ax:3008-3021`, passed at `codegen.ax:5925`). Enforced by refusal, not by convention — see `FFI-SAFE-4`.
3. **Effect.** Every extern call site is inside a function whose inferred effect set contains `b:Ffi`, transitively, by the existing monotone fixpoint (`typecheck.ax:5200-5241`).
4. **Non-collision.** No extern names a symbol the emitted runtime or the FFI facade owns.

Everything else — that the Rust function has the arity you declared, the widths you declared, the null-tolerance you assumed, the lifetime you assumed — is **outside the compiler's knowledge and always will be**, because `tyCompat` is the whole unifier and three attempts to replace it were merged and withdrawn (`5f2a616`→`053c525`, `6ff9e2c`→`9d5b508`).

**FFI-SAFE-2 (P). The binding generator guarantees the type mapping.** `axiom-bindgen` reads Rust's real types (via `syn` over the annotated crate, `rust/axiom-bindgen/src/main.rs:187-215`) and emits *both* sides from one description: the `extern "C"` shim (through `axiom-ffi-macros`) and the Axiom `extern` declaration plus its wrapper. It is the only party in the system that ever sees two type systems at once, so it is the only party that can compare them. **Its two passes must agree** — `classify` in `rust/axiom-ffi-macros/src/lib.rs:53-95` and `axiom_ty` in `rust/axiom-bindgen/src/main.rs:187-215` are separate implementations of one mapping, and `check-ffi.sh`'s regenerate-and-diff is what notices a drift. Its output carries a content hash of the binding set, distinct from `ABI_VERSION` (`FFI-ABI-0`).

**FFI-SAFE-3 (H, program obligation). The programmer guarantees the four things neither tool can see:** that a pointer handed across is valid for the length claimed; that two buffer parameters do not alias; that a `Foreign` handle is closed exactly once; and that an exported Axiom function is not re-entered while it holds an arena mark. Each is named individually below rather than left as "be careful".

**FFI-SAFE-4 (P). The safety property is enforced at the gate, not the declaration.** A hand-written `extern` **MUST** compile — the language cannot make itself depend on a Rust tool that is not present at bootstrap, and `scripts/bootstrap-from-seed.sh` stays cargo-free. What is refused is *shipping* one: `scripts/check-ffi.sh` (`MM-FFI-5` requirement 4, already in the tree) fails a build whose extern set is not exactly the manifest's extern set, by symbol and by arity. This is the honest placement. The declaration is a claim; the gate is the check.

---

### 2. How a program signals it is taking on FFI risk

**FFI-SAFE-5 (P). Risk is signalled three times, at three different granularities, and none of them is a compiler flag.**

| Granularity | Mechanism | Who reads it |
|---|---|---|
| The declaration | the `extern` form itself | the checker, `axiom symbols`, the reader |
| The call graph | a new built-in effect `Ffi`, seeded at registration and inferred transitively | `inferEffects`, AX3010, `axiom symbols` |
| The program | the FFI allowlist manifest (`axiom-allow.txt`) replacing the blanket ban | `scripts/check-ffi.sh` |

**Alternatives considered and rejected.**

*A compiler flag (`--allow-ffi`).* Rejected: it is invisible in the source, invisible to `axiom symbols`, invisible to a reviewer reading a diff, and it does not survive into an imported module. The property "this function reaches outside the process" has to travel with the function, not with the build command. (Note that `--link-lib` / `--link-search` in `FFI-LINK-1` are *not* this: they say where an archive is, not that reaching outside is permitted.)

*An AXTAG (`;@axiom:unsafe`).* Rejected, and the reason is measured: AXTAGs are *claims the compiler checks*, not enforcement. `AX3010` is the only warning stage1 emits — constructed by `emitAxtag` at `self_host/typecheck.ax:6871-6879` — and the whole tag mechanism is a comment scanner (`self_host/lexer.ax:532-586`) that a single apostrophe once silently disabled for a whole file. An unenforced comment cannot be the thing that unlocks a hazard.

> *Citation corrected.* Earlier drafts cited AX3010's site as `typecheck.ax:4940-4945`, which is a comment header, not an emission site.

*A per-declaration marker only.* Insufficient on its own: it tells you which declarations are externs but not which of the 40k lines of your program can reach one. That is what the effect is for.

**FFI-SAFE-6 (P). `Ffi` is a new built-in effect, and this costs nothing extra.** Concretely: add `"Ffi"` to `isBuiltinEffect` (`typecheck.ax:3088-3092`) and map `ffi` in `axtagEffectOf` (`typecheck.ax:6845-6851`). Registration seeds `FnEnt` word 5 with **both** `(builtinEff "IO")` and `(builtinEff "Ffi")`, exactly as `tcAddEffectOp` pre-seeds an effect operation's entry (`typecheck.ax:1866-1876`) — the model to follow, because after that the fixpoint at `typecheck.ax:5200-5241` propagates it through the call graph for free and no walk needs a special case.

Why `IO` *as well as* `Ffi`: a foreign call can do anything a syscall can, and `isSyscallPrim` (`typecheck.ax:5029-5034`) adds `b:IO` at both the call-position walk (`typecheck.ax:4889-4890`) and the value-position walk (`typecheck.ax:4929-4930`). Anything in the tree that already refuses `IO` must refuse this too; anything that wants to distinguish "reaches the kernel" from "reaches Rust" reads the second name. The shipped bindgen already emits `#:effect io` (`rust/axiom-bindgen/src/main.rs:169`); that line becomes `#:effect ffi` and the seeding adds `IO` on top.

The objection that a new built-in costs a seed rebuild — `ERR-TYPE-2`'s stated reason for shipping `Result` as an ordinary declaration — does not apply here, because the extern form already forces a seed rebuild. **The full plumbing list, which earlier drafts left incomplete in the one place that decides whether the type exists at all:**

| Site | File | What it needs |
|---|---|---|
| `typeKeywordCanon` | `self_host/parser.ax:1620-1628` | **`"Foreign"` added.** Without it `Foreign` is not a type. |
| declaration tag 53 | `self_host/parser.ax:100-104` | 29 is retired permanently; 53 is next free |
| `tcCollect` | `typecheck.ax:1669-1782` | a tag-53 arm; it falls through to 0 otherwise |
| `declNamespace` | `typecheck.ax:790-796` | tag 53 → `NS_VALUE` |
| `ambBuildDecl` | `typecheck.ax:3657-3669` | tag 53 as a definer, for AX3014 |
| `tcCheckSigTypes` | `typecheck.ax:2612-2626` | a tag-53 arm |
| `emitDecl` | `codegen.ax:2817-2846` | a tag-53 arm; emits `TAG_D_FN` only and drops the rest in silence |
| `scanFloatSigs` | `codegen.ax:339-349` | a tag-53 arm registering an `FSig` |
| `scalarTyName` | `codegen.ax:6134-6148` | **`"Foreign"` added** |
| `evScalarName` | `typecheck.ax:542-556` | **`"Foreign"` added** |
| `isBuiltinEffect` | `typecheck.ax:3088-3092` | `"Ffi"` |
| `axtagEffectOf` | `typecheck.ax:6845-6851` | `ffi` |

Two of these were missing from every earlier draft and each is load-bearing:

- **`typeKeywordCanon` decides whether `Foreign` is a type at all.** `tyConKnown` (`typecheck.ax:2415-2427`) accepts a constructor name only if `typeKeywordCanon` (`parser.ax:1620-1628`: Int, Integer, Float, Bool, Char, String, Void, Unit, Any) answers non-zero, or the name is `Linear`, or it resolves to a `data`/`struct`/alias. Until `"Foreign"` is added there, every `(:: f (-> Foreign Int))` draws `AX3002 undefined-type` (`typecheck.ax:2641-2654`).
- **`tcCheckSigTypes` walks `TAG_D_SIG` only** (`typecheck.ax:2612-2626`), so an extern carrying its signature inline on tag 53 gets no AX3002 sweep at all — a typo'd type name in an extern signature would be *silent*. The tag-53 arm restores it.

`isBuiltinEffect` already answers 1 for `"Err"` and `"Pure"`, which nothing in the tree ever constructs; one more string in that `if` is free.

**Known consequence, stated rather than discovered later:** because `effHandledBy` (`typecheck.ax:4838-4848`) matches a built-in name in a `handle` list and `checkHandleEffects` (`self_host/typecheck.ax:5362-5405`, skipping built-ins at `:5373`) skips built-ins before the AX3016 lookup, `(handle body (Ffi) …)` will be *accepted and inert* — it suppresses the AX3011 line without installing anything, because `handleIsDynamic` (`typecheck.ax:4851-4861`) requires a non-built-in with a declaration. That is exactly the status quo for `IO` and is not made worse. It is not a recovery mechanism and `ERR-REC-3` already explains why no effect ever will be.

> *Citation corrected.* `checkHandleEffects` is at `:5362-5405`, not `:3070+`.

---

### 3. Safe and unsafe, enumerated in both languages

**FFI-SAFE-7 (P). The classification.**

**Axiom side.** Axiom has no `unsafe` keyword and this design does not add one — the effect *is* the marker, and adding a second one would give two answers to one question. What "unsafe" means here is: *the operation's correctness is not derivable from anything the compiler read.*

| Operation | Class | Why |
|---|---|---|
| writing an `extern` declaration | **assertive** | it is a claim about a symbol in another translation unit; nothing verifies it at declaration time |
| calling an extern through its generated wrapper | **safe iff the declaration is true** | the wrapper is generated, checked against the manifest by the gate |
| calling an extern directly (bypassing the wrapper) | **unsafe** | the wrapper is where the out-cell, the `axffi_free_bytes` pairing, and `Result` construction live |
| holding a `Foreign` in a `let`, a field, a `Vec` | **safe** | it is a repr-scalar; ARC never walks it (§4, U7) |
| any arithmetic on a `Foreign` | **refused** — AX3041 | it is opaque by construction (`MM-FFI-5` req. 1) |
| `__load8`/`__load64`/`__store*`/`memAlloc`/`__axiom_arena_reset_keeping` on a `Foreign` | **refused** — AX3041 | `MM-FFI-5` req. 2; `MM-FFI-3` says such memory is outside every arena |
| `(cast Foreign x)` / `(cast Int f)` | **unsafe, permitted** | `cast` is a bit reinterpretation the tree depends on (`stdlib/Str.ax:79`); refusing it here would be a language change with no way to spell the escape hatch. This is the hole; §10 says so. |
| passing a `String` to an extern | **safe** | the shim borrows through `AxStr::from_raw`, reading `len` from word 0 and `data` from word 1 of the header (`rust/axiom-abi/src/lib.rs`, verified against `stdlib/Str.ax:126-141`) |
| closing a `Foreign` | **program obligation** | there are no finalizers (`MM-EXEC-17`, `docs/memory-model.md:421-423`) |

**Rust side.** Every generated shim body is *safe Rust*. Unsafety is confined to a small set of helpers, each written once per crate and reviewed once:

| Operation | Class | Notes |
|---|---|---|
| the `#[no_mangle] pub extern "C"` shim body | safe | takes `i64`s, returns `i64` |
| `AxStr::from_raw` → `as_bytes` / `as_str` | `unsafe fn` | `slice::from_raw_parts`; the length is Axiom's, not derived |
| `AxOutCell::from_word` | `unsafe fn` | writes into an Axiom-allocated leaf block |
| `AxOpaque::<T>::borrow` / `borrow_mut` | `unsafe fn` | reconstitutes a `&T`/`&mut T` from a `Box::into_raw` word |
| `axiom_retain` / `axiom_release` | `unsafe extern "C"` | **signature is `fn(i64)` returning `()`** — both are `define void` (`codegen.ax:2274`, `codegen.ax:2292`), *not* `i64`. Declaring them `-> i64` reads a garbage return register. `rust/axiom-abi/src/lib.rs` already gets this right; a hand-written binding is where it goes wrong. |
| `Box::into_raw` / `Box::from_raw` for a `Foreign` | `unsafe` at the `from_raw` end only | one `from_raw` per handle, in the generated destructor (`axffi_counter_close`, `rust/examples/demo/src/lib.rs:66-75`) |
| `axffi_free_bytes` | `unsafe extern "C"` | reconstitutes the `Box<[u8]>` the shim leaked; called exactly once per `AxBytes` |

**FFI-SAFE-8 (P). No *caller-supplied* buffer parameter is ever a `&mut` slice, and no extern takes two of them.** Rust's `&mut [T]` carries LLVM `noalias`. Axiom emits no parameter attributes at all and has no aliasing information to give — `MM-MUT-2` says a field store is visible through *every* alias. So a `String` parameter lowers to a borrowed `&[u8]` and never `&mut [u8]`, and an extern that would take two writable caller-supplied buffers is refused by the generator, because it cannot prove disjointness and the failure is silent miscompilation rather than a crash.

Two exemptions, both necessary and both narrow:

- **The out-cell is exempt.** It is allocated by the generated Axiom wrapper from its own `axiom_alloc` block, is passed to exactly one shim, and no other parameter of that call can alias it. Earlier drafts of this rule were written as a blanket "a generated shim never takes `&mut`" and "two mutable buffer parameters is refused", which **made the generator reject its own output** — every fallible shim writes the cell. The rule is scoped to caller-supplied buffers precisely so the generator-owned cell stays legal.
- **`AxOpaque::borrow_mut` is exempt.** A `&mut T` behind a `Foreign` handle is sound because the handle is a `Box::into_raw` word that only Rust has ever dereferenced, Axiom holds it as one opaque scalar, and no second Axiom-visible path to that allocation exists. `rust/axiom-ffi-macros/src/lib.rs:211-222` already emits it.

With the `AxBytes` transport adopted (`FFI-ABI-0`) there is exactly **one** Axiom-allocated writable pointer per call — the cell — so this rule and §7's generated code no longer contradict each other.

---

### 4. Every way the boundary invokes UB, and what defends against each

The interesting entries are U3, U7, U12, U15 and U17; the rest are stated so the list is closed.

**U1 — arity mismatch.** Axiom declares 2 parameters, Rust defines 3. On AArch64 and x86-64 SysV a trailing unread argument is harmless; a *missing* one reads an uninitialised register. **Defence:** one manifest, two emitted sides, and the gate diffs the built object's symbol arity against it. Additionally, the extern's `FnEnt` **MUST** register `paramCount` at the declared arity, never `-1`: `repArity` (`typecheck.ax:2728-2734`) answers `-1` for a signature-only name, and a `-1` silently switches off both the AX3013 bare-value refusal and the AX3009/AX3013 saturation check (`checkSaturation`, `typecheck.ax:4534-4570`, whose `(< ar 0)` arm answers 0). The retired `foreign` used `paramCount -1`. Repeating that is how `(rustAdd 1)` becomes a one-argument call to a two-argument symbol.

**U2 — type mismatch the checker cannot see.** `(:: rustAdd (-> Int Int Int))` against `extern "C" fn(f64, f64) -> f64` type-checks. **Defence:** generation-time only (`FFI-SAFE-2`). The one surviving in-checker check, `tyReprClash` (`typecheck.ax:7052-7072`), names only `Bool`, `Float`, `String` (`tyIsReprScalar`, `typecheck.ax:7095-7097`) and is consulted from exactly one place — `checkDeclaredReturn` (`typecheck.ax:7020`), the signature-vs-body comparison. It never runs at an argument position. Adding `"Foreign"` to `tyIsReprScalar` is worth doing, and buys precisely one thing: a function declared to return `Foreign` whose body returns an `Int`-typed expression is refused. It does **not** make `Foreign` distinct from `Int` at call sites; `tyCompat`'s constructor arm already does that for statically-known types, and nothing does it for the rest.

**U3 — the evidence word reaches, or fails to reach, a callee.** This is the worst hazard in the design and the reason C3 exists.

*Axiom → Rust:* a polymorphic extern would append `i64 %__evw.h` (`codegen.ax:3008-3021`) and pass it (`codegen.ax:5925`). A trailing extra `i64` into a C callee is benign, so this direction merely wastes a register.

*Rust → Axiom:* an exported Axiom function that is polymorphic takes the word as a real parameter, and Rust does not know to supply it. The callee then reads an **uninitialised register as a pointerhood bitmap** (`MM-LIFE-2d`), and the ARC boundary events act on it: a scalar whose bit happens to be set is handed to `axiom_retain` (`codegen.ax:2274-2290`), which for any value ≥ 4096 loads the word at `h-16` and stores `h-16 = c+1`. That is an arbitrary write to an arbitrary address, silently, on a program that passed `check`. The matching `axiom_release` (`codegen.ax:2292+`) can then walk the shape word at `h-8` as a reference map and recurse into whatever it finds, and file the block onto `@__axiom_slabs`.

**Defence:** C3, enforced by refusal in *both* directions and given its own code. A type variable anywhere in an extern signature is **AX3040 `extern-polymorphic`**. The generator refuses to export an Axiom function whose `FSig` word 4 is 1 (`cgTakesEvidence`, `self_host/codegen.ax:453-459`; `fnTakesEvw`, `codegen.ax:465-468`). `axiom-ffi-macros` already refuses a generic Rust `fn` at `rust/axiom-ffi-macros/src/lib.rs` (the `!func.sig.generics.params.is_empty()` arm), which is the same rule from the other side.

> *Citation corrected.* `cgTakesEvidence` is at `:453-459`, not `:391-398`; `fnTakesEvw` is at `:465-468`.

**The `FSig` requirement, restated correctly.** A new declaration tag is invisible to `scanFloatSigs` (`codegen.ax:339-349`), which reads `TAG_D_SIG` only. Earlier drafts offered two remedies and **both were wrong**:

- *"carry a companion `TAG_D_SIG`"* — this draws a **false AX3015 on every extern**. `defIdxBuild` (`typecheck.ax:1115-1132`) indexes only nodes with `(nodeTag d) == TAG_D_FN && (nodeVis d) == 1`, and `checkMissingDefs` (`typecheck.ax:1243-1262`) reports `AX3015 missing-definition` — "`name` has a signature but no definition" — for every entry-file `TAG_D_SIG` not in that index. An extern is by construction not backed by a `TAG_D_FN`. This option is dropped. (It could be rescued by teaching `defIdxBuild` tag 53, but that is a larger change than the alternative and buys nothing.)
- *"register its own `FSig` entry with `takesEv` pinned to 0"* — a no-op. `fnTakesEvw` is `(if (== e 0) 0 (memGetWord e 4))`, so a *missing* `FSig` already answers 0.

**The real requirement is the other half of the same table.** `FSig` is `(name, nameLen, flags, sigTy, takesEv)` (`codegen.ax:336`), and the entry is read for three different things:

| Read | Site | What a missing `FSig` gives |
|---|---|---|
| `takesEv` (word 4) | `fnTakesEvw`, `codegen.ax:465-468` | 0 — correct by luck |
| float flags (word 2) | `fnRetIsFloat`, `codegen.ax:613-620`; parameter classification, `codegen.ax:3000-3001` | **0 — silently wrong for any `Float`** |
| parameter ref classes via `sigTy` (word 3) | `curParamRefClass`, `codegen.ax:3199-3209` | **0 — no reference parameter is recognised** |

So `scanFloatSigs` **MUST** grow a tag-53 arm that registers an `FSig` with `takesEv` pinned to 0 *and correct float flags from the extern's own signature*, because the same entry is what the call site reads to decide whether a returned or passed word is IEEE-754 bits.

**U4 — Rust retains an Axiom handle past the call.** Axiom's boundary release runs, the count reaches 0, the block joins its size-class freelist at `count >> 1`, and the next `axiom_alloc` of that class pops it and **scrubs it** (the `wipe:` loop, `codegen.ax:2210-2219`). Rust's copy now points into a live, rewritten block. **Defence:** C7, and the shipped `AxStr<'a>` already encodes it — the `PhantomData<&'a [u8]>` lifetime is *the call*, and its doc comment says so. A shim that stores a bare `i64` past the call is a review failure, not a compile error — stated, not solved. A shim that genuinely needs to outlive the call calls `axiom_retain` and pairs it with `axiom_release`.

**U5 — Rust writes into an Axiom `Str`'s bytes.** `MM-VAL-7`'s NUL terminator is what makes `strCStr` free (`MM-FFI-4`), and a `Str` slice shares its parent's buffer (`stdlib/Str.ax:222-233`). **Defence:** `FFI-SAFE-8` — a `String` parameter lowers to `&[u8]` (`Wire::StrRef` / `Wire::BytesRef`, `rust/axiom-ffi-macros/src/lib.rs:191-210`), never `&mut [u8]`.

**U6 — `axiom_release` reaches a non-arena pointer.** `MM-FFI-3`: memory not from `axiom_alloc` is outside the arena. `axiom_release` on a Rust `Box` address reads `p-16` as a count word. If it is `-1` it no-ops (lucky); if `0` it no-ops (lucky); otherwise it decrements *whatever that is* and may file the block onto the allocator's freelist, permanently corrupting the allocator. **Defence:** the `Foreign` type is a repr-scalar (U7), so no ARC event is ever emitted for a value of that type, and AX3041 refuses `__release`/`__retain` on one.

**U7 — `Foreign` must be scalar in *two* lists, and it must not be a `data` type.** This is a measured trap that would land on the first user, in silence, and earlier drafts closed only half of it.

*Half one — the record's reference map.* `fldClass` (`codegen.ax:6160-6178`) answers `1` — *unclassifiable* — for any `TAG_T_CON` whose name is not in `scalarTyName` (`codegen.ax:6134-6148`), is not `"String"`, is not a known `data` name, and does not resolve to a `TF_STRUCT`. `shapeBits` (`codegen.ax:6198-6207`) turns a single `1` into `-1` **for the entire block**, which forces the empty (leaf) map. So:

```scheme
(pub struct Conn
  (h    : Foreign)
  (name : String))    ; <- leaks forever, silently
```

the `String` is invisible to the release path, exactly as `ERR-TYPE-5`/`ERR-MEM-1` describe for a `String` behind an `Int` field. The same is true today for `(* T)` (`TAG_T_PTR`, `parser.ax:178`), which `fldClass` also falls through to `1`.

*Half two — the evidence stamp, which is worse.* `scalarTyName` has a twin the earlier draft never named. `evScalarName` (`self_host/typecheck.ax:542-556`) is the checker's own copy of the same list, and its comment says outright: *"the two lists must agree, and the evidence fixture is what notices a drift."* `evClassOf` (`typecheck.ax:587-613`) classifies a `TAG_T_CON` by `evScalarName` **first**, then `"String"`, then `evDataTyKnown` (`typecheck.ax:559-580`). If `Foreign` is introduced the cheap way — as a `data` or `struct` declaration in a stdlib module, which is exactly what avoids a seed rebuild — then `evDataTyKnown` answers 1, `evClassOf` answers **1 = REFERENCE**, the MM-LIFE-2d stamp sets that variable's bit, and `emitRetainIfEvBit` (`codegen.ax:6290-6320`) emits `call void @axiom_retain(i64 %v)` **on a raw Rust pointer** the first time a `Foreign` is passed into any polymorphic Axiom function. That is U3's arbitrary write at `h-16`, reached through the *argument* path U3 does not cover, on a program that passed `check`.

**Defence, and it is three parts, not one line:**

1. `"Foreign"` **MUST** be added to `scalarTyName` (`codegen.ax:6134-6148`), so `fldClass` answers `0` and a record keeps its map for every other field.
2. `"Foreign"` **MUST** be added to `evScalarName` (`typecheck.ax:542-556`), so `evClassOf` answers `0` and no retain is ever stamped on a foreign pointer. Adding it to `scalarTyName` alone does **not** close this: `scalarTyName` governs only `fldClass`/`shapeBits` and `curParamRefClass` (`codegen.ax:3199-3209`), never `evClassOf`.
3. `Foreign` **MUST NOT** be introduced as a `data`, a `struct`, or a type alias. It is a **type keyword** in `typeKeywordCanon` (`parser.ax:1620-1628`), which is the only shape in which `evDataTyKnown` can never see it. This is what C4 asks for, and the cost — a seed rebuild — is already paid by the extern form itself.

The evidence-drift fixture is added to §9's list of what must exist before the type ships, because that fixture is the only thing in the tree that notices if the two lists diverge again.

**U8 — Rust unwinds across the boundary.** §6.

**U9 — reentrancy across an open arena mark.** Axiom → Rust → Axiom, where the outer Axiom frame holds a mark from `__axiom_arena_mark_fn` (`codegen.ax:2503+`). The inner Axiom code allocates; if it also resets, invariant **I8** ("marks nest, and a mark is never reclaimed by its own reset") is violated by a control flow the compiler never sees, because the mark's owner is not on the Rust-visible stack. **Defence: none in v0.** This is a genuine gap and is recorded as such in §10. The stated program obligation is that an Axiom function reachable from a Rust callback **MUST NOT** reset an arena. Nothing checks it.

**U10 — an Axiom trap fires inside a Rust process.** §8.

**U11 — a Rust shim calls `axiom_alloc` before Axiom's runtime is initialised.** Benign, and worth recording because it is not obvious: `@__axiom_bump` and `@__axiom_bump_end` are `internal global i64 0` (`codegen.ax:2052-2053`), so the first request fails `%fits = icmp ule %next, 0`, falls to `refill:`, scans an empty free list, and `map:`s a fresh chunk (`codegen.ax:2132-2141`). `axiom_alloc` is self-initialising and may be called from Rust at any time. `@__axiom_argc`/`@__axiom_argv` (`codegen.ax:1991-1992`) are **not** — they are written only by the `@main` wrapper (`codegen.ax:1996-1997`), so in the Rust-calls-Axiom direction `sysArg` reads address 0 until `axiom_rt_init` is called. `FFI-LINK-2` makes that call the documented entry contract.

**U12 — symbol collision.** `checkReservedNames` (`typecheck.ax:983-1021`) refuses an entry-file `fn` named `axiom_alloc`, `axiom_retain`, or `axiom_release` with AX3026. It looks at `TAG_D_FN` only and knows nothing about Rust. A Rust staticlib defining `axiom_alloc` links cleanly and replaces the allocator; one defining `main` collides at link time; one defining `__axiom_bump` corrupts the arena; one defining `axffi_free_bytes` or `axffi_abi_version` replaces the facade the generated glue depends on. **Defence:** two halves. (a) An extern whose `#:symbol` names any of `main`, `axiom_alloc`, `axiom_retain`, `axiom_release`, or matches `__axiom_*` **or `axffi_*`** is **AX3042 `extern-reserved-symbol`** — the AX3026 rule extended to the symbol string rather than the Axiom name. The `axffi_*` prefix is included because the runtime facade already owns it (`rust/axiom-ffi/src/lib.rs:98-121`), which earlier drafts missed. Generated shims are exempt by construction: they are emitted by the generator, which owns the prefix. (b) `check-ffi.sh` runs `nm --defined-only` over every staticlib in the link line and fails on the same set.

**U13 — std Rust drags libc in.** Measured: the std staticlib linked and ran, and the executable carried 188 undefined symbols, 14 of them on `check-freestanding.sh`'s list (`scripts/check-freestanding.sh:53-72`) plus `_Unwind_*`, `_tlv_bootstrap`, and Mach-O bits. The `no_std` staticlib produced an executable whose `nm -u` was **empty**.

**Defence: two profiles, aligned with the gate that already exists.**

- **`freestanding` (default).** `#![no_std]` + `panic = "abort"`, and the gate is the existing name-list *plus* an empty-`nm -u` assertion. This is the mode `rust/axiom-abi` is already built in.
- **`hosted`.** The `MM-FFI-5` allowlist takes over: `scripts/check-ffi.sh` reads the crate's checked-in `axiom-allow.txt` and fails on any imported symbol not enumerated there. A crate that starts needing a new symbol changes a reviewed file.

**Corrected: there is no second never-permitted list, and `_tlv_bootstrap` is not banned outright.** An earlier draft asserted that `_tlv_bootstrap` is "permitted **never**", which **fails the only FFI example crate in the tree**: `rust/examples/demo/axiom-allow.txt` lists `_tlv_bootstrap`, `_tlv_atexit`, the full `_Unwind_*` set, every `pthread_*` name, and `malloc`/`free`/`memcpy`/`memset`/`strlen`/`bzero`/`calloc`/`realloc`/`dup2`/`getenv`/`setenv`/`pipe`. The one authoritative never-permitted set is `check-ffi.sh:64` — `printf|puts|fopen|fwrite|fread|system|popen|execv|execve|posix_spawn` — and this section does not invent a second one. The justification was also overstated: **I11** says all *allocator* state is process-private, and Rust std's own TLS does not touch Axiom's allocator; **MM-PAR-1** constrains the *language*, not what a linked archive's runtime does internally. So the rule is: **a hosted crate's TLS and unwinder symbols are a per-manifest review requirement, not a ban.** A reviewer approving `axiom-allow.txt` is approving them explicitly, which is the whole point of enumerating rather than forbidding. A crate that wants the stronger property rebuilds `no_std` and its manifest empties — measured.

Also corrected: `check-freestanding.sh:267-289` is **not** "the only probe in the tree that shows the old door is still shut". `check-ffi.sh`'s negative probe 4 (`scripts/check-ffi.sh:206-218`) already asserts the same thing — that a `foreign` binding stays AX2004. Both should be kept; two probes on the retired keyword is cheap and the duplication is deliberate, since the two gates can be run independently.

**U14 — float ABI mismatch.** Axiom carries a `Float` as its IEEE-754 **bits in an i64** and bitcasts only at operators. Axiom therefore emits `call i64 @f(i64 %bits)` and passes the value in an *integer* register (x0 / rdi). A Rust `extern "C" fn(f64)` expects it in an *FP* register (d0 / xmm0). The two never meet, in either direction, and nothing diagnoses it.

**Defence: already implemented, and this rule now records that.** `axiom-ffi-macros` declares every shim parameter as `AxWord` and inserts `f64::from_bits(#w as u64)` in the body (`rust/axiom-ffi-macros/src/lib.rs:185-187`), with `v.to_bits()` on the return (`:304`) and into the cell (`:315`). `axiom-bindgen` maps `f64` → `Float` (`rust/axiom-bindgen/src/main.rs:207`). A **hand-written** `extern "C" fn(f64)` is what the manifest check refuses. This remains the single most likely hand-written mistake in the whole FFI and it is 100% silent.

**U15 — width and overflow disagreeing across profiles.** `binopToLLVM` (`codegen.ax:6037-6047`) emits bare `add`, `sub`, `mul` — **no `nsw`, no `nuw`** — so Axiom arithmetic wraps and is fully defined. Rust wraps in release and *panics* in debug. The same shim would then have two behaviours depending on the cargo profile, which is exactly the `--opt`-dependent divergence `MM-VAL-3b` names as intolerable and `ERR-REC-2` exists to end.

**Decision:** the `rust/` workspace sets `overflow-checks = false` in **every** profile, including `dev`. Alternative considered: leave checks on and let `catch_unwind` turn an overflow into `AX_PANIC`. Rejected — it is inconsistent with `panic = "abort"` in the freestanding profile, so the two profiles would still disagree, which is the defect being fixed. A shim that *wants* checked arithmetic writes `checked_add` and returns `Err`, which is a decision in the source rather than in the build.

**Width — corrected, because the shipped generator does not do what the earlier draft claimed.** An Axiom `Int` is exactly `i64` and there is no unsigned Axiom integer. The draft said a Rust `u32`/`i32`/`usize`/`bool` parameter is "refused by the generator unless the manifest names an explicit narrowing". **It is not refused.** `classify` (`rust/axiom-ffi-macros/src/lib.rs:75`) maps `"i64" | "i32" | "isize" | "u32" | "usize"` all to `Wire::Int`, and the shim emits `#w as _` (`:183`) — an inferred, *silently truncating* cast — while `axiom_ty` (`rust/axiom-bindgen/src/main.rs:204`) maps the same set to `Int`. So `fn f(n: u32)` called from Axiom with `1 << 40` truncates to 0 with no diagnostic anywhere.

The rule is therefore a **change to the shipped generator**, not a description of it:

- `i64` and `u64` cross bit-for-bit; the shim writes an explicit `as u64` — a reinterpretation, never a conversion.
- `i32`, `u32`, `isize`, `usize`, `bool` are **refused** by `classify` and by `axiom_ty` unless the extern is annotated as narrowing, in which case the shim emits `i32::try_from(#w).map_err(…)?` and the extern becomes fallible.
- *Changes:* `rust/axiom-ffi-macros/src/lib.rs:75` and `:182-184`; `rust/axiom-bindgen/src/main.rs:204`. `bool` keeps its `#w != 0` arm, which is total and needs no narrowing.

**U16 — a cycle spanning the boundary.** Axiom record → `Foreign` → Rust struct → retained Axiom handle → back. ARC cannot see into Rust, so this leaks by construction. `MM-LIFE-2f` already prices cycles as a stated cost and **I14** says the heap graph may contain them; this widens the class from "Axiom-internal cycles" to "any cycle through a foreign object". Recorded, not solved.

**U17 — a status word returned as a value from an infallible shim.** New, and found in the shipped macro. The `Wire::StrRef` prologue emits `Err(_) => return ::axiom_ffi::AX_ERR` on invalid UTF-8 (`rust/axiom-ffi-macros/src/lib.rs:198-201`). That prologue is shared between the fallible and infallible shim shapes, so an **infallible** `#[axiom_export] pub fn f(s: &str) -> i64` handed non-UTF-8 bytes returns **`1`** — not a status, but `f`'s ordinary return value, indistinguishable from a legitimate answer of 1. This is `docs/error-model.md` §1.2's sentinel defect, reintroduced at the boundary by the code generator rather than by a human. **Defence:** a shim whose parameters include a `Wire::StrRef` (which requires valid UTF-8) **MUST** be fallible; the macro refuses `&str` in an infallible signature and directs the author to `&[u8]`, which has no validity requirement and whose prologue cannot fail. *Changes:* `rust/axiom-ffi-macros/src/lib.rs:191-203`.

---

### 5. The link line, and what an "export" is

Nothing in the earlier draft said how the Rust archive reaches the link line, and today it cannot. `assembleAndLink` (`self_host/driver.ax:205-233`) builds the `cc` invocation as exactly `objPath -o outPath` — no `-l`, no `-L` — and `grep -n 'link-lib\|link-search' self_host/*.ax` returns nothing. Meanwhile `scripts/check-ffi.sh:135-137` **already invokes `--link-lib` and `--link-search`**, so the gate meant to enforce this section calls driver flags that do not exist. Both directions are unimplementable until this subsection lands.

**FFI-LINK-1 (P). The driver grows `--link-lib NAME` and `--link-search DIR`, both repeatable.**

`assembleAndLink` (`driver.ax:205-233`) appends to `ccArgs`, after `objPath -o outPath`: every `--link-search DIR` as `-L DIR`, then every `--link-lib NAME` as `-l NAME`, in declaration order. Archives come after the object that references them, which is what a static link needs on ELF and is harmless on Mach-O. A program with no `--link-lib` produces a byte-identical command line to today's, which is the project owner's "a program using no FFI must be byte-identical" requirement applied to the link step as well as the IR.

The **module preamble and the emitted IR are unchanged by these flags**. What changes is that `emitDecl`'s new tag-53 arm writes `declare i64 @sym(i64, …) #0` for each extern — the first `declare` the emitter has ever written, and the reason `grep -c '^declare'` on `bootstrap/axiom-darwin-aarch64.ll` must stay `0` for the seed and may be non-zero only for a program with externs.

**FFI-LINK-2 (P). `--emit-staticlib` is the Rust-calls-Axiom direction, and it defines the export set.**

The measured experiment renamed the emitted `@main` to `@axiom_rt_init`, assembled to `.o`, and `ar rcs`'d it into an archive a normal Rust binary linked. That is promoted to a driver mode:

- Codegen takes a flag that renames the `@main` wrapper (`codegen.ax:1994-2001`) to **`axiom_rt_init`**. The rename lives in codegen, not in a post-hoc `sed`, so `llvmSym` quoting and the symbol map stay consistent.
- The driver runs `llc -filetype=obj` as usual, then `ar rcs` instead of `cc … -o`.
- **The export set is the entry file's `pub fn` declarations.** Entry-file declarations keep their bare names (`llvmSym`, `codegen.ax:982-990`), which is why `@addTwo` was callable in the experiment. `__axiom_user_main` is *not* exported.
- **`axiom_rt_init(argc, argv)` MUST be called before any exported function that reads `sysArg`.** `@__axiom_argc`/`@__axiom_argv` are written only by that wrapper (`codegen.ax:1991-1997`); U11 records that the allocator self-initialises but these globals do not. A Rust program that never reads argv may skip it; one that does and skips it reads address 0.

**This is the definition `AX3043` needs.** "Exporting a function" means "being in the `--emit-staticlib` export set", which is a set the *checker* can compute from the entry file's declaration list after `inferEffects` — which is what makes the diagnostic constructible in `self_host/` rather than in a Rust tool that cannot see `FnEnt` (§9).

---

### 6. Panics and unwinding

**FFI-PANIC-1 (R). `extern "C-unwind"` is refused. Externs are `extern "C"`, in both directions, always.**

The justification is not preference; Axiom physically cannot participate.

- The emitter never emits `invoke` or `landingpad`. Grepping `self_host/codegen.ax` for `invoke|landingpad|personality|uwtable` yields one hit, and it is the word "invoked" in a comment about PATH resolution (`codegen.ax:1327`). There is no cleanup edge on any call.
- `attributes #0 = { "no-builtins" }` (`codegen.ax:2805`) is the module's **one** attribute group. No `uwtable`, no `personality`.
- `llc` will still emit `.cfi_*` directives, so an unwinder *can* walk an Axiom frame. What it cannot do is find a personality routine or an LSDA, so every Axiom frame is "no handler", and `_Unwind_RaiseException` walks straight past `@main` and calls `std::process::abort`.
- More seriously, the frames it walked past are exactly where the ARC boundary releases live (`MM-LIFE-2c` event 4). Unwinding through Axiom leaks every retained value on the abandoned frames, and — because a skipped release means a count that never reaches zero — leaves the arena permanently over-counted. There is no shape of `C-unwind` in which the result is recoverable.

So the choice is not between "propagate" and "abort". It is between "abort" and "abort after corrupting the heap". Rust 1.81+ already aborts on an unwind out of `extern "C"`, which agrees with this rule for free.

**FFI-PANIC-2 (P). Freestanding profile: `panic = "abort"` in every profile, no shim.** `#![no_std]` with `panic_immediate_abort` or a `#[panic_handler]` that writes to fd 2 and exits. `catch_unwind` does not exist in `no_std`; there is nothing to catch. A panic here is a process abort, which is honest and matches the three traps Axiom already has.

**FFI-PANIC-3 (P). Hosted profile: `panic = "unwind"` in every profile, and every fallible shim is wrapped in `catch_unwind`; a caught panic becomes `AX_PANIC`.**

**The per-profile requirement is normative, and the workspace does not satisfy it today.** `rust/Cargo.toml` sets `panic = "abort"` under `[profile.release]` only, and `scripts/check-ffi.sh:117` builds with `cargo build --release`. Two consequences, both defects:

1. Under `panic = "abort"`, `catch_unwind` never returns `Err`. No shim can produce `AX_PANIC` and `FFI-PANIC-4`'s poisoning is unreachable. (Independently, there is no `catch_unwind` anywhere in `rust/` yet, so `AX_PANIC` is presently a dead constant.)
2. Under the unset `dev` profile, Rust unwinds. The *same shim* would then return a `Result` in dev and abort the process in release — a cargo-profile-dependent behaviour difference in the panic path, which is precisely the divergence U15 calls intolerable and legislates `overflow-checks = false` to prevent for arithmetic. Having fixed it for arithmetic and left it for panics would be incoherent.

So: **the panic strategy is a property of the profile, not of the optimisation level**, and each profile sets it in *both* `[profile.dev]` and `[profile.release]`. *Changes:* `rust/Cargo.toml`'s single `[profile.release] panic = "abort"` is split into a `[profile.dev]` + `[profile.release]` pair per profile; a hosted crate overrides both to `"unwind"`; `scripts/check-ffi.sh` builds and checks each profile it claims to gate.

Cost of the wrapper:

- With `panic = "abort"` the wrapper is a no-op the optimiser removes entirely. Zero. (This is why the freestanding profile emits none.)
- With `panic = "unwind"`: one call to `__rust_try`, a landing pad, a `.gcc_except_table` entry per shim, a personality reference, and inhibited inlining of the closure into the caller. On the happy path this is one untaken branch — comparable to the div-by-zero guard Axiom already pays at every `/` and `%` (`emitDivGuard`, `codegen.ax:5809-5828`), which `MM-VAL-3a` accepted on exactly the same reasoning ("one predictable branch, paid only by `/` and `%`").
- It is generated **only** for shims whose Rust function returns `Result`, so an infallible extern pays nothing. This is `ERR-REC-2`'s rule — the raw operator keeps its semantics and no hot loop pays for a check it did not ask for — applied to the boundary.

`UnwindSafe`: generated shims take `i64`s and raw pointers, and the generator emits `AssertUnwindSafe`. **This is a real assertion and not a proof**, and §10 records it as a gap. The mitigation is `FFI-PANIC-4`.

**FFI-PANIC-4 (P). A caught panic poisons the receiver's `Foreign` handle.** If the shim's first parameter is a `Foreign`, the caught panic marks that handle dead in the crate's handle table, and every subsequent call on it returns **`AX_POISONED` (3)** without entering Rust. The reasoning: `catch_unwind` returns control, but a panic out of a method leaves the object in a state its own author never reasoned about, and Axiom will happily keep calling it. Poisoning turns "undefined behaviour later, somewhere else" into "a deterministic error at the next call", which is the trade `Mutex` poisoning makes for the same reason. It does **not** make `AssertUnwindSafe` true. `AX_POISONED` is the fourth status constant added by `FFI-ABI-0`; there is no free encoding for it in the shipped `{0,1,2}`.

**FFI-PANIC-5 (P). No exported Axiom function may be on the stack when a panic is caught.** That is: `catch_unwind` may not span a Rust→Axiom callback, because the unwind would have crossed Axiom frames to get there and `FFI-PANIC-1` applies. The generator refuses to emit a `catch_unwind` around a shim that takes an Axiom function handle.

---

### 7. Errors

#### 7.1 The three encodings

**(A) Out-parameter plus a status word.** The C-ABI classic. `-> i64` is the status; a caller-supplied cell receives the payload.

**(B) A tagged Axiom data value allocated by the shim.** Rust builds `(Ok x)` / `(Err e)` directly on the Axiom heap and returns the handle.

**(C) A global last-error slot plus a sentinel return.** `errno`, essentially.

#### 7.2 Evaluation against Axiom's real constraints

**(B) is rejected, and the reasons are structural, not aesthetic.**

- Constructor tags are **globally unique** (invariant **I4**, `MM-VAL-8`) and assigned by the compiler over the whole merged declaration list. Rust would have to be regenerated whenever any unrelated `data` declaration is added anywhere in the program, because that can renumber `Ok`.
- The block's shape word encodes the reference bitmap computed by `shapeBits` (`codegen.ax:6198-6207`) from **declared field types** via `fldClass`. Rust writing that word by hand is Rust taking on `MM-LIFE-2d`, and getting one bit wrong is a use-after-free (`codegen.ax:6128-6131`: "under-reclaiming leaks, a wrong bit use-after-frees, and only one of those is survivable").
- `Result` is not built in. It is an ordinary declaration in `stdlib/Err.ax:30-32` (`ERR-TYPE-2`), so its tags depend on the import graph of the program being compiled.
- It would put the FFI in the business of writing `MM-LIFE-2b` headers from a language that cannot see them. Every future change to the header layout would break every shipped Rust crate.

This is also the rule `rust/axiom-abi`'s module documentation already states in its own voice — "Rust returns raw bytes or an opaque handle; generated Axiom glue does every Axiom-side allocation" — so (B) is rejected on both sides independently.

**(C) is rejected — but not for the reason it is usually rejected.** The usual objection is thread-safety, and *that objection does not apply here*: `MM-PAR-1` says there are no threads, no async, no atomics and no TLS, the unit of parallelism is the process (`stdlib/Job.ax` over fork/exec), and invariant **I11** says all allocator state is process-private. A plain mutable global is genuinely sound in this language, and the emitted runtime already owns several (`@__axiom_argc`, `@__axiom_bump`, the per-effect evidence slots). So (C) is *implementable*. It is rejected on three other grounds:

1. **A sentinel return is a value of the success type.** That is precisely the defect `docs/error-model.md` §1.2 counted at 65 sites across 12 files and wrote the whole model to end. Adding a 66th at a boundary that is *more* dangerous than a syscall would be a regression with a spec number against it. (U17 shows the shipped macro already made this mistake once, by accident.)
2. **The read is a second effectful call the inference must also see.** A caller who forgets `(ffiLastError)` gets silence. `Result` makes forgetting a type error at the `match`.
3. **Cost.** It needs a new runtime global plus a primitive to read it — a codegen change and a seed rebuild — for strictly less safety than (A), which needs neither.

**(A) is adopted at the C ABI, in the shape `rust/axiom-abi` already ships. The Axiom surface is `Result`, built by generated Axiom code.**

#### 7.3 FFI-ERR-1 (P): the adopted encoding

> A fallible extern's C symbol returns an `i64` **status** and takes one extra trailing `i64` parameter: the address of a **3-word out cell** allocated by Axiom (`(memAlloc 24)`). The cell is `#[repr(C)] AxOutCell { payload, extra, code }` — words 0 and 1 are byte-compatible with the shipped 2-word cell, and word 2 is added by `FFI-ABI-0`. **Rust never constructs an Axiom data value, never allocates on the Axiom heap, and never writes an Axiom header.**

**One meaning per word per status class, and the wrapper reads every word the shim writes.** The earlier draft's normative text and its own example disagreed about `out[0]` — the text called it "the success word", the example wrote a byte count into it on success and a domain code into it on error, and the wrapper ignored `out[1]` and the message entirely. This table is the whole contract:

| Status | `payload` (word 0) | `extra` (word 1) | `code` (word 2) |
|---|---|---|---|
| `AX_OK` = 0 | the success word; **or**, for a bytes/String-returning shim, an `AxBytes` pointer | 0; **or** the `AxBytes` byte count | 0 |
| `AX_ERR` = 1 | an `AxBytes` pointer to the rendered message, or 0 for none | its byte count, or 0 | the shim's domain code, or 0 |
| `AX_PANIC` = 2 | an `AxBytes` pointer to the panic message, or 0 | its byte count, or 0 | 0 |
| `AX_POISONED` = 3 | 0 | 0 | 0 — the shim was never entered |

Why the cell is Axiom-allocated and why that is not a new hazard: it comes from `axiom_alloc`, so it is *inside* the arena and gets the allocator's zero-fill (`MM-ALLOC-6`, the `wipe:` loop at `codegen.ax:2210-2219`) and its 16-byte header. Critically the allocator writes the **leaf** shape — `%wshp = shl i64 %wleaf, 1`, map bits empty (`codegen.ax:2242-2252`, whose comment says why: "the allocator leaves EMPTY, because it cannot know a field from an int") — so nothing Rust writes into that cell is ever walked as a reference by the release path. Rust writing into an Axiom-allocated buffer is the same boundary `MM-FFI-2`'s first row already blesses for the kernel. The zero-fill is also what makes an unwritten word readable: a shim that writes only `payload` leaves `extra` and `code` at 0, which the table above defines.

**Messages cross as `AxBytes`, borrowed for exactly one copy.** This is the shipped transport (`rust/axiom-ffi/src/lib.rs:60-90`) and it is adopted in place of the earlier draft's fixed-capacity caller buffer:

1. Rust renders the message and calls `leak_bytes` / `error_bytes`, handing back a `(ptr, len)` pair in `payload`/`extra`. The bytes are on **Rust's** heap — `MM-FFI-3` memory, outside the arena, not scrubbed and not counted.
2. The generated Axiom wrapper does exactly one `strAlloc len` + `memCopy`, producing a real Axiom `Str`.
3. The wrapper immediately calls **`axffi_free_bytes(ptr, len)`**, which reconstitutes and drops the `Box<[u8]>`.

The window in which Rust memory is reachable from Axiom is one copy long, and it is closed on **every** path out of the wrapper. `axffi_free_bytes` is itself an extern in the Axiom→Rust direction: it must appear in the generated glue, in the manifest, and in the allowlist, and it is exempt from `AX3042` only because the generator owns the `axffi_*` prefix.

**This dissolves the truncation problem entirely.** The earlier draft's Tier-2 scheme passed a caller-allocated buffer with a fixed `cap`, needed an `AX_ERR_MSG_TRUNCATED` status, and — in its own worked example — could never succeed (§7.4). With `AxBytes` the buffer is sized from the length Rust reports, so there is no `cap`, no truncation, and no truncation status. **`AX_ERR_MSG_TRUNCATED` is withdrawn before it is constructed.**

Alternatives for the message that were considered and rejected: a `&'static str` pointer (restricts messages to constants, and `Display` output is not constant); a Rust-owned `static mut` scratch buffer (works today, and is *exactly* the thing that becomes a data race the moment `MM-PAR-1` changes — refused so that no part of this design has to be revisited if threads ever land); Rust building the `Str` header itself (three payload words plus `memAllocMapped`'s map bit 2, `stdlib/Str.ax:68-83`, `stdlib/Mem.ax:74-86` — four invariants deep into Rust, for a string).

**FFI-ERR-2 (P). The status is a small closed set of *classes*; the domain code rides in the cell, not the status.**

| Code | Name | Meaning |
|---|---|---|
| `0` | `AX_OK` | the call succeeded; read `payload`/`extra` per the table |
| `1` | `AX_ERR` | the Rust function returned `Err`; `code` carries the domain code |
| `2` | `AX_PANIC` | a Rust panic was caught (`FFI-PANIC-3`) |
| `3` | `AX_POISONED` | the receiver handle was poisoned by an earlier panic (`FFI-PANIC-4`) |

Positive and contiguous, matching `rust/axiom-abi/src/lib.rs:48-52` as shipped; `0` for success so the common branch is `icmp eq i64 %st, 0`. The earlier draft proposed a *negative* reserved range with `>= 1` meaning "domain code", under which the shipped `AX_PANIC = 2` would decode as a domain code — a silent misclassification of every caught panic. That redesign is dropped.

**Domain codes never share a numeric space with `stdlib/Err.ax`'s codes.** This is the substantive fix. `stdlib/Err.ax:49-51` defines `errDivideByZero = 1`, `errOverflow = 2`, `errShiftTooWide = 3`, and `divChecked` builds `(Err (mkError (errDivideByZero) …))` (`stdlib/Err.ax:182-196`). Putting a status of `1` into `Error.code` — which the earlier draft's example did on every domain error — makes every foreign error indistinguishable from a division by zero, while the actual domain code sits unread in the cell. That defeats the rule's own stated rationale one level up from where it was stated.

So the generated wrapper maps into **two reserved bands, and never writes the raw status into `Error.code`:**

```scheme
(pub :: errFfiBase       Int) (pub fn (errFfiBase)        65536)
(pub :: errFfiDomainBase Int) (pub fn (errFfiDomainBase) 131072)
```

| Condition | `Error.code` |
|---|---|
| `AX_ERR` with `code == 0` | `errFfiBase + 1` = 65537 |
| `AX_ERR` with `code == d` | `errFfiDomainBase + d` |
| `AX_PANIC` | `errFfiBase + 2` = 65538 |
| `AX_POISONED` | `errFfiBase + 3` = 65539 |

Both bands sit far above `stdlib/Err.ax`'s 1-3 and above any plausible hand-assigned program code, and the two are disjoint from each other so a class code can never be read as a domain code. **The wrapper puts `cell.code` — not the status — into `Error.code`.**

**FFI-ERR-3 (P). The Axiom surface is `(Result a Error)` from `stdlib/Err.ax`.** This **supersedes** the shipped `(Result T String)` (`rust/axiom-bindgen/src/main.rs:159`, and the comment at `rust/examples/demo/src/lib.rs:40-41`), for the reason `FFI-ABI-0` gives: `String` discards the code and the context word, and every propagation rule in `docs/error-model.md` is written against `Error`.

`Error` is `(code : Int) (message : String) (context : String)` (`stdlib/Err.ax:42-45`); `mkError` (`stdlib/Err.ax:53-55`) builds it, `withContext` (`stdlib/Err.ax:140-144`) attaches the call site, and `try!` (`stdlib/Err.ax:239-242`) propagates — which is also what keeps `ERR-PROP-3`'s tail-call shape, since the form puts the continuation in the arm.

Three consequences of matching the existing model that the implementer must not rediscover:

- `ERR-TYPE-3a`/B5: an FFI-error-inspecting combinator **MUST** take the error through a parameter declared `Error`. `(match r ((Err y) y.code))` over a polymorphic scrutinee is `AX3004 expected struct or data type, found _tN`. The generator emits combinators in `errContextOf`'s shape (`stdlib/Err.ax:136-138`), not in the arm.
- `ERR-MEM-2`: the error value handed to a self tail call **MUST** pass through a `let`. Measured at 144 bytes per iteration leaked otherwise. Generated wrappers bind before returning.
- `ERR-MEM-4`: every fallible call already leaks 32 bytes today, and the FFI adds the out cell and any message copy on top. See `FFI-ERR-6` for the real arithmetic.

#### 7.4 The generated shim, end to end

Manifest entry (hand-written, in the Rust crate). Note `#[axiom_export]` with **no arguments** — `FFI-ABI-0` item 4:

```rust
// rust/crates/axfs/src/lib.rs
#[axiom_export]
pub fn read_at(f: &FileHandle, off: i64, len: i64) -> Result<Vec<u8>, std::io::Error> {
    f.read_exact_at(off as u64, len as u64)
}
```

Generated Rust (checked in, reviewed, never hand-edited):

```rust
// GENERATED by axiom-bindgen. Bindings sha256:9f3c…  ABI_VERSION 2.
use core::panic::AssertUnwindSafe;
use axiom_ffi::{AxOpaque, AxOutCell, AxStatus, AxWord,
                AX_OK, AX_ERR, AX_PANIC, AX_POISONED};

/// # Safety
/// `out` must be the address of a 3-word Axiom block from `axiom_alloc`.
/// `h` must be a live handle previously returned by `axffi_fs_open`.
#[no_mangle]
pub unsafe extern "C" fn axffi_read_at(h: AxWord, off: AxWord, len: AxWord,
                                       out: AxWord) -> AxStatus {
    let cell = AxOutCell::from_word(out);

    let Some(f) = crate::handles::get(h) else { return AX_POISONED };

    let r = std::panic::catch_unwind(AssertUnwindSafe(|| {
        crate::read_at(f, off, len)
    }));

    match r {
        Ok(Ok(bytes)) => {
            // Rust owns these until the Axiom wrapper calls axffi_free_bytes.
            let (p, n) = axiom_ffi::__private::leak_bytes(bytes);
            cell.payload = p;
            cell.extra   = n;
            cell.code    = 0;
            AX_OK
        }
        Ok(Err(e)) => {
            let (p, n) = axiom_ffi::__private::error_bytes(&e);
            cell.payload = p;
            cell.extra   = n;
            cell.code    = crate::io_code(&e);   // the DOMAIN code, word 2
            AX_ERR
        }
        Err(_) => {
            crate::handles::poison(h);
            let (p, n) = axiom_ffi::__private::leak_bytes(
                b"the foreign call panicked".to_vec());
            cell.payload = p;
            cell.extra   = n;
            cell.code    = 0;
            AX_PANIC
        }
    }
}
```

Generated Axiom (`Fs.ffi.ax`, checked in, never hand-edited):

```scheme
; GENERATED by axiom-bindgen. Bindings sha256:9f3c…  ABI_VERSION 2.
(import Err)
(import Mem)
(import Str)

; The raw symbols. Monomorphic by construction (C3): no type variable
; appears, so no `%__evw.h` is emitted and none is expected. The
; trailing Int is the out-cell address.
(pub extern (fsReadAtRaw (h : Foreign) (off : Int) (len : Int) (out : Int)) Int
  #:symbol "axffi_read_at"
  #:lib    "axfs"
  #:out-cell
  #:effect ffi)

; The free callback is an extern in the Axiom -> Rust direction too, and
; is subject to every rule in this section. It is exempt from AX3042
; only because the generator owns the `axffi_*` prefix.
(pub extern (ffiFreeBytes (ptr : Int) (len : Int)) Unit
  #:symbol "axffi_free_bytes"
  #:lib    "axfs"
  #:effect ffi)

; Copy an AxBytes pair into a real Axiom Str and close the window in
; the same breath. Every path out of the wrapper goes through here, so
; there is no path on which Rust's bytes are not freed.
(pub :: ffiTakeBytes (-> Int Int String))
;@axiom:effect(ffi)
(pub fn (ffiTakeBytes p n)
  (if (|| (== p 0) (<= n 0))
      ""
      (let ((s (strAlloc n)))
        {
          (memCopy (strData s) p n)
          (ffiFreeBytes p n)
          s
        })))

; The wrapper is the only thing a program calls. It owns the out cell,
; owns the copy, and is the only place `Ok`/`Err` are built - so no
; Axiom constructor tag and no MM-LIFE-2d shape word ever has to be
; known on the Rust side.
;
; `;@axiom:effect(ffi)` is a CLAIM; the inferred set is what AX3010
; checks it against, and the extern seeds it at registration.
(pub :: fsReadAt (-> Foreign Int Int (Result String Error)))
;@axiom:effect(ffi)
(pub fn (fsReadAt h off len)
  (let ((cell (memAlloc 24)))                  ; 3 words: payload, extra, code
    (let ((st (fsReadAtRaw h off len cell)))
      ; Every word the shim writes is read, for every status class.
      (let ((p (memGetWord cell 0))
            (n (memGetWord cell 1))
            (d (memGetWord cell 2)))
        (if (== st 0)
            ; ERR-MEM-2: bind before it crosses a boundary.
            (let ((s (ffiTakeBytes p n)))
              (Ok s))
            ; FFI-ERR-2: the DOMAIN code, never the status, reaches
            ; Error.code - and it lands in a band stdlib's 1-3 cannot
            ; reach.
            (let ((msg (ffiTakeBytes p n)))
              (let ((c (if (== st 1)
                           (if (== d 0) (+ (errFfiBase) 1) (+ (errFfiDomainBase) d))
                           (+ (errFfiBase) st))))
                (let ((e (mkError c (if (== (strLen msg) 0) (ffiErrText st) msg))))
                  (Err e)))))))))

; The class-code fallback text, for a shim that sent no message.
; Every arm is a string literal, so every message is a static with
; count -1 and retain/release stop on it.
(pub :: ffiErrText (-> Int String))
(pub fn (ffiErrText st)
  (if (== st 2) "the foreign call panicked"
  (if (== st 3) "the foreign handle was poisoned by an earlier panic"
      "the foreign call failed")))
```

Use site, in the shape every rule in `docs/error-model.md` converges on:

```scheme
(:: loadHeader (-> Foreign (Result String Error)))
;@axiom:effect(ffi)
(fn (loadHeader h)
  (withContext (fsReadAt h 0 512) "reading the archive header"))
```

**This example now succeeds.** The earlier draft's version could not: the wrapper hard-coded `(strAlloc 256)` and passed `256` as `msgcap`, the shim computed `min(bytes.len(), msgcap)` and returned `AX_ERR_MSG_TRUNCATED` whenever `n < bytes.len()`, and the use site asked for 512 bytes — so a 512-byte read into a 256-byte buffer always truncated, and the wrapper mapped every non-zero status to `Err`. The one worked example in the section was a function that always failed. The buffer size was a generator constant with no relation to the `len` argument. Under `AxBytes` the payload buffer is sized from the byte count Rust actually produced, so payload size and message size are independent quantities and neither is bounded by a constant the generator invented.

**FFI-ERR-4 (P). Rust never allocates on the *Axiom* heap.** Everything Rust writes into was sized and allocated by the generated Axiom wrapper. Rust's own `leak_bytes` allocation is on Rust's heap — `MM-FFI-3` memory, outside the arena — and is freed through `axffi_free_bytes` before the wrapper returns. This is the rule that keeps `MM-ALLOC-6` and `MM-LIFE-2d` entirely on the Axiom side of the line. (The earlier draft stated this as "Rust never allocates", full stop, which the shipped `leak_bytes` transport contradicts; the correct rule names *which* heap.)

**FFI-ERR-6 (P). The per-call cost, stated correctly.**

The earlier draft claimed "Tier 1 (default, zero allocation)" and "a fallible extern costs ~64 bytes per call". Both were wrong, the first categorically and the second by roughly 5×. The real arithmetic, against `codegen.ax:2242-2252` (every block carries a mandatory 16-byte header) and `stdlib/Str.ax:89-99` / `:222-233`:

| Item | Bytes | When |
|---|---|---|
| the out cell — `(memAlloc 24)` payload + 16-byte header | **40** | **every fallible call**, success or failure, message or not |
| `strAlloc n` — `memAlloc (n+1)` payload + header | `n + 1` padded + **16** | only when a message or byte payload actually crosses |
| the `Str` header from `strAlloc` — `memAllocMapped 24` + header | **40** | same |
| Rust-side `leak_bytes` `Box<[u8]>` | `n`, on Rust's heap | freed by `axffi_free_bytes` before the wrapper returns |

So: **there is no zero-allocation tier.** The out cell is unavoidable in this encoding and is paid on every fallible call. A call that returns no message costs **40 bytes**; a call that carries an `n`-byte message or payload costs **40 + 56 + n** (padded), i.e. about **100 bytes plus the payload**.

Two things the `AxBytes` adoption improves over the earlier draft: there is no second `Str` header, because the wrapper copies into an exactly-sized `strAlloc` rather than slicing an oversized buffer (`strSlice` would have added another `memAllocMapped 24` + header = 40 bytes and a `__retain` on the owner, `stdlib/Str.ax:222-233`); and there is no 257-byte buffer allocated on calls that never use it.

None of this is reclaimed, for the same `ERR-MEM-4` reason the section already cites: every fallible call leaks its `Result` today. That is survivable for a compiler that runs once and is **not** survivable for `self_host/lsp.ax` (`ERR-ADOPT-3`). The FFI is now a second caller for the escape analysis that `MM-LIFE-2c` events 2 and 3 are waiting on, **with a number attached: 40 bytes per fallible foreign call at minimum, ~100 + n when a message crosses.**

---

### 8. OOM, and the traps

**FFI-ERR-5 (P). Axiom's allocator and Rust's allocator do not unify, and the FFI does not pretend they do.**

- Axiom's OOM is the `oom:` block (`codegen.ax:2253-2260`): a raw `exit` syscall with status **70**, followed by `unreachable`. No message, no unwinding, no cleanup. `MM-ALLOC-7`, `MM-EXEC-16` (`docs/memory-model.md:408-415`). It is the one reserved status no fixture reaches (`docs/memory-model.md:2527-2529`).
- Rust's std OOM is `handle_alloc_error` → `abort()` → SIGABRT (status 134), which is not in `MM-EXEC-16`'s reserved set and prints Rust's message, not Axiom's.

**Decision.** In the **freestanding** profile a generated shim **MUST NOT** allocate on a Rust global heap — enforced structurally by `#![no_std]` with no `alloc` crate, which is what made the measured `nm -u` empty. Note this excludes the `AxBytes` message path entirely, since `leak_bytes` needs `alloc`: a freestanding shim's errors are code-only, with the message supplied by `ffiErrText` on the Axiom side. In the **hosted** profile the generated crate root installs an allocation-error hook that writes `axiom: rust allocator out of memory` to fd 2 and exits **70**, so the two allocators agree on the status a reader sees. `MM-EXEC-16` reserves 70 for "allocator out of memory" without saying whose; this reads it at its word.

**Finding, flagged rather than absorbed: exit 70 is already double-booked.** `docs/memory-model.md:413` assigns 70 to allocator OOM (**H**, holds today); `docs/error-model.md` `ERR-REC-4` (**P**) proposes 70 for a `main` that renders an `Error`. Those collide before the FFI exists. The FFI must not deepen the collision, so `ERR-REC-4` should move to **73** — the family stays contiguous (70 OOM, 71 unhandled operation, 72 division, 73 main-returned-an-error) and no **H** rule moves. This section does not claim the authority to renumber it; it records that whoever implements `ERR-REC-4` must.

**FFI-ERR-7 (H). Every Axiom trap kills the process outright, from wherever it fires, and runs no Rust cleanup.** All three are an `exit` syscall followed by `unreachable`:

| Trap | Emission | Status |
|---|---|---|
| division / remainder by zero | `emitDivGuard` (`codegen.ax:5809-5828`) branches to `@__axiom_div_by_zero` (`emitDivTrap`, `codegen.ax:2481-2501`) — writes to fd 2, then `exit(72)` | 72 |
| effect operation with no handler | `emitEffectOp` (`codegen.ax:4504-4527`) loads the evidence slot, `icmp eq 0`, calls `@__axiom_unhandled_effect` (`codegen.ax:4611-4626`) — `exit(71)`, no message | 71 |
| allocator failure | `codegen.ax:2253-2260` | 70 |

Consequences, in both directions:

- **Rust → Axiom.** A trap inside an Axiom function called from Rust terminates the *Rust* process. It is not a panic: `catch_unwind` does not see it, no `Drop` runs, no `MutexGuard` releases, no buffered stdout flushes, and **`axffi_free_bytes` is never reached** — so any `AxBytes` in flight is leaked, which is the least of the problems but is worth naming. Rust code holding OS resources across an Axiom call must be written knowing the call may never return. (`MM-EXEC-17`, `docs/memory-model.md:421-423`: there are no finalizers, no destructors, no atexit hooks.)
- **The unhandled-effect trap is the sharp one, because it fires on *entry*, not on a mistake.** An effect handler is installed dynamically by a `handle` form in the *Axiom* call stack. A Rust→Axiom entry point has no `handle` above it, so the evidence slot global is 0 and **any exported Axiom function that performs a custom effect operation traps at status 71 the first time it is called from Rust**, on a program that passed `check` — because AX3011 fires only at a `handle` site (`checkUnhandled`, `typecheck.ax:5308-5330`) and there is no top-level unhandled check.

  **Defence: AX3043 `export-unhandled-effect`, constructed in `self_host/`.** After `inferEffects`, the checker reads `FnEnt` word 5 (`typecheck.ax:1309-1316`) for every function in the `--emit-staticlib` export set (`FFI-LINK-2`) and refuses any whose transitive set contains a `c:` effect that the function's own body does not `handle`. Built-in effects (`b:IO`, `b:Mut`, `b:Div`, `b:Alloc`, `b:Ffi`) are exempt: they are labels, never operations, and never reach `emitEffectOp`. The earlier draft assigned this to "the generator", a Rust tool — which cannot see `FnEnt` at all, and which §9's own construction-site rule would then make it impossible to list. Defining the export surface in the language (`FFI-LINK-2`) is what makes this diagnostic constructible.
- **A Rust callback made from inside a handler body sees the *outer* handler.** `emitEffectOp` stores `prev` back into the slot before applying the handler (`codegen.ax:4531`), so the handler is not re-entrant by construction. A Rust shim that calls back into Axiom during a handler will not re-enter that handler; it will find whatever was installed above it, or trap.
- **The div guard is emitted at the *caller*.** It is per-`/` and per-`%` (`isDivOp`, `codegen.ax:5804`) — so an exported Axiom shim that divides by a value Rust supplied traps at 72 with Rust's stack below it. `stdlib/Err.ax`'s `divChecked`/`remChecked` (`stdlib/Err.ax:182-196`) are the value-returning alternatives, and **generated Axiom wrappers MUST use them** for any arithmetic on a foreign-supplied operand. `ERR-REC-2` already made them exist; this is their first mandatory use. (Their codes are `errDivideByZero`/`errOverflow` = 1/2 — inside stdlib's band, disjoint from the FFI bands by `FFI-ERR-2`'s construction, which is exactly the separation that rule buys.)

---

### 9. Diagnostics allocated

Codes are never renamed and never reused (`docs/error-model.md` §0.1). The highest constructed code is `AX3035`; `AX3032` is retired; `AX3036`–`AX3038` are **proposed** by `ERR-DIAG-2` and not constructed. `scripts/check-doc-drift.sh:19-27` checks constructed-against-listed in **both** directions — "every code with a construction site outside explain.ax is listed by `explain --list`, and every listed code has a construction site" — so **a code listed before it is built turns the gate red.**

The FFI therefore starts at **AX3040**, leaving `AX3036`–`AX3039` to the error model with one spare.

| Code | Slug | Severity | Construction site | Condition |
|---|---|---|---|---|
| `AX3040` | `extern-polymorphic` | error | `self_host/typecheck.ax`, extern registration | a type variable anywhere in an extern signature (C3, U3) |
| `AX3041` | `foreign-primitive` | error | `self_host/typecheck.ax`, primitive-application check | an arena primitive, `__retain`/`__release`, or a raw load/store applied to a `Foreign` (`MM-FFI-5` req. 2, U6) |
| `AX3042` | `extern-reserved-symbol` | error | `self_host/typecheck.ax`, beside `checkReservedNames` (`:983-1021`) | an extern whose `#:symbol` is `main`, `axiom_alloc`, `axiom_retain`, `axiom_release`, or matches `__axiom_*` **or `axffi_*`** (U12; the `AX3026` rule extended to the symbol string) |
| `AX3043` | `export-unhandled-effect` | error | `self_host/typecheck.ax`, after `inferEffects`, over `FFI-LINK-2`'s export set | exporting a function whose transitive effect set contains a custom effect operation with no enclosing `handle` (§8) |
| `AX4004` | `link-archive-missing` | error | `self_host/driver.ax`, in `assembleAndLink` (`:205-233`) | a `--link-lib NAME` names an archive found under no `--link-search DIR` |

**Two reassignments from the earlier draft, both forced by `check-doc-drift.sh`.**

- `AX3043` was assigned to "the generator" — a Rust tool reading `FnEnt` word 5, an in-memory checker structure (`typecheck.ax:1309-1316`) it cannot see. It is moved into `self_host/`, which required defining what an export *is* (`FFI-LINK-2`).
- `AX4004` was assigned to the allowlist shell gate, which today prints bare `FAIL` lines and emits no diagnostic codes anywhere. A shell script cannot have a construction site, an `explain.ax` entry, or a `.axdl` golden, so listing it would fail the gate in the "listed but not constructed" direction. **`scripts/check-ffi.sh` is not allocated a compiler diagnostic code at all** — its failures stay bare `FAIL` lines, which is the right register for a gate. `AX4004` is instead spent on the one genuinely compiler-side link failure `FFI-LINK-1` introduces: a `--link-lib` the driver cannot resolve. `AX4001` already sat in the table with no construction site for months; this section does not add a second.

Each code needs, before it is listed anywhere: a construction site, `self_host/explain.ax` text, a `tests/diagnostics/NNN-*.ax` case with `.axdl`, `.human` and `.json` goldens blessed by `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`, and a run of that case against a compiler built before the change, to prove the refusal is not vacuous.

**Plus one fixture that is not a diagnostic and must exist before the `Foreign` type ships:** the **evidence-drift fixture** that notices `scalarTyName` (`codegen.ax:6134-6148`) and `evScalarName` (`typecheck.ax:542-556`) disagreeing. `evScalarName`'s own comment names this fixture as the thing that catches the drift, and U7 shows that getting only one of the two lists is a wild write through `emitRetainIfEvBit` on a program that passed `check`. Adding `"Foreign"` to one list and not the other must turn a gate red.

**Existing codes reused, no allocation.** A typo'd type name in an extern signature is `AX3002 undefined-type` (`typecheck.ax:2641-2654`) via the new `tcCheckSigTypes` tag-53 arm (§2); an AXTAG claiming `ffi` on a function that reaches no extern is `AX3010` (`emitAxtag`, `typecheck.ax:6871-6879`), a warning, unchanged.

**Parser-level, no new code.** `foreign` stays `AX2004` (`pErrRemoved`, `self_host/parser.ax:376`; rendered at `parser.ax:459-460`), and its `removedHelp` text (`parser.ax:594-605`) is updated from "use the standard library, which reaches the kernel through `__syscall0`-`__syscall6`" to name `extern` and the manifest. The arm stays ahead of `TAG_D_MACROCALL` in `parseTopForm` so the migration advice survives. **Two probes assert this and both should be kept:** `scripts/check-freestanding.sh:267-289` and `scripts/check-ffi.sh:206-218`, negative probe 4. The earlier draft called the first "the only probe in the tree that shows the old door is still shut"; it is not, and the duplication is deliberate, since the two gates can be run independently.

---

### 10. What is genuinely unresolved

Stated plainly, because a known gap is worth more than a confident guess.

1. **`Foreign` leaks by default and nothing can change that today.** C8 requires an explicitly registered destructor. ARC cannot run it: the release path (`codegen.ax:2292+`) walks map bits and calls `axiom_release` on each — there is no per-type hook, and `MM-EXEC-17` (`docs/memory-model.md:421-423`) says there are no finalizers, no destructors and no atexit hooks. Nor is there room to add one: the shape word's bits 16..62 are the reference map and bit 63 is reserved so shape constants stay non-negative (`codegen.ax:6190-6196`), so there is nowhere to put a type id the release path could dispatch on. A `Foreign` is closed by an explicit generated call — `axffi_counter_close` in the demo (`rust/examples/demo/src/lib.rs:66-75`) is exactly this shape — that the program must make, like a file descriptor. **This is the weakest part of the design.** A debug-profile handle-table leak counter, printed at `main`'s exit, is the strongest mitigation available without a language change.
2. **`(cast Foreign x)` defeats the type.** `checkCastForm` (`typecheck.ax:4405-4457`) checks the value not at all, and the tree depends on `cast` — `stdlib/Str.ax:79` is the site where three raw words legitimately become a `String`. Refusing `cast` to `Foreign` would be a language change with no escape hatch left; permitting it means C4's guarantee is a convention above the checker, not below it. Recorded as such.
3. **Reentrancy across an arena mark (U9) has no defence.** Invariant **I8** can be violated by a control flow no phase of the compiler observes.
4. **`AssertUnwindSafe` in every generated `catch_unwind` is an assertion, not a proof.** `FFI-PANIC-4`'s poisoning bounds the damage; it does not establish the property. And today it is entirely theoretical: there is no `catch_unwind` anywhere in `rust/`, and the workspace's release profile aborts, so `AX_PANIC` is a constant nothing constructs.
5. **Nothing prevents a hand-written `extern` from being wrong in every way U1, U2, U14 and U15 describe.** The gate refuses to *ship* one, and the gate is a shell script that can be skipped. This is the same structural position `ERR-PROP-3` and `ERR-MEM-2` occupy — program obligations that nothing enforces — and it is stated in the same voice rather than dressed up.
6. **The two type-mapping passes are separate implementations of one mapping.** `classify` (`rust/axiom-ffi-macros/src/lib.rs:53-95`) and `axiom_ty` (`rust/axiom-bindgen/src/main.rs:187-215`) must agree, and only `check-ffi.sh`'s regenerate-and-diff notices when they do not. This is the same "two lists must agree" hazard as `scalarTyName`/`evScalarName` (U7), one language over, and it has the same answer: a fixture, not a convention.
7. **`axiom-allow.txt` is a review artefact, not a proof.** The hosted profile's boundary is exactly as strong as the person who approved the manifest. `rust/examples/demo/axiom-allow.txt` today permits the full `pthread_*` and `_Unwind_*` sets and 16 of `check-freestanding.sh`'s forbidden names, which is *correct* for a std crate and *is* the cost of the hosted profile. The freestanding profile, whose measured `nm -u` is empty, is the only mode where the property is machine-checked rather than reviewed.
8. **If real type inference ever lands, every extern signature becomes a source of `MM-LIFE-2d` evidence.** Three attempts were merged and withdrawn (`053c525`, `9d5b508`) because a statically resolved argument type feeds the ARC evidence word and containers are deliberately untyped `Int` handles, so resolution claims pointerhood for scalars and segfaults. An extern signature is the *most* confidently-typed thing in the program and would therefore be the loudest source of that failure — and U7 shows the mechanism concretely, since `evClassOf` is the function that would be asked. Whoever attempts inference a fourth time must treat the extern set as the first corpus to run it against, not the last.
---

## 9. Performance and Zero-Copy Paths

All numbers in this section were measured on the host this specification was written on — Darwin arm64 (M-series), Homebrew LLVM 22.1.8 (`opt`/`llc`), Apple clang 21.0.0 (`cc`), rustc 1.97.1 (LLVM 22.1.6) — using the methodology `scripts/bench-datastructures.sh` establishes: whole processes, best of N runs rather than the mean, process startup measured separately with a do-nothing binary and subtracted. Where a figure is a measurement it is labelled as one; where it is a projection it says so.

### P1. Baseline: an Axiom→Rust call is not a foreign call

The measured claim is stronger than "cheap". It is *identical*.

Take a real emitted Axiom module, keep the call site untouched, and replace only the callee — internal Axiom function in one variant, `declare`d external symbol in the other. `opt -O1` then `llc -O1 -relocation-model=pic` produces, for the calling function `spin`:

```
; internal callee (marked noinline so the call survives)   ; extern callee
LBB205_1:                                                  LBB205_1:
	mov	w1, #1                                              	mov	w1, #1
	sub	x19, x19, #1                                        	sub	x19, x19, #1
	bl	_ffiAdd                                             	bl	_ax_rust_add
	cbnz	x19, LBB205_1                                       	cbnz	x19, LBB205_1
```

Byte-identical but for the symbol. There is no thunk, no argument buffer, no dispatch table, no state save, no mode switch. This falls out of the ABI rather than being engineered: every Axiom value is one 64-bit word and every user function already emits `define i64 @sym(i64 %p, ...) #0` with no calling-convention marker and no parameter attributes (`self_host/codegen.ax:3014-3018`), so `emitPlainCall` (`self_host/codegen.ax:5907-5941`) is already emitting a C-ABI call. C1/C2 do not *add* a boundary; they *notice* that the existing internal call shape already is one.

Timed at 100M iterations, best of 11, startup subtracted:

| variant | ns/call |
|---|---|
| internal Axiom call (`noinline`) | 1.546 |
| extern, plain `declare` | 1.545 |
| extern, `declare … nounwind` | 1.547 |
| extern, `declare … nounwind willreturn memory(none)` | 1.546 |

At ~4 GHz that is ~6 cycles, which is the `bl`/`ret` pair plus the loop's own arithmetic. **The dispatch overhead of the Axiom→Rust boundary is zero, and this is measured, not asserted.**

One correction to that sentence, stated here because P6 later leans on it: it is true for *integer-class* arguments, which is every Axiom value except a `Float` in a Rust shim that spells its parameter `f64`. See "Floats cross as bits" in P4 — the AArch64 and x86-64 C ABIs put `double` in a different register class, and the shim must not ask for it.

The contrast worth drawing is with the FFIs Axiom will be compared against. CPython's `ctypes` builds an argument buffer and dispatches through libffi (hundreds of ns); JNI crosses a stack barrier and a handle table; a WASM host call traps out of the sandbox. Those costs exist because the calling language's values are not machine words and its stack is not the C stack. Axiom's are and is. The correct mental model for a reader is not "Axiom gained an FFI" but "Axiom's internal calls were always C calls, and the FFI is permission to name a symbol the module does not define."

**What is genuinely lost is not instructions, it is information.** A `declare` is opaque to `opt`.

Here the two figures must be kept apart, because they come from two different binaries and only one of them is a call-cost measurement.

- The **1.546 ns/call** internal control in the table above is `bench_internal_ni.ll`, whose callee is forced `noinline` (`attributes #1 = { "no-builtins" noinline }`) precisely so the call survives to be timed. That number is a call cost and is directly comparable to the extern rows.
- The **0.157s → 0.0028s** figure is a *different binary*, `bench_internal.ll`, with no `noinline`. There LLVM inlined `ffiAdd`, then recognised that `(spin (- n 1) (ffiAdd acc 1))` over `(+ a b)` is `acc + n`, and emitted `add x0, x1, x0; ret`. **The 100M iterations never run.** That is a closed-form solve of an accumulator loop, not a general inlining win, and the ratio it produces (56×) is a property of this microbenchmark's arithmetic rather than of the boundary.

So the honest statement is: the boundary costs no instructions at the call, and costs the optimiser *whatever that program's callee was worth as an inlining candidate* — which for a real Rust shim doing real work is far less than 56×, possibly nothing. P3 and P6 are about recovering that lost information, and P6 repeats this caveat at the point where someone might otherwise commit engineering effort to LTO on the strength of a number that measures a deleted loop.

### P2. Where cost actually appears

Measured against the same 1.55 ns call, using Axiom programs built by the committed compiler at `--opt 1`:

| operation | ns | in call-units |
|---|---|---|
| extern call, 2 scalar args | 1.55 | 1.0 |
| `__retain` + `__release` pair on a live block | 6.6 | 4.3 |
| `memAlloc 4` (`stdlib/Mem.ax:39-41`) | 7.9 | 5.1 |
| `strDup` of a 12-byte literal (`stdlib/Str.ax:236-243`) | 18.1 | 11.7 |
| `catch_unwind` on the happy path | +0.02–0.07 on a 3.65 ns base | ~0 |

Read the ratios, because they set every design priority in this section:

- **The call is free; the allocation is not.** One `axiom_alloc` costs five calls. A marshalling layer that allocates once per argument turns a free boundary into an expensive one single-handedly.
- **The copy is worse than the allocation.** `strDup` is two allocations plus a byte loop and costs twelve calls for twelve bytes. Copy cost is linear in length on top of that.
- **ARC traffic is real but second-order.** A retain/release pair is 4.3 calls. `axiom_retain`/`axiom_release` (`self_host/codegen.ax:2274-2291`, `2292-2374`) are each a compare-against-4096, a load at `h-16`, a compare against the `-1` statics sentinel, and an add/store — no atomics, because MM-PAR-1 gives the language no threads. C7's requirement that Rust call `axiom_retain` to hold a value past the call is therefore cheap in absolute terms and should never be avoided on performance grounds. (It is also not *sufficient* on its own — see P4 precondition 2, which is a lifetime correction, not a cost one.)
- **`catch_unwind` is free on the happy path and should not be priced.** Itanium-model unwinding is table-driven: nothing executes in the non-panicking case, only an LSDA entry exists statically. Measured delta between a bare `extern "C"` shim and one wrapping the same body in `catch_unwind` was 3.648 → 3.654 ns/call, inside run-to-run noise. **Decision: the choice between `catch_unwind` and `panic="abort"` is never made on cost.** The alternative — refusing `catch_unwind` because it is expensive — was considered and rejected as measurably unfounded. What actually decides it is the *tier* the crate is built at: `catch_unwind` requires `std`, and P8 shows `std` is the tier-3 mode that gives up an empty `nm -u`. So: `panic="abort"` satisfies C6 at tier 2 (the no_std default), and `catch_unwind` is the tier-3 answer where a rich error value is wanted and the program has already accepted the allowlist gate. Both are permitted; neither is a performance decision.

Validation and error encoding are the two costs that do not appear in the table because they are entirely within the binding generator's control, and they are where a naive design loses. Since the Axiom type checker cannot enforce the boundary — `tyCompat` matches a type variable against anything and `tyReprClash`/`tyIsReprScalar` (`self_host/typecheck.ax:7051-7061`, `7094-7096`) name only `Bool`, `Float` and `String` as non-handles — there is a standing temptation to insert dynamic checks at each shim. **Decision: no per-call dynamic validation on the Axiom side.** Boundary type safety comes from the binding generator at generation time, where real Rust types exist, exactly as the ABI contract states. A generated shim that re-checks what generation already proved pays a branch per argument to re-derive a static fact. The one thing that *is* checked at runtime is what cannot be known statically: a `Ptr` that Rust must dereference is the Rust shim's `unsafe` obligation, documented at the shim, not a tag test in Axiom.

**Error encoding.** A fallible extern must not allocate to report failure. The encoding depends on the *return type*, and the earlier draft of this section got that wrong by appealing to invariant I3; the correction matters enough to state in full.

I3 (`docs/memory-model.md:2387`) says "every heap address handed out for a VALUE is ≥ 4096, and no immediate tag is", its cause is `MM-VAL-9` and its stated consequence when violated is that "mixed-representation `match` picks the wrong arm". It is a *discrimination* rule between heap addresses and immediate constructor tags. It does **not** reserve 0..4095 as an unused range. An extern declared to return `Int` returns a raw machine word, and 0..4095 is ordinary result space: this section's own `ax_sum_bytes` example returns **1150** for `"hello, axiom"`, and every count, index, byte, `Bool`, and error-free `0` lands there. "Constrain the successful range in the binding generator" is unimplementable for scalar returns without forbidding small integers, which is absurd.

So the protocol splits:

- **Handle-typed returns (`String`, `Ptr`, a record).** The sub-4096 range genuinely is uninhabited for these by `MM-VAL-9`'s discrimination, and `axiom_retain`/`axiom_release` already branch to `done` on `icmp slt i64 %h, 4096` (`self_host/codegen.ax:2294`), so an error sentinel in that range is both distinguishable and inert under ARC. **Decision: for handle-typed returns, the sad path returns a small sentinel in the same single i64, and a rich error is fetched by a second, explicitly-called extern.** Cite `MM-VAL-9`, not I3, and cite it as *discrimination*, not as a reserved range.
- **Scalar-typed returns (`Int`, `Bool`, `Char`, `Float`, the fixed-width family).** There is no free sentinel. Three permitted forms, chosen at declaration: (i) declare the fallible variant to return a handle and use the sentinel protocol above; (ii) declare an explicit reserved value as part of the extern's declared type, so the generator can refuse it as an input and the reader can see it (this is a documented narrowing of the return type, not a free range); (iii) return the value unconditionally and have the caller consult the error extern unconditionally — two calls at 1.55 ns each, which is still cheaper than one allocation.

Alternatives considered and rejected for both cases: (a) an out-param pointer, rejected because it forces a stack slot and a store on the *happy* path, which is the path that runs; (b) returning an allocated Axiom result block, rejected because it prices every fallible call at 5+ call-units of allocation whether or not it fails — and, per P5 and P6 below, a Rust-constructed result block is a leak unless it is built through a mapped allocation.

### P3. Declaration-site attributes: the one lever with measured leverage

The single highest-value performance decision in this design is *what Axiom writes on the `declare` line*. It costs nothing at runtime and it is the only channel through which an extern can tell `opt` anything.

Measured on this host with `opt -O1`:

- **Plain `declare i64 @f(i64, i64) #0`.** The caller gains `.cfi_startproc` and full unwind directives, because LLVM must assume the callee unwinds.
- **`nounwind`.** All `.cfi_*` directives disappear from the caller. Frame and unwind metadata shrink. No instruction-count change in the loop body itself, but every caller of every extern pays the metadata otherwise.
- **`nounwind willreturn memory(none)`.** Two adjacent calls with identical arguments were CSE'd to one (`cse.opt.ll` has 2 calls, `cse_pure.opt.ll` has 1). A call whose result is unused was deleted entirely (`dce.opt.ll` has 0 where the source had 1). Neither happens without it.

**Decision: an extern declaration carries a purity level, defaulting to the conservative one, and the levels map onto LLVM attributes as follows.**

| Axiom level | LLVM attributes emitted | Rust obligation |
|---|---|---|
| default | `nounwind` | must not unwind (C6) |
| `reads` | `nounwind willreturn memory(read)` | no observable writes; may read Axiom or foreign memory |
| `pure` | `nounwind willreturn memory(none)` | result a function of arguments only; no memory access, no I/O |

`nounwind` is unconditional and not a level, because C6 already forbids unwinding across the boundary — an extern that may unwind is a program that is already broken, so declaring `nounwind` gives up nothing that was ever available.

**Purity is an unchecked assertion, and the spelling must say so.** Two routes to checking it were considered and both were rejected: inferring purity from the Rust signature is impossible, because `extern "C" fn(i64) -> i64` is exactly as opaque to the generator as it is to LLVM and `&self`-free-ness proves nothing about a raw pointer argument; reading purity out of the Rust MIR is a cargo dependency on the compile path, which the project owner's decision forbids — cargo runs the gates, never the build. Having rejected both, this design cannot then hand the generator an obligation to "refuse `pure` for any shim that touches `axiom_alloc`, `axiom_retain`, `axiom_release`, or a `Ptr` dereference", because with both inference routes gone the generator cannot see whether a shim touches any of those. Saying so anyway would leave an implementer either rebuilding the MIR reader this section forbids, or — worse — believing `pure` is machine-checked when it is not.

So, plainly:

- **`pure` and `reads` are unchecked assertions made by the author of the Axiom `extern` declaration, in the same class as `unsafe` in Rust.** They must be spelled so they read as assertions rather than as facts the compiler verified — an `unsafe`-adjacent keyword, not a bare adjective — and the diagnostic text and documentation must say "you are asserting" rather than "declare that".
- The failure mode is silent and is measured in this section's own scratch: a lying `pure` gets its calls CSE'd (2 → 1) and its unused calls deleted (1 → 0), with no diagnostic anywhere.
- **The generator's only enforceable rule is over shims it generates itself.** It wrote those bodies, so it knows whether they call `axiom_alloc`, `axiom_retain`, `axiom_release`, or dereference a `Ptr`, and it must refuse to emit `pure` for them. That rule is real and should be implemented. **Hand-written externs over hand-written Rust get no check at all**, and the spec must say that rather than implying coverage the toolchain does not have.

Note the pleasing consequence for C5. Seeding `builtinEff "IO"` into the extern's FnEnt at registration — the `tcAddEffectOp` model (`self_host/typecheck.ax:1866-1876`) — is an *effect-system* fact and carries no code-generation weight; `inferEffects` (`self_host/typecheck.ax:5199-5241`) runs once, before any body is checked, and emits nothing. A `pure` extern is still an inferred effect at the type level while being `memory(none)` at the IR level, and there is no contradiction: the effect system tracks what the *program* may observe, the attribute tracks what the *optimiser* may assume. Do not let one collapse into the other.

Worth stating for scale: an extern with `memory(none)` is **strictly more optimisable than Axiom's existing `__syscallN`**, which lowers to `call i64 asm sideeffect` carrying `~{memory}` in every target template (`self_host/codegen.ax:1887-1919`). Every syscall in an Axiom program today is a full optimiser barrier. A pure extern is not a barrier at all.

### P4. Zero-copy paths and their preconditions

**Strings, Axiom → Rust. Zero copy, verified end to end.**

An Axiom `Str` value is the address of a three-word header — length, byte address, owner (`stdlib/Str.ax:1-12`, accessors at `125-137`). A string literal's header is a static of shape `{ i64, i64, i64, ptr, i64 }` and the circulating value is `ptrtoint` of *element 2* (`self_host/codegen.ax:7227-7244`), so a literal and a heap `Str` present the identical `{len, ptr}` layout at offsets +0 and +8 from the handle. Rust reads it directly:

```rust
#[no_mangle]
pub unsafe extern "C" fn ax_sum_bytes(h: i64) -> i64 {
    let p = h as *const i64;
    let len  = *p as usize;
    let data = *p.add(1) as *const u8;
    let s = core::slice::from_raw_parts(data, len);
    s.iter().fold(0i64, |a, &b| a.wrapping_add(b as i64))
}
```

Built as a `#![no_std]` staticlib and linked into a real Axiom program whose `sumBytes` body was replaced by this call, it returned 1150 for `"hello, axiom"` — the correct byte sum — with `nm -u` on the executable **empty**. No allocation, no copy, no NUL scan.

Preconditions, and they are not negotiable:

1. **`&[u8]`, not `&str`.** Axiom's `Str` carries a length and *may contain a NUL* by construction (`stdlib/Str.ax:14-17`); it makes no UTF-8 promise. Handing it to `str::from_utf8_unchecked` is unsound. The generator emits `&[u8]` for the free path and `str::from_utf8` — an O(n) validation, not a copy — only where the Rust signature demands `&str`. **Decision: `&[u8]` is the default marshalling of `String`; `&str` is opt-in and priced.**

2. **Lifetime is the call, and `axiom_retain` on the owner extends it only sometimes.** The `&[u8]` borrows Axiom memory that ARC may free on return. C7 governs: to hold it, Rust calls `axiom_retain` on the *owner* word (handle+16), not on the `Str` header, because word 2 is what names the block owning the bytes and a slice inherits its parent's owner one hop deep (`stdlib/Str.ax:222-234`). Retaining the header keeps the header alive and lets the bytes go. That much stands. Two holes in it must be stated, because a binding that assumes "retain the owner, done" hands Rust a dangling slice with no diagnostic:

   - **`owner == 0` conveys no lifetime at all.** `strWrap` builds a `Str` with owner 0 (`stdlib/Str.ax:50-57`), and the accessor comment at `stdlib/Str.ax:137-138` enumerates three cases: a literal's bytes (loader-resident, immortal — retaining is correctly unnecessary), a syscall buffer's (the kernel's — mortal), and an arena keep block's interior (the arena's — mortal). `axiom_retain(0)` takes the `%imm = icmp slt i64 %h, 4096` branch straight to `done` (`self_host/codegen.ax:2294`) and does nothing. For the literal that is right; for the other two Rust now holds a slice into memory nothing is counting. **A retained-owner promise is sound only when the owner is a counted `axiom_alloc` block; owner 0 must be treated as "borrow for the duration of the call and no longer", and the generator must not emit a "retained" path for it.**
   - **No refcount survives an arena reset.** `__axiom_arena_reset` "returns every chunk mapped since the mark to the free list" and consults no count (`self_host/codegen.ax:2394-2398`, invariants I7/I15). A Rust-held, retained block inside a region that is then reset is reclaimed anyway, and handed out — and scrubbed — by the next `memAlloc`. **`axiom_retain` is not protection against a reset and must never be documented as if it were.** A binding whose Rust side outlives an Axiom call must therefore do one of: copy the bytes into Rust's own allocator; be documented as requiring that the program hold no arena mark across the retained lifetime, making arena discipline part of the binding's published contract; or hold the data as a `Ptr` with a registered destructor — the only form that is reset-safe by construction, because MM-FFI-3 (`docs/memory-model.md:2354-2361`) puts non-`axiom_alloc` memory outside the arena entirely.

3. **`*const c_char` is the narrow path, and slices are excluded from it.** MM-FFI-4 (`docs/memory-model.md:2363-2367`) makes NUL-termination a program obligation and `strCStr` is literally `strData` (`stdlib/Str.ax:160-162`) — free. But `strSlice` explicitly does *not* terminate (`stdlib/Str.ax:213-220`): "a slice is not NUL-terminated unless it happens to end where `s` does, so `strCStr` must not be called on one." **The binding generator cannot tell a slice from a whole string — `tyCompat` gives it nothing, and both are `String`.** Three options: (a) forbid `*const c_char` in extern signatures outright and require `&[u8]` plus explicit length, (b) require the caller to spell `(strDup s)` at the call site, paying ~18 ns to guarantee termination, (c) check `data[len] == 0` at the shim — one load and one predictable branch, ~1 call-unit.

   An earlier draft rejected (c) with "it reads one byte past a slice's end to decide whether reading past its end is safe, which is circular." **That premise is false for every `Str` the `Str` module builds, and the argument is withdrawn.** `strAlloc` reserves `len + 1` bytes and the allocator zeroes, "so the terminator is already in place" (`stdlib/Str.ax:85-99`); `strSlice` clamps both `from` and `n` to the parent (`stdlib/Str.ax:222-234`). A slice's `data[len]` is therefore always *interior* to its parent's live buffer, and a whole string's `data[len]` is its own reserved terminator. The load is in-bounds by construction. The one exception is `strWrap` over foreign or kernel memory, where the caller already carries the MM-FFI-4 obligation for `bytes[len]` — the same obligation the check would be testing.

   **Decision: (a) remains the default, on type-story grounds alone** — a C-string-taking Rust API is rare enough not to warrant a `String` marshalling whose correctness depends on which constructor produced the value, and `&[u8]` + length is strictly more informative. **Two escapes are available and both are honest: (b) an explicit `(strDup s)` at the call site, ~18 ns plus length, guaranteeing termination for any `Str` including a `strWrap`ped one; and (c) an opt-in terminator check at the shim, ~1 call-unit, sound for any `Str` built by the `Str` module and undefined only for `strWrap`-over-foreign bytes, exactly where MM-FFI-4 already places the obligation.** Prefer (c) over (b) when the caller cannot afford the copy and the string's provenance is the `Str` module, which is nearly always.

**Floats cross as bits in an integer register, and the shim signature must say `i64`.**

Axiom carries a `Float` as its IEEE-754 bits in an i64 and bitcasts only at operators. An extern declared `(-> Float Float Float)` therefore emits `declare i64 @axffi_hypot(i64, i64) #0` and is called with integer operands — verified in the end-to-end module: `call i64 @ffiHypot(i64 4613937818241073152, i64 4616189618054758400)` against `declare i64 @axffi_hypot(i64, i64) #0`. But the AArch64 and x86-64 C ABIs pass `double` in `v0`–`v7` / `xmm0`–`xmm7`, **not** in `x0`–`x7` / `rdi`,`rsi`. A Rust shim spelled `extern "C" fn(f64, f64) -> f64` reads the wrong register class and returns garbage — silently, with no link error and no diagnostic anywhere.

**Decision: a generated Rust shim's float parameters and returns are always spelled `i64`, with `f64::from_bits` on entry and `f64::to_bits` on exit; `extern "C" fn(f64, …)` and `-> f64` are generator-refused signatures, refused at binding-generation time with a diagnostic that names this paragraph.** The cost is one `fmov` per float argument and one per float return, on each side — a register-class move, sub-nanosecond, but *not zero*, and it is mandatory rather than avoidable. This also means P1's "every Axiom value is one 64-bit word, so `emitPlainCall` is already emitting a C-ABI call" holds for integer-class arguments and needs this one qualification for floats. Note that the emitter already tracks float-ness separately from the i64 return type (`fnRetIsFloat`, `self_host/codegen.ax:613-614`, consulted at `4897` and `5938`), so the generator has the information it needs on the Axiom side; the refusal is about what it emits on the Rust side.

**Byte slices and vectors, Axiom → Rust.** Same mechanism, weaker preconditions: a `{ptr, len}` pair carved from an Axiom block and reconstituted with `from_raw_parts` is zero-copy for any element type that is one word. Axiom containers are deliberately untyped `Int` handles, which is exactly why the type checker cannot be trusted here and why the generator, seeing the *Rust* type `&[i64]`, is the authority. Element types narrower than a word are *not* zero-copy: every Axiom value is one word (invariant I1), so `&[u8]` over an Axiom `Vec` of bytes would be a lie about the stride. `Str`'s byte array is the exception precisely because it is a raw byte buffer, not a `Vec` of values.

**Opaque handles, both directions — free by construction, but only if `Ptr` is introduced through the right two lists. This is the load-bearing subsection for C4/C8, and it is where the earlier draft was wrong.**

A `Ptr` is one i64 at the ABI. The claim that it is therefore free needs a precise account of *how* the checker and emitter learn that, because ARC emission is driven by the **declared type** through four string-keyed classifiers, and getting the introduction wrong reproduces exactly the failure that withdrew three inference attempts (053c525, 9d5b508).

*The trap.* If `Ptr` is introduced the obvious way for "a distinct opaque built-in type" — as a `data` or `struct` registration — then `evDataTyKnown` (`self_host/typecheck.ax:558-585`) finds it in `tcDatas`/`tcStructs` and `evClassOf` (`self_host/typecheck.ax:587-613`) answers **1, reference**; and `fldClass` (`self_host/codegen.ax:6159-6178`) takes the `dataTyKnown` branch and answers **2, reference**. From there, `curParamRefClass`/`retainRefParams` (`self_host/codegen.ax:3198-3221`) emit `axiom_retain(%p)` at the entry of **every Axiom function with a `Ptr` parameter**, and `emitSetF` (`self_host/codegen.ax:4676-4690`) emits a retain/release pair on every struct field set. `axiom_retain` on a foreign address ≥ 4096 does not bail at the immediates guard: it loads at `ptr-16`, compares against the `-1` statics sentinel, and **stores `c+1` into Rust-owned memory** (`self_host/codegen.ax:2274-2291`). That is a wild write into the other language's heap, on every call, produced by the very type C4 introduces to prevent confusion.

*The fix, stated as a requirement on the implementation.*

- **`Ptr` MUST be named in `scalarTyName` (`self_host/codegen.ax:6133-6148`) and in `evScalarName` (`self_host/typecheck.ax:542-557`).** The comment at `self_host/typecheck.ax:539-541` is explicit that these are one list spelled twice — "the two lists must agree, and the evidence fixture is what notices a drift" — so both edits land together or neither does.
- **`Ptr` MUST NOT be registered in `tcDatas` or `tcStructs`.** It is a built-in name, not a user type; registering it re-enables the reference branch the two edits above are there to avoid.
- With those, `fldClass` answers **0 (machine scalar)** and `evClassOf` answers **0**, so: no entry retain, no field retain/release, and the MM-LIFE-2d evidence bit for a `Ptr` argument to a polymorphic callee is **0**.
- **Fixture, required:** pass a `Ptr` to a polymorphic callee and assert the emitted evidence word has that position's bit clear; and assert no `call void @axiom_retain` appears in the entry block of a function taking a `Ptr` parameter. The evidence fixture is the mechanism that notices scalar-list drift; this is what it should be pointed at.

*A second, distinct hazard the leaf default does not cover.* The reference bitmap is **all-or-nothing per block**. `shapeBits` (`self_host/codegen.ax:6197-6206`) returns `-1` the moment *any* field classifies as 1 (unclassifiable) — `(if (|| (== c 1) (== rest -1)) -1 …)` — and `ctorShapeConst` (`self_host/codegen.ax:6217-6222`) converts `-1` to `0`, making the whole block a leaf. The comment at `self_host/codegen.ax:6128-6131` already names "a Ptr" as the canonical unclassifiable field and states the consequence: "forces the whole block to the LEAF (empty map): under-reclaiming leaks, a wrong bit use-after-frees, and only one of those is survivable." So an unclassified `Ptr` does not merely leave itself unwalked — `(data Conn (MkConn Ptr String))` **silently stops releasing the `String` in the same record, forever**, a per-record leak introduced by C4's own type in the section that claims C4 is free.

Classifying `Ptr` as class 0 — the same single edit the paragraph above requires — resolves this too: a scalar contributes no bit and does not poison the map, so `MkConn`'s `String` keeps its bit. **Fixture, required:** a `data` with a `Ptr` field and a `String` field, asserting the emitted shape constant still has the `String`'s bit set and the `Ptr`'s clear. Without that fixture, a future edit that moves `Ptr` back into the data-type path turns a checked leak into an unchecked one. The alternative considered — forbidding `Ptr` in `data`/`struct` fields and requiring a dedicated one-field wrapper block — is strictly worse ergonomics for the same safety, and is recorded here only so a reader knows it was weighed.

*What remains true after the corrections.* Once `Ptr` is class 0, the allocator's default does the rest and does it for free: `memAlloc` "sees a byte count and nothing else, so it stamps every block a LEAF" (`stdlib/Mem.ax:43-56`), only `memAllocMapped` sets reference bits, and the release walk in `axiom_release` branches on `%dowalk = and i1 %isrec, %hasmap` (`self_host/codegen.ax:2327-2352`) and skips entirely when the map is zero. **A `Ptr` in an ordinary Axiom block is never walked, never released, and never mistaken for a handle — MM-FFI-5 requirement 2 is satisfied at zero runtime cost with no new primitive, *provided* the type is introduced through the scalar lists rather than the data lists.** The obligation is therefore not "purely negative": there is one positive edit (two lists), one prohibition (`tcDatas`/`tcStructs`), one generator rule (never emit `memAllocMapped` with a bit set over a `Ptr` word), one checker rule (refuse arena primitives on `Ptr`, MM-FFI-3), and two fixtures.

One further clarification, because P2 cites the neighbouring predicate: **`tyIsReprScalar` has nothing to do with ARC.** It feeds only `tyReprClash`'s signature-versus-body check (`self_host/typecheck.ax:7051-7096`) and names `Bool`, `Float`, `String`. Whether `Ptr` should join that list is a *separate* decision from the ARC classification, and it should be taken separately: adding it would make a declared `Ptr` over an `Int` body a reported clash, which is MM-FFI-5 requirement 1 enforced where it can be, at the cost of flagging any deliberate `Int`↔`Ptr` conversion that is not spelled with a cast. Recommended, but as its own change with its own corpus sweep — and under no circumstances confused with the `scalarTyName`/`evScalarName` edit, which is the one that prevents the wild write.

C8's registered destructor is an explicit Axiom-side call, not an ARC hook, and pays only when invoked.

**Rust → Axiom, and the symbol-naming rule that decides how the generator names things.** The reverse direction is free for scalars and handles by the same register-class argument (floats included, with the same `i64` shim rule). Verified: renaming the emitted `@main` (`self_host/codegen.ax:1994-2001`) to an init symbol, archiving the object, and linking it into a Rust binary that declares `extern "C" { fn addTwo(i64, i64) -> i64; }` works.

But that experiment used an **entry-file** function, and the rule does not generalise:

- **Entry-file declarations keep their bare name.** `@addTwo` is emitted literally, and Rust can name it as a plain identifier.
- **Every imported-module declaration is renamed in place to `Mod$name`.** `llvmSym` (`self_host/codegen.ax:982-990`) quotes only symbols containing characters outside `[-A-Za-z0-9$._]`, and `$` is inside that set, so the symbol goes out unquoted and unmangled-further: `define i64 @Mem$memAllocMapped(i64 %bytes, i64 %map) #0` is in the committed bootstrap IR at line 428. `Mem$memAllocMapped` is not spellable as a Rust identifier.

**Decision: the generator must apply the rule explicitly — a bare `extern "C"` name for entry-file declarations, and `#[link_name = "Mod$name"]` for everything else — or the Axiom declaration must carry an explicit export-name annotation that pins a bare symbol.** This is not a corner case: a Rust binary built over an *Axiom library* reaches exactly the functions that live outside the entry file, so the `Mod$` form is the common case for that direction and the bare form is the exception. A reader who generalises from the `addTwo` experiment will hit an unresolved symbol on their first real library.

Rust *constructing* an Axiom `Str` is the one place a copy is usually unavoidable, and it carries a trap of its own; see P5.

### P5. When a copy is unavoidable, and why

Five cases. Four are copies; the fifth is a mandatory register-class repack that is not a copy but belongs in the same "you cannot design this away" list.

1. **Rust owns the bytes and Axiom must outlive the call.** A `String` or `Vec<u8>` produced inside Rust lives in Rust's allocator; MM-FFI-3 puts it outside the arena — not scrubbed, not reclaimed, not counted. Axiom cannot adopt it. Either Rust copies into Axiom-allocated memory or Axiom holds it as a `Ptr` with a registered destructor (C8, zero copy) and reaches into it through accessors.

   **The copy option is not simply "call `axiom_alloc`", and stating it that way leaks on every call.** A `Str` header must be allocated **mapped, with bit 2 set**, so that release follows the owner word: `strWrapOwned` is `(memAllocMapped 24 4)` and its comment is explicit — "The header is allocated MAPPED, with bit 2 set: word 2 is the only word of a `Str` that holds a handle to a counted block, so a header whose count reaches zero releases its owner" (`stdlib/Str.ax:59-70`). `axiom_alloc` — the only allocator symbol this section lists as externally linked — writes count 0 and an **empty** bitmap (`self_host/codegen.ax:2229-2250`, `%wshp = shl i64 %wleaf, 1`; "memAlloc'd memory is therefore a leaf by construction"), and `axiom_release` skips the walk entirely when the map is 0 (`self_host/codegen.ax:2332`). A header Rust builds with `axiom_alloc` can therefore **never** release the buffer it owns. Every string Rust hands back leaks its bytes.

   **Decision: name the construction path explicitly, and export what it needs.** Preferred: **export a runtime helper `axiom_alloc_mapped(size, map)` with external linkage alongside `axiom_alloc`/`axiom_retain`/`axiom_release`** in the runtime preamble (`self_host/codegen.ax:2046` and neighbours), because it is a stable, unmangled name that does not depend on which module `Mem` happens to be. Acceptable alternative: have Rust call the already-externally-linked `Mem$memAllocMapped` — verified present as `define i64 @Mem$memAllocMapped(i64 %bytes, i64 %map) #0` — but only through `#[link_name]` per P4's naming rule, and accepting that the symbol is hostage to the module's name. Third option, and the safest for a generated binding: make string construction a **Rust→Axiom callback** into a small Axiom constructor, so the mapped allocation happens on the side that owns the convention and Rust never spells a shape word at all.

   **Decision on the threshold: the generator defaults to the `Ptr` form for anything above a threshold and to the copy for small results**, because below roughly two words the copy is cheaper than the destructor bookkeeping it avoids. The copy's price is one mapped allocation (~8 ns, and `strAlloc` is two allocations plus the byte loop) *plus* the correctness cost of getting the map right; the `Ptr` form's price is the destructor registration and an accessor per read. The exact threshold is a tuning parameter the benchmark plan below is designed to find; do not hard-code a guess, and price the leak risk — not just the nanoseconds — when the threshold is chosen.

2. **A `&str` is required and the bytes are not known-UTF-8.** O(n) validation, not a copy, but it scales like one.

3. **A NUL terminator is required over a slice.** `strDup`, ~18 ns plus length — or the ~1-call-unit terminator check, which P4 precondition 3 now permits as an escape since the load is in-bounds for any `Str` the `Str` module built.

4. **Representation genuinely differs** — a Rust `#[repr(C)]` struct with sub-word fields against Axiom's one-word-per-value world. There is no zero-copy path here and pretending otherwise would be the single worst error this design could make. Pass a `Ptr` and accessors, or copy.

5. **A `Float` crosses the boundary.** Not a copy — an `fmov` per float argument and per float return, on each side, because the value travels in an integer register and Rust must `from_bits`/`to_bits` it. Unavoidable given C2's one-word rule, small, and listed here so that no one designs a "zero-overhead float path": there isn't one, and a shim that appears to have one is reading the wrong register class (P4).

Everything else is a copy someone chose. The generator should be auditable on this point: it should be possible to ask a generated binding "does this call allocate?" and get a static answer — and P10 makes that answer the benchmark's oracle rather than a runtime counter.

### P6. Keeping the boundary inlinable: attributes, and the LTO question answered

`opt` runs over the Axiom module only (`self_host/driver.ax:137-165`), then `llc -filetype=obj`, then `cc obj -o out` (`self_host/driver.ax:205-234`) with no `-l` and no `-L`. The Rust `.a` is already machine code by the time it is seen. So cross-language inlining requires LTO, and the brief asks whether that is feasible. **It is, it was measured working, and the blocker is one attribute group in `codegen.ax`.**

**The finding.** `llvm-link` of the emitted Axiom `.ll` with rustc's `--emit=llvm-ir` output succeeds cleanly — no warnings, despite Axiom's module having no `datalayout` and a different triple minor version. But `opt -O1` over the merged module inlined *nothing*: 3 calls to `@ax_rust_add` survived. The cause is that LLVM's inliner refuses caller/callee pairs with incompatible target attributes. Axiom emits exactly one attribute group, `attributes #0 = { "no-builtins" }` (`self_host/codegen.ax:2805`); rustc emits `{ … "target-cpu"="apple-m1" … }`. Adding `"target-cpu"="apple-m1"` to Axiom's `#0` group and re-running:

```
calls to ax_rust_add remaining: 0
_spin:
	add	x0, x1, x0
	ret
```

The Rust function was inlined into the Axiom loop and the entire recursion was then solved — 0.157s → 0.0028s, and `nm -u` on the linked executable still **empty**. Cross-language inlining across an Axiom/Rust boundary works and preserves freestanding. **Read that ratio with P1's caveat attached**: it is the same closed-form accumulator solve, not a general inlining win.

**The `cc -flto` route does not work here, and the diagnosis matters.** `rustc --crate-type=staticlib -C linker-plugin-lto` does emit the crate's own CGU as bitcode (verified: `liblto.lib.…rcgu.o` is `LLVM bitcode, wrapper`; 1 of 374 members, the rest are `compiler_builtins` Mach-O). `cc -flto -x ir -c` on the Axiom `.ll` plus `cc -flto` to link produces a correct binary with zero undefined symbols — but **no inlining**, timed at 0.1573s, and still 0.1573s after matching `target-cpu`. The remaining cause is the toolchain version split: Apple `ld64`'s LTO plugin is clang 21's LLVM, the Rust bitcode is LLVM 22.1.6, and the plugin evidently declines the mismatched member rather than failing.

**Decision: LTO is an opt-in, off-by-default mode built on `llvm-link`, not on `cc -flto`.** What it costs to ship:

- `llvm-link` becomes a required tool *for that mode only* — it ships in the same LLVM distribution as `opt` and `llc`, which are already required, so this is not a new dependency class. It must be handled the way `opt` already is: absent is a warning and a fallback, present-but-failing is fatal (`self_host/driver.ax:140-142`).
- The Rust side must build with `--emit=llvm-ir` **and** rustc's LLVM must be version-compatible with the LLVM on PATH. This is a real, fragile, new coupling with no good mitigation, and it should be stated in the spec rather than discovered by a user: a rustc upgrade can silently disable LTO or loudly break the build. Gate it by comparing `rustc -vV`'s LLVM major.minor against `opt --version` and refusing the mode on mismatch.
- **The `target-cpu` change is required, and the earlier draft described it in a way an implementer could get exactly backwards.** Two corrections:

  **Where the attribute lives.** The `#0` suffix is a literal inside the function-header string built at `self_host/codegen.ax:3014-3018` — `(let ((hdr (strConcat (cat4 "define i64 @" …) ") #0 {")))` — and the group's text is a literal at `self_host/codegen.ax:2805`. There are further hardcoded `#0` suffixes on the runtime helpers: `@axiom_alloc` (`2046`), `@axiom_retain` (`2274`), `@axiom_release` (`2292`), `@__axiom_str_eq` (`2428`), and on every emitted `declare`. **`emitDecl` (`self_host/codegen.ax:2817-2846`) has nothing to do with attribute groups**, and the earlier draft's "`emitDecl` already ignores unknown tags, so this is additive" was a non-sequitur — true of declaration tags, irrelevant to attributes. The edit is to the function-header emitter and the hardcoded helper headers, not to `emitDecl`.

  **Which functions carry it.** The inliner compares **caller against callee**. For Rust to be inlined *into* Axiom, the `target-cpu` attribute must be on the **Axiom `define`s** — putting it only on the `declare` changes nothing and reproduces precisely the "1 call survives" result reported above as the bug.

  **Decision, stated so it cannot be implemented backwards: in a module that declares at least one extern, every emitted `define` — user functions at `self_host/codegen.ax:3014-3018` and the runtime helpers at `2046`, `2274`, `2292`, `2428` alike — carries `#1` instead of `#0`, where `#1` is `{ "no-builtins" "target-cpu"="<the target's cpu>" }` emitted beside the existing group at `self_host/codegen.ax:2805`. A module with no extern emits `#0` only, exactly as today, and is byte-identical to today** — which is what keeps `scripts/check-reproducible.sh`'s fixpoint and the owner's non-FFI byte-identity requirement intact. Note that this makes the group selection a whole-module property decided before emission begins, not a per-declaration one.
- Whether LTO is *worth* it is program-dependent and the honest answer is "unknown until measured on a real workload". The 56× above is a microbenchmark measuring a call LLVM could delete; a real Rust shim that does real work will inline to a much smaller win, possibly none. The benchmark plan's `--lto` ablation exists to answer this, and no one should commit to LTO on the strength of the number above.

### P7. Batching for chatty APIs

Batching is the wrong first instinct here and should be presented as such. At 1.55 ns/call, a boundary crossing costs less than a single L2 miss; an API is not chatty because it crosses the boundary often, it is chatty because it *allocates* or *copies* often. Batching a sequence of pure scalar calls saves nothing measurable and costs a vector.

Batch when, and only when, one of these holds:

- **The per-call cost is dominated by a fixed setup the batch amortises** — acquiring a `Ptr`-held Rust resource, taking a lock, opening a handle. Amortise the setup, not the call.
- **The calls allocate.** N calls each returning a fresh Axiom `Str` cost N × (mapped allocation + copy). One call filling a caller-provided block costs one allocation. This is the real case and it is an *allocation* optimisation wearing a batching costume.
- **`memory(none)` is unavailable and the optimiser barrier is the cost.** A non-pure extern in a hot loop blocks LICM and CSE across every iteration. Hoisting the barrier out by batching recovers the loop body. Prefer fixing the purity annotation (P3) if it is honest — remembering that "honest" is an unchecked assertion, so the annotation must be *true*, not merely convenient; batch only if it is not.

The mechanism, when it applies: pass a `Ptr` to a caller-allocated Axiom block plus a count, have Rust fill it, return the number written. Zero copy in, zero allocation out, one call.

**Two shape rules on that block, and the second is the one the earlier draft got wrong:**

- If the block will hold `Ptr`s, `memAlloc` is correct: it leaf-stamps, and per P4 a `Ptr` is class 0 and contributes no bit, so nothing walks it.
- **If Rust fills the block with Axiom handles — which is exactly the N-strings case named above as the real batching win — a `memAlloc`'d block is a leak.** It is leaf-stamped, its map is 0, and `axiom_release`'s walk is skipped (`self_host/codegen.ax:2332`), so none of the N handles is ever released. Such a block must be allocated **mapped**, with a bit per handle word, through the same path P5 case 1 requires: `axiom_alloc_mapped` if that helper is exported, `Mem$memAllocMapped` via `#[link_name]` otherwise, or an Axiom-side constructor the Rust shim calls back into. **A "fill this block" batching API must declare, at the binding, whether the block's cells are handles or scalars, and the generator must choose the allocator from that declaration rather than defaulting to `memAlloc`.**

Do not build a general "call batcher" — a queue of encoded calls drained by one crossing. It reintroduces exactly the marshalling-and-dispatch cost that P1 shows Axiom does not have, in order to avoid a cost that is 1.55 ns.

### P8. The freestanding interaction is a performance constraint, not just a policy one

The measured facts, because this determines what the Rust side is *allowed* to be and therefore what it can cost:

- **`#![no_std]` + `panic="abort"` staticlib: `nm -u` on the linked executable is empty.** Independently reproduced here. Freestanding fully preserved.
- **But `no_std` alone is not sufficient.** rustc performs loop-idiom recognition *itself*, before Axiom or `opt` ever sees the IR: a plain byte-zeroing loop in `no_std` Rust emits `llvm.memset.p0.i64` in rustc's own output, `llc` lowers it to `_bzero`, and the linked executable carries `_bzero` undefined — a name explicitly on `scripts/check-freestanding.sh`'s list, added there on 2026-08-16 after it was found to be escaping. Axiom's `"no-builtins"` cannot prevent this because the transformation happened upstream of it.
- **The fix is exact.** `#![no_builtins]` on the Rust crate emits the string attribute `"no-builtins"` — character-for-character the attribute Axiom's `#0` group carries at `self_host/codegen.ax:2805`. With it: zero `llvm.mem*` in the Rust IR, zero undefined symbols in the executable. This is also what makes LTO safe: the merged module is uniformly no-builtins, so `opt` cannot reintroduce libc after linking either.
- **`std` is not merely "adds symbols", it is unpredictable.** A trivial `std` shim dead-strips to zero undefined symbols. A realistic one — `Vec::with_capacity`, `format!`, `parse` — produces **190 undefined symbols, 15 on the forbidden list**: `bzero calloc dup2 free getenv malloc memcmp memcpy memmove memset pipe realloc setenv strlen waitpid`. The boundary between passing and failing is dead-code elimination, which means a program that passes today fails when someone adds a `format!` to a shim. **That fragility, not the symbol count, is the argument.**

**Decision: this is a tier structure, not a mandate**, matching the gate already on disk (`scripts/check-ffi.sh:18-30`) and the owner's binding decision that freestanding is opt-in *relaxed* rather than opt-out forbidden:

- **Tier 1 — no extern at all.** Imports nothing. The old contract, unchanged, gated by `check-freestanding.sh`. This is what makes "the FFI costs non-users nothing" a checked claim.
- **Tier 2 — extern against a `#![no_std]`, `#![no_builtins]`, `panic="abort"` crate.** Also imports nothing: `nm -u` empty, measured. **This is the mode the `rust/` workspace should encourage and the mode a generated binding should default to**, and all three attributes are *required to be at this tier* — a crate claiming tier 2 without `#![no_builtins]` fails, because that is the measured escape route. Note that `rust/Cargo.toml` already sets `panic = "abort"` workspace-wide but does not set `no_std`/`no_builtins`, which are per-crate; the gate, not prose, is what checks them.
- **Tier 3 — extern against a `std` crate.** Permitted. The program moves from the blanket ban to MM-FFI-5 requirement 4's allowlist: it imports only what its `axiom-allow.txt` manifest enumerates, every name outside the manifest is a failure, and the never-permitted list cannot be laundered by a manifest (`scripts/check-ffi.sh:60-61`, `104-128`, `147-149`). `rust/axiom-ffi/Cargo.toml` makes `std` the default feature deliberately, "because it is what makes the ecosystem reachable" — that stands, and a tier-2 crate opts out with `default-features = false`.

Making tier 2 *mandatory* — as an earlier draft did — would leave tier 3 and the whole allowlist with nothing to gate, and would collapse MM-FFI-5 requirement 4 back into the blanket ban it was written to replace. It would also strand P2's `catch_unwind` decision, since `catch_unwind` requires `std`.

The performance consequence, stated as a tier fact rather than a contradiction: **`catch_unwind` needs `std`, so C6 is satisfied by `panic="abort"` at tiers 1–2 and may be satisfied by `catch_unwind` at tier 3.** P2's measurement says the choice costs nothing either way; this says the choice is usually made for you by the tier you are building at, and that a program wanting rich error values from Rust is a program choosing tier 3 with its eyes open.

### P9. Forward compatibility with AOT/JIT work

Nothing in this design constrains future work, because nothing in it is new machinery:

- **AOT is the only mode today and the design adds no runtime.** There is no lookup, no binding table, no trampoline that a future AOT compiler would have to reproduce. The extern is a symbol name in the emitted module and a `-l`/object on the link line. The one genuinely new runtime *symbol* this section asks for is `axiom_alloc_mapped` (P5), which is a sibling of `axiom_alloc` in the same preamble, not a new subsystem.
- **A future JIT gets the boundary for free.** A JIT resolving `@ax_rust_add` through `dlsym` or an ORC symbol resolver produces the same `call i64 (i64, i64)`. The one thing that must not be built is a JIT-only calling path, because then the AOT and JIT boundaries could diverge in ABI — the whole value of C1 is that there is exactly one. Note that a JIT will meet P4's `Mod$name` rule as a *string* lookup rather than a link-time identifier, which is easier, not harder.
- **The declared-purity attributes (P3) are IR-level and survive any pipeline.** They are not an Axiom-side annotation the backend interprets; they are text on the `declare` line. Their unchecked-assertion status travels with them, unchanged.
- **The one real forward risk is `target-cpu`.** Pinning `apple-m1` into the emitted module makes the artifact host-specific and interacts with `scripts/check-cross-targets.sh`. Emit the *target's* CPU, derived from the same target table that already drives the triple and the syscall templates (`self_host/codegen.ax:1887-1919`), or emit a generic baseline and accept that inlining may be refused. **Do not emit the build host's CPU.** Because the attribute lives in a second group `#1` used only by extern-declaring modules (P6), a cross-compiled non-FFI module is untouched by this risk entirely.
- **C3 protects the future more than the present.** Because an extern is monomorphic by construction, no extern ever grows the hidden trailing `i64 %__evw.h` that `fnTakesEvw` (`self_host/codegen.ax:464`) adds to polymorphic callees and `emitPlainCall` passes at the call site. The evidence word is MM-LIFE-2d machinery whose representation is free to change; keeping it strictly inside the language means a representation change never becomes an ABI break. P4's requirement that `Ptr` classify as an evidence-word *scalar* is the same protection one level down: it keeps a foreign address out of the machinery whose representation is expected to change.

### P10. Benchmark plan: `scripts/bench-ffi.sh`

Written in the house style of `bench-compile.sh` and `bench-datastructures.sh`: whole processes, best of REPS rather than mean (the distribution is one-sided — interference only ever makes a run slower), startup measured separately with a do-nothing binary of each language and subtracted, a printed table rather than a threshold by default because a wall-clock bound on a shared runner is a flaky test, with `--check` to enforce the bounds anyway. `black_box`-equivalent on both sides: the Rust side reads its size from `argv`, and the Axiom side derives its loop bound from `__argc`, because without that both compilers delete the loop — the first version of this benchmark measured 100M FFI calls at 0.0028s, which is not a fast FFI, it is no FFI at all. (That number is the same closed-form solve P1 and P6 warn about, met from the third direction.)

**What it decides.** Whether the boundary is free, which is the claim the whole design rests on, and where the cost that does exist is. Every microbenchmark below is paired with a *native* control — the same work with the callee written in Axiom, `noinline` so the call survives — because the interesting quantity is the *difference*, and an absolute number on a shared runner means nothing.

| # | benchmark | shape | expected | regression |
|---|---|---|---|---|
| 1 | **empty call** | `extern` taking and returning nothing, 100M iterations | **1.5–1.6 ns/call**, within ±3% of the `noinline` Axiom control | >1.15× the control, or any absolute figure >2.5 ns |
| 2 | **scalar call** | 2 i64 in, 1 i64 out | **1.55 ns/call**; must be indistinguishable from #1 — integer arguments are registers | any measurable gap over #1 **for integer-class arguments** means an argument is being spilled or marshalled; that is a bug, not a cost. Floats are row 9 and are explicitly exempt from this rule |
| 3 | **string round-trip, zero-copy** | Axiom `Str` handle → Rust `&[u8]` → byte sum | **call cost + O(n) scan only.** At 12 bytes, ≤3 ns total. Must not allocate: assert zero surviving `call i64 @axiom_alloc` sites in the loop body of the row's `.opt.ll` | any surviving allocation call site; or >1.3× the same fold written in Axiom |
| 4 | **string round-trip, copied** | same, but `strDup` first | **~20 ns at 12 bytes**, i.e. #3 + ~18 ns. Reported beside #3 so the copy's price is visible rather than inferred | >1.2× #3 + measured `strDup` |
| 5 | **opaque handle churn** | Axiom acquires a `Ptr` from Rust, stores it in a `memAlloc` block, reads it back, releases via the registered destructor, 10M iterations | **2 call-units + the destructor.** Critically: assert `axiom_release`'s reference walk is never entered — the block must be leaf-stamped — **and** assert the function taking the `Ptr` parameter emits **no** `call void @axiom_retain` in its entry block (P4's `fldClass` requirement, checked statically in the `.opt.ll`) | any evidence of the walk running over a `Ptr` word, or any entry retain on a `Ptr` parameter; both are correctness failures surfacing as performance ones |
| 6 | **fallible call, happy path** | extern with a **handle-typed** return, sub-4096 sentinel on failure, never failing | **indistinguishable from #2.** This is the number that justifies the sentinel encoding over an out-param | >1.05× #2 |
| 7 | **fallible call, sad path** | same extern, always failing | **within 2× of #6.** The sad path may branch; it must not allocate — assert zero surviving `axiom_alloc` call sites on the failure path | any surviving allocation call site, or >5× #6 |
| 8 | **retain/release across the boundary** | Rust calls `axiom_retain`, holds, calls `axiom_release` | **~6.6 ns/pair**, matching the in-Axiom measurement — an externally-linked call to the same symbol, no atomics (MM-PAR-1) | >1.2× the in-Axiom pair |
| 9 | **float call** | 2 `Float` in, 1 `Float` out; Rust shim takes `i64` and uses `f64::from_bits`/`to_bits` | **#2 plus the mandatory `fmov` pair on each side** — a small, non-zero delta, expected well under 1 ns total. Reported as a *delta from #2*, not as a pass/fail against it | >1.3× #2. A result *equal* to #2 is also suspicious and should be investigated: it may mean the shim was compiled with an `f64` signature, which reads the wrong register class and returns garbage (P4) — so this row must additionally assert the returned value is numerically correct |
| 10 | **mapped construction** | Rust builds an Axiom `Str` through `axiom_alloc_mapped` (or the callback form) and returns it; Axiom releases it | **one mapped allocation + linear copy**, and the point of the row is the *assertion*, not the time: the returned header's shape word must have bit 2 set and the buffer's refcount must reach 0 after release | a leaf-stamped header (P5 case 1's leak), or a buffer whose count never reaches 0 |

**On the allocation oracle.** An earlier draft proposed asserting that "the arena high-water mark is unchanged across the loop", and printing its movement per row. **That oracle does not exist and would not answer the question.** `@__axiom_high` is an `internal global` (`self_host/codegen.ax:2018`) with no stdlib accessor in `stdlib/Mem.ax` and no primitive that answers it, so the benchmark cannot read it without compiler work this section does not schedule. And even if it could: the watermark "describes the CURRENT chunk — `install` resets it to the new chunk's base and a reset rewinds it" (`self_host/codegen.ax:2189-2191`), and the recycled-block path leaves it untouched by construction (`%newhigh = select i1 %recyc, i64 %hh, i64 %nh`, `self_host/codegen.ax:2216`). A loop that allocates and frees every iteration through the size-class freelist moves it by exactly zero — which is precisely the shape rows 3, 5 and 7 assert. They would have passed while allocating on every iteration.

**Decision: the allocation oracle is static.** Count the `call i64 @axiom_alloc` (and `@axiom_alloc_mapped` / `@Mem$memAllocMapped`) sites surviving in the row's `.opt.ll`, scoped to the benchmarked loop. It is exact, needs no runtime support, cannot be fooled by the freelist, and is stable across machines in a way a wall clock is not. If a *dynamic* oracle is later wanted — for a workload whose allocation is data-dependent — then schedule the work honestly: a new monotone counter of bytes ever handed out, distinct from `@__axiom_high` and never rewound by a reset, plus an `Int`-answering primitive to read it. That is a real compiler change with its own fixture, not a benchmark detail, and it must not be assumed to already exist.

**Two ablations, and the script is a stopwatch pointed at nothing without them.**

*Ablation A — purity.* Re-run #2 with the extern declared `pure` and then default. The `pure` variant of a loop with a loop-invariant call must get *faster* and its IR must contain fewer calls. If both variants produce identical timings and identical call counts, the attributes are not reaching the `declare` line and P3 is not implemented. (This ablation is also the only automated evidence that `pure` does anything at all — since P3 makes purity an unchecked assertion, nothing else in the toolchain will ever tell you it was honoured or ignored.)

*Ablation B — LTO.* Re-run with `--lto`. Rows 1, 2 and 6 should collapse toward zero (the microbenchmark callees are deletable); row 3 should improve modestly; row 5 should barely move. **If every row moves together, the script is measuring process startup rather than the boundary.** `--lto` must additionally assert that `nm -u` is still empty and no `llvm.mem*` survives in the merged module, because P6 and P8 are the same risk seen from two sides — and it must assert that the Axiom `define`s in the merged module carry the `#1` group, since P6's failure mode is putting `target-cpu` on the `declare` instead and getting "1 call survives" with no other symptom.

A third check, cheap and worth having: **a byte-identity probe.** Build a program with no extern, with and without the FFI support compiled into the driver, and assert the emitted `.ll` is byte-identical and still carries `#0` as its only attribute group. That is the owner's non-FFI requirement and `scripts/check-reproducible.sh`'s fixpoint, checked directly rather than inferred from P6's reasoning.

**Files produced during this analysis** (measurement scratch, not deliverables): `/private/tmp/claude-501/-Users-chris--axiom/07fa7764-107a-4b87-a630-2d6e1f143f76/scratchpad/ffi/` — contains the patched IR variants (`bench_internal_ni.ll` with the forced-`noinline` control, `bench_internal.ll` without it, `bench_extern_{plain,nounwind,pure}.ll`, `cse.opt.ll`/`cse_pure.opt.ll`/`dce.opt.ll` for the purity ablation, `linked_cpu.ll` for the LTO finding, and `e2e-ffi.ll` for the float register-class finding), the `no_std`/`no_builtins` Rust crates under `rs/`, and the built comparison binaries.
---

## 10. Testing Strategy, Gates, and Documentation

> **Which of these exist today.** Eighteen fixtures are written and
> passing: `tests/ffi/no-extern/` (010-arith, 020-string,
> 030-effects-unchanged), `tests/ffi/nostd/` (010-fnv1a), and
> `tests/ffi/demo/` (010-add, 020-float-bits, 030-string-borrow,
> 040-owned-bytes, 050-fallible, 060-opaque-handle,
> 070-extern-effect-transitive, 200-differential-int,
> 210-differential-float, 220-differential-string, 300-arity-sweep,
> 310-abi-version, 410-foreign-not-walked, 420-null-foreign).
>
> Four are still **planned** and are deliberately written without a file
> extension, so that `scripts/check-doc-drift.sh` - which requires every
> `NNN-name.ext` a document names to exist under `tests/` - keeps
> telling the truth about which is which. All four need a second example
> crate that does not exist yet: a deliberately leaky `std` crate for the
> allowlist probe, and an ungrounded-symbol probe.


### 0. What the existing tree decides before any of this is designed

Five couplings constrain the landing order, and all five are the "corpus is the spec" trap in reverse — a gate that sweeps *every* `.ax` in the repository will judge the FFI corpus the moment it exists:

| Gate | Sweep | Consequence |
|---|---|---|
| `scripts/check-fmt.sh:65` (over a tarred copy) and `:82` (over `.`) | `find … -name '*.ax'` | `format.ax` must print `extern` **before** the first fixture lands, or every FFI case is reformatted into something that does not parse |
| `scripts/check-tree-sitter.sh:112` | `find . -name '*.ax'` | `tree-sitter-axiom/grammar.js` must have an `extern_declaration` rule first, for the same reason |
| `scripts/check-diagnostics.sh:330-331` silence sweep | `self_host/`, `stdlib/`, `stdlib/Sys/`, `tests/stdlib/`, `tests/selfhost/` | `tests/ffi/` must be **added** to that sweep, or a checker that rejects every FFI program passes it. Three mechanical edits, not one — see §1.9 |
| `scripts/check-doc-drift.sh:135,141` | `ax_files = len(glob("**/*.ax"))`, matched against `` gated against all (\d+) `\.ax` files `` | adding `tests/ffi/*.ax` changes a number `README.md:1324` states (**404** today), recomputed on every CI run. The count must move in the same commit |
| `scripts/check-doc-drift.sh:94` | constructed `AX` codes, floor 45, **47 today** | seven new codes takes the constructed count to **54**. The floor at `:94` must be re-derived in the same commit, or it is a floor with nine cases of slack (§1.6's own lesson, applied to the gate that teaches it) |

And one hard prohibition: **no FFI case may live in `tests/stdlib/`.** `check-freestanding.sh:77` and `:139` and `check-reproducible.sh:39` all glob `tests/stdlib/*.ax` unconditionally; a linked case dropped there turns the freestanding gate red on purpose-built code, which is worse than no gate. `tests/ffi/` is a separate tree by necessity, not by taste.

**Decision: that prohibition gets a gate, not a paragraph.** It was stated as convention in the first draft and left unenforced, which is this repository's own named failure — a constraint nobody can see fail is a constraint nobody has checked. `check-ffi.sh` Check G (§1.4) asserts that no file matching `tests/stdlib/*.ax` contains an `extern` declaration, and prints the count of files it scanned so the assertion cannot pass on an empty glob. Two lines, the same shape as §1.7's Class-1 probes, and it closes a hazard that is exactly one misplaced file away.

---

### 1. `scripts/check-ffi.sh` — the MM-FFI-5(4) replacement

#### 1.1 Division of labour with `check-freestanding.sh`

**Decision: `check-freestanding.sh` is not replaced, retargeted, or taught about the FFI. It keeps its corpus (`tests/stdlib/`), its 31-name `libc_names` list (`check-freestanding.sh:55-70`), its `llvm.mem*` intrinsic check (`:91-103`), its stage1 pass (`:135-168`) and its negative probes, and it keeps ending in the `foreign` → AX2004 probe (`:265-288`).** MM-FFI-5's word "replaced" is satisfied per-program, not per-repository: for a program with no `extern` the blanket ban still applies and `check-freestanding.sh` is still what enforces it; for a program with one, `check-ffi.sh` is the gate and it enumerates.

Alternative considered and rejected: fold everything into one script that decides per case which contract applies. Rejected because the decision would have to be made by reading the program, and a gate that reads the program to decide what to demand of it is a gate that a mis-parse silently relaxes. Two scripts over two disjoint trees have no such degree of freedom.

The one edit to `check-freestanding.sh` is its header paragraph, which currently says the source-level door is shut *forever* (`check-freestanding.sh:36-54`, and again at the probe's own comment `:265-288`). It becomes: the door named `foreign` is shut forever; the door named `extern` is opened and gated elsewhere; and the probe stays exactly as it is, because AX2004 for `foreign` is now a *stronger* claim than before — the language has an FFI and still refuses the retired spelling.

#### 1.2 Where the permitted set comes from

Three candidate sources, and the design uses two of them for two different questions:

1. **The program's own `extern` declarations** — compiler-derived, zero maintenance. This answers *"is every `declare` grounded?"*
2. **A checked-in per-crate manifest** — human-reviewed. This answers *"what does the archive drag in?"*
3. A single global allowlist — **rejected.** It would permit a symbol for every program because one program needs it, which is the laundering the never-permitted list exists to stop.

The split matters because the two sets do not overlap. An `extern`'s `axffi_*` symbol is *defined* by the static archive and resolved at link, so it never appears in `nm -u` on the executable. What appears there is what the archive itself left undefined — libc, `_Unwind_*`, dyld stubs. So:

```
permitted(exe)  =  union over crates on the link line of  axiom-allow[.<target>].txt
grounded        =  { declare-set of the emitted IR }  ⊆  { defined_symbols_of over the archives }
```

**Decision: the gate must not re-derive the `declare` set by parsing Axiom source.** A gate that re-implements the compiler's idea of the program disagrees with it exactly when it matters. The compiler gains one flag:

```
axiom build --input p.ax --output p --emit-link-manifest p.link
```

which writes one line per emitted `declare` and one per archive on the link line:

```
extern axffi_add       arity=2  lib=demo
extern axffi_shout     arity=2  lib=demo   out-cell
archive rust/target/release/libaxiom_demo.a
```

That file is the gate's input for the grounded check and for the ABI-shape checks in §6. It is also what makes the gate cheap: no LLVM parsing, no `nm` on the IR.

**Symbol names in the manifest are written unprefixed**, in the spelling the Axiom source used. Every comparison against a platform symbol table — defined *or* undefined — goes through the platform split of §1.4; see the correction in §1.4 Check B, which was the first draft's most consequential single error.

#### 1.3 Manifest format

`rust/examples/<crate>/axiom-allow.txt`, or `axiom-allow.<target>.txt` when present (`darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`, `linux-x86_64` — the four `check-cross-targets.sh:44` already names). One name per line, `#` comments, blanks ignored.

**Decision: a line ending in `*` is a prefix pattern, and a pattern line MUST carry a `# why:` comment on the same line or the gate refuses the manifest outright.** Measurement 2 in the brief produced 188 undefined symbols against a std staticlib; enumerating all 188 exactly is a file nobody will re-review, and collapsing them silently to `*` is a manifest that permits everything. Forcing a written justification per wildcard is the compromise, and it is checkable.

**The exemplar's two justifications are load-bearing and the first draft got both wrong.** A wildcard's whole value is that it forces a *true* sentence; an exemplar that models plausible-sounding fiction teaches the failure mode it exists to prevent. Both are rewritten:

```
# std staticlib, darwin-aarch64. Measured 2026-08-18: 188 undefined.
malloc
free
memcpy
memmove
memset
_Unwind_*   # why: std ships unwind tables and personality routines even under
            # panic="abort". Permitted because C6 FORBIDS unwinding across the
            # boundary and the shim aborts first - NOT because the code is
            # unreachable; std's abort path does reach its backtrace machinery.
dyld_*      # why: Mach-O lazy-binding stubs the system linker inserts, not
            # program symbols; resolved by the loader, touch no Axiom state.
_tlv_*      # why: Darwin's TLS accessor. std's own runtime DOES enter it on
            # ordinary paths (panic count, stdio locks, thread info), so a shim
            # that touches TLS reaches it. Permitted because it is resolved by
            # the system loader and touches no Axiom state. MM-PAR-1 is
            # unaffected: it constrains the AXIOM side - no threads, no async,
            # no atomics, no TLS at the LANGUAGE level - and says nothing about
            # what a linked archive does inside itself.
```

Both old justifications asserted unreachability, and both were false: `_tlv_bootstrap` appears among the 188 measured undefined symbols precisely because linked-in code references it. A wildcard is permitted for what it *cannot reach into* (Axiom state), not for being dead.

Per-target manifests rather than one merged file: a merged file permits a Linux symbol on Darwin, which is precisely the class of hole this gate exists to close.

Above the manifest sits `never_permitted`, unconditional and un-launderable:

```
never_permitted='printf|puts|fopen|fwrite|fread|system|popen|execv|execve|execvp|posix_spawn|posix_spawnp|fork|vfork'
```

Note what is **not** on it: `malloc`, `free`, `memcpy`, `strlen`. Those are on `check-freestanding.sh`'s `libc_names` (`:55-70`) and must stay there, but a std Rust crate genuinely needs them, and a gate that refuses them refuses the entire std tier the owner decided to support. The distinction is *who* calls them, and the first draft asserted that distinction without gating it — see Check F, which is the correction. Say this out loud in the script header, because it looks like a weakening and is not one.

`never_permitted` keeps the process-control family because that is the one capability where reaching for libc is tempting from *Axiom's* side (`check-freestanding.sh:41-48`, which records the measured `(foreign posix_spawn ...)` incident) and `stdlib/Job.ax` already implements it over raw syscalls. A manifest permitting `posix_spawn` means someone routed process control through Rust to get around MM-PAR-1, and that is a design decision, not a manifest edit.

**A corollary of Check F, stated here because it is a language rule and not only a gate rule: an `extern`'s `#:symbol` may not name a libc function directly.** The boundary is Axiom → `axffi_*` shim → whatever Rust does inside. Binding `malloc` from Axiom source puts `call i64 @malloc(…)` in Axiom's own emitted module, and Check F catches it with the same grep `check-freestanding.sh` uses. That is the intended reading of MM-FFI-3: the archive may allocate; Axiom's emitted code may not.

#### 1.4 The checks, in order

**Check A — tier 1, structural.** For every `tests/ffi/no-extern/*.ax`:
- emitted IR has zero `^declare` lines,
- the module preamble is still exactly `target triple = "…"` with no `datalayout`, no `source_filename`, no module flags,
- the only attribute group is `attributes #0 = { "no-builtins" }` (`codegen.ax:2805`),
- `nm -u` on the executable is **empty**,
- and the `cc` argv contains no `-l` and no `-L`.

That last one is the only direct observation of "the link line is unchanged", and it is measured the way `check-driver.sh:146,168` already measures a driver's behaviour — by putting a recording shim named `cc` on the front of `PATH`:

```bash
mkdir -p "$work/rec"
cat > "$work/rec/cc" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$AXIOM_CC_ARGV_LOG"
exec /usr/bin/cc "$@"
SH
chmod +x "$work/rec/cc"
AXIOM_CC_ARGV_LOG="$work/argv.log" PATH="$work/rec:$PATH" \
  "$axiom" build --input "$case_file" --output "$exe"
grep -qE '^-[lL]' "$work/argv.log" && { echo "FAIL $name: a no-extern build put a library on the link line"; status=1; }
```

**Which IR each check reads is part of the check.** `driver.ax:236-243` documents that `--emit-llvm` preserves the **PRE-`opt`** IR — "the optimiser's input rather than what llc consumed", written there expressly for whoever writes a gate that greps it. So: Check A's IR assertions, Check D and Check F all read pre-`opt` IR; Check A's `nm -u` and Check C read the linked executable, which is the only post-`opt` window either has. Neither window alone is sufficient, which is the whole subject of Check F.

**Check B — grounded declares.** Every `extern` line in the `.link` manifest names a symbol that the **defined-symbol reader** reports in one of the archives that manifest lists.

**The reader is platform-split, exactly like the undefined-symbol reader, and this is a correction.** The first draft confined underscore handling to `symbols_of` on the grounds that "the Darwin `_`-prefix asymmetry is handled where it is observable" — but it is observable on the defined side too, and confining it there would have made Check B fail on every case on the only platform where all three hands-on experiments were run. Measured on this host: `cc -c` a file defining `axffi_add`, `ar rcs libt.a t.o`, then `nm --defined-only libt.a` → `0000000000000000 T _axffi_add`.

```bash
# Undefined side, mirroring check-freestanding.sh:108 and :150.
symbols_of() {
  case "$(uname -s)" in
    Darwin) nm -u "$1" 2>/dev/null | sed 's/^_//' || true ;;
    *)      nm -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' || true ;;
  esac
}
# Defined side. Same split, same reason, and it is the half a first
# draft of this section omitted.
defined_symbols_of() {
  case "$(uname -s)" in
    Darwin) nm --defined-only "$1" 2>/dev/null | awk '{print $NF}' | sed 's/^_//' || true ;;
    *)      nm --defined-only "$1" 2>/dev/null | awk '{print $NF}' || true ;;
  esac
}
```

Check B is what stops §9.1 of `docs/self-hosting.md` from happening a second time: `foreign` emitted `call i64 @putchar(…)` into a module declaring no `@putchar`, `check` answered OK, and the program died in `opt` with an error about generated code and no span into the source. **The FFI's whole claim to being better than `foreign` is that this is a compile-time refusal (AX3041, §8), and Check B is what proves the refusal is wired to reality rather than to a hand-maintained list.**

**Check C — closure.** `symbols_of exe` ⊆ `permitted(exe)`.

**Check D — no backdoor.** The `declare` set of the emitted pre-`opt` IR equals the `extern`-declaration set of the `.link` manifest, as sets. An extra `declare` means some emitter path other than the `TAG_D_EXTERN` arm learned to write one; a missing one means a declaration was dropped, which is `emitDecl`'s (`codegen.ax:2817-2846`) documented failure mode — it emits only `TAG_D_FN` and every other tag falls through unchanged and *silently*.

**Check E — the compiler itself is extern-free, and cargo never bootstraps it.** Two assertions:

```bash
# 1. zero declares in the compiler's own IR
[[ "$("$axiom" emit-llvm self_host/main.ax | grep -c '^declare')" == 0 ]] || fail

# 2. cargo appears in bootstrap-from-seed.sh only in COMMENTS.
#    A bare `grep -c cargo` answers 2 on a clean tree today and the
#    check would be red the day it was written - the comment-vs-code
#    trap check-doc-drift.sh:85-88 documents and works around by
#    truncating at the first `;`. Strip comments, then count.
n=$(grep -v '^[[:space:]]*#' scripts/bootstrap-from-seed.sh | grep -c cargo || true)
(( n == 0 )) || { echo "FAIL: bootstrap-from-seed.sh invokes cargo ($n sites)"; status=1; }
```

The two surviving mentions are `scripts/bootstrap-from-seed.sh:36` ("Requires: llc, cc. Not cargo, not rustc.") and `:43` (a note that `AXIOM=<dir>/axiom` is the single knob for a `cargo build --release` tree). **They must not be deleted.** They are the script's own written promise, and this assertion exists to protect that promise, not to erase its statement. The owner made "cargo never bootstraps the compiler" binding; this is the two-line assertion of it, and it belongs here rather than in `check-bootstrap.sh` because the pressure to break it comes from the FFI.

**Check F — Axiom's own emitted code still calls no libc, in FFI programs too.** This is the check the first draft was missing, and its absence was a hole the manifest itself opened.

The reasoning that failed: §1.3 permits `malloc`, `free`, `memcpy` and `strlen` in a std-crate manifest, and justified it by saying "Axiom's own code may not, which `check-freestanding.sh` still enforces over `tests/stdlib/`". But `check-freestanding.sh` never sees `tests/ffi/`. So `opt -O1` rewriting an Axiom byte loop into a `strlen` call inside an FFI program — the exact bug the stage1 pass exists for (`check-freestanding.sh:130-134` records it, measured, caught only by `nm`), and the entire reason `attributes #0 = { "no-builtins" }` exists in the string form — would sail through Check C, because `strlen` is in the manifest.

So, for **every** case under `tests/ffi/` including tier 2 and 3, unconditionally and *independently of the manifest*:

```bash
# check-freestanding.sh:83 and :91-103, run verbatim over the FFI corpus.
grep -nE "call[^\"]*@($libc_names)\(" "$ir"                 && fail   # Axiom's own calls
grep -nE '@llvm\.(memset|memcpy|memmove)\.' "$ir"           && fail   # the intrinsic door
```

The manifest governs **only what the archive left undefined**. It has no authority over what Axiom's own module emits, and saying so in the script header is the difference between a permitted symbol and a laundered one. The `libc_names` list is sourced from `check-freestanding.sh` rather than copied, so the two cannot drift.

This is also what enforces §1.3's corollary: an `extern` whose `#:symbol` names a libc function directly emits `call i64 @malloc(…)` into Axiom's module and is caught here.

**Check G — no FFI case in `tests/stdlib/`.** §0's prohibition, gated:

```bash
scanned=0; offenders=""
for f in tests/stdlib/*.ax; do
  scanned=$((scanned + 1))
  grep -qE '^\s*\(\s*(pub\s+)?extern\b' "$f" && offenders="$offenders $f"
done
(( scanned >= 140 )) || { echo "FAIL: the tests/stdlib scan read only $scanned files"; status=1; }
[[ -z "$offenders" ]] || { echo "FAIL: extern in a tree three gates glob unconditionally:$offenders"; status=1; }
echo "ok   $scanned tests/stdlib cases contain no extern"
```

The printed count is what stops the assertion from passing on an empty glob — the same discipline §1.6 applies everywhere else.

#### 1.5 Counting: no hand-written floors where a filesystem count exists

`check-freestanding.sh:164` has `[[ "$s1_checked" -ge 30 ]]`, and `tests/diagnostics/verify-axdl-spans.py:96-121` records at length what happens to such a number when the corpus triples: on 100 of the 126 goldens, all four old floors report nothing, and "a floor is a measurement with an expiry date, and a growing corpus is what expires it."

**Decision: this gate counts what it *should* have read, from the filesystem, and compares.**

```bash
expected=$(ls tests/ffi/no-extern/*.ax 2>/dev/null | wc -l | tr -d ' ')
(( expected >= 3 )) || { echo "FAIL: tests/ffi/no-extern holds only $expected cases"; status=1; }
(( tier1 == expected )) || { echo "FAIL: read $tier1 of $expected no-extern cases"; status=1; }
```

The `>= 3` is the only constant, and it guards an empty directory rather than a shrinking one. Floors survive only where the thing counted is not a file: the permitted-symbol count printed per crate, the `tests/stdlib` scan of Check G, and the never-permitted alternation's own parse (`(( ${#forbidden[@]} < 12 ))` — the shape of `check-freestanding.sh:204`, whose own guard is `< 25` against a 31-name list).

**A `.ax` with no `.out` is a failure, not a skip — scoped to the case directories.** The rule is `tests/ffi/no-extern/`, `tests/ffi/demo/` and `tests/ffi/probe-*/`. It explicitly does **not** apply to `tests/ffi/bindings/`, which holds generated *modules* rather than cases and must not have `.out` files; the first draft stated the rule over the whole tree and its own layout contradicted it. A fixture that stops being checked because its expectation was deleted is the vacuous-agreement failure `check-diagnostics.sh:85-95` names first.

#### 1.6 Negative probes

The repo's rule — "a gate that has never been seen to fail is a gate nobody has checked" (`check-freestanding.sh:176`) — bites hard here, because Checks A–G all assert set relations, and every one of them is satisfied by an empty corpus, a silent `nm`, and a manifest that permits everything. Twelve probes, in three classes.

**Class 1 — the instruments report at all.**

- **P1. The undefined-symbol reader sees an undefined symbol.** Compile a two-line C file naming `some_undefined_symbol_xyz`, require `symbols_of` to report it. Without this, Checks A and C both pass vacuously on every input.
- **P1b. The *defined*-symbol reader sees a defined symbol.** Build a one-function archive (`cc -c`, `ar rcs`), require `defined_symbols_of` to report that function *unprefixed*. This is the probe whose absence would have let Check B report "every extern is ungrounded" on Darwin — a prefix mismatch must surface as a probe failure, not as a corpus-wide false refusal.
- **P2. The `declare` grep fires.** Run it against a line the script writes itself: `declare i64 @axffi_probe(i64, i64) #0` must match; `define i64 @axffi_probe(i64, i64) #0` must not. A pattern anchored wrong reports "no declares" over an IR full of them.
- **P3. The never-permitted alternation catches each of its names and discriminates.** One synthetic line per name, exactly as `check-freestanding.sh:197-212` does it — the old single-probe form exercised one alternative of a 31-name alternation and a typo in the other thirty was invisible. Plus the discrimination half: `freelist`, `awaited`, `axiom_alloc`, `axffi_forkjoin` must **not** match (`fork` inside `forkjoin` is a live substring hazard, and `check-freestanding.sh:222` already probes exactly this shape).

**Class 2 — the gate goes red on a real build.** These are the ones the string-comparison probes cannot stand in for, and they are the reason this design costs three extra cargo builds.

- **P4. An unpermitted symbol fails a real link-and-scan.** `rust/examples/probe-leaky/` is a std crate that calls `std::env::var` (dragging in `getenv`) with an `axiom-allow.txt` that deliberately does not list it. `tests/ffi/probe-leaky/010-uses-env.ax` binds it. The gate builds it and **requires Check C to fail**; the gate fails if it passes. This is the only probe that exercises `nm`, the manifest parser, `comm`, and the per-target file selection together on real artifacts.
- **P5. An ungrounded `declare` is refused before the toolchain runs.** `tests/ffi/probe-ungrounded/020-missing-symbol.axbad` declares `#:symbol "axffi_no_such_thing"` against the demo crate. **The invocation is `axiom build --input … --output …`, not `axiom check`** — see §1.9: AX3041 is a build-mode diagnostic by construction, because the link line is what it consults. Required outcome: exit non-zero, AXDL carrying **AX3041**, and — critically — the string `opt:` and the string `AX4003` must **not** appear. A refusal that arrives from the native toolchain is the `foreign` bug wearing a new name, and this probe is what tells the two apart.
- **P6. Tier 1's emptiness claim can fail.** Run the tier-1 assertions against a case that *does* link (`tests/ffi/demo/010-add.ax`), and require the assertion to report a non-empty `nm -u`, an `-l` on the argv, or a non-zero `declare` count. Without P6, "no-extern programs import nothing" is a statement about an empty directory.
- **P7. The no_std emptiness is a measurement, not an artifact.** Link `tests/ffi/demo/010-add.ax` against the **std** build of the same crate (`--features std`) with the no_std manifest in force, and require Check C to report symbols in the tens or hundreds. Experiment 1 measured `nm -u` **empty** against a no_std staticlib; P7 is what makes that emptiness evidence rather than a broken toolchain. Assert `count >= 20`, not `== 188` — the exact number is a Rust-version artifact and pinning it is a gate that goes red on a toolchain bump for no reason.
- **P12. Check F's grep fires on real post-`opt` output.** Build one tier-2 case with `"no-builtins"` ablated out of the attribute group in a scratch copy of `codegen.ax` (the `check-symbol-names.sh:80-90` ablation idiom, which ran `llvmSym` reduced to the identity against its own script), and require Check F to report a `strlen` or `memset` call. Without this, Check F is a grep nobody has watched match, over exactly the window the string attribute exists to protect.

**Class 3 — the policy surfaces stay shut.**

- **P8. A manifest may not launder a never-permitted name.** A probe manifest listing `posix_spawn` must be refused, and refused *before* any build, so the refusal is not confused with a link failure.
- **P9. A wildcard without `# why:` is refused.** `_Unwind_*` alone fails; `_Unwind_*  # why: …` passes. The whole value of the pattern form is that it forces a sentence, and a gate that accepts a bare wildcard has silently returned to "permit everything".
- **P10. `foreign` is still AX2004.** Carried over verbatim from `check-freestanding.sh:265-288`, including the assign-inside-the-`if` trick documented at `:273-280` (a bare `out="$(cmd)"` under `set -e` kills the script one line before its own verdict). It means more now than it did: the language has an FFI and still refuses the retired spelling, so old source keeps getting migration advice instead of a new meaning.
- **P11. Check G can fail.** Write an `extern` into a scratch copy of one `tests/stdlib` case and require Check G to name that file. A prohibition whose detector has never matched is the prohibition §0 spent a paragraph on and then left to trust.

Two housekeeping probes worth having but not worth a number: `axiom --abi-version` prints something parseable, and the bindgen regeneration diff is non-vacuous (mutate one byte of the checked-in `.ax`, require the diff to fail).

#### 1.7 The stage1 pass

`check-freestanding.sh:135-168` re-runs its entire sweep with the self-hosted compiler, and its header (`:130-134`) records why in one measured sentence: nothing ever ran the gate against stage1's output, and a real bug lived in that gap — `opt` rewrites a byte loop into `strlen` on stage1's register/phi IR while it cannot on stage0's alloca form, so every case failed and the gate was green because it only ever asked stage0.

**The FFI has a strictly larger version of that gap**, because the FFI is one new `emitDecl` arm and one new call-site shape, and `emitDecl` (`codegen.ax:2817-2846`) is exactly the function whose documented behaviour is that an unhandled tag is dropped in silence. A stage1 that parses `extern` and does not emit its `declare` produces a module with a call to an undeclared symbol — the `foreign` failure, reintroduced in the *second* compiler only.

So the stage1 pass re-runs **Checks A, B, C, D and F**, not a subset. F is in the list for the reason the header above records: the measured `strlen` rewrite happened *only* on stage1's IR shape, so a stage0-only Check F would be the same blindness in a new place.

```bash
if [[ "${AXIOM_SKIP_STAGE1:-0}" != 1 ]]; then
  "$axiom" build --input self_host/main.ax --output "$work/stage1" || { … }
  # every tier, Checks A B C D F, with $axiom replaced by $work/stage1
fi
```

and it adds one check that only makes sense at stage1: **stage0 and stage1 must emit the byte-identical `declare` block and the byte-identical `.link` manifest** for every FFI case. Not the whole module — `docs/v1-roadmap.md:1264` records that 0 of 71 comparable `.ll` pairs are byte-identical by design, and demanding more would be asking stage1 to adopt a retired compiler's register naming. The `declare` block is the part that *is* the contract, and it is small enough to diff.

The environment variable name matches `check-freestanding.sh:135` deliberately: one switch turns off the stage1 half of both freestanding gates, because a contributor who wants the fast loop wants it in both.

#### 1.8 Cargo, skipping, and CI

```bash
if ! command -v cargo > /dev/null 2>&1; then
  if [[ "${AXIOM_REQUIRE_CARGO:-0}" == 1 ]]; then
    echo "FAIL: cargo is not on PATH and AXIOM_REQUIRE_CARGO=1"; exit 1
  fi
  echo "skip: cargo not on PATH; tiers 2 and 3 need it ($n_ffi cases not run)"
  # tier 1 plus Checks E and G still run - they need no Rust at all
  run_tier1; check_e; check_g; exit "$status"
fi
```

**Decision: a cargo-less machine skips tiers 2–3 and still runs tier 1 and Checks E and G, and `.github/workflows/ci.yml` sets `AXIOM_REQUIRE_CARGO=1`.** A silent full skip is the failure this repository names most often; a hard failure on a fresh checkout contradicts the owner's rule that a checkout with no Rust toolchain still produces a compiler. The env var is how both are true at once, and the skip line prints the count it did not run, so "skip" never reads as "pass". Checks E and G stay in the skip path deliberately: they are the two that assert cargo's *absence* from the bootstrap and the FFI's absence from `tests/stdlib`, and a machine with no cargo is exactly where those claims should still be tested.

CI placement: a new job after `check-freestanding.sh` (`.github/workflows/ci.yml:105-106`) and before `check-self-host.sh` (`:119-120`), because it is the cheapest gate that can fail on an FFI change, and CI is staged cheapest-first by its own header.

#### 1.9 Which invocation AX3041 fires under, and what that costs the silence sweep

**Decision: AX3041 is a `build`-mode diagnostic and cannot fire under `axiom check`.** Its condition — "the `#:symbol` name is defined by no archive on the link line" — names an artifact that `check` does not have and does not construct. Pretending otherwise would require `check` to run cargo, which contradicts §1.8's whole premise.

That has three consequences the first draft left unstated, and all three are mechanical edits to `scripts/check-diagnostics.sh`:

1. **The sweep entry.** `tests/ffi/*/*.ax` joins the globs at `:330-331`, excluding nothing — `bindings/Demo.ax` is included on purpose, because a generated module that draws a diagnostic is precisely what should be caught. `.axbad` files are outside the glob by extension, so `probe-ungrounded/020-missing-symbol.axbad` never reaches it.
2. **No exit-status exemption is needed, and this is a claim, not a hope.** The sweep runs `./axc --diagnostic-format=ai "$src"` from `$work` (`:339`) and demands both silence and exit 0, with the exemption at `:346` (`elif [[ "$out" != 0 && "$src" != tests/stdlib/* ]]`) applying to `tests/stdlib/` alone. Every `tests/ffi/` case is a well-formed program under `check`: the `extern` parses, registers, seeds its effect, and — because AX3041 is build-only — grounds nothing. So each exits 0 and stays silent. **The corollary is that the sweep covers every FFI check *except* AX3041**, and that must be written into the script's header beside the entry, or a future reader will believe the sweep proves grounding.
3. **Both floors move.** A `sweep_floor "tests/ffi/" <n> "$(ls tests/ffi/*/*.ax 2>/dev/null)"` line joins the four at `:455-458`, and the total floor at `:461-463` (`swept -lt 240`, comment "expected ~256") must be re-derived against the printed count once `tests/ffi/` lands — roughly 256 + 18. Landing the glob without the floor is the "floors expire" lesson committed in the same commit that teaches it.

`$work` symlinks only `stdlib/` and `self_host/`, so any FFI case that imports the generated `bindings/Demo.ax` must reach it by a path the sweep can resolve; the simplest answer, and the one taken, is that `tests/ffi/bindings/` joins the symlinked set.

---

### 2. The FFI test corpus

#### 2.1 Layout and numbering

```
tests/ffi/
  no-extern/                       tier 1: controls, no Rust, no cargo needed
    010-arith.ax        .out
    020-string.ax       .out
    030-effects-unchanged.ax  .out      (see §2.4 - NOT the FFI effect pin)
  demo/                            binds rust/examples/demo
    010-add.ax          .out
    020-float-bits.ax   .out
    030-string-borrow.ax .out
    040-owned-bytes.ax  .out
    050-fallible.ax     .out  .exit
    060-opaque-handle.ax .out
    070-extern-effect-transitive.ax  .out  .exit   ← MM-FFI-5(3)'s pin (§2.4)
    200-differential-int.ax    .out
    210-differential-float.ax  .out
    220-differential-string.ax .out
    310-abi-version.ax  .out
    400-arc-retain   .out
    410-foreign-not-walked.ax  .out
    420-null-foreign.ax .out
  probe-leaky/                     P4's crate: must FAIL the gate
    010-uses-env     .out
  probe-ungrounded/                P5: must FAIL the checker, under `build`
    020-missing-symbol
  bindings/
    Demo.ax                        generated by axiom-bindgen, checked in
                                   (a module, not a case: no .out, §1.5)
```

Three-digit prefixes, as everywhere. The block convention: `0xx` shapes, `2xx` differentials, `3xx` ABI facts, `4xx` memory. The crate is the directory name — no per-case metadata file, so a case cannot name a crate the gate does not build.

Two corrections against the first draft's layout, both consistency repairs:

- **`300-arity-sweep.ax` is gone from the tree, because the arity sweep is generated.** §5 and §6 both describe it as one program per shape emitted into a work directory by `check-ffi.sh`, and listing a checked-in fixture of the same name meant the same thing existed twice under two contradictory descriptions. **Decision: the sweep is generated, never checked in.** Nothing under `tests/ffi/` is a sweep case; §5's shape assertions read the generated IR.
- **`310-abi-version.ax` is present**, because §5 requires an end-to-end ABI-version diff through a linked artifact and the first draft's layout omitted the file it named. §1.5 derives its expectation count from the filesystem, so a case named in prose and absent from the tree is a count that does not add up.

#### 2.2 How expectations are pinned

**Decision: `.out` + optional `.exit`, exactly `run-stdlib-tests.sh`'s convention (`scripts/run-stdlib-tests.sh:50-53`), and NOT `tests/selfhost`'s `; expect N` first line.** `tests/selfhost` uses exit status because stage1 has no way to print (`check-self-host.sh:12-15`); FFI cases have `IO` and printing a value is a far better failure message than an exit code. The `.exit` file is kept for the fallible cases, where the point is that an `Err` reaches `main`'s exit status.

A fourth runner is not written. `scripts/run-stdlib-tests.sh` gains an optional tree argument:

```
scripts/run-stdlib-tests.sh                    # tests/stdlib, unchanged
scripts/run-stdlib-tests.sh --tree tests/ffi/demo --link demo
```

Alternative considered: a `run-ffi-tests.sh`. Rejected — the build/run/diff/exit logic is 40 lines and duplicating it means two places to fix the next `case_dir` isolation bug (`run-stdlib-tests.sh:55-59`, where each case gets its own directory because leftovers make a failure look like a pass).

#### 2.3 Refusal cases live in `tests/diagnostics/`

**Decision: every FFI *refusal* fixture goes in `tests/diagnostics/`, numbered in the free `7xx` block, and gets all three goldens (`.axdl`, `.human`, `.json`).** Not in `tests/ffi/bad/`.

Why: `tests/diagnostics` is where the three-format golden machinery lives, where `AXIOM_BLESS=1` works (`check-diagnostics.sh:68-72`), and — the load-bearing part — where `tests/diagnostics/verify-axdl-spans.py` re-derives every span against the fixture's own bytes and *refuses the bless if it fails*. A separate FFI golden tree would get none of that, and span correctness is exactly what a new declaration form gets wrong: `extern`'s span must cover the name, not the keyword, and nothing but the span verifier would notice.

The one exception is `probe-ungrounded/020-missing-symbol.axbad`, which lives under `tests/ffi/` because its refusal depends on an *archive* being on the link line and on `build` rather than `check` (§1.9) — it is not reproducible from the fixture's bytes alone, so it cannot join a tree whose whole discipline is that it is.

Planned fixtures (each pins one new code, §8):

```
tests/diagnostics/700-extern-type-variable.axbad     AX3040
tests/diagnostics/710-extern-wire-type.axbad         AX3042
tests/diagnostics/720-foreign-arena-primitive.axbad  AX3043
tests/diagnostics/730-foreign-unclosed.ax            AX3044   (warning: exit 0)
tests/diagnostics/740-extern-duplicate-symbol.axbad  AX3045
tests/diagnostics/750-extern-freestanding.axbad      AX3046
```

`730` carries no `E` line and must exit **0** — `check-diagnostics.sh:31-37` reads the required exit status off the golden's own severity column ("a golden carrying an `E` line means the run must fail, a golden carrying only `W` means it must succeed"), so a warning fixture that exits non-zero fails without anyone writing a rule.

#### 2.4 The effect pin is an extern case, not a no-extern case

The first draft claimed MM-FFI-5's requirement (3) — an extern call is an inferred effect — was "pinned by `tests/ffi/no-extern/030-effects.ax`". It cannot be. §1.4 Check A requires every case in that tree to emit **zero** `declare` lines, so by construction nothing there has an extern, and nothing there can witness `builtinEff "IO"` being seeded into an extern's `FnEnt` or propagated out of one. Requirement (3) would have landed with no fixture at all.

**Decision: `tests/ffi/demo/070-extern-effect-transitive.ax` is the pin.** Its `main` calls an extern through **one intermediate function that performs no syscall and looks pure**, with no `handle` and no `;@axiom:effect(io)` anywhere:

```axiom
(import Demo)

; No syscall anywhere in this file. The only source of IO is the
; extern's SEEDED FnEnt (C5, the tcAddEffectOp shape at
; typecheck.ax:1866-1876), and `wrap` gets it only because
; inferEffects (typecheck.ax:5199-5241) is a monotone fixpoint over
; the call graph. Both halves fail loudly if either is missing:
; without the seed there is no effect to propagate, and without the
; fixpoint the effect stops at `wrap`.
(:: wrap (-> Int Int))
(fn (wrap n) (Demo::add n 1))

(:: main Int)
(fn (main) (wrap 41))
```

Required outcome: **AX3011**, at the `handle` site the program does not have, exit non-zero. That single case proves seeding *and* transitive propagation together; neither is provable without the other present.

The no-extern tier keeps an effects case, renamed to say what it actually checks: **`030-effects-unchanged.ax` asserts that a program with no `extern` produces exactly the effect sets it produced before the FFI landed** — that adding a seeding path to registration perturbed nothing for the 99% of the corpus that never uses it. That is a real claim and a different one, and naming the file for it stops the two from being confused again.

---

### 3. Round-trip and differential tests

A differential between Axiom and Rust proves they agree. It does not prove either is right, and this repository has already been bitten by that: `check-diagnostics.sh:9-15` records a differential whose reference disappeared, becoming a compiler compared against itself — "swept, zero differences, exit 0, nothing tested."

**Decision: every differential is three-way — Axiom native, Rust through the FFI, and a checked-in `.out` holding the expected values.** The `.out` is the third opinion, and it is what makes the case fail when both implementations are wrong the same way.

**Decision: differentials are written over the representations that actually differ, not over arithmetic.** `add(20, 22) == 42` proves the link works and nothing else.

#### 3.1 `210-differential-float.ax`

Axiom carries a `Float` as its IEEE-754 bits in an i64 and bitcasts only at operators. Every one of these has bitten a real FFI.

**The first draft's version of this program did not compile, in three independent ways, and all three are fixed below rather than papered over:**

- **A format hole may hold a bare name and nothing else.** `(println "{x} -> ax {(hypot x 0.0)}")` is **AX3031** — `explain.ax:110` states it directly: "A hole holds a bare name and nothing else. There are no positional holes (`{}`, `{0}`) and no argument list." Every interpolated value is therefore `let`-bound first.
- **The lexer has no exponent form.** `stepNumberFrom` (`lexer.ax:478-492`) takes digits, optionally `.` followed by digits, and stops; there is no `e`/`E` arm. So `1.0e308` lexes as the float `1.0` followed by the identifier `e308`, and because `-` is an identifier character (`isIdentChar`, `lexer.ax:40-43`, admits ch 45) `5.0e-324` lexes as `5.0` followed by the *single* identifier `e-324`. Every extreme value is built from its bit pattern instead.
- **`fltBits` and `fltFromBits` do not exist.** `grep -rn 'fltBits\|fltFromBits' stdlib/ self_host/` returns nothing, and `stdlib/` has no Float module at all. The first draft used both as if they shipped. They are pure bitcasts, the emitter already bitcasts at operators, and **they land as new stdlib primitives in §10 step 0** — the float differential is literally unwritable without them, and no `.ax` source syntax reaches +inf or a subnormal by any other route.

```axiom
(import IO)
(import Demo)

; Float crosses as BITS in an i64 and is bitcast only at operators.
; A shim declared `extern "C" fn(f64) -> f64` reads d0/v0 on AArch64
; AAPCS64 and xmm0 on SysV while Axiom wrote x0/rdi: it links, runs,
; and returns garbage - only for floats. See the generated arity
; sweep (§5), which is where that failure is hunted systematically.
;
; Compared on BITS, never with `==`: `-0.0 == 0.0` is true and
; `NaN == NaN` is false, so a value comparison passes for the wrong
; reason on one and fails for the wrong reason on the other.
;
; No exponent literals appear below: the lexer has no `e`/`E` form
; (lexer.ax:478-492), and `-` is an identifier character
; (lexer.ax:40-43), so `5.0e-324` would lex as `5.0` then the single
; identifier `e-324`. Every value is built from its bit pattern.
;
; Every interpolated value is let-bound: an expression inside a
; format hole is AX3031 (explain.ax:110).

; Round-trip half: Rust must return the bits it was handed.
(:: probeBits (-> Float Int))
;@axiom:effect(io)
(fn (probeBits x)
  (let ((sent (fltBits x))
        (back (fltBits (Demo::identityF x))))
    {
      (println "sent {sent} back {back}")
      (if (== sent back) 0 1)
    }))

; Arithmetic half: Axiom's own `*` against Rust's. NaN is excluded
; from this half on purpose - see gap 3 in §7. Squaring a NaN may
; canonicalise its payload on either side and that is a corner this
; design explicitly does not claim.
(:: probeSquare (-> Float Int))
;@axiom:effect(io)
(fn (probeSquare x)
  (let ((ax (fltBits (* x x)))
        (rs (fltBits (Demo::square x))))
    {
      (println "ax {ax} rs {rs}")
      (if (== ax rs) 0 1)
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  ; i64::MIN has no literal spelling that `intLitFits` accepts, so
  ; -0.0's sign bit is built by arithmetic rather than written.
  (let ((zero      (fltFromBits 0))
        (negZero   (fltFromBits (- (- 0 9223372036854775807) 1)))
        (maxFinite (fltFromBits 9218868437227405311))   ; 0x7FEFFFFFFFFFFFFF
        (subnormal (fltFromBits 1))                     ; smallest subnormal
        (posInf    (fltFromBits 9218868437227405312))   ; 0x7FF0000000000000
        (quietNaN  (fltFromBits 9221120237041090560)))  ; 0x7FF8000000000000
    (+ (probeBits zero)
    (+ (probeBits negZero)
    (+ (probeBits maxFinite)
    (+ (probeBits subnormal)
    (+ (probeBits posInf)
    (+ (probeBits quietNaN)                    ; round-trip only
    (+ (probeSquare zero)
    (+ (probeSquare negZero)
    (+ (probeSquare maxFinite)
    (+ (probeSquare subnormal)
       (probeSquare posInf))))))))))))
```

#### 3.2 `220-differential-string.ax`

`Str` maintains a NUL terminator (MM-VAL-7 / MM-FFI-4) and a string literal's value is the address of a `{len, ptr}` pair with `count`/`shape` physically at handle−16/−8 and `count == -1` as the static sentinel (`codegen.ax:991-1040`). A Rust `&str` view must be built from `len` and `ptr`, never from the NUL — and must be shown to be, by round-tripping a string with an **interior NUL**, which `tests/stdlib/035-string-equality.ax` already establishes Axiom handles. If Rust reads to the NUL, that case truncates and the differential goes red. Also: empty string, 1 byte, invalid UTF-8 (must be refused as an error, never UB), a 2 MiB string, and a *slice of a literal* (whose `count` is the −1 sentinel that `axiom_retain`/`axiom_release` read and stop on).

#### 3.3 `200-differential-int.ax`

Wraparound. Axiom's `*` wraps; Rust's `*` panics in debug. Every arithmetic shim must use `wrapping_*`, and this case is what proves it: `i64::MIN`, `i64::MAX`, `i64::MIN / -1`, and a multiply that overflows. A shim built without `wrapping_mul` aborts the process here, which is a loud and correct failure.

---

### 4. Memory tests

The in-language high-water probe already exists as an idiom: `tests/stdlib/364-arc-frame-release.ax` measures the bump pointer by differencing successive `(memAlloc 200)` addresses across a loop.

**Correction to the first draft, and it inverts the design.** The first draft said every memory test follows 364's shape "so the numbers land in `.out` and a regression is a diff rather than a judgement call", and then tabulated exact deltas ("0 bytes", "≤ one block"). **364 does the opposite.** Its `.out` is **empty** and its `.exit` is **127**: it folds boolean predicates into a bitmask returned from `main` (`:262-266`), and every predicate is a *threshold* — `(fn (grew before after) (> (- after before) 100000))` at `:204`, `(< (- b2 b1) 4096)` at `:218`. Pinning an exact bump delta in a golden is precisely what 364 avoids, because that number churns on any allocator or codegen change and turns a legitimate improvement into a red gate.

**Decision: threshold predicates, computed in-language, exactly as 364 does — and one deliberate departure from 364, stated as a departure.** Where 364 returns a bitmask and prints nothing, these cases **print one pass/fail token per block** and return 0. §2.2 already decided printing over exit codes for this tree, on the grounds that a printed name is a far better failure message than a bit position in an exit status, and the FFI cases have `IO` where stage1 does not. So the `.out` is non-empty and diffable, but it holds **tokens, not measurements**:

```
a ok
b ok
c ok
d leaked-outside-arena   (expected: see block d)
```

The raw deltas are printed to stderr, which the runner does not diff, so a human debugging a failure can see the number without the number being the contract. Where a band rather than a boolean is wanted, the band is what is pinned — `(< delta 4096)`, `(> delta 100000)` — never the value.

**`400-arc-retain` — does a crossing leak?** Four blocks, each 20,000 crossings:

| block | crossing | predicate | why |
|---|---|---|---|
| a | `(Demo::countVowels s)` — `String` in, `Int` out | `(< delta 4096)` | the `&str` is a borrow over the words Axiom already holds; MM-FFI-4's no-copy route. Any allocation here means the shim copied |
| b | `(Demo::shout s)` — owned bytes out, under a mark/reset bracket | `(< delta 4096)` | the out-cell is one Axiom allocation per call and the reset reclaims it |
| c | `(Demo::counterNew 0)` then `(Demo::counterClose h)` | `(< delta 4096)` | a `Foreign` handle is Rust memory; MM-FFI-3 says it is outside the arena, not counted |
| d | **the unsound control**: block c without the `counterClose` | arena `(< delta 4096)` **and** RSS `(> growth 4 MiB)` | proves (c)'s flat delta is a measurement and not blindness |

Block (d) is the `measure-memory-baseline.sh --gate` discipline (`scripts/check-memory-baseline.sh:6-9`: "The negative runs every time"). Without it, "the arena did not move" is satisfied by a probe that leaks entirely into Rust's allocator, which is exactly the leak the design most needs to see. **Its RSS half is measured with `/usr/bin/time -l` on Darwin and `-v` on GNU (`measure-memory-baseline.sh:101-110`, which already carries the bytes-versus-kilobytes split), not with the bump pointer**, because MM-FFI-3 is precisely the statement that the arena cannot see it. Say so in the case's header comment: the arena probe is *structurally blind* to a Rust leak, and RSS is the only instrument that is not.

**`400-arc-retain` block e — C7.** Rust calls `axiom_retain` on a value it keeps past the call, then `axiom_release`. The discriminating half: a sibling case that **omits the retain**, drops the Axiom-side reference, and reads through the Rust-held pointer. Under a bump allocator with size-class freelists that read may succeed by luck, so the assertion cannot be "it crashes" — it must be "the block was handed out again", checked by allocating and comparing addresses. State plainly that this case is *probabilistic in the failing direction* and is therefore an `.out` recording what was measured, not a gate that must go red.

**`410-foreign-not-walked.ax` — C4, MM-FFI-5(1)/(2) and MM-FFI-10, the single most important memory case.** Build a record with three payload words: an Axiom `Str`, an `Int`, and a `Foreign`. Release it. Required outcome:

- the `Str` **is** released (its bytes are reclaimed — observable as in `tests/stdlib/359-arc-str-bytes.ax`),
- the Rust destructor **did not** run (a counter the crate exposes via `#[axiom_export] pub fn counter_close_count() -> i64` reads 0),
- and `(Demo::counterValue h)` still answers, i.e. the handle is live.

**This case needs a third assertion, and the reason is a soundness bug in the first draft's design that the case as originally written would have passed for the wrong reason.** See §4.1.

**`420-null-foreign.ax` — the null handle.** Round-trip a null `Foreign` through a record and a release (§7 gap 6 and the I3 amendment in §9). Rust returns null routinely — a failed constructor, an OOM allocation, a not-found lookup — and 0 is inside the range I3 reserves for immediate tags (`docs/memory-model.md:2387`). `axiom_retain` and `axiom_release` both open with `icmp slt i64 %h, 4096` and no-op below it (`codegen.ax:2274-2280`, `:2292-2296`), so a null `Foreign` is inert in the ARC path — but that is a property to *test*, not to assume, and it is the only reason the amendment's wording can be honest.

**`720-foreign-arena-primitive`** — `(__axiom_arena_reset_keeping mark foreignPtr 64)` must be **refused at check time** (AX3043). MM-FFI-2 already documents that passing non-arena memory as the kept block is undefined; MM-FFI-5(2) upgrades it from documented-undefined to refused, and this fixture is the upgrade.

#### 4.1 Why `410` needs a third assertion: the bitmap's authority is `scalarTyName`, not `tyIsReprScalar`

The first draft made `Foreign` safe from ARC by adding it to `tyIsReprScalar` (`typecheck.ax:7094-7096`). **That function has nothing to do with the reference bitmap**, and the mechanism it named would have failed silently in a way `410` as drafted could not detect.

The bitmap is computed in codegen. `fldClass` (`codegen.ax:6158-6178`) classifies each declared field type: 0 = machine scalar (never mapped), 2 = reference (mapped), 1 = **unclassifiable**. A `TAG_T_CON` whose name is not in `scalarTyName` (`codegen.ax:6134-6148` — `Int`, `Bool`, `Char`, `Float`, `I8`–`U64`, `F32`, `F64`, with no extension point), is not `"String"`, is not a known data type and is not a struct falls through the final `else` to **class 1**. Class 1 forces `shapeBits` (`:6197-6206`) to answer −1, and `ctorShapeConst` (`:6208-6221`) then stores `bits 0` — an **empty map for the whole block**. The MM-LIFE-2d comment at `codegen.ax:6118-6132` states the policy in as many words: "Anything UNCLASSIFIABLE — a type variable, a `Ptr`, an alias, a qualified spelling — forces the whole block to the LEAF (empty map): under-reclaiming leaks, a wrong bit use-after-frees, and only one of those is survivable."

So a record `{Str, Int, Foreign}` with `Foreign` unknown to `scalarTyName` becomes a **leaf**. The `Foreign` is not walked — accidentally right — and **the `Str` is never released** — wrong. `410`'s first required outcome fails, and MM-FFI-10 as originally drafted is unpinnable.

**Decision: `Foreign` is added to `scalarTyName` (`codegen.ax:6134-6148`), so `fldClass` answers 0 — machine scalar, never mapped — and the block keeps a real map with a 0 in the `Foreign` slot.** This is a codegen change, it lands in §10 step 3 beside the `emitDecl` arm, and every document that describes the mechanism must name `scalarTyName`/`fldClass` in `codegen.ax` as the bitmap's authority. `tyIsReprScalar` is a *type-checker* predicate with a different job; conflating them is how the first draft produced a design that would have leaked every `Str` in every record that held a handle.

**And `410` gains a third assertion, because a leaf block passes the `Foreign` half of the case for the wrong reason.** Two forms, both cheap, and the case carries both:

1. **A twin record.** Build `{Str, Int, Int}` and `{Str, Int, Foreign}` from the same `Str`, release both, and require the `Str` bytes to be reclaimed **identically** — same bump-delta band. If `Foreign` fell to class 1, the second record is a leaf, its `Str` survives, and the two deltas diverge. This is the assertion that catches the exact bug above.
2. **The shape word, read directly.** `(memGetWord (- h 8) 0)` at handle−8 is the shape; assert that bit 16+*i* is 1 for the `Str` slot and 0 for the `Foreign` slot. This is a direct read of the thing MM-FFI-10 claims and costs one line.

Getting this wrong has exactly one failure mode and it is silent: a `Foreign` is a machine address ≥ 4096 (when non-null), indistinguishable at run time from a heap handle (I3), so if the bitmap said "reference", `axiom_release` would walk into Rust memory and free it. There is no loud symptom; it is a corruption weeks later.

---

### 5. ABI-drift tests

The ABI is a set of textual facts about emitted IR (C2) plus a set of register-allocation facts about the C calling convention (C1). Both drift silently.

**The arity sweep — the register-bank boundary. Generated, never checked in** (see §2.1). `#[axiom_export]`'s shim must be `extern "C" fn(i64, …) -> i64` and do `f64::from_bits` **inside**. A shim written the natural way —

```rust
#[no_mangle]
pub extern "C" fn axffi_hypot(x: f64, y: f64) -> f64 { … }   // WRONG
```

— reads `d0`/`d1` on AArch64 AAPCS64 and `xmm0`/`xmm1` on SysV, while Axiom wrote `x0`/`x1` and `rdi`/`rsi`. It links. It runs. It returns garbage, and only for floats.

The sweep is generated into the gate's work directory, one program per shape, arities 0..10 of each wire type, every function an identity that returns argument *i*:

- **arity 9 is mandatory on AArch64** (x0–x7 are the eight integer argument registers; the ninth spills to the stack),
- **arity 7 is mandatory on x86-64 SysV** (rdi, rsi, rdx, rcx, r8, r9 — six; the seventh spills),
- **eight consecutive `Float` parameters** is the case that fails loudly if any shim ever takes `f64` directly, because it fills both banks and the values interleave visibly.

Sweeping 0..10 covers both spill boundaries with one loop and no per-target logic.

**Shape assertions on the emitted `declare`**, read off the generated sweep's pre-`opt` IR. For each supported shape, the emitted line must be exactly:

```llvm
declare i64 @axffi_add(i64, i64) #0
```

Pinned as a string. No `...` (there is no varargs anywhere and no source syntax for it), no `zeroext`/`signext`/`noalias`/`nounwind`, no `dso_local`, no calling-convention marker, and **the same `#0` group as every `define`**. The `#0` is load-bearing: it is the module's one attribute group (`codegen.ax:2805`) and it carries `"no-builtins"`, the string form — the enum `nobuiltin` was measured not to work. A `declare` emitted without it is a hole through which `opt -O1` can still recognise a loop idiom, which is Check F's whole subject.

**The evidence word must never cross.** Two halves:
1. C3's refusal, pinned by `tests/diagnostics/700-extern-type-variable.axbad` (AX3040).
2. The positive control nobody would think to write: a **polymorphic Axiom function that calls an extern**. It grows the hidden trailing `i64 %__evw.h` (`codegen.ax:3008-3021`, passed at `:5925`), and the assertion is that the *extern call site's* operand count equals the extern's declared arity, not arity+1. Checked by counting operands on the `call` line in emitted IR. Without this, a change to `emitPlainCall` (`codegen.ax:5908-5941`) that appends the evidence word unconditionally would pass every runtime test whose extern happens to ignore its last argument.

**ABI version.** `rust/axiom-abi` exposes `axffi_abi_version()`; the compiler exposes `axiom --abi-version`. **Decision: compared at gate time, end to end, through the linked artifact** — `tests/ffi/demo/310-abi-version.ax` prints what the linked archive answers, and the gate diffs it against `axiom --abi-version`. Not a startup check (it costs a call in every program for a build-configuration error) and not a source grep (which compares two constants without proving either reached the binary).

**Four targets.** `check-cross-targets.sh:269` already loops the four triples (the array itself is at `:44`). It gains one probe: an `extern` declaration must **assemble** on all four at `-O0` and `-O2`. It does not gain a link, because three of the four are cross-targets with no archive to link against. The Darwin `_`-prefix asymmetry is handled in **both** readers of §1.4 — `symbols_of` and `defined_symbols_of` — because it is observable on both sides.

---

### 6. Fuzz and property strategy for the marshalling layer

**Decision: no `cargo fuzz`.** It needs a nightly toolchain and libFuzzer, and the owner made cargo a gate-only dependency; adding a *nightly* cargo dependency to a repository whose bootstrap is deliberately toolchain-light is a worse trade than the coverage is worth. The input space that matters here is small and structured — word values, lengths, UTF-8 validity, arity, wire type — and boundary enumeration beats coverage-guided search on a space like that.

**What is built instead, in two layers:**

**Layer 1 — `rust/axiom-abi/tests/roundtrip.rs`, run by `cargo test`.** Property tests over `AxStr`/`AxBytes` construction, against **hand-built Axiom-shaped memory** — a test-only allocator that lays out `count` at −16, `shape` at −8, and a `{len, ptr}` pair at the handle, matching `codegen.ax:991-1040`. Properties: round-trip identity for arbitrary byte strings; empty; interior NUL; length 1; invalid UTF-8 returns `Err`, never panics and never UB; the `count == -1` static sentinel is read and not decremented; a 2 MiB payload. The PRNG is a seeded xorshift with the seed printed on failure and a `regressions/` file of pinned seeds — deterministic, because I12 says compilation is deterministic and a non-reproducible test failure in this repository is a test nobody will act on.

**Layer 2 — the generated arity/type sweep, in `check-ffi.sh`.** This is the differential fuzz that finds real bugs, and it is the same generated corpus §5 reads its shape assertions from: for each shape in `{Int, Float, Bool, String, Foreign} × arity 0..10`, generate the Rust function, run `axiom-bindgen` over it, compile the Axiom caller, link, run, and require every argument to arrive with the sentinel value it was sent (position *i* gets `0x1000 + i`, distinct per position so a transposition is visible and a truncation is not mistaken for a zero). Argument-order and out-cell-offset bugs are where a marshalling layer actually breaks, and neither is reachable from Layer 1.

The `Foreign` row of that sweep uses `0x1000 + i` like every other, which keeps every generated handle above 4096; the null case is `420-null-foreign.ax`'s job and is not folded in here, because a sweep that sometimes sends 0 and sometimes does not is a sweep whose failures are hard to localise.

**Bindgen/proc-macro drift is not fuzzed, it is diffed.** `axiom-bindgen` reads Rust source and the proc macro reads the same annotations independently (`rust/axiom-bindgen/src/main.rs:9-12`), so they can disagree. The gate regenerates `tests/ffi/bindings/Demo.ax` and fails on any difference from what is checked in — the `check-fmt.sh --check` shape. Its negative probe: mutate one byte of the checked-in file and require the diff to fail.

---

### 7. Known gaps, stated plainly

1. **Signature arity cannot be verified against an arbitrary archive.** `nm` reports names, not arities. Check B proves the symbol *exists*; nothing proves it takes the number of `i64`s the `extern` declares. Declaring `(extern (f (a : Int)) Int #:symbol "axffi_add")` against a two-argument shim links, runs, and reads a garbage second argument. The mitigation is the generated-binding path (`axiom-bindgen` writes the declaration from the same source the shim is generated from, and the gate diffs it), which covers every crate that uses `#[axiom_export]` — and covers **nothing** for a hand-written `extern` against a hand-written archive. That is a real hole in the FFI's safety story and it should be written into `docs/ffi.md` in those words, not softened.

2. **Boundary type safety is not enforceable by the Axiom checker, by construction — and the FFI's type-checker footprint is smaller than the first draft claimed.** `tyCompat` (`typecheck.ax:188-235`) is the entire unifier; a type variable on either side matches anything and `tyInst` only freshens. `tyReprClash`/`tyIsReprScalar` (`typecheck.ax:7051-7096`) names only `Bool`, `Float` and `String` as non-handles.

   **The first draft said adding `Foreign` to that list "is what makes AX3042 and AX3043 possible at all". It is not.** `tyReprClash` has exactly one call site — inside `checkDeclaredReturn` (`typecheck.ax:6987-7022`), whose entire body compares a function's **declared return type** against its **inferred body type**. Its own header comment says it is "deliberately NOT `tyCompat`" and exists for that one case. It never runs at an argument position, so it cannot see `(__axiom_arena_reset_keeping mark foreignPtr 64)` (AX3043) and has no bearing on an extern signature's wire types (AX3042). The actual machinery is specified in §8: **AX3042 is a syntactic check over the extern declaration's own signature, run at registration**, and **AX3043 is a new argument-position check against the arena primitives' parameter list** — neither routes through `tyReprClash`.

   **Naming `Foreign` in `tyIsReprScalar` also has an unmentioned cost, and it is a real one.** With `Foreign` in that list, any function declared `(-> … Int)` whose body answers a `Foreign` becomes a hard `checkDeclaredReturn` error — so a `Foreign` cannot travel through the tree's deliberate untyped-`Int`-handle convention, the convention `Span` and `JobPool` rely on and that `tyReprClash`'s own comment defends at length (21 of 271 files return a handle through `Int` on purpose). **Decision: that is intended, and it is the point.** A `Foreign` laundered through `Int` is a Rust pointer that no longer carries its type, and MM-FFI-5(1)'s "distinct type from Int" is exactly the claim that this must stop being possible. But it is a behavioural change to a shared predicate, it will reject code someone writes by habit, and it must be stated in `docs/ffi.md` §8.2 rather than discovered.

   Everything else in the tree is still an untyped `Int` handle by decision, so a `JobPool` passed where a `Foreign` is declared is accepted. Boundary type safety comes from the binding generator, checked at binding-generation time, and the Axiom side is a backstop over four type names.

3. **NaN payload preservation across the boundary is not guaranteed by anything.** Axiom moves the bits through an i64 and Rust does `f64::from_bits`/`to_bits`, so in principle payloads survive — but an intermediate `f64` register move can canonicalise a signalling NaN on some targets. So `210-differential-float.ax` round-trips a quiet NaN and **excludes NaN from its arithmetic half entirely** (§3.1), and the case carries a comment saying sNaN is **untested and unclaimed**. Better an unclaimed corner than a claim measured on one target.

4. **A Rust leak is invisible to every arena instrument.** MM-FFI-3 says so; §4 block (d) works around it with RSS. RSS is coarse (page granularity, allocator caching), so a small leak per crossing is undetectable below a few thousand iterations. There is no in-language instrument for Rust's allocator and this design does not invent one.

5. **The "byte-identical to today" claim expires.** The strongest durable form is structural (§1.4 Check A): zero `declare`s, unchanged preamble, one attribute group, empty `nm -u`, no `-l`/`-L`. Full IR byte-identity can only be checked against a frozen reference, and the two candidates both fail: a committed 140-file baseline churns on every legitimate codegen change, and a comparison against the seed compiler expires at the next `scripts/reseed.sh`. **So full byte-identity is a landing measurement, not a standing gate** — the FFI commit must record, in the `check-symbol-names.sh:80-90` idiom ("the change is a no-op on this tree, to the byte … 2,342,271 bytes of it"), the SHA-256 of `emit-llvm` output for all 140 `tests/stdlib` cases plus the compiler's own IR, before and after, and state that they are identical.

   **One nuance the `scalarTyName` change forces (§4.1):** adding a name to `scalarTyName` is reachable by every record construction site in the tree, so this measurement is not a formality. If any existing type is spelled `Foreign` anywhere, its blocks' shape constants move. Grep before, and record the grep in the commit message alongside the hashes.

6. **A null `Foreign` shares the immediate-tag range, and the wire contract has to say something about it.** Rust returns null routinely. 0 is below 4096, so a null `Foreign` is indistinguishable from an immediate tag by I3's own test. **Decision: both halves.** (a) `#[axiom_export]`'s generated shim diagnoses a null return at the boundary and aborts, so a *checked* extern never hands Axiom a null — but that covers only the generated path, not a hand-written `extern` (gap 1 again). (b) The normative sentence is written honestly rather than optimistically: see §9's I3 amendment. `420-null-foreign.ax` pins the inert case. What is **not** claimed: that a null `Foreign` can be pattern-matched or discriminated. It cannot, and nothing in the design needs it to be.

---

### 8. New diagnostic codes

`AX3036`–`AX3038` are already spoken for by `docs/error-model.md:474-480` (proposed, not constructed). **`AX3039` is left unallocated** so that block can grow by one; an unallocated number costs nothing and a collision costs a rename the scheme forbids. The FFI block starts at `AX3040`.

| Code | Slug | Sev | Condition and mechanism | Fixture |
|---|---|---|---|---|
| `AX3040` | `extern-type-variable` | E | a type variable anywhere in an `extern` signature. **Syntactic, over the declaration's own signature, at registration.** C3: a polymorphic function grows the hidden trailing `i64 %__evw.h` (`codegen.ax:3008-3021`) and that word must never reach Rust | `tests/diagnostics/700-extern-type-variable.axbad` |
| `AX3041` | `extern-unresolved-symbol` | E | the `#:symbol` name is defined by no archive on the link line. **`build`-mode only** — `check` has no link line and cannot fire it (§1.9). **This is the code that stops `docs/self-hosting.md` §9.1 from recurring** — the name that passed `check` and then died in `opt` with an error about generated code and no span | `tests/ffi/probe-ungrounded/020-missing-symbol.axbad` |
| `AX3042` | `extern-wire-type` | E | a parameter or return type with no wire representation — a user `data` type, a tuple, a function type, a `List`. **Syntactic, over the extern declaration's own signature, at registration — an allowlist of four constructor names plus `Foreign`, walked over the arrow spine.** It does not go through `tyReprClash`, which has one call site and it is `checkDeclaredReturn` (§7 gap 2) | `tests/diagnostics/710-extern-wire-type.axbad` |
| `AX3043` | `foreign-arena-primitive` | E | an arena primitive applied to a `Foreign` value. **A new argument-position check: the arena primitives' parameter lists are known, and an argument whose static type is `Foreign` at one of those positions is refused.** Nothing existing checks argument positions this way, so this is new machinery rather than a list entry. MM-FFI-5(2), upgrading MM-FFI-3's documented-undefined to refused | `tests/diagnostics/720-foreign-arena-primitive.axbad` |
| `AX3044` | `foreign-unclosed` | W | a `Foreign` with a registered destructor stored in a record or reaching a release path with no `close` on any route out. ARC has no finalizers (MM-LIFE-2f leaks cycles by stated cost); C8 says nothing is implicit, and this is the warning that says so at the site | `tests/diagnostics/730-foreign-unclosed.ax` |
| `AX3045` | `extern-duplicate-symbol` | E | two `extern` declarations naming one `#:symbol` with different signatures. Identical re-declaration is permitted and deduplicated — a generated bindings module imported twice is normal | `tests/diagnostics/740-extern-duplicate-symbol.axbad` |
| `AX3046` | `extern-under-freestanding` | E | an `extern` reached from the entry file under `axiom build --freestanding`. This is the user-facing half of "freestanding is opt-in relaxed": a program that wants the old contract can demand it, and CI can demand it of a subtree | `tests/diagnostics/750-extern-freestanding.axbad` |

**Codes deliberately NOT minted:**

- **The effect.** C5 seeds `builtinEff "IO"` into the extern's `FnEnt` word 5 at registration, exactly as `tcAddEffectOp` (`typecheck.ax:1866-1876`) does for an effect operation, and the existing monotone fixpoint (`inferEffects`, `typecheck.ax:5199-5241`) propagates it transitively for free. An unhandled FFI effect is therefore **AX3011**, at a `handle` site, with no new machinery — pinned by `tests/ffi/demo/070-extern-effect-transitive.ax` (§2.4). An AXTAG mismatch is **AX3010**, unchanged. Minting an FFI-specific effect code would split one condition across two numbers for no gain.
- **A link-failure code.** `AX4003` (`toolchain-failure`) already covers a failed `cc` (`driver.ax:230-233`). The FFI's contribution is that AX3041 fires *before* `cc` runs; a code for a case the design says is unreachable is exactly how `AX4001` sat in the registry with no construction site for months — **and `check-doc-drift.sh` now fails on that in both directions.** Every code above must land with its construction site *and* its `explain` entry in the same commit, or CI is red. Note also that seven new constructed codes takes `check-doc-drift.sh:94`'s count from 47 to 54 against a floor of 45; §0 and §10 step 7 both name the re-derivation.
- **A syntax code.** `extern`'s malformed forms ride `AX2001`/`AX2003`. AX2004 stays reserved to the retired `foreign`/`union`/`region` forever.

**AXSYM kind.** `X` (foreign binding) was removed with `foreign` (`docs/self-hosting.md:4234`). **Decision: reuse `X`.** The never-reuse rule protects identifiers a stale reader can *misinterpret* — AST tag 29 (`parser.ax:100-104`) turns a stale reader into a silent misparse, and a recycled diagnostic code makes an old CI grep match a different condition. An AXSYM kind letter is neither: it is rendered fresh on every `axiom symbols` run, and `X` means what it always meant — a binding to an external symbol. If the meaning had changed, a new letter; it has not. Metadata keys: `#symbol=axffi_add`, `#lib=demo`, `#wire=Int,Int->Int`. `docs/diagnostics.md:326` gains `X` to the `KIND` list and the metadata table at `:333-341` gains those three keys.

---

### 9. Documentation: every file, and what it must say

**`docs/ffi.md` (new).** Outline:

```
1. What this is, and what it costs
   1.1 The three measured tiers (nm -u: 0 / 0 / 188-of-which-14-forbidden)
   1.2 What you give up: MM-FFI-1's blanket guarantee, and what you keep
2. The contract (C1-C8), stated normatively as MM-FFI-6..13
3. Calling Rust from Axiom
   3.1 `extern` declaration form and its attributes
   3.2 The wire types: Int, Float, Bool, String, Foreign - and what has none
   3.3 Generated bindings: axiom-bindgen, and why the .ax is checked in
   3.4 Effects: why an extern is IO by seeding, not by a new rule
   3.5 An extern may not name a libc symbol directly (Check F's corollary)
4. Calling Axiom from Rust
   4.1 @main -> axiom_rt_init, `ar rcs`, the link line
   4.2 The four externally-linked runtime symbols, and the rest that are internal
5. Memory across the boundary
   5.1 Rust must never construct an Axiom heap block (the MM-LIFE-2d bitmap)
   5.2 axiom_retain / axiom_release, and the -1 static sentinel
   5.3 Foreign handles: no finalizer, no arena primitive, no ARC walk -
       and WHERE that is decided (scalarTyName/fldClass in codegen.ax)
   5.4 Null Foreign, and why it is inert rather than discriminated
   5.5 What the arena instruments cannot see
6. Panics and unwinding (C6)
7. Building: the two modes, the manifest, --freestanding
8. What is NOT checked
   8.1 Arity against an arbitrary archive
   8.2 The type checker is not a boundary checker, and why (tyCompat) -
       including the cost: a Foreign may no longer travel through an
       Int-declared return (checkDeclaredReturn)
   8.3 sNaN payloads
9. The gates, and how to make each one go red
```

Section 8 is the one that must not be trimmed. Section 9 exists because this repository's readers are the people who maintain the gates.

**`docs/memory-model.md`.** Both MM-FFI-1 and MM-FFI-5 are rewritten, and §8 grows.

- **MM-FFI-1 (R)** currently reads "**Axiom has no FFI.** … `scripts/check-freestanding.sh` gates that it stays that way" (`:2323-2327`), followed by "This is not an omission awaiting a section" (`:2329`). Rewrite:

  > **MM-FFI-1 (R).** **Axiom is freestanding by default and by construction.** A program that declares no `extern` emits no LLVM `declare`, links no library, and imports no symbol — measured as an empty `nm -u`, gated by `scripts/check-freestanding.sh` over `tests/stdlib/` and by `scripts/check-ffi.sh` tier 1 over `tests/ffi/no-extern/`. `foreign` remains removed and remains `AX2004`; so do `union` and `region`.
  >
  > **A program that declares an `extern` leaves this guarantee deliberately and locally.** It does not leave §3, §5 or `MM-PAR-3`, all of which describe memory that came from `axiom_alloc` and are unaffected by memory that did not (`MM-FFI-3`). What it leaves is the *closure* property: the module is no longer closed, and `MM-FFI-6` states what replaces it.
  >
  > **What it does not leave is the libc ban on Axiom's own emitted code.** An `extern` permits a linked *archive* to call `malloc`; it does not permit Axiom's module to. `scripts/check-ffi.sh` Check F runs `check-freestanding.sh`'s own name list over every FFI case's IR, and an `extern` may not name a libc symbol directly.
  >
  > The paragraph this replaces read "This is not an omission awaiting a section." It was true when written and is now the section.

- **MM-FFI-5 (P)** (`:2369-2373`) is promoted from prospective to Requirement, its four minima discharged one by one with the gate that discharges each: (1) `Foreign` is a distinct built-in type — pinned by `tests/diagnostics/710`, and its **non-referenceness is decided in `codegen.ax`'s `scalarTyName`/`fldClass`, not in `typecheck.ax`** (see MM-FFI-10); (2) no arena primitive applies — `AX3043`, `tests/diagnostics/720`, an argument-position check; (3) an extern call is an inferred effect — seeded in `FnEnt` word 5 at registration, propagated by `inferEffects`, pinned by `tests/ffi/demo/070-extern-effect-transitive.ax` and `AX3011`; (4) `check-freestanding.sh` is **joined** by `scripts/check-ffi.sh` — and the honest wording is *joined*, not *replaced*, because the ban still holds for non-FFI programs and the specification should say what the tree does.

- **New: MM-FFI-6 through MM-FFI-13**, carrying C1–C8 as numbered rules so the rest of the document can cite them. In particular:
  - **MM-FFI-9** — Rust may not construct an Axiom heap block.
  - **MM-FFI-10** — *a `Foreign` word's reference-map bit is 0, and the authority for that is `scalarTyName`/`fldClass` in `self_host/codegen.ax:6134-6178`, not `tyIsReprScalar` in `typecheck.ax`.* State the failure mode explicitly, because it is not the obvious one: a `Foreign` unknown to `scalarTyName` falls to `fldClass` class 1, which forces the **whole block** to the leaf shape (`shapeBits` → −1, `ctorShapeConst` stores an empty map), so every *other* reference in that record — including a `Str` — stops being released. Under-reclaiming rather than over-reclaiming is the deliberate choice recorded at `codegen.ax:6118-6132`, and it means this bug leaks silently instead of crashing. Pinned by `410-foreign-not-walked.ax`'s twin-record and shape-word assertions.
  - **MM-FFI-11** — a non-null `Foreign` is an opaque machine address; a null `Foreign` is 0 (see the I3 amendment).

- **§8, invariant table (`:2387`).** `I2` and `I3` need a sentence, and the honest form is not the one the first draft wrote. It claimed "a `Foreign` word is an address ≥ 4096". That is false for the null case, which Rust produces routinely. The amendment, in the shape of the existing I3-narrowing paragraph at `:2403-2408`:

  > - **I3** and `Foreign`. A **non-null** `Foreign` word is a machine address ≥ 4096 and is therefore *indistinguishable at run time* from a heap handle: its non-referenceness is carried entirely by the shape word's bitmap (`MM-FFI-10`) and by the static type, never by its value. A **null** `Foreign` is 0 and therefore shares the immediate-tag range that I3 reserves. That is safe, and safe for a narrow reason worth writing down: a `Foreign` is never pattern-matched, so the `< 4096` discrimination is never applied to one, and its bitmap bit is always 0, so `axiom_retain`/`axiom_release` never reach it — and both would no-op on it anyway, since each opens with `icmp slt i64 %h, 4096` (`codegen.ax:2274-2280`, `:2292-2296`). Pinned by `tests/ffi/demo/420-null-foreign.ax`. This is the one place I3 is load-bearing for the FFI, and it is load-bearing by *not* being consulted.

- **`:2494` gate table.** New row: `| scripts/check-ffi.sh | FFI-1, FFI-3, FFI-5, FFI-6..13 |`. Existing row (`| scripts/check-freestanding.sh | ALLOC-1, ALLOC-8c, FFI-1 |`) keeps `FFI-1` unchanged.

- **MM-FFI-2's five-boundary table (`:2333-2342`)** gains a sixth row: *memory a linked Rust archive allocates* — owned by Rust, outside every arena, released only by an explicitly registered destructor, invisible to the high-water mark.

**`docs/self-hosting.md` §9 "Retiring the C FFI" (`:4231-4343`).** **Decision: §9 is not rewritten. It is a historical record and it is correct.** `foreign` did not work, and nothing said so; that stays true. Three edits only:

- **§9.4** (`:4307-4313`) currently says "With `foreign` gone the language cannot name an external symbol at all, so that probe cannot be written any more". Add a dated sentence: the probe still cannot be written *as `foreign`*, and now cannot be written as `extern` either, because an `extern` naming a symbol no archive defines is `AX3041` at build time — which is the property `foreign` never had and the reason its removal was not a capability loss.
- **§9.5 "What stays"** (`:4331-4342`) already says tag 29 is retired, not reused, and why. It gains: `extern` takes **tag 53**, the next free declaration tag (`parser.ax:100-104` documents 0–17, 20–28, 30, 31, 47–52 in use). Recycling 29 for `extern` would be the exact mistake that paragraph exists to forbid, and it would be *tempting*, because the two forms are cousins. Write the temptation down.
- **New §9.6 "The FFI that came back, and why it is a different thing."** Six bullets: it is `extern` not `foreign`; it emits a `declare` (the one thing `foreign` never did); its symbol is checked against the archive at build time; its effect is seeded rather than special-cased; it may not name a libc symbol directly; and it is opt-in with an enumerating gate. Ends by naming `docs/ffi.md`.

**`README.md`.** Status-table row for FFI, which must name a fixture (`check-doc-drift.sh:144-155` fails a `**Complete**` row that names none). The gate list at `:1467` gains `./scripts/check-ffi.sh # externs link only what a manifest permits`. The `.ax`-file count claim lives at **`README.md:1324`** and currently reads **404**; the gate that recomputes it is `check-doc-drift.sh:135` (the count) and `:141` (the regex `` gated against all (\d+) `\.ax` files ``). `tests/ffi/` adds roughly 22 files and CI recomputes the number on every run, so the claim must move in the same commit.

**`CONTRIBUTING.md`.** An "FFI check" subsection beside "Freestanding check" (`:238-243`), saying what it needs (cargo) and what happens without it (tiers 2–3 skip, with the count printed; tier 1 and Checks E and G still run). The PR gate list at `:466-473` gains `./scripts/check-ffi.sh` beside the existing `./scripts/check-freestanding.sh` at `:470`. And one new sentence in the toolchain section: **cargo is required for exactly one gate and for no build of the compiler** — `scripts/bootstrap-from-seed.sh` stays cargo-free, asserted by Check E, whose grep strips comments precisely so the script's own written promise at `:36` and `:43` can survive.

**`docs/reference.md`.** The `extern` declaration form, its attribute keywords (`#:symbol`, `#:lib`, `#:out-cell`, `#:effect`), the `Foreign` built-in type beside `Bool`/`Float`/`String`, the wire-type table, and the two new float primitives `fltBits :: (-> Float Int)` / `fltFromBits :: (-> Int Float)` (§10 step 0). Also the `--freestanding`, `--emit-link-manifest` and `--abi-version` flags.

**Correction on the help-text claim.** The first draft said `check-driver.sh:562-566` "enforces that every flag the compiler accepts appears in `axiom --help`". It does not — `check-driver.sh:568-573` is a **hand-maintained** list of 13 flag names and 11 command names, checked against `--help` output. Nothing derives it from what the compiler accepts. So the true statement, and the one to write: **`--freestanding`, `--emit-link-manifest` and `--abi-version` must be added by hand to the loop at `check-driver.sh:568-569`, or nothing enforces their help text at all.** That is a step in §10, not a property that comes for free.

**`docs/error-model.md`.** Two edits: `Result` across the boundary — a fallible shim returns a status word and fills an out-cell, and the Axiom glue reconstructs `(Result T String)`, so `AX3037` (`discarded-result`, proposed at `:479`) applies unchanged to an extern's result; and the panic contract (C6), which is an *abort*, not an error value, unless the shim catches it. `docs/error-model.md` is in `check-doc-drift.sh:168-181`'s document list, so every fixture it names must exist.

**`docs/diagnostics.md`.** The seven new codes in the `AX3xxx` narrative, the `X` AXSYM kind at `:326`, and its three metadata keys in the table at `:333-341`.

**`docs/v1-roadmap.md`.** The FFI row moves from absent to shipped with its gate named. **§4.5 "HTTP — out of scope, and the shape it should have outside" is at `:1106-1142`** (the first draft mis-cited it as ":1264 context"; `:1264` is the P4 row, which is where the "0 of 71 comparable `.ll` pairs are byte-identical" fact §1.7 cites actually lives). §4.5 needs a sentence: HTTP stays out of scope *for the standard library*, and is now reachable by binding a Rust crate — which is a different claim and should not be left to inference.

**`scripts/check-doc-drift.sh`.** Add `docs/ffi.md` to the document list at `:168-181`, and **re-derive the floors, which the first draft named at the wrong lines.** They are:

| Line | Floor | Today | After |
|---|---|---|---|
| `:94` | 45 constructed codes | 47 | **54** — this is the one this section's own change invalidates |
| `:148` | 15 `**Complete**` rows | — | +1 (the FFI row) |
| `:188-189` | 185 `tests/` paths across the docs | — | re-derive |
| `:241-242` | 64 `tests/` paths across the sources | — | re-derive |
| `:291-292` | 82 bare fixture names | — | re-derive |
| `:318` | 4 rendered blocks | — | unchanged |

This is the "floors expire" lesson applied at the moment it is cheapest to apply, and `:94` is the case where skipping it leaves nine cases of slack in the gate that exists to catch a code without a construction site.

**`tree-sitter-axiom/grammar.js` and its corpus.** A real `extern_declaration` rule with `name`, `params`, `return_type`, and the attribute keywords, added to the **`_declaration` choice at `grammar.js:198-210`**. (The first draft said "the `_declaration` choice at `:776`". Line 776 is `$.removed_form` inside the **`_expression`** choice — `lambda` begins at `:783` — so following that instruction literally would have made `(extern …)` an expression and walked straight into the `_declaration`/`_expression` ambiguity the file's own comment at `:193` warns about.) `removed_form`'s `_removed_foreign` branch (`:568-580`, with `_removed_foreign: _ => 'foreign'` at `:583`) **stays exactly as it is** — `foreign` is still a removed construct and an editor must still mark it as one bounded error region rather than reinterpreting it. Corpus: `test/corpus/declarations.txt` gains three cases (minimal extern, extern with all attributes, `pub extern`); `test/corpus/removed.txt` keeps its `foreign` case unchanged and gains a fourth asserting that `foreign` next to `extern` in one file still parses as one `removed_form` plus one `extern_declaration` — which is the case an editor actually meets during a migration.

**`.claude/skills/axiom-helper/SKILL.md`.** §4.2 (`:127-141`) currently reads "**There is no FFI.** … Do not write `foreign` bindings and do not suggest them." Replace with:

> **There is an FFI, and it is spelled `extern`.** `foreign` was removed and is still `AX2004`; never suggest it. An `extern` names a symbol in a linked Rust staticlib, emits an LLVM `declare`, and is refused at **build** time (`AX3041`) if no archive defines it — `axiom check` has no link line and cannot see it. Prefer generated bindings — write `#[axiom_export]` on the Rust side and run `axiom-bindgen`; a hand-written `extern` is not arity-checked against the archive and a mismatch reads garbage arguments at run time.
>
> **Reach for the FFI last.** Generated code still calls no libc function by default, and a program with no `extern` still has an empty `nm -u`. Using the FFI moves the program from `scripts/check-freestanding.sh`'s blanket ban to `scripts/check-ffi.sh`'s manifest, which is a reviewed file someone has to widen. A `no_std` + `panic = "abort"` crate keeps the empty `nm -u`; a `std` crate imports 188 symbols, 14 of them on the forbidden list. Say which you chose.
>
> **An `extern` may not name a libc function.** Bind an `axffi_*` shim and let Rust call libc inside the archive. Axiom's own emitted module is still swept for libc calls, in FFI programs too.
>
> An `extern` is `IO` by construction, so a caller needs the effect handled or `;@axiom:effect(io)` claimed — `AX3011` and `AX3010` as usual.

§4.3 (`:146`) is edited in place: `union` and `region` remain removed; `foreign` remains removed; there *is* now a way to reach a C allocator, through a linked archive, and it is gated by a manifest rather than by impossibility. Leaving that sentence as "there is no way to reach C, because there is no way to reach C" is the single most misleading line the agent-facing document could carry after this lands.

---

### 10. Landing order

The couplings in §0 make this a sequence, not a set:

0. **`fltBits` / `fltFromBits` as stdlib primitives**, with their own `tests/stdlib` case. They are pure bitcasts and the emitter already bitcasts at operators, but nothing in the tree exposes them, and §3.1's float differential is unwritable without them — the lexer has no exponent form (`lexer.ax:478-492`), so `+inf`, the smallest subnormal and a quiet NaN have no source spelling at all by any other route. This lands first because it is independent of everything else and because a differential written against functions that do not exist is the first draft's mistake.
1. `parser.ax` tag 53 + `format.ax` printer + `tree-sitter` rule at `grammar.js:198-210` + corpus. **No fixture yet** — the sweeps in §0 would judge it.
2. `typecheck.ax`: `Foreign` as a built-in type name, the `FnEnt` effect seed at registration, `AX3040` (syntactic over the extern signature), `AX3042` (syntactic, wire-type allowlist over the arrow spine), `AX3043` (**new argument-position check** against the arena primitives' parameter lists), `AX3045`. `Foreign` also joins `tyIsReprScalar` (`typecheck.ax:7094-7096`), which is a separate and smaller change than the first draft thought: it makes a `Foreign` returned through an `Int`-declared signature a `checkDeclaredReturn` error, and that is intended (§7 gap 2) — but it is a behavioural change to shared code and needs its own `tests/stdlib` regression pass. Fixtures + goldens + `explain` entries in the same commit (`check-doc-drift.sh`'s registry is bidirectional).
3. `codegen.ax`: the `emitDecl` arm (`:2817-2846`), the `declare` block, `#0` on it — **and `Foreign` added to `scalarTyName` (`:6134-6148`)**, which is what actually keeps the reference bitmap correct (§4.1, MM-FFI-10). These land together because the `declare` without the bitmap fix is a compiler that leaks every `Str` in a record that holds a handle, silently, and the bitmap fix without the `declare` is unreachable code. Record the §7 gap-5 grep for any existing `Foreign` spelling in this commit.
4. `driver.ax`: `-l`/`-L` on the `cc` argv, `--emit-link-manifest`, `--freestanding` + `AX3046`, `--abi-version`, **and the three new flag names added by hand to `check-driver.sh:568-569`** — nothing derives that list, so a flag left out of it is a flag with no help-text gate at all.
5. `rust/` workspace + `tests/ffi/` + `scripts/check-ffi.sh` (Checks A–G, twelve probes) + the CI job at `.github/workflows/ci.yml` between `:106` and `:119` + the three `check-diagnostics.sh` edits of §1.9 (the glob at `:330-331`, the `sweep_floor` line at `:455-458`, the total at `:461-463`).
6. `AX3041` last, because it needs the manifest from step 4 to know what the archives define, and because it is `build`-only by construction.
7. Docs, with the recomputed counts and re-derived floors — `check-doc-drift.sh:94` (47 → 54), `:148`, `:188-189`, `:241-242`, `:291-292`, and `README.md:1324`'s `.ax` count — **in the commit that makes them false, not after.**

Steps 1–4 each land with the measurement that the tree is unchanged: zero `declare`s in `bootstrap/axiom-darwin-aarch64.ll`, `check-freestanding.sh` green, `check-reproducible.sh` green, and the before/after IR hashes from §7 gap 5 in the commit message. Step 3 is the one where "unchanged" is a real claim rather than a formality, because `scalarTyName` is read by every record construction site in the tree.
---

## 11. Compiler Implementation Plan

Seven files change. Every line number below is against `handle-convention`
at `9d5b508` and was read, not guessed.

### 1. `self_host/parser.ax` — the declaration form

**Tag.** `(pub :: TAG_D_EXTERN Int) (pub fn (TAG_D_EXTERN) 53)`. Not 29:
tag 29 was `TAG_D_FOREIGN` and is permanently retired (parser.ax:100-104)
because tag numbers are the AST's wire format between the parser and its
four readers, and a recycled one turns a stale reader into a silent
misparse rather than a crash. 53 is the next free number after
`TAG_D_SYNFOR` (52).

**Node layout.** `a` = the Axiom name; `b` = a `Vec` of `TAG_FIELD` nodes
(one per parameter: name + declared type); `c` = the return type node;
`span` = the name token. The attribute keywords (`#:symbol`, `#:lib`,
`#:out-cell`, `#:effect`) go in a fourth slot — reuse `ty` (ASTNode word
6), which is unused for declarations.

**Hook.** `parseTopForm` (parser.ax:~1090) is an `if` chain on the keyword
lexeme. Add `(if (kwEq name "extern") (parseExternDecl tokens (advance pos) pos) ...)`
beside the `impl` and `syntax/for` arms, i.e. **ahead of** the
`TAG_D_MACROCALL` fallthrough, for the same reason those are: an
identifier head that reaches the fallthrough becomes a declaration-macro
invocation and the error stops naming the construct.

**`foreign` stays AX2004.** The removed-construct arm at parser.ax:1103
is untouched. Old source keeps getting migration advice; the new keyword
is `extern`, so nothing is silently reinterpreted. This is also what
`check-ffi.sh`'s fourth negative probe asserts.

### 2. `self_host/typecheck.ax` — collection, arity, effects

**`tcCollect`** (1669-1782) dispatches on tag and falls through to `0`
for anything unknown, so an unhandled `TAG_D_EXTERN` is silently ignored
— which reads as "undefined variable" at every call site. Add an arm that
pushes through **`tcPushFn`** (1980-1982), never a raw `vecPush`: it is
the single point that keeps the exact-name hash index in step.

The `FnEnt` is 8 words read positionally (1309-1316):

```
name        the Axiom name
ty          the declared arrow type, built from the parsed signature
paramCount  the ACTUAL parameter count  <- not -1
isBuiltin   0
isEffectOp  0
effects     vecPush vecNew (builtinEff "IO")   <- pre-seeded
eparams     vecNew
declared    1
```

Two fields deserve comment.

`paramCount` is set to the real count. The removed `foreign` used `-1`,
and `repArity` (2728-2733) answers `-1` for a non-builtin with
`paramCount < 0`, which **silently disables** both the AX3013 bare-value
refusal (3833) and the AX3009/AX3013 saturation check (4543). Setting it
means an extern gets arity checking the old `foreign` never had.

`effects` is pre-seeded with `IO`, exactly as `tcAddEffectOp` (1866-1876)
pre-seeds an operation's `Custom(E)`. This is the whole of MM-FFI-5's
"a foreign call is an inferred effect like a syscall": the monotone
fixpoint in `inferEffects` (5199-5241) then propagates it transitively to
every caller for free. **No new inference machinery, no new walk, no
change to `isSyscallPrim` (5029-5034).** A dedicated `builtinEff "FFI"`
is the alternative and is worse: `handle` lists, AX3011 and the AXTAG
vocabulary all key on the builtin effect names, so a new one means
touching `isBuiltinEffect`, `effHandledBy` (4835-4849) and
`axtagEffectOf` (6845-6852) to no benefit an FFI-specific effect actually
buys.

**Four more tables must learn the tag**, each of which is silently wrong
otherwise:

| Site | Lines | Symptom if skipped |
|---|---|---|
| `declNamespace` | 790-796 | returns `NS_NONE`, so the duplicate pass short-circuits and two externs with one name are accepted |
| `defIdxBuild` | 1114-1132 | indexes only `TAG_D_FN` with `nodeVis == 1`, so **every `::` over an extern draws a false AX3015** |
| `ambBuildDecl` | 3657-3669 | an extern is not an AX3014 definer, so a name defined by two imported binding modules is not caught |
| `tcWalkDecls` | 6705-6724 | no scope entry is parked, so the name is invisible to `set`-target resolution |

**Reject polymorphism.** A type variable anywhere in an extern signature
must be refused. A polymorphic Axiom function silently grows a hidden
trailing `i64 %__evw.h` parameter (codegen.ax:3008-3021, passed at 5925),
and that word would be handed to Rust as a real argument. This is
contract C3 and it is not optional.

**What the checker cannot do.** `tyCompat` (188-235) is the entire
"unifier": a type variable on either side matches anything, and
constructors match by name and arity only. It will not catch a binding
that says `Int` where Rust said `f64`. That check belongs to
`axiom-bindgen`, which reads real Rust types. The one representational
check that does survive is `tyReprClash`/`tyIsReprScalar` (7051-7096),
naming only `Bool`, `Float` and `String` as non-handles — and that is
where the new opaque `Foreign` type registers, so ARC never treats a
foreign pointer as a reference.

### 3. `self_host/codegen.ax` — the `declare`, and the call

**`emitDecl`** (2817-2846) emits only `TAG_D_FN`; every other tag falls
through unchanged. Add a `TAG_D_EXTERN` arm that emits

```llvm
declare i64 @axffi_count_vowels(i64) #0
```

using `llvmSym` (982-990) for the symbol and the same `#0` group every
other function carries. `#0` is `{ "no-builtins" }` (2805) and it must be
on the declare too: without it `opt` is free to reason about a declared
name that happens to match a libc signature.

This is the fix for the bug that killed `foreign`. The old binding
emitted `call i64 @putchar(i64 65)` into a module that declared no
`@putchar`; LLVM **textual IR requires a declare for an undeclared
callee**, so `check` passed and `opt` then died with `use of undefined
value '@putchar'` (docs/self-hosting.md:4247-4260). Emitting the declare
is the entire difference.

Declares must be emitted **before** the bodies that reference them, and
deduplicated — two Axiom names may bind one symbol.

**Call sites need no new code.** `emitPlainCall` (5908-5941) already
emits `%tN = call i64 @<sym>(i64 %a0, ...)`. The only change is
resolution: `mangledFor` (1696-1716) must answer the extern's `#:symbol`
rather than its Axiom name. Everything downstream is unchanged, which is
the point — **an FFI call is the same instruction sequence as an internal
call**, with no trampoline and no dispatcher.

**Two hazards.**

`emitPlainCall` with zero arguments emits the invalid `@f(i64 )`
(5930-5934 has no empty-args branch). It is unreachable today because
`mkEApp` (parser.ax:302-303) always carries one argument, so `(f)` parses
as a bare variable and goes down `emitVar`'s nullary arm. A zero-argument
extern is reachable, so the nullary path must be used for it.

Entry-file declarations keep their **bare** name (`@addTwo` is emitted
literally; only imports become `Mod$name` via `mangleDecl`,
namespace.ax:128). So an Axiom program with a top-level `sha256Hex` and a
Rust crate exporting `sha256Hex` would collide at link. Binding modules
are always imported, so their names are mangled and safe; the collision
is only reachable for an extern declared in the entry file. Either refuse
that, or extend AX3026 (`reserved-runtime-name`) to cover it.

### 4. `self_host/driver.ax` — the link line

The build pipeline is IR → `opt` → `llc -filetype=obj
-relocation-model=pic` → `cc <obj> -o <out>` (207-235), and the `cc`
invocation takes **no `-l` and no `-L` today**. Thread two new flags,
`--link-lib NAME` (repeatable) and `--link-search DIR` (repeatable),
into `ccArgs` at 226-230 as `-L<dir>` then `-l<name>`, in declaration
order so the link is deterministic — `check-reproducible.sh` compares
bytes and an unordered link line will flip them.

Both flags also need entries in the help text (315-317) and the flag
parser in `main.ax`.

The archive path is not inferred from `#:lib`; the manifest names the
library and the flag supplies the search path. Inferring it would make
the compiler go looking in cargo's target directory, which is a build
system's job.

### 5. `self_host/symbols.ax` — AXSYM

Re-add a symbol kind. **Do not reuse `X`**: it was the foreign-binding
kind and was removed with `foreign` (docs/self-hosting.md:4234). Use `E`
for an extern, and render the linked symbol as a `#symbol=` field
alongside the existing `#effect=io`. `SymMaps` grew from 22 fields to 20
when the foreign map pair was dropped; adding one pair back returns it to
22.

### 6. `self_host/format.ax` — the printer

Add an `fpDeclExtern` arm. This one carries a specific historical
warning: `check-fmt.sh`'s own header records that `type`, `trait`, `impl`
**and `foreign`** were all formatted into source that did not parse, with
CI green, because the fmt zoo only carries what someone wrote into it. So
the printer arm and a zoo case land in the same commit, and the zoo case
must be **compiled**, not merely formatted and type-checked — that is the
exact gap that let the old `foreign` fixtures sit broken for months
(docs/self-hosting.md:4265-4270).

### 7. `tree-sitter-axiom/` — grammar and corpus

A rule for `extern` plus corpus cases. `scripts/check-tree-sitter.sh`
gates it. Note the precedent at docs/self-hosting.md:4233-4240: `packed`,
`repr(C)` and `align(N)` were in the grammar and the corpus and were
**rejected by the compiler the whole time**, so a grammar rule is not
evidence the language accepts the form.
