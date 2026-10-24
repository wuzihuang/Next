package com.nextbody.hoop.features.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.FuelCardMath
import com.nextbody.hoop.band.TrainingRangeStatus
import com.nextbody.hoop.band.TrainingWindowMath
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.hotZoneTap

/**
 * 04 · 05 这条带 The Strip. 358 × 136, two 174-wide cards, gap 10, order written in stone:
 * TRAINING left, CALORIES right — the causal order of a day, burn before refuel.
 * The whole card is the tap target; there is no second-level button inside it.
 */
@Composable
fun BottomStrip(
    m: DailyMetrics,
    onTraining: () -> Unit,
    onFuel: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = NB.Layout.contentWidth,
) {
    Row(
        modifier.width(width).height(NB.Layout.stripHeight),
        horizontalArrangement = Arrangement.spacedBy(NB.Layout.cardGap),
    ) {
        // ADR-0001 · the card is a hot zone: it fires on a tap and never on a touch
        // that travelled (hotZoneTap), so a page drag that starts here turns the page.
        Box(Modifier.hotZoneTap(onClick = onTraining)) { TrainingCard(m) }
        Box(Modifier.weight(1f).hotZoneTap(onClick = onFuel)) { FuelCard(m) }
    }
}

@Composable
private fun StripText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    Text(text, modifier, style = style, color = color, maxLines = maxLines,
        softWrap = maxLines > 1, overflow = TextOverflow.Clip, textAlign = align)
}

private val cardShape = RoundedCornerShape(NB.R.card)

@Composable
fun TrainingCard(m: DailyMetrics) {
    val status = TrainingWindowMath.rangeStatus(m.trainingLoad, m.targetLoad, m.optimalZone)
    val statusText = when (status) {
        TrainingRangeStatus.NoLoad -> L("ACTIVITY DATA NEEDED")
        TrainingRangeStatus.NoTarget -> L("AWAITING MORNING")
        is TrainingRangeStatus.Below -> L("%.1f BELOW RANGE", status.by)
        TrainingRangeStatus.InRange -> L("IN RANGE")
        is TrainingRangeStatus.Above -> L("%.1f ABOVE RANGE", status.by)
        TrainingRangeStatus.Capped -> L("SCALE LIMIT")
    }
    val statusTint = when (status) {
        TrainingRangeStatus.NoLoad, TrainingRangeStatus.NoTarget -> NB.text3Prod
        is TrainingRangeStatus.Above, TrainingRangeStatus.Capped -> NB.ember1
        is TrainingRangeStatus.Below, TrainingRangeStatus.InRange -> NB.limePale
    }
    Column(
        Modifier
            .size(NB.Layout.cardWidth, NB.Layout.stripHeight)
            .background(NB.carbon4, cardShape)
            .border(1.dp, NB.hairline, cardShape)
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            StripText(MetricNames.training, NBFont.ui(500, 11f).tracking(0.14f), NB.text3Prod)
            // ⚠️ an 8pt floor: a long status shrinks before it closes the gap.
            Spacer(Modifier.width(8.dp))
            Spacer(Modifier.weight(1f))
            StripText(statusText, NBFont.dot(700, 12f).tracking(0.04f), statusTint)
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TrainingRing(m.trainingLoad, m.targetLoad, m.optimalZone)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                if (m.targetLoad == null) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        StripText(L("TARGET"), NBFont.ui(500, 11f).tracking(0.06f), NB.text3Prod)
                        StripText(L("NOT SET"), NBFont.ui(600, 12f), NB.text1, maxLines = 2)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        StripText(L("FULL RING"), NBFont.ui(500, 11f).tracking(0.06f), NB.text3Prod)
                        StripText(L("21.0"), NBFont.dot(700, 14f).tracking(0.02f), NB.text3Prod)
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        StripText(L("SUGGESTED RANGE"), NBFont.ui(500, 9f), NB.text3Prod, maxLines = 2)
                        StripText(
                            m.optimalZone?.let { swiftFormat("%.1f–%.1f", it.start, it.endInclusive) } ?: Fmt.dash,
                            NBFont.dot(700, 12f), NB.text1, maxLines = 2,
                        )
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        StripText(L("RULE ESTIMATE"), NBFont.ui(500, 9f), NB.text3Prod, maxLines = 2)
                        val n = m.nightInputs
                        StripText(
                            if (n == null) L("BASELINE UNKNOWN")
                            else if (n.hrvNights < 5 || n.rhrNights < 5) L("BASELINE BUILDING")
                            else L("NIGHT INPUTS"),
                            NBFont.ui(500, 9f), NB.limePale, maxLines = 2,
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun FuelCard(m: DailyMetrics) {
    val read = FuelCardMath.readout(eaten = m.eIn, target = m.targetIn)
    val pairLabel: String? = when (read.pair) {
        FuelCardMath.Pair.Silent -> null
        is FuelCardMath.Pair.ToGo -> L("TO GO")
        is FuelCardMath.Pair.Over -> L("OVER")
    }
    val pairValue = when (val p = read.pair) {
        FuelCardMath.Pair.Silent -> Fmt.dash
        is FuelCardMath.Pair.ToGo -> Fmt.pairKcal(p.delta)
        is FuelCardMath.Pair.Over -> Fmt.pairKcal(p.delta)
    }
    val pairTint = if (read.pair == FuelCardMath.Pair.Silent) NB.text3Prod else NB.emberPale
    Column(
        Modifier
            .fillMaxWidth()
            .height(NB.Layout.stripHeight)
            .background(NB.carbon4, cardShape)
            .border(1.dp, NB.hairline, cardShape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            StripText(MetricNames.calories, NBFont.ui(500, 11f).tracking(0.2f), NB.text3Prod)
            Spacer(Modifier.weight(1f))
            val target = read.target
            if (target != null && target > 0) {
                StripText(L("OF %@", Fmt.kcal(target)), NBFont.dot(500, 11f).tracking(0.04f), NB.text3Prod)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            PairCol(L("EATEN"), Fmt.kcal(read.eaten), if (read.eaten == null) NB.text3Prod else NB.ember1, Modifier.weight(1f))
            PairCol(pairLabel, pairValue, pairTint, Modifier.weight(1f))
        }
        CalorieFill(read.fill)
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            MacroBar(L("PRO"), m.protein?.eaten ?: m.proteinIn, m.protein?.target, NB.violet1)
            MacroBar(L("CARB"), m.carb?.eaten ?: m.carbIn, m.carb?.target, NB.optimal2)
            MacroBar(L("FAT"), m.fat?.eaten ?: m.fatIn, m.fat?.target, NB.run1)
        }
    }
}

@Composable
private fun PairCol(label: String?, value: String, tint: Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        StripText(label ?: " ", NBFont.ui(500, 9f).tracking(0.12f), NB.text3Prod,
            Modifier.alpha(if (label == null) 0f else 1f))
        StripText(value, NBFont.dot(700, 18f).tracking(-0.02f), tint)
    }
}

/** Ember fill for EATEN / TARGET. Full stops the bar; over does not turn it red. */
@Composable
private fun CalorieFill(fraction: Double) {
    BoxWithConstraints(Modifier.fillMaxWidth().height(6.dp)) {
        Box(Modifier.fillMaxWidth().fillMaxHeight().background(NB.barTrack, CircleShape))
        Box(
            Modifier.width(maxWidth * fraction.coerceIn(0.0, 1.0).toFloat()).fillMaxHeight()
                .background(NB.ember1, CircleShape),
        )
    }
}

/**
 * Three independent bars, 4px tall, each capped at its own target.
 * 09 · B2 · in the empty state the three bars are complete: —/145, —/195, —/60.
 */
@Composable
fun MacroBar(label: String, eaten: Int?, target: Int?, tint: Color) {
    val fraction = if (eaten != null && target != null && target > 0 && eaten > 0) minOf(1.0, eaten.toDouble() / target) else 0.0
    val value = when {
        target == null || target <= 0 -> eaten?.let { "$it g" } ?: Fmt.dash
        eaten == null -> "—/$target"
        else -> "$eaten/$target"
    }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        StripText(label, NBFont.ui(500, 11f).tracking(0.02f), tint, Modifier.width(32.dp))
        if (target != null && target > 0) {
            BoxWithConstraints(Modifier.weight(1f).height(4.dp)) {
                Box(Modifier.fillMaxWidth().fillMaxHeight().background(NB.barTrack, CircleShape))
                Box(Modifier.width(maxWidth * fraction.toFloat()).fillMaxHeight().background(tint, CircleShape))
            }
        } else {
            Spacer(Modifier.weight(1f))
        }
        StripText(value, NBFont.dot(500, 11f), NB.macroValue, Modifier.widthIn(min = 48.dp).width(48.dp), align = TextAlign.End)
    }
}
