import { asset } from '../lib/asset.ts'
import { BLOB, DOCS, RELEASES, REPO, VERSION } from '../data/site.ts'

const COLUMNS: { title: string; links: [string, string][] }[] = [
  {
    title: 'Learn',
    links: [
      ['Tour', '#tour'],
      ['Language reference', `${DOCS}/reference.md`],
      ['Standard library', `${DOCS}/stdlib-api.md`],
      ['Examples', `${BLOB}/examples/README.md`],
      ['Editor setup', `${DOCS}/lsp.md`],
      ['Calling Rust', `${DOCS}/ffi.md`],
    ],
  },
  {
    title: 'Specifications',
    links: [
      ['Memory model', `${DOCS}/memory-model.md`],
      ['Error model', `${DOCS}/error-model.md`],
      ['Diagnostics', `${DOCS}/diagnostics.md`],
      ['Agent harness', `${DOCS}/agent-harness.md`],
      ['Compatibility', `${DOCS}/compatibility.md`],
      ['Status', `${DOCS}/status.md`],
    ],
  },
  {
    title: 'Project',
    links: [
      ['GitHub', REPO],
      ['Releases', RELEASES],
      ['Changelog', `${BLOB}/CHANGELOG.md`],
      ['Contributing', `${BLOB}/CONTRIBUTING.md`],
      ['Security', `${BLOB}/SECURITY.md`],
      ['Issues', `${REPO}/issues`],
    ],
  },
]

export function Footer() {
  return (
    <footer className="footer">
      <div className="container footer__inner">
        <div className="footer__brand">
          <a className="brand" href="#top">
            <img className="brand__mark" src={asset('axiom-mark.png')} alt="" width={26} height={24} />
            <span className="brand__word">Axiom</span>
          </a>
          <p>
            A small language for ambitious ideas. Built in the open, with room for your contribution.{' '}
            <a href={`${REPO}/issues`} target="_blank" rel="noreferrer noopener">
              Open an issue
            </a>
            .
          </p>
          <p className="footer__fine">
            Axiom {VERSION} · MIT licensed · © 2026 Chris Paige
            <br />
            High-level thinking. Native-level control.
          </p>
        </div>
        {COLUMNS.map((c) => (
          <nav className="footer__col" key={c.title} aria-label={c.title}>
            <h2>{c.title}</h2>
            <ul>
              {c.links.map(([label, href]) => (
                <li key={label}>
                  {href.startsWith('#') ? (
                    <a href={href}>{label}</a>
                  ) : (
                    <a href={href} target="_blank" rel="noreferrer noopener">
                      {label}
                    </a>
                  )}
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>
    </footer>
  )
}
