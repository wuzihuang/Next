package com.nextbody.hoop.features.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import com.nextbody.hoop.features.home.panel.OrbitField
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.LaunchFilmPolicy
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.app.DebugLaunch
import com.nextbody.hoop.band.Band
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.pow

/**
 * MOTION SPEC · 05 · FIRST RUN · FULL PAGE.
 *
 * It boots as one screen, then folds into a page. On the very first entry to Home the whole
 * display *is* the panel — no status bar, no wordmark, no tiles, no dock — and at 5.20s that
 * one surface folds down to 358 × 470 and the rest of the page takes the space it gave up.
 *
 *   ◇1  0.00  BLACK     one lime pixel, dead centre
 *   ◇2  0.40  CORE      it bursts into a core; the backplate lifts to 20%
 *   ◇3  1.20  SWEEP     the orbit draws from the right, 0.8s ease-out
 *   ◇4  1.90  ALIVE     the planet starts 90s a revolution and never stops again
 *   ◇5  2.60  TYPE      hairline opens from the centre, then Doto types at 28ms a character
 *   ◇6  3.90  LIME      line one drops to white, line two comes in lime, 0.4s of silence between
 *   ◇7  5.20  KEY       390×844 → 358×470, radius 44 → 30, 0.62s spring(0.82 / 0.34)
 *   ◇8  5.60  TOP       status bar and wordmark slide in from −8px, 120ms apart
 *   ◇9  6.10  STAGGER   the two tiles rise from +16px, left then right, 80ms apart
 *   ◇10 6.70  INPUT     the dock's three keys land together — it is one tool, not three
 *   ◇11 7.40  IDLE      the home indicator last. Two things still move, and only two.
 *
 * Swift animates each beat with `withAnimation`; Compose callers animate the derived values
 * themselves with [transition] (the spring the beat that just landed asked for).
 */
class FirstRun {
    enum class Beat(val at: Double) {
        black(0.00), core(0.40), sweep(1.20), alive(1.90), type(2.60),
        lime(3.90), key(5.20), top(5.60), stagger(6.10), input(6.70), idle(7.40);
    }

    /** SwiftUI `.spring(response:dampingFraction:)` of the last beat change; null = no animation. */
    data class Transition(val response: Float, val dampingFraction: Float, val easeOutSeconds: Float? = null)

    var playing by mutableStateOf(false)
        private set
    var beat by mutableStateOf(Beat.black)
        private set
    /** How many characters of each subtitle line have been typed. */
    var typed by mutableStateOf(0 to 0)
        private set
    var transition by mutableStateOf<Transition?>(null)
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var task: Job? = null

    companion object {
        private const val key = LaunchFilmPolicy.firstRunPlayedKey
        val lineOne: String get() = L("I DON'T COACH.")
        val lineTwo: String get() = L("I READ YOU.")
        val lineThree: String get() = L("THE FIRST TARGET LANDS BY MORNING")
        val lineThreeUnpaired: String get() = L("PAIR YOUR BAND TO START")

        /** Only after onboarding, only once. Reinstalling is the only way back. */
        val shouldPlay: Boolean get() = !Defaults.getBoolean(key)
        fun markPlayed() = Defaults.putBoolean(key, true)
    }

    private fun set(beat: Beat, transition: Transition?) {
        this.transition = transition
        this.beat = beat
    }

    fun start(reduceMotion: Boolean, lowPower: Boolean) {
        if (Band.allowsSeed) {
            val raw = DebugLaunch["NB_DEBUG_FIRSTRUN_BEAT"]
            if (!raw.isNullOrEmpty()) {
                Beat.entries.firstOrNull { it.name == raw }?.let { b ->
                    playing = true
                    set(b, null)
                    if (b >= Beat.type) typed = lineOne.length to (if (b >= Beat.lime) lineTwo.length else 0)
                    return
                }
            }
        }
        if (playing) return
        if (!shouldPlay) { finish(); return }
        playing = true
        markPlayed()

        // Reduce Motion: ◇1–◇7 are skipped and the whole page fades in over 0.3s,
        // with the subtitle shown at once rather than typed.
        if (reduceMotion) {
            typed = lineOne.length to lineTwo.length
            set(Beat.idle, Transition(0f, 1f, easeOutSeconds = 0.3f))
            end(after = 0.3)
            return
        }
        // Low Power Mode: only ◇7's fold survives, 0.4s, and nothing before it.
        if (lowPower) {
            typed = lineOne.length to lineTwo.length
            set(Beat.key, null)
            set(Beat.idle, Transition(0.4f, 0.82f))
            end(after = 0.6)
            return
        }
        task = scope.launch { run() }
    }

    private suspend fun run() {
        for (step in listOf(Beat.core, Beat.sweep, Beat.alive, Beat.type, Beat.lime, Beat.key,
            Beat.top, Beat.stagger, Beat.input, Beat.idle)) {
            val wait = step.at - beat.at
            delay((wait * 1000).toLong())
            if (!playing) return
            when (step) {
                // ⚠️ One view, animating frame and cornerRadius. Not a cross-fade between two.
                Beat.key -> set(step, Transition(0.62f, 0.82f))
                // The top bar, the tiles and the dock share one spring and differ only in when.
                Beat.top, Beat.stagger, Beat.input -> set(step, Transition(0.34f, 0.82f))
                else -> set(step, null)
            }
            // The typing runs alongside the beats, not inside them.
            if (step == Beat.type) scope.launch { type(1, lineOne) }
            if (step == Beat.lime) scope.launch {
                // 0.4s of silence between the two lines — the whole point of the pause.
                delay(400)
                type(2, lineTwo)
            }
        }
        end(after = 0.0)
    }

    /** 28ms a character. Not an opacity animation, and not a sequence of images. */
    private suspend fun type(line: Int, text: String) {
        for (n in 1..text.length) {
            if (!playing) return
            typed = if (line == 1) n to typed.second else typed.first to n
            delay(28)
        }
    }

    /** Any tap at all lands on ◇11 — no "skip?" prompt. */
    fun skip() {
        if (!playing || beat >= Beat.idle) return
        task?.cancel()
        typed = lineOne.length to lineTwo.length
        set(Beat.idle, Transition(0.42f, 0.86f))
        end(after = 0.42)
    }

    private fun end(after: Double) {
        scope.launch {
            delay((after * 1000).toLong())
            finish()
        }
    }

    private fun finish() {
        task?.cancel()
        playing = false
        beat = Beat.idle
    }

    // MARK: what the layout asks it

    /** ◇7 · the panel is the whole screen until the fold, then it is 358 × 470. */
    val panelIsFullScreen: Boolean get() = playing && beat < Beat.key
    val panelRadius: Dp get() = if (panelIsFullScreen) 44.dp else NB.R.hero
    val coreLit: Boolean get() = !playing || beat >= Beat.core
    val orbitFraction: Double get() = if (!playing) 1.0 else if (beat >= Beat.sweep) 1.0 else 0.0
    val orbitSpinning: Boolean get() = !playing || beat >= Beat.alive
    val hairlineOpen: Boolean get() = !playing || beat >= Beat.type
    /** The dock cannot be pressed before ◇10 — and when it cannot, it is simply not there. */
    val chromeVisible: Boolean get() = !playing || beat >= Beat.top
    val tilesVisible: Boolean get() = !playing || beat >= Beat.stagger
    val dockVisible: Boolean get() = !playing || beat >= Beat.input
    val indicatorVisible: Boolean get() = !playing || beat >= Beat.idle
    val statusBarHidden: Boolean get() = playing && beat < Beat.top
}

/**
 * ◇2–◇4 · the core, the orbit and the planet, as one layer that is never rebuilt.
 * After the fold this same view is what the panel draws — it is not replaced, so the
 * field does not restart and does not blink.
 */
@Composable
fun FirstRunArt(
    coreLit: Boolean,
    orbitFraction: Double,
    spinning: Boolean,
    modifier: Modifier = Modifier,
) {
    var clock by remember { mutableDoubleStateOf(0.0) }
    var sweep by remember { mutableDoubleStateOf(0.0) }
    val fraction by rememberUpdatedState(orbitFraction)
    val spin by rememberUpdatedState(spinning)
    LaunchedEffect(Unit) {
        var last = -1L
        while (true) withFrameNanos { now ->
            val dt = if (last < 0) 0.0 else min((now - last) / 1e9, 1.0 / 20)
            last = now
            // ◇3 · the sweep is drawn, not faded: 0…1 over 0.8s.
            if (fraction > 0) sweep = min(1.0, sweep + dt / 0.8)
            // ◇4 · from here the field never stops. 90 seconds a revolution.
            if (spin) clock += dt
        }
    }
    Canvas(modifier.fillMaxSize()) {
        OrbitField(
            clock = clock,
            arrival = 1 - (1 - sweep).pow(2),   // ease-out
            coreLit = coreLit,
            moving = spinning,
        ).draw(this)
    }
}

/** ◇5–◇6 · the subtitle. Line one types, drops to white, then line two comes in lime. */
@Composable
fun FirstRunSubtitle(typed: Pair<Int, Int>, bandPaired: Boolean, showsCursor: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            FirstRun.lineOne.take(typed.first),
            style = NBFont.dot(700, 20f).tracking(0.14f),
            // Line one steps back to white the moment line two starts.
            color = if (typed.second > 0) NB.white else NB.lime1,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(FirstRun.lineTwo.take(typed.second), style = NBFont.dot(700, 20f).tracking(0.14f), color = NB.lime1)
            // A lime square, and it does not blink: a dot screen has no need to.
            if (showsCursor) Box(Modifier.size(9.dp).background(NB.lime1))
        }
        Text(
            if (bandPaired) FirstRun.lineThree else FirstRun.lineThreeUnpaired,
            style = NBFont.dot(500, 11f).tracking(0.2f),
            color = NB.white.copy(alpha = 0.34f),
            modifier = Modifier.padding(top = 8.dp).alpha(if (typed.second == FirstRun.lineTwo.length) 1f else 0f),
        )
    }
}
