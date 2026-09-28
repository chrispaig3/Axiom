import { useEffect, useId, useState } from 'react'
import { asset } from '../lib/asset.ts'
import { DOCS, REPO, VERSION } from '../data/site.ts'
import { GitHub, Menu, Moon, Sun, X } from './Icons.tsx'

const LINKS = [
  { href: '#why', label: 'Why Axiom' },
  { href: '#tour', label: 'Tour' },
  { href: '#speed', label: 'Performance' },
  { href: '#status', label: 'Status' },
]

/**
 * The section links are a row on a wide screen and a disclosure on a
 * narrow one. The link for the section in view is marked
 * `aria-current`, which is an enhancement: the server renders none
 * marked, and nothing depends on it.
 */
export function Nav({ onToggle }: { onToggle: () => void }) {
  const [open, setOpen] = useState(false)
  const [current, setCurrent] = useState<string | null>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    const close = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', close)
    return () => window.removeEventListener('keydown', close)
  }, [open])

  useEffect(() => {
    if (typeof IntersectionObserver !== 'function') return
    const targets = ['#top', ...LINKS.map((l) => l.href)].map((href) => document.getElementById(href.slice(1))).filter(
      (el): el is HTMLElement => Boolean(el),
    )
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) if (e.isIntersecting) setCurrent(e.target.id === 'top' ? null : `#${e.target.id}`)
      },
      { rootMargin: '-45% 0px -50% 0px' },
    )
    targets.forEach((t) => io.observe(t))
    return () => io.disconnect()
  }, [])

  return (
    <header className="nav" data-open={open}>
      <div className="container nav__inner">
        <a className="brand" href="#top" aria-label="Axiom, back to the top">
          <img
            className="brand__mark"
            src={asset('axiom-mark.png')}
            alt=""
            width={26}
            height={24}
          />
          <span className="brand__word">Axiom</span>
          <span className="brand__version">{VERSION}</span>
        </a>

        <nav className="nav__links" id={menuId} aria-label="Sections">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              aria-current={current === l.href ? 'true' : undefined}
              onClick={() => setOpen(false)}
            >
              {l.label}
            </a>
          ))}
          <a href={`${DOCS}/reference.md`} target="_blank" rel="noreferrer noopener">
            Docs
          </a>
        </nav>

        <div className="nav__actions">
          {/* BOTH GLYPHS, and CSS picks. The page is rendered in Node at
              build time (scripts/prerender.mjs), where there is no
              `matchMedia` and no `localStorage`, so React would emit one
              glyph for every reader and a dark-mode visitor would hydrate
              into a mismatch. `data-theme` is stamped by the inline
              script in index.html before first paint, so CSS knows the
              answer and React renders one thing. */}
          <button
            type="button"
            className="icon-btn icon-btn--theme"
            onClick={onToggle}
            aria-label="Switch the colour theme"
          >
            <span className="icon-btn__moon" aria-hidden="true">
              <Moon />
            </span>
            <span className="icon-btn__sun" aria-hidden="true">
              <Sun />
            </span>
          </button>
          <a
            className="icon-btn"
            href={REPO}
            target="_blank"
            rel="noreferrer noopener"
            aria-label="Axiom on GitHub"
          >
            <GitHub />
          </a>
          <a className="btn btn--primary btn--sm nav__cta" href="#start">
            Get started
          </a>
          <button
            type="button"
            className="icon-btn icon-btn--menu"
            onClick={() => setOpen((o) => !o)}
            aria-expanded={open}
            aria-controls={menuId}
            aria-label={open ? 'Close the section menu' : 'Open the section menu'}
          >
            {open ? <X /> : <Menu />}
          </button>
        </div>
      </div>
    </header>
  )
}
