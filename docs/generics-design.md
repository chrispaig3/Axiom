# Parameterised containers, and what `Vec a` actually costs

`for` cannot become a language keyword covering both a range and a
container until a container has an element type. `Vec` does not: it is
an `Int` handle, and an element is read through `vecGetStr` or
`vecGetWord` depending on what it holds. That is why `stdlib/Html.ax`
carries **two** loop macros for one idea, and why a keyword written
today would be as type-specific as those macros — the problem would
move from the macro layer into the code generator, not go away.

The asymmetry is already in the signatures:

```
(pub :: vecPush (-> Int a Int))     ; the element going IN is polymorphic
(pub :: vecGet  (-> Int Int Int))   ; the element coming OUT is an Int
(pub :: vecGetStr (-> Int Int String))
```

`vecPush` takes an `a`. Nothing ties that `a` to what `vecGet` answers,
because there is no `Vec a` to carry it. **That is the whole of the
generics problem.**

## 1. `Vec` is a type now

`Vec` is seeded in `typecheck.ax` beside `Option`: a `DataEnt` with
**no constructors** — abstract and parameterised. A `Vec` is made by
`vecNew` and read by `vecGet`, never matched, so there is nothing for
a pattern to name. `(Vec a)` is a writable type; before this it was
`AX3002 undefined type`.

**The runtime shape does not move.** A `Vec` is the handle it always
was, one word, allocated by `vecNew`. This is a type-level change, and
that separability is the point: it can land before the migration that
uses it, and `fldClass` keeps answering for `Vec` exactly what it
answered for the `Int` it replaces.

## 2. `AX3040` had to narrow, and it was wrong as written

`(pub :: vecNew (Vec a))` drew **`AX3040` result-only-tyvar**: "the
caller chooses the type and a `cast` fabricates the value."

It does not. `(-> Int (Vec a))` returns a **`Vec`**, not an `a`, and an
empty container holds no value of type `a` for anything to have
fabricated. The rule's own sentence says "returns type variable `a`",
and that is now what it checks: only a **bare** result variable.
`(-> Int a)` still fires; a variable nested under a type constructor
does not.

`None : (Option a)` has had exactly this shape since `Option` was
seeded — it was never refused only because a builtin constructor never
passes through the check. Before the narrowing, **every polymorphic
empty constructor was refused**, so no generic container could declare
the one function it cannot do without.
`tests/diagnostics/347-result-only-tyvar.ax` carries both arms: the
bare case still refused, the nested case silent.

## 3. What the migration costs, measured

Flipping **four** signatures in `stdlib/Vec.ax` — `vecNew`, `vecLen`,
`vecGet`, `vecPush` — produces **3,934 errors** across the tree, 7,866
`AX3004`s among them. The whole compiler passes Vecs as `Int`, so every
signature that takes or returns one has to say so.

That is mechanical and the type checker drives it: each error names a
file, line and column, and the fixpoint is "no errors", which is a
strong acceptance condition. There is a stronger one available.
`(Vec a)` and `Int` have the **same runtime representation**, so a
correct type-level migration must emit **byte-identical IR**. That is
the test to hold it to.

## 4. The blocker: `vecGet` cannot answer `a`

Flipping all thirty container positions leaves **42 errors inside
`Vec.ax` itself**, and they are not bookkeeping. Two shapes matter:

* **The implementation must reach through the abstraction.**
  `(memGetWord (vecData v) i)` needs the handle as a word. Inside the
  module a `Vec` IS an `Int`, so these are honest `cast`s at the
  boundary — but `docs/memory-model.md` records that **`cast` kills ARC
  evidence**, so a generic accessor built out of casts is not free.

* **`vecGet`'s sentinel cannot survive.** Its body answers `0` for an
  out-of-range index. Under `(-> (Vec a) Int a)` that is fabricating an
  `a` — and for a reference element it is a null a caller would
  dereference. **You cannot make up an `a`.**

So generics forces a decision about `vecGet` that has nothing to do
with types:

1. `vecGet` answers `(Option a)` and the sentinel goes — which is
   `vecTry` today, and would make the safe accessor the only accessor.
2. `vecGet` traps out of range.
3. `vecGet` stays raw, tagged `;@axiom:raw`, with `vecTry` the checked
   surface — the unsafe layer made finite and enumerable, which is what
   `#raw` in AXSYM is for.

**(1) is the one that matches everything else this repository has
decided** — it is `compat/SENTINELS`'s direction rule applied to the
literal-`0` sentinel the census already names as out of its reach — and
it is the one with a cost: `vecGet` has hundreds of call sites.

## 5. The order

1. **`Vec` as a type, and `AX3040` narrowed.** Landed; nothing uses the
   type yet.
2. **Decide `vecGet`.** Section 4 is the fork, and it is a language
   decision, not a refactor.
3. **The migration**, driven by the checker, with byte-identical IR as
   the acceptance test.
4. **`for` as a keyword**, which is only expressible once 3 exists.

## 6. A route that was tried and is the wrong one

Before seeding `Vec` as a type, the obvious move looked like a wrapper:
`(data Vec (a) (MkVec Int))`, since `axiom-bindgen` already wraps every
opaque Rust type that way. That costs a heap block — measured on
`(data Box (MkBox Int))`, `axiom_alloc(16)` plus four stores — so it
was prototyped as a **transparent newtype**: one constructor with one
field represented AS the field. It works and is free (`mk` becomes
`mul; ret`, fixpoint holds, 96/96, 179/179, 194/194).

It is still the wrong route, and two measurements say why:

* **`fldClass` answers from the TYPE NAME.** A `data` name classifies
  as a reference because a type name cannot reach its constructor's
  entry (`lookupType` is keyed by constructor). Transparent, the value
  IS the field — so a newtype over `Int` classified as a reference
  hands `axiom_release` an integer to read as a block header.
* **`Handle` has an identity the FFI relies on.** Restricting to
  reference fields avoids the first problem and breaks
  `demo/060-opaque-handle`: `exit 73, handle is closed`. `Handle`
  carries a close/inert protocol, the wrapper and the handle were two
  identities, and collapsing them makes a close through one visible
  through the other.

Seeding `Vec` as an abstract type needs neither: no wrapper, no
allocation, no reclassification. The newtype work is not in the tree.

## 7. Status

`Vec` is a type and `AX3040` is narrowed — both landed, both inert
until section 4 is decided. The migration is measured at 3,934 errors
and is not started.
