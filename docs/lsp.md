# The Axiom language server

`axiom lsp` is the language server. It is `self_host/lsp.ax`, one
module of the self-hosted compiler, and it owns the protocol and
nothing else: every diagnostic it publishes comes from the same
`parseModuleWith`/`checkModule` pair that `axiom check` runs, and every
answer below is read off the compiler's own parse tree. This document
says how to run it, how to point four editors at it, what each request
answers and what it deliberately refuses, the legend its highlighting
uses, and the one cost rule the whole design follows.

Every claim here is held by `scripts/check-lsp-selfhost.sh`, which
builds a server from `self_host/` and drives it with
`tests/lsp/drive.py`; each section names the part of that gate that
holds it. Counts are kept out of the prose on purpose —
`scripts/check-doc-drift.sh` recomputes every number a document
states, and the gate's own output prints the current ones — and the
one release that grew the server from four questions to the set below
is [CHANGELOG.md](../CHANGELOG.md) `## 0.3.5`, which records what was
measured when each request landed.

## Running it

```bash
axiom lsp
```

That is the whole command line, and `axiom help lsp` says so: the
server speaks JSON-RPC 2.0 over stdin and stdout with the base
protocol's `Content-Length` framing, takes no operand, accepts no flag
of its own, and writes nothing else to stdout. It writes nothing to
stderr either — a session of `initialize`, `shutdown`, `exit` leaves
stderr empty. `scripts/check-driver.sh` holds `--help` to the
driver's accept-chain, so a flag the subcommand grew would have to
appear there.

A session from a shell, for when an editor's log is not enough:

```bash
python3 - <<'PY'
import json, subprocess
def frame(m):
    b = json.dumps(m).encode()
    return b"Content-Length: %d\r\n\r\n" % len(b) + b
msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"processId": None, "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
        {"jsonrpc": "2.0", "method": "exit", "params": None}]
p = subprocess.run(["axiom", "lsp"], input=b"".join(map(frame, msgs)),
                   capture_output=True)
print(p.stdout.decode())
print("exit", p.returncode)
PY
```

The first reply is the `initialize` result: the capabilities object
the rest of this document walks through, and `serverInfo` naming
`axiom` and the compiler's version. The exit status is `0` after a
`shutdown`, and `1` when the client sent `exit` without one or closed
the pipe — measured on all three endings against the release binary.
The framed byte stream of a fixed session, capabilities included, is
pinned by the goldens under `tests/lsp/`.

What the lifecycle does, and what it does not:

- **Sync is full-text**, `textDocumentSync: 1`. Every `didChange`
  carries the whole document — the server reads the LAST content
  change of the notification — because the checker takes a whole
  source string anyway, and an incremental store would exist only to
  be re-flattened before every check. `didOpen`, `didChange` and
  `didClose` are the three notifications it reads; a `didSave` is
  dropped, as any notification it does not know is.
- **Diagnostics are published on every `didOpen` and `didChange`**,
  under the document's own URI, and they are `axiom check`'s: a
  lexical error first, then a parse error with a span on the token
  that failed, then `AX5001` for an import that does not resolve, then
  the expander's refusals alone when it refused, else the expander's
  and the checker's diagnostics merged in the compiler's order. Each
  carries the `AX` code as `code`, `axiom` as `source`, and
  everything the terminal prints about it: the message's first line,
  the LABEL the terminal draws at the caret, and its `note:` and
  `help:` paragraphs. A SECONDARY span — `AX3006`'s "first defined
  here", `AX3012`'s "`x` is bound here" — is published as
  `relatedInformation`, which an editor renders as a link: before
  2026-09-03 a duplicate `main` said "duplicate definition `main`" and
  pointed at nothing while `axiom check` pointed at the other one. The
  gate holds that as a differential against
  `axiom check --diagnostic-format json` over every fixture — every
  label carried into the message, every secondary published at the
  UTF-16 position converted in Python from the terminal's character
  offset — and refuses to run if the corpus stops producing either.
  Only THIS document's diagnostics are published: a diagnostic the checker
  raised inside an imported module is not attributed to the file that
  imports it — open that module and it is published there. `didClose`
  publishes an empty list, which is how a server retracts squiggles.
  `tests/lsp/expected-diagnostics.txt` is the manifest every fixture's
  diagnostics are held to, by severity, code, an anchor string and the
  message line, with positions recomputed in Python from the bytes.
- **Imports resolve as `axiom check` resolves them** from the file the
  URI names: the entry file's directory, an `axiom.pkg`'s `depend` and
  `crate` directories, then `$AXIOM_PATH`. If `axiom check f.ax` finds
  the standard library from the shell your editor launches, the server
  finds it too; a half-typed `(import Fo` is answered as "this
  document alone", never as an error and never by a dead server
  (`lspPreflight` in `self_host/lsp.ax` walks the imports non-fatally
  before anything resolves).
- **Positions are UTF-16 code units**, the protocol's default.
  `tests/lsp/030-utf16-columns.ax` is the fixture that pins it.
- **A request the server does not know is answered with `-32601`**
  (`method not found: <name>`), a notification it does not know is
  dropped, and a message that is not JSON is dropped; `shutdown` is
  answered `null`. One `initialize` per process: there is no
  workspace-folder state to update.
- **Memory is flat across a session.** The arena is reset after every
  message, keeping the document store and the reader's unconsumed
  bytes; `drive.py`'s editing session, which edits one document many
  times and requires the process not to grow, is the check.

## Editor setup

Two things are separate, and an editor can have either without the
other — which is the confusion worth naming before the configurations:

| | What it gives | Which editors use it |
|---|---|---|
| the **language server** (`axiom lsp`) | every request in this document: navigation, hover, completion, hints, formatting, fixes, expansion | all of them |
| the **tree-sitter grammar** (`tree-sitter-axiom/`) | **all of the highlighting** — `highlights.scm` colours by syntactic role, `rainbows.scm` colours bracket pairs by depth | Helix, Neovim (nvim-treesitter), Emacs 29+ (`treesit`), Zed, the `tree-sitter` CLI |

The server colours nothing: it offers no semantic tokens (0.3.5 did,
and they came out again in favour of one source of colour — see
`CHANGELOG.md`). So a buffer with the server attached and no grammar
installed is plain text, however well every request is being
answered; install the grammar or the file stays uncoloured. VS Code
has no tree-sitter, so its highlighting needs a TextMate grammar, which
this repository does not ship. Every section below ends with the
command that tells you which of the two you actually have.

The server is found through the editor's `PATH`, so `axiom` must be on
it — or write the absolute path where the configurations below say
`"axiom"`. Source files end in `.ax`; the server does not read the
`languageId` a client sends, so name the filetype whatever your editor
wants, and the configurations below call it `axiom`. The two code-lens
commands `axiom.run` and `axiom.expandMacro` are the client's to
define (see [Changing and running](#changing-and-running)); each
configuration below defines them where the editor can.

### Neovim

Neovim's built-in client, for every request; nvim-treesitter for the
colour. Nothing in the client configuration turns highlighting on,
because highlighting is not the server's — the grammar block after it
is what colours the buffer.

```lua
-- init.lua
vim.filetype.add({ extension = { ax = "axiom" } })

-- Neovim 0.11+: a named client configuration, enabled for the filetype.
vim.lsp.config("axiom", {
  cmd = { "axiom", "lsp" },
  filetypes = { "axiom" },
  root_markers = { "axiom.pkg", ".git" },
})
vim.lsp.enable("axiom")

-- Neovim 0.10: start the client by hand instead of the two calls above.
-- vim.api.nvim_create_autocmd("FileType", {
--   pattern = "axiom",
--   callback = function(ev)
--     vim.lsp.start({
--       name = "axiom",
--       cmd = { "axiom", "lsp" },
--       root_dir = vim.fs.root(ev.buf, { "axiom.pkg", ".git" }),
--     })
--   end,
-- })

-- The two commands the code lenses name. The server never runs them.
vim.lsp.commands["axiom.run"] = function(command)
  vim.cmd.split()
  vim.cmd.terminal("axiom run " .. vim.fn.shellescape(command.arguments[1]))
end
vim.lsp.commands["axiom.expandMacro"] = function(command)
  local uri, position = command.arguments[1], command.arguments[2]
  vim.lsp.buf_request(0, "axiom/expandMacro",
    { textDocument = { uri = uri }, position = position },
    function(err, result)
      if err or not result then
        vim.notify("nothing to expand here")
        return
      end
      vim.cmd.new()
      vim.bo.filetype, vim.bo.buftype = "axiom", "nofile"
      vim.api.nvim_buf_set_lines(0, 0, -1, false,
        vim.split("; " .. result.name .. "\n" .. result.expansion, "\n"))
    end)
end

-- Hints and lenses are off until asked for.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "axiom" then return end
    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    vim.lsp.codelens.refresh({ bufnr = ev.buf })
    vim.keymap.set("n", "<leader>l", vim.lsp.codelens.run, { buffer = ev.buf })
  end,
})
```

**Verify:** open a `.ax` file and run `:checkhealth vim.lsp` — the
client must be listed as attached. Highlighting is the grammar's, so
register it with nvim-treesitter, pointed at
[`tree-sitter-axiom/`](../tree-sitter-axiom/README.md) in a checkout,
and then `:Inspect` on any identifier must name a `@...axiom` capture
such as `@function.call.axiom` — that is the proof colour is arriving.
`:TSInstall axiom` failing, or `:Inspect` showing no treesitter
capture, means the grammar is not built for this Neovim. For rainbow
brackets, rainbow-delimiters.nvim reads `queries/rainbows.scm`'s
capture names when pointed at it.

```lua
require("nvim-treesitter.parsers").get_parser_configs().axiom = {
  install_info = {
    url = "/path/to/axiom/tree-sitter-axiom",
    files = { "src/parser.c", "src/scanner.c" },
  },
  filetype = "axiom",
}
-- then :TSInstall axiom, and copy tree-sitter-axiom/queries/highlights.scm
-- to a queries/axiom/highlights.scm directory on the runtimepath.
```

### Helix

Helix highlights with tree-sitter alone and does not consume code
lenses, so the grammar is where every colour comes from and the two
lens commands are out of reach. Everything else — definition, references, rename, hover,
completion, signature help, inlay hints, document and workspace
symbols, formatting, code actions — is the built-in client's.

Three parts have to be in place, and `hx --health axiom` is the one
command that says which are: the server, the compiled grammar, and the
highlight queries in the runtime directory. Configuration first:

```toml
# ~/.config/helix/languages.toml
[language-server.axiom]
command = "axiom"                 # or the absolute path to the binary
args = ["lsp"]

[[language]]
name = "axiom"
scope = "source.axiom"
file-types = ["ax"]
roots = ["axiom.pkg", ".git"]
comment-token = ";"
block-comment-tokens = { start = "#|", end = "|#" }
indent = { tab-width = 2, unit = "  " }
language-servers = ["axiom"]
auto-format = true

[[grammar]]
name = "axiom"
source = { path = "/path/to/axiom/tree-sitter-axiom" }
```

**Do not set `formatter` for this language.** `axiom fmt` rewrites a
file in place and has no `--stdin`, and Helix formats by piping the
buffer through a command's standard input — so a
`formatter = { command = "axiom fmt", args = ["--stdin"] }` line cannot
work, and, because a configured formatter takes precedence over the
language server, it turns off the formatting that does. `hx --health
axiom` reports such a line as `✘ 'axiom fmt' not found in $PATH`
(Helix reads the whole string as one command name). With no `formatter`
line, `auto-format` uses the server's `textDocument/formatting`, which
runs the same `fmtFormat` the command does.

Then build the grammar and install the queries — Helix loads queries
from its runtime directory, **not** from the grammar's own `queries/`:

```bash
mkdir -p ~/.config/helix/runtime/queries/axiom
cp /path/to/axiom/tree-sitter-axiom/queries/highlights.scm \
   /path/to/axiom/tree-sitter-axiom/queries/rainbows.scm \
   ~/.config/helix/runtime/queries/axiom/
hx --grammar build            # compiles the [[grammar]] entries above
```

**Verify, and do not skip this:** `hx --health axiom` must print a
green tick on the server, the parser and the highlight queries.

```
Configured language servers:
  ✓ axiom: /path/to/axiom
Configured formatter: None          <- correct; the server formats
Tree-sitter parser: ✓
Highlight queries: ✓
Rainbow queries: ✓
```

Rainbow brackets — every `(`, `[` and `{` pair coloured by its nesting
depth, from `rainbows.scm` — are off until `~/.config/helix/config.toml`
says `[editor] rainbow-brackets = true`.

`Tree-sitter parser: None` or `Highlight queries: ✘` means the buffer
will render as plain text no matter what the language server answers.
That is the whole failure mode: the server can be attached and answering
every request while nothing in the file is coloured — measured on
2026-08-28, when it read exactly that way on a machine whose server was
green.

Capture names in `highlights.scm` follow nvim-treesitter's convention.
Helix resolves a scope it does not spell by trimming the last segment —
`@keyword.modifier` falls back to `keyword`, `@number.float` to
`number` — so a theme that names only the coarse scopes still colours
everything; a theme that names the fine ones colours it more precisely.
Measured on `stdlib/Vec.ax`: 2,392 captures over 15 distinct names.

Inlay hints are off until `~/.config/helix/config.toml` says:

```toml
[editor.lsp]
display-inlay-hints = true
```

### Emacs (eglot)

Eglot is in Emacs 29 and later. It does not consume code lenses, so
the `Run` lens is not reachable (`lsp-mode` does, with `lsp-lens-mode`,
and is configured the same way with `lsp-register-client`).
Highlighting is the major mode's: Emacs 29's `treesit` can load the
grammar built from `tree-sitter-axiom/` and use `highlights.scm`'s
captures through a `treesit-font-lock-rules` mapping. Definition is `M-.`,
references `M-?`, hover and signature help are `eldoc`, the outline is
`imenu`, and `eglot-rename`, `eglot-code-actions` and
`eglot-format-buffer` are the rest.

```elisp
;; init.el
(define-derived-mode axiom-mode lisp-data-mode "Axiom"
  "Axiom source: s-expressions, `;' line comments.")
(add-to-list 'auto-mode-alist '("\\.ax\\'" . axiom-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(axiom-mode . ("axiom" "lsp"))))
(add-hook 'axiom-mode-hook #'eglot-ensure)

;; The custom request, as a command: the expansion in a new buffer.
;; `eglot--' helpers are Eglot's internals and may move between releases.
(defun axiom-expand-macro ()
  "Show what the macro at point generated."
  (interactive)
  (let ((res (jsonrpc-request (eglot--current-server-or-lose) :axiom/expandMacro
                              (list :textDocument (eglot--TextDocumentIdentifier)
                                    :position (eglot--pos-to-lsp-position)))))
    (if (null res)
        (message "Nothing to expand here")
      (with-current-buffer
          (get-buffer-create (format "*axiom expand %s*" (plist-get res :name)))
        (erase-buffer)
        (insert (plist-get res :expansion) "\n")
        (axiom-mode)
        (pop-to-buffer (current-buffer))))))
```

### VS Code

There is no published Axiom extension. What follows is a snippet to
build one from: two files in a directory, `npm install`, then open the
directory in VS Code and press F5 for an Extension Development Host
with the extension loaded. `vscode-languageclient` asks the server for
inlay hints, code lenses and everything else it advertises without
being told to; the two commands are the only code that is not
boilerplate. Highlighting is NOT among what it gets: VS Code has no
tree-sitter and the server will not send semantic tokens (see
[Highlighting](#highlighting) for why that is settled rather than
pending), so a `.ax` file is uncoloured until the extension
contributes a TextMate grammar, which this repository does not ship.

```json
{
  "name": "axiom-editor",
  "displayName": "Axiom",
  "version": "0.0.1",
  "publisher": "local",
  "engines": { "vscode": "^1.85.0" },
  "main": "./extension.js",
  "activationEvents": ["onLanguage:axiom"],
  "contributes": {
    "languages": [{ "id": "axiom", "aliases": ["Axiom"], "extensions": [".ax"] }],
    "commands": [
      { "command": "axiom.run", "title": "Axiom: Run" },
      { "command": "axiom.expandMacro", "title": "Axiom: Expand Macro" }
    ]
  },
  "dependencies": { "vscode-languageclient": "^9.0.1" }
}
```

```js
// extension.js
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");
let client;
function activate(context) {
  client = new LanguageClient("axiom", "Axiom",
    { command: "axiom", args: ["lsp"] },
    { documentSelector: [{ scheme: "file", language: "axiom" }] });
  context.subscriptions.push(
    vscode.commands.registerCommand("axiom.run", (path) => {
      const t = vscode.window.createTerminal("axiom run");
      t.show();
      t.sendText("axiom run " + JSON.stringify(path));
    }),
    vscode.commands.registerCommand("axiom.expandMacro", async (uri, position) => {
      const r = await client.sendRequest("axiom/expandMacro", { textDocument: { uri }, position });
      if (!r) { vscode.window.showInformationMessage("Nothing to expand here"); return; }
      const doc = await vscode.workspace.openTextDocument(
        { language: "axiom", content: "; " + r.name + "\n" + r.expansion + "\n" });
      await vscode.window.showTextDocument(doc, { preview: true });
    }));
  client.start();
}
function deactivate() { return client && client.stop(); }
module.exports = { activate, deactivate };
```

**Verify:** with the Extension Development Host open on a `.ax` file,
hover a function name — a tooltip quoting its `(:: f T)` signature is
the proof the client connected (the *Output* panel, channel *Axiom*,
carries the server's stderr when it did not). Colour is a separate
matter: *Developer: Inspect Editor Tokens and Scopes* shows a TextMate
scope only once a grammar is contributed under `contributes.grammars`;
until then the row reads *no grammar*. A `language-configuration.json`
naming `;` as the line comment and the bracket pairs is the other file
a builder adds.

## What each request answers

The requests are grouped as README.md's *Editor support* row groups
them. Each paragraph says what the request answers, what it
deliberately does not, and where in `tests/lsp/drive.py` the derived
check lives — a check whose expected answer is computed from a
document the driver writes itself, so that re-blessing a golden cannot
satisfy it. `SECTION NAV TESTS`, `SECTION VIEW TESTS` and
`SECTION FIX TESTS` are the marker comments to search for.

Two facts hold for every request that takes a position. The word
under the cursor is found by the same string-and-comment-aware
scanner (`lspWordSpan`, `lspFormEnd`), so no two requests disagree
about where a form ends; and a document that does not parse answers
`null` or `[]` — except for the requests that work from the bytes,
which are named below. The sweep at the end of
`scripts/check-lsp-selfhost.sh` fires every advertised request at
every 97th byte of a real standard-library module, at the positions
that break scanners (offset 0, EOF, one past EOF, a line past the end,
inside a string, inside a comment, on `(`, on `)`), at the same module
cut off mid-form, and at an empty document, and requires an answer to
every id, no error, and a server still alive to say `shutdown`. Its
method table is DERIVED from the capabilities the server advertises,
so a key it cannot build a request for fails the gate.

This document is used for the examples below; it checks clean, and
the answers quoted are the release binary's.

```axiom
(import IO)

; A tag function for the data it is given.
(pub macro deriveTag
  ((deriveTag T)
   (pub :: (syntax/join tag T) Int)
   (pub fn ((syntax/join tag T)) 7)))

(data Colour
  (Red)
  (Green))

(deriveTag Colour)

; Add one.
(:: bump (-> Int Int))
(fn (bump x) (+ x 1))

;@axiom:effect(io)
(fn (main)
  {
    (println "hi")
    (bump 4)
  })
```

### Navigation

**`textDocument/definition`.** Where the name under the cursor is
bound, asked in the language's own order: the innermost local binding
first — a `let` name, a `fn` or `lambda` parameter, a pattern
variable, landing on the binder — then this document's declarations,
then the merged declarations of every module this document imports,
answering a `Location` in that module's own file. A macro invocation
is a reference to its `macro` declaration (`MAC-TOOL-2` in
[macro-system.md](macro-system.md)). A CONSTRUCTOR is a declaration
too, and since 2026-09-03 this says where: the answer is the
constructor's OWN name span inside the `data` — `Green` in
`(data Colour (Red) (Green))`, not `Colour` — from a pattern head,
from an application, from its own declaration, and from another
document that imports it. `lspFindDecl` matches whole declarations and
never looks inside a constructor list, which is why five requests
could see a constructor and three could not. What it does not do: a builtin
(`Int`, `+`), a keyword and a name nothing declares answer `null`; a
name a macro would generate has no definition, because nothing has
expanded it; and an import that does not resolve narrows the search
to this document rather than failing it.

**`textDocument/declaration`.** The `(:: f T)` signature, where the
language has one to point at — and in Axiom it usually does, which is
why this is not a second name for `definition`. A function is written
twice, `(:: bump (-> Int Int))` declaring it and `(fn (bump x) ...)`
defining it, and the parser keeps both as nodes with their own name
spans; so `declaration` on any occurrence of `bump` lands on the `::`
and `definition` on the `fn` below it. The order is `definition`'s
with one step inserted: a local binding first, then this document's
`::`, then this document's declaration of that name, then the imported
modules, signature first. A `data`, a `struct`, a macro, a CONSTRUCTOR and a
local are not written twice, so for them the two requests agree, by
construction rather than by fallback — the gate asks both at a
constructor and requires the two answers to be EQUAL, where at a `fn`
it requires them to differ. There is one position where this
answers and `definition` cannot: a signature whose `fn` has not been
written yet — what an editor sees mid-keystroke, and what `AX3015`
reports. `null` for a keyword, a builtin, a name nothing declares and
a document that does not parse. Derived in `SECTION NAV TESTS`, which
asks both requests at the same position and requires the two ranges to
DIFFER, each equal to a whole-identifier position computed from the
document's own bytes, in `tests/lsp/drive.py`.

**`textDocument/prepareCallHierarchy`, `callHierarchy/incomingCalls`
and `callHierarchy/outgoingCalls`.** Who calls this function, and what
it calls. A call site here is an occurrence that the scope-aware walk
resolved to a top-level name AND that stands in the head position of a
form — two questions the server already answers, intersected by byte
offset. That definition is what makes the answer right in the two
cases a spelling match gets wrong: `(fn (apply k v) (k v))` calls the
parameter `k`, not the top-level `fn` of that name, so neither
direction reports an edge; and `(fn (handoff z) helper)` NAMES
`helper` without applying it, so it is not among `helper`'s callers.
Incoming calls read this document and every OTHER open document whose
imports resolve to this file, the same workspace `references` uses,
and a caller that calls twice is one entry with two ranges. Outgoing
calls name every callee this server can point at — one this document
declares, or one an imported module declares, resolved as
`definition` resolves it — and leave out what it cannot: a builtin, an
operator, a constructor. `prepare` answers `null` for a local, for a
`data`, `struct` or macro, for a document that does not parse, and for
an IMPORTED name: the two requests that follow carry the item and
nothing else, so go to the definition first and ask there. An item
whose document the server has not opened answers `null` rather than
`[]`, because `[]` claims the function has no callers and a server
that cannot read the file has not earned that claim.

This is not `axiom symbols --calls`. That key is the checker's edge
set, harvested from the effect walk, so it costs a full typecheck and
carries no positions at all — measured on the gate's own fixture,
`handoff` gets `#calls=helper` for a body that never applies it, while
`CallHierarchyIncomingCall.fromRanges` is a list of ranges the
protocol requires. The two agree where they overlap and this one is a
strict subset. Derived in `tests/lsp/drive.py`'s `SECTION NAV TESTS`,
whose five documents carry both confusable shapes and which refuses to
run if either ever leaves them.

**`textDocument/references` and `textDocument/documentHighlight`.**
Every occurrence of the same BINDING, not the same spelling: the
walk records each occurrence with the key of what it resolves to, so
the `i` of one function is not the `i` of another, and a `let` that
shadows a parameter is a different name from it. Type positions —
the names inside every `::`, `data`, `struct` and `type` form — are
read from the bytes, since type nodes carry no span, and resolved
against the type table alone, so a `fn` spelled like a `data` is not
the same name. `references` reaches every OTHER
open document whose imports resolve to this file, each under its own
URI, and honours `includeDeclaration`; it does not open files the
editor has not, so a reference in a closed module is not listed.
`documentHighlight` is the same set within one document, with the
binder as the `Write` kind and reads as `Read`. A form the parser
DESUGARS contributes only what the user wrote: a binder whose name
holds `$` — `for$v`, `for$i`, unwritable by AX1001 — is never
recorded, and a reference is recorded only where the document's bytes
at its span spell its bare name, which drops the loop's `Vec$vecGet`
read and the `<`/`+` it emits on the keyword while keeping a user's
`Vec::vecLen` and a template's `IO$writeStr` (what `println`'s
`writeStr` is rewritten to). So `documentHighlight`
and `prepareRename` at the word `for` answer `null`, as at `while`;
before that rule, `prepareRename` there answered the placeholder
`for$v` with the keyword's own range, and highlight listed ten
occurrences the document does not contain. The gate derives every
expected `Location` from documents the driver writes — a parameter
with and without its declaration, a `let` from its read, a type in a
signature, a struct field and an alias — and the changelog's review
section records the measurement beyond it: on four real files,
`references` on twenty top-level names equals a whole-identifier grep
of the code.

**`textDocument/prepareRename` and `textDocument/rename`.**
`prepareRename` answers the word's range for a name this server will
rename, and `null` for one it will not: a name declared in another
module, even an open one — renaming across files the server did not
open would leave a broken workspace, and a standard-library name must
never be renamed from a client — a builtin, an effect, a keyword,
`_`, and a parameter whose position could not be recovered from the
header's bytes. `rename` refuses, with `null`, a new name the lexer
would not read as one identifier, a keyword, the old name itself, and
a collision: for a local, a name already bound in an enclosing or the
same scope or one the renamed binding would capture (a second walk
with a probe decides this, inside the scope stack); for a declaration,
a name this document or any importing document already spells
anywhere, because a rename that makes a call resolve somewhere else
is a change of meaning disguised as a change of spelling. The edit
covers every open importing document. The gate APPLIES a cross-file
rename in Python, writes both files, reopens them and requires the
checker to publish nothing for the pair.

**`textDocument/typeDefinition`.** From a signed function's result,
a header parameter or a constructor to the `data`, `struct` or `type`
that declares its type, in this document or an imported one. On a
constructor this is the one request that answers the `data` rather
than the constructor, because the type of `Green` is `Colour`;
`definition` at the same character answers `Green`, and
`SECTION NAV TESTS` asks both there and requires the two to differ.
The imported half of that was missing until 2026-09-03 — `null` at a
character where `signatureHelp` was rendering the constructor's own
shape. `null` for a builtin type, for a `fn` with no `::`, and for a
position that is none of those three.

### Reading

**`textDocument/hover`.** Markdown with an `axiom` fence quoting the
declaration, the module below it when the name was imported, and the
comment paragraph written above the declaration. A `fn` is quoted as
its `(:: f T)` signature rather than its body, and its paragraph is
read from above the signature, because that is where this language
puts it; a `fn` with no signature is quoted as its first line. A
`data`, `struct` or `macro` is quoted whole, cut to a tooltip's
height by `lspClampLines`. A CONSTRUCTOR is read at the whole `data`
that declares it — its siblings and its field types are what a reader
wants — with one line under the fence naming which of them the cursor
is on:

```text
(data Colour
  (Red)
  (Green))

constructor `Green` of `Colour`
```

and the module below that when the `data` came from another file. A local answers from the walk: a parameter
of `bump` answers

```text
x : Int

parameter of `bump`
```

with the type cut from the signature's arrow. The `range` is the word
under the cursor, not the declaration, which for an imported name is
in a different file. `null` for a builtin, a keyword or a name nothing
declares. The gate cuts every quoted form and every paragraph out of
the document itself — a second implementation, in Python, of
`lspFormText` and `lspDocComment` — and compares.

**`textDocument/completion`.** In this order: the head keywords the
parser dispatches on (extracted from the `kwEq` call sites of
`self_host/parser.ax` by the gate, so the copy in `lsp.ax` is a
checked claim), this document's declarations and the constructors its
`data` forms name, and every imported module's declarations under
their bare names — a local name shadowing an imported one and both
shadowing a keyword. The list is filtered on the prefix under the
cursor, capped at `LSP_COMPL_MAX`, and sent `isIncomplete: true`,
which tells the client to ask again on the next keystroke; `(` is the
trigger character. A document that does not parse still completes
keywords — the normal case, since a file is unparseable exactly while
a form is half written. It does not offer a name a macro would
generate: `(deriveTag Colour)` does not put `tagColour` in the menu,
and the gate asserts that absence.

**`textDocument/signatureHelp`.** The call the cursor is inside — a
`fn` of this document, one of its constructors, or an imported `fn`
with its module named — as `(bump x) : (-> Int Int)`, the type cut
from the `::` beside the `fn`, each parameter as the UTF-16 offset
pair that slices the label to its name, the paragraph above the
declaration as `documentation`, and `activeParameter` counted from
the bytes. `(` and space trigger it, space retriggers. A local
shadowing a top-level `fn` of the same name is asked first, so
`(fn (t7 f) (f 1 2))` beside a top-level `f` answers nothing for
`f`; a `fn` header does not answer its own signature; outside any
call it is `null`.

**`textDocument/inlayHint`.** Three hints the source does not spell:
`x:` before each argument of a call to a declared or imported `fn`
(kind `Parameter`, never before a variable spelled like the
parameter), `: Int` after each parameter in a `fn` header and
` -> Int` after the header (kind `Type`), the last two from the
signature's arrow — so a `fn` with no `::` gets no type hints. The
callee lookup is indexed per request; the measured cost of not doing
so is in the changelog.

**`textDocument/foldingRange`.** Every form and brace block whose
opener and closer sit on different lines, a run of `;` comment lines
as kind `comment`, a run of imports as kind `imports` — from a bracket
scan of the bytes, so a half-typed file still folds.

**`textDocument/selectionRange`.** Word, then the enclosing form,
then each form around it, then the document, for each position sent.

**`textDocument/documentLink`.** One link per `(import M)` whose
module the resolver's own search finds, over the dotted name as
written, targeting that file. An import that does not resolve is no
link, not an error; `resolveProvider` is false.

**`textDocument/documentSymbol`.** The outline: every `fn` and
`macro` as `Function`, every `data` as `Enum`, every `struct` as
`Struct`, straight off the parse tree with no checker running — a file
with a type error still has an outline, and a file that does not parse
has an empty one. A `::` signature is not listed beside its `fn`, and
neither is a `type` alias.

`range` is the whole top-level form and `selectionRange` is the name
inside it. Both used to be the name, which the protocol permits and an
editor cannot use: `range` is what a client highlights in the
breadcrumb, keeps in sticky scroll, and expands a selection to, and
four characters of it is none of those. The extent is recovered from
the BYTES by the same `lspFormStart`/`lspFormEnd` pair hover quotes a
declaration with; when it cannot be — a declaration indented mid-edit,
where `lspFormStart`'s column-zero rule has nothing to find — this
answers the name span and publishes no children, rather than a range
that does not contain what it claims to.

And it NESTS: a `data`'s constructors are `EnumMember` children and a
`struct`'s fields are `Field` children, each at its own name span.
`workspace/symbol` had been listing constructors at those spans all
along while the outline of the same file showed neither them nor a
field, which is two views of one document disagreeing. `children` is
omitted rather than sent empty, so no client draws an expander over
nothing.

`tests/lsp/expected-outline.txt` is total: a fixture publishes exactly
those rows, in that order, with the CONTAINER each belongs to, and
`tests/lsp/060-outline.ax` is the one that carries a `data` and a
`struct` with members. Four invariants hold for every symbol of every
document with no row at all — `selectionRange` inside `range`, a
parent containing its `selectionRange` STRICTLY, every child inside its
parent, and the source at `selectionRange` spelling the symbol's name.

**`workspace/symbol`.** Every declaration the OPEN documents can see
— their own and every module each imports — whose bare name holds the
query, case-folded, with constructors as `EnumMember` and the module
as `containerName` for an imported one; a declaration reached twice
through two open documents is listed once. The workspace this server
knows is the document store: it does not walk a directory, so a module
nothing open imports is not searched. The list stops at
`LSP_COMPL_MAX`.

### Changing and running

**`textDocument/formatting`.** One `TextEdit` over the whole document
holding the output of the same `fmtFormat` that `axiom fmt` runs;
`[]` for a document already in the formatter's normal form; `null`
for one that does not parse. The gate holds the edit's text equal,
byte for byte, to what `axiom fmt` wrote to a copy.
`textDocument/rangeFormatting` is deliberately not offered, and the
reason is measured rather than assumed. `fmtFormat` proves its output
a fixed point of the WHOLE file, so a range formatter would have to
format a slice and hope the answer matched. Over `stdlib/` and
`self_host/` on 2026-08-31 — 8,437 slices, each one a whole run of
top-level forms, formatted alone and compared against the same forms
cut out of the whole document's formatted output — 8,416 matched and
**21 did not**. Every disagreement is comment placement, and both
shapes are real: `(pub :: SGR_ERROR String)  ; bold red` in
`self_host/style.ax` keeps its trailing comment when the slice is
formatted and loses it to the next declaration when the file is, and a
comment block inside `codegen.ax`'s `CG` struct migrates ACROSS a
top-level form boundary in the whole-document pass and stays put in
the slice. An editor with format-on-save and format-selection both
bound would therefore rewrite bytes that the other had just written.
Whole-document formatting is the one answer this server gives.

**`textDocument/codeAction`.** Three kinds, all advertised in
`codeActionKinds`. `quickfix`: every machine-applicable fix the
compiler attaches to a diagnostic in the range — a help carrying a
fix span, exactly what AXDL prints after `~>` — as a preferred action,
so a code that gains a fix in `typecheck.ax` gains a quickfix without
a line changing in `lsp.ax`; and two the server writes itself. *Import
`name` from `Mod`*, on an AX3001 whose reference is a bare name: every
module the resolver could reach — the entry file's directory,
`axiom.pkg`'s `depend` and `crate` directories, `AXIOM_PATH`,
`AXIOM_STDLIB`, each walked three levels deep for a nested
`Sys.Platform` — is a candidate under the name `moduleSrcPath` would
resolve it by, so a `Str.ax` beside the entry file shadows the stdlib's
exactly as it does for the compiler; a file is parsed only when its
bytes spell the name as a whole word, and one action is offered per
module that declares it `pub`. The edit adds the name to an existing
`(import Mod (...))` list, else writes `(import Mod (name))` on its own line after the last
import, else as the first line. A qualified `Mod::name` gets no
action: it names its module already. *Make `name` public in `Mod`*, on
AX3023: a `WorkspaceEdit` keyed by the **declaring file's** URI that
inserts `pub ` after the opening paren of the `fn` and of its `::` —
`check` refuses either alone — with the written visibility read from
that file's bytes, since the resolver's `nodeVis` records exportedness
rather than what was written; an AX3023 on a name that IS written
`pub` is one the document's import list left out, and gets the import
action instead. `refactor.rewrite`: *Add type signature for `f`* on a
`fn` with no `::`, written from the type the checker inferred in the
parser's own spelling `(-> Int Int)`, with an unresolved type variable
lettered in order of appearance. `refactor.extract`: *Extract to
`let`*, with no diagnostic, when the range trimmed of whitespace is
exactly one item — a form, a brace block, a literal or an identifier —
inside the body of a `fn` of this document. The statement it is
hoisted above is the innermost enclosing item that is a direct child
of a `{ }` block, else the fn body; it becomes `(let ((x E)) S')` with
`x` for `E`, where `x` is `extracted` or the first `extractedN` the
document does not spell. It is refused wherever hoisting would change
how often or whether `E` runs — under a `lambda`, `while`, `cond` or
`handle`, in a branch of an `if` or an arm of a `match` (the test and
the scrutinee are fine), in a head position or a binding list, and
past the first operand of a `for`: the container, or a range's start,
is hoisted into a binding the loop reads once and stays extractable,
while the third item is `hi` in one shape and the body in the other
and the rule sees the head and the position but not the arity, so it
is refused in both (measured before the rule: extraction was offered
on a per-iteration `(mk 5)` in a `for` body) — and
whenever `E` references a binder bound inside the statement. What it
changes on purpose: `E` now runs before whatever the statement
evaluated ahead of it. This request runs the pipeline for the
diagnostic-attached kinds (see [The cost rule](#the-cost-rule)) and
the raw tree for the extraction; `[]` on a document that does not
parse. The gate applies AX3012's `mut x` at the BINDER, AX3001's
respelling at the call, and the signature assist, in Python, reopens
the result and requires no diagnostics at all; applies each import and
the `pub ` edits and requires `check` to answer OK; and runs the
extracted program to require the same output and exit status as the
original, on a document whose extracted call performs a side effect
exactly once.

**`textDocument/codeLens`.** A `▶ Run` lens over `(fn (main) ...)`
when `main` takes no parameters — that is what `axiom run` runs — and
an `Expand macro` lens over every `pub macro`. A lens carries a command
NAME and its arguments, and the server runs nothing: `axiom.run`
carries the document's filesystem path, `axiom.expandMacro` the
document's URI and the macro declaration's position, and the editor
does the rest, as rust-analyzer's `Run` lens works. On the document
above:

```json
{"range": {"start": {"line": 3, "character": 11}, "end": {"line": 3, "character": 20}},
 "command": {"title": "Expand macro", "command": "axiom.expandMacro",
             "arguments": ["file:///path/to/doc.ax", {"line": 3, "character": 11}]}}
{"range": {"start": {"line": 19, "character": 5}, "end": {"line": 19, "character": 9}},
 "command": {"title": "▶ Run", "command": "axiom.run",
             "arguments": ["/path/to/doc.ax"]}}
```

`resolveProvider` is false; `[]` on a document that does not parse.

**`axiom/expandMacro`.** The analogue of `rust-analyzer/expandMacro`,
advertised as `experimental.expandMacro: true`. Params are a text
document and a position:

```json
{"textDocument": {"uri": "file:///path/to/doc.ax"},
 "position": {"line": 12, "character": 0}}
```

and the result is the macro's name and what it generated, as Axiom
source, or `null`:

```json
{"name": "deriveTag",
 "expansion": "(pub :: tagColour Int)\n\n(pub fn (tagColour)\n  7)"}
```

On a top-level invocation — by its head or anywhere inside its bytes
— it answers that invocation's own products; on a macro declaration,
by its name or its form, everything the macro generated in this
document. The rendering is the compiler's first `ASTNode`-to-source
printer, whose promise is that the output parses and means what the
tree meant: the gate reopens the expansion as a document and requires
a clean parse with an outline of exactly the generated name, and a
differential over every top-level invocation under `tests/` and
`docs/` splices each expansion into a copy in place of the invocation
and holds `check`'s codes and `symbols`' names equal. What it does not
answer: an invocation in expression position inside a body (phase E
rewrites it in place and records nothing to attribute), an expansion
the expander refused (the refusal is already on screen as a
diagnostic), a position on anything else, and a document that does not
parse — all `null`. Three things the printer says out loud: a hygiene
binder `x.3` is written `x_3`, a `syntax/binders` variable `x#0` is
written with `_` for every byte the lexer refuses, and `Mod$name` is
written `Mod::name`. A macro whose template queries declarations
another invocation would have generated is shown without them, since
each invocation is expanded with every other removed. And a generated
`struct`'s fields print with their types, since the expander was fixed
to carry the type node where it had been carrying the parser's float
flag — an expander defect, not a printer choice, recorded beside
`MAC-TOOL-3` in [macro-system.md](macro-system.md).

## Highlighting

**The server will not send `textDocument/semanticTokens`.** That is a
decision and not a gap, and it is closed: highlighting is
`tree-sitter-axiom/queries/highlights.scm`'s alone. Release 0.3.5
shipped semantic tokens — every identifier coloured by what the
occurrence walk resolved it to — and they came out again before the
next release, with the whole of `SECTION HL`, because two sources of
colour can disagree about the same token and one cannot. One
highlighter means the editor cannot contradict itself; a second one in
the server would be a second thing to keep in step with the grammar,
forever, for a result the grammar already gives.

`highlights.scm` colours by syntactic role — a declaration's name by
what it declares, an application's head as a call, a constructor in a
pattern as a constructor, an AXTAG as an attribute rather than a
comment — and `queries/rainbows.scm` colours every bracket pair by its
nesting depth, with every bracket-opening rule of the grammar as a
scope. `scripts/check-tree-sitter.sh` holds both against every `.ax`
file in the repository. An editor that consumes semantic tokens but
not tree-sitter (VS Code) therefore has no highlighting from this
repository; one that consumes tree-sitter (Helix, Neovim, Emacs 29,
Zed) has all of it.

**`self_host/replhl.ax` is not an argument to revisit this.** It
paints Axiom source from the compiler's own lexer, and the reason is
the REPL's situation rather than a general one: a REPL has no
tree-sitter grammar loaded and no editor to consult, so it either
paints from the lexer or shows plain text. An editor has both already.
Giving it a second opinion is precisely how the two drift apart, which
is the failure 0.3.5 shipped and the next release withdrew.

## The cost rule

Every request that is asked per keystroke or per cursor move reads
the RAW parse tree and the document's bytes and expands no macro.
That is `MAC-TOOL-3` in [macro-system.md](macro-system.md), and the
reason is measured there: expansion is bounded but not free, and an
editor cannot wait. Each such request costs one parse, one line index
and one walk — the walk that `references` and its siblings share, the
bracket scan that folding and selection share, the bucket index that
parameter hints and signature help share — and its answer is derived
from what the file SAYS, which is why a name a macro would generate is
absent from completion, from the outline and from navigation.

Three things run the pipeline, each because the pipeline's output is
the answer: `didOpen` and `didChange`, which publish diagnostics,
because a diagnostic about generated code is exactly what expansion
is for; `codeAction`, because a quickfix is a checker diagnostic's own
fix and the assist writes what the checker inferred; and
`axiom/expandMacro`, because rendering what a macro generated is the
question being asked. None of the three is sent per keystroke — a
client asks for code actions when the cursor rests and for an
expansion on demand — and each costs about one `didOpen` of the same
document, which the editor paid on the last keystroke anyway.

The gate that holds it is `scripts/check-lsp-selfhost.sh`, and it
holds a RATIO rather than a stopwatch, so a slow runner cannot fail it
and a fast one cannot hide a regression: on a generated document with
at least `sym_floor` declarations it times `didOpen` — the whole
parse-and-check — and then `documentSymbol` and `completion` at an
empty and a filtered prefix, and fails any of them over a ceiling of
2.00x. A server that answers nothing is fast, so each measurement
carries a floor on the answer's size — the outline must carry
`sym_floor` symbols, the empty-prefix menu `item_floor` items — below
which the gate fails rather than measures. The same document and the
same `didOpen`-ratio method were used to measure every request that
landed in 0.3.5, and the numbers are in [CHANGELOG.md](../CHANGELOG.md)
`## 0.3.5` beside the change each one forced: the per-request
declaration index that replaced a first-byte bucket, and the
is-there-a-signature question the whole-document code action asks
before it walks. Run the gate and read its `ratio` lines for today's.
