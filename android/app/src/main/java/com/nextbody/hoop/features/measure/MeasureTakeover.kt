package com.nextbody.hoop.features.measure

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.app.EntryPoint
import com.nextbody.hoop.app.MeasureKind
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandLog
import com.nextbody.hoop.band.BandMain
import com.nextbody.hoop.band.BandMeasurementLifetimeShared
import com.nextbody.hoop.band.BodyCompositionReading
import com.nextbody.hoop.band.CompositionScan
import com.nextbody.hoop.band.LiveReadout
import com.nextbody.hoop.band.MeasurementProgress
import com.nextbody.hoop.band.MeasurementResult
import com.nextbody.hoop.band.PartialReading
import com.nextbody.hoop.band.PersonalInfo
import com.nextbody.hoop.band.PulseStudy
import com.nextbody.hoop.band.PulseStudyStep
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.Goal
import com.nextbody.hoop.model.MeasurementRecord
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.BalanceCheckQueue
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.ui.CloseMark
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.rememberReduceMotion
import com.nextbody.hoop.ui.swiftSpring
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * 06 · 02–04 · the measurement takeover.
 * It is not a new page — it is the panel grown to full screen, so the only way out is the close
 * mark. 0.92 → full bleed in 0.46 s, corner radius held.
 *
 * Choreography: the finger arrives, the band answers, the number writes itself, then the whole
 * thing folds back into the panel as one widget (`Router.measuredWidget`).
 *
 * Wire for `Takeover.Measure(kind)`; `close` dismisses the takeover.
 */
@Composable
fun MeasureTakeover(kind: MeasureKind, close: () -> Unit) {
    val m = remember(kind) { MeasureModel(kind) }
    m.done = close

    // `onAppear { open() }` / `onDisappear { cancelMeasurement() }`.
    DisposableEffect(m) {
        m.open()
        onDispose { m.cancelMeasurement() }
    }
    // The second hand: the phone's clock counts only when the band has none of its own.
    LaunchedEffect(m) {
        while (true) {
            delay(1_000)
            m.tick()
        }
    }
    // The body scan's result hero writes itself 120 ms after the screen lands.
    LaunchedEffect(m.phase) {
        if (!(m.isBodyScan && m.phase == MeasurePhase.result)) {
            m.resultHeroVisible = false
            return@LaunchedEffect
        }
        m.resultHeroVisible = false
        delay(120)
        m.resultHeroVisible = true
    }

    val grownScale by animateFloatAsState(if (m.grown) 1f else 0.92f, swiftSpring(0.46f, 0.86f), label = "grow")
    val grownProgress by animateFloatAsState(if (m.grown) 1f else 0f, swiftSpring(0.46f, 0.86f), label = "grown")
    val contentAlpha by animateFloatAsState(if (m.grown) 1f else 0f, swiftSpring(0.46f, 0.86f), label = "alpha")
    val radius = NB.R.hero * (1 - grownProgress).coerceIn(0f, 1f)

    Box(
        Modifier
            .fillMaxSize()
            .scale(grownScale)
            // ⚠️ The clip covers the whole screen, system bars included: the field reaches
            // the edges, and only the words put the inset back for themselves.
            .clip(RoundedCornerShape(radius))
            .background(NB.panelInk),
    ) {
        // 06 · the field is the SCREEN, not a panel in the middle of one. Drawn behind
        // everything and never taking a touch — the close mark is still the only way out.
        AnimatedVisibility(m.isBalance && m.balanceFieldVisible, enter = fadeIn(), exit = fadeOut()) {
            BreathingDots(
                bpm = m.balanceTempo,
                modifier = Modifier.fillMaxSize(),
                intensity = 0.25 + 0.75 * m.studyProgress,
                held = m.phase == MeasurePhase.lost,
            )
        }

        Box(Modifier.fillMaxSize().alpha(contentAlpha)) {
            when {
                m.isBodyScan -> BodyScanContent(m)
                m.isBalance && BalanceLayout.current != BalanceLayout.original -> BalanceVariant(m)
                else -> OriginalColumn(m)
            }
        }
    }
}

// MARK: layouts

/** 06 · E/F · the board's column, centred: eyebrow and close mark, one sentence, the band,
 *  the count, and the two lines at the foot. */
@Composable
private fun OriginalColumn(m: MeasureModel) {
    val over = m.isBalance && m.balanceFieldVisible
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(ScreenMetrics.safeTop + Chrome.gateTopInset))
        MeasureHeader(m)
        Crossfading(m.headlineText, Modifier.padding(top = 32.dp)) {
            MText(it, NBFont.brand(500, 20f).tracking(-0.01f), NB.text1, Modifier.width(318.dp),
                align = TextAlign.Center, shadow = over)
        }
        Settled(m)
        Box(Modifier.fillMaxWidth().weight(1f)) { Stage(m) }
        Count(m)
        // The Doto line is the state, not a command.
        MText(m.statusLine, NBFont.dot(600, 10.5f).tracking(0.16f), m.statusTint,
            Modifier.width(NB.Layout.contentWidth), align = TextAlign.Center, shadow = over)
        // Grey, in front — what to do if it breaks, said before it breaks.
        MText(m.helpLine, NBFont.ui(300, 12.5f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 18.dp).width(318.dp), align = TextAlign.Center, shadow = over)
        Spacer(Modifier.height(26.dp))
    }
}

/** The balance check's chosen layouts: eyebrow and close mark at the top and the help line
 *  at the foot — the way out and the way to fix it — never move. */
@Composable
private fun BalanceVariant(m: MeasureModel) {
    val over = m.balanceFieldVisible
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(ScreenMetrics.safeTop + Chrome.gateTopInset))
        MeasureHeader(m)
        when (BalanceLayout.current) {
            BalanceLayout.header -> {
                BalanceHeader(m.balanceTempo, m.balanceSourceLine, m.remaining, m.total, m.statusLine,
                    if (m.phase == MeasurePhase.lost) NB.ember1 else NB.lime1, over, Modifier.padding(top = 24.dp))
                Spacer(Modifier.weight(1f))
            }
            BalanceLayout.dashboard -> {
                BalanceDashboard(m.balanceTempo, m.remaining, m.total,
                    contact = m.phase != MeasurePhase.lost && m.phase != MeasurePhase.notWearing,
                    over = over, tint = NB.lime1, modifier = Modifier.padding(top = 22.dp))
                Spacer(Modifier.weight(1f))
                MText(m.headlineText, NBFont.brand(500, 18f).tracking(-0.01f), NB.text1,
                    Modifier.width(318.dp), align = TextAlign.Center, shadow = over)
            }
            BalanceLayout.monolith -> {
                Spacer(Modifier.weight(1f))
                BalanceMonolith(m.balanceTempo, m.balanceSourceLine, m.remaining,
                    if (m.phase == MeasurePhase.lost) NB.ember1 else NB.lime1, over)
                Spacer(Modifier.weight(1f))
                // The sentence lives at the foot, directly over the help line.
                BalanceFootLine(m.headlineText, over, Modifier.padding(bottom = 10.dp))
            }
            BalanceLayout.original -> Unit
        }
        MText(m.helpLine, NBFont.ui(300, 12.5f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 18.dp).width(318.dp), align = TextAlign.Center, shadow = over)
        Spacer(Modifier.height(ScreenMetrics.safeBottom + 18.dp))
    }
}

@Composable
private fun BodyScanContent(m: MeasureModel) {
    val screen = when (m.phase) {
        MeasurePhase.counting, MeasurePhase.halfway, MeasurePhase.lost, MeasurePhase.computing -> 1
        MeasurePhase.result -> 2
        else -> 0
    }
    AnimatedContent(screen, transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) },
        label = "scan", modifier = Modifier.fillMaxSize()) { s ->
        val copy = m.scanCopy
        when (s) {
            0 -> BodyScanPrepareLayout(
                topInset = ScreenMetrics.safeTop + Chrome.gateTopInset,
                bottomInset = ScreenMetrics.safeBottom + 24.dp,
                status = copy.status, statusTint = copy.tint, headline = copy.headline, help = copy.help,
                header = { MeasureHeader(m) },
                stage = {
                    val blank = m.phase == MeasurePhase.failed || m.phase == MeasurePhase.busy ||
                        m.phase == MeasurePhase.dropped || m.phase == MeasurePhase.noReading
                    if (!blank) HoopFigure(m.hoopMode)
                },
            )
            1 -> BodyScanScanningLayout(
                topInset = ScreenMetrics.safeTop + Chrome.gateTopInset,
                bottomInset = ScreenMetrics.safeBottom + 28.dp,
                headerHeight = 34.dp,
                remaining = m.remaining, held = m.phase == MeasurePhase.lost,
                status = copy.status, statusTint = copy.tint, headline = copy.headline, help = copy.help,
                beat = if (m.phase == MeasurePhase.computing) m.total else m.total - m.remaining,
                total = m.total, beatAt = m.beatAt, complete = m.phase == MeasurePhase.computing,
                header = { MeasureHeader(m) },
            )
            else -> BodyScanResult(m)
        }
    }
}

@Composable
private fun BodyScanResult(m: MeasureModel) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(ScreenMetrics.safeTop + Chrome.gateTopInset))
        MeasureHeader(m)
        Spacer(Modifier.weight(1f))
        MText(L("BODY FAT"), NBFont.dot(600, 11f).tracking(0.16f), NB.white.copy(alpha = 0.72f),
            Modifier.padding(top = 28.dp))
        Box(Modifier.height(106.dp), contentAlignment = Alignment.Center) {
            val heroAlpha by animateFloatAsState(if (m.resultHeroVisible) 1f else 0.6f, tween(550), label = "hero")
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                MText(if (m.resultHeroVisible) m.bodyFatValue else Fmt.dash,
                    NBFont.dot(700, 88f).tracking(-0.04f), NB.white, Modifier.alignByBaseline().alpha(heroAlpha))
                MText("%", NBFont.dot(500, 14f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline())
            }
        }
        MText(m.bodyFatDelta, NBFont.dot(500, 10.5f).tracking(0.1f), m.bodyFatDeltaTint,
            maxLines = 1, minScale = 0.8f)
        ResultMetricGrid(m, Modifier.padding(top = 22.dp))
        Row(Modifier.padding(start = 24.dp, end = 24.dp, top = 15.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MText(L("+ %d MORE FIELDS", m.remainingFieldCount), NBFont.dot(600, 10.5f).tracking(0.08f),
                NB.white.copy(alpha = 0.55f), Modifier.weight(1f).padding(end = 8.dp), maxLines = 1, minScale = 0.7f)
            MText(L("IN COMPOSITION →"), NBFont.dot(600, 10.5f).tracking(0.08f), NB.lime1,
                Modifier.clickable(remember { MutableInteractionSource() }, null) { m.openComposition() })
        }
        Spacer(Modifier.height(32.dp))
        Spacer(Modifier.weight(3f))
        Box(
            Modifier
                .padding(start = NB.Layout.gutter, end = NB.Layout.gutter, top = 20.dp)
                .fillMaxWidth()
                .height(52.dp)
                .background(NB.lime1, CircleShape)
                .clickable(remember { MutableInteractionSource() }, null) { m.done() },
            contentAlignment = Alignment.Center,
        ) {
            MText(L("DONE"), NBFont.dot(600, 13f).tracking(0.14f), NB.panelInk)
        }
        MText(L("Next scan is worth taking in 7 days. A wrist reading moves with water and the hour."),
            NBFont.ui(300, 12f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 14.dp).width(318.dp), align = TextAlign.Center)
        Spacer(Modifier.height(ScreenMetrics.safeBottom + 18.dp))
    }
}

@Composable
private fun ResultMetricGrid(m: MeasureModel, modifier: Modifier = Modifier) {
    val r = m.resultReading
    val rule = NB.white.copy(alpha = 0.1f)
    Column(modifier.padding(horizontal = NB.Layout.gutter).fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
        Row(Modifier.fillMaxWidth().height(68.dp)) {
            ResultMetric(L("FAT MASS"), positive(r?.fatMassKg), L("KG"))
            ResultRule()
            ResultMetric(L("LEAN MASS"), positive(r?.leanMassKg), L("KG"))
            ResultRule()
            ResultMetric(L("MUSCLE"), positive(r?.muscleKg), L("KG"), lime = true)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
        Row(Modifier.fillMaxWidth().height(68.dp)) {
            ResultMetric(L("BODY WATER"), positive(r?.bodyWaterPercent), "%")
            ResultRule()
            ResultMetric(L("BONE"), positive(r?.boneKg), L("KG"))
            ResultRule()
            ResultMetric(L("BMR"), positive(r?.bmrKcal?.toDouble(), decimals = 0), L("KCAL"))
        }
    }
}

@Composable
private fun ResultRule() {
    Box(Modifier.padding(vertical = 15.dp).width(1.dp).fillMaxHeight().background(NB.white.copy(alpha = 0.1f)))
}

@Composable
private fun RowScope.ResultMetric(label: String, value: String, unit: String, lime: Boolean = false) {
    Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
        MText(label, NBFont.dot(600, 10.5f).tracking(0.08f), NB.white.copy(alpha = 0.55f), maxLines = 1, minScale = 0.65f)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            MText(value, NBFont.dot(700, 26f), if (lime) NB.lime1 else NB.white, Modifier.alignByBaseline(),
                maxLines = 1, minScale = 0.55f)
            if (value != Fmt.dash) {
                MText(unit, NBFont.dot(500, 10f), NB.white.copy(alpha = 0.4f), Modifier.alignByBaseline(), maxLines = 1)
            }
        }
    }
}

/** The board's header: what is being measured on the left; the only way out on the right.
 *  06 · the close mark is the sole exit — nothing on this screen times out. */
@Composable
private fun MeasureHeader(m: MeasureModel) {
    val over = m.isBalance && m.balanceFieldVisible
    // Android only · system back is the close mark: the same leave (or done, on a scan result).
    androidx.activity.compose.BackHandler(enabled = m.phase != MeasurePhase.opening) {
        if (m.isBodyScan && m.phase == MeasurePhase.result) m.done() else m.leave()
    }
    Row(Modifier.width(NB.Layout.contentWidth).height(34.dp), verticalAlignment = Alignment.CenterVertically) {
        // ⚠️ White over the field, not the usual lime: lime on a lime-heavy point cloud with a
        // coloured fringe was unreadable.
        MText(m.eyebrow, NBFont.dot(600, 11f).tracking(0.24f),
            if (over) NB.white.copy(alpha = 0.92f) else NB.lime1, shadow = over)
        Spacer(Modifier.weight(1f))
        Box(
            Modifier
                .size(44.dp, 34.dp)
                .alpha(if (m.phase == MeasurePhase.opening) 0f else 1f)
                .clickable(remember { MutableInteractionSource() }, null,
                    enabled = m.phase != MeasurePhase.opening) {
                    if (m.isBodyScan && m.phase == MeasurePhase.result) m.done() else m.leave()
                },
            contentAlignment = Alignment.Center,
        ) { CloseMark() }
    }
}

/** The number the band has already settled, in the empty half of the screen. */
@Composable
private fun Settled(m: MeasureModel) {
    val show = (m.phase == MeasurePhase.halfway || m.phase == MeasurePhase.lost) && m.reading != null
    AnimatedVisibility(show, enter = fadeIn(), exit = fadeOut()) {
        val lost = m.phase == MeasurePhase.lost
        Column(Modifier.padding(top = 22.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MText(m.firstNumber, NBFont.brand(700, 34f).tracking(-0.045f),
                    if (lost) NB.white.copy(alpha = 0.32f) else NB.text1, Modifier.alignByBaseline())
                MText(if (m.isBodyScan) "%" else L("BPM"), NBFont.dot(500, 12f),
                    NB.white.copy(alpha = if (lost) 0.20f else 0.42f), Modifier.alignByBaseline())
            }
            MText(
                if (m.isBodyScan) L("BODY FAT · SETTLED")
                else if (m.isBalance) L("HEART RATE · MEASURING") else L("HEART RATE · SETTLED"),
                NBFont.dot(500, 10f).tracking(0.2f), NB.white.copy(alpha = if (lost) 0.20f else 0.34f))
        }
    }
}

/** The count: Doto, big, white while it runs, amber the moment a finger comes off. */
@Composable
private fun Count(m: MeasureModel) {
    when (m.phase) {
        MeasurePhase.opening, MeasurePhase.waiting, MeasurePhase.nudge, MeasurePhase.contact,
        MeasurePhase.failed, MeasurePhase.busy, MeasurePhase.dropped, MeasurePhase.noReading,
        MeasurePhase.notWearing -> Unit
        else -> Box(Modifier.height(56.dp), contentAlignment = Alignment.Center) {
            MText(swiftFormat("00:%02d", max(0, m.remaining)), NBFont.dot(700, 52f).tracking(0.04f),
                if (m.phase == MeasurePhase.lost) NB.ember1 else NB.text1,
                shadow = m.isBalance && m.balanceFieldVisible)
        }
    }
}

/** The figure is the band itself. A battery check keeps the trace over the band, dimmed to 14 %. */
@Composable
private fun Stage(m: MeasureModel) {
    when (m.phase) {
        MeasurePhase.opening, MeasurePhase.waiting -> HoopFigure(HoopFigureMode.waiting)
        // Amber is the first time this flow uses colour: "we need you to move", never "failed".
        MeasurePhase.nudge, MeasurePhase.notWearing -> HoopFigure(HoopFigureMode.nudge)
        MeasurePhase.contact -> when {
            m.isBodyScan -> HoopFigure(HoopFigureMode.contact)
            m.isBalance -> BalanceStage(m)
            else -> TraceOverBand(m.reading?.heartRate, NB.lime1, 1.0)
        }
        // Nothing where the reading would have been: an empty frame reads as a lost number.
        MeasurePhase.failed, MeasurePhase.busy, MeasurePhase.dropped, MeasurePhase.noReading -> Unit
        else -> when {
            m.isBodyScan -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ScanBody(
                    beat = if (m.phase == MeasurePhase.computing || m.phase == MeasurePhase.result) m.total else m.total - m.remaining,
                    total = m.total, beatAt = m.beatAt, held = m.phase == MeasurePhase.lost,
                    complete = m.phase == MeasurePhase.computing || m.phase == MeasurePhase.result,
                    modifier = Modifier.fillMaxWidth().height(280.dp))
            }
            m.isBalance -> BalanceStage(m)
            // ⚠️ Not an ECG channel: this Battery Check is PPG heart rate, shaped into a
            // monitor sweep from the measured BPM.
            else -> TraceOverBand(m.reading?.heartRate,
                if (m.phase == MeasurePhase.lost) NB.ember2 else NB.lime1,
                if (m.phase == MeasurePhase.computing) 0.0 else 1.0)
        }
    }
}

@Composable
private fun TraceOverBand(bpm: Int?, tint: Color, amplitude: Double) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        HoopFigure(HoopFigureMode.lit, Modifier.alpha(0.14f))
        LiveECG(bpm, Modifier.fillMaxWidth().height(96.dp), tint, amplitude)
    }
}

/** What is left in the stage slot once the field became the whole screen: the one line that
 *  says where the tempo is coming from. ⚠️ The field is deliberately NOT a heart trace. */
@Composable
private fun BalanceStage(m: MeasureModel) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        MText(m.balanceSourceLine, NBFont.dot(500, 9.5f).tracking(0.18f), NB.white.copy(alpha = 0.42f),
            shadow = m.isBalance && m.balanceFieldVisible)
    }
}

@Composable
private fun <T> Crossfading(value: T, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    AnimatedContent(value, modifier, transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(240)) },
        label = "fade", contentAlignment = Alignment.Center) { content(it) }
}

// MARK: the model

enum class MeasurePhase {
    opening, waiting, nudge, contact, counting, halfway, lost, computing, result, failed,
    // 06 edges · the four device-side states are 32 % + a Doto line, never amber (rule 07).
    notWearing, busy, dropped, noReading,
}

@Stable
private class MeasureModel(val kind: MeasureKind) {
    var done: () -> Unit = {}

    /** F1 rule 05 · the takeover's only exit is the close mark, and the measurement has to be
     *  stopped before it goes. Cancelling this job ends the stream, which stops the test. */
    private var run: Job? = null
    private val measurementID: UUID = UUID.randomUUID()
    private val data = DataStore

    var fields by mutableIntStateOf(0)
    var phase by mutableStateOf(MeasurePhase.opening)
    private var _remaining by mutableIntStateOf(60)
    var remaining: Int
        get() = _remaining
        set(v) {
            // `.onChange(of: remaining) { beatAt = Date() }` — the body figure hops from here.
            if (v != _remaining) beatAt = Instant.now()
            _remaining = v
        }
    var lostGrace by mutableStateOf(3.0)
    var grown by mutableStateOf(false)
    var reading by mutableStateOf<PartialReading?>(null)
    var resultReading by mutableStateOf<BodyCompositionReading?>(null)
    var previousScan by mutableStateOf<CompositionScan?>(null)
    private var resultScanAt: Instant? = null
    private var scanOpenedAt: Instant = Instant.now()
    private var scanStartedAt: Instant? = null
    private var scanRestarts = 0
    var resultHeroVisible by mutableStateOf(false)
    var failure by mutableStateOf<String?>(null)
    /** True once the stream has carried the band's own seconds; the phone's clock then stops. */
    private var bandClock = false
    var beatAt by mutableStateOf(Instant.now())
    private var hrSamples: List<Int> = emptyList()
    /** 06 · how far into the balance check, 0…1. */
    var studyProgress by mutableStateOf(0.0)

    val isBodyScan: Boolean get() = kind == MeasureKind.bodyComposition
    /** 06 · the balance check. ⚠️ The kind is still `.ecg` because that is the SDK command
     *  underneath; nothing the user reads ever says so. */
    val isBalance: Boolean get() = kind == MeasureKind.ecg
    /** Measured on a real NEXTBODY: the balance check runs 40 s, the body scan 30, the heart leg 60. */
    val total: Int get() = if (isBodyScan) 30 else if (isBalance) 40 else 60

    data class ScanCopy(val status: String, val tint: Color, val headline: String, val help: String)

    /** The shared body-scan words when the phase maps onto one; the device-side phases keep
     *  the takeover's own copy. */
    val scanCopy: ScanCopy
        get() = bodyScanState?.let { ScanCopy(it.status, it.statusTint, it.headline, it.help) }
            ?: ScanCopy(statusLine, statusTint, headlineText, helpLine)

    private val bodyScanState: BodyScanState?
        get() = when (phase) {
            MeasurePhase.opening -> BodyScanState.Opening
            MeasurePhase.waiting -> BodyScanState.Waiting
            MeasurePhase.nudge -> BodyScanState.Nudge
            MeasurePhase.contact -> BodyScanState.Contact
            MeasurePhase.counting -> BodyScanState.Counting(fields)
            MeasurePhase.halfway -> BodyScanState.Halfway
            MeasurePhase.lost -> BodyScanState.Lost(lostGrace.roundToInt())
            MeasurePhase.computing -> BodyScanState.Computing
            else -> null
        }

    val hoopMode: HoopFigureMode
        get() = when (phase) {
            MeasurePhase.contact -> HoopFigureMode.contact
            MeasurePhase.nudge, MeasurePhase.notWearing -> HoopFigureMode.nudge
            else -> HoopFigureMode.waiting
        }

    val bodyFatValue: String
        get() {
            val v = resultReading?.bodyFatPercent ?: return Fmt.dash
            return if (v > 0) swiftFormat("%.1f", v) else Fmt.dash
        }

    val bodyFatDelta: String
        get() {
            val value = resultReading?.bodyFatPercent
            val prev = previousScan
            val previous = prev?.bodyFatPercent
            if (value == null || value <= 0 || prev == null || previous == null || previous <= 0) return L("FIRST READING")
            val delta = value - previous
            val signed = (if (delta < 0) "−" else "+") + swiftFormat("%.1f", abs(delta))
            val days = max(0L, ChronoUnit.DAYS.between(prev.at, Instant.now())).toInt()
            val age = when (days) { 0 -> L("TODAY"); 1 -> L("1 DAY AGO"); else -> L("%d DAYS AGO", days) }
            return L("%@ SINCE LAST SCAN · %@", signed, age)
        }

    val bodyFatDeltaTint: Color
        get() = if (previousScan?.bodyFatPercent == null) NB.white.copy(alpha = 0.42f) else NB.violet1.copy(alpha = 0.75f)

    val remainingFieldCount: Int
        get() {
            val r = resultReading ?: return 0
            return listOf(r.inputWeightKg, r.bmi, r.proteinPercent, r.subcutaneousFatPercent,
                r.skeletalMusclePercent, r.muscleRatePercent, r.waterKg, r.proteinKg)
                .filterNotNull().count { it > 0 }
        }

    fun openComposition() {
        val date = resultScanAt?.atZone(currentZone())?.toLocalDate()
        done()
        BandMain.scope.launch {
            delay(500)
            Router.open(Destination.Composition(date), EntryPoint.home)
        }
    }

    /** The eyebrow: what is being measured and how long it takes. */
    val eyebrow: String
        get() {
            if (isBodyScan && phase == MeasurePhase.result) return L("BODY SCAN · SAVED")
            return if (isBodyScan) L("BODY SCAN · 30S") else if (isBalance) L("BALANCE CHECK · 40S") else L("BATTERY CHECK · 60S")
        }

    val headlineText: String
        get() = when (phase) {
            // Opening borrows waiting's words: a sentence under an empty line reads as a
            // screen that failed to draw.
            MeasurePhase.opening, MeasurePhase.waiting -> L("Index finger on the side key.")
            MeasurePhase.nudge -> L("Still nothing on the key.")
            MeasurePhase.contact -> L("Got it. Hold still.")
            MeasurePhase.counting -> if (isBodyScan) L("Mapping you.") else if (isBalance) L("Listening to your rhythm.") else L("Reading you.")
            MeasurePhase.halfway -> L("Halfway.")
            MeasurePhase.lost -> L("Put it back.")
            MeasurePhase.computing -> L("Working it out.")
            MeasurePhase.result -> if (isBodyScan) L("Fourteen fields.") else if (isBalance) L("Rest and drive.") else L("Done.")
            MeasurePhase.failed -> L("That didn't take.")
            MeasurePhase.notWearing -> L("The band isn't on your wrist.")
            MeasurePhase.busy -> L("She's already measuring something.")
            MeasurePhase.dropped -> L("Lost the band.")
            MeasurePhase.noReading -> L("Couldn't get a clean read.")
        }

    /** What the field breathes at: this run's rate, or the wrist's last measured one. Both
     *  are measured; neither is invented; the line under it says which. */
    val balanceTempo: Int? get() = reading?.heartRate ?: LiveReadout.shared.hr

    val balanceSourceLine: String
        get() {
            reading?.heartRate?.let { return "$it BPM · FROM THIS READING" }
            LiveReadout.shared.hr?.let { return "$it BPM · YOUR LAST READING" }
            return if (balanceFieldVisible) "FINDING YOUR PULSE" else "WAITING FOR THE KEY"
        }

    /** The field runs while the band is being read, and only then. */
    val balanceFieldVisible: Boolean
        get() = when (phase) {
            MeasurePhase.contact, MeasurePhase.counting, MeasurePhase.halfway, MeasurePhase.lost,
            MeasurePhase.computing -> true
            else -> false
        }

    /** The number the band has settled so far, and a dash until it has one. ⚠️ Never a placeholder. */
    val firstNumber: String
        get() = if (isBodyScan) reading?.bodyFatPercent?.let { swiftFormat("%.1f", it) } ?: Fmt.dash
        else reading?.heartRate?.toString() ?: Fmt.dash

    val statusLine: String
        get() = when (phase) {
            MeasurePhase.opening -> ""
            MeasurePhase.waiting -> L("WAITING FOR YOUR FINGER")
            MeasurePhase.nudge -> L("NO CONTACT · %dS", 6)
            MeasurePhase.contact -> if (isBodyScan) L("CONTACT · CIRCUIT CLOSED") else L("CONTACT · PULSE LOCK")
            MeasurePhase.counting -> if (isBodyScan) L("%d / 14 FIELDS", fields) else L("MEASURING · KEEP STILL")
            MeasurePhase.halfway -> if (isBodyScan || isBalance) L("HALFWAY · KEEP THE FINGER THERE") else L("KEEP STILL · STRESS NEXT")
            MeasurePhase.lost -> L("PAUSED · %dS TO RESUME", lostGrace.roundToInt())
            MeasurePhase.computing -> if (isBodyScan) L("COMPUTING 14 FIELDS")
                else if (isBalance) L("WORKING OUT THE BALANCE") else L("MEASURING STRESS · HRV")
            // ⚠️ The balance check is not written to any trace table; this says what happened.
            MeasurePhase.result -> if (isBalance) L("ON THE PANEL") else L("SAVED")
            MeasurePhase.failed -> failure ?: L("NOT MEASURED")
            MeasurePhase.notWearing -> L("NOT WEARING · PUT IT BACK ON")
            MeasurePhase.busy -> L("MEASURING NOW · TRY IN A MOMENT")
            MeasurePhase.dropped -> L("DISCONNECTED · RECONNECTING")
            MeasurePhase.noReading -> L("NO READING · NOTHING KEPT")
        }

    val statusTint: Color
        get() = when (phase) {
            // E02 · the waiting line is lime: the screen saying it is ready, not a warning.
            MeasurePhase.waiting -> NB.lime1.copy(alpha = 0.85f)
            MeasurePhase.nudge, MeasurePhase.lost, MeasurePhase.notWearing -> NB.ember2
            MeasurePhase.failed -> NB.ember2
            MeasurePhase.contact, MeasurePhase.counting, MeasurePhase.halfway -> NB.lime1
            // 06 rule 07 · device-side states are 32 % grey, not amber and not red.
            MeasurePhase.busy, MeasurePhase.dropped, MeasurePhase.noReading -> NB.white.copy(alpha = 0.32f)
            else -> NB.white.copy(alpha = 0.40f)
        }

    val helpLine: String
        get() = when (phase) {
            MeasurePhase.opening -> ""
            MeasurePhase.waiting -> if (isBodyScan)
                L("Rest your hand on the table. Nothing to press. It takes about 30 seconds.")
                else L("Rest your hand on the table. Nothing to press.")
            MeasurePhase.nudge -> L("Skin, not a nail or a sleeve. Let it rest, don't press.")
            MeasurePhase.contact -> if (isBodyScan) L("A tiny current crosses your body. You won't feel it.")
                else if (isBalance) L("Keep the finger on the key. The field breathes with your pulse.")
                else L("Breathe normally. Talking is fine.")
            // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
            MeasurePhase.counting -> if (isBodyScan) L("Lift a finger and the scan starts over.")
                else if (isBalance) L("One breath of the field for every beat it reads.")
                else L("Heart rate from the band — the sweep follows that beat.")
            MeasurePhase.halfway -> if (isBodyScan) L("One steady contact makes one reading.")
                else if (isBalance) L("Halfway. Keep the finger where it is.")
                else L("Almost there. Stress and HRV come after the minute.")
            MeasurePhase.lost -> if (isBodyScan) L("Your finger came off the key. This one has to start over.")
                else L("Your finger came off the key.")
            MeasurePhase.computing -> if (isBodyScan || isBalance) L("You can lift your finger now.")
                else L("Stress on the band now. HRV if this firmware has it.")
            MeasurePhase.result -> L("Folding it back onto the panel.")
            MeasurePhase.notWearing -> L("Not a failure — it slipped or came off. Put it back on and the count continues.")
            MeasurePhase.busy -> L("One measurement at a time. It frees itself when the other one ends.")
            MeasurePhase.dropped -> L("Nothing half-done is kept. Reconnecting — then put your finger back on.")
            MeasurePhase.noReading -> L("This one didn't read cleanly. Nothing invented, nothing stored.")
            MeasurePhase.failed -> L("Close this and try again when you are ready.")
        }

    private val terminal: Boolean
        get() = phase == MeasurePhase.failed || phase == MeasurePhase.busy || phase == MeasurePhase.dropped ||
            phase == MeasurePhase.noReading || phase == MeasurePhase.notWearing

    // MARK: choreography

    /** ⚠️ Closing used to call `done()` and nothing else — the test kept running after the
     *  screen was gone, and the next command came back DEVICE_BUSY. */
    fun cancelMeasurement() {
        BandMeasurementLifetimeShared.instance.cancel(measurementID)
        run?.cancel()
        run = null
    }

    fun leave() {
        if (isBodyScan && phase != MeasurePhase.result) {
            val reason = phase.name.uppercase()
            BandMain.scope.launch { Analytics.track("SCAN_ABORT", mapOf("REASON" to reason)) }
        }
        cancelMeasurement()
        done()
    }

    /** DEBUG · 06 edges on the mock band, which never fails on its own. */
    private fun applyDebugPhase(forced: MeasurePhase) {
        grown = true
        phase = forced
        when (forced) {
            MeasurePhase.counting -> {
                remaining = if (isBalance) 28 else if (isBodyScan) 22 else 42
                reading = PartialReading(heartRate = 72); studyProgress = 0.32; fields = 4
            }
            MeasurePhase.halfway -> {
                remaining = if (isBalance) 16 else if (isBodyScan) 12 else 26
                reading = PartialReading(heartRate = 74); studyProgress = 0.62; fields = 8
            }
            MeasurePhase.computing -> {
                remaining = 0; reading = PartialReading(heartRate = 68); studyProgress = 1.0; fields = 14
            }
            MeasurePhase.result -> {
                remaining = 0; reading = PartialReading(heartRate = 68); studyProgress = 1.0; fields = 14
                if (isBodyScan) {
                    val now = Instant.now()
                    resultReading = BodyCompositionReading(
                        bodyFatPercent = 23.5, fatMassKg = 17.4, leanMassKg = 55.6, muscleKg = 52.1,
                        boneKg = 2.8, bodyWaterPercent = 56.2, proteinPercent = 18.4,
                        subcutaneousFatPercent = 15.2, skeletalMusclePercent = 41.8, bmrKcal = 1_640,
                        bmi = 22.7, inputWeightKg = 73.0, muscleRatePercent = 71.4, waterKg = 41.0, proteinKg = 13.4)
                    reading = PartialReading(heartRate = 68, bodyFatPercent = 23.5)
                    previousScan = CompositionScan(id = UUID.randomUUID(), at = now.minusSeconds(2 * 24 * 60 * 60),
                        bodyFatPercent = 24.1, fatMassKg = 18.0, leanMassKg = 55.2, bmrKcal = 1_625.0,
                        inputWeightKg = 73.2, muscleMassKg = 51.9, bodyWaterPercent = 55.8, boneMassKg = 2.8,
                        proteinPercent = 18.2)
                    resultScanAt = now
                }
            }
            MeasurePhase.lost -> {
                remaining = if (isBodyScan) 18 else 37
                lostGrace = 2.1
                reading = PartialReading(heartRate = 71, bodyFatPercent = if (isBodyScan) 23.8 else null)
                if (isBodyScan) fields = 5
            }
            MeasurePhase.failed -> failure = L("No reading this time.")
            MeasurePhase.nudge -> remaining = total
            else -> Unit
        }
    }

    /** The panel grows to full screen, then waits for a finger. Everything after that is
     *  driven by what the band actually reports — not by a timer pretending to be one. */
    fun open() {
        scanOpenedAt = Instant.now()
        scanStartedAt = null
        scanRestarts = 0
        resultReading = null
        previousScan = null
        resultScanAt = null
        resultHeroVisible = false
        remaining = total
        bandClock = false
        reading = null
        hrSamples = emptyList()
        grown = true
        // DEBUG · 06 edges on the mock band (`-e NB_DEBUG_EDGE <phase>`).
        val forced = when (DebugEdgeFlag.name) {
            "notwearing" -> MeasurePhase.notWearing; "busy" -> MeasurePhase.busy
            "dropped" -> MeasurePhase.dropped; "noreading" -> MeasurePhase.noReading
            "opening" -> MeasurePhase.opening; "waiting" -> MeasurePhase.waiting
            "contact" -> MeasurePhase.contact; "nudge" -> MeasurePhase.nudge
            "counting" -> MeasurePhase.counting; "halfway" -> MeasurePhase.halfway
            "lost" -> MeasurePhase.lost; "computing" -> MeasurePhase.computing
            "result" -> MeasurePhase.result; "failed" -> MeasurePhase.failed
            else -> null
        }
        if (forced != null) { applyDebugPhase(forced); return }

        run = BandMeasurementLifetimeShared.instance.start(measurementID) {
            delay(460)
            phase = MeasurePhase.waiting
            coroutineScope {
                // The nudge lands at 5 s and the screen never times out on its own.
                val nudge = launch {
                    delay(5_000)
                    if (phase == MeasurePhase.waiting) phase = MeasurePhase.nudge
                }
                // ⚠️ THE BAND HAS ONE COMMAND CHANNEL. The panel's live readout is stood down
                // and awaited first, and the band gets the settling second.
                LiveReadout.shared.standDown {
                    delay((LiveReadout.Cadence.settle * 1000).toLong())
                    currentCoroutineContext().ensureActive()
                    measure(nudge)
                }
                nudge.cancel()
            }
        }
    }

    /** One measurement, from the first command to the stream ending. */
    private suspend fun measure(nudge: Job) {
        try {
            // ⚠️ The plus key can be pressed while the link is still coming back; restore first.
            if (Band.live.state != BandConnectionState.connected) Band.live.reconnectIfBound()
            currentCoroutineContext().ensureActive()
            when {
                isBodyScan -> {
                    // F2 §05 · the band's BIA multiplies by the weight we push down.
                    val p = data.profile
                    Band.live.syncPersonalInfo(PersonalInfo(
                        heightCm = p.heightCm.toInt(),
                        weightKg = (data.today.weightKg ?: 70.0).roundToInt(),
                        birthYear = p.birthdate.atZone(currentZone()).year,
                        sexIsMale = p.sexIsMale,
                        targetStep = p.stepGoal))
                    currentCoroutineContext().ensureActive()
                    Band.live.measureBodyComposition().collect { step ->
                        if (step !is MeasurementProgress.WaitingForContact) nudge.cancel()
                        apply(step)
                    }
                }
                isBalance -> measureBalanceCheck(nudge)
                else -> measureBatteryCheck(nudge)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: BandError.Busy) {
            // 06 edge 3 · DEVICE BUSY: one test at a time. Not amber — not the wearer's doing.
            nudge.cancel()
            phase = MeasurePhase.busy
        } catch (e: BandError.NotConnected) {
            nudge.cancel()
            dropped()
        } catch (e: Throwable) {
            nudge.cancel()
            failure = (e as? BandError)?.errorDescription ?: "BAND OFFLINE"
            phase = MeasurePhase.failed
        }
    }

    /** 06 · Balance Check: the band's own forty seconds. ⚠️ The count comes from the BAND's
     *  percentage, not the phone's clock. */
    private suspend fun measureBalanceCheck(nudge: Job) {
        Band.live.measurePulseStudy().collect { step ->
            when (step) {
                PulseStudyStep.WaitingForContact -> apply(MeasurementProgress.WaitingForContact)
                PulseStudyStep.Contact -> { nudge.cancel(); apply(MeasurementProgress.Contact) }
                is PulseStudyStep.Measuring -> {
                    nudge.cancel()
                    bandClock = true
                    // ⚠️ Only a rate the band actually reported.
                    step.heartRate?.let { reading = PartialReading(heartRate = it) }
                    studyProgress = min(1.0, step.percent / 100.0)
                    remaining = max(0, total - (total * step.percent / 100.0).roundToInt())
                    val next = if (step.percent >= 50) MeasurePhase.halfway else MeasurePhase.counting
                    if (phase != next) phase = next
                }
                PulseStudyStep.LostContact -> apply(MeasurementProgress.LostContact)
                is PulseStudyStep.Finished -> applyFinished(Finished.PulseStudyResult(step.study))
                is PulseStudyStep.Failed -> apply(MeasurementProgress.Failed(step.reason))
            }
        }
    }

    /** 06 · Battery Check: 60 s of PPG heart rate on the phone's clock, then stress (and HRV
     *  when the firmware answers) during computing. */
    private suspend fun measureBatteryCheck(nudge: Job) {
        val box = ArrayList<Int>()
        while (currentCoroutineContext().isActive) {
            when (collectHeartLeg(box, nudge)) {
                HeartLegOutcome.clockDone -> break
                HeartLegOutcome.restartAfterLift -> continue
                HeartLegOutcome.aborted -> return
            }
        }
        currentCoroutineContext().ensureActive()
        if (terminal) return
        nudge.cancel()
        // One settling spike is not a reading — need a short run of plausible beats.
        val hr = stableHeartRate(box)
        if (box.size < 3 || hr == null) {
            failure = "NO READING"
            phase = MeasurePhase.noReading
            return
        }
        reading = PartialReading(heartRate = hr)
        phase = MeasurePhase.computing

        delay((LiveReadout.Cadence.settle * 1000).toLong())
        var stress: Int? = null
        var hrv: Int? = null
        try {
            stress = Band.live.measureStress {}
        } catch (e: CancellationException) {
            throw e
        } catch (e: BandError.Unsupported) {
            stress = null
        } catch (e: Throwable) {
            BandLog.shared.record("batteryCheck.stress", e)
        }
        delay((LiveReadout.Cadence.settle * 1000).toLong())
        try {
            // Firmware often needs a long hold; twenty seconds is a try, not a promise.
            hrv = Band.live.measureHRV(20.0)
        } catch (e: CancellationException) {
            throw e
        } catch (e: BandError.Unsupported) {
            hrv = null
        } catch (e: Throwable) {
            BandLog.shared.record("batteryCheck.hrv", e)
        }
        currentCoroutineContext().ensureActive()
        applyFinished(Finished.HeartRate(hr, hrv, stress))
    }

    private enum class HeartLegOutcome { clockDone, restartAfterLift, aborted }

    /** One heart-rate stream, until the minute ends, the user lifts past grace, or the screen
     *  fails. The phone clock is the authority: an early SDK finish does not shorten the minute. */
    private suspend fun collectHeartLeg(box: MutableList<Int>, nudge: Job): HeartLegOutcome {
        var lifted = false
        coroutineScope {
            val winner = CompletableDeferred<Unit>()
            val stream = launch {
                try {
                    Band.live.measureHeartRate().collect { step ->
                        when (step) {
                            MeasurementProgress.WaitingForContact -> apply(step)
                            MeasurementProgress.Contact -> { nudge.cancel(); apply(step) }
                            is MeasurementProgress.Measuring -> {
                                nudge.cancel()
                                val hr = step.partial?.heartRate
                                if (hr != null && isPlausibleHeartRate(hr)) {
                                    box.add(hr)
                                    hrSamples = box.toList()
                                    reading = PartialReading(heartRate = stableHeartRate(hrSamples))
                                }
                                // Phone clock owns `remaining` — never rewrite it from a fraction.
                                val next = if (remaining <= total / 2) MeasurePhase.halfway else MeasurePhase.counting
                                if (phase != next) phase = next
                            }
                            MeasurementProgress.LostContact -> {
                                lifted = true
                                nudge.cancel()
                                apply(step)
                            }
                            is MeasurementProgress.Finished -> {
                                val r = step.result
                                if (r is MeasurementResult.HeartRate && isPlausibleHeartRate(r.hr)) box.add(r.hr)
                                // Stream over early — stay alive until the phone clock says so.
                                while (currentCoroutineContext().isActive && remaining > 0 &&
                                    (phase == MeasurePhase.counting || phase == MeasurePhase.halfway || phase == MeasurePhase.lost)) {
                                    delay(100)
                                }
                                throw StopCollecting()
                            }
                            is MeasurementProgress.Failed -> {
                                nudge.cancel()
                                apply(MeasurementProgress.Failed(step.reason))
                                throw StopCollecting()
                            }
                        }
                        if (remaining == 0 && (phase == MeasurePhase.counting || phase == MeasurePhase.halfway)) throw StopCollecting()
                    }
                    // Stream ended without a finish; in lift-off grace, wait it out.
                    while (currentCoroutineContext().isActive && phase == MeasurePhase.lost) delay(100)
                } catch (e: StopCollecting) {
                    // Done on purpose.
                } catch (e: CancellationException) {
                    // Countdown or leave() ended the heart stream on purpose.
                } catch (e: BandError.Busy) {
                    nudge.cancel(); phase = MeasurePhase.busy
                } catch (e: BandError.NotConnected) {
                    nudge.cancel(); dropped()
                } catch (e: Throwable) {
                    nudge.cancel()
                    failure = (e as? BandError)?.errorDescription ?: "BAND OFFLINE"
                    phase = MeasurePhase.failed
                } finally {
                    winner.complete(Unit)
                }
            }
            val deadline = launch {
                try {
                    while (currentCoroutineContext().isActive) {
                        if (remaining == 0 && (phase == MeasurePhase.counting || phase == MeasurePhase.halfway)) break
                        if (terminal) break
                        // After grace, tick puts us back on counting with a dead SDK test.
                        if (lifted && (phase == MeasurePhase.counting || phase == MeasurePhase.halfway) && remaining > 0) break
                        delay(100)
                    }
                } finally {
                    winner.complete(Unit)
                }
            }
            winner.await()
            stream.cancel(); deadline.cancel()
            stream.join(); deadline.join()
        }

        if (!currentCoroutineContext().isActive) return HeartLegOutcome.aborted
        if (terminal) return HeartLegOutcome.aborted
        if (remaining == 0) return HeartLegOutcome.clockDone
        while (currentCoroutineContext().isActive && phase == MeasurePhase.lost) delay(100)
        if (!currentCoroutineContext().isActive) return HeartLegOutcome.aborted
        if (lifted && (phase == MeasurePhase.counting || phase == MeasurePhase.halfway) && remaining > 0) {
            return HeartLegOutcome.restartAfterLift
        }
        // Stream died early but the clock still runs and no lift — wait out the minute.
        while (currentCoroutineContext().isActive && remaining > 0) {
            if (terminal) return HeartLegOutcome.aborted
            delay(100)
        }
        return if (currentCoroutineContext().isActive) HeartLegOutcome.clockDone else HeartLegOutcome.aborted
    }

    private class StopCollecting : CancellationException("stop collecting")

    /** Physiological gate for a live PPG sample. */
    private fun isPlausibleHeartRate(hr: Int): Boolean = hr in 40..180

    /** Median of the recent window so one 120 from a settling sensor cannot own the screen. */
    private fun stableHeartRate(samples: List<Int>): Int? {
        val window = samples.takeLast(7)
        if (window.isEmpty()) return null
        val sorted = window.sorted()
        return sorted[sorted.size / 2]
    }

    /** 06 edge 4 · LINK DROPPED. Nothing half-done is kept; the screen reconnects on its own and
     *  goes back to "put your finger on". */
    private suspend fun dropped() {
        phase = MeasurePhase.dropped
        Band.live.reconnectIfBound()
        if (Band.live.state == BandConnectionState.connected) BandMain.scope.launch { open() }
    }

    private sealed class Finished {
        data class HeartRate(val hr: Int, val hrv: Int?, val stress: Int?) : Finished()
        data class PulseStudyResult(val study: PulseStudy) : Finished()
        data class BodyComposition(val reading: BodyCompositionReading) : Finished()
    }

    private fun apply(step: MeasurementProgress) {
        when (step) {
            MeasurementProgress.WaitingForContact -> if (phase == MeasurePhase.opening) phase = MeasurePhase.waiting
            MeasurementProgress.Contact -> {
                // The only haptic in the flow, fired on the first state that comes back.
                Haptics.impact(ImpactStyle.Medium)
                if (isBodyScan && scanStartedAt == null) {
                    scanStartedAt = Instant.now()
                    BandMain.scope.launch { Analytics.track("SCAN_START", emptyMap()) }
                }
                // After a lift-off restart the stream yields contact again; keep the count.
                if (phase != MeasurePhase.counting && phase != MeasurePhase.halfway) phase = MeasurePhase.contact
                lostGrace = 3.0
            }
            is MeasurementProgress.Measuring -> {
                reading = step.partial
                // Body scan: the band's own seconds (or its fraction). Battery Check never
                // enters here — its path owns `remaining` on the phone clock.
                if (isBodyScan) {
                    val left = step.secondsLeft
                    if (left != null) { bandClock = true; remaining = left }
                    else remaining = max(0, total - (total * step.fraction).roundToInt())
                    fields = min(14, (14 * step.fraction).toInt())
                }
                val half = if (isBodyScan) step.fraction >= 0.5 else remaining <= total / 2
                val next = if (half) MeasurePhase.halfway else MeasurePhase.counting
                if (phase != next) phase = next
            }
            MeasurementProgress.LostContact -> {
                if (isBodyScan && phase != MeasurePhase.lost) scanRestarts += 1
                phase = MeasurePhase.lost
            }
            is MeasurementProgress.Finished -> when (val r = step.result) {
                is MeasurementResult.HeartRate -> applyFinished(Finished.HeartRate(r.hr, r.hrv, r.stress))
                is MeasurementResult.PulseStudyResult -> applyFinished(Finished.PulseStudyResult(r.study))
                is MeasurementResult.BodyComposition -> applyFinished(Finished.BodyComposition(r.reading))
            }
            is MeasurementProgress.Failed -> {
                // 06 edges 1 / 5 · the SDK's own words decide.
                val reason = step.reason
                if (reason.lowercase().contains("wear") || reason.lowercase().contains("worn")) {
                    phase = MeasurePhase.notWearing
                } else if (reason == "BAND OFFLINE") {
                    BandMain.scope.launch { dropped() }
                } else {
                    failure = reason
                    phase = MeasurePhase.noReading
                }
            }
        }
    }

    private fun applyFinished(result: Finished) {
        if (isBodyScan && result is Finished.BodyComposition) {
            val finishedAt = Instant.now()
            previousScan = data.compositionScans.filter { it.at < finishedAt }.maxByOrNull { it.at }
            resultReading = result.reading
        }
        // 06 rule 09 · store, then the result folds back onto the panel as one widget —
        // built before the store so the sentence can say what moved.
        val widget = resultWidget(result)
        store(result)
        Router.measuredWidget = widget.toPanelWidget()
        if (isBodyScan) {
            resultScanAt = data.compositionScans.firstOrNull()?.at
            phase = MeasurePhase.computing
            run = BandMain.scope.launch {
                delay(650)
                phase = MeasurePhase.result
                val elapsed = ChronoUnit.MILLIS.between(scanOpenedAt, Instant.now())
                Analytics.track("SCAN_DONE", mapOf("MS" to elapsed, "RESTARTS" to scanRestarts))
            }
            return
        }
        // Battery Check already spent computing on the real stress/HRV legs.
        if (phase != MeasurePhase.computing) phase = MeasurePhase.computing
        // Held on `run` so leave() cancels the fold-back.
        run = BandMain.scope.launch {
            delay(600)
            phase = MeasurePhase.result
            delay(500)
            done()
        }
    }

    /** The phone's clock counts only when the band has no clock of its own to report. */
    fun tick() {
        when (phase) {
            MeasurePhase.counting, MeasurePhase.halfway -> if (!bandClock && remaining > 0) remaining -= 1
            MeasurePhase.lost -> {
                lostGrace -= 1
                // Three seconds of grace on a battery check; a body scan has no resume at all.
                if (lostGrace <= 0) {
                    if (isBodyScan) {
                        remaining = total
                        phase = MeasurePhase.waiting
                    } else {
                        phase = MeasurePhase.counting
                    }
                    lostGrace = 3.0
                }
            }
            else -> Unit
        }
    }

    /** 06 · 16 / 20 · the result is not a report page: it is the panel's own widget. */
    private fun resultWidget(result: Finished): PanelWidgetSpec = when (result) {
        is Finished.HeartRate -> {
            val bb = data.bodyBatteryNow ?: data.today.bbWake ?: 0
            val yesterday = data.history.lastOrNull { it.day < data.today.day }?.bbWake
            val hrv = result.hrv; val stress = result.stress
            PanelWidgetSpec(
                type = PanelWidgetSpec.Type.wave, title = MetricNames.bodyBattery, tag = PanelWidgetSpec.Tag.recover,
                sentence = if (bb < 60) L("You're still carrying yesterday. Keep it easy today.")
                    else L("Steady enough. Today can take the session."),
                footer = L("HR %d · HRV %@ · STRESS %@", result.hr,
                    hrv?.let { "$it MS" } ?: "——", stress?.let { "$it / 100" } ?: "——"),
                action = L("TAP FOR THE FULL READING"),
                data = PanelWidgetSpec.Data.Trace(ecgTrace(result.hr), 50.0),
                hero = "$bb", heroLarge = true,
                heroSub = yesterday?.let { L("READINESS · WAS %d YESTERDAY", it) } ?: MetricNames.bodyBattery,
                // 06 · 16 · lime, not the ECG warning red
                accentOverride = NB.lime1,
                replyPrompt = L("Just measured: HR %d, HRV %@ ms, stress %@", result.hr,
                    hrv?.toString() ?: "——", stress?.toString() ?: "——") +
                    (yesterday?.let { L(", readiness %d yesterday", it) } ?: "") +
                    L(". What should today look like?"),
            )
        }
        is Finished.PulseStudyResult -> {
            val study = result.study
            // ⚠️ Nothing here is drawn unless the band reported enough beats.
            val balance = AutonomicBalance(study.intervals)
            if (balance == null) {
                PanelWidgetSpec(
                    type = PanelWidgetSpec.Type.metric, title = L("BALANCE"), tag = null,
                    sentence = L("The band didn't send enough beats to read the balance. Nothing was made up to fill it."),
                    footer = study.heartRate?.let { L("HEART RATE %d BPM · %d INTERVALS", it, study.intervals.size) }
                        ?: L("NO READING · %d INTERVALS", study.intervals.size),
                    action = L("TRY IT AGAIN WHEN YOU'RE STILL"),
                    hero = Fmt.dash, accentOverride = NB.lime1)
            } else {
                val footer = listOf(
                    "${study.heartRate ?: balance.beatsPerMinute} BPM",
                    "SD1 ${balance.sd1.roundToInt()} MS",
                    "SD2 ${balance.sd2.roundToInt()} MS",
                    // ⚠️ Says which series it read.
                    if (study.source == PulseStudy.Source.intervals) L("%d BEATS", balance.points.size)
                    else L("%d SAMPLES · PER SECOND", balance.points.size),
                ).joinToString(" · ")
                PanelWidgetSpec(
                    type = PanelWidgetSpec.Type.metric, title = L("BALANCE"), tag = null,
                    sentence = balance.note, footer = "", action = L("TAP TO ASK ABOUT IT"),
                    accentOverride = NB.lime1,
                    balance = PanelWidgetSpec.BalanceAnswer(balance.headline, balance.note,
                        balance.parasympatheticShare, footer, balance.points),
                    replyPrompt = L("Just did a balance check: rest %d%%, drive %d%%, SD1 %d ms, SD2 %d ms. What does that suggest for today?",
                        balance.split.rest, balance.split.drive, balance.sd1.roundToInt(), balance.sd2.roundToInt()),
                )
            }
        }
        is Finished.BodyComposition -> {
            val r = result.reading
            val fatDown = data.today.fatKg?.let { r.fatMassKg < it } ?: false
            val leanHeld = data.today.leanKg?.let { abs(r.leanMassKg - it) < 0.3 } ?: true
            // 06 · 20 · the line under the hero is the last measured fat percent and its month,
            // read before this one is stored; the first scan ever says so instead.
            val prior = data.weighIns.firstOrNull { it.bodyFatPercent != null }
            val monthFormat = DateTimeFormatter.ofPattern(if (AppLanguage.isEnglish) "MMMM" else "M月",
                AppLanguage.locale.javaLocale)
            PanelWidgetSpec(
                type = PanelWidgetSpec.Type.metric, title = L("BODY COMPOSITION"), tag = null,
                sentence = if (fatDown && leanHeld) L("Fat down, muscle held. That is the version you wanted.")
                    else L("One reading, not a verdict. The trend is what counts."),
                footer = listOfNotNull(r.bmi?.let { swiftFormat("BMI %.1f", it) }, L("LEAN %.1f KG", r.leanMassKg),
                    r.boneKg?.let { L("BONE %.1f KG", it) }).joinToString(" · "),
                action = L("TAP FOR ALL 14 FIELDS"),
                hero = swiftFormat("%.1f%%", r.bodyFatPercent),
                targetOverride = Destination.Composition(null),
                accentOverride = NB.lime1,
                composition = PanelWidgetSpec.CompositionAnswer(
                    heroSub = prior?.bodyFatPercent?.let {
                        L("BODY FAT · %.1f%% IN %@", it, monthFormat.format(prior.date.atZone(currentZone())).uppercase())
                    } ?: L("BODY FAT · FIRST READING"),
                    fields = goalFields(r, data.profile.goal)),
            )
        }
    }

    /** 06 · 20 · four tiles, picked by the goal. Lime for composition, cyan for water and
     *  protein, amber for BMR. */
    private fun goalFields(r: BodyCompositionReading, goal: Goal): List<PanelWidgetSpec.CompositionAnswer.Field> {
        fun n(v: Double?): String = v?.let { swiftFormat("%.1f", it) } ?: Fmt.dash
        val lime = NB.lime1.copy(alpha = 0.68f)
        val cyan = NB.cyan1.copy(alpha = 0.78f)
        val ember = NB.ember1.copy(alpha = 0.78f)
        val bmr = PanelWidgetSpec.CompositionAnswer.Field(L("BMR ESTIMATE"), r.bmrKcal?.toString() ?: Fmt.dash, ember)
        fun f(label: String, value: String, tint: Color) = PanelWidgetSpec.CompositionAnswer.Field(label, value, tint)
        return when (goal) {
            Goal.cut -> listOf(f(L("FAT"), n(r.fatMassKg), lime), f(L("MUSCLE"), n(r.muscleKg), lime),
                f(L("WATER"), n(r.bodyWaterPercent), cyan), bmr)
            Goal.bulk -> listOf(f(L("MUSCLE"), n(r.muscleKg), lime), f(L("LEAN"), n(r.leanMassKg), lime),
                f(L("PROTEIN"), n(r.proteinPercent), cyan), bmr)
            Goal.recomp -> listOf(f(L("MUSCLE"), n(r.muscleKg), lime), f(L("WATER"), n(r.bodyWaterPercent), cyan),
                f(L("PROTEIN"), n(r.proteinPercent), cyan), bmr)
        }
    }

    /** A trace shaped by the measured rate: one PQRST every 60/hr seconds at 50 Hz, four
     *  seconds of it. Drawn from the number, not the ECG channel. */
    private fun ecgTrace(hr: Int, seconds: Double = 4.0, hz: Double = 50.0): List<Double> {
        if (!Band.allowsSeed) return emptyList()
        val period = 60.0 / max(hr, 30)
        return (0 until (seconds * hz).toInt()).map { i ->
            val t = i / hz
            EcgMonitor.pqrst((t % period) / period)
        }
    }

    private fun store(result: Finished) {
        when (result) {
            is Finished.HeartRate -> {
                // ⚠️ Do not copy bbWake into bodyBattery — the check does not rewrite the reserve.
                reading = PartialReading(heartRate = result.hr)
            }
            is Finished.PulseStudyResult -> {
                val study = result.study
                study.heartRate?.let { reading = PartialReading(heartRate = it) }
                // ADR 0010 · 摘要行落库。逐拍序列一个字都不写——那是心律波形，产品不呈现也不解读。
                val balance = AutonomicBalance(study.intervals) ?: return
                val at = Instant.now()
                val lead = when (balance.lead) {
                    AutonomicBalance.Lead.parasympathetic -> MeasurementRecord.BalanceCheck.Lead.rest
                    AutonomicBalance.Lead.sympathetic -> MeasurementRecord.BalanceCheck.Lead.drive
                    AutonomicBalance.Lead.even -> MeasurementRecord.BalanceCheck.Lead.even
                }
                // 先进内存再上传：测完退回「我的」，那块 MEASUREMENTS 第一行立刻就是它。
                data.measurements = listOf(MeasurementRecord(UUID.randomUUID(), at, MeasurementRecord.BalanceCheck(
                    lead = lead, restShare = balance.split.rest,
                    sd1Ms = balance.sd1, sd2Ms = balance.sd2, sdnnMs = balance.sdnn,
                    heartRate = study.heartRate ?: balance.beatsPerMinute,
                    beatCount = balance.points.size + 1))) + data.measurements
                BandMain.scope.launch {
                    Repository.recordBalanceCheck(
                        lead = when (balance.lead) {
                            AutonomicBalance.Lead.parasympathetic -> BalanceCheckQueue.Lead.parasympathetic
                            AutonomicBalance.Lead.sympathetic -> BalanceCheckQueue.Lead.sympathetic
                            AutonomicBalance.Lead.even -> BalanceCheckQueue.Lead.even
                        },
                        restShare = balance.split.rest, sd1 = balance.sd1, sd2 = balance.sd2, sdnn = balance.sdnn,
                        beatsPerMinute = balance.beatsPerMinute, pointCount = balance.points.size,
                        heartRate = study.heartRate, at = at)
                }
            }
            is Finished.BodyComposition -> {
                val r = result.reading
                // F0 rule 09 · a band BIA reading is MEASURED and re-anchors the EMA.
                data.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = r.inputWeightKg,
                    bodyFatPercent = r.bodyFatPercent, source = MeasurementSource.measured, origin = WeighIn.Origin.band))
                data.today = data.today.copy().also {
                    it.fatKg = r.fatMassKg
                    it.leanKg = r.leanMassKg
                    it.fatSource = MeasurementSource.measured
                    it.scans7d += 1
                }
                data.bodyFatPercent = r.bodyFatPercent
                // ADR 0010 · 同一次扫描也立刻进测量记录。
                data.rememberBodyScan(MeasurementRecord(UUID.randomUUID(), Instant.now(), MeasurementRecord.BodyScan(
                    bodyFatPercent = r.bodyFatPercent, fatMassKg = r.fatMassKg, leanMassKg = r.leanMassKg,
                    bmrKcal = r.bmrKcal, inputWeightKg = r.inputWeightKg, muscleMassKg = r.muscleKg,
                    bodyWaterPercent = r.bodyWaterPercent, boneMassKg = r.boneKg, proteinPercent = r.proteinPercent)))
                // The row goes up now; a scan that only lived in memory would be replaced by the seed.
                BandMain.scope.launch { Repository.recordBodyComposition(r) }
            }
        }
    }
}

private fun positive(value: Double?, decimals: Int = 1): String {
    if (value == null || value <= 0) return Fmt.dash
    return swiftFormat("%.${decimals}f", value)
}

// MARK: the monitor

/**
 * A monitor, not a medical ECG. The sweep is written left to right at 200 Hz from a running
 * beat phase that advances at the band's own PPG rate: until the first value lands the sweep is
 * flat — a beating wave with nothing being read is a picture of a measurement not happening.
 */
@Composable
fun LiveECG(bpm: Int?, modifier: Modifier = Modifier, tint: Color = NB.lime1, amplitude: Double = 1.0) {
    val reduceMotion = rememberReduceMotion()
    val monitor = remember { EcgMonitor() }
    var frameNanos by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) { while (true) withFrameNanos { frameNanos = System.nanoTime() } }
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val now = frameNanos
            monitor.advance(now, bpm, amplitude, reduceMotion)
            val d = density
            val w = size.width
            val h = size.height
            val mid = h / 2
            val n = monitor.samples.size
            val gain = mid * 0.78f

            // ECG paper, in the house dot-matrix: a 1 mm grid at 6 % white.
            var gy = 4 * d
            while (gy < h) {
                var gx = 4 * d
                while (gx < w) {
                    drawCircle(NB.white.copy(alpha = 0.06f), radius = 0.6f * d, center = Offset(gx, gy))
                    gx += 8 * d
                }
                gy += 8 * d
            }

            // The sweep: every column holds the sample the head wrote there last. The gap ahead
            // of the head is what a monitor erases before it writes.
            val gap = (n * 0.07).toInt()
            val trace = Path()
            var pen = false
            var x = 0f
            while (x <= w) {
                val idx = min(n - 1, (x / w * n).toInt())
                val ahead = (idx - monitor.head + n) % n
                if (ahead in 1..gap) { pen = false; x += d; continue }
                val y = mid - monitor.samples[idx].toFloat() * gain
                if (pen) trace.lineTo(x, y) else { trace.moveTo(x, y); pen = true }
                x += d
            }
            drawPath(trace, tint, style = Stroke(width = 1.8f * d, cap = StrokeCap.Round, join = StrokeJoin.Round))

            // The head: white core and lime glow, the same one that leads the body scan.
            if (!reduceMotion) {
                val hx = monitor.head.toFloat() / n * w
                val hy = mid - monitor.samples[(monitor.head - 1 + n) % n].toFloat() * gain
                val r = (9 + 5 * monitor.flash).toFloat() * d
                drawCircle(Brush.radialGradient(listOf(tint.copy(alpha = 0.55f), tint.copy(alpha = 0f)),
                    center = Offset(hx, hy), radius = r), radius = r, center = Offset(hx, hy))
                drawCircle(NB.white, radius = 1.6f * d, center = Offset(hx, hy))
            }
        }
        // The readout: the number the rhythm is drawn from.
        if (bpm != null) {
            Row(Modifier.align(Alignment.TopEnd).padding(end = 4.dp, top = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                MText("$bpm", NBFont.dot(700, 16f).tracking(0.08f), tint, Modifier.alignByBaseline())
                MText(L("BPM"), NBFont.dot(500, 9f).tracking(0.2f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline())
            }
        }
    }
}

/** The paper the trace is written on: a ring of samples, one per column of the sweep. */
internal class EcgMonitor {
    val samples = DoubleArray((HZ * SECONDS).toInt())
    var head = 0
    private var phase = 0.0
    private var last = 0L
    /** 1 at the R spike, fading over ~120 ms: the head swells on every beat. */
    var flash = 0.0
        private set

    fun advance(now: Long, bpm: Int?, amplitude: Double, still: Boolean) {
        // This PQRST shape is synthetic, not samples from the ECG channel.
        if (!Band.allowsSeed || now == 0L) return
        if (last == 0L) {
            last = now
            if (still && bpm != null) prefill(bpm, amplitude)
            return
        }
        if (still) return
        val n = min(HZ.toInt(), ((now - last) / 1e9 * HZ).toInt())
        if (n <= 0) return
        last += (n / HZ * 1e9).toLong()
        val step = (bpm?.let { it / 60.0 } ?: 0.0) / HZ
        repeat(n) {
            if (bpm != null) {
                phase += step
                if (phase >= 1) { phase -= 1; flash = 1.0 }
            }
            val v = if (bpm == null) 0.0 else pqrst(phase) * amplitude
            samples[head] = v + Random.nextDouble(-0.012, 0.012)
            head = (head + 1) % samples.size
            flash *= 0.96
        }
    }

    /** Reduce Motion: the whole paper written once, at the measured rate, and left still. */
    private fun prefill(bpm: Int, amplitude: Double) {
        val step = bpm / 60.0 / HZ
        for (i in samples.indices) {
            phase += step
            if (phase >= 1) phase -= 1
            samples[i] = pqrst(phase) * amplitude
        }
        head = 0
    }

    companion object {
        const val HZ = 200.0
        const val SECONDS = 4.0

        /** One PQRST complex over a beat phase in [0, 1): the shape the panel widget draws too. */
        fun pqrst(ph: Double): Double {
            fun bump(c: Double, w: Double, a: Double): Double = a * exp(-((ph - c) / w).pow(2))
            return bump(0.18, 0.05, 0.12) - bump(0.30, 0.012, 0.18) + bump(0.33, 0.015, 1.0) -
                bump(0.37, 0.014, 0.28) + bump(0.60, 0.06, 0.22)
        }
    }
}

// MARK: type

/**
 * One line of the measure / sport screens' type. `shadow` is 06's OverFieldShadow: a tight dark
 * halo that travels with the glyphs, so type can sit on the field without a bar behind it.
 * `minScale` is SwiftUI's `minimumScaleFactor` (single-line only).
 */
@Composable
internal fun MText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
    minScale: Float = 1f,
    shadow: Boolean = false,
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    val sized = if (scale < 1f) style.copy(fontSize = style.fontSize * scale) else style
    val density = LocalDensity.current
    val shrinkable = minScale < 1f
    val lines = if (shrinkable) 1 else maxLines
    if (!shadow) {
        Text(text, modifier, color = color, style = sized, textAlign = align, maxLines = lines,
            softWrap = !shrinkable && maxLines > 1, overflow = if (shrinkable) TextOverflow.Clip else TextOverflow.Clip,
            onTextLayout = { r ->
                if (shrinkable && (r.didOverflowWidth || r.hasVisualOverflow) && scale > minScale) {
                    scale = max(minScale, scale * 0.92f)
                }
            })
        return
    }
    val wide = with(density) { 14.dp.toPx() }
    val tight = with(density) { 5.dp.toPx() }
    val fill = if (align != null) Modifier.fillMaxWidth() else Modifier
    Box(modifier, contentAlignment = Alignment.Center) {
        // The wide halo alone: transparent glyphs carrying only their 75 % shadow.
        Text(text, fill, color = Color.Transparent, textAlign = align, maxLines = lines,
            style = sized.copy(shadow = Shadow(NB.panelInk.copy(alpha = 0.75f), Offset.Zero, wide)))
        Text(text, fill, color = color, textAlign = align, maxLines = lines,
            style = sized.copy(shadow = Shadow(NB.panelInk.copy(alpha = 0.95f), Offset.Zero, tight)),
            onTextLayout = { r ->
                if (shrinkable && (r.didOverflowWidth || r.hasVisualOverflow) && scale > minScale) {
                    scale = max(minScale, scale * 0.92f)
                }
            })
    }
}
