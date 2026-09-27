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
        <SectionHead id="why-h" eyebrow="Why Axiom" title="What it does differently.">
          <p>Six design decisions. The link under each goes to the code that enforces it.</p>
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
