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

### DECIDED: `vecGet` traps, `vecTry` stays the checked read

**(2)**, and the case rests on three decisions this repository has
already made rather than on taste.

* **`Vec.ax`'s own comment already calls the sentinel the worse
  failure.** "0 IS A VALUE A CALLER MAY HAVE PUSHED — so a caller who
  reads past the end and one who reads a stored zero receive the same
  answer and cannot tell which happened. On a parser fed by a peer that
  is the worse of the two failure modes: **not a crash, a wrong answer
  that keeps going**." The file argues for the crash; it just could not
  have one while the element was an untyped word.
* **The same comment already chose the split.** "`vecGet` is unchanged
  and stays. It is the right call where the index is already known good
  — a loop bounded by `vecLen`." `vecGet` direct, `vecTry` checked, is
  the design on file. Trapping keeps it; option (1) discards it and
  forces a match at every in-range access.
* **Axiom already answers this class of bug with a trap.** Division by
  zero exits 72 with `axiom: division by zero`. An index out of range
  is the same class of programmer error, and answering it with a value
  is the odd one out.

And the trap is **recoverable**, which is what makes it acceptable
rather than merely blunt: `__axiom_recover` answers 70, 71 or 72 at a
recovery point instead of exiting, and 77 would join them. A trap in
Axiom is a catchable outcome, not unconditional process death.

**(1) is the runner-up and is rejected on cost, not principle.** It is
`compat/SENTINELS`'s direction rule applied to the literal-`0`
sentinel, and today's register-pair work makes `(Option a)` free at a
direct match — the 11.86 ns objection that governed this for months is
gone. What it does not answer is the ergonomics: `vecGet` has hundreds
of call sites, most of them indices a loop already bounded, and forcing
a match there adds noise without adding safety. `vecTry` exists for the
ones that need it.

**(3) is refused outright.** `docs/memory-model.md` records the raw
layer closed 14 → 0; making `vecGet` — one of the highest-traffic
functions in the tree — `;@axiom:raw` would reopen it at the worst
possible place.

### What (2) needs, and why it is not in this commit

1. A trap `@__axiom_index_out_of_range`, status **77** (70–76 are
   taken; 73 is the FFI's), mirroring `emitDivTrap` — message,
   `__axiom_recover_abort` first, backtrace, exit.
2. A **diverging nullary primitive** so `stdlib/Vec.ax` can reach it.
   Traps today are `internal` LLVM functions emitted by codegen and
   unreachable from Axiom source.
3. **The primitive must type as `(-> a)`** — it never returns, so it
   inhabits every result type, which is `AX3040`'s own stated way out
   ("make it DIVERGE, so every path ends in a call that never returns,
   which is what makes `for all a` honest").

**Steps 1–3 are built.** `(__indexTrap)` is a nullary primitive typed
`(mkTVar "a")` — a bare variable, freshly instantiated at each use, so
one call stands in an `Int` result and a `String` result in the same
program. The divergence fixpoint never entered it: that fixpoint
decides whether a DECLARATION with a result-only variable is honest,
and a builtin registered in `fns` has no declaration to ask about. The
teeth were in the wrong place.

**Step 4 — `vecGet` calling it — is not built, and the reason is the
bootstrap.** `scripts/build-shared-axc.sh` compiles `stdlib/` with the
INSTALLED compiler, so a library that uses a primitive the seed does
not know cannot be built:

```
error[AX3001]: undefined variable `__indexTrap`
   --> stdlib/Vec.ax:225:7
```

A primitive lands in the compiler first and the library uses it after
the seed advances. That is the ordinary shape of adding one to a
bootstrapped language, and it is why this commit stops one step short
of the change it exists for.

## 5. The order

1. **`Vec` as a type, and `AX3040` narrowed.** Landed; nothing uses the
   type yet.
2. **`vecGet` traps.** Decided (§4). The trap and the primitive are
   built; `vecGet` uses them once the seed carries `__indexTrap`.
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
until §4 is built. §4 is **decided** — `vecGet` traps — and not
implemented: it needs a diverging primitive, and divergence is a
fixpoint over Axiom-level tails that no builtin is currently in. The
migration is measured at 3,934 errors and is not started. Nothing from
§4 or §6 is in the tree.
