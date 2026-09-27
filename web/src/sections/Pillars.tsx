import { PILLARS, type PillarIcon } from '../data/content.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight, Bot, Box, LinkIcon, Loop, Shield, Terminal } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

const ICONS: Record<PillarIcon, typeof Box> = {
  box: Box,
  shield: Shield,
  terminal: Terminal,
  bot: Bot,
  loop: Loop,
  link: LinkIcon,
}

export function Pillars() {
  return (
    <section className="section section--alt" id="why" aria-labelledby="why-h">
      <div className="container">
        <SectionHead id="why-h" eyebrow="Why Axiom" title="Small on purpose. Strict where it counts." center>
          <p>
            A small, explicit core, a compiler that refuses to guess, and executables with nothing
            inside them you did not ask for. Six properties, each held by something you can run.
          </p>
        </SectionHead>

        <ul className="pillars">
          {PILLARS.map((p) => {
            const Icon = ICONS[p.icon]
            return (
              <li className="pillar" key={p.title}>
                <span className="pillar__icon" aria-hidden>
                  <Icon size={20} />
                </span>
                <h3>{p.title}</h3>
                <p>{inline(p.body)}</p>
                <a className="pillar__proof" href={p.href} target="_blank" rel="noreferrer noopener">
                  <code>{p.proof}</code>
                  <ArrowUpRight size={12} />
                </a>
              </li>
            )
          })}
        </ul>
      </div>
    </section>
  )
}
