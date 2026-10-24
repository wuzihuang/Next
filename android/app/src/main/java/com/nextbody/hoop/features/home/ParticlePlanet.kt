package com.nextbody.hoop.features.home

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * False while a home art layer cannot be seen: its page is off to the side, the timeline
 * covers it, or a detail page / takeover sits on top. Animated art pauses on it.
 * (SwiftUI `EnvironmentValues.homeArtActive`.)
 */
val LocalHomeArtActive = compositionLocalOf { true }

/** Seconds (wall clock, wrapped like `timeIntervalSinceReferenceDate`) ticking at ~[hz] while [running]. */
@Composable
internal fun rememberArtClock(running: Boolean, hz: Double = 30.0): Double {
    val t by produceState(nowSeconds(), running) {
        if (!running) return@produceState
        val step = 1.0 / hz
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                if (last == 0L || (now - last) / 1e9 >= step - 0.002) {
                    last = now
                    value = nowSeconds()
                }
            }
        }
    }
    return t
}

/**
 * A planet as a fine grain screen, drawn per grain on the GPU (`GrainPlanet.metal` → AGSL).
 * Surfaces are procedural and turn about their own pole; every grain is a soft lamp, and a
 * smooth neon halo blooms past the limb. Everything draws additively (`.plusLighter`), so the
 * night side and the sky simply vanish into the page. [lit] sets how much of the face the sun
 * reaches.
 *
 * ⚠️ Performance. Three of these share the planet page and every grain runs several fbm
 * octaves. 30 Hz reads the same as 120 for a body that turns once a minute, and it stops
 * entirely while the page sits off screen or under a pushed page.
 */
enum class ParticlePlanetKind { terra, luna, mars }

@Composable
fun ParticlePlanet(
    kind: ParticlePlanetKind,
    /** Planet centre as a fraction of the view's size. */
    centerX: Float,
    centerY: Float,
    /** Radius as a fraction of the view's height. */
    radius: Float,
    /** Edge length of one grain in dp. */
    pitch: Float,
    /** Lit fraction of the visible disc, 0...1. */
    lit: Double,
    /** Which side the light comes from: -1 left, +1 right. */
    sunSide: Float = -1f,
    /** Seconds for one full turn. */
    day: Double,
    /** Density of the twinkling star field around the planet. */
    stars: Int = 0,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion()
    val artActive = LocalHomeArtActive.current
    val time = rememberArtClock(!reduceMotion && artActive)
    val density = LocalDensity.current.density
    val sun = remember(lit, sunSide) { sunVector(lit, sunSide) }
    val shader = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) GrainPlanetShader.make() else null
    }
    Canvas(modifier.clearAndSetSemantics { }) {
        val t = if (reduceMotion) 0.0 else time
        val r = radius * size.height
        val c = Offset(size.width * centerX, size.height * centerY)
        val turns = t / day
        val phase = when (kind) {
            ParticlePlanetKind.terra -> 2.4
            ParticlePlanetKind.luna -> 0.6
            ParticlePlanetKind.mars -> 4.1
        }
        val spin = (turns % 1.0) * 2 * PI + phase
        val cloudSpin = ((turns * 1.18) % 1.0) * 2 * PI + phase * 1.7
        val seconds = t % 3600.0
        if (shader != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            GrainPlanetShader.draw(
                this, shader as RuntimeShader, c, r, pitch * density, sun, kind.ordinal,
                spin.toFloat(), cloudSpin.toFloat(), seconds.toFloat(), stars.toFloat(),
            )
        } else {
            drawFallbackPlanet(kind, c, r, pitch * density, sun, stars, seconds.toFloat())
        }
    }
}

/** Unit vector toward the sun: +x right, +y up, +z toward the viewer. */
private fun sunVector(lit: Double, sunSide: Float): FloatArray {
    val k = max(0.04, min(1.0, lit)).toFloat()
    val a = acos(2 * k - 1)
    val x = sunSide * sin(a)
    val y = 0.24f
    val z = cos(a)
    val len = sqrt(x * x + y * y + z * z)
    return floatArrayOf(x / len, y / len, z / len)
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private object GrainPlanetShader {
    fun make(): Any = RuntimeShader(SOURCE)

    fun draw(
        scope: DrawScope, shader: RuntimeShader, c: Offset, r: Float, pitch: Float, sun: FloatArray,
        kind: Int, spin: Float, cloudSpin: Float, seconds: Float, stars: Float,
    ) = with(scope) {
        shader.setFloatUniform("size", size.width, size.height)
        shader.setFloatUniform("body", c.x, c.y, max(1f, r), pitch)
        shader.setFloatUniform("light", sun[0], sun[1], sun[2], kind.toFloat())
        shader.setFloatUniform("clock", spin, cloudSpin, seconds, stars)
        drawRect(ShaderBrush(shader), blendMode = BlendMode.Plus)
    }

    // 1:1 port of Features/Home/GrainPlanet.metal. AGSL wants constant loop bounds and no
    // reference parameters, so octave counts break out of a fixed loop and the surface
    // hands its emission and normal back through `out`.
    private const val SOURCE = """
uniform float2 size;
uniform float4 body;
uniform float4 light;
uniform float4 clock;

const float PI_F = 3.14159265;

float hash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float hash3(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
               mix(hash(i + float2(0, 1)), hash(i + 1.0), f.x), f.y);
}

float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i + float3(1, 0, 0)), f.x),
            mix(hash3(i + float3(0, 1, 0)), hash3(i + float3(1, 1, 0)), f.x), f.y),
        mix(mix(hash3(i + float3(0, 0, 1)), hash3(i + float3(1, 0, 1)), f.x),
            mix(hash3(i + float3(0, 1, 1)), hash3(i + 1.0), f.x), f.y), f.z);
}

float fbm3(float3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; ++i) {
        if (i >= octaves) { break; }
        sum += amplitude * noise3(p);
        p = p * 2.03 + float3(3.1, 8.7, 2.4);
        amplitude *= 0.5;
    }
    return sum;
}

float fbm2(float2 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * noise(p);
        p = float2(p.x * 1.64 - p.y * 1.18, p.x * 1.18 + p.y * 1.64) + 7.3;
        amplitude *= 0.5;
    }
    return sum;
}

float2 rotate2(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 craters(float3 s, float seed, float density) {
    float lat = asin(clamp(s.y, -1.0, 1.0));
    float2 uv = float2(atan(s.x, s.z), lat);
    float coslat = max(cos(lat), 0.15);
    float3 sum = float3(0.0);
    for (int scale = 0; scale < 2; ++scale) {
        float rows = (scale == 0 ? 3.6 : 11.0) * density;
        float cols = (scale == 0 ? 22.0 : 70.0) * density;
        float2 p = float2(uv.x / (2.0 * PI_F) * cols, uv.y * rows);
        float2 base = floor(p);
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 id = base + float2(float(x), float(y));
                float2 wrapped = float2(id.x - floor(id.x / cols) * cols, id.y);
                float h = hash(wrapped + seed);
                if (h < (scale == 0 ? 0.62 : 0.72)) { continue; }
                float2 center = id + 0.2 + 0.6 * float2(hash(wrapped + seed + 17.0), hash(wrapped + seed + 39.0));
                float2 offset = p - center;
                float radius = 0.06 + 0.32 * h * h * h;
                float len = length(offset);
                float d = len / radius;
                if (d > 1.6) { continue; }
                float bowl = exp(-d * d * 3.0);
                float rim = exp(-pow((d - 0.87) * 6.0, 2.0));
                float height = rim * 0.10 - bowl * 0.16;
                float slope = (-72.0 * (d - 0.87) * rim * 0.10 + 6.0 * d * bowl * 0.16) / radius;
                float2 g = slope * offset / max(len, 0.0001);
                sum += float3(height, g.x * cols / (2.0 * PI_F) / coslat, g.y * rows);
            }
        }
    }
    return sum;
}

float3 bump(float3 s, float2 slope, float strength) {
    float3 east = normalize(float3(s.z, 0.0, -s.x) + float3(0.0001, 0.0, 0.0));
    float3 north = cross(s, east);
    return normalize(s - strength * (slope.x * east + slope.y * north));
}

float2 reliefSlope(float3 s, float frequency, float seed) {
    float e = 0.012;
    float3 east = normalize(float3(s.z, 0.0, -s.x) + float3(0.0001, 0.0, 0.0));
    float3 north = cross(s, east);
    float h0 = fbm3(s * frequency + seed, 3);
    float he = fbm3((s + east * e) * frequency + seed, 3);
    float hn = fbm3((s + north * e) * frequency + seed, 3);
    return float2(he - h0, hn - h0) / e;
}

float3 surface(int kind, float3 s, float3 cs, float3 n, float3 sun, float night,
               float time, out float3 emission, out float3 normal) {
    emission = float3(0.0);
    normal = s;
    if (kind == 0) {
        float h = fbm3(s * 1.8 + 3.1, 5);
        float land = smoothstep(0.505, 0.53, h);
        float3 ocean = mix(float3(0.006, 0.030, 0.085), float3(0.020, 0.150, 0.300),
                           smoothstep(0.32, 0.50, h));
        float detail = fbm3(s * 7.5 + 1.7, 3);
        float3 ground = mix(float3(0.07, 0.15, 0.08), float3(0.40, 0.32, 0.19),
                            smoothstep(0.35, 0.75, detail + (h - 0.53) * 2.2));
        float3 albedo = mix(ocean, ground, land);
        float ice = smoothstep(0.80, 0.90, abs(s.y) + detail * 0.10);
        albedo = mix(albedo, float3(0.86, 0.91, 0.97), ice);

        float c = fbm3(cs * 2.4 + 11.0, 5);
        float cloud = smoothstep(0.50, 0.74, c) * 0.92;
        albedo = mix(albedo, float3(0.93, 0.96, 1.00), cloud);

        if (night < 0.999) {
            float3 r = reflect(-sun, n);
            float glint = pow(max(r.z, 0.0), 36.0) * (1.0 - land) * (1.0 - cloud) * (1.0 - ice);
            emission += float3(0.65, 0.85, 1.00) * glint * 0.75 * (1.0 - night);
        }
        if (night < 0.001 || land < 0.001) { return albedo; }

        float3 lot = floor(s * 95.0);
        float sprawl = smoothstep(0.42, 0.68, fbm3(s * 5.0 + 7.0, 3));
        float lamp = step(0.62, hash3(lot)) * sprawl * land * (1.0 - ice) * (1.0 - cloud * 0.85);
        float pick = hash3(lot + 13.0);
        float3 tint = pick < 0.72 ? float3(1.00, 0.62, 0.26)
                    : (pick < 0.90 ? float3(0.30, 0.92, 1.00) : float3(1.00, 0.32, 0.78));
        float flicker = 0.80 + 0.20 * sin(time * (0.6 + pick * 1.4) + pick * 40.0);
        emission += tint * lamp * night * flicker * 0.85;
        return albedo;
    }
    if (kind == 1) {
        float m = fbm3(s * 1.6 + 5.0, 4);
        float maria = smoothstep(0.44, 0.60, m);
        float3 albedo = mix(float3(0.66, 0.66, 0.70), float3(0.26, 0.26, 0.31), maria);
        albedo *= 0.82 + 0.34 * fbm3(s * 16.0, 3);
        float3 crater = craters(s, 3.0, 1.0);
        albedo *= 1.0 + crater.x * 0.9;
        float2 slope = crater.yz * 0.018 + reliefSlope(s, 5.0, 2.0) * 0.030;
        normal = bump(s, slope, 1.0);
        emission += albedo * night * float3(0.18, 0.22, 0.45) * 0.035;
        return albedo;
    }
    float m = fbm3(s * 1.9 + 1.3, 5);
    float3 albedo = mix(float3(0.40, 0.12, 0.05), float3(0.84, 0.44, 0.22), smoothstep(0.33, 0.66, m));
    float dark = smoothstep(0.54, 0.70, fbm3(s * 3.2 + 9.0, 4));
    albedo = mix(albedo, float3(0.20, 0.07, 0.04), dark * 0.65);
    float rift = exp(-pow((s.y + 0.12 + 0.06 * sin(s.x * 7.0 + s.z * 3.0)) * 26.0, 2.0))
               * smoothstep(-0.6, 0.2, s.z);
    albedo *= 1.0 - rift * 0.35;
    float3 crater = craters(s, 9.0, 0.8);
    albedo *= 1.0 + crater.x * 0.6;
    float detail = fbm3(s * 9.0, 2);
    float cap = smoothstep(0.84, 0.92, s.y + detail * 0.06);
    albedo = mix(albedo, float3(0.96, 0.92, 0.88), cap);
    float riftLine = s.y + 0.12 + 0.06 * sin(s.x * 7.0 + s.z * 3.0);
    float riftSlope = 2.0 * riftLine * 26.0 * 26.0 * exp(-pow(riftLine * 26.0, 2.0))
                    * smoothstep(-0.6, 0.2, s.z);
    float2 slope = crater.yz * 0.015 + reliefSlope(s, 4.0, 6.0) * 0.040 * (1.0 - cap)
                 + float2(0.0, riftSlope * 0.0045);
    normal = bump(s, slope, 1.0);
    return albedo;
}

float3 stars(float2 here, float2 sz, float pitch, float amount, float time) {
    float3 sum = float3(0.0);
    float area = sz.x * sz.y;
    for (int layer = 0; layer < 2; ++layer) {
        float count = amount * (layer == 0 ? 1.4 : 7.0);
        float cell = sqrt(area / max(count, 1.0));
        float2 p = (here + 0.5) * pitch;
        float2 g = floor(p / cell);
        float2 id = g + float(layer) * 131.0;
        if (hash(id + 2.1) > (layer == 0 ? 0.80 : 0.86)) { continue; }
        float2 seat = floor((g + 0.15 + 0.70 * float2(hash(id + 19.2), hash(id + 73.1))) * cell / pitch);
        float2 delta = seat - here;
        float reach = dot(delta, delta);
        float grade = hash(id + 4.7);
        float bright = layer == 0 ? 0.30 + 0.70 * pow(grade, 1.6) : 0.10 + 0.22 * grade;
        float twinkle = 0.55 + 0.45 * sin(time * (0.5 + hash(id + 8.3) * 1.6) + hash(id + 3.9) * 6.283);
        float core = step(reach, 0.5);
        float spill = layer == 0 ? exp(-reach * 0.9) * 0.40 * step(0.55, grade) : 0.0;
        float crossv = (layer == 0 && grade > 0.86)
            ? (exp(-abs(delta.x) * 0.55) * step(abs(delta.y), 0.5)
               + exp(-abs(delta.y) * 0.55) * step(abs(delta.x), 0.5)) * 0.28 * step(0.5, reach)
            : 0.0;
        float shade = hash(id + 55.7);
        float3 tint = shade < 0.40 ? float3(1.00, 1.00, 1.00)
                    : (shade < 0.62 ? float3(0.70, 0.88, 1.00)
                    : (shade < 0.80 ? float3(1.00, 0.88, 0.74)
                    : (shade < 0.92 ? float3(0.45, 1.00, 0.95)
                                    : float3(1.00, 0.55, 0.92))));
        sum += tint * (core + spill + crossv) * bright * twinkle;
    }
    return sum;
}

half4 main(float2 position) {
    int kind = int(light.w + 0.5);
    float3 inner;
    float3 outer;
    float rimAmt;
    float haloAmt;
    if (kind == 0) { inner = float3(0.28, 0.72, 1.00); outer = float3(0.58, 0.32, 1.00); rimAmt = 1.00; haloAmt = 0.55; }
    else if (kind == 1) { inner = float3(0.70, 0.64, 1.00); outer = float3(0.30, 0.82, 1.00); rimAmt = 0.45; haloAmt = 0.30; }
    else { inner = float3(1.00, 0.48, 0.22); outer = float3(1.00, 0.24, 0.58); rimAmt = 0.70; haloAmt = 0.42; }

    float pitch = max(body.w, 0.5);
    float radius = max(body.z, 1.0);
    float time = clock.z;
    float3 sun = normalize(light.xyz);

    float2 here = floor(position / pitch);
    float2 cp = (here + 0.5) * pitch;
    float2 lamp = (position - cp) / pitch;

    float2 q = (position - body.xy) / radius;
    q.y = -q.y;
    float rr = dot(q, q);

    float3 col = float3(0.0);
    if (rr < 1.0) {
        float z = sqrt(1.0 - rr);
        float3 n = float3(q, z);
        float3 t = float3(rotate2(n.xy, 0.38), n.z);
        float3 s = float3(rotate2(t.xz, clock.x), t.y).xzy;
        float3 cs = float3(rotate2(t.xz, clock.y), t.y).xzy;
        float3 st = float3(rotate2(sun.xy, 0.38), sun.z);
        float3 sunLocal = float3(rotate2(st.xz, clock.x), st.y).xzy;

        float lambert = dot(n, sun);
        float night = 1.0 - smoothstep(-0.18, 0.04, lambert);
        float3 emission;
        float3 normal;
        float3 albedo = surface(kind, s, cs, n, sun, night, time, emission, normal);
        float limb = 0.70 + 0.30 * z;
        if (kind == 0) {
            float dayside = smoothstep(-0.07, 0.28, lambert);
            col = albedo * (0.012 + (max(lambert, 0.0) * 0.95 + dayside * 0.30) * limb);
        } else {
            float relief = max(dot(normal, sunLocal), 0.0);
            float terminator = smoothstep(-0.03, 0.10, lambert);
            float grazing = 1.0 - smoothstep(0.0, 0.45, lambert);
            float litv = relief * terminator;
            litv *= mix(1.0, smoothstep(0.0, 0.55, relief), grazing * 0.85);
            col = albedo * (0.003 + litv * 1.30 * (0.82 + 0.18 * z));
        }
        col += emission;

        float fresnel = pow(1.0 - z, 2.6);
        float rimFloor = kind == 0 ? 0.22 : 0.04;
        float rimSun = rimFloor + (1.0 - rimFloor) * smoothstep(-0.35, 0.45, lambert);
        col += mix(inner, outer, fresnel) * fresnel * rimAmt * rimSun * 0.85;

        float scanY = 1.35 - fract(time / 11.0) * 2.7;
        float scan = exp(-pow((q.y - scanY) * 16.0, 2.0));
        col += outer * scan * 0.07 * (0.4 + 0.6 * smoothstep(-0.07, 0.28, lambert));

        col *= 0.90 + 0.18 * hash(here + float(kind) * 7.0);
    } else {
        col += stars(here, size, pitch, clock.w, time);
        float2 sky = (cp - body.xy) / (radius * 2.6);
        float wisps = fbm2(sky * 2.2 + float2(time * 0.006, -time * 0.004) + float(kind) * 5.0);
        float dust = smoothstep(0.42, 0.85, wisps) * exp(-dot(sky, sky) * 0.9);
        col += mix(outer, inner, fbm2(sky * 4.0 + 3.0)) * dust * 0.045;
    }

    col = 1.0 - exp(-col * 1.55);
    float grain = exp(-dot(lamp, lamp) / (2.0 * 0.30 * 0.30));
    float3 outColor = col * (0.20 + 0.95 * grain);

    float2 qs = (position - body.xy) / radius;
    float d = length(qs);
    float2 qn = float2(qs.x, -qs.y) / max(d, 0.0001);
    float facing = smoothstep(-0.55, 0.65, dot(qn, normalize(sun.xy + 0.0001)) * 0.8 + sun.z * 0.6);
    float beyond = max(d - 1.0, 0.0);
    float hug = exp(-beyond * 16.0) * smoothstep(0.90, 1.0, d);
    float bloom = exp(-beyond * 3.2) * step(1.0, d);
    float3 halo = inner * hug * 0.55
                + mix(inner, outer, smoothstep(0.0, 0.35, beyond)) * bloom * 0.16;
    halo += inner * (1.0 - smoothstep(0.0, 1.0, d)) * 0.035;
    outColor += halo * haloAmt * (0.30 + 0.70 * facing);

    return half4(half3(clamp(outColor, 0.0, 1.0)), 1.0);
}
"""
}

/**
 * Below API 33 there is no runtime shader. The same disc is drawn on the grain lattice on the
 * CPU — a lambert-lit sphere in the body's own colours, its neon rim and halo, and the star
 * seats — so the page keeps its composition; the surface does not turn.
 */
private fun DrawScope.drawFallbackPlanet(
    kind: ParticlePlanetKind, c: Offset, r: Float, pitch: Float, sun: FloatArray, stars: Int, time: Float,
) {
    val (inner, outer, base) = when (kind) {
        ParticlePlanetKind.terra -> Triple(Color(0.28f, 0.72f, 1f), Color(0.58f, 0.32f, 1f), Color(0.10f, 0.30f, 0.52f))
        ParticlePlanetKind.luna -> Triple(Color(0.70f, 0.64f, 1f), Color(0.30f, 0.82f, 1f), Color(0.55f, 0.55f, 0.60f))
        ParticlePlanetKind.mars -> Triple(Color(1f, 0.48f, 0.22f), Color(1f, 0.24f, 0.58f), Color(0.72f, 0.34f, 0.16f))
    }
    // halo
    drawCircle(
        Brush.radialGradient(
            listOf(inner.copy(alpha = 0.35f), outer.copy(alpha = 0.10f), Color.Transparent),
            center = c, radius = r * 1.6f,
        ),
        radius = r * 1.6f, center = c, blendMode = BlendMode.Plus,
    )
    val grain = pitch * 0.62f
    var y = c.y - r
    while (y <= c.y + r) {
        var x = c.x - r
        while (x <= c.x + r) {
            val dx = (x - c.x) / r
            val dy = -(y - c.y) / r
            val rr = dx * dx + dy * dy
            if (rr < 1f) {
                val z = sqrt(1f - rr)
                val lambert = dx * sun[0] + dy * sun[1] + z * sun[2]
                val light = max(0f, lambert) * (0.7f + 0.3f * z)
                val fresnel = Math.pow((1f - z).toDouble(), 2.6).toFloat()
                val alpha = (light * 0.9f + fresnel * 0.5f).coerceIn(0f, 1f)
                if (alpha > 0.03f) {
                    val col = if (fresnel > 0.3f) inner else base
                    drawRect(col.copy(alpha = alpha), Offset(x - grain / 2, y - grain / 2), Size(grain, grain), blendMode = BlendMode.Plus)
                }
            }
            x += pitch
        }
        y += pitch
    }
    // star seats, deterministic
    if (stars > 0) {
        val count = stars * 2
        for (i in 0 until count) {
            val hx = frac(sin(i * 12.9898f) * 43758.547f)
            val hy = frac(sin(i * 78.233f) * 43758.547f)
            val p = Offset(hx * size.width, hy * size.height)
            val dd = (p - c).getDistance()
            if (dd < r * 1.02f) continue
            val tw = 0.55f + 0.45f * sin(time * (0.5f + hx * 1.6f) + hy * 6.283f)
            val a = (0.15f + 0.6f * frac(hx * 7.3f)) * tw
            drawRect(Color.White.copy(alpha = a), Offset(p.x - grain / 2, p.y - grain / 2), Size(grain, grain), blendMode = BlendMode.Plus)
        }
    }
}

private fun frac(v: Float): Float = v - kotlin.math.floor(v)
