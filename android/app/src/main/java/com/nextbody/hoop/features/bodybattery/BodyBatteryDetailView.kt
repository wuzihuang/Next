package com.nextbody.hoop.features.bodybattery

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.app.EntryPoint
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.band.BandHost
import com.nextbody.hoop.band.BandLiveLifecycle
import com.nextbody.hoop.band.BodyBatteryDayFacts
import com.nextbody.hoop.band.BodyBatteryLedgerMath
import com.nextbody.hoop.band.BodyBatteryLedgerRow
import com.nextbody.hoop.band.BodyBatteryWeekRoll
import com.nextbody.hoop.band.BodyBatteryWindowMath
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.Ports
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.training.SegmentedPills
import com.nextbody.hoop.features.home.HomeV2Model
import com.nextbody.hoop.features.vitals.MetricTrendMath
import com.nextbody.hoop.features.vitals.VitalsStatPair
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.band.OriginDataSync
import com.nextbody.hoop.band.BandRefreshRequest
import com.nextbody.hoop.band.BandRefreshResult
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.BodyBatteryConfidence
import com.nextbody.hoop.model.BodyBatteryCurveMath
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.NightInputs
import com.nextbody.hoop.model.ReserveDrivers
import com.nextbody.hoop.model.ReserveSample
import com.nextbody.hoop.model.TickFreshness
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.settingHour
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.ui.CardBlock
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.SectionLabel
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * 13 / ADR 0017 · BODY BATTERY. Scheme A is the curve: one page, DAY / WEEK /
 * MONTH. Day answers why today is this number. Week and month speak a typical
 * morning peak, never a sum. Lime is the page colour. Sleep never reaches it.
 */
@Composable
fun BodyBatteryDetailView() {
    val data = DataStore
    val scope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    var refreshMessage by remember { mutableStateOf<String?>(null) }
    var rangeRaw by remember { mutableStateOf(RollingPills.day.raw) }
    // TimelineView(.periodic(by: 60)) · the page re-reads the clock once a minute.
    var minuteTick by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            minuteTick = Instant.now()
        }
    }
    @Suppress("UNUSED_VARIABLE") val tick = minuteTick

    val range = RollingPills.parse(rangeRaw)
    val detail = DetailWindow(DetailSurface.bodyBattery, range)
    val today = UserDay.containing(Instant.now())
    val m = data.todayForDisplay
    val hasNight = m.bbWake != null
    val hasScore = m.bodyBatteryForDisplay(Instant.now()) != null
    val hasRecord = m.bodyBatteryObservedAt != null
    val forceEmpty = DebugEdgeFlag.on("empty")

    fun facts(count: Int): List<BodyBatteryDayFacts> = today.rollingBack(count).map { day ->
        val row = if (day == today) m else (data.history.firstOrNull { it.day == day } ?: DailyMetrics(day = day))
        BodyBatteryDayFacts(
            day = day,
            wake = row.bbWake,
            now = if (day == today) data.bodyBatteryNow else row.bodyBattery,
            nightCharge = row.reserveDrivers?.nightCharge,
            worn = row.worn,
            isOpen = day == today && !day.isClosed,
        )
    }

    // From the panel, back is the root. From ME, back is ME — same one-layer
    // memory composition already uses.
    val leave: () -> Unit = { if (Router.entry == EntryPoint.profile) Router.back() else Router.backToRoot() }

    val windowRequest = Router.windowRequest
    LaunchedEffect(windowRequest) {
        val request = windowRequest ?: return@LaunchedEffect
        rangeRaw = RollingPills.parse(request).raw
        Router.windowRequest = null
    }

    LaunchedEffect(Unit) {
        DetailWindow.debugRange(DetailSurface.bodyBattery)?.let { rangeRaw = it.raw }
        if (!Band.allowsSeed) {
            Repository.hydrate(detail, endingAt = today, store = data)
        }
        Analytics.track("READINESS_DETAIL_OPEN", mapOf(
            "ENTRY" to (if (Router.entry == EntryPoint.profile) "profile" else if (Router.homePage == 1) "page2" else "panel"),
            "RANGE" to RollingPills.parse(rangeRaw).raw,
        ))
        if (RollingPills.parse(rangeRaw) != RollingPills.day) return@LaunchedEffect
        val bb = m.bodyBattery
        if (bb != null) {
            Analytics.track("READINESS_CONFIDENCE_SHOWN", mapOf("LEVEL" to m.bodyBatteryConfidence.raw, "SCORE" to bb))
        } else {
            Analytics.track("READINESS_NO_SCORE", mapOf("REASON" to if (hasNight) "NOT_SYNCED" else "NO_NIGHT"))
        }
        if (hasNight && m.reserveDrivers == null) {
            Analytics.track("BB_ATTRIBUTION_MISMATCH", mapOf("TICKS" to m.reserveCurve.size))
        }
        val target = m.targetLoad
        val zone = m.optimalZone
        if (bb != null && target != null && zone != null) {
            Analytics.track("READINESS_TARGET_SET", mapOf("READINESS" to bb, "TARGET" to target,
                "LO" to zone.start, "HI" to zone.endInclusive))
        }
        val at = m.bodyBatteryObservedAt
        if (m.bodyBatteryFreshness(Instant.now()) == TickFreshness.stale && at != null) {
            Analytics.track("READINESS_STALE_SHOWN", mapOf("MIN" to (Instant.now().timeIntervalSince(at) / 60).toInt()))
        }
    }

    /** Re-read real band evidence through the existing sync lane. A request to refresh
     *  never edits a calculated value. Settlement updates reserve and training guidance together. */
    fun refreshBattery() {
        if (isRefreshing) return
        refreshMessage = null
        if (!ConsentStore.granted) { Router.setTakeover(Takeover.Consent); return }
        if (Ports.boundBand.identifier == null) {
            refreshMessage = L("Connect the band to see the ticks it has been recording.")
            return
        }
        if (Ports.supabase.currentUserIdSnapshot() == null) {
            refreshMessage = L("Sign in to sync this NEXTBODY.")
            return
        }
        if (BandHost.liveSession().hasSession || BandLiveLifecycle.shared.hasExclusiveOperation) {
            refreshMessage = L("Finish the current measurement or device operation, then sync again.")
            return
        }
        isRefreshing = true
        scope.launch {
            try {
                val status = OriginDataSync.refreshNow(data, BandRefreshRequest.latest).status
                if (Band.live.state != BandConnectionState.connected) {
                    refreshMessage = L("Could not reach this NEXTBODY. Keep it nearby, check Bluetooth, then tap Sync to try again.")
                } else if (status == BandRefreshResult.Status.partial) {
                    refreshMessage = L("Some readings could not sync. Tap Sync to try again.")
                } else if (status == BandRefreshResult.Status.failed) {
                    refreshMessage = L("Sync did not complete. Tap Sync to try again.")
                }
            } finally {
                isRefreshing = false
            }
        }
    }

    val headerStatus = if (range == RollingPills.day) L("TODAY") else L(detail.periodKey)
    val headerTint = if (range == RollingPills.day && !hasScore) NB.text3Prod else NB.lime1

    DetailScroll(
        glow = NB.lime1,
        title = MetricNames.bodyBattery,
        onBack = leave,
        trailing = {
            BText(headerStatus, NBFont.dot(600, 11f).tracking(0.24f), headerTint)
        },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 30.dp)
                .testTag("bodyBattery.page"),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SegmentedPills(options = RollingPills.words, selection = rangeRaw,
                onSelect = { rangeRaw = it }, lined = true)
            val footer: @Composable () -> Unit = {
                Footer(observationLabel(m), isRefreshing, refreshMessage) { refreshBattery() }
            }
            when (range) {
                RollingPills.day -> {
                    if (forceEmpty || !(hasScore || hasRecord)) {
                        EmptyCard()
                        NeedsCard()
                        footer()
                    } else {
                        HeroCard(m)
                        DayVerdict(m, hasScore)
                        SectionLabel(L("KEY METRICS"))
                        DayKeyMetrics(m)
                        SectionLabel(L("DETAILS"))
                        if (m.reserveDrivers != null && hasScore) LedgerCard(m)
                        VitalsCard(m)
                        ConfidenceCard(m)
                        footer()
                    }
                }
                RollingPills.week -> WeekBoard(facts(DetailWindow(DetailSurface.bodyBattery, RollingPills.week).days)) { facts(it) }
                RollingPills.month -> MonthBoard(facts(DetailWindow(DetailSurface.bodyBattery, RollingPills.month).days))
            }
        }
    }
}

// MARK: text helpers

@Composable
private fun BText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    Text(
        text = text,
        modifier = modifier,
        style = style,
        color = color,
        maxLines = maxLines,
        softWrap = maxLines > 1,
        overflow = if (maxLines > 1) TextOverflow.Clip else TextOverflow.Ellipsis,
        textAlign = align,
    )
}

/** Body copy with SwiftUI's `.lineSpacing(n)`, wrapping freely. */
@Composable
private fun Prose(text: String, size: Float, spacing: Float, color: Color, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier.fillMaxWidth(),
        style = NBFont.brand(400, size).copy(lineHeight = (size * 1.2f + spacing).sp),
        color = color,
    )
}

/** #25 · 0% is a measurement; —— is the absence of one. When the hero is showing ——
 *  this line has to name the wrist, not a sync, or the two read the same. */
private fun observationLabel(m: DailyMetrics): String {
    val at = m.bodyBatteryObservedAt ?: return L("NO TICK")
    if (m.bodyBatteryReadout(Instant.now()).isPlaceholder) {
        return L("NOT WORN SINCE %@ · NO CURRENT READING", Fmt.clock(at))
    }
    return L("SYNCED %@", Fmt.clock(at))
}

// MARK: DAY

/** The home page's own bands (<50 recover · 50–79 steady · ≥80 peak), so the word here is
 *  the word the planet board already says. */
private fun readinessBand(m: DailyMetrics): HomeV2Model.ReadinessBand =
    if (m.bodyBatteryFreshness(Instant.now()) != TickFreshness.fresh) HomeV2Model.ReadinessBand.unknown
    else HomeV2Model.readinessBand(m.bodyBatteryForDisplay(Instant.now()))

private fun bandTint(band: HomeV2Model.ReadinessBand): Color = when (band) {
    HomeV2Model.ReadinessBand.recover -> NB.ember1
    HomeV2Model.ReadinessBand.steady, HomeV2Model.ReadinessBand.peak -> NB.lime1
    HomeV2Model.ReadinessBand.unknown -> NB.text3Prod
}

/** The curve colours observed increases and decreases, with its actual last timestamp. */
@Composable
private fun HeroCard(m: DailyMetrics) {
    val isDim = m.bodyBatteryFreshness(Instant.now()) != TickFreshness.fresh
    val band = readinessBand(m)
    Column(
        Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            BText(Fmt.int(m.bodyBatteryForDisplay(Instant.now())), NBFont.dot(800, 64f),
                if (isDim) NB.text3Prod else NB.text1, Modifier.alignByBaseline())
            Column(Modifier.alignByBaseline(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (band != HomeV2Model.ReadinessBand.unknown) {
                    BText(HomeV2Model.status(band).first, NBFont.ui(600, 15f), bandTint(band))
                }
                BText(L("OF 100"), NBFont.dot(600, 12f).tracking(0.18f), NB.white.copy(alpha = 0.42f))
            }
        }
        BatteryCurve(m.reserveCurve, m.day, isDim, modifier = Modifier.fillMaxWidth().height(120.dp))
        BodyBatteryTimeAxis(m.day)
    }
}

/**
 * Oura's headline / WHOOP's recovery sentence: the band as a title, and one line read off the
 * ledger below — where the day started, what sleep and rest added, and which drain has cost
 * the most since. Nothing here is advice the ledger cannot back.
 */
@Composable
private fun DayVerdict(m: DailyMetrics, hasScore: Boolean) {
    val band = readinessBand(m)
    val title = when (band) {
        HomeV2Model.ReadinessBand.recover -> L("REST TODAY")
        HomeV2Model.ReadinessBand.steady -> L("READY TO TRAIN")
        HomeV2Model.ReadinessBand.peak -> L("FULL CHARGE")
        HomeV2Model.ReadinessBand.unknown -> L("NO RECENT READINESS READING")
    }
    val d = m.reserveDrivers
    val observed = m.bodyBatteryObservedAt
    val line = when {
        band == HomeV2Model.ReadinessBand.unknown && observed != null ->
            L("The last reading was at %@. Wear the band and sync for a current one.", Fmt.clock(observed))
        d != null && hasScore -> {
            val worst = listOf(
                BodyBatteryLedgerRow.Term.awake to d.awake,
                BodyBatteryLedgerRow.Term.movement to d.movement,
                BodyBatteryLedgerRow.Term.stress to d.stress,
            ).minBy { it.second }
            if (worst.second <= -0.5)
                L("Started the day at %d and sleep & rest added %@. %@ has cost the most since: %@.",
                    d.anchor, Fmt.signed(d.chargeForDay), ledgerName(worst.first), Fmt.signed(worst.second))
            else L("Started the day at %d and sleep & rest added %@. Nothing has drained it noticeably since.",
                d.anchor, Fmt.signed(d.chargeForDay))
        }
        m.bbWake != null -> L("Morning reading %d. The breakdown appears once today's readings line up.", m.bbWake!!)
        else -> L("Estimated from recent wrist readings. A recorded night adds a morning reading.")
    }
    Column(Modifier.width(NB.Layout.contentWidth).testTag("bodyBattery.verdict"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = NBFont.ui(600, 19f), color = bandTint(band))
        Text(line, style = NBFont.ui(400, 14f).copy(lineHeight = 17.sp), color = NB.text2)
    }
}

/** WHOOP's recovery statistics: what the night left, and the two measurements it was charged
 *  through, each against this person's own 14-night baseline. */
@Composable
private fun DayKeyMetrics(m: DailyMetrics) {
    val n = m.nightInputs ?: NightInputs()
    val pace = n.multiplier?.let { BodyBatteryLedgerMath.pace(it) }
    Column(Modifier.testTag("bodyBattery.keyMetrics"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        VitalsStatPair(
            VitalsStatPair.Model(L("MORNING READINESS"), m.bbWake?.toString(), null,
                m.bodyBatteryWakeAt?.let { L("WAKE %@", Fmt.clock(it)) } ?: L("NO MORNING READING"), NB.lime1),
            VitalsStatPair.Model(L("OVERNIGHT RECOVERY"), m.reserveDrivers?.nightCharge?.let { Fmt.signed(it) }, null,
                pace?.let { paceWord(it) } ?: L("NO BASELINE YET"), null),
        )
        VitalsStatPair(
            VitalsStatPair.Model(L("NIGHT HRV"), n.hrv?.roundedInt()?.toString(), "MS",
                baselineNote(n.hrv, n.hrvBase) ?: L("NO BASELINE YET"), null),
            VitalsStatPair.Model(L("Resting heart rate"), n.rhr?.roundedInt()?.toString(), "BPM",
                baselineNote(n.rhr, n.rhrBase) ?: L("NO BASELINE YET"), null),
        )
    }
}

/**
 * 13 · WHY <n> as a ledger. Where the day started, four signed rows with the reason
 * each one has its sign, the balance after each, and the number at the top as the last
 * balance. Recovery combines sleep and sustained rest; the other three drain. No training
 * target here — it read as a fifth term of the sum.
 */
@Composable
private fun LedgerCard(m: DailyMetrics) {
    val d = m.reserveDrivers ?: return
    val now = m.bodyBattery ?: return
    val rows = BodyBatteryLedgerMath.rows(anchor = d.anchor, recovery = d.chargeForDay, awake = d.awake,
        movement = d.movement, stress = d.stress, current = now)
    val scale = max(1, rows.maxOfOrNull { abs(it.delta) } ?: 1)
    val startClock = Fmt.clock(m.day.start)
    val nowClock = m.bodyBatteryObservedAt?.let { Fmt.clock(it) }
    CardBlock(
        title = L("WHY %@", Fmt.int(now)),
        trailing = nowClock?.let { L("%@ → %@", startClock, it) } ?: startClock,
    ) {
        LedgerEdge(L("START %@", startClock), d.anchor, if (d.assumedAnchor) L("ESTIMATED") else null,
            NB.white.copy(alpha = 0.55f))
        Hairline()
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            val style = NBFont.dot(500, 9f).tracking(0.16f)
            val ink = NB.white.copy(alpha = 0.30f)
            Spacer(Modifier.weight(1f))
            BText(L("CHANGE"), style, ink, Modifier.width(LedgerBar + 10.dp + LedgerDelta), align = TextAlign.End)
            BText(L("AFTER"), style, ink, Modifier.width(LedgerBalance), maxLines = 2, align = TextAlign.End)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            rows.forEach { row ->
                LedgerRow(ledgerName(row.term), ledgerReason(row.term, d, m), row.delta, row.balance, scale)
            }
        }
        Hairline()
        LedgerEdge(nowClock?.let { L("NOW %@", it) } ?: L("NOW"), now, null, NB.lime1)
        Prose(L("Sleep and sustained quiet rest can raise readiness. Training and physiological strain lower it; high strain can limit recovery even during sleep."),
            13f, 6f, NB.white.copy(alpha = 0.62f))
        if (d.assumedAnchor) {
            Prose(L("Starting readiness estimated — earlier readings were missing."), 13f, 6f, NB.white.copy(alpha = 0.62f))
        }
    }
}

private fun ledgerName(term: BodyBatteryLedgerRow.Term): String = when (term) {
    BodyBatteryLedgerRow.Term.recovery -> L("Sleep & rest")
    BodyBatteryLedgerRow.Term.awake -> L("Awake fatigue")
    BodyBatteryLedgerRow.Term.movement -> L("Training & effort")
    BodyBatteryLedgerRow.Term.stress -> L("Physiological strain")
}

/** Why the row has its sign, in the day's own numbers where the page has them. */
private fun ledgerReason(term: BodyBatteryLedgerRow.Term, d: ReserveDrivers, m: DailyMetrics): String = when (term) {
    BodyBatteryLedgerRow.Term.recovery -> L("Sleep and sustained quiet rest since midnight")
    BodyBatteryLedgerRow.Term.awake -> {
        val minutes = BodyBatteryLedgerMath.awakeMinutes(m.bodyBatteryWakeAt, m.day.start, m.bodyBatteryObservedAt)
        if (minutes != null) L("Awake for %@", Fmt.duration(minutes)) else L("Awake fatigue while up")
    }
    BodyBatteryLedgerRow.Term.movement -> {
        val sessions = m.trainingSettlement?.sessions ?: emptyList()
        when {
            abs(d.movement) < 0.5 -> L("Light daily movement stays neutral")
            sessions.isNotEmpty() -> {
                val minutes = sessions.sumOf { max(0, (it.endedAt.timeIntervalSince(it.startedAt) / 60).toInt()) }
                L("Training sessions · %@", Fmt.duration(minutes))
            }
            else -> L("Elevated effort above daily movement")
        }
    }
    BodyBatteryLedgerRow.Term.stress -> {
        val minutes = BodyBatteryLedgerMath.stressedMinutes(m.vitalsCurve)
        when {
            minutes == null -> L("Heart rate, HRV and stress; sustained temperature and oxygen changes can limit recovery")
            minutes > 0 -> L("Stress above 45 for %@ · heart rate and HRV versus your baseline", Fmt.duration(minutes))
            else -> L("Heart rate and HRV relative to your own baseline")
        }
    }
}

/** "BASE 61 · −7": the baseline and how far last night sat from it. */
private fun baselineNote(value: Double?, base: Double?): String? {
    if (base == null) return null
    if (value == null) return L("BASE %d", base.toInt())
    return L("BASE %d · %@", base.toInt(), Fmt.signed(value - base))
}

private fun paceWord(pace: BodyBatteryLedgerMath.Pace): String = when (pace) {
    BodyBatteryLedgerMath.Pace.slower -> L("SLOWER THAN USUAL")
    BodyBatteryLedgerMath.Pace.usual -> L("USUAL PACE")
    BodyBatteryLedgerMath.Pace.faster -> L("FASTER THAN USUAL")
}

/** Heart and stress sit under the curve. They are measurements, not a second
 *  colour for the battery itself. */
@Composable
private fun VitalsCard(m: DailyMetrics) {
    val data = DataStore
    val day = m.vitalsCurve
    val hrs = day.mapNotNull { it.hr }
    val stresses = day.mapNotNull { it.stress }
    val lastTick = day.lastOrNull()
    val live = data.vitals
    val showsLive = m.day == UserDay.containing(Instant.now())
    val at = if (showsLive) live.at else lastTick?.ts
    val gone = showsLive && live.freshness == TickFreshness.gone
    val stale = showsLive && live.freshness == TickFreshness.stale
    val hr = if (gone) null else if (showsLive) (live.hr ?: lastTick?.hr) else lastTick?.hr
    val stress = if (gone) null else if (showsLive) (live.stress ?: lastTick?.stress) else lastTick?.stress
    CardBlock(
        title = L("HEART & STRESS"),
        trailing = at?.let { L("LAST TICK %@", Fmt.clock(it)) } ?: L("NO TICK"),
        trailingTint = if (gone || at == null) NB.text3Prod else NB.lime1,
    ) {
        Row {
            VitalReading(L("HEART"), hr?.toString(), "BPM", NB.lime1, stale)
            VitalReading(L("STRESS"), stress?.toString(), L("INDEX"), NB.white.copy(alpha = 0.55f), stale)
        }
        if (hrs.isNotEmpty() || stresses.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (hrs.isNotEmpty()) {
                    VitalTrace(day, { it.hr }, NB.lime1, L("HEART"), hrs.min(), hrs.max(), L("BPM"))
                }
                if (stresses.isNotEmpty()) {
                    VitalTrace(day, { it.stress }, NB.white.copy(alpha = 0.55f), L("STRESS"),
                        stresses.min(), stresses.max(), L("INDEX"))
                }
                BodyBatteryTimeAxis(m.day)
            }
        }
        Hairline()
        Prose(vitalsLine(day.size, gone, stale, data.band.connected), 13f, 6f,
            if (gone || day.isEmpty()) NB.text3Prod else NB.white.copy(alpha = 0.62f))
    }
}

private fun vitalsLine(ticks: Int, gone: Boolean, stale: Boolean, connected: Boolean): String {
    if (ticks == 0) {
        return if (connected) L("No ticks for this day yet.")
        else L("Connect the band to see the ticks it has been recording.")
    }
    if (gone) return L("Nothing for over six hours.")
    if (stale) return L("%d ticks · nothing new for a while.", ticks)
    return L("%d ticks today. Gaps stay open.", ticks)
}

/**
 * Evidence quality, in the two places evidence comes from. NIGHT is what the
 * multiplier and the morning reading stood on; DAY is what the three drain rows stood on.
 */
@Composable
private fun ConfidenceCard(m: DailyMetrics) {
    val coverage = m.reserveDrivers?.coverage
    val hrvNights = coverage?.hrvNights ?: m.nightInputs?.hrvNights ?: 0
    val rhrNights = coverage?.rhrNights ?: m.nightInputs?.rhrNights ?: 0
    val tierIndex = when (m.bodyBatteryConfidence) {
        BodyBatteryConfidence.low -> 1
        BodyBatteryConfidence.medium -> 2
        BodyBatteryConfidence.high -> 3
    }
    CardBlock(title = L("CONFIDENCE"), trailing = L(m.bodyBatteryConfidence.raw), trailingIsDot = true) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (i in 0 until 3) {
                Box(Modifier.weight(1f).height(5.dp)
                    .background(if (i < tierIndex) NB.lime1 else NB.white.copy(alpha = 0.10f), CircleShape))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GroupLabel(L("NIGHT"))
            CoverageRow(L("HRV COVERAGE"), pct(coverage?.nightHRV))
            CoverageRow(L("HEART COVERAGE"), pct(coverage?.nightRHR))
            CoverageRow(L("HRV BASELINE"), L("%d / 14 NIGHTS", hrvNights))
            CoverageRow(L("RESTING BASELINE"), L("%d / 14 NIGHTS", rhrNights))
        }
        Hairline()
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GroupLabel(L("DAY"))
            CoverageRow(L("HEART COVERAGE"), pct(coverage?.dayHeart))
            CoverageRow(L("HRV COVERAGE"), pct(coverage?.dayHRV))
            CoverageRow(L("STRESS COVERAGE"), pct(coverage?.dayStress))
        }
        Prose(L("Missing HRV or stress readings reduce confidence; they do not mean no stress."),
            13f, 6f, NB.white.copy(alpha = 0.62f))
    }
}

@Composable
private fun GroupLabel(text: String) {
    BText(text, NBFont.dot(600, 9f).tracking(0.18f), NB.lime1.copy(alpha = 0.75f))
}

private fun pct(fraction: Double?): String =
    fraction?.let { "${(min(1.0, max(0.0, it)) * 100).rounded().toInt()}%" } ?: Fmt.dash

@Composable
private fun CoverageRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        BText(title, NBFont.ui(500, 10f), NB.text3Prod, Modifier.weight(1f))
        Spacer(Modifier.width(16.dp))
        BText(value, NBFont.dot(600, 12f), if (value == Fmt.dash) NB.text3Prod else NB.text2)
    }
}

@Composable
private fun Footer(label: String, isRefreshing: Boolean, message: String?, onSync: () -> Unit) {
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            BText(label, NBFont.dot(500, 10f).tracking(0.14f), NB.text3Prod, Modifier.weight(1f))
            Spacer(Modifier.width(16.dp))
            val syncLabel = L("Sync now")
            Box(
                Modifier
                    .height(34.dp)
                    .border(1.dp, NB.hairline, CircleShape)
                    .hotZoneTap(enabled = !isRefreshing) { onSync() }
                    .semantics { contentDescription = syncLabel }
                    .testTag("bodyBattery.sync")
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                BText(L(if (isRefreshing) "SYNCING…" else "SYNC"), NBFont.dot(600, 10f).tracking(0.16f), NB.text2)
            }
        }
        if (message != null) {
            BText(message, NBFont.brand(400, 13f), NB.text3Prod, maxLines = Int.MAX_VALUE)
        }
    }
}

@Composable
private fun EmptyCard() {
    Column(
        Modifier.width(NB.Layout.contentWidth).padding(bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            BText(Fmt.dash, NBFont.dot(800, 36f), NB.text3Prod, Modifier.alignByBaseline())
            BText(L("OF 100"), NBFont.dot(600, 12f).tracking(0.18f), NB.white.copy(alpha = 0.30f), Modifier.alignByBaseline())
        }
        BText(L("NO RECENT READINESS READING"), NBFont.dot(600, 11f).tracking(0.2f), NB.ember1)
        Prose(L("Sync recent wrist readings to estimate readiness. A recorded night also establishes your morning reading."),
            16f, 8f, NB.text1)
    }
}

@Composable
private fun NeedsCard() {
    CardBlock(title = L("WHAT IT NEEDS")) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            NeedRow("Recent heart rate and activity readings")
            NeedRow("A recorded night for a morning reading")
            NeedRow("Enough complete nights to build a personal baseline")
        }
    }
}

// MARK: WEEK

@Composable
private fun WeekBoard(days: List<BodyBatteryDayFacts>, facts: (Int) -> List<BodyBatteryDayFacts>) {
    val avg = BodyBatteryWindowMath.averageWake(days)
    val peak = BodyBatteryWindowMath.peakDay(days)
    val night = BodyBatteryWindowMath.typicalNightCharge(days)
    val prior = facts(days.size * 2).take(days.size)
    val delta = MetricTrendMath.delta(current = days.map { it.wake?.toDouble() }, prior = prior.map { it.wake?.toDouble() })
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // The week leads with its shape, not a number: the line is the seven mornings
        // and the row under it says the average once, beside how it moved.
        CardBlock(title = L("SEVEN DAYS"), trailing = L("MORNING READINESS · ROLLING"), trailingIsDot = true) {
            BodyBatteryDayLine(days.map { it.wake }, avg, Modifier.fillMaxWidth().height(130.dp),
                todayIndex = days.indices.lastOrNull())
            Row(Modifier.fillMaxWidth()) {
                days.forEachIndexed { i, day ->
                    val isLast = i == days.size - 1
                    BText(Fmt.weekday(day.day.date).take(1), NBFont.dot(if (isLast) 700 else 500, 10f),
                        if (isLast) NB.lime1 else hex(0x8A8A96), Modifier.weight(1f), align = TextAlign.Center)
                }
            }
            BText(L("Rolling 7 days · lime is today. A dashed gap is a morning with no reading."),
                NBFont.ui(400, 11f).tracking(0.04f), NB.text3Prod, maxLines = Int.MAX_VALUE)
            WindowSummary(avg, delta, days.count { it.hasWake }, days.size)
        }
        SectionLabel(L("KEY METRICS"))
        VitalsStatPair(
            VitalsStatPair.Model(L("MORNING READINESS"), avg?.rounded()?.toInt()?.toString(), null, L("AVERAGE"), NB.lime1),
            VitalsStatPair.Model(L("HIGHEST"), peak?.wake?.toString(), null,
                peak?.let { Fmt.weekday(it.day.date) } ?: Fmt.dash, null),
        )
        VitalsStatPair(
            VitalsStatPair.Model(L("OVERNIGHT RECOVERY"), night?.let { Fmt.signed(it) }, null, L("TYPICAL DAY"), null),
            VitalsStatPair.Model(L("NO MORNING READING"), "${BodyBatteryWindowMath.emptyCount(days)}",
                L("OF %d", days.size), L("A gap is not a zero."), null),
        )
    }
}

// MARK: MONTH

@Composable
private fun MonthBoard(days: List<BodyBatteryDayFacts>) {
    val typical = BodyBatteryWindowMath.typicalWake(days)
    val mornings = days.count { it.hasWake }
    val empty = BodyBatteryWindowMath.emptyCount(days)
    val rolls = BodyBatteryWindowMath.weekRolls(days)
    val night = BodyBatteryWindowMath.typicalNightCharge(days)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        CardBlock(title = L("THIRTY DAYS"), trailing = L("%d MORNINGS · %d MISSING", mornings, empty), trailingIsDot = true) {
            BodyBatteryDayLine(days.map { it.wake }, typical, Modifier.fillMaxWidth().height(140.dp),
                todayIndex = days.indices.lastOrNull())
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                BText(days.firstOrNull()?.let { Fmt.displayDate(it.day.date, "d MMM").uppercase(Locale.ROOT) } ?: Fmt.dash,
                    NBFont.dot(500, 10f), hex(0x8A8A96))
                Spacer(Modifier.weight(1f))
                BText(L("TODAY"), NBFont.dot(700, 10f), NB.lime1)
            }
            BText(L("One point per morning readiness · a dashed gap is a morning with no reading."),
                NBFont.ui(400, 11f).tracking(0.04f), NB.text3Prod, maxLines = Int.MAX_VALUE)
            // Thirty mornings have no sixty behind them to compare with, so the row
            // is the typical morning and the count; the week-by-week card below is
            // where the month's drift reads.
            WindowSummary(typical, null, mornings, days.size)
        }
        SectionLabel(L("KEY METRICS"))
        VitalsStatPair(
            VitalsStatPair.Model(L("TYPICAL MORNING"), typical?.rounded()?.toInt()?.toString(), null,
                L("%d OF %d MORNINGS", mornings, days.size), NB.lime1),
            VitalsStatPair.Model(L("OVERNIGHT RECOVERY"), night?.let { Fmt.signed(it) }, null, L("TYPICAL DAY"), null),
        )
        SectionLabel(L("DETAILS"))
        CardBlock(title = L("WHAT THE MONTH LOOKED LIKE")) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                BText(L("WEEK BY WEEK"), NBFont.ui(500, 11f).tracking(0.2f), NB.text1, Modifier.weight(1f))
                Spacer(Modifier.width(16.dp))
                BText(weekTrend(rolls), NBFont.dot(700, 11f), NB.lime1)
            }
            BodyBatteryDayLine(rolls.map { r -> r.average?.rounded()?.toInt() }, typical,
                Modifier.fillMaxWidth().height(72.dp),
                todayIndex = if (rolls.isEmpty()) null else rolls.size - 1)
            Row(Modifier.fillMaxWidth()) {
                rolls.forEachIndexed { i, roll ->
                    BText(L("%dD %@", roll.days, Fmt.int(roll.average?.rounded()?.toInt())), NBFont.dot(500, 9f),
                        if (i == rolls.size - 1) NB.lime1 else hex(0x8A8A96), Modifier.weight(1f), align = TextAlign.Center)
                }
            }
            BText(L("Two days, then four weeks."), NBFont.ui(400, 11f).tracking(0.04f), NB.text3Prod)
        }
    }
}

/**
 * The window's one number, said once under its line: the average morning, how it
 * moved against the window before, and how many mornings actually recorded. A rolling
 * window has no single reading, and printed like one it read as today's.
 */
@Composable
private fun WindowSummary(headline: Double?, delta: Double?, recorded: Int, total: Int) {
    Row(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawRect(NB.white.copy(alpha = 0.06f), Offset.Zero, Size(size.width, 1.dp.toPx())) }
            .padding(top = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        BText(L("AVG %@", Fmt.int(headline?.rounded()?.toInt())), NBFont.dot(700, 14f).tracking(0.02f),
            if (headline == null) NB.text3Prod else NB.lime1, Modifier.alignByBaseline())
        if (headline != null) {
            BText(L("OF 100"), NBFont.ui(600, 10f), NB.text1, Modifier.alignByBaseline())
        }
        if (delta != null) {
            val n = delta.rounded().toInt()
            val text = L("· %@", if (n == 0) L("LEVEL WITH %@", L("PRIOR %dD", total))
            else L("%@%@ VS %@", if (n > 0) "+" else "−", abs(n).toString(), L("PRIOR %dD", total)))
            BText(text, NBFont.ui(500, 10f), NB.white.copy(alpha = 0.62f), Modifier.alignByBaseline().weight(1f, fill = false))
        }
        Spacer(Modifier.weight(1f))
        BText(L("%d OF %d MORNINGS", recorded, total), NBFont.ui(400, 10f), NB.white.copy(alpha = 0.42f),
            Modifier.alignByBaseline())
    }
}


private fun weekTrend(rolls: List<BodyBatteryWeekRoll>): String {
    val values = rolls.mapNotNull { it.average }
    if (values.size < 2) return L("NO TREND YET")
    return if (values.last() >= values.first()) L("TRENDING UP") else L("TRENDING DOWN")
}

// MARK: pieces

@Composable
private fun NeedRow(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(9.dp).border(1.dp, NB.white.copy(alpha = 0.28f), CircleShape))
        BText(L(text), NBFont.brand(400, 13f), NB.text2, maxLines = Int.MAX_VALUE)
    }
}

private val LedgerBar = 76.dp
private val LedgerDelta = 34.dp
private val LedgerBalance = 30.dp

/** One ledger line: the term, why it has its sign, a bar that leaves the centre to the
 *  right for a charge and to the left for a drain, the signed change, and the balance after. */
@Composable
private fun LedgerRow(name: String, reason: String, delta: Int, balance: Int, scale: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            BText(name, NBFont.brand(400, 13f), NB.text1, Modifier.weight(1f).padding(end = 10.dp))
            Box(Modifier.size(LedgerBar, 14.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(1.dp, 10.dp).background(NB.white.copy(alpha = 0.14f)))
                val half = LedgerBar / 2
                val length = half * (abs(delta).toFloat() / max(1, scale).toFloat())
                Box(
                    Modifier
                        .offset(x = if (delta > 0) length / 2 else -length / 2)
                        .size(width = maxOf(if (delta == 0) 0.dp else 3.dp, length), height = 6.dp)
                        .background(if (delta > 0) NB.lime1 else NB.white.copy(alpha = 0.38f), CircleShape),
                )
            }
            BText(if (delta > 0) "+$delta" else "$delta", NBFont.dot(700, 12f).tracking(0.04f),
                if (delta > 0) NB.lime1 else if (delta == 0) NB.text3Prod else NB.white.copy(alpha = 0.62f),
                Modifier.width(LedgerDelta), align = TextAlign.End)
            BText("$balance", NBFont.dot(600, 12f).tracking(0.04f), NB.text3Prod,
                Modifier.width(LedgerBalance), align = TextAlign.End)
        }
        BText(reason, NBFont.ui(400, 11f), NB.text3Prod, maxLines = Int.MAX_VALUE)
    }
}

/** The two edges of the ledger: where the day started and where it stands now. */
@Composable
private fun LedgerEdge(label: String, value: Int, note: String?, tint: Color) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BText(label, NBFont.dot(600, 10f).tracking(0.16f), NB.white.copy(alpha = 0.55f))
        if (note != null) BText(note, NBFont.dot(500, 9f).tracking(0.14f), NB.ember1)
        Spacer(Modifier.weight(1f))
        BText("$value", NBFont.dot(700, 16f).tracking(0.02f), tint)
    }
}


/**
 * Each observed rise is lime; flat or falling segments are white. Missing ticks
 * stay open. The last point marks the last observation, not an extrapolated NOW.
 */
@Composable
fun BatteryCurve(
    samples: List<ReserveSample> = emptyList(),
    day: UserDay? = null,
    dim: Boolean = false,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.alpha(if (dim) 0.45f else 1f)) {
        val last = samples.maxByOrNull { it.ts } ?: return@Canvas
        val u = density
        val window = day ?: UserDay.containing(last.ts)
        val pad = (if (compact) 3f else 8f) * u
        val inset = (if (compact) 2f else 4f) * u
        fun point(sample: ReserveSample): Offset = Offset(
            inset + BodyBatteryCurveMath.fraction(sample.ts, window).toFloat() * max(0f, size.width - inset * 2),
            size.height - pad - min(100, max(0, sample.value)) / 100f * max(0f, size.height - pad * 2),
        )
        if (!compact) {
            for (value in listOf(30f, 70f)) {
                val y = size.height - pad - value / 100f * max(0f, size.height - pad * 2)
                drawRect(NB.white.copy(alpha = 0.06f), Offset(0f, y), Size(size.width, 1f * u))
            }
        }
        val lineWidth = (if (compact) 1.5f else 2.2f) * u
        for (segment in BodyBatteryCurveMath.segments(samples)) {
            drawLine(if (segment.charging) NB.lime1 else NB.white.copy(alpha = 0.42f),
                point(segment.start), point(segment.end), strokeWidth = lineWidth, cap = StrokeCap.Round)
        }
        val r = (if (compact) 2.5f else 4.5f) * u
        drawCircle(NB.lime1, r, point(last))
    }
}

/**
 * Local clock labels share the same second-based coordinates as both charts.
 * No fixed-position NOW label implies that an old observation is current.
 */
@Composable
private fun BodyBatteryTimeAxis(day: UserDay) {
    // ⚠️ The end label is pinned to the right edge, so an hour mark that lands close to
    // it collides with it. An hour inside the last tenth of the day is dropped rather
    // than drawn on top of the edge.
    val ticks: List<Instant> = listOf(4, 10, 16, 22)
        .map { day.start.settingHour(it, 0, 0) }
        .filter { BodyBatteryCurveMath.fraction(it, day) < 0.9 } + day.end
    Layout(
        content = {
            ticks.forEach { BText(Fmt.clock(it), NBFont.dot(500, 9f), NB.white.copy(alpha = 0.34f)) }
        },
        modifier = Modifier.fillMaxWidth().height(12.dp),
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(constraints.copy(minWidth = 0, minHeight = 0)) }
        val w = constraints.maxWidth.toFloat()
        val h = 12.dp.roundToPx()
        layout(constraints.maxWidth, h) {
            val p16 = 16.dp.toPx()
            placeables.forEachIndexed { i, p ->
                val f = BodyBatteryCurveMath.fraction(ticks[i], day).toFloat()
                val x = min(max(p16, 4.dp.toPx() + f * max(0f, w - 8.dp.toPx())), max(p16, w - p16))
                p.place((x - p.width / 2f).toInt(), (6.dp.toPx() - p.height / 2f).toInt())
            }
        }
    }
}

@Composable
private fun RowScope.VitalReading(label: String, value: String?, unit: String, tint: Color, dim: Boolean = false) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        BText(label, NBFont.ui(500, 10f).tracking(0.16f), NB.text3Prod)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            BText(value ?: Fmt.dash, NBFont.dot(700, 24f).tracking(0.02f),
                if (value == null) NB.text3Prod else if (dim) NB.text2 else tint, Modifier.alignByBaseline())
            BText(unit, NBFont.dot(500, 8f).tracking(0.16f), NB.white.copy(alpha = 0.34f), Modifier.alignByBaseline())
        }
    }
}

/**
 * A day of one tick series, drawn across the same width as the battery curve.
 * ⚠️ A gap in the series is a gap in the line, not a straight segment across it.
 */
@Composable
private fun VitalTrace(
    samples: List<VitalSample>,
    value: (VitalSample) -> Int?,
    tint: Color,
    name: String,
    low: Int,
    high: Int,
    unit: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            BText(name, NBFont.dot(600, 9f).tracking(0.18f), tint.copy(alpha = tint.alpha * 0.75f))
            Spacer(Modifier.weight(1f))
            BText("$low – $high $unit", NBFont.dot(500, 9f).tracking(0.12f), NB.white.copy(alpha = 0.30f))
        }
        Canvas(Modifier.fillMaxWidth().height(34.dp)) {
            val first = samples.firstOrNull() ?: return@Canvas
            val u = density
            val day = UserDay.containing(first.ts)
            val span = max(1, high - low)
            val run = Path()
            var open = false
            var previous: Instant? = null
            for (s in samples.sortedBy { it.ts }) {
                val v = value(s)
                val prev = previous
                previous = s.ts
                if (v == null) { open = false; continue }
                if (prev != null && s.ts.timeIntervalSince(prev) > 10 * 60) open = false
                val t = BodyBatteryCurveMath.fraction(s.ts, day).toFloat()
                val x = size.width * t
                val y = size.height - ((v - low).toFloat() / span) * (size.height - 4f * u) - 2f * u
                if (open) run.lineTo(x, y) else { run.moveTo(x, y); open = true }
            }
            drawPath(run, tint.copy(alpha = tint.alpha * 0.85f),
                style = Stroke(1.6f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
    }
}
