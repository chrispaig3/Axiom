import { BLOB, DOCS, INSTALL_CMD, REPO } from '../data/site.ts'
import { Command } from '../components/Command.tsx'
import { ArrowUpRight, Book, Chat, GitBranch, Star } from '../components/Icons.tsx'

/**
 * The close: the install command again, where a reader who scrolled the
 * whole way has run out of page, and three ways to take part, in the
 * shape of rust-lang.org's "Get involved".
 */
const INVOLVED = [
  {
    Icon: Book,
    title: 'Learn it',
    body: 'Start with the tour on this page, then the reference, which covers the whole language section by section.',
    link: { label: 'Language reference', href: `${DOCS}/reference.md` },
  },
  {
    Icon: Chat,
    title: 'Report what you find',
    body: 'A wrong answer, a confusing error, a claim on this page that does not hold. An issue with a reproduction is the most useful thing you can send.',
    link: { label: 'Open an issue', href: `${REPO}/issues` },
  },
  {
    Icon: GitBranch,
    title: 'Contribute',
    body: 'The compiler is Axiom, so contributing means writing it. One rule governs every change: if you claim it, gate it.',
    link: { label: 'Contributing guide', href: `${BLOB}/CONTRIBUTING.md` },
  },
]

export function Closing() {
  return (
    <section className="cta ink" aria-labelledby="cta-h">
      <div className="cta__bg" aria-hidden />
      <div className="container">
        <div className="cta__inner">
          <h2 id="cta-h">
            Write a program that is <span className="grad">just a program.</span>
          </h2>
          <p>
            No runtime to ship, no collector to tune, no C library underneath. Install it in a
            minute, or build it from source with <code>llc</code> and a C compiler.
          </p>
          <Command command={INSTALL_CMD} />
          <div className="cta__actions">
            <a className="btn btn--primary btn--lg" href="#start">
              Get started
            </a>
            <a className="btn btn--ghost btn--lg" href={`${REPO}/stargazers`} target="_blank" rel="noreferrer noopener">
              <Star size={16} />
              Star on GitHub
            </a>
          </div>
        </div>

        <ul className="involved" aria-label="Get involved">
          {INVOLVED.map(({ Icon, title, body, link }) => (
            <li key={title}>
              <span className="involved__icon" aria-hidden>
                <Icon size={18} />
              </span>
              <h3>{title}</h3>
              <p>{body}</p>
              <a href={link.href} target="_blank" rel="noreferrer noopener">
                {link.label}
                <ArrowUpRight size={12} />
              </a>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
