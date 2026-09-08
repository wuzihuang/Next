export function LandingFaces() {
  return (
    <div className="lp-faces">
      <div className="lp-faces-row">
        <FaceRing />
        <FaceLine />
        <FaceSleep />
      </div>
      <div className="lp-faces-row">
        <FaceDays />
        <FaceFuel />
        <FaceHeat />
      </div>
      <div className="lp-faces-row">
        <FaceBattery />
        <FaceGauge />
        <FaceZones />
      </div>
    </div>
  );
}

function FaceRing() {
  return (
    <article className="lp-face">
      <div className="lp-face-k">TRAINING LOAD · TODAY</div>
      <div style={{alignItems: 'center', display: 'flex', gap: 20, paddingTop: 16}}>
        <svg width="152" height="152" viewBox="0 0 152 152" aria-hidden="true">
          <rect x="19.8" y="99" width="12" height="12" fill="#26262E" />
          <rect x="13.5" y="82.9" width="12" height="12" fill="#26262E" />
          <rect x="12.2" y="65.7" width="12" height="12" fill="#26262E" />
          <rect x="16" y="48.8" width="12" height="12" fill="#26262E" />
          <rect x="24.7" y="33.8" width="12" height="12" fill="#26262E" />
          <rect x="37.3" y="22.1" width="12" height="12" fill="#26262E" />
          <rect x="52.9" y="14.6" width="12" height="12" fill="#26262E" />
          <rect x="70" y="12" width="12" height="12" fill="#EFF65A" />
          <rect x="87.1" y="14.6" width="12" height="12" fill="#EFF65A" />
          <rect x="102.7" y="22.1" width="12" height="12" fill="#EFF65A" />
          <rect x="115.3" y="33.8" width="12" height="12" fill="#EFF65A" />
          <rect x="124" y="48.8" width="12" height="12" fill="#EFF65A" />
          <rect x="127.8" y="65.7" width="12" height="12" fill="#EFF65A" />
          <rect x="126.5" y="82.9" width="12" height="12" fill="#EFF65A" />
          <rect x="120.2" y="99" width="12" height="12" fill="#EFF65A" />
          <rect x="109.5" y="112.5" width="12" height="12" fill="#EFF65A" />
          <rect x="95.2" y="122.3" width="12" height="12" fill="#EFF65A" />
          <rect x="78.6" y="127.4" width="12" height="12" fill="#EFF65A" />
          <rect x="61.4" y="127.4" width="12" height="12" fill="#EFF65A" />
          <rect x="44.8" y="122.3" width="12" height="12" fill="#EFF65A" />
          <rect x="30.5" y="112.5" width="12" height="12" fill="#EFF65A" />
          <text x="76" y="90" fontFamily="Doto" fontWeight="800" fontSize="54" textAnchor="middle" fill="#EFF65A">
            14
          </text>
        </svg>
        <div style={{display: 'flex', flex: 1, flexDirection: 'column', gap: 2}}>
          <div style={{color: '#fff', fontFamily: 'Doto, monospace', fontSize: 34, fontWeight: 800, lineHeight: '36px'}}>
            7
          </div>
          <div style={{color: '#ffffff66', fontFamily: 'Doto, monospace', fontSize: 11, letterSpacing: '0.16em', paddingBottom: 10}}>
            TO GO
          </div>
          <div style={{background: '#ffffff1f', height: 2}} />
          <div style={{display: 'flex', justifyContent: 'space-between', paddingTop: 10}}>
            <span style={{color: '#ffffff66', fontFamily: 'Doto, monospace', fontSize: 11, letterSpacing: '0.14em'}}>
              GOAL
            </span>
            <span style={{color: '#ffffffd9', fontFamily: 'Doto, monospace', fontSize: 14, fontWeight: 700}}>
              21
            </span>
          </div>
          <div style={{display: 'flex', justifyContent: 'space-between', paddingTop: 6}}>
            <span style={{color: '#ffffff66', fontFamily: 'Doto, monospace', fontSize: 11, letterSpacing: '0.14em'}}>
              PCT
            </span>
            <span style={{color: '#ffffffd9', fontFamily: 'Doto, monospace', fontSize: 14, fontWeight: 700}}>
              67%
            </span>
          </div>
        </div>
      </div>
      <p className="lp-face-cap">14 of 21. Midday took most of it.</p>
      <p className="lp-face-meta">3 SEGMENTS · TOP 12:10 · 8.4</p>
    </article>
  );
}

function FaceLine() {
  return (
    <article className="lp-face">
      <div style={{alignItems: 'center', display: 'flex'}}>
        <div className="lp-face-k" style={{flex: 1}}>
          HEART · TODAY
        </div>
        <div style={{background: '#F6A41C', padding: '3px 7px'}}>
          <span style={{color: '#070709', fontFamily: 'Doto, monospace', fontSize: 10, fontWeight: 600, letterSpacing: '0.16em'}}>
            MOVE
          </span>
        </div>
      </div>
      <div style={{alignItems: 'baseline', display: 'flex', gap: 10, paddingTop: 12}}>
        <strong style={{color: '#F6A41C', fontFamily: 'Doto, monospace', fontSize: 62, fontWeight: 800, lineHeight: '56px'}}>
          74
        </strong>
        <span style={{color: '#ffffff8c', fontFamily: 'Doto, monospace', fontSize: 14, fontWeight: 600, letterSpacing: '0.2em'}}>
          BPM
        </span>
      </div>
      <div style={{paddingTop: 16}}>
        <svg width="100%" height="136" viewBox="0 0 384 152" aria-hidden="true">
          <rect x="0" y="0" width="384" height="136" fill="#26262E" />
          <rect x="0" y="128" width="16" height="8" fill="#F6A41C" />
          <rect x="16" y="128" width="16" height="8" fill="#F6A41C" />
          <rect x="32" y="128" width="16" height="8" fill="#F6A41C" />
          <rect x="48" y="128" width="16" height="8" fill="#F6A41C" />
          <rect x="64" y="128" width="16" height="8" fill="#F6A41C" />
          <rect x="80" y="120" width="16" height="16" fill="#F6A41C" />
          <rect x="96" y="120" width="16" height="16" fill="#F6A41C" />
          <rect x="112" y="88" width="16" height="48" fill="#F6A41C" />
          <rect x="128" y="104" width="16" height="32" fill="#F6A41C" />
          <rect x="144" y="104" width="16" height="32" fill="#F6A41C" />
          <rect x="160" y="96" width="16" height="40" fill="#F6A41C" />
          <rect x="176" y="72" width="16" height="64" fill="#F6A41C" />
          <rect x="192" y="16" width="16" height="120" fill="#F6A41C" />
          <rect x="208" y="40" width="16" height="96" fill="#F6A41C" />
          <rect x="224" y="56" width="16" height="80" fill="#F6A41C" />
          <rect x="240" y="72" width="16" height="64" fill="#F6A41C" />
          <rect x="256" y="88" width="16" height="48" fill="#F6A41C" />
          <rect x="272" y="96" width="16" height="40" fill="#F6A41C" />
          <rect x="288" y="96" width="16" height="40" fill="#F6A41C" />
          <rect x="304" y="104" width="16" height="32" fill="#F6A41C" />
          <rect x="320" y="96" width="16" height="40" fill="#F6A41C" />
          <rect x="336" y="96" width="16" height="40" fill="#F6A41C" />
          <rect x="352" y="104" width="16" height="32" fill="#F6A41C" />
          <rect x="368" y="104" width="16" height="32" fill="#F6A41C" />
          <path d="M0 72H384" fill="none" stroke="#FFFFFF8C" strokeWidth="2" strokeDasharray="8 8" />
          <path d="M16 0V136 M32 0V136 M48 0V136 M64 0V136 M80 0V136 M96 0V136 M112 0V136 M128 0V136 M144 0V136 M160 0V136 M176 0V136 M192 0V136 M208 0V136 M224 0V136 M240 0V136 M256 0V136 M272 0V136 M288 0V136 M304 0V136 M320 0V136 M336 0V136 M352 0V136 M368 0V136 M0 16H384 M0 32H384 M0 48H384 M0 64H384 M0 80H384 M0 96H384 M0 112H384 M0 128H384" fill="none" stroke="#070709" strokeWidth="2.5" />
        </svg>
      </div>
      <p className="lp-face-cap">Peak 141 at 14:10. Then back to rest.</p>
      <div style={{borderTop: '2px solid #ffffff14', display: 'flex', paddingTop: 12}}>
        {[
          ['MIN', '52', '#ffffffd9'],
          ['MEAN', '74', '#ffffffd9'],
          ['MAX', '141', '#F6A41C'],
          ['Δ 7D', '+2', '#EFF65A'],
        ].map(([k, v, c]) => (
          <div key={k} style={{display: 'flex', flex: 1, flexDirection: 'column', gap: 4}}>
            <span style={{color: '#ffffff52', fontFamily: 'Doto, monospace', fontSize: 10, letterSpacing: '0.16em'}}>
              {k}
            </span>
            <span style={{color: c, fontFamily: 'Doto, monospace', fontSize: 16, fontWeight: 700}}>
              {v}
            </span>
          </div>
        ))}
      </div>
    </article>
  );
}

function FaceSleep() {
  return (
    <article className="lp-face">
      <div className="lp-face-k">SLEEP · 23:42 → 07:20</div>
      <div style={{paddingTop: 12}}>
        <strong style={{color: '#A78BFA', fontFamily: 'Doto, monospace', fontSize: 62, fontWeight: 800, lineHeight: '56px'}}>
          7H38
        </strong>
      </div>
      <div style={{paddingTop: 16}}>
        <svg width="100%" height="124" viewBox="0 0 384 128" aria-hidden="true">
          <rect x="0" y="0" width="384" height="88" fill="#1A1A20" />
          <rect x="0" y="0" width="16" height="16" fill="#FFFFFFBF" />
          <rect x="96" y="0" width="16" height="16" fill="#FFFFFFBF" />
          <rect x="272" y="0" width="16" height="16" fill="#FFFFFFBF" />
          <rect x="368" y="0" width="16" height="16" fill="#FFFFFFBF" />
          <rect x="16" y="24" width="48" height="16" fill="#A78BFAA6" />
          <rect x="80" y="24" width="16" height="16" fill="#A78BFAA6" />
          <rect x="112" y="24" width="48" height="16" fill="#A78BFAA6" />
          <rect x="176" y="24" width="48" height="16" fill="#A78BFAA6" />
          <rect x="256" y="24" width="16" height="16" fill="#A78BFAA6" />
          <rect x="288" y="24" width="48" height="16" fill="#A78BFAA6" />
          <rect x="64" y="48" width="16" height="16" fill="#A78BFA" />
          <rect x="160" y="48" width="16" height="16" fill="#A78BFA" />
          <rect x="336" y="48" width="16" height="16" fill="#A78BFA" />
          <rect x="224" y="72" width="32" height="16" fill="#A78BFAD9" />
          <rect x="352" y="72" width="16" height="16" fill="#A78BFAD9" />
          <path d="M16 0V88 M32 0V88 M48 0V88 M64 0V88 M80 0V88 M96 0V88 M112 0V88 M128 0V88 M144 0V88 M160 0V88 M176 0V88 M192 0V88 M208 0V88 M224 0V88 M240 0V88 M256 0V88 M272 0V88 M288 0V88 M304 0V88 M320 0V88 M336 0V88 M352 0V88 M368 0V88 M0 16H384 M0 32H384 M0 48H384 M0 64H384 M0 80H384" fill="none" stroke="#070709" strokeWidth="2.5" />
        </svg>
      </div>
      <p className="lp-face-cap">Three deep blocks. Two before midnight.</p>
      <div style={{borderTop: '2px solid #ffffff14', display: 'flex', paddingTop: 12}}>
        {[
          ['DEEP', '1H48', '#A78BFA'],
          ['REM', '1H12', '#ffffffd9'],
          ['WAKE', '4', '#ffffffd9'],
        ].map(([k, v, c]) => (
          <div key={k} style={{display: 'flex', flex: 1, flexDirection: 'column', gap: 4}}>
            <span style={{color: '#ffffff52', fontFamily: 'Doto, monospace', fontSize: 10, letterSpacing: '0.16em'}}>
              {k}
            </span>
            <span style={{color: c, fontFamily: 'Doto, monospace', fontSize: 16, fontWeight: 700}}>
              {v}
            </span>
          </div>
        ))}
      </div>
    </article>
  );
}

function FaceDays() {
  return (
    <article className="lp-face">
      <div className="lp-face-k">STEPS · 7 DAYS</div>
      <div style={{alignItems: 'baseline', display: 'flex', gap: 10, paddingTop: 12}}>
        <strong style={{color: '#EFF65A', fontFamily: 'Doto, monospace', fontSize: 62, fontWeight: 800, lineHeight: '56px'}}>
          7610
        </strong>
        <span style={{color: '#ffffff8c', fontFamily: 'Doto, monospace', fontSize: 13, fontWeight: 600, letterSpacing: '0.2em'}}>
          AVG
        </span>
      </div>
      <div style={{paddingTop: 16}}>
        <svg width="100%" height="136" viewBox="0 0 384 152" aria-hidden="true">
          <rect x="0" y="0" width="384" height="136" fill="#26262E" />
          <rect x="0" y="72" width="48" height="64" fill="#EFF65A8C" />
          <rect x="56" y="40" width="48" height="96" fill="#EFF65A8C" />
          <rect x="112" y="96" width="48" height="40" fill="#EFF65A8C" />
          <rect x="168" y="16" width="48" height="120" fill="#EFF65A" />
          <rect x="224" y="64" width="48" height="72" fill="#EFF65A8C" />
          <rect x="280" y="48" width="48" height="88" fill="#EFF65A8C" />
          <rect x="336" y="96" width="48" height="40" fill="#EFF65A8C" />
          <path d="M0 56H384" fill="none" stroke="#FFFFFF" strokeWidth="2" strokeDasharray="8 8" />
          <path d="M16 0V136 M32 0V136 M48 0V136 M64 0V136 M80 0V136 M96 0V136 M112 0V136 M128 0V136 M144 0V136 M160 0V136 M176 0V136 M192 0V136 M208 0V136 M224 0V136 M240 0V136 M256 0V136 M272 0V136 M288 0V136 M304 0V136 M320 0V136 M336 0V136 M352 0V136 M368 0V136 M0 16H384 M0 32H384 M0 48H384 M0 64H384 M0 80H384 M0 96H384 M0 112H384 M0 128H384" fill="none" stroke="#070709" strokeWidth="2.5" />
          <text x="12" y="150" fontFamily="Doto" fontSize="10" fill="#FFFFFF66">
            MON
          </text>
          <text x="180" y="150" fontFamily="Doto" fontSize="10" fill="#EFF65A">
            THU
          </text>
          <text x="348" y="150" fontFamily="Doto" fontSize="10" fill="#FFFFFF66">
            SUN
          </text>
        </svg>
      </div>
      <p className="lp-face-cap">Thursday 12,070 carries the week.</p>
      <div className="lp-face-facts">
        <FaceFact k="TOTAL" v="53 270" />
        <FaceFact k="HIT" v="3/7" />
        <FaceFact k="Δ WK" v="+8%" accent="#EFF65A" />
      </div>
    </article>
  );
}

function FaceFuel() {
  return (
    <article className="lp-face">
      <div className="lp-face-k">MACROS · TODAY</div>
      <div style={{alignItems: 'baseline', display: 'flex', gap: 10, paddingTop: 12}}>
        <strong style={{color: '#22D3EE', fontFamily: 'Doto, monospace', fontSize: 62, fontWeight: 800, lineHeight: '56px'}}>
          -48
        </strong>
        <span style={{color: '#ffffff8c', fontFamily: 'Doto, monospace', fontSize: 13, fontWeight: 600, letterSpacing: '0.2em'}}>
          G PRO
        </span>
      </div>
      <div style={{paddingTop: 18}}>
        <svg width="100%" height="120" viewBox="0 0 384 132" aria-hidden="true">
          <rect x="0" y="0" width="384" height="24" fill="#26262E" />
          <rect x="0" y="40" width="384" height="24" fill="#26262E" />
          <rect x="0" y="80" width="384" height="24" fill="#26262E" />
          <rect x="0" y="0" width="208" height="24" fill="#A78BFA" />
          <rect x="0" y="40" width="336" height="24" fill="#38BDF8" />
          <rect x="0" y="80" width="272" height="24" fill="#22D3EE" />
          <path d="M16 0V24 M32 0V24 M48 0V24 M64 0V24 M80 0V24 M96 0V24 M112 0V24 M128 0V24 M144 0V24 M160 0V24 M176 0V24 M192 0V24 M208 0V24 M224 0V24 M240 0V24 M256 0V24 M272 0V24 M288 0V24 M304 0V24 M320 0V24 M336 0V24 M352 0V24 M368 0V24 M16 40V64 M32 40V64 M48 40V64 M64 40V64 M80 40V64 M96 40V64 M112 40V64 M128 40V64 M144 40V64 M160 40V64 M176 40V64 M192 40V64 M208 40V64 M224 40V64 M240 40V64 M256 40V64 M272 40V64 M288 40V64 M304 40V64 M320 40V64 M336 40V64 M352 40V64 M368 40V64 M16 80V104 M32 80V104 M48 80V104 M64 80V104 M80 80V104 M96 80V104 M112 80V104 M128 80V104 M144 80V104 M160 80V104 M176 80V104 M192 80V104 M208 80V104 M224 80V104 M240 80V104 M256 80V104 M272 80V104 M288 80V104 M304 80V104 M320 80V104 M336 80V104 M352 80V104 M368 80V104 M0 8H384 M0 16H384 M0 48H384 M0 56H384 M0 88H384 M0 96H384" fill="none" stroke="#070709" strokeWidth="2.5" />
          <text x="0" y="126" fontFamily="Doto" fontSize="10" fill="#FFFFFF66">
            PRO 62/110 · CHO 184/210 · FAT 44/62 G
          </text>
        </svg>
      </div>
      <p className="lp-face-cap">Carbs nearly full. Protein is short.</p>
      <div className="lp-face-facts">
        <FaceFact k="IN" v="1 480" />
        <FaceFact k="TARGET" v="1 900" />
        <FaceFact k="LEFT" v="420" accent="#22D3EE" />
      </div>
    </article>
  );
}

function FaceHeat() {
  return (
    <article className="lp-face">
      <div className="lp-face-k">HEART · WEEK × HOUR</div>
      <div style={{paddingTop: 10}}>
        <strong style={{color: '#F6A41C', fontFamily: 'Doto, monospace', fontSize: 44, fontWeight: 800, lineHeight: '48px'}}>
          THU 18-20
        </strong>
      </div>
      <div style={{paddingTop: 14}}>
        <svg width="100%" height="128" viewBox="0 0 384 134" aria-hidden="true">
          <rect x="0" y="0" width="384" height="112" fill="#26262E" />
          <rect x="64" y="0" width="32" height="16" fill="#F6A41C70" />
          <rect x="96" y="0" width="32" height="16" fill="#F6A41C9E" />
          <rect x="128" y="0" width="32" height="16" fill="#F6A41CCF" />
          <rect x="160" y="0" width="32" height="16" fill="#F6A41C9E" />
          <rect x="192" y="0" width="32" height="16" fill="#F6A41C70" />
          <rect x="224" y="0" width="32" height="16" fill="#F6A41C70" />
          <rect x="256" y="0" width="32" height="16" fill="#F6A41C9E" />
          <rect x="288" y="0" width="32" height="16" fill="#F6A41CCF" />
          <rect x="320" y="0" width="32" height="16" fill="#F6A41C9E" />
          <rect x="352" y="0" width="32" height="16" fill="#F6A41C70" />
          <rect x="32" y="16" width="32" height="16" fill="#F6A41C70" />
          <rect x="64" y="16" width="32" height="16" fill="#F6A41C70" />
          <rect x="96" y="16" width="32" height="16" fill="#F6A41C9E" />
          <rect x="128" y="16" width="32" height="16" fill="#F6A41C9E" />
          <rect x="160" y="16" width="32" height="16" fill="#F6A41C70" />
          <rect x="192" y="16" width="32" height="16" fill="#F6A41C70" />
          <rect x="224" y="16" width="32" height="16" fill="#F6A41C9E" />
          <rect x="256" y="16" width="32" height="16" fill="#F6A41CCF" />
          <rect x="288" y="16" width="32" height="16" fill="#F6A41C" />
          <rect x="320" y="16" width="32" height="16" fill="#F6A41C9E" />
          <rect x="352" y="16" width="32" height="16" fill="#F6A41C70" />
          <rect x="64" y="32" width="32" height="16" fill="#F6A41C70" />
          <rect x="96" y="32" width="32" height="16" fill="#F6A41C70" />
          <rect x="128" y="32" width="32" height="16" fill="#F6A41C9E" />
          <rect x="160" y="32" width="32" height="16" fill="#F6A41C9E" />
          <rect x="192" y="32" width="32" height="16" fill="#F6A41C70" />
          <rect x="224" y="32" width="32" height="16" fill="#F6A41C70" />
          <rect x="256" y="32" width="32" height="16" fill="#F6A41C9E" />
          <rect x="288" y="32" width="32" height="16" fill="#F6A41C9E" />
          <rect x="320" y="32" width="32" height="16" fill="#F6A41C70" />
          <rect x="0" y="48" width="32" height="16" fill="#F6A41C70" />
          <rect x="32" y="48" width="32" height="16" fill="#F6A41C70" />
          <rect x="64" y="48" width="32" height="16" fill="#F6A41C9E" />
          <rect x="96" y="48" width="32" height="16" fill="#F6A41CCF" />
          <rect x="128" y="48" width="32" height="16" fill="#F6A41C" />
          <rect x="160" y="48" width="32" height="16" fill="#F6A41CCF" />
          <rect x="192" y="48" width="32" height="16" fill="#F6A41C9E" />
          <rect x="224" y="48" width="32" height="16" fill="#F6A41C9E" />
          <rect x="256" y="48" width="32" height="16" fill="#F6A41CCF" />
          <rect x="288" y="48" width="32" height="16" fill="#F6A41CCF" />
          <rect x="320" y="48" width="32" height="16" fill="#F6A41C9E" />
          <rect x="352" y="48" width="32" height="16" fill="#F6A41C70" />
          <rect x="64" y="64" width="32" height="16" fill="#F6A41C70" />
          <rect x="96" y="64" width="32" height="16" fill="#F6A41C9E" />
          <rect x="128" y="64" width="32" height="16" fill="#F6A41C9E" />
          <rect x="160" y="64" width="32" height="16" fill="#F6A41C70" />
          <rect x="192" y="64" width="32" height="16" fill="#F6A41C70" />
          <rect x="224" y="64" width="32" height="16" fill="#F6A41C70" />
          <rect x="256" y="64" width="32" height="16" fill="#F6A41C9E" />
          <rect x="288" y="64" width="32" height="16" fill="#F6A41C9E" />
          <rect x="320" y="64" width="32" height="16" fill="#F6A41C70" />
          <rect x="32" y="80" width="32" height="16" fill="#F6A41C70" />
          <rect x="64" y="80" width="32" height="16" fill="#F6A41C9E" />
          <rect x="96" y="80" width="32" height="16" fill="#F6A41CCF" />
          <rect x="128" y="80" width="32" height="16" fill="#F6A41CCF" />
          <rect x="160" y="80" width="32" height="16" fill="#F6A41C9E" />
          <rect x="192" y="80" width="32" height="16" fill="#F6A41C9E" />
          <rect x="224" y="80" width="32" height="16" fill="#F6A41CCF" />
          <rect x="256" y="80" width="32" height="16" fill="#F6A41C" />
          <rect x="288" y="80" width="32" height="16" fill="#F6A41CCF" />
          <rect x="320" y="80" width="32" height="16" fill="#F6A41C9E" />
          <rect x="352" y="80" width="32" height="16" fill="#F6A41C70" />
          <rect x="96" y="96" width="32" height="16" fill="#F6A41C70" />
          <rect x="128" y="96" width="32" height="16" fill="#F6A41C70" />
          <rect x="160" y="96" width="32" height="16" fill="#F6A41C70" />
          <rect x="224" y="96" width="32" height="16" fill="#F6A41C70" />
          <rect x="256" y="96" width="32" height="16" fill="#F6A41C70" />
          <rect x="288" y="96" width="32" height="16" fill="#F6A41C9E" />
          <rect x="320" y="96" width="32" height="16" fill="#F6A41C70" />
          <path d="M32 0V112 M64 0V112 M96 0V112 M128 0V112 M160 0V112 M192 0V112 M224 0V112 M256 0V112 M288 0V112 M320 0V112 M352 0V112 M0 16H384 M0 32H384 M0 48H384 M0 64H384 M0 80H384 M0 96H384" fill="none" stroke="#070709" strokeWidth="2.5" />
          <text x="0" y="130" fontFamily="Doto" fontSize="10" fill="#FFFFFF66">
            MON → SUN · 00 → 22 · 4 LEVELS
          </text>
        </svg>
      </div>
      <p className="lp-face-cap">Weeknights light up after six. Sunday stays dark.</p>
      <div className="lp-face-facts">
        <FaceFact k="DAYS" v="7" />
        <FaceFact k="HOURS" v="00–22" />
        <FaceFact k="PEAK" v="THU" accent="#F6A41C" />
      </div>
    </article>
  );
}

function FaceBattery() {
  return (
    <article className="lp-face">
      <div style={{alignItems: 'center', display: 'flex'}}>
        <div className="lp-face-k" style={{flex: 1}}>
          BODY BATTERY
        </div>
        <div style={{background: '#EFF65A', padding: '3px 7px'}}>
          <span style={{color: '#070709', fontFamily: 'Doto, monospace', fontSize: 10, fontWeight: 600, letterSpacing: '0.16em'}}>
            RECOVER
          </span>
        </div>
      </div>
      <div style={{alignItems: 'center', display: 'flex', gap: 24, paddingTop: 18}}>
        <svg width="152" height="152" viewBox="0 0 152 152" aria-hidden="true">
          <rect x="24.7" y="33.8" width="12" height="12" fill="#26262E" />
          <rect x="37.3" y="22.1" width="12" height="12" fill="#26262E" />
          <rect x="52.9" y="14.6" width="12" height="12" fill="#26262E" />
          <rect x="70" y="12" width="12" height="12" fill="#EFF65A" />
          <rect x="87.1" y="14.6" width="12" height="12" fill="#EFF65A" />
          <rect x="102.7" y="22.1" width="12" height="12" fill="#EFF65A" />
          <rect x="115.3" y="33.8" width="12" height="12" fill="#EFF65A" />
          <rect x="124" y="48.8" width="12" height="12" fill="#EFF65A" />
          <rect x="127.8" y="65.7" width="12" height="12" fill="#EFF65A" />
          <rect x="126.5" y="82.9" width="12" height="12" fill="#EFF65A" />
          <rect x="120.2" y="99" width="12" height="12" fill="#EFF65A" />
          <rect x="109.5" y="112.5" width="12" height="12" fill="#EFF65A" />
          <rect x="95.2" y="122.3" width="12" height="12" fill="#EFF65A" />
          <rect x="78.6" y="127.4" width="12" height="12" fill="#EFF65A" />
          <rect x="61.4" y="127.4" width="12" height="12" fill="#EFF65A" />
          <rect x="44.8" y="122.3" width="12" height="12" fill="#EFF65A" />
          <rect x="30.5" y="112.5" width="12" height="12" fill="#EFF65A" />
          <rect x="19.8" y="99" width="12" height="12" fill="#EFF65A" />
          <rect x="13.5" y="82.9" width="12" height="12" fill="#EFF65A" />
          <rect x="12.2" y="65.7" width="12" height="12" fill="#EFF65A" />
          <rect x="16" y="48.8" width="12" height="12" fill="#EFF65A" />
          <text x="76" y="92" fontFamily="Doto" fontWeight="800" fontSize="52" textAnchor="middle" fill="#EFF65A">
            86
          </text>
        </svg>
        <div style={{display: 'flex', flex: 1, flexDirection: 'column', gap: 12}}>
          {[
            ['WOKE AT', '91', '#ffffffd9'],
            ['MIN', '38', '#ffffffd9'],
            ['SINCE WAKE', '-5', '#F6A41C'],
          ].map(([k, v, c]) => (
            <div key={k} style={{display: 'flex', justifyContent: 'space-between'}}>
              <span style={{color: '#ffffff66', fontFamily: 'Doto, monospace', fontSize: 12, letterSpacing: '0.14em'}}>
                {k}
              </span>
              <span style={{color: c, fontFamily: 'Doto, monospace', fontSize: 15, fontWeight: 700}}>
                {v}
              </span>
            </div>
          ))}
        </div>
      </div>
      <p className="lp-face-cap">Now 86. Woke at 91.</p>
      <p className="lp-face-meta">battery.now · THE FALLBACK FACE</p>
    </article>
  );
}

function FaceGauge() {
  return (
    <article className="lp-face">
      <div style={{alignItems: 'center', display: 'flex'}}>
        <div className="lp-face-k" style={{flex: 1}}>
          STRESS · 14:20
        </div>
        <div style={{background: '#A3E635', padding: '3px 7px'}}>
          <span style={{color: '#070709', fontFamily: 'Doto, monospace', fontSize: 10, fontWeight: 600, letterSpacing: '0.16em'}}>
            REST
          </span>
        </div>
      </div>
      <div style={{alignItems: 'baseline', display: 'flex', gap: 12, paddingTop: 14}}>
        <strong style={{color: '#A3E635', fontFamily: 'Doto, monospace', fontSize: 62, fontWeight: 800, lineHeight: '56px'}}>
          34
        </strong>
        <span style={{color: '#ffffff8c', fontFamily: 'Doto, monospace', fontSize: 16, fontWeight: 600, letterSpacing: '0.2em'}}>
          REST
        </span>
      </div>
      <div style={{paddingTop: 24}}>
        <svg width="100%" height="70" viewBox="0 0 384 70" aria-hidden="true">
          <rect x="0" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="16" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="32" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="48" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="64" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="80" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="96" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="112" y="0" width="16" height="40" fill="#A3E635" />
          <rect x="128" y="0" width="16" height="40" fill="#A3E63533" />
          <rect x="144" y="0" width="16" height="40" fill="#A3E63533" />
          <rect x="160" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="176" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="192" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="208" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="224" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="240" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="256" y="0" width="16" height="40" fill="#EFF65A33" />
          <rect x="272" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="288" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="304" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="320" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="336" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="352" y="0" width="16" height="40" fill="#F6A41C33" />
          <rect x="368" y="0" width="16" height="40" fill="#F6A41C33" />
          <path d="M16 0V40 M32 0V40 M48 0V40 M64 0V40 M80 0V40 M96 0V40 M112 0V40 M128 0V40 M144 0V40 M160 0V40 M176 0V40 M192 0V40 M208 0V40 M224 0V40 M240 0V40 M256 0V40 M272 0V40 M288 0V40 M304 0V40 M320 0V40 M336 0V40 M352 0V40 M368 0V40 M0 8H384 M0 16H384 M0 24H384 M0 32H384" fill="none" stroke="#070709" strokeWidth="2.5" />
          <rect x="120" y="46" width="8" height="8" fill="#FFFFFF" />
          <text x="0" y="68" fontFamily="Doto" fontSize="10" fill="#A3E635">
            REST 0-40
          </text>
          <text x="160" y="68" fontFamily="Doto" fontSize="10" fill="#EFF65A99">
            MID 40-70
          </text>
          <text x="288" y="68" fontFamily="Doto" fontSize="10" fill="#F6A41C99">
            HIGH 70+
          </text>
        </svg>
      </div>
      <p className="lp-face-cap">Still in REST. Sliding down.</p>
      <p className="lp-face-meta">stress.now · 24 CELLS · THREE ZONES</p>
    </article>
  );
}

function FaceZones() {
  return (
    <article className="lp-face">
      <div style={{alignItems: 'center', display: 'flex'}}>
        <div className="lp-face-k" style={{flex: 1}}>
          ZONES · TODAY
        </div>
        <div style={{background: '#F6A41C', padding: '3px 7px'}}>
          <span style={{color: '#070709', fontFamily: 'Doto, monospace', fontSize: 10, fontWeight: 600, letterSpacing: '0.16em'}}>
            MOVE
          </span>
        </div>
      </div>
      <div style={{alignItems: 'baseline', display: 'flex', gap: 10, paddingTop: 14}}>
        <strong style={{color: '#A3E635', fontFamily: 'Doto, monospace', fontSize: 56, fontWeight: 800, lineHeight: '52px'}}>
          Z2
        </strong>
        <span style={{color: '#ffffff99', fontFamily: 'Doto, monospace', fontSize: 20, fontWeight: 600, letterSpacing: '0.14em'}}>
          34 MIN
        </span>
      </div>
      <div style={{paddingTop: 22}}>
        <svg width="100%" height="118" viewBox="0 0 392 118" aria-hidden="true">
          <rect x="0" y="0" width="392" height="96" fill="#131318" />
          <rect x="0" y="56" width="72" height="40" fill="#26262E" />
          <rect x="80" y="0" width="72" height="96" fill="#A3E635" />
          <rect x="160" y="32" width="72" height="64" fill="#EFF65A" />
          <rect x="240" y="72" width="72" height="24" fill="#F6A41C" />
          <rect x="320" y="88" width="72" height="8" fill="#EF4444" />
          <path d="M16 0V96 M32 0V96 M48 0V96 M64 0V96 M80 0V96 M96 0V96 M112 0V96 M128 0V96 M144 0V96 M160 0V96 M176 0V96 M192 0V96 M208 0V96 M224 0V96 M240 0V96 M256 0V96 M272 0V96 M288 0V96 M304 0V96 M320 0V96 M336 0V96 M352 0V96 M368 0V96 M0 16H392 M0 32H392 M0 48H392 M0 64H392 M0 80H392" fill="none" stroke="#070709" strokeWidth="2.5" />
          <text x="24" y="114" fontFamily="Doto" fontSize="11" fill="#FFFFFF52">
            Z1
          </text>
          <text x="104" y="114" fontFamily="Doto" fontSize="11" fill="#A3E635">
            Z2
          </text>
          <text x="184" y="114" fontFamily="Doto" fontSize="11" fill="#FFFFFF8C">
            Z3
          </text>
          <text x="264" y="114" fontFamily="Doto" fontSize="11" fill="#FFFFFF8C">
            Z4
          </text>
          <text x="344" y="114" fontFamily="Doto" fontSize="11" fill="#FFFFFF8C">
            Z5
          </text>
        </svg>
      </div>
      <p className="lp-face-cap">14 · 34 · 22 · 9 · 3 MIN</p>
      <p className="lp-face-meta">zones.today · PEAK 168</p>
    </article>
  );
}

function FaceFact({k, v, accent}: {k: string; v: string; accent?: string}) {
  return (
    <div style={{display: 'flex', flex: 1, flexDirection: 'column', gap: 4}}>
      <span style={{color: '#ffffff52', fontFamily: 'Doto, monospace', fontSize: 10, letterSpacing: '0.16em'}}>
        {k}
      </span>
      <span style={{color: accent ?? '#ffffffd9', fontFamily: 'Doto, monospace', fontSize: 16, fontWeight: 700}}>
        {v}
      </span>
    </div>
  );
}
