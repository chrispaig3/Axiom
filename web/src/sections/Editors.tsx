import { DOCS } from '../data/site.ts'

/**
 * Everything here is from docs/lsp.md's "Editor setup" table and the
 * README's "Editor support" row. Two things are separate and the doc is
 * careful about it: the server answers requests and colours nothing; the
 * tree-sitter grammar does all of the highlighting.
 */
const EDITORS = [
  'Neovim',
  'Helix',
  'Emacs 29+',
  'Zed',
  // The server works here like anywhere else; the highlighting does not,
  // because VS Code has no tree-sitter and this repository ships no
  // TextMate grammar. docs/lsp.md says so, and so does this label.
  'VS Code (server only)',
]

export function Editors() {
  return (
    <section className="editors" aria-labelledby="editors-h">
      <div className="container editors__inner">
        <div className="editors__lead">
          <h2 id="editors-h">Editor support</h2>
          <ul className="editors__list">
            {EDITORS.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        </div>

        <dl className="editors__facts">
          <div>
            <dt>
              <code>axiom lsp</code> — the language server
            </dt>
            <dd>
              Written in Axiom, like the rest of the compiler, and answers
              twenty-four requests. Among them a distinction most languages do
              not have: a function is written twice, as{' '}
              <code>(:: f T)</code> and <code>(fn (f x) …)</code>, so{' '}
              <em>declaration</em> lands on the signature and{' '}
              <em>definition</em> on the body.
            </dd>
          </div>
          <div>
            <dt>
              <code>tree-sitter-axiom</code> — the grammar
            </dt>
            <dd>
              All of the highlighting: colour by syntactic role, plus
              rainbow-bracket queries. The capture names follow the convention
              Neovim, Helix and the <code>tree-sitter</code> CLI share, so one
              query file works in all three — and it is parsed against all 581{' '}
              <code>.ax</code> files in the repository on every change.
            </dd>
          </div>
        </dl>

        <p className="micro editors__note">
          The two are independent: the server colours nothing, so a buffer with
          it attached and no grammar installed is plain text.{' '}
          <a href={`${DOCS}/lsp.md`} target="_blank" rel="noreferrer noopener">
            docs/lsp.md
          </a>{' '}
          has a configuration per editor;{' '}
          <a
            href="https://github.com/chrispaig3/Axiom/tree/trunk/tree-sitter-axiom"
            target="_blank"
            rel="noreferrer noopener"
          >
            tree-sitter-axiom/
          </a>{' '}
          is the grammar this page's own highlighting was written from.
        </p>
      </div>
    </section>
  )
}
