# Design tokens · NEXTBODY-HOOP · 新版设计

Read off the Paper file with `get_tokens` while the server was still answering. This is the
palette, the type scale and the spacing/radius ladders exactly as the file defines them — the
「色彩」 half of criterion 1, in the repo rather than in a design tool that has to be running.

⚠️ Source of truth is still the Paper file. This is a mirror, and it can go stale: if a token is
changed there, change it here in the same commit. It exists because the file was unreachable for
an entire working session and every screen-board check stalled on that.

Fonts in use: **Inter Tight** (brand), **Jost** (UI), **Doto** (dot-matrix), System Sans, System Mono.

## Ground

| Token | Value |
|---|---|
| `--carbon` | `#0B0B0D` |
| `--carbon-deep` | `#0A0A0C` |
| `--carbon-2` | `#0D0D10` |
| `--carbon-3` | `#0D0D11` |
| `--carbon-4` | `#101014` |
| `--carbon-5` | `#111114` |
| `--smoke-key` | `#1B1B20` |
| `--led-off` | `#1A1A1F` |

## Text and rules

| Token | Value |
|---|---|
| `--white` / `--text-1` | `#FFFFFF` |
| `--text-2` | `rgb(255 255 255 / 60%)` |
| `--text-3` | `rgb(255 255 255 / 42%)` |
| `--text-3-prod` | `rgb(255 255 255 / 55%)` |
| `--hairline` | `rgb(255 255 255 / 8%)` |

## Domain ramps

| Token | Value | | Token | Value |
|---|---|---|---|---|
| `--cyan-pale` | `#CFFAFE` | | `--lime-pale` | `#D9F99D` |
| `--cyan-1` | `#22D3EE` | | `--lime-pip` | `#BEF264` |
| `--cyan-2` | `#16A3B8` | | `--lime-1` | `#EFF65A` |
| `--cyan-3` | `#0E7490` | | `--lime-2` | `#A3E635` |
| `--cyan-deep` | `#155E75` | | `--lime-mid` | `#65A30D` |
| `--blue-pale` | `#BAE6FD` | | `--lime-3` | `#4D7C0F` |
| `--blue-1` | `#38BDF8` | | `--violet-1` | `#A78BFA` |
| `--blue-2` | `#2563EB` | | `--violet-2` | `#8F9FE8` |
| `--blue-3` | `#1D4ED8` | | `--violet-3` | `#6D28D9` |
| `--blue-deep` | `#0B1E3F` | | `--violet-4` | `#4F46E5` |
| `--ember-pale` | `#FFE9B8` | | `--violet-pink` | `#D774B4` |
| `--ember-1` | `#F6A41C` | | `--run-1` | `#FB923C` |
| `--ember-2` | `#E05E10` | | `--run-2` | `#DC2626` |
| `--ember-3` | `#C2570C` | | `--accent-yellow` | `#F3E545` |
| `--ember-deep` | `#7C2D12` | | `--compare-amber` | `#D9A441` |

## State

| Token | Value |
|---|---|
| `--state-optimal-1` | `#A7F3D0` |
| `--state-optimal-2` | `#34D399` |
| `--state-optimal-3` | `#0F766E` |
| `--state-steady-2` | `#38BDF8` |
| `--state-caution-2` | `#F6A41C` |
| `--state-alert-1` | `#FECACA` |
| `--state-alert-2` | `#EF4444` |
| `--state-alert-3` | `#B91C1C` |
| `--film-yellow` | `#FDE047` |
| `--thermal-1` | `#E84393` |
| `--thermal-2` | `#F97316` |
| `--thermal-4` | `#FBBF24` |

## Type

`--font-ui` Jost · `--font-brand` Inter Tight · `--font-dot` Doto

| Size | | Size | |
|---|---|---|---|
| `--fs-tile-foot` | 9px | `--fs-unit` | 14px |
| `--fs-tile-label` | 10px | `--fs-imm-value` | 16px |
| `--fs-micro` | 11px | `--fs-card-title` | 20px |
| `--fs-eyebrow` | 11px | `--fs-title-lg` | 32px |
| `--fs-imm-label` | 11px | `--fs-hero-dot` | 64px |
| `--fs-sub` | 12.5px | | |
| `--fs-greet` | 13px | | |
| `--fs-cta` | 13.5px | | |
| `--fs-tile-value` | 14px | | |

Weights `--w-hair` 200 · `--w-light` 300 · `--w-book` 400 · `--w-med` 500 · `--w-bold` 700

Tracking `--ls-giant` −0.045em · `--ls-brand` −0.01em · `--ls-title` 0.01em · `--ls-cta` 0.15em ·
`--ls-eyebrow` 0.34em

Leading `--lh-tight` 100% · `--lh-snug` 140% · `--lh-body` 190% · `--lh-loose` 200%

## Spacing

`--sp-1` 3 · `--sp-2` 4 · `--sp-3` 6 · `--sp-4` 7 · `--sp-5` 8 · `--sp-6` 10 · `--sp-7` 12 ·
`--sp-8` 14 · `--sp-9` 16 · `--sp-10` 18 · `--sp-11` 22 · `--sp-12` 26 · `--sp-13` 28 ·
`--sp-14` 34 · `--sp-15` 40 · `--sp-16` 52 · `--sp-17` 74 · `--pad-glass` 20

## Radii

`--r-key` 9 · `--r-tile` 13 · `--r-inner` 14 · `--r-chip` 18 · `--r-spec` 22 · `--r-mat` 24 ·
`--r-card` 26 · `--r-aura` 28 · `--r-hero` 30 · `--r-phone` 34 · `--r-panel` 40 · `--r-pill` 999
