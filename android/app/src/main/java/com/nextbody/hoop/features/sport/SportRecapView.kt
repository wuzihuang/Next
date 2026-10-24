package com.nextbody.hoop.features.sport

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.SportRecapMath
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.band.TrainingSessionContribution
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.features.measure.MText
import com.nextbody.hoop.features.training.ZoneBar
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SportRecapStore
import com.nextbody.hoop.ui.CardBlock
import kotlinx.coroutines.launch
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The same saved record is shown immediately after stopping and from Training history. iOS
 * presents it as a sheet with an inline SESSION title and a DONE key; `close` dismisses it.
 */
@Composable
fun SportRecapView(recap: SportSessionRecap, close: () -> Unit) {
    val data = DataStore
    val contributions: List<Pair<UserDay, TrainingSessionContribution>> = run {
        val found = LinkedHashMap<UserDay, TrainingSessionContribution>()
        for (row in data.history + listOf(data.today)) {
            row.trainingSettlement?.session(recap.sessionID, row.day)?.let { found[row.day] = it }
        }
        found.entries.map { it.key to it.value }.sortedBy { it.first }
    }

    LaunchedEffect(recap.id) {
        if (Band.allowsSeed) return@LaunchedEffect
        // Refresh every day touched by a workout, including a midnight crossing.
        Repository.load(days = 2, endingAt = UserDay.containing(recap.endedAt), store = data)
    }

    Column(Modifier.fillMaxSize().background(NB.panelInk).semantics { testTag = "sport.recap" }) {
        // The inline navigation bar: SESSION centred, DONE on the right.
        Box(Modifier.fillMaxWidth().padding(top = 8.dp).height(44.dp)) {
            MText(L("SESSION"), NBFont.ui(600, 17f), NB.text1, Modifier.align(Alignment.Center))
            MText(L("DONE"), NBFont.ui(600, 17f), NB.lime1,
                Modifier.align(Alignment.CenterEnd).padding(end = 16.dp)
                    .clickable(remember { MutableInteractionSource() }, null) { close() })
        }
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            MText(recap.title, NBFont.ui(600, 24f), NB.text1)
            MText("${Fmt.clock(recap.startedAt)} → ${Fmt.clock(recap.endedAt)} · ${Fmt.duration(recap.seconds / 60)}",
                NBFont.ui(400, 12f), NB.text3Prod)
            Row(Modifier.fillMaxWidth()) {
                Stat("AVG HR", recap.avgHR?.toString() ?: Fmt.dash)
                Spacer(Modifier.width(24.dp))
                Spacer(Modifier.weight(1f))
                Stat("PEAK", recap.peakHR?.toString() ?: Fmt.dash)
                Spacer(Modifier.width(24.dp))
                Spacer(Modifier.weight(1f))
                Stat(if (recap.caloriesEstimated) "KCAL EST" else "ACTIVE KCAL",
                    if (recap.hasEnergy) (if (recap.caloriesEstimated) "≈" else "") + recap.kcal.roundToInt() else Fmt.dash)
            }
            val observedEnergy = recap.energyObservedSeconds
            if (recap.caloriesEstimated && observedEnergy != null) {
                MText(L("Active calories over %.0f observed seconds only. Resting energy and missing intervals are excluded.",
                    observedEnergy), NBFont.ui(400, 11f), NB.text3Prod)
            }
            CardBlock(title = L("HEART RATE"), trailing = "BPM") {
                SportRecapCurve(recap, Modifier.fillMaxWidth().height(140.dp))
                Row(Modifier.fillMaxWidth()) {
                    MText(Fmt.clock(recap.startedAt), NBFont.ui(400, 10f), NB.text3Prod)
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    MText(Fmt.clock(recap.endedAt), NBFont.ui(400, 10f), NB.text3Prod)
                }
                MText(L("Gaps have no heart-rate observations."), NBFont.ui(400, 11f), NB.text3Prod)
            }
            CardBlock(title = L("TIME IN EACH ZONE"), trailing = "") {
                for (index in 0 until 5) {
                    val minutes = recap.zoneMinutes.getOrNull(index) ?: 0.0
                    val observed = recap.observedSeconds ?: (recap.zoneMinutes.sum() * 60)
                    val share = if (observed > 0) minutes * 60 / observed else 0.0
                    ZoneBar(zone = "Z${index + 1}", fill = share, tint = if (index < 3) NB.lime1 else NB.ember1,
                        value = if (recap.hasZones) swiftFormat("%.1f MIN · %.0f%%", minutes, share * 100) else Fmt.dash)
                }
                MText(L(if (recap.restHR == null)
                    "Estimated maximum HR: Z1 50–60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥90%."
                    else "Heart-rate reserve: Z1 30–40%, Z2 40–55%, Z3 55–70%, Z4 70–85%, Z5 ≥85%."),
                    NBFont.ui(400, 11f), NB.text3Prod)
                MText(L("Shares use observed time. Below Z1 is excluded; gaps add no time."), NBFont.ui(400, 11f), NB.text3Prod)
            }
            MText(L(recap.conclusion), NBFont.ui(500, 14f), NB.text1)
            MText(L("Aerobic: Z1–3. Anaerobic: Z4–5. This describes recorded intensity."), NBFont.ui(400, 11f), NB.text3Prod)
            CardBlock(title = L("LOAD"), trailing = "") {
                if (contributions.isNotEmpty()) {
                    val dayFormat = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(AppLanguage.locale.javaLocale)
                    for ((day, value) in contributions) {
                        Row(Modifier.fillMaxWidth()) {
                            MText(dayFormat.format(day.date.atZone(currentZone())), NBFont.ui(400, 13f), NB.text1)
                            Spacer(Modifier.width(24.dp))
                            Spacer(Modifier.weight(1f))
                            MText(value.deltaText, NBFont.ui(400, 13f), NB.lime1)
                        }
                        MText(L(if (value.rawLoad == 0.0) "No measurable training contribution in the observed intervals."
                            else "Included in the day's settled training load."), NBFont.ui(400, 12f), NB.text3Prod)
                    }
                } else {
                    MText(L(if (recap.hasZones || recap.hasEnergy) "Session recorded. Its load will appear after sync."
                        else "No continuous sensor evidence. This session has no measured load."),
                        NBFont.ui(400, 12f), NB.text3Prod)
                }
                SportPublicationStatus()
            }
            Spacer(Modifier.height(ScreenMetrics.safeBottom))
        }
    }
}

@Composable
private fun Stat(title: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MText(L(title), NBFont.ui(400, 10f), NB.text3Prod)
        MText(value, NBFont.dot(700, 24f), NB.lime1)
    }
}

/** Upload / settlement state of the sport records, with RETRY when one failed. */
@Composable
fun SportPublicationStatus() {
    val records = SportRecapStore
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (records.updatingTraining) MText(L("UPDATING TRAINING"), NBFont.ui(400, 12f), NB.text3Prod)
        val error = records.errorLine ?: records.trainingError
        if (error != null) {
            MText(error, NBFont.ui(400, 12f), NB.ember1)
            MText(L("RETRY"), NBFont.ui(400, 12f), NB.lime1,
                Modifier.alpha(if (records.updatingTraining) 0.4f else 1f)
                    .clickable(remember { MutableInteractionSource() }, null, enabled = !records.updatingTraining) {
                        scope.launch { records.retry() }
                    })
        } else if (records.pendingCount > 0) {
            MText(L("Session saved on this phone. Waiting to upload."), NBFont.ui(400, 12f), NB.text3Prod)
        }
    }
}

@Composable
private fun SportRecapCurve(recap: SportSessionRecap, modifier: Modifier = Modifier) {
    val points = recap.curvePoints
    if (points.isNullOrEmpty()) {
        Column(modifier, horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
            MText(Fmt.dash, NBFont.dot(700, 24f), NB.text3Prod)
            MText(L("No heart-rate record."), NBFont.ui(400, 12f), NB.text3Prod)
        }
        return
    }
    val label = L("HEART RATE")
    Canvas(modifier.semantics { contentDescription = label }) {
        val low = max(0, (points.minOf { it.bpm }) - 10).toDouble()
        val high = (points.maxOf { it.bpm } + 10).toDouble()
        val duration = max(1.0, ChronoUnit.MILLIS.between(recap.startedAt, recap.endedAt) / 1000.0)
        fun at(beat: SportRecapMath.Beat): Offset {
            val fx = min(1.0, max(0.0, ChronoUnit.MILLIS.between(recap.startedAt, beat.at) / 1000.0 / duration))
            return Offset((fx * size.width).toFloat(), ((1 - (beat.bpm - low) / (high - low)) * size.height).toFloat())
        }
        var previous: SportRecapMath.Beat? = null
        for (beat in points) {
            val point = at(beat)
            val last = previous
            if (last != null && last.segment == beat.segment) {
                drawLine(NB.lime1, at(last), point, strokeWidth = 2 * density)
            }
            drawCircle(NB.lime1, radius = 1.5f * density, center = point)
            previous = beat
        }
    }
}
