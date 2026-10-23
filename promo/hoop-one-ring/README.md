# hoop-one-ring — NEXTBODY HOOP, 13.6 s

Made with the onetake skill (github.com/feitangyuan/onetake) on 2026-10-22. One canvas, one camera, zero footage.
The product's own tokens (`app/NextBody/DesignSystem/Tokens.swift`) and faces (Doto, Jost, Inter Tight from
`app/NextBody/Resources/Fonts`) are the look; the numbers on screen are the product's (the training page screenshot:
12.4 / 21, aim 13.0–16.0, strength 14:00 +3.2, all day +9.2; sleep 7h 12m; sleep score 82).

## Concept (the one picked of three)

**One ring.** The band is a ring. The day is a ring of 96 fifteen-minute slots. The training load is a ring. The O
in NEXTBODY is a ring of dots. Nothing is replaced: the pip you open inside is on the band, the band is the dial the
day runs around, the day's number fills the same ring, the page is drawn around the ring that is already there, and
the ring folds into the wordmark.

The two not picked:

- **One dot is one measurement** — Doto's dot matrix as the material: a lime pixel on the wrist ticks, the ticks pile
  into a heart-rate envelope, the envelope's dots re-sort into the big 78, the 78 spills into the pixel moon and Mars,
  the dots write NEXTBODY. Rejected for this cut because onetake's own one-dot case already owns that picture.
- **One zoom from the wrist to the number** — inside the optical sensor's green LED, out through the wrist, through the
  phone glass, into the Home page, down into one card, back out to the lockup. A scale dive; clearing and pith already
  did it, and the app's screens are too dense to dive through without a hand.

Look: `look.json` — carbon ground #0B0B0D, lime #EFF65A as the one accent, violet #A78BFA for the night; Inter Tight
800 for the hits, Jost 500 for labels, Doto 700 for numbers and the wordmark (Doto 400 for the second line, as the
app's launch mark does).

## Beat sheet

| t | beat | what moves | what is still | carries into the next beat |
|---|---|---|---|---|
| 0.00–1.30 | the pip | its lub-dub (two heartbeats at 0.50 / 1.04) | the band's edge at 28× | the pip |
| 1.30–2.70 | pull out | 28× → 1.25× on a quintInOut; shake on the landing | — | the band (the pip is on it) |
| 2.70–3.30 | the band | — | dead still | the band |
| 3.30–5.54 | the day | the pip runs 00:00 → 20:40 along the band; each 15-min slot pops as it passes (violet night, lime strength, white day); three captions rise where they happened; the operator trails the pip | the band | the ring and the pip |
| 5.54–6.17 | the number | the pip stops at NOW (shake); the lime arc fills to 12.4 / 21 inside the band, the digits count up | the band | the ring with its number |
| 6.17–7.55 | hold | — | dead still, near silent | the ring |
| 7.55–8.60 | the page | 1.25× → 0.5×; the band thins and greys into the UI's track in place; the training page's rows rise around it; the phone's slab fades in | the ring's centre | the phone, the ring |
| 8.60–9.80 | hold | — | dead still, silent | — |
| 9.80–10.50 | hits | KNOW · YOUR · NUMBERS. — hard cuts, 0.23 s each (`__meta.cuts`) | — | (burst; the ring returns) |
| 10.50–11.10 | the fold | the ring of 96 dots shrinks and flies into the O's slot while N E X T B type at 28 ms a character; lands with impact and a shake, the glyph O takes over | — | the wordmark |
| 11.16–12.11 | the launch mark | D Y type; the lime pip pops after the word; BUILD YOUR NEXTBODY types | the wordmark | — |
| 12.11–13.60 | end | — | dead still, silent | — |

Shot lengths 0.23–2.24 s. Rests: 0–1.3 (but for the blinks), 2.7–3.3, 6.17–7.55, 8.6–9.8, 12.11–13.6.

## Reference numbers (pith-21s, the skill's own dark case — no user reference was supplied)

still 0.295 · low 0.426 · longest quiet 3.25 s · cuts in two bursts · peak 403 px/frame · median t80 0.67.

## Files

- `comp.html` — the composition (`?play`, `?t=6.4&hud`); `motion.js` from the skill; `look.js` / `fonts.js` generated
  (`look.py apply look.json comp.html`, `make_fonts.py`)
- `dump_events.py` → `events.json`; `score.py` → `sfx.wav` (synthetic palette, one room, no music)
- `probe/` — continuity and curves; `draft1.mp4` + `.render.json` — the 1080p30 draft with a 180° shutter
