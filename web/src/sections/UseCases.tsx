import { USE_CASES, type UseCaseIcon } from '../data/content.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowRight, Bot, Globe, Shield, Terminal } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

const ICONS: Record<UseCaseIcon, typeof Bot> = {
  terminal: Terminal,
  globe: Globe,
  shield: Shield,
  bot: Bot,
}

/**
 * Where the design pays off, four ways. The shape is rust-lang.org's
 * "Build it in Rust": a kind of work, the claim for it, the reasons,
 * and a door into the documentation - rather than a feature list that
 * leaves the reader to work out what it is for.
 */
export function UseCases() {
  return (
    <section className="section section--alt" id="built-for" aria-labelledby="usecases-h">
      <div className="container">
        <SectionHead id="usecases-h" eyebrow="Built for" title="Where a runtime you did not write is a liability.">
          <p>
            Axiom is small on purpose. These are the kinds of work where that pays off, and where a
            compiler that checks what a function may do is worth the most.
          </p>
        </SectionHead>

        <div className="usecases">
          {USE_CASES.map((u, i) => {
            const Icon = ICONS[u.icon]
            return (
              <article className="usecase" key={u.kicker} data-i={i}>
                <div className="usecase__top">
                  <span className="usecase__icon" aria-hidden>
                    <Icon size={20} />
                  </span>
                  <span className="usecase__kicker">{u.kicker}</span>
                </div>
                <h3>{u.title}</h3>
                <p>{inline(u.body)}</p>
                <ul>
                  {u.points.map((pt) => (
                    <li key={pt}>{inline(pt)}</li>
                  ))}
                </ul>
                <a className="usecase__link" href={u.link.href} target="_blank" rel="noreferrer noopener">
                  {u.link.label}
                  <ArrowRight size={14} />
                </a>
              </article>
            )
          })}
        </div>
      </div>
    </section>
  )
}
