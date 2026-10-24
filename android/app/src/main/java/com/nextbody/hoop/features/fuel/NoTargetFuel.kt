package com.nextbody.hoop.features.fuel

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.lineSkin

/**
 * 补屏 B · NO TARGET 整屏 — 09 板 · 四块不是六块 · ONE ACTION.
 *
 * Shown only to an account that has never had a weight (rule 07). The page says what it *can*
 * count without a denominator, and what a weigh-in turns on. Rule 08: what disappears is the bar,
 * not the number. Rule 09: any subtraction with a —— in it is ——, never 0. Rule 11: the last
 * block is text only.
 */
@Composable
fun NoTargetFuel() {
    val data = DataStore
    val m = data.today
    val ink = hex(0xF4F4F6)
    val sub = hex(0x8A8A93)
    val context = LocalContext.current

    // Same header as the page with a target, so the two never feel like two apps.
    DetailScroll(
        glow = NB.ember1, title = L("CALORIES"), onBack = { Router.backToRoot() },
        trailing = {
            Text(L("%@ ALLOWANCE", Fmt.dash), style = NBFont.dot(700, 12f).tracking(0.04f), color = NB.emberPale)
        },
    ) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)) {
            // NO ALLOWANCE · the one action
            Column(Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(L("NO ALLOWANCE"), style = NBFont.dot(700, 11f).tracking(0.24f), color = NB.ember1)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(Fmt.dash, style = NBFont.dot(800, 64f), color = NB.white.copy(alpha = 0.24f))
                    Text(L("KCAL ALLOWANCE"), style = NBFont.dot(600, 11f).tracking(0.2f), color = NB.text3Prod)
                }
                Text(L("Targets are built from your body weight. Without it, NEXTBODY can count what you eat, but it can't tell you how much you need."),
                    style = NBFont.ui(300, 15f).copy(lineHeight = (15 + 8).sp), color = sub)
                // 1F5B · one 298 × 52 pill, the screen's only action.
                Box(
                    Modifier.size(298.dp, 52.dp)
                        .hotZoneTap { Router.sheet = SheetRoute.WeighIn }
                        .background(NB.lime1, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(L("Add a weigh-in"), style = NBFont.ui(500, 13.5f).tracking(0.15f), color = NB.carbon)
                }
                Text(L("Type it in, or pull the latest from Health Connect."),
                    style = NBFont.ui(300, 13f).copy(lineHeight = (13 + 6).sp), color = sub)
            }

            // LOGGED TODAY · counts, not comparisons
            Column(Modifier.width(NB.Layout.contentWidth).lineSkin(top = 18.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(L("LOGGED TODAY"), style = NBFont.dot(600, 11f).tracking(0.24f), color = NB.text3Prod)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(Fmt.kcal(m.eIn), Modifier.alignByBaseline(), style = NBFont.dot(800, 44f),
                            color = if (m.eIn == null) NB.white.copy(alpha = 0.24f) else NB.ember1)
                        Text(L("KCAL EATEN"), Modifier.alignByBaseline(), style = NBFont.dot(600, 11f).tracking(0.2f),
                            color = NB.text3Prod)
                    }
                    Text(mealsLine(), style = NBFont.ui(300, 13f), color = sub)
                }
                Row {
                    Gram(L("PROTEIN"), m.protein?.eaten ?: m.proteinIn, ink, Modifier.width(102.dp))
                    Gram(L("CARBS"), m.carb?.eaten ?: m.carbIn, ink, Modifier.width(91.dp))
                    Gram(L("FAT"), m.fat?.eaten ?: m.fatIn, ink, Modifier.width(80.dp))
                }
                Text(L("No targets to compare them to yet."), style = NBFont.ui(300, 13f), color = sub)
            }

            // THE BAND COUNTED · true without a weight
            Column(Modifier.width(NB.Layout.contentWidth).lineSkin(top = 18.dp)) {
                Text(L("THE BAND COUNTED"), Modifier.padding(bottom = 8.dp),
                    style = NBFont.dot(600, 11f).tracking(0.24f), color = NB.text3Prod)
                CountRow(L("Steps"), m.steps?.let { Fmt.int(it) } ?: Fmt.dash, ink)
                CountRow(L("Distance"), distance(context, m.distanceM), ink)
                CountRow(L("Active minutes"), m.activeMinutes?.toString() ?: Fmt.dash, ink)
                val needs = L("Needs you")
                Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Burn"), Modifier.weight(1f), style = NBFont.ui(400, 15f), color = ink)
                    // 8 + 0 + 8, as SwiftUI spaces around the Spacer
                    Spacer(Modifier.width(16.dp))
                    Text(L("NEEDS YOUR WEIGHT"), Modifier.semantics { contentDescription = needs },
                        style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.ember1)
                    Text(Fmt.dash, Modifier.padding(start = 18.dp), style = NBFont.dot(600, 15f),
                        color = NB.white.copy(alpha = 0.32f))
                }
            }

            // WHAT A WEIGH-IN TURNS ON · text only (rule 11)
            Column(Modifier.width(NB.Layout.contentWidth).lineSkin(top = 18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("WHAT A WEIGH-IN TURNS ON"), style = NBFont.dot(600, 11f).tracking(0.24f), color = NB.text3Prod)
                listOf(
                    "A calorie target for the day, and how far you are from it.",
                    "Protein, carbs and fat measured against a target, not just a total.",
                    "Energy gap — what you ate minus what the band burned.",
                    "NEXTBODY can finally answer \"how much more should I eat today?\"",
                ).forEach { line ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.padding(top = 9.dp).size(4.dp).background(NB.ember1, CircleShape))
                        // Swift prints the English source here (no L()); kept as-is.
                        Text(line, style = NBFont.ui(300, 14f).copy(lineHeight = (14 + 7).sp), color = sub)
                    }
                }
            }
            FastingAction(day = m.day)
        }
    }
}

private fun mealsLine(): String {
    val m = DataStore.today
    if (m.fuelState == com.nextbody.hoop.model.FuelState.Fasted) return L("Recorded: nothing eaten today")
    val n = DataStore.meals.count { it.status == MealEntry.Status.confirmed }
    return when (n) {
        0 -> L("nothing yet")
        1 -> L("from %d meal", n)
        else -> L("from %d meals", n)
    }
}

private fun distance(context: Context, d: Int?): String {
    if (d == null) return Fmt.dash
    // Swift reads UserDefaults "nb.units"; the Android port keeps it in the default prefs.
    val units = context.getSharedPreferences(context.packageName + "_preferences", Context.MODE_PRIVATE)
        .getString("nb.units", null)
    return if (units == "imperial") swiftFormat("%.1f mi", d.toDouble() / 1609.344)
    else swiftFormat("%.1f km", d.toDouble() / 1000)
}

@Composable
private fun Gram(label: String, g: Int?, ink: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.text3Prod)
        Text(g?.let { "$it g" } ?: Fmt.dash, style = NBFont.brand(500, 16f), color = ink)
    }
}

@Composable
private fun CountRow(label: String, value: String, ink: androidx.compose.ui.graphics.Color) {
    Row(
        Modifier.fillMaxWidth().height(44.dp).drawBehind {
            drawRect(NB.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), style = NBFont.ui(400, 15f), color = ink)
        Spacer(Modifier.width(16.dp))
        Text(value, style = NBFont.dot(600, 15f), color = if (value == Fmt.dash) NB.white.copy(alpha = 0.32f) else ink)
    }
}
