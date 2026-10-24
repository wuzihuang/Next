package com.nextbody.hoop.features.home

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.semantics.clearAndSetSemantics
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The idle collection shares one lighting model and one continuous, slow camera.
 * Coordinates are authored on the existing 358 × 470 panel; bodies stay circular
 * on every device and the lower third remains quiet behind the live readout.
 *
 * API 33+: the Metal fragment (`DeepSpacePlate.metal`) ported to AGSL, one fragment per pixel.
 * Below 33: a Canvas rendering of the same plate on the same 4-unit LED lattice — sky, the
 * lit sphere and its terminator, and the stars — without the dust lane, meteors or rings.
 */
@Composable
fun DeepSpacePlate(plate: Int, clock: Double, modifier: Modifier = Modifier) {
    val look = SpaceLook.collection[min(28, maxOf(1, plate)) - 1]
    val shader = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) runCatching { DeepSpaceShader.make() }.getOrNull() else null
    }
    Canvas(modifier.fillMaxSize().clipToBounds().clearAndSetSemantics { }) {
        if (shader != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            DeepSpaceShader.configure(shader as RuntimeShader, size.width, size.height, density,
                clock.toFloat(), plate.toFloat(), look)
            drawRect(ShaderBrush(shader as RuntimeShader))
        } else {
            DeepSpaceFallback.draw(this, look, plate, clock)
        }
    }
}

internal data class SpaceLook(
    val x: Float = 179f,
    val y: Float = 174f,
    val radius: Float = 78f,
    /** 0 gas bands, 1 rock, 2 ocean/ice. */
    val surface: Float = 0f,
    val tilt: Float = -18f,
    val inclination: Float = 0.32f,
    val ringInner: Float = 1.34f,
    val ringOuter: Float = 2.12f,
    val shadow: Long = 0x655646,
    val light: Long = 0xE3D3AF,
    val air: Long = 0xAABAD1,
    val sunX: Float = -0.78f,
    val sunY: Float = -0.48f,
    val sunZ: Float = 0.48f,
    val nebula: Float = 0.5f,
) {
    companion object {
        /** Stable plate IDs preserve the daily/event selection policy. */
        val collection: List<SpaceLook> = listOf(
            SpaceLook(), // 01 · ivory rings
            SpaceLook(y = 169f, radius = 106f, surface = 1f, ringOuter = 0f,
                shadow = 0x575A60, light = 0xD5D7D6, air = 0x818997, sunZ = 0.68f, nebula = 0.22f),
            SpaceLook(y = 132f, radius = 58f, tilt = -6f, inclination = 0.22f,
                light = 0xE4E7E9, air = 0xB2C7DC, nebula = 0.4f),
            SpaceLook(y = 171f, radius = 48f, tilt = -32f, inclination = 0.55f, ringInner = 1.8f, ringOuter = 3.35f,
                shadow = 0x3D4957, light = 0xACBDCB, air = 0x9AB8D0, sunZ = 0.18f),
            SpaceLook(y = 168f, radius = 75f, tilt = -31f, inclination = 0.26f,
                shadow = 0x493A2A, light = 0xC5B395, air = 0xAD9680, sunZ = 0.08f, nebula = 0.25f),
            SpaceLook(x = 212f, y = 152f, radius = 46f, surface = 1f, tilt = -38f, inclination = 0.4f,
                ringInner = 2.25f, ringOuter = 3.1f, shadow = 0x414C58, light = 0xC4D1D8, nebula = 0.6f),
            SpaceLook(y = 166f, radius = 82f, tilt = -24f, inclination = 0.3f, ringOuter = 1.83f,
                shadow = 0x314956, light = 0xA0BBCB, air = 0x6CADD2, nebula = 0.38f),
            SpaceLook(x = 147f, y = 167f, radius = 51f, tilt = -25f, inclination = 0.42f,
                ringInner = 1.5f, ringOuter = 3.0f, shadow = 0x6C6252, light = 0xD1C7B3, nebula = 0.3f),
            SpaceLook(y = 173f, radius = 84f, surface = 1f, tilt = 22f, inclination = 0.17f,
                ringInner = 1.45f, ringOuter = 1.87f, shadow = 0x58524C, light = 0xC9C3B3, nebula = 0.45f),
            SpaceLook(x = 221f, y = 143f, radius = 33f, surface = 1f, ringOuter = 0f,
                shadow = 0x4D5863, light = 0xCAD6DA, sunZ = -0.05f, nebula = 0.75f),
            SpaceLook(x = 330f, y = 144f, radius = 173f, tilt = -12f, inclination = 0.27f,
                shadow = 0x4A5155, light = 0xC6C9BD, air = 0x81949E, sunZ = 0.12f, nebula = 0.25f),
            SpaceLook(y = 168f, radius = 78f, tilt = -8f, inclination = 0.24f,
                shadow = 0x3D414B, light = 0x9BA3AF, air = 0x7489A5, sunZ = -0.36f, nebula = 0.25f),
            SpaceLook(x = 198f, y = 145f, radius = 45f, surface = 2f, tilt = -38f, inclination = 0.5f,
                ringInner = 1.9f, ringOuter = 3.4f, shadow = 0x294E67, light = 0xA9C9D7, air = 0x639DCA, nebula = 0.7f),
            SpaceLook(y = 170f, radius = 77f, surface = 1f, ringOuter = 0f,
                shadow = 0x55504A, light = 0xD6D0C5, sunZ = -0.62f, nebula = 0.4f),
            SpaceLook(x = 171f, y = 268f, radius = 155f, surface = 1f, ringOuter = 0f,
                shadow = 0x5B3024, light = 0xB98E64, air = 0xD58C54,
                sunX = -0.2f, sunY = -0.9f, sunZ = -0.22f, nebula = 0.3f),
            SpaceLook(x = 86f, y = 126f, radius = 108f, surface = 2f, ringOuter = 0f,
                shadow = 0x1C395C, light = 0x6D9CBF, air = 0x528FD4, sunX = 0.7f, sunZ = -0.12f, nebula = 0.4f),
            SpaceLook(y = 161f, radius = 66f, tilt = -20f, inclination = 0.52f, ringOuter = 2.35f,
                shadow = 0x4A3E60, light = 0xB8AAC6, air = 0x9994D3, nebula = 0.85f),
            SpaceLook(x = 214f, y = 143f, radius = 61f, surface = 2f, ringOuter = 0f,
                shadow = 0x553C59, light = 0xB79EBB, air = 0xBC95BF, sunZ = 0.15f, nebula = 1.25f),
            SpaceLook(y = 168f, radius = 73f, tilt = -19f, inclination = 0.34f,
                shadow = 0x62585E, light = 0xD3C4B9, air = 0xB4A4CA, nebula = 0.65f),
            SpaceLook(x = 335f, y = 162f, radius = 145f, surface = 2f, ringOuter = 0f,
                shadow = 0x1C344B, light = 0x83AABD, air = 0x689FCA, sunZ = -0.04f, nebula = 0.35f),
            SpaceLook(x = 5f, y = 177f, radius = 153f, surface = 2f, ringOuter = 0f,
                shadow = 0x1D3652, light = 0x6E9CBA, air = 0x528BBD, sunX = 0.85f, sunZ = 0.12f, nebula = 0.4f),
            SpaceLook(y = 193f, radius = 70f, tilt = -6f, inclination = 0.2f,
                shadow = 0x5E594D, light = 0xD7CFB7, air = 0xB3BBC6, nebula = 0.4f),
            SpaceLook(x = 160f, y = 158f, radius = 139f, surface = 1f, ringOuter = 0f,
                shadow = 0x565A61, light = 0xC7C9CA, air = 0x8493A5, sunZ = 0.32f, nebula = 0.2f),
            SpaceLook(x = 273f, y = 111f, radius = 42f, surface = 2f, ringOuter = 0f,
                shadow = 0x28434E, light = 0x8EB4C2, air = 0x7FB9D4, sunZ = 0.28f, nebula = 1.0f),
            SpaceLook(x = 183f, y = 222f, radius = 94f, surface = 1f, ringOuter = 0f,
                shadow = 0x532D22, light = 0xBD9772, air = 0xD09261,
                sunX = 0.3f, sunY = -0.85f, sunZ = -0.5f, nebula = 0.22f),
            SpaceLook(x = 200f, y = 169f, radius = 91f, surface = 2f, ringOuter = 0f,
                shadow = 0x303758, light = 0x969FCA, air = 0x849BE0, sunX = 0.9f, sunZ = 0.1f, nebula = 0.5f),
            SpaceLook(x = 277f, y = 86f, radius = 113f, surface = 1f, ringOuter = 0f,
                shadow = 0x444C53, light = 0xBAC6CD, air = 0x889FB4, sunZ = -0.28f, nebula = 0.4f),
            SpaceLook(y = 169f, radius = 80f, tilt = -2f, inclination = 0.09f,
                ringInner = 1.25f, ringOuter = 2.4f, shadow = 0x3C4B56, light = 0xBDC9CA,
                air = 0x90B1C9, sunZ = 0.18f, nebula = 0.4f),
        )
    }
}

private fun rgb(v: Long): FloatArray = floatArrayOf(
    ((v shr 16) and 0xFF) / 255f, ((v shr 8) and 0xFF) / 255f, (v and 0xFF) / 255f)

@RequiresApi(33)
private object DeepSpaceShader {
    fun make(): Any = RuntimeShader(SRC)

    fun configure(any: Any, w: Float, h: Float, density: Float, time: Float, seed: Float, look: SpaceLook) {
        val s = any as RuntimeShader
        s.setFloatUniform("size", w / density, h / density)
        s.setFloatUniform("density", density)
        s.setFloatUniform("time", time)
        s.setFloatUniform("seed", seed)
        s.setFloatUniform("body", look.x, look.y, look.radius, look.surface)
        s.setFloatUniform("ring", look.tilt, look.inclination, look.ringInner, look.ringOuter)
        s.setFloatUniform("darkColor", rgb(look.shadow))
        s.setFloatUniform("lightColor", rgb(look.light))
        s.setFloatUniform("airColor", rgb(look.air))
        s.setFloatUniform("lighting", look.sunX, look.sunY, look.sunZ, look.nebula)
    }

    // A line-for-line AGSL port of DeepSpacePlate.metal. Positions are in points (dp), as on iOS.
    private const val SRC = """
uniform float2 size;
uniform float density;
uniform float time;
uniform float seed;
uniform float4 body;
uniform float4 ring;
uniform float3 darkColor;
uniform float3 lightColor;
uniform float3 airColor;
uniform float4 lighting;

const float PI = 3.14159265;

float dsHash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float dsHash3(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
float dsNoise(float2 p) {
    float2 i = floor(p); float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(dsHash(i), dsHash(i + float2(1, 0)), f.x),
               mix(dsHash(i + float2(0, 1)), dsHash(i + 1.0), f.x), f.y);
}
float dsNoise3(float3 p) {
    float3 i = floor(p); float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dsHash3(i), dsHash3(i + float3(1, 0, 0)), f.x),
            mix(dsHash3(i + float3(0, 1, 0)), dsHash3(i + float3(1, 1, 0)), f.x), f.y),
        mix(mix(dsHash3(i + float3(0, 0, 1)), dsHash3(i + float3(1, 0, 1)), f.x),
            mix(dsHash3(i + float3(0, 1, 1)), dsHash3(i + 1.0), f.x), f.y), f.z);
}
float dsCloud(float2 p) {
    float sum = 0.0; float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * dsNoise(p);
        p = float2(p.x * 1.64 - p.y * 1.18, p.x * 1.18 + p.y * 1.64) + 7.3;
        amplitude *= 0.5;
    }
    return sum;
}
float dsTerrain(float3 p) {
    float sum = 0.0; float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * dsNoise3(p);
        p = p * 2.07 + float3(3.1, 8.7, 2.4);
        amplitude *= 0.5;
    }
    return sum;
}
float2 dsRotate(float2 p, float angle) {
    return float2(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y);
}
float3 dsStars(float2 p, float t, float sd, float pitch) {
    float3 result = float3(0.0);
    float2 here = floor(p / pitch);
    for (int layer = 0; layer < 3; ++layer) {
        float depth = float(layer);
        float cell = 27.0 + depth * 24.0;
        float2 grid = p / cell;
        float2 id = floor(grid) + sd * 17.0 + depth * 109.0;
        float grade = dsHash(id + 4.7);
        float2 seat = 0.18 + 0.64 * float2(dsHash(id + 19.2), dsHash(id + 73.1));
        float2 delta = floor((floor(grid) + seat) * cell / pitch) - here;
        float reach = dot(delta, delta);
        float core = step(reach, 0.5);
        float spill = exp(-reach * 2.2) * 0.30 * step(0.88, grade);
        float breath = 0.76 + 0.24 * sin(t * (0.9 + 1.4 * dsHash(id + 61.4)) + 6.28 * dsHash(id + 12.9));
        float brightness = 0.52 * pow(grade, 2.6) * breath;
        float shade = dsHash(id + 55.7);
        float3 tint = shade < 0.34 ? float3(1.00, 1.00, 1.00)
                    : shade < 0.58 ? float3(1.00, 0.91, 0.79)
                    : shade < 0.86 ? float3(0.81, 0.89, 1.00)
                                   : float3(0.91, 0.87, 1.00);
        result += tint * (core + spill) * brightness * step(0.76, dsHash(id));
    }
    return result;
}
float3 dsMeteors(float2 p, float t, float sd, float pitch) {
    float3 sum = float3(0.0);
    for (int lane = 0; lane < 4; ++lane) {
        float period = 12.0 + float(lane) * 5.7;
        float tt = t / period + dsHash(float2(float(lane) * 37.1, sd * 5.3 + 2.0));
        float2 id = float2(floor(tt) * 3.7 + float(lane) * 19.0, sd * 11.0 + 4.1);
        float live = 0.035 + 0.022 * dsHash(id + 5.0);
        float u = fract(tt) / live;
        if (dsHash(id) >= 0.42 && u <= 1.0) {
            float side = dsHash(id + 9.0) < 0.5 ? 1.0 : -1.0;
            float angle = 0.42 + 0.62 * dsHash(id + 13.0);
            float2 dir = float2(cos(angle) * side, sin(angle));
            float2 mid = float2(179.0, 150.0)
                       + float2(250.0 * (dsHash(id + 23.0) - 0.5), 260.0 * (dsHash(id + 31.0) - 0.5));
            float2 head = mid + dir * (u * 2.0 - 1.0) * 300.0;
            float tail = 54.0 + 62.0 * dsHash(id + 41.0);
            float2 pa = p - (head - dir * tail);
            float along = clamp(dot(pa, dir) / tail, 0.0, 1.0);
            float off = length(pa - dir * (along * tail));
            float width = pitch * (0.30 + 0.62 * along);
            float streak = exp(-(off * off) / (width * width)) * pow(along, 1.7);
            float spark = exp(-dot(p - head, p - head) / (pitch * pitch * 1.6));
            float fade = smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.80, 1.0, u));
            float pick = dsHash(id + 57.0);
            float3 tint = pick < 0.42 ? float3(0.80, 0.90, 1.00)
                        : pick < 0.68 ? float3(1.00, 0.90, 0.70)
                        : pick < 0.89 ? float3(0.78, 0.98, 0.42)
                                      : float3(0.92, 0.72, 1.00);
            sum += tint * (streak * 0.62 + spark * 0.95) * fade;
        }
    }
    return sum;
}
float dsCraters(float2 uv, float sd) {
    float shade = 0.0;
    for (int scale = 0; scale < 2; ++scale) {
        float dens = scale == 0 ? 3.4 : 12.0;
        float longitudeCells = scale == 0 ? 22.0 : 76.0;
        float2 p = float2(uv.x / (2.0 * PI) * longitudeCells, uv.y * dens);
        float2 base = floor(p);
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 id = base + float2(float(x), float(y));
                float2 wrapped = float2(id.x - floor(id.x / longitudeCells) * longitudeCells, id.y);
                float h = dsHash(wrapped + sd);
                float2 center = id + 0.2 + 0.6 * float2(dsHash(wrapped + sd + 17.0), dsHash(wrapped + sd + 39.0));
                float2 offset = p - center;
                float radius = 0.055 + 0.32 * h * h * h;
                float d = length(offset) / radius;
                float bowl = exp(-d * d * 3.0);
                float rim = exp(-pow((d - 0.87) * 6.0, 2.0));
                float direction = dot(normalize(offset + 0.0001), normalize(float2(-0.7, -0.5)));
                shade += (rim * (0.04 + 0.11 * direction) - bowl * 0.16)
                       * step(scale == 0 ? 0.62 : 0.73, h);
            }
        }
    }
    return shade;
}
float3 dsSphere(float2 p, float radius, float material, float tilt, float inclination, float3 dark,
                float3 bright, float3 air, float3 sun, float t, float sd) {
    float2 q = p / radius;
    float z = sqrt(max(0.0, 1.0 - dot(q, q)));
    float3 normal = float3(q, z);
    float spin = t * 0.085 + sd * 0.71;
    float3 local = float3(dsRotate(normal.xy, -tilt), normal.z);
    float pole = sqrt(1.0 - inclination * inclination);
    local.yz = float2(local.y * pole - local.z * inclination, local.y * inclination + local.z * pole);
    float2 rotated = dsRotate(local.xz, spin);
    float3 surface = float3(rotated.x, local.y, rotated.y);
    float rough = dsTerrain(surface * 4.0 + sd * 3.7);
    float3 albedo;
    if (material < 0.5) {
        float latitude = surface.y * 24.0 + (rough - 0.5) * 6.0;
        float bands = 0.5 + 0.22 * sin(latitude) + 0.11 * sin(latitude * 2.7 + rough * 3.0);
        float wisps = dsNoise3(surface * float3(18.0, 52.0, 18.0) + rough * 2.0);
        albedo = mix(dark, bright, clamp(bands * 0.85 + wisps * 0.25, 0.0, 1.0));
    } else if (material < 1.5) {
        float2 uv = float2(atan(surface.x, surface.z), asin(clamp(surface.y, -1.0, 1.0)));
        float relief = dsCraters(uv, sd * 7.0);
        float maria = smoothstep(0.37, 0.61, rough);
        albedo = mix(dark, bright, 0.2 + maria * 0.65) * (0.83 + dsNoise3(surface * 95.0) * 0.28);
        albedo *= 1.0 + relief * 1.6;
    } else {
        float land = smoothstep(0.42, 0.63, rough);
        float clouds = smoothstep(0.51, 0.77, dsTerrain(surface * 7.0 + float3(t * 0.001, 9.0, 2.0)));
        albedo = mix(dark, bright * 0.83, land * 0.8);
        albedo = mix(albedo, bright, clouds * 0.68);
    }
    float diffuse = max(dot(normal, sun), 0.0);
    float night = 0.009;
    float3 color = albedo * (night + diffuse * 1.13);
    float grazing = pow(1.0 - z, 3.4);
    float rimLight = pow(max(dot(normalize(float3(q, 0.15)), sun) + 0.18, 0.0), 2.0);
    color += air * grazing * rimLight * (material == 1.0 ? 0.025 : 0.26);
    return color;
}
float4 dsRings(float2 q, float sphereZ, float4 rg, float3 sun, float3 tint, float sd, float pixelWidth, float spin) {
    float2 v = dsRotate(q, -rg.x);
    float flatten = max(rg.y, 0.06);
    float3 pt = float3(v.x, v.y, v.y * sqrt(1.0 - flatten * flatten) / flatten);
    float r = length(float2(v.x, v.y / flatten));
    float aa = max(pixelWidth / flatten, 0.003);
    float mask = smoothstep(rg.z, rg.z + aa, r) * (1.0 - smoothstep(rg.w - aa, rg.w, r));
    if (mask < 0.001 || (sphereZ > 0.0 && pt.z < sphereZ)) return float4(0.0);
    float width = rg.w - rg.z;
    float radial = (r - rg.z) / width;
    float gap = 1.0 - 0.91 * exp(-pow((radial - 0.66) / 0.027, 2.0));
    float fine = 0.67 + 0.045 * sin(r * 171.0) + 0.025 * sin(r * 317.0 + sd);
    float2 spun = dsRotate(float2(v.x, v.y / flatten), spin * pow(max(r, 0.5), -1.5));
    float grains = dsNoise(spun * 2.6 + sd);
    float dens = (0.34 + 0.36 * grains) * fine * gap;
    float3 worldPoint = float3(dsRotate(pt.xy, rg.x), pt.z);
    float b = dot(worldPoint, sun);
    float discriminant = b * b - dot(worldPoint, worldPoint) + 1.0;
    float shadow = b < 0.0 ? 1.0 - smoothstep(-0.07, 0.04, discriminant) * 0.94 : 1.0;
    float edge = 0.65 + 0.35 * smoothstep(0.0, 0.25, radial);
    float3 color = tint * edge * shadow;
    return float4(color, mask * dens);
}

half4 main(float2 fragCoord) {
    float2 position = fragCoord / density;
    float scale = max(min(size.x / 358.0, size.y / 470.0), 0.01);
    float2 p = (position - size * 0.5) / scale + float2(179.0, 235.0);
    float pitch = 4.0;
    float2 lamp = fract(p / pitch) * pitch - pitch * 0.5;
    p = (floor(p / pitch) + 0.5) * pitch;
    float2 uv = p / float2(358.0, 470.0);
    float3 air = airColor;
    float3 sun = normalize(lighting.xyz);
    sun.xy = dsRotate(sun.xy, 0.82 * sin(time * 0.088 + seed));
    sun = normalize(sun);

    float2 sky = dsRotate((p - float2(179, 185)) / 210.0, -0.45 + seed * 0.13 + time * 0.0075);
    sky += float2(seed * 3.13, time * -0.016);
    float wisps = dsCloud(sky * float2(2.0, 3.8));
    float lane = exp(-pow(dsRotate((p - float2(179, 175)) / 210.0, -0.45 + seed * 0.13).y * 1.35, 2.0));
    float dust = smoothstep(0.3, 0.78, wisps) * lane;
    float filaments = dsCloud(sky * 5.0 + wisps * 1.7 + float2(time * 0.030, time * -0.020));
    float3 color = float3(0.006, 0.008, 0.013);
    color += mix(float3(0.145, 0.170, 0.255), air * 0.32, 0.45)
           * dust * (0.3 + filaments * 0.8) * lighting.w
           * (0.76 + 0.24 * sin(time * 0.10 + seed * 2.1));
    color *= 1.0 - smoothstep(0.51, 0.75, filaments) * lane * 0.42;
    color += dsStars(p, time, seed, pitch);
    color += dsMeteors(p, time, seed, pitch);

    float2 drift = float2(sin(time * 0.019 + seed) - sin(seed),
                          cos(time * 0.014 + seed) - cos(seed)) * float2(2.3, 3.2);
    float2 q = (p - body.xy - drift) / body.z;
    float rr = dot(q, q);
    float radius = sqrt(rr);
    float pixel = 0.65 / scale / body.z;
    float sphereMask = 1.0 - smoothstep(1.0 - pixel, 1.0 + pixel, radius);
    float sphereZ = rr < 1.0 ? sqrt(1.0 - rr) : -1.0;
    float atmosphere = exp(-max(radius - 1.0, 0.0) * 55.0) * (1.0 - sphereMask) * step(radius, 1.25);
    float limbSun = pow(max(dot(normalize(float3(q, 0.08)), sun), 0.0), 2.0);
    color += air * atmosphere * limbSun * (body.w == 1.0 ? 0.018 : 0.20);
    if (sphereMask > 0.0) {
        float3 surface = dsSphere(q * body.z, body.z, body.w, ring.x * PI / 180.0, ring.y, darkColor,
                                  lightColor, air, sun, time, seed);
        color = mix(color, surface, sphereMask);
    }
    if (ring.w > ring.z) {
        float4 rg = ring;
        rg.x *= PI / 180.0;
        float4 r = dsRings(q, sphereZ, rg, sun, mix(lightColor, float3(0.73, 0.77, 0.82), 0.3), seed, pixel,
                           time * 0.11);
        color = mix(color, r.rgb, r.a);
    }
    float lower = 1.0 - smoothstep(0.58, 0.94, uv.y) * 0.94;
    float vignette = 1.0 - smoothstep(0.33, 0.79, length((uv - float2(0.5, 0.39)) * float2(0.9, 0.78))) * 0.6;
    color *= lower * vignette;
    color += (dsHash(p + seed) - 0.5) / 650.0;
    color = color * 2.15 / (1.0 + 1.35 * color);
    color *= 0.44 + 0.64 * exp(-dot(lamp, lamp) / (2.0 * 0.95 * 0.95));
    return half4(half3(clamp(color, 0.0, 1.0)), 1.0);
}
"""
}

/** API < 33 · the plate on the same 4-unit lattice, drawn cell by cell from a coarse model. */
private object DeepSpaceFallback {
    fun draw(scope: androidx.compose.ui.graphics.drawscope.DrawScope, look: SpaceLook, plate: Int, clock: Double) = with(scope) {
        drawRect(Color(0xFF020203))
        val d = density
        val wPt = size.width / d; val hPt = size.height / d
        val scale = maxOf(min(wPt / 358f, hPt / 470f), 0.01f)
        val pitch = 4f
        val dot = pitch * scale * d * 0.46f
        val dark = rgb(look.shadow); val light = rgb(look.light)
        var sx = look.sunX; var sy = look.sunY; var sz = look.sunZ
        val sl = sqrt(sx * sx + sy * sy + sz * sz); sx /= sl; sy /= sl; sz /= sl
        val cols = (358 / pitch).toInt(); val rows = (470 / pitch).toInt()
        val ox = size.width / 2 - 179f * scale * d; val oy = size.height / 2 - 235f * scale * d
        for (j in 0 until rows) for (i in 0 until cols) {
            val px = (i + 0.5f) * pitch; val py = (j + 0.5f) * pitch
            val qx = (px - look.x) / look.radius; val qy = (py - look.y) / look.radius
            val rr = qx * qx + qy * qy
            var r = 0f; var g = 0f; var b = 0f
            if (rr < 1f) {
                val z = sqrt(1f - rr)
                val diffuse = maxOf(0f, qx * sx + qy * sy + z * sz)
                val band = 0.5f + 0.3f * sin((qy * 9f + plate).toDouble()).toFloat()
                val k = 0.009f + diffuse * 1.13f
                r = (dark[0] + (light[0] - dark[0]) * band) * k
                g = (dark[1] + (light[1] - dark[1]) * band) * k
                b = (dark[2] + (light[2] - dark[2]) * band) * k
            } else {
                val h = hash(i.toFloat() + plate * 17f, j.toFloat())
                if (h > 0.985f) {
                    val breath = 0.76f + 0.24f * sin(clock * (0.9 + h) + h * 40).toFloat()
                    r = 0.5f * breath; g = r; b = r
                }
            }
            val lower = 1f - smoothstep(0.58f, 0.94f, py / 470f) * 0.94f
            r = r * lower; g = g * lower; b = b * lower
            r = r * 2.15f / (1 + 1.35f * r); g = g * 2.15f / (1 + 1.35f * g); b = b * 2.15f / (1 + 1.35f * b)
            if (r + g + b < 0.01f) continue
            drawCircle(Color(r.coerceIn(0f, 1f), g.coerceIn(0f, 1f), b.coerceIn(0f, 1f)), dot,
                Offset(ox + px * scale * d, oy + py * scale * d))
        }
    }

    private fun hash(x: Float, y: Float): Float {
        val v = sin(x * 127.1f + y * 311.7f) * 43758.547f
        return v - floor(v)
    }

    private fun smoothstep(a: Float, b: Float, x: Float): Float {
        val t = ((x - a) / (b - a)).coerceIn(0f, 1f)
        return t * t * (3 - 2 * t)
    }
}
