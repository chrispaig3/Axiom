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

**THE NARROWING IS RIGHT AND ITS ARGUMENT IS INCOMPLETE**, measured in
§4d. "An empty container holds no value of type `a` for anything to
have fabricated" is true at the moment of construction, and it stops
being the whole story one line later: the caller still CHOOSES `a`, and
then mutates the container at that choice. Where nothing pins the
choice — an un-annotated `let` — the same binding can be written at one
type and read at another, and `AX3040`'s own exit 139 is reached with
no `cast` written anywhere. The refusal `AX3040` gives up here has to
be paid for by pinning (§5 item 4), not by re-widening the rule: the
nested case really is a different shape, and a bare result variable is
still the only one a `cast` alone can produce.

## 3. What the migration costs, measured

Flipping **four** signatures in `stdlib/Vec.ax` — `vecNew`, `vecLen`,
`vecGet`, `vecPush` — produces **3,934 errors** across the tree, 7,866
`AX3004`s among them. The whole compiler passes Vecs as `Int`, so every
signature that takes or returns one has to say so.

**"That is mechanical and the type checker drives it" is WITHDRAWN**
— §4c drove it and measured otherwise. The checker does name a file,
line and column for every error, and the fixpoint is "no errors",
which is a strong acceptance condition; what does not follow is that a
rule can reach it. Widening a parameter because a `Vec` arrives there
breaks the callers that pass an `Int`, and the tree diverges rather
than converging. Read §4c before planning the port. There is a
stronger acceptance condition available, and it still holds.
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

## 4b. `Vec` as a FIELD type was a silent leak, measured

Seeding `Vec` as a writable type had a consequence section 1 did not
look for, and it is a live defect rather than a migration blocker:
**`fldClass` had no arm for `Vec`.**

`self_host/codegen.ax`'s `fldClass` answers 0 (machine scalar, never
walked), 2 (reference, walked and released) or 1 (UNCLASSIFIABLE) —
and 1 does not mean "skip this field". It forces the whole block to
the LEAF shape, on the stated grounds that "under-reclaiming leaks, a
wrong bit use-after-frees, and only one of those is survivable". A
`Vec` reached that arm: not a scalar name, not one of the
`String`/`Option`/`Handle` trio, and — being seeded by the checker
rather than declared — not in the module's data list either.

Measured on one record, one field type apart:

| the record | shape word | the `String` field |
|---|---|---|
| `(data Rec (MkRec Int String))` | `262152` | walked |
| `(data Rec (MkRec (Vec Int) String))` | **`8`** | **never walked** |

`262152` is `0x40008`: bit 18 names block word 2, the `String`. At `8`
the map is empty, so the sibling's share is never handed back. No
diagnostic, every gate green, and reachable from ordinary source the
day `Vec` became writable.

**`Vec` is class 0, and that is an ownership decision rather than a
claim that a vector is a number.** `stdlib/Vec.ax` says "a vector is
born owned ... and `vecFree` is the only thing that ends one", so a
record that merely HOLDS a vector does not own it and must not release
it. Class 0 is also exactly what such a field got while it was spelled
`Int`, which is what makes typing the handle a type-level change with
no reclamation consequence. Class 2 — walking and releasing it, as
`String` and `Handle` are — is the other defensible answer and is a
SEPARATE decision: it would have to audit every `vecFree` in the tree
first, because an automatic release beside an explicit one is a double
free.

The name is spelled in the two lists the tree requires to agree —
`scalarTyName` in codegen and `evScalarName` in typecheck — so
evidence reaches the same answer the reference map does.

**It is inert for everything that exists.** Stage-matched emission of
`self_host/main.ax` before and after: **199,765 lines of IR, byte for
byte identical**. The classification can only move code that has a
`Vec`-typed field, and nothing in the tree has one yet.

Gated by `scripts/check-vec-field-shape.sh`, whose table has four rows
so the equality cannot pass vacuously: two of them must read a
different number, and the `(Vec Int)`/`String` row read `8` before the
fix.

## 4c. What the migration actually costs, re-measured

Section 3 records "3,934 errors ... mechanical, and the checker drives
it". The first half is right and **the second half is wrong**,
measured 2026-09-01 by driving it.

Flipping `Vec.ax`'s thirty container positions — `vecGet` answering
`a`, `vecTry` `(Option a)`, `vecPush` `(-> (Vec a) a (Vec a))` —
typechecks **`Vec.ax` itself with zero errors** and leaves **4,406**
in the tree, every one `AX3004`. A checker-driven rewriter then took
it to **1,916** over four rules, each verified by recompiling and
rolled back when it made things worse:

| rule | what it does | effect |
|---|---|---|
| typed view | `(memGetWord n i)` becomes `(memGetWordVec n i)`; `nodeB` becomes `nodeBVec` | **converges** |
| param | a parameter USED as a `Vec` gets `(Vec a)` | **converges** |
| null check | `(== v 0)` on a handle becomes `(== (cast Int v) 0)` | **converges** |
| callee param | a parameter that RECEIVES a `Vec` gets `(Vec a)` | **diverges** |

**THE LAST ROW IS THE FINDING.** Widening a parameter because one
caller passes a `Vec` breaks the callers that pass an `Int`, and those
are not a residue: run unguarded, the tree goes 1,916 to 5,990 to
10,102 to 14,392 and never comes back. The compiler uses `Int` as a
universal word type on purpose, and many functions are genuinely
polymorphic by punning. Separating `Vec` out of that is a decision per
function, not a rewrite.

**The vehicle that works is the typed view**, and it is the one this
repository already uses for the same problem: `nodeAName` casts word 1
to `String` at a RETURN, inside a signature that carries the type,
"and not at the call sites — a cast at an argument root classifies
that value's evidence 0 and drops its retain or its release"
(`docs/memory-model.md` MM-VAL-22). `memGetWordVec` and
`nodeAVec`/`nodeBVec`/`nodeCVec` are the same move for containers.

**What remains is 1,916 errors over 648 declarations**, and the head
of that list is the compiler's context constructors — `newCG`,
`tcNew`, `smNew`, `symbolsRenderGens` — which build records of many
`Vec` fields through raw words. Those need §4b's classification to be
correct before they can be typed at all, which is why it went first.

**`vecPop` is a second `vecGet`, and section 4 did not name it.** Its
body answers `0` on an empty vector, and under `(-> (Vec a) a)` that
fabricates an `a` exactly as `vecGet`'s sentinel did. It takes the
same answer — `__indexTrap` — and `vecLast` inherits the trap for
free because it delegates to `vecGet`. Nothing else in the module has
the shape.

## 4d. The migration's PREMISE only half holds, measured

`(Vec a)` exists to stop a caller putting an `Int` in and taking a
`String` out. It does that **exactly where a declaration says the
element type, and nowhere else** — and the second half is not a
rough edge, it is the shape `AX3040` was promoted to an error for.

Measured against a migrated `Vec.ax`, four probes:

| the program | `check` | runs |
|---|---|---|
| push a `String` into a declared `(Vec Int)` parameter | **refused** | — |
| pass a `(Vec Int)` where `(Vec String)` is declared | **refused** | — |
| read an element through a declared return type at the wrong type | **refused** | — |
| `(let ((v vecNew)) { (vecPush v 42) (needVec (vecGet v 0)) })` | **OK** | **exit 139** |

The last row has **no `cast` anywhere in it**. An `Int` goes in, a
`(Vec Int)` comes out, and `vecLen` dereferences 42 as a block header.
That is `conjure`'s exit 139 reached without writing the coercion
`AX3040`'s own help text says is the only way to produce it.

**THE CAUSE IS THAT THE CHECKER DOES NOT UNIFY.** `tyCompat` is a
COMPATIBILITY PREDICATE — it answers 1 or 0 and records nothing.
A minted placeholder "still matches anything — that is the whole
reason it exists", and since no binding is ever written down, `(Vec
_a)` is compatible with `(Vec Int)` and then, just as happily, with
`(Vec String)`. The let-bound vector's placeholder is never pinned,
because each `vecPush` matches against its own fresh one.

It is NOT a general unifier defect, which is worth stating because it
narrows the fix. A user-defined `(Box a)` behaves:
`(needStr (unbox (MkBox 42)))` is refused, because the constructor
hands over a concrete `(Box Int)` and nothing has to be remembered.
`(-> a a)` behaves for the same reason. The hole needs a placeholder
that OUTLIVES the expression that could have pinned it, which is
precisely what a `let`-bound mutable container is.

**So `Vec` is not the subject here.** Any parameterised type reached
through an un-annotated `let` has it; `Vec` is where it bites because
a container is the thing you bind and then mutate.

**WHAT THIS MEANS FOR THE ORDER.** The migration must not land before
pinning exists. Landing it would replace a visible unsafety with an
invisible one: today reading an element back at a reference type is
spelled `vecGetStr` or an explicit `cast` and `#raw`/`AXSYM` can
enumerate it, whereas afterwards `(vecGet v 0)` would silently become
whatever the context asked for. The type-level win at declared
boundaries is real and is worth having — it is the first three rows
above — but it is not worth buying with the fourth.

Pinning is a substitution, and the checker has nowhere to put one:
`tyCompat` returns a Bool. That is an architectural change to
inference, not a patch, and it is the next thing this document should
be about.

## 5. The order

1. **`Vec` as a type, and `AX3040` narrowed.** Landed.
2. **`vecGet` traps.** Landed. The seed carries `__indexTrap`, and
   `vecGet` calls it on an out-of-range index (status 77).
3. **The field-shape defect.** Landed, and it was NOT on this list
   until a migration attempt found it — see §4b. It is a
   prerequisite: until `fldClass` classifies `Vec`, every record that
   holds one leaks its OTHER fields.
4. **Pinning a placeholder** — the checker compares types and never
   records a binding, so an un-annotated `let` over a container is
   unpinned and `(vecGet v 0)` answers whatever the context wants
   (§4d, `check` OK and exit 139). This is now BEFORE the migration
   rather than after it, because the migration would otherwise trade a
   visible unsafety for a silent one.
5. **The migration**, driven by the checker, with byte-identical IR as
   the acceptance test. Measured in §4c, and it is not the mechanical
   change this document assumed.
6. **`for` as a keyword**, which is only expressible once 5 exists.

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

`Vec` is a type, `AX3040` is narrowed, and **§4 is built**: `vecGet`
refuses an out-of-range index through `(__indexTrap)` at status 77,
and the seed carries both. `vecTry` remains the checked read.

**§4b is built and gated** — `fldClass` classifies `Vec` as class 0,
so a record holding one keeps the reference map for its other fields.
That was a live defect from the day `Vec` became writable, it is
byte-for-byte inert for every program that exists, and
`scripts/check-vec-field-shape.sh` is what would notice it coming
back.

**The migration is measured and BLOCKED, and §4d is why.** §4c
replaces this document's earlier cost estimate: 4,406 errors, reducible
to about 1,500 over ~650 declarations by checker-driven rewriting, with
the remainder needing a per-function decision rather than a rule. §4d
is the harder finding: the safety the migration exists for holds only
where a declaration names the element type, because `tyCompat` compares
and never binds. Pinning comes first (§5 item 4). Nothing from §4c,
§4d or §6 is in the tree.
