package com.nextbody.hoop.features.measurements

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.profile.SheetFrame
import com.nextbody.hoop.features.profile.spaced
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.MeasurementRecord
import java.time.Instant
import java.util.Locale
import java.util.UUID

/**
 * ADR 0010 · 一条测量记录的全部字段，盖在清单上。**只读**：没有删除，没有编辑，没有分享，
 * 也没有「去成分详情页」——两个详情页之间没有路。
 */
@Composable
fun MeasurementSheet(id: UUID, close: () -> Unit) {
    val record = DataStore.measurements.firstOrNull { it.id == id }
    Box(Modifier.fillMaxSize().background(NB.carbon2)) {
        when (val d = record?.detail) {
            is MeasurementRecord.BodyScan -> BodyScan(d, record.at)
            is MeasurementRecord.BalanceCheck -> BalanceCheck(d, record.at)
            null -> {
                // 上一条记录被另一次读取换掉了（换账号、重新拉取）。不猜，也不留空白。
                SheetFrame(title = L("Measurement")) {
                    Text(L("This record isn't loaded any more."), style = NBFont.ui(300, 13.5f).tracking(0.02f), color = NB.text2)
                }
            }
        }
    }
}

// MARK: 身体扫描

@Composable
private fun BodyScan(scan: MeasurementRecord.BodyScan, at: Instant) {
    SheetFrame(title = L("Body scan")) {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Stamp("${stamp(at)} · ${L("BAND BIA")}")
            // 顶部这两个大数就是清单行右列那两个数——同一条记录在两处必须说同一句话。
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                BigNumber(L("BODY FAT"), scan.bodyFatPercent?.let { "${Fmt.kg(it)} %" } ?: Fmt.dash, NB.lime1)
                BigNumber(L("LEAN MASS"), scan.leanMassKg?.let { "${Fmt.kg(it)} KG" } ?: Fmt.dash, NB.emberPale)
            }
            Column {
                Field(L("FAT MASS"), scan.fatMassKg?.let { "${Fmt.kg(it)} KG" })
                Field(L("BMR ESTIMATE"), scan.bmrKcal?.let { "${Fmt.kcal(it.toDouble())} KCAL/DAY" })
                // ⚠️ 手环不产生体重。这一行必须说明这个数是我们推下去的，否则读起来像手环把人称了一遍。
                Field(L("INPUT WEIGHT"), scan.inputWeightKg?.let { "${Fmt.kg(it)} KG" }, last = true)
            }
            Text(
                L("The band has no scale. Its BIA numbers are computed from the weight this app sent down, so a wrong weight moves every field here."),
                style = NBFont.ui(300, 12f).tracking(0.02f).copy(lineHeight = spaced(12f, 4f)), color = NB.text3Prod,
            )
        }
    }
}

// MARK: 平衡检查

@Composable
private fun BalanceCheck(check: MeasurementRecord.BalanceCheck, at: Instant) {
    SheetFrame(title = L("Balance check")) {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Stamp("${stamp(at)} · 40 S")
            // ⚠️ 没有曲线。大数是结论词，不是波形，也不是一条可以被读成心电的东西。
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(L("WHICH SIDE LED"), style = NBFont.ui(500, 11f).tracking(0.16f), color = NB.text3Prod)
                Text(check.lead.word, style = NBFont.dot(700, 36f), color = NB.lime1)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                SmallNumber(L("HEART RATE"), check.heartRate?.let { "$it BPM" } ?: Fmt.dash)
                SmallNumber(L("BEATS"), "${check.beatCount}")
                // ⚠️ 这个词只能叫 SPREAD。它是这次四十秒采样的 SD1，不是 RMSSD，也不是夜间 HRV。
                SmallNumber(L("SPREAD"), String.format(Locale.US, "%.0f MS", check.spreadMs))
            }
            Text(
                L("Forty seconds of beat-to-beat spacing, kept as a summary. The rhythm itself was not recorded."),
                style = NBFont.ui(300, 12f).tracking(0.02f).copy(lineHeight = spaced(12f, 4f)), color = NB.text3Prod,
            )
        }
    }
}

// MARK: pieces

@Composable
private fun Stamp(text: String) {
    Text(text, style = NBFont.dot(500, 12f).tracking(0.04f), color = NB.macroValue)
}

@Composable
private fun RowScope.BigNumber(label: String, value: String, tint: Color) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = NBFont.ui(500, 11f).tracking(0.16f), color = NB.text3Prod)
        Text(value, style = NBFont.dot(700, 30f), color = tint, maxLines = 1)
    }
}

@Composable
private fun RowScope.SmallNumber(label: String, value: String) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = NBFont.ui(500, 11f).tracking(0.16f), color = NB.text3Prod)
        Text(value, style = NBFont.dot(600, 20f), color = NB.text1, maxLines = 1)
    }
}

/** 缺的字段印 ——，不隐藏：一行不见了，读的人不知道是没测到还是产品不给看。 */
@Composable
private fun Field(label: String, value: String?, last: Boolean = false) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(38.dp)
            .drawBehind {
                if (!last) drawRect(NB.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = NBFont.ui(500, 12f).tracking(0.08f), color = NB.text2, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(24.dp)) // 8 + 8 + 8, as SwiftUI spaces around the Spacer
        Text(value ?: Fmt.dash, style = NBFont.dot(600, 13f), color = NB.text1, maxLines = 1)
    }
}

private fun stamp(at: Instant): String = MeasurementStamp.list(at)
