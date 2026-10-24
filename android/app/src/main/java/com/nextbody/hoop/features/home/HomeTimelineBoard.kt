package com.nextbody.hoop.features.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.R
import com.nextbody.hoop.band.HomeTimeline
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.services.MealPhotoStore
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import java.time.Instant
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * 11-A · Today timeline. The workout pill is chrome, not an event.
 * The top edge is the way home: a lime chevron and "Swipe down for home".
 *
 * [readPull]/[writePull] · sheet progress owned by the deck: 1 is up, 0 is dismissed.
 * ⚠️ Not a state the board reads in composition: the deck writes it on every frame of every
 * pull, and depending on it would rebuild the whole list per frame.
 * [onPullEnd] · finger lifted mid-pull. Velocity is dp per second (positive = down); the
 * second value is where the pull started.
 */
@Composable
fun HomeTimelineBoard(
    events: List<HomeTimeline.Item>,
    earlier: Boolean,
    onHistory: () -> Unit,
    onWorkout: () -> Unit,
    onOpen: (HomeTimeline.Item) -> Unit,
    onClose: () -> Unit,
    readPull: () -> Float,
    writePull: (Float) -> Unit,
    onPullEnd: (velocity: Float, startedAt: Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val rows = remember(events, earlier) {
        if (BuildConfig.DEBUG && DebugEnv["NB_DEBUG_HOME_BOARD"] == "timeline") {
            val day = UserDay.containing(Instant.now())
            HomeTimeline.visible(timelineBoardSample(), on = day, earlier = earlier,
                now = day.end.minusSeconds(1))
        } else events
    }
    val days = remember(rows) { rows.map { it.day }.toSet().sortedDescending() }

    val density = LocalDensity.current
    val currentRead by rememberUpdatedState(readPull)
    val currentWrite by rememberUpdatedState(writePull)
    val currentEnd by rememberUpdatedState(onPullEnd)
    val currentOpen by rememberUpdatedState(onOpen)

    // Plain holders: the pull never needs a recomposition.
    val pull = remember { PullState() }
    var pullEndedAt by remember { mutableLongStateOf(0L) }

    fun dragSheet(translationDp: Float) {
        if (!pull.pulling) {
            pull.pulling = true
            pull.atTouch = currentRead()
        }
        val span = max(ScreenMetrics.height.value, 1f)
        currentWrite(min(1f, max(0f, pull.atTouch - translationDp / span)))
    }

    fun endSheet(velocityDp: Float) {
        val started = pull.atTouch
        pull.pulling = false
        pullEndedAt = System.currentTimeMillis()
        currentEnd(velocityDp, started)
    }

    /** A pull is never a tap: drop the row's lift-off whichever of the two lands first. */
    fun open(event: HomeTimeline.Item) {
        if (pull.pulling || System.currentTimeMillis() - pullEndedAt <= 350) return
        currentOpen(event)
    }

    /** Dragging the hint or the title down carries the sheet with the finger. */
    val headerPull = Modifier.pointerInput(Unit) {
        val tracker = VelocityTracker()
        var dy = 0f
        detectDragGestures(
            onDragStart = { tracker.resetTracking(); dy = 0f },
            onDragEnd = {
                val v = tracker.calculateVelocity().y / density.density
                endSheet(v)
            },
            onDragCancel = { endSheet(0f) },
        ) { change, drag ->
            change.consume()
            tracker.addPosition(change.uptimeMillis, change.position)
            dy += drag.y
            dragSheet(dy / density.density)
        }
    }

    // A downward pull that starts with the list at rest carries the sheet.
    // Upward travel is left to the list so it can still scroll.
    val scroll = rememberScrollState()
    val listPull = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (!pull.listEngaged) return Offset.Zero
                // While the sheet rides the finger the list stays pinned at its top.
                pull.travel = max(0f, pull.travel + available.y)
                dragSheet(pull.travel / density.density)
                return Offset(0f, available.y)
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput) return Offset.Zero
                if (!pull.armed || available.y <= 0f) return Offset.Zero
                pull.listEngaged = true
                pull.travel = max(0f, pull.travel + available.y)
                dragSheet(pull.travel / density.density)
                return Offset(0f, available.y)
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (!pull.listEngaged) return Velocity.Zero
                pull.listEngaged = false
                pull.travel = 0f
                endSheet(available.y / density.density)
                return available
            }
        }
    }

    Column(
        modifier
            .fillMaxSize()
            .background(NB.carbon),
    ) {
        // Pinned under the status bar. The planet's up-chevron opens this sheet; this one sends it home.
        Row(
            Modifier
                .padding(top = ScreenMetrics.safeTop + 2.dp)
                .fillMaxWidth()
                .heightIn(min = 36.dp)
                .hotZoneTap(pressedScale = 1f, onClick = onClose)
                .then(headerPull),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ChevronDownMark()
            Spacer(Modifier.width(6.dp))
            Text(L("Swipe down for home"), style = jost(400, 12f).copy(color = NB.white.copy(alpha = 0.62f)))
        }
        Row(
            Modifier
                .fillMaxWidth()
                .then(headerPull)
                .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = if (rows.isEmpty()) 8.dp else 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    if (earlier) L("Past 7 days") else L("Today"),
                    style = timelineInterTight(700, 30f).tracking(-0.02f).copy(color = Color.White),
                    modifier = Modifier.alignByBaseline(),
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    L("%d events", rows.size),
                    style = jost(400, 13f).copy(color = Color.White.copy(alpha = 0.48f)),
                    modifier = Modifier.alignByBaseline(),
                )
            }
            Spacer(Modifier.width(24.dp))
            Spacer(Modifier.weight(1f))
            Row(
                Modifier
                    .hotZoneTap(pressedScale = 0.97f, onClick = onWorkout)
                    .background(NB.lime1, CircleShape)
                    .padding(start = 13.dp, end = 15.dp, top = 7.dp, bottom = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PlayMark()
                Spacer(Modifier.width(6.dp))
                Text(L("Workout"), style = jost(600, 13f).tracking(0.01f).copy(color = NB.carbon))
            }
        }
        if (rows.isEmpty()) {
            Column(
                Modifier.padding(horizontal = 20.dp, vertical = 18.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(L("No events yet"), style = timelineInterTight(600, 17f).copy(color = Color.White))
                Text(
                    L("Meals, workouts, sleep, weigh-ins and measurements appear here."),
                    style = jost(400, 15f).copy(color = Color.White.copy(alpha = 0.72f)),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                )
            }
        }
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .pointerInput(Unit) {
                    // Armed only when the touch lands with the list at rest at its top.
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        pull.armed = scroll.value == 0
                        pull.travel = 0f
                    }
                }
                .nestedScroll(listPull)
                .verticalScroll(scroll)
                .padding(start = 20.dp, end = 20.dp, bottom = ScreenMetrics.safeBottom + 12.dp),
        ) {
            for (day in days) {
                if (earlier) {
                    Text(
                        Fmt.displayDate(day.start, "EEE d MMM").uppercase(),
                        style = jost(500, 12f).tracking(0.08f).copy(color = Color.White.copy(alpha = 0.48f)),
                        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
                    )
                }
                val entries = rows.filter { it.day == day }
                entries.forEachIndexed { index, event ->
                    TimelineRailRow(event, continues = index < entries.size - 1, onOpen = { open(event) })
                }
            }
            Text(
                L("View history →"),
                style = jost(400, 14f).copy(color = Color.White.copy(alpha = 0.55f)),
                modifier = Modifier
                    .fillMaxWidth()
                    .hotZoneTap(pressedScale = 1f, onClick = onHistory)
                    .padding(vertical = 18.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

private class PullState {
    var pulling = false
    var atTouch = 1f
    var armed = false
    var listEngaged = false
    var travel = 0f
}

@Composable
private fun TimelineRailRow(event: HomeTimeline.Item, continues: Boolean, onOpen: () -> Unit) {
    val tap = if (event.accent == HomeTimeline.Accent.weighIn) Modifier
    else Modifier.hotZoneTap(pressedOpacity = 0.72f, pressedScale = 1f, onClick = onOpen)
    Row(
        Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .then(tap),
    ) {
        Text(
            Fmt.clock(event.at),
            style = NBFont.dot(700, 13f).copy(color = Color.White.copy(alpha = 0.72f)),
            modifier = Modifier.width(44.dp).padding(top = 2.dp),
            maxLines = 1,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.width(12.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.padding(top = 7.dp).size(7.dp).background(dotColor(event.accent), CircleShape))
            if (continues) {
                Box(
                    Modifier
                        .padding(top = 6.dp)
                        .width(1.dp)
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.12f)),
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(
            Modifier
                .weight(1f)
                .padding(bottom = if (continues) 22.dp else 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                Text(
                    event.title,
                    style = timelineInterTight(600, 15f).copy(color = Color.White),
                    // The title takes every point the trailing number leaves; a spacer sharing
                    // the weight halved the line and wrapped short titles.
                    modifier = Modifier.weight(1f).alignByBaseline(),
                )
                event.trailing?.let {
                    Text(
                        it,
                        style = NBFont.dot(700, 13f).copy(color = Color.White.copy(alpha = 0.56f)),
                        modifier = Modifier.padding(start = 24.dp).alignByBaseline(),
                    )
                }
            }
            event.meal?.let { MealCard(it) }
            if (event.detail.isNotEmpty()) {
                if (event.meal != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SteadyWave()
                        Spacer(Modifier.width(10.dp))
                        Text(event.detail, style = jost(400, 13f).copy(color = Color.White.copy(alpha = 0.56f)))
                    }
                } else {
                    Text(event.detail, style = jost(400, 13f).copy(color = Color.White.copy(alpha = 0.56f)))
                }
            }
        }
    }
}

private fun dotColor(accent: HomeTimeline.Accent): Color = when (accent) {
    HomeTimeline.Accent.meal -> Color.White.copy(alpha = 0.35f)
    HomeTimeline.Accent.stress -> NB.ember1
    HomeTimeline.Accent.workout, HomeTimeline.Accent.activity -> NB.lime1
    HomeTimeline.Accent.sleep, HomeTimeline.Accent.wake -> Color.White.copy(alpha = 0.35f)
    HomeTimeline.Accent.weighIn, HomeTimeline.Accent.bodyScan, HomeTimeline.Accent.balanceCheck ->
        Color.White.copy(alpha = 0.55f)
}

@Composable
private fun MealCard(meal: HomeTimeline.Meal) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .background(hex(0x141418), shape)
            .border(1.dp, Color.White.copy(alpha = 0.06f), shape)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        meal.photoPath?.let {
            TimelineMealThumbnail(it, 64.dp, 12.dp)
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row {
                Text("${meal.kcal}", style = NBFont.dot(700, 22f).copy(color = Color.White), modifier = Modifier.alignByBaseline())
                Spacer(Modifier.width(4.dp))
                Text("kcal", style = jost(400, 12f).copy(color = Color.White.copy(alpha = 0.56f)), modifier = Modifier.alignByBaseline())
            }
            BoxWithConstraints(Modifier.fillMaxWidth().height(4.dp)) {
                val segments = listOf(meal.protein to NB.optimal2, meal.carb to NB.lime1, meal.fat to NB.run1)
                    .filter { it.first > 0 }
                val total = segments.sumOf { it.first }
                val width = maxWidth - 2.dp * max(segments.size - 1, 0)
                if (segments.isEmpty()) {
                    Box(Modifier.fillMaxSize().background(NB.barTrack, CircleShape))
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        for ((value, tint) in segments) {
                            Box(Modifier.width(width * (value.toFloat() / total)).fillMaxHeight().background(tint))
                        }
                    }
                }
            }
            Text(
                L("Protein %dg · Carbs %dg · Fat %dg", meal.protein, meal.carb, meal.fat),
                style = jost(400, 12f).copy(color = Color.White.copy(alpha = 0.72f)),
            )
        }
    }
}

/** A plate thumbnail that fills its frame, or a quiet tile while there is nothing to show. */
@Composable
private fun TimelineMealThumbnail(path: String, side: Dp, radius: Dp) {
    val generation by MealPhotoStore.generation.collectAsState()
    val image = remember(path, generation) { MealPhotoStore.image(path) }
    val shape = RoundedCornerShape(radius)
    if (image != null) {
        Image(
            image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(side).clip(shape),
        )
    } else {
        Box(Modifier.size(side).clip(shape).background(NB.carbon3, shape).border(1.dp, NB.hairline, shape))
    }
}

@Composable
private fun SteadyWave() {
    Canvas(Modifier.size(72.dp, 18.dp)) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(0f, h * 0.65f)
            cubicTo(w * 0.15f, h * 0.65f, w * 0.25f, h * 0.3f, w * 0.4f, h * 0.3f)
            cubicTo(w * 0.6f, h * 0.3f, w * 0.75f, h * 0.6f, w, h * 0.6f)
        }
        drawPath(path, Color.White.copy(alpha = 0.72f), style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round))
    }
}

@Composable
private fun PlayMark() {
    Canvas(Modifier.size(9.dp, 10.dp)) {
        val u = 1.dp.toPx()
        val path = Path().apply {
            moveTo(1 * u, 1 * u)
            lineTo(8 * u, 5 * u)
            lineTo(1 * u, 9 * u)
            close()
        }
        drawPath(path, NB.carbon)
    }
}

/** Same stroke as the planet's up-chevron, turned down; it bobs while the sheet is up. */
@Composable
private fun ChevronDownMark() {
    val reduceMotion = rememberReduceMotion()
    val artActive = LocalHomeArtActive.current
    var wave by remember { mutableStateOf(0f) }
    androidx.compose.runtime.LaunchedEffect(reduceMotion, artActive) {
        if (reduceMotion) { wave = 0f; return@LaunchedEffect }
        if (!artActive) return@LaunchedEffect
        while (isActive) {
            wave = sin(System.currentTimeMillis() / 1000.0 * 2.4).toFloat()
            delay(50)
        }
    }
    Canvas(
        Modifier
            .size(16.dp, 10.dp)
            .offset(y = (wave * 2).dp),
    ) {
        val u = 1.dp.toPx()
        val path = Path().apply {
            moveTo(2 * u, 2 * u)
            lineTo(size.width / 2, size.height - 2 * u)
            lineTo(size.width - 2 * u, 2 * u)
        }
        drawPath(path, NB.lime1, style = Stroke(width = 1.4f * u, cap = StrokeCap.Square, join = StrokeJoin.Miter))
    }
}

/** Inter Tight by name (iOS `.custom("InterTight-…")`), without the pixel primary. */
internal fun timelineInterTight(weight: Int, size: Float): TextStyle {
    val res = when {
        weight < 350 -> R.font.inter_tight_light
        weight < 450 -> R.font.inter_tight_regular
        weight < 550 -> R.font.inter_tight_medium
        weight < 650 -> R.font.inter_tight_semi_bold
        weight < 750 -> R.font.inter_tight_bold
        weight < 850 -> R.font.inter_tight_extra_bold
        else -> R.font.inter_tight_black
    }
    return timelineInterTightCache.getOrPut(res) { TextStyle(fontFamily = FontFamily(Font(res))) }.copy(fontSize = size.sp)
}

private val timelineInterTightCache = HashMap<Int, TextStyle>()

private fun timelineBoardSample(): List<HomeTimeline.Item> {
    val day = UserDay.containing(Instant.now())
    val zone = ZoneId.systemDefault()
    fun at(h: Int, m: Int): Instant =
        day.start.atZone(zone).withHour(h).withMinute(m).withSecond(0).toInstant()
    return listOf(
        HomeTimeline.Item("lunch", at(12, 45), "Lunch · chicken rice bowl", "", HomeTimeline.Accent.meal,
            HomeTimeline.Meal(620, 38, 72, 18), null),
        HomeTimeline.Item("stress", at(11, 30), "Stress peak · 68", "Highest recorded stress that day.",
            HomeTimeline.Accent.stress, null, null),
        HomeTimeline.Item("move", at(8, 15), "Morning mobility", "08:15–08:37 · 22 min · 142 kcal",
            HomeTimeline.Accent.workout, null, "+2.4"),
        HomeTimeline.Item("scan", at(7, 25), "Body scan", "18.9% · 55.5 KG", HomeTimeline.Accent.bodyScan, null, null),
        HomeTimeline.Item("weight", at(7, 20), "Weigh-in", "68.4 KG · Manual entry", HomeTimeline.Accent.weighIn, null, null),
        HomeTimeline.Item("wake", at(7, 12), "Woke up · sleep 82", "7h 12m · HRV 54 ms · SpO2 97%",
            HomeTimeline.Accent.wake, null, null),
        HomeTimeline.Item("sleep", at(23, 50).atZone(zone).minusDays(1).toInstant(), "Fell asleep",
            "Recorded by NEXTBODY", HomeTimeline.Accent.sleep, null, null),
    )
}
