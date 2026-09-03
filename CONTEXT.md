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
A card's whole surface as the one tap target — no second-level button inside a card. The strip's two cards and page two's SLEEP / HRV cards are hot zones.
_Avoid_: 按钮 (a card is not a button; it carries a hot zone)
