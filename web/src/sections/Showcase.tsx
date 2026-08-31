import { Fragment } from 'react'
import { SAMPLES } from '../data/samples.ts'
import { TabbedCode, type TabbedItem } from '../components/Code.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'
import { Reveal } from '../components/Reveal.tsx'

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
        <Reveal className="lede-block">
          <span className="index">02</span>
          <h2 id="code-h">Five ways in.</h2>
          <p>
            Three complete programs, run to produce the output shown under them,
            and two excerpts of code that does a real job in the repository — one
            from the prelude, one from the compiler's own lexer.
          </p>
        </Reveal>

        <Reveal>
          <TabbedCode items={items} label="Axiom programs" />
        </Reveal>
      </div>
    </section>
  )
}
