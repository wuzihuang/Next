# NextBody HOOP

The iOS app and Supabase backend for the HOOP band. One root (Home), five detail pages, and a panel that is the only place the product speaks.

## Language

**手势所有权 (gesture ownership)**:
One touch has exactly one owner for its whole life. Once the page drag is recognized, it owns the touch until the finger lifts; every control underneath is cancelled, not deferred.
_Avoid_: 手势冲突 (that is the symptom, not the rule), 并行手势

**翻页拖动 (page drag)**:
The horizontal drag that turns Home between its two pages. The axis locks on the first points of travel; a vertical touch never becomes a page drag.
_Avoid_: swipe, 横滑 (ambiguous about ownership)

**点按 (tap)**:
A touch that never moved beyond the touch slop and was claimed by no gesture. Only a tap may fire a hot zone.
_Avoid_: click, 点了卡片 (says the action, not the gesture kind)

**热区 (hot zone)**:
A card's whole surface as the one tap target — no second-level button inside a card. The strip's two cards and page two's instrument cards are hot zones.
_Avoid_: 按钮 (a card is not a button; it carries a hot zone)

**夜间 HRV (night HRV)**:
The night's RMSSD over the band's recorded sleep window. It belongs to the night (the SLEEP surface), not to a page-two instrument of its own. The sleep page's NIGHT HRV tile is its home; the HEART page does not repeat it.
_Avoid_: 睡眠 HRV as a second number, last-night HRV as its own vitals card, daytime RMSSD as a vitals instrument

**进餐反应 (Meal response)**:
A unitless optical index on page two. The card label is RESPONSE; the number is the latest point, as a deviation from this person's own daytime median. It is not a blood concentration and carries no mmol/L or /100.
_Avoid_: 血糖, 代谢压力, metabolic load, MEAL as the card label (that word belongs to fuel)

**夜间血氧 (overnight SpO2)**:
Automatic oxygen readings taken during the recorded night only: the night's mean, its minimum, and the curve on that night's clock. Not an apnea grade.
_Avoid_: 血氧 as a daytime, manual, or health-glance reading on the sleep page; 呼吸暂停 as a on-screen result

**睡眠页 (sleep page)**:
The second-level surface for last night. It prints staging, night HRV, and overnight SpO2 as measurements. It does not score the night.
_Avoid_: sleep report, sleep quality, 睡眠评分, RESTORATIVE as a badge

**健康账号 (health account)**:
个人健康历史的归属主体；相同的已验证邮箱对应同一个健康账号，登录方式本身不构成另一份健康身份。
_Avoid_: 把 Apple 登录、邮箱登录分别称为不同用户

**手环归属 (band ownership)**:
一只手环与一个健康账号之间的有效归属关系；第一版一个账号同时只拥有一只有效绑定手环，不支持临时共享。
_Avoid_: 蓝牙连接、手机配对

**手环转让 (band transfer)**:
手环归属从一个健康账号明确交接给另一个健康账号；转让前的健康历史仍属于原账号。
_Avoid_: 换账号、重新连接
