package com.nextbody.hoop.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/**
 * ADR-0001 · 手势所有权 · the other half of the rule, for the key that cannot wait.
 *
 * [hotZoneTap] settles a tap on lift-off, which is all a card ever needs. The dock's middle
 * key needs the opposite: it has to know the finger is down and still 200 ms into the touch,
 * while the touch is happening. The arbitration the ADR asks for:
 *   · finger still for [minimumDurationMs] → the press arms first and from then on consumes
 *     the touch, so the page drag (still waiting for its slop) never starts. The key owns it.
 *   · finger past the slop first → the press is dead for this touch; the page drag turns the
 *     page and nothing was recorded.
 *
 * @param onTouch finger down / finger gone. For the press dim only; a touch the page drag
 *   steals arrives here as gone.
 * @param onArm the threshold was crossed: this is where the mic goes up.
 * @param onMove travel since the finger went down, in screen dp, while armed. Slide-up-to-cancel.
 * @param onLift the armed press ended. `interrupted` is the system taking the touch away
 *   rather than the finger lifting — half a sentence is worse than none, so callers cancel.
 * @param onTap lift before the threshold, in place, not cancelled. Travel past
 *   [HotZoneTap.slop] retires it for the rest of the touch.
 * @param allowsQualifiedRelease STOP may settle a completed, stationary hold on lift. Recording
 *   controls must leave this false: starting on lift is too late.
 */
fun Modifier.pressHold(
    minimumDurationMs: Long = 200,
    allowsQualifiedRelease: Boolean = false,
    onTouch: (Boolean) -> Unit = {},
    onArm: () -> Unit = {},
    onMove: (DpOffset) -> Unit = {},
    onLift: (interrupted: Boolean) -> Unit = {},
    onTap: () -> Unit = {},
): Modifier = composed {
    val touch by rememberUpdatedState(onTouch)
    val arm by rememberUpdatedState(onArm)
    val move by rememberUpdatedState(onMove)
    val lift by rememberUpdatedState(onLift)
    val tap by rememberUpdatedState(onTap)
    val qualified by rememberUpdatedState(allowsQualifiedRelease)
    val holder = remember { arrayOfNulls<LayoutCoordinates>(1) }

    this
        .onGloballyPositioned { holder[0] = it }
        .pointerInput(minimumDurationMs) {
            val slop = HotZoneTap.slop.toPx()
            // Window coordinates: the key can grow under the finger while the press is live,
            // so its own space moves and cannot measure the travel.
            fun root(p: Offset): Offset = holder[0]?.takeIf { it.isAttached }?.localToRoot(p) ?: p

            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val origin = root(down.position)
                var touchReported = true
                var armed = false
                var finished = false
                touch(true)

                fun touchGone() {
                    if (touchReported) {
                        touchReported = false
                        touch(false)
                    }
                }

                try {
                    // Phase 1 · before the threshold.
                    var moved = false
                    var upChange: PointerInputChange? = null
                    var lost = false
                    withTimeoutOrNull(minimumDurationMs) {
                        while (true) {
                            val e = awaitPointerEvent()
                            val c = e.changes.firstOrNull { it.id == down.id }
                            if (c == null) { lost = true; return@withTimeoutOrNull }
                            if (!c.pressed) { upChange = c; return@withTimeoutOrNull }
                            if (c.isConsumed || (root(c.position) - origin).getDistance() > slop) {
                                moved = true; return@withTimeoutOrNull
                            }
                            val f = awaitPointerEvent(PointerEventPass.Final)
                            if (f.changes.any { it.id == down.id && it.isConsumed }) {
                                moved = true; return@withTimeoutOrNull
                            }
                        }
                    }

                    val up = upChange
                    when {
                        lost -> { touchGone(); finished = true }
                        up != null -> {
                            val elapsed = up.uptimeMillis - down.uptimeMillis
                            touchGone()
                            finished = true
                            if (!up.isConsumed && qualified && elapsed >= minimumDurationMs) {
                                arm(); lift(false)
                            } else if (!up.isConsumed) {
                                up.consume()
                                tap()
                            }
                        }
                        moved -> {
                            // Dead for this touch; the page drag may own it. The dim lifts now.
                            touchGone()
                            while (true) {
                                val e = awaitPointerEvent()
                                val c = e.changes.firstOrNull { it.id == down.id } ?: break
                                if (!c.pressed) break
                            }
                            finished = true
                        }
                        else -> {
                            // Phase 2 · armed: the key owns the touch.
                            armed = true
                            arm()
                            while (true) {
                                val e = awaitPointerEvent()
                                val c = e.changes.firstOrNull { it.id == down.id }
                                if (c == null) {
                                    touchGone(); finished = true; lift(true); break
                                }
                                c.consume()
                                if (!c.pressed) {
                                    touchGone(); finished = true; lift(false); break
                                }
                                val d = root(c.position) - origin
                                move(DpOffset((d.x / density).dp, (d.y / density).dp))
                            }
                        }
                    }
                } finally {
                    // Cancelled (the node left, or the system took the touch).
                    touchGone()
                    if (armed && !finished) lift(true)
                }
            }
        }
}
