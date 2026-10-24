package com.nextbody.hoop.features.weighin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.app.MeasureKind
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.RulerHaptics
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

/**
 * 14 · SCAN AGAIN 体重门 — the dial that stands in front of a body scan.
 * Reached only from the body page's text-state scan entry: the band reads fat against a weight,
 * so a scan with a stale one would only re-print the same table. The dial opens on the latest
 * weigh-in, snaps to 0.1 kg with ruler detents under the thumb, and the confirm button both
 * records the weigh-in and fires the scan — the sheet never asks for a second tap.
 */
@Composable
fun WeighInDialSheet(close: () -> Unit) {
    val data = DataStore
    val scope = rememberCoroutineScope()
    val metric = data.profile.usesMetric
    // The dial always starts from the latest recorded weigh-in — never from zero and never from
    // wherever a previous drag happened to stop.
    var kg by remember {
        mutableDoubleStateOf((data.weighIns.firstOrNull()?.weightKg ?: data.today.weightKg ?: 70.0).coerceIn(RANGE))
    }
    val shown = String.format(Locale.US, "%.1f", if (metric) kg else kg * 2.2046226)
    val unit = if (metric) "KG" else "LB"

    fun confirm() {
        Haptics.impact(ImpactStyle.Soft)
        val settled = kg
        scope.launch { Analytics.track("DIAL_SETTLE", mapOf("KG" to settled)) }
        data.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = settled,
            bodyFatPercent = null, source = MeasurementSource.measured, origin = WeighIn.Origin.manual))
        close()
        Router.setTakeover(Takeover.Measure(MeasureKind.bodyComposition))
    }

    Column(Modifier.fillMaxSize().background(NB.carbon2), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 22.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(L("BODY SCAN · ONE NUMBER FIRST"), style = NBFont.dot(600, 11f).tracking(0.22f), color = NB.white.copy(alpha = 0.42f))
            Text(L("Weigh-in first."), style = NBFont.brand(700, 26f).tracking(-0.01f), color = NB.text1)
            Text(L("The band reads you against a weight. Give it today's."), style = NBFont.ui(300, 13.5f).tracking(0.02f),
                color = NB.white.copy(alpha = 0.55f))
        }

        Row(Modifier.padding(top = 24.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(shown, style = NBFont.dot(700, 56f), color = NB.text1, modifier = Modifier.alignByBaseline())
            Text(unit, style = NBFont.dot(500, 14f), color = NB.white.copy(alpha = 0.4f), modifier = Modifier.alignByBaseline())
        }

        Ruler(kg, onKg = { kg = it }, modifier = Modifier.padding(top = 14.dp).fillMaxWidth().height(78.dp))

        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 10.dp)) {
            Text(L("LAST · %@", lastLabel(metric)), style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.white.copy(alpha = 0.42f),
                modifier = Modifier.weight(1f))
            Spacer(Modifier.width(24.dp)) // 8 + 8 + 8, as SwiftUI spaces around the Spacer
            Text(lastWhen(), style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.white.copy(alpha = 0.42f))
        }

        Spacer(Modifier.weight(1f))

        Box(
            Modifier
                .padding(start = 16.dp, end = 16.dp, bottom = 8.dp + ScreenMetrics.safeBottom)
                .fillMaxWidth()
                .height(48.dp)
                .background(NB.lime1, CircleShape)
                .hotZoneTap(pressedScale = 1f) { confirm() },
            contentAlignment = Alignment.Center,
        ) {
            Text(L("SCAN AT %@ %@", shown, unit), style = NBFont.ui(500, 13f).tracking(0.15f), color = NB.carbon, maxLines = 1)
        }
    }
}

/** 10S rule 03 · same hard range as the keypad: 20–300 kg. */
private val RANGE = 20.0..300.0
/** dp of ruler travel per kilogram of drag. */
private const val PTS_PER_KG = 90f

@Composable
private fun Ruler(kg: Double, onKg: (Double) -> Unit, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    val haptics = remember { RulerHaptics() }
    var lastTick by remember { mutableIntStateOf((kg * 10).roundToInt()) }
    val labelStyle = NBFont.dot(600, 10f).copy(letterSpacing = 1.sp, color = NB.white.copy(alpha = 0.5f))
    val current by androidx.compose.runtime.rememberUpdatedState(kg)

    Box(
        modifier
            // The fade at both ends: 58 of black-to-clear masking the ticks and the needle.
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
            .drawWithContent {
                drawContent()
                val fade = 58.dp.toPx()
                drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.Black), startX = 0f, endX = fade),
                    size = Size(fade, size.height), blendMode = BlendMode.DstIn)
                drawRect(Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = size.width - fade, endX = size.width),
                    topLeft = Offset(size.width - fade, 0f), size = Size(fade, size.height), blendMode = BlendMode.DstIn)
            }
            .pointerInput(Unit) {
                val perKg = PTS_PER_KG.dp.toPx()
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    down.consume()
                    val from = current
                    haptics.prepare()
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        change.consume()
                        val dx = change.position.x - down.position.x
                        val raw = from - dx / perKg
                        val next = raw.coerceIn(RANGE)
                        val snapped = (next * 10).roundToInt() / 10.0
                        onKg(snapped)
                        val tick = (snapped * 10).roundToInt()
                        if (tick != lastTick) {
                            haptics.tick(mark(lastTick, tick))
                            lastTick = tick
                        }
                        if (raw != next) haptics.edge()
                    }
                    haptics.end()
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val mid = size.width / 2
            val k = 1.dp.toPx()
            // ±5 kg of ticks around the needle; anything further fades at the edges anyway.
            val lo = ((kg - 5) * 10).toInt()
            val hi = ((kg + 5) * 10).toInt()
            for (t in lo..hi) {
                val v = t / 10.0
                val x = mid + ((v - kg) * PTS_PER_KG).toFloat() * k
                if (x <= -4 * k || x >= size.width + 4 * k) continue
                val major = t % 10 == 0
                val half = !major && t % 5 == 0
                val h = (if (major) 20f else if (half) 13f else 8f) * k
                val op = if (major) 0.55f else if (half) 0.34f else 0.18f
                drawRect(Color.White.copy(alpha = op), Offset(x - 0.75f * k, 34f * k - h), Size(1.5f * k, h))
                if (major) {
                    val layout = measurer.measure(String.format(Locale.US, "%.0f", v), labelStyle)
                    drawText(layout, topLeft = Offset(x - layout.size.width / 2f, 68f * k - layout.size.height / 2f))
                }
            }
        }
        // The needle, with a one-tick ghost trail — the dial was caught mid-settle.
        Box(Modifier.align(Alignment.TopCenter).offset(x = (-7).dp).size(2.dp, 30.dp).background(NB.lime1.copy(alpha = 0.22f)))
        Box(Modifier.align(Alignment.TopCenter).offset(x = 7.dp).size(2.dp, 30.dp).background(NB.lime1.copy(alpha = 0.1f)))
        Box(Modifier.align(Alignment.TopCenter).size(2.dp, 30.dp).background(NB.lime1))
        Box(Modifier.align(Alignment.TopCenter).size(5.dp).background(NB.lime1, CircleShape))
    }
}

/**
 * The heaviest detent between two ticks, so a fast drag across a whole kilogram still feels the
 * notch even when the minor clicks around it were skipped.
 */
private fun mark(from: Int, to: Int): RulerHaptics.Mark {
    val crossed = if (from < to) (from + 1)..to else to..(from - 1)
    if (crossed.any { it % 10 == 0 }) return RulerHaptics.Mark.Major
    if (crossed.any { it % 5 == 0 }) return RulerHaptics.Mark.Half
    return RulerHaptics.Mark.Minor
}

private fun lastLabel(metric: Boolean): String {
    val v = DataStore.weighIns.firstOrNull()?.weightKg ?: DataStore.today.weightKg
    return if (metric) Fmt.kg(v) + " KG" else Fmt.kg(v?.let { it * 2.2046226 }) + " LB"
}

private fun lastWhen(): String {
    val at = DataStore.weighIns.firstOrNull()?.date ?: return L("NEVER")
    val days = Duration.between(at, Instant.now()).toDays()
    if (days <= 0) return L("TODAY")
    if (days == 1L) return L("YESTERDAY")
    return L("%d DAYS AGO", days.toInt())
}
