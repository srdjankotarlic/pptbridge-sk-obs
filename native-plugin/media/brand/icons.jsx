// PPTBridge SK — premium icon system v2
// Hero metaphor: presenter pane (back, dim) + broadcast output pane (front, bright)
// joined by a bridge cable. Restraint + depth + gradient strokes for premium feel.

const PPT = {
  // background — deep navy-graphite, not pure gray
  bg0: "#0E1620",
  bg1: "#070B12",
  glow: "#1B3148",         // upper-center subtle radial highlight
  rimLight: "rgba(255,255,255,0.10)",
  rimShadow: "rgba(0,0,0,0.55)",
  innerBorder: "rgba(255,255,255,0.05)",
  // primary (front pane) — light azure → deep cyan
  primaryHi: "#7DD3FC",
  primaryLo: "#0891B2",
  // back pane — slate, bumped for legibility at small sizes
  back: "#6B8294",
  // cable + accent glow
  cable: "#67E8F9",
  cableHi: "#A5F3FC",
  // status / live
  live: "#34D399",
  // mono variants
  monoLight: "#F2F6FA",
  monoDark: "#0B0F14",
};

// ──────────────────────────────────────────────────────────────────────────
// Surface — premium app-icon shell with inner light, rim highlight, vignette.
// idPrefix lets us reuse <defs> safely when many icons share the page.
// ──────────────────────────────────────────────────────────────────────────
function PPTSurface({ idPrefix, children, surface = "dark", radius = 224 }) {
  const id = idPrefix;
  if (surface === "transparent") return <g>{children}</g>;
  if (surface === "light") {
    return (
      <g>
        <defs>
          <clipPath id={`${id}_clip`}>
            <rect width="1000" height="1000" rx={radius} ry={radius} />
          </clipPath>
        </defs>
        <g clipPath={`url(#${id}_clip)`}>
          <rect width="1000" height="1000" fill="#F2F6FA" />
        </g>
        <rect x="3" y="3" width="994" height="994" rx={radius - 3} ry={radius - 3}
              fill="none" stroke="rgba(0,0,0,0.08)" strokeWidth="2" />
        {children}
      </g>
    );
  }
  return (
    <g>
      <defs>
        <linearGradient id={`${id}_bg`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={PPT.bg0} />
          <stop offset="1" stopColor={PPT.bg1} />
        </linearGradient>
        <radialGradient id={`${id}_glow`} cx="0.5" cy="0.18" r="0.85">
          <stop offset="0" stopColor={PPT.glow} stopOpacity="0.7" />
          <stop offset="0.55" stopColor={PPT.glow} stopOpacity="0.12" />
          <stop offset="1" stopColor={PPT.glow} stopOpacity="0" />
        </radialGradient>
        <linearGradient id={`${id}_rim`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="rgba(255,255,255,0.16)" />
          <stop offset="0.18" stopColor="rgba(255,255,255,0)" />
          <stop offset="0.82" stopColor="rgba(0,0,0,0)" />
          <stop offset="1" stopColor="rgba(0,0,0,0.45)" />
        </linearGradient>
        <clipPath id={`${id}_clip`}>
          <rect width="1000" height="1000" rx={radius} ry={radius} />
        </clipPath>
      </defs>

      {/* base surface */}
      <g clipPath={`url(#${id}_clip)`}>
        <rect width="1000" height="1000" fill={`url(#${id}_bg)`} />
        <rect width="1000" height="1000" fill={`url(#${id}_glow)`} />
        {/* rim light + inner shadow as a single overlay gradient */}
        <rect width="1000" height="1000" fill={`url(#${id}_rim)`} />
        {/* top hairline */}
        <rect x="0" y="0" width="1000" height="1.5" fill="rgba(255,255,255,0.18)" />
      </g>

      {/* outer dual-hairline border — the premium tell */}
      <rect x="1" y="1" width="998" height="998" rx={radius - 1} ry={radius - 1}
            fill="none" stroke="rgba(0,0,0,0.6)" strokeWidth="2" />
      <rect x="3" y="3" width="994" height="994" rx={radius - 3} ry={radius - 3}
            fill="none" stroke={PPT.innerBorder} strokeWidth="1" />

      {children}
    </g>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// PRIMARY MARK — dual-screen depth + bridge cable
// Drawn in 1000-unit space; coords chosen for legibility down to 16px.
// ──────────────────────────────────────────────────────────────────────────
function PPTMark({ idPrefix, tone = "color", showLive = false }) {
  const id = idPrefix;
  const isColor = tone === "color";
  const monoStroke = tone === "mono-light" ? PPT.monoLight : PPT.monoDark;

  const sw = 32; // base stroke width

  // Back pane (presenter view): smaller, top-left, recedes
  const back = { x: 165, y: 200, w: 460, h: 290, r: 32 };
  // Front pane (broadcast output): larger, bottom-right, advances
  const front = { x: 360, y: 460, w: 520, h: 330, r: 36 };

  // cable endpoints — exit back's right edge, enter front's top edge
  const cableStart = { x: back.x + back.w, y: back.y + back.h - 70 };       // (625, 420)
  const cableEnd   = { x: front.x + 90,    y: front.y };                     // (450, 460)

  return (
    <g>
      {isColor && (
        <defs>
          {/* primary stroke gradient — light azure top-left → deep cyan bottom-right */}
          <linearGradient id={`${id}_pri`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.primaryHi} />
            <stop offset="1" stopColor={PPT.primaryLo} />
          </linearGradient>
          {/* play-triangle fill gradient */}
          <linearGradient id={`${id}_play`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.primaryHi} />
            <stop offset="1" stopColor={PPT.primaryLo} />
          </linearGradient>
          {/* cable glow */}
          <linearGradient id={`${id}_cable`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.back} stopOpacity="0.4" />
            <stop offset="0.5" stopColor={PPT.cableHi} />
            <stop offset="1" stopColor={PPT.primaryHi} />
          </linearGradient>
          {/* soft glow under front pane */}
          <radialGradient id={`${id}_under`} cx="0.5" cy="0.5" r="0.5">
            <stop offset="0" stopColor={PPT.primaryHi} stopOpacity="0.32" />
            <stop offset="1" stopColor={PPT.primaryHi} stopOpacity="0" />
          </radialGradient>
        </defs>
      )}

      {/* halo behind front pane — sells the depth */}
      {isColor && (
        <ellipse cx={front.x + front.w / 2} cy={front.y + front.h - 30}
                 rx={front.w * 0.55} ry="60" fill={`url(#${id}_under)`} />
      )}

      {/* ── BACK PANE — presenter view ───────────────────────────────── */}
      <g>
        <rect x={back.x} y={back.y} width={back.w} height={back.h}
              rx={back.r} ry={back.r}
              fill="none"
              stroke={isColor ? PPT.back : monoStroke}
              strokeOpacity={isColor ? 1 : 0.55}
              strokeWidth={sw} />
        {/* header bar */}
        <path d={`M ${back.x} ${back.y + 56} L ${back.x + back.w} ${back.y + 56}`}
              stroke={isColor ? PPT.back : monoStroke}
              strokeOpacity={isColor ? 1 : 0.5}
              strokeWidth={sw * 0.7} />
        {/* tiny next-slide preview chip — bottom-right inside back pane */}
        <rect x={back.x + back.w - 165} y={back.y + back.h - 130}
              width="120" height="80" rx="10" ry="10"
              fill="none"
              stroke={isColor ? PPT.back : monoStroke}
              strokeOpacity={isColor ? 0.85 : 0.45}
              strokeWidth={sw * 0.55} />
      </g>

      {/* ── BRIDGE CABLE ─────────────────────────────────────────────── */}
      {/* outer glow stroke */}
      <path d={`M ${cableStart.x} ${cableStart.y}
                 C ${cableStart.x + 60} ${cableStart.y + 60},
                   ${cableEnd.x - 50}    ${cableEnd.y - 30},
                   ${cableEnd.x}         ${cableEnd.y}`}
            fill="none"
            stroke={isColor ? PPT.cableHi : monoStroke}
            strokeOpacity={isColor ? 0.3 : 0.25}
            strokeWidth={sw * 1.5}
            strokeLinecap="round" />
      {/* main cable */}
      <path d={`M ${cableStart.x} ${cableStart.y}
                 C ${cableStart.x + 60} ${cableStart.y + 60},
                   ${cableEnd.x - 50}    ${cableEnd.y - 30},
                   ${cableEnd.x}         ${cableEnd.y}`}
            fill="none"
            stroke={isColor ? `url(#${id}_cable)` : monoStroke}
            strokeWidth={sw * 0.9}
            strokeLinecap="round" />
      {/* connection nodes */}
      <circle cx={cableStart.x} cy={cableStart.y} r="14"
              fill={isColor ? PPT.bg0 : (tone === "mono-light" ? PPT.monoDark : PPT.monoLight)}
              stroke={isColor ? PPT.cable : monoStroke} strokeWidth={sw * 0.55} />
      <circle cx={cableEnd.x} cy={cableEnd.y} r="14"
              fill={isColor ? PPT.bg0 : (tone === "mono-light" ? PPT.monoDark : PPT.monoLight)}
              stroke={isColor ? PPT.primaryHi : monoStroke} strokeWidth={sw * 0.55} />

      {/* ── FRONT PANE — broadcast output ───────────────────────────── */}
      <g>
        <rect x={front.x} y={front.y} width={front.w} height={front.h}
              rx={front.r} ry={front.r}
              fill="none"
              stroke={isColor ? `url(#${id}_pri)` : monoStroke}
              strokeWidth={sw + 4} />
        {/* header bar — colored bar to set apart from back pane */}
        <path d={`M ${front.x + 18} ${front.y + 60}
                  L ${front.x + front.w - 18} ${front.y + 60}`}
              stroke={isColor ? `url(#${id}_pri)` : monoStroke}
              strokeOpacity={isColor ? 1 : 0.7}
              strokeWidth={sw * 0.85}
              strokeLinecap="round" />
        {/* play triangle — broadcast output indicator, centered in body */}
        {(() => {
          const cx = front.x + front.w / 2 + 8;
          const cy = front.y + 60 + (front.h - 60) / 2 + 4;
          const tw = 90, th = 110;
          const path = `M ${cx - tw / 2} ${cy - th / 2}
                        L ${cx + tw / 2} ${cy}
                        L ${cx - tw / 2} ${cy + th / 2} Z`;
          return (
            <path d={path}
                  fill={isColor ? `url(#${id}_play)` : monoStroke}
                  fillOpacity={isColor ? 1 : 0.95}
                  strokeLinejoin="round" />
          );
        })()}
      </g>

      {/* LIVE indicator — small dot on the front pane's header */}
      {showLive && (
        <g>
          <circle cx={front.x + front.w - 50} cy={front.y + 30} r="14"
                  fill={PPT.live} />
          <circle cx={front.x + front.w - 50} cy={front.y + 30} r="22"
                  fill="none" stroke={PPT.live} strokeOpacity="0.45" strokeWidth="4" />
        </g>
      )}
    </g>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// VARIANT B — Single broadcast frame (most reductive). Slide rectangle with a
// play triangle whose tip extends as a signal beam to a small node.
// ──────────────────────────────────────────────────────────────────────────
function PPTMarkBeam({ idPrefix, tone = "color" }) {
  const id = idPrefix;
  const isColor = tone === "color";
  const monoStroke = tone === "mono-light" ? PPT.monoLight : PPT.monoDark;
  const sw = 38;

  const f = { x: 200, y: 290, w: 540, h: 340, r: 36 };

  return (
    <g>
      {isColor && (
        <defs>
          <linearGradient id={`${id}_pri2`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.primaryHi} />
            <stop offset="1" stopColor={PPT.primaryLo} />
          </linearGradient>
          <radialGradient id={`${id}_under2`} cx="0.5" cy="0.5" r="0.5">
            <stop offset="0" stopColor={PPT.primaryHi} stopOpacity="0.3" />
            <stop offset="1" stopColor={PPT.primaryHi} stopOpacity="0" />
          </radialGradient>
        </defs>
      )}
      {isColor && (
        <ellipse cx={f.x + f.w / 2} cy={f.y + f.h - 20}
                 rx={f.w * 0.55} ry="55" fill={`url(#${id}_under2)`} />
      )}

      <rect x={f.x} y={f.y} width={f.w} height={f.h} rx={f.r} ry={f.r}
            fill="none"
            stroke={isColor ? `url(#${id}_pri2)` : monoStroke}
            strokeWidth={sw} />
      <line x1={f.x + 18} y1={f.y + 60} x2={f.x + f.w - 18} y2={f.y + 60}
            stroke={isColor ? `url(#${id}_pri2)` : monoStroke}
            strokeWidth={sw * 0.7} strokeLinecap="round" />

      {/* play triangle, off-center left to leave room for beam */}
      {(() => {
        const cx = f.x + f.w * 0.42;
        const cy = f.y + 60 + (f.h - 60) / 2 + 5;
        const tw = 92, th = 112;
        return (
          <path d={`M ${cx - tw / 2} ${cy - th / 2}
                    L ${cx + tw / 2} ${cy}
                    L ${cx - tw / 2} ${cy + th / 2} Z`}
                fill={isColor ? `url(#${id}_pri2)` : monoStroke} />
        );
      })()}

      {/* signal beam — emanating from triangle tip out the right edge */}
      <line x1={f.x + f.w * 0.42 + 46} y1={f.y + 60 + (f.h - 60) / 2 + 5}
            x2={f.x + f.w + 60} y2={f.y + 60 + (f.h - 60) / 2 + 5}
            stroke={isColor ? PPT.cableHi : monoStroke}
            strokeWidth={sw * 0.7} strokeLinecap="round" strokeDasharray="4 24" />

      {/* output node */}
      <circle cx={f.x + f.w + 90} cy={f.y + 60 + (f.h - 60) / 2 + 5} r="32"
              fill="none"
              stroke={isColor ? `url(#${id}_pri2)` : monoStroke} strokeWidth={sw * 0.7} />
      <circle cx={f.x + f.w + 90} cy={f.y + 60 + (f.h - 60) / 2 + 5} r="12"
              fill={isColor ? PPT.cableHi : monoStroke} />
    </g>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// VARIANT C — Stacked broadcast layers (3 thin frames receding).
// Communicates "presentation source feeding broadcast layers".
// ──────────────────────────────────────────────────────────────────────────
function PPTMarkStack({ idPrefix, tone = "color" }) {
  const id = idPrefix;
  const isColor = tone === "color";
  const monoStroke = tone === "mono-light" ? PPT.monoLight : PPT.monoDark;
  const sw = 30;

  return (
    <g>
      {isColor && (
        <defs>
          <linearGradient id={`${id}_pri3`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.primaryHi} />
            <stop offset="1" stopColor={PPT.primaryLo} />
          </linearGradient>
        </defs>
      )}

      {/* back layer — most recessed */}
      <rect x="220" y="240" width="500" height="100" rx="20" ry="20"
            fill="none"
            stroke={isColor ? PPT.back : monoStroke}
            strokeOpacity={isColor ? 0.55 : 0.35}
            strokeWidth={sw * 0.9} />
      {/* mid layer */}
      <rect x="200" y="380" width="540" height="120" rx="22" ry="22"
            fill="none"
            stroke={isColor ? PPT.back : monoStroke}
            strokeOpacity={isColor ? 0.85 : 0.6}
            strokeWidth={sw} />
      {/* front layer — bright */}
      <rect x="180" y="540" width="580" height="240" rx="32" ry="32"
            fill="none"
            stroke={isColor ? `url(#${id}_pri3)` : monoStroke}
            strokeWidth={sw + 4} />
      <line x1="198" y1="600" x2="742" y2="600"
            stroke={isColor ? `url(#${id}_pri3)` : monoStroke}
            strokeOpacity={isColor ? 1 : 0.7}
            strokeWidth={sw * 0.7} strokeLinecap="round" />
      {/* play triangle in front layer */}
      {(() => {
        const cx = 470, cy = 690, tw = 78, th = 96;
        return (
          <path d={`M ${cx - tw / 2} ${cy - th / 2}
                    L ${cx + tw / 2} ${cy}
                    L ${cx - tw / 2} ${cy + th / 2} Z`}
                fill={isColor ? `url(#${id}_pri3)` : monoStroke} />
        );
      })()}
    </g>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Tile wrapper — renders a mark inside a premium broadcast surface.
// ──────────────────────────────────────────────────────────────────────────
// Simplified mark — no cable, no preview chip. Used automatically at <= 64px,
// where fine details would muddle. Just back panel + front panel + play.
function PPTMarkSmall({ idPrefix, tone = "color" }) {
  const id = idPrefix;
  const isColor = tone === "color";
  const monoStroke = tone === "mono-light" ? PPT.monoLight : PPT.monoDark;
  const back  = { x: 170, y: 220, w: 480, h: 300, r: 40 };
  const front = { x: 350, y: 460, w: 540, h: 340, r: 44 };
  return (
    <g>
      {isColor && (
        <defs>
          <linearGradient id={`${id}_psm`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={PPT.primaryHi} />
            <stop offset="1" stopColor={PPT.primaryLo} />
          </linearGradient>
        </defs>
      )}
      {/* Back pane — solid stroke, bumped contrast for small sizes */}
      <rect x={back.x} y={back.y} width={back.w} height={back.h}
            rx={back.r} ry={back.r} fill="none"
            stroke={isColor ? PPT.back : monoStroke}
            strokeOpacity={isColor ? 1 : 0.6}
            strokeWidth="54" />
      {/* Front pane — heavier stroke at small sizes */}
      <rect x={front.x} y={front.y} width={front.w} height={front.h}
            rx={front.r} ry={front.r} fill="none"
            stroke={isColor ? `url(#${id}_psm)` : monoStroke}
            strokeWidth="60" />
      {/* Play triangle */}
      {(() => {
        const cx = front.x + front.w / 2 + 14;
        const cy = front.y + front.h / 2 + 8;
        const tw = 110, th = 130;
        return (
          <path d={`M ${cx - tw/2} ${cy - th/2}
                    L ${cx + tw/2} ${cy}
                    L ${cx - tw/2} ${cy + th/2} Z`}
                fill={isColor ? `url(#${id}_psm)` : monoStroke} />
        );
      })()}
    </g>
  );
}

function PPTTile({
  size = 512,
  variant = "primary",     // "primary" | "beam" | "stack"
  surface = "dark",        // "dark" | "transparent" | "light"
  tone,                    // override tone for the mark
  cornerRadius = 0.224,    // Apple-like 22.4%
  showLive = false,
  forceFull = false,       // bypass auto small-size simplification
}) {
  const r = size * cornerRadius;
  const reactId = React.useId().replace(/:/g, "_");
  const idPrefix = `t_${reactId}`;
  // At <= 64px the cable + preview chip muddle. Auto-swap to simplified mark.
  const useSmall = !forceFull && variant === "primary" && size <= 64;
  const Mark = useSmall ? PPTMarkSmall
             : variant === "beam" ? PPTMarkBeam
             : variant === "stack" ? PPTMarkStack
             : PPTMark;
  const markTone = tone || (surface === "light" ? "mono-dark" : "color");

  return (
    <svg width={size} height={size} viewBox="0 0 1000 1000"
         xmlns="http://www.w3.org/2000/svg"
         style={{ display: "block", borderRadius: r,
                  filter: surface === "dark"
                    ? `drop-shadow(0 ${size*0.025}px ${size*0.05}px rgba(0,0,0,0.45))`
                    : "none" }}>
      <PPTSurface idPrefix={`${idPrefix}_s`} surface={surface}
                  radius={1000 * cornerRadius}>
        <Mark idPrefix={`${idPrefix}_m`} tone={markTone} showLive={showLive} />
      </PPTSurface>
    </svg>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// GitHub social preview — 1280×640 landscape lockup
// ──────────────────────────────────────────────────────────────────────────
function PPTSocialBanner({ width = 1280, height = 640 }) {
  return (
    <svg width={width} height={height} viewBox="0 0 1280 640"
         xmlns="http://www.w3.org/2000/svg" style={{ display: "block" }}>
      <defs>
        <linearGradient id="sb_bg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#0E1620" />
          <stop offset="1" stopColor="#040810" />
        </linearGradient>
        <radialGradient id="sb_glow" cx="0.78" cy="0.4" r="0.6">
          <stop offset="0" stopColor="#0891B2" stopOpacity="0.22" />
          <stop offset="1" stopColor="#0891B2" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="sb_pri" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#7DD3FC" />
          <stop offset="1" stopColor="#0891B2" />
        </linearGradient>
        <linearGradient id="sb_div" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="rgba(125,211,252,0)" />
          <stop offset="0.5" stopColor="rgba(125,211,252,0.5)" />
          <stop offset="1" stopColor="rgba(125,211,252,0)" />
        </linearGradient>
      </defs>

      <rect width="1280" height="640" fill="url(#sb_bg)" />
      <rect width="1280" height="640" fill="url(#sb_glow)" />
      {/* top hairline rim light */}
      <rect width="1280" height="1.5" fill="rgba(255,255,255,0.10)" />

      {/* faint corner crosshairs — broadcast UI cue */}
      <g stroke="rgba(255,255,255,0.16)" strokeWidth="1.2" fill="none">
        <path d="M 32 32 L 32 64 M 32 32 L 64 32" />
        <path d="M 1248 32 L 1248 64 M 1248 32 L 1216 32" />
        <path d="M 32 608 L 32 576 M 32 608 L 64 608" />
        <path d="M 1248 608 L 1248 576 M 1248 608 L 1216 608" />
      </g>

      {/* Icon tile — left, scaled into 1000-space */}
      <g transform="translate(80 124) scale(0.392)">
        <rect width="1000" height="1000" rx="224" ry="224" fill="#0B1219" />
        <PPTSurface idPrefix="sb_surf" surface="dark" radius={224}>
          <PPTMark idPrefix="sb_mark" tone="color" />
        </PPTSurface>
      </g>

      {/* vertical divider */}
      <line x1="546" y1="180" x2="546" y2="460" stroke="url(#sb_div)" strokeWidth="1.2" />

      {/* Wordmark */}
      <text x="600" y="240"
            fontFamily="Inter, system-ui, sans-serif"
            fontWeight="700" fontSize="74"
            fill="#F2F6FA" letterSpacing="-2.4">
        PPTBridge
      </text>
      <text x="600" y="240"
            fontFamily="Inter, system-ui, sans-serif"
            fontWeight="700" fontSize="74"
            fill="url(#sb_pri)" letterSpacing="-2.4">
        <tspan x="600" y="240" opacity="0">PPTBridge </tspan>
        <tspan>SK</tspan>
      </text>
      <text x="600" y="288"
            fontFamily="'JetBrains Mono', ui-monospace, monospace"
            fontWeight="500" fontSize="18"
            fill="#7C8B9A" letterSpacing="3">
        NATIVE OBS PLUGIN  ·  macOS
      </text>

      <text x="600" y="356"
            fontFamily="Inter, system-ui, sans-serif"
            fontWeight="400" fontSize="26"
            fill="#B8C3CD">
        PowerPoint &amp; PDF as native sources for OBS Studio.
      </text>
      <text x="600" y="392"
            fontFamily="Inter, system-ui, sans-serif"
            fontWeight="400" fontSize="26"
            fill="#B8C3CD">
        Presenter view, speaker notes &amp; clicker control.
      </text>

      {/* status pill — LIVE READY */}
      <g transform="translate(600 440)">
        <rect x="0" y="0" width="178" height="44" rx="22" ry="22"
              fill="rgba(52,211,153,0.10)"
              stroke="rgba(52,211,153,0.45)" strokeWidth="1.2" />
        <circle cx="22" cy="22" r="6" fill="#34D399" />
        <text x="40" y="28"
              fontFamily="'JetBrains Mono', ui-monospace, monospace"
              fontWeight="600" fontSize="13"
              fill="#34D399" letterSpacing="2.8">LIVE READY</text>
      </g>
    </svg>
  );
}

Object.assign(window, { PPTMark, PPTMarkSmall, PPTMarkBeam, PPTMarkStack, PPTTile, PPTSurface, PPTSocialBanner, PPT });
