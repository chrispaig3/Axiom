import { useId, useState } from 'react'
import { BREAKS, BREAK_FILE } from '../data/samples.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { CodeWindow } from '../components/Code.tsx'
import { RenderTabs } from '../components/Terminal.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * Five one-line edits to the hero program, and the compiler's answer to
 * each. Every report is the compiler's real stderr for that exact file,
 * re-checked by `scripts/check-samples.mjs`, in both the human and the
 * `ai` renderings - which is the argument of the whole section: two
 * audiences, one set of facts.
 */
export function BreakIt() {
  const [active, setActive] = useState(0)
  const [format, setFormat] = useState(0)
  const uid = useId()
  const b = BREAKS[active] ?? BREAKS[0]
  if (!b) return null

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    const keys: Record<string, number> = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }
    const d = keys[e.key]
    if (d === undefined) return
    e.preventDefault()
    const next = (active + d + BREAKS.length) % BREAKS.length
    setActive(next)
    document.getElementById(`${uid}-b-${next}`)?.focus()
  }

  return (
    <section className="section section--stage ink" id="break" aria-labelledby="break-h">
      <div className="container">
        <SectionHead id="break-h" eyebrow="Try to break it" title="A compiler that argues back, precisely.">
          <p>
            Five small edits to the program above. Each is refused before anything runs, and the
            report says what went wrong, exactly where, and very often how to fix it, in a form a
            person can read and a tool can apply.
          </p>
        </SectionHead>

        <div className="breaker">
          <div
            className="breaker__list"
            role="tablist"
            aria-label="Ways to break the program"
            aria-orientation="vertical"
            onKeyDown={onKeyDown}
          >
            {BREAKS.map((x, i) => (
              <button
                key={x.id}
                id={`${uid}-b-${i}`}
                type="button"
                role="tab"
                className="breaker__item"
                aria-selected={i === active}
                aria-controls={`${uid}-panel`}
                tabIndex={i === active ? 0 : -1}
                onClick={() => setActive(i)}
              >
                <span className="breaker__n">{String(i + 1).padStart(2, '0')}</span>
                <span className="breaker__label">{x.label}</span>
                <span className="breaker__code">{codeOf(x.ai)}</span>
              </button>
            ))}
          </div>

          <div
            className="breaker__stage"
            id={`${uid}-panel`}
            role="tabpanel"
            aria-labelledby={`${uid}-b-${active}`}
          >
            <div className="breaker__head">
              <h3>{b.title}</h3>
              <p>{inline(b.note)}</p>
            </div>
            <CodeWindow
              name={BREAK_FILE}
              code={b.code}
              marked={b.changed}
              badge={<span className="badge badge--err">refused</span>}
            />
            <RenderTabs
              label="Two renderings of the same diagnostics"
              name={`$ axiom check ${BREAK_FILE}`}
              active={format}
              onChange={setFormat}
              items={[
                { id: 'human', tab: 'human', kind: 'human', text: b.human },
                { id: 'ai', tab: '--diagnostic-format=ai', kind: 'axdl', text: b.ai },
              ]}
            />
          </div>
        </div>
      </div>
    </section>
  )
}

/** The diagnostic codes an AXDL stream carries, in order, deduplicated. */
function codeOf(axdl: string): string {
  const codes = [...axdl.matchAll(/^[EW] (AX\d{4})/gm)].map((m) => m[1])
  return [...new Set(codes)].join(' + ')
}
