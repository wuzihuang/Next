package com.nextbody.hoop.features.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.HomeTimeline
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/** Historical timeline: day columns share a time-of-day axis instead of stacking event rows. */
@Composable
fun HomeRhythmHistory(
    today: UserDay,
    events: List<HomeTimeline.Item>,
    metrics: List<DailyMetrics>,
    loading: Boolean,
    onBack: () -> Unit,
    onOpen: (HomeTimeline.Item) -> Unit,
    modifier: Modifier = Modifier,
) {
    var range by remember { mutableIntStateOf(30) }
    var selected by remember { mutableStateOf<UserDay?>(null) }

    val days = remember(range, today) { UserDay.last(range, endingAt = today) }
    // Monday = 0.
    val firstWeekday = days[0].start.atZone(ZoneId.systemDefault()).dayOfWeek.value - 1
    val calendarDays: List<UserDay?> = run {
        val filled = List<UserDay?>(firstWeekday) { null } + days
        filled + List<UserDay?>((7 - filled.size % 7) % 7) { null }
    }
    val visibleEvents = events.filter { it.at >= days[0].start && it.at < today.end }

    Box(modifier.fillMaxSize().background(NB.carbon)) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 20.dp, end = 20.dp, top = ScreenMetrics.safeTop + 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "‹ " + L("Today"),
                    style = jost(500, 15f).copy(color = Color.White.copy(alpha = 0.62f)),
                    modifier = Modifier.hotZoneTap(onClick = onBack),
                )
                Spacer(Modifier.width(24.dp))
                Spacer(Modifier.weight(1f))
                Row(
                    Modifier
                        .background(hex(0x141418), CircleShape)
                        .padding(3.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    for (value in listOf(7, 30)) {
                        val on = range == value
                        Box(
                            Modifier
                                .size(39.dp, 25.dp)
                                .background(if (on) NB.lime1 else Color.Transparent, CircleShape)
                                .clickable(remember { MutableInteractionSource() }, null) {
                                    selected = null
                                    range = value
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                if (value == 7) "7D" else "30D",
                                style = NBFont.dot(600, 10f).tracking(0.1f)
                                    .copy(color = if (on) NB.carbon else Color.White.copy(alpha = 0.55f)),
                            )
                        }
                    }
                    val yearLabel = L("Year view unavailable")
                    Box(
                        Modifier.size(39.dp, 25.dp).semantics { contentDescription = yearLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("1Y", style = NBFont.dot(600, 10f).copy(color = Color.White.copy(alpha = 0.25f)))
                    }
                }
            }
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = ScreenMetrics.safeBottom + 20.dp),
            ) {
                val title = (if (range == 30) L("PAST 30 DAYS") else L("PAST 7 DAYS")) +
                    " · " + Fmt.displayDate(days[0].start, "MMM d").uppercase() +
                    " – " + Fmt.displayDate(today.start, "MMM d").uppercase()
                Text(
                    title,
                    style = NBFont.dot(600, 11f).tracking(2f / 11f).copy(color = Color.White.copy(alpha = 0.4f)),
                    maxLines = 1,
                )
                Row(Modifier.padding(bottom = 15.dp)) {
                    Text(
                        "Rhythm",
                        style = timelineInterTight(700, 30f).copy(color = Color.White),
                        modifier = Modifier.alignByBaseline(),
                    )
                    Spacer(Modifier.width(9.dp))
                    Text(
                        L("columns are weekdays"),
                        style = jost(400, 13f).copy(color = Color.White.copy(alpha = 0.48f)),
                        modifier = Modifier.alignByBaseline(),
                    )
                }
                // Weekday header.
                Row(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
                    for (index in 0 until 7) {
                        val date = if (range == 7) days[index].start
                        else days[0].adding(index - firstWeekday).start
                        Text(
                            Fmt.displayDate(date, "EEEEE").uppercase(),
                            style = NBFont.dot(600, 9f).copy(color = Color.White.copy(alpha = 0.35f)),
                            textAlign = TextAlign.Center,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                if (loading) {
                    val loadingLabel = L("Loading history")
                    Box(
                        Modifier.fillMaxWidth().padding(bottom = 8.dp).semantics { contentDescription = loadingLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = NB.lime1, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                    }
                }
                if (range == 30) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (row in 0 until calendarDays.size / 7) {
                            Row(Modifier.fillMaxWidth()) {
                                for (column in 0 until 7) {
                                    val day = calendarDays[row * 7 + column]
                                    if (day != null) {
                                        DayCell(day, today, events, 62.dp, compact = true) { selected = day }
                                    } else {
                                        Spacer(Modifier.weight(1f).height(80.dp))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Row(Modifier.fillMaxWidth()) {
                        for (day in days) {
                            DayCell(day, today, events, 300.dp, compact = false) { selected = day }
                        }
                    }
                }
                // Legend.
                Row(
                    Modifier.fillMaxWidth().padding(top = 17.dp),
                    horizontalArrangement = Arrangement.spacedBy(13.dp, Alignment.CenterHorizontally),
                ) {
                    LegendItem(L("SLEEP"), hex(0x7B83E8).copy(alpha = 0.6f))
                    LegendItem(L("MEAL"), Color.White.copy(alpha = 0.72f))
                    LegendItem(L("ACTIVITY"), NB.lime1)
                    LegendItem(L("STRESS"), NB.ember1)
                }
                // Summary.
                val recorded = metrics.filter { m -> days.contains(m.day) }
                val nights = recorded.mapNotNull { it.sleep?.totalMinutes }.filter { it > 0 }
                val steps = recorded.mapNotNull { it.steps }
                Column(Modifier.padding(top = 20.dp)) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))
                    Row(Modifier.fillMaxWidth().padding(top = 15.dp), verticalAlignment = Alignment.Top) {
                        SummaryValue(L("SLEEP AVG"),
                            if (nights.isEmpty()) Fmt.dash else Fmt.duration(nights.sum() / nights.size))
                        SummaryValue(L("STEPS"),
                            if (steps.isEmpty()) Fmt.dash else Fmt.kcal(steps.sum().toDouble()))
                        SummaryValue(L("WORKOUTS"),
                            if (recorded.isEmpty() && visibleEvents.isEmpty()) Fmt.dash
                            else visibleEvents.count { it.accent == HomeTimeline.Accent.workout }.toString())
                    }
                }
                Text(
                    L("TAP A DAY FOR ITS TIMELINE"),
                    style = NBFont.dot(600, 9f).tracking(1.5f / 9f).copy(color = Color.White.copy(alpha = 0.4f)),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 25.dp),
                )
            }
        }

        var shown by remember { mutableStateOf<UserDay?>(null) }
        if (selected != null) shown = selected
        AnimatedVisibility(
            visible = selected != null,
            enter = fadeIn(tween(200)),
            exit = fadeOut(tween(200)),
        ) {
            shown?.let { day ->
                DayDetail(day, events, onClose = { selected = null }, onOpen = { entry ->
                    selected = null
                    onOpen(entry)
                })
            }
        }
    }
}

@Composable
private fun RowScope.DayCell(
    day: UserDay,
    today: UserDay,
    events: List<HomeTimeline.Item>,
    height: Dp,
    compact: Boolean,
    onSelect: () -> Unit,
) {
    val count = events.count { it.day == day }
    val label = Fmt.displayDate(day.start, "EEE d MMM") + ", " + count + " " + L("events")
    Column(
        Modifier
            .weight(1f)
            .height(height + if (compact) 18.dp else 26.dp)
            .clickable(remember { MutableInteractionSource() }, null, onClick = onSelect)
            .semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(
            Fmt.displayDate(day.start, "d"),
            style = NBFont.dot(600, if (compact) 9f else 11f)
                .copy(color = if (day == today) NB.lime1 else Color.White.copy(alpha = 0.55f)),
        )
        RhythmBar(day, today, events, height, if (compact) 12.dp else 23.dp)
    }
}

@Composable
private fun LegendItem(label: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(7.dp).background(color, RoundedCornerShape(2.dp)))
        Text(
            label,
            style = NBFont.dot(600, 9f).copy(color = Color.White.copy(alpha = 0.5f)),
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
    }
}

@Composable
private fun RowScope.SummaryValue(label: String, value: String) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = NBFont.dot(600, 9f).copy(color = Color.White.copy(alpha = 0.4f)), maxLines = 1)
        Text(value, style = timelineInterTight(600, 16f).copy(color = Color.White))
    }
}

@Composable
private fun DayDetail(
    day: UserDay,
    events: List<HomeTimeline.Item>,
    onClose: () -> Unit,
    onOpen: (HomeTimeline.Item) -> Unit,
) {
    val entries = events.filter { it.day == day }.sortedBy { it.at }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.7f))
                .clickable(remember { MutableInteractionSource() }, null, onClick = onClose),
        )
        Column(
            Modifier
                .fillMaxWidth()
                .background(hex(0x141418), RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                // Swallow taps on the card so they don't reach the scrim.
                .clickable(remember { MutableInteractionSource() }, null) {}
                .padding(20.dp)
                .padding(bottom = ScreenMetrics.safeBottom),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    Fmt.displayDate(day.start, "EEE d MMM").uppercase(),
                    style = NBFont.dot(600, 13f).copy(color = NB.lime1),
                )
                Spacer(Modifier.width(24.dp))
                Spacer(Modifier.weight(1f))
                Text(
                    L("Close"),
                    style = jost(500, 13f).copy(color = Color.White.copy(alpha = 0.6f)),
                    modifier = Modifier.hotZoneTap(onClick = onClose),
                )
            }
            Column(
                Modifier
                    .heightIn(max = 300.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                if (entries.isEmpty()) {
                    Text(L("No events yet"), style = jost(400, 15f).copy(color = Color.White.copy(alpha = 0.6f)))
                }
                for (entry in entries) {
                    val enabled = entry.accent != HomeTimeline.Accent.weighIn
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .hotZoneTap(enabled = enabled, pressedScale = 1f) { onOpen(entry) }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            Fmt.clock(entry.at),
                            style = NBFont.dot(600, 12f).copy(color = Color.White.copy(alpha = 0.6f)),
                            modifier = Modifier.width(45.dp),
                        )
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(entry.title, style = timelineInterTight(500, 15f).copy(color = Color.White))
                            if (entry.detail.isNotEmpty()) {
                                Text(entry.detail, style = jost(400, 12f).copy(color = Color.White.copy(alpha = 0.55f)))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RhythmBar(day: UserDay, today: UserDay, events: List<HomeTimeline.Item>, height: Dp, width: Dp) {
    val span = (day.end.toEpochMilli() - day.start.toEpochMilli()).toFloat()
    fun position(date: Instant): Dp = height * ((date.toEpochMilli() - day.start.toEpochMilli()) / span)
    val shape = RoundedCornerShape(4.dp)
    Box(Modifier.size(width, height), contentAlignment = Alignment.TopCenter) {
    Box(
        Modifier
            .size(width, height)
            .clip(shape)
            .background(hex(0x111116), shape),
        contentAlignment = Alignment.TopCenter,
    ) {
        events.filter { e ->
            e.accent == HomeTimeline.Accent.sleep && e.at < day.end && (e.endAt?.let { it > day.start } ?: false)
        }.forEach { entry ->
            val end = entry.endAt ?: return@forEach
            val top = maxOf(0.dp, position(entry.at))
            val bottom = minOf(height, position(end))
            Box(
                Modifier
                    .offset(y = top)
                    .size(width - 2.dp, maxOf(0.dp, bottom - top))
                    .background(hex(0x7B83E8).copy(alpha = 0.46f)),
            )
        }
        val marked = setOf(
            HomeTimeline.Accent.meal, HomeTimeline.Accent.wake, HomeTimeline.Accent.workout,
            HomeTimeline.Accent.activity, HomeTimeline.Accent.stress,
        )
        events.filter { it.day == day && it.accent in marked }.forEach { entry ->
            val marker = when (entry.accent) {
                HomeTimeline.Accent.meal, HomeTimeline.Accent.wake -> Color.White.copy(alpha = 0.72f)
                HomeTimeline.Accent.workout, HomeTimeline.Accent.activity -> NB.lime1
                HomeTimeline.Accent.stress -> NB.ember1
                else -> Color.Transparent
            }
            val tall = entry.accent == HomeTimeline.Accent.workout || entry.accent == HomeTimeline.Accent.activity
            Box(
                Modifier
                    .offset(y = maxOf(0.dp, minOf(height - 5.dp, position(entry.at))))
                    .size(width - 3.dp, if (tall) 5.dp else 2.dp)
                    .background(marker, RoundedCornerShape(1.dp)),
            )
        }
    }
    // Today: the now line overhangs the column by 2 on each side, the frame is outlined in lime.
    if (day == today) {
        Box(
            Modifier
                .offset(y = max(0f, min(height.value, position(VitalsClock.now).value)).dp)
                .requiredSize(width + 4.dp, 1.dp)
                .background(NB.lime1),
        )
        Box(Modifier.size(width, height).border(1.dp, NB.lime1.copy(alpha = 0.8f), shape))
    }
    }
}
