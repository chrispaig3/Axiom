# The Axiom language server

`axiom lsp` gives your editor the same diagnostics `axiom check` prints,
plus navigation, hover, completion, formatting and fixes. This page
shows how to run it, how to connect Neovim, Helix, Emacs and VS Code,
and what each request answers and refuses. It ends with how
highlighting works and the cost rule the server follows.

The server is `self_host/lsp.ax`, one module of the self-hosted
compiler, and it handles the protocol and nothing else. Every
diagnostic it publishes comes from the same
`parseModuleWith`/`checkModule` pair that `axiom check` runs. Every
answer is read off the compiler's own parse tree.

Tested by `scripts/check-lsp-selfhost.sh`, which builds a server from
`self_host/` and drives it with `tests/lsp/drive.py`.

<a id="running-it"></a>
## Run the server

```bash
axiom lsp
```

That's the whole command line, and `axiom help lsp` says the same. The
server speaks JSON-RPC 2.0 over stdin and stdout, with the base
protocol's `Content-Length` framing. It takes no operand and no flags
of its own.

It writes nothing else to stdout, and nothing to stderr: a session of
`initialize`, `shutdown`, `exit` leaves stderr empty.

To try a session from a shell, when an editor's log isn't enough:

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

The first reply is the `initialize` result. It holds the capabilities
object that the rest of this page walks through, and a `serverInfo`
naming `axiom` and the compiler's version.

The exit status is `0` after a `shutdown`. It is `1` when the client
sends `exit` without one, or closes the pipe. The goldens under
`tests/lsp/` pin the framed byte stream of a fixed session,
capabilities included.

### How a session behaves

- Sync is full text: `textDocumentSync: 1`. Every `didChange` carries
  the whole document, and the server reads the last content change in
  the notification. The checker takes a whole source string anyway, so
  an incremental store would only be flattened again before each
  check.
- The server reads three notifications: `didOpen`, `didChange` and
  `didClose`. It drops `didSave`, as it drops any notification it
  doesn't know.
- Positions are UTF-16 code units, the protocol's default.
  `tests/lsp/030-utf16-columns.ax` pins this.
- A request the server doesn't know gets the error `-32601`
  (`method not found: <name>`). A notification it doesn't know is
  dropped, and so is a message that isn't JSON.
- `shutdown` is answered with `null`.
- There is one `initialize` per process, because there is no
  workspace-folder state to update.
- Memory stays flat across a session. The server resets its arena
  after every message, keeping the document store and the reader's
  unconsumed bytes. `drive.py`'s editing session edits one document
  many times and checks that the process doesn't grow.

### Diagnostics

The server publishes diagnostics on every `didOpen` and `didChange`,
under the document's own URI. They are `axiom check`'s diagnostics. As
in the compiler, the first stage that fails decides what you see:

1. a lexical error;
2. a parse error, with its span on the token that failed;
3. `AX5001`, for an import that doesn't resolve;
4. the expander's refusals alone, when it refuses;
5. otherwise, the expander's and the checker's diagnostics, merged in
   the compiler's order.

Each diagnostic carries its `AX` code as `code` and `axiom` as
`source`. It also carries everything the terminal prints about it: the
message's first line, the label drawn at the caret, and the `note:`
and `help:` paragraphs.

A secondary span is published as `relatedInformation`, which your
editor shows as a link. Examples are `AX3006`'s "first defined here"
and `AX3012`'s "`x` is bound here".

Only this document's diagnostics are published. A diagnostic the
checker raises inside an imported module isn't attributed to the file
that imports it. Open that module and you'll see it there. `didClose`
publishes an empty list, which is how a server clears its squiggles.

Tested against the manifest `tests/lsp/expected-diagnostics.txt`, and
by a comparison with `axiom check --diagnostic-format json` over every
fixture.

### Imports

The server resolves imports the way `axiom check` does, starting from
the file the URI names. It looks in the entry file's directory, then
in the `depend` and `crate` directories of an `axiom.pkg`, then in
`$AXIOM_PATH`. If `axiom check f.ax` finds the standard library from
the shell your editor launches, the server finds it too.

A half-typed `(import Fo` doesn't break anything. Requests are
answered from that document alone, never with an error response, and
the server keeps running. This works because `lspPreflight` in
`self_host/lsp.ax` walks the imports without failing before anything
resolves.

## Editor setup

Your editor can use two separate pieces, and it can have either one
without the other:

| | What it gives | Which editors use it |
|---|---|---|
| the language server (`axiom lsp`) | every request on this page: navigation, hover, completion, hints, formatting, fixes, expansion | all of them |
| the tree-sitter grammar ([`tree-sitter-axiom/`](../tree-sitter-axiom/README.md)) | all of the highlighting: `highlights.scm` colours by syntactic role, and `rainbows.scm` colours bracket pairs by depth | Helix, Neovim (nvim-treesitter), Emacs 29+ (`treesit`), Zed, the `tree-sitter` CLI |

The server colours nothing, because it offers no semantic tokens. See
[Highlighting](#highlighting) for why. With the server attached and no
grammar installed, a buffer stays plain text, however well every
request is answered. Install the grammar to get colour.

VS Code has no tree-sitter, so its highlighting needs a TextMate
grammar, which this repository doesn't ship. The Neovim, Helix and
VS Code sections each end with a check that tells you which of the two
pieces you have.

The editor finds the server through its `PATH`, so `axiom` must be on
it. Otherwise, write the absolute path where the configurations below
say `"axiom"`.

Source files end in `.ax`. The server doesn't read the `languageId` a
client sends, so name the filetype whatever your editor wants. The
configurations below call it `axiom`.

The two code-lens commands, `axiom.run` and `axiom.expandMacro`, are
the client's to define (see [Changing and running](#changing-and-running)).
Each configuration below defines them where the editor can.

### Neovim

Neovim's built-in client handles every request, and nvim-treesitter
provides the colour. Nothing in the client configuration turns
highlighting on, because highlighting isn't the server's job. The
grammar block further down is what colours the buffer.

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

To check the client, open a `.ax` file and run `:checkhealth vim.lsp`.
The client should be listed as attached.

For colour, register the grammar with nvim-treesitter, pointed at
`tree-sitter-axiom/` in a checkout:

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

To check the colour, run `:Inspect` on any identifier. It should name
an `@...axiom` capture, such as `@function.call.axiom`. If
`:TSInstall axiom` fails, or `:Inspect` shows no treesitter capture,
the grammar isn't built for this Neovim.

For rainbow brackets, point rainbow-delimiters.nvim at
`queries/rainbows.scm`, and it reads the capture names there.

### Helix

Helix highlights with tree-sitter alone and doesn't use code lenses.
So every colour comes from the grammar, and the two lens commands are
out of reach. The built-in client handles everything else: definition,
references, rename, hover, completion, signature help, inlay hints,
document and workspace symbols, formatting and code actions.

You need three parts in place: the server, the compiled grammar, and
the highlight queries in the runtime directory. `hx --health axiom`
tells you which ones are. Start with the configuration:

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

**Don't set `formatter` for this language.** Helix formats by piping
the buffer through a command's standard input. `axiom fmt` rewrites a
file in place and has no `--stdin`, so a
`formatter = { command = "axiom fmt", args = ["--stdin"] }` line can't
work.

A configured formatter also takes precedence over the language
server, so that line turns off the formatting that does work.
`hx --health axiom` reports it as `✘ 'axiom fmt' not found in $PATH`,
because Helix reads the whole string as one command name. With no
`formatter` line, `auto-format` uses the server's
`textDocument/formatting`, which runs the same `fmtFormat` as the
command.

Then build the grammar and install the queries. Helix loads queries
from its runtime directory, not from the grammar's own `queries/`:

```bash
mkdir -p ~/.config/helix/runtime/queries/axiom
cp /path/to/axiom/tree-sitter-axiom/queries/highlights.scm \
   /path/to/axiom/tree-sitter-axiom/queries/rainbows.scm \
   ~/.config/helix/runtime/queries/axiom/
hx --grammar build            # compiles the [[grammar]] entries above
```

Always check the result. `hx --health axiom` must show a green tick
for the server, the parser and the highlight queries:

```text
Configured language servers:
  ✓ axiom: /path/to/axiom
Configured formatter: None          <- correct; the server formats
Tree-sitter parser: ✓
Highlight queries: ✓
Rainbow queries: ✓
```

`Tree-sitter parser: None` or `Highlight queries: ✘` means the buffer
renders as plain text, whatever the language server answers. That's
the whole failure mode: the server can be attached and answering every
request while nothing in the file is coloured.

Rainbow brackets colour every `(`, `[` and `{` pair by its nesting
depth, using `rainbows.scm`. They're off until
`~/.config/helix/config.toml` says `[editor] rainbow-brackets = true`.

Capture names in `highlights.scm` follow nvim-treesitter's convention.
When a theme doesn't name a scope, Helix trims its last segment:
`@keyword.modifier` falls back to `keyword`, and `@number.float` to
`number`. So a theme that names only the coarse scopes still colours
everything, and one that names the fine scopes colours it more
precisely.

Inlay hints are off until `~/.config/helix/config.toml` says:

```toml
[editor.lsp]
display-inlay-hints = true
```

### Emacs (eglot)

Eglot is part of Emacs 29 and later. It doesn't use code lenses, so the
`Run` lens isn't available. `lsp-mode` does support lenses, through
`lsp-lens-mode`, and you configure it the same way with
`lsp-register-client`.

Highlighting comes from the major mode. Emacs 29's `treesit` can load
the grammar built from `tree-sitter-axiom/`, and use the captures in
`highlights.scm` through a `treesit-font-lock-rules` mapping.

In Eglot, definition is `M-.` and references are `M-?`. Hover and
signature help come through `eldoc`, and the outline is `imenu`.
`eglot-rename`, `eglot-code-actions` and `eglot-format-buffer` cover
the rest.

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

There is no published Axiom extension. You can build one from the two
files below, `package.json` and `extension.js`, in a directory of their
own. Run `npm install`, open the directory in VS Code, and press F5.
That starts an Extension Development Host with the extension loaded.

`vscode-languageclient` asks the server for inlay hints, code lenses
and everything else it advertises, with no extra setup. The two
commands are the only code that isn't boilerplate.

Highlighting isn't included. VS Code has no tree-sitter, and the
server doesn't send semantic tokens. [Highlighting](#highlighting)
explains why that's settled. So a `.ax` file stays uncoloured until
the extension contributes a TextMate grammar, which this repository
doesn't ship.

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

To check the client, open a `.ax` file in the Extension Development
Host and hover a function name. A tooltip quoting its `(:: f T)`
signature means the client connected. If it didn't, the *Output*
panel's *Axiom* channel shows the server's stderr.

Colour is a separate check. *Developer: Inspect Editor Tokens and
Scopes* shows a TextMate scope only once a grammar is contributed
under `contributes.grammars`. Without one, the row reads *no grammar*.
You'll also want a `language-configuration.json` that names `;` as the
line comment and lists the bracket pairs.

## What each request answers

The requests below fall into three groups: navigation, reading, and
changing and running. The editor-only lint hints come last. Each paragraph
says what a request answers, what it doesn't, and where its check
lives in `tests/lsp/drive.py`. Search that file for the marker
comments `SECTION NAV TESTS`, `SECTION VIEW TESTS` and
`SECTION FIX TESTS`.

Those checks compute each expected answer from a document the driver
writes itself, so re-blessing a golden can't satisfy them.

Two things hold for every request that takes a position:

- One string- and comment-aware scanner (`lspWordSpan`, `lspFormEnd`)
  finds the word under the cursor, so no two requests disagree about
  where a form ends.
- A document that doesn't parse answers `null` or `[]`. The exceptions
  are the requests that work from the bytes, which are named below.

The sweep at the end of `scripts/check-lsp-selfhost.sh` checks that
requests survive awkward positions. It fires every advertised request
at every 97th byte of a real standard-library module, and at the
positions that break scanners: offset 0, EOF, one past EOF, a line
past the end, inside a string, inside a comment, on `(` and on `)`.

It does the same on that module cut off mid-form, and on an empty
document. Every id must get an answer with no error, and the server
must still be alive to answer `shutdown`. The sweep builds its method
table from the capabilities the server advertises, so a capability it
can't build a request for fails the gate.

The examples below use this document. It checks clean, and the answers
quoted come from the release binary.

```scheme
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

#### Go to definition

`textDocument/definition` jumps to where the name under the cursor is
bound. It searches in the language's own scope order:

1. The innermost local binding: a `let` name, a `fn` or `lambda`
   parameter, or a pattern variable. The answer lands on the binder.
2. This document's declarations.
3. The merged declarations of every module this document imports. The
   answer is a `Location` in that module's own file.

A macro invocation is a reference to its `macro` declaration
(`MAC-TOOL-2` in [macro-system.md](macro-system.md)).

A constructor is a declaration too. Its definition is the constructor's
own name inside the `data`: `Green` in `(data Colour (Red) (Green))`,
not `Colour`. That holds from a pattern head, from an application, from
the declaration itself, and from another document that imports it.

A builtin (`Int`, `+`), a keyword and a name nothing declares answer
`null`. A name a macro would generate has no definition, because
nothing has expanded it. An import that doesn't resolve narrows the
search to this document instead of failing it.

#### Go to declaration

`textDocument/declaration` jumps to the `(:: f T)` signature. In Axiom
this is a different place from the definition, because a function is
written twice:

```scheme
(:: bump (-> Int Int))
(fn (bump x) (+ x 1))
```

The parser keeps both forms, each with its own name span. So
`declaration` on any occurrence of `bump` lands on the `::`, and
`definition` lands on the `fn` below it.

The search order is `definition`'s with one extra step: a local
binding, then this document's `::`, then this document's declaration
of the name, then the imported modules, signature first.

A `data`, a `struct`, a macro, a constructor and a local are written
only once, so for them the two requests give the same answer. There is
one place where `declaration` answers and `definition` can't: a
signature whose `fn` isn't written yet. That's what an editor sees
mid-keystroke, and what `AX3015` reports.

It answers `null` for a keyword, a builtin, a name nothing declares and
a document that doesn't parse.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`, which asks both
requests at the same position. The ranges must differ at a `fn` and
match at a constructor.

#### Call hierarchy

`textDocument/prepareCallHierarchy`, `callHierarchy/incomingCalls` and
`callHierarchy/outgoingCalls` show who calls a function and what it
calls.

A call site is an occurrence that the scope-aware walk resolves to a
top-level name *and* that stands in the head position of a form. That
rule gets right two cases that a spelling match gets wrong:

- `(fn (apply k v) (k v))` calls the parameter `k`, not a top-level
  `fn` named `k`, so neither direction reports an edge.
- `(fn (handoff z) helper)` names `helper` without applying it, so it
  isn't among `helper`'s callers.

Incoming calls read this document and every other open document whose
imports resolve to this file, the same workspace `references` uses. A
caller that calls twice is one entry with two ranges.

Outgoing calls name every callee the server can point at: one this
document declares, or one an imported module declares, resolved the
way `definition` resolves it. They leave out builtins, operators and
constructors.

`prepareCallHierarchy` answers `null` for a local, for a `data`,
`struct` or macro, for a document that doesn't parse, and for an
imported name. The two follow-up requests carry only the item, so go to
the definition first and ask there. An item whose document the server
hasn't opened answers `null`, not `[]`. An empty list would claim the
function has no callers, and the server can't know that without reading
the file.

Call hierarchy differs from `axiom symbols --calls`. That key is the
checker's edge set, taken from the effect walk, so it costs a full
typecheck and carries no positions. For `handoff` above it reports
`#calls=helper`, although the body never applies `helper`. Call
hierarchy has to send ranges (`CallHierarchyIncomingCall.fromRanges`).
The two agree where they overlap, and call hierarchy's edges are a
strict subset.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`, whose documents
contain both of the shapes above.

#### Type hierarchy

`textDocument/prepareTypeHierarchy`, `typeHierarchy/supertypes` and
`typeHierarchy/subtypes` show what a type derives from and what derives
from it.

The graph has one kind of edge: a `subtype` derives from its base. A
range check runs at every narrowing conversion and widening is free, so
a `Positive` is an `Int` in one direction only. Nothing else is an
edge:

- Constructors are values, not types. The outline lists them as
  children, and `definition` finds them.
- A `struct` field is a member, not a derivation.
- An alias is transparent, because the checker expands it. A parent and
  child direction over `Age = Int` would be arbitrary.

The graph is two levels deep for now, because the checker accepts only
bare `Int` as a base. The requests are written for the general case: a
base that names a declared type resolves to that declaration by the
same rule that resolves it to a builtin item today.

The nodes are the four type declarations (`data`, `struct`, `type` and
`subtype`) plus the builtin type names.
A builtin item is anchored at the word that named it, since it has no
declaration to point at. A declaration shadows a builtin of the same
spelling.

- `prepareTypeHierarchy` answers for a type named in this document or
  an imported one.
- `supertypes` of a subtype is its base. A `data`, `struct`, alias or
  builtin derives from nothing, so it answers `[]`.
- `subtypes` searches the open documents for `subtype` declarations
  that constrain the item. It looks in the item's own document first,
  then the rest in the order they were opened.

A local, a constructor, an effect name and a `fn` answer `null`. So
does an item nothing declares, or whose document isn't open or doesn't
parse. An empty list would claim the type stands alone, which the
server can't know without reading the file.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`. There the
supertype anchor is the `Int` of the subtype's own `is Int range`, and
`references` on the `Positive` binder finds the binder, the signature
use and the `cast` target.

#### Find references and highlights

`textDocument/references` and `textDocument/documentHighlight` find
every occurrence of the same *binding*, not the same spelling. The walk
records each occurrence with the key of what it resolves to. So the `i`
of one function isn't the `i` of another, and a `let` that shadows a
parameter is a different name from it.

Type positions are the names inside every `::`, `data`, `struct` and
`type` form. Type nodes carry no span, so these names are read from the
bytes and resolved against the type table alone. A `fn` spelled like a
`data` isn't the same name.

`references` reaches every other open document whose imports resolve
to this file, each under its own URI, and honours
`includeDeclaration`. It doesn't open files your editor hasn't, so a
reference in a closed module isn't listed.

`documentHighlight` is the same set within one document. The binder has
the `Write` kind and reads have `Read`.

A form the parser desugars contributes only what you wrote:

- A binder whose name holds `$`, such as `for$v` or `for$i`, is never
  recorded. `AX1001` stops you writing that name yourself.
- A reference is recorded only where the document's bytes at its span
  spell its bare name. That drops the loop's `Vec$vecGet` read and the
  `<` and `+` it emits on the keyword. It keeps your own `Vec::vecLen`
  and a template's `IO$writeStr`, which is what `println`'s `writeStr`
  is rewritten to.

So `documentHighlight` and `prepareRename` at the word `for` answer
`null`, as they do at `while`.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`: a parameter with
and without its declaration, a `let` from its read, a type in a
signature, a struct field and an alias.

#### Rename

`textDocument/prepareRename` answers the word's range for a name the
server will rename. It answers `null` for:

- a name declared in another module, even an open one. Renaming across
  files the server didn't open would leave a broken workspace, and a
  client must never rename a standard-library name.
- a builtin, an effect, a keyword or `_`.
- a parameter whose position can't be recovered from the header's
  bytes.

`textDocument/rename` refuses these new names with `null`:

- a name the lexer wouldn't read as one identifier.
- a keyword.
- the old name itself.
- a collision. For a local, that's a name already bound in the same or
  an enclosing scope, or one the renamed binding would capture. A second
  walk with a probe decides this, inside the scope stack. For a
  declaration, it's a name this document or any importing document
  already spells anywhere, because a rename that makes a call resolve
  somewhere else changes what the program means.

The edit covers every open importing document.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`, which applies a
cross-file rename, writes both files, reopens them and requires the
checker to report nothing for the pair.

#### Go to type definition

`textDocument/typeDefinition` jumps to the `data`, `struct` or `type`
that declares a value's type, in this document or an imported one. It
works from a function's result when the function has a `::` signature,
from a header parameter, and from a constructor.

On a constructor it's the one request that answers the `data`, because
the type of `Green` is `Colour`. `definition` at the same character
answers `Green`.

It answers `null` for a builtin type, for a `fn` with no `::`, and for
any other position.

Tested by `SECTION NAV TESTS` in `tests/lsp/drive.py`, which asks both
requests at a constructor and requires the answers to differ.

### Reading

#### Hover

`textDocument/hover` answers Markdown: an `axiom` fence quoting the
declaration, the module below it when the name was imported, and the
comment paragraph written above the declaration.

- A `fn` is quoted as its `(:: f T)` signature, not its body. Its
  paragraph is read from above the signature, because that's where
  Axiom puts it. A `fn` with no signature is quoted as its first line.
- A `data`, `struct` or `macro` is quoted whole, cut to a tooltip's
  height by `lspClampLines`.

A constructor is quoted as the whole `data` that declares it, since its
siblings and field types are what you want to see. One line under the
fence names the constructor under the cursor:

```text
(data Colour
  (Red)
  (Green))

constructor `Green` of `Colour`
```

The module comes below that, when the `data` came from another file.

A field works the same way, at a use and where it's declared.
`base.field` resolves as a path. A parameter's struct comes from the
owning signature, and a `let`'s from the constructor application its
value builds. The fence quotes the whole `struct`, with one line naming
the field:

```text
(struct Point (x : Int) (y : Int))

field `x` of `struct Point`
```

When the path can't be resolved, hover answers `null` instead of
guessing. That covers a lambda parameter, a call result, a name from
another module and a `data` payload, which isn't a field.

A local answers from the walk. A parameter of `bump` answers this, with
the type cut from the signature's arrow:

```text
x : Int

parameter of `bump`
```

A `let` answers its binding pair, with the value's shape under it when
the walk knows one. Here `(ph (+ ph 1))` gets `ph : Int` from the
checker's own row for `+`:

```text
(ph (+ ph 1))
ph : Int

bound by `let` in `area`
```

The shape is read off the raw tree and never elaborated. It comes from
a literal's kind, a `::` call's result, a constructor's `data`, a
builtin's row, or a variable through its binder. When the walk can't
tell, as for a name from another module, a `lambda` or a parameter the
call leaves unbound, the pair is shown on its own with no guess.

The `range` is the word under the cursor, not the declaration, which
for an imported name is in a different file. Hover answers `null` for a
builtin, a keyword or a name nothing declares.

Tested by `tests/lsp/drive.py`, which cuts every quoted form and
paragraph out of the document with its own Python copy of
`lspFormText` and `lspDocComment`. `SECTION NAV TESTS` takes every
expected shape from the modules that declare it.

#### Completion

`textDocument/completion` offers, in this order:

1. The head keywords the parser dispatches on.
2. This document's declarations, and the constructors its `data` forms
   name.
3. Every imported module's declarations, under their bare names.

A local name shadows an imported one, and both shadow a keyword. The
keyword list in `lsp.ax` is checked against the `kwEq` call sites in
`self_host/parser.ax`, so the two can't drift apart.

The list is filtered on the prefix under the cursor and capped at
`LSP_COMPL_MAX`. It's sent with `isIncomplete: true`, which tells the
client to ask again on the next keystroke. `(` is the trigger
character.

A document that doesn't parse still completes keywords. That's the
normal case, since a file is unparseable exactly while a form is half
written.

Completion doesn't offer a name a macro would generate:
`(deriveTag Colour)` doesn't put `tagColour` in the menu. The tests
check that it's absent.

#### Signature help

`textDocument/signatureHelp` shows the call the cursor is inside. That
can be a `fn` of this document, one of its constructors, or an imported
`fn` with its module named. The label reads `(bump x) : (-> Int Int)`,
with the type cut from the `::` beside the `fn`.

- Each parameter is sent as the UTF-16 offset pair that slices the
  label to its name.
- The paragraph above the declaration is the `documentation`.
- `activeParameter` is counted from the bytes.

`(` and space trigger it, and space retriggers it. A local that shadows
a top-level `fn` of the same name is looked up first, so
`(fn (t7 f) (f 1 2))` beside a top-level `f` answers nothing for `f`. A
`fn` header doesn't answer its own signature. Outside any call, the
answer is `null`.

#### Inlay hints

`textDocument/inlayHint` shows four hints the source doesn't spell out:

| Hint | Where | Kind |
|---|---|---|
| `x:` | Before each argument of a call to a declared or imported `fn`, but never before a variable spelled like the parameter | `Parameter` |
| `: Int` | After each parameter in a `fn` header | `Type` |
| ` -> Int` | After the `fn` header | `Type` |
| `: T` | After each `let` or `letm` binder whose value resolves | `Type` |

The header hints come from the signature's arrow, so a `fn` with no
`::` gets no type hints. The binder hints come from the value-shape
reader that hover uses, so generated binders and `_` get none.

#### Folding ranges

`textDocument/foldingRange` folds every form and brace block whose
opener and closer sit on different lines. A run of `;` comment lines
folds as kind `comment`, and a run of imports as kind `imports`. It
works from a bracket scan of the bytes, so a half-typed file still
folds.

#### Selection ranges

`textDocument/selectionRange` expands from the word to the enclosing
form, then to each form around it, then to the whole document. It
answers for each position sent.

#### Document links

`textDocument/documentLink` gives one link per `(import M)` whose
module the resolver's own search finds. The link covers the dotted name
as written and targets that file. An import that doesn't resolve gets
no link and no error. `resolveProvider` is false.

#### Outline

`textDocument/documentSymbol` answers the outline straight from the
parse tree, with no checker running. A file with a type error still has
an outline, and a file that doesn't parse has an empty one.

| Declaration | Symbol kind |
|---|---|
| `fn`, `macro` | `Function` |
| `data` | `Enum` |
| `struct` | `Struct` |
| `type` alias | `Class` |
| A `data`'s constructor | `EnumMember`, as a child of the `data` |
| A `struct`'s field | `Field`, as a child of the `struct` |

The protocol has no `TypeAlias` kind, so an alias becomes `Class`, just
as a macro becomes `Function`. A `::` signature isn't listed beside its
`fn`, and neither is an `effect` declaration.

`range` is the whole top-level form, and `selectionRange` is the name
inside it. Your editor uses `range` for the breadcrumb, sticky scroll
and expanding a selection. The server finds the form's extent from the
bytes, with the same `lspFormStart` and `lspFormEnd` pair that hover
quotes a declaration with.

Sometimes it can't. A declaration indented mid-edit gives
`lspFormStart`'s column-zero rule nothing to find. Then the symbol's
`range` is just the name span and it has no children. That's better
than a range that doesn't contain what it claims to.

Each child sits at its own name span. `children` is left out, not sent
empty, so no client draws an expander over nothing.

`tests/lsp/expected-outline.txt` lists exactly the rows each fixture
publishes, in order, with the container each belongs to.
`tests/lsp/060-outline.ax` is the fixture with a `data` and a `struct`
that have members. Four invariants hold for every symbol of every
document, with no row in that file needed:

- `selectionRange` is inside `range`.
- A symbol with children contains its own `selectionRange` strictly.
- Every child is inside its parent.
- The source at `selectionRange` spells the symbol's name.

#### Workspace symbols

`workspace/symbol` finds every declaration the open documents can see,
their own and those of every module each imports, whose bare name
contains the query, case-folded. Constructors are `EnumMember` and
aliases are `Class`. An imported declaration has its module as
`containerName`. A declaration reached through two open documents is
listed once.

The workspace is the server's document store. The server doesn't walk
a directory, so a module that nothing open imports isn't searched. The
list stops at `LSP_COMPL_MAX`.

Signature help, inlay hints, folding ranges, selection ranges, document
links and workspace symbols are tested by `SECTION VIEW TESTS` in
`tests/lsp/drive.py`.

### Changing and running

#### Formatting

`textDocument/formatting` answers one `TextEdit` over the whole
document, holding the output of the same `fmtFormat` that `axiom fmt`
runs. The edit's text is byte for byte what `axiom fmt` writes. A
document already in the formatter's normal form gets `[]`, and one that
doesn't parse gets `null`.

`textDocument/rangeFormatting` isn't offered. `fmtFormat` proves its
output is a fixed point of the whole file, and a slice formatted alone
doesn't always give the same bytes. Across `stdlib/` and `self_host/`,
a few runs of top-level forms formatted differently alone than inside
their file. Every difference was about where a comment lands:

- A trailing comment such as `(pub :: SGR_ERROR String)  ; bold red`
  stays on its line when the slice is formatted, and moves to the next
  declaration when the whole file is.
- A comment block inside `codegen.ax`'s `CG` struct moves across a
  top-level form boundary in the whole-document pass, and stays put in
  the slice.

With format-on-save and format-selection both bound, each would
rewrite bytes the other had just written. So whole-document formatting
is the only formatting the server does.

#### Code actions

`textDocument/codeAction` offers three kinds, all advertised in
`codeActionKinds`: `quickfix`, `refactor.rewrite` and
`refactor.extract`.

Every machine-applicable fix the compiler attaches to a diagnostic in
the range is offered as a preferred `quickfix`. That's a help carrying a
fix span, exactly what AXDL prints after `~>`. So when a code gains a
fix in `typecheck.ax`, it gains a quick fix with no change to `lsp.ax`.

The server also writes these assists itself:

| Action | Kind | Offered on |
|---|---|---|
| *Import `name` from `Mod`* | `quickfix` | An `AX3001` whose reference is a bare name |
| *Make `name` public in `Mod`* | `quickfix` | `AX3023` |
| *Suppress `RULE` on `F`* | `quickfix` | Every live lint Hint |
| *Treat unhandled `E` as a deliberate abort* | `quickfix` | An `AX3053` whose effect this document declares |
| *Add type signature for `f`* | `refactor.rewrite` | A `fn` with no `::` |
| *Simplify to `c`* | `refactor.rewrite` | The `lint-bool-if` Hint |
| *Extract to `let`* | `refactor.extract` | A selected range, with no diagnostic |

This request runs the pipeline for the kinds attached to diagnostics
(see [The cost rule](#the-cost-rule)), and reads the raw tree for
extraction. It answers `[]` on a document that doesn't parse.

*Import `name` from `Mod`* looks at every module the resolver could
reach: the entry file's directory, `axiom.pkg`'s `depend` and `crate`
directories, `AXIOM_PATH` and `AXIOM_STDLIB`. Each is walked three
levels deep, to find a nested module such as `Sys.Platform`. Each
candidate gets the name `moduleSrcPath` would resolve it by, so a
`Str.ax` beside the entry file shadows the standard library's, exactly
as it does for the compiler. A file is parsed only when its bytes spell
the name as a whole word, and one action is offered per module that
declares the name `pub`.

The edit adds the name to an existing `(import Mod (...))` list.
Otherwise it writes `(import Mod (name))` on its own line after the
last import, or as the first line. A qualified `Mod::name` gets no
action, because it already names its module.

*Make `name` public in `Mod`* is a `WorkspaceEdit` keyed by the
declaring file's URI. It inserts `pub ` after the opening paren of the
`fn` and of its `::`, since `check` refuses either alone. The server
reads what visibility is written from that file's bytes. An `AX3023` on
a name that *is* written `pub` means the document's import list left it
out, so it gets the import action instead.

*Add type signature for `f`* is written from the type the checker
inferred, in the parser's own spelling, such as `(-> Int Int)`. An
unresolved type variable is lettered in order of appearance.

*Extract to `let`* is offered when the range, trimmed of whitespace, is
exactly one item inside the body of a `fn` in this document. An item is
a form, a brace block, a literal or an identifier. The expression `E`
is hoisted above a statement `S`: the innermost enclosing item that is
a direct child of a `{ }` block, or else the `fn` body. `S` becomes
`(let ((x E)) S')`, with `x` in place of `E`. The name `x` is
`extracted`, or the first `extractedN` the document doesn't already
spell.

Extraction is refused wherever hoisting would change how often, or
whether, `E` runs:

- under a `lambda`, `while` or `handle`.
- in a branch of an `if` or an arm of a `match`. The test and the
  scrutinee are fine.
- in a head position or a binding list.
- past the first operand of a `for`.
- whenever `E` references a binder bound inside the statement.

A `for`'s first operand, the container or a range's start, is hoisted
into a binding the loop reads once, so it stays extractable. The third
item is `hi` in one `for` shape and the body in the other. The rule
sees the head and the position but not the arity, so it refuses both.

Extraction does make one change: `E` now runs before whatever the
statement evaluated ahead of it.

*Suppress `RULE` on `F`* puts `;@axiom:nolint(RULE)` on its own line
above the declaration. It's offered once per declaration and rule, so
two unread bindings in one body give two suppressions with different
owners, not two copies of one action. It's never offered for a Hint the
client can't see, since suppressed records never reach the assist walk.

*Simplify to `c`* replaces the whole `(if c true false)` with the
condition's own bytes. The edit uses the lint's own guards. A dead
branch gets no rewrite, because a live arm has no exact span to write
back.

*Treat unhandled `E` as a deliberate abort* puts
`;@axiom:unhandled(trap)` above the `(effect E ...)` line. It never
edits another file, and it's never offered when an `unhandled` tag of
any value is already there. It silences exactly that one warning, and
the program still traps with 71.

Tested by `SECTION FIX TESTS` in `tests/lsp/drive.py`. It applies
`AX3012`'s `mut x` at the binder, `AX3001`'s respelling at the call and
the signature assist, and requires no diagnostics after reopening. It
requires `check` to answer OK after each import and `pub ` edit. Each
suppression must reopen silent, and the extracted and simplified
programs must keep the original's output and exit status.

#### Code lenses

`textDocument/codeLens` puts a `▶ Run` lens over `(fn (main) ...)` when
`main` takes no parameters, since that's what `axiom run` runs. It puts
an `Expand macro` lens over every `pub macro`.

A lens carries a command name and its arguments, and the server runs
nothing. `axiom.run` carries the document's filesystem path.
`axiom.expandMacro` carries the document's URI and the macro
declaration's position. Your editor does the rest, the way
rust-analyzer's `Run` lens works. On the example document:

```json
{"range": {"start": {"line": 3, "character": 11}, "end": {"line": 3, "character": 20}},
 "command": {"title": "Expand macro", "command": "axiom.expandMacro",
             "arguments": ["file:///path/to/doc.ax", {"line": 3, "character": 11}]}}
{"range": {"start": {"line": 19, "character": 5}, "end": {"line": 19, "character": 9}},
 "command": {"title": "▶ Run", "command": "axiom.run",
             "arguments": ["/path/to/doc.ax"]}}
```

`resolveProvider` is false. A document that doesn't parse gets `[]`.

#### Macro expansion

`axiom/expandMacro` is the analogue of `rust-analyzer/expandMacro`,
advertised as `experimental.expandMacro: true`. Its params are a text
document and a position:

```json
{"textDocument": {"uri": "file:///path/to/doc.ax"},
 "position": {"line": 12, "character": 0}}
```

The result is the macro's name and what it generated, as Axiom source,
or `null`:

```json
{"name": "deriveTag",
 "expansion": "(pub :: tagColour Int)\n\n(pub fn (tagColour)\n  7)"}
```

On a top-level invocation, at its head or anywhere inside its bytes, it
answers that invocation's own products. On a macro declaration, at its
name or anywhere in its form, it answers everything the macro generated
in this document.

The expansion is printed by the compiler's first `ASTNode`-to-source
printer, which promises that the output parses and means what the tree
meant. The printer changes three spellings:

- A hygiene binder `x.3` is written `x_3`.
- A `syntax/binders` variable `x#0` is written with `_` for every byte
  the lexer refuses.
- `Mod$name` is written `Mod::name`.

A generated `struct`'s fields print with their types. The note beside
`MAC-TOOL-3` in [macro-system.md](macro-system.md) has the details.

It answers `null` for:

- An invocation in expression position inside a body. Phase E rewrites
  it in place and records nothing to attribute.
- An expansion the expander refused. The refusal is already on screen
  as a diagnostic.
- A position on anything else, and a document that doesn't parse.

Each invocation is expanded with every other invocation removed. So a
macro whose template queries declarations another invocation would have
generated is shown without them.

Tested by `tests/lsp/drive.py`, which reopens each expansion as a
document and requires a clean parse with an outline of exactly the
generated name. It also splices every top-level invocation's expansion
under `tests/` and `docs/` into a copy in its place, and requires
`check`'s codes and `symbols`' names to stay the same.

### Lint hints

On top of the checker's diagnostics, the server adds three lint Hints
to every document that parses. `axiom check` never emits them. They
have severity `Hint`, they're on for every document, and they never
fail a build. A Hint is your editor thinking out loud, so it lives in
the server. The checker's warnings are what the project promises about
every build.

The lints read the raw tree and expand nothing. They see what you
wrote, not what it expands to, so a lint can never disagree with the
checker about what your code means.

- `lint-dead-branch`: `(if true A B)` or `(if false A B)`. One arm can
  never run. This is usually a condition left literal while debugging,
  or a copy-pasted arm. The squiggle sits on the literal. A `while`
  with a literal condition isn't linted, because an infinite loop is a
  normal idiom.
- `lint-bool-if`: `(if c true false)` where `c` is a bare name. The
  `if` returns its condition unchanged. The reverse,
  `(if c false true)`, isn't linted. Axiom has no `not` operator, so
  that form is how you write boolean negation, and `stdlib/Http.ax`
  spells `httpNot` exactly that way.
- `lint-unused-let`: a `let` or `mut` binding that nothing reads. This
  is usually a forgotten use or a leftover. Only reads keep a binding
  alive, so a binding that is written but never read still draws the
  Hint. `_` is the explicit discard and stays silent, as do pattern
  binders, parameters and anything inside a macro body.

Three rules keep the lints precise:

- A lint that can't point precisely doesn't fire. Every range spells
  exactly what its message quotes.
- A `true` that you rebound with a `let` isn't the boolean.
- The lint walk recurses into every expression form the navigation
  walk knows, because a missed use would be a false positive.

To opt out, put one tag above either half of the declaration, the
signature or the `fn`:

```scheme
;@axiom:nolint(lint-dead-branch)
(:: quietIf (-> Int Int))
(fn (quietIf n)
  (if true n 0))
```

`;@axiom:nolint(RULE)` quiets one rule, and `;@axiom:nolint(all)`
quiets all three. The tag syntax is in
[the reference](reference.md#nolint---quieting-the-editors-hints).

Tested by `tests/lsp/100-lint-dead-branch.ax` through
`tests/lsp/103-lint-nolint.ax`, each with controls that must stay silent.

#### Code actions for hints

Each Hint comes with a code action that clears it, and one checker
warning has its own:

- `Suppress RULE on F` writes the `nolint` tag above the declaration,
  in the same place `103-lint-nolint.ax` puts it. It's offered once
  per declaration and rule, and only where the Hint is drawn. A Hint
  that's already suppressed gets no action, since your editor can't
  see it.
- `Simplify to C` rewrites `(if c true false)` to its condition. It
  follows the lint's own guards. A dead branch gets no rewrite, because
  a live arm has no exact span to write back, so use the suppression
  there.
- On AX3053, an effect operation with no handler,
  `Treat unhandled E as a deliberate abort` writes
  `;@axiom:unhandled(trap)` above this document's own `(effect E ...)`
  declaration. It never edits another file, and it never writes beside
  an `unhandled` tag of any value that's already there.

Tested by the code-action session in `tests/lsp/drive.py`. It checks
the exact edits, that suppressed documents reopen silent, that the
simplified program still exits 11, and that the acknowledgement
silences exactly one warning while the program still traps 71.

## Highlighting

The server doesn't send `textDocument/semanticTokens`, and we don't
plan to add it. Highlighting comes only from
`tree-sitter-axiom/queries/highlights.scm`. Two sources of colour can
disagree about the same token, and one can't. A single highlighter
means your editor never contradicts itself, and there's no second
highlighter to keep in step with the grammar.

`highlights.scm` colours by syntactic role:

- a declaration's name by what it declares;
- an application's head as a call;
- a constructor in a pattern as a constructor;
- an AXTAG as an attribute, not a comment.

`queries/rainbows.scm` colours each bracket pair by its nesting depth,
with every bracket-opening rule of the grammar as a scope.
`scripts/check-tree-sitter.sh` tests both against every `.ax` file in
the repository.

Editors that use tree-sitter (Helix, Neovim, Emacs 29 and Zed) get all
of this. VS Code reads semantic tokens but not tree-sitter, so it gets
no highlighting from this repository.

The REPL is the one place that colours Axiom another way.
`self_host/replhl.ax` paints source from the compiler's own lexer,
because a REPL has no tree-sitter grammar loaded and no editor to
consult. An editor has both, and a second opinion there would only let
the two drift apart.

## The cost rule

Every request your editor sends per keystroke or per cursor move reads
the raw parse tree and the document's bytes, and expands no macros.
This is `MAC-TOOL-3` in [macro-system.md](macro-system.md), which
gives the measured reason: expansion is bounded but not free, and an
editor can't wait.

Each such request costs one parse, one line index and one walk.
Requests share their walks:

- `references` and its siblings share one walk;
- folding and selection share the bracket scan;
- parameter hints and signature help share the bucket index.

Answers come from what the file says. A name that a macro would
generate doesn't appear in completion, the outline or navigation.

Three things run the full pipeline, because its output is the answer:

- `didOpen` and `didChange`, which publish diagnostics. A diagnostic
  about generated code is exactly what expansion is for.
- `codeAction`, because a quickfix is a checker diagnostic's own fix,
  and the assist writes what the checker inferred.
- `axiom/expandMacro`, because showing what a macro generated is the
  question being asked.

None of the three is sent per keystroke. A client asks for code
actions when the cursor rests, and for an expansion on demand. Each
costs about one `didOpen` of the same document, which the editor
already paid for on the last keystroke.

`scripts/check-lsp-selfhost.sh` holds the rule with a ratio instead of
a stopwatch, so a slow runner can't fail it and a fast one can't hide a
regression. It generates a document with at least `sym_floor`
declarations and times `didOpen`, the whole parse and check. It then
times `documentSymbol`, and `completion` with an empty and a filtered
prefix. The gate fails if any of them costs more than 2.00x the
`didOpen`.

A server that answers nothing is fast, so each measurement also has a
floor on the answer's size. The outline must carry `sym_floor` symbols
and the empty-prefix menu `item_floor` items, or the gate fails instead
of measuring. Run the gate and read its `ratio` lines for current
numbers. The measurements for each request added in 0.3.5 are in
[CHANGELOG.md](../CHANGELOG.md) under `## 0.3.5`.
