import type {ReactNode} from 'react';

const INK = '#26262E';
const PLATE = '#1A1A20';
const GRID = '#070709';
const LIME = '#EFF65A';
const AMBER = '#F6A41C';
const VIOLET = '#A78BFA';
const CYAN = '#22D3EE';
const SKY = '#38BDF8';

const W = 208;
const CELL = 8;

// The nine faces the model draws. One rail, one screen shape, nine readings.
export function LandingFaces() {
  return (
    <div className="lp-faces">
      <div className="lp-faces-rail">
        <FaceRing />
        <FaceLine />
        <FaceSleep />
        <FaceDays />
        <FaceFuel />
        <FaceHeat />
        <FaceBattery />
        <FaceGauge />
        <FaceZones />
      </div>
    </div>
  );
}

function gridPath(w: number, h: number, cell = CELL) {
  const parts: string[] = [];
  for (let x = cell; x < w; x += cell) parts.push(`M${x} 0V${h}`);
  for (let y = cell; y < h; y += cell) parts.push(`M0 ${y}H${w}`);
  return parts.join(' ');
}

function Grid({w, h, cell = CELL}: {w: number; h: number; cell?: number}) {
  return (
    <path d={gridPath(w, h, cell)} fill="none" stroke={GRID} strokeWidth="1.5" />
  );
}

function Face({
  kicker,
  badge,
  hero,
  unit,
  tone,
  children,
  facts,
  caption,
  meta,
}: {
  kicker: string;
  badge?: {label: string; tone: string};
  hero: string;
  unit?: string;
  tone: string;
  children: ReactNode;
  facts?: Array<[string, string, string?]>;
  caption: string;
  meta: string;
}) {
  return (
    <article className="lp-face">
      <div className="lp-face-screen">
        <div className="lp-face-k">
          <span>{kicker}</span>
          {badge ? (
            <b className="lp-face-badge" style={{background: badge.tone}}>
              {badge.label}
            </b>
          ) : null}
        </div>
        <div className="lp-face-hero">
          <strong style={{color: tone}}>{hero}</strong>
          {unit ? <span>{unit}</span> : null}
        </div>
        <div className="lp-face-art">{children}</div>
        {facts ? (
          <div className="lp-face-facts">
            {facts.map(([k, v, accent]) => (
              <div className="lp-face-fact" key={k}>
                <span>{k}</span>
                <b style={accent ? {color: accent} : undefined}>{v}</b>
              </div>
            ))}
          </div>
        ) : null}
      </div>
      <p className="lp-face-cap">{caption}</p>
      <p className="lp-face-meta">{meta}</p>
    </article>
  );
}

// 01 · TRAINING LOAD — 21 cells around the wrist, 14 of them spent.
function FaceRing() {
  const total = 21;
  const done = 14;
  const size = 168;
  const c = size / 2;
  const r = 66;
  const cells = Array.from({length: total}, (_, i) => {
    const a = (-90 + (i * 360) / total) * (Math.PI / 180);
    return {
      x: c + r * Math.cos(a) - 6,
      y: c + r * Math.sin(a) - 6,
      on: i < done,
    };
  });
  return (
    <Face
      kicker="TRAINING LOAD"
      hero="14"
      unit="/ 21"
      tone={LIME}
      facts={[
        ['TO GO', '7', LIME],
        ['TOP', '12:10'],
      ]}
      caption="14 of 21. Midday took most of it."
      meta="load.today · 3 SEGMENTS"
    >
      <svg viewBox={`0 0 ${size} ${size}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        {cells.map((cell, i) => (
          <rect
            key={i}
            x={cell.x}
            y={cell.y}
            width="12"
            height="12"
            fill={cell.on ? LIME : INK}
          />
        ))}
        <text
          x={c}
          y={c + 6}
          fontFamily="Doto"
          fontWeight="800"
          fontSize="34"
          textAnchor="middle"
          fill={LIME}
        >
          67%
        </text>
        <text
          x={c}
          y={c + 26}
          fontFamily="Doto"
          fontWeight="600"
          fontSize="10"
          letterSpacing="2"
          textAnchor="middle"
          fill="#ffffff66"
        >
          OF GOAL
        </text>
      </svg>
    </Face>
  );
}

// 02 · HEART — the day as 24 columns, one per hour.
function FaceLine() {
  const hours = [
    54, 51, 49, 50, 52, 57, 72, 68, 63, 79, 74, 66, 92, 71, 141, 108, 77, 84, 69,
    73, 64, 88, 61, 56,
  ];
  const h = 96;
  const max = 150;
  const rest = 52;
  return (
    <Face
      kicker="HEART"
      badge={{label: 'MOVE', tone: AMBER}}
      hero="74"
      unit="BPM"
      tone={AMBER}
      facts={[
        ['REST', '52'],
        ['PEAK', '141', AMBER],
      ]}
      caption="Peak 141 at 14:10. Then back to rest."
      meta="heart.today · 24 HOURS"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        <rect x="0" y="0" width={W} height={h} fill={INK} />
        {hours.map((v, i) => {
          const bar = Math.max(CELL, Math.round((v / max) * h / CELL) * CELL);
          return (
            <rect
              key={i}
              x={8 + i * CELL}
              y={h - bar}
              width={CELL}
              height={bar}
              fill={v > 120 ? AMBER : '#F6A41CA6'}
            />
          );
        })}
        <path
          d={`M0 ${h - Math.round((rest / max) * h)}H${W}`}
          fill="none"
          stroke="#FFFFFF"
          strokeWidth="1.5"
          strokeDasharray="6 6"
        />
        <Grid w={W} h={h} />
      </svg>
    </Face>
  );
}

// 03 · SLEEP — four bands, one row each, midnight to morning.
function FaceSleep() {
  const rows: Array<[string, string, string]> = [
    ['WAKE', '#FFFFFFBF', '0000000010000000000100000'],
    ['REM', '#A78BFAA6', '0011100011110000111100000'],
    ['LIGHT', '#A78BFAD9', '1100011100001111000011111'],
    ['DEEP', VIOLET, '0000100000110000000100000'],
  ];
  const rowH = 18;
  const h = rows.length * rowH;
  return (
    <Face
      kicker="SLEEP · 23:42 → 07:20"
      hero="7H38"
      tone={VIOLET}
      facts={[
        ['DEEP', '1H48', VIOLET],
        ['REM', '1H12'],
        ['WAKE', '4'],
      ]}
      caption="Three deep blocks. Two before midnight."
      meta="sleep.last · SCORE 82"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        <rect x="0" y="0" width={W} height={h} fill={PLATE} />
        {rows.map(([label, colour, mask], row) =>
          mask.split('').map((on, i) =>
            on === '1' ? (
              <rect
                key={`${label}-${i}`}
                x={16 + i * CELL}
                y={row * rowH + 3}
                width={CELL}
                height="12"
                fill={colour}
              />
            ) : null,
          ),
        )}
        {rows.map(([label], row) => (
          <text
            key={label}
            x="0"
            y={row * rowH + 13}
            fontFamily="Doto"
            fontSize="9"
            fill="#FFFFFF66"
          >
            {label[0]}
          </text>
        ))}
      </svg>
    </Face>
  );
}

// 04 · STEPS — seven days, Thursday carries them.
function FaceDays() {
  const days = [7100, 9800, 4300, 12070, 7600, 8800, 3600];
  const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  const h = 104;
  const max = 13000;
  const avg = 7610;
  const bw = 24;
  return (
    <Face
      kicker="STEPS · 7 DAYS"
      hero="7 610"
      unit="AVG"
      tone={LIME}
      facts={[
        ['TOTAL', '53 270'],
        ['HIT', '3/7'],
        ['Δ WK', '+8%', LIME],
      ]}
      caption="Thursday 12,070 carries the week."
      meta="steps.week · GOAL 8 000"
    >
      <svg viewBox={`0 0 ${W} ${h + 14}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        <rect x="0" y="0" width={W} height={h} fill={INK} />
        {days.map((v, i) => {
          const bar = Math.max(CELL, Math.round((v / max) * h / CELL) * CELL);
          const peak = v === Math.max(...days);
          return (
            <rect
              key={i}
              x={8 + i * (bw + 4)}
              y={h - bar}
              width={bw}
              height={bar}
              fill={peak ? LIME : '#EFF65A8C'}
            />
          );
        })}
        <path
          d={`M0 ${h - Math.round((avg / max) * h)}H${W}`}
          fill="none"
          stroke="#FFFFFF"
          strokeWidth="1.5"
          strokeDasharray="6 6"
        />
        <Grid w={W} h={h} />
        {names.map((n, i) => (
          <text
            key={i}
            x={8 + i * (bw + 4) + bw / 2}
            y={h + 12}
            fontFamily="Doto"
            fontSize="9"
            textAnchor="middle"
            fill={i === 3 ? LIME : '#FFFFFF66'}
          >
            {n}
          </text>
        ))}
      </svg>
    </Face>
  );
}

// 05 · MACROS — three bars, one short.
function FaceFuel() {
  const bars: Array<[string, number, number, string]> = [
    ['PRO', 62, 110, VIOLET],
    ['CHO', 184, 210, SKY],
    ['FAT', 44, 62, CYAN],
  ];
  const rowH = 34;
  const h = bars.length * rowH;
  return (
    <Face
      kicker="MACROS · TODAY"
      hero="-48"
      unit="G PRO"
      tone={CYAN}
      facts={[
        ['IN', '1 480'],
        ['TARGET', '1 900'],
        ['LEFT', '420', CYAN],
      ]}
      caption="Carbs nearly full. Protein is short."
      meta="fuel.today · 3 MEALS"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        {bars.map(([label, value, target, colour], i) => {
          const full = Math.round(((value / target) * W) / CELL) * CELL;
          return (
            <g key={label}>
              <text
                x="0"
                y={i * rowH + 8}
                fontFamily="Doto"
                fontSize="9"
                letterSpacing="1"
                fill="#FFFFFF66"
              >
                {`${label} ${value}/${target} G`}
              </text>
              <rect x="0" y={i * rowH + 14} width={W} height="16" fill={INK} />
              <rect x="0" y={i * rowH + 14} width={full} height="16" fill={colour} />
            </g>
          );
        })}
      </svg>
    </Face>
  );
}

// 06 · HEART, WEEK × HOUR — where the week actually burned.
function FaceHeat() {
  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  // twelve two-hour buckets per day, 0 (cold) to 4 (hot)
  const heat = [
    '000011223321',
    '000012234421',
    '000011222210',
    '000012344431',
    '000011233321',
    '001122333221',
    '000011111000',
  ];
  const cell = 14;
  const gap = 2;
  const h = days.length * (cell + gap);
  const shade = ['#1A1A20', '#F6A41C33', '#F6A41C66', '#F6A41CB3', AMBER];
  return (
    <Face
      kicker="HEART · WEEK × HOUR"
      hero="THU"
      unit="18–20"
      tone={AMBER}
      facts={[
        ['HOT', 'THU 19:00', AMBER],
        ['COLD', 'SUN'],
      ]}
      caption="Weeknights light up after six. Sunday stays dark."
      meta="heart.week · 84 CELLS"
    >
      <svg viewBox={`0 0 ${W} ${h + 12}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        {heat.map((row, y) =>
          row.split('').map((v, x) => (
            <rect
              key={`${y}-${x}`}
              x={14 + x * (cell + gap)}
              y={y * (cell + gap)}
              width={cell}
              height={cell}
              fill={shade[Number(v)]}
            />
          )),
        )}
        {days.map((d, y) => (
          <text
            key={y}
            x="0"
            y={y * (cell + gap) + 11}
            fontFamily="Doto"
            fontSize="9"
            fill="#FFFFFF66"
          >
            {d}
          </text>
        ))}
        <text x="14" y={h + 10} fontFamily="Doto" fontSize="9" fill="#FFFFFF66">
          00
        </text>
        <text x={W - 20} y={h + 10} fontFamily="Doto" fontSize="9" fill="#FFFFFF66">
          24
        </text>
      </svg>
    </Face>
  );
}

// 07 · BODY BATTERY — the fallback face, the one it draws when nothing else is louder.
function FaceBattery() {
  const curve = [
    91, 92, 92, 91, 90, 88, 86, 84, 83, 82, 80, 78, 74, 70, 68, 72, 76, 80, 84,
    86, 86, 86, 86, 86,
  ];
  const h = 96;
  return (
    <Face
      kicker="BODY BATTERY"
      badge={{label: 'NOW', tone: LIME}}
      hero="86"
      unit="/ 100"
      tone={LIME}
      facts={[
        ['WOKE', '91'],
        ['LOW', '68'],
      ]}
      caption="Now 86. Woke at 91."
      meta="battery.now · FALLBACK FACE"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        <rect x="0" y="0" width={W} height={h} fill={INK} />
        {curve.map((v, i) => {
          const bar = Math.max(CELL, Math.round((v / 100) * h / CELL) * CELL);
          const last = i === curve.length - 1;
          return (
            <g key={i}>
              <rect
                x={8 + i * CELL}
                y={h - bar}
                width={CELL}
                height={bar}
                fill="#EFF65A40"
              />
              <rect
                x={8 + i * CELL}
                y={h - bar}
                width={CELL}
                height={CELL}
                fill={last ? '#FFFFFF' : LIME}
              />
            </g>
          );
        })}
        <Grid w={W} h={h} />
      </svg>
    </Face>
  );
}

// 08 · STRESS — twenty-four cells, three zones, one caret.
function FaceGauge() {
  const cells = 24;
  const now = 7;
  const h = 56;
  const zone = (i: number) => (i < 8 ? '#EFF65A' : i < 16 ? '#F6A41C' : '#F43F5E');
  return (
    <Face
      kicker="STRESS"
      badge={{label: 'REST', tone: LIME}}
      hero="32"
      unit="MID"
      tone={LIME}
      facts={[
        ['DAY AVG', '38'],
        ['PEAK', '11:20'],
      ]}
      caption="Still in REST. Sliding down."
      meta="stress.now · THREE ZONES"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        {Array.from({length: cells}, (_, i) => (
          <rect
            key={i}
            x={8 + i * CELL}
            y="8"
            width={CELL - 1}
            height="24"
            fill={i <= now ? zone(i) : `${zone(i)}2E`}
          />
        ))}
        <rect x={8 + now * CELL} y="36" width={CELL - 1} height="6" fill="#FFFFFF" />
        <text x="8" y="54" fontFamily="Doto" fontSize="9" fill="#FFFFFF66">
          REST
        </text>
        <text x="82" y="54" fontFamily="Doto" fontSize="9" fill="#FFFFFF66">
          MID
        </text>
        <text x={W - 30} y="54" fontFamily="Doto" fontSize="9" fill="#FFFFFF66">
          HIGH
        </text>
      </svg>
    </Face>
  );
}

// 09 · ZONES — the session, split five ways.
function FaceZones() {
  const zones: Array<[string, number, string]> = [
    ['Z1', 14, '#ffffff40'],
    ['Z2', 34, '#ffffff73'],
    ['Z3', 22, LIME],
    ['Z4', 9, AMBER],
    ['Z5', 3, '#F43F5E'],
  ];
  const rowH = 20;
  const h = zones.length * rowH;
  const max = 40;
  return (
    <Face
      kicker="ZONES · 82 MIN"
      hero="Z2"
      unit="34 MIN"
      tone={LIME}
      facts={[
        ['PEAK', '168'],
        ['AVG', '131'],
      ]}
      caption="14 · 34 · 22 · 9 · 3 MIN"
      meta="zones.today · PEAK 168"
    >
      <svg viewBox={`0 0 ${W} ${h}`} width="100%" aria-hidden="true" shapeRendering="crispEdges">
        {zones.map(([label, mins, colour], i) => {
          const full = Math.round(((mins / max) * (W - 26)) / CELL) * CELL;
          return (
            <g key={label}>
              <rect x="26" y={i * rowH} width={W - 26} height="14" fill={INK} />
              <rect x="26" y={i * rowH} width={full} height="14" fill={colour} />
              <text
                x="0"
                y={i * rowH + 11}
                fontFamily="Doto"
                fontSize="9"
                fill="#FFFFFF8C"
              >
                {label}
              </text>
              <text
                x={W - 2}
                y={i * rowH + 11}
                fontFamily="Doto"
                fontSize="9"
                textAnchor="end"
                fill="#FFFFFF66"
              >
                {mins}
              </text>
            </g>
          );
        })}
      </svg>
    </Face>
  );
}
