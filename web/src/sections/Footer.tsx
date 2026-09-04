import { REPO, VERSION } from '../data/site.ts'

const LINKS = [
  ['GitHub', REPO],
  ['Reference', `${REPO}/blob/trunk/docs/reference.md`],
  ['Changelog', `${REPO}/blob/trunk/CHANGELOG.md`],
  ['Releases', `${REPO}/releases`],
  ['Issues', `${REPO}/issues`],
]

export function Footer() {
  return (
    <footer className="site-footer">
      <div className="container site-footer__inner">
        <p>
          Axiom {VERSION} · MIT · © 2026 Chris Paige
          <br />
          Code on this page is coloured by a highlighter that follows the
          language's own tree-sitter queries, capture for capture.
        </p>
        <nav aria-label="Elsewhere">
          {LINKS.map(([label, href]) => (
            <a key={label} href={href} target="_blank" rel="noreferrer noopener">
              {label}
            </a>
          ))}
        </nav>
      </div>
    </footer>
  )
}
