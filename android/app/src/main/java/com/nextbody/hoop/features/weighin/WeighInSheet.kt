package com.nextbody.hoop.features.weighin

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.profile.LimePill
import com.nextbody.hoop.features.profile.ProfileUnitToggle
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.model.isSameDay
import com.nextbody.hoop.services.HealthService
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * 10S · 称重录入 Add a weigh-in.
 * D06 struck the old "NOT IN V1": without a manual entry, anyone without a smart scale could never
 * unlock the composition call — the product's headline feature. Reached from the composition
 * detail's ADD A WEIGH-IN, from 11's body rows and from the Health Connect sheet's manual link —
 * all about the same physical fact. Never from the dock.
 */
@Composable
fun WeighInSheet(close: () -> Unit) {
    val data = DataStore
    val debugImperial = DebugEdgeFlag.on("imperial") || DebugEdgeFlag.on("fromhealthlb")
    var fromHealth by remember { mutableStateOf(false) }
    var unit by remember { mutableStateOf(if (debugImperial || !data.profile.usesMetric) "LB" else "KG") }
    // The keypad opens on what they weigh now, not on an empty field: most entries are a small
    // correction to the last one.
    var typed by remember {
        val kg = data.today.weightKg
        mutableStateOf(
            when {
                DebugEdgeFlag.on("outofrange") -> "9"
                kg == null -> ""
                unit == "LB" -> String.format(Locale.US, "%.1f", kg * 2.2046226)
                else -> Fmt.kg(kg)
            },
        )
    }

    /**
     * Health Connect's number may come from another scale, another person, or one mis-step, and
     * it would flow all the way through to the macros and The Call — so it is confirmed, never
     * adopted silently. ⚠️ Null by default: a prompt to confirm a number nobody measured is the
     * worst thing this sheet can do.
     */
    var candidate by remember { mutableStateOf<HealthCandidate?>(null) }

    LaunchedEffect(Unit) {
        if (DebugEdgeFlag.on("fromhealth") || DebugEdgeFlag.on("fromhealthlb")) {
            candidate = HealthCandidate(78.6, "TODAY 07:12", Instant.now(), "debug-health")
            fromHealth = true
            return@LaunchedEffect
        }
        // Only a weigh-in newer than NEXTBODY's own last one is worth confirming.
        val w = HealthService.latestWeight() ?: return@LaunchedEffect
        if (w.at > (data.weighIns.firstOrNull()?.date ?: Instant.MIN)) {
            val zone = ZoneId.systemDefault()
            val day = w.at.atZone(zone).toLocalDate()
            val today = LocalDate.now(zone)
            val clock = DateTimeFormatter.ofPattern("HH:mm").format(w.at.atZone(zone))
            val label = when (day) {
                today -> L("TODAY")
                today.minusDays(1) -> L("YESTERDAY")
                else -> clock
            }
            candidate = HealthCandidate(w.kg, "$label $clock", w.at, w.uuid)
            fromHealth = true
        }
    }

    Box(Modifier.fillMaxSize().background(NB.carbon2)) {
        if (fromHealth) {
            FromHealth(candidate, metric = !debugImperial && data.profile.usesMetric,
                onUse = {
                    candidate?.let { c ->
                        // 10 rule 08 · a Health Connect reading keeps its own timestamp, and its
                        // own id (10S rule 04) so the same sample never enters twice.
                        data.addWeighIn(WeighIn(id = UUID.randomUUID(), date = c.at, weightKg = c.kg,
                            bodyFatPercent = null, source = MeasurementSource.measured,
                            origin = WeighIn.Origin.health, healthUUID = c.uuid))
                    }
                    close()
                },
                onDifferent = { fromHealth = false })
        } else {
            ByHand(typed, { typed = it }, unit, { unit = it }) { kg ->
                data.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = kg,
                    bodyFatPercent = null, source = MeasurementSource.measured, origin = WeighIn.Origin.manual))
                Haptics.impact(ImpactStyle.Rigid)
                close()
            }
        }
    }
}

private data class HealthCandidate(val kg: Double, val label: String, val at: Instant, val uuid: String)

// MARK: 02 · 手填 By hand

@Composable
private fun ByHand(typed: String, onTyped: (String) -> Unit, unit: String, onUnit: (String) -> Unit, onSave: (Double) -> Unit) {
    val data = DataStore
    val typedKg: Double? = typed.toDoubleOrNull()?.let { if (unit == "KG") it else it / 2.2046226 }
    val parsed: Double? = typedKg?.takeIf { it in 20.0..300.0 }
    // 10S rule 03 / edge 3 · 20–300 kg (44–661 lb), fixed: SAVE off, the number amber, the range
    // and nothing else. Never 「与上次相差过大」.
    val outOfRange = typedKg?.let { it !in 20.0..300.0 } ?: false
    // 10S edge 2 · a second one today replaces the first in the calculation; the row stays.
    val todaysEarlier = data.weighIns.firstOrNull { it.date.isSameDay(Instant.now()) }

    Column(Modifier.fillMaxSize()) {
      // The keypad block scrolls only when the sheet is shorter than it; SAVE stays put.
      Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
        Column(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 22.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(L("Add a weigh-in"), style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
            // It stays in NEXTBODY: we never write a hand-typed number back into Health Connect.
            Text(L("Stays in NEXTBODY. It never goes back to Health."), style = NBFont.ui(300, 12.5f).tracking(0.02f),
                color = NB.white.copy(alpha = 0.38f))
        }

        Row(
            Modifier.fillMaxWidth().padding(top = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        ) {
            Text(if (typed.isEmpty()) "—" else typed, style = NBFont.brand(700, 54f).tracking(-0.045f),
                color = if (outOfRange) NB.ember1 else NB.text1, maxLines = 1, modifier = Modifier.alignByBaseline())
            Text(unit.lowercase(), style = NBFont.ui(300, 16f), color = NB.white.copy(alpha = 0.38f),
                modifier = Modifier.alignByBaseline())
        }

        if (outOfRange) {
            Notice(L("OUT OF RANGE"), if (unit == "KG") "20–300 KG" else "44–661 LB")
        } else if (todaysEarlier != null && parsed != null) {
            Notice(L("ALREADY ONE TODAY"), L("%@ REPLACES %@", Fmt.kg(parsed), Fmt.kg(todaysEarlier.weightKg)))
        }

        Row(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ProfileUnitToggle(listOf("KG", "LB"), unit, onUnit)
            Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
            Spacer(Modifier.weight(1f))
            // The date cannot be changed: back-filling goes through the day's own page.
            Text(L("TODAY · %@", Fmt.displayDate(Instant.now(), "MMM d").uppercase()),
                style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.white.copy(alpha = 0.34f))
        }

        // Its own keypad, not the system keyboard: this screen takes one decimal number, so
        // letters, emoji and a return key are all noise.
        DecimalPad(typed, onTyped, Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 12.dp))
      }

        // SAVE is the only lime on this screen, and it stays tappable even when the number has
        // not moved — "yes, today is still 78.6" is a valid record.
        Box(Modifier.fillMaxWidth().padding(bottom = 22.dp + ScreenMetrics.safeBottom), contentAlignment = Alignment.Center) {
            LimePill(L("SAVE"), enabled = parsed != null) { parsed?.let(onSave) }
        }
    }
}

@Composable
private fun Notice(head: String, line: String) {
    Column(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(head, style = NBFont.dot(600, 12f).tracking(0.22f), color = NB.ember1.copy(alpha = 0.85f))
        Text(line, style = NBFont.brand(500, 13.5f), color = NB.white.copy(alpha = 0.70f))
    }
}

// MARK: 03 · Health Connect 那一条 — confirm, not auto-adopt

@Composable
private fun FromHealth(c: HealthCandidate?, metric: Boolean, onUse: () -> Unit, onDifferent: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 22.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(L("FROM HEALTH"), style = NBFont.dot(600, 10f).tracking(0.24f), color = NB.white.copy(alpha = 0.34f))
            Text(L("There's a new weigh-in"), style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
        }
        if (c != null) {
            Row(
                Modifier.fillMaxWidth().padding(top = 28.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
            ) {
                Text(if (metric) Fmt.kg(c.kg) else String.format(Locale.US, "%.1f", c.kg * 2.2046226),
                    style = NBFont.brand(700, 54f).tracking(-0.045f), color = NB.text1, modifier = Modifier.alignByBaseline())
                Text(if (metric) "KG" else "LB", style = NBFont.dot(500, 14f), color = NB.white.copy(alpha = 0.34f),
                    modifier = Modifier.alignByBaseline())
            }
            // The number, its source and its time — three facts before one green button.
            Text(L("HEALTH CONNECT  ·  %@", c.label), style = NBFont.dot(600, 10f).tracking(0.2f),
                color = NB.white.copy(alpha = 0.34f), modifier = Modifier.padding(top = 12.dp))
        }
        Spacer(Modifier.weight(1f))
        LimePill(L("USE THIS"), action = onUse)
        // Swiping away is a refusal; we do not ask again for the same record.
        Text(L("Enter a different number"), style = NBFont.ui(400, 13f).tracking(0.02f), color = NB.text3Prod,
            modifier = Modifier.padding(top = 16.dp, bottom = 24.dp + ScreenMetrics.safeBottom).hotZoneTap(pressedScale = 1f, onClick = onDifferent))
    }
}

/** One decimal number, one delete key, and nothing else. */
@Composable
fun DecimalPad(text: String, onText: (String) -> Unit, modifier: Modifier = Modifier) {
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(".", "0", "DEL"))
    fun tap(key: String) {
        when (key) {
            "DEL" -> if (text.isNotEmpty()) onText(text.dropLast(1))
            "." -> if (!text.contains(".")) onText("$text.")
            else -> {
                // one decimal place, 0.1 kg per notch
                val dot = text.indexOf('.')
                if (dot >= 0 && text.length - dot > 1) return
                if (text.length < 6) onText(text + key)
            }
        }
        Haptics.selection()
    }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { key ->
                    val del = key == "DEL"
                    Box(
                        Modifier
                            .weight(1f)
                            .height(46.dp)
                            .background(NB.smokeKey, RoundedCornerShape(NB.R.key))
                            .hotZoneTap(pressedScale = 1f) { tap(key) },
                        contentAlignment = Alignment.Center,
                    ) {
                        val style: TextStyle = if (del) NBFont.ui(500, 12f).tracking(0.16f) else NBFont.ui(400, 22f)
                        Text(if (del) L("DEL") else key, style = style, color = if (del) NB.text3Prod else NB.text1)
                    }
                }
            }
        }
    }
}
