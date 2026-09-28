/** A lightweight, decorative view of the source-to-native pipeline. */
export function NativeVisual() {
  return (
    <div className="native-visual" aria-hidden="true">
      <div className="native-visual__grid" />
      <div className="native-visual__label"><span>AX / NATIVE COMPILATION</span><span>001</span></div>
      <svg className="native-visual__drawing" viewBox="0 0 500 430" fill="none">
        <defs>
          <linearGradient id="axiom-prism" x1="140" y1="100" x2="340" y2="345" gradientUnits="userSpaceOnUse">
            <stop stopColor="currentColor" stopOpacity=".22" /><stop offset="1" stopColor="currentColor" stopOpacity=".015" />
          </linearGradient>
        </defs>
        <g className="native-orbits" stroke="currentColor">
          <ellipse cx="250" cy="228" rx="208" ry="78" transform="rotate(-28 250 228)" />
          <ellipse cx="250" cy="228" rx="190" ry="124" transform="rotate(38 250 228)" />
          <circle cx="250" cy="228" r="171" strokeDasharray="2 9" />
        </g>
        <g className="native-prism">
          <path d="M250 79 380 317 250 371 120 317Z" fill="url(#axiom-prism)" stroke="currentColor" strokeOpacity=".5" />
          <path d="m250 79 0 292M120 317l130-63 130 63M250 79 180 290m70-211 70 211" stroke="currentColor" strokeOpacity=".22" />
          <path d="m186 287 64-126 64 126m-106-39h84" stroke="currentColor" strokeWidth="9" strokeLinecap="square" />
          <path d="M250 79 380 317 250 371 120 317Z" className="native-prism__trace" stroke="currentColor" strokeWidth="2" />
        </g>
        <g fill="currentColor"><circle cx="250" cy="79" r="3" /><circle cx="120" cy="317" r="3" /><circle cx="380" cy="317" r="3" /><circle cx="250" cy="371" r="3" /></g>
      </svg>
      <div className="native-chip native-chip--source"><span className="native-chip__label">SOURCE / .ax</span><code>(fn (square x) (* x x))</code></div>
      <div className="native-chip native-chip--output"><span className="native-chip__label"><i /> NATIVE EXECUTABLE</span><code>Ideas in. Machine code out.</code></div>
      <div className="native-visual__pipeline"><span>Axiom</span><i /><span>LLVM IR</span><i /><span>Native</span></div>
    </div>
  )
}
