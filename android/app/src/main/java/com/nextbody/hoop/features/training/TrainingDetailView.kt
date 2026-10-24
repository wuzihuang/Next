package com.nextbody.hoop.features.training

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.app.EntryPoint
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.FunctionStatus
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.band.TrainingCurvePoint
import com.nextbody.hoop.band.TrainingDayFacts
import com.nextbody.hoop.band.TrainingRangeStatus
import com.nextbody.hoop.band.TrainingSessionContribution
import com.nextbody.hoop.band.TrainingTargetEvidence
import com.nextbody.hoop.band.TrainingWeekRoll
import com.nextbody.hoop.band.TrainingWindowMath
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.Ports
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.vitals.FitText
import com.nextbody.hoop.features.vitals.MetricTrendMath
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.features.vitals.VitalsScaleRail
import com.nextbody.hoop.features.vitals.VitalsStatPair
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.DistantPast
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.LoadPoint
import com.nextbody.hoop.model.SportModeCatalog
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.ui.CardBlock
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.SectionLabel
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Swift reads `LiveSessionStore.shared.lastRecap` and `SportRecapStore.shared` (Features/Sport).
 * `LiveSessionStore.install()` fills this
 * feed (recaps, the live session's last recap, the error lines, `load`), and supplies the
 * recap sheet (`SportRecapView`) and the publication status row (`SportPublicationStatus`).
 */
object TrainingSportFeed {
    var lastRecap: SportSessionRecap? by mutableStateOf(null)
    var recaps: List<SportSessionRecap> by mutableStateOf(emptyList())
    var errorLine: String? by mutableStateOf(null)
    var trainingError: String? by mutableStateOf(null)
    /** `await sportRecords.load()` */
    var load: suspend () -> Unit = {}
    /** `SportRecapView(recap:)`, presented as a sheet. */
    var recapView: (@Composable (recap: SportSessionRecap, close: () -> Unit) -> Unit)? = null
    /** `SportPublicationStatus()` at the head of SESSION HISTORY. */
    var publicationStatus: (@Composable () -> Unit)? = null
    /** `Repository.shared.hydrate(detail, endingAt:, into:)`; installed by LiveSessionStore. */
    var hydrate: suspend (DetailWindow, UserDay) -> Unit = { _, _ -> }
}

private val statGrey = hex(0x8A8A96)

/**
 * 08 / ADR 0015 · training load. One page, DAY / WEEK / MONTH. DAY is the
 * ring; WEEK and MONTH are a line of daily loads. The hero stays 0–21.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrainingDetailView() {
    val data = DataStore
    var rangeRaw by rememberSaveable { mutableStateOf(RollingPills.day.raw) }
    var selectedSport by remember { mutableStateOf<SportSessionRecap?>(null) }
    val range = RollingPills.parse(rangeRaw)
    val detail = DetailWindow(DetailSurface.training, range)
    val today = UserDay.containing(Instant.now())

    val m: DailyMetrics = TrainingDebugFixture.metrics(data.today)

    val page = TrainingPage(m, range, detail, today)

    DetailScroll(
        glow = NB.lime1,
        title = MetricNames.training,
        onBack = { Router.backToRoot() },
        trailing = {
            FitText(page.headerStatus, NBFont.dot(700, 12f).tracking(0.04f), page.headerTint, minScale = 0.72f)
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SegmentedPills(RollingPills.words, rangeRaw, { rangeRaw = it }, lined = true)
            when (range) {
                RollingPills.day -> page.DayBoard { selectedSport = it }
                RollingPills.week -> page.WeekBoard()
                RollingPills.month -> page.MonthBoard()
            }
            SessionButton()
        }
    }

    // router.$windowRequest
    val request = Router.windowRequest
    LaunchedEffect(request) {
        if (request == null) return@LaunchedEffect
        rangeRaw = request
        Router.windowRequest = null
    }
    LaunchedEffect(Unit) { TrainingSportFeed.load() }
    LaunchedEffect(Unit) {
        DetailWindow.debugRange(DetailSurface.training)?.let { rangeRaw = it.raw }
        if (Band.allowsSeed) return@LaunchedEffect
        Repository.hydrate(detail, today, store = DataStore)
    }

    val recap = selectedSport
    val recapView = TrainingSportFeed.recapView
    if (recap != null && recapView != null) {
        ModalBottomSheet(
            onDismissRequest = { selectedSport = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = NB.carbon2,
            dragHandle = null,
        ) {
            recapView(recap) { selectedSport = null }
        }
    }
}

/** The page's derived reads, one per composition (Swift's computed properties). */
private class TrainingPage(
    val m: DailyMetrics,
    val range: RollingPills,
    val detail: DetailWindow,
    val today: UserDay,
) {
    val data = DataStore

    val staleMinutes: Int = data.lastSync?.let { (Instant.now().timeIntervalSince(it) / 60).toInt() } ?: Int.MAX_VALUE
    val isStale: Boolean = DebugEdgeFlag.on("stale") || staleMinutes >= 60
    val staleAgo: String
        get() {
            if (data.lastSync == null) return L("NEVER")
            return if (staleMinutes >= 120) L("%dH AGO", staleMinutes / 60) else L("%d MIN AGO", staleMinutes)
        }
    val lastSyncClock: String get() = data.lastSync?.let { Fmt.clock(it) } ?: Fmt.dash
    val autoHROff: Boolean = DebugEdgeFlag.on("autohr") || data.capabilities.autoMeasure == FunctionStatus.close
    val rangeStatus: TrainingRangeStatus =
        if (DebugEdgeFlag.on("over")) TrainingRangeStatus.Capped
        else TrainingWindowMath.rangeStatus(m.trainingLoad, m.targetLoad, m.optimalZone)
    val isOver: Boolean = rangeStatus is TrainingRangeStatus.Above || rangeStatus is TrainingRangeStatus.Capped
    val targetEvidence: TrainingTargetEvidence? = m.trainingSettlement?.target

    val curvePoints: List<LoadPoint>
        get() {
            if (TrainingDebugFixture.name != null) return m.loadCurve
            val historical = data.history.firstOrNull { it.day == m.day && it.loadCurve.isNotEmpty() }?.loadCurve ?: emptyList()
            return if ((m.loadCurve.lastOrNull()?.ts ?: DistantPast) >= (historical.lastOrNull()?.ts ?: DistantPast))
                m.loadCurve else historical
        }

    val curveData
        get() = TrainingWindowMath.curveData(
            curvePoints.map { TrainingCurvePoint(it.ts, it.load) }, m.day, Instant.now())

    val weekFacts: List<TrainingDayFacts> get() = facts(DetailWindow(DetailSurface.training, RollingPills.week).days)
    val monthFacts: List<TrainingDayFacts> get() = facts(DetailWindow(DetailSurface.training, RollingPills.month).days)

    val headerStatus: String
        get() {
            if (range != RollingPills.day) return L(detail.periodKey)
            return when (val s = rangeStatus) {
                TrainingRangeStatus.NoLoad -> L("ACTIVITY DATA NEEDED")
                TrainingRangeStatus.NoTarget -> L("NO TARGET YET")
                is TrainingRangeStatus.Below -> L("%.1f BELOW RANGE", s.by)
                TrainingRangeStatus.InRange -> L("IN RANGE")
                is TrainingRangeStatus.Above -> L("%.1f ABOVE RANGE", s.by)
                TrainingRangeStatus.Capped -> L("SCALE LIMIT")
            }
        }

    val headerTint: Color
        get() {
            if (range == RollingPills.day) {
                if (isOver) return NB.ember1
                if (m.targetLoad == null || m.trainingLoad == null) return NB.text3Prod
            }
            return NB.lime1
        }

    // MARK: DAY

    /**
     * WHOOP / Oura order: the number and what it means, the four facts behind it, then the
     * details from today's own activities down to how the target was set.
     */
    @Composable
    fun DayBoard(onRecap: (SportSessionRecap) -> Unit) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            RingCard(m.trainingLoad, "OF 21")
            DayVerdict()
            SectionLabel(L("KEY METRICS"))
            DayKeyMetrics()
            SectionLabel(L("DETAILS"))
            TodayBuildCard()
            LastSessionCard(onRecap)
            ThroughTheDayCard()
            TimeInZoneCard()
            DayMoveCard()
            EvidenceCard()
            SessionHistoryCard(onRecap)
        }
    }

    @Composable
    fun DayVerdict() {
        val (title, line) = dayVerdictText
        Column(Modifier.width(NB.Layout.contentWidth), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = NBFont.ui(600, 19f), color = headerTint)
            Text(line, style = NBFont.ui(400, 14f).copy(lineHeight = lineHeightFor(14f, 3f)), color = NB.text2)
        }
    }

    val dayVerdictText: Pair<String, String>
        get() {
            val zone = m.optimalZone
            val span = zone?.let { swiftFormat("%.1f–%.1f", it.start, it.endInclusive) } ?: Fmt.dash
            return when (val s = rangeStatus) {
                TrainingRangeStatus.NoLoad ->
                    L("ACTIVITY DATA NEEDED") to L("Movement and sessions the band records build today's load.")
                TrainingRangeStatus.NoTarget ->
                    L("NO TARGET YET") to L("No suggested range yet. Recorded activity is still shown below.")
                is TrainingRangeStatus.Below ->
                    L("Below range") to L("%.1f more reaches today's suggested range of %@. Everyday movement and sessions both count.", s.by, span)
                TrainingRangeStatus.InRange ->
                    L("In range") to L("Today's load is inside the suggested range of %@. Staying under %.1f keeps it there.", span, zone?.endInclusive ?: 0.0)
                is TrainingRangeStatus.Above ->
                    L("Above range") to L("%.1f above the suggested range of %@. Rest is the better choice for the rest of today.", s.by, span)
                TrainingRangeStatus.Capped ->
                    L("SCALE LIMIT") to L("Already above the suggested range. Nothing left to fill.")
            }
        }

    /** Today against this person's own finished days, the way WHOOP prints "vs previous 30 days". */
    @Composable
    fun DayKeyMetrics() {
        val past = monthFacts
        val zone = m.optimalZone
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            VitalsStatPair(
                left = VitalsStatPair.Model(
                    L("SUGGESTED RANGE"),
                    zone?.let { swiftFormat("%.1f–%.1f", it.start, it.endInclusive) }, null,
                    m.targetLoad?.let { L("TARGET %@", Fmt.load(it)) } ?: L("NO TARGET YET"), NB.lime1,
                ),
                right = VitalsStatPair.Model(
                    L("HR ZONES 4–5"), hardMinutes?.let { Fmt.duration(it) }, null,
                    typicalFoot(zoneMinutes(TrainingWindowMath.typicalZones(past), hard = true)?.let { Fmt.duration(it) }), null,
                ),
            )
            VitalsStatPair(
                left = VitalsStatPair.Model(
                    L("ACTIVE BURN"), m.eActive?.let { Fmt.kcal(it) }, "KCAL",
                    typicalFoot(TrainingWindowMath.typicalActiveKcal(past)?.let { Fmt.kcal(it) }), null,
                ),
                right = VitalsStatPair.Model(
                    L("STEPS"), m.steps?.let { Fmt.kcal(it.toDouble()) }, null,
                    typicalFoot(TrainingWindowMath.typicalSteps(past)?.let { Fmt.kcal(it) }), null,
                ),
            )
        }
    }

    fun typicalFoot(value: String?): String =
        value?.let { L("30-DAY TYPICAL %@", it) } ?: L("NO 30-DAY BASELINE YET")

    @Composable
    fun LastSessionCard(onRecap: (SportSessionRecap) -> Unit) {
        val feed = TrainingSportFeed
        val recap = (listOfNotNull(feed.lastRecap) + feed.recaps).firstOrNull {
            (Band.allowsSeed || (it.ownerUserID != null && it.ownerUserID == Ports.supabase.currentUserIdSnapshot())) &&
                TrainingSessionContribution.overlaps(it.startedAt, it.endedAt, m.day)
        } ?: return
        val kcal = if (recap.hasEnergy) {
            if (recap.caloriesEstimated) "≈${recap.kcal.rounded().toInt()}" else "${recap.kcal.rounded().toInt()}"
        } else Fmt.dash
        val contribution = m.trainingSettlement?.session(recap.sessionID, m.day)
        val loadLine = when {
            contribution != null -> contribution.deltaText
            Band.allowsSeed && recap.loadBefore != null && recap.loadAfter != null ->
                TrainingSessionContribution.deltaText(max(0.0, recap.loadAfter!! - recap.loadBefore!!))
            else -> L("LOAD PENDING")
        }
        CardBlock(
            title = L("LAST SESSION"), trailing = recap.title, trailingIsDot = true,
            modifier = Modifier.hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { onRecap(recap) },
        ) {
            Row {
                MoveStat(L("AVG HR"), recap.avgHR?.toString() ?: Fmt.dash, NB.lime1)
                MoveStat(L("PEAK"), recap.peakHR?.toString() ?: Fmt.dash, NB.lime1)
                MoveStat(L("KCAL EST"), kcal, NB.macroValue)
            }
            Row {
                MoveStat(L("AEROBIC"), if (recap.hasZones) L("%dm", recap.aerobicMinutes) else Fmt.dash, NB.lime1)
                MoveStat(L("ANAEROBIC"), if (recap.hasZones) L("%dm", recap.anaerobicMinutes) else Fmt.dash, NB.ember1)
                MoveStat(L("LOAD"), loadLine, NB.macroValue)
            }
            Note(L(recap.conclusion))
            if (contribution == null && !Band.allowsSeed) {
                Note(L("Session recorded. Its load will appear after sync."))
            }
        }
    }

    @Composable
    fun SessionHistoryCard(onRecap: (SportSessionRecap) -> Unit) {
        val feed = TrainingSportFeed
        if (feed.recaps.isEmpty() && feed.errorLine == null && feed.trainingError == null) return
        val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(AppLanguage.locale.javaLocale)
        CardBlock(title = L("SESSION HISTORY"), trailing = "") {
            feed.publicationStatus?.invoke()
            for (recap in feed.recaps) {
                Row(
                    Modifier.fillMaxWidth().hotZoneTap { onRecap(recap) }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(recap.title, style = NBFont.ui(400, 12f), color = NB.text1)
                        Text(formatter.format(recap.startedAt.atZone(java.time.ZoneId.systemDefault())),
                            style = NBFont.ui(400, 12f), color = NB.text3Prod)
                    }
                    // 8 + 8 + 8, as SwiftUI spaces around the Spacer
                    Spacer(Modifier.width(24.dp))
                    Text(Fmt.duration(recap.seconds / 60), style = NBFont.ui(400, 12f), color = NB.lime1)
                }
            }
        }
    }

    @Composable
    fun TodayBuildCard() {
        val sessions = m.trainingSettlement?.sessions ?: emptyList()
        val unmeasured = m.trainingSettlement?.unmeasuredSessions ?: emptyList()
        val segments = m.segments.filter { it.name != "RECORDED SESSION" }
        if (sessions.isEmpty() && unmeasured.isEmpty() && segments.isEmpty()) return
        CardBlock(title = L("TODAY'S BUILD"), trailing = L("LOAD ADDED"), trailingIsDot = true) {
            for (session in sessions) {
                val title = SportModeCatalog.modes.firstOrNull { it.rawValue == session.sportMode }?.displayName ?: L("SESSION")
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ContributionRow(
                        title,
                        L("%@ → %@ · %@ recorded", Fmt.clock(session.startedAt), Fmt.clock(session.endedAt),
                            Fmt.duration((session.observedSeconds / 60).rounded().toInt())),
                        session.deltaText,
                    )
                    if (session.reachesScaleLimit) {
                        Note(L("Load has reached the scale limit. This session is still recorded."))
                    }
                }
            }
            for (session in unmeasured) {
                val title = SportModeCatalog.modes.firstOrNull { it.rawValue == session.sportMode }?.displayName ?: L("SESSION")
                ContributionRow(
                    title,
                    "${Fmt.clock(session.startedAt)} → ${Fmt.clock(session.endedAt)} · ${L("ADDED BY YOU · NO MEASUREMENTS")}",
                    Fmt.dash,
                )
            }
            for (segment in segments) {
                ContributionRow(
                    L(segment.name),
                    if (segment.allDay) L("ALL DAY") else Fmt.clock(segment.at),
                    TrainingSessionContribution.deltaText(segment.delta),
                )
            }
        }
    }

    @Composable
    fun ContributionRow(title: String, detail: String, delta: String) {
        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = NBFont.ui(500, 13f), color = NB.text1)
                Text(detail, style = NBFont.ui(400, 10f), color = NB.text3Prod)
            }
            // HStack spacing 12 either side of a Spacer(minLength: 8)
            Spacer(Modifier.width(32.dp))
            Text(delta, style = NBFont.dot(700, 20f), color = NB.lime1, maxLines = 1)
        }
    }

    @Composable
    fun EvidenceCard() {
        // TimelineView(.periodic(from: .now, by: 60))
        val now by produceState(Instant.now()) {
            while (true) { delay(60_000); value = Instant.now() }
        }
        EvidenceCard(now)
    }

    @Composable
    fun EvidenceCard(now: Instant) {
        val te = targetEvidence
        val currentReserve = te?.followsCurrentReserve(now) == true
        val trailing = when {
            m.targetLoad == null -> L("NO TARGET YET")
            currentReserve -> L("CURRENT READINESS")
            te?.hasReserveLimit == true -> L("LAST RECORDED READINESS")
            te == null -> L("RULE ESTIMATE")
            te.limited -> L("BASELINE BUILDING")
            else -> L("SLEEP & RECOVERY")
        }
        CardBlock(title = L("TARGET BASIS"), trailing = trailing) {
            Row {
                MoveStat(L("SLEEP SCORE"), te?.sleepScore?.let { swiftFormat("%.0f", it) } ?: Fmt.dash, NB.lime1)
                MoveStat(L("RECOVERY"), te?.recoveryScore?.let { swiftFormat("%.0f", it) } ?: Fmt.dash, NB.lime1)
                MoveStat(L("RECENT LOAD"), Fmt.load(te?.recentLoad), NB.macroValue)
            }
            Note(
                when {
                    m.targetLoad == null -> L("Sleep and recovery are needed before suggesting a range. Today's activity still counts.")
                    te == null || te.limited -> L("Sleep and recovery guide today's range. More recorded days will refine it.")
                    else -> L("Last night's sleep and recovery set today's range. Recent load helps adjust it to you.")
                },
            )
            if (te?.hasReserveLimit == true) {
                Row {
                    MoveStat(L("BASE TARGET"), Fmt.load(te.baseTarget), NB.lime1)
                    MoveStat(MetricNames.bodyBattery, te.currentReserve?.let { swiftFormat("%.0f", it) } ?: Fmt.dash, NB.lime1)
                    MoveStat(L("REMAINING LOAD"), Fmt.load(te.remaining), NB.macroValue)
                }
                if (!currentReserve) {
                    Note(L("The last readiness reading still limits this target. Sync for current guidance."))
                }
                if (currentReserve && m.targetLoad != null && (te.reserveAdjustment ?: 0.0) >= -0.05) {
                    Note(L("Current readiness can lower the sleep and recovery target. Rest can raise it back toward the base target. Completed load stays recorded."))
                }
            }
            if (te != null) {
                Row {
                    MoveStat(L("SLEEP"), te.sleepMinutes?.let { Fmt.duration(it.rounded().toInt()) } ?: Fmt.dash, NB.lime1)
                    MoveStat(L("RECORDED DAYS"), "${te.historyDays}", NB.lime1)
                    MoveStat(
                        L(if (te.hasReserveLimit) "READINESS READING" else "LAST SYNC"),
                        if (te.hasReserveLimit) te.observedAt?.let { Fmt.clock(it) } ?: Fmt.dash else lastSyncClock,
                        NB.macroValue,
                    )
                }
                val adjustment = te.reserveAdjustment
                val base = te.baseTarget
                val adjusted = te.target
                if (te.hasReserveLimit && adjustment != null && adjustment < -0.05 && base != null && adjusted != null) {
                    Note(L(
                        if (currentReserve) "Current readiness has lowered today's target from %@ to %@."
                        else "The last recorded readiness has lowered today's target from %@ to %@.",
                        Fmt.load(base), Fmt.load(adjusted),
                    ))
                }
            }
            Hairline()
            val evidence = m.trainingEvidence
            if (evidence != null) {
                Row {
                    MoveStat(L("VALID HR"), coverageLine(evidence.heartRateMinutes, evidence.elapsedMinutes), NB.lime1)
                    MoveStat(L("RECORDED"), coverageLine(evidence.recordedMinutes, evidence.elapsedMinutes), NB.lime1)
                    MoveStat(L("ELAPSED"), Fmt.duration(evidence.elapsedMinutes), NB.macroValue)
                }
                Note(L("Coverage is valid recorded minutes against elapsed time, not time worn."))
            } else {
                Note(L("Recording coverage is unavailable. Sync to retrieve it."))
            }
            Note(L("Guidance, not an exercise quota."))
        }
    }

    @Composable
    fun ThroughTheDayCard() {
        CardBlock(title = L("THROUGH THE DAY"), trailing = L("CUMULATIVE 0–21"), trailingIsDot = true) {
            CumulativeCurve(
                target = m.targetLoad, zone = m.optimalZone, points = curvePoints, day = m.day,
                modifier = Modifier.height(120.dp).padding(horizontal = 14.dp),
            )
            BoxWithConstraints(Modifier.fillMaxWidth().height(14.dp)) {
                val w = maxWidth
                val density = LocalDensity.current
                for (index in 0 until 5) {
                    val fraction = index / 4.0
                    val date = m.day.start.addingTimeInterval(m.day.end.timeIntervalSince(m.day.start) * fraction)
                    var labelWidth by remember { mutableStateOf(0) }
                    val cx = 14.dp + (w - 28.dp) * fraction.toFloat()
                    Text(
                        Fmt.clock(date), style = NBFont.dot(500, 10f), color = NB.text3Prod, maxLines = 1, softWrap = false,
                        modifier = Modifier
                            .onSizeChanged { labelWidth = it.width }
                            .offset(x = cx - with(density) { (labelWidth / 2).toDp() }),
                    )
                }
            }
            val last = curveData.segments.lastOrNull()?.lastOrNull()
            if (last != null) {
                Text(L("LATEST LOAD SAMPLE %@", Fmt.clock(last.ts)), style = NBFont.ui(400, 10f), color = NB.text3Prod)
            }
            Hairline()
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(L("ELEVATED HR PERIOD"), style = NBFont.ui(500, 12f), color = NB.text1,
                    maxLines = 1, modifier = Modifier.weight(1f))
                Text(elevatedHRLine, style = NBFont.dot(700, 14f), color = NB.lime1, maxLines = 1)
            }
            Note(L("The largest elevated-heart-rate period. No sport is inferred."))
        }
    }

    val hardMinutes: Int? get() = m.zoneMinutes?.drop(3)?.sum()

    val elevatedHRLine: String
        get() {
            // Swift max(by:) keeps the last of equal maxima.
            val seg = m.segments.filter { !it.allDay }.reduceOrNull { a, b -> if (a.delta <= b.delta) b else a }
                ?: return Fmt.dash
            val mins = seg.minutes?.let { Fmt.duration(it) } ?: Fmt.dash
            return L("%@ · %.1f SHARE", mins, seg.delta)
        }

    @Composable
    fun TimeInZoneCard() {
        val mins = paddedZones(m.zoneMinutes)
        val top = max(1, mins.maxOrNull() ?: 1)
        val tints = listOf(NB.lime1.copy(alpha = 0.33f), NB.lime1.copy(alpha = 0.47f), NB.lime1, NB.ember1, NB.ember1)
        val total = mins.sum()
        CardBlock(
            title = L("TIME IN EACH ZONE"),
            trailing = if (m.zoneMinutes == null) Fmt.dash else L("%@ TOTAL", Fmt.duration(total)),
            trailingIsDot = true,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                for (i in 0 until 5) {
                    ZoneBar(
                        zone = "Z${i + 1}", fill = mins[i].toDouble() / top, tint = tints[i],
                        value = if (m.zoneMinutes == null) Fmt.dash else L("%dm", mins[i]),
                    )
                }
            }
            Text(
                L("Estimated maximum and resting heart rate. Amber is Z4–5."),
                style = NBFont.ui(400, 11f).tracking(0.04f).copy(lineHeight = lineHeightFor(11f, 5f)),
                color = NB.text3Prod,
            )
        }
    }

    @Composable
    fun DayMoveCard() {
        val bins = hourSteps(m)
        CardBlock(
            title = L("STEPS AND BURN"),
            trailing = L("%@ STEPS", Fmt.kcal(m.steps?.toDouble())),
            trailingIsDot = true,
        ) {
            if (bins != null) {
                TrainingStepBars(bins, Modifier.height(96.dp), sessionIndex = sessionBin(bins))
                Row(Modifier.fillMaxWidth()) {
                    val style = NBFont.dot(500, 10f)
                    Text(Fmt.clock(m.day.start), style = style, color = NB.text3Prod)
                    Spacer(Modifier.weight(1f))
                    Text(Fmt.clock(m.day.start.addingTimeInterval(m.day.end.timeIntervalSince(m.day.start) / 2)), style = style, color = NB.text3Prod)
                    Spacer(Modifier.weight(1f))
                    Text(Fmt.clock(m.day.end), style = style, color = NB.text3Prod)
                }
            } else {
                Text(L("STEP TIMELINE UNAVAILABLE"), style = NBFont.ui(500, 11f), color = NB.text3Prod)
            }
            Row {
                MoveStat(L("ACTIVE BURN"), Fmt.kcal(m.eActive), NB.lime1)
                MoveStat(L("RESTING"), Fmt.kcal(restingKcal), NB.macroValue)
                MoveStat(L("TOTAL EST"), Fmt.kcal(m.eOutNow), NB.macroValue)
            }
            Text(L("Calories are an estimate, not a measurement."), style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
        }
    }

    val restingKcal: Double?
        get() {
            val total = m.eOutNow
            val active = m.eActive
            if (total == null || active == null) return m.bmr
            return total - active
        }

    // MARK: WEEK

    @Composable
    fun WeekBoard() {
        val days = weekFacts
        val avg = TrainingWindowMath.averageLoad(days)
        val zones = TrainingWindowMath.typicalZones(days)
        val prior = facts(days.size * 2).take(days.size)
        val delta = MetricTrendMath.delta(finishedLoads(days), finishedLoads(prior))
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // The week leads with its columns, not a number: each day's load against the
            // target that day was set, and the average said once underneath.
            CardBlock(title = L("SEVEN DAYS"), trailing = L("LOAD VS TARGET · ROLLING"), trailingIsDot = true) {
                TrainingTargetBars(days)
                Row(Modifier.fillMaxWidth().padding(end = VitalsScaleRail.gutter)) {
                    for ((i, day) in days.withIndex()) {
                        val last = i == days.size - 1
                        Text(
                            Fmt.weekday(day.day.date), style = NBFont.ui(if (last) 500 else 400, 9f),
                            color = if (last) NB.lime1 else NB.white.copy(alpha = 0.45f),
                            textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.weight(1f),
                        )
                    }
                }
                TrainingTargetBarsLegend()
                Text(L("Rolling 7 days · today is hollow because it is still counting."),
                    style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
                WindowSummary(avg, delta, days)
            }
            SectionLabel(L("KEY METRICS"))
            WindowKeyMetrics(days)
            SectionLabel(L("DETAILS"))
            CardBlock(title = L("HOW THE ZONES STACK"), trailing = L("MINUTES / DAY"), trailingIsDot = true) {
                TrainingZoneStack(days)
                Text(
                    if (days.any { it.zoneMinutes != null })
                        L("SHARED SCALE · %@ MAX", Fmt.duration(TrainingWindowMath.zoneScaleMinutes(days).toInt()))
                    else L("NO ZONE SAMPLES"),
                    style = NBFont.ui(400, 10f), color = NB.text3Prod,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    LegendDot(NB.lime1.copy(alpha = 0.53f), L("Z1–3 · %@", Fmt.duration((zones?.take(3)?.sum() ?: 0.0).rounded().toInt())))
                    LegendDot(NB.ember1, L("Z4–5 · %@", Fmt.duration((zones?.drop(3)?.sum() ?: 0.0).rounded().toInt())))
                }
            }
            WeekMoveCard(days)
        }
    }

    /** A typical finished day of the window, as tiles: never a window sum. */
    @Composable
    fun WindowKeyMetrics(days: List<TrainingDayFacts>) {
        val zones = TrainingWindowMath.typicalZones(days)
        val counts = TrainingWindowMath.bandCounts(days)
        val finished = counts.light + counts.steady + counts.heavy + counts.over + counts.unknown
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            VitalsStatPair(
                left = VitalsStatPair.Model(
                    L("DAYS IN RANGE"), if (finished == 0) null else "${counts.steady}", L("OF %d", finished),
                    L("FINISHED DAYS ONLY"), NB.lime1,
                ),
                right = VitalsStatPair.Model(
                    L("HARD DAYS"), "${TrainingWindowMath.sessionDays(days)}", null,
                    L("20 MIN OR MORE IN Z4–5"), null,
                ),
            )
            VitalsStatPair(
                left = VitalsStatPair.Model(
                    L("HR ZONES 4–5"), zoneMinutes(zones, hard = true)?.let { Fmt.duration(it) }, null,
                    L("TYPICAL DAY"), null,
                ),
                right = VitalsStatPair.Model(
                    L("HR ZONES 1–3"), zoneMinutes(zones, hard = false)?.let { Fmt.duration(it) }, null,
                    L("TYPICAL DAY"), null,
                ),
            )
            VitalsStatPair(
                left = VitalsStatPair.Model(
                    L("STEPS"), TrainingWindowMath.typicalSteps(days)?.let { Fmt.kcal(it) }, null,
                    L("TYPICAL DAY"), null,
                ),
                right = VitalsStatPair.Model(
                    L("ACTIVE BURN"), TrainingWindowMath.typicalActiveKcal(days)?.let { Fmt.kcal(it) }, "KCAL",
                    L("TYPICAL DAY"), null,
                ),
            )
        }
    }

    @Composable
    fun WeekMoveCard(days: List<TrainingDayFacts>) {
        val steps = days.map { it.steps?.toDouble() ?: 0.0 }
        val typical = TrainingWindowMath.typicalSteps(days)
        val best = steps.maxOrNull() ?: 0.0
        CardBlock(title = L("STEPS AND BURN"), trailing = L("TYPICAL %@", Fmt.kcal(typical)), trailingIsDot = true) {
            TrainingStepBars(steps, Modifier.height(100.dp), sessionIndex = steps.indexOf(best).takeIf { it >= 0 })
            Row {
                MoveStat(L("BEST DAY"), Fmt.kcal(best), NB.ember1)
                MoveStat(L("ACTIVE BURN"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))), NB.lime1)
                MoveStat(L("TOTAL EST"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalTotalKcal(days))), NB.macroValue)
            }
            Text(L("Per-day, never a weekly sum."), style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
        }
    }

    // MARK: MONTH

    @Composable
    fun MonthBoard() {
        val days = monthFacts
        val typical = TrainingWindowMath.typicalLoad(days)
        val counts = TrainingWindowMath.bandCounts(days)
        val rolls = TrainingWindowMath.weekRolls(days)
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            CardBlock(title = L("THIRTY DAYS"), trailing = L("LOAD VS TARGET · ROLLING"), trailingIsDot = true) {
                TrainingTargetBars(days)
                Row(
                    Modifier.fillMaxWidth().padding(end = VitalsScaleRail.gutter),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        days.firstOrNull()?.let { Fmt.displayDate(it.day.date, "d MMM").uppercase() } ?: Fmt.dash,
                        style = NBFont.ui(400, 9f), color = NB.white.copy(alpha = 0.45f),
                    )
                    Spacer(Modifier.weight(1f))
                    Text(L("TODAY"), style = NBFont.ui(500, 9f), color = NB.lime1)
                }
                TrainingTargetBarsLegend()
                Text(L("One column a day on the 0–21 scale · the tick is that day's target."),
                    style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
                // Thirty days have no sixty behind them to compare with, so no change is
                // printed; the five groups below are where the month's drift reads.
                WindowSummary(typical, null, days)
            }
            SectionLabel(L("KEY METRICS"))
            WindowKeyMetrics(days)
            SectionLabel(L("DETAILS"))
            CardBlock(title = L("WHAT THE MONTH LOOKED LIKE")) {
                MonthBandRow(L("LIGHT"), counts.light, 30, NB.lime1.copy(alpha = 0.33f))
                MonthBandRow(L("STEADY"), counts.steady, 30, NB.lime1)
                MonthBandRow(L("HEAVY"), counts.heavy + counts.over, 30, NB.ember1)
                MonthBandRow(L("NO TARGET"), counts.unknown, 30, NB.text3Prod)
                Note(L("Each finished day uses its own range. Today is excluded."))
                Hairline()
                Row(Modifier.fillMaxWidth()) {
                    Text(L("FIVE GROUPS"), style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text1,
                        modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(16.dp))
                    Text(weekTrend(rolls), style = NBFont.dot(700, 11f), color = NB.lime1)
                }
                TrainingDayLine(
                    values = rolls.map { it.average }, average = typical,
                    todayIndex = if (rolls.isEmpty()) null else rolls.size - 1,
                    modifier = Modifier.height(72.dp),
                )
                Row(Modifier.fillMaxWidth()) {
                    for ((i, roll) in rolls.withIndex()) {
                        FitText(
                            L("%dD %@", roll.days, Fmt.load(roll.average)), NBFont.dot(500, 9f),
                            if (i == rolls.size - 1) NB.lime1 else statGrey,
                            Modifier.weight(1f), minScale = 0.7f, align = TextAlign.Center,
                        )
                    }
                }
                Text(L("2 days, then four groups of 7."), style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
            }
            MonthMoveCard(days, rolls)
        }
    }

    @Composable
    fun MonthMoveCard(days: List<TrainingDayFacts>, rolls: List<TrainingWeekRoll>) {
        val typical = TrainingWindowMath.typicalSteps(days)
        val weekSteps = rolls.map { roll ->
            TrainingWindowMath.typicalSteps(days.filter { it.day >= roll.start && it.day <= roll.end })
        }
        val peak = maxOf(typical ?: 0.0, weekSteps.filterNotNull().maxOrNull() ?: 0.0, 1.0)
        CardBlock(title = L("STEPS AND BURN"), trailing = L("TYPICAL %@", Fmt.kcal(typical)), trailingIsDot = true) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((i, roll) in rolls.withIndex()) {
                    val steps = weekSteps[i]
                    val last = i == rolls.size - 1
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(L("%dD", roll.days), style = NBFont.dot(700, 10f), color = statGrey, modifier = Modifier.width(26.dp))
                        Box(
                            Modifier.size(max(0.0, 200 * ((steps ?: 0.0) / peak)).dp, 12.dp)
                                .background(if (last) NB.ember1 else NB.lime1.copy(alpha = 0.85f), CircleShape),
                        )
                        Text(
                            Fmt.kcal(steps), style = NBFont.dot(700, 11f), color = if (last) NB.ember1 else NB.macroValue,
                            textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
            Row {
                MoveStat(L("RECORDED DAYS"), L("%d OF %d", TrainingWindowMath.recordedCount(days), days.size), NB.lime1)
                MoveStat(L("ACTIVE BURN"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))), NB.lime1)
                MoveStat(L("TOTAL EST"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalTotalKcal(days))), NB.macroValue)
            }
            Text(L("Each bar is that group's typical day."), style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
        }
    }

    fun weekTrend(rolls: List<TrainingWeekRoll>): String {
        val values = rolls.mapNotNull { it.average }
        if (values.size < 2) return L("NO TREND YET")
        return if (values.last() >= values.first()) L("TRENDING UP") else L("TRENDING DOWN")
    }

    @Composable
    fun MonthBandRow(label: String, count: Int, total: Int, tint: Color) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = NBFont.dot(700, 10f), color = statGrey, maxLines = 1, modifier = Modifier.width(52.dp))
            Box(Modifier.size(max(0f, 200f * count / max(1, total)).dp, 14.dp).background(tint, CircleShape))
            Text(
                L("%d DAYS", count), style = NBFont.dot(700, 11f), color = tint,
                textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.weight(1f),
            )
        }
    }

    // MARK: shared chrome

    /** Finished days only: today is still counting and must not pull the average. */
    fun finishedLoads(days: List<TrainingDayFacts>): List<Double?> = days.map { if (it.isOpen) null else it.load }

    /**
     * The window's one number, said once under its columns: the average finished day,
     * how it moved against the window before, and how many finished days landed in
     * their zone. A rolling window has no single reading, so no 64pt figure.
     */
    @Composable
    fun WindowSummary(average: Double?, delta: Double?, days: List<TrainingDayFacts>) {
        val counts = TrainingWindowMath.bandCounts(days)
        val finished = counts.light + counts.steady + counts.heavy + counts.over + counts.unknown
        Row(
            Modifier
                .fillMaxWidth()
                .drawBehind { drawRect(NB.white.copy(alpha = 0.06f), Offset.Zero, Size(size.width, 1.dp.toPx())) }
                .padding(top = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                L("AVG %@", Fmt.load(average)), style = NBFont.dot(700, 14f).tracking(0.02f),
                color = if (average == null) NB.text3Prod else NB.lime1, maxLines = 1, softWrap = false,
                modifier = Modifier.alignByBaseline(),
            )
            if (average != null) {
                Text(L("OF 21"), style = NBFont.ui(600, 10f), color = NB.text1, modifier = Modifier.alignByBaseline())
            }
            if (delta != null) {
                val magnitude = Fmt.load(abs(delta))
                val span = L("PRIOR %dD", days.size)
                Text(
                    L("· %@", if (magnitude == Fmt.load(0.0)) L("LEVEL WITH %@", span)
                    else L("%@%@ VS %@", if (delta > 0) "+" else "−", magnitude, span)),
                    style = NBFont.ui(500, 10f), color = NB.white.copy(alpha = 0.62f), maxLines = 1, softWrap = false,
                    modifier = Modifier.alignByBaseline(),
                )
            }
            Spacer(Modifier.weight(1f))
            Text(
                L("%d OF %d DAYS IN ZONE", counts.steady, finished), style = NBFont.ui(400, 10f),
                color = NB.white.copy(alpha = 0.42f), maxLines = 1, softWrap = false,
                modifier = Modifier.alignByBaseline(),
            )
        }
    }

    @Composable
    fun RingCard(load: Double?, caption: String) {
        val day = range == RollingPills.day
        Column(
            Modifier.width(NB.Layout.contentWidth).padding(top = 8.dp, bottom = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            BigTrainingRing(
                load = load,
                target = if (day) m.targetLoad else null,
                zone = if (day) m.optimalZone else null,
                tint = if (isOver && day) NB.ember1 else if (isStale && day) hex(0x6B7039) else NB.lime1,
                heroTint = if (isStale && day) hex(0xB8B46A) else null,
                over = isOver && day,
                caption = caption,
            )
            if (day) DayEdges()
        }
    }

    @Composable
    fun DayEdges() {
        if (isStale) {
            EdgeNote(
                sub = L("AS OF %@", lastSyncClock), line = L("LAST SYNC %@", staleAgo),
                text = if (data.lastSync == null) L("No sync time yet. Records may be incomplete.")
                else L("Synced %@. Later activity may be missing.", lastSyncClock),
            )
        }
        if (autoHROff) {
            EdgeNote(
                line = L("AUTO HR IS OFF"),
                text = L("Steps still count. Turn on continuous heart rate for intensity."),
                action = { Router.open(Destination.DeviceAutoMonitor, EntryPoint.home) },
            )
        }
    }

    fun facts(count: Int): List<TrainingDayFacts> = today.rollingBack(count).map { day ->
        val row = if (day == today) m else (data.history.firstOrNull { it.day == day } ?: DailyMetrics(day = day))
        TrainingDayFacts(
            day = day,
            load = row.trainingLoad,
            target = row.targetLoad,
            zone = row.optimalZone,
            zoneMinutes = row.zoneMinutes,
            steps = row.steps,
            activeKcal = row.eActive,
            totalKcal = row.eOutNow,
            worn = row.worn,
            isOpen = day == today && !day.isClosed,
        )
    }

    fun paddedZones(zones: List<Int>?): List<Int> {
        val mins = (zones ?: emptyList()).toMutableList()
        while (mins.size < 5) mins.add(0)
        return mins.take(5)
    }

    fun coverageLine(minutes: Int, elapsed: Int): String {
        if (elapsed <= 0) return Fmt.dash
        val percent = (100 * minutes.toDouble() / elapsed).rounded().toInt()
        return L("%d%% · %@", min(100, max(0, percent)), Fmt.duration(minutes))
    }

    fun zoneMinutes(zones: List<Double>?, hard: Boolean): Int? {
        if (zones == null || zones.size < 5) return null
        val slice = if (hard) zones.drop(3) else zones.take(3)
        return slice.sum().rounded().toInt()
    }

    fun hourSteps(row: DailyMetrics): List<Double>? {
        val ticks = data.history.firstOrNull { it.day == row.day && it.vitalsCurve.isNotEmpty() }?.vitalsCurve
            ?: row.vitalsCurve
        if (ticks.none { it.steps != null }) return null
        val bins = MutableList(12) { 0.0 }
        for (tick in ticks) {
            val steps = tick.steps ?: continue
            if (tick.ts < row.day.start || tick.ts >= row.day.end || steps <= 0) continue
            bins[min(11, (TrainingWindowMath.dayFraction(tick.ts, row.day) * 12).toInt())] += steps.toDouble()
        }
        return bins
    }

    fun sessionBin(bins: List<Double>): Int? {
        val seg = m.segments.firstOrNull { !it.allDay }
            // Swift max(by:) keeps the last of equal maxima.
            ?: return bins.withIndex().reduceOrNull { a, b -> if (a.value <= b.value) b else a }?.index
        val hour = UserDay.hours(seg.at, m.day)
        if (hour < 0 || hour >= 24) return null
        return min(11, (hour / 2).toInt())
    }
}

@Composable
private fun SessionButton() {
    Column(
        Modifier.fillMaxWidth().padding(top = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier
                .width(NB.Layout.contentWidth)
                .height(48.dp)
                .background(NB.lime1, CircleShape)
                .hotZoneTap {
                    // Swift `router.path = [.sportMode]`: the stack becomes the one page.
                    Router.backToRoot()
                    Router.open(Destination.SportMode)
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(L("START A SESSION"), style = NBFont.ui(500, 12f).tracking(0.2f), color = NB.carbon)
        }
        Text(L("PICK A MODE · THE BAND RUNS IT"), style = NBFont.dot(500, 9.5f).tracking(0.14f), color = NB.text3Prod)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.MoveStat(label: String, value: String, tint: Color) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = NBFont.ui(400, 10f).tracking(0.14f), color = statGrey, maxLines = 1)
        FitText(value, NBFont.dot(700, 15f), tint, minScale = 0.7f)
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = NBFont.ui(400, 11f), color = NB.text3Prod)
}

@Composable
private fun LegendDot(color: Color, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(color, RoundedCornerShape(3.dp)))
        Text(text, style = NBFont.dot(700, 10f), color = statGrey)
    }
}
