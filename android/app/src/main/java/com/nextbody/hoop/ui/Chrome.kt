package com.nextbody.hoop.ui

import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Design geometry: the boards are 390 × 844 with a 358 content column and draw their own
 * 62pt status bar and 19pt home-indicator block. On device the system draws both, at whatever
 * height the phone has, so the page reads the real safe area and never reserves a
 * board-sized block.
 */
object Chrome {
    /** The board's own status-bar block. Only for converting a board Y into a safe-area Y. */
    const val boardStatusBar = 62f
    /** The board's own home-indicator block. A real phone is ~34; Home drops the lip into the extra. */
    const val boardHomeIndicator = 19f
    /** The device's status bar — what a page that draws under it must leave clear. */
    val statusBarBlock: Dp get() = ScreenMetrics.safeTop
    /** The device's home-indicator inset. */
    val homeIndicatorBlock: Dp get() = ScreenMetrics.safeBottom
    /** The gate screens put their header line at y = 66. Inside the safe area that is 19. */
    val gateTopInset: Dp = 19.dp

    /**
     * A Y written on the board (from the board's top edge) as a Y measured from the top of
     * the safe area. On a phone whose safe area is shorter than the board's 763 column the
     * column is compressed to fit, so nothing placed near the bottom falls off the screen.
     */
    fun boardY(y: Float): Dp {
        val boardSafe = 844f - boardStatusBar - boardHomeIndicator
        val deviceSafe = (ScreenMetrics.height - ScreenMetrics.safeTop - ScreenMetrics.safeBottom).value
        return ((y - boardStatusBar + gateTopInset.value) * min(1f, deviceSafe / boardSafe)).dp
    }
}

/** SwiftUI's `.spring(response:dampingFraction:)` as a Compose spring (mass 1). */
fun <T> swiftSpring(response: Float, dampingFraction: Float): SpringSpec<T> {
    val w = (2 * PI / response).toFloat()
    return spring(dampingRatio = dampingFraction, stiffness = w * w)
}

/** SwiftUI's `.easeOut` / `.easeInOut` curves. */
val SwiftEaseOut = androidx.compose.animation.core.CubicBezierEasing(0f, 0f, 0.58f, 1f)
val SwiftEaseInOut = androidx.compose.animation.core.CubicBezierEasing(0.42f, 0f, 0.58f, 1f)

/** Reduce Motion: Android's equivalent is "Remove animations" (animator scale 0). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) { SystemMotion.reduceMotion(context) }
}

/** Seconds since an arbitrary origin, ticking every frame while [running]. */
@Composable
internal fun rememberFrameClock(running: Boolean): Double {
    val t by produceState(0.0, running) {
        if (!running) return@produceState
        while (true) withFrameNanos { value = it / 1_000_000_000.0 }
    }
    return t
}

/** One-line text with the design's styles; Compose's `Text` with SwiftUI defaults. */
@Composable
internal fun ChromeText(
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
        overflow = TextOverflow.Ellipsis,
        softWrap = maxLines > 1,
        textAlign = align,
    )
}

@Composable
fun HomeIndicator(modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(top = 8.dp, bottom = 6.dp)
            .size(134.dp, 5.dp)
            .background(NB.white.copy(alpha = 0.35f), CircleShape),
    )
}

/** The one page background. #0B0B0D, edge to edge. */
fun Modifier.carbonPage(): Modifier = this.background(NB.carbon)

/** Same as [carbonPage], as a container. */
@Composable
fun CarbonBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(NB.carbon), content = content)
}

/** NEXTBODY · lime pip. Inter Tight 800 @24, tracking −0.01em. */
@Composable
fun Wordmark(size: Float = 24f, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        ChromeText(L("NEXTBODY"), NBFont.brand(800, size).tracking(-0.01f), NB.text1)
        Box(Modifier.size(6.dp).background(NB.lime1, RoundedCornerShape(1.5.dp)))
    }
}

// shared: mirrors BandBattery.ChargeState (Services/Band/BandService.swift).
enum class BandChargeState { Unplugged, Charging, Full, Unknown }

// shared: mirrors WearRun.Flame (Services/Band/WearRun.swift). ADR 0010.
sealed interface WearFlame {
    data class Live(val days: Int) : WearFlame
    data object Amber : WearFlame
    data object Gray : WearFlame
}

/** `Fmt.dash` — the empty reading. */
internal const val DASH = "——"

/** The unlit gray shared by the battery shell and the gray flame. */
private val unlitGray = hex(0x3A3A44)

/**
 * The band's own battery, as the header draws it — a 12×7 dot-matrix cell scaled to
 * 22×13, plus a Doto percentage. Charging adds a pixel bolt and a live fill pulse.
 * [percent] null = the band has not said: the shell is drawn empty and the label is a dash.
 */
@Composable
fun BandBatteryPip(percent: Int?, chargeState: BandChargeState = BandChargeState.Unknown, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val isCharging = chargeState == BandChargeState.Charging
    val showBolt = chargeState == BandChargeState.Charging || chargeState == BandChargeState.Full
    val animate = isCharging && !reduceMotion
    val time = rememberFrameClock(animate)

    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(22.dp, 13.dp)) {
            val pulse = if (animate) ((sin(time * 2.6) + 1) / 2).toFloat() else 1f
            val s = size.width / 12f // viewBox is 12 × 7
            fun rect(x: Float, y: Float, w: Float, h: Float, c: Color) =
                drawRect(c, Offset(x * s, y * s), Size(w * s, h * s))
            val shell = if (showBolt) NB.lime3 else unlitGray
            rect(0f, 0f, 10f, 1f, shell)
            rect(0f, 6f, 10f, 1f, shell)
            rect(0f, 1f, 1f, 5f, shell)
            rect(9f, 1f, 1f, 5f, shell)
            rect(10f, 2f, 2f, 3f, shell)
            val fillWidth = percent?.let { 8f * it / 100f } ?: 0f
            if (fillWidth > 0) {
                val fill = if (showBolt) NB.lime1.copy(alpha = 0.55f + 0.45f * pulse) else NB.lime2
                rect(1f, 1f, fillWidth, 5f, fill)
            }
            if (showBolt) {
                // Pixel lightning: a pixel over the fill is punched out; over empty interior
                // it stays lime so a low charge still reads as charging.
                for ((x, y) in BOLT) {
                    val overFill = x + 1f <= 1f + fillWidth
                    rect(x.toFloat(), y.toFloat(), 1f, 1f, if (overFill) NB.carbon else NB.lime1)
                }
            }
        }
        ChromeText(
            percent?.let { "$it%" } ?: DASH,
            NBFont.dot(700, 11f).tracking(0.06f),
            if (showBolt) NB.lime1 else NB.limePale,
        )
    }
}

private val BOLT = listOf(5 to 1, 4 to 2, 5 to 2, 3 to 3, 4 to 3, 5 to 3, 6 to 3, 5 to 4, 6 to 4, 5 to 5)

/**
 * 12 格粗段环 — the header's sync indicator. Twelve dot-matrix cells on a ring: lit cells
 * count the sync fraction, dim cells are what the pull has not read yet. The same progress
 * as the Device page's bar, drawn round — never a second estimate.
 */
@Composable
fun BandSyncRing(fraction: Double, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(16.dp)) {
        val s = size.width / 24f // viewBox is 24 × 24
        val lit = (min(1.0, max(0.0, fraction)) * 12).roundToInt()
        for (i in 0 until 12) {
            val a = i * PI / 6 // 12 o'clock, clockwise
            val x = (12 + 9 * sin(a)).toFloat()
            val y = (12 - 9 * cos(a)).toFloat()
            drawRect(if (i < lit) tint else NB.barTrack, Offset((x - 2.2f) * s, (y - 2.2f) * s), Size(4.4f * s, 4.4f * s))
        }
    }
}

/** `BandSyncProgress.tint`: cloud stages are blue, on-phone stages lime. */
fun bandSyncTint(toCloud: Boolean): Color = if (toCloud) NB.blue1 else NB.lime1

/**
 * The avatar. 36 in the home header, 44 on 11 · Profile, 26 where a board draws the smaller
 * one. It carries the initials of the name — an account with no name is YOU, never empty.
 * [ink]: 11C · the identity plate inks the letters lime; everywhere else they stay white.
 */
@Composable
fun Avatar(initials: String, size: Dp = 36.dp, ink: Color = NB.text1, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(size)
            .background(NB.smokeKey, CircleShape)
            .border(1.dp, NB.hairline, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        ChromeText(initials, NBFont.ui(600, size.value * 0.32f).tracking(0.06f), ink)
    }
}

/**
 * The only way into 11 · Profile. F1 · 「热区不小于 44×44」 — Compose already extends a
 * small pointer target to the minimum touch size without changing the row's own height.
 */
@Composable
fun AvatarButton(initials: String, size: Dp = 26.dp, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val label = L("Profile")
    Avatar(
        initials, size,
        modifier = modifier
            .hotZoneTap(onClick = onClick)
            .clearAndSetSemantics { contentDescription = label },
    )
}

private val dayFormatters = HashMap<Locale, SimpleDateFormat>()

/** One formatter per language for the process — building one costs milliseconds. */
private fun dayLine(): String {
    val locale = AppLanguage.locale.javaLocale
    val f = dayFormatters.getOrPut(locale) {
        SimpleDateFormat(if (AppLanguage.isEnglish) "EEE · d MMM" else "EEE · M月d日", locale)
    }
    return f.format(Date()).uppercase(locale)
}

/**
 * 04 · header row, laid out the way an iOS navigation bar is: 44 tall, the identity on the
 * left (avatar 36 + the day over the name), the band battery on the right. The whole left
 * block is the one way into 11 · Profile; the battery is the way into 12 · Device.
 *
 * [syncFraction] non-null shows the sync ring. It only exists while a pull is running —
 * a finished ring left sitting at 100% is not a state, it is clutter.
 */
@Composable
fun HomeHeader(
    name: String,
    initials: String,
    batteryPercent: Int?,
    flame: WearFlame,
    onProfile: () -> Unit,
    modifier: Modifier = Modifier,
    chargeState: BandChargeState = BandChargeState.Unknown,
    width: Dp = NB.Layout.contentWidth,
    syncFraction: Double? = null,
    syncTint: Color = NB.lime1,
    syncProgressLine: String = "",
    onDevice: () -> Unit = {},
) {
    val profileLabel = when (flame) {
        is WearFlame.Live -> L("Profile · %@ · %d-day wear run", name, flame.days)
        WearFlame.Amber -> L("Profile · %@ · wear run broken yesterday", name)
        WearFlame.Gray -> L("Profile · %@", name)
    }
    val pipLabel = run {
        val level = batteryPercent?.let { "Band · battery $it%" } ?: "Band · battery not read"
        when (chargeState) {
            BandChargeState.Charging -> "$level · charging"
            BandChargeState.Full -> "$level · charged"
            else -> level
        }
    }
    val syncLabel = L("Sync progress")

    Row(
        modifier.width(width).height(HomeHeaderHeight),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .widthIn(max = width - 110.dp)
                .height(HomeHeaderHeight)
                .hotZoneTap(pressedScale = 1f, onClick = onProfile)
                .clearAndSetSemantics { contentDescription = profileLabel },
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar(initials, 36.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                ChromeText(dayLine(), NBFont.dot(600, 10f).tracking(0.18f), NB.text3Prod)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    ChromeText(name, NBFont.brand(700, 20f).tracking(-0.01f), NB.text1, Modifier.weight(1f, fill = false))
                    WearFlameMark(flame)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        AnimatedVisibility(
            visible = syncFraction != null,
            enter = fadeIn(tween(200, easing = SwiftEaseInOut)),
            exit = fadeOut(tween(200, easing = SwiftEaseInOut)),
        ) {
            Box(
                Modifier.height(HomeHeaderHeight).clearAndSetSemantics {
                    contentDescription = syncLabel
                    stateDescription = syncProgressLine
                },
                contentAlignment = Alignment.Center,
            ) { BandSyncRing(syncFraction ?: 0.0, syncTint) }
        }
        Box(
            Modifier
                .height(HomeHeaderHeight)
                .hotZoneTap(pressedScale = 1f, onClick = onDevice)
                .clearAndSetSemantics { contentDescription = pipLabel }
                .padding(start = 12.dp),
            contentAlignment = Alignment.Center,
        ) { BandBatteryPip(batteryPercent, chargeState) }
    }
}

val HomeHeaderHeight: Dp = 44.dp

/**
 * ADR 0010 · the flame outline, drawn in a 26 × 34 box and scaled. Off the header's pixel
 * grid on purpose: a dot matrix this small reads as a blob, and the notch between the two
 * tongues is the only thing that separates a flame from a drop.
 */
private fun DrawScope.wearFlamePath(): Path {
    val sx = size.width / 26f
    val sy = size.height / 34f
    return Path().apply {
        moveTo(15f * sx, 0.6f * sy)
        cubicTo(16.5f * sx, 6.2f * sy, 19f * sx, 10.2f * sy, 21f * sx, 14.6f * sy)
        cubicTo(23.5f * sx, 20f * sy, 22f * sx, 27.6f * sy, 16.5f * sx, 30.7f * sy)
        cubicTo(11f * sx, 33.7f * sy, 4f * sx, 31f * sy, 2.4f * sx, 25f * sy)
        cubicTo(1f * sx, 19.8f * sy, 4f * sx, 16.4f * sy, 6.6f * sx, 13.4f * sy)
        cubicTo(7.6f * sx, 12.2f * sy, 8.2f * sx, 10.6f * sy, 8.4f * sx, 8.6f * sy)
        cubicTo(10f * sx, 11.7f * sy, 11.4f * sx, 13.1f * sy, 13.2f * sx, 14.1f * sy)
        cubicTo(12.6f * sx, 9.7f * sy, 13.2f * sx, 4.5f * sy, 15f * sx, 0.6f * sy)
        close()
    }
}

/**
 * ADR 0010 · one flame plus an optional count, to the right of the name. No placeholder
 * digit: the gray flame holds the slot — the number does not.
 */
@Composable
fun WearFlameMark(flame: WearFlame, modifier: Modifier = Modifier) {
    val tint = when (flame) {
        is WearFlame.Live -> NB.lime1
        WearFlame.Amber -> NB.caution2
        // The same unlit gray as the battery shell: two dead marks in one header are the same dead.
        WearFlame.Gray -> unlitGray
    }
    Row(
        modifier.clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Canvas(Modifier.size(14.dp, 18.dp)) { drawPath(wearFlamePath(), tint) }
        if (flame is WearFlame.Live) {
            ChromeText(flame.days.toString(), NBFont.dot(700, 11f).tracking(0.06f), tint)
        }
    }
}

// MARK: detail page chrome · shared by 08 · 09 · 10 · 11 · 12 · 13

/**
 * The edge drag's own geometry — how wide the grab strip is and how far or how fast a drag
 * has to travel before it commits to leaving the page.
 */
object DetailBack {
    val edgeWidth: Dp = 32.dp
    const val commitFraction = 0.4f
    /** dp per second */
    const val commitVelocity = 300f

    fun shouldPop(translation: Float, velocity: Float, width: Float): Boolean =
        translation > width * commitFraction || velocity > commitVelocity
}

/**
 * The page's own back control asks its edge-back host to play the slide instead of popping
 * straight away, so every exit takes the one slide.
 */
val LocalDetailBackSlide = staticCompositionLocalOf<(() -> Unit)?> { null }

/**
 * Every detail page is one scroll under a pinned header washed in the pillar's tint.
 * The header is a 52 bar — a glass back disc on the left, the page's name centred — with a
 * 36 context row under it whenever the page has something to say there: an eyebrow, a
 * headline, or a trailing figure. A tinted gradient falls from the top of the screen behind
 * everything; the header paints the same slice opaque so content scrolling under it
 * disappears cleanly, and a hairline fades in at its foot as the page moves.
 *
 * The page draws edge to edge (status bar included): it reads [ScreenMetrics.safeTop].
 * Content is centred; give children their own width (`NB.Layout.contentWidth`) as on iOS.
 *
 * @param headline the context row's headline when the page leads with something other than
 *   its name: 10's date, 09's closed day.
 * @param eyebrow an eyebrow of its own, left of the headline in the context row.
 * @param trailing the right end of the context row: 08's `2.1 TO GO`, 10's pager, 12's pill.
 * @param onBack typically `Router.back()`.
 */
@Composable
fun DetailScroll(
    glow: Color,
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    headline: String? = null,
    eyebrow: String? = null,
    scrollState: ScrollState = rememberScrollState(),
    trailing: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val barHeight = 52.dp
    val contextHeight = 36.dp
    // The context row exists only when something would print in it.
    val showsContextRow = eyebrow != null || (headline != null && headline != title) || trailing != null
    val headerHeight = barHeight + if (showsContextRow) contextHeight else 0.dp
    val safeTop = ScreenMetrics.safeTop
    val scrolled = rememberScrollOffset(scrollState)

    // The pillar wash the whole top of the page shares. The backdrop and the header ground
    // draw this same gradient anchored at the same screen top, so at rest the seam is invisible.
    val tint = remember(glow) {
        Brush.verticalGradient(
            0f to glow.copy(alpha = 0.22f),
            0.45f to glow.copy(alpha = 0.08f),
            1f to glow.copy(alpha = 0f),
        )
    }

    DetailEdgeBack(onBack, modifier) {
        Box(Modifier.fillMaxSize().background(NB.carbon)) {
            Box(Modifier.fillMaxWidth().height(460.dp).background(tint))

            Column(
                Modifier.fillMaxSize().verticalScroll(scrollState),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(safeTop + headerHeight + 6.dp))
                content()
                Spacer(Modifier.height(1.dp))
            }

            // The header's opaque ground: carbon plus the same tint slice the backdrop draws
            // behind it — status bar plus header tall, so the page slides under it unseen.
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(safeTop + headerHeight)
                    .clipToBounds()
                    .background(NB.carbon),
            ) {
                Box(Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top, unbounded = true).height(460.dp).background(tint))
            }

            // The pinned header: the bar, then the context row when the page has one.
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(top = safeTop)
                    .drawBehind {
                        val a = min(1f, scrolled.value.value / 24f)
                        if (a > 0f) drawRect(NB.hairline.copy(alpha = NB.hairline.alpha * a), Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
                    },
            ) {
                // The 52 bar: back disc on the left, title centred, right side empty.
                Box(Modifier.fillMaxWidth().height(barHeight)) {
                    ChromeText(
                        title, NBFont.brand(700, 16f).tracking(0.02f), NB.text1,
                        Modifier.fillMaxWidth().padding(horizontal = 68.dp).align(Alignment.Center),
                        align = TextAlign.Center,
                    )
                    DetailBackButton(
                        title, onBack,
                        Modifier.align(Alignment.CenterStart).padding(start = NB.Layout.gutter + 20.dp - 22.dp),
                    )
                }
                if (showsContextRow) {
                    // Oura's date-pager slot: eyebrow, headline, trailing, centred.
                    Row(
                        Modifier.fillMaxWidth().height(contextHeight),
                        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (eyebrow != null) ChromeText(eyebrow, NBFont.ui(500, 11f), NB.text3Prod)
                        if (headline != null && headline != title) ChromeText(headline, NBFont.ui(600, 15f), NB.text1)
                        trailing?.invoke(this)
                    }
                }
            }
        }
    }
}

/**
 * The back disc — a 40 glass circle holding the chevron inside a 44 hit area. It plays the
 * host's slide-out when there is one.
 */
@Composable
fun DetailBackButton(title: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val slide = LocalDetailBackSlide.current
    val label = L("Back")
    Box(
        modifier
            .size(44.dp)
            .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { slide?.invoke() ?: onBack() }
            .clearAndSetSemantics { contentDescription = label; stateDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(NB.white.copy(alpha = 0.08f), CircleShape)
                .border(1.dp, NB.white.copy(alpha = 0.14f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            BackChevron(height = 15.dp, line = 1.8.dp, color = NB.text1, modifier = Modifier.offset(x = (-1).dp))
        }
    }
}

/**
 * The page's scroll offset in dp, 0 at rest and positive once the page has moved up.
 * Chrome is fully collapsed at 52; beyond that its appearance is constant, so further
 * travel is discarded rather than recomposing readers. 12 · ME fades its own bar this way.
 */
@Composable
fun rememberScrollOffset(state: ScrollState, cap: Dp = 52.dp): androidx.compose.runtime.State<Dp> {
    val density = LocalDensity.current
    return remember(state, density, cap) {
        derivedStateOf { with(density) { min(cap.toPx(), max(0f, state.value.toFloat())).toDp() } }
    }
}

@Composable
fun rememberScrollOffset(state: LazyListState, cap: Dp = 52.dp): androidx.compose.runtime.State<Dp> {
    val density = LocalDensity.current
    return remember(state, density, cap) {
        derivedStateOf {
            with(density) {
                if (state.firstVisibleItemIndex > 0) cap
                else min(cap.toPx(), state.firstVisibleItemScrollOffset.toFloat()).toDp()
            }
        }
    }
}

/**
 * The page follows the finger off to the right and commits past 40% of the width or a
 * 300 dp/s fling. Android's own back (button, predictive gesture) drives the same slide;
 * the in-page left-edge strip covers 3-button navigation. Whatever the router composes under
 * this page shows through as it slides.
 */
@Composable
fun DetailEdgeBack(onBack: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val widthPx = with(density) { ScreenMetrics.width.toPx() }
    val x = remember { Animatable(0f) }
    var committing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val back by rememberUpdatedState(onBack)

    // The drag's commit and the ‹ key share this: slide the page off, then pop. Some back
    // actions change local content (Fuel's past day → today) rather than removing the page,
    // so a page still here afterwards is made ready for another drag.
    val slideOff: () -> Unit = remember(widthPx) {
        {
            if (!committing) {
                committing = true
                scope.launch {
                    x.animateTo(widthPx, swiftSpring(0.32f, 0.90f))
                    back()
                    delay(300)
                    x.snapTo(0f)
                    committing = false
                }
            }
        }
    }

    PredictiveBackHandler(enabled = !committing) { progress ->
        try {
            progress.collect { e -> x.snapTo(e.progress * widthPx * DetailBack.commitFraction) }
            slideOff()
        } catch (e: CancellationException) {
            scope.launch { x.animateTo(0f, swiftSpring(0.32f, 0.88f)) }
            throw e
        }
    }

    Box(
        modifier
            .fillMaxSize()
            .offset { IntOffset(x.value.roundToInt(), 0) }
            .pointerInput(widthPx) {
                val edge = DetailBack.edgeWidth.toPx()
                val slop = viewConfiguration.touchSlop
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (down.position.x > edge || committing) return@awaitEachGesture
                    val tracker = VelocityTracker()
                    tracker.addPointerInputChange(down)
                    // Wait for a rightward, mostly horizontal travel past the slop; anything
                    // else leaves the touch to the page (taps on the back disc included).
                    var engaged = false
                    while (true) {
                        val e = awaitPointerEvent(PointerEventPass.Initial)
                        val c = e.changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
                        tracker.addPointerInputChange(c)
                        val d = c.position - down.position
                        if (!c.pressed) {
                            if (engaged) finishEdge(d.x, tracker, density.density, widthPx, x, scope, slideOff)
                            return@awaitEachGesture
                        }
                        if (!engaged) {
                            if (abs(d.x) < slop && abs(d.y) < slop) continue
                            if (d.x <= 0 || abs(d.x) < abs(d.y)) return@awaitEachGesture
                            engaged = true
                        }
                        // A recognised edge drag owns the touch, including row/button gestures.
                        c.consume()
                        val dx = max(0f, d.x)
                        scope.launch { x.snapTo(dx) }
                    }
                }
            },
    ) {
        CompositionLocalProvider(LocalDetailBackSlide provides slideOff) { content() }
    }
}

private fun finishEdge(
    translation: Float,
    tracker: VelocityTracker,
    density: Float,
    widthPx: Float,
    x: Animatable<Float, *>,
    scope: kotlinx.coroutines.CoroutineScope,
    slideOff: () -> Unit,
) {
    val v = tracker.calculateVelocity().x / density
    if (DetailBack.shouldPop(translation / density, v, widthPx / density)) slideOff()
    else scope.launch { x.animateTo(0f, swiftSpring(0.32f, 0.88f)) }
}

/** The back chevron. The 8 × 13 mark the boards drew, scaled — 15 inside the glass back disc. */
@Composable
fun BackChevron(height: Dp = 13.dp, line: Dp = 1.6.dp, color: Color = NB.macroLabel, modifier: Modifier = Modifier) {
    val s = height / 13f
    Canvas(modifier.size(s * 8f, height)) {
        val k = s.toPx()
        val p = Path().apply {
            moveTo(7f * k, 1f * k)
            lineTo(1.5f * k, 6.5f * k)
            lineTo(7f * k, 12f * k)
        }
        drawPath(p, color, style = Stroke(width = line.toPx(), cap = StrokeCap.Square))
    }
}

/** The close mark. The only exit from a takeover. */
@Composable
fun CloseMark(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(36.dp)
            .background(NB.carbon4, CircleShape)
            .border(1.dp, NB.hairline, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(26.dp)) {
            val u = 1.dp.toPx()
            val st = 1.6.dp.toPx()
            drawLine(NB.iconInk, Offset(8 * u, 8 * u), Offset(18 * u, 18 * u), st, StrokeCap.Round)
            drawLine(NB.iconInk, Offset(18 * u, 8 * u), Offset(8 * u, 18 * u), st, StrokeCap.Round)
        }
    }
}

/**
 * The small mosaic exit: five square pixels per diagonal, printed directly onto the panel
 * with no surrounding key. Its caller supplies the invisible 44 hit target.
 */
@Composable
fun PixelCloseMark(modifier: Modifier = Modifier) {
    Canvas(modifier.size(19.dp).clearAndSetSemantics { }) {
        val pixel = 3.dp.toPx()
        val step = 4.dp.toPx()
        for ((row, column) in PIXEL_CLOSE) {
            drawRect(NB.iconInk, Offset(column * step, row * step), Size(pixel, pixel))
        }
    }
}

private val PIXEL_CLOSE = listOf(0 to 0, 0 to 4, 1 to 1, 1 to 3, 2 to 2, 3 to 1, 3 to 3, 4 to 0, 4 to 4)

/** A hairline rule. 1px, white 8%. [width] null fills the available width. */
@Composable
fun Hairline(width: Dp? = null, modifier: Modifier = Modifier) {
    Box(
        (if (width != null) modifier.width(width) else modifier.fillMaxWidth())
            .height(1.dp)
            .background(NB.hairline),
    )
}

/**
 * 05 · the dock is the only thing that moves when the keyboard comes up. Everything else on
 * the home screen stays exactly where it was. The IME inset, measured from the screen bottom.
 */
@Composable
fun keyboardHeight(): Dp {
    val density = LocalDensity.current
    return with(density) { WindowInsets.ime.getBottom(this).toDp() }
}

// MARK: card skins · shared by the detail pages (TrainingDetailView.swift on iOS)

/** The plain card fill: white 6% at radius 20. */
fun Modifier.cardSkin(): Modifier = this.background(NB.white.copy(alpha = 0.06f), RoundedCornerShape(20.dp))

/**
 * The card skin every section wears: a white-6% fill reaching 12 into the gutter, so the
 * card draws 4 from the screen edges while the layout width stays `contentWidth`.
 */
fun Modifier.lineSkin(top: Dp = 14.dp): Modifier = this
    .drawBehind {
        val bleed = NB.Layout.cardBleed.toPx()
        val r = 20.dp.toPx()
        drawRoundRect(
            NB.white.copy(alpha = 0.06f),
            topLeft = Offset(-bleed, 0f),
            size = Size(size.width + bleed * 2, size.height),
            cornerRadius = CornerRadius(r, r),
        )
    }
    .padding(vertical = max(top.value, 16f).dp)

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    ChromeText(
        text, NBFont.ui(600, 21f), NB.text1,
        modifier.padding(top = 14.dp).width(NB.Layout.contentWidth),
    )
}

/** A titled section card: title left, an optional trailing note right, then the content. */
@Composable
fun CardBlock(
    title: String,
    modifier: Modifier = Modifier,
    trailing: String? = null,
    trailingIsDot: Boolean = false,
    trailingTint: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier.width(NB.Layout.contentWidth).lineSkin(),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            ChromeText(title, NBFont.ui(500, 13f), NB.text2, Modifier.alignByBaseline().weight(1f))
            // 8 + 0 + 8, as SwiftUI spaces around the Spacer
            Spacer(Modifier.width(if (trailing != null) 16.dp else 8.dp))
            if (trailing != null) {
                ChromeText(
                    trailing,
                    if (trailingIsDot) NBFont.dot(700, 12f).tracking(0.04f) else NBFont.ui(500, 12f),
                    trailingTint ?: if (trailingIsDot) NB.macroValue else NB.text3Prod,
                    Modifier.alignByBaseline(),
                )
            }
        }
        content()
    }
}
