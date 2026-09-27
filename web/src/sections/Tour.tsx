import { useId, useMemo, useRef, useState } from 'react'
import { TOUR, commandFor } from '../data/samples.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { CodeWindow, RunOutput, type LineMark } from '../components/Code.tsx'
import { Report } from '../components/Terminal.tsx'
import { ArrowRight, ArrowUpRight, Bolt, Undo } from '../components/Icons.tsx'
import { changedLines, lineOf, reportedLines } from '../lib/diff.ts'
import { inline } from '../lib/inline.tsx'

/** Programs longer than this open folded; one control opens them. */
const FOLD_AT = 36

/**
 * Ten small real programs, one idea each, as a tabbed chapter list.
 *
 * Each point beside a program names the line it is about, and hovering
 * or focusing it lights that line. A chapter with a refusal can be
 * broken in place: the changed program comes in with the lines the edit
 * touched in amber and the line the compiler points at in red, which is
 * what the note under the button describes. All of it is checked by
 * `scripts/check-samples.mjs`.
 */
export function Tour() {
  const [active, setActive] = useState(0)
  const [broken, setBroken] = useState(false)
  const [focus, setFocus] = useState<number | null>(null)
  const uid = useId()
  const panel = useRef<HTMLDivElement>(null)
  const p = TOUR[active] ?? TOUR[0]

  const pointLines = useMemo(() => (p ? p.points.map((pt) => lineOf(p.code, pt.at)) : []), [p])

  const breakMarks = useMemo(() => {
    const m = new Map<number, LineMark>()
    if (!p?.refusal) return m
    for (const l of changedLines(p.code, p.refusal.code)) m.set(l, 'edit')
    for (const l of reportedLines(p.refusal.human)) m.set(l, 'error')
    return m
  }, [p])

  if (!p) return null

  const go = (i: number, focusTab = false) => {
    setActive(i)
    setBroken(false)
    setFocus(null)
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
  const focusLine = focus === null ? 0 : (pointLines[focus] ?? 0)
  const marks = showBroken
    ? breakMarks
    : focusLine
      ? new Map<number, LineMark>([[focusLine, 'focus']])
      : undefined

  return (
    <section className="section" id="tour" aria-labelledby="tour-h">
      <div className="container">
        <SectionHead id="tour-h" eyebrow="The tour" title="Learn Axiom in ten programs.">
          <p>
            Each one is a small task, compiled and run; the output under it is what it printed.
            Point at a note to light the line it describes.
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
                {String(active + 1).padStart(2, '0')}/{TOUR.length} · <code>{p.file}</code>
              </p>
              <h3>{p.title}</h3>
              <p className="tour__lede">{inline(p.lede)}</p>
              <ul className="tour__points" aria-label="What to notice">
                {p.points.map((pt, i) => (
                  <li
                    key={pt.at}
                    tabIndex={0}
                    data-active={focus === i && !showBroken}
                    onMouseEnter={() => setFocus(i)}
                    onMouseLeave={() => setFocus(null)}
                    onFocus={() => setFocus(i)}
                    onBlur={() => setFocus(null)}
                  >
                    <span className="tour__ln">L{pointLines[i]}</span>
                    <span>{inline(pt.text)}</span>
                  </li>
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
              marks={marks}
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
                  {broken ? 'Restore the program' : `Break it: ${p.refusal.label.toLowerCase()}`}
                </button>
                <div>
                  <p>{inline(p.refusal.note)}</p>
                  {broken && (
                    <p className="legend">
                      <span data-k="edit">your edit</span>
                      <span data-k="error">where the compiler points</span>
                    </p>
                  )}
                </div>
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
