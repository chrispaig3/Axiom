import { DOC_GROUPS } from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'

export function Docs() {
  return (
    <section className="section" id="docs" aria-labelledby="docs-h">
      <div className="container">
        <SectionHead id="docs-h" eyebrow="Documentation" title="Go deeper.">
          <p>
            The reference covers the whole language. The specifications behind it mark every rule
            as holding, planned or refused, and name the probe that shows it.
          </p>
        </SectionHead>
        <div className="docs">
          {DOC_GROUPS.map((g) => (
            <div className="docs__group" key={g.title}>
              <h3>{g.title}</h3>
              <ul>
                {g.links.map((d) => (
                  <li key={d.name}>
                    <a href={d.href} target="_blank" rel="noreferrer noopener">
                      <span className="docs__name">
                        {d.name}
                        <ArrowUpRight size={12} />
                      </span>
                      <span className="docs__desc">{d.desc}</span>
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
