package com.nextbody.hoop.features.profile

import android.content.Context
import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.app.EntryPoint
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.CompositionAim
import com.nextbody.hoop.band.CompositionScan
import com.nextbody.hoop.band.CompositionWeekCell
import com.nextbody.hoop.band.CompositionWeekTone
import com.nextbody.hoop.band.CompositionWindowMath
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.localDate
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.ui.BackChevron
import com.nextbody.hoop.ui.DetailEdgeBack
import com.nextbody.hoop.ui.HapticsSetting
import com.nextbody.hoop.ui.LocalDetailBackSlide
import com.nextbody.hoop.ui.cardSkin
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.rememberScrollOffset
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 12-B · ME. The page answers who you are: the person, the one year of direction, and the way
 * in for outside AI assistants. Today's readiness stays on Home, so this page does not draw a
 * second Body Battery.
 */
@Composable
fun ProfileView() {
    val data = DataStore
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var notifyLamp by remember { mutableStateOf(NotificationAccess.lamp(context)) }
    var showGuide by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val scrolled by rememberScrollOffset(scroll, cap = 52.dp)

    val profile = data.profile
    val latestScan: CompositionScan? = data.compositionScans.maxByOrNull { it.at }
    val goalWord = L(profile.goal.raw)

    fun track(row: String) { scope.launch { Analytics.track("ME_ROW_TAP", mapOf("ROW" to row)) } }
    fun closeGuide() { showGuide = false }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { notifyLamp = NotificationAccess.lamp(context) }
    LaunchedEffect(Unit) {
        val state = if (latestScan?.inputWeightKg == null) "NO_SCAN" else "SCAN"
        Analytics.track("ME_OPEN", mapOf("STATE" to state))
    }

    DetailEdgeBack(onBack = { if (showGuide) closeGuide() else Router.backToRoot() }) {
        Box(Modifier.fillMaxSize().background(NB.carbon).clipToBounds()) {
            // ⚠️ The iOS page lays out 24 wider than the screen (the 26-week row is sized off
            // the screen, not the card), so every card draws 4 from the edges. Matched 1:1.
            Box(Modifier.requiredWidth(ScreenMetrics.width + 24.dp).fillMaxHeight().align(Alignment.TopCenter)) {
                Bloom()
                Column(
                    Modifier.fillMaxSize().verticalScroll(scroll),
                ) {
                    Spacer(Modifier.height(ScreenMetrics.safeTop + 44.dp))
                    Identity(profile.initials, profile.displayName) {
                        track("IDENTITY"); Router.sheet = SheetRoute.ProfileEdit
                    }
                    Gauges(latestScan)
                    Composition(goalWord) { track("COMPOSITION") }
                    McpCard {
                        track("AI_ASSISTANTS")
                        showGuide = true
                        scope.launch { Analytics.track("ME_MCP_GUIDE_OPEN") }
                    }

                    SectionMark(L("ACCOUNT"))
                    LineGroup {
                        ProfileLine(L("PROFILE"), value = profile.displayName.uppercase(), id = "PROFILE", track = ::track) {
                            Router.sheet = SheetRoute.ProfileEdit
                        }
                        ProfileLine(L("TRAINING GOAL"), value = goalWord, id = "TRAINING_GOAL", track = ::track) {
                            Router.sheet = SheetRoute.Goal
                        }
                        ProfileLine(L("DEVICE"), value = deviceValue(), id = "DEVICE", last = true, track = ::track) {
                            Router.open(Destination.Device, EntryPoint.profile)
                        }
                    }

                    SectionMark(L("PREFERENCES"))
                    LineGroup {
                        ProfileLine(
                            L("NOTIFICATIONS"), value = notifyValue(notifyLamp),
                            valueTint = if (notifyLamp == NotificationAccess.Lamp.Denied) ProfileTint.amber else null,
                            id = "NOTIFICATIONS", track = ::track,
                        ) { Router.sheet = SheetRoute.Notifications }
                        ProfileLine(
                            L("HEALTH CONNECT"),
                            value = if (profile.appleHealthLinked) L("SYNCED") else L("ACCESS OFF"),
                            valueTint = if (profile.appleHealthLinked) null else ProfileTint.amber,
                            id = "HEALTH_CONNECT", track = ::track,
                        ) { Router.sheet = SheetRoute.HealthConnect }
                        ProfileLine(L("UNITS · HAPTICS"), value = unitsValue(), id = "UNITS", track = ::track) {
                            Router.sheet = SheetRoute.Units
                        }
                        ProfileLine(L("LANGUAGE · WIDGETS"), value = AppLanguage.locale.nativeName, id = "LANGUAGE",
                            last = true, track = ::track) {
                            Router.sheet = SheetRoute.Language
                        }
                    }

                    SectionMark(L("DATA & LEGAL"))
                    LineGroup {
                        ProfileLine(L("AI ASSISTANTS"), value = L("MANAGE"), id = "ASSISTANTS_MANAGE", track = ::track) {
                            Router.sheet = SheetRoute.Assistants
                        }
                        ProfileLine(L("COLLECTING HEALTH DATA"),
                            value = if (ConsentStore.granted) L("ON") else L("OFF"), id = "COLLECTING", track = ::track) {
                            if (ConsentStore.granted) {
                                scope.launch { ConsentStore.record(ConsentStore.Choice.Withdrawn, msOnScreen = null) }
                            } else {
                                Router.setTakeover(Takeover.Consent)
                            }
                        }
                        // AI MEMORY is an AI-only row: AIFeature.enabled is false, so it is not drawn.
                        ProfileLine(L("PRIVACY · TERMS"), value = legalStamp(), id = "PRIVACY", track = ::track) {
                            Router.sheet = SheetRoute.Privacy
                        }
                        ProfileLine(L("REPORT A PROBLEM"), id = "REPORT", track = ::track) {
                            Router.sheet = SheetRoute.Feedback
                        }
                        ProfileLine(L("DELETE ACCOUNT"), titleTint = ProfileTint.deleteRed, id = "DELETE", last = true,
                            track = ::track) {
                            Router.sheet = SheetRoute.DeleteAccount
                        }
                    }

                    SignOff { track("SIGN_OUT"); Router.sheet = SheetRoute.SignOut }
                    Spacer(Modifier.height(ScreenMetrics.safeBottom))
                }
                BarGround(scrolled)
                Bar()
            }
            AnimatedVisibility(
                visible = showGuide,
                enter = fadeIn(tween(320, easing = com.nextbody.hoop.ui.SwiftEaseOut)),
                exit = fadeOut(tween(320, easing = com.nextbody.hoop.ui.SwiftEaseOut)),
            ) {
                ProfileMCPGuide(backTitle = L("ME"), onBack = ::closeGuide)
            }
        }
    }
}

internal object ProfileTint {
    val amber = hex(0xF59E5B)
    val deleteRed = hex(0xF87171)
}

// MARK: chrome

@Composable
private fun Bar() {
    Row(
        Modifier.fillMaxWidth().padding(top = ScreenMetrics.safeTop).height(44.dp).padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ProfileBackKey()
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).background(NB.lime1, CircleShape))
            Text(L("YOU"), style = NBFont.dot(600, 10f).tracking(0.2f), color = NB.lime1, maxLines = 1)
        }
    }
}

/**
 * ‹ ME. Plays the edge-back host's slide-out when there is one, so the key and the edge drag
 * leave the page the same way.
 */
@Composable
private fun ProfileBackKey() {
    val slide = LocalDetailBackSlide.current
    val back = L("Back")
    val me = L("ME")
    Row(
        Modifier
            .hotZoneTap(pressedScale = 1f) { slide?.invoke() ?: Router.backToRoot() }
            .semantics { contentDescription = back; stateDescription = me },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BackChevron(height = 16.dp, line = 1.6.dp, color = NB.white)
        Text(me, style = NBFont.ui(500, 16f), color = NB.white, maxLines = 1)
    }
}

/**
 * The lime glow the identity block sits in. It paints from the screen's top corner — through
 * the clock and the glass bar — so the header and the page read as one surface, and it fades
 * to clear before its own edge so nothing is clipped.
 */
@Composable
private fun Bloom() {
    Canvas(Modifier.offset(x = (-70).dp, y = (-55).dp).size(480.dp, 380.dp)) {
        drawRect(
            Brush.radialGradient(
                0f to NB.lime1.copy(alpha = 0.12f),
                0.55f to NB.lime1.copy(alpha = 0.04f),
                1f to NB.lime1.copy(alpha = 0f),
                center = Offset.Zero,
                radius = 300.dp.toPx(),
            ),
        )
    }
}

/**
 * At rest the bar is glass and the bloom runs straight through it. Carbon fades in — through
 * the clock, past the 44 bar, out in a short gradient — once the page slides under.
 */
@Composable
private fun BarGround(scrolled: Dp) {
    val a = min(1f, scrolled.value / 36f)
    if (a <= 0f) return
    Column(Modifier.fillMaxWidth().drawWithContent { drawContent() }) {
        Box(Modifier.fillMaxWidth().height(ScreenMetrics.safeTop + 44.dp).background(NB.carbon.copy(alpha = a)))
        Box(
            Modifier.fillMaxWidth().height(22.dp).background(
                Brush.verticalGradient(listOf(NB.carbon.copy(alpha = a), NB.carbon.copy(alpha = 0f))),
            ),
        )
    }
}

// MARK: identity · gauges

@Composable
private fun Identity(initials: String, name: String, onTap: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .hotZoneTap(pressedScale = 1f, onClick = onTap)
            .padding(start = 20.dp, end = 20.dp, top = 26.dp, bottom = 28.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(72.dp)
                .drawBehind {
                    // `.shadow(color: lime 25 %, radius: 14)`: the ring's own glow, both ways.
                    val r = size.minDimension / 2
                    val outer = r + 14.dp.toPx()
                    drawCircle(
                        Brush.radialGradient(
                            0f to Color.Transparent,
                            max(0f, r - 14.dp.toPx()) / outer to Color.Transparent,
                            r / outer to NB.lime1.copy(alpha = 0.07f),
                            1f to NB.lime1.copy(alpha = 0f),
                            center = center, radius = outer,
                        ),
                        radius = outer,
                    )
                }
                .border(2.dp, NB.lime1, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(initials, style = NBFont.ui(600, 22f), color = NB.lime1, maxLines = 1)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(L("NOW"), style = NBFont.dot(700, 10f).tracking(0.2f), color = NB.white.copy(alpha = 0.9f))
            FitText(
                name, NBFont.brand(700, 38f).tracking(-0.01f).copy(lineHeight = 42.sp), NB.white,
                minScale = 0.5f,
            )
        }
        Spacer(Modifier.width(0.dp)) // 14 + 0, as SwiftUI spaces before the trailing Spacer
    }
}

@Composable
private fun Gauges(latestScan: CompositionScan?) {
    val profile = DataStore.profile
    val metric = profile.usesMetric
    val height: Pair<String, String> = if (metric) {
        "${profile.heightCm.roundToInt()}" to "CM"
    } else {
        val inches = (profile.heightCm / 2.54).roundToInt()
        "${inches / 12}'${inches % 12}" to "FT"
    }
    // The same weight Home's body page reads: the latest scan, or a dash.
    val unit = if (metric) "KG" else "LB"
    val kg = latestScan?.inputWeightKg
    val weightValue = if (kg == null) Fmt.dash else Fmt.kg(if (metric) kg else kg * 2.2046226)
    val weightCaption = if (kg == null || latestScan == null) null else L("SCAN · %@", stamp(latestScan.at))

    Row(
        Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .cardSkin()
            .height(IntrinsicSize.Min)
            .drawBehind {
                val w = 1.dp.toPx()
                val third = (size.width - 2 * w) / 3
                drawRect(NB.hairline, Offset(third, 0f), Size(w, size.height))
                drawRect(NB.hairline, Offset(third * 2 + w, 0f), Size(w, size.height))
            },
        verticalAlignment = Alignment.Top,
    ) {
        Gauge(L("HEIGHT"), height.first, height.second)
        Gauge(L("WEIGHT"), weightValue, unit, tint = if (weightCaption == null) NB.white else NB.lime1, caption = weightCaption)
        Gauge(L("AGE"), "${profile.age}")
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Gauge(
    label: String, value: String, unit: String? = null, tint: Color = NB.white, caption: String? = null,
) {
    Column(
        Modifier.weight(1f).padding(vertical = 14.dp, horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(label, style = NBFont.ui(500, 10f).tracking(0.16f), color = NB.white.copy(alpha = 0.9f), maxLines = 1)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(value, NBFont.dot(800, 28f).tracking(-0.03f), tint, Modifier.alignByBaseline(), minScale = 0.6f)
            if (unit != null) {
                Text(unit, style = NBFont.dot(700, 9f), color = NB.white.copy(alpha = 0.8f), maxLines = 1,
                    modifier = Modifier.alignByBaseline())
            }
        }
        if (caption != null) {
            FitText(caption, NBFont.dot(700, 9f).tracking(0.08f), NB.white.copy(alpha = 0.8f), minScale = 0.7f)
        }
    }
}

// MARK: composition · mcp

@Composable
private fun Composition(goalWord: String, onTrack: () -> Unit) {
    val data = DataStore
    val scope = rememberCoroutineScope()
    val weeks = CompositionWindowMath.weekCells(
        scans = data.compositionScans,
        aim = CompositionAim.entries.firstOrNull { it.raw == data.profile.goal.raw } ?: CompositionAim.recomp,
        endingOn = UserDay.containing(Instant.now()),
    )
    Column(
        Modifier
            .padding(start = 16.dp, end = 16.dp, top = 16.dp)
            .fillMaxWidth()
            .cardSkin()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().hotZoneTap(pressedScale = 1f) {
                onTrack()
                Router.open(Destination.Composition(data.today.day.start.localDate()), EntryPoint.profile)
            },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(6.dp).background(NB.lime1, CircleShape))
            Box(Modifier.weight(1f)) {
                FitText(L("COMPOSITION · 26 W · %@", goalWord), NBFont.dot(700, 14f).tracking(0.12f), NB.lime1, minScale = 0.65f)
            }
            Spacer(Modifier.width(0.dp))
            Text("›", style = NBFont.ui(400, 16f), color = NB.white.copy(alpha = 0.35f))
        }
        MonthAxis()
        CompositionWeekRow(weeks) { week ->
            Router.open(Destination.Composition(week.end.start.localDate()), EntryPoint.profile)
        }
        CompositionWeekLegend()
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                L("The latest fat and lean mass are on the Body page"),
                style = NBFont.ui(300, 12f), color = NB.white.copy(alpha = 0.8f),
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(12.dp + 8.dp + 12.dp))
            Text(
                L("BODY ›"), style = NBFont.dot(700, 10f).tracking(0.12f), color = NB.lime1, maxLines = 1,
                modifier = Modifier.hotZoneTap(pressedScale = 1f) {
                    scope.launch { Analytics.track("ME_BODY_LINK_TAP") }
                    Router.showHome(page = 2)
                },
            )
        }
    }
}

/** The way in for ChatGPT, Claude, Cursor or Grok: the address to paste and the steps per client. */
@Composable
private fun McpCard(onTap: () -> Unit) {
    Column(
        Modifier
            .padding(start = 16.dp, end = 16.dp, top = 16.dp)
            .fillMaxWidth()
            .cardSkin()
            .hotZoneTap(onClick = onTap)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).background(NB.lime1, CircleShape))
            Text(L("MCP"), style = NBFont.dot(700, 12f).tracking(0.2f), color = NB.lime1)
        }
        Text(L("Connect your AI"), style = NBFont.ui(700, 20f).tracking(0.04f), color = NB.white)
        Text(
            L("ChatGPT, Claude, Cursor and Grok can read your own data."),
            style = NBFont.ui(300, 13f).copy(lineHeight = spaced(13f, 5f)), color = NB.white.copy(alpha = 0.7f),
        )
        Box(
            Modifier.fillMaxWidth().height(44.dp).background(NB.lime1, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(L("How to connect"), style = NBFont.ui(600, 13f).tracking(0.12f), color = NB.carbon4, maxLines = 1)
        }
    }
}

@Composable
private fun SignOff(onSignOut: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 28.dp, bottom = 34.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.fillMaxWidth().hotZoneTap(pressedScale = 1f, onClick = onSignOut), contentAlignment = Alignment.Center) {
            Text(L("SIGN OUT"), style = NBFont.ui(500, 12f).tracking(0.22f), color = NB.white, maxLines = 1)
        }
        Text(
            L("NEXTBODY %@ · BUILD %@", BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString()),
            style = NBFont.dot(700, 10f).tracking(0.16f), color = NB.lime1.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}

// MARK: rows

@Composable
private fun SectionMark(text: String) {
    Text(
        text, style = NBFont.ui(700, 16f).tracking(0.1f), color = NB.lime1,
        modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 30.dp, bottom = 10.dp),
    )
}

/** The last row's rule is left off, so the card's own edge closes the group. */
@Composable
private fun LineGroup(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().cardSkin(),
        content = content,
    )
}

@Composable
private fun ProfileLine(
    title: String,
    value: String? = null,
    valueTint: Color? = null,
    titleTint: Color? = null,
    id: String,
    last: Boolean = false,
    track: (String) -> Unit,
    action: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(54.dp)
            .drawBehind {
                if (!last) {
                    val inset = 16.dp.toPx()
                    drawRect(NB.hairline, Offset(inset, size.height - 1.dp.toPx()), Size(size.width - inset, 1.dp.toPx()))
                }
            }
            .hotZoneTap(pressedScale = 1f) { track(id); action() }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f)) {
            FitText(title, NBFont.ui(500, 14f).tracking(0.08f), titleTint ?: NB.white, minScale = 0.7f)
        }
        Spacer(Modifier.width(12.dp + 8.dp + 12.dp))
        if (value != null) {
            FitText(value, NBFont.dot(700, 11f), valueTint ?: NB.white.copy(alpha = 0.8f), minScale = 0.7f)
            Spacer(Modifier.width(12.dp))
        }
        Chevron()
    }
}

/** The row chevron: a 6 × 10 open angle in #5A5A66. */
@Composable
fun Chevron(color: Color = hex(0x5A5A66), modifier: Modifier = Modifier) {
    Canvas(modifier.size(6.dp, 10.dp)) {
        val k = 1.dp.toPx()
        val p = Path().apply {
            moveTo(1 * k, 1 * k); lineTo(5 * k, 5 * k); lineTo(1 * k, 9 * k)
        }
        drawPath(p, color, style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Square))
    }
}

// MARK: composition grid

@Composable
private fun MonthAxis() {
    val english = AppLanguage.isEnglish
    val f = DateTimeFormatter.ofPattern(if (english) "MMM" else "M月", AppLanguage.locale.javaLocale)
    val now = ZonedDateTime.now()
    val months = (5 downTo 0).map { back -> f.format(now.minusMonths(back.toLong())).uppercase() }
    Row(Modifier.fillMaxWidth()) {
        months.forEach { m ->
            Text(
                m, style = NBFont.dot(500, 10f).tracking(0.08f), color = NB.white.copy(alpha = 0.45f),
                maxLines = 1, modifier = Modifier.weight(1f),
            )
        }
    }
}

/**
 * One cell is one user week; the colour is that week's measured direction toward the training
 * goal — never what was eaten that day. BIA only means something a week apart, so a single scan
 * lights the whole week and a grey cell is a week nobody scanned. Every cell is tappable and
 * lands on composition detail at that week's end.
 */
@Composable
fun CompositionWeekRow(weeks: List<CompositionWeekCell>, onWeek: (CompositionWeekCell) -> Unit) {
    if (weeks.isEmpty()) return
    val gap = 3.dp
    val cell = (NB.Layout.screenWidth - 40.dp - gap * (weeks.size - 1)) / weeks.size
    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
        weeks.forEachIndexed { index, week ->
            CompositionWeekCellView(
                tone = week.tone, current = index == weeks.size - 1, height = cell, radius = 2.dp,
                modifier = Modifier.size(cell).hotZoneTap(pressedScale = 1f) { onWeek(week) },
            )
        }
    }
}

@Composable
fun CompositionWeekCellView(
    tone: CompositionWeekTone,
    modifier: Modifier = Modifier,
    current: Boolean = false,
    height: Dp = 34.dp,
    radius: Dp = 6.dp,
) {
    val fill = when (tone) {
        CompositionWeekTone.aligned -> NB.lime1
        CompositionWeekTone.held -> Color.Transparent
        CompositionWeekTone.drift -> NB.ember1
        CompositionWeekTone.noScan -> hex(0x26262E)
    }
    val stroke = if (tone == CompositionWeekTone.held) NB.white.copy(alpha = 0.35f)
    else if (current) NB.white.copy(alpha = 0.7f) else Color.Transparent
    val line = if (tone == CompositionWeekTone.held) 1.5.dp else if (current) 2.dp else 0.dp
    val shape = RoundedCornerShape(radius)
    Box(
        modifier
            .height(height)
            .background(fill, shape)
            .let { if (line > 0.dp) it.border(line, stroke, shape) else it },
    )
}

@Composable
fun CompositionWeekLegend() {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(
            CompositionWeekTone.aligned to L("ALIGNED"),
            CompositionWeekTone.held to L("HELD"),
            CompositionWeekTone.drift to L("DRIFT"),
            CompositionWeekTone.noScan to L("NO SCAN"),
        ).forEach { (tone, label) ->
            Row(
                Modifier.weight(1f),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CompositionWeekCellView(tone, Modifier.size(8.dp), height = 8.dp, radius = 2.dp)
                FitText(label, NBFont.dot(700, 10f).tracking(0.06f), NB.white.copy(alpha = 0.8f), minScale = 0.7f)
            }
        }
    }
}

// MARK: values

private fun deviceValue(): String {
    val band = DataStore.band
    if (!band.connected) return L("DISCONNECTED")
    val percent = band.batteryPercent
    return if (percent != null) L("NEXTBODY · %d%%", percent) else L("NEXTBODY · %@", Fmt.dash)
}

private fun unitsValue(): String {
    val unit = if (DataStore.profile.usesMetric) L("METRIC") else L("IMPERIAL")
    return L("%@ · %@", unit, if (HapticsSetting.enabled) L("ON") else L("OFF"))
}

private fun notifyValue(lamp: NotificationAccess.Lamp): String = when (lamp) {
    NotificationAccess.Lamp.On -> L("ON")
    NotificationAccess.Lamp.Off -> L("OFF")
    NotificationAccess.Lamp.Denied -> L("OFF IN SETTINGS")
}

private fun legalStamp(): String {
    val format = if (AppLanguage.isEnglish) "MMM d" else "M月d日"
    return Fmt.displayDate(LegalText.revised, format).uppercase()
}

private fun stamp(date: Instant): String {
    val format = if (AppLanguage.isEnglish) "MMM d" else "M月d日"
    return Fmt.displayDate(date, format).uppercase()
}

/**
 * The notification lamp on Android. iOS has three answers (authorized, denied, not determined);
 * here: enabled → ON; off before Android 13 can only be the system switch → OFF IN SETTINGS;
 * from 13 on, never asked → OFF, asked and refused → OFF IN SETTINGS.
 */
internal object NotificationAccess {
    enum class Lamp { On, Off, Denied }

    /** Written by the primer's Turn on, just before the POST_NOTIFICATIONS dialog. */
    val askedKey: String get() = com.nextbody.hoop.features.home.NotificationPrimerPolicy.askedKey

    fun enabled(context: Context): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** iOS `.notDetermined`: the system has never been asked. */
    fun notDetermined(context: Context): Boolean =
        !enabled(context) && Build.VERSION.SDK_INT >= 33 && !Defaults.getBoolean(askedKey)

    fun lamp(context: Context): Lamp = when {
        enabled(context) -> Lamp.On
        notDetermined(context) -> Lamp.Off
        else -> Lamp.Denied
    }
}

// MARK: text helpers

/** Swift `lineSpacing(n)`: the font's natural line plus n. */
internal fun spaced(size: Float, spacing: Float) = (size * 1.2f + spacing).sp

/**
 * One line that shrinks to fit, down to [minScale] — SwiftUI's `.lineLimit(1)` +
 * `.minimumScaleFactor`. Compose 1.7 has no auto-size, so it steps the size down on overflow.
 */
@Composable
internal fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.7f,
    align: TextAlign? = null,
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    var ready by remember(text, style) { mutableStateOf(false) }
    Text(
        text,
        style = style.copy(fontSize = style.fontSize * scale),
        color = color,
        maxLines = 1,
        softWrap = false,
        overflow = if (scale <= minScale) TextOverflow.Ellipsis else TextOverflow.Clip,
        textAlign = align,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        onTextLayout = { r ->
            if (r.hasVisualOverflow && scale > minScale) {
                scale = max(minScale, scale - 0.05f)
            } else {
                ready = true
            }
        },
    )
}

/** Home's MCP guide, laid over ME with ‹ ME as its way back. */
@Composable
private fun ProfileMCPGuide(backTitle: String, onBack: () -> Unit) {
    com.nextbody.hoop.features.home.HomeMCPGuide(onBack = onBack, backTitle = backTitle)
}
