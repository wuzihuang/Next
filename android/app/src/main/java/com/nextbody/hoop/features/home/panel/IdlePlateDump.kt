package com.nextbody.hoop.features.home.panel

import com.nextbody.hoop.features.home.DeepSpacePlate

import android.util.Log
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.IdlePlateMotion
import com.nextbody.hoop.data.DebugEnv
import kotlin.math.max
import kotlin.math.min

/**
 * DEBUG · `NB_DUMP_PLATES=1` plus optional `NB_DUMP_PLATE=1…28` holds the real deep-space
 * renderer on the window for a screenshot. `NB_DUMP_CLOCK` selects an exact still;
 * `NB_DUMP_LIVE=1` advances it for video. (iOS reads these from `SIMCTL_CHILD_*`; here from
 * the debug launch extras behind [DebugEnv].)
 */
object IdlePlateDump {
    val requested: Boolean
        get() {
            if (!BuildConfig.DEBUG) return false
            val raw = DebugEnv["NB_DUMP_PLATES"] ?: return false
            return raw.isNotEmpty()
        }

    val plate: Int
        get() {
            val raw = DebugEnv["NB_DUMP_PLATE"]?.toIntOrNull() ?: 1
            return min(28, max(1, raw))
        }

    val clock: Double get() = DebugEnv["NB_DUMP_CLOCK"]?.toDoubleOrNull() ?: 0.0

    val live: Boolean get() = DebugEnv["NB_DUMP_LIVE"] == "1"
}

/**
 * Root overlay (RootView `.overlay { IdlePlateDumpOverlay() }`): nothing unless a DEBUG dump
 * was requested.
 *
 * Draws `DeepSpacePlate`, as iOS does.
 */
@Composable
fun IdlePlateDumpOverlay() {
    if (!IdlePlateDump.requested) return
    val plate = IdlePlateDump.plate
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateAsState()
    val moving = IdlePlateDump.live && state.isAtLeast(Lifecycle.State.RESUMED)
    var elapsed by remember { mutableDoubleStateOf(0.0) }

    DisposableEffect(Unit) {
        Log.i("debug", "idle plate dump showing plate=$plate")
        onDispose { }
    }
    LaunchedEffect(moving) {
        if (!moving) return@LaunchedEffect
        var lastTick: Long? = null
        while (true) {
            withFrameNanos { now ->
                val previous = lastTick
                if (previous == null) lastTick = now
                else {
                    val dt = (now - previous) / 1_000_000_000.0
                    if (dt >= 1.0 / 30 - 0.002) {
                        lastTick = now
                        elapsed += min(max(0.0, dt), 0.1)
                    }
                }
            }
        }
    }

    Box(Modifier.fillMaxSize().background(col(0x070709)), contentAlignment = Alignment.Center) {
        DeepSpacePlate(plate = plate, clock = IdlePlateDump.clock + elapsed, modifier = Modifier.size(358.dp, 470.dp))
    }
}
