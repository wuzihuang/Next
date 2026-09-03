# 手势所有权：识别即独占 (a recognized page drag owns the touch)

首页两页横滑（04B：方向锁、40% 宽或 300pt/s 翻页、共用 spring）是手写的 DragGesture，曾以 `simultaneousGesture` 与卡片热区并行，`allowsHitTesting(!swiping)` 闸门只在触摸落点时判定——从卡片上起手的拖动在抬指时仍触发卡片：燃料卡上左滑进了燃料详情而不是翻页（`NextBodyUITests/PagingCardDragTests` 红样）。裁决：采纳系统法则（UIKit `cancelsTouchesInView` / Android 拦截的共通语义）——翻页拖动一经识别，独占整条触摸直到抬指，其下所有热区收到取消；位移超过触控死区的触摸永远不是点按，无论抬指落在哪。

## Considered Options

- **原生 TabView(.page) / UIPageViewController**：系统免费送正确的取消语义，但 04B 的方向锁、翻页阈值、spring、无过滚全部要重写——弃。
- **维持 simultaneousGesture + swiping 闸门**：命中测试在触摸开始时判定，中途翻转取消不了已被按钮认领的触摸——本案已证明漏，弃。
- **只靠 `highPriorityGesture`**：把取消交给 SwiftUI 的手势仲裁。XCUITest 的拖动下成立，真机手指下不成立——从面板上起手的拖动抬指仍进了二级页。仲裁是别人的，不能只靠它，弃。

## 补充裁决 (2026-09-03)

死区规则落到热区自己身上：`HotZoneTap`（`Features/Shared/HotZoneTap.swift`，一个 `PrimitiveButtonStyle`）用 `DragGesture(minimumDistance: 0)` 接管每个热区的触摸，任一方向位移超过 10pt 即为整条触摸退掉点按（手指回到原位也不算），抬指时只有从未离开死区的触摸才触发。翻页拖动的识别门槛是 12pt，所以它识别到的触摸，点按已经退掉了——无论上层仲裁怎么判。首页两页上所有热区（带的两张卡、页二的 SLEEP / HRV、面板画布与其动作行、NOT COLLECTING 的 Turn it on、dock 提示的设置键）都用它；`highPriorityGesture` 和 `!swiping` 闸门保留，作为第二道。
