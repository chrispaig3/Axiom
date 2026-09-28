import { BLOB, INSTALL_CMD, RELEASES, VERSION } from '../data/site.ts'
import { Command } from '../components/Command.tsx'
import { Demo } from '../components/Demo.tsx'
import { ArrowRight, ArrowUpRight } from '../components/Icons.tsx'
import { NativeVisual } from '../components/NativeVisual.tsx'

export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-h">
      <div className="hero__bg" aria-hidden />
      <div className="container">
        <div className="hero__opening">
          <div className="hero__lead">
            <a className="release-link" href={`${RELEASES}/tag/v${VERSION}`} target="_blank" rel="noreferrer noopener">
              <span className="release-link__dot" aria-hidden />
              Axiom {VERSION}<span className="release-link__sep" aria-hidden>/</span> Open source. Built in Axiom.
              <ArrowUpRight size={13} />
            </a>
            <p className="hero__eyebrow">The functional systems language</p>
            <h1 id="hero-h">High-level thinking.<br /><span>Native-level control.</span></h1>
            <p className="hero__lede">
              Express your ideas with powerful types. Catch missing cases and check effects at compile time.
              Ship a native binary with no VM or garbage collector.
            </p>
            <div className="hero__actions">
              <a className="btn btn--primary btn--lg" href="#start">Build with Axiom <ArrowRight /></a>
              <a className="btn btn--ghost btn--lg" href="#tour">Explore the language <span aria-hidden>↗</span></a>
            </div>
            <p className="hero__audience">For people who care how their code reaches the machine.</p>
          </div>
          <NativeVisual />
        </div>

        <div className="hero__principles" aria-label="Axiom at a glance">
          <a href="#tour"><span>01 / Expressive by design</span><strong>Types that model your ideas.</strong><ArrowUpRight size={16} /></a>
          <a href="#why"><span>02 / Explicit where it counts</span><strong>Effects the compiler checks.</strong><ArrowUpRight size={16} /></a>
          <a href="#speed"><span>03 / Native from the start</span><strong>LLVM. Straight to the machine.</strong><ArrowUpRight size={16} /></a>
        </div>

        <div className="hero__stage">
          <div className="stage-heading">
            <div><p className="eyebrow">See it in action</p><h2>A small program. The whole picture.</h2></div>
            <p>Write it. Run it. Break it.<br />Watch the compiler catch what changed.</p>
          </div>
          <Demo />
        </div>

        <div className="hero__install">
          <div><span className="install-label">Your next native binary starts here.</span><p className="hero__note">Prebuilt for macOS &amp; Linux arm64. <a href="#start">Setup &amp; other targets <ArrowRight size={12} /></a></p></div>
          <Command command={INSTALL_CMD} />
        </div>
        <p className="hero__footnote">Early-stage language. Real compiler. <a href={`${BLOB}/docs/status.md`} target="_blank" rel="noreferrer noopener">See what’s ready today.</a></p>
      </div>
    </section>
  )
}
