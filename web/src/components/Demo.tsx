import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { DEMO, DEMO_FILE } from '../data/samples.ts'
import { cloneFrame, compile, emptyFrame, frameAt, type Frame } from '../lib/demo.ts'
import { highlight } from '../lib/highlight.ts'
import { inline } from '../lib/inline.tsx'
import { paint, toLines } from './Code.tsx'
import { paintReport } from './Terminal.tsx'

/**
 * The landing demo: a terminal session that plays like a video.
 *
 * `shapes.ax` is typed into an editor pane, run, broken, refused, fixed
 * and built in a shell pane beside it. Every keystroke, command and line
 * of output comes from the script in `samples.ts`, which
 * `check-samples.mjs` replays against the compiler.
 *
 * It plays on arrival and loops. It pauses itself while scrolled out of
 * view, and under `prefers-reduced-motion` it does not start at all: it
 * shows the finished session, with a button to play it.
 *
 * THE SERVER RENDERS THE LAST FRAME. The prerendered page, and a reader
 * with no JavaScript, get the finished program and every command's
 * output; the animation begins from an empty editor once the page is
 * live. Both renders start from the same frame, so hydration matches.
 */

const TL = compile(DEMO)
const LAST = frameAt(TL, TL.end)
/** How long the finished session stays up before it plays again. */
const HOLD = 6000
const LOOP = TL.end + HOLD

const reducedMotion = () =>
  typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches

/** The script, told in words, for a reader who cannot watch it. */
const TRANSCRIPT = (() => {
  const out: string[] = []
  for (const s of DEMO) {
    if (s.do === 'say') out.push(s.text.replace(/`/g, ''))
    if (s.do === 'run') out.push(`$ ${s.command}`)
  }
  return out
})()

export function Demo() {
  const [frame, setFrame] = useState<Frame>(LAST)
  const [playing, setPlaying] = useState(false)
  const clock = useRef({ t: TL.end, next: TL.events.length, f: cloneFrame(LAST) })
  const fills = useRef<(HTMLSpanElement | null)[]>([])
  const root = useRef<HTMLElement>(null)
  const inView = useRef(true)

  /** Paint each chapter's progress straight onto its bar: no re-render per frame. */
  const paintProgress = useCallback((t: number) => {
    TL.chapters.forEach((c, i) => {
      const el = fills.current[i]
      if (!el) return
      const end = TL.chapters[i + 1]?.start ?? TL.end
      const p = Math.max(0, Math.min(1, (t - c.start) / (end - c.start)))
      el.style.transform = `scaleX(${p})`
    })
  }, [])

  const seek = useCallback(
    (t: number) => {
      const c = clock.current
      let changed = false
      if (t < c.t) {
        c.f = emptyFrame()
        c.next = 0
        changed = true
      }
      while (c.next < TL.events.length && (TL.events[c.next]?.t ?? Infinity) <= t) {
        TL.events[c.next]?.apply(c.f)
        c.next++
        changed = true
      }
      c.t = t
      if (changed) setFrame(cloneFrame(c.f))
      paintProgress(t)
    },
    [paintProgress],
  )

  // Arrival: play from an empty editor, unless motion is unwelcome.
  // `?demo-at=MS` holds the frame at that moment instead, paused, for a
  // screenshot or a link to one step.
  useEffect(() => {
    paintProgress(TL.end)
    const at = Number(new URLSearchParams(location.search).get('demo-at'))
    if (at > 0) {
      seek(0)
      seek(at)
      return
    }
    if (reducedMotion()) return
    seek(0)
    setPlaying(true)
  }, [seek, paintProgress])

  // Out of view, the clock stops; back in view, it carries on.
  useEffect(() => {
    const el = root.current
    if (!el || typeof IntersectionObserver !== 'function') return
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) inView.current = e.isIntersecting
      },
      { threshold: 0.15 },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  useEffect(() => {
    if (!playing) return
    let raf = 0
    let last = performance.now()
    const tick = (now: number) => {
      // A long gap (a background tab) resumes where it was rather than
      // skipping ahead.
      const dt = Math.min(100, now - last)
      last = now
      if (inView.current && !document.hidden) {
        const t = clock.current.t + dt
        seek(t >= LOOP ? 0 : t)
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [playing, seek])

  const toggle = () => {
    if (!playing && clock.current.t >= TL.end) seek(0)
    setPlaying((p) => !p)
  }

  const jump = (i: number) => {
    const c = TL.chapters[i]
    if (!c) return
    seek(Math.max(0, c.start - 1))
    seek(c.start)
    setPlaying(true)
  }

  const lines = useMemo(() => toLines(highlight(frame.code)), [frame.code])
  const before = frame.code.slice(0, frame.cursor).split('\n')
  const caretLine = before.length
  const caretCol = (before[before.length - 1] ?? '').length
  const marks = new Map(frame.marks.map((m) => [m.line, m]))
  // An error outranks an edit on the same line.
  for (const m of frame.marks) if (m.kind === 'error') marks.set(m.line, m)

  return (
    <figure className="demo ink" ref={root} aria-labelledby="demo-title">
      <div className="demo__screen">
        <div className="demo__bar">
          <span className="demo__dots" aria-hidden>
            <i />
            <i />
            <i />
          </span>
          <span className="demo__title" id="demo-title">
            axiom — a terminal session, played back
          </span>
          <span className="demo__rec" data-on={playing} aria-hidden>
            {playing ? 'PLAY' : 'PAUSE'}
          </span>
        </div>

        <div className="demo__panes" aria-hidden>
          <div className="demo__pane demo__ed" data-focus={frame.focus === 'editor'}>
            <div className="demo__tab">
              <span>{DEMO_FILE}</span>
              <span className="demo__pos">
                {caretLine}:{caretCol + 1}
              </span>
            </div>
            <div className="demo__view">
              <div className="demo__lines" style={{ ['--top' as string]: frame.top }}>
                {lines.map((ln, i) => {
                  const n = i + 1
                  const m = marks.get(n)
                  return (
                    <div className="dl" key={i} data-mark={m?.kind}>
                      <span className="dl__n">{n}</span>
                      <span className="dl__c">
                        {paint(ln)}
                        {m?.kind === 'error' && m.col !== undefined && (
                          <span
                            className="dl__squiggle"
                            style={{ left: `${m.col}ch`, width: `${m.len ?? 1}ch` }}
                          />
                        )}
                        {n === caretLine && (
                          <span
                            key={frame.cursor}
                            className="caret"
                            data-idle={frame.focus !== 'editor'}
                            style={{ left: `${caretCol}ch` }}
                          />
                        )}
                      </span>
                    </div>
                  )
                })}
              </div>
            </div>
          </div>

          <div className="demo__pane demo__sh" data-focus={frame.focus === 'shell'}>
            <div className="demo__tab">
              <span>sh</span>
              <span className="demo__pos">~/demo</span>
            </div>
            <div className="demo__term">
              <div className="demo__scroll">
                {frame.shell.map((b, i) =>
                  b.kind === 'cmd' ? (
                    <div className="sh__line" key={i}>
                      <span className="sh__ps">~/demo $</span> {b.text}
                    </div>
                  ) : (
                    <pre className={`sh__${b.kind}`} key={i}>
                      {b.kind === 'err' ? paintReport('human', b.text) : b.text}
                    </pre>
                  ),
                )}
                <div className="sh__line">
                  {!frame.busy && <span className="sh__ps">~/demo $</span>} {frame.input}
                  <span
                    key={frame.input.length}
                    className="caret caret--inline"
                    data-idle={frame.focus !== 'shell'}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <p className="demo__caption" aria-hidden>
          <span className="demo__chapter">
            [{frame.chapter + 1}/{TL.chapters.length}]
          </span>{' '}
          <span className="demo__say">{inline(frame.caption)}</span>
        </p>

        <div className="demo__status">
          <button
            type="button"
            className="demo__play"
            onClick={toggle}
            aria-label={playing ? 'Pause the demo' : 'Play the demo'}
          >
            {playing ? (
              <svg viewBox="0 0 12 12" width="12" height="12" aria-hidden>
                <path d="M3 2h2v8H3zM7 2h2v8H7z" fill="currentColor" />
              </svg>
            ) : (
              <svg viewBox="0 0 12 12" width="12" height="12" aria-hidden>
                <path d="M3 1.5v9l7-4.5z" fill="currentColor" />
              </svg>
            )}
          </button>
          <span className="demo__session" aria-hidden>
            [axiom]
          </span>
          <ol className="demo__chapters" aria-label="Chapters">
            {TL.chapters.map((c, i) => (
              <li key={c.name}>
                <button
                  type="button"
                  aria-current={frame.chapter === i ? 'step' : undefined}
                  aria-label={`Play from ${c.name}`}
                  onClick={() => jump(i)}
                >
                  <span aria-hidden>
                    {i}:{c.name}
                    {frame.chapter === i ? '*' : ''}
                  </span>
                  <span
                    className="demo__fill"
                    aria-hidden
                    ref={(el) => {
                      fills.current[i] = el
                    }}
                  />
                </button>
              </li>
            ))}
          </ol>
        </div>
      </div>

      <figcaption className="visually-hidden">
        A recorded terminal session: {TRANSCRIPT.join(' ')}
      </figcaption>
    </figure>
  )
}
