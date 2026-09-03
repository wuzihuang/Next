# 手势所有权：识别即独占 (a recognized page drag owns the touch)

首页两页横滑（04B：方向锁、40% 宽或 300pt/s 翻页、共用 spring）是手写的 DragGesture，曾以 `simultaneousGesture` 与卡片热区并行，`allowsHitTesting(!swiping)` 闸门只在触摸落点时判定——从卡片上起手的拖动在抬指时仍触发卡片：燃料卡上左滑进了燃料详情而不是翻页（`NextBodyUITests/PagingCardDragTests` 红样）。裁决：采纳系统法则（UIKit `cancelsTouchesInView` / Android 拦截的共通语义）——翻页拖动一经识别，独占整条触摸直到抬指，其下所有热区收到取消；位移超过触控死区的触摸永远不是点按，无论抬指落在哪。

## Considered Options

- **原生 TabView(.page) / UIPageViewController**：系统免费送正确的取消语义，但 04B 的方向锁、翻页阈值、spring、无过滚全部要重写——弃。
- **维持 simultaneousGesture + swiping 闸门**：命中测试在触摸开始时判定，中途翻转取消不了已被按钮认领的触摸——本案已证明漏，弃。
