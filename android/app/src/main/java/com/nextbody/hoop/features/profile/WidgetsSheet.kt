package com.nextbody.hoop.features.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L

/**
 * TODAY, and how to put it on the home screen.
 *
 * ⚠️ This sheet exists because of a funnel nobody could see. A background pull is only scheduled
 * when a widget is installed — without one there is no reader, so the app does not light up the
 * radio (ADR 0026) — and nothing else in the product ever says the word "widget".
 *
 * The preview is drawn, not screenshotted: a picture of numbers from somebody else's day would be
 * the one thing on this page making a claim.
 */
@Composable
fun WidgetsSheet(close: () -> Unit) {
    SheetFrame(title = L("Widgets"), fillsHeight = false, footer = { LimePill(L("Done")) { close() } }) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            TodayFace()
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Step(1, L("Touch and hold an empty spot on your home screen."))
                // Android's launcher lists widgets by app, behind its own Widgets key.
                Step(2, L("Tap Widgets, then find NEXTBODY."))
                Step(3, L("Pick TODAY and add it."))
            }
            Text(
                L("A widget is also the only reader the app syncs for in the background. With one on your home screen the day's numbers stay current between opens; without one, nothing is fetched until you open the app."),
                style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            )
        }
    }
}

@Composable
private fun Step(number: Int, text: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(20.dp).border(1.dp, NB.lime1.copy(alpha = 0.4f), CircleShape), contentAlignment = Alignment.Center) {
            Text("$number", style = NBFont.dot(700, 11f), color = NB.lime1)
        }
        Text(text, style = NBFont.ui(400, 13.5f), color = NB.text1, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(0.dp)) // 10 + 0, as SwiftUI spaces before the trailing Spacer
    }
}

@Composable
private fun TodayFace() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(
            Modifier
                .size(132.dp)
                .background(NB.carbon, RoundedCornerShape(22.dp))
                .border(1.dp, NB.hairline, RoundedCornerShape(22.dp))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(MetricNames.bodyBattery, style = NBFont.dot(600, 7f).tracking(0.18f), color = NB.white.copy(alpha = 0.4f))
            Text("72", style = NBFont.dot(700, 30f), color = NB.lime1)
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MiniFact(L("LOAD"), "12.4", NB.lime1)
                MiniFact(L("EATEN"), "1,240", NB.ember1)
            }
        }
        Text(L("TODAY"), style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.text3Prod)
    }
}

@Composable
private fun MiniFact(label: String, value: String, tint: Color) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label, style = NBFont.dot(600, 7f).tracking(0.18f), color = NB.white.copy(alpha = 0.4f))
        Text(value, style = NBFont.dot(700, 12f), color = tint)
    }
}
