/**
 * App screens drawn as web components — NextBody's own faces, not mockups.
 * Carbon ground, Doto-style numbers, one lime accent. The panel is the only
 * place the product speaks.
 */

type ScreenProps = {className?: string};

function Dot({className}: {className?: string}) {
  return <span className={['nb-dot', className].filter(Boolean).join(' ')} />;
}

function Hairline() {
  return <div className="nb-hairline" />;
}

function PanelChrome({children}: {children: React.ReactNode}) {
  return <div className="nb-panel">{children}</div>;
}

export function HomeScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-statusbar">
        <span>9:41</span>
        <span className="nb-status-icons">
          <i className="nb-signal" />
          <i className="nb-wifi" />
          <i className="nb-batt" />
        </span>
      </div>
      <div className="nb-home-header">
        <div className="nb-avatar">ZW</div>
        <div className="nb-home-id">
          <p className="nb-dayline">SUN · 6 SEP</p>
          <p className="nb-name">
            Zihuang <span className="nb-flame" /> <span className="nb-flame-n">12</span>
          </p>
        </div>
        <div className="nb-battery-pip">
          <span className="nb-battery-fill" style={{width: '72%'}} />
        </div>
      </div>

      <PanelChrome>
        <div className="nb-panel-head">
          <span className="nb-panel-title">STANDBY</span>
          <span className="nb-panel-clock">11:27</span>
        </div>
        <div className="nb-planet">
          <span className="nb-planet-core" />
          <span className="nb-planet-ring nb-planet-ring-lime" />
          <span className="nb-planet-ring nb-planet-ring-blue" />
        </div>
        <div className="nb-panel-hero">
          <p className="nb-eyebrow">BODY BATTERY</p>
          <p className="nb-hero-num">
            61<span className="nb-hero-unit">%</span>
          </p>
          <p className="nb-hero-sub">CHARGED +38 OVERNIGHT</p>
        </div>
        <div className="nb-panel-vitals">
          <div className="nb-vital">
            <p className="nb-vital-num nb-live">72</p>
            <p className="nb-vital-label">HR</p>
          </div>
          <div className="nb-vital">
            <p className="nb-vital-num">34</p>
            <p className="nb-vital-label">STRESS</p>
          </div>
        </div>
        <p className="nb-panel-hint">LIVE · TAP OR TALK — I&apos;M UP</p>
      </PanelChrome>

      <div className="nb-strip">
        <div className="nb-card">
          <div className="nb-card-top">
            <span>TRAINING</span>
            <span className="nb-card-tag nb-lime">IN RANGE</span>
          </div>
          <div className="nb-ring">
            <span className="nb-ring-track" />
            <span className="nb-ring-fill" />
            <span className="nb-ring-num">14.2</span>
          </div>
          <div className="nb-card-meta">
            <p>SUGGESTED RANGE</p>
            <p className="nb-card-value">12.4–16.8</p>
          </div>
        </div>
        <div className="nb-card">
          <div className="nb-card-top">
            <span>CALORIES</span>
            <span className="nb-card-tag">OF 2,400</span>
          </div>
          <div className="nb-fuel">
            <div>
              <p>EATEN</p>
              <p className="nb-fuel-num">1,240</p>
            </div>
            <div>
              <p>TO GO</p>
              <p className="nb-fuel-num">1,160</p>
            </div>
          </div>
          <div className="nb-fuel-bar">
            <span style={{width: '52%'}} />
          </div>
          <div className="nb-macros">
            <div className="nb-macro">
              <span>PRO</span>
              <div className="nb-macro-bar">
                <span className="nb-violet" style={{width: '64%'}} />
              </div>
              <span>92/145</span>
            </div>
            <div className="nb-macro">
              <span>CARB</span>
              <div className="nb-macro-bar">
                <span className="nb-green" style={{width: '48%'}} />
              </div>
              <span>118/195</span>
            </div>
            <div className="nb-macro">
              <span>FAT</span>
              <div className="nb-macro-bar">
                <span className="nb-ember" style={{width: '55%'}} />
              </div>
              <span>33/60</span>
            </div>
          </div>
        </div>
      </div>

      <div className="nb-dock">
        <div className="nb-dock-key">
          <span className="nb-kbd" />
        </div>
        <div className="nb-dock-orb" />
        <div className="nb-dock-key">
          <span className="nb-cam" />
        </div>
      </div>
      <div className="nb-plan-lip">
        <span className="nb-chevron" />
        <span className="nb-page-dots">
          <Dot className="on" />
          <Dot />
        </span>
        <span>PLAN</span>
      </div>
    </div>
  );
}

export function VitalsScreen({className}: ScreenProps) {
  const cards = [
    {label: 'SLEEP', tag: 'LAST NIGHT', value: '87', unit: 'ASLEEP', tint: 'nb-violet'},
    {label: 'HEART', tag: 'NOW', value: '72', unit: 'BPM', tint: 'nb-lime'},
    {label: 'RESPONSE', tag: 'NOW', value: '—', unit: '', tint: 'nb-amber'},
    {label: 'STRESS', tag: 'TODAY', value: '34', unit: '/100 NOW', tint: 'nb-ember'},
    {label: 'TEMP', tag: 'NOW', value: '33.4', unit: '°C SKIN', tint: 'nb-cyan'},
    {label: 'STEPS', tag: 'TODAY', value: '8,412', unit: '', tint: 'nb-green'},
    {label: 'DISTANCE', tag: 'TODAY', value: '6.2', unit: 'KM', tint: 'nb-pink'},
    {label: 'ACTIVE ENERGY', tag: 'TODAY', value: '412', unit: 'KCAL', tint: 'nb-lime'},
  ];
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-statusbar">
        <span>9:41</span>
        <span className="nb-status-icons">
          <i className="nb-signal" />
          <i className="nb-wifi" />
          <i className="nb-batt" />
        </span>
      </div>
      <div className="nb-home-header">
        <div className="nb-avatar">ZW</div>
        <div className="nb-home-id">
          <p className="nb-dayline">SUN · 6 SEP</p>
          <p className="nb-name">
            Zihuang <span className="nb-flame" /> <span className="nb-flame-n">12</span>
          </p>
        </div>
        <div className="nb-battery-pip">
          <span className="nb-battery-fill" style={{width: '72%'}} />
        </div>
      </div>
      <div className="nb-vitals-grid">
        {cards.map((card) => (
          <div className="nb-instrument" key={card.label}>
            <div className="nb-card-top">
              <span>{card.label}</span>
              <span className={`nb-card-tag ${card.tint}`}>{card.tag}</span>
            </div>
            <div className="nb-instrument-num">
              <span className={card.tint}>{card.value}</span>
              {card.unit ? <span className="nb-instrument-unit">{card.unit}</span> : null}
            </div>
            <div className="nb-instrument-chart">
              <span className={`nb-spark ${card.tint}`} />
            </div>
            <p className="nb-instrument-foot">LAST TICK 11:27 · 2 MIN AGO</p>
          </div>
        ))}
      </div>
      <p className="nb-vitals-foot">LAST TICK 11:27 · 2 MIN AGO · 1H 05M OFF WRIST</p>
      <div className="nb-plan-lip">
        <span className="nb-chevron" />
        <span className="nb-page-dots">
          <Dot />
          <Dot className="on" />
        </span>
        <span>PLAN</span>
      </div>
    </div>
  );
}

export function BodyBatteryScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-detail-nav">
        <span className="nb-back">‹</span>
        <span className="nb-detail-title">BODY BATTERY</span>
        <span className="nb-detail-status nb-lime">TODAY</span>
      </div>
      <div className="nb-pills">
        <span className="nb-pill on">DAY</span>
        <span className="nb-pill">WEEK</span>
        <span className="nb-pill">MONTH</span>
      </div>
      <div className="nb-detail-hero">
        <p className="nb-eyebrow">BODY BATTERY</p>
        <p className="nb-hero-num nb-lime">
          61<span className="nb-hero-unit">%</span>
        </p>
        <p className="nb-hero-sub">SYNCED 11:27 · WAKE 07:12</p>
      </div>
      <div className="nb-chart-card">
        <div className="nb-chart-head">
          <span>LAST 24H RESERVE</span>
          <span>0–100</span>
        </div>
        <div className="nb-bb-curve">
          <span className="nb-bb-line" />
          <span className="nb-bb-dot" />
        </div>
        <div className="nb-chart-foot">
          <span>CHARGED +38 · NIGHT 22:40–07:12</span>
          <span>NOW 61</span>
        </div>
      </div>
      <div className="nb-detail-rows">
        <div className="nb-detail-row">
          <span>Sleep recovery</span>
          <span className="nb-lime">+38</span>
        </div>
        <div className="nb-detail-row">
          <span>Daytime spend</span>
          <span>−22</span>
        </div>
        <div className="nb-detail-row">
          <span>Verified rest</span>
          <span className="nb-lime">+7</span>
        </div>
        <div className="nb-detail-row">
          <span>Off-wrist</span>
          <span>0</span>
        </div>
      </div>
    </div>
  );
}

export function SleepScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-detail-nav">
        <span className="nb-back">‹</span>
        <span className="nb-detail-title">SLEEP</span>
        <span className="nb-detail-status nb-violet">LAST NIGHT</span>
      </div>
      <div className="nb-pills">
        <span className="nb-pill on">DAY</span>
        <span className="nb-pill">WEEK</span>
        <span className="nb-pill">MONTH</span>
      </div>
      <div className="nb-detail-hero">
        <p className="nb-eyebrow">SLEEP SCORE</p>
        <p className="nb-hero-num nb-violet">87</p>
        <p className="nb-hero-sub">7H 42M · BED 22:40 · WAKE 07:12</p>
      </div>
      <div className="nb-chart-card">
        <div className="nb-chart-head">
          <span>STAGES HYPNOGRAM</span>
          <span>22:40–07:12</span>
        </div>
        <div className="nb-hypno">
          <span className="nb-hypno-awake" style={{left: '4%', width: '6%'}} />
          <span className="nb-hypno-light" style={{left: '10%', width: '22%'}} />
          <span className="nb-hypno-deep" style={{left: '32%', width: '18%'}} />
          <span className="nb-hypno-rem" style={{left: '50%', width: '14%'}} />
          <span className="nb-hypno-light" style={{left: '64%', width: '20%'}} />
          <span className="nb-hypno-deep" style={{left: '84%', width: '12%'}} />
        </div>
        <div className="nb-chart-foot">
          <span>DEEP 22% · REM 18% · LIGHT 54%</span>
          <span>NIGHT HRV 58 MS</span>
        </div>
      </div>
      <div className="nb-detail-rows">
        <div className="nb-detail-row">
          <span>Duration</span>
          <span>25 / 25</span>
        </div>
        <div className="nb-detail-row">
          <span>Structure</span>
          <span>22 / 25</span>
        </div>
        <div className="nb-detail-row">
          <span>Recovery</span>
          <span className="nb-violet">30 / 35</span>
        </div>
        <div className="nb-detail-row">
          <span>Consistency</span>
          <span>10 / 15</span>
        </div>
      </div>
    </div>
  );
}

export function TrainingScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-detail-nav">
        <span className="nb-back">‹</span>
        <span className="nb-detail-title">TRAINING</span>
        <span className="nb-detail-status nb-lime">IN RANGE</span>
      </div>
      <div className="nb-pills">
        <span className="nb-pill on">DAY</span>
        <span className="nb-pill">WEEK</span>
        <span className="nb-pill">MONTH</span>
      </div>
      <div className="nb-detail-hero">
        <p className="nb-eyebrow">TRAINING LOAD</p>
        <p className="nb-hero-num nb-lime">14.2</p>
        <p className="nb-hero-sub">TARGET 15.0 · ZONE 12.4–16.8</p>
      </div>
      <div className="nb-chart-card">
        <div className="nb-chart-head">
          <span>TODAY&apos;S LOAD CURVE</span>
          <span>0–21</span>
        </div>
        <div className="nb-load-curve">
          <span className="nb-load-line" />
          <span className="nb-load-target" />
        </div>
        <div className="nb-chart-foot">
          <span>HR ZONES 42 MIN · SPORT 0</span>
          <span>ESTIMATE</span>
        </div>
      </div>
      <div className="nb-detail-rows">
        <div className="nb-detail-row">
          <span>Heart-rate zones</span>
          <span>42 MIN</span>
        </div>
        <div className="nb-detail-row">
          <span>Sport sessions</span>
          <span>0</span>
        </div>
        <div className="nb-detail-row">
          <span>Steps</span>
          <span>8,412</span>
        </div>
      </div>
      <div className="nb-cta">START A SESSION</div>
    </div>
  );
}

export function FuelScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-detail-nav">
        <span className="nb-back">‹</span>
        <span className="nb-detail-title">CALORIES</span>
        <span className="nb-detail-status">TODAY</span>
      </div>
      <div className="nb-pills">
        <span className="nb-pill on">DAY</span>
        <span className="nb-pill">WEEK</span>
        <span className="nb-pill">MONTH</span>
      </div>
      <div className="nb-detail-hero">
        <p className="nb-eyebrow">EATEN</p>
        <p className="nb-hero-num nb-ember">1,240</p>
        <p className="nb-hero-sub">OF 2,400 · 1,160 TO GO</p>
      </div>
      <div className="nb-chart-card">
        <div className="nb-chart-head">
          <span>IN / OUT CLOCK</span>
          <span>04:00–NOW</span>
        </div>
        <div className="nb-fuel-clock">
          <span className="nb-fuel-in" />
          <span className="nb-fuel-out" />
          <span className="nb-fuel-now" />
        </div>
        <div className="nb-chart-foot">
          <span>IN 1,240 · OUT 1,890</span>
          <span>DIFF −650</span>
        </div>
      </div>
      <div className="nb-detail-rows">
        <div className="nb-detail-row">
          <span>Oat bowl</span>
          <span>420 KCAL</span>
        </div>
        <div className="nb-detail-row">
          <span>Chicken rice</span>
          <span>640 KCAL</span>
        </div>
        <div className="nb-detail-row">
          <span>Coffee</span>
          <span>180 KCAL</span>
        </div>
      </div>
      <div className="nb-cta nb-ember-bg">LOG A MEAL</div>
    </div>
  );
}

export function PlanScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-plan-chrome">
        <span className="nb-chevron nb-chevron-down" />
        <span className="nb-plan-count">TODAY · 5 TASKS</span>
      </div>
      <div className="nb-plan-summary">
        <p className="nb-plan-title">Keep the morning easy, lift after 16:00.</p>
        <p className="nb-plan-sub">
          Body battery is 61 after a short night. Hold load in range and eat
          before the session.
        </p>
        <p className="nb-plan-read">AI READ 09-04 → 09-06</p>
      </div>
      <div className="nb-plan-tasks">
        <div className="nb-plan-task">
          <span className="nb-check on" />
          <div>
            <p className="nb-plan-task-title">Bed by 22:30</p>
            <p className="nb-plan-task-sub">Last night was 6 h 12 m. Tonight is the recovery night.</p>
            <p className="nb-plan-task-basis">SLEEP · 09-05</p>
          </div>
        </div>
        <div className="nb-plan-task">
          <span className="nb-check" />
          <div>
            <p className="nb-plan-task-title">Zone 2, 35 min</p>
            <p className="nb-plan-task-sub">Keep HR under 135. The load target is 15.0.</p>
            <p className="nb-plan-task-basis">TRAINING · 09-06</p>
          </div>
        </div>
        <div className="nb-plan-task">
          <span className="nb-check" />
          <div>
            <p className="nb-plan-task-title">Eat before 15:00</p>
            <p className="nb-plan-task-sub">1,160 kcal to go. A late meal pushes the session.</p>
            <p className="nb-plan-task-basis">FUEL · 09-06</p>
          </div>
        </div>
        <div className="nb-plan-task">
          <span className="nb-check" />
          <div>
            <p className="nb-plan-task-title">Ten minutes quiet</p>
            <p className="nb-plan-task-sub">Stress peaked at 14:20 yesterday. Take the afternoon down.</p>
            <p className="nb-plan-task-basis">STRESS · 09-05</p>
          </div>
        </div>
        <div className="nb-plan-task">
          <span className="nb-check" />
          <div>
            <p className="nb-plan-task-title">Strength, 20 min</p>
            <p className="nb-plan-task-sub">Two sets, not four. The week is already at 78.</p>
            <p className="nb-plan-task-basis">BODY · 09-04</p>
          </div>
        </div>
      </div>
      <div className="nb-plan-regen">REGENERATE</div>
    </div>
  );
}

export function ChatScreen({className}: ScreenProps) {
  return (
    <div className={['nb-screen', className].filter(Boolean).join(' ')}>
      <div className="nb-chat-top">
        <span className="nb-back">‹</span>
        <div>
          <p className="nb-chat-title">AI COACH <span className="nb-lime-dot" /></p>
          <p className="nb-chat-sub">ASK ANYTHING · YOUR AI COACH</p>
        </div>
        <span className="nb-chat-history">HISTORY</span>
      </div>
      <div className="nb-chat-thread">
        <div className="nb-msg-user">
          <p>Why am I so tired today?</p>
          <p className="nb-msg-time">11:24 · DELIVERED</p>
        </div>
        <div className="nb-msg-ai">
          <p>
            Your body battery is 61 after a 6 h 12 m night. Night HRV is 58 ms,
            which is 12% under your own median. That is the tired.
          </p>
          <p className="nb-msg-detail">
            Keep training in the suggested range and move the session to after
            16:00. Eat before you lift.
          </p>
        </div>
        <div className="nb-msg-thinking">
          <p className="nb-thinking-head">
            <span className="nb-lime-dot" /> THINKING…
          </p>
          <p>Reading last night&apos;s sleep and this morning&apos;s reserve…</p>
        </div>
      </div>
      <div className="nb-chat-dock">
        <div className="nb-chat-cmds">
          <span className="nb-cmd nb-cmd-on">[CMD: ADJUST PLAN]</span>
          <span className="nb-cmd">[CMD: SLEEP CORRELATION]</span>
        </div>
        <div className="nb-chat-input">
          <span className="nb-chat-cam" />
          <span className="nb-chat-placeholder">Ask anything, or share a photo…</span>
          <span className="nb-chat-send" />
        </div>
      </div>
    </div>
  );
}
