import {
  Fragment,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { highlight, type Token } from '../lib/highlight.ts'
import { ArrowUpRight } from './Icons.tsx'

const cls = (capture: Token['capture']) => `tok-${capture.replace(/\./g, '-')}`

function Highlighted({ code }: { code: string }) {
  const tokens = useMemo(() => highlight(code), [code])
  return (
    <>
      {tokens.map((t, i) =>
        t.capture === 'text' ? (
          <Fragment key={i}>{t.text}</Fragment>
        ) : (
          <span key={i} className={cls(t.capture)}>
            {t.text}
          </span>
        ),
      )}
    </>
  )
}

/**
 * The gutter. It is a sibling of the code rather than part of it, and is
 * `aria-hidden` with `user-select: none`, so selecting the sample copies
 * the program and not a column of integers.
 */
function Gutter({ code }: { code: string }) {
  const count = code.split('\n').length
  return (
    <div className="code__gutter" aria-hidden>
      {Array.from({ length: count }, (_, i) => (
        <span key={i}>{i + 1}</span>
      ))}
    </div>
  )
}

const reducedMotion = () =>
  typeof matchMedia === 'function' &&
  matchMedia('(prefers-reduced-motion: reduce)').matches

/**
 * The run strip: a prompt, a brief compile beat, then the program's real
 * output a line at a time.
 *
 * The delay is theatre and is labelled as such — it is not a measured
 * compile time, and the benchmark section carries the number that is.
 * It exists because a static block of green text does not read as
 * *output*; watching it arrive does. Under `prefers-reduced-motion` the
 * whole sequence collapses to the finished state, and the text is in the
 * DOM either way, so a screen reader never waits for an animation.
 */
function RunOutput({ tab, output }: { tab: string; output: string }) {
  const lines = useMemo(() => output.split('\n'), [output])
  const [shown, setShown] = useState(() => (reducedMotion() ? lines.length : 0))
  const [busy, setBusy] = useState(() => !reducedMotion())
  const timers = useRef<number[]>([])

  useEffect(() => {
    for (const t of timers.current) window.clearTimeout(t)
    timers.current = []

    if (reducedMotion()) {
      setShown(lines.length)
      setBusy(false)
      return
    }

    setShown(0)
    setBusy(true)
    timers.current.push(
      window.setTimeout(() => setBusy(false), 420),
      ...lines.map((_, i) =>
        window.setTimeout(() => setShown(i + 1), 460 + i * 130),
      ),
    )
    return () => {
      for (const t of timers.current) window.clearTimeout(t)
    }
  }, [tab, lines])

  return (
    <div className="code__out" data-busy={busy}>
      <span className="code__out-label">
        <span className="code__out-prompt">$</span> axiom run {tab}
      </span>
      <pre>
        {busy ? (
          <span className="code__out-busy">compiling…</span>
        ) : (
          lines.map((line, i) => (
            <span
              key={i}
              className="code__out-line"
              data-shown={i < shown}
            >
              {line}
              {'\n'}
            </span>
          ))
        )}
      </pre>
    </div>
  )
}

interface CodeProps {
  code: string
  name?: string
  badge?: string
  caption?: ReactNode
  /** `false` renders plain — for terminal output, not source. */
  axiom?: boolean
  wrap?: boolean
  tight?: boolean
  /** Show the line-number gutter. */
  numbered?: boolean
  label?: string
}

export function Code({
  code,
  name,
  badge,
  caption,
  axiom = true,
  wrap = false,
  tight = false,
  numbered = false,
  label,
}: CodeProps) {
  const classes = ['code']
  if (wrap) classes.push('code--wrap')
  if (tight) classes.push('code--tight')

  return (
    <figure className={classes.join(' ')} style={{ margin: 0 }}>
      {(name || badge) && (
        <div className="code__bar">
          {name && <span className="code__name">{name}</span>}
          {badge && <span className="code__badge">{badge}</span>}
        </div>
      )}
      <div className={numbered ? 'code__body code__body--numbered' : 'code__body'}>
        {numbered && <Gutter code={code} />}
        <pre>
          <code aria-label={label}>
            {axiom ? <Highlighted code={code} /> : code}
          </code>
        </pre>
      </div>
      {caption && <figcaption className="code__caption">{caption}</figcaption>}
    </figure>
  )
}

export interface TabbedItem {
  id: string
  tab: string
  code: string
  /** Real program output, shown under the source. */
  output?: string
  caption?: ReactNode
}

export function TabbedCode({
  items,
  label,
}: {
  items: TabbedItem[]
  label: string
}) {
  const [active, setActive] = useState(0)
  const uid = useId()
  const current = items[active] ?? items[0]
  if (!current) return null

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    e.preventDefault()
    const delta = e.key === 'ArrowRight' ? 1 : -1
    const next = (active + delta + items.length) % items.length
    setActive(next)
    document.getElementById(`${uid}-tab-${next}`)?.focus()
  }

  return (
    <div className="code code--program">
      <div className="code__bar">
        <div
          className="code__tabs"
          role="tablist"
          aria-label={label}
          onKeyDown={onKeyDown}
        >
          {items.map((item, i) => (
            <button
              key={item.id}
              id={`${uid}-tab-${i}`}
              className="code__tab"
              type="button"
              role="tab"
              aria-selected={i === active}
              aria-controls={`${uid}-panel-${i}`}
              tabIndex={i === active ? 0 : -1}
              onClick={() => setActive(i)}
            >
              {item.tab}
            </button>
          ))}
        </div>
      </div>

      <div
        className="code__body code__body--numbered"
        id={`${uid}-panel-${active}`}
        role="tabpanel"
        aria-labelledby={`${uid}-tab-${active}`}
        tabIndex={0}
      >
        <Gutter code={current.code} />
        <pre>
          <code>
            <Highlighted code={current.code} />
          </code>
        </pre>
      </div>

      {current.output && (
        <RunOutput
          key={current.id}
          tab={current.tab}
          output={current.output}
        />
      )}

      {current.caption && <div className="code__caption">{current.caption}</div>}
    </div>
  )
}

/** A repo path rendered as a link to the file on GitHub. */
export function SourceLink({ path, href }: { path: string; href: string }) {
  return (
    <a href={href} target="_blank" rel="noreferrer noopener">
      {path}
      <ArrowUpRight size={11} />
    </a>
  )
}
