#!/usr/bin/env bash
# The self-hosted language server, session by session, with no second
# compiler anywhere in the loop.
#
# WHAT THIS USED TO PIN. Half of this gate ran the Rust compiler. For
# every fixture it ran the Rust binary's `check --diagnostic-format ai`,
# parsed the AXDL line, converted stage0's 1-based CHARACTER column
# into the 0-based UTF-16 code unit LSP requires, and demanded the set of
# (severity, code, line, column) tuples the server published equal it.
# That was the half a `--bless` could not satisfy. The Rust compiler is
# being deleted, and a differential does not fail when its reference
# disappears - point `$axiom` at a self-hosted binary and every
# comparison becomes a compiler against itself: 7 fixtures swept, zero
# differences, exit 0, nothing tested. That is the failure mode this
# repository names most often, so the gate was rewritten rather than
# left to rot into agreement by mutual silence.
#
# WHAT IT PINS NOW. tests/lsp/drive.py runs one fixed session per
# fixture - lifecycle, didOpen, documentSymbol, hover, an unsupported
# request, didClose, shutdown, exit - and checks the result against a
# checked-in golden AND against two hand-maintained manifests plus the
# fixture's own bytes. Only the first of those is re-blessable.
#
# Beside the per-fixture sessions it drives three whole-document ones
# that are written INTO drive.py rather than read from `tests/lsp/`, so
# their positions cannot drift away from the text they describe: a
# generated 500-diagnostic document, an editing session that must not
# grow, and the LANGUAGE-FEATURE block - six `definition` requests,
# six `hover`s and three `completion`s over a document that imports a
# module written to a temp directory. That block is the one whose
# answers are all DERIVED: every expected range, every quoted
# declaration, every paragraph and every completion `detail` is
# computed from the two documents' own bytes, so no re-bless of any
# golden can satisfy it.
#
# Beside those run three multi-file blocks, also written into drive.py:
# SECTION DEP TESTS, where a dirty dependency's errors publish under
# the dependency's own URI with its secondary linked beside them, an
# opened-then-dirtied buffer keeps its own array through an importer's
# recheck, and closes, dropped imports and broken imports retract
# exactly what no open document covers; SECTION WS TESTS, where a
# bare `initialize` earns no registration, a capable one earns one
# `client/registerCapability` with four registrations whose reply
# earns no reply, and watched changes, creations, deletions and a
# rename converge every open importer with no keystroke; and a closed
# block inside SECTION NAV TESTS where references and rename reach
# two closed importers sorted by path while a stranger's own same
# spelling is nowhere. All compare whole publish sequences or edit
# maps for equality, so a publish too many, too few, or under the
# wrong URI fails.
#
# HOVER AND COMPLETION were widened on 2026-08-26 and the block grew
# with them. Hover used to answer for macros alone; it now answers for
# every declaration kind the outline lists, quotes a `fn` as its
# SIGNATURE, carries the comment paragraph above the declaration, and
# reaches into an imported module and names it. Completion is new.
# What each of those adds to this gate is a DERIVED obligation:
#
#   * the form text every hover must quote is CUT OUT of the document
#     that holds it, and the paragraph below the fence is recomputed
#     from the same lines with `; ` taken off - a second
#     implementation, in Python, of `lspFormText` and `lspDocComment`;
#   * every hover's `range` must be the WORD under the cursor, which
#     for an imported name is in a different file from the declaration
#     being quoted;
#   * a prefix-filtered completion's every label must start with the
#     prefix READ OUT of the document at the position sent, and
#     `helper`'s `detail` must be the type sliced from its own
#     signature;
#   * the menu offered to a document that does NOT parse must equal,
#     exactly, the head keywords extracted from the `kwEq name ...`
#     call sites in self_host/parser.ax - so the copy of that
#     vocabulary in self_host/lsp.ax is a checked claim rather than a
#     list that drifts. drive.py refuses to run if that extraction
#     yields fewer than 15 keywords, or if any derived form text or
#     paragraph comes out empty.
#
# AND, SINCE 2026-08-28, THE SWEEP at the end of this file: every
# request the server ADVERTISES in `initialize` - the list is derived
# from the capabilities, not written down - fired at every 97th byte
# and every scanner-breaking position of a real stdlib module, of the
# same module cut off mid-form, and of an empty document, with the one
# obligation an editor needs before any other: an answer to every id,
# no error, and a server still alive to say `shutdown`. It refuses to
# run under twelve advertised providers, and it FAILS on a capability
# key it does not know how to build a request for, so a feature added
# to lsp.ax and not to the sweep's table is a red gate rather than an
# untested promise. Dynamic registration is invisible to it by design:
# the sweep's `initialize` offers no workspace capabilities, so no
# `client/registerCapability` is sent and the byte stream stays
# golden-stable; the handshake and the five workspace notifications
# are driven in drive.py instead, against a live process.
#
#   GOLDEN-ONLY, and therefore exactly as strong as whichever compiler
#   last blessed it: the framed byte stream - framing, field order,
#   JSON escaping, message sequence, the `initialize` capabilities, the
#   -32601 body - and the `help:` paragraph after a diagnostic
#   message's first line.
#
#   NOT RE-BLESSABLE, because there is no field in either manifest a
#   wrong answer could be written into and `--bless` rewrites *.golden
#   only:
#
#     * every diagnostic of every fixture, as a sorted LIST of (LSP
#       severity integer, code, line, UTF-16 start, UTF-16 end, first
#       line of the message). Positions are recomputed in Python from
#       the fixture's bytes - `len(line[:col].encode("utf-16-le")) // 2`
#       - a second implementation, in another language, of the exact
#       quantity stage0 used to supply. tests/lsp/expected-diagnostics.txt
#       names each diagnostic by severity, code, an ANCHOR STRING the
#       source contains, and the message line it must render; it carries
#       no line and no column at all. A list and not a set, so a
#       document with three diagnostics is three obligations.
#     * every symbol of every fixture: name, SymbolKind, container and
#       selectionRange, against tests/lsp/expected-outline.txt, which
#       is total - a fixture with no rows must publish an empty outline.
#       The manifest gained a CONTAINER column on 2026-09-03, when the
#       outline learnt to nest, and drive.py flattens the server's tree
#       in document order to compare against it, so a member hung off
#       the wrong parent is as visible as a member that is missing.
#     * four invariants on every symbol of every document including the
#       6001-symbol generated one, needing no manifest: selectionRange
#       contained in range; a symbol that HAS children containing its
#       selectionRange STRICTLY; every child's range inside its
#       parent's; and the source sliced at selectionRange spelling the
#       symbol's own name. The second of those exists because the first
#       was satisfied by IDENTITY - measured 2026-09-03, range ==
#       selectionRange on 543 of 543 symbols over ten documents, so
#       only an ablation that made range SMALLER could reach it.
#     * every non-empty diagnostic range must SPELL the name its own
#       message quotes in backticks, read back out of the source at
#       exactly those UTF-16 units - the shape of
#       tests/tools/verify-axsym.py.
#     * THE EDITOR IS NOT SHOWN LESS THAN THE TERMINAL, added
#       2026-09-03. For every fixture, `$axiom check --diagnostic-format
#       json` is run beside the server and the two are compared: the
#       same diagnostics in the same order, every caret LABEL carried
#       into the published message, and every SECONDARY span published
#       as `relatedInformation` at the UTF-16 position drive.py converts
#       from the terminal's character offset. Nothing here is written
#       down, so nothing here can be blessed - and the assertion is
#       containment rather than equality, so the editor's side cannot
#       satisfy it by also saying nothing. Two floors over the whole
#       corpus keep it from going vacuous from below: at least 5 label(s)
#       and at least 1 related location, or drive.py exits without a
#       verdict. tests/lsp/090-related-spans.ax is the fixture that
#       supplies the second, and it is the only one that does.
#
# The one thing the deleted differential had that this does not is
# stage0's opinion about WHICH diagnostics a file deserves; the manifest
# carries that, and it was cross-checked against stage0 on 2026-08-08
# while both compilers still existed - 0 disagreements over all 7
# fixtures then present. That check is recorded in the manifest's
# header, because it cannot be repeated.
#
# NEGATIVE TESTS, re-run 2026-08-08 against this version of the gate.
# The hover and completion ablations are from 2026-08-26 and are at the
# end. Six ablations first. Each PATCHES self_host/lsp.ax in a scratch tree (never
# the real one), builds a server from it - six distinct binaries, sha256
# all different from the good one's 0cffc884 - RE-BLESSES every golden
# from that build so the golden half is green by construction, and then
# runs this whole script clean against the re-blessed tree. Every status
# below was captured with output redirected and `echo $?`, never through
# a pipe.
#
#   BYTE COLUMNS. `lspChar` returns `off - lineStartOf` instead of
#   walking UTF-16 code units. Caught before and still caught: 1 golden
#   rewritten, exit 1, 030-utf16-columns publishes 23 where the source
#   derives 20. That fixture's last line carries U+00E9 and U+1F600
#   inside a string literal before the anchor `zzz`, which therefore
#   sits at character 19, byte 23 and UTF-16 unit 20 - three different
#   numbers on purpose. drive.py refuses to run at all if no anchor in
#   the corpus has that property any more.
#
#   The next three all PASSED this gate as it stood on the morning of
#   2026-08-08 - "9 passed, 0 failed", exit 0, from a compiler that was
#   wrong about the language server's actual job. Each now fails:
#
#   SEVERITY 3. `lspSeverity` publishes Warning as LSP severity 3.
#   WAS exit 0, with the re-blessed golden reading `"severity":3` where
#   the checked-in one reads 2, because the driver projected everything
#   that was not 1 onto "W". NOW exit 1: 2 goldens rewritten, and both
#   070 and 080 report "published severities outside LSP Error(1) and
#   Warning(2): [('AX3039', 3)]". (It read `AX3010` until 2026-08-25,
#   when that code became an error and both fixtures were re-founded on
#   `AX3039` so a WARNING still existed anywhere in this corpus to
#   project.)
#
#   OUTLINE DESTROYED. `lspSymKind` always answers 12 AND every symbol
#   `range` is `(lspRange src 0)`. WAS exit 0, with 060-outline.golden
#   re-blessed to call an enum a Function and to publish a
#   selectionRange NOT contained in its range - the invariant
#   self_host/lsp.ax's own comment claims it satisfies. NOW exit 1:
#   7 goldens rewritten, 8 failures, the first being "symbol 'Color':
#   selectionRange (0, 6)-(0, 11) is not contained in range
#   (0, 0)-(0, 0), which the protocol requires", and the large-document
#   case fails the same way on 6001 generated symbols.
#
#   ONLY THE FIRST DIAGNOSTIC, message text corrupted. The publish loop
#   becomes `(while (&& (< i 1) (< i (vecLen ds)))` and every message is
#   prefixed "WRONG-EXPLANATION ". WAS exit 0: every fixture had exactly
#   one expected diagnostic, so a set comparison could not see a dropped
#   one, and the backtick check reads only the FIRST quoted name out of
#   a message, so arbitrary prose around it was free. NOW exit 1:
#   5 goldens rewritten, 6 failures.
#
# The last two ablations exist because the two above each break two
# things at once, and a gate must be shown to catch each one ALONE -
# otherwise the weaker assertion is carried by the stronger:
#
#   KIND ONLY. `lspSymKind` answers 12 for everything; every range and
#   selectionRange is left exactly as it was, so both manifest-free
#   symbol invariants are satisfied. Exit 1, 1 golden rewritten, and
#   exactly one failure, from the hand-written file:
#     FAIL 060-outline: outline is not what expected-outline.txt and
#          the source say
#          server:  [('Color', 12, ...), ('P', 12, ...), ...]
#          derived: [('Color', 10, ...), ('P', 23, ...), ...]
#
#   DROP ONLY. The publish loop stops after one diagnostic; message
#   text untouched. Exit 1, 1 golden rewritten, and exactly one
#   failure, from comparing counted lists rather than sets:
#     FAIL 080-many-diagnostics: count: server published 1, manifest
#          demands 3
#
#   FILTERED RUN. `check-lsp-selfhost.sh 010` used to disable all three
#   anti-vacuousness floors - `if not filt:` - and exit 0 having swept
#   one fixture. Measured now: exit 1, with the floors scaled to the
#   selection rather than skipped (1 derived position, 1 name-at-range
#   check, 6002 symbol names, all equalities) and a PARTIAL line saying
#   the status is 1 by construction, because a one-fixture sweep must
#   not read as "the gate passed".
#
# THE MANIFESTS THEMSELVES are what those assertions rest on, so
# gutting one is refused before any server starts. Measured, each exit
# 1 with no fixture run: a diagnostic manifest where every fixture
# expects exactly one diagnostic ("comparing lists is the same as
# comparing sets"); one with no anchor whose UTF-16 column differs from
# both the byte and the character column ("no run could tell the three
# encodings apart"); an outline manifest naming fewer than three
# distinct SymbolKinds ("a server that answered 12 to everything would
# pass").
#
# HOVER AND COMPLETION, nine more ablations, 2026-08-26. Each patches
# self_host/lsp.ax in a scratch tree, builds a server from it,
# re-blesses every golden from that build, and then runs this script
# clean. Every one exits 1, and each names its own thing:
#
#   HOVER FOR MACROS ONLY. `lspHover`'s first lookup goes back to
#   `lspFindMacroDecl` - the state it was in until 2026-08-26. 8
#   goldens rewritten, exit 1: "fn hover: request 10 answered null".
#
#   RANGE IS THE DECLARATION. `range` becomes `(lspRange dsrc (nodeSpan
#   d))` again. Exit 1: "macro hover: request 3 covered (3, 11)-(3, 20),
#   want the word at (14, 1)-(14, 10)" - the declaration is nine lines
#   above the word being read, and for an imported name it is in
#   another file.
#
#   NO PARAGRAPH. `lspDocComment`'s result is replaced by "". The fence
#   is untouched and every range still correct. Exit 1: "request 3 did
#   not carry 'A macro that derives a tag function.'".
#
#   NO PREFIX FILTER. `strStartsWith label prefix` becomes `(|| ...
#   true)`. Exit 1: "completion filtered on 'he' still offered
#   ['alloc', 'begin', 'cond', ...]".
#
#   ONE KEYWORD MISSING. `handle` is dropped from `lspKeywords`, which
#   is what a keyword the parser learns and this list does not looks
#   like. Exit 1, with both lists printed and `handle` absent from the
#   server's.
#
#   NO DETAIL. `lspComplDetail` answers "" for everything. Exit 1:
#   "request 15 offered 'helper' with detail None, want 'Int'".
#
#   UNBOUNDED MENU. `LSP_COMPL_MAX` raised to a million. Exit 1: "the
#   empty prefix menu carried 2075 item(s), over the 200" - from the
#   cost block, whose RATIO alone did not fail.
#
#   NO CLAMP. `lspClampLines` is taken off the fence. Exit 1: "clamped
#   hover: request 18 did not carry '; ...'" - the corpus carries a
#   47-line `data` for this, and drive.py refuses to run if that
#   declaration ever stops overrunning the 40-line clamp, because the
#   truncation check would then pass on an unclamped server.
#
#   NO EARLY GUARD - the one that is NOT caught, recorded because a
#   gate has to say what it does not hold. `lspComplWants` is removed
#   from `lspComplLocal`'s call site so a `detail` is built for every
#   declaration and discarded on the prefix. Measured 1.05x here and
#   1.65x at 6,000 declarations against a good build's 0.5-0.75x, both
#   inside the 2.00x ceiling, and this script exits 0. The reason is in
#   the cost block's own header.
#
# DECLARATION AND CALL HIERARCHY, five more ablations, 2026-08-31.
# Same method: each patches self_host/lsp.ax in a scratch COPY of the
# tree (never this one), builds a server from it, re-blesses all 8
# goldens from that build so the golden half is green by construction,
# and runs this script clean. Every one exits 1 with "31 passed, 1
# failed", and each names its own thing rather than printing two
# CallHierarchyItems side by side - `ch_brief` reports an entry as
# (function, file, the position of every call site) while the
# comparison stays against the whole structure.
#
#   DECLARATION IS DEFINITION. `lspDeclaration`'s `lspFindSig` step is
#   removed, so it answers what `definition` answers - the state this
#   server was in before 2026-08-31, and the state a "declaration is
#   just an alias" implementation would be in. Exit 1:
#     "declaration on a local `fn` (request 2) answered ... line 4,
#      character 9 ..., want ... line 2, character 8 ..."
#   - the `(pub fn (helper n)` where the `(pub :: helper` was asked
#   for. The check asks BOTH requests at that position and requires
#   the two ranges to differ, so an alias cannot satisfy it.
#
#   A CALL IS ANY MENTION. `lspChSites` stops requiring the occurrence
#   to be a HEAD (`lspNavLocalIndexHas heads ...` dropped), which is
#   what a call graph built from references alone would report - and
#   what `axiom symbols --calls` does report, by design, because it is
#   the effect walk's edge set. Exit 1:
#     "incoming calls to `helper` (request 100) answered [('caller',
#      'ChMain.ax', [(25, 23), (25, 34)]), ('handoff', 'ChMain.ax',
#      [(30, 20)])], want [('caller', ...)]"
#   `(fn (handoff z) helper)` names `helper` and never applies it.
#   drive.py refuses to run if ChMain.ax ever stops containing that
#   shape.
#
#   A LOCAL IS CALLABLE. `lspChCallable` answers true for a local key,
#   so a head is resolved by SPELLING rather than by what the scope
#   says it is. Exit 1:
#     "outgoing calls from `apply`, whose body's head is its parameter
#      (request 105) answered [('k', 'ChMain.ax', [(16, 21)])], want []"
#   - `(fn (apply k v) (k v))` calls its own parameter, and ChMain.ax
#   declares a top-level `k` for exactly this. drive.py refuses to run
#   if that shadowing pair leaves the document.
#
#   NO GROUPING. `lspChGroupPush` never finds an existing group, so
#   every call site becomes its own entry - which is what a client
#   draws as two callers. Exit 1:
#     "incoming calls to `helper` (request 100) answered [('caller',
#      'ChMain.ax', [(25, 23)]), ('caller', 'ChMain.ax', [(25, 34)])],
#      want [('caller', 'ChMain.ax', [(25, 23), (25, 34)])]"
#
#   `[]` INSTEAD OF null. `lspIncomingCalls` answers an empty list
#   where it cannot reach the item's document or the item names no
#   `fn`. Exit 1:
#     "an item nothing declares (incoming) answered [], want null -
#      `[]` would claim the function has no callers, which a server
#      that cannot read the file has not earned"
#   This is the one ablation that produces a plausible answer rather
#   than a wrong one, which is why it has a check of its own.
#
# CONSTRUCTORS, seven more ablations, 2026-09-03. A constructor was a
# name five requests could see and three could not: `completion`
# offered it, `references` found it, `signatureHelp` rendered it,
# `workspace/symbol` listed it at its own span and `typeDefinition`
# jumped to its `data`, while `definition`, `declaration` and `hover`
# answered null on the same character - 116 such occurrences over four
# real files, measured 2026-09-03.
#
# THESE SEVEN TOUCH NO GOLDEN, and that is worth saying rather than
# leaving to be noticed: the constructor block's requests are written
# INTO drive.py's navigation session, not read from tests/lsp/, so
# there is no *.golden a bless could satisfy and none of these runs
# rewrote one. Each patches self_host/lsp.ax in a scratch copy, builds
# a server with scripts/build-shared-axc.sh, and runs drive.py against
# the UNBLESSED goldens. Every one exits 1 with "33 passed, 1 failed"
# and exactly one FAIL line, which is also the proof that the change
# moved nothing else.
#
#   NO LOCAL STEP. `lspCtorDefinition`'s call site is removed from
#   `lspDefinition`, so it falls straight through to the imported
#   lookup - the state this server was in until today. Exit 1:
#     "FAIL nav-constructors: definition on `Circle` as a pattern
#      head: request 40 answered null"
#
#   THE `data`'S SPAN, NOT THE CONSTRUCTOR'S. `lspCtorDefinition`
#   answers `(nodeSpan dat)` where it answered `(nodeSpan c)`. This is
#   the one that says the fix landed on the right WORD rather than
#   merely inside the right declaration, and NavMain.ax declares
#   `Shape` and `Circle` on one line on purpose so a wrong answer
#   differs only in column. drive.py refuses to run if that line is
#   ever split. Exit 1:
#     "request 40 answered ... character 10 ... to ... 15 ..., want
#      ... character 23 ... to ... 29 ..."
#   - `Shape` where `Circle` was asked for.
#
#   NO IMPORTED HALF, `definition` alone. The `data` an import brought
#   in is skipped in `lspDefinitionImported`. Exit 1 on the OTHER
#   document alone, with every local assertion still green:
#     "definition on the imported `Circle`, from NavUser.ax: request
#      43 answered null"
#
#   NO NOTE. `lspCtorNote` answers "". The fence is untouched and the
#   paragraph still there, so the hover is a plausible answer rather
#   than an empty one - it quotes `(pub data Shape ...)` and never
#   says which of its two constructors the cursor is on. Exit 1:
#     "hover on `Circle`: request 46 did not carry 'constructor
#      `Circle` of `Shape`'; it answered '```axiom\n(pub data Shape
#      (Dot) (Circle Int))\n```\n\nA shape with two constructors...'"
#
# The last three exist because "the imported half" is four halves, and
# a gate must be shown to catch each ALONE or the weaker assertion is
# carried by the stronger. Each drops ONE request's imported step:
#
#   HOVER.          "hover on the imported `Circle`, from NavUser.ax:
#                    request 47 answered null"
#   TYPEDEFINITION. "typeDefinition on the imported `Circle`, which is
#                    `Shape`: request 45 answered null"
#   DECLARATION.    "declaration on the imported `Circle`, from
#                    NavUser.ax: request 44 answered null"
#
# WHAT NO ABLATION ABOVE PRODUCES, and is asserted structurally
# instead: `declaration` answering something OTHER than `definition`
# on a constructor (they are compared to each other, since a
# constructor is written once), and `typeDefinition` answering the
# SAME range as `definition` (they are compared for inequality, since
# one is the constructor and the other is the `data`). An
# implementation that aliased either pair fails without any patch.
#
# DIAGNOSTIC FIDELITY, four more ablations, 2026-09-03. `lspDiagJson`
# published range/severity/code/source/message and dropped the two
# fields the terminal shows at the caret: the primary LABEL (215 of the
# 422 diagnostics in tests/diagnostics carry one) and the SECONDARY
# spans (32 do). `axiom check` on a duplicate `main` names and points at
# the first definition; VS Code said "duplicate definition `main`" and
# pointed at nothing.
#
# Each of these patches self_host/lsp.ax in a scratch copy, builds a
# server, re-blesses all 9 goldens FROM THAT BUILD into a scratch copy
# of tests/lsp/ so the golden half is green by construction, and runs
# drive.py clean against it. All four exit 1.
#
#   NO RELATED. `lspDiagRelated`'s result is replaced by an empty
#   array, which is a legal LSP answer and the state this server was in
#   until today. 9 goldens rewritten, "35 passed, 1 failed":
#     "FAIL diagnostic-fidelity: 090-related-spans.ax: AX3006 published
#      0 related location(s) and the terminal derives 1"
#
#   THE PRIMARY SPAN. The related range becomes `(diagSpan d)` - the
#   right COUNT at the wrong PLACE, which is the answer a client would
#   render as a link back to the squiggle you are already on. This is
#   the one that makes the ablation above non-carryable. Exit 1:
#     "published 1 related location(s) and the terminal derives 1: ...
#      line 14 ... against ... line 10 ..."
#
#   NO LABEL. The label is dropped from `lspDiagText` again. Exit 1 on
#   the FIRST fixture that has one, not on the fixture written for
#   this:
#     "020-undefined.ax: AX3001 - the terminal prints the label 'no
#      binding named `nosuch` in scope' at the caret and the editor's
#      message does not carry it"
#
#   NO NULL GUARD, and this one is not hypothetical - it is what the
#   change did on its first build. A diagnostic with no label carries 0
#   rather than an empty String (render.ax's own header records the
#   same trap, found there 2026-08-16), so reading `strLen` off it
#   takes the server down. Exit 1 with only 7 of 9 goldens written:
#     "FAIL 070-warning-only: server exited -11"
#     "FAIL 080-many-diagnostics: server exited -11"
#   Both fixtures carry an AX3039 with no label. The gate found this
#   before any of it was committed.
#
# AND THE FLOOR ITSELF, checked the way the manifest floors are: run
# against a tests/lsp/ with 090-related-spans.ax removed (and the
# fixture floor lowered to 8, so the earlier refusal does not mask it),
# drive.py exits without a verdict - "no fixture in tests/lsp produces
# a diagnostic with a secondary span, so the relatedInformation
# comparison below would be two empty lists on every fixture".
#
# THE OUTLINE'S EXTENT AND ITS NESTING, five more ablations,
# 2026-09-03. `documentSymbol` published `range` equal to
# `selectionRange` - the declaration's NAME - for every symbol, and no
# `children` at all, so `workspace/symbol` listed a `data`'s
# constructors at their own spans while the outline of the same file
# showed neither them nor a `struct`'s fields, and an editor's
# breadcrumb, sticky scroll and expand-to-symbol had four characters to
# work with. The header comment claimed the extent needed "spans this
# parser does not record"; hover has recovered it from the bytes since
# 2026-08-26.
#
# Same method as the four above: patch a scratch copy, build, re-bless
# all 9 goldens into a scratch tests/lsp/, run drive.py clean.
#
#   NO EXTENT. `lspSymbolExtent` always answers 0, which is the state
#   the outline was in until today - the name span, and no children,
#   because a fallback range cannot contain one. Exit 1, "35 passed, 2
#   failed": the manifest comparison ("outline is not what
#   expected-outline.txt and the source say") and the extent block.
#
#   CHILDREN WITHOUT THE EXTENT. `range` goes back to the name span
#   while `children` are still published - a protocol violation the
#   OLD containment check could not see, because range and
#   selectionRange were equal everywhere. Exit 1:
#     "FAIL 060-outline: symbol 'Color' has 2 child(ren) and its range
#      (0, 6)-(0, 11) is exactly its selectionRange, so it cannot
#      contain any of them"
#   This is the one that says the strengthened invariant earns its
#   place.
#
#   ONE KIND FOR EVERY MEMBER. `lspMemberKind` answers EnumMember for
#   a `struct` too, so fields and constructors are indistinguishable.
#   Exit 1 with exactly one failure, from the hand-written manifest -
#   the CONTAINER column is satisfied and the kind column is not, which
#   is what that column is for.
#
# The last two are the extent GUARD, and they are separate because it
# refuses two different fallbacks for two different reasons. Both are
# exercised on documents drive.py writes itself, since `axiom fmt`
# would take an indented top-level declaration out of any fixture:
#
#   NO CONTAINMENT TEST. An indented `fn` after a top-level form takes
#   the PRECEDING form's range - one that ends two lines before the
#   declaration starts. Exit 1: "the INDENTED `fn` in A got range
#   (0,0)-(2,10) ... must fall back to its name span (4,7)-(4,15)".
#
#   NO HEADER TEST. An indented `fn` with nothing at column zero takes
#   its own PARAMETER LIST as its form - `(only y)` - which CONTAINS
#   the name and passes the containment test on its own. Exit 1: "the
#   INDENTED `fn` alone in B got range (0,6)-(0,14) ... must be the
#   name span (0,7)-(0,11)".
#
#   AND THE THIRD DOCUMENT IS THE ONE NEITHER MAY BREAK: an indented
#   `struct` keeps its whole form and its field as a child, because its
#   name is not inside a parameter list and the nearest opener IS its
#   own form. A guard aimed at indentation rather than at that one
#   shape fails there.
#
# THE COST of widening the range: `lspFormEnd` scans each form
# forward, so the outline became O(document) rather than O(symbols).
# The ratio block below is what watches it - measured 0.48x before and
# 0.64x after on the same 2,051-symbol document, against a 2.00x
# ceiling.
#
# AND ONE THE GATE CAUGHT WITHOUT BEING ASKED, recorded because it is
# the sweep's whole purpose: adding `declarationProvider` to
# `lspCapabilities` before adding it to the sweep's table below failed
# the run - "FAIL capability 'declarationProvider' is advertised and
# this sweep does not know how to exercise it - add it to the table,
# or a capability nothing tests ships". A capability advertised and
# unswept is a red gate, not a silent promise.
#
# The keyword extraction's floor was checked the same way the manifest
# floors are: run against a parser.ax carrying two `kwEq` sites,
# drive.py refuses before any server starts - "derived only 2 head
# keywords ... an equality against a list this short asserts nothing".
#
# RESTORED, this tree, same day: exit 0. 10 passed, 0 failed, 8
# fixtures + 2 generated; 7 positions derived from source, 7
# name-at-range checks, 6015 symbol names read back out of the source,
# discriminating on 030-utf16-columns:zzz. With hover and completion:
# 13 passed, 0 failed.
#
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh 080      # one, exits 1
#
# Blessing does NOT skip the derived checks: a bless from a broken
# compiler prints its failures in the same run that wrote the goldens.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"

# The server under test is built FROM SOURCE by `$axiom`, not `$axiom`
# itself: this gate exists to watch self_host/, and `$axiom` may be an
# older seed-descended binary that predates the change being tested.
gate_build_axc stage1

# `.axbad` is the deliberately-unparseable fixture; it is not `.ax`
# because check-fmt.sh and check-tree-sitter.sh sweep every `*.ax` file
# in the repository and require all of them to parse.
fixtures=$(find tests/lsp \( -name '*.ax' -o -name '*.axbad' \) | wc -l | tr -d ' ')
# A sweep that quietly shrinks is the failure mode this floor exists
# for: a glob that stops matching removes fixtures while the gate goes
# on reporting the silence it was looking for.
floor=9
if [[ "$fixtures" -lt "$floor" ]]; then
  echo "FAIL: only $fixtures LSP fixtures found, expected at least $floor" >&2
  echo "      (a gate that reads fewer files than it should reports success it has not earned)" >&2
  exit 1
fi

# The two manifests are the half no re-bless can satisfy. If either is
# missing the gate is only a golden comparison, which is worth saying
# out loud rather than discovering later from a green run.
manifest="tests/lsp/expected-diagnostics.txt"
outline="tests/lsp/expected-outline.txt"
for f in "$manifest" "$outline"; do
  if [[ ! -s "$f" ]]; then
    echo "FAIL: $f is missing or empty - without it this gate is a golden" >&2
    echo "      comparison and nothing else, and a bless would satisfy all of it" >&2
    exit 1
  fi
done
rows=$(grep -cE '^[^#[:space:]]' "$manifest")
if [[ "$rows" -lt 6 ]]; then
  echo "FAIL: $manifest has $rows rows, expected at least 6" >&2
  exit 1
fi
orows=$(grep -cE '^[^#[:space:]]' "$outline")
if [[ "$orows" -lt 10 ]]; then
  echo "FAIL: $outline has $orows rows, expected at least 10" >&2
  exit 1
fi

args=("$work/stage1" "$repo_root/tests/lsp")
if [[ "$bless" == "1" ]]; then
  args+=("--bless")
fi
if [[ -n "$filter" ]]; then
  args+=("$filter")
fi

# Run it directly, not through a pipe: `... | tail` reports TAIL's exit
# status, which has made a failing gate in this repository read as
# green more than once.
python3 tests/lsp/drive.py "${args[@]}"
status=$?

echo "swept $fixtures fixtures (floor $floor), $rows manifest rows, $orows outline rows"

# ------------------------------------------------------------------
# The outline's COST, as a ratio rather than a stopwatch.
#
# Everything above pins what the server answers; nothing pinned what it
# spends. `lspPos` used to answer both halves of a position by scanning
# the document from byte 0 - `lineOf` counts newlines from 0 and
# `lspChar`'s `lineStartOf` rescans to find the line start - and
# `lspRange` calls it twice per symbol, so an outline cost four
# whole-document scans per symbol. Measured before the line index:
# `documentSymbol` on `self_host/typecheck.ax` took 0.166 s against
# 0.042 s for the entire `didOpen` that parses and checks the same file,
# and 2.22 s at 8,002 symbols against 0.20 s.
#
# The assertion is a RATIO of two measurements taken here, on the same
# machine, in the same run: the outline request must not cost more than
# the whole parse-and-check of the same document. `didOpen` does strictly
# more work, so a correct index makes this comfortable (measured ~0.02x)
# and the quadratic makes it impossible (measured ~11x). An absolute
# millisecond ceiling would be a machine-speed assertion wearing a
# performance costume.
#
# And it proves the work happened before it reports the number, because
# a server that answers no symbols is extremely fast: the outline must
# carry at least $sym_floor symbols or this section fails rather than
# passes.
# ------------------------------------------------------------------
sym_floor=2000
perf=$(SERVER="$work/stage1" SYM_FLOOR="$sym_floor" python3 - <<'PY'
import json, os, subprocess, sys, time
server=os.environ["SERVER"]; floor=int(os.environ["SYM_FLOOR"])
n=floor+50   # one TAG_D_FN symbol per function; the `::` lines are not symbols
text="".join(f"(:: f{i} (-> Int Int))\n(fn (f{i} x) (+ x {i}))\n" for i in range(n))
text+="(:: main Int)\n(fn (main) 0)\n"
uri="file:///tmp/axiom-lsp-perf/big.ax"
def frame(o):
    b=json.dumps(o).encode(); return b"Content-Length: "+str(len(b)).encode()+b"\r\n\r\n"+b
base=[frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":None,"rootUri":None,"capabilities":{}}}),
      frame({"jsonrpc":"2.0","method":"initialized","params":{}}),
      frame({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"axiom","version":1,"text":text}}})]
tail=[frame({"jsonrpc":"2.0","id":9,"method":"shutdown","params":{}}),frame({"jsonrpc":"2.0","method":"exit","params":{}})]
ds=[frame({"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":uri}}})]
def best(msgs):
    b=None; out=None
    for _ in range(3):
        t0=time.time()
        p=subprocess.run([server,"lsp","--no-banner"],input=b"".join(msgs),capture_output=True,timeout=600)
        dt=time.time()-t0
        if p.returncode!=0:
            print(f"FAIL server exited {p.returncode}"); sys.exit(1)
        if b is None or dt<b: b=dt;
        out=p.stdout
    return b,out
t_open,_=best(base+tail)
t_all,out=best(base+ds+tail)
syms=out.count(b'"selectionRange"')
if syms < floor:
    print(f"FAIL the outline carried {syms} symbols, floor {floor} - a server that")
    print(f"     answers nothing is fast, so the ratio below would mean nothing")
    sys.exit(1)
cost=max(t_all-t_open, 0.0)
ratio=cost/t_open if t_open>0 else 0.0
print(f"outline {syms} symbols: didOpen {t_open:.3f}s, documentSymbol {cost:.3f}s, ratio {ratio:.2f}x")
if ratio > 2.0:
    print(f"FAIL documentSymbol cost {ratio:.2f}x the whole parse-and-check of the same")
    print( "     document, over a ceiling of 2.00x. The line index is what keeps this")
    print( "     under one - see lspLineIndex in self_host/lsp.ax.")
    sys.exit(1)
PY
)
perf_status=$?
echo "$perf"
if [[ "$perf_status" -ne 0 ]]; then
  status=1
fi

# ------------------------------------------------------------------
# COMPLETION'S COST, as the same kind of ratio, on the same document.
#
# `textDocument/completion` is a per-KEYSTROKE request - more so than
# the outline, which a client asks for once per open - and it does the
# most expensive thing this server knows how to do: parse, resolve
# every transitive import, and then, for each item it accepts, walk the
# declaration list for that name's signature.
#
# The assertion is the outline's, at two positions: an EMPTY prefix,
# where nothing is filtered out and the menu is as long as it ever
# gets, and a FILTERED one two characters into a name, which is what a
# client actually sends while someone types. Neither may cost more than
# the whole parse-and-check of the same document, which `didOpen` does
# anyway on the same keystroke.
#
# WHAT THIS RATIO CATCHES AND WHAT IT DOES NOT, measured 2026-08-26 on
# the 2,050-declaration document below, best of three, against builds
# from a patched scratch tree:
#
#   * AN UNBOUNDED MENU. `LSP_COMPL_MAX` raised to a million: the
#     request carried 2,075 items, and the cap check below fails - "the
#     menu carried 2075 item(s), over the 200 LSP_COMPL_MAX says it
#     sends". The RATIO alone did not fail, which is why the count is
#     asserted beside it.
#   * A SERVER THAT ANSWERS NOTHING. The item floor, for the reason the
#     outline has one: an empty menu is instant, so a ratio taken
#     without it would be a measurement of nothing.
#
#   NOT CAUGHT, and said out loud rather than left to be discovered:
#   building a `detail` for every declaration and discarding it on the
#   prefix - the quadratic `lspComplWants` exists to avoid. Removing
#   that guard measured 1.05x here and 1.65x at 6,000 declarations,
#   both inside this ceiling; the good build measures 0.5-0.75x. Both
#   requests are dominated by ONE PARSE of the document, which every
#   request in this server pays and which no ceiling can go below, so
#   there is no wall-clock threshold that separates the two builds
#   without flaking. The guard is held by the comment on it and by
#   review, not by this number.
# ------------------------------------------------------------------
item_floor=100
item_cap=200
cperf=$(SERVER="$work/stage1" ITEM_FLOOR="$item_floor" ITEM_CAP="$item_cap" python3 - <<'PY'
import json, os, subprocess, sys, time
server=os.environ["SERVER"]
floor=int(os.environ["ITEM_FLOOR"]); cap=int(os.environ["ITEM_CAP"])
n=2050
text="".join(f"(:: f{i} (-> Int Int))\n(fn (f{i} x) (+ x {i}))\n" for i in range(n))
text+="(:: main Int)\n(fn (main) 0)\n"
uri="file:///tmp/axiom-lsp-perf/big.ax"
def frame(o):
    b=json.dumps(o).encode(); return b"Content-Length: "+str(len(b)).encode()+b"\r\n\r\n"+b
base=[frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":None,"rootUri":None,"capabilities":{}}}),
      frame({"jsonrpc":"2.0","method":"initialized","params":{}}),
      frame({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"axiom","version":1,"text":text}}})]
tail=[frame({"jsonrpc":"2.0","id":9,"method":"shutdown","params":{}}),frame({"jsonrpc":"2.0","method":"exit","params":{}})]
# The last line is `(fn (main) 0)`. Column 1 is just past `(`, so the
# prefix is empty; column 8 is three characters into `main`, which is
# the shape a client sends between keystrokes.
last=len(text.split("\n"))-2
def cm(line,ch):
    return frame({"jsonrpc":"2.0","id":3,"method":"textDocument/completion",
                  "params":{"textDocument":{"uri":uri},"position":{"line":line,"character":ch}}})
def best(msgs):
    b=None; out=None
    for _ in range(3):
        t0=time.time()
        p=subprocess.run([server,"lsp","--no-banner"],input=b"".join(msgs),capture_output=True,timeout=600)
        dt=time.time()-t0
        if p.returncode!=0:
            print(f"FAIL server exited {p.returncode}"); sys.exit(1)
        if b is None or dt<b: b=dt; out=p.stdout
    return b,out
def menu(out):
    i=0
    while True:
        j=out.find(b"\r\n\r\n",i)
        if j<0: return None
        hdr=out[i:j].decode("utf-8","replace")
        cl=[l for l in hdr.split("\r\n") if l.lower().startswith("content-length")]
        if not cl: return None
        ln=int(cl[0].split(":")[1]); m=json.loads(out[j+4:j+4+ln]); i=j+4+ln
        if m.get("id")==3: return (m.get("result") or {}).get("items")
t_open,_=best(base+tail)
bad=0
for what, ch, want_floor in (("empty prefix", 1, floor), ("filtered", 8, 1)):
    t_all,out=best(base+[cm(last,ch)]+tail)
    its=menu(out)
    if its is None:
        print(f"FAIL the server answered no completion result at the {what}")
        bad=1; continue
    if len(its) < want_floor:
        print(f"FAIL the {what} menu carried {len(its)} item(s), floor {want_floor} - a")
        print( "     server that answers nothing is fast, so the ratio would mean nothing")
        bad=1; continue
    if len(its) > cap:
        print(f"FAIL the {what} menu carried {len(its)} item(s), over the {cap}")
        print( "     LSP_COMPL_MAX says it sends - the cap is what keeps a stdlib-wide")
        print( "     empty prefix off the wire on every keystroke")
        bad=1; continue
    cost=max(t_all-t_open, 0.0)
    ratio=cost/t_open if t_open>0 else 0.0
    print(f"completion {what}: {len(its)} item(s), didOpen {t_open:.3f}s, "
          f"completion {cost:.3f}s, ratio {ratio:.2f}x")
    if ratio > 2.0:
        print(f"FAIL completion cost {ratio:.2f}x the whole parse-and-check of the same")
        print( "     document, over a ceiling of 2.00x. It is asked once per keystroke,")
        print( "     so this is the budget - see lspComplWants and LSP_COMPL_MAX in")
        print( "     self_host/lsp.ax.")
        bad=1
sys.exit(bad)
PY
)
cperf_status=$?
echo "$cperf"
if [[ "$cperf_status" -ne 0 ]]; then
  status=1
fi

# ------------------------------------------------------------------
# EVERY ADVERTISED REQUEST, AT EVERY KIND OF POSITION, ON REAL FILES.
#
# The derived checks above ask each request the RIGHT question on a
# document written for it. This asks every request the WRONG question,
# many times, on documents written for something else: a stdlib module
# as it is, the same module cut off mid-form so it does not parse, and
# an empty document. The property is the one an editor depends on
# before any other - the server ANSWERS, with a result or with an
# error that is not "method not found", and is still alive afterwards.
# A server that dies on a `references` request at byte 0 of a comment
# has every other feature it advertises taken away with it.
#
# THE METHOD LIST IS DERIVED FROM THE CAPABILITIES, not written here.
# A provider the server advertises is a promise a client will act on,
# so every advertised provider is exercised; a request this table does
# not know how to build from a capability key is a FAILURE, because a
# capability nothing sweeps is a capability nothing tested. And the
# sweep refuses to run under a floor of advertised providers, for the
# reason every other floor in this gate exists: a server advertising
# three things sweeps three things, and the exit status would read as
# coverage it does not have.
#
# POSITIONS. Every K-th byte of the document plus the ones that break
# scanners: 0, EOF, one past EOF, a line past the end, inside a string
# literal, inside a comment, on `(`, on `)`. Each is converted to
# {line, character} in Python, from the bytes, in UTF-16 units.
#
# COST. One session per document, all requests framed up front; the
# request count is printed so a sweep that shrinks is visible.
# ------------------------------------------------------------------
sweep=$(SERVER="$work/stage1" REPO="$repo_root" python3 - <<'PY'
import json, os, subprocess, sys
server=os.environ["SERVER"]; repo=os.environ["REPO"]
FLOOR=12          # advertised providers, below which this sweep asserts nothing
STEP=97           # bytes between sampled positions
def frame(o):
    b=json.dumps(o).encode(); return b"Content-Length: "+str(len(b)).encode()+b"\r\n\r\n"+b
def unframe(out):
    msgs=[]; i=0
    while True:
        j=out.find(b"\r\n\r\n",i)
        if j<0: return msgs, out[i:]
        hdr=out[i:j].decode("utf-8","replace")
        cl=[l for l in hdr.split("\r\n") if l.lower().startswith("content-length")]
        if not cl: return msgs, out[i:]
        n=int(cl[0].split(":")[1]); msgs.append(json.loads(out[j+4:j+4+n])); i=j+4+n
def pos_of(text, off):
    off=min(off,len(text)); head=text[:off]
    line=head.count("\n"); ls=head.rfind("\n")+1
    return {"line":line,"character":len(text[ls:off].encode("utf-16-le"))//2}
def positions(text):
    n=len(text); offs=set(range(0,n,STEP)); offs.update([0,n,n+1])
    for needle in ('"', ';', '(', ')'):
        k=text.find(needle)
        if k>=0: offs.add(k+1 if needle in '";' else k)
    ps=[pos_of(text,o) for o in sorted(o for o in offs if o<=n)]
    ps.append({"line":text.count("\n")+5,"character":0})
    return ps
def build(cap, name, uri, text, p, rid):
    """One request per capability key, at position p. Answers None for a
    key this table does not know, which the caller treats as failure."""
    td={"textDocument":{"uri":uri}}
    whole={"start":{"line":0,"character":0},"end":pos_of(text,len(text))}
    m={"definitionProvider":("textDocument/definition",{**td,"position":p}),
       "declarationProvider":("textDocument/declaration",{**td,"position":p}),
       "hoverProvider":("textDocument/hover",{**td,"position":p}),
       "completionProvider":("textDocument/completion",{**td,"position":p}),
       "documentSymbolProvider":("textDocument/documentSymbol",td),
       "referencesProvider":("textDocument/references",{**td,"position":p,"context":{"includeDeclaration":True}}),
       "documentHighlightProvider":("textDocument/documentHighlight",{**td,"position":p}),
       "signatureHelpProvider":("textDocument/signatureHelp",{**td,"position":p}),
       "inlayHintProvider":("textDocument/inlayHint",{**td,"range":whole}),
       "foldingRangeProvider":("textDocument/foldingRange",td),
       "selectionRangeProvider":("textDocument/selectionRange",{**td,"positions":[p]}),
       "documentLinkProvider":("textDocument/documentLink",td),
       "workspaceSymbolProvider":("workspace/symbol",{"query":"vec" if rid%2 else ""}),
       "documentFormattingProvider":("textDocument/formatting",{**td,"options":{"tabSize":2,"insertSpaces":True}}),
       "codeActionProvider":("textDocument/codeAction",{**td,"range":{"start":p,"end":p},"context":{"diagnostics":[]}}),
       "typeDefinitionProvider":("textDocument/typeDefinition",{**td,"position":p}),
       "codeLensProvider":("textDocument/codeLens",td),
       "diagnosticProvider":("textDocument/diagnostic",td),
      }
    if name=="renameProvider":
        return [("textDocument/prepareRename",{**td,"position":p}),
                ("textDocument/rename",{**td,"position":p,"newName":"renamedName"})]
    if name=="callHierarchyProvider":
        # The two hierarchy requests carry an ITEM and no textDocument, so
        # the sweep builds one out of the position it is at: a name the
        # document may or may not declare, a range that may not be a form.
        # That is the point - the item a client sends back is whatever a
        # previous `prepare` handed it, and a stale one must not kill the
        # server.
        item={"name":"main","kind":12,"uri":uri,
              "range":{"start":p,"end":p},"selectionRange":{"start":p,"end":p}}
        return [("textDocument/prepareCallHierarchy",{**td,"position":p}),
                ("callHierarchy/incomingCalls",{"item":item}),
                ("callHierarchy/outgoingCalls",{"item":item})]
    if name=="experimental":
        if isinstance(cap,dict) and cap.get("expandMacro"):
            return [("axiom/expandMacro",{**td,"position":p})]
        return []
    if name in ("textDocumentSync", "positionEncoding"): return []
    if name not in m: return None
    return [m[name]]
def caps_of():
    msgs=[frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":None,"rootUri":None,"capabilities":{}}}),
          frame({"jsonrpc":"2.0","id":2,"method":"shutdown","params":None}),
          frame({"jsonrpc":"2.0","method":"exit","params":None})]
    p=subprocess.run([server,"lsp"],input=b"".join(msgs),capture_output=True,timeout=600)
    ms,_=unframe(p.stdout)
    return {m["id"]:m for m in ms if "id" in m}[1]["result"]["capabilities"]
caps=caps_of()
providers=[k for k,v in caps.items() if v not in (None,False)]
if len(providers) < FLOOR:
    print(f"FAIL the server advertises {len(providers)} capabilities ({sorted(providers)}), under the")
    print(f"     floor of {FLOOR} - a sweep over that few would report coverage it does not have")
    sys.exit(1)
src=open(os.path.join(repo,"stdlib","Json.ax"),encoding="utf-8").read()
docs=[("Json.ax", src), ("Json-truncated.ax", src[:len(src)*2//3]), ("empty.ax", "")]
bad=0; total=0
for label,text in docs:
    uri="file://"+os.path.join(repo,"stdlib",label)
    reqs=[]; rid=10
    for p in positions(text):
        for name in providers:
            built=build(caps[name],name,uri,text,p,rid)
            if built is None:
                print(f"FAIL capability {name!r} is advertised and this sweep does not know how to")
                print( "     exercise it - add it to the table, or a capability nothing tests ships")
                sys.exit(1)
            for method,params in built:
                reqs.append((rid,method,params)); rid+=1
    msgs=[frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":None,"rootUri":None,"capabilities":{}}}),
          frame({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"axiom","version":1,"text":text}}})]
    msgs+=[frame({"jsonrpc":"2.0","id":r,"method":m,"params":ps}) for r,m,ps in reqs]
    msgs+=[frame({"jsonrpc":"2.0","id":2,"method":"shutdown","params":None}),
           frame({"jsonrpc":"2.0","method":"exit","params":None})]
    p=subprocess.run([server,"lsp"],input=b"".join(msgs),capture_output=True,timeout=1200)
    ms,tail=unframe(p.stdout)
    byid={m["id"]:m for m in ms if "id" in m}
    why=""
    if p.returncode!=0: why=f"the server exited {p.returncode} (stderr: {p.stderr[-300:]!r})"
    elif tail: why=f"{len(tail)} trailing bytes after the last frame"
    elif 2 not in byid: why="the shutdown after the sweep was never answered - the server died mid-sweep"
    else:
        for r,m,ps in reqs:
            a=byid.get(r)
            if a is None: why=f"request {r} ({m} at {ps.get('position',ps.get('range','-'))}) was never answered"; break
            if "error" in a: why=f"request {r} ({m} at {ps.get('position',ps.get('range','-'))}) answered error {a['error']}"; break
    total+=len(reqs)
    if why:
        print(f"FAIL sweep on {label}: {why}"); bad=1
    else:
        print(f"ok   sweep on {label}: {len(reqs)} requests over {len(positions(text))} positions x {len(providers)} providers, all answered")
print(f"sweep: {total} requests, {len(providers)} advertised providers (floor {FLOOR})")
sys.exit(bad)
PY
)
sweep_status=$?
echo "$sweep"
if [[ "$sweep_status" -ne 0 ]]; then
  status=1
fi

exit $status
