import { asset } from '../lib/asset.ts'
import { REPO, VERSION } from '../data/site.ts'
import { GitHub, Moon, Sun } from './Icons.tsx'
import type { Theme } from '../lib/theme.ts'

const LINKS = [
  { href: '#code', label: 'The language' },
  { href: '#speed', label: 'Measured' },
  { href: '#for', label: 'Built for' },
  { href: '#agents', label: 'Diagnostics' },
  { href: '#start', label: 'Install' },
]

export function Nav({ theme, onToggle }: { theme: Theme; onToggle: () => void }) {
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
          <button
            type="button"
            className="icon-btn"
            onClick={onToggle}
            aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
          >
            {theme === 'dark' ? <Sun /> : <Moon />}
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
