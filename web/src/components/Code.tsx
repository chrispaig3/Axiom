import { Fragment, useId, useMemo, useState, type ReactNode } from 'react'
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

interface CodeProps {
  code: string
  /** Filename shown in the frame's title bar. */
  name?: string
  /** Right-hand badge. */
  badge?: string
  caption?: ReactNode
  /** `false` renders plain — for terminal output, not source. */
  axiom?: boolean
  /** Wrap long lines instead of scrolling them. */
  wrap?: boolean
  tight?: boolean
  /** Accessible label when the frame has no visible filename. */
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
      <div className="code__body">
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

/**
 * A tab strip over several programs, each with its own output. A real
 * ARIA tablist with arrow-key navigation, because a set of buttons that
 * swaps a panel is a tablist whether or not it says so.
 */
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
        className="code__body"
        id={`${uid}-panel-${active}`}
        role="tabpanel"
        aria-labelledby={`${uid}-tab-${active}`}
        tabIndex={0}
      >
        <pre>
          <code>
            <Highlighted code={current.code} />
          </code>
        </pre>
      </div>

      {current.output && (
        <div className="code__out">
          <span className="code__out-label">
            $ axiom run {current.tab}
          </span>
          <pre>{current.output}</pre>
        </div>
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
