import { Fragment } from 'react'
import { SAMPLES } from '../data/samples.ts'
import { TabbedCode, type TabbedItem } from '../components/Code.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'

/** Render the backtick spans in a note without pulling in a markdown parser. */
function note(text: string) {
  return text
    .split(/`([^`]+)`/g)
    .map((part, i) =>
      i % 2 === 1 ? (
        <code key={i}>{part}</code>
      ) : (
        <Fragment key={i}>{part}</Fragment>
      ),
    )
}

const items: TabbedItem[] = SAMPLES.map((s) => {
  const link =
    s.docs ?? (s.source && s.href ? { label: s.source, href: s.href } : null)
  return {
    id: s.id,
    tab: s.tab,
    code: s.code,
    ...(s.result ? { output: s.result } : {}),
    caption: (
      <>
        <strong>{s.title}.</strong> {note(s.note)}
        {link && (
          <>
            {' '}
            <a href={link.href} target="_blank" rel="noreferrer noopener">
              {link.label}
              <ArrowUpRight size={11} />
            </a>
          </>
        )}
      </>
    ),
  }
})

export function Showcase() {
  return (
    <section className="section section--alt" id="code" aria-labelledby="code-h">
      <div className="container">
        <div className="lede-block">
          <span className="index">02</span>
          <h2 id="code-h">What it actually looks like.</h2>
          <p>
            Six complete programs, each one compiled and run to produce the
            output shown under it. They walk from the thing every language has
            — types and matching — to the things only this one does: checked
            effects, a region per row, and a join across processes.
          </p>
        </div>

        <div>
          <TabbedCode items={items} label="Axiom programs" />
        </div>
      </div>
    </section>
  )
}
