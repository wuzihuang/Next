package com.nextbody.hoop.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs

/**
 * ADR-0001 · 手势所有权 · the 点按 rule, enforced at the hot zone itself.
 *
 * A hot zone fires on a tap only: a touch that never travelled past the dead zone. The first
 * 10 dp of travel in any direction retire the tap for the rest of the touch (even if the
 * finger wanders back), so a page drag — which recognises past its own slop — can only ever
 * recognise on a touch whose tap is already retired. A drag that started on a card never
 * settles as a tap when it lifts.
 *
 * Travel is measured in root (screen) coordinates: a card inside a scroll or pager moves with
 * the finger, so its local space cannot measure how far the finger went. A touch an ancestor
 * consumed (the scroll or the pager took it) is retired too, and a tap a nested hot zone took
 * is not also delivered to the outer one.
 */
object HotZoneTap {
    /** The dead zone — the platform's own: a scroll view starts panning at ~10. */
    val slop: Dp = 10.dp
}

/**
 * The whole-card tap target. Keeps the Button semantics (role + accessibility click);
 * only the touch handling is ours. Pressed: [pressedOpacity] / [pressedScale], eased 0.12 s.
 */
fun Modifier.hotZoneTap(
    enabled: Boolean = true,
    pressedOpacity: Float = 0.72f,
    pressedScale: Float = 0.985f,
    role: Role? = Role.Button,
    onClickLabel: String? = null,
    onClick: () -> Unit,
): Modifier = composed {
    var pressed by remember { mutableStateOf(false) }
    val current by rememberUpdatedState(onClick)
    val holder = remember { arrayOfNulls<LayoutCoordinates>(1) }
    val alpha by animateFloatAsState(if (pressed) pressedOpacity else 1f, tween(120, easing = SwiftEaseOut), label = "hz.alpha")
    val scale by animateFloatAsState(if (pressed) pressedScale else 1f, tween(120, easing = SwiftEaseOut), label = "hz.scale")

    this
        .semantics {
            if (role != null) this.role = role
            onClick(onClickLabel) { if (enabled) current(); enabled }
            if (!enabled) disabled()
        }
        .graphicsLayer {
            this.alpha = alpha
            scaleX = scale
            scaleY = scale
        }
        .onGloballyPositioned { holder[0] = it }
        .pointerInput(enabled) {
            if (!enabled) return@pointerInput
            val slop = HotZoneTap.slop.toPx()
            fun root(p: Offset): Offset = holder[0]?.takeIf { it.isAttached }?.localToRoot(p) ?: p
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val origin = root(down.position)
                var moved = false
                fun inside(p: Offset): Boolean {
                    val d = root(p) - origin
                    return abs(d.x) <= slop && abs(d.y) <= slop
                }
                pressed = true
                try {
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) {
                            val tap = !moved && !change.isConsumed && inside(change.position)
                            if (tap) {
                                change.consume()
                                pressed = false
                                current()
                            }
                            break
                        }
                        if (change.isConsumed || !inside(change.position)) moved = true
                        // An ancestor (scroll, pager, edge back) consumed the move: it owns the touch.
                        val final = awaitPointerEvent(PointerEventPass.Final)
                        if (final.changes.any { it.id == down.id && it.isConsumed }) moved = true
                        if (moved) pressed = false
                    }
                } finally {
                    pressed = false
                }
            }
        }
}
