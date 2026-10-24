package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SleepContributor
import com.nextbody.hoop.model.SleepScore
import com.nextbody.hoop.model.SleepScoreGroup
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import java.time.ZoneId
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// ADR 0008 · the sleep board's three windows.
//
// The windows are **rolling** — the last 1, 7 and 30 nights — not calendar weeks and months.
// A natural week collapses to one bar every Monday morning, which reads as data loss rather
// than as a Monday; and the data layer counts backwards from `user_day` anyway.
//
// ⚠️ RESPONSE now carries the same three pills (ADR 0012). Sleep still medians a night;
// RESPONSE means a week.

/**
 * ADR 0008 · the score's four bands. Only the numeral is tinted — the SLEEP card keeps
 * `NB.violet1` for its label, its tag and its strip.
 */
val SleepScore.tint: Color
    get() {
        if (usesContributors) return SleepContributorRow.tint(score.toDouble())
        return when {
            score >= 80 -> NB.optimal2
            score >= 60 -> NB.violet1
            score >= 40 -> NB.compareAmber
            else -> NB.ember1
        }
    }

/** One slot on the multi-night chart: the day it belongs to and the score it settled, if any. */
data class SleepNightSlot(val day: UserDay, val score: SleepScore?) {
    val id: String get() = day.key
}

/**
 * Everything the week and month windows print, reduced from the slots once. Medians, not
 * means, throughout: one two-hour night drags a mean far enough to be read as a bad week.
 */
class SleepWindowSummary(val slots: List<SleepNightSlot>) {
    val recorded: Int
    val score: Int?
    val weakest: SleepScoreGroup?
    val durationMinutes: Int?
    val deepPercent: Double?
    val lightPercent: Double?
    val remPercent: Double?
    val bedOffset: Double?
    val wakes: Double?

    init {
        val scored = slots.mapNotNull { it.score }
        recorded = scored.size
        score = median(scored.map { it.score.toDouble() })?.roundedInt()
        // The one thing a median score cannot say by itself: which part is dragging.
        weakest = SleepScoreMath.weakest(SleepScoreGroup.entries.map { group ->
            group to scored.mapNotNull { it.value(group)?.toDouble() }
        })
        fun input(key: String): Double? = median(scored.mapNotNull { it.inputs[key] })
        durationMinutes = input("duration_min")?.roundedInt()
        deepPercent = input("deep_pct")
        lightPercent = input("light_pct")
        remPercent = input("rem_pct")
        bedOffset = input("bed_offset")
        wakes = input("wakes")
    }

    val scores: List<SleepScore> get() = slots.mapNotNull { it.score }

    val contributorScores: List<SleepScore> get() = scores.filter { it.usesContributors }

    fun groupMedian(group: SleepScoreGroup): Int? =
        median(scores.mapNotNull { it.value(group)?.toDouble() })?.roundedInt()

    /** `bed_offset` is minutes past 18:00 local. */
    val bedClock: String? get() = bedOffset?.let { SleepScoreMath.bedClock(it) }

    /** Stage proportions across the window, renormalised over the stages that were measured.
     *  REM drops out entirely on a run of nights the band filed no stage line for. */
    val bands: List<VitalsSplit.Band>
        get() {
            val raw = mutableListOf<Triple<String, Color, Double>>()
            deepPercent?.let { raw.add(Triple(L("Deep"), NB.violet1, it)) }
            lightPercent?.let { raw.add(Triple(L("Light"), NB.violet2, it)) }
            remPercent?.let { if (it > 0) raw.add(Triple(L("REM"), NB.blue1, it)) }
            if (raw.sumOf { it.third } <= 0) return emptyList()
            val shares = SleepScoreMath.renormalised(raw.map { it.third })
            return raw.zip(shares).map { (entry, share) ->
                VitalsSplit.Band(entry.first, entry.second, share, "${share.roundedInt()}%")
            }
        }

    companion object {
        fun median(values: List<Double>): Double? = SleepScoreMath.median(values)
    }
}

private fun dayOfMonth(at: Instant): Int = at.atZone(currentZone()).dayOfMonth

// MARK: - the chart

/** A column that sits on the field's floor, or a dotted full-height slot when there is none. */
@Composable
private fun BarSlot(width: Dp, height: Dp, radius: Dp, fill: Color?, fillHeight: Dp) {
    Box(Modifier.size(width, height), contentAlignment = Alignment.BottomCenter) {
        if (fill == null) {
            DottedSlot(radius, Modifier.fillMaxSize())
        } else {
            Box(Modifier.fillMaxWidth().height(fillHeight).background(fill, RoundedCornerShape(radius)))
        }
    }
}

/**
 * One bar a night, height by score, coloured by the score's own band. A night with no record
 * is a dotted slot at full height: the reader has to be able to see *which* night is missing.
 */
@Composable
fun SleepScoreBars(slots: List<SleepNightSlot>, tint: Color = NB.violet1, height: Dp = 160.dp) {
    val ranges = VitalsProbeMath.equalSlots(slots.size)
    val probeBins = slots.zip(ranges).map { (slot, range) ->
        val clock = "${Fmt.weekday(slot.day.date)} ${dayOfMonth(slot.day.date)}"
        val score = slot.score
        if (score != null) {
            VitalsProbeMath.Bin(range.start, range.end, 1 - score.score / 100.0,
                VitalsProbeCopy.line(clock, score.score.toString()))
        } else {
            VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
        }
    }
    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        accessibilityTitle = L("SLEEP SCORE BY NIGHT"),
        accessibilityName = "vitals.probe.score",
    ) { _ ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
                val count = max(slots.size, 1)
                val spacing = if (slots.size > 10) 2.dp else 6.dp
                val width = max(2f, (maxWidth.value - spacing.value * (count - 1)) / count).dp
                // ⚠️ Capped for the week window, where a slot is 38pt and half of that would
                // read as a pill rather than a column.
                val radius = min(width.value / 2, 6f).dp
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(spacing),
                    verticalAlignment = Alignment.Bottom) {
                    slots.forEach { slot ->
                        val score = slot.score
                        BarSlot(width, height, radius, score?.tint,
                            max(radius.value * 2, height.value * score?.score.let { (it ?: 0) / 100f }).dp)
                    }
                }
            }
            VitalsScaleRail(listOf("100", "50", "0"), tint)
        }
    }
}

object SleepScoreBars {
    /** What the colours mean, said under the field instead of keyed in it. */
    @Composable
    fun Legend() {
        VitalsChartLegend(
            items = listOf(
                VitalsChartLegend.Item(L("80+"), NB.optimal2),
                VitalsChartLegend.Item(L("60–79"), NB.violet1),
                VitalsChartLegend.Item(L("40–59"), NB.compareAmber),
                VitalsChartLegend.Item(L("UNDER 40"), NB.ember1),
            ),
            trailing = L("DOTTED · NO SETTLED SCORE"),
            trailingTint = NB.white.copy(alpha = 0.45f),
        )
    }
}

// MARK: - the breakdown

/**
 * ADR 0008 · the score explains itself on the next screenful, not five cards down. Four rows,
 * one per group, each carrying its weight and how much of the group it actually got to see.
 */
@Composable
fun SleepScoreBreakdown(score: SleepScore) {
    if (score.usesContributors) {
        SleepContributorBreakdown(score)
        return
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        SleepScoreGroup.entries.forEach { BreakdownRow(score, it) }
        FitText(
            L(if (score.inputs["duration_score_cap"] == null)
                "WEIGHTS ARE SHARES OF THIS SCORE; MISSING GROUPS ARE EXCLUDED"
            else "WEIGHTS APPLY BEFORE THE DURATION LIMIT; MISSING GROUPS ARE EXCLUDED"),
            NBFont.dot(500, 9f).tracking(0.06f), NB.text3Prod,
            Modifier.padding(top = 2.dp), maxLines = Int.MAX_VALUE,
        )
        score.appliedDurationCap?.let { cap ->
            FitText(L("SHORT SLEEP · SCORE CAPPED AT %d", cap), NBFont.dot(500, 9f).tracking(0.06f),
                NB.compareAmber, Modifier.testTag("sleep.durationCap"), maxLines = Int.MAX_VALUE)
        }
        SleepScoreCalibration(score)
    }
}

@Composable
private fun BreakdownRow(score: SleepScore, group: SleepScoreGroup) {
    val value = score.value(group)
    val present = group.memberKeys.count { score.inputs[it] != null }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            FitText(group.title, NBFont.ui(500, 10f).tracking(0.14f), NB.text3Prod, Modifier.width(84.dp))
            BoxWithConstraints(Modifier.weight(1f).height(6.dp)) {
                Box(Modifier.fillMaxSize().background(NB.barTrack, CircleShape))
                if (value != null) {
                    Box(Modifier.width(max(2f, maxWidth.value * value / 100f).dp).fillMaxHeight()
                        .background(NB.violet1, CircleShape))
                }
            }
            Text(value?.toString() ?: Fmt.dash, Modifier.width(26.dp), style = NBFont.dot(700, 12f),
                color = if (value == null) NB.text3Prod else NB.text1, textAlign = TextAlign.End, maxLines = 1)
            FitText(breakdownNote(score, group, value), NBFont.dot(500, 9f).tracking(0.05f), NB.text3Prod,
                Modifier.width(74.dp), minScale = 0.75f, align = TextAlign.End)
        }
        // A group name alone says nothing — the members print with what was measured, and a
        // member the night did not have prints ——.
        Text(SleepInputLabel.line(group, score.inputs), Modifier.padding(start = 92.dp),
            style = NBFont.dot(500, 9f).tracking(0.05f), color = NB.white.copy(alpha = 0.34f), maxLines = 2)
        if (value != null && present < group.memberKeys.size) {
            Text(L("%d OF %d INPUTS", present, group.memberKeys.size), Modifier.padding(start = 92.dp),
                style = NBFont.dot(500, 9f), color = NB.text3Prod)
        }
    }
}

/** A group that scored on fewer inputs than it has says so. */
private fun breakdownNote(score: SleepScore, group: SleepScoreGroup, value: Int?): String {
    if (value == null) {
        if (group != SleepScoreGroup.regularity) return L("NOT SCORED")
        if (score.inputs["bed_offset"] == null) return L("NO BEDTIME RECORDED")
        // The baseline exists from the third prior night, so the note counts up to it.
        return L("%d / %d NIGHTS", (score.inputs["baseline_bed_nights"] ?: 0.0).toInt(),
            SleepScoreMath.regularityBaselineNights)
    }
    return score.effectiveWeight(group)?.let { L("WEIGHT %.1f%%", it) } ?: Fmt.dash
}

fun SleepScore.effectiveWeight(group: SleepScoreGroup): Double? {
    if (usesContributors) return null
    val groups = SleepScoreGroup.entries
    val weights = SleepScoreMath.effectiveWeights(
        values = groups.map { value(it)?.toDouble() },
        weights = groups.map { g ->
            val weight = inputs["weight_${g.raw}"]
            if (weight == null || !weight.isFinite() || weight <= 0) g.weight.toDouble() else weight
        },
    )
    val index = groups.indexOf(group)
    if (index < 0) return null
    return weights[index]
}

val SleepScore.appliedDurationCap: Int?
    get() {
        if (inputs["duration_cap_applied"] != 1.0) return null
        val cap = inputs["duration_score_cap"] ?: return null
        if (!cap.isFinite() || cap !in 0.0..100.0) return null
        return cap.roundedInt()
    }

@Composable
fun SleepScoreCalibration(score: SleepScore) {
    val individual = listOf("hrv" to L("HRV"), "rhr" to L("RESTING")).mapNotNull { (key, title) ->
        val weight = score.inputs["${key}_personal_weight"] ?: return@mapNotNull null
        if (weight >= 1) return@mapNotNull null
        val nights = (score.inputs["baseline_${key}_nights"] ?: 0.0).toInt()
        L("%@ BASELINE · %d NIGHTS · %.0f%% PERSONAL", title, nights, weight * 100)
    }
    val lines = when {
        score.inputs["hrv_personal_weight"] != null || score.inputs["rhr_personal_weight"] != null -> individual
        !score.isCalibrating -> emptyList()
        else -> listOf(L("BASELINE LEARNING · %d NIGHTS · %.0f%% PERSONAL",
            (score.inputs["baseline_nights"] ?: 0.0).toInt(), score.personalWeight * 100))
    }
    lines.forEach { Text(it, style = NBFont.dot(500, 9f), color = NB.text3Prod) }
}

@Composable
fun SleepScoreCoverage(score: SleepScore) {
    fun coverageDetail(key: String): String {
        val parts = mutableListOf<String>()
        score.inputs["${key}_sample_count"]?.let { parts.add(L("%d READINGS", it.toInt())) }
        score.inputs["${key}_expected_minutes"]?.let { parts.add(L("RECORDED SLEEP %@", Fmt.duration(it.roundedInt()))) }
        score.inputs["${key}_longest_gap_min"]?.let { parts.add(L("LONGEST GAP %@", Fmt.duration(it.roundedInt()))) }
        return if (parts.isEmpty()) L("THIS SCORE HAS NO COVERAGE DETAILS") else parts.joinToString(" · ")
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf("hrv", "rhr", "spo2", "respiration").forEach { key ->
            val title = SleepInputLabel.title(if (key == "hrv") "hrv_ms" else if (key == "spo2") "spo2_min" else key)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(Modifier.fillMaxWidth()) {
                    Text(title, style = NBFont.dot(600, 10f), color = NB.text3Prod)
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    Text(score.inputs["${key}_coverage"]?.let { L("%.1f%% OF SLEEP", it * 100) }
                        ?: L("COVERAGE NOT AVAILABLE"), style = NBFont.dot(600, 10f), color = NB.text1)
                }
                Text(coverageDetail(key), style = NBFont.dot(500, 9f), color = NB.text3Prod)
            }
        }
        Text(L("ONLY MEASURED PORTIONS CONTRIBUTE; GAPS ARE NOT TREATED AS NORMAL"),
            style = NBFont.dot(500, 9f), color = NB.text3Prod)
    }
}

/** Group medians explain a window without pretending their weighted sum is its median total. */
@Composable
fun SleepWindowBreakdown(summary: SleepWindowSummary) {
    if (summary.contributorScores.isNotEmpty()) {
        SleepContributorWindow(summary)
        return
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SleepScoreGroup.entries.forEach { group ->
            val scored = summary.scores.filter { it.value(group) != null }
            val complete = scored.count { s -> group.memberKeys.all { s.inputs[it] != null } }
            val weights = scored.mapNotNull { it.effectiveWeight(group) }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(group.title, style = NBFont.ui(500, 10f), color = NB.text3Prod)
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    Text(summary.groupMedian(group)?.toString() ?: Fmt.dash, style = NBFont.dot(700, 14f), color = NB.violet1)
                }
                Text(L("SCORED %d OF %d NIGHTS · COMPLETE INPUTS %d", scored.size, summary.slots.size, complete),
                    style = NBFont.dot(500, 9f), color = NB.text3Prod)
                val low = weights.minOrNull()
                val high = weights.maxOrNull()
                if (low != null && high != null) {
                    Text(if (low == high) L("WEIGHT %.1f%%", low) else L("WEIGHT %.1f–%.1f%% BY NIGHT", low, high),
                        style = NBFont.dot(500, 9f), color = NB.text3Prod)
                }
            }
        }
        val calibrating = summary.scores.count { s ->
            (s.inputs["hrv_personal_weight"] ?: s.personalWeight) < 1 ||
                (s.inputs["rhr_personal_weight"] ?: s.personalWeight) < 1
        }
        Text(L("%d NIGHTS STILL LEARNING PERSONAL BASELINES", calibrating), style = NBFont.dot(500, 9f), color = NB.text3Prod)
        Text(L("GROUP MEDIANS ARE SHOWN SEPARATELY; THE TOTAL IS THE MEDIAN OF NIGHTLY SCORES"),
            style = NBFont.dot(500, 9f), color = NB.text3Prod)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SleepContributorBreakdown(score: SleepScore) {
    var selected by remember { mutableStateOf<SleepContributor?>(null) }
    var showsMethod by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        SleepContributor.entries.forEach { contributor ->
            Box(Modifier.testTag("sleep.contributor.${contributor.raw}")
                .hotZoneTap(pressedScale = 1f) { selected = contributor }) {
                SleepContributorRow(contributor.title, contributorMeasured(score, contributor),
                    score.contributorScore(contributor), showsChevron = true)
            }
        }
        score.appliedDurationCap?.let { cap ->
            Text(L("SHORT SLEEP · SCORE CAPPED AT %d", cap), Modifier.testTag("sleep.durationCap"),
                style = NBFont.dot(500, 10f), color = NB.compareAmber)
        }
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).testTag("sleep.scoringInfo")
                .hotZoneTap(pressedScale = 1f) { showsMethod = true },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(L("ABOUT THIS SLEEP SCORE"), style = NBFont.ui(500, 11f), color = NB.text3Prod)
            Spacer(Modifier.width(24.dp))
            Spacer(Modifier.weight(1f))
            InfoGlyph(NB.text3Prod)
        }
    }

    selected?.let { contributor ->
        ScoreSheet(contributor.title, onClose = { selected = null }) {
            Text(contributorMeasured(score, contributor, detailed = true), style = NBFont.dot(700, 28f), color = NB.white)
            score.contributorScore(contributor)?.let { value ->
                Row(Modifier.fillMaxWidth()) {
                    Text(SleepContributor.rating(value), style = NBFont.dot(600, 12f), color = SleepContributorRow.tint(value))
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    Text(L("%.0f OUT OF 100", value), style = NBFont.dot(600, 12f), color = SleepContributorRow.tint(value))
                }
            }
            Text(contributor.explanation, style = NBFont.ui(400, 15f), color = NB.text2)
            Text(score.contributorWeight(contributor)?.let { L("WEIGHT %.1f%%", it) }
                ?: L("NOT MEASURED · EXCLUDED FROM SCORE"), style = NBFont.dot(500, 11f), color = NB.text3Prod)
        }
    }
    if (showsMethod) {
        ScoreSheet(L("ABOUT THIS SLEEP SCORE"), onClose = { showsMethod = false }) {
            Text(L("NEXTBODY scoring inspired by Oura's public contributors, not Oura's proprietary formula. Missing factors are excluded and remaining weights are normalized."),
                style = NBFont.ui(400, 14f), color = NB.text2)
            SleepContributorCoverage(score)
        }
    }
}

private fun contributorMeasured(score: SleepScore, contributor: SleepContributor, detailed: Boolean = false): String {
    fun number(key: String): Double? {
        val value = score.inputs[key] ?: return null
        return if (value.isFinite() && value >= 0 && value <= 100_000) value else null
    }
    fun duration(key: String): String = number(key)?.let { Fmt.duration(it.roundedInt()) } ?: Fmt.dash
    return when (contributor) {
        SleepContributor.totalSleep -> duration("duration_min")
        SleepContributor.efficiency -> number("efficiency_pct")?.let { swiftFormat("%.0f%%", it) } ?: L("NOT MEASURED")
        SleepContributor.restfulness -> score.contributorScore(contributor)?.let { SleepContributor.rating(it) } ?: L("NOT MEASURED")
        SleepContributor.rem, SleepContributor.deep -> {
            val key = contributor.raw
            if (number("${key}_min") == null) L("NOT MEASURED")
            else duration("${key}_min") + (number("${key}_pct")?.let { swiftFormat(" · %.0f%%", it) } ?: "")
        }
        SleepContributor.latency -> L("NOT MEASURED")
        SleepContributor.timing -> {
            if (!detailed) score.contributorScore(contributor)?.let { SleepContributor.rating(it) } ?: L("NOT MEASURED")
            else {
                val midpoint = number("midpoint_min")
                if (midpoint == null || midpoint >= 1440) L("NOT MEASURED")
                else L("MIDPOINT %@", SleepScoreMath.bedClock(midpoint - 1080))
            }
        }
    }
}

/** The factor and method sheets: medium-then-large detents, carbon ground, dark. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScoreSheet(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = state,
        containerColor = NB.carbon,
        contentColor = NB.text1,
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title, Modifier.weight(1f).padding(top = 8.dp, end = 12.dp), style = NBFont.ui(600, 21f), color = NB.text1)
                Box(
                    Modifier.size(44.dp).testTag("sleep.factor.close")
                        .clearAndSetSemantics { contentDescription = L("CLOSE") }
                        .hotZoneTap(pressedScale = 1f) { onClose() },
                    contentAlignment = Alignment.Center,
                ) { XGlyph(NB.text2) }
            }
            content()
        }
    }
}

/** SF Symbol `xmark` at 15pt medium. */
@Composable
private fun XGlyph(color: Color) {
    Canvas(Modifier.size(12.dp)) {
        val w = 1.6.dp.toPx()
        drawLine(color, Offset.Zero, Offset(size.width, size.height), w, StrokeCap.Round)
        drawLine(color, Offset(size.width, 0f), Offset(0f, size.height), w, StrokeCap.Round)
    }
}

/** SF Symbol `info.circle` at 15pt. */
@Composable
private fun InfoGlyph(color: Color) {
    Canvas(Modifier.size(15.dp)) {
        val w = 1.3.dp.toPx()
        drawCircle(color, size.minDimension / 2 - w / 2, style = Stroke(w))
        val cx = size.width / 2
        drawLine(color, Offset(cx, size.height * 0.45f), Offset(cx, size.height * 0.74f), w, StrokeCap.Round)
        drawCircle(color, w * 0.75f, Offset(cx, size.height * 0.29f))
    }
}

/** SF Symbol `chevron.right` at 11pt medium. */
@Composable
private fun ChevronGlyph(color: Color) {
    Canvas(Modifier.size(6.dp, 11.dp)) {
        val w = 1.5.dp.toPx()
        drawLine(color, Offset(0f, 0f), Offset(size.width, size.height / 2), w, StrokeCap.Round)
        drawLine(color, Offset(size.width, size.height / 2), Offset(0f, size.height), w, StrokeCap.Round)
    }
}

object SleepContributorRow {
    fun tint(score: Double?): Color {
        if (score == null) return NB.text3Prod
        return when {
            score >= 85 -> NB.optimal2
            score >= 70 -> NB.violet1
            score >= 60 -> NB.compareAmber
            else -> NB.ember1
        }
    }
}

@Composable
fun SleepContributorRow(title: String, value: String, score: Double?, showsChevron: Boolean = false) {
    val readingTint = if (score == null) NB.text3Prod else if (score < 70) NB.compareAmber else NB.white
    val access = score?.let { L("%@ · %.0f OUT OF 100", SleepContributor.rating(it), it) } ?: L("NOT MEASURED")
    Column(
        Modifier.fillMaxWidth().heightIn(min = 52.dp)
            .clearAndSetSemantics { contentDescription = "$title, $value"; stateDescription = access },
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, Modifier.alignBy(FirstBaseline), style = NBFont.ui(500, 14f), color = NB.text1)
            Spacer(Modifier.weight(1f))
            Text(value, Modifier.alignBy(FirstBaseline).padding(start = 4.dp), style = NBFont.dot(600, 14f), color = readingTint,
                textAlign = TextAlign.End)
            if (showsChevron) {
                Box(Modifier.width(12.dp).alignBy { it.measuredHeight * 3 / 4 }, contentAlignment = Alignment.Center) {
                    ChevronGlyph(NB.text3Prod)
                }
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(4.dp)) {
            Box(Modifier.fillMaxSize().background(NB.barTrack, CircleShape))
            if (score != null && score.isFinite()) {
                Box(Modifier.width((maxWidth.value * min(100.0, max(0.0, score)).toFloat() / 100f).dp)
                    .fillMaxHeight().background(readingTint, CircleShape))
            }
        }
    }
}

@Composable
fun SleepContributorCoverage(score: SleepScore) {
    val style = NBFont.ui(400, 11f)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(L("%d OF 7 FACTORS SCORED", SleepContributor.entries.count { score.contributorScore(it) != null }),
            style = NBFont.dot(600, 11f), color = NB.text1)
        if (score.inputs["duration_recorded"] != 1.0) {
            Text(L("Duration is reported or estimated, not fully measured time asleep."), style = style, color = NB.text3Prod)
        }
        val missing = score.inputs["unstaged_minutes"]
        if (missing != null && missing.isFinite() && missing > 0 && missing <= 2880) {
            Text(L("%@ WITHOUT STAGES · EFFICIENCY AND RESTFULNESS EXCLUDED", Fmt.duration(missing.roundedInt())),
                style = style, color = NB.text3Prod)
        }
        Text(L("Latency is unavailable. Efficiency covers recorded periods only; restfulness uses wake episodes only. Timing uses a population midpoint reference."),
            style = style, color = NB.text3Prod)
        Text(L("Only recorded sleep is included. Unrecorded naps are not added. Heart rate, HRV, oxygen and respiration remain supporting measurements, not sleep-score factors."),
            style = style, color = NB.text3Prod)
    }
}

@Composable
fun SleepContributorWindow(summary: SleepWindowSummary) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SleepContributor.entries.forEach { contributor ->
            val values = summary.contributorScores.mapNotNull { it.contributorScore(contributor) }
            val median = SleepScoreMath.median(values)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SleepContributorRow(contributor.title, median?.roundedInt()?.toString() ?: L("NOT MEASURED"), median)
                Text(L("%d OF %d NIGHTS MEASURED", values.size, summary.slots.size),
                    style = NBFont.dot(500, 9f), color = NB.text3Prod)
            }
        }
        if (summary.contributorScores.size != summary.scores.size) {
            Text(L("LEGACY SCORES ARE SHOWN IN THE TREND, NOT MIXED INTO THE SEVEN FACTORS"),
                style = NBFont.ui(400, 10f), color = NB.compareAmber)
        }
        Text(L("FACTOR MEDIANS ARE SEPARATE; THE TOTAL IS THE MEDIAN OF NIGHTLY SCORES"),
            style = NBFont.ui(400, 10f), color = NB.text3Prod)
    }
}

// MARK: - what a group is made of

/** ADR 0008 · the names and measured values behind each group. A member the night never
 *  recorded prints —— so that "scored on 2 of 4" is visible as well as stated. */
object SleepInputLabel {
    fun line(group: SleepScoreGroup, inputs: Map<String, Double>): String =
        group.memberKeys.joinToString(" · ") { key -> "${title(key)} ${inputs[key]?.let { value(key, it) } ?: Fmt.dash}" }

    fun title(key: String): String = when (key) {
        "duration_min" -> L("TOTAL")
        "deep_pct" -> L("DEEP")
        "rem_pct" -> L("REM")
        "wakes" -> L("WAKES")
        "hrv_ms" -> L("HRV")
        "rhr" -> L("RESTING")
        "spo2_min" -> L("SPO2 MIN")
        "respiration" -> L("RESP")
        "bed_offset" -> L("BEDTIME")
        else -> key
    }

    fun value(key: String, measured: Double): String = when (key) {
        "duration_min" -> Fmt.duration(measured.toInt())
        "deep_pct", "rem_pct", "spo2_min" -> "${measured.roundedInt()}%"
        "wakes" -> "${measured.roundedInt()}"
        "hrv_ms" -> "${measured.roundedInt()}MS"
        "rhr" -> "${measured.roundedInt()}"
        "respiration" -> "${measured.roundedInt()}/MIN"
        "bed_offset" -> SleepScoreMath.bedClock(measured)
        else -> "${measured.roundedInt()}"
    }
}

// MARK: - a section of the board

/** One of the score's four groups, used as a heading for the charts that feed it. */
@Composable
fun SleepSectionHeader(group: SleepScoreGroup, score: Int?, effectiveWeight: Double? = null) {
    Row(
        Modifier.fillMaxWidth().padding(top = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(group.title, style = NBFont.ui(600, 13f).tracking(0.18f), color = NB.text1, maxLines = 1)
        Box(Modifier.weight(1f).height(1.dp).background(NB.hairline))
        Text(score?.toString() ?: Fmt.dash, style = NBFont.dot(700, 13f),
            color = if (score == null) NB.text3Prod else NB.violet1, maxLines = 1)
        Text(effectiveWeight?.let { L("WEIGHT %.1f%%", it) } ?: L("NOT SCORED"),
            style = NBFont.dot(500, 9f).tracking(0.05f), color = NB.text3Prod, maxLines = 1)
    }
}

// MARK: - duration

/** The only chart DURATION can honestly have: the night against the line it is scored on. */
object SleepDurationBar {
    /** 7.5h earns full marks and 9.5h is where the mild oversleep penalty starts. */
    const val fullFrom = 450.0
    const val fullTo = 570.0
    internal const val scale = 720.0 // twelve hours of track
}

@Composable
fun SleepDurationBar(minutes: Int) {
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = L("TOTAL"); stateDescription = Fmt.duration(minutes)
        },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(14.dp)) {
            val w = maxWidth.value
            val s = SleepDurationBar.scale
            Box(Modifier.fillMaxSize().background(NB.barTrack, CircleShape))
            // The full-marks band, drawn behind the night so the night sits in or out of it.
            Box(Modifier.offset(x = (w * SleepDurationBar.fullFrom / s).toFloat().dp)
                .width((w * (SleepDurationBar.fullTo - SleepDurationBar.fullFrom) / s).toFloat().dp)
                .fillMaxHeight().background(NB.optimal2.copy(alpha = 0.16f)))
            Box(Modifier.width(max(3.0, w * min(minutes.toDouble(), s) / s).toFloat().dp)
                .fillMaxHeight().background(NB.violet1, CircleShape))
            Box(Modifier.offset(x = (w * SleepDurationBar.fullFrom / s).toFloat().dp).width(1.5.dp)
                .fillMaxHeight().background(NB.optimal2))
        }
        Row(Modifier.fillMaxWidth()) {
            Text(Fmt.duration(minutes), style = NBFont.dot(700, 11f), color = NB.violet1)
            Spacer(Modifier.weight(1f))
            Text(L("FULL MARKS FROM %@", Fmt.duration(SleepDurationBar.fullFrom.toInt())),
                style = NBFont.dot(500, 9f).tracking(0.05f), color = NB.text3Prod)
        }
    }
}

// MARK: - regularity

/**
 * One night on the schedule: when the person fell asleep and when they woke, as minutes past
 * 18:00 local — `bed_offset`'s own ruler. `wake` is on the same ruler and always later than `bed`.
 */
class SleepScheduleNight(val day: UserDay, score: SleepScore?, summary: SleepSummary?) {
    val bed: Double?
    val wake: Double?
    val id: String get() = day.key
    val isRecorded: Boolean get() = bed != null && wake != null

    init {
        val start = summary?.sleepStart
        val end = summary?.wakeAt
        val scoreBed = score?.inputs?.get("bed_offset")
        val scoreMinutes = score?.inputs?.get(if (score.usesContributors) "sleep_elapsed_minutes" else "duration_min")
        if (start != null && end != null && end > start) {
            val b = eveningOffset(start)
            bed = b
            wake = b + end.timeIntervalSince(start) / 60
        } else if (scoreBed != null && scoreMinutes != null && scoreBed.isFinite() && scoreMinutes.isFinite() &&
            scoreMinutes > 0 && scoreMinutes <= 2880) {
            bed = scoreBed
            wake = scoreBed + scoreMinutes
        } else {
            bed = null
            wake = null
        }
    }

    companion object {
        fun eveningOffset(date: Instant, zone: ZoneId = currentZone()): Double {
            val z = date.atZone(zone)
            val minutes = z.hour * 60 + z.minute
            return (((minutes - 1080) % 1440 + 1440) % 1440).toDouble()
        }
    }
}

object SleepScheduleBars {
    const val tolerance = 30.0

    @Composable
    fun Legend(baseline: Double?, tint: Color = NB.violet1) {
        VitalsChartLegend(
            items = (if (baseline == null) emptyList() else listOf(VitalsChartLegend.Item(L("USUAL BEDTIME ±30 MIN"), tint, isArea = true))) +
                listOf(VitalsChartLegend.Item(L("ASLEEP → AWAKE"), tint)),
            trailing = L("DOTTED · NOT RECORDED"),
            trailingTint = NB.white.copy(alpha = 0.45f),
        )
    }

    /** Evening at the top, morning at the bottom. The default 20:00–10:00 window covers a normal
     *  week; a 04:00 bedtime or an 11:30 lie-in stretches it out to the next whole hour. */
    internal fun domain(nights: List<SleepScheduleNight>, baseline: Double?): Pair<Double, Double> {
        var low = 120.0 // 20:00
        var high = 960.0 // 10:00
        for (night in nights) {
            night.bed?.let { low = min(low, it - 30) }
            night.wake?.let { high = max(high, it + 30) }
        }
        if (baseline != null) {
            low = min(low, baseline - tolerance - 15)
            high = max(high, baseline + tolerance + 15)
        }
        low = floor(low / 60) * 60
        high = ceil(high / 60) * 60
        return low to max(high, low + 60)
    }
}

/**
 * The regularity group's chart: a week of nights side by side, each a column from the minute
 * the person fell asleep down to the minute they woke, on one shared clock that runs
 * evening-to-morning top-to-bottom. Regularity is a *shape*.
 *
 * This person's usual bedtime is the band behind the columns (median ± 30 minutes).
 */
@Composable
fun SleepScheduleBars(
    nights: List<SleepScheduleNight>,
    baseline: Double?,
    tint: Color = NB.violet1,
    height: Dp = 176.dp,
) {
    val (low, high) = SleepScheduleBars.domain(nights, baseline)
    fun yFrac(offset: Double): Float = ((min(max(offset, low), high) - low) / (high - low)).toFloat()
    val railLabels = listOf(low, (low + high) / 2, high).map { SleepScoreMath.bedClock(it) }
    val ranges = VitalsProbeMath.equalSlots(nights.size)
    val probeBins = nights.zip(ranges).map { (night, range) ->
        val clock = "${Fmt.weekday(night.day.date)} ${dayOfMonth(night.day.date)}"
        val bed = night.bed
        val wake = night.wake
        if (bed != null && wake != null) {
            VitalsProbeMath.Bin(range.start, range.end, (bed - low) / (high - low),
                VitalsProbeCopy.ranges(clock,
                    listOf(SleepScoreMath.bedClock(bed) to SleepScoreMath.bedClock(wake)),
                    Fmt.duration((wake - bed).roundedInt())))
        } else {
            VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        VitalsChartProbe(
            series = VitalsProbeMath.Series.Bins(probeBins),
            tint = tint,
            height = height,
            trailingInset = VitalsScaleRail.gutter,
            accessibilityTitle = L("SLEEP BY NIGHT"),
            accessibilityName = "vitals.probe.schedule",
        ) { _ ->
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
                BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
                    val fieldH = maxHeight
                    val count = max(nights.size, 1)
                    val spacing = if (nights.size > 10) 2.dp else 6.dp
                    val width = max(2f, (maxWidth.value - spacing.value * (count - 1)) / count).dp
                    val radius = min(width.value / 2, 6f).dp
                    // The habit band: usual bedtime ± the 30 minutes the score gives full marks for.
                    if (baseline != null) {
                        val top = fieldH * yFrac(baseline - SleepScheduleBars.tolerance)
                        val bottom = fieldH * yFrac(baseline + SleepScheduleBars.tolerance)
                        Box(Modifier.offset(y = top).fillMaxWidth().height(max(1f, (bottom - top).value).dp)
                            .background(tint.copy(alpha = 0.16f)))
                        Box(Modifier.offset(y = fieldH * yFrac(baseline)).fillMaxWidth().height(1.dp)
                            .background(tint.copy(alpha = 0.7f)))
                    }
                    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(spacing)) {
                        nights.forEachIndexed { index, night ->
                            val last = index == nights.size - 1
                            Box(Modifier.width(width).fillMaxHeight()) {
                                // A night not on record is a dotted slot at full height.
                                if (!night.isRecorded) DottedSlot(radius, Modifier.fillMaxSize())
                                val bed = night.bed
                                val wake = night.wake
                                if (bed != null && wake != null) {
                                    val top = fieldH * yFrac(bed)
                                    val bottom = fieldH * yFrac(wake)
                                    Box(Modifier.offset(y = top).fillMaxWidth()
                                        .height(max(radius.value * 2, (bottom - top).value).dp)
                                        .background(if (last) tint else tint.copy(alpha = 0.55f), RoundedCornerShape(radius)))
                                }
                            }
                        }
                    }
                }
                VitalsScaleRail(railLabels, tint)
            }
        }
        // One weekday under each column, in the column's own width.
        Row(Modifier.fillMaxWidth().padding(end = VitalsScaleRail.gutter)) {
            nights.forEachIndexed { index, night ->
                val last = index == nights.size - 1
                // A month is thirty slots; only every fifth date is printed.
                val hidden = nights.size > 10 && index % 5 != nights.size % 5 - 1 && !last
                Box(Modifier.weight(1f).alpha(if (hidden) 0f else 1f), contentAlignment = Alignment.Center) {
                    FitText(
                        if (nights.size > 10) dayOfMonth(night.day.date).toString() else Fmt.weekday(night.day.date),
                        NBFont.ui(if (last) 500 else 400, 9f),
                        if (last) tint else NB.white.copy(alpha = 0.45f),
                        minScale = 0.6f,
                    )
                }
            }
        }
    }
}
