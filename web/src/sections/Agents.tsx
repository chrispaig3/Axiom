import { AXSYM_AI, AXSYM_SOURCE, AXSYM_TABLE, FIX_AXDL, FIX_JSON, FIX_SOURCE } from '../data/samples.ts'
import { BLOB, DOCS, stat } from '../data/site.ts'
import { CodeWindow } from '../components/Code.tsx'
import { RenderTabs } from '../components/Terminal.tsx'
import { SectionHead } from '../components/SectionHead.tsx'
import { inline } from '../lib/inline.tsx'

/** docs/agent-harness.md §1: the four notations that ship and are gated. */
const NOTATIONS = [
  { k: 'AXDL', v: 'One line per diagnostic, with machine-applicable fixes as byte-range substitutions.' },
  { k: 'AXSYM', v: 'One line per symbol: kind, name, span, exact type, id, and every accepted tag.' },
  { k: 'NID', v: 'A content-derived id per declaration, stable across reordering and reformatting.' },
  { k: 'AXTAG', v: '`;@axiom:` claims above a declaration, validated wherever the compiler knows the key.' },
]

export function Agents() {
  const bytes = new TextEncoder().encode(FIX_AXDL).length
  return (
    <section className="section section--alt" id="agents" aria-labelledby="agents-h">
      <div className="container">
        <SectionHead id="agents-h" eyebrow="Built for agents, too" title="Answer the machine in its own format.">
          <p>
            Most toolchains publish their failures as prose and keep their successes to themselves.
            Axiom publishes both as data: one line per diagnostic <em>and</em> one line per symbol,
            built from the same structured facts the human report is built from, so the two can
            never disagree.
          </p>
        </SectionHead>

        <ul className="notations">
          {NOTATIONS.map((n) => (
            <li key={n.k}>
              <b>{n.k}</b>
              <span>{inline(n.v)}</span>
            </li>
          ))}
        </ul>

        <div className="duo">
          <div className="duo__panel">
            <h3>Every fact in {bytes} bytes, and the fix with it</h3>
            <p>
              The exact span, the kind of error, the label, the message, and a replacement a tool
              applies as a substitution instead of parsing English. Both renderings are real output,
              re-checked against the compiler.
            </p>
            <CodeWindow name="main.ax" code={FIX_SOURCE} badge="a typo on line 6" marked={[6]} copyText={null} />
            <RenderTabs
              label="One diagnostic, two machine formats"
              name="$ axiom check main.ax"
              items={[
                { id: 'axdl', tab: '--diagnostic-format=ai', kind: 'axdl', text: FIX_AXDL },
                { id: 'json', tab: '--diagnostic-format=json', kind: 'json', text: FIX_JSON },
              ]}
            />
          </div>

          <div className="duo__panel">
            <h3>What does this file already provide?</h3>
            <p>
              <code>axiom symbols</code> runs the same pipeline as <code>check</code> and prints one
              line per declaration. An agent greps <code>^D Maybe</code> for the constructor set
              instead of re-reading the file, and the <code>@27bcb2…</code> id still names the same
              function after the file is reordered or reformatted.
            </p>
            <CodeWindow name="main.ax" code={AXSYM_SOURCE} copyText={null} />
            <RenderTabs
              label="Symbol renderings"
              name="$ axiom symbols main.ax"
              wrap={false}
              items={[
                { id: 'axsym', tab: '--diagnostic-format=ai', kind: 'axsym', text: AXSYM_AI },
                { id: 'table', tab: 'human', kind: 'plain', text: AXSYM_TABLE },
              ]}
            />
          </div>
        </div>

        <p className="aside">
          The AXDL line above is the golden of{' '}
          <a href={`${BLOB}/tests/diagnostics/150-undefined-suggestion.axdl`} target="_blank" rel="noreferrer noopener">
            one diagnostics fixture
          </a>
          , re-rendered against the live compiler on every run.{' '}
          <a href={`${DOCS}/diagnostics.md`} target="_blank" rel="noreferrer noopener">
            diagnostics.md
          </a>{' '}
          has the grammar, and <code>axiom explain --list</code> names all {stat('codes')} codes.
        </p>
      </div>
    </section>
  )
}
