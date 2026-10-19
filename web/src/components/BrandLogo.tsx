import brand from '../../../assets/logo/geometry.json'

const HEIGHT = 26

// The social card's split-A wordmark (generate-brand.cjs `socialLogo`):
// the lime mark stands in for the wordmark's `A`, and the remaining
// letters move 60px left at the card's 0.66 render scale.
const SOCIAL_SHIFT = -60 / 0.66

/** The split-A lockup from the brand kit, drawn from the same outlines as assets/logo. */
export function BrandLogo() {
  const { height, mark, word } = brand.lockup
  const wordX = Number(/translate\(([-\d.]+)/.exec(word)?.[1] ?? 0)
  const width = wordX + SOCIAL_SHIFT + brand.wordmark.width
  return (
    <svg
      className="brand__logo"
      width={Math.round((HEIGHT * width) / height)}
      height={HEIGHT}
      viewBox={`0 0 ${width} ${height}`}
      aria-hidden="true"
      focusable="false"
    >
      <path d={brand.markPath} transform={mark} className="brand__symbol" />
      <g fill="currentColor" transform={word}>
        <g transform={`translate(${SOCIAL_SHIFT} 0)`}>
          {brand.wordmarkPaths.slice(1).map((d, i) => <path key={i} d={d} />)}
        </g>
      </g>
    </svg>
  )
}
