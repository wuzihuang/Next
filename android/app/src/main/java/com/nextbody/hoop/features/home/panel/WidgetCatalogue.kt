package com.nextbody.hoop.features.home.panel

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.hotZoneTap

/**
 * 07 · the render contract, laid out so it can be audited. Every type the model is allowed to
 * pick, with data shaped exactly as the contract table on 07 specifies it.
 *
 * ⚠️ DEBUG only, reachable only from a long press on the wordmark (seed builds). Not a product
 * surface. Present it full screen; [close] dismisses it.
 */
@Composable
fun WidgetCatalogue(close: () -> Unit) {
    val types = PanelType.entries
    val cw = NB.Layout.contentWidth
    val ph = NB.Layout.panelHeight
    Column(
        Modifier.fillMaxSize().background(NB.carbon).verticalScroll(rememberScrollState())
            .padding(top = ScreenMetrics.safeTop, bottom = 40.dp + ScreenMetrics.safeBottom),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText(L("%d TYPES · 16 RENDERERS", types.size),
                style = NBFont.dot(600, 10f).tracking(0.18f).copy(color = NB.text3Prod))
            Spacer(Modifier.width(28.dp))
            Spacer(Modifier.weight(1f))
            BasicText(L("CLOSE"), Modifier.hotZoneTap { close() },
                style = NBFont.dot(600, 10f).tracking(0.18f).copy(color = NB.lime1))
        }
        // Two columns at 44%, so the whole contract fits in three screenfuls.
        Column(Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            types.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    pair.forEach { type ->
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            BasicText("${type.raw.uppercase()} · ${type.renderer.name.uppercase()}",
                                style = NBFont.dot(500, 8f).tracking(0.12f).copy(color = NB.text3Prod), maxLines = 1)
                            // Default (centre) anchor, so the scaled panel stays inside its cell.
                            Box(Modifier.size(cw * 0.44f, ph * 0.44f).clipToBounds(), contentAlignment = Alignment.Center) {
                                val shape = RoundedCornerShape(NB.R.hero)
                                Box(
                                    Modifier.requiredSize(cw, ph)
                                        .graphicsLayer { scaleX = 0.44f; scaleY = 0.44f }
                                        .background(NB.carbon2, shape)
                                        .border(1.dp, NB.hairline, shape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    PanelWidgetView(widget = WidgetCatalogue.sample(type), onTap = {})
                                }
                            }
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

object WidgetCatalogue {
    /** Pin the band's result layout without starting a BLE measurement. */
    val balanceResult: PanelWidget
        get() {
            val points = (0 until 22).map { i ->
                val interval = (850 + i * 4).toFloat()
                val variation = ((i % 3 - 1) * 9).toFloat()
                Offset(interval, interval + variation)
            }
            return PanelWidget(type = PanelType.balance, title = L("BALANCE"), sentence = "", data = PanelData.None,
                balance = BalanceAnswer(
                    headline = L("Drive is leading."),
                    note = L("Your beats came at a steadier spacing, which is what effort, caffeine or a busy head all look like from here."),
                    restShare = 0.19,
                    footer = L("67 BPM · SD1 7 MS · SD2 30 MS · 22 BEATS"),
                    points = points))
        }

    /** One envelope per type, with the data shape the contract table gives it. */
    fun sample(type: PanelType): PanelWidget {
        val series = listOf(58.0, 60.0, 58.0, 64.0, 63.0, 62.0, 66.0, 64.0, 69.0, 71.0, 68.0, 72.0)
        return when (type) {
            PanelType.battery -> w(type, MetricNames.bodyBattery, "64 right now.", data = PanelData.Ring(64.0, 100.0, ""))
            PanelType.metric -> w(type, "HEART RATE", "Calm pulse — right where it should be", data = PanelData.None).apply {
                hero = "68 bpm"
                heroSub = L("+4 VS RHR 52 · MEASURED 14:20")
                footer = L("RANGE TODAY 52–172 · BASELINE STEADY")
            }
            // 07 · rule 6 · the board's own text screen, its three lines and no sentence slot.
            PanelType.text -> w(type, "TODAY'S CALL", "4 days since your last lift · legs are fresh", data = PanelData.None).apply {
                tag = PanelTag.move
                headline = HeadlineBlock(eyebrow = L("BATTERY 86% · TARGET 14.5"), headline = L("LIFT TODAY"), sub = L("STRENGTH · 45 MIN"))
                action = L("PRIME WINDOW 17:00 → 20:00")
                footer = L("8,432 STEPS · 7H12M IN BED")
            }
            PanelType.line -> w(type, "HRV · 12 NIGHTS", "62 ms over twelve nights", data = PanelData.Series(series)).apply { hero = "62 ms" }
            PanelType.band -> w(type, "BLOOD PRESSURE", "118 / 76 · in range", data = PanelData.Pair(series.map { it + 50 }, series))
            PanelType.bars -> w(type, "STEPS · 30-MIN", "The evening walk carried the day", data = PanelData.Bins(listOf(
                "06:00" to 120.0, "08:00" to 340.0, "10:00" to 260.0, "12:00" to 410.0,
                "14:00" to 300.0, "16:00" to 620.0, "18:00" to 1904.0, "20:00" to 480.0)))
            PanelType.days -> w(type, "LOAD", "7d avg 13.1", data = PanelData.Bins(listOf(
                "M" to 15.0, "T" to 9.3, "W" to 16.0, "T" to 11.5, "F" to 6.9, "S" to 13.9, "S" to 12.4)))
            PanelType.sparks -> w(type, "LAST NIGHT", "Three inputs, all measured.", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("HRV"), "62 ms", spark = series),
                PanelData.RowItem(L("RHR"), "48 bpm", spark = series.reversed()),
                PanelData.RowItem(L("SPO2"), "97 %", spark = series))))
            PanelType.ring -> w(type, MetricNames.training, "5.0 of 21", data = PanelData.Ring(5.0, 21.0, ""))
            PanelType.gauge -> w(type, "STRESS", "31 · resting", data = PanelData.Gauge(31.0, listOf(
                Triple(0.0, 40.0, "REST"), Triple(40.0, 70.0, "MID"), Triple(70.0, 100.0, "HIGH"))))
            PanelType.cells -> w(type, "WEIGH-INS", "5 of 7 days", data = PanelData.Cells(1, 7, listOf(1, 1, 0, 1, 1, 0, 1), 2))
            // 13 · five columns, minutes per zone.
            PanelType.zones -> w(type, "TIME IN ZONE", "50 min elevated · Z2 carried it",
                data = PanelData.Zones(listOf(25.0, 30.0, 20.0, 8.0, 0.0)))
            // 12 · run-length lanes: 0 awake · 1 light · 2 deep.
            PanelType.hypnogram -> w(type, "SLEEP · 23:41 → 07:18", "Two clean deep blocks before 3 am", data = PanelData.Lanes(
                listOf(0 to 18.0, 1 to 42.0, 2 to 108.0, 1 to 36.0, 2 to 44.0, 1 to 30.0, 0 to 14.0, 1 to 46.0, 0 to 30.0),
                "23:41", "07:18"))
            PanelType.split -> w(type, "SLEEP MIX", "Deep sleep did its job — 24% of the night", hero = "7H38",
                data = PanelData.Parts(listOf(Triple("DEEP", 108.0, NB.violet1), Triple("LIGHT", 324.0, NB.violet1.copy(alpha = 0.6f)),
                    Triple("AWAKE", 26.0, NB.white.copy(alpha = 0.5f)))))
            PanelType.o2night -> w(type, "NIGHT O2", "Mean 95% · lowest 89%",
                data = PanelData.Series(listOf(97.0, 96.0, 96.0, 95.0, 97.0, 96.0, 89.0, 94.0, 96.0, 97.0, 91.0, 96.0)))
            // The RR tachogram: one sample per beat, in milliseconds, so the copy is milliseconds too.
            PanelType.wave -> w(type, "RR INTERVALS", "Steady beat to beat", hero = "48 BEATS", data = PanelData.Trace(
                listOf(812, 796, 824, 808, 788, 832, 800, 776, 820, 804, 796, 840, 812, 784, 808, 828, 792, 816, 800, 780).map { it.toDouble() },
                1.3)).apply { footer = L("MEAN 806 MS · LAST READING") }
            PanelType.table -> w(type, "TODAY'S BUILD", "Three sources, 5.0 total", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("MORNING WALK"), "+2.0"),
                PanelData.RowItem(L("ELEVATED HR"), "+1.3"),
                PanelData.RowItem(L("STEPS"), "+1.7"))))
            PanelType.workout -> w(type, "SESSION", "45 min · avg 136 bpm", hero = "45 MIN", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("STRENGTH"), "45 MIN"),
                PanelData.RowItem(L("AVG HR"), "136"))))
            PanelType.events -> w(type, "TODAY", "Four things happened", hero = "4", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("07:20 BREAKFAST"), "375"),
                PanelData.RowItem(L("07:30 WALK"), "+2.0"),
                PanelData.RowItem(L("12:40 LUNCH"), "532"),
                PanelData.RowItem(L("18:00 SESSION"), "+8.9"))))
            PanelType.heat -> w(type, "WEEK × HOUR", "Evenings are the load", hero = "18:00",
                data = PanelData.Cells(7, 12, (0 until 84).map { (it * 7) % 4 }, 4))
            // 07 · 20 · the plate: one row per food, already on the record.
            PanelType.food -> w(type, "LOGGED · 12:42", "This meal is on the record.", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("CHICKEN"), "220"),
                PanelData.RowItem(L("RICE"), "160"),
                PanelData.RowItem(L("GREENS"), "40")))).apply {
                plate = PlateBlock(name = L("Chicken, rice, greens"), portion = L("1 bowl"), kcal = 420.0,
                    protein = 32.0, carb = 18.0, fat = 22.0, pctOfBudget = 31)
                footer = L("660 KCAL LEFT · KITCHEN CLOSES 21:00")
                action = L("OPEN FUEL")
            }
            // ADR 0018 · the plan face's frame: the tasks are rows, the summary is the sentence.
            PanelType.plan -> w(type, "EASY DAY", "Yesterday was light. Keep it easy, sleep early.", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("BED BY 23:00"), ""),
                PanelData.RowItem(L("WALK 30 MIN"), ""),
                PanelData.RowItem(L("PROTEIN AT DINNER"), ""))))
            PanelType.meal -> w(type, "LUNCH", "532 kcal · 50 g protein", hero = "532", data = PanelData.Rows(listOf(
                PanelData.RowItem(L("CHICKEN"), "310"),
                PanelData.RowItem(L("RICE"), "160"),
                PanelData.RowItem(L("GREENS"), "62"))))
            // ⚠️ fuel's hero is "biggest gap", which the stack shape cannot derive: data.hero.
            PanelType.fuel -> w(type, "MACROS", "Protein is the gap", hero = "61 G PRO", data = PanelData.Parts(listOf(
                Triple("PRO", 84.0, NB.violet1), Triple("CARB", 80.0, NB.optimal2), Triple("FAT", 22.0, NB.run1))))
            // Same reason: the board's hero is "in − out", not either operand.
            PanelType.balance -> w(type, "ENERGY", "907 in · 1,578 out", hero = "−671", data = PanelData.Parts(listOf(
                Triple("IN", 907.0, NB.ember1), Triple("OUT", 1578.0, NB.cyan1))))
            PanelType.recomp -> w(type, "COMPOSITION · 12 W", "Nine of the last twelve weeks moved fat down",
                hero = "−3.1 % FAT", data = PanelData.Cells(7, 12, (0 until 84).map { it % 5 }, 5))
            PanelType.delta -> w(type, "NET CHANGE", "−0.5 kg fat, +2.0 kg lean",
                data = PanelData.Bins(listOf("FAT" to -0.5, "LEAN" to 2.0)))
            PanelType.dual -> w(type, "FAT VS LEAN", "The lines crossed in week 9",
                data = PanelData.Pair(series, series.map { it * 0.8 }))
            // ------------------------------------------------------- 2026-09-06 gap audit
            PanelType.score -> w(type, "SLEEP SCORE", "Architecture is the drag — 42 min deep", hero = "73",
                data = PanelData.Meter(listOf(Triple("DURATION", 78.0, 100.0), Triple("ARCHITECTURE", 61.0, 100.0),
                    Triple("RECOVERY", 84.0, 100.0), Triple("REGULARITY", 92.0, 100.0)))).apply {
                footer = L("6 BELOW YOUR 7-DAY MEAN")
            }
            PanelType.poincare -> {
                // A cloud along the diagonal with a narrow waist: rest-led, spread 48 ms.
                val pts = ArrayList<Offset>()
                var seed = 7.0
                repeat(90) {
                    seed = (seed * 9301 + 49297).rem(233280)
                    val a = seed / 233280
                    seed = (seed * 9301 + 49297).rem(233280)
                    val b = seed / 233280
                    val along = 760 + (a - 0.5) * 220
                    val across = (b - 0.5) * 46
                    pts.add(Offset((along - across).toFloat(), (along + across).toFloat()))
                }
                w(type, "BALANCE CHECK", "Tight cloud, rest side leading", hero = "48 ms",
                    data = PanelData.Scatter(pts, 600.0, 900.0,
                        listOf("SDNN" to "48 ms", "LEAD" to "REST", "REST SHARE" to "64 %"))).apply {
                    footer = L("812 BEATS · 2 MIN 14 S")
                }
            }
            PanelType.matrix -> {
                // 0 not collected · 1 unsupported · 2 failed · 3 partial · 4 complete.
                val m = listOf(
                    listOf(4, 4, 4, 4, 4, 4, 4),
                    listOf(4, 4, 3, 4, 4, 4, 4),
                    listOf(4, 4, 0, 0, 4, 2, 4),
                    listOf(4, 4, 4, 4, 4, 4, 4),
                    listOf(0, 0, 4, 0, 0, 0, 4))
                w(type, "SYNC STATUS", "Body comp is the gap — 5 days missing",
                    data = PanelData.Matrix(5, 7, m.flatten(), listOf(L("HEART"), L("SLEEP"), L("SPO2"), L("STEPS"), L("BODY")))).apply {
                    footer = L("9 OF 35 CELLS NOT COMPLETE")
                }
            }
            PanelType.call -> w(type, "THE CALL", "Weight flat, lean +0.4 kg, fat −0.5 kg",
                data = PanelData.Verdict("RECOMP", listOf("RECOMP", "CUT", "BULK", "DRIFT", "NO_CHANGE"), 2, 3)).apply {
                footer = L("MEDIUM · 4 WEIGH-INS IN 14 DAYS")
            }
            // The day's TRAINING LOAD accumulating towards its full value of 21.
            PanelType.curve -> w(type, "LOAD TODAY", "Two blocks, most of it before noon", hero = "14.2",
                data = PanelData.Series(listOf(0.0, 0.4, 1.2, 2.6, 4.1, 6.8, 9.2, 10.1, 10.3, 10.4, 11.8, 13.6, 14.2))).apply {
                curveMark = 21.0
                footer = L("Z4+Z5 11 MIN · PEAK 178 BPM")
            }
            // Unitless on purpose: the rise over this meal's own baseline. Never a lab unit.
            PanelType.response -> w(type, "MEAL RESPONSE", "Peak at 42 min, back down by 14:05", hero = "+38",
                data = PanelData.Series(listOf(2.0, 1.0, 3.0, 12.0, 26.0, 35.0, 38.0, 34.0, 27.0, 19.0, 12.0, 7.0, 4.0, 3.0, 2.0))).apply {
                curveMarks = listOf(2, 12)
                footer = L("LUNCH · 115 MIN TO BASELINE")
            }
        }
    }

    private fun w(type: PanelType, title: String, sentence: String, hero: String? = null, data: PanelData): PanelWidget =
        PanelWidget(type = type, title = L(title), tag = null, sentence = L(sentence), footer = null, action = null,
            hero = hero, data = data)
}
