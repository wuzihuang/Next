package com.nextbody.hoop.features.measure

import androidx.compose.foundation.background
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.Hairline
import kotlin.math.max
import kotlin.math.min

/**
 * 06 · THREE WAYS TO LAY OUT THE BALANCE CHECK, so they can be compared on the wrist rather
 * than argued about as pictures. All carry the same facts and the same field.
 *
 * `-e NB_DEBUG_BALANCE_STYLE header|dashboard|monolith` picks one. Absent, the chosen one.
 *
 * ⚠️ Not one of them invents a number.
 */
enum class BalanceLayout {
    /** Instruction on top, field through the middle, count low. */
    original,
    /** The key data pulled to the top as a masthead. */
    header,
    /** An instrument row: three labelled cells across the top. */
    dashboard,
    /** One enormous rate, the field behind it, and nothing else until the foot. */
    monolith;

    companion object {
        /** `monolith` is the chosen one; the others stay reachable behind the launch flag. */
        val current: BalanceLayout
            get() {
                val raw = DebugEnv["NB_DEBUG_BALANCE_STYLE"]
                return entries.firstOrNull { it.name == raw } ?: monolith
            }
    }
}

/**
 * What the screen is doing, said once, at the foot of the monolith layout.
 * ⚠️ No full stop: it sits directly over the help line, and two stacked sentences both ending
 * in a period read as a paragraph broken in the wrong place.
 */
@Composable
fun BalanceFootLine(headline: String, over: Boolean, modifier: Modifier = Modifier) {
    MText(
        headline.trim { it in "。.！!" },
        NBFont.brand(500, 19f).tracking(-0.01f), NB.text1,
        modifier.width(300.dp), align = TextAlign.Center, shadow = over,
    )
}

/** The masthead: the rate at the size of a headline, the clock beside it, one line of state. */
@Composable
fun BalanceHeader(
    bpm: Int?, source: String, remaining: Int, total: Int, status: String,
    tint: Color, over: Boolean, modifier: Modifier = Modifier,
) {
    val fraction = if (total > 0) min(1.0, max(0.0, (total - remaining).toDouble() / total)) else 0.0
    Column(modifier.width(NB.Layout.contentWidth)) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // ⚠️ A dash until a rate has been measured.
            MText(bpm?.toString() ?: Fmt.dash, NBFont.dot(700, 72f).tracking(-0.03f), tint,
                Modifier.alignByBaseline(), shadow = over)
            MText(L("BPM"), NBFont.dot(600, 13f).tracking(0.2f), NB.white.copy(alpha = 0.45f),
                Modifier.alignByBaseline(), shadow = over)
            Spacer(Modifier.weight(1f))
            MText(swiftFormat("00:%02d", max(0, remaining)), NBFont.dot(700, 30f).tracking(0.04f),
                NB.white.copy(alpha = 0.85f), Modifier.alignByBaseline(), shadow = over)
        }
        MText(source, NBFont.dot(500, 9.5f).tracking(0.18f), NB.white.copy(alpha = 0.40f),
            Modifier.padding(top = 6.dp), shadow = over)
        // The run drawn as one line rather than a ring: a fixed forty seconds.
        Box(Modifier.padding(top = 14.dp).fillMaxWidth().height(2.dp).background(NB.white.copy(alpha = 0.12f))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.toFloat()).background(tint.copy(alpha = 0.9f)))
        }
        MText(status, NBFont.dot(600, 10f).tracking(0.16f), NB.white.copy(alpha = 0.5f),
            Modifier.padding(top = 10.dp), shadow = over)
    }
}

/** The instrument row: three cells, one hairline, nothing else. */
@Composable
fun BalanceDashboard(
    bpm: Int?, remaining: Int, total: Int, contact: Boolean, over: Boolean, tint: Color,
    modifier: Modifier = Modifier,
) {
    Column(modifier.width(NB.Layout.contentWidth), verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            DashCell("RATE", bpm?.toString() ?: Fmt.dash, "BPM", tint, over)
            DashDivider()
            DashCell("LEFT", max(0, remaining).toString(), "SEC", NB.white.copy(alpha = 0.9f), over)
            DashDivider()
            // The wrist's own state, in a word — the band's judgement, not the app's guess.
            DashCell("CONTACT", if (contact) "ON" else "OFF", if (contact) "KEY" else "LIFT",
                if (contact) tint else NB.ember1, over)
        }
        Hairline(width = NB.Layout.contentWidth)
    }
}

@Composable
private fun DashDivider() {
    Box(Modifier.width(1.dp).height(34.dp).background(NB.white.copy(alpha = 0.12f)))
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.DashCell(
    label: String, value: String, unit: String, tint: Color, over: Boolean,
) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)) {
        MText(label, NBFont.dot(600, 9f).tracking(0.24f), NB.white.copy(alpha = 0.38f), shadow = over)
        MText(value, NBFont.dot(700, 30f).tracking(0.02f), tint, shadow = over)
        MText(unit, NBFont.dot(500, 9f).tracking(0.18f), NB.white.copy(alpha = 0.30f), shadow = over)
    }
}

/**
 * One number, as big as the column allows, with the field behind it. The chosen layout:
 * the rate, where it came from, how long is left — and nothing else competes with the field.
 */
@Composable
fun BalanceMonolith(
    bpm: Int?, source: String, remaining: Int, tint: Color, over: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier.width(NB.Layout.contentWidth), horizontalAlignment = Alignment.CenterHorizontally) {
        // 132 fills the 358 column with three digits and leaves the field readable around it.
        MText(bpm?.toString() ?: Fmt.dash, NBFont.dot(700, 132f).tracking(-0.045f), tint,
            maxLines = 1, minScale = 0.6f, shadow = over)
        MText(source, NBFont.dot(500, 10f).tracking(0.2f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 2.dp), shadow = over)
        // ⚠️ 32, not 15: "how much longer do I have to hold this" is the second thing read.
        MText(swiftFormat("00:%02d", max(0, remaining)), NBFont.dot(700, 32f).tracking(0.04f),
            NB.white.copy(alpha = 0.9f), Modifier.padding(top = 26.dp), shadow = over)
    }
}
