import { useId, useMemo, useRef, useState } from 'react'
import { TOUR, commandFor } from '../data/samples.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { CodeWindow, RunOutput } from '../components/Code.tsx'
import { Report } from '../components/Terminal.tsx'
import { ArrowRight, ArrowUpRight, Bolt, Undo } from '../components/Icons.tsx'
import { changedLines } from '../lib/diff.ts'
import { inline } from '../lib/inline.tsx'

/** Programs longer than this open folded; one control opens them. */
const FOLD_AT = 36

/**
 * Ten small real programs, one idea each, as a tabbed chapter list.
 *
 * Every chapter's output is the program's real stdout, and a chapter
 * with a refusal can be broken in place: the button swaps in the
 * changed program, marks the changed lines, and shows the compiler's
 * real report. All of it is checked by `scripts/check-samples.mjs`.
 */
export function Tour() {
  const [active, setActive] = useState(0)
  const [broken, setBroken] = useState(false)
  const uid = useId()
  const panel = useRef<HTMLDivElement>(null)
  const p = TOUR[active] ?? TOUR[0]

  const diff = useMemo(
    () => (p?.refusal ? changedLines(p.code, p.refusal.code) : []),
    [p],
  )
  if (!p) return null

  const go = (i: number, focusTab = false) => {
    setActive(i)
    setBroken(false)
    if (focusTab) document.getElementById(`${uid}-t-${i}`)?.focus()
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    const keys: Record<string, number> = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }
    const d = keys[e.key]
    if (d === undefined) return
    e.preventDefault()
    go((active + d + TOUR.length) % TOUR.length, true)
  }

  const next = TOUR[active + 1]
  const showBroken = broken && p.refusal

  return (
    <section className="section" id="tour" aria-labelledby="tour-h">
      <div className="container">
        <SectionHead id="tour-h" eyebrow="The tour" title="Learn Axiom in ten programs.">
          <p>
            Each is a small real task, not a feature demo, and each was compiled and run: the
            output under it is what it printed. Where the compiler refuses something interesting,
            there is a button to try it.
          </p>
        </SectionHead>

        <div className="tour">
          <div
            className="tour__nav"
            role="tablist"
            aria-label="Tour chapters"
            aria-orientation="vertical"
            onKeyDown={onKeyDown}
          >
            {TOUR.map((t, i) => (
              <button
                key={t.id}
                id={`${uid}-t-${i}`}
                type="button"
                role="tab"
                className="tour__tab"
                aria-selected={i === active}
                aria-controls={`${uid}-panel`}
                tabIndex={i === active ? 0 : -1}
                onClick={() => go(i)}
              >
                <span className="tour__num">{String(i + 1).padStart(2, '0')}</span>
                <span>{t.tab}</span>
              </button>
            ))}
          </div>

          <div
            className="tour__panel"
            id={`${uid}-panel`}
            role="tabpanel"
            aria-labelledby={`${uid}-t-${active}`}
            ref={panel}
          >
            <header className="tour__head">
              <p className="tour__count">
                Chapter {active + 1} of {TOUR.length} · <code>{p.file}</code>
              </p>
              <h3>{p.title}</h3>
              <p className="tour__lede">{inline(p.lede)}</p>
              <ul className="tour__points">
                {p.points.map((pt) => (
                  <li key={pt}>{inline(pt)}</li>
                ))}
              </ul>
            </header>

            {p.rust && (
              <CodeWindow
                name={p.rust.path.split('/').pop() ?? 'lib.rs'}
                code={p.rust.code}
                lang="rust"
                badge={<span className="badge">the crate, Rust</span>}
                foldAt={18}
                className="win--rust"
              />
            )}

            <CodeWindow
              name={p.file}
              code={showBroken ? p.refusal!.code : p.code}
              marked={showBroken ? diff : undefined}
              foldAt={FOLD_AT}
              badge={
                showBroken ? (
                  <span className="badge badge--err">refused</span>
                ) : p.rust ? (
                  <span className="badge">the program, Axiom</span>
                ) : undefined
              }
            >
              {showBroken ? (
                <Report text={p.refusal!.human} command={`axiom check ${p.file}`} />
              ) : (
                <RunOutput command={commandFor(p)} output={p.output} replay={p.id} />
              )}
            </CodeWindow>

            {p.refusal && (
              <div className="tour__try" data-broken={broken}>
                <button
                  type="button"
                  className="btn btn--sm btn--try"
                  onClick={() => setBroken((b) => !b)}
                  aria-pressed={broken}
                >
                  {broken ? <Undo /> : <Bolt />}
                  {broken ? 'Restore the program' : `Now break it: ${p.refusal.label.toLowerCase()}`}
                </button>
                <p>{inline(p.refusal.note)}</p>
              </div>
            )}

            <footer className="tour__foot">
              {p.docs && (
                <a href={p.docs.href} target="_blank" rel="noreferrer noopener">
                  Read more: {p.docs.label}
                  <ArrowUpRight size={12} />
                </a>
              )}
              {next ? (
                <button
                  type="button"
                  className="tour__next"
                  onClick={() => {
                    go(active + 1)
                    panel.current?.closest('section')?.scrollIntoView({ block: 'start' })
                  }}
                >
                  Next: {next.tab}
                  <ArrowRight size={14} />
                </button>
              ) : (
                <a className="tour__next" href="#start">
                  Install it and try your own
                  <ArrowRight size={14} />
                </a>
              )}
            </footer>
          </div>
        </div>
      </div>
    </section>
  )
}
