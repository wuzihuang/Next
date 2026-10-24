package com.nextbody.hoop.features.sport

import android.graphics.Bitmap
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 14 · LIVE SESSION · the globe: one rectangle, one fragment shader, redrawn by the display
 * clock. A turning world, ordered-dithered through an 8×8 Bayer matrix in lime on the panel's
 * ink, its halo swelling on every beat and its lime warming to amber as effort climbs.
 *
 * Android 13+ runs the same shader as AGSL; older phones compute the cells on the CPU into a
 * cell-sized bitmap and scale it up unfiltered, so the picture is still made of square cells.
 *
 * `center` and `radius` are in the takeover's own dp, so the halo bleeds across the screen.
 */
@Composable
fun BayerGlobe(
    center: Offset,
    radius: Float,
    bpm: Int?,
    modifier: Modifier = Modifier,
    effort: Double = 0.0,
    turnRate: Double = 0.14,
    cell: Float = 5f,
    levels: Double = 5.0,
    landLevel: Double = 0.50,
    glowReach: Double = 1.95,
) {
    val reduceMotion = rememberReduceMotion()
    // Starts part-turned so the first frame is a composed one rather than the seam.
    val state = remember { GlobeClock() }
    val rate by rememberUpdatedState(turnRate)
    var frame by remember { mutableLongStateOf(0L) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        var last = 0L
        while (true) withFrameNanos { now ->
            // On-screen seconds, capped so a stall does not jump the world.
            val dt = if (last == 0L) 0.0 else min((now - last) / 1e9, 1.0 / 20)
            last = now
            state.clock += dt
            state.spin += dt * rate * 2 * PI
            frame = now
        }
    }
    val shader = remember { if (Build.VERSION.SDK_INT >= 33) GlobeShader.make() else null }
    // A shader the driver refuses falls back to the CPU picture rather than a blank screen.
    val cpu = remember { if (shader != null) null else GlobeCpu() }

    Canvas(modifier) {
        @Suppress("UNUSED_VARIABLE") val tick = frame
        val beat = if (reduceMotion) 0.0 else beatAt(state.clock, bpm)
        val d = density
        val params = GlobeParams(
            cx = center.x * d, cy = center.y * d, radius = radius * d, cell = cell * d,
            time = state.clock, spin = state.spin, beat = beat, landLevel = landLevel, levels = levels,
            glowReach = glowReach, effort = effort)
        if (shader != null && Build.VERSION.SDK_INT >= 33) {
            GlobeShader.bind(shader, params)
            drawRect(ShaderBrush(shader))
        } else if (cpu != null) {
            val bmp = cpu.render(size.width, size.height, params)
            drawImage(bmp.asImageBitmap(), srcOffset = IntOffset.Zero, srcSize = IntSize(bmp.width, bmp.height),
                dstOffset = IntOffset.Zero,
                dstSize = IntSize((bmp.width * params.cell).roundToInt(), (bmp.height * params.cell).roundToInt()),
                filterQuality = FilterQuality.None)
        }
    }
}

private class GlobeClock {
    var spin = 2.1
    var clock = 0.0
}

/** 0…1 · a sharp rise and an exponential fall once per beat, phased off the on-screen clock. */
private fun beatAt(t: Double, bpm: Int?): Double {
    if (bpm == null || bpm <= 0) return 0.0
    val period = 60.0 / bpm
    val phase = (t % period) / period
    return exp(-phase * 7)
}

private data class GlobeParams(
    val cx: Float, val cy: Float, val radius: Float, val cell: Float,
    val time: Double, val spin: Double, val beat: Double, val landLevel: Double, val levels: Double,
    val glowReach: Double, val effort: Double,
)

@RequiresApi(33)
private object GlobeShader {
    // The Metal shader, line for line, in AGSL. Bit operations are not available, so the
    // Bayer threshold is computed from the bits of x ^ y and y (the matrix's own recursion).
    const val SRC = """
uniform float2 center;
uniform float radius;
uniform float cell;
uniform float time;
uniform float spin;
uniform float beat;
uniform float landLevel;
uniform float levels;
uniform float glowReach;
uniform float effort;
layout(color) uniform half4 ink;
layout(color) uniform half4 lime;
layout(color) uniform half4 hot;
layout(color) uniform half4 ember;

float nb_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float nb_noise(float2 p) {
    float2 i = floor(p);
    float2 f = p - i;
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = nb_hash(i);
    float b = nb_hash(i + float2(1.0, 0.0));
    float c = nb_hash(i + float2(0.0, 1.0));
    float d = nb_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float nb_fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        v += nb_noise(p) * amp;
        p *= float2(2.03, 2.01);
        amp *= 0.5;
    }
    return v;
}

float nbBit(float v, float k) {
    return mod(floor(v / exp2(k)), 2.0);
}

float bayer8(float x, float y) {
    float m = 0.0;
    for (int i = 0; i < 3; i++) {
        float k = float(i);
        float xb = nbBit(x, k);
        float yb = nbBit(y, k);
        m += abs(xb - yb) * exp2(5.0 - 2.0 * k) + yb * exp2(4.0 - 2.0 * k);
    }
    return m;
}

half4 main(float2 position) {
    float2 cellIndex = floor(position / cell);
    float2 p = (cellIndex + 0.5) * cell;
    float dx = p.x - center.x;
    float dy = p.y - center.y;
    float rr = sqrt(dx * dx + dy * dy);
    float R = max(1.0, radius);
    float3 L = normalize(float3(-0.5, -0.4, 1.0));

    float v;
    if (rr < R) {
        float nx = dx / R;
        float ny = dy / R;
        float nz = sqrt(max(0.0, 1.0 - nx * nx - ny * ny));
        float lam = max(0.0, nx * L.x + ny * L.y + nz * L.z);
        float lon = atan(nx, nz) + spin;
        float lat = asin(clamp(ny, -1.0, 1.0));
        float land = nb_fbm(float2(lon * 1.6 + 10.0, lat * 2.2 + 5.0));
        float isLand = land > landLevel ? 1.0 : 0.56;
        float coast = abs(land - landLevel) < 0.035 ? 0.22 + 0.14 * beat : 0.0;
        float lit = 0.30 + 0.80 * lam;
        v = lit * isLand + coast;
        float limb = smoothstep(0.80, 1.0, rr / R);
        v += limb * (0.08 + (0.10 + 0.14 * effort) * beat);
    } else {
        float d = (rr - R) / (R * glowReach);
        float halo = max(0.0, 1.0 - d);
        float rim = exp(-(rr - R) / (R * 0.06));
        v = halo * halo * halo * (0.085 + (0.07 + 0.10 * effort) * beat)
          + rim * (0.24 + (0.18 + 0.22 * effort) * beat);
    }

    float shift = floor(time * 4.0);
    float mx = mod(cellIndex.x + shift, 8.0);
    float my = mod(cellIndex.y + shift, 8.0);
    float m = bayer8(mx, my) / 64.0 - 0.5;

    float last = max(1.0, levels - 1.0);
    float idx = clamp(floor(v * last + m + 0.5), 0.0, last);
    float f = idx / last;
    half4 tone = mix(lime, ember, half(smoothstep(0.35, 0.95, effort)));
    half4 to = (idx >= last && levels > 2.0) ? hot : tone;
    half4 outc = mix(ink, to, half(f));
    outc.a = 1.0;
    return outc;
}
"""

    fun make(): RuntimeShader? = runCatching { RuntimeShader(SRC) }.getOrNull()

    fun bind(s: RuntimeShader, p: GlobeParams) {
        s.setFloatUniform("center", p.cx, p.cy)
        s.setFloatUniform("radius", p.radius)
        s.setFloatUniform("cell", p.cell)
        s.setFloatUniform("time", p.time.toFloat())
        s.setFloatUniform("spin", (p.spin % (2 * PI * 1000)).toFloat())
        s.setFloatUniform("beat", p.beat.toFloat())
        s.setFloatUniform("landLevel", p.landLevel.toFloat())
        s.setFloatUniform("levels", p.levels.toFloat())
        s.setFloatUniform("glowReach", p.glowReach.toFloat())
        s.setFloatUniform("effort", p.effort.toFloat())
        s.setColorUniform("ink", NB.panelInk.toArgb())
        s.setColorUniform("lime", NB.lime1.toArgb())
        s.setColorUniform("hot", NB.limePale.toArgb())
        s.setColorUniform("ember", NB.ember1.toArgb())
    }
}

/** The same picture on the CPU, one pixel per cell. */
private class GlobeCpu {
    private var bitmap: Bitmap? = null
    private var pixels = IntArray(0)

    fun render(width: Float, height: Float, p: GlobeParams): Bitmap {
        val cols = max(1, ceil(width / p.cell).toInt())
        val rows = max(1, ceil(height / p.cell).toInt())
        var bmp = bitmap
        if (bmp == null || bmp.width != cols || bmp.height != rows) {
            bmp = Bitmap.createBitmap(cols, rows, Bitmap.Config.ARGB_8888)
            bitmap = bmp
            pixels = IntArray(cols * rows)
        }
        val ink = NB.panelInk; val lime = NB.lime1; val hot = NB.limePale; val ember = NB.ember1
        val warm = smoothstep(0.35, 0.95, p.effort).toFloat()
        val tone = lerp(lime, ember, warm)
        val lx = -0.5; val ly = -0.4; val lz = 1.0
        val ll = sqrt(lx * lx + ly * ly + lz * lz)
        val shift = floor(p.time * 4).toInt()
        val last = max(1.0, p.levels - 1)
        val r = max(1.0, p.radius.toDouble())
        for (row in 0 until rows) {
            for (col in 0 until cols) {
                val px = (col + 0.5) * p.cell
                val py = (row + 0.5) * p.cell
                val dx = px - p.cx
                val dy = py - p.cy
                val rr = sqrt(dx * dx + dy * dy)
                var v: Double
                if (rr < r) {
                    val nx = dx / r; val ny = dy / r
                    val nz = sqrt(max(0.0, 1 - nx * nx - ny * ny))
                    val lam = max(0.0, (nx * lx + ny * ly + nz * lz) / ll)
                    val lon = atan2(nx, nz) + p.spin
                    val lat = asin(ny.coerceIn(-1.0, 1.0))
                    val land = fbm(lon * 1.6 + 10, lat * 2.2 + 5)
                    val coast = if (abs(land - p.landLevel) < 0.035) 0.22 + 0.14 * p.beat else 0.0
                    v = (0.30 + 0.80 * lam) * (if (land > p.landLevel) 1.0 else 0.56) + coast
                    v += smoothstep(0.80, 1.0, rr / r) * (0.08 + (0.10 + 0.14 * p.effort) * p.beat)
                } else {
                    val d = (rr - r) / (r * p.glowReach)
                    val halo = max(0.0, 1 - d)
                    val rim = exp(-(rr - r) / (r * 0.06))
                    v = halo * halo * halo * (0.085 + (0.07 + 0.10 * p.effort) * p.beat) +
                        rim * (0.24 + (0.18 + 0.22 * p.effort) * p.beat)
                }
                val mx = (col + shift) and 7
                val my = (row + shift) and 7
                val m = BAYER8[my * 8 + mx] / 64.0 - 0.5
                val idx = (v * last + m).roundToInt().toDouble().coerceIn(0.0, last)
                val f = (idx / last).toFloat()
                val to = if (idx >= last && p.levels > 2) hot else tone
                pixels[row * cols + col] = lerp(ink, to, f).copy(alpha = 1f).toArgb()
            }
        }
        bmp.setPixels(pixels, 0, cols, 0, 0, cols, rows)
        return bmp
    }

    private fun lerp(a: Color, b: Color, t: Float) = Color(
        a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t, 1f)

    private fun smoothstep(e0: Double, e1: Double, x: Double): Double {
        val t = ((x - e0) / (e1 - e0)).coerceIn(0.0, 1.0)
        return t * t * (3 - 2 * t)
    }

    private fun fract(x: Double) = x - floor(x)
    private fun hash(x: Double, y: Double) = fract(sin(x * 127.1 + y * 311.7) * 43758.5453)
    private fun noise(x: Double, y: Double): Double {
        val ix = floor(x); val iy = floor(y)
        val fx = x - ix; val fy = y - iy
        val ux = fx * fx * (3 - 2 * fx); val uy = fy * fy * (3 - 2 * fy)
        val a = hash(ix, iy); val b = hash(ix + 1, iy); val c = hash(ix, iy + 1); val d = hash(ix + 1, iy + 1)
        val ab = a + (b - a) * ux
        val cd = c + (d - c) * ux
        return ab + (cd - ab) * uy
    }
    private fun fbm(x0: Double, y0: Double): Double {
        var v = 0.0; var amp = 0.5; var x = x0; var y = y0
        repeat(3) { v += noise(x, y) * amp; x *= 2.03; y *= 2.01; amp *= 0.5 }
        return v
    }

    companion object {
        /** The threshold map: neighbouring cells as far apart in the sequence as possible. */
        val BAYER8 = intArrayOf(
            0, 32, 8, 40, 2, 34, 10, 42,
            48, 16, 56, 24, 50, 18, 58, 26,
            12, 44, 4, 36, 14, 46, 6, 38,
            60, 28, 52, 20, 62, 30, 54, 22,
            3, 35, 11, 43, 1, 33, 9, 41,
            51, 19, 59, 27, 49, 17, 57, 25,
            15, 47, 7, 39, 13, 45, 5, 37,
            63, 31, 55, 23, 61, 29, 53, 21,
        )
    }
}
