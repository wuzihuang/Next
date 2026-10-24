package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.OvernightOxygenPoint
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.ui.CardBlock

/**
 * HEART second level after the hero. The page stays a heart page: the lead envelope is the
 * pulse, HRV and overnight SpO2 share the same clock as companions. Empty slots stay empty —
 * SpO2 has nothing to draw in daylight.
 *
 * Emits its cards as siblings into the caller's column.
 */
@Composable
fun HeartBoard(
    range: RollingPills,
    window: VitalsWindow,
    ticks: List<VitalSample>,
    oxygen: List<OvernightOxygenPoint>,
    readout: VitalsReadout,
    slotMinutes: Double,
    dial: VitalsDial.Model?,
    /** False on the rolling windows, where the trend hero above already drew the pulse a night
     *  at a time and a second envelope of the same days would be the page repeating itself. */
    showsLead: Boolean = true,
) {
    if (showsLead) {
        CardBlock(title = L("HEART RATE"), trailing = readout.chartNote) {
            if (ticks.any { it.hr != null }) {
                VitalsTrace(
                    samples = ticks, value = { it.hr?.toDouble() },
                    window = window, low = 40.0, high = 160.0, tint = NB.lime1,
                    zones = dial,
                    referenceBand = readout.referenceBand,
                    referenceSpan = readout.referenceSpan,
                    slotMinutes = slotMinutes,
                    unit = "BPM",
                )
            } else {
                VitalsChartEmpty(
                    line = if (range == RollingPills.day) L("NO HEART TICKS IN 24H") else L("NO HEART TICKS IN THIS WINDOW"),
                    sub = L("THE NEXT SYNC DRAWS THE LINE"),
                )
            }
            VitalsAxis(window.labels, highlightsLast = window.endsNow, tint = NB.lime1,
                modifier = Modifier.padding(end = VitalsScaleRail.gutter))
            VitalsChartLegend(
                items = listOf(
                    VitalsChartLegend.Item(
                        if (range == RollingPills.day)
                            L("EVERY %d MIN · MEASURED", DetailWindow(DetailSurface.heart, RollingPills.day).slotMinutes.toInt())
                        else L("EVERY DAY · MEASURED"),
                        NB.lime1, stops = dial?.legendStops,
                    ),
                ) + (readout.referenceLabel?.let { listOf(VitalsChartLegend.Item(it, NB.lime1, isArea = true)) } ?: emptyList()),
                trailing = ticks.mapNotNull { it.hr }.maxOrNull()?.let { L("MAX %d", it) },
                trailingTint = NB.lime1,
            )
        }
    }

    CardBlock(title = L("ON THE SAME CLOCK"), trailing = L("COMPANIONS SHARE THIS CLOCK")) {
        // HRV
        if (ticks.any { it.hrv != null }) {
            VitalsTrace(
                samples = ticks, value = { it.hrv },
                window = window, low = 0.0, high = 90.0, tint = VitalsMetric.hrv.tint,
                height = 112.dp,
                slotMinutes = slotMinutes,
                unit = "MS",
            )
            CompanionNote(L("HRV · RMSSD"),
                ticks.mapNotNull { it.hrv }.maxOrNull()?.let { L("NIGHT HIGH %d", it.roundedInt()) },
                VitalsMetric.hrv.tint)
        } else {
            VitalsChartEmpty(L("NO RMSSD IN THIS WINDOW"), L("THE BAND MEASURES IT EVERY TEN MINUTES"))
        }
        // Overnight oxygen: the same line the sleep page draws — one reading every few minutes,
        // and an occupancy capsule per slot reads as a fence, not a night.
        if (oxygen.isNotEmpty()) {
            VitalsLineTrace(
                points = oxygen.map { TimedValue(it.ts, it.percent.toDouble()) },
                window = window, low = 85.0, high = 100.0, tint = NB.optimal2,
                marksMaximum = false,
                height = 112.dp,
                unit = "%",
            )
            CompanionNote(L("OVERNIGHT SPO2"), oxygen.minOfOrNull { it.percent }?.let { L("MIN %d", it) }, NB.optimal2)
        } else {
            VitalsChartEmpty(L("NO OVERNIGHT OXYGEN"), L("AUTO NIGHT MEASUREMENT WAS OFF OR EMPTY"))
        }
        VitalsAxis(window.labels, highlightsLast = window.endsNow, tint = VitalsMetric.hrv.tint,
            modifier = Modifier.padding(end = VitalsScaleRail.gutter))
        VitalsChartLegend(
            items = listOf(
                VitalsChartLegend.Item(L("WINDOW RMSSD · SPARSER THAN HEART"), VitalsMetric.hrv.tint),
                VitalsChartLegend.Item(L("NIGHT WINDOW ONLY · DAY IS EMPTY"), NB.optimal2),
            ),
            trailing = null,
        )
    }
}

@Composable
private fun CompanionNote(title: String, trailing: String?, tint: Color) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
        FitText(title, NBFont.ui(500, 10f).tracking(0.12f), NB.white.copy(alpha = 0.45f), Modifier.alignBy(FirstBaseline))
        Spacer(Modifier.width(16.dp))
        Spacer(Modifier.weight(1f))
        if (trailing != null) FitText(trailing, NBFont.ui(500, 10f), tint, Modifier.alignBy(FirstBaseline))
    }
}
