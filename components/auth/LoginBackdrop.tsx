// Moving background for the login page: a slowly drifting honeycomb (the hexagon from the
// logo) over three soft lights. Styles and keyframes are in app/globals.css (.login-*);
// everything stands still when the visitor prefers reduced motion.
const HEX_TILE_WIDTH = 52
const HEX_TILE_HEIGHT = 90.0666

// Five hexagons (radius 52 / sqrt(3)) that tile seamlessly in a 52 x 90.07 pattern cell.
const HEX_PATH =
  'M0 -30.02 L26 -15.01 L26 15.01 L0 30.02 L-26 15.01 L-26 -15.01 Z ' +
  'M52 -30.02 L78 -15.01 L78 15.01 L52 30.02 L26 15.01 L26 -15.01 Z ' +
  'M0 60.04 L26 75.06 L26 105.08 L0 120.09 L-26 105.08 L-26 75.06 Z ' +
  'M52 60.04 L78 75.06 L78 105.08 L52 120.09 L26 105.08 L26 75.06 Z ' +
  'M26 15.01 L52 30.02 L52 60.04 L26 75.06 L0 60.04 L0 30.02 Z'

export function LoginBackdrop() {
  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden">
      <div className="login-orb login-orb-a" />
      <div className="login-orb login-orb-b" />
      <div className="login-orb login-orb-c" />

      {/* The mask is on this static wrapper; only the inner lattice moves. */}
      <div className="absolute inset-0 [mask-image:radial-gradient(ellipse_75%_70%_at_68%_45%,black,transparent)]">
        <svg className="login-lattice">
          <defs>
            <pattern
              id="login-hex"
              width={HEX_TILE_WIDTH}
              height={HEX_TILE_HEIGHT}
              patternUnits="userSpaceOnUse"
            >
              <path d={HEX_PATH} fill="none" stroke="currentColor" strokeWidth="1.25" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#login-hex)" />
        </svg>
      </div>
    </div>
  )
}
