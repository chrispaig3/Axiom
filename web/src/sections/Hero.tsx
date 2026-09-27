import { useId, useState } from 'react'
import { HERO, HERO_NOTES as NOTES, HERO_SESSIONS, type Session } from '../data/samples.ts'
import { BENCH } from '../data/bench.ts'
import { BLOB, INSTALL_CMD, RELEASES, VERSION, stat } from '../data/site.ts'
import { CodeWindow, RunOutput } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowRight, Play } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * The terminal docked under the hero program: five commands a reader
 * can click through, each printing what the compiler really printed.
 * The first renders server-side, so a crawler reads real output.
 */
function HeroTerminal({ sessions }: { sessions: Session[] }) {
  const [active, setActive] = useState(0)
  const uid = useId()
  const s = sessions[active] ?? sessions[0]
  if (!s) return null

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    e.preventDefault()
    const next = (active + (e.key === 'ArrowRight' ? 1 : -1) + sessions.length) % sessions.length
    setActive(next)
    document.getElementById(`${uid}-${next}`)?.focus()
  }

  return (
    <div className="hterm">
      <div className="hterm__bar">
        <span className="hterm__label">Terminal</span>
        <div className="tabs" role="tablist" aria-label="Commands to try" onKeyDown={onKeyDown}>
          {sessions.map((x, i) => (
            <button
              key={x.id}
              id={`${uid}-${i}`}
              type="button"
              role="tab"
              className="tab"
              aria-selected={i === active}
              aria-controls={`${uid}-panel`}
              tabIndex={i === active ? 0 : -1}
              onClick={() => setActive(i)}
            >
              axiom {x.tab}
            </button>
          ))}
        </div>
      </div>
      <div id={`${uid}-panel`} role="tabpanel" aria-labelledby={`${uid}-${active}`}>
        <RunOutput command={s.command} output={s.output} replay={s.id} />
        <p className="hterm__note">{s.note}</p>
      </div>
    </div>
  )
}

/** The run-time row, reduced to the one sentence the proof strip needs. */
function speedClaim() {
  const run = BENCH.find((r) => r.metric === 'Run time')
  if (!run) return { big: '—', small: '' }
  const s = (v: string) => Number.parseFloat(v)
  const ms = Math.round(Math.abs(s(run.axiom) - s(run.c)) * 1000)
  return { big: `${ms} ms`, small: `between Axiom and C on the same loop (${run.axiom} against ${run.c}).` }
}

export function Hero() {
  const [focus, setFocus] = useState<number | null>(null)
  const speed = speedClaim()
  const marked = focus === null ? undefined : [focus]

  return (
    <section className="hero" id="top" aria-labelledby="hero-h">
      <div className="hero__bg" aria-hidden />
      <div className="container">
        <div className="hero__lead">
          <a className="pill" href={`${RELEASES}/tag/v${VERSION}`} target="_blank" rel="noreferrer noopener">
            <span className="pill__tag">v{VERSION}</span>
            <span>Released under MIT. Read the notes</span>
            <ArrowRight size={13} />
          </a>

          <h1 id="hero-h">
            Functional programming that ships <span className="grad">a binary, not a runtime.</span>
          </h1>

          <p className="hero__lede">
            Algebraic data types, exhaustive matching and effects the compiler <em>checks</em>,
            compiled through LLVM to a native executable. No VM, no garbage collector, and no C
            library call inside it.
          </p>

          <div className="hero__actions">
            <a className="btn btn--primary btn--lg" href="#start">
              Get started
              <ArrowRight />
            </a>
            <a className="btn btn--ghost btn--lg" href="#break">
              <Play />
              Try to break it
            </a>
          </div>

          <div className="hero__install">
            <Command command={INSTALL_CMD} />
            <p className="hero__note">
              Prebuilt for macOS and Linux on arm64. Everywhere else,{' '}
              <a href="#start">build from source</a> with <code>llc</code> and a C compiler.
            </p>
          </div>
        </div>

        <div className="hero__stage">
          <CodeWindow
            name={HERO.file}
            code={HERO.code}
            marked={marked}
            badge="a whole program"
            className="win--hero"
          >
            <HeroTerminal sessions={HERO_SESSIONS} />
          </CodeWindow>

          <ol className="notes" aria-label="What to notice in this program">
            {NOTES.map((n) => (
              <li
                key={n.line}
                tabIndex={0}
                data-active={focus === n.line}
                onMouseEnter={() => setFocus(n.line)}
                onMouseLeave={() => setFocus(null)}
                onFocus={() => setFocus(n.line)}
                onBlur={() => setFocus(null)}
              >
                <span className="notes__line">L{n.line}</span>
                <span className="notes__text">
                  <b>{n.title}</b>
                  <span>{inline(n.body)}</span>
                </span>
              </li>
            ))}
          </ol>
        </div>

        <ul className="proof" aria-label="Measured, not asserted">
          <li>
            <b>0</b>
            <span>
              C library calls: printing and allocation are raw syscalls.{' '}
              <a href={`${BLOB}/scripts/check-freestanding.sh`} target="_blank" rel="noreferrer noopener">
                Gated
              </a>
              .
            </span>
          </li>
          <li>
            <b>{speed.big}</b>
            <span>
              {speed.small} <a href="#speed">Measured</a>.
            </span>
          </li>
          <li>
            <b>{stat('lines')}</b>
            <span>lines of Axiom that compile Axiom, rebuilt byte for byte.</span>
          </li>
          <li>
            <b>{stat('codes')}</b>
            <span>
              diagnostic codes, every one of them explained by <code>axiom explain</code>.
            </span>
          </li>
        </ul>
      </div>
    </section>
  )
}
