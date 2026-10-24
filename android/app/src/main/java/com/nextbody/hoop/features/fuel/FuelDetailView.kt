package com.nextbody.hoop.features.fuel

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.FuelCardMath
import com.nextbody.hoop.band.FuelDayFacts
import com.nextbody.hoop.band.FuelWeekRoll
import com.nextbody.hoop.band.FuelWindowMath
import com.nextbody.hoop.band.PortionMath
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.Replace
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.composition.PagerButton
import com.nextbody.hoop.features.training.SegmentedPills
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.FuelState
import com.nextbody.hoop.model.MacroSlot
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.profile.FieldBox
import com.nextbody.hoop.features.profile.SheetFrame
import com.nextbody.hoop.features.profile.TimeFieldBox
import com.nextbody.hoop.services.MealFavorites
import com.nextbody.hoop.services.MealQueue
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.queueScope
import com.nextbody.hoop.model.settingHour
import kotlinx.coroutines.launch
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.swiftSpring
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

/**
 * 09 / ADR 0014 · calories. DAY is the clock plus one food table; WEEK and MONTH are rolling
 * windows of the same page. LOG A MEAL is an ember state that opens a plate over a pressed-down
 * page. [focus] is 09 edge 5's PAST DAY (Router `Destination.FuelDay`); null lands on today.
 */
@Composable
fun FuelDetailView(focus: UserDay? = null) {
    val data = DataStore
    val today = UserDay.containing(Instant.now())

    var plate by remember { mutableStateOf<FuelPlate?>(null) }
    /** Paper 09H · DAY / WEEK / MONTH. Default lands on the clock. */
    var rangeRaw by remember { mutableStateOf(RollingPills.day.raw) }
    /** 09 edge 5 · PAST DAY. Range-limited to 7 user days (F2 §08). */
    var day by remember(focus) { mutableStateOf(focus ?: today) }
    val range = RollingPills.parse(rangeRaw)
    val isPast = day < today

    // The day's own rows: today's from `meals`, a past day's from the week window.
    val dayMeals: List<MealEntry> = run {
        if (DebugEdgeFlag.on("unlogged") || DebugEdgeFlag.on("fasted")) return@run emptyList()
        val own = data.meals.filter { it.day == day && it.status == MealEntry.Status.confirmed }
        val window = data.recentMeals.filter { r -> r.day == day && own.none { it.id == r.id } }
        (own + window).sortedBy { it.at }
    }
    val m = fuelRow(data, day, isPast, dayMeals)
    val logged = m.eIn != null
    val pastTitle = Fmt.displayDate(day.start, "EEE d MMM").uppercase()
    /** 09H · a day is closed when its user-day window has ended. */
    val closed = isPast || day.isClosed
    /** 09 edge 2 · OUT is trusted only when the day's activity data covers the day so far.
     *  ⚠️ Half of the elapsed day is the working value until the threshold is ruled. */
    val outUnknown = run {
        if (DebugEdgeFlag.on("outunknown")) return@run true
        val curve = data.history.firstOrNull { it.day == m.day && it.loadCurve.isNotEmpty() }?.loadCurve ?: m.loadCurve
        val coverageHours = curve.size.toDouble() * 5 / 60
        // A closed day is judged on the whole day it had, not on the clock.
        val elapsed = minOf(Instant.now(), m.day.end).timeIntervalSince(m.day.start) / 3600
        elapsed > 6 && coverageHours < elapsed * 0.5
    }
    /** 补屏 B rule 07 · NO TARGET is for an account that has never had a weight. */
    val noTarget = (Band.allowsSeed && DebugEnv["NB_DEBUG_NO_TARGET"] == "1") ||
        (data.weighIns.isEmpty() && m.weightKg == null && m.targetIn == null)

    val windowRequest = Router.windowRequest
    LaunchedEffect(windowRequest) {
        if (windowRequest != null) {
            rangeRaw = windowRequest
            Router.windowRequest = null
        }
    }
    LaunchedEffect(day) {
        SupabaseClient.currentUserIdSnapshot()?.let { MealQueue.refreshStatus(it) }
        DetailWindow.debugRange(DetailSurface.fuel)?.let { rangeRaw = it.raw }
        // `NB_DEBUG_FUEL_PLATE=1` opens LOG A MEAL; `=edit` opens the edit plate on the day's
        // first meal, which no harness can reach by tapping a seeded row.
        when (DebugEnv["NB_DEBUG_FUEL_PLATE"] ?: "") {
            "1" -> plate = FuelPlate.Log
            "edit" -> dayMeals.firstOrNull()?.let { plate = FuelPlate.Edit(it) }
        }
        if (Band.allowsSeed) return@LaunchedEffect
        Repository.hydrate(DetailWindow(DetailSurface.fuel, RollingPills.parse(rangeRaw)), endingAt = today, focus = day, store = data)
    }

    Box(Modifier.fillMaxSize()) {
        if (noTarget) NoTargetFuel()
        else PlatedPage(
            plate = plate,
            onClosePlate = { plate = null },
            day = day,
        ) {
            FuelPage(
                data = data, m = m, day = day, today = today, isPast = isPast, range = range,
                rangeRaw = rangeRaw, onRange = { rangeRaw = it },
                onDay = { day = it }, dayMeals = dayMeals, logged = logged, closed = closed,
                outUnknown = outUnknown, pastTitle = pastTitle,
                onEdit = { meal -> if (data.canEdit(meal)) plate = FuelPlate.Edit(meal) },
            )
        }

        // safeAreaInset(edge: .bottom): the receipt rides above the home indicator.
        AnimatedVisibility(
            visible = data.mealReceipt != null,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = ScreenMetrics.safeBottom + 8.dp),
            enter = slideInVertically(swiftSpring(0.34f, 0.86f)) { it } + fadeIn(),
            exit = slideOutVertically(swiftSpring(0.34f, 0.86f)) { it } + fadeOut(),
        ) {
            MealReceiptBar()
        }
        if (data.mealReceipt == null) {
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = ScreenMetrics.safeBottom)) {
                if (MealQueue.rejected.isNotEmpty()) RejectedMeals(data)
                else if (MealQueue.pendingCount > 0 && MealQueue.lastError != null) {
                    Text(L("Meal changes are saved on this device and waiting to sync."),
                        Modifier.fillMaxWidth().background(NB.carbon4).padding(12.dp),
                        style = NBFont.ui(400, 12f), color = NB.text1)
                }
            }
        }
    }
}

@Composable
private fun RejectedMeals(data: DataStore) {
    Column(Modifier.fillMaxWidth().background(NB.carbon4).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MealQueue.rejected.forEach { failure ->
            Text(failure.name, style = NBFont.ui(600, 13f), color = NB.text3Prod)
            Text(failure.reason, style = NBFont.ui(400, 12f), color = NB.text3Prod)
            Row(Modifier.fillMaxWidth()) {
                // 8 + 8 + 8, as SwiftUI spaces around the Spacer
                Text(L("Retry"), Modifier.padding(end = 24.dp).hotZoneTap { MealQueue.retryRejected(failure.id) },
                    style = NBFont.ui(500, 12f), color = NB.ember1)
                Spacer(Modifier.weight(1f))
                Text(L("Remove pending change"), Modifier.hotZoneTap { MealQueue.discardRejected(failure.id, data) },
                    style = NBFont.ui(500, 12f), color = NB.ember1)
            }
        }
    }
}

/** The row the page reads: today's, or a past day's from history, with the macro slots and the
 *  intake re-derived from the day's own meals. */
private fun fuelRow(data: DataStore, day: UserDay, isPast: Boolean, dayMeals: List<MealEntry>): DailyMetrics {
    val row = (if (isPast) data.history.firstOrNull { it.day == day } ?: DailyMetrics(day = day) else data.today).copy()
    if (DebugEdgeFlag.on("unlogged") || DebugEdgeFlag.on("fasted")) {
        val fasted = DebugEdgeFlag.on("fasted")
        row.eIn = if (fasted) 0.0 else null
        row.fuelState = if (fasted) FuelState.Fasted else FuelState.Unlogged
        row.protein = row.protein?.let { MacroSlot(it.target, 0) }
        row.carb = row.carb?.let { MacroSlot(it.target, 0) }
        row.fat = row.fat?.let { MacroSlot(it.target, 0) }
        return row
    }
    // History rows carry what went in as totals; the macro slots are filled from them so the
    // same card reads the same way on a past day.
    row.protein = row.protein?.let { MacroSlot(it.target, row.proteinIn ?: dayMeals.sumOf { m -> m.protein }.rounded().toInt()) }
    row.carb = row.carb?.let { MacroSlot(it.target, row.carbIn ?: dayMeals.sumOf { m -> m.carb }.rounded().toInt()) }
    row.fat = row.fat?.let { MacroSlot(it.target, row.fatIn ?: dayMeals.sumOf { m -> m.fat }.rounded().toInt()) }
    val fasted = row.fuelState == FuelState.Fasted
    row.eIn = FuelCardMath.eaten(mealKcals = dayMeals.map { it.kcal }, server = row.eIn, fasted = fasted)
    return row
}

@Composable
private fun PlatedPage(plate: FuelPlate?, onClosePlate: () -> Unit, day: UserDay, page: @Composable () -> Unit) {
    val up = plate != null
    val spec = swiftSpring<Float>(0.36f, 0.86f)
    val scale by animateFloatAsState(if (up) 0.88f else 1f, spec, label = "fuel.plate.scale")
    val lift by animateFloatAsState(if (up) 1f else 0f, spec, label = "fuel.plate.lift")
    // The last plate shown, so the exit transition still has something to draw.
    var shown by remember { mutableStateOf<FuelPlate?>(null) }
    if (plate != null) shown = plate

    // Black only matters once the card has lifted; at rest the page fills the screen.
    Box(Modifier.fillMaxSize().background(if (up || lift > 0f) Color.Black else NB.carbon)) {
        val shape = RoundedCornerShape(NB.R.panel * lift)
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale; scaleY = scale
                    // ⚠️ At rest the page is not clipped: clipping sheared the bloom off at the
                    // status bar. It tightens to the rounded card only while a plate is up.
                    clip = lift > 0f
                    this.shape = shape
                    shadowElevation = if (lift > 0f) 22.dp.toPx() * lift else 0f
                }
                .let { if (lift > 0f) it.border(1.dp, NB.white.copy(alpha = 0.12f * lift), shape) else it },
        ) {
            page()
        }
        AnimatedVisibility(
            visible = up,
            enter = slideInVertically(swiftSpring(0.36f, 0.86f)) { it } + fadeIn(),
            exit = slideOutVertically(swiftSpring(0.32f, 0.86f)) { it } + fadeOut(),
        ) {
            shown?.let { FuelPlateLayer(plate = it, day = day, onClose = onClosePlate) }
        }
    }
}

@Composable
private fun FuelPage(
    data: DataStore, m: DailyMetrics, day: UserDay, today: UserDay, isPast: Boolean,
    range: RollingPills, rangeRaw: String, onRange: (String) -> Unit, onDay: (UserDay) -> Unit,
    dayMeals: List<MealEntry>, logged: Boolean, closed: Boolean, outUnknown: Boolean,
    pastTitle: String, onEdit: (MealEntry) -> Unit,
) {
    val headerPeriod = when (range) {
        RollingPills.day -> if (isPast) pastTitle else Fmt.clock(Instant.now())
        RollingPills.week -> L(DetailWindow(DetailSurface.fuel, RollingPills.week).periodKey)
        RollingPills.month -> L(DetailWindow(DetailSurface.fuel, RollingPills.month).periodKey)
    }
    val weekFacts = facts(data, today, DetailWindow(DetailSurface.fuel, RollingPills.week).days)

    // ADR 0014 / Paper 09H · DAY is the clock plus one food table. WEEK and MONTH are rolling
    // windows of the same page.
    DetailScroll(
        glow = NB.ember1,
        title = L("CALORIES"),
        headline = if (isPast) pastTitle else null,
        onBack = { if (isPast) onDay(today) else Router.backToRoot() },
        trailing = {
            FitText(headerPeriod, NBFont.dot(600, 11f).tracking(0.24f), NB.text3Prod, minScale = 0.72f)
            if (isPast && range == RollingPills.day) {
                Row(Modifier.padding(start = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    PagerButton(forward = false, enabled = day > today.adding(-6)) { onDay(day.adding(-1)) }
                    PagerButton(forward = true, enabled = isPast) { onDay(day.adding(1)) }
                }
            }
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SegmentedPills(options = RollingPills.words, selection = rangeRaw, onSelect = onRange, lined = true)
            when (range) {
                RollingPills.day -> DayBoard(data, m, day, isPast, dayMeals, logged, closed, outUnknown, weekFacts, onEdit)
                RollingPills.week -> WeekBoard(m, weekFacts, today)
                RollingPills.month -> MonthBoard(m, facts(data, today, DetailWindow(DetailSurface.fuel, RollingPills.month).days))
            }
            if (!isPast) FastingAction(day = day)
        }
    }
}

@Composable
private fun DayBoard(
    data: DataStore, m: DailyMetrics, day: UserDay, isPast: Boolean, dayMeals: List<MealEntry>,
    logged: Boolean, closed: Boolean, outUnknown: Boolean, weekFacts: List<FuelDayFacts>,
    onEdit: (MealEntry) -> Unit,
) {
    val dayFoot = when {
        m.fuelState == FuelState.Fasted -> L("Recorded: nothing eaten today")
        isPast -> if (logged) L("CLOSED") else L("NOTHING LOGGED")
        !logged -> L("NOTHING LOGGED YET")
        else -> {
            val n = dayMeals.size
            if (closed) (if (n == 1) L("%d MEAL", n) else L("%d MEALS", n))
            else (if (n == 1) L("%d MEAL · NOT CLOSED", n) else L("%d MEALS · NOT CLOSED", n))
        }
    }
    // Five-minute steps on this user day. The cyan line uses them so a walk is steeper than
    // sitting — not a ruler from 04:00 to now.
    val dayBurnTicks: List<VitalSample> = m.energyDistribution?.map { it.tick }
        ?: data.history.firstOrNull { it.day == day && it.vitalsCurve.isNotEmpty() }?.vitalsCurve
        ?: m.vitalsCurve
    val dim = NB.white.copy(alpha = 0.34f)

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Text(L("THE DAY SO FAR"), Modifier.alignByBaseline(), style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.ember1)
                Spacer(Modifier.width(16.dp))
                FitText(dayFoot, NBFont.ui(500, 11f).tracking(0.06f), NB.ember1, Modifier.alignByBaseline().weight(1f), minScale = 0.7f,
                    align = TextAlign.End)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                Column(Modifier.alignByBaseline(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("IN"), style = NBFont.ui(500, 10f).tracking(0.12f), color = NB.text3Prod)
                    FitText(Fmt.kcal(m.eIn), NBFont.dot(700, 36f).tracking(-0.02f),
                        if (logged) NB.ember1 else NB.text3Prod, minScale = 0.7f)
                }
                Column(Modifier.alignByBaseline(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("OUT"), style = NBFont.ui(500, 10f).tracking(0.12f), color = NB.text3Prod)
                    FitText(if (outUnknown) Fmt.dash else Fmt.kcal(m.eOutNow), NBFont.dot(700, 36f).tracking(-0.02f),
                        if (logged && !outUnknown) NB.cyan1 else NB.text3Prod, minScale = 0.7f)
                }
                Spacer(Modifier.weight(1f))
                Column(Modifier.alignByBaseline(), horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("DIFF"), style = NBFont.ui(500, 10f).tracking(0.12f), color = NB.text3Prod)
                    FitText(if (outUnknown) Fmt.dash else Fmt.signedKcal(m.balance), NBFont.dot(700, 22f).tracking(-0.01f),
                        gapTint(m.balance), minScale = 0.7f)
                }
            }
            FuelDayChart(
                meals = dayMeals.map { it.at to it.kcal },
                burnedNow = if (outUnknown) null else m.eOutNow,
                restingNow = m.bmr,
                burnedAt = minOf(day.end, m.asOf ?: Instant.now()),
                burnedFull = if (isPast) m.eOutNow else m.eOutFull,
                budget = m.targetIn,
                now = if (isPast) day.end else Instant.now(),
                dayStart = day.start,
                happenedIntake = m.eIn ?: 0.0,
                burnTicks = dayBurnTicks,
                outUnknown = outUnknown,
            )
            val budget = m.targetIn
            if (budget != null) {
                Text(L("ALLOWANCE %@", Fmt.kcal(budget)), style = NBFont.dot(500, 10f).tracking(0.08f), color = dim)
                // An allowance nobody can account for is a number, not a reference. #29: resting
                // for the whole day plus the activity measured so far.
                val resting = m.bmrFull
                if (resting != null) {
                    val active = m.eActive ?: 0.0
                    val restingLabel = if (m.restingSource == "BODY_SCAN")
                        L("BODY SCAN %@", m.restingMeasuredAt?.let { Fmt.monthDay(it) } ?: Fmt.dash)
                    else L("ESTIMATED FROM WEIGHT")
                    val floored = budget - (resting + active) > 40
                    FitText(L("RESTING %@ · %@ · ACTIVE +%@%@", Fmt.kcal(resting), restingLabel, Fmt.kcal(active),
                        if (floored) L(" · FLOOR") else ""),
                        NBFont.dot(500, 10f).tracking(0.08f), dim, minScale = 0.7f)
                }
            }
            WeekSoFar(isPast, weekFacts)
            Text(L("Solid already happened. Dashed is the usual rhythm."),
                style = NBFont.ui(400, 11f).tracking(0.02f), color = NB.text3Prod)
        }

        // AI is off: no plate is ever being read, so `reading` stays null.
        FuelFoodTable(meals = dayMeals, trailing = Fmt.kcal(m.eIn), reading = null, onSelect = onEdit)
    }
}

/**
 * One day is not the account. This product does not move the line (no rollover) — TARGET is
 * computed fresh every day (ADR 0025) — so the reassurance is told the true way: the running
 * total you are actually eating against. The number is the week's own DIFF, not a second budget.
 */
@Composable
private fun WeekSoFar(isPast: Boolean, weekFacts: List<FuelDayFacts>) {
    if (isPast) return
    val week = FuelWindowMath.sum(weekFacts) ?: return
    if (week.pairedDays < 2) return
    val dim = NB.white.copy(alpha = 0.34f)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L("WEEK SO FAR"), style = NBFont.dot(500, 10f).tracking(0.08f), color = dim)
        Text(Fmt.signedKcal(week.gap), style = NBFont.dot(700, 12f).tracking(0.02f), color = gapTint(week.gap))
        Text(L("· %d DAYS", week.pairedDays), style = NBFont.dot(500, 10f).tracking(0.08f), color = dim)
    }
}

@Composable
private fun WeekBoard(m: DailyMetrics, days: List<FuelDayFacts>, today: UserDay) {
    val total = FuelWindowMath.sum(days)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(L("THIS WEEK"), style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text3Prod)
                Spacer(Modifier.width(16.dp))
                FitText(weekSpan(days), NBFont.ui(500, 11f).tracking(0.06f), NB.ember1, Modifier.weight(1f), minScale = 0.7f,
                    align = TextAlign.End)
            }
            FuelStackedHero(intake = Fmt.kcal(total?.intake), burned = Fmt.kcal(total?.burned),
                gap = Fmt.signedKcal(total?.gap), gapTint = gapTint(total?.gap))
            m.targetIn?.let {
                Text(L("ALLOWANCE %@", Fmt.kcal(it)), style = NBFont.dot(500, 10f).tracking(0.08f),
                    color = NB.white.copy(alpha = 0.34f))
            }
            FuelWeekBars(days = days, budget = m.targetIn)
            Text(L("Known days: IN %d · OUT %d · DIFF %d", total?.intakeDays ?: 0, total?.burnedDays ?: 0, total?.pairedDays ?: 0),
                style = NBFont.ui(400, 11f).tracking(0.02f), color = NB.text3Prod)
            Text(L("DIFF only includes days with both intake and burn recorded."),
                style = NBFont.ui(400, 11f).tracking(0.02f), color = NB.text3Prod)
        }
        FuelLedgerTable(
            title = L("DAYS"),
            trailing = L("%d DAYS · %d OPEN", days.size, days.count { it.isOpen }),
            dayHeader = L("DAY"),
            rows = days.map { weekRow(it, today) },
            footer = total?.let {
                FuelLedgerRow(id = "week-total", title = L("WEEK"), intake = Fmt.kcal(it.intake),
                    burned = Fmt.kcal(it.burned), gap = Fmt.signedKcal(it.gap), gapTint = gapTint(it.gap))
            },
        )
    }
}

@Composable
private fun MonthBoard(m: DailyMetrics, days: List<FuelDayFacts>) {
    val rolls = FuelWindowMath.weekRolls(days)
    val typical = FuelWindowMath.typicalDay(rolls)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(L("A TYPICAL DAY"), Modifier.weight(1f), style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text3Prod)
                Spacer(Modifier.width(16.dp))
                Text(L("PER DAY"), style = NBFont.ui(500, 11f).tracking(0.06f), color = NB.ember1)
            }
            FuelStackedHero(intake = Fmt.kcal(typical?.intake), burned = Fmt.kcal(typical?.burned),
                gap = Fmt.signedKcal(typical?.gap), gapTint = gapTint(typical?.gap))
            m.targetIn?.let {
                Text(L("ALLOWANCE %@", Fmt.kcal(it)), style = NBFont.dot(500, 10f).tracking(0.08f),
                    color = NB.white.copy(alpha = 0.34f))
            }
            FuelMonthBars(days = days, budget = m.targetIn)
            Text(L("Complete days: IN %d · OUT %d · DIFF %d", typical?.intakeDays ?: 0, typical?.burnedDays ?: 0,
                typical?.pairedDays ?: 0), style = NBFont.ui(400, 11f).tracking(0.02f), color = NB.text3Prod)
            Text(L("DIFF only includes days with both intake and burn recorded."),
                style = NBFont.ui(400, 11f).tracking(0.02f), color = NB.text3Prod)
        }
        FuelLedgerTable(
            title = L("WEEKS"),
            trailing = L("PER DAY"),
            dayHeader = L("WEEK"),
            rows = rolls.mapIndexed { i, roll -> monthRow(roll, newest = i == 0) },
            footer = typical?.let {
                FuelLedgerRow(id = "typical", title = L("TYPICAL DAY"), intake = Fmt.kcal(it.intake),
                    burned = Fmt.kcal(it.burned), gap = Fmt.signedKcal(it.gap), gapTint = gapTint(it.gap))
            },
        )
    }
}

private fun facts(data: DataStore, end: UserDay, count: Int): List<FuelDayFacts> {
    val today = UserDay.containing(Instant.now())
    return end.rollingBack(count).map { slot ->
        val row = data.history.firstOrNull { it.day == slot } ?: (if (slot == data.today.day) data.today else null)
        val meals = (data.meals + data.recentMeals).filter { it.day == slot && it.status == MealEntry.Status.confirmed }
        val unique = LinkedHashMap<java.util.UUID, MealEntry>().apply { meals.forEach { putIfAbsent(it.id, it) } }.values
        val fasted = row?.fuelState == FuelState.Fasted
        val intake = FuelCardMath.eaten(mealKcals = unique.map { it.kcal }, server = row?.eIn, fasted = fasted)
        FuelDayFacts(
            day = slot,
            intake = intake,
            burned = row?.eOutNow,
            foodCount = unique.size,
            isFasted = fasted,
            isOpen = slot == today && (row?.fuelState == FuelState.Unlogged || !slot.isClosed),
        )
    }
}

private fun weekRow(fact: FuelDayFacts, today: UserDay): FuelLedgerRow {
    val caption: String
    val captionTint: Color
    when {
        fact.day == today -> { caption = L("TODAY"); captionTint = NB.ember1 }
        fact.isFasted -> { caption = L("FASTED"); captionTint = NB.text3Prod }
        fact.foodCount == 0 -> { caption = if (fact.intake == null) Fmt.dash else L("LOGGED"); captionTint = NB.text3Prod }
        else -> {
            caption = if (fact.foodCount == 1) L("%d MEAL", fact.foodCount) else L("%d MEALS", fact.foodCount)
            captionTint = NB.text3Prod
        }
    }
    return FuelLedgerRow(
        id = fact.day.key,
        title = Fmt.displayDate(fact.day.date, "EEE d").uppercase(),
        caption = caption,
        captionTint = captionTint,
        intake = Fmt.kcal(fact.intake),
        burned = Fmt.kcal(fact.burned),
        gap = Fmt.signedKcal(fact.gap),
        gapTint = gapTint(fact.gap),
    )
}

private fun monthRow(roll: FuelWeekRoll, newest: Boolean): FuelLedgerRow {
    val span = weekSpan(roll.start, roll.end)
    return FuelLedgerRow(
        id = roll.start.key,
        title = if (newest) L("THIS WEEK") else span,
        caption = L("IN %d days\nOUT %d days\nDIFF %d days", roll.intakeDays, roll.burnedDays, roll.pairedDays),
        captionTint = if (newest) NB.ember1 else NB.text3Prod,
        intake = Fmt.kcal(roll.avgIn),
        burned = Fmt.kcal(roll.avgOut),
        gap = Fmt.signedKcal(roll.avgGap),
        gapTint = gapTint(roll.avgGap),
    )
}

private fun weekSpan(days: List<FuelDayFacts>): String {
    val first = days.firstOrNull() ?: return ""
    val last = days.lastOrNull() ?: return ""
    return weekSpan(first.day, last.day)
}

private fun weekSpan(from: UserDay, to: UserDay): String {
    val left = Fmt.displayDate(from.date, "d MMM").uppercase()
    val right = Fmt.displayDate(to.date, "d MMM").uppercase()
    return "$left — $right"
}

private fun gapTint(gap: Double?): Color {
    if (gap == null) return NB.text3Prod
    return if (gap > 0) NB.lime2 else NB.cyan1
}

// MARK: rows

@Composable
fun MacroDetailRow(
    name: String,
    slot: MacroSlot?,
    tint: Color,
    note: String,
    intake: Int? = null,
    logged: Boolean = false,
) {
    // 09 · B2 · the numerator is blank until something is logged; the denominator is there from
    // the start. That is the line between "no answer yet" and "broken".
    val macroValue = if (slot == null) intake?.let { "$it g" } ?: Fmt.dash
    else if (logged || slot.eaten > 0) "${slot.eaten}/${slot.target}" else "—/${slot.target}"
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L(name), Modifier.width(44.dp).alignByBaseline(), style = NBFont.ui(600, 12f).tracking(0.06f), color = NB.text1)
            Text(if (note.isEmpty()) "" else L(note), Modifier.alignByBaseline(),
                style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
            Spacer(Modifier.weight(1f))
            Text(macroValue, Modifier.width(70.dp).alignByBaseline(), style = NBFont.dot(700, 13f).tracking(0.02f),
                color = NB.macroValue, textAlign = TextAlign.End)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
            Box(Modifier.fillMaxSize().background(hex(0x1A1A20), CircleShape))
            if (slot != null && slot.target > 0 && slot.eaten > 0) {
                Box(Modifier.width(maxWidth * min(1f, slot.eaten.toFloat() / slot.target)).height(8.dp)
                    .background(tint, CircleShape))
            }
        }
    }
}


@Composable
fun BalanceStat(label: String, value: String, tint: Color, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = NBFont.ui(500, 11f).tracking(0.1f), color = NB.text3Prod)
        Text(value, style = NBFont.dot(700, 24f).tracking(-0.01f), color = tint)
    }
}

/** −800 … +400, absolute. The RECOMP window (−200 … −500) never rescales with the day's data. */
@Composable
fun BalanceAxis(now: Double?, ifBudget: Double, enabled: Boolean, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth().height(52.dp)) {
        val w = maxWidth
        fun x(v: Double): Dp = w * ((v + 800) / 1200).toFloat()
        Box(Modifier.offset(y = 24.dp).width(w).height(8.dp).background(hex(0x1A1A20), CircleShape))
        Box(Modifier.offset(x = x(-500.0), y = 24.dp).size(x(-200.0) - x(-500.0), 8.dp).background(NB.limeMid.copy(alpha = 0.55f)))
        Box(Modifier.offset(x = x(0.0), y = 20.dp).size(1.dp, 16.dp).background(NB.white.copy(alpha = 0.18f)))
        if (enabled) {
            Box(Modifier.offset(x = x(ifBudget) - 4.5.dp, y = 23.5.dp).size(9.dp)
                .background(NB.carbon2, CircleShape).border(2.dp, NB.ember1, CircleShape))
            Box(Modifier.offset(x = x(now ?: 0.0) - 1.25.dp, y = 18.dp).size(2.5.dp, 20.dp).background(NB.white, CircleShape))
            Text(L("%@ NOW", Fmt.signedKcal(now)), Modifier.offset(x = max(0f, (x(now ?: 0.0) - 22.dp).value).dp, y = 0.dp),
                style = NBFont.dot(700, 10f).tracking(0.02f), color = NB.text1)
            Text(L("%@ EST", Fmt.signedKcal(ifBudget)), Modifier.offset(x = max(0f, (x(ifBudget) - 18.dp).value).dp, y = 38.dp),
                style = NBFont.dot(700, 10f).tracking(0.02f), color = NB.ember1)
        }
    }
}

// MARK: edit

/** F0 right column · "改一笔／删一笔". Same plate chrome as Profile / Log a meal. */
@Composable
fun EditMealSheet(entry: MealEntry, keyboard: Dp = 0.dp, onClose: () -> Unit) {
    val data = DataStore
    var text by remember(entry.id) { mutableStateOf(entry.text) }
    var kcal by remember(entry.id) { mutableStateOf(entry.kcal.toString()) }
    var protein by remember(entry.id) { mutableStateOf(entry.protein.toString()) }
    var carb by remember(entry.id) { mutableStateOf(entry.carb.toString()) }
    var fat by remember(entry.id) { mutableStateOf(entry.fat.toString()) }
    var portion by remember(entry.id) { mutableStateOf(entry.portion ?: "") }
    var fiber by remember(entry.id) { mutableStateOf(entry.fiber) }
    var sugar by remember(entry.id) { mutableStateOf(entry.sugar) }
    var sodium by remember(entry.id) { mutableStateOf(entry.sodium) }
    var eatenAt by remember(entry.id) { mutableStateOf(entry.at) }
    var slot by remember(entry.id) { mutableStateOf(entry.slot) }

    // ⚠️ Saving used to require all four numbers to parse. The row keeps whatever this sheet
    // leaves blank, and the numbers have a servings row above them for "that was half of that".
    val canSave = text.trim().isNotEmpty() && number(kcal) != null && grams(protein) != null &&
        grams(carb) != null && grams(fat) != null

    // 420 with the keys down. With them up the form takes whatever is left between the status
    // bar and the top of the keys — the footer is outside the scroll, so SAVE and DELETE stay
    // reachable either way.
    val formHeight: Dp = run {
        val chrome = 244.dp
        val floor = maxOf(keyboard, ScreenMetrics.safeBottom)
        val room = ScreenMetrics.height - floor - ScreenMetrics.safeTop - 12.dp - chrome
        maxOf(44.dp, minOf(420.dp, room))
    }

    fun apply(factor: Double) {
        if (factor == 1.0) return
        number(kcal)?.let { kcal = PortionMath.scale(it, factor).toString() }
        grams(protein)?.let { protein = PortionMath.scale(it, factor).toString() }
        grams(carb)?.let { carb = PortionMath.scale(it, factor).toString() }
        grams(fat)?.let { fat = PortionMath.scale(it, factor).toString() }
        fiber = fiber?.let { PortionMath.scale(it, factor) }
        sugar = sugar?.let { PortionMath.scale(it, factor) }
        sodium = sodium?.let { PortionMath.scale(it, factor) }
        portion = PortionMath.scale(if (portion.isEmpty()) null else portion, factor) ?: ""
    }

    val scroll = rememberScrollState()
    Box(Modifier.padding(bottom = if (keyboard > 0.dp) 8.dp else maxOf(8.dp, Chrome.homeIndicatorBlock - 8.dp))) { SheetFrame(
        title = L("Edit this meal"), fillsHeight = false,
        content = {
            Column(
                Modifier
                    .heightIn(max = formHeight)
                    // A row cut clean in half under the title reads as a bug; the fade says "this
                    // scrolls". Only while it actually does.
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        if (scroll.maxValue > 0) {
                            drawRect(
                                Brush.verticalGradient(
                                    0f to Color.Transparent, 0.05f to Color.Black,
                                    0.95f to Color.Black, 1f to Color.Transparent,
                                ),
                                blendMode = BlendMode.DstIn,
                            )
                        }
                    }
                    .verticalScroll(scroll),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (entry.photoPath != null) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        MealThumbnail(entry.photoPath, side = 64.dp, radius = 14.dp)
                        Column(Modifier.padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(L("THE PLATE YOU SHOT"), style = NBFont.dot(600, 10f).tracking(0.18f),
                                color = NB.white.copy(alpha = 0.42f))
                            Text(portion.ifEmpty { L("Portion unknown") }, style = NBFont.ui(400, 14f), color = NB.text1)
                        }
                    }
                }
                SlotRow(slot) { slot = it }
                TimeFieldBox(label = L("Eaten at"), time = eatenAt.atZone(java.time.ZoneId.systemDefault()).toLocalTime(),
                    onChange = { t -> eatenAt = eatenAt.settingHour(t.hour, t.minute, 0) })
                FieldBox(label = L("What you ate"), text = text, onText = { text = it })
                ServingsRow(::apply)
                FieldBox(label = L("PORTION"), text = portion, onText = { portion = it })
                FieldBox(label = L("KCAL"), text = kcal, onText = { kcal = it },
                    keyboard = androidx.compose.ui.text.input.KeyboardType.Decimal)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    FieldBox(label = L("PROTEIN"), text = protein, onText = { protein = it }, modifier = Modifier.weight(1f),
                        keyboard = androidx.compose.ui.text.input.KeyboardType.Decimal)
                    FieldBox(label = L("CARB"), text = carb, onText = { carb = it }, modifier = Modifier.weight(1f),
                        keyboard = androidx.compose.ui.text.input.KeyboardType.Decimal)
                    FieldBox(label = L("FAT"), text = fat, onText = { fat = it }, modifier = Modifier.weight(1f),
                        keyboard = androidx.compose.ui.text.input.KeyboardType.Decimal)
                }
                MicroRow(fiber, sugar, sodium)
                Text(L("This recomputes the user day. Range is the last 7 days."),
                    Modifier.fillMaxWidth().padding(top = 6.dp),
                    style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f))
            }
        },
        footer = {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                LimePillButton(title = L("Save"), enabled = canSave) {
                    val trimmed = portion.trim()
                    data.amendMeal(
                        entry.id,
                        text = text,
                        kcal = number(kcal) ?: entry.kcal,
                        protein = grams(protein) ?: entry.protein,
                        carb = grams(carb) ?: entry.carb,
                        fat = grams(fat) ?: entry.fat,
                        at = entry.day.pinningClock(eatenAt),
                        slot = slot,
                        portion = trimmed.ifEmpty { null },
                        fiber = Replace(fiber), sugar = Replace(sugar), sodium = Replace(sodium),
                    )
                    onClose()
                }
                TextAction(if (entry.groupID == null) L("Keep as a regular") else L("Keep this plate as a regular"), NB.ember1) {
                    val recent = data.recentMeals
                    queueScope.launch { MealFavorites.save(entry, recent) }
                    onClose()
                }
                TextAction(L("Delete this entry"), NB.alert2) {
                    data.deleteMeal(entry.id)
                    onClose()
                }
            }
        },
    ) }
}

@Composable
private fun TextAction(title: String, tint: Color, action: () -> Unit) {
    Box(Modifier.fillMaxWidth().hotZoneTap(onClick = action), contentAlignment = Alignment.Center) {
        Text(title, style = NBFont.ui(400, 13f).tracking(0.02f), color = tint)
    }
}

@Composable
private fun SlotRow(slot: MealEntry.Slot, onSlot: (MealEntry.Slot) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        MealEntry.Slot.entries.forEach { item ->
            val on = slot == item
            Box(
                Modifier.weight(1f).height(36.dp)
                    .hotZoneTap { onSlot(item) }
                    .background(NB.carbon4, CircleShape)
                    .border(1.dp, if (on) NB.ember1 else NB.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                FitText(L(item.raw), NBFont.dot(600, 11f), if (on) NB.ember1 else NB.text2, minScale = 0.7f)
            }
        }
    }
}

/** Four multipliers and no keyboard. Scaling reads whatever is in the fields right now, so two
 *  taps compose — ×0.5 then ×0.5 is a quarter — and ×1 is how a mis-tap is undone. */
@Composable
private fun ServingsRow(apply: (Double) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L("SERVINGS"), Modifier.width(66.dp), style = NBFont.dot(600, 10f).tracking(0.18f),
            color = NB.white.copy(alpha = 0.42f))
        PortionMath.factors.forEach { factor ->
            Box(
                Modifier.weight(1f).height(32.dp)
                    .hotZoneTap { apply(factor) }
                    .background(NB.carbon4, CircleShape)
                    .border(1.dp, NB.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(if (factor == 1.0) "×1" else "×${PortionMath.label(factor)}", style = NBFont.dot(600, 11f),
                    color = if (factor == 1.0) NB.text2 else NB.ember1)
            }
        }
    }
}

/** Read-only, because nothing on this phone measured them. They come from the estimate or they
 *  are ——; a text field here would invite a number nobody has. */
@Composable
private fun MicroRow(fiber: Double?, sugar: Double?, sodium: Double?) {
    if (fiber == null && sugar == null && sodium == null) return
    Row(Modifier.fillMaxWidth().padding(top = 2.dp)) {
        listOf(
            L("FIBER") to fiber?.let { "${Fmt.nutrient(it)} G" },
            L("SUGAR") to sugar?.let { "${Fmt.nutrient(it)} G" },
            L("SODIUM") to sodium?.let { "${Fmt.nutrient(it)} MG" },
        ).forEach { (label, value) ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(label, style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.white.copy(alpha = 0.42f))
                Text(value ?: "——", style = NBFont.dot(600, 13f),
                    color = if (value == null) NB.white.copy(alpha = 0.32f) else NB.text1)
            }
        }
    }
}

private fun number(raw: String): Double? {
    val trimmed = raw.trim()
    val value = trimmed.replace(',', '.').toDoubleOrNull() ?: return null
    if (!value.isFinite() || value < 0 || value > 100_000) return null
    return value
}

private fun grams(raw: String): Double? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return 0.0
    return number(trimmed)
}
