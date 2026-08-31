import {
  AXSYM_AI,
  AXSYM_TABLE,
  FIX_AXDL,
  FIX_JSON,
  FIX_SOURCE,
  SET_AXDL,
  SET_HUMAN,
  SET_SOURCE,
} from '../data/samples.ts'
import { BLOB, DOCS } from '../data/site.ts'
import { Code } from '../components/Code.tsx'
import { RenderTabs } from '../components/Terminal.tsx'
import { Reveal } from '../components/Reveal.tsx'

export function Agents() {
  return (
    <section className="section" id="agents" aria-labelledby="agents-h">
      <div className="container">
        <Reveal className="lede-block">
          <span className="index index--violet">06</span>
          <h2 id="agents-h">
            The compiler answers twice — once for you, once for your tools.
          </h2>
          <p>
            One structured diagnostic is built at every stage that can refuse,
            and the renderers never see anything the compiler did not already
            know. So the report you read and the line your tooling parses can
            never disagree about what went wrong.
          </p>
        </Reveal>

        <div className="duo">
          <Reveal className="duo__panel">
            <h3>Why did this fail?</h3>
            <Code code={SET_SOURCE} name="count.ax" badge="refused" />
            <RenderTabs
              label="Diagnostic renderings"
              items={[
                { id: 'human', tab: 'human', kind: 'human', text: SET_HUMAN },
                { id: 'ai', tab: 'ai', kind: 'axdl', text: SET_AXDL },
              ]}
              caption={
                <>
                  The human report quotes <em>both</em> spans and elides the
                  lines between them, labels the binding site as well as the
                  offence, and ends with a fix rather than a restatement.
                  Columns count characters, not bytes, so a caret under a line
                  containing an em dash lands where the eye expects.
                </>
              }
            />
          </Reveal>

          <Reveal className="duo__panel" delay={60}>
            <h3>What does this file already provide?</h3>
            <p className="duo__lede">
              The other question a tool asks is not about failure at all.{' '}
              <code>axiom symbols</code> runs the same pipeline as{' '}
              <code>check</code> and prints one line per symbol — kind, name,
              location, exact type. An agent greps <code>^D Maybe</code> for the
              constructor set instead of re-parsing the file.
            </p>
            <RenderTabs
              label="Symbol renderings"
              items={[
                { id: 'table', tab: 'table', kind: 'plain', text: AXSYM_TABLE },
                { id: 'axsym', tab: 'AXSYM', kind: 'axsym', text: AXSYM_AI },
              ]}
              caption={
                <>
                  The <code>@27bcb2…</code> is a content-derived id that does not
                  move when the declaration is reordered, reformatted, or read
                  from another path — identity is the id, and the rest of the row
                  is the contract.
                </>
              }
            />
          </Reveal>
        </div>

        <Reveal className="fixline" delay={40}>
          <div className="fixline__text">
            <h3>Every fact, in 193 bytes — and the fix comes with it</h3>
            <p>
              The exact span, the kind of error, the primary label, the message,
              and a replacement a tool applies as a byte-range substitution
              instead of parsing English.
            </p>
            <p className="micro">
              Both blocks are real compiler output, re-rendered and diffed
              against the live compiler by{' '}
              <a
                href={`${BLOB}/scripts/check-doc-drift.sh`}
                target="_blank"
                rel="noreferrer noopener"
              >
                check-doc-drift.sh
              </a>{' '}
              on every run — documentation showing output nobody could reproduce
              would fail the build.{' '}
              <a
                href={`${DOCS}/diagnostics.md`}
                target="_blank"
                rel="noreferrer noopener"
              >
                diagnostics.md
              </a>{' '}
              has the grammar and all 68 codes.
            </p>
          </div>
          <div className="stack">
            <Code code={FIX_SOURCE} name="main.ax" badge="a typo on line 6" />
            <RenderTabs
              label="One diagnostic, two machine formats"
              items={[
                { id: 'axdl', tab: 'ai', kind: 'axdl', text: FIX_AXDL },
                { id: 'json', tab: 'json', kind: 'json', text: FIX_JSON },
              ]}
            />
          </div>
        </Reveal>
      </div>
    </section>
  )
}
