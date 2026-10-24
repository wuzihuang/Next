package com.nextbody.hoop.features.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.nextbody.hoop.R
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.ui.hotZoneTap
import kotlin.math.max
import kotlin.math.min

/** Jost, by name — the planet board asks for the face itself, not the pixel-first UI stack. */
private val jostCache = HashMap<Int, FontFamily>()

internal fun jost(weight: Int, size: Float): TextStyle {
    val res = when {
        weight < 450 -> R.font.jost_regular
        weight < 550 -> R.font.jost_medium
        weight < 650 -> R.font.jost_semi_bold
        else -> R.font.jost_bold
    }
    val family = jostCache.getOrPut(res) { FontFamily(Font(res)) }
    return TextStyle(fontFamily = family, fontSize = size.sp)
}

/** Inter Tight, by name (`.custom("InterTight-Bold")`). */
internal fun interTightBold(size: Float): TextStyle =
    TextStyle(fontFamily = interTightFamily, fontSize = size.sp)

private val interTightFamily: FontFamily by lazy { FontFamily(Font(R.font.inter_tight_bold)) }

/**
 * One line of text that shrinks to fit, down to [minScale] (SwiftUI `.minimumScaleFactor`).
 * Kept a plain `Text`, so a row aligned on baselines still finds its baseline.
 */
@Composable
internal fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 1f,
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    var ready by remember(text, style) { mutableStateOf(minScale >= 1f) }
    Text(
        text = text,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        style = style.copy(
            fontSize = style.fontSize * scale,
            letterSpacing = style.letterSpacing,
        ),
        color = color,
        maxLines = 1,
        softWrap = false,
        overflow = if (minScale >= 1f) TextOverflow.Clip else TextOverflow.Visible,
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && scale > minScale + 0.001f) {
                scale = max(minScale, scale * 0.94f)
            } else {
                ready = true
            }
        },
    )
}

/** 06-A · the centre page, measured off the 390×746 board. Planets are drawn in code (see ParticlePlanet). */
@Composable
fun HomePlanetBoard(
    model: HomeV2Model.Planet,
    events: Int,
    onGuide: () -> Unit,
    onTimeline: () -> Unit,
    onReadiness: () -> Unit,
    onSleep: () -> Unit,
    onLoad: () -> Unit,
    onFood: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var guideDismissed by remember { mutableStateOf(Defaults.getBoolean("nb.home.mcpGuideDismissed")) }
    var mcpConnected by remember { mutableStateOf(Defaults.getBoolean("nb.home.mcpConnected")) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    // `.task` plus every return to the foreground.
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            val rows = runCatching {
                SupabaseClient.select(
                    "mcp_grants",
                    listOf("select" to "client_id", "revoked_at" to "is.null", "limit" to "1"),
                )
            }.getOrNull() ?: return@repeatOnLifecycle
            mcpConnected = rows.isNotEmpty()
            Defaults.putBoolean("nb.home.mcpConnected", mcpConnected)
        }
    }
    val face = remember(model, events) { PlanetFace.make(model, events) }

    Column(modifier.fillMaxSize().background(NB.carbon)) {
        Spacer(Modifier.height(16.dp))
        Hero(face, onReadiness, Modifier.weight(1f).fillMaxWidth().heightIn(min = 244.dp))
        Twin(face, onSleep, onLoad)
        FoodBlock(
            face, onFood, onGuide,
            showGuide = !guideDismissed && !mcpConnected,
            onDismissGuide = {
                guideDismissed = true
                Defaults.putBoolean("nb.home.mcpGuideDismissed", true)
            },
        )
        Spacer(Modifier.height(17.dp))
        Footer(events, onTimeline)
    }
}

private val white = Color.White

@Composable
private fun Hero(face: PlanetFace, onReadiness: () -> Unit, modifier: Modifier) {
    Box(
        modifier
            .clipToBounds()
            .testTag("READINESS")
            .hotZoneTap(pressedScale = 1f, onClick = onReadiness),
    ) {
        ParticlePlanet(
            ParticlePlanetKind.terra, centerX = 0.79f, centerY = 0.54f, radius = 0.32f, pitch = 1.5f,
            lit = face.terraLit, sunSide = 1f, day = 90.0, stars = 70, modifier = Modifier.fillMaxSize(),
        )
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 18.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).background(face.orbitColor, CircleShape))
                Text(face.orbit, style = NBFont.dot(700, 11f).tracking(0.12f), color = face.orbitColor, maxLines = 1,
                    overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.weight(1f))
            Text(L("READINESS"), style = jost(500, 11f).tracking(0.18f), color = white.copy(alpha = 0.72f))
            Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                FitText(face.readiness, NBFont.dot(800, 88f).tracking(-0.04f), NB.lime1,
                    Modifier.alignByBaseline().weight(1f, fill = false), minScale = 0.5f)
                Text("/100", Modifier.alignByBaseline(), style = NBFont.dot(700, 16f), color = white.copy(alpha = 0.30f))
            }
            Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                FitText(face.statusLead, NBFont.dot(700, 11f).tracking(0.08f), NB.lime1, minScale = 0.7f)
                Text("·", style = NBFont.dot(700, 11f), color = white.copy(alpha = 0.56f), maxLines = 1)
                FitText(face.statusDelta, NBFont.dot(700, 11f), white.copy(alpha = 0.56f), minScale = 0.7f)
            }
        }
    }
}

@Composable
private fun Twin(face: PlanetFace, onSleep: () -> Unit, onLoad: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(170.dp)
            .drawBehind { drawRect(white.copy(alpha = 0.08f), size = Size(size.width, 1.dp.toPx())) },
    ) {
        // SLEEP · LUNA
        Box(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .clipToBounds()
                .testTag("SLEEP")
                .hotZoneTap(pressedScale = 1f, onClick = onSleep)
                .drawWithContent {
                    drawContent()
                    drawRect(white.copy(alpha = 0.08f), Offset(size.width - 1.dp.toPx(), 0f), Size(1.dp.toPx(), size.height))
                },
        ) {
            ParticlePlanet(
                ParticlePlanetKind.luna, centerX = 0.70f, centerY = 0.43f, radius = 0.29f, pitch = 1.34f,
                lit = face.lunaLit, sunSide = -1f, day = 50.0, stars = 24, modifier = Modifier.fillMaxSize(),
            )
            Column(Modifier.fillMaxSize().padding(start = 20.dp, end = 16.dp, top = 14.dp, bottom = 14.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("SLEEP"), style = jost(500, 11f).tracking(0.16f), color = white.copy(alpha = 0.72f))
                    Text(L("LUNA"), style = NBFont.dot(700, 9f), color = NB.violet1)
                }
                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(face.sleepScore, Modifier.alignByBaseline(), style = NBFont.dot(800, 44f).tracking(-0.04f),
                        color = NB.violet1, maxLines = 1, softWrap = false)
                    Text("/100", Modifier.alignByBaseline(), style = NBFont.dot(700, 12f), color = white.copy(alpha = 0.30f))
                }
                Spacer(Modifier.weight(1f))
                Meter(face.sleepFill, NB.violet1, null)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    Text(face.sleepDuration, style = NBFont.dot(700, 10f), color = NB.violet1, maxLines = 1)
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    Text(face.sleepDeep, style = NBFont.dot(700, 10f), color = white.copy(alpha = 0.45f), maxLines = 1)
                }
            }
        }
        // LOAD · MARS
        Box(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .clipToBounds()
                .testTag("LOAD")
                .hotZoneTap(pressedScale = 1f, onClick = onLoad),
        ) {
            ParticlePlanet(
                ParticlePlanetKind.mars, centerX = 0.72f, centerY = 0.43f, radius = 0.29f, pitch = 1.34f,
                lit = face.marsLit, sunSide = -1f, day = 36.0, stars = 24, modifier = Modifier.fillMaxSize(),
            )
            Column(Modifier.fillMaxSize().padding(start = 16.dp, end = 20.dp, top = 14.dp, bottom = 14.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("LOAD"), style = jost(500, 11f).tracking(0.16f), color = white.copy(alpha = 0.72f))
                    Text(L("MARS"), style = NBFont.dot(700, 9f), color = NB.run1)
                }
                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(face.load, Modifier.alignByBaseline(), style = NBFont.dot(800, 44f).tracking(-0.04f),
                        color = if (face.loadHit) NB.lime1 else NB.run1, maxLines = 1, softWrap = false)
                    Text("/" + face.loadTarget, Modifier.alignByBaseline(), style = NBFont.dot(800, 20f), color = NB.lime1,
                        maxLines = 1, softWrap = false)
                }
                Spacer(Modifier.weight(1f))
                Meter(face.loadFill, if (face.loadHit) NB.lime1 else NB.run1, face.aimTick)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    Text(face.aimLeft, style = NBFont.dot(700, 10f), color = NB.lime1, maxLines = 1)
                    Spacer(Modifier.width(24.dp))
                    Spacer(Modifier.weight(1f))
                    Text(face.aimRight, style = NBFont.dot(700, 10f), color = white.copy(alpha = 0.56f), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun Meter(fill: Float, tint: Color, marker: Float?) {
    Canvas(Modifier.fillMaxWidth().height(9.dp)) {
        val w = size.width
        val y = (size.height - 3.dp.toPx()) / 2
        drawRect(white.copy(alpha = 0.08f), Offset(0f, y), Size(w, 3.dp.toPx()))
        drawRect(tint, Offset(0f, y), Size(max(0f, w * fill), 3.dp.toPx()))
        if (marker != null) {
            drawRect(NB.lime1, Offset(w * marker - 1.dp.toPx(), 0f), Size(2.dp.toPx(), 9.dp.toPx()))
        }
    }
}

private fun Modifier.hairlineTop(alpha: Float): Modifier = drawWithContent {
    drawContent()
    drawRect(white.copy(alpha = alpha), Offset.Zero, Size(size.width, 1.dp.toPx()))
}

private fun Modifier.hairlineBottom(alpha: Float): Modifier = drawWithContent {
    drawContent()
    drawRect(white.copy(alpha = alpha), Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
}

private fun Modifier.hairlineTrailing(alpha: Float): Modifier = drawWithContent {
    drawContent()
    drawRect(white.copy(alpha = alpha), Offset(size.width - 1.dp.toPx(), 0f), Size(1.dp.toPx(), size.height))
}

@Composable
private fun FoodBlock(
    face: PlanetFace,
    onFood: () -> Unit,
    onGuide: () -> Unit,
    showGuide: Boolean,
    onDismissGuide: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().hairlineBottom(0.08f)) {
        when (val food = face.food) {
            is PlanetFace.Food.Empty -> {
                AllowanceRow(
                    food.kcal, food.meals,
                    Modifier.testTag("FOOD").hotZoneTap(pressedScale = 1f, onClick = onFood),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        MacroTarget(L("PROTEIN"), food.protein, NB.optimal2)
                        MacroTarget(L("CARBS"), food.carbs, NB.lime1)
                        MacroTarget(L("FAT"), food.fat, NB.run1)
                    }
                }
                AnimatedVisibility(showGuide, enter = androidx.compose.animation.EnterTransition.None,
                    exit = fadeOut(tween(200))) {
                    Box(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .hairlineTop(0.07f)
                                .testTag("CONNECT_MCP")
                                .hotZoneTap(pressedScale = 1f, onClick = onGuide)
                                .padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 18.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(
                                food.guide, Modifier.fillMaxWidth(),
                                style = jost(400, 15f).copy(lineHeight = (15f * 1.2f + 7f).sp),
                                color = white,
                            )
                            Box(
                                Modifier
                                    .height(36.dp)
                                    .border(1.dp, white.copy(alpha = 0.45f), RoundedCornerShape(18.dp))
                                    .padding(horizontal = 14.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(L("CONNECT MCP →"), style = NBFont.dot(700, 11f).tracking(0.08f), color = white)
                            }
                        }
                        // ×
                        Box(
                            Modifier
                                .align(Alignment.BottomEnd)
                                .padding(end = 8.dp, bottom = 6.dp)
                                .size(44.dp)
                                .testTag("CONNECT_MCP_DISMISS")
                                .hotZoneTap(pressedOpacity = 0.72f, pressedScale = 1f, onClick = onDismissGuide),
                            contentAlignment = Alignment.Center,
                        ) { XMark(9.dp, 1.9.dp, white.copy(alpha = 0.65f)) }
                    }
                }
            }
            is PlanetFace.Food.Logged -> {
                Column(Modifier.testTag("FOOD").hotZoneTap(pressedScale = 1f, onClick = onFood)) {
                    LoggedHeader(food.eaten, food.allow, food.meals, food.left)
                    Row(Modifier.fillMaxWidth().height(68.dp)) {
                        food.rows.forEachIndexed { index, row -> LoggedMacro(row, index, food.rows.size) }
                    }
                }
            }
        }
    }
}

/** SF Symbol `xmark`, drawn. */
@Composable
internal fun XMark(size: Dp, line: Dp, color: Color) {
    Canvas(Modifier.size(size).clearAndSetSemantics { }) {
        val s = this.size.width
        val w = line.toPx()
        drawLine(color, Offset(0f, 0f), Offset(s, s), w, StrokeCap.Round)
        drawLine(color, Offset(s, 0f), Offset(0f, s), w, StrokeCap.Round)
    }
}

/** Unlogged top line: today's allowance, with the three macro targets on the right. */
@Composable
private fun AllowanceRow(kcal: String, meals: String, modifier: Modifier, trailing: @Composable () -> Unit) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.alignBy(LastBaseline), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(L("FOOD"), style = jost(600, 10f).tracking(0.18f), color = white.copy(alpha = 0.72f))
                Text(meals, style = NBFont.dot(700, 9f), color = white.copy(alpha = 0.52f), maxLines = 1)
            }
            Row(Modifier.alignBy(LastBaseline), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                FitText(kcal, NBFont.dot(800, 28f).tracking(-0.03f), white, Modifier.alignByBaseline(), minScale = 0.72f)
                FitText(L("KCAL ALLOW"), NBFont.dot(700, 11f).tracking(0.04f), white.copy(alpha = 0.65f),
                    Modifier.alignByBaseline(), minScale = 0.72f)
            }
        }
        // 8 + 8 + 8, as SwiftUI spaces around the Spacer
        Spacer(Modifier.width(24.dp))
        trailing()
    }
}

@Composable
private fun MacroTarget(name: String, value: String, tint: Color) {
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, style = NBFont.dot(800, 16f), color = tint, maxLines = 1)
        Text(name, style = jost(600, 9f).tracking(0.12f), color = white.copy(alpha = 0.52f), maxLines = 1)
    }
}

@Composable
private fun LoggedHeader(eaten: String, allow: String, meals: String, left: String) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).hairlineBottom(0.07f)) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .hairlineTrailing(0.07f)
                .padding(start = 20.dp, end = 16.dp, top = 14.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(L("FOOD"), style = jost(600, 10f).tracking(0.18f), color = white.copy(alpha = 0.72f))
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(eaten, Modifier.alignByBaseline(), style = NBFont.dot(800, 28f).tracking(-0.03f), color = white,
                    maxLines = 1, softWrap = false)
                FitText(L("/ %@ ALLOW", allow), NBFont.dot(700, 12f), white.copy(alpha = 0.65f),
                    Modifier.alignByBaseline(), minScale = 0.7f)
            }
            Text(meals, style = NBFont.dot(700, 9f), color = white.copy(alpha = 0.52f))
        }
        Column(
            Modifier
                .width(124.dp)
                .padding(start = 12.dp, end = 20.dp, top = 14.dp, bottom = 16.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(L("LEFT"), style = jost(600, 10f).tracking(0.18f), color = white.copy(alpha = 0.72f))
            FitText(left, NBFont.dot(800, 28f).tracking(-0.03f), white, minScale = 0.7f)
            Text(L("KCAL"), style = NBFont.dot(700, 9f).tracking(0.08f), color = white.copy(alpha = 0.52f))
        }
    }
}

@Composable
private fun RowScope.LoggedMacro(row: PlanetFace.Row, index: Int, count: Int) {
    Column(
        Modifier
            .weight(1f)
            .fillMaxHeight()
            .then(if (index < count - 1) Modifier.hairlineTrailing(0.07f) else Modifier)
            .padding(
                start = if (index == 0) 20.dp else 14.dp,
                end = if (index == count - 1) 20.dp else 14.dp,
                top = 10.dp, bottom = 10.dp,
            ),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(row.name, style = jost(600, 9f).tracking(0.14f), color = white.copy(alpha = 0.56f), maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(if (row.aside.isNotEmpty()) 12.dp else 8.dp))
            if (row.aside.isNotEmpty()) {
                FitText(row.aside, NBFont.dot(700, 9f), if (row.met) row.tint else white.copy(alpha = 0.52f), minScale = 0.7f)
            }
        }
        Spacer(Modifier.weight(1f).heightIn(min = 2.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.eaten, Modifier.alignByBaseline(), style = NBFont.dot(800, 20f), color = row.tint, maxLines = 1)
            Text("/${row.target}G", Modifier.alignByBaseline(), style = NBFont.dot(700, 10f), color = white.copy(alpha = 0.38f),
                maxLines = 1)
        }
        Spacer(Modifier.weight(1f).heightIn(min = 2.dp))
        BoxWithConstraints(Modifier.fillMaxWidth().height(3.dp)) {
            Box(Modifier.fillMaxSize().background(white.copy(alpha = 0.10f)))
            Box(Modifier.width(maxWidth * max(0f, row.fill)).fillMaxHeight().background(row.tint))
        }
    }
}

@Composable
private fun Footer(events: Int, onTimeline: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ChevronUp()
        Column(
            Modifier.hotZoneTap(pressedScale = 1f, onClick = onTimeline),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(L("TODAY TIMELINE · %d EVENTS", events), style = NBFont.dot(600, 11f).tracking(0.18f), color = NB.lime1)
            if (events == 0) {
                Text(L("Start your workout"), style = jost(400, 12f), color = white.copy(alpha = 0.48f))
            }
        }
    }
}

@Composable
private fun ChevronUp() {
    Canvas(Modifier.size(16.dp, 10.dp).clearAndSetSemantics { }) {
        val p = Path().apply {
            moveTo(2.dp.toPx(), size.height - 2.dp.toPx())
            lineTo(size.width / 2, 2.dp.toPx())
            lineTo(size.width - 2.dp.toPx(), size.height - 2.dp.toPx())
        }
        drawPath(p, NB.lime1, style = Stroke(1.4.dp.toPx(), cap = StrokeCap.Square, join = StrokeJoin.Miter))
    }
}

/** What the board prints, already formatted. */
private class PlanetFace(
    val orbit: String,
    val orbitColor: Color,
    val readiness: String,
    val statusLead: String,
    val statusDelta: String,
    val sleepScore: String,
    val sleepDuration: String,
    val sleepDeep: String,
    val sleepFill: Float,
    val load: String,
    val loadTarget: String,
    val loadFill: Float,
    val aimTick: Float,
    val aimLeft: String,
    val aimRight: String,
    val loadHit: Boolean,
    val food: Food,
) {
    sealed class Food {
        class Empty(val kcal: String, val meals: String, val protein: String, val carbs: String, val fat: String, val guide: String) : Food()
        class Logged(val eaten: String, val allow: String, val meals: String, val left: String, val rows: List<Row>) : Food()
    }

    class Row(
        val id: String, val name: String, val eaten: String, val target: String,
        val fill: Float, val tint: Color, val met: Boolean, val aside: String,
    )

    /**
     * How much of each planet the sun reaches. Never less than half, so the planet always
     * reads; a full score lights the whole disc.
     */
    val terraLit: Double get() = lit(readiness.toIntOrNull())
    val lunaLit: Double get() = lit(sleepScore.toIntOrNull())
    val marsLit: Double get() = 0.5 + 0.5 * loadFill

    companion object {
        fun lit(score: Int?): Double {
            if (score == null) return 0.5
            return 0.5 + 0.5 * max(0, min(100, score)).toDouble() / 100
        }

        fun make(model: HomeV2Model.Planet, events: Int): PlanetFace {
            when (DebugEnv["NB_DEBUG_HOME_BOARD"]) {
                "A" -> return boardA
                "B" -> return boardB
                "C" -> return boardC
                "D" -> return boardD
            }
            val orbitColor = if (model.food.face == HomeV2Model.FoodFace.complete) NB.lime1
            else if (model.band == HomeV2Model.ReadinessBand.recover) white.copy(alpha = 0.72f) else NB.blue1
            val loadTarget = model.loadTarget?.let { Fmt.load(it) } ?: Fmt.dash
            val target = model.loadTarget ?: 0.0
            val current = model.load ?: 0.0
            val loadHit = target > 0 && current >= target
            val loadFill = if (target > 0) min(1.0, current / target).toFloat() else 0f
            val ceiling = max(target, 10.0)
            val aimTick = if (target > 0) min(1.0, target / ceiling).toFloat() else 0f
            val aim = model.loadTarget
            val now = model.load
            val (aimLeft, aimRight) = when {
                model.band == HomeV2Model.ReadinessBand.recover && aim != null ->
                    L("LOW AIM %@", Fmt.load(aim)) to L("HOLD & REST")
                loadHit -> L("AIM %@ HIT", loadTarget) to
                    (if (model.band == HomeV2Model.ReadinessBand.peak) L("OPTIMAL") else L("HIT"))
                aim != null && now != null -> L("AIM %@", Fmt.load(aim)) to L("%@ TO GO", Fmt.load(max(0.0, aim - now)))
                else -> L("NO AIM YET") to Fmt.dash
            }
            val food = when (model.food.face) {
                HomeV2Model.FoodFace.unlogged, HomeV2Model.FoodFace.recovery -> Food.Empty(
                    kcal = model.food.targetKcal?.let { Fmt.kcal(it.toDouble()) } ?: Fmt.dash,
                    meals = L("%d MEALS", model.food.meals),
                    protein = model.food.protein.target?.toString() ?: Fmt.dash,
                    carbs = model.food.carb.target?.toString() ?: Fmt.dash,
                    fat = model.food.fat.target?.toString() ?: Fmt.dash,
                    guide = model.food.guide ?: "",
                )
                HomeV2Model.FoodFace.remaining, HomeV2Model.FoodFace.complete -> Food.Logged(
                    eaten = model.food.eatenKcal?.let { Fmt.kcal(it.toDouble()) } ?: Fmt.dash,
                    allow = model.food.targetKcal?.let { Fmt.kcal(it.toDouble()) } ?: Fmt.dash,
                    meals = L("%d MEALS", model.food.meals),
                    left = model.food.kcalLeft?.let { Fmt.kcal(max(0, it).toDouble()) } ?: Fmt.dash,
                    rows = listOf(
                        macro("protein", L("PROTEIN"), model.food.protein, NB.optimal2),
                        macro("carbs", L("CARBS"), model.food.carb, NB.lime1),
                        macro("fat", L("FAT"), model.food.fat, NB.run1),
                    ),
                )
            }
            return PlanetFace(
                orbit = L("TERRA · %@ · %@", model.orbitPlace, model.orbitState),
                orbitColor = orbitColor,
                readiness = model.readiness?.toString() ?: Fmt.dash,
                statusLead = if (model.band == HomeV2Model.ReadinessBand.unknown) Fmt.dash
                else L("%@ · %@", model.statusWord, model.statusPhrase),
                statusDelta = model.vsAverage?.let { HomeV2Model.signedInt(it) + " " + L("VS AVG") } ?: L("—— VS AVG"),
                sleepScore = model.sleepScore?.toString() ?: Fmt.dash,
                sleepDuration = model.sleepMinutes?.let { Fmt.duration(it) } ?: Fmt.dash,
                sleepDeep = model.sleepDeepMinutes?.let { L("DEEP %@", Fmt.duration(it)) } ?: model.sleepFoot,
                sleepFill = (model.sleepScore ?: 0) / 100f,
                load = Fmt.load(model.load),
                loadTarget = loadTarget,
                loadFill = loadFill,
                aimTick = aimTick,
                aimLeft = aimLeft,
                aimRight = aimRight,
                loadHit = loadHit,
                food = food,
            )
        }

        private fun macro(id: String, name: String, macro: HomeV2Model.Macro, tint: Color): Row {
            val eaten = macro.eaten
            val target = macro.target
            val fill = if (eaten != null && target != null && target > 0) min(1f, eaten.toFloat() / target) else 0f
            val aside = when {
                macro.met -> L("HIT") + " ✓"
                macro.left != null -> L("%dG LEFT", max(0, macro.left!!))
                else -> ""
            }
            return Row(id, name, eaten?.toString() ?: Fmt.dash, target?.toString() ?: Fmt.dash, fill, tint, macro.met, aside)
        }

        private const val guideCopy = "Connect MCP, then type what you eat in your personal agent."

        private val boardA get() = PlanetFace(
            "TERRA · HOME BASE · STEADY", NB.blue1, "78", "STEADY · READY TO TRAIN", "+12 VS AVG",
            "82", "7H 12M", "DEEP 1H 48M", 0.82f, "5.1", "8.0", 98f / 154f, 124f / 154f, "AIM 8.0", "2.9 TO GO", false,
            Food.Empty("2,280", "0 MEALS", "145", "290", "60", guideCopy),
        )
        private val boardB get() = PlanetFace(
            "TERRA · LOW ORBIT · RECOVERY HOLD", white.copy(alpha = 0.72f), "44", "RECOVER · REST TODAY", "−24 VS AVG",
            "52", "5H 10M", "DEBT −2H 15M", 0.52f, "1.8", "3.0", 0.22f, 3f / 10f, "LOW AIM 3.0", "HOLD & REST", false,
            Food.Empty("2,100", "0 MEALS", "145", "245", "60", guideCopy),
        )
        private val boardC get() = PlanetFace(
            "TERRA · ORBIT LOCKED · ALL TARGETS MET", NB.lime1, "88", "PEAK · FULL CHARGE", "+18 VS AVG",
            "90", "7H 54M", "OPTIMAL FULL", 0.90f, "8.2", "8.0", 1f, 0.80f, "AIM 8.0 HIT", "OPTIMAL", true,
            Food.Logged(
                "2,240", "2,280", "3 MEALS", "40",
                listOf(
                    Row("protein", "PROTEIN", "142", "145", 142f / 145f, NB.optimal2, true, "HIT ✓"),
                    Row("carbs", "CARBS", "282", "290", 282f / 290f, NB.lime1, true, "HIT ✓"),
                    Row("fat", "FAT", "58", "60", 58f / 60f, NB.run1, true, "HIT ✓"),
                ),
            ),
        )
        private val boardD get() = PlanetFace(
            "TERRA · HOME BASE · STEADY", NB.blue1, "78", "STEADY · READY TO TRAIN", "+12 VS AVG",
            "82", "7H 12M", "DEEP 1H 48M", 0.82f, "5.1", "8.0", 98f / 154f, 124f / 154f, "AIM 8.0", "2.9 TO GO", false,
            Food.Logged(
                "1,420", "2,280", "2 MEALS", "860",
                listOf(
                    Row("protein", "PROTEIN", "96", "145", 96f / 145f, NB.optimal2, false, "49G LEFT"),
                    Row("carbs", "CARBS", "142", "290", 142f / 290f, NB.lime1, false, "148G LEFT"),
                    Row("fat", "FAT", "48", "60", 48f / 60f, NB.run1, false, "12G LEFT"),
                ),
            ),
        )
    }
}
