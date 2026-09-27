import { Nav } from './components/Nav.tsx'
import { Hero } from './sections/Hero.tsx'
import { Pillars } from './sections/Pillars.tsx'
import { Tour } from './sections/Tour.tsx'
import { Benchmark } from './sections/Benchmark.tsx'
import { Compare } from './sections/Compare.tsx'
import { Start } from './sections/Start.tsx'
import { Status } from './sections/Status.tsx'
import { Faq } from './sections/Faq.tsx'
import { Footer } from './sections/Footer.tsx'
import { useTheme } from './lib/theme.ts'

/**
 * The page, in the order a newcomer's questions arrive: show me, why
 * would I want it, teach me, is it fast, how does it compare, how do I
 * start, what is missing, and the questions left over. Each question is
 * answered once; the footer carries the links to everything else.
 */
export default function App() {
  // The theme VALUE is not read here: the toggle stamps `data-theme`,
  // and the glyph that depends on it is chosen by CSS, so the markup is
  // identical on the server and the client.
  const [, toggle] = useTheme()

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav onToggle={toggle} />
      <main id="main">
        <Hero />
        <Pillars />
        <Tour />
        <Benchmark />
        <Compare />
        <Start />
        <Status />
        <Faq />
      </main>
      <Footer />
    </>
  )
}
