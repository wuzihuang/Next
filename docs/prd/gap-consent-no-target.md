# 补屏 · 同意屏与 NO TARGET

Mirrored from node `1F2A-0`. 「一屏是「什么都还没读」，一屏是「只有分母死了」」.

## A · 同意屏 What HOOP collects — 03 板 · 六屏变七屏 · 1 CHECKBOX · 1 BUTTON

Copy (verbatim, in `ConsentCopy`): eyebrow NOTHING READ YET · title *What HOOP collects* ·
lede *Nothing has been read yet — not from the band, not from Apple Health. This is the complete
list, and what each item is for.* · sections FROM APPLE HEALTH · READ ONLY / FROM THE BAND (heart
rate · HRV incl. raw RR · steps, distance, calories, intensity · sleep signals · body composition
14 · skin temperature) / FROM YOU (meals · voice · usage · band battery & firmware) · WHAT WE
DON'T TOUCH · WHAT WE NEVER DO · WHERE IT GOES · checkbox *I agree to let HOOP collect the health
data listed on this screen.* · the two closing paragraphs.

## B · NO TARGET 整屏 — 09 板 · 四块不是六块 · ONE ACTION

`‹ FUEL · TODAY` · NO TARGET · `——` KCAL TARGET · *Targets are built from your body weight.
Without it, HOOP can't…* · [Add a weigh-in] · *Type it in, or pull the latest from Apple Health.*
· LOGGED TODAY (kcal eaten, from N meals, PROTEIN/CARBS/FAT grams, *No targets to compare them to
yet.*) · THE BAND COUNTED (Steps · Distance · Active minutes · Burn `——` NEEDS YOUR WEIGHT) ·
WHAT A WEIGH-IN TURNS ON (four bullets, text only).

分拣: 照常渲染 = steps, distance, active minutes (真值，不依赖体重); 整段消失 = kcal target, macro
targets, bars/rings/percentages, Remaining, Energy gap.

## Edge cases

1 DECLINED · 不勾就是不同意，没有第二个按钮。返回箭头把人送回上一屏；onboarding 可以走完；落到首页时
显示屏不渲染任何 widget，所有卡片是 ——，手环保持配对但永不调用 startReadOriginData()。
2 WITHDRAWN · 关掉即时生效；/v1/turn 返 403 consent_withdrawn；显示屏原地降级成 NOT COLLECTING，不弹
Alert。撤回 ≠ 删除。
3 CONSENT VERSION BUMPED · "One more thing / HOOP wants to collect" — delta screen.
4 STALE WEIGH-IN · 目标照常渲染，永不因为过期而作废 (62 days is still a better denominator than none).
5 TARGET BUT NEVER LOGGED · TARGET 2,180 · EATEN —— · REMAINING —— (不是 2,180).

## Hard rules

01 同意屏在 HealthKit 弹窗之前、在第一次 readOriginData() / readHRVData() / startReadOriginData()
之前；02 板配对成功不构成取数许可 · 02 一个 checkbox 一个 Continue，不预勾、不折叠、不与
Terms/Privacy 合并 · 03 两阶段高光，任何一帧只有一个高光色 · 04 不上屏 ≠ 不披露 (skin temperature is
on the list) · 05 同意入库 consent_version · granted_at · text_sha256 · locale · 06 撤回 ≠ 删除，
两行入口 · 07 NO TARGET 只对从未填过体重的账号出现 · 08 缺分母时消失的是「条」不是「数」· 09 减法里
只要有一个减数是 ——，结果就是 —— · 10 Active minutes = 5 分钟点里 met ≥ 3 的点数 × 5 · 11
「填完之后会怎样」只允许文字.
