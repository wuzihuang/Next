package com.nextbody.hoop.app

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.l10n.AppLanguage
import kotlinx.coroutines.launch

/**
 * The root: gate stages, or the one NavigationStack (Home + its detail pages), with takeovers
 * and sheets on top. Mirrors `RootView.swift`.
 */
@Composable
fun RootView() {
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    SideEffect {
        ScreenMetrics.width = config.screenWidthDp.dp
        ScreenMetrics.safeTop = top
        ScreenMetrics.safeBottom = bottom
    }

    // F5 C11 · 「maxFontSizeMultiplier = 1.35」. Fixed-pixel layouts honour system font size only
    // up to the cap; beyond it they freeze rather than clip.
    val capped = Density(density.density, density.fontScale.coerceAtMost(1.35f))
    val locale = AppLanguage.locale
    CompositionLocalProvider(LocalDensity provides capped) {
        key(locale) {
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize().background(NB.carbon)) {
                // The window itself, bars included (edge to edge). screenHeightDp already counts
                // the bars on API 35 and not before, so it is not used.
                val h = maxHeight
                SideEffect { ScreenMetrics.height = h }
                Screens.Stage()
                TakeoverHost()
                SheetHost()
                Screens.LaunchOverlay()
                com.nextbody.hoop.features.home.panel.IdlePlateDumpOverlay()
            }
        }
    }
}

/** B + C · Home and the pages pushed on it. Back (system gesture or chevron) pops one. */
@Composable
fun RootStack() {
    val path = Router.path
    BackHandler(enabled = path.isNotEmpty() && Router.takeover == null && Router.sheet == null) {
        Router.back()
    }
    Box(Modifier.fillMaxSize()) {
        Screens.Home()
        StackHost(path)
    }
    if (com.nextbody.hoop.BuildConfig.DEBUG) DebugWalk.Run()
}

/**
 * iOS NavigationStack motion: the new page slides in from the right edge over the one
 * underneath, which drifts left by a third; a pop reverses it.
 */
@Composable
private fun StackHost(path: List<Destination>) {
    val shown = remember { mutableStateListOf<Destination>() }
    val leaving = remember { mutableStateListOf<Destination>() }
    LaunchedEffect(path) {
        val gone = shown.filter { it !in path }
        leaving.addAll(gone.filter { it !in leaving })
        shown.removeAll { it !in path }
        path.forEach { if (it !in shown) shown.add(it) }
    }
    val widthPx = with(LocalDensity.current) { ScreenMetrics.width.toPx() }
    val all = shown + leaving.filter { it !in shown }
    all.forEach { d ->
        key(d.key) {
            val isLeaving = d in leaving && d !in shown
            val x = remember { Animatable(widthPx) }
            LaunchedEffect(isLeaving) {
                if (isLeaving) {
                    x.animateTo(widthPx, tween(320, easing = FastOutSlowInEasing))
                    leaving.remove(d)
                } else {
                    x.animateTo(0f, tween(380, easing = FastOutSlowInEasing))
                }
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { translationX = x.value }
                    .background(NB.carbon)
            ) {
                Screens.Detail(d)
            }
        }
    }
}

/** D · ON TOP. A takeover is the panel grown to full screen, never a page. */
@Composable
private fun TakeoverHost() {
    val takeover = Router.takeover
    AnimatedContent(
        targetState = takeover,
        transitionSpec = {
            // The wordmark film starts on a cut: the power-on is the flash, not a slide.
            if (targetState is Takeover.Wordmark || initialState is Takeover.Wordmark) {
                fadeIn(tween(0)) togetherWith fadeOut(tween(160))
            } else {
                slideInVertically(tween(380)) { it } togetherWith slideOutVertically(tween(320)) { it }
            }
        },
        label = "takeover",
    ) { t ->
        if (t != null) {
            val generation = remember(t) { Router.takeoverGeneration }
            Box(Modifier.fillMaxSize().background(NB.carbon)) {
                BackHandler {
                    // Measuring owns its own exit (it has a stop to confirm); everything else closes.
                    if (t !is Takeover.Measure && t !is Takeover.Wordmark) Router.setTakeover(null)
                }
                Screens.Takeover(t) {
                    if (Router.takeoverGeneration == generation) Router.setTakeover(null)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetHost() {
    val route = Router.sheet ?: return
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(
        onDismissRequest = { Router.sheet = null },
        sheetState = state,
        // iOS 26 floats the sheet as a card: 8pt in from the sides and the bottom, every
        // corner rounded. The system container is cleared and the card is drawn here.
        containerColor = Color.Transparent,
        contentColor = NB.text1,
        scrimColor = Color.Black.copy(alpha = 0.45f),
        shape = RectangleShape,
        tonalElevation = 0.dp,
        // iOS draws its grabber over the sheet content, 5pt from the top; it takes no room.
        dragHandle = null,
        contentWindowInsets = { WindowInsets(0) },
    ) {
        Box(
            Modifier
                .padding(start = SheetChrome.inset, end = SheetChrome.inset, bottom = SheetChrome.inset)
                .fillMaxWidth()
                .height(SheetChrome.height(route) + SheetChrome.rise - SheetChrome.inset)
                .clip(SheetChrome.cardShape)
                .background(NB.carbon2)
        ) {
            Screens.Sheet(route) {
                scope.launch { state.hide() }.invokeOnCompletion { Router.sheet = null }
            }
            Box(
                Modifier.align(androidx.compose.ui.Alignment.TopCenter).padding(top = 5.dp)
                    .size(36.dp, 5.dp)
                    .background(NB.white.copy(alpha = 0.3f), RoundedCornerShape(2.5.dp))
            )
        }
    }
}

/**
 * F1 · D — a sheet never exceeds 78% of the screen, and the screen behind it always keeps
 * showing its title and at least one row of value. Each route asks for the height its own
 * content needs.
 */
object SheetChrome {
    val maxHeight: Dp get() = (844f * 0.78f).dp

    /** The gap iOS 26 leaves around a floating sheet, measured off the simulator. */
    val inset: Dp = 8.dp
    val cardShape = RoundedCornerShape(38.dp)

    /** A `.height(h)` detent on iOS 26 puts the sheet top about 20pt above h. Measured. */
    val rise: Dp = 20.dp

    fun height(route: SheetRoute): Dp = when (route) {
        SheetRoute.PlusMenu -> 430.dp            // 06 · two groups, five rows
        // 10S · the keypad, and no more. +60 over iOS: Android type sets a few percent larger
        // and the keypad must never sit under SAVE.
        SheetRoute.WeighIn -> 620.dp
        SheetRoute.ScanWeighIn -> 462.dp         // 14 · dial + one confirm, no keypad
        SheetRoute.SignOut -> 360.dp
        // 11's delete sheet has room for the sentence that counts out what is lost *and* the
        // line that says nothing was deleted when the endpoint cannot be reached.
        SheetRoute.DeleteAccount -> 400.dp
        SheetRoute.Language, SheetRoute.HealthConnect -> 400.dp
        // ADR 0010 · 身体扫描要装下 14 个字段。
        is SheetRoute.Measurement -> 620.dp
        SheetRoute.Goal, SheetRoute.Units -> 480.dp
        SheetRoute.Notifications -> 516.dp
        // 9-0 A·S8 · one sentence and one key.
        is SheetRoute.WearSwitch -> 380.dp
        else -> maxHeight
    }
}
