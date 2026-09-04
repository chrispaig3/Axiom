import { DOCS, INSTALL_CMD, REPO } from '../data/site.ts'
import { Command } from '../components/Command.tsx'
import { ArrowUpRight, GitHub } from '../components/Icons.tsx'

/**
 * The final call to action: the same command as the top of the page,
 * restated where a reader who scrolled the whole way has run out of
 * page. README.md, "Install", is the source of the installer's claim.
 */
export function Closing() {
  return (
    <section className="cta" aria-labelledby="cta-h">
      <div className="container cta__inner">
        <h2 id="cta-h">Try it in the next minute.</h2>
        <p>
          <code>llc</code> and a C compiler are the only prerequisites. The
          installer verifies the archive, builds and runs a program that
          imports the standard library, and only then reports success.
        </p>
        <Command command={INSTALL_CMD} />
        <div className="hero__actions">
          <a
            className="btn btn--ghost"
            href={`${DOCS}/reference.md`}
            target="_blank"
            rel="noreferrer noopener"
          >
            Read the reference
            <ArrowUpRight size={14} />
          </a>
          <a
            className="btn btn--ghost"
            href={REPO}
            target="_blank"
            rel="noreferrer noopener"
          >
            <GitHub />
            GitHub
          </a>
        </div>
      </div>
    </section>
  )
}
