import { COMMANDS, DOCS, stat } from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * The toolchain in one section. The subcommand list is `COMMANDS`,
 * which `check-claims.mjs` holds to `axiom --help` word for word. The
 * editor facts are docs/lsp.md's "Editor setup" table, careful about a
 * distinction repeated here: the server answers requests and colours
 * nothing; the tree-sitter grammar does all of the highlighting. VS
 * Code gets the server but not the colours, because it has no
 * tree-sitter and this repository ships no TextMate grammar.
 */
const EDITORS = [
  { name: 'Neovim', both: true },
  { name: 'Helix', both: true },
  { name: 'Emacs 29+', both: true },
  { name: 'Zed', both: true },
  { name: 'VS Code', both: false },
]

export function Toolchain() {
  return (
    <section className="section" id="tooling" aria-labelledby="tooling-h">
      <div className="container">
        <SectionHead id="tooling-h" eyebrow="Tooling" title="One binary. Everything you need.">
          <p>
            No build system to configure, no formatter to choose, no test runner to add, and no
            language server to install separately: {stat('commands')} subcommands, one download,
            and the same compiler behind all of them.
          </p>
        </SectionHead>

        <ul className="cmds">
          {COMMANDS.map((c) => (
            <li key={c.name}>
              <code className="cmds__name">
                <span>axiom</span> {c.name}
              </code>
              <span className="cmds__desc">{inline(c.desc)}</span>
            </li>
          ))}
        </ul>

        <div className="tools">
          <div className="tool">
            <h3>
              <code>axiom explain</code>
            </h3>
            <p>
              Every one of the {stat('codes')} diagnostic codes has a full written explanation behind
              it. Codes are stable across wording changes, so you can grep for them in CI or match
              on them in editor tooling.
            </p>
          </div>
          <div className="tool">
            <h3>
              <code>axiom lsp</code>
            </h3>
            <p>
              Written in Axiom like the rest of the compiler, and answers {stat('lspRequests')}{' '}
              requests, including one most languages lack: a function is written twice, so{' '}
              <em>declaration</em> lands on the signature and <em>definition</em> on the body.
            </p>
          </div>
          <div className="tool">
            <h3>
              <code>tree-sitter-axiom</code>
            </h3>
            <p>
              All of the highlighting, plus rainbow brackets. One query file serves Neovim, Helix
              and the <code>tree-sitter</code> CLI, and it is parsed against all {stat('axfiles')}{' '}
              <code>.ax</code> files in the repository on every change.
            </p>
          </div>
        </div>

        <div className="editors">
          <ul aria-label="Editors">
            {EDITORS.map((e) => (
              <li key={e.name} data-both={e.both}>
                {e.name}
                {!e.both && <span> · server only</span>}
              </li>
            ))}
          </ul>
          <p>
            <a href={`${DOCS}/lsp.md`} target="_blank" rel="noreferrer noopener">
              docs/lsp.md
              <ArrowUpRight size={12} />
            </a>{' '}
            has a configuration for each. The server and the grammar are independent: the server
            colours nothing, so a buffer with it attached and no grammar installed is plain text.
          </p>
        </div>
      </div>
    </section>
  )
}
