package com.nextbody.hoop.features.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.random.Random

/**
 * Originkit's Grain Mass behind the panel's THINKING slot.
 *
 * iOS runs `GrainMass.html` (WebGL2) in a WKWebView. Here the same simulation runs natively:
 * the seeds (golden-spiral shell, cube-root radius), the lumpy rest shape, the spring toward it,
 * the two-octave curl-noise boil, the 45° tilt with the slow yaw and wobble, the 42° camera,
 * the four-colour palette picked by value noise, the key/fill form light and the two-second
 * boot flare — on a transparent ground, coverage following brightness. The GPU's 65k points
 * are 4,096 here and the bloom is a soft additive halo on the bright grains.
 */
@Composable
fun GrainMassBackground(modifier: Modifier = Modifier) {
    val reduced = rememberReduceMotion()
    val mass = remember { GrainMass() }
    var active by remember { mutableStateOf(true) }
    var frame by remember { mutableIntStateOf(0) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, _ ->
            active = owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    LaunchedEffect(active, reduced) {
        if (!active) return@LaunchedEffect
        if (reduced) { mass.step(0.0, still = true); frame++; return@LaunchedEffect }
        var last = -1L
        while (true) withFrameNanos { now ->
            val dt = if (last < 0) 0.0 else ((now - last) / 1e9).coerceIn(0.0, 1.0 / 30)
            last = now
            mass.step(dt, still = false)
            frame++
        }
    }
    Canvas(modifier.fillMaxSize().clearAndSetSemantics { }) {
        @Suppress("UNUSED_EXPRESSION") frame
        mass.draw(this)
    }
}

private class GrainMass {
    private val side = 64
    private val n = side * side
    private val seed = FloatArray(n * 4)
    private val pos = FloatArray(n * 3)
    private val vel = FloatArray(n * 3)
    private val base = FloatArray(n * 3)
    private val color = IntArray(n)
    private val ao = FloatArray(n)
    private val out0 = FloatArray(n)
    private var clock = 0.0
    private var yaw = 0.0
    private var reset = true
    private var stillFrame = false
    private val spring = 5 + (1.3 / 10).pow(1.5) * 65
    private val damp = exp(-1.7 * sqrt(spring) / 60)

    // Projected, per frame.
    private val sx = FloatArray(n); private val sy = FloatArray(n); private val sw = FloatArray(n)
    private val shade = FloatArray(n)
    private var order = (0 until n).toList().toTypedArray()

    private val colors = arrayOf(
        floatArrayOf(239 / 255f, 246 / 255f, 90 / 255f),
        floatArrayOf(170 / 255f, 0f, 1f),
        floatArrayOf(67 / 255f, 0f, 1f),
        floatArrayOf(99 / 255f, 186 / 255f, 1f),
    )
    private val glows = floatArrayOf(1.24f, 2f, 2f, 2f)
    private val bounce = FloatArray(3) { i -> (colors[0][i] + colors[1][i] + colors[2][i] + colors[3][i]) / 4 }
    private val lx: Float; private val ly: Float; private val lz: Float

    init {
        val ll = sqrt(0.55f * 0.55f + 0.62f * 0.62f + 0.52f * 0.52f)
        lx = -0.55f / ll; ly = 0.62f / ll; lz = 0.52f / ll
        val golden = PI * (3 - sqrt(5.0))
        val jitter = 2 / sqrt(n.toDouble()) * 0.33
        val rng = Random(0x6A1A)
        for (i in 0 until n) {
            val z = 1 - 2 * (i + 0.5) / n
            val rxy = sqrt(max(0.0, 1 - z * z))
            val phi = golden * i
            val x = cos(phi) * rxy + (rng.nextDouble() * 2 - 1) * jitter
            val y = sin(phi) * rxy + (rng.nextDouble() * 2 - 1) * jitter
            val zz = z + (rng.nextDouble() * 2 - 1) * jitter
            val len = sqrt(x * x + y * y + zz * zz).takeIf { it > 0 } ?: 1.0
            val r = cbrt(0.35 + 0.65 * rng.nextDouble())
            seed[i * 4] = (x / len * r).toFloat(); seed[i * 4 + 1] = (y / len * r).toFloat()
            seed[i * 4 + 2] = (zz / len * r).toFloat(); seed[i * 4 + 3] = rng.nextFloat()
        }
        for (i in 0 until n) {
            val s0 = seed[i * 4]; val s1 = seed[i * 4 + 1]; val s2 = seed[i * 4 + 2]; val w = seed[i * 4 + 3]
            val l = sqrt(s0 * s0 + s1 * s1 + s2 * s2) + 1e-5f
            val dx = s0 / l; val dy = s1 / l; val dz = s2 / l
            val o = smooth(0.93f, 1f, w)
            out0[i] = o
            val lump = shapeLump(dx, dy, dz)
            val k = lump * (1 + o * 0.9f * 0.65f)
            base[i * 3] = s0 * k; base[i * 3 + 1] = s1 * k; base[i * 3 + 2] = s2 * k
            var m = 0.66f * vnoise(s0 * 1.75f + 7.31f, s1 * 1.75f + 7.31f, s2 * 1.75f + 7.31f) +
                0.34f * vnoise(s0 * 1.75f * 2.1f + 7.31f * 1.7f + 5f, s1 * 1.75f * 2.1f + 7.31f * 1.7f + 5f, s2 * 1.75f * 2.1f + 7.31f * 1.7f + 5f)
            m = smooth(0.30f, 0.70f, m)
            color[i] = floor(m * 4f).toInt().coerceIn(0, 3)
            ao[i] = smooth(0.50f, 1.15f, lump)
        }
    }

    fun step(dt: Double, still: Boolean) {
        stillFrame = still
        clock += dt
        if (!still) yaw += 0.5 * dt
        if (reset) {
            for (i in 0 until n) {
                val s0 = seed[i * 4]; val s1 = seed[i * 4 + 1]; val s2 = seed[i * 4 + 2]; val w = seed[i * 4 + 3]
                val l = sqrt(s0 * s0 + s1 * s1 + s2 * s2) + 1e-5f
                val f = if (still) 1f else 0.55f
                for (a in 0..2) pos[i * 3 + a] = base[i * 3 + a] * f
                val sp = if (still) 0f else 2f * (0.5f + 0.9f * w)
                vel[i * 3] = s0 / l * sp; vel[i * 3 + 1] = s1 / l * sp; vel[i * 3 + 2] = s2 / l * sp
            }
            reset = false
            return
        }
        if (still) return
        val fdt = dt.toFloat()
        val t = clock.toFloat()
        val dampK = damp.pow(dt * 60).toFloat()
        val c = FloatArray(3); val c2 = FloatArray(3)
        for (i in 0 until n) {
            val o = out0[i]; val loose = o * 0.9f
            val k = (spring * (1.0 - 0.55 * o)).toFloat()
            val px = pos[i * 3]; val py = pos[i * 3 + 1]; val pz = pos[i * 3 + 2]
            var vx = vel[i * 3] + (base[i * 3] - px) * k * fdt
            var vy = vel[i * 3 + 1] + (base[i * 3 + 1] - py) * k * fdt
            var vz = vel[i * 3 + 2] + (base[i * 3 + 2] - pz) * k * fdt
            curl(px * 1.35f, py * 1.35f + t * 0.11f, pz * 1.35f, c)
            curl(px * 1.35f * 2.35f + 19.7f, py * 1.35f * 2.35f + 3.1f, pz * 1.35f * 2.35f - 7.4f, c2)
            val g = 0.12f * k * (1 + loose * 0.8f) * fdt
            vx += (c[0] + 0.48f * c2[0]) * g; vy += (c[1] + 0.48f * c2[1]) * g; vz += (c[2] + 0.48f * c2[2]) * g
            vx *= dampK; vy *= dampK; vz *= dampK
            vel[i * 3] = vx; vel[i * 3 + 1] = vy; vel[i * 3 + 2] = vz
            pos[i * 3] = px + vx * fdt; pos[i * 3 + 1] = py + vy * fdt; pos[i * 3 + 2] = pz + vz * fdt
        }
    }

    fun draw(scope: androidx.compose.ui.graphics.drawscope.DrawScope) = with(scope) {
        if (size.width < 1 || size.height < 1) return@with
        val w = size.width; val h = size.height
        val dpr = min(density, 2f)
        val phase = if (stillFrame) 0.42 else min(clock / 2.0, 1.0) * 0.42
        val fade = smooth(0f, 0.055f, phase.toFloat())
        val flare = 1 + 1.15f * (1 - smooth(0f, 0.1f, phase.toFloat()))
        val aspect = w / h
        val minHalf = 1.4 * 100 / 104
        val tanHalf = tan(42 * PI / 360)
        val dist = if (aspect >= 1) minHalf / tanHalf else minHalf / (aspect * tanHalf)
        val f = (1 / tanHalf).toFloat()
        // orientation(π/4, yaw, wobble) · column-major, as the shader reads it.
        val tilt = PI / 4; val wob = sin(clock * 0.13) * 0.08
        val cz = cos(tilt).toFloat(); val sz = sin(tilt).toFloat()
        val cy = cos(yaw).toFloat(); val syw = sin(yaw).toFloat()
        val cx = cos(wob).toFloat(); val sxw = sin(wob).toFloat()
        val m0 = floatArrayOf(cz * cy, sz * cy, -syw)
        val m1 = floatArrayOf(cz * syw * sxw - sz * cx, sz * syw * sxw + cz * cx, cy * sxw)
        val m2 = floatArrayOf(cz * syw * cx + sz * sxw, sz * syw * cx - cz * sxw, cy * cx)
        val pointScale = 1.5f * dpr * dist.toFloat() * (density / dpr)
        for (i in 0 until n) {
            val px = pos[i * 3]; val py = pos[i * 3 + 1]; val pz = pos[i * 3 + 2]
            val rx = m0[0] * px + m1[0] * py + m2[0] * pz
            val ry = m0[1] * px + m1[1] * py + m2[1] * pz
            val rz = m0[2] * px + m1[2] * py + m2[2] * pz
            val cw = (dist.toFloat() - rz)
            sw[i] = cw
            sx[i] = (f / aspect * rx / cw * 0.5f + 0.5f) * w
            sy[i] = (0.5f - f * ry / cw * 0.5f) * h
            // macro normal → form light
            val l = sqrt(rx * rx + ry * ry + rz * rz) + 1e-5f
            val nx = rx / l; val ny = ry / l; val nz = rz / l
            val key = ((nx * lx + ny * ly + nz * lz + 0.35f) / 1.35f).coerceIn(0f, 1f)
            shade[i] = 0.10f + 0.62f * key + 0.28f * max(0f, nz)
        }
        // Painter's order stands in for the depth test: far grains first.
        order.sortByDescending { sw[it] }
        val micro = 0.648f
        for (i in order) {
            val cw = sw[i]
            if (cw <= 0.01f) continue
            val jitter = 0.70f + 0.62f * seed[i * 4 + 3]
            val r = (pointScale * jitter / cw).coerceIn(1f, 48f) / 2f
            val col = colors[color[i]]
            val form = shade[i]
            val s = form * (0.55f + 0.45f * micro)
            val a = 0.35f + 0.65f * ao[i]
            val dim = 1 - max(col[0], max(col[1], col[2])).coerceIn(0f, 1f)
            val mixK = smooth(0.05f, 0.60f, s)
            val rgb = FloatArray(3)
            val warm = floatArrayOf(0.34f, 0.2f, 0.09f)
            for (k in 0..2) {
                val bodyC = col[k] * (warm[k] + (1 - warm[k]) * mixK)
                var v = bodyC * (0.10f + 1.75f * s) * a + col[k] * dim * (0.30f + 0.55f * s) * a +
                    bounce[k] * 0.34f * dim * s * a
                v *= flare * fade
                rgb[k] = v
            }
            val mx = max(rgb[0], max(rgb[1], rgb[2]))
            val bloom = max(mx - 0.45f, 0f) / max(mx, 1e-4f) * glows[color[i]] * fade
            val tm = 1 + mx * 0.55f
            val outR = (rgb[0] / tm).coerceIn(0f, 1f); val outG = (rgb[1] / tm).coerceIn(0f, 1f); val outB = (rgb[2] / tm).coerceIn(0f, 1f)
            val alpha = (max(outR, max(outG, outB)) * 1.35f).coerceIn(0f, 1f)
            val center = Offset(sx[i], sy[i])
            if (bloom > 0.02f) {
                drawCircle(
                    Brush.radialGradient(listOf(Color(outR, outG, outB, (0.35f * bloom).coerceIn(0f, 1f)), Color.Transparent),
                        center = center, radius = r * 5f),
                    radius = r * 5f, center = center, blendMode = BlendMode.Plus,
                )
            }
            drawCircle(Color(outR, outG, outB, alpha), radius = r, center = center)
        }
    }

    // MARK: noise (the html's NOISE block)

    private fun hash13(x: Float, y: Float, z: Float): Float {
        var px = fract(x * 0.1031f); var py = fract(y * 0.1031f); var pz = fract(z * 0.1031f)
        val d = px * (pz + 31.32f) + py * (py + 31.32f) + pz * (px + 31.32f)
        px += d; py += d; pz += d
        return fract((px + py) * pz)
    }

    private fun fract(v: Float): Float = v - floor(v)

    /** Value noise with its analytic gradient: out = (v, dx, dy, dz). */
    private fun vnoised(x: Float, y: Float, z: Float, out: FloatArray) {
        val ix = floor(x); val iy = floor(y); val iz = floor(z)
        val wx = x - ix; val wy = y - iy; val wz = z - iz
        fun q(w: Float) = w * w * w * (w * (w * 6 - 15) + 10)
        fun dq(w: Float) = 30 * w * w * (w * (w - 2) + 1)
        val ux = q(wx); val uy = q(wy); val uz = q(wz)
        val a = hash13(ix, iy, iz); val b = hash13(ix + 1, iy, iz)
        val c = hash13(ix, iy + 1, iz); val d = hash13(ix + 1, iy + 1, iz)
        val e = hash13(ix, iy, iz + 1); val f = hash13(ix + 1, iy, iz + 1)
        val g = hash13(ix, iy + 1, iz + 1); val h = hash13(ix + 1, iy + 1, iz + 1)
        val k0 = a; val k1 = b - a; val k2 = c - a; val k3 = e - a
        val k4 = a - b - c + d; val k5 = a - c - e + g; val k6 = a - b - e + f
        val k7 = -a + b + c - d + e - f - g + h
        out[0] = k0 + k1 * ux + k2 * uy + k3 * uz + k4 * ux * uy + k5 * uy * uz + k6 * uz * ux + k7 * ux * uy * uz
        out[1] = dq(wx) * (k1 + k4 * uy + k6 * uz + k7 * uy * uz)
        out[2] = dq(wy) * (k2 + k5 * uz + k4 * ux + k7 * uz * ux)
        out[3] = dq(wz) * (k3 + k6 * ux + k5 * uy + k7 * ux * uy)
    }

    private val n1 = FloatArray(4); private val n2 = FloatArray(4); private val n3 = FloatArray(4)

    private fun vnoise(x: Float, y: Float, z: Float): Float { vnoised(x, y, z, n1); return n1[0] }

    private fun curl(x: Float, y: Float, z: Float, out: FloatArray) {
        vnoised(x, y, z, n1)
        vnoised(x + 31.416f, y + 47.853f, z + 12.793f, n2)
        vnoised(x - 8.271f, y + 63.147f, z + 91.428f, n3)
        out[0] = n3[2] - n2[3]; out[1] = n1[3] - n3[1]; out[2] = n2[1] - n1[2]
    }

    private fun shapeLump(dx: Float, dy: Float, dz: Float): Float {
        var v = vnoise(dx * 0.75f + 11.3f, dy * 0.75f + 11.3f, dz * 0.75f + 11.3f)
        v += 0.55f * vnoise(dx * 1.90f + 47.9f, dy * 1.90f + 47.9f, dz * 1.90f + 47.9f)
        return 0.42f + 1.20f * (v / 1.55f)
    }

    private fun smooth(a: Float, b: Float, x: Float): Float {
        val t = ((x - a) / (b - a)).coerceIn(0f, 1f)
        return t * t * (3 - 2 * t)
    }
}
