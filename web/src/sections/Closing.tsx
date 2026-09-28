import { ArrowRight, GitHub } from '../components/Icons.tsx'
import { REPO } from '../data/site.ts'

export function Closing() {
  return (
    <section className="closing" aria-labelledby="closing-h">
      <div className="container closing__inner">
        <div className="closing__copy">
          <p className="eyebrow">From idea to executable</p>
          <h2 id="closing-h">Think in types.<br /><span>Build something native.</span></h2>
          <p>Your first program is a few commands away. Try the language, inspect the compiler, and help shape what comes next.</p>
          <div className="hero__actions">
            <a className="btn btn--primary btn--lg" href="#start">Get started <ArrowRight /></a>
            <a className="btn btn--ghost btn--lg" href={REPO} target="_blank" rel="noreferrer noopener"><GitHub size={17} /> Explore the source</a>
          </div>
        </div>
        <span className="closing__glyph" aria-hidden="true">(λ)</span>
      </div>
    </section>
  )
}
