package com.nextbody.hoop.features.measurements

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.profile.Chevron
import com.nextbody.hoop.features.profile.spaced
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.MeasurementRecord
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * ADR 0010 · 测量记录。全产品第二个二级页——第一个是设备页。做成页面而不是 sheet，是因为它过了
 * F1 那道门槛：一份按月累积、会一直长的清单，一屏放不下。
 *
 * 返回回「我的」，不回首页。清单里的一行点开是盖在这一页上的 sheet，不是第三级页面。
 */
@Composable
fun MeasurementsView() {
    val kept: List<MeasurementRecord> = if (DebugEdgeFlag.on("empty")) emptyList() else DataStore.measurements

    // 按月分组，月内倒序。⚠️ 这里不做筛选也不做统计：清单只是清单。
    val months = run {
        val zone = ZoneId.systemDefault()
        val key = DateTimeFormatter.ofPattern("yyyy-MM", Locale.US)
        // ⚠️ 每次重建：语言可以在「我的」里当场改，记住旧 locale 的 formatter 会继续印英文月份。
        val label = DateTimeFormatter.ofPattern(if (AppLanguage.isEnglish) "MMMM yyyy" else "yyyy年M月",
            AppLanguage.locale.javaLocale)
        kept.sortedByDescending { it.at }
            .groupBy { key.format(it.at.atZone(zone)) }
            .map { (k, records) -> Triple(k, label.format(records.first().at.atZone(zone)).uppercase(), records) }
    }

    DetailScroll(
        glow = NB.lime1,
        title = L("MEASUREMENTS"),
        onBack = { Router.back() },   // 返回回「我的」——这一页是从那里进来的，不回首页。
        trailing = {
            // ⚠️ KEPT 是留下的行数，不是尝试次数——失败的测量从没进过这张表。
            Text(L("%d KEPT", kept.size), style = NBFont.dot(500, 12f).tracking(0.04f), color = NB.macroValue)
        },
    ) {
        Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 30.dp)) {
            if (kept.isEmpty()) {
                EmptyState()
            } else {
                months.forEach { (_, label, records) ->
                    MonthHeader(label, records.size)
                    records.forEach { record ->
                        MeasurementRow(record) { Router.sheet = SheetRoute.Measurement(record.id) }
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthHeader(label: String, count: Int) {
    Row(Modifier.fillMaxWidth().padding(top = 26.dp, bottom = 10.dp)) {
        Text(label, style = NBFont.dot(700, 11f).tracking(0.24f), color = NB.lime1, modifier = Modifier.alignByBaseline().weight(1f))
        Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
        Text("$count", style = NBFont.dot(500, 11f).tracking(0.04f), color = NB.text2, modifier = Modifier.alignByBaseline())
    }
}

/**
 * 一次都没测过。这一页仍然可达，所以它得有话说，而且说的是怎么开始，不是「暂无数据」。
 */
@Composable
private fun EmptyState() {
    Column(Modifier.padding(top = 26.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(L("NOTHING KEPT YET"), style = NBFont.dot(700, 11f).tracking(0.24f), color = NB.text3Prod)
        Text(
            L("A measurement is you holding the side key — a body scan or a balance check, from the plus menu. Thirty seconds makes the first row."),
            style = NBFont.ui(300, 13.5f).tracking(0.02f).copy(lineHeight = spaced(13.5f, 5f)),
            color = NB.text2,
        )
    }
}

/** 「我的」那块卡上的一行，或者记录页清单上的一行。 */
enum class MeasurementRowStyle {
    /** 一行高，只印日期，没有分隔线也没有箭头。 */
    card,
    /** 两行高，印星期、日期和时刻，带分隔线和箭头。 */
    list,
}

/**
 * 模块和清单画的是同一种行。⚠️ 一份实现——两处各写一遍，是这两块早晚说出不同话的方式。
 * `onTap` 为 null 的行不可点：「我的」那块卡上唯一的热区是底部的 ALL MEASUREMENTS。
 */
@Composable
fun MeasurementRow(
    record: MeasurementRecord,
    modifier: Modifier = Modifier,
    style: MeasurementRowStyle = MeasurementRowStyle.list,
    onTap: (() -> Unit)? = null,
) {
    val list = style == MeasurementRowStyle.list
    Row(
        modifier
            .fillMaxWidth()
            .height(if (list) 60.dp else 34.dp)
            .let { if (onTap != null) it.hotZoneTap(pressedScale = 1f, onClick = onTap) else it }
            .drawBehind {
                if (list) drawRect(NB.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 实心点是身体扫描，空心点是平衡检查。
        Box(
            Modifier.size(8.dp).let {
                if (record.isFilledDot) it.background(NB.lime1, CircleShape) else it.border(1.5.dp, NB.lime1, CircleShape)
            },
        )
        if (list) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(record.title, style = NBFont.ui(500, 12f).tracking(0.06f), color = NB.text1, maxLines = 1)
                Text(MeasurementStamp.list(record.at), style = NBFont.dot(500, 11f), color = NB.macroValue, maxLines = 1)
            }
        } else {
            // 卡上一行只有三样：类型、日期、两个数。日期是固定宽的一栏，三行才对得齐。
            Text(record.title, style = NBFont.ui(500, 12f).tracking(0.06f), color = NB.text1, maxLines = 1)
            Text(MeasurementStamp.day(record.at), style = NBFont.dot(500, 11f), color = NB.text3Prod, maxLines = 1,
                modifier = Modifier.width(44.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text(record.summary, style = NBFont.dot(600, 13f), color = NB.emberPale, maxLines = 1,
            textAlign = TextAlign.End, modifier = Modifier.weight(1f))
        if (onTap != null) Chevron()
    }
}

/** The row and sheet stamps: `FRI 10·23 · 07:10`. */
internal object MeasurementStamp {
    private val dayFormatter = DateTimeFormatter.ofPattern("MM·dd", Locale.US)
    private val timeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    fun day(at: Instant): String = dayFormatter.format(at.atZone(ZoneId.systemDefault()))
    fun time(at: Instant): String = timeFormatter.format(at.atZone(ZoneId.systemDefault()))
    fun list(at: Instant): String = "${Fmt.weekday(at).uppercase()} ${day(at)} · ${time(at)}"
}
