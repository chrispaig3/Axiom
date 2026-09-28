import brand from '../../../assets/logo/geometry.json'

const HEIGHT = 26

/** The lockup from the brand kit, drawn from the same outlines as assets/logo. */
export function BrandLogo() {
  const { width, height, mark, word } = brand.lockup
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
        {brand.wordmarkPaths.map((d, i) => <path key={i} d={d} />)}
      </g>
    </svg>
  )
}
