# Changelog

Notable changes to Axiom, newest first.

This file starts at `0.2.0` because `0.2.0` is the first tag. The tree
said `0.1.0` from its first commit and nothing ever tagged it, so there
is no `0.1.x` to compare against and no `0.2.0-rc` that preceded this.
Rather than invent a history, the entry below states what `0.2.0` *is*
— and, in the same detail, what it is not.

Every claim here carries the gate that holds it. A claim without one is
a comment, which is this project's rule everywhere else and applies to
its changelog too.

---

## Unreleased

### Added

- **`symbols` answers for a file that does not compile.** It printed
  the diagnostics and exited with stdout **empty**, which is the moment
  a reader most needs the declarations: the file is wrong and they are
  working out why. `tc` is built by the line above the branch that
  exited, so the table was being *thrown away*, not spared — and every
  language server answers `documentSymbol` for a file that does not
  compile.

  Measured: a file with an undefined variable answered **0** symbol rows
  and answers **3**. **The exit status does not move** — still 1 — so
  `check-tools-selfhost.sh`'s equivalence (`symbols` exits 0 for exactly
  the files `check` exits 0 for) is untouched; what changed is stdout,
  which that sweep reads separately. A healthy file's output is
  byte-identical.

  One renderer serves both arms now (`symbolsEmit`). It was written out
  in the success arm only, which is how the failure arm came to print
  nothing at all.

  **This was the second of the two reasons `docs/agent-harness.md` §6
  gave for not promoting `AX3010` to an error** — "making the claim an
  error deletes the AXSYM surface for the files that carry a wrong tag,
  eight files in this repository's own corpus, one of them 196 symbol
  lines". With the first closed earlier in this release, neither
  objection stands, and promotion is a decision rather than a blocked
  one. §6 records what it would buy and what it would not: it makes a
  FALSE tag fatal; it does not make effects *checked*, because a tag is
  opt-in and an untagged function performing IO still draws nothing.

- **One of the two measured reasons `AX3010` could not become an error
  is gone.** `docs/agent-harness.md` §6 refused promotion on two
  grounds, and the first was that *"`pure` claim contradicted"* fires on
  a function that merely **names** an effectful function without calling
  it — `(fn (handoff k) shout)` reported `#effects=IO` and was accused
  of performing IO it does not perform. "Promoting that shape refuses
  correct programs."

  The cause is the reference-site rule unioning a referent's effects,
  and it is **exact for a nullary referent**: this language invokes
  `vecNew`, `sysArgc` and `__argc` by writing their names, so naming one
  *is* calling it. It is an over-approximation only for a referent that
  takes arguments, where a bare name is a value.

  **Deleting the over-approximation was tried first, and measured
  wrong.** `tests/diagnostics/340-effect-op-value.ax` is
  `(handle (apply ask 1) (IO) ...)`, which reaches `Ask` only through
  the bare `ask`; without the union its `AX3011` — a hard error for an
  inexhaustive `handle` list — became an `AX3038` **warning**. Weakening
  the one effect check that is already an error is the wrong direction
  for this work, so the union stays.

  **The two consumers get different answers from the same walk
  instead.** A contribution made by naming an arrow-typed function now
  also sets `?:byref`, a marker beside `?:incomplete` and its exact
  opposite — `?:incomplete` says the row is a *lower* bound, `?:byref`
  says it may be an *upper* one. `AX3011` keeps the upper bound and is
  unchanged. The `contradicted` arm, the one that accuses an author of
  writing a false claim, declines to do so on evidence that may be the
  analysis's rather than the body's, and emits `AX3037` *cannot be
  checked* instead. `handoff` draws that; a function that really
  performs IO under a `pure` tag still draws `AX3010`.

  **And the row says so.** `#effects-overapprox` joins
  `#effects-incomplete` in AXSYM, because a reader who sees
  `#effects=IO` on `handoff` and nothing else has been told the same
  falsehood the diagnostic used to tell. `handoff` reads
  `#pure #effects=IO #effects-overapprox`.

  Two things this cost, both found by running it. A marker riding the
  effects Vec is invisible until a consumer treats it as an effect:
  `AX3011` emitted a **second** *unhandled effect* diagnostic naming the
  marker, and AXSYM rendered `#effects=IO,byref`. `checkUnhandled`'s own
  comment had already warned about exactly this — *"every consumer that
  renders an effect has to skip it"* — written when there was one marker
  and one place to forget it. The test is a function now,
  `effIsMarker`, so a third marker cannot be forgotten in the same way.

  Measured across `stdlib/` and `self_host/`: **zero** of 3,034 effect
  rows changed, and no other fixture's diagnostics moved.
  `tests/diagnostics/355-tag-over-approximated.ax` pins both directions,
  `handoff` beside `liar`, because a check that went quiet on the second
  would have traded one wrong answer for another.

  **What is still open**, and it is now the only thing: `symbols` folds
  every failure into exit 1 and prints no table, so promoting `AX3010`
  would delete the AXSYM surface for exactly the files carrying a wrong
  tag. A symbol table is a fact about the *source* — every language
  server answers `documentSymbol` for a file that does not compile — and
  fixing it moves no exit status, so `check-tools-selfhost.sh`'s
  equivalence still holds.

- **`Vec` can sort.** It could not, which is a strange thing for a
  language to ship: `Vec` was `new`/`push`/`pop`/`get`/`set`/`len`/
  `cap`/`sum`/`hash`, so every program that needed ordering wrote its
  own. `vecSort` orders ascending by machine word and `vecSortBy` takes
  a comparator, both in place, both answering the vector.

  **Heapsort, and the reasons are the container's.** It is in place, it
  has no recursion to grow a stack with, and its worst case is its
  average case — where quicksort's worst case is a sorted input, which
  is the input a caller most often has, and a merge sort's extra array
  is expensive in exactly the way a bump allocator with no `free` makes
  it.

  **The swap does not go through `vecSet`, and that is the whole
  correctness argument.** A sort is a *permutation*. `vecSet` releases
  the element it displaces on a `vecNewRef` vector — right for a write,
  wrong for a swap, because the two halves displace each other, so the
  pair would release both shares and retain them back, and a count that
  touches zero between the two hands the block to the next same-size
  allocation while this vector still addresses it. Moving the raw words
  takes no share and gives none back; a permutation changes no
  element's count. `tests/stdlib/405-vec-sort.ax` is what would catch
  the other choice: four heap `String`s sorted and then all four read
  back, since a freed element reads as whatever was allocated over it.

  The fixture also carries the shapes a heapsort gets wrong when its
  bounds are off — empty, one element (`n/2 - 1` is `-1`, so the
  heapify loop must not run), already sorted, exactly reversed,
  duplicates, and negatives, which a comparison written with unsigned
  intent orders wrong and nothing else would show. 5,000 elements are
  checked ordered rather than printed, and `vecSort` and `vecSortBy`
  sort one input both ways and must agree, which is what keeps two
  implementations of thirty near-identical lines from diverging.
  Drilled: making the sift pick the smaller child turns it red.

  Measured 160,000 elements in **0.016s**, and the curve is flat —
  1.01×, 1.84×, 1.11× per doubling.

  **And the first higher-order function in this library made the effect
  system admit a lower bound, on its first run.**
  `check-agent-policy.sh` has an exempt list for declarations carrying
  `#effects-incomplete`, and the list was **empty** — the comment above
  it says that emptiness *was* the finding the assertion was written
  for. It was empty because nothing in the library called a function it
  was handed. `vecSortBy` does, by definition, so its `#effects=Mut` is
  *at least* `Mut`: the comparator a caller supplies may perform
  anything.

  It did not squeak past the check — it was refused by it, which is what
  the check is for, and the two entries are that refusal examined and
  accepted rather than routed around. This is `MM-EXEC-9a`'s one
  remaining row meeting real code, and it is not fixable by naming the
  function at the call site: the call site's whole purpose is that the
  function is the caller's. A sort that could only order words its
  author anticipated would not be a sort. The row still *announces*
  itself — `#effects-incomplete` is on it and a `;@axiom:pure` claim
  over it draws `AX3037` — so a reader gets a lower bound labelled as
  one, which is what makes the entry acceptable at all.

  The gate's own summary said *"nothing in it carries an effect row the
  checker could not finish"*, which stopped being true the moment the
  list stopped being empty; it now names the count and reads it from
  the list rather than asserting it.

  Two things the API reference caught rather than a reviewer.
  `vecSortBy`'s documentation was written above the private helper
  instead of above the public declaration, so the generated reference
  printed the name with an **empty summary**. And its first draft
  documented `(vecSortBy v strCmp)`, which does not compile: a
  top-level function is not a value here, because a partial
  application has no closure record to hold what it was not given
  (`AX3013`). The spelling in the comment is the one that works.

- **Effect inference was quadratic in the depth of a call chain, and the
  losing declaration order is the one people write.** A round of
  `inferEffects` propagates an effect **one call edge** when it meets the
  caller before the callee, and the **whole chain** when it meets them
  the other way. `inferEffectsPass` binds its recursive call before its
  body, so it walks declarations last-to-first — fast for a file whose
  callers sit above their callees, slow for the conventional layout of
  helpers above their users.

  Measured on one call graph written both ways, 2,000 functions with an
  effect at the bottom:

  | declaration order | N=2000 |
  |---|---|
  | callers first | 0.052s |
  | callees first | **3.504s** (67×, 3.66× per doubling) |

  3.66× per doubling is the quadratic `README`'s retirement table has
  suspected since it was written — *"watch the known quadratic at 55.7%
  of a check at N=8000"*. It is rounds × declarations, where rounds is
  the depth of the chain.

  **One round is two passes now, in opposite directions.** The
  per-declaration work is `inferEffectsOne`, so the same work walks
  either way; a round goes forward first and backward only if forward
  grew something. Either pass answering 0 ends the fixpoint — a complete
  pass that grows nothing has reached it, whichever way it walked.

  | | before | after | |
  |---|---|---|---|
  | chain, callees first | 3.180s | **0.038s** | 82.8× |
  | chain, callers first | 0.040s | 0.035s | no regression |
  | 16,000 plain functions | 0.530s | 0.526s | no regression |
  | `self_host/main.ax` | 0.339s | **0.248s** | **1.37×** |

  The last row is the one that matters daily: the compiler's own
  self-check is **27% faster** on a real 60,881-line program.

  **It changes no answer.** All **3,029** `#effects=` rows `axiom
  symbols` reports across `stdlib/` and `self_host/` are identical
  before and after, and a diagnostic differential over every `.ax` in
  the tree reports zero differences. A fixpoint's result does not depend
  on the order it is reached in; only the round count does.

  Not the complete answer: a graph that is not a chain can still need
  several rounds, and the general fix is a **worklist** over the reverse
  call graph — when a row grows, re-examine that function's callers and
  nothing else. The edges already exist (`tcNoteCall`, word 29, resolved
  in round 1), so the reverse map is buildable from what is here. That
  is written down where the next reader meets it and is not made here.

- **The FFI boundary is a C ABI, and now something says so.**
  `docs/ffi.md` has always described it as one machine word per argument
  and one word back — `extern "C" fn(i64, ...) -> i64` — and the emitter
  writes an ordinary `declare i64 @sym(i64, ...)`. Nothing about that is
  Rust. But every FFI fixture here is a Rust crate, and `check-ffi.sh`
  mentions cargo or Rust **46** times against **2** mentions of a C
  compiler, so the boundary was tested only through one client of it.

  Measured before writing any gate: a three-function C archive built
  with `cc -c` and `ar rcs`, bound with an ordinary `extern` block and
  `--link-lib`/`--link-search`, compiled and ran and answered on the
  first attempt. No cargo, no `#[axiom_export]`, no `axiom-bindgen`, no
  crate. Then a `String` crossed and plain C read it through the
  documented two-word header — word 0 the byte length, word 1 the
  NUL-terminated bytes — with no helper on the C side.

  So the capability was already there, untested, undocumented for C
  users and one refactor from breaking silently.
  `scripts/check-c-abi.sh` is **thirty-five gates**' worth of the same
  discipline applied to it: 8 checks, three arities, two `String` reads,
  the emitted `; axiom-extern-lib` comment and the
  `declare i64 @axc_add(i64, i64)` asserted directly rather than
  inferred from an exit status, and two negative probes — an ungrounded
  symbol must be `AX4004` rather than a linker error, and dropping
  `--link-search` must fail, so the first assertion cannot be passing
  for another reason. Drilled by making the C function return `a + b + 1`
  and watching it go red. **It runs no cargo**, deliberately: the ABI
  now keeps a test that survives the Rust workspace being changed,
  moved or removed.

- **A changelog is not a statement about the present, and
  `check-gate-lib.sh` was reading it as one.** That gate holds six
  documents to the number of gates calling `gate_build_axc`. Five state
  the live count. The sixth is `CHANGELOG.md`, whose `0.2.0` entry
  states the count as it stood on 2026-08-24, one lower than today's,
  in a sentence about what that release contained.
  Both arms read whole files, so when the count moved to thirty-five one
  arm demanded the changelog state the new number and the other refused
  it for stating the old one, and the only way to satisfy both was to
  edit a shipped release note into something that did not happen.

  This paragraph originally quoted that entry's exact words, and the
  fixed gate refused *it* — a stale spelling is stale wherever it stands
  in the Unreleased section, quotation marks included. A gate that
  catches its own author is a gate that can fail, which the arm's own
  comment already said about a different draft.

  It now reads a changelog from `## Unreleased` to the next `## ` and
  nowhere else: a released section is history and is left alone. The
  stale-spelling sweep also had `word_for`'s domain at `15..34` while
  the live word became `thirty-five` — the same defect its own comment
  describes, one number later — so the domain follows the table.

  **And scoping the read exposed a third thing, in the shell.** Both
  arms used `grep -q`, which exits at the *first* match — sending
  SIGPIPE to whatever is still writing. Under this script's own
  `set -o pipefail` that makes the pipeline report failure for a search
  that **succeeded**. It is invisible while the producer is a `cat` of a
  short file that finishes first, and it bit the moment the producer
  became an `awk` with 800 lines left to write: `CHANGELOG.md` matched
  by hand and the gate said it did not. Both arms redirect to
  `/dev/null` instead, so grep reads all of its input and the exit
  status is about the search. Same shape as the stray `set -e` in
  `check-diverging-tyvar.sh` earlier in this release — a shell subtlety
  making a check answer about something other than its subject.

- **`linear` and `consume` are refused, not reserved-and-inert.** Both
  parsed; neither did anything. `linear T` built the nominal type
  `Linear T` — a real barrier against `T` (`AX3004`) and nothing more —
  and counted no uses, so a value could be consumed twice or never.
  `(consume e)` was a parse-time **identity** that kept the wrapper: the
  checker typed it as its operand, the IR lowered it to its operand, and
  the form reclaimed nothing.

  `docs/reference.md` said so plainly — "Parsed only", "Nothing enforces
  it today" — which made it honest documentation of a spelling that
  still reads, at the call site, like an ownership guarantee. That is
  the ground `deriving` was refused on here, in this repository's own
  words: *"a clause that does nothing is worse than one that does not
  parse"*.

  They join `union`, `region`, `foreign` and `deriving` as reserved
  words reporting `AX2004` with migration advice, so old source gets an
  explanation instead of an `AX3002` about an unknown type named
  `linear`. They get the **`deriving` verb** — "parsed and enforced
  nothing, and is now refused" — rather than "is no longer part of
  Axiom", because union, region and foreign once worked and these never
  did.

  **The removal found a justification resting on them.** `union`'s
  rationale — in `parser.ax`, in `explain.ax` and in `docs/reference.md`
  — read *"C interoperability is no longer a goal, and an untagged union
  has no meaning under linear types."* The second clause appealed to a
  feature that enforced nothing, to explain a removal that does not need
  it: an untagged union cannot be pattern-matched safely because its
  variants are not distinguishable at run time. All three copies are
  corrected, each recording what it used to say.

  Gone with them: the parse sites and `parseConsumeExpr`; the
  `linear_type` and `consume_expression` grammar rules and their
  highlight entries (`src/` regenerated and checked in);
  `docs/reference.md` §23, now two entries under Removed Features; and
  `ERR-MEM-6`, which said the *model* does not use linear types and now
  records that the *language* does not either.
  `tests/diagnostics/941`, `942` are the refusals.

- **Two gates swept 5,809 files, and this repository has 506.**
  `check-fmt.sh` copies the tree and formats every `.ax`;
  `check-tree-sitter.sh` parses every `.ax` with the grammar. The other
  5,303 were under `.claude/worktrees/` — **eleven abandoned agent
  worktrees, 494 MB**, each a full checkout of this repository at
  whatever commit its run started from, months apart. They are in
  `.gitignore`; `find` does not read `.gitignore`, and neither does
  `tar`.

  It is not only slow, though `check-fmt.sh` spent most of its 238
  seconds formatting ten stale copies of the tree. **A gate that sweeps
  "every file in the repository" and reaches files that are not in the
  repository goes red for a change that is correct here and stale
  there** — which is exactly how this surfaced: removing `linear` from
  the grammar made `check-tree-sitter.sh` report 22 parse failures,
  every one in a worktree carrying pre-change source.

  The two counts had also disagreed with each other unnoticed, because
  different gates print them: `check-doc-drift.sh` counts with Python's
  `glob('**/*.ax')`, which does not descend into a dotted directory, so
  it has always said 506 — the right number, by an accident of which
  tool it reached for. Both sweeps now exclude `.claude/`. The rule:
  whatever a sweep means by "the repository", it must not mean "whatever
  is under this directory".

- **`mapGet` answers `Int`, and a default argument no longer names the
  type of a value it did not supply.** Found by writing the program
  rather than reading the code, which is §1b's own rule:

  ```scheme
  (mapInsert m 1 100000000)
  (strLen (mapGet m 1 "absent"))
  ```

  `check` answered **OK** and the binary exited **139** — 100000000
  dereferenced as a String pointer. `mapGet` was `(-> Int Int a a)`, and
  the variable is in a PARAMETER, so `AX3040` does not fire: the rule
  asks whether a parameter mentions it and one does. What the rule
  cannot see is *which* parameter. `dflt` witnesses what the caller
  wants back when the key is **absent**; the cast inside `mapGet` was on
  the **found** path, where the word comes out of a table that carries
  no element type. The two are unrelated, and the source said so in the
  other direction — "`a` here is witnessed by `dflt`" — with
  `docs/memory-model.md` repeating it as the reason `mapValAt` was moved
  off the `#raw` layer.

  It answers `Int` now, which is the truth about a machine word, and
  `mapGetStr` is the typed reader beside it. That is exactly the pair
  `vecGet`/`vecGetStr` and `memGetWord`/`memGetWordStr` already were —
  **`Map` was the last container whose reader still wore a polymorphic
  spelling**, and `vecGet` had been given this same treatment already.
  Swept the whole standard library to be sure: every other polymorphic
  signature is either over a *parameterised* container (`(Result a e)`,
  `(Option a)`, where the `a` that comes out is the one that went in) or
  write-side (`mapInsert`, `vecPush`, `vecSet`, `memSetWord`, where the
  caller supplies it). One outlier, now closed.

  The blast radius is the measurement: **23 call sites, 22 of them
  already passing an `Int` default** — the one exception is a
  homogeneous `Map` of Strings in `080-map.ax`, which becomes
  `mapGetStr` and drops an outer `cast String`. `mapGetStr` is spelled
  out rather than delegating, because delegating needs `(cast Int dflt)`
  — a cast at an ARGUMENT root, which classifies that value's evidence 0
  and drops its retain (`MM-LIFE-2d`). The cast stays at a RETURN, which
  is the position `vecGetStr` uses.

  `tests/stdlib/081-map-value-type.ax` is the positive half — both
  readers, and an absent key on each — and
  `tests/diagnostics/354-map-value-type.ax` is the refusal, with the
  `Int`-default call beside it as the control that must stay silent.

- **A checked-in list whose ORDER was part of the golden, sorted in
  whatever locale the machine happened to have.**
  `tests/agent/stdlib-effects.allow` is derived by `sort -u` and
  compared with `diff`, so its order is as load-bearing as its contents
  — and `sort` collates by locale unless told otherwise. Measured
  2026-08-25: `en_US.UTF-8` orders `sysEnvp` before `sysEnvSlot`,
  `LC_ALL=C` orders them the other way. All **44** local gates were
  green and all three CI `Tests` legs went red on the same two lines —
  **including darwin**, so it was the locale and not the platform.

  It had been latent since the file was created and surfaced only when
  `sysEnvSlot` joined the list, because until then no two names in it
  differed at a letter whose case decides the order. `scripts/lib/gate.sh`
  already carries the rule, for the seed stamp — "a property of the tree,
  not of where it was checked out or of the runner's locale" — and this
  gate had simply never applied it. Every `sort` in
  `check-agent-policy.sh` and the two in `check-agent-calls.sh` are
  `LC_ALL=C` now, the `comm` calls included: `comm` requires both inputs
  collated the same way and answers nonsense rather than failing when
  they are not. The probe is the gate passing under `LC_ALL=en_US.UTF-8`
  **and** `LC_ALL=C`, and the previous list failing against a C-collated
  derivation.

  **And the gate now asks the question that does not depend on its own
  sort.** The population comparison cannot catch a repeat: un-pin the
  derivation and re-bless, and the two move together — green on the
  machine that blessed it, red on every other one. So the gate also
  asserts that the checked-in list *is in C collation order*, which is
  meaningful in every locale. A probe that re-sorted under a named
  second locale would not be: a runner without that locale falls back to
  C and passes for the wrong reason. Drilled by un-pinning the sort and
  re-blessing — the population check reports "261 declarations, exactly
  as the file says" and the collation check goes red beside it.

- **Five of `MM-EXEC-9a`'s seven under-approximations are closed, and
  the row the table never listed is now in it.** `docs/memory-model.md`
  said the inferred effect set is an under-approximation "in five
  measured ways" and that a conforming implementation SHOULD make it an
  over-approximation. Probed one at a time on 2026-08-25, that sentence
  was wrong in both directions.

  **One row was already closed and still listed.** A trait method whose
  implementation does I/O was documented as inferred effect-free "and so
  are its callers". It is not: the fixpoint unions every implementation
  of the method — which is what dynamic dispatch means — so a caller
  reports `#effects=IO`, and a call that dispatches to a *silent*
  implementation reports it too, because the set is a property of the
  method and not of one call site. Measured, not assumed.

  **Three were the same defect `__alloc` had been**, a primitive that
  PERFORMS something registered like `__load64`, which computes, and
  they are registered now: `__store8`/`__store64` as `Mut`,
  `__argc`/`__argv` as `IO`, the three arena primitives as `Alloc`.
  Each is chosen against a definition the reference already carried
  rather than invented for it — a field store *lowers to* `__store64`,
  and `Mut`'s whole definition is that a field store is visible through
  every alias while a `mut` local is not. `__argc` **broadens** `IO`
  from "reaches a `__syscallN`" to "reaches the outside world"; the
  reference's table is corrected rather than left to disagree.
  `__axiom_arena_mark` only reads the bump pointer and is
  over-approximated on purpose, which is what the rule's own SHOULD
  asks for.

  **And a seventh was found while closing them.** A `data` or `struct`
  constructor allocates and contributes nothing.
  `docs/error-model.md` had named that since it was written — "an
  under-approximation here in the sense `MM-EXEC-9a` already names" —
  and `MM-EXEC-9a` did not name it. It is a row there now, left open
  with its reason: `ERR-PROP-2`'s purity claim relies on the omission,
  so closing it is a decision about that rule and not a repair.

  Measured cost, and it discriminates rather than blankets — counted the
  way `check-agent-policy.sh` counts, one probe importing every module
  and 578 declarations listed: **216** carried an effect before and
  **261** after, and of the 431 arrow-typed ones **187** are still
  effect-free, down from 230. A diagnostic
  differential over every `.ax` in the tree moved exactly one file —
  `tests/stdlib/320-effect-gc-roots.ax`, whose `handle` list `AX3011`
  requires to be exhaustive, had to name `Mut` because `vecPush` stores
  — which is the check working.

  **And that differential was not enough, which is worth more than the
  result.** `scripts/check-recover.sh` builds its 100,000-abort probe
  from a heredoc, with a `handle` of its own; `println` reaches
  `__store64`, so that list needed `Mut` too, and no sweep over
  `tests/**/*.ax` could ever have seen it. It arrived as a red gate in
  the battery, which is the right place for it to arrive. **A gate that
  generates a program is a second corpus**, and an effect-inference
  change has to be measured against both. `__retain`/`__release` deliberately get
  nothing: their writes are the runtime's own bookkeeping, and `Mut`
  there marks every function that touches a reference.

  **A gate held the old definition, which is the best evidence here that
  the change is real.** `check-agent-calls.sh` walks the call graph and
  requires every inferred `IO` in the library to *reach* an origin — it
  said "a `__syscallN` or an `extern`, the only two things in this
  language that can perform one", which was the definition of `IO` until
  this commit. Nine rows failed it immediately and correctly: they
  perform IO and reach no syscall, because reading the command line is
  not one. The origin list is four now, and it is the same list
  `regFnEff` registers, so when one grows so does the other. And those
  nine — `sysArgc`, `sysArg`, `sysEnv`, `sysEnvp` and five helpers —
  carry `;@axiom:effect(io)` now, because `check-agent-policy.sh`
  requires every derived IO in the library to be a declared one. The
  reason is written once, above the argument-vector block, since a
  reader meeting that tag on `(pub fn (sysArgc) __argc)` will otherwise
  go looking for the syscall.

  `scripts/check-agent-policy.sh` asserts the mapping **one primitive at
  a time**, with `__load64`, `__load8` and `__retain` as controls that
  must report nothing. The population golden beside it cannot hold that
  rule: re-blessing an allow list after a regression makes the gate
  agree with whatever the compiler now says, which is what a golden is
  for and exactly why the rule needs an assertion that is not one. Seven
  of the eleven cases go red against the compiler built before this.

- **Two documents restated a fact and went stale, and one gate reported
  less the worse things got.** All three surfaced while closing
  `AX3040`'s second shape, and none of them is about types.

  `docs/error-model.md` reserved `AX3041` for `recursion-in-scrutinee`
  and called it "the next free semantic number". The parser has been
  emitting `AX3041` as `extern-library-name` since 2026-08-22, and
  `AX3044` is spent too. The sentence that was supposed to prevent this
  named the wrong comparison — "`check-doc-drift.sh` comparing
  constructed against listed" is a statement about `explain.ax` and
  reads that document not at all. Renumbered to `AX3045`; the gate now
  compares constructed against **proposed** as well, in the one
  direction that can fail, and the negative probe plants a spent number
  and watches it go red.

  `docs/agent-harness.md` called `tests/diagnostics/severity.policy` "an
  allowlist of the only five codes permitted to render as warnings" and
  named `AX3040` among them — one day after `AX3040` became an error and
  left that file. The `claim()` sweep recomputes *numbers* a document
  states and this one spells its number as a word; a count is the weaker
  half regardless, so the **set** is compared now, both directions,
  against the paragraph that quotes it.

  And `scripts/check-diverging-tyvar.sh` ran under `set -e` that it never
  asked for: `check_of` closed with `set -e` while the script's own
  header is `set -uo pipefail`, deliberately without `-e`, because every
  check reports and carries on. `set +e` was a no-op and `set -e` was
  not. Green, it cost nothing. Ablated — the variance flip removed — the
  gate found **13** failures, printed **2**, and died on a bare `grep`
  whose only job was to dump context for a failure it had already
  reported; 10 checks after it never ran. It reports all 13 of 27 now.

- **What an arena reset costs, gated — and the number the memory model
  stated was wrong.** `MM-LIFE-2a` sat in `docs/memory-model.md`'s
  open-issue table with its own diagnosis: every arena reset charges
  4,097 slab-head stores on the once-per-request path, "no gate
  measures it, and with the strategy withdrawn the cost belongs to no
  plan". The document went further at §5: "no gate anywhere in this
  repository compares a reset carrying the scrub against one without
  it ... not that the cost is unknown, but that nothing would notice it
  changing."

  That is the roadmap's **P8**, and it was ungated for a reason worth
  restating: every timing gate here asserts a RATIO, deliberately, so
  that a slow runner cannot fail it — and a rate is not a ratio. The
  way out is to make the rate a ratio anyway.
  `scripts/check-arena-reset-rate.sh` runs ONE program in three
  spellings a word apart — mark and reset, mark only, neither — so the
  cost is **attributed** rather than merely observed, and all three
  must answer the same number or they are not the same workload.

  Measured: a reset is **about 1.35 µs** and a mark under 10 ns, at
  `--opt 1` (what `axiom build` defaults to, and what `check-net.sh`
  builds the echo server at). Against the document's own 77 µs
  per-connection budget that is **1.7–1.8%**, not the "under one
  percent" it claimed — that figure was an ESTIMATE from a bench which
  ablates the whole reset rather than the scrub and whose two arms
  overlap. Both numbers are corrected in place.

  Two halves that are not a clock. The emitted IR is asserted directly
  — one store per iteration, bounded at 4,097, over a `[4097 x i64]`
  array — so the gate pins the *cause* and not only the symptom. And
  the negative probe deletes the `slabclear` block from the emitted IR
  and rebuilds with the same `llc` and `cc`, so the two binaries differ
  in the scrub and nothing else: the cost falls by **42×**, which is
  what makes "live is 45× noreset" a fact about the scrub rather than
  about two programs.

  The obvious design was refused, and the reason is worth recording: an
  "the reset is O(1) in live allocations" gate is **inverted**. 64
  allocations against 1 gives a ratio of 1.27 with the scrub and 11.69
  without — the 4,097 stores are the constant that makes the ratio flat,
  so that gate would go GREEN the moment the cost it defends was
  deleted.

- **`AX3040` is an error, and the compiler can now tell a diverging
  function from a cast.** It shipped as a WARNING on a stated ground:
  the rule conflated two signatures and only one of them is unsound.

  ```scheme
  (:: conjure (-> Int a))     ; body CASTS a word out
  (:: panic   (-> String a))  ; body NEVER RETURNS
  ```

  Measured on the tree before this landed: both check clean with the
  identical diagnostic, and then `conjure` exits **139** and `panic`
  runs correctly and exits **70**. A check that says the same thing
  about a segfault and a correct program is not yet a check, and
  promoting it as it stood would have refused the second — with help
  text telling that author to tag a diverging function `;@axiom:raw`,
  polluting the one enumeration that tag exists to keep exact.

  The analysis is exact rather than approximate, because the type
  system admits only two ways to produce such a result: a `cast`,
  which fabricates the value, or a call to another such function,
  which is the same question one level down. So the set splits by a
  **greatest fixpoint** over tail positions — assume they all diverge,
  strike out any whose tail can produce a value. Starting from
  "diverges" is what admits a self-call; starting from "returns" would
  never admit one and would refuse every diverging function there is.
  `sysExitWith` is the base case for "never returns", inherited by
  anything whose every tail reaches it (which is how `IO.exit` and
  `IO.die` qualify without being named), and a `cast` whose ARGUMENT
  never returns never returns either.

  That last arm is not a nicety: the repository's own control fixture
  spells its diverging `panic` as `(cast a (exit 70))`, so a rule that
  looked only at the head of the tail would have refused the program
  the fixture exists to protect. Two more arms came from writing the
  shapes out rather than reasoning about them — a block whose
  *statement* never returns, and an endless `while` — because the
  first version accepted six of the eight spellings and refusing the
  other two would have been the exact failure this promotion waited to
  avoid.

  **The second shape, closed the same day.** The rule asked whether the
  variable appears in a PARAMETER, and every left side of the arrow
  spine counted as one — including inside a function-typed parameter,
  where the callee still chooses the type. `(:: apply1 (-> (-> a Int)
  Int))` with `(fn (apply1 f) (f (cast a 42)))` drew **no diagnostic at
  all**, checked OK, and exited **139** — the same dereference through
  a positive occurrence one level in.

  The spine is split by **variance** now rather than by side
  (`sigSplitPolar`): a parameter is a position the caller fills, the
  left of an arrow *inside* it flips back to one the callee fills, and
  a variable with a produced position and no supplied one is
  unwitnessed wherever it sits. That arm has no fixpoint behind it,
  deliberately — `panic` is honest because a function that never
  returns never produced the `a` it promised, and `apply1` returns an
  `Int` perfectly well while fabricating on the way.

  **The two arms decide their overlap rather than subtract it, and the
  first version got that wrong.** A variable can be a callback's *and*
  the result's — `(-> (-> a Int) a)` — and the obvious way to keep one
  declaration from drawing two diagnostics is to subtract the result's
  variables from the demanded set. That reads as "the other arm has
  it", and the other arm does not always speak:

  ```scheme
  (:: divDemand (-> (-> a Int) a))
  (fn (divDemand f) { (f (cast a 42)) (cast a (exit 70)) })
  (divDemand strLen)
  ```

  `divDemand` **diverges**, so the returned-variable arm is honestly
  silent — `for all a` is the true type of a function that never
  returns. It hands `f` a fabricated `a` on the way to not returning,
  and a divergence that happens afterwards does not unmake the call.
  Measured: `check` OK, exit **139**, a second time in the same session
  and for a different reason than the first. The demanded arm now
  yields only when the arm above *actually reported the same variable*,
  which is two conditions and both are load-bearing:
  `(-> (-> a Int) b)` fabricates two different variables and draws two
  diagnostics.

  The corpus does not move: 19 signatures in this tree nest an arrow,
  the four with type variables in one — `(-> (-> a b) a b)` and
  `(-> (-> a a) a a)` — mention every variable on both sides, and a
  diagnostic differential over every `.ax` in the tree reports zero
  differences. Two shapes DO change, neither of which occurs here:
  `(-> (-> a Int) a)` is newly refused, and — with `Holder` a
  parameterised `data`, because an arrow may not be a type argument to
  anything else here — `(-> Int (Holder (-> a Int)))` is newly
  **silent**, which was a false positive: `a` is witnessed by whoever
  calls the callback `g` hands back. Both were run against the compiler
  before the change to confirm they were not already what they are now. What it over-approximates is asserted
  rather than left to be found: the rule reads the SIGNATURE, so
  `(fn (apply1 f) 0)`, which never calls its callback, is refused for a
  value it does not make. `axiom explain AX3040` says all of this too.

  Two arms could report one declaration twice, and do not: the demanded
  set subtracts the result's variables, so `(-> (-> a Int) a)` draws one
  diagnostic. They were also two sweeps, which made a file holding one
  of each report the LATER declaration first — nothing sorts
  diagnostics after the fact in this compiler — so they are one
  declaration-ordered sweep (`tyvarEmit`).

  **The first version cost 76% of a self-check; the shipped one saves
  17%.** Asking every signature about both arms is cheap — two walks
  over one type tree. Asking `rawTagged` or `findFnBody` about every
  signature is not: both reach `findFnDecl`, which scans the
  declaration list, so a pass that asks one of them per signature is
  O(n²) over ~2,400 declarations. `findFnBody` was the outer test,
  behind no guard: **0.852s → 1.352s** per `check` of
  `self_host/main.ax` (median of 7 interleaved runs).

  Putting the cheap test first lands at **0.560s** — *34% below the
  0.852s it started at* — and the reason is a second instance of the
  same mistake, which was already there. `&&` short-circuits (measured:
  a call in its right operand does not run), so the guard this replaced,
  `(&& (== (nodeTag d) TAG_D_SIG) (&& (== (rawTagged decls d) 0) ...))`,
  was asking `rawTagged` of every *signature* in the program before
  knowing whether there was anything to ask about — and `rawTagged`
  reaches `findFnDecl` too. About 2,400 scans of a 2,400-entry list, for
  an answer that is `no` for every declaration in this repository. A
  diagnostic differential over every `.ax` in the tree reports zero
  differences against the compiler before any of this, so the 34% is
  free.

  `scripts/check-diverging-tyvar.sh`, 26 checks. The probe that makes
  the acceptances worth anything changes ONE WORD in the accepted
  program — the `(exit 70)` a cast wraps becomes the literal `70` —
  and requires it to be refused. The diverging control moved out of the diagnostics corpus
  into `tests/selfhost/976-diverging-tyvar.ax`: once it
  stopped diagnosing anything, the diagnostics corpus refused it, and
  it was right to — the file now claims something about a *program*,
  not about a diagnostic.

- **The one script a stranger pipes into bash is gated.**
  `scripts/install.sh` fetches an archive and a checksum, compares
  them, unpacks, installs, and proves the result works by building a
  program that imports the standard library. Every one of those steps
  was written carefully; none had ever been executed by a gate.
  `scripts/check-install.sh` serves a release built from this tree over
  the loopback and asserts four things — a good release installs and
  the installed compiler runs; a tampered archive, a missing checksum
  file, and an archive with no `stdlib/` are each refused.

  The probe on the gate itself is the part that makes it evidence:
  `install.sh`'s checksum comparison is deleted in a COPY, and the
  tampered case must then stop being refused. A verification test that
  passes against an unverifying installer is testing something else.

  `install.sh` gained one seam for this, `AXIOM_BASE_URL`, and it is
  documented in that file as not being a back door: setting it takes
  the same access as setting `PATH`, and it changes only WHERE the
  archive comes from — the checksum file is still mandatory, the
  comparison still happens, and the protocol allow-list widens from
  `https` to `http,https,file` only when the variable is set.

- **A project can say what it depends on: `axiom.pkg`.** A dependency
  was a directory on `$AXIOM_PATH` — a real mechanism, and one that
  records nothing: the list lived in whoever's shell ran the compiler,
  it did not travel with the source, and two directories providing a
  module of the same name resolved first-wins by environment order,
  silently, with the loser's modules compiled against declarations from
  a package they had never named. That is the value-namespace twin of
  the type collision `AX3044` closed the day before, with the same
  failure mode: a wrong answer at exit 0.

  The manifest is line-based — `#` comments, `name`, `version`, and one
  `depend` per dependency directory, resolved against the manifest's
  own directory so the project relocates. It is looked for at or above
  the entry file's directory, bounded at eight levels. Each `depend`
  joins the search path after the entry file's own directory and before
  `$AXIOM_PATH`: a project still shadows a dependency with its own
  file, and a dependency the project DECLARED outranks one an
  environment variable happened to be carrying.

  **Two dependencies providing one module are refused**, before a byte
  is compiled, naming both files and the manifest — at the manifest
  rather than per-import, because the fault is in the configuration and
  reporting it only for the imports that happen to be ambiguous lets a
  program build today and stop building when somebody adds an import.

  There is no registry, no lockfile, no version constraint and no
  fetching, and `README.md` says so where a reader will look. Each is a
  policy decision that wants a maintainer, and a half-made one is worse
  than the mechanism it would rest on.

  `scripts/check-packages.sh`, 11 checks, every project built in the
  gate's own work directory and every module answering a distinct
  number so the exit status says which file was chosen. Its negative
  probe removes the manifest and requires the same program to stop
  resolving — without it, the positive checks could be measuring
  `$AXIOM_PATH`.

- **Go-to-definition reaches functions, types, and other modules.** It
  resolved a macro invocation to a macro declaration in the same
  document, and nothing else — so a call to a function three lines
  above answered `null`, which an editor renders as "there is nothing
  here" rather than as "this server does not do that". It now answers
  in two steps, in the language's own shadowing order: this document
  first, over every declaration kind `documentSymbol` already lists (a
  `fn`, a `data`, a `struct`, a macro), and then every imported module,
  jumping into that module's own file.

  The second step resolves the import graph, which `MAC-TOOL-3` was
  written to keep off the fast path — so it runs only when the first
  step misses, and nothing expands: the raw parse tree carries every
  declaration either lookup needs. `docs/macro-system.md`'s "v1 limit"
  paragraph, which predicted this cost and concluded against paying it,
  is corrected in place rather than deleted.

  New: `lspPathToUri`, the inverse of the `lspUriToPath` the server
  already had, percent-encoding the bytes a path may hold — an editor
  handed `file:///Some Project/a.ax` opens nothing, silently. The
  crash this found on the way is worth recording: unit 0 is the entry
  file and its module name is a null handle, so a unit walk that
  started at 0 asked `strEq` about null and took the server down with
  SIGSEGV. `symbols.ax`'s `saUnitOf` starts at 1 for that reason;
  `lspUnitOf` now says so.

  `tests/lsp/drive.py`'s navigation block now drives six requests
  instead of three, every position derived from the documents' own
  bytes, and the imported module is written to a temp directory rather
  than into `tests/lsp/` — a `.ax` file there joins the diagnostics
  sweep and needs a golden, and this one is the other side of a
  navigation rather than a diagnostics fixture.

- **The standard library has an API reference, and it is generated.**
  [`docs/stdlib-api.md`](docs/stdlib-api.md): every public name of
  every module — **417** of them — with its source-spelled type, the
  effect row the compiler derived, and the first paragraph of the
  comment above it. What existed before were two hand-written module
  tables, in `README.md` and `docs/reference.md`, which between them
  named a minority of the public surface, were read by no gate, and had
  already drifted apart: `docs/reference.md` called the `Err` macro
  `try` where the library spells it `try!`. That is corrected here too.

  The generator is **an Axiom program**, `examples/axdoc/axdoc.ax`,
  which is also this repository's first worked example of a real
  program rather than a fixture. It joins two sources because neither
  is sufficient: visibility is only in the SOURCE (`axiom symbols` has
  no `pub` field and emits no row for a macro, so an AXSYM-driven
  reference would print an `IO` with no `println` and be
  self-consistent about it), and the effect row is only in AXSYM,
  where it is a fixpoint over every body rather than a claim in a
  comment.

  `scripts/check-stdlib-api.sh` regenerates the document and requires
  byte-identity, then checks it against a name list `grep` derives from
  the sources — every `(pub` name exactly once — so a generator that
  dropped a module fails against a source outside itself rather than
  being re-blessed. It also asserts the three `Sys/Platform.*.ax` files
  declare the same 81 names, which is what makes carrying one of them
  in the reference safe, and carries a documentation-coverage ratchet
  at 290 of 417.

- **A shipped binary names the tree it was built from.** `axiom
  version` printed `axiom (self-hosted) 0.2.0` and nothing else, so two
  builds of two *different* trees at one version were the same binary
  to whoever held one — the half of the roadmap's P6 that
  `scripts/check-version.sh` has named in its own header since it was
  written. It now prints a **build id**: twelve hex characters of a
  hash over every `.ax` byte under `self_host/` and `stdlib/`, plus the
  commit and a `-dirty` flag when git can answer. The hash is the
  identity and the commit is the convenience, because a commit cannot
  distinguish two builds of one commit with an edit in the working
  directory and the hash can.

  The value is an ordinary string literal that
  `scripts/build-stamped.sh` rewrites **in a copy** of `self_host/`,
  never in the tree. The three alternatives were each priced and
  refused in `self_host/build.ax`: a compile-time environment read is a
  new built-in and therefore a seed window; a linker-injected symbol is
  an ungrounded `declare`, which `driver.ax` refuses at `AX4004` and is
  right to; stamping the archive answers for a release and not for the
  binary that outlives it. Because the rewrite happens in a copy and
  behind a script the ladder never runs, `check-bootstrap.sh` and
  `check-reproducible.sh` see nothing new — an unstamped build says
  exactly `unstamped`, which is not a value any stamped build could be
  confused with.

  `scripts/check-build-id.sh`, 12 checks, and the negative probe is
  the one that matters: one changed byte under `self_host/` or
  `stdlib/` must move the id, or the id names nothing. The release
  workflow now refuses to ship a binary reporting `(build unstamped)`.

- **The seed is the emission of source in this history, and here is the
  regeneration that says so.** `scripts/check-seed-provenance.sh`
  resolves the commit that last wrote the four seed files, requires that
  commit's `self_host/**.ax` and `stdlib/**.ax` to hash to
  `bootstrap/STAMP`, and then regenerates all four seeds from them and
  requires byte-identity: **139,638 lines each, on all four targets**.
  Until this, nothing in the repository related the 5 MB under
  `bootstrap/` to any source in either direction — `SHA256SUMS` is a
  hash and a file committed together, which is a corruption check by
  its own README's words, and `check-bootstrap.sh` asks only whether
  the seed can BUILD this source.

  It found that `bootstrap/STAMP` was **wrong, by construction rather
  than by accident**. It recorded `git rev-parse HEAD` from inside
  `reseed.sh`, and the routine reason to reseed is that `self_host/`
  has just changed — so the tree is dirty when it runs, and HEAD is the
  commit *before* the one that carries the seed. It named `ee0e4e1`;
  the seed is `93a74e5`'s emission, and regenerating from `ee0e4e1`
  differs by **1,532 lines** — the seed defines `parser$nodeBName` and
  `parser$nodeCName`, which that commit's source does not declare.
  Nothing read the line, so nothing said so. `STAMP` now records a hash
  of the source bytes, which cannot be wrong at the moment it is
  written, and the gate derives the commit the other way round.

  This does **not** answer Ken Thompson, and `bootstrap/README.md` says
  why at length: the compiler doing the regenerating is itself
  seed-descended. What it converts is a 5 MB artifact you had to trust
  into a build product of `.ax` files you can read.

- **`axiom test`, and assertions to write tests with.** A test is a
  top-level function whose name begins with `test` and which takes no
  parameters; the runner appends a `main` to the file's own bytes and
  arms one recovery point per test, so a failed assertion, an unhandled
  effect, an allocation failure and a division by zero each end ONE
  test and answer with a status (`docs/error-model.md` `ERR-REC-6` —
  this is that mechanism's first consumer, and it needed no new
  machinery). `stdlib/Test.ax` is the assertion surface: `assertEq`,
  `assertNe`, `assertStrEq`, `assertTrue`, `assertFalse`, `testFail`,
  and the `Assert` effect a failed one performs.

  Nothing is skipped in silence, which is a runner's characteristic
  defect: a file that declares no test is a failure rather than an
  empty success, and a `test`-named function that takes parameters is
  refused by name rather than passed over. The `;@axiom:test` AXTAG was
  tried first and refused for the same reason — a tag above the `::`
  signature is dropped when the `fn` carries one of its own, so
  `symbols` reports `#effect=io` and no `#test` at all (probed
  2026-08-25), and a test that vanishes because its tag sat one
  declaration too high reads exactly like a passing one.

  `scripts/check-test-runner.sh` is the gate, and its negative probe is
  the part worth the cycles: every `assertEq` in the passing fixture is
  mutated in turn and each mutant must exit 1 with a `FAIL` line — five
  observed red. It also checks the report against a list `grep` derives
  from the fixture's own bytes, so a runner that ran four of five tests
  fails against a source outside the compiler.

- **The containers own what they hold, and can be freed.** The shape
  word gained an **array form** — one bit saying every payload word of a
  block is a handle — which is the only encoding that can describe an
  element buffer: the record form's bitmap holds 47 words and `Intern`'s
  string vector is 64 words before a single string is interned.
  `vecNewRef`, `mapNewRefVals` and `internNew` own their elements;
  `vecFree`, `mapFree` and `internFree` hand them back, four levels deep
  (`docs/memory-model.md` `MM-LIFE-2h`;
  `tests/stdlib/404-container-reference-maps.ax` answers 255, eight
  probes at one bit each). Containers built and dropped in a loop with
  no arena reset now hold **1,360 KiB flat** where the same program one
  word different grows to 61,344 (`scripts/check-container-reclaim.sh`).
- **A bounded live set has bounded memory.** The acceptance property
  above that one, and the readiness plan's P3 stated so it can be
  falsified: a 256-entry window over **2,000,000** inserts holds 1,392
  KiB, unmoved across a hundredfold in iterations, against 34,368 KiB
  with the eviction removed (`scripts/check-steady-state.sh`,
  `MM-LIFE-2i`).

- **A dying program names the frames it died in.** Three pieces, none of
  them debug metadata: `"frame-pointer"="all"` on the module's one
  attribute group, a table of address-beside-name over every symbol the
  module defines, and a walker that resolves each return address at
  `ra - 1`. All emitted text, so `-g` is still never passed, there is
  still no `!dbg` anywhere, and the committed seed still compiles
  `self_host/` unchanged. An allocation failure now reads:

  ```
  axiom: out of memory (mmap failed)
  axiom: backtrace (most recent call first)
    at __axiom_out_of_memory
    at axiom_alloc
    at Mem$memAlloc
    at __axiom_user_main
    at main
  ```

  Cost, measured 2026-08-24 at `--opt 2` on darwin-aarch64: a
  hello-world binary goes 65,704 → 82,536 bytes, the compiler itself
  1,452,688 → 1,471,520 (+1.3%), and `axiom check self_host/main.ax`
  is unchanged at 0.51 s. `scripts/check-backtrace.sh` pins the whole
  trace byte for byte at `--opt 0`, cross-checks every name it prints
  against `nm` at every optimisation level, and ablates the attribute
  per target — it discriminates on all four.

  What it deliberately is not: line numbers. Function-level frames
  answer most of production triage, and a line table is the part that
  needs real debug records.

### Fixed

- **A ceiling that measured the library's size rather than the gap it
  named.** `check-agent-calls.sh` bounds the rowless trait-implementation
  edges — the open `symbols.ax` gap, where an impl method body gets no
  AXSYM row — at 12, with 4 measured. It counted EDGES, and an edge is
  one caller naming one implementation, so the number scales with how
  many functions call a trait method: `stdlib/Test.ax` arrived with six
  public assertions that each `println` a value, and 6 callers × 4
  `Show` implementations took it from 4 to 28 without the gap moving at
  all. The bound is now on DISTINCT rowless callees — 4, the four
  `Show#T#show` — which is the size of the gap rather than of the
  library. The edge count is still printed, because it is what a reader
  sees in the stream, and is no longer asserted.

- **The documented module search order was wrong, and it was wrong on a
  module the standard library ships.** `README.md` said "a module in
  the entry file's own directory always wins". Resolution is a ladder
  of SUFFIXES over a list of DIRECTORIES with the suffix as the OUTER
  loop, so a more target-specific file anywhere on the path beats a
  less specific one nearer the entry file. Measured 2026-08-25: a
  project's own `Sys/Platform.ax` loses to the standard library's
  `Sys/Platform.darwin.ax` — which is the mechanism that makes one
  `(import Sys.Platform)` resolve per target, and is not a bug. The
  whole order is now written out, in one place, and gated.

- **A 256-entry cache grew without bound.** `mapNeedsGrow` reads `used`,
  and `used` counts tombstones, so a table under insert-and-remove churn
  reached the load factor with a live set that had not moved and
  doubled itself for entries that did not exist: 256 live keys, roughly
  524,288 slots, 10 MB. `mapRehashCap` now rehashes at the same capacity
  when the live entries would sit at a quarter load or less, which drops
  every tombstone and grows nothing — 10,048 → 1,392 KiB. Every other
  gate in the tree was green across it, including the container gate,
  which frees its containers whole and never removes an entry from one.

- **The shared CI artifact was trusted on a stamp nobody could fail.**
  `scripts/build-shared-axc.sh` claimed the artifact equals a fresh
  build and checked it by calling one pure function twice in one
  process over an unchanged tree. It now builds the compiler a second
  time and compares the IR both emit for `self_host/main.ax` — 144,818
  lines, byte for byte. (Not the binaries: the macOS linker stamps a
  UUID into every Mach-O, so two builds of one source differ by ~11 KB
  no compiler chose.)
- **`AXIOM_AXC` pointing at a compiler with no stamp went green.**
  `gate_build_axc` treated "no stamp beside the artifact" and "a stamp
  that no longer matches" as one event, and both fell through to
  rebuilding. So `AXIOM_AXC=.axiom-bin/axiom` — a real, working, seed
  compiler — was silently ignored while every gate reported success,
  having quietly paid the build the variable was set to avoid. The two
  are now separated by what the stamp says: a stale stamp rebuilds (as
  `check-fmt.sh` requires, since it runs its inner gates against a copy
  of the tree), and an absent one is refused.
- **Three files stated three different counts of one countable fact.**
  How many gates call `gate_build_axc` was written down as seventeen,
  eighteen and nineteen across six places, none of them swept by
  `check-doc-drift.sh` because they live in `scripts/` and in the
  workflow. The answer is eighteen, and `check-gate-lib.sh` now
  recomputes it and refuses any of the six that says otherwise. It
  found its first drift while being written, in its own comment.

---

## 0.2.0 — 2026-08-24

The first tagged release. Thirty days of work by one author, and the
first time any of these numbers is something a stranger reads.

### What this is

A self-hosted, freestanding systems language. The compiler is written in
Axiom, compiles itself, and reproduces itself byte-for-byte; a clean
checkout builds it from `bootstrap/` with nothing but `llc` and a C
linker.

**Language.** Functions with curried signatures and exact return types ·
algebraic data types with struct variants and pattern matching ·
structs with mutable fields · traits with static dispatch · effects
with `handle` · lambdas and closures · `while` with `mut` locals ·
modules with `pub` visibility and selective import · a two-form macro
system with hygiene, declaration macros, and a closed `syntax/*`
compile-time query vocabulary.

**Runtime.** An `mmap`-backed bump allocator emitted by the backend, no
libc. Reclamation is the arena scope — `__axiom_arena_mark` /
`__axiom_arena_reset` — measured at **291× less memory** than the same
binary unscoped at ten thousand connections (`scripts/check-net.sh`,
run 2026-08-24: 512 KiB scoped against 149,328 KiB). The exact ratio
moves with the machine — the run recorded in that script's own header
reads 313× — so what the gate asserts is a **floor of 50×**, not either
number.

**Targets.** `darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`,
`linux-x86_64`. Three are executed in CI; **`darwin-x86_64` is
assembled and compared but never run** — no runner for it exists.

**Standard library.** Eighteen modules over the syscall primitives:
`Pre`, `Mem`, `Str`, `Utf8`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`,
`Path`, `IO`, `Show`, `Err`, `Json`, `Rpc`, `Job`, `Ffi`, `Agent.Tags`.
TCP sockets, readiness over `kqueue` *and* `epoll` behind one API, and
signals delivered into the event loop with no handler.

**FFI, both directions.** `extern` blocks bind Rust; `--emit-staticlib`
makes every `pub fn` a C symbol. Freestanding is tiered and measured: a
program with no `extern` imports **0** symbols, one bound to a `no_std`
crate also **0**, one bound to a `std` crate **188** — counted on
`darwin-aarch64`, which is the platform those three numbers are
literal on; the gate enumerates permitted symbols per platform rather
than forbidding all of them (`scripts/check-ffi.sh`).

**Tooling.** `build`, `check`, `run`, `emit-llvm`, `fmt`, `explain`,
`symbols`, `repl`, `lsp`, `version`. Diagnostics render as human text,
AXDL, or JSON; 57 codes, each constructed, explained and listed, gated
in both directions.

### Added in this release

- **`symbols --calls`** — the call graph the effect fixpoint already
  resolves, printed as `#calls=` beside `#effects=`. Gated by
  `scripts/check-agent-calls.sh` on four properties: no callee's effect
  escapes its caller, every inferred effect row carries an edge, every
  IO reaches a syscall or an `extern`, and the default stream is
  unchanged.
- **`VERSION` and `scripts/check-version.sh`** — one number, and a gate
  asserting that all eleven sites and the built compiler agree with it.
  Each site is named with the count it must yield, so a file that
  quietly stops stating the version at one of them is a failure rather
  than a smaller sweep, and the negative probe mutates every named file
  and requires every extractor to read the mutation back.
- **A release workflow and an installer** —
  `.github/workflows/release.yml` cuts a release when a `v*` tag is
  pushed, refusing to build until the tag, `VERSION` and the number the
  freshly built compiler prints are the same string; `scripts/install.sh`
  downloads an archive, verifies its SHA-256, and then compiles a
  program that *imports the standard library* through a bare-name
  `PATH` invocation before reporting success. Neither publishes a
  `darwin-x86_64` binary, because no runner has ever executed one.
  `CONTRIBUTING.md` has the procedure.
- **A shared compiler artifact for CI** (`AXIOM_AXC`) — thirty-four gates
  rebuild the same compiler; now one step builds it, and builds it
  twice to measure that the artifact emits the same IR as a fresh
  build. (Not the same *bytes*: the macOS linker stamps a UUID into
  every Mach-O, so two builds of one source differ by ~11 KB no
  compiler chose.) The cache is content-addressed, so an ablation of
  `self_host/` still invalidates it, and a path with no stamp beside it
  is refused rather than ignored. `scripts/check-gate-lib.sh` proves
  all three.

### Fixed

- **An installed compiler could not find its own standard library.**
  `argv[0]` is not `current_exe`, so a compiler found on `PATH` and
  invoked by its bare name — `export PATH=…/bin:$PATH`, then `axiom`,
  which is exactly what the installer sets up — resolved
  `<exe>/../stdlib` against the *working directory*. The first program
  a new user wrote that imported anything answered `AX5001 cannot
  resolve import IO` on a completely correct installation. The bare
  name is now resolved the way the shell resolved it: the first `PATH`
  entry holding a file of that name, and that entry only — resolving
  through *every* entry was the first attempt, and it let a compiler
  whose `stdlib/` had been deleted keep working against a different
  installation's. Gated in both directions by
  `scripts/check-driver.sh`, which installs a layout, resolves through
  it by bare name, and requires the same invocation to fail once
  `stdlib/` is removed.
- `netAccept` discarded the peer address and `bind` passed a literal
  addrlen, so IPv6 was impossible.
- An unhandled effect exited 71 in silence; a worker could vanish with
  nothing on stderr.
- A Rust panic and a division by zero both exited 72, so the two were
  indistinguishable by status.
- `+`, `-` and `*` wrap silently and had no checked counterpart;
  `addChecked` / `subChecked` / `mulChecked` now exist.
- `308-poll-readiness` asserted that two connects produce one poll wake
  carrying two events. No kernel promises that; it failed under load.

### Known limitations, stated plainly

These are measured, not suspected. They are why this is `0.2.0`.

- **No debug information.** No DWARF, no line tables, `-g` is never
  passed. A dying process yields an exit status and at most 35 bytes.
  A SIGSEGV yields nothing. (Since `0.2.0`: a trap now also prints a
  function-level backtrace — see Unreleased. Line numbers and SIGSEGV
  are still uncovered.)
- **No fault containment.** There is no unwinding and no `catch`;
  handlers are tail-resumptive. A fault's only containment is the
  worker process dying.
- **Types share one flat namespace.** Two modules declaring the same
  type name collide **silently**, and the collision reaches the answer.
  Measured 2026-08-24: two modules each declaring `(struct Point (x :
  Int) (y : Int))` and `(struct Point (y : Int) (x : Int))`, a
  constructor in the second building `(y=10, x=20)`, and `p.x` read
  back. `check` says `OK`; the program answers **10**, having read the
  first module's layout, where **20** is correct. Note that a *value*
  name collision is caught — two modules exporting the same
  constructor is `AX3014 ambiguous name` — so the hole is specific to
  the type namespace. This is the single worst defect in the release.
- **`AX3040` is a known unsoundness that ships as a warning.** It
  cannot yet be promoted, because it cannot tell an unsound cast from a
  legitimately diverging function
  (`tests/selfhost/976-diverging-tyvar.ax`, which lived in the
  diagnostics corpus as case 351 until the analysis landed and it
  stopped diagnosing anything).
- **Error handling is mid-migration.** `Err.ax` ships `Result`, but the
  standard library still signals failure with `-errno` sentinels at 84
  sites over 12 files, and a fallible call leaks the block it returns.
  Counted 2026-08-24, the way [docs/error-model.md](docs/error-model.md)
  §1.2 says to count them: `grep -cE "errno|sentinel|\(- 0 1\)"` across
  `stdlib/*.ax`.
- **No `axiom test`.** There is no test runner a consumer can use
  outside this repository. (True of `0.2.0`, and closed after it — see
  Unreleased.)
- **No package management.** Dependencies are `$AXIOM_PATH`, a
  colon-separated environment variable. No manifest, lockfile or
  registry.
- **No throughput or latency gate.** Every timing gate asserts a ratio,
  deliberately, to avoid runner flakiness — which leaves rate
  uncovered.
- **No Windows, containers, or musl story.**

### Compatibility

`0.2.0` makes no compatibility promise. Language constructs have been
*removed outright* rather than deprecated. Four of them refuse loudly:
`union`, `region` and `foreign` are `AX2004` naming what happened to
them, and `--gc` is a driver refusal that says the tracing collector
belonged to the retired Rust implementation.

Two do not, and saying otherwise would be the kind of claim this file
exists to avoid:

- `begin` is an ordinary `AX3001 undefined variable begin`. It names no
  replacement and reads like a typo rather than a removal.
- A **sized integer type is not refused at all**. `i32`, `u64` and the
  rest are lowercase, so this compiler reads them as *type variables*:
  `(:: f (-> u64 Int))` checks **OK** and silently generalises, and
  `(:: main i32)` is a warning about an unwitnessed type variable
  (`AX3040`) rather than a word about sized integers. A program ported
  from a language that has them compiles and means something else.

A deprecation policy and a compatibility gate over the symbol stream
are the next release's work; until they exist, pin a commit.
