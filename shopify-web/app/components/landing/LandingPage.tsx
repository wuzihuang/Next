import {Link} from 'react-router';
import {landingCopy, type LandingLocale} from '~/lib/landing';
import {LandingCompositionPhone} from '~/components/landing/LandingCompositionPhone';
import {LandingFaces} from '~/components/landing/LandingFaces';

export function LandingPage({locale}: {locale: LandingLocale}) {
  const t = landingCopy(locale);
  const home = locale === 'zh' ? '/zh' : '/';
  const other = locale === 'zh' ? '/' : '/zh';

  return (
    <div className="lp" data-locale={locale}>
      <div className="lp-shell">
        <header className="lp-nav">
          <Link className="lp-wordmark" prefetch="intent" to={home}>
            <span className="lp-wordmark-name">NEXTBODY</span>
            <span className="lp-pip" aria-hidden="true" />
          </Link>
          <nav className="lp-nav-mid" aria-label="Primary">
            <a className="lp-nav-link" href="#band">
              {t.nav.band}
            </a>
            <a className="lp-nav-link" href="#app">
              {t.nav.app}
            </a>
            <a className="lp-nav-link" href="#science">
              {t.nav.science}
            </a>
          </nav>
          <div className="lp-nav-end">
            <div className="lp-langs">
              {locale === 'en' ? (
                <>
                  <span className="lp-lang is-on">EN</span>
                  <span className="lp-lang-rule" />
                  <Link className="lp-lang" prefetch="intent" to={other}>
                    中文
                  </Link>
                </>
              ) : (
                <>
                  <span className="lp-lang is-on">中文</span>
                  <span className="lp-lang-rule" />
                  <Link className="lp-lang" prefetch="intent" to={other}>
                    EN
                  </Link>
                </>
              )}
            </div>
            <Link className="lp-sign" prefetch="intent" to="/account/login">
              {t.nav.signIn}
            </Link>
            <Link className="lp-pill" prefetch="intent" to="/products/hoop">
              {t.nav.getHoop}
            </Link>
          </div>
        </header>

        <section className="lp-hero" aria-labelledby="hero-title">
          <div className="lp-hero-bg" />
          <div className="lp-hero-scrim" />
          <div className="lp-hero-inner">
            <div className="lp-hero-lock">
              <div>
                <div className="lp-hero-kicker">
                  <span className="lp-pip" />
                  <p>{t.hero.kicker}</p>
                </div>
                <h1 id="hero-title">
                  {t.hero.title[0]}
                  <br />
                  {t.hero.title[1]}
                </h1>
              </div>
              <div className="lp-hero-bottom">
                <p className="lp-hero-lede">{t.hero.lede}</p>
                <div className="lp-hero-cta">
                  <Link className="lp-pill lp-pill-hero" prefetch="intent" to="/products/hoop">
                    {t.hero.cta}
                    <Arrow />
                  </Link>
                  <div className="lp-hero-nosub">
                    <i />
                    <span>{t.hero.noSub}</span>
                  </div>
                </div>
              </div>
            </div>
            <div className="lp-hero-floor">
              {t.hero.floor.map((item) => (
                <span key={item}>{item}</span>
              ))}
            </div>
          </div>
        </section>

        <section className="lp-gallery" id="band">
          <div className="lp-gallery-head">
            <div className="lp-gallery-copy">
              <p className="lp-kicker-lime">{t.gallery.kicker}</p>
              <h2 className="lp-display-title">
                {t.gallery.title[0]}
                <br />
                {t.gallery.title[1]}
              </h2>
            </div>
            <div className="lp-gallery-aside">
              <p>{t.gallery.lede}</p>
              <span>{t.gallery.note}</span>
            </div>
          </div>
          <div className="lp-gallery-row">
            <div className="lp-shot" style={{backgroundImage: 'url(/landing/buckle.png)'}} />
            <div className="lp-shot" style={{backgroundImage: 'url(/landing/weave.png)'}} />
            <div
              className="lp-shot lp-shot-sensor"
              style={{backgroundImage: 'url(/landing/sensor.png)'}}
            >
              <b>{t.gallery.sensorLabel}</b>
              <span>{t.gallery.sensorRatio}</span>
            </div>
          </div>
        </section>

        <section className="lp-hl" id="app">
          <div className="lp-hl-head">
            <div>
              <p className="lp-hl-kicker">{t.highlights.kicker}</p>
              <h2 className="lp-hl-title">{t.highlights.title}</h2>
            </div>
          </div>
          <div className="lp-hl-grid">
            <article className="lp-hl-card">
              <div className="lp-hl-media" style={{backgroundImage: 'url(/landing/light.png)'}} />
              <HlCopy card={t.highlights.cards[0]} />
            </article>
            <article className="lp-hl-card">
              <div className="lp-hl-media" style={{backgroundImage: 'url(/landing/water.png)'}} />
              <HlCopy card={t.highlights.cards[1]} />
            </article>
            <article className="lp-hl-card">
              <div className="lp-triad">
                {t.highlights.triad.map((row, i) => (
                  <div key={row.label}>
                    {i > 0 ? <hr /> : null}
                    <div className="lp-triad-row">
                      <strong>{row.value}</strong>
                      <span>{row.label}</span>
                    </div>
                  </div>
                ))}
              </div>
              <HlCopy card={t.highlights.cards[2]} />
            </article>
            <article className="lp-hl-card">
              <div className="lp-scan">
                <div className="lp-scan-bg" />
                <div className="lp-scan-plate">
                  <div className="lp-scan-col">
                    <strong>
                      {t.highlights.scan.fat}
                      <em> {t.highlights.scan.fatUnit}</em>
                    </strong>
                    <span>{t.highlights.scan.fatLabel}</span>
                  </div>
                  <i className="lp-scan-rule" />
                  <div className="lp-scan-col">
                    <strong>{t.highlights.scan.bmi}</strong>
                    <span>{t.highlights.scan.bmiLabel}</span>
                  </div>
                </div>
              </div>
              <HlCopy card={t.highlights.cards[3]} />
            </article>
            <article className="lp-hl-card">
              <div className="lp-mini-coach">
                <div className="lp-mini-q">
                  <span>{t.highlights.coach.question}</span>
                </div>
                <div className="lp-mini-a">
                  <div className="lp-mini-a-k">
                    <i />
                    <span>{t.highlights.coach.kicker}</span>
                  </div>
                  <p>{t.highlights.coach.answer}</p>
                  <span className="lp-mini-act">{t.highlights.coach.action}</span>
                </div>
              </div>
              <HlCopy card={t.highlights.cards[4]} />
            </article>
            <article className="lp-hl-card">
              <AiDisplayCard copy={t.highlights.aiDisplay} />
              <HlCopy card={t.highlights.cards[5]} />
            </article>
          </div>
        </section>

        <section className="lp-app">
          <div className="lp-app-copy">
            <h2>{t.appRead.title}</h2>
            <p>{t.appRead.lede}</p>
            <span>{t.appRead.note}</span>
            <a className="lp-app-cta" href="#science">
              {t.appRead.cta}
            </a>
          </div>
          <div className="lp-phones">
            <Phone className="lp-phone-s lp-phone-sleep" src="/landing/phone-sleep.png" />
            <Phone className="lp-phone-m lp-phone-vitals" src="/landing/phone-vitals.png" />
            <Phone className="lp-phone-l" src="/landing/phone-home.png" />
            <Phone className="lp-phone-m lp-phone-battery" src="/landing/phone-battery.png" />
            <Phone className="lp-phone-s lp-phone-heart" src="/landing/phone-heart.png" />
          </div>
        </section>

        <section className="lp-radar">
          <div className="lp-radar-copy">
            <b>{t.radar.kicker}</b>
            <h2>
              {t.radar.title[0]}
              <br />
              {t.radar.title[1]}
            </h2>
            <p>{t.radar.lede}</p>
          </div>
          <img alt="" src="/landing/radar.png" />
        </section>

        <section className="lp-comp">
          <div className="lp-comp-head">
            <b>{t.composition.kicker}</b>
            <h2>{t.composition.title}</h2>
            <p>{t.composition.lede}</p>
          </div>
          <div className="lp-comp-hero">
            <LandingCompositionPhone copy={t.composition} />
          </div>
        </section>

        <section className="lp-stress">
          <div className="lp-stress-head">
            <h2>{t.stress.title}</h2>
            <p>{t.stress.lede}</p>
          </div>
          <div className="lp-stress-live">
            <div className="lp-stress-num">
              <b>{t.stress.live}</b>
              <div style={{alignItems: 'baseline', display: 'flex', gap: 12}}>
                <strong>{t.stress.liveValue}</strong>
                <em>{t.stress.liveBand}</em>
              </div>
            </div>
            <svg width="200" height="34" viewBox="0 0 200 34" aria-hidden="true">
              <path
                d="M0 22 C14 21 22 24 32 20 C44 15 52 26 64 18 C76 10 86 16 98 12 C110 8 118 20 132 14 C146 8 158 18 172 16 C184 14 192 10 200 7"
                fill="none"
                stroke="#16EC06"
                strokeWidth="1.5"
              />
              <circle cx="200" cy="7" r="2.5" fill="#16EC06" />
            </svg>
            <div className="lp-stress-move">
              <b>{t.stress.move}</b>
              <p>{t.stress.moveText}</p>
            </div>
          </div>
          <div className="lp-stress-out">
            {t.stress.outcomes.map((item) => (
              <article key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.lede}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="lp-science" id="science">
          <div>
            <p className="lp-kicker-lime">{t.display.kicker}</p>
            <h2 className="lp-display-title">
              {t.display.title[0]}
              <br />
              {t.display.title[1]}
            </h2>
            <p className="lp-science-lede">{t.display.lede}</p>
            <p className="lp-science-legal">{t.display.legal}</p>
            <p className="lp-science-ticker">{t.display.ticker}</p>
          </div>
          <LandingFaces />
          <div className="lp-faces-note">
            <span>{t.display.captionLeft}</span>
            <span>{t.display.captionRight}</span>
          </div>
        </section>

        <section className="lp-science">
          <div>
            <p className="lp-kicker-lime">{t.coach.kicker}</p>
            <h2 className="lp-display-title">
              {t.coach.title[0]}
              <br />
              {t.coach.title[1]}
            </h2>
            <p className="lp-science-lede">{t.coach.lede}</p>
            <p className="lp-science-legal">{t.coach.legal}</p>
          </div>
          <div className="lp-coach-well">
            <div className="lp-coach-top">
              <div className="lp-coach-thread">
                <div className="lp-q">
                  <div className="lp-q-bubble">{t.coach.question}</div>
                  <time>{t.coach.you}</time>
                </div>
                <div className="lp-a">
                  <div className="lp-a-head">
                    <div className="lp-a-head-l">
                      <i />
                      <span>{t.coach.coachLabel}</span>
                    </div>
                    <time>{t.coach.readLine}</time>
                  </div>
                  <h3>{t.coach.verdict}</h3>
                  <p>{t.coach.p1}</p>
                  <p>{t.coach.p2}</p>
                  <ol className="lp-a-steps">
                    <b>{t.coach.today}</b>
                    {t.coach.steps.map((step, i) => (
                      <li key={step}>
                        <em>{String(i + 1).padStart(2, '0')}</em>
                        {step}
                      </li>
                    ))}
                  </ol>
                  <div className="lp-a-acts">
                    <span className="is-lime">{t.coach.actPlan}</span>
                    <span>{t.coach.actSleep}</span>
                    <span>{t.coach.actAlarm}</span>
                  </div>
                </div>
              </div>
              <div className="lp-plan">
                <div className="lp-plan-head">
                  <b>{t.coach.planKicker}</b>
                  <span>{t.coach.planRead}</span>
                </div>
                <div>
                  <h3>{t.coach.planTitle}</h3>
                  <p>{t.coach.planLede}</p>
                </div>
                <div>
                  {t.coach.tasks.map((task) => (
                    <div className={task.done ? 'lp-task is-done' : 'lp-task'} key={task.title}>
                      <div className={task.done ? 'lp-check is-on' : 'lp-check'}>
                        {task.done ? <Check /> : null}
                      </div>
                      <div>
                        <strong>{task.title}</strong>
                        <span>{task.sub}</span>
                        {task.meta ? <em>{task.meta}</em> : null}
                      </div>
                    </div>
                  ))}
                </div>
                <div className="lp-plan-foot">
                  <p>{t.coach.planFoot}</p>
                  <span>{t.coach.regenerate}</span>
                </div>
              </div>
            </div>
            <div className="lp-caps">
              {t.coach.caps.map((cap) => (
                <article className="lp-cap" key={cap.kicker}>
                  <b>{cap.kicker}</b>
                  <h3>{cap.title}</h3>
                  <p>{cap.lede}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="lp-next">
          <div className="lp-next-head">
            <b>{t.nextBody.kicker}</b>
            <h2>{t.nextBody.title}</h2>
            <em>{t.nextBody.mark}</em>
            <p>{t.nextBody.lede}</p>
          </div>
          <div className="lp-chase">
            <div className="lp-chase-words">
              <span>{t.nextBody.break}</span>
              <span>{t.nextBody.feel}</span>
              <em>{t.nextBody.chase}</em>
            </div>
          </div>
        </section>

        <section className="lp-finishes">
          <div className="lp-finishes-head">
            <b>{t.finishes.kicker}</b>
            <strong>{t.finishes.price}</strong>
            <h2>{t.finishes.title}</h2>
            <p>{t.finishes.lede}</p>
          </div>
          <div className="lp-facts">
            {t.finishes.facts.map((fact) => (
              <div key={fact.label}>
                <strong>{fact.value}</strong>
                <span>{fact.label}</span>
              </div>
            ))}
          </div>
          <div className="lp-finishes-photo" />
          <div className="lp-finish-labels">
            <div>
              <b>{t.finishes.white}</b>
              <span>{t.finishes.once}</span>
            </div>
            <div>
              <b>{t.finishes.black}</b>
              <span>{t.finishes.once}</span>
            </div>
          </div>
        </section>

        <section className="lp-signals">
          <div className="lp-signals-head">
            <b>{t.signals.kicker}</b>
            <h2>{t.signals.title}</h2>
            <p>{t.signals.lede}</p>
            <span>{t.signals.note}</span>
          </div>
          <div className="lp-sig-grid">
            {SIGNAL_ICONS.map((icon, i) => (
              <div className={i === 11 ? 'lp-sig is-dash' : 'lp-sig'} key={t.signals.items[i]}>
                <div className="lp-sig-icon">{icon}</div>
                <span>{t.signals.items[i]}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="lp-close">
          <div className="lp-close-orbit" aria-hidden="true">
            <svg width="1000" height="640" viewBox="0 0 1000 640">
              <ellipse cx="500" cy="320" rx="470" ry="280" fill="none" stroke="rgb(255 255 255 / 16%)" strokeWidth="1.2" strokeDasharray="3 12" />
              <ellipse cx="500" cy="320" rx="470" ry="280" fill="none" stroke="#EFF65A" strokeWidth="2" strokeLinecap="round" strokeDasharray="110 2640" />
              <circle cx="500" cy="40" r="5" fill="#EFF65A" />
              <circle cx="500" cy="40" r="12" fill="none" stroke="#EFF65A59" />
            </svg>
          </div>
          <b>{t.close.kicker}</b>
          <h2>
            {t.close.title[0]}
            <br />
            {t.close.title[1]}
          </h2>
          <p>{t.close.lede}</p>
          <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/products/hoop">
            {t.close.cta}
            <Arrow />
          </Link>
        </section>

        <footer className="lp-foot">
          <div className="lp-foot-brand">
            <p className="lp-wordmark">
              <span className="lp-wordmark-name">NEXTBODY</span>
              <span className="lp-pip" />
            </p>
            <p>{t.footer.tag}</p>
          </div>
          <div className="lp-foot-cols">
            <nav className="lp-foot-col" aria-label={t.footer.product}>
              <b>{t.footer.product}</b>
              <a href="#band">{t.footer.band}</a>
              <Link prefetch="intent" to="/collections/all">
                {t.footer.shop}
              </Link>
              <a href="#science">{t.footer.science}</a>
            </nav>
            <nav className="lp-foot-col" aria-label={t.footer.support}>
              <b>{t.footer.support}</b>
              <Link prefetch="intent" to="/pages/faq">
                {t.footer.faq}
              </Link>
              <Link prefetch="intent" to="/pages/about">
                {t.footer.about}
              </Link>
              <Link prefetch="intent" to="/pages/contact">
                {t.footer.contact}
              </Link>
              <Link prefetch="intent" to="/blogs">
                {t.footer.journal}
              </Link>
            </nav>
            <nav className="lp-foot-col" aria-label={t.footer.legal}>
              <b>{t.footer.legal}</b>
              <Link prefetch="intent" to="/policies/privacy-policy">
                {t.footer.privacy}
              </Link>
              <Link prefetch="intent" to="/policies/user-agreement">
                {t.footer.agreement}
              </Link>
              <Link prefetch="intent" to="/policies/terms-of-service">
                {t.footer.terms}
              </Link>
              <Link prefetch="intent" to="/policies/refund-policy">
                {t.footer.refund}
              </Link>
              <Link prefetch="intent" to="/policies/shipping-policy">
                {t.footer.shipping}
              </Link>
            </nav>
          </div>
        </footer>
        <div className="lp-legal">
          <span>{t.footer.disclaimer}</span>
          <span>{t.footer.copy}</span>
        </div>
      </div>
    </div>
  );
}

const AI_DISPLAY_ROWS = [
  [false, true, false, false, true, true, false, false, false, false],
  [true, false, false, false, false, true, true, false, false, false],
  [true, false, false, false, false, true, false, false, true, false],
] as const;

function AiDisplayCard({
  copy,
}: {
  copy: {question: string; nights: string; caption: string};
}) {
  return (
    <div className="lp-ai-display">
      <div className="lp-ai-inner">
        <div className="lp-ai-q">
          <span>{copy.question}</span>
        </div>
        <div className="lp-ai-card">
          <div className="lp-ai-grid">
            {AI_DISPLAY_ROWS.map((row) => {
              const rowKey = row.map((on) => (on ? '1' : '0')).join('');
              return (
                <div className="lp-ai-row" key={rowKey}>
                  {row.map((on, dotIndex) => (
                    <i
                      className={on ? 'is-on' : undefined}
                      key={`${rowKey}-${'abcdefghij'[dotIndex]}`}
                    />
                  ))}
                </div>
              );
            })}
          </div>
          <div className="lp-ai-sum">
            <strong>{copy.nights}</strong>
            <span>{copy.caption}</span>
          </div>
        </div>
        <div className="lp-ai-bar">
          <div className="lp-ai-round" aria-hidden="true">
            <AiKeyboardIcon />
          </div>
          <div className="lp-ai-listen" aria-hidden="true">
            <AiListenDots />
          </div>
          <div className="lp-ai-round" aria-hidden="true">
            <AiOrbIcon />
          </div>
        </div>
      </div>
    </div>
  );
}

function AiKeyboardIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true">
      <rect x="2.5" y="5.5" width="19" height="13" rx="3" fill="none" stroke="#E8E8EA" strokeWidth="1.6" />
      <rect x="5.6" y="9" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="9.1" y="9" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="12.6" y="9" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="16.1" y="9" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="5.6" y="12.4" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="16.1" y="12.4" width="1.8" height="1.8" rx="0.4" fill="#E8E8EA" />
      <rect x="8" y="15.8" width="8" height="1.6" rx="0.8" fill="#E8E8EA" />
    </svg>
  );
}

function AiListenDots() {
  return (
    <svg width="96" height="32" viewBox="0 0 96 32" aria-hidden="true">
      {[
        [3.2, 3.2, 0.2],
        [86.4, 3.2, 0.2],
        [3.2, 28.8, 0.2],
        [86.4, 28.8, 0.2],
        [86.4, 9.6, 0.31],
        [86.4, 16, 0.31],
        [86.4, 22.4, 0.31],
        [9.6, 3.2, 0.43],
        [80, 3.2, 0.43],
        [3.2, 9.6, 0.43],
        [3.2, 16, 0.43],
        [3.2, 22.4, 0.43],
        [9.6, 28.8, 0.43],
        [80, 28.8, 0.43],
        [80, 9.6, 0.66],
        [80, 16, 0.66],
        [80, 22.4, 0.66],
      ].map(([cx, cy, opacity]) => (
        <circle cx={cx} cy={cy} r="1.3" fill="#000" key={`${cx}-${cy}`} style={{opacity}} />
      ))}
      {Array.from({length: 10}, (_, col) =>
        [3.2, 9.6, 16, 22.4, 28.8].map((cy, row) => {
          const cx = 16 + col * 6.4;
          if ((row === 0 || row === 4) && (col === 0 || col === 9)) {
            return null;
          }
          return <circle cx={cx} cy={cy} r="1.3" fill="#000" key={`${cx}-${cy}`} style={{opacity: 0.78}} />;
        }),
      )}
    </svg>
  );
}

function AiOrbIcon() {
  return (
    <svg width="54" height="54" viewBox="0 0 54 54" aria-hidden="true">
      {([
        [27, 27, 1.05, '#E8E8EA', 0.9],
        [24.8, 29, 1.04, '#E8E8EA', 0.89],
        [30.1, 25.3, 1.04, '#E8E8EA', 0.88],
        [31.1, 31.8, 1.03, '#E8E8EA', 0.88],
        [24.2, 35.4, 1.02, '#EFF65A', 0.85],
        [35.5, 24.3, 1.02, '#EFF65A', 0.85],
        [20.3, 22.3, 1.02, '#E8E8EA', 0.86],
        [18.5, 30.6, 1.01, '#E8E8EA', 0.85],
        [26.5, 20, 0.99, '#E8E8EA', 0.81],
        [21, 23.8, 0.99, '#E8E8EA', 0.82],
        [38.8, 30.4, 0.98, '#E8E8EA', 0.8],
        [19.6, 34.2, 0.84, '#EFF65A', 0.61],
        [35, 23.3, 0.94, '#EFF65A', 0.74],
        [29.7, 36.3, 0.9, '#EFF65A', 0.69],
        [19.7, 12.9, 0.91, '#EFF65A', 0.7],
        [10.1, 25.4, 0.86, '#EFF65A', 0.63],
        [42.7, 19.3, 0.82, '#EFF65A', 0.58],
        [14.9, 39.4, 0.77, '#EFF65A', 0.51],
        [31.7, 12.9, 0.67, '#EFF65A', 0.37],
        [25.5, 20.1, 0.61, '#EFF65A', 0.29],
        [15.2, 19.5, 0.95, '#E8E8EA', 0.76],
        [13.2, 27.5, 0.95, '#E8E8EA', 0.76],
        [23.6, 34.4, 0.96, '#E8E8EA', 0.77],
        [31.9, 38.6, 0.97, '#E8E8EA', 0.79],
        [24, 15.4, 0.98, '#E8E8EA', 0.81],
        [38.3, 36.9, 0.93, '#E8E8EA', 0.73],
        [15.3, 36.1, 0.93, '#E8E8EA', 0.74],
        [42.5, 24.5, 0.91, '#E8E8EA', 0.71],
        [18, 29, 0.92, '#E8E8EA', 0.72],
        [27.4, 10.5, 0.88, '#E8E8EA', 0.67],
        [43.5, 31, 0.86, '#E8E8EA', 0.63],
        [11.3, 33.7, 0.85, '#E8E8EA', 0.62],
        [41.1, 37.3, 0.82, '#E8E8EA', 0.57],
        [10.6, 32, 0.75, '#E8E8EA', 0.48],
        [26, 10.1, 0.74, '#E8E8EA', 0.46],
        [42.7, 32.3, 0.72, '#E8E8EA', 0.44],
        [13.2, 30.1, 0.65, '#E8E8EA', 0.34],
        [40.4, 26.8, 0.64, '#E8E8EA', 0.33],
        [36.5, 32.7, 0.61, '#E8E8EA', 0.28],
        [18.2, 27.3, 0.58, '#E8E8EA', 0.25],
      ] satisfies [cx: number, cy: number, r: number, fill: string, opacity: number][]).map(([cx, cy, r, fill, opacity]) => (
        <circle cx={cx} cy={cy} r={r} fill={fill} key={`${cx}-${cy}-${r}`} style={{opacity}} />
      ))}
    </svg>
  );
}

function HlCopy({card}: {card: {kicker: string; title: string}}) {
  return (
    <div className="lp-hl-copy">
      <b>{card.kicker}</b>
      <p>{card.title}</p>
    </div>
  );
}

function Phone({className, src}: {className: string; src: string}) {
  return (
    <div className={`lp-phone ${className}`}>
      <div className="lp-phone-screen">
        <img alt="" src={src} />
      </div>
      <div className="lp-phone-notch" />
    </div>
  );
}

function Arrow() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
      <path
        d="M2.5 8h10M8.5 3.5 13 8l-4.5 4.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function Check() {
  return (
    <svg width="12" height="10" viewBox="0 0 12 10" aria-hidden="true">
      <path
        d="M1 5L4.5 8.5L11 1.5"
        fill="none"
        stroke="#0B0B0D"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

const SIGNAL_ICONS = [
  <svg key="bb" width="40" height="40" viewBox="0 0 40 40">
    <rect x="8" y="12" width="21" height="16" rx="3.5" fill="none" stroke="#EFF65A" strokeWidth="2" />
    <rect x="31" y="16.5" width="3" height="7" rx="1" fill="#EFF65A" />
    <rect x="11.5" y="15.5" width="10" height="9" rx="1.5" fill="#EFF65A" />
  </svg>,
  <svg key="tl" width="40" height="40" viewBox="0 0 40 40">
    <rect x="9" y="22" width="5" height="10" rx="1.5" fill="none" stroke="#EFF65A" strokeWidth="2" />
    <rect x="17.5" y="15" width="5" height="17" rx="1.5" fill="none" stroke="#EFF65A" strokeWidth="2" />
    <rect x="26" y="8" width="5" height="24" rx="1.5" fill="#EFF65A" />
  </svg>,
  <svg key="sl" width="40" height="40" viewBox="0 0 40 40">
    <path d="M24 8a12 12 0 1 0 8 21 10 10 0 0 1-8-21z" fill="none" stroke="#EFF65A" strokeWidth="2" strokeLinejoin="round" />
  </svg>,
  <svg key="hr" width="40" height="40" viewBox="0 0 40 40">
    <path d="M20 31s-11-6.8-11-14.2C9 12.9 12 10 15.6 10c2 0 3.6 1 4.4 2.4C20.8 11 22.4 10 24.4 10 28 10 31 12.9 31 16.8 31 24.2 20 31 20 31z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
  </svg>,
  <svg key="o2" width="40" height="40" viewBox="0 0 40 40">
    <path d="M20 7c6 7 9 11.5 9 16a9 9 0 0 1-18 0c0-4.5 3-9 9-16z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
    <circle cx="20" cy="23" r="3" fill="none" stroke="#E8E4DC" strokeWidth="2" />
  </svg>,
  <svg key="st" width="40" height="40" viewBox="0 0 40 40">
    <path d="M6 21h6l3-7 5 14 4-11 3 4h7" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
  </svg>,
  <svg key="tp" width="40" height="40" viewBox="0 0 40 40">
    <path d="M17 10a3 3 0 0 1 6 0v14.5a5.5 5.5 0 1 1-6 0z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
    <path d="M20 16v12" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinecap="round" />
  </svg>,
  <svg key="cal" width="40" height="40" viewBox="0 0 40 40">
    <path d="M9 19h22c-1 10-5.6 14-11 14S10 29 9 19z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
    <path d="M16 13c0-2 1.2-3.2 3-3.5M23 12c.5-1.8 1.8-2.8 3.5-2.6" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinecap="round" />
  </svg>,
  <svg key="sp" width="40" height="40" viewBox="0 0 40 40">
    <ellipse cx="15" cy="14.5" rx="4.5" ry="7" transform="rotate(-18 15 14.5)" fill="none" stroke="#E8E4DC" strokeWidth="2" />
    <ellipse cx="25" cy="25.5" rx="4.5" ry="7" transform="rotate(18 25 25.5)" fill="none" stroke="#E8E4DC" strokeWidth="2" />
  </svg>,
  <svg key="ds" width="40" height="40" viewBox="0 0 40 40">
    <path d="M20 32s-9-7.5-9-15a9 9 0 0 1 18 0c0 7.5-9 15-9 15z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
    <circle cx="20" cy="17" r="3" fill="none" stroke="#E8E4DC" strokeWidth="2" />
  </svg>,
  <svg key="ae" width="40" height="40" viewBox="0 0 40 40">
    <path d="M22 6L10 23h9l-1 11 12-17h-9l1-11z" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinejoin="round" />
  </svg>,
  <svg key="cm" width="40" height="40" viewBox="0 0 40 40">
    <circle cx="20" cy="13" r="5" fill="none" stroke="#E8E4DC" strokeWidth="2" />
    <path d="M11 32c0-5.5 4-9 9-9s9 3.5 9 9" fill="none" stroke="#E8E4DC" strokeWidth="2" strokeLinecap="round" />
  </svg>,
];
