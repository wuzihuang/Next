# F5 · 合规、权限与无障碍 Compliance

Mirrored from the Paper board (node `1E1D-0`, 2174 × 8140) while the server was answering.
「合规不是免责声明，是十几处界面」— every line lands somewhere concrete: a plist key, a screen, a table.

**NOT IN V1** — 不弹 ATT（no data marked Used to Track You, no ad SDK, no ATTrackingManager）.

## Sec 01 · App Review — 七条指南

| Guideline | Demands | HOOP today | Gap |
|---|---|---|---|
| 4.8 Login | third-party login ⇒ equivalent option | Apple first, only solid white | met · 「等价」是视觉判断，不许把 Apple 折进 More options |
| 5.1.1(v) Deletion | in-app account deletion | 11 · DELETE ACCOUNT, 唯一红字, PERMANENT | ≤2 taps, no Safari |
| 5.1.1(i) Privacy policy | what/how/why/retention/withdraw | 缺 | three documents, see §05 |
| 5.1.3(i) Health | no ads/marketing/mining; disclose types | no ad or analytics SDK | policy must name HealthKit 四项 + BIA 十四项 |
| 5.1.3(ii) HealthKit | no fake writes; no PHI in iCloud | never writes back | ⚠️ local DB & export temp files `isExcludedFromBackup`; no iCloud capability |
| 2.5.1 Public APIs | HealthKit for health; public CoreBluetooth | met | `BatteryInfo.percent` only — no private symbols |
| 1.4.1 Physical harm | no phone-sensor BP/glucose/SpO2 claims | BIA/PPG are on the band | copy (§06) and SDK whitelist (§07) |

## Sec 02 · App Privacy — Used to Track You = NO everywhere

Health & Fitness → Health / Fitness · Contact → Email · Identifiers → User ID (Supabase uid) ·
Usage → Product Interaction (自建 analytics) · User Content → Photos (餐照, 30 days) — all
COLLECTED · LINKED · **NOT TRACKING**. Device ID (CBPeripheral UUID stays in Keychain), Audio
(never stored), Crash (no SDK) — NOT COLLECTED.

## Sec 03 · HealthKit — 只读，只四项，只弹一次

READ: `biologicalSex · dateOfBirth · height · bodyMass`. ⚠️ HK sex is four-state, SDK is two.
STRING: *"HOOP reads your sex, date of birth, height and weight from Health to set up your
baseline. It never writes to Health, and never shares this data."* — 两个 never 是承诺.
WRITE: 裁决 V1 不写回 (10S 的手动体重不回 Apple Health).
LAW: 读权限不可探测 — every cold start re-checks the four; denial is silent → manual four fields.

## Sec 04 · Permissions — 五个要申请的，两个坚决不申请的，一道年龄门

| Permission | Screen · key | If denied |
|---|---|---|
| Bluetooth | 02 · It's on · `NSBluetoothAlwaysUsageDescription` | stay on 02 EDGE 2, button → Open Settings |
| HealthKit read | 03 · after consent, at Sync | silently fall to manual |
| Camera | 05 · first photo tap · `NSCameraUsageDescription` | slot dims, "Camera is off in Settings" |
| Photo library | — not requested (`PHPickerViewController`) | — |
| Microphone | 05 · first hold-to-talk · `NSMicrophoneUsageDescription` | hold is a no-op, "Microphone is off in Settings" |
| Notifications | 13 primer · runtime, no plist key | 「昨夜」 shows in-panel on morning open; never re-ask |
| Location | — not requested (02 EDGE 3 is Android) | — |

**通知的裁决**: never on cold start. First morning after a night on the band, when a real 昨夜
is waiting: one in-app primer — *"Every morning HOOP tells you how last night went. That's the
only thing it will ever notify you about."* — with exactly two buttons **Not now / Turn on**.
Not now ≠ refusal (ask again next morning); the system dialog, once refused, is never shown again.

**年龄门 · 16**: judged on 03/02 「Looks right」, not live on the birthday wheel.

## Sec 05 · State & federal — 三份文档，四处界面

WA MHMDA (private right of action) / NV SB370 / CA CCPA-CPRA / CO·CT·VA·OR·TX / FTC HBNR.
Three documents, none substitutes for another: Privacy Policy · Consumer Health Data Privacy
Notice · Terms. Export = access right; delete = deletion right. 必须先拍板: is the meal text
sent to the model provider a "share with a third party" under MHMDA.

## Sec 06 · FDA general wellness — 禁用词表

| Allowed | Forbidden — never ship |
|---|---|
| "a direction, not a diagnosis" | diagnose / diagnosis / detect |
| "your seven-day trend" / "an estimate" | clinically validated / medical-grade / accurate to ±X% |
| "low confidence" / "not enough data yet" | normal / abnormal / normal range / out of range |
| "general wellness" / "healthy lifestyle" | disease / disorder / condition / any named illness |
| "This isn't medical advice." | treat / cure / prevent / manage your X |
| "Talk to a professional if you want to go further." (static) | "You should see a doctor." (value-triggered) |
| "body fat estimate" / "body composition scan" | "body fat measurement" / "BIA test result" |

## Sec 07 · SDK whitelist — SDK 给得出来，不代表我们敢渲染

| Capability | V1 |
|---|---|
| bloodPressure | 不调用、不渲染、不入库、不进导出 |
| spoH (SpO2) | Overnight automatic history only: stored in `oxygen_samples`, shown on the sleep page (mean / min / curve), fed to AI as `o2.night`. Daytime spot, health-glance, and vendor apnea grades stay DROP. The device auto-measure switch remains the collection gate. |
| bloodGlucose | May store vendor optical scalars in `response_samples`. May render only the unitless meal-response index on page two (RESPONSE). Must not export or prompt mmol/L / blood glucose / 血糖 / SPIKE. 1.4.1 still forbids blood-test claims. |
| ecgFunction | 不调用；HRV 走 readHRVData() |
| temperature | 不上屏、不入库；只作 Body Battery 隐藏输入 |
| heartRateAlarm | kept as the band's buzz switch; copy says "Buzz above / below" only |

## Sec 08 · Delete & export

立即硬删，无冷静期，one Edge Function, one transaction, 30 s timeout → fail + rollback.
Failure copy fixed: **"Couldn't finish. Nothing was deleted."** 删除边界到手环为止；备份 30 天
但永不回滚 (policy text, not screen). Export: one zip incl. raw 5-minute points, via
`UIActivityViewController` only.

## Sec 09 · Accessibility — WCAG 2.1 AA

- ⚠️ `--text-3` (42%) is 4.06:1 — **code never references it**; secondary text is `--text-3-prod` (55%).
- Lime 16.86:1 · amber 9.59:1 · red passes but 别再往深了调.
- Sentences ≥ 13px; 9–11px tokens are for tiles/eyebrows only.
- Colour is never the only carrier: every amber dot has a VoiceOver word ("Needs you").
- Touch targets: dock, plus key, settings rows measured; hitSlop makes up the difference.
- Ring = one element, "Training load 14.5 out of 21"; children hidden.
- Panel open ⇒ `accessibilityViewIsModal`; focus moves inside.
- Reduce Motion: ring fill, waves, dot-fall → duration 0, land on the final value; numbers stay.
- Dynamic Type: fixed px, `maxFontSizeMultiplier = 1.35`, allow to xLarge then freeze.
- Doto: numbers and all-caps labels only, never sentences; values ≥ 16px / weight ≥ 500.

## Hard rules C1–C11

C1 Used to Track You all NO · C2 HealthKit four read types only · C3 MHMDA consent is its own
screen: one checkbox, one Continue · C4 notification dialog once, only after the 13 primer's
Turn on · C5 age gate 16+ at Looks right · C6 SDK whitelist (HR, HRV, steps/cal/dist/MET, body
composition, overnight automatic SpO2, wrist optical meal response as RESPONSE, battery/firmware, six writable settings) · C7 every AI English sentence passes the
§06 list first, hit ⇒ discard, E_CLAIM, never sent back for rewrite; the list lives in DB,
cached 5 min · C8 delete = single-transaction hard delete, 30 s, fixed failure copy · C9 two
data exits only · C10 no `--text-3` in code · C11 Reduce Motion → 0 with numbers present;
Dynamic Type capped at 1.35.
