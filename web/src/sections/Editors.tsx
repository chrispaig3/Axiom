import { DOCS, stat } from '../data/site.ts'

/**
 * The toolchain, in one band.
 *
 * The subcommand list is `axiom --help` verbatim, minus `help` itself.
 * The editor facts are docs/lsp.md's "Editor setup" table, which is
 * careful about a distinction repeated here: the server answers requests
 * and colours nothing; the tree-sitter grammar does all of the
 * highlighting. VS Code gets the server but not the colours, because it
 * has no tree-sitter and this repository ships no TextMate grammar.
 */
const COMMANDS = [
  'build',
  'check',
  'run',
  'test',
  'emit-llvm',
  'fmt',
  'explain',
  'symbols',
  'repl',
  'lsp',
  'version',
]

const EDITORS = ['Neovim', 'Helix', 'Emacs 29+', 'Zed', 'VS Code (server only)']

export function Editors() {
  return (
    <section className="editors" aria-labelledby="editors-h">
      <div className="container">
        <div className="editors__top">
          <div>
            <h2 id="editors-h">The toolchain is one binary.</h2>
            <p>
              No build system to configure, no formatter to choose, no test
              runner to add, no language server to install separately. Eleven
              subcommands, one download, and the same compiler behind all of
              them.
            </p>
          </div>
          <ul className="editors__cmds">
            {COMMANDS.map((c) => (
              <li key={c}>
                <span>axiom</span> {c}
              </li>
            ))}
          </ul>
        </div>

        <dl className="editors__facts">
          <div>
            <dt>
              <code>axiom explain</code>
            </dt>
            <dd>
              Every one of the {stat('codes')} diagnostic codes has a full written
              explanation behind it — and where a fix is machine-applicable, it
              travels with the error as a span and a replacement.
            </dd>
          </div>
          <div>
            <dt>
              <code>axiom lsp</code>
            </dt>
            <dd>
              Written in Axiom like the rest of the compiler, and answers
              twenty-four requests — including a distinction most languages do
              not have: a function is written twice, so{' '}
              <em>declaration</em> lands on the signature and{' '}
              <em>definition</em> on the body.
            </dd>
          </div>
          <div>
            <dt>
              <code>tree-sitter-axiom</code>
            </dt>
            <dd>
              All of the highlighting, plus rainbow-bracket queries. One query
              file serves Neovim, Helix and the <code>tree-sitter</code> CLI —
              and it is parsed against all {stat('axfiles')}{' '}
              <code>.ax</code> files in the repository on every change.
            </dd>
          </div>
        </dl>

        <div className="editors__foot">
          <ul className="editors__list">
            {EDITORS.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
          <p className="micro">
            <a href={`${DOCS}/lsp.md`} target="_blank" rel="noreferrer noopener">
              docs/lsp.md
            </a>{' '}
            has a configuration per editor. The server and the grammar are
            independent: the server colours nothing, so a buffer with it
            attached and no grammar installed is plain text.
          </p>
        </div>
      </div>
    </section>
  )
}
