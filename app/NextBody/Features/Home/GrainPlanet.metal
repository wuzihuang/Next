#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// The home planets as a fine grain screen: the scene is sampled once per grain, each grain
// is a soft lamp, and a smooth neon halo sits under the whole field so the disc glows
// instead of reading as a tiled mosaic.
namespace grainPlanet {
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
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
               mix(hash(i + float2(0, 1)), hash(i + 1.0), f.x), f.y);
}

float noise3(float3 p) {
    float3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i + float3(1, 0, 0)), f.x),
            mix(hash3(i + float3(0, 1, 0)), hash3(i + float3(1, 1, 0)), f.x), f.y),
        mix(mix(hash3(i + float3(0, 0, 1)), hash3(i + float3(1, 0, 1)), f.x),
            mix(hash3(i + float3(0, 1, 1)), hash3(i + 1.0), f.x), f.y), f.z);
}

float fbm3(float3 p, int octaves) {
    float sum = 0, amplitude = 0.5;
    for (int i = 0; i < octaves; ++i) {
        sum += amplitude * noise3(p);
        p = p * 2.03 + float3(3.1, 8.7, 2.4);
        amplitude *= 0.5;
    }
    return sum;
}

float fbm2(float2 p) {
    float sum = 0, amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * noise(p);
        p = float2(p.x * 1.64 - p.y * 1.18, p.x * 1.18 + p.y * 1.64) + 7.3;
        amplitude *= 0.5;
    }
    return sum;
}

float2 rotate(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Craters live in longitude/latitude, so they turn with the sphere and foreshorten at the limb.
// Returns (height, east slope, north slope); the slope tilts the normal so the sun lights the
// far wall and leaves the near wall in shadow, which is what makes relief read near the terminator.
float3 craters(float3 s, float seed, float density) {
    float lat = asin(clamp(s.y, -1.0, 1.0));
    float2 uv = float2(atan2(s.x, s.z), lat);
    float coslat = max(cos(lat), 0.15);
    float3 sum = 0;
    for (int scale = 0; scale < 2; ++scale) {
        float rows = (scale == 0 ? 3.6 : 11.0) * density;
        float cols = (scale == 0 ? 22.0 : 70.0) * density;
        float2 p = float2(uv.x / (2.0 * M_PI_F) * cols, uv.y * rows);
        float2 base = floor(p);
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 id = base + float2(x, y);
                float2 wrapped = float2(id.x - floor(id.x / cols) * cols, id.y);
                float h = hash(wrapped + seed);
                if (h < (scale == 0 ? 0.62 : 0.72)) continue;
                float2 center = id + 0.2 + 0.6 * float2(hash(wrapped + seed + 17.0), hash(wrapped + seed + 39.0));
                float2 offset = p - center;
                float radius = 0.06 + 0.32 * h * h * h;
                float len = length(offset);
                float d = len / radius;
                if (d > 1.6) continue;
                float bowl = exp(-d * d * 3.0);
                float rim = exp(-pow((d - 0.87) * 6.0, 2.0));
                float height = rim * 0.10 - bowl * 0.16;
                float slope = (-72.0 * (d - 0.87) * rim * 0.10 + 6.0 * d * bowl * 0.16) / radius;
                float2 g = slope * offset / max(len, 0.0001);
                sum += float3(height, g.x * cols / (2.0 * M_PI_F) / coslat, g.y * rows);
            }
        }
    }
    return sum;
}

// Tilt the sphere normal `s` by a height slope given in (east, north).
float3 bump(float3 s, float2 slope, float strength) {
    float3 east = normalize(float3(s.z, 0.0, -s.x) + float3(0.0001, 0.0, 0.0));
    float3 north = cross(s, east);
    return normalize(s - strength * (slope.x * east + slope.y * north));
}

struct Look {
    float3 inner;   // atmosphere hugging the limb
    float3 outer;   // neon fringe further out
    float rim;
    float halo;
};

Look look(int kind) {
    if (kind == 0) return { float3(0.28, 0.72, 1.00), float3(0.58, 0.32, 1.00), 1.00, 0.55 };
    if (kind == 1) return { float3(0.70, 0.64, 1.00), float3(0.30, 0.82, 1.00), 0.45, 0.30 };
    return { float3(1.00, 0.48, 0.22), float3(1.00, 0.24, 0.58), 0.70, 0.42 };
}

// Slope of a rolling height field along (east, north), by finite differences.
float2 reliefSlope(float3 s, float frequency, float seed) {
    const float e = 0.012;
    float3 east = normalize(float3(s.z, 0.0, -s.x) + float3(0.0001, 0.0, 0.0));
    float3 north = cross(s, east);
    float h0 = fbm3(s * frequency + seed, 3);
    float he = fbm3((s + east * e) * frequency + seed, 3);
    float hn = fbm3((s + north * e) * frequency + seed, 3);
    return float2(he - h0, hn - h0) / e;
}

// Surface colour at sphere point `s` (rotated into the planet's frame). `emission` carries
// light that does not depend on the sun: city grids and earthshine. `normal` is the shading
// normal in the same frame; rocky bodies tilt it with their relief.
float3 surface(int kind, float3 s, float3 cs, float3 n, float3 sun, float night,
               float time, thread float3 &emission, thread float3 &normal) {
    emission = 0;
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
        if (night < 0.001 || land < 0.001) return albedo;

        float3 lot = floor(s * 95.0);
        float sprawl = smoothstep(0.42, 0.68, fbm3(s * 5.0 + 7.0, 3));
        float lamp = step(0.62, hash3(lot)) * sprawl * land * (1.0 - ice) * (1.0 - cloud * 0.85);
        float pick = hash3(lot + 13.0);
        float3 tint = pick < 0.72 ? float3(1.00, 0.62, 0.26)
                    : pick < 0.90 ? float3(0.30, 0.92, 1.00)
                                  : float3(1.00, 0.32, 0.78);
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
    // The rift is a trench: its walls slope toward the centre line.
    float riftLine = s.y + 0.12 + 0.06 * sin(s.x * 7.0 + s.z * 3.0);
    float riftSlope = 2.0 * riftLine * 26.0 * 26.0 * exp(-pow(riftLine * 26.0, 2.0))
                    * smoothstep(-0.6, 0.2, s.z);
    float2 slope = crater.yz * 0.015 + reliefSlope(s, 4.0, 6.0) * 0.040 * (1.0 - cap)
                 + float2(0.0, riftSlope * 0.0045);
    normal = bump(s, slope, 1.0);
    return albedo;
}

// Stars sit on the grain lattice: each seat is exactly one grain, and the brightest few
// spill a soft cross into their neighbours.
float3 stars(float2 here, float2 size, float pitch, float amount, float time) {
    float3 sum = 0;
    float area = size.x * size.y;
    for (int layer = 0; layer < 2; ++layer) {
        float count = amount * (layer == 0 ? 1.4 : 7.0);
        float cell = sqrt(area / max(count, 1.0));
        float2 p = (here + 0.5) * pitch;
        float2 g = floor(p / cell);
        float2 id = g + float(layer) * 131.0;
        if (hash(id + 2.1) > (layer == 0 ? 0.80 : 0.86)) continue;
        float2 seat = floor((g + 0.15 + 0.70 * float2(hash(id + 19.2), hash(id + 73.1))) * cell / pitch);
        float2 delta = seat - here;
        float reach = dot(delta, delta);
        float grade = hash(id + 4.7);
        float bright = layer == 0 ? 0.30 + 0.70 * pow(grade, 1.6) : 0.10 + 0.22 * grade;
        float twinkle = 0.55 + 0.45 * sin(time * (0.5 + hash(id + 8.3) * 1.6) + hash(id + 3.9) * 6.283);
        float core = step(reach, 0.5);
        float spill = layer == 0 ? exp(-reach * 0.9) * 0.40 * step(0.55, grade) : 0.0;
        float cross = layer == 0 && grade > 0.86
            ? (exp(-abs(delta.x) * 0.55) * step(abs(delta.y), 0.5)
               + exp(-abs(delta.y) * 0.55) * step(abs(delta.x), 0.5)) * 0.28 * step(0.5, reach)
            : 0.0;
        float shade = hash(id + 55.7);
        float3 tint = shade < 0.40 ? float3(1.00, 1.00, 1.00)
                    : shade < 0.62 ? float3(0.70, 0.88, 1.00)
                    : shade < 0.80 ? float3(1.00, 0.88, 0.74)
                    : shade < 0.92 ? float3(0.45, 1.00, 0.95)
                                   : float3(1.00, 0.55, 0.92);
        sum += tint * (core + spill + cross) * bright * twinkle;
    }
    return sum;
}
}

/// body: centre (pt), radius (pt), grain pitch (pt)
/// light: sun direction (x right, y up, z toward viewer), kind (0 terra, 1 luna, 2 mars)
/// clock: surface spin (rad), cloud spin (rad), seconds, star amount
[[ stitchable ]] half4 nbGrainPlanet(float2 position, half4 source, float2 size,
                                     float4 body, float4 light, float4 clock) {
    using namespace grainPlanet;
    int kind = int(light.w + 0.5);
    Look style = look(kind);
    float pitch = max(body.w, 0.5);
    float radius = max(body.z, 1.0);
    float time = clock.z;
    float3 sun = normalize(light.xyz);

    float2 here = floor(position / pitch);
    float2 cp = (here + 0.5) * pitch;
    float2 lamp = (position - cp) / pitch;

    // The surface is sampled at the true pixel, not the grain centre: the grain screen stays
    // fixed while the world glides under it, so the turn is continuous instead of stepping a
    // whole grain at a time.
    float2 q = (position - body.xy) / radius;
    q.y = -q.y;
    float rr = dot(q, q);

    float3 col = 0;
    if (rr < 1.0) {
        float z = sqrt(1.0 - rr);
        float3 n = float3(q, z);
        // Axial tilt, then the turn about the planet's own pole. The sun goes through the same
        // turn so relief normals can be lit in the planet's frame.
        float3 t = float3(rotate(n.xy, 0.38), n.z);
        float3 s = float3(rotate(t.xz, clock.x), t.y).xzy;
        float3 cs = float3(rotate(t.xz, clock.y), t.y).xzy;
        float3 st = float3(rotate(sun.xy, 0.38), sun.z);
        float3 sunLocal = float3(rotate(st.xz, clock.x), st.y).xzy;

        float lambert = dot(n, sun);
        float night = 1.0 - smoothstep(-0.18, 0.04, lambert);
        float3 emission, normal;
        float3 albedo = surface(kind, s, cs, n, sun, night, time, emission, normal);
        float limb = 0.70 + 0.30 * z;
        if (kind == 0) {
            float dayside = smoothstep(-0.07, 0.28, lambert);
            col = albedo * (0.012 + (max(lambert, 0.0) * 0.95 + dayside * 0.30) * limb);
        } else {
            // Airless rock: a hard terminator, relief lit by the tilted normal, and a night
            // side that falls to almost nothing. Low sun stretches the crater shadows.
            float relief = max(dot(normal, sunLocal), 0.0);
            float terminator = smoothstep(-0.03, 0.10, lambert);
            float grazing = 1.0 - smoothstep(0.0, 0.45, lambert);
            float lit = relief * terminator;
            lit *= mix(1.0, smoothstep(0.0, 0.55, relief), grazing * 0.85);
            col = albedo * (0.003 + lit * 1.30 * (0.82 + 0.18 * z));
        }
        col += emission;

        float fresnel = pow(1.0 - z, 2.6);
        float rimFloor = kind == 0 ? 0.22 : 0.04;
        float rimSun = rimFloor + (1.0 - rimFloor) * smoothstep(-0.35, 0.45, lambert);
        col += mix(style.inner, style.outer, fresnel) * fresnel * style.rim * rimSun * 0.85;

        // A slow holographic scan, a breath of neon drifting down the disc.
        float scanY = 1.35 - fract(time / 11.0) * 2.7;
        float scan = exp(-pow((q.y - scanY) * 16.0, 2.0));
        col += style.outer * scan * 0.07 * (0.4 + 0.6 * smoothstep(-0.07, 0.28, lambert));

        col *= 0.90 + 0.18 * hash(here + float(kind) * 7.0);
    } else {
        col += stars(here, size, pitch, clock.w, time);
        // Faint nebula dust around the body, quantised to the grain like everything else.
        float2 sky = (cp - body.xy) / (radius * 2.6);
        float wisps = fbm2(sky * 2.2 + float2(time * 0.006, -time * 0.004) + float(kind) * 5.0);
        float dust = smoothstep(0.42, 0.85, wisps) * exp(-dot(sky, sky) * 0.9);
        col += mix(style.outer, style.inner, fbm2(sky * 4.0 + 3.0)) * dust * 0.045;
    }

    // Filmic shoulder, then each grain lit as a soft lamp; the floor keeps the gaps glowing.
    col = 1.0 - exp(-col * 1.55);
    float grain = exp(-dot(lamp, lamp) / (2.0 * 0.30 * 0.30));
    float3 outColor = col * (0.20 + 0.95 * grain);

    // Smooth halo, sampled per display pixel so the bloom never shows the lattice.
    float2 qs = (position - body.xy) / radius;
    float d = length(qs);
    float2 qn = float2(qs.x, -qs.y) / max(d, 0.0001);
    float facing = smoothstep(-0.55, 0.65, dot(qn, normalize(sun.xy + 0.0001)) * 0.8 + sun.z * 0.6);
    float beyond = max(d - 1.0, 0.0);
    float hug = exp(-beyond * 16.0) * smoothstep(0.90, 1.0, d);
    float bloom = exp(-beyond * 3.2) * step(1.0, d);
    float3 halo = style.inner * hug * 0.55
                + mix(style.inner, style.outer, smoothstep(0.0, 0.35, beyond)) * bloom * 0.16;
    halo += style.inner * (1.0 - smoothstep(0.0, 1.0, d)) * 0.035;
    outColor += halo * style.halo * (0.30 + 0.70 * facing);

    return half4(half3(clamp(outColor, 0.0, 1.0)), source.a);
}
