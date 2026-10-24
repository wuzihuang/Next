package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.profile.SheetFrame
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.settingHour
import com.nextbody.hoop.ui.CardBlock
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale

/**
 * #28 · the night's own start and end, and the way to say the band got them wrong.
 *
 * A correction is an override, never an edit of the band's record. The window the band filed
 * stays underneath it, printed here, and CLEAR gives it back.
 */
@Composable
fun SleepWindowCard(night: SleepSummary, editable: Boolean = true, edit: () -> Unit) {
    CardBlock(
        title = L("SLEEP WINDOW"),
        trailing = if (night.isUserReported) L("ADDED BY YOU") else if (night.isCorrected) L("CORRECTED") else null,
        trailingTint = if (night.isCorrected) NB.lime1 else null,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val big = NBFont.dot(700, 24f).tracking(0.02f)
                Text(SleepWindowCard.clock(night.sleepStart), Modifier.alignBy(FirstBaseline), style = big, color = NB.text1)
                Text("→", Modifier.alignBy(FirstBaseline), style = NBFont.ui(400, 14f), color = NB.text3Prod)
                Text(SleepWindowCard.clock(night.wakeAt), Modifier.alignBy(FirstBaseline), style = big, color = NB.text1)
                Spacer(Modifier.weight(1f))
                if (editable) {
                    Text(L("CHANGE TIMES"), Modifier.alignBy(FirstBaseline).hotZoneTap(pressedScale = 1f) { edit() },
                        style = NBFont.dot(600, 11f).tracking(0.2f), color = NB.lime1, maxLines = 1)
                }
            }
            // Both windows are printed when they differ, because a corrected night is not a
            // measurement and must not read as one.
            Text(
                when {
                    night.isUserReported -> L("TIMES REPORTED BY YOU")
                    night.isCorrected -> L("BAND RECORDED %@ → %@", SleepWindowCard.clock(night.bandStart), SleepWindowCard.clock(night.bandEnd))
                    editable -> L("FROM THE BAND · EDIT IF IT IS WRONG")
                    else -> L("FROM THE BAND")
                },
                style = NBFont.ui(300, 12f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            )
            if (night.unstagedMinutes > 0) {
                Text(L("%@ WITHOUT STAGE READINGS", Fmt.duration(night.unstagedMinutes)),
                    style = NBFont.ui(300, 12f), color = NB.text3Prod)
            }
        }
    }
}

object SleepWindowCard {
    fun clock(at: Instant?): String = at?.let { Fmt.clock(it) } ?: Fmt.dash
}

/**
 * The two wheels themselves. A night is corrected through one control wherever the correction
 * started, so the same drag means the same thing in both.
 *
 * ⚠️ One wheel per row, full width — the same layout the iOS sheet settled on. Android has no
 * wheel date picker, so each row is an hour wheel and a minute wheel side by side, looping,
 * snapping, faded top and bottom the way a shortened iOS wheel is.
 */
@Composable
fun SleepWindowWheels(
    start: Instant,
    onStart: (Instant) -> Unit,
    end: Instant,
    onEnd: (Instant) -> Unit,
    wheelHeight: Dp = 150.dp,
    enabled: Boolean = true,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TimeWheel(L("FELL ASLEEP"), start, onStart, wheelHeight, enabled)
        TimeWheel(L("WOKE"), end, onEnd, wheelHeight, enabled)
    }
}

object SleepWindowWheels {
    /** `HH:MM` on the wearer's own clock — the only shape `correct_sleep_window` accepts. */
    fun hhmm(at: Instant): String {
        val z = at.atZone(currentZone())
        return String.format(Locale.ROOT, "%02d:%02d", z.hour, z.minute)
    }

    /** A wheel has to stand on some date; only its hour and minute are ever read back. */
    fun date(hhmm: String?, fallback: Instant = Instant.now()): Instant {
        val parts = (hhmm ?: "").split(":")
        if (parts.size != 2) return fallback
        val h = parts[0].toIntOrNull() ?: return fallback
        val m = parts[1].toIntOrNull() ?: return fallback
        if (h !in 0..23 || m !in 0..59) return fallback
        return runCatching { fallback.settingHour(h, m, 0) }.getOrDefault(fallback)
    }
}

private val wheelRow = 34.dp
private const val wheelLoops = 200

@Composable
private fun TimeWheel(label: String, value: Instant, onChange: (Instant) -> Unit, wheelHeight: Dp, enabled: Boolean) {
    val zoned = value.atZone(currentZone())
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onChange)
    Column(
        Modifier
            .fillMaxWidth()
            .background(NB.carbon4, RoundedCornerShape(NB.R.chip))
            .border(1.dp, NB.hairline, RoundedCornerShape(NB.R.chip))
            .padding(horizontal = 10.dp, vertical = 8.dp)
            .alpha(if (enabled) 1f else 0.5f),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(label, style = NBFont.ui(400, 11f).tracking(0.06f), color = NB.white.copy(alpha = 0.38f))
        Box(Modifier.fillMaxWidth().height(wheelHeight), contentAlignment = Alignment.Center) {
            // The selection band iOS draws behind the chosen row.
            Box(Modifier.fillMaxWidth().height(wheelRow).background(NB.white.copy(alpha = 0.08f), RoundedCornerShape(8.dp)))
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(wheelHeight)
                    // A shortened wheel is cut, not shrunk: fade its two edges.
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            Brush.verticalGradient(
                                0f to Color.Transparent, 0.22f to Color.Black,
                                0.78f to Color.Black, 1f to Color.Transparent,
                            ),
                            blendMode = BlendMode.DstIn,
                        )
                    },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                WheelColumn(24, zoned.hour, wheelHeight, enabled) { h ->
                    val z = current.atZone(currentZone())
                    if (h != z.hour) change(current.settingHour(h, z.minute, 0))
                }
                Text(":", style = NBFont.ui(400, 22f), color = NB.text1)
                WheelColumn(60, zoned.minute, wheelHeight, enabled) { m ->
                    val z = current.atZone(currentZone())
                    if (m != z.minute) change(current.settingHour(z.hour, m, 0))
                }
            }
        }
    }
}

@Composable
private fun WheelColumn(count: Int, selected: Int, wheelHeight: Dp, enabled: Boolean, onSelect: (Int) -> Unit) {
    val base = count * (wheelLoops / 2)
    val state: LazyListState = rememberLazyListState(initialFirstVisibleItemIndex = base + selected)
    val fling = rememberSnapFlingBehavior(state)
    val select by rememberUpdatedState(onSelect)
    val scope = rememberCoroutineScope()

    // The centred row once the wheel comes to rest.
    LaunchedEffect(state) {
        snapshotFlow { state.isScrollInProgress }
            .distinctUntilChanged()
            .collect { scrolling ->
                if (!scrolling) select(centred(state) % count)
            }
    }
    // A value set from outside (the sheet's first appearance) turns the wheel to it.
    LaunchedEffect(selected) {
        if (!state.isScrollInProgress && centred(state) % count != selected) {
            val now = centred(state)
            val target = now - (now % count) + selected
            state.scrollToItem(target)
        }
    }
    val pad = (wheelHeight - wheelRow) / 2
    LazyColumn(
        Modifier.width(64.dp).height(wheelHeight),
        state = state,
        flingBehavior = fling,
        userScrollEnabled = enabled,
        contentPadding = PaddingValues(vertical = pad),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        items(count * wheelLoops) { index ->
            val v = index % count
            Box(
                Modifier.height(wheelRow).fillMaxWidth().hotZoneTap(enabled = enabled, pressedScale = 1f) {
                    scope.launch { state.animateScrollToItem(index) }
                },
                contentAlignment = Alignment.Center,
            ) {
                Text(String.format(Locale.ROOT, "%02d", v), style = NBFont.ui(400, 22f), color = NB.text1,
                    textAlign = TextAlign.Center)
            }
        }
    }
}

private fun centred(state: LazyListState): Int {
    val info = state.layoutInfo
    val first = state.firstVisibleItemIndex
    val rowPx = info.visibleItemsInfo.firstOrNull()?.size ?: return first
    return if (state.firstVisibleItemScrollOffset > rowPx / 2) first + 1 else first
}

/**
 * Two wheels and an explicit save. A drag is not a correction: nothing is written until SAVE,
 * which is the same rule the AI path gets from its confirmation.
 */
@Composable
fun SleepWindowSheet(day: UserDay, night: SleepSummary?, close: () -> Unit) {
    var start by remember { mutableStateOf(night?.sleepStart ?: SleepWindowWheels.date("23:00", day.start)) }
    var end by remember { mutableStateOf(night?.wakeAt ?: SleepWindowWheels.date("07:00", day.start)) }
    var saving by remember { mutableStateOf(false) }
    var savedPending by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun run(work: suspend () -> Boolean) {
        if (saving) return
        saving = true
        failure = null
        scope.launch {
            try {
                val settled = work()
                saving = false
                if (settled) {
                    close()
                } else {
                    savedPending = true
                    failure = L("Saved. Your metrics will refresh after the next sync.")
                }
            } catch (e: Throwable) {
                failure = SleepCorrection.message(SleepCorrection.code(e))
                saving = false
            }
        }
    }

    Box(Modifier.background(NB.carbon2)) {
        SheetFrame(
            title = if (night == null) L("Add sleep") else L("Sleep times"),
            content = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L("The night filed under %@. Times are your own clock; a start after the end belongs to the evening before.", day.key),
                        style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f))
                    Text(L("Available measurements are filled from these times. Missing sleep stages and HRV remain unmeasured."),
                        style = NBFont.ui(300, 12.5f), color = NB.text3Prod)
                    SleepWindowWheels(start, { start = it }, end, { end = it }, enabled = !(saving || savedPending))
                    failure?.let {
                        Text(it, style = NBFont.ui(400, 12.5f).tracking(0.02f),
                            color = if (savedPending) NB.text3Prod else NB.ember1)
                    }
                    if (night?.isCorrected == true && night.isUserReported != true &&
                        night.bandStart != null && night.bandEnd != null) {
                        Text(L("Use the band's times"),
                            Modifier.hotZoneTap(enabled = !(saving || savedPending), pressedScale = 1f) {
                                run { SleepCorrection.clear(day, DataStore) }
                            },
                            style = NBFont.ui(400, 13f), color = NB.text3Prod)
                    }
                }
            },
            footer = {
                Box(Modifier.testTag("sleep.window.save")) {
                    LimePillButton(
                        title = if (savedPending) L("Done") else if (saving) L("Saving…") else L("Save"),
                        enabled = !saving,
                    ) {
                        if (savedPending) {
                            close()
                        } else {
                            run {
                                if (night == null) SleepCorrection.create(day, SleepWindowWheels.hhmm(start), SleepWindowWheels.hhmm(end), DataStore)
                                else SleepCorrection.save(day, SleepWindowWheels.hhmm(start), SleepWindowWheels.hhmm(end), DataStore)
                            }
                        }
                    }
                }
            },
        )
    }
}
