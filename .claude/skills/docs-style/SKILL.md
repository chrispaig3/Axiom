---
name: docs-style
description: The house style for every Markdown page in this repository (README, the language reference, guides, specifications, design records, READMEs in subdirectories). Load it before writing or editing any .md file, before adding user-facing prose to a compiler message or `axiom explain` text, and before reviewing a documentation change. It covers the voice, page shapes, how to cite evidence, formatting, the CI gates that read prose, and the checker to run before committing.
---

# Writing Axiom's documentation

Axiom's website sets the tone: short, direct and warm, with no hype.
It shows a small program, says what to notice, and is upfront about
what isn't ready yet. Every page in this repository should sound like the
same people wrote it.

Keep one reader in mind: a capable programmer who is new to Axiom. They
want to get something working, understand why it works, and trust what
they read. Welcome them, respect their time, and never make them wade
through our internal history to find an answer.

## The voice

- **Talk to the reader.** Use "you" and "your program". Use "we" only
  for the project's own decisions ("we chose S-expressions because…").
- **Lead with what they can do.** Say what the feature is for, show a
  small example, then explain the details and the limits.
- **Keep it short.** One idea per paragraph, and usually no more than
  four sentences. Aim for sentences under 25 words, and treat 40 as a
  hard ceiling.
- **Use plain words.** Say "uses", "runs", "checks" and "rejects". Define
  a term the first time it appears on a page.
- **Be calm and confident.** State what is true. Don't argue with an
  imagined skeptic, and don't dress facts up.
- **Be upfront about limits, briefly.** For example: "Not yet: packages
  can't pin versions. Use a git URL and commit hash for now." Limits
  get one or two sentences, not a paragraph of drama.
- **Spell it British.** Write behaviour, colour, optimise, initialise
  and parameterised, as the website does. Identifiers, flags and quoted
  output keep their own spelling.

The website's lines show the target:

> Ship the binary. That's it. Your program compiles to a native
> executable, with its allocator included and direct calls to the
> kernel. No VM to provision. No garbage collector to tune.

> Find the problem. Keep moving. Get a precise location, a stable
> error code, and often a fix your tools can apply.

## What to cut

These patterns crept into our docs and made them hard to read. Remove
them when you touch a page.

| Pattern | Example | Instead |
|---|---|---|
| History in a present-tense page | "since 2026-08-15", "until then the formatter reserved…", "there were 350 such sites" | Describe what is true now. History goes in `CHANGELOG.md`. A removed feature gets one line saying what to use instead. |
| Gate narration for maintainers | "`check-x.sh` requires this sentence to be here", "stated here once", "this is the one copy" | Cut it from user pages. If contributors need to know a check exists, say so once in `CONTRIBUTING.md`. |
| Defensive emphasis | "deliberately", "on purpose", "not an afterthought", "named rather than left quiet", "and that is the point" | State the fact. If the reason matters, give the reason in one sentence. |
| "X, not Y" everywhere | "a contract, not a plan", "loud and wrong over quiet and absent" | Say X. Mention Y only if readers commonly expect it. |
| Shouting | "the type variables BIND", "String and Int are DISTINCT" | Plain case. Use *italics* for rare emphasis. |
| Bold lead-ins on every paragraph | "**One word each way.** Every Axiom value…" | Use a heading if it's a new topic, or nothing. Keep bold for the one thing a skimmer must not miss. |
| Chains of dashes and parentheses | "…the fiat — that unified them — is deleted (see …), and…" | Break it into two sentences. Never use a spaced hyphen ` - ` as a dash. |
| Measurement diaries | "Measured on 2026-08-23: `nm` listed both" | "`nm` on the result lists no C library symbols." Keep the fact, drop the diary. |
| Internals in a newcomer section | LLVM globals in the "Literals" section | A short *Under the hood* note at the end, or a link to the specification. |
| Throat-clearing | "Welcome! Whether you're…", "A friendly, comprehensive guide…", "This document describes…" | Open with what the page gives the reader, in one or two sentences. |

## Page shapes

**Guides** are pages people learn from: `README.md`, `docs/reference.md`,
`examples/README.md`, `docs/status.md`, the how-to guides
(`diagnostics`, `lsp`, `ffi`, `agent-harness`, `compatibility`) and
`CONTRIBUTING.md`.

1. The title, then one or two sentences on what the page gives the
   reader.
2. The shortest path to something working: a command, a program and
   its output.
3. The details, in the order a reader needs them, under task-shaped
   headings such as "Handle a missing value" or "Run the tests".
4. Limits, in a short section or a line under the feature.
5. *See also*: links to the next page to read.

**Specifications** are `memory-model.md`, `macro-system.md` and
`error-model.md`. Their numbered sections, rule identifiers
(`MM-ALLOC-9`), status markers (**H**, **P**, **R**, **W**, **B**) and
RFC 2119 keywords are the structure other code cites. Keep every rule,
its number and its marker exactly. Write each rule as a clear
statement, followed by its evidence. Start the page with a short
plain-language overview and a pointer to the matching reference
section for readers who don't need the full contract.

**Design records and proposals** are the `*-design.md` and
`*-proposal.md` pages, `docs/assurance/`, audits and ledgers. They
record a decision and the reasons for it. Keep their conclusions,
numbers and evidence, but write them in the same plain voice. A dated
audit keeps its date in the title. The rest of the page doesn't need
more dates.

## Evidence, quietly

Axiom's rule is that a claim is backed by something you can run. Keep
that, but make it a footnote, not the story. The website does this with
a small "proof" token under each claim, and the docs do the same.

- In a guide, end a section with one line when a test or check pins
  the behaviour:

  ```text
  Tested by `tests/stdlib/466-for-loop.ax`.
  ```

  Don't narrate the test's history. Don't cite more than two paths in a
  line.
- In a specification, each rule names its probe after the statement,
  as it does today. Rule identifiers stay. Dates of measurement go.
- Never cite a path you haven't checked exists.

## Mechanics

- **Headings** use sentence case: "Pattern matching", not "Pattern
  Matching". Keep the wording of a heading that anything links to (see
  *Anchors*).
- **Code**: use ```` ```scheme ```` for Axiom, ```` ```bash ```` for
  shell commands and ```` ```text ```` for output. Show what a program
  prints. Prefer small, complete programs over fragments. A block that
  declares `main` is compiled in CI, so run it first.
- **Fragments** that mention `main` but aren't whole programs take
  ```` ```scheme fragment ````. A block showing code the compiler
  rejects takes ```` ```scheme refused ````.
- **Links** are relative to the page: a page inside `docs/` links to
  `ffi.md`, and a page at the root links to `docs/ffi.md`. Link the
  first mention of another page, not every mention.
- **Anchors**: before renaming a heading, search the tree (the web
  sources included) for `page.md#anchor` and `${REF}#anchor`. Either
  keep the heading, add `<a id="old-anchor"></a>` above the new one, or
  update every link.
- **Lists** for three or more parallel items. **Tables** for reference
  data. Otherwise, write prose.
- **Numbers that go stale**, such as file counts, line counts and
  sizes, belong only in the sentences a gate recomputes. Don't add new
  ones.
- **Dashes**: prefer a full stop or a colon. An em dash (—) is fine now
  and then. A spaced hyphen ` - ` is never a dash.
- **No emoji**, except in the output of a program that prints one.

## The CI gates that read prose

Several gates read the documents themselves. A rewrite must keep them
green. The ones that bite most often:

- **Paths must exist.** Every `tests/...` path, every bare fixture name
  like `466-for-loop.ax`, every `docs/*.md` path and every relative
  link target (`scripts/check-doc-drift.sh`).
- **Negative claims about tests name a path.** A paragraph with "no",
  "nothing", "never", "cannot" or "only" followed closely by "fixture",
  "probe", "test case" or "corpus" must also contain a `tests/` or
  `scripts/` path. Reword it, or name the path.
- **Gated sentences stay.** These sentences are read by pattern:
  - README's `### Targets` section. Its `Supported: ` line, the phrase
    "executes what the compiler emits there", and the "executed by no
    runner" explanation. `docs/reference.md` repeats the list as
    `Supported targets: `.
  - The version banners `Axiom X.Y.Z - REPL` and `Axiom X.Y.Z (build`:
    one each in README, `docs/reference.md` and `docs/status.md`.
  - `SECURITY.md`'s "The supported release is **X.Y.Z**", its
    `Support window:` paragraph, and the `- **os-arch.** Not a
    supported target` bullet.
  - The numbers in "N lines of it", "N `.ax` files" and "N-case
    tree-shape corpus".
  - The one paragraph in `docs/agent-harness.md` containing "permitted
    to render as warnings", which lists exactly the codes in
    `tests/diagnostics/severity.policy`.
  - The `| AXNNNN | slug |` rows in `docs/error-model.md`, the `| 70 |`
    to `| 80 |` trap rows in `docs/memory-model.md`, and the
    `~~ID~~ | **CLOSED**` defect rows.
- **`docs/status.md` rows.** The feature column and the bold status
  column must match `web/src/data/content.ts` word for word. Every
  `**Complete**` row names a fixture that exists.
- **Generated blocks are copied byte for byte.** Blocks under
  `<!-- doc-gate:source -->` and `<!-- doc-gate:render -->` markers are
  re-rendered by the compiler and compared. `docs/stdlib-api.md` is
  written by `examples/axdoc/axdoc.ax`, so change the generator, never
  the page.
- **Rule identifiers** are defined once, as a line-start `**ID (M).**`
  or `| **I8** |`, and never renamed.
- **Every documented program compiles**, and delimiters balance in
  every Axiom block (`tests/docs/verify-doc-code.py`).
- **Examples are listed.** `examples/README.md` names every program in
  `examples/`, and README links to it.
- **New pages under `docs/`** must be added to `gate_prose_docs` in
  `scripts/lib/gate.sh`.

## Before you commit

```bash
./scripts/bootstrap-from-seed.sh --install .axiom-bin     # once, for --axiom
python3 scripts/lib/doc-style.py --axiom .axiom-bin/axiom path/to/page.md
AXIOM=$PWD/.axiom-bin/axiom ./scripts/check-doc-drift.sh
```

`doc-style.py` reports *errors*, which CI will also catch or which mean
a fact went missing, and *style* notes, which point at the patterns
above. Fix every error. Treat style notes as a reviewer's comments: most
deserve a fix, and a few are fine as they are.

When you are rewriting an existing page, compare it against the
original. The comparison lists every rule id, gated sentence and
generated block the new text lost, and every code or path it no longer
mentions:

```bash
git show HEAD:docs/reference.md > /tmp/before.md
python3 scripts/lib/doc-style.py --before /tmp/before.md docs/reference.md
```

Read the "no longer mentioned" list. Each entry should be something you
chose to cut, such as a history note, and not a fact the reader needed.
