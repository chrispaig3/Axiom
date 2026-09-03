import { asset } from '../lib/asset.ts'
import { REPO, VERSION } from '../data/site.ts'
import { GitHub, Moon, Sun } from './Icons.tsx'

const LINKS = [
  { href: '#code', label: 'The language' },
  { href: '#speed', label: 'Measured' },
  { href: '#for', label: 'Built for' },
  { href: '#agents', label: 'Diagnostics' },
  { href: '#start', label: 'Install' },
]

export function Nav({ onToggle }: { onToggle: () => void }) {
  return (
    <header className="site-nav">
      <div className="container site-nav__inner">
        <a className="brand" href="#top">
          <img
            className="brand__mark"
            src={asset('axiom-mark.png')}
            alt=""
            width={26}
            height={24}
            style={{ borderRadius: 4 }}
          />
          Axiom
          <span className="brand__version">{VERSION}</span>
        </a>

        <nav className="nav-links" aria-label="Sections">
          {LINKS.map((l) => (
            <a key={l.href} href={l.href}>
              {l.label}
            </a>
          ))}
        </nav>

        <div className="nav-actions">
          {/* BOTH GLYPHS, and CSS picks. The page is rendered in Node at
              build time (scripts/prerender.mjs), where there is no
              `matchMedia` and no `localStorage`, so `useTheme` resolves
              to 'light' and React would emit the Moon on the server for
              every reader. A dark-mode visitor would then hydrate into a
              mismatch — a console error on the one page whose gate exists
              to catch console errors. `data-theme` is stamped by the
              inline script in index.html before first paint, so CSS knows
              the answer and React renders one thing. */}
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
        </div>
      </div>
    </header>
  )
}
