import { FAQS } from '../data/content.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * Questions people actually ask, as <details>: they open with no
 * JavaScript, a crawler reads every answer, and `prerender.mjs` emits
 * the same list as FAQPage structured data.
 */
export function Faq() {
  return (
    <section className="section section--alt" id="faq" aria-labelledby="faq-h">
      <div className="container">
        <SectionHead id="faq-h" eyebrow="FAQ" title="Questions people ask." />
        <div className="faq">
          {FAQS.map((f) => (
            <details key={f.q} className="faq__item">
              <summary>
                <span>{f.q}</span>
              </summary>
              <div className="faq__a">
                {f.a.map((para) => (
                  <p key={para.slice(0, 32)}>{inline(para)}</p>
                ))}
                {f.link && (
                  <a href={f.link.href} target="_blank" rel="noreferrer noopener">
                    {f.link.label}
                    <ArrowUpRight size={12} />
                  </a>
                )}
              </div>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
