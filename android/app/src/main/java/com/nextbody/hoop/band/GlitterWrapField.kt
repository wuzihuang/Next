package com.nextbody.hoop.band

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.pow
import kotlin.math.sin

/**
 * Originkit Glitter Wrap — the THINKING field.
 *
 * Clock-stepped particle state. The panel paints the stamps this step emits;
 * tests sample the same structs. Live uses a random seed; tests pass a fixed one.
 */
data class GlitterWrapRGB(val r: Double, val g: Double, val b: Double) {
    companion object {
        fun hex(n: Long): GlitterWrapRGB = GlitterWrapRGB(
            r = ((n shr 16) and 0xFF).toDouble(),
            g = ((n shr 8) and 0xFF).toDouble(),
            b = (n and 0xFF).toDouble())
    }
}

data class GlitterWrapConfig(
    val particleCount: Int,
    val color1: GlitterWrapRGB,
    val color2: GlitterWrapRGB,
    val color3: GlitterWrapRGB,
    val speed: Double,
    val density: Double,
    val starSize: Double,
    val focalDepth: Double,
    val turbulence: Double,
    val brightness: Double,
    val glitterIntensity: Double,
    val trailAmount: Double,
    val reverse: Boolean,
) {
    val palette: List<GlitterWrapRGB> get() = listOf(color1, color2, color3)

    companion object {
        /** Originkit wrap, retimed to the panel: white / cool gray / lime, not the stock red. */
        val thinking = GlitterWrapConfig(
            particleCount = 773,
            color1 = GlitterWrapRGB.hex(0xFFFFFF),
            color2 = GlitterWrapRGB.hex(0xB0B0BA),
            color3 = GlitterWrapRGB.hex(0xEFF65A),
            speed = 4.0, density = 77.0, starSize = 18.0, focalDepth = 7.0, turbulence = 0.0,
            brightness = 100.0, glitterIntensity = 3.0, trailAmount = 67.0, reverse = true)
    }
}

/** Derived quantities the Originkit `cfg()` closure computes each frame. */
data class GlitterWrapDerived(
    val reverse: Boolean,
    val density: Double,
    val stepZ: Double,
    val focalDepth: Double,
    val starScale: Double,
    val turbulence: Double,
    val glitter: Double,
    val brightness: Double,
    val trail: Double,
) {
    constructor(c: GlitterWrapConfig) : this(
        reverse = c.reverse,
        density = c.density,
        stepZ = c.speed * 0.0008,
        focalDepth = c.focalDepth / 100,
        starScale = c.starSize * 0.15,
        turbulence = c.turbulence * 0.2,
        glitter = c.glitterIntensity * 0.1,
        brightness = minOf(1.0, c.brightness / 100),
        trail = c.trailAmount / 100)
}

data class GlitterWrapStar(
    var x: Double,
    var y: Double,
    var z: Double,
    var px: Double?,
    var py: Double?,
    var seed: Double,
    var vmul: Double,
    var colorIdx: Int,
    var flashUntil: Double,
    var nextFlash: Double,
)

data class GlitterWrapStamp(
    val sx: Double,
    val sy: Double,
    val px: Double?,
    val py: Double?,
    val r: Double,
    val haloR: Double?,
    val alpha: Double,
    val colorIdx: Int,
    val flashMult: Double,
)

data class GlitterWrapFrame(val stamps: List<GlitterWrapStamp>, val trailAlpha: Double)

data class GlitterWrapProjection(val sx: Double, val sy: Double, val radius: Double)

/** SplitMix64. `unit()` is `[0, 1)`, the same interval as `Math.random()`. */
class GlitterWrapRNG(seed: ULong) {
    private var state: ULong = if (seed == 0uL) 0x9E3779B97F4A7C15uL else seed

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    fun unit(): Double = (next() shr 11).toDouble() * 2.0.pow(-53)
}

class GlitterWrapField(
    val config: GlitterWrapConfig = GlitterWrapConfig.thinking,
    seed: ULong,
    var width: Double = 358.0,
    var height: Double = 470.0,
) {
    private val _stars = mutableListOf<GlitterWrapStar>()
    val stars: List<GlitterWrapStar> get() = _stars
    var elapsed: Double = 0.0
        private set
    private val rng = GlitterWrapRNG(seed)
    private val derived = GlitterWrapDerived(config)

    init { syncCount() }

    /** Flattened star state. Two clocks compare equal only when the field did not step. */
    fun samples(): List<Double> = _stars.flatMap { s ->
        listOf(s.x, s.y, s.z, s.vmul, s.colorIdx.toDouble(), s.seed, s.flashUntil, s.nextFlash)
    }

    /** One Originkit `drawFrame`. `moving: false` freezes the pose (Reduce Motion). */
    fun step(deltaSec: Double, moving: Boolean = true): GlitterWrapFrame {
        if (!moving) return GlitterWrapFrame(stamps = snapshot(scheduleFlash = false), trailAlpha = 0.0)
        syncCount()
        val d = derived
        val dt = frameDt(deltaSec)
        val w = maxOf(1.0, width); val h = maxOf(1.0, height)
        val cx = w / 2; val cy = h / 2
        val projScale = minOf(w, h) * 0.9
        val stamps = ArrayList<GlitterWrapStamp>(_stars.size)

        for (s in _stars) {
            val vz = d.stepZ * s.vmul * dt
            if (d.reverse) {
                s.z += vz
                if (s.z >= 1.0) { resetStar(s, initial = false); continue }
            } else {
                s.z -= vz
                if (s.z <= d.focalDepth) { resetStar(s, initial = false); continue }
            }

            var tx = s.x
            var ty = s.y
            if (d.turbulence > 0) {
                val t = elapsed * 1.2 + s.seed
                val amp = d.turbulence * (1 - s.z) * 0.25
                tx += sin(t + s.seed) * amp
                ty += cos(t * 1.13 + s.seed * 0.7) * amp
            }

            val persp = d.focalDepth / maxOf(s.z, 0.0001)
            val sx = cx + tx * persp * projScale
            val sy = cy + ty * persp * projScale

            if (!d.reverse && (sx < -20 || sx > w + 20 || sy < -20 || sy > h + 20)) {
                resetStar(s, initial = false); continue
            }

            val flashMult = flash(s, schedule = true)
            stamps.add(stamp(s, sx, sy, flashMult, d))
            s.px = sx
            s.py = sy
        }

        elapsed += minOf(0.1, maxOf(0.0, deltaSec))
        return GlitterWrapFrame(stamps = stamps, trailAlpha = trailAlpha(config.trailAmount, deltaSec))
    }

    private fun snapshot(scheduleFlash: Boolean): List<GlitterWrapStamp> {
        val d = derived
        val w = maxOf(1.0, width); val h = maxOf(1.0, height)
        val cx = w / 2; val cy = h / 2
        val projScale = minOf(w, h) * 0.9
        val stamps = ArrayList<GlitterWrapStamp>(_stars.size)
        for (i in _stars.indices) {
            val s = if (scheduleFlash) _stars[i] else _stars[i].copy()
            var tx = s.x
            var ty = s.y
            if (d.turbulence > 0) {
                val t = elapsed * 1.2 + s.seed
                val amp = d.turbulence * (1 - s.z) * 0.25
                tx += sin(t + s.seed) * amp
                ty += cos(t * 1.13 + s.seed * 0.7) * amp
            }
            val persp = d.focalDepth / maxOf(s.z, 0.0001)
            val sx = cx + tx * persp * projScale
            val sy = cy + ty * persp * projScale
            val flashMult = flash(s, schedule = scheduleFlash)
            stamps.add(stamp(s, sx, sy, flashMult, d))
        }
        return stamps
    }

    private fun flash(s: GlitterWrapStar, schedule: Boolean): Double {
        val glitter = derived.glitter
        if (glitter <= 0) return 1.0
        if (schedule && elapsed >= s.nextFlash && s.flashUntil < elapsed) {
            s.flashUntil = elapsed + 0.04 + rng.unit() * 0.07
            s.nextFlash = elapsed + 1 + rng.unit() * 4 * (1 / maxOf(0.0001, glitter))
        }
        return if (elapsed <= s.flashUntil) 1 + 2.5 * glitter else 1.0
    }

    private fun stamp(s: GlitterWrapStar, sx: Double, sy: Double, flashMult: Double, d: GlitterWrapDerived): GlitterWrapStamp {
        val sizePersp = minOf(2.5, (d.focalDepth / maxOf(s.z, 0.0001)) * 0.6)
        val baseR = maxOf(0.25, d.starScale * (0.4 + sizePersp))
        val maxR = 1 + d.starScale * 2.5
        val gain = edgeGain(sx, sy, width, height)
        val bloom = 1 + (1 - gain) * 1.6
        val r = minOf(baseR * flashMult * bloom, maxR * 2.2)
        val lifeT = if (d.reverse) s.z else 1 - s.z
        val fadeIn = if (d.reverse) minOf(1.0, (s.z - d.focalDepth) / (1 - d.focalDepth) / 0.12) else 1.0
        val a = minOf(1.0, if (d.reverse) 0.85 - lifeT * 0.6 else lifeT * 0.9 + 0.05) *
            fadeIn * d.brightness * (if (flashMult > 1) 1.0 else 0.85) * gain
        val halo: Double? = if (flashMult > 1 || gain < 0.85) minOf(r * 1.4, maxR * 2.4) else null
        return GlitterWrapStamp(sx = sx, sy = sy, px = s.px, py = s.py, r = r, haloR = halo, alpha = a,
            colorIdx = s.colorIdx, flashMult = flashMult)
    }

    private fun syncCount() {
        val count = maxOf(1, config.particleCount)
        if (_stars.size == count) return
        if (_stars.size > count) {
            repeat(_stars.size - count) { _stars.removeAt(_stars.size - 1) }
            return
        }
        while (_stars.size < count) {
            val s = GlitterWrapStar(x = 0.0, y = 0.0, z = 0.0, px = null, py = null,
                seed = 0.0, vmul = 1.0, colorIdx = 0, flashUntil = 0.0, nextFlash = 0.0)
            resetStar(s, initial = true)
            _stars.add(s)
        }
    }

    private fun resetStar(s: GlitterWrapStar, initial: Boolean) {
        val d = derived
        val angle = rng.unit() * PI * 2
        val radius = (0.2 + rng.unit() * 0.8) * (d.density / 15)
        s.x = cos(angle) * radius
        s.y = sin(angle) * radius
        s.z = if (d.reverse) {
            if (initial) d.focalDepth + rng.unit() * (1 - d.focalDepth) else d.focalDepth
        } else {
            if (initial) rng.unit() else 1.0
        }
        s.px = null
        s.py = null
        s.seed = rng.unit() * 1000
        s.vmul = 0.6 + rng.unit() * 0.8
        s.colorIdx = (rng.unit() * 3).toInt()
        s.flashUntil = 0.0
        s.nextFlash = elapsed + 1 + rng.unit() * 4 * (1 / maxOf(0.0001, d.glitter))
    }

    companion object {
        /** Originkit `dt = clamp(deltaSec, 0.001, 0.1) * 60`. */
        fun frameDt(deltaSec: Double): Double = maxOf(0.001, minOf(0.1, deltaSec)) * 60

        /** `keep = pow(min(0.98, max(0, trail)), dt)` with `trail = trailAmount / 100`. */
        fun trailKeep(trailAmount: Double, deltaSec: Double): Double {
            val trail = trailAmount / 100
            val dt = frameDt(deltaSec)
            return minOf(0.98, maxOf(0.0, trail)).pow(dt)
        }

        fun trailAlpha(trailAmount: Double, deltaSec: Double): Double =
            maxOf(0.02, 1 - trailKeep(trailAmount, deltaSec))

        /** Elliptical falloff so the field dissolves before this slot's rect clip. */
        fun edgeGain(x: Double, y: Double, width: Double, height: Double): Double {
            val w = maxOf(1.0, width); val h = maxOf(1.0, height)
            val nx = (x - w / 2) / (w * 0.54)
            val ny = (y - h / 2) / (h * 0.46)
            return 1 - smoothstep(0.62, 1.08, hypot(nx, ny))
        }

        fun smoothstep(edge0: Double, edge1: Double, x: Double): Double {
            val t = maxOf(0.0, minOf(1.0, (x - edge0) / maxOf(1e-9, edge1 - edge0)))
            return t * t * (3 - 2 * t)
        }

        /** Perspective `focalDepth / z`. Reverse motion increases `z`, so radius shrinks. */
        fun project(x: Double, y: Double, z: Double, width: Double, height: Double, focalDepth: Double): GlitterWrapProjection {
            val w = maxOf(1.0, width); val h = maxOf(1.0, height)
            val cx = w / 2; val cy = h / 2
            val projScale = minOf(w, h) * 0.9
            val persp = focalDepth / maxOf(z, 0.0001)
            val sx = cx + x * persp * projScale
            val sy = cy + y * persp * projScale
            return GlitterWrapProjection(sx = sx, sy = sy, radius = hypot(sx - cx, sy - cy))
        }
    }
}
