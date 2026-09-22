#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// One fragment per display pixel. There are no repeating video seams, screen-space
// crater stickers, blinking orbit tracks, or CPU particle arrays.
namespace deepSpace {
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

float cloud(float2 p) {
    float sum = 0, amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * noise(p);
        p = float2(p.x * 1.64 - p.y * 1.18, p.x * 1.18 + p.y * 1.64) + 7.3;
        amplitude *= 0.5;
    }
    return sum;
}

float terrain(float3 p) {
    float sum = 0, amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * noise3(p);
        p = p * 2.07 + float3(3.1, 8.7, 2.4);
        amplitude *= 0.5;
    }
    return sum;
}

float2 rotate(float2 p, float angle) {
    return float2(cos(angle) * p.x - sin(angle) * p.y,
                  sin(angle) * p.x + cos(angle) * p.y);
}

// A star owns exactly one cell of the screen, and it never leaves that cell. The field
// used to slide with the camera, which on a lattice this coarse is not drift but a
// twitch — a star sitting still for nine seconds and then jumping a whole pixel. The
// sky is nailed down now, and the only thing a star does is breathe.
float3 stars(float2 p, float time, float seed, float pitch) {
    float3 result = 0;
    float2 here = floor(p / pitch);
    for (int layer = 0; layer < 3; ++layer) {
        float depth = float(layer);
        float cell = 27.0 + depth * 24.0;
        float2 grid = p / cell;
        float2 id = floor(grid) + seed * 17.0 + depth * 109.0;
        float grade = hash(id + 4.7);
        float2 seat = 0.18 + 0.64 * float2(hash(id + 19.2), hash(id + 73.1));
        float2 delta = floor((floor(grid) + seat) * cell / pitch) - here;
        float reach = dot(delta, delta);
        // The lit cell, plus a faint spill into its neighbours for the brightest few.
        float core = step(reach, 0.5);
        float spill = exp(-reach * 2.2) * 0.30 * step(0.88, grade);
        // Not scintillation — the air does that, and there is no air here. This is the
        // slow unequal breathing of a field of point sources, a fifth of a stop at most.
        float breath = 0.76 + 0.24 * sin(time * (0.9 + 1.4 * hash(id + 61.4))
                                         + 6.28 * hash(id + 12.9));
        float brightness = 0.52 * pow(grade, 2.6) * breath;
        // The printed loops' four-colour star palette, so both renderers draw one sky.
        float shade = hash(id + 55.7);
        float3 tint = shade < 0.34 ? float3(1.00, 1.00, 1.00)
                    : shade < 0.58 ? float3(1.00, 0.91, 0.79)
                    : shade < 0.86 ? float3(0.81, 0.89, 1.00)
                                   : float3(0.91, 0.87, 1.00);
        result += tint * (core + spill) * brightness * step(0.76, hash(id));
    }
    return result;
}

// The only fast thing in the scene. Four lanes, each of which fires at most once a
// period and crosses in about half a second, so the plate holds still for long
// stretches and then flicks. Colour is drawn per pass — ice, warm, the house lime,
// and a rare violet — so it never reads as one tinted streak on a timer.
float3 meteors(float2 p, float time, float seed, float pitch) {
    float3 sum = 0;
    for (int lane = 0; lane < 4; ++lane) {
        float period = 12.0 + float(lane) * 5.7;
        float t = time / period + hash(float2(float(lane) * 37.1, seed * 5.3 + 2.0));
        float2 id = float2(floor(t) * 3.7 + float(lane) * 19.0, seed * 11.0 + 4.1);
        if (hash(id) < 0.42) continue;                   // most periods stay empty
        float live = 0.035 + 0.022 * hash(id + 5.0);     // share of the period in flight
        float u = fract(t) / live;
        if (u > 1.0) continue;

        float side = hash(id + 9.0) < 0.5 ? 1.0 : -1.0;
        float angle = 0.42 + 0.62 * hash(id + 13.0);
        float2 dir = float2(cos(angle) * side, sin(angle));
        float2 mid = float2(179.0, 150.0)
                   + float2(250.0 * (hash(id + 23.0) - 0.5), 260.0 * (hash(id + 31.0) - 0.5));
        float2 head = mid + dir * (u * 2.0 - 1.0) * 300.0;
        float tail = 54.0 + 62.0 * hash(id + 41.0);

        float2 pa = p - (head - dir * tail);
        float along = clamp(dot(pa, dir) / tail, 0.0, 1.0);
        float off = length(pa - dir * (along * tail));
        // Thin and cold where the trail has already cooled, a full cell wide at the head.
        float width = pitch * (0.30 + 0.62 * along);
        float streak = exp(-(off * off) / (width * width)) * pow(along, 1.7);
        float spark = exp(-dot(p - head, p - head) / (pitch * pitch * 1.6));
        float fade = smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.80, 1.0, u));

        float pick = hash(id + 57.0);
        float3 tint = pick < 0.42 ? float3(0.80, 0.90, 1.00)
                    : pick < 0.68 ? float3(1.00, 0.90, 0.70)
                    : pick < 0.89 ? float3(0.78, 0.98, 0.42)
                                  : float3(0.92, 0.72, 1.00);
        sum += tint * (streak * 0.62 + spark * 0.95) * fade;
    }
    return sum;
}

// Small craters are projected with longitude/latitude, so the same relief rotates
// across the sphere and foreshortens at its limb. Two scales avoid a uniform golf ball.
float craters(float2 uv, float seed) {
    float shade = 0;
    for (int scale = 0; scale < 2; ++scale) {
        float density = scale == 0 ? 3.4 : 12.0;
        float longitudeCells = scale == 0 ? 22.0 : 76.0;
        float2 p = float2(uv.x / (2.0 * M_PI_F) * longitudeCells, uv.y * density);
        float2 base = floor(p);
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 id = base + float2(x, y);
                float2 wrapped = float2(id.x - floor(id.x / longitudeCells) * longitudeCells, id.y);
                float h = hash(wrapped + seed);
                float2 center = id + 0.2 + 0.6 * float2(hash(wrapped + seed + 17.0), hash(wrapped + seed + 39.0));
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

float3 sphere(float2 p, float radius, float material, float tilt, float inclination, float3 dark,
              float3 bright, float3 air, float3 sun, float time, float seed) {
    float2 q = p / radius;
    float z = sqrt(max(0.0, 1.0 - dot(q, q)));
    float3 normal = float3(q, z);
    // Roughly one turn and a quarter a minute. Read against a clock that is far too fast
    // for a planet; read against a 4-unit screen it is the slowest rate that still moves
    // a surface feature off its pixel while someone is looking at it, and the screen is
    // what sets the floor here. Rotation only — no rocking, no scaling.
    float spin = time * 0.085 + seed * 0.71;
    float3 local = float3(rotate(normal.xy, -tilt), normal.z);
    float pole = sqrt(1.0 - inclination * inclination);
    local.yz = float2(local.y * pole - local.z * inclination,
                      local.y * inclination + local.z * pole);
    float2 rotated = rotate(local.xz, spin);
    float3 surface = float3(rotated.x, local.y, rotated.y);
    float rough = terrain(surface * 4.0 + seed * 3.7);
    float3 albedo;
    if (material < 0.5) {
        float latitude = surface.y * 24.0 + (rough - 0.5) * 6.0;
        float bands = 0.5 + 0.22 * sin(latitude) + 0.11 * sin(latitude * 2.7 + rough * 3.0);
        float wisps = noise3(surface * float3(18.0, 52.0, 18.0) + rough * 2.0);
        albedo = mix(dark, bright, clamp(bands * 0.85 + wisps * 0.25, 0.0, 1.0));
    } else if (material < 1.5) {
        float2 uv = float2(atan2(surface.x, surface.z), asin(clamp(surface.y, -1.0, 1.0)));
        float relief = craters(uv, seed * 7.0);
        float maria = smoothstep(0.37, 0.61, rough);
        albedo = mix(dark, bright, 0.2 + maria * 0.65) * (0.83 + noise3(surface * 95.0) * 0.28);
        albedo *= 1.0 + relief * 1.6;
    } else {
        float land = smoothstep(0.42, 0.63, rough);
        float clouds = smoothstep(0.51, 0.77, terrain(surface * 7.0 + float3(time * 0.001, 9.0, 2.0)));
        albedo = mix(dark, bright * 0.83, land * 0.8);
        albedo = mix(albedo, bright, clouds * 0.68);
    }
    float diffuse = max(dot(normal, sun), 0.0);
    float night = 0.009;
    float3 color = albedo * (night + diffuse * 1.13);
    // Fine forward scattering follows the illuminated limb, never a full neon hoop.
    float grazing = pow(1.0 - z, 3.4);
    float rimLight = pow(max(dot(normalize(float3(q, 0.15)), sun) + 0.18, 0.0), 2.0);
    color += air * grazing * rimLight * (material == 1.0 ? 0.025 : 0.26);
    return color;
}

float4 rings(float2 q, float sphereZ, float4 ring, float3 sun,
             float3 tint, float seed, float pixelWidth, float spin) {
    float2 v = rotate(q, -ring.x);
    float flatten = max(ring.y, 0.06);
    float3 point = float3(v.x, v.y, v.y * sqrt(1.0 - flatten * flatten) / flatten);
    float r = length(float2(v.x, v.y / flatten));
    float aa = max(pixelWidth / flatten, 0.003);
    float mask = smoothstep(ring.z, ring.z + aa, r) * (1.0 - smoothstep(ring.w - aa, ring.w, r));
    if (mask < 0.001 || (sphereZ > 0 && point.z < sphereZ)) return float4(0);

    float width = ring.w - ring.z;
    float radial = (r - ring.z) / width;
    float gap = 1.0 - 0.91 * exp(-pow((radial - 0.66) / 0.027, 2.0));
    float fine = 0.67 + 0.045 * sin(r * 171.0) + 0.025 * sin(r * 317.0 + seed);
    // The divisions are cut in the rock and do not move; the grain orbits, and under
    // Kepler the inner grain laps the outer, so the ring shears instead of turning as
    // one rigid piece. A ring with only radial structure cannot show rotation at all.
    float2 spun = rotate(float2(v.x, v.y / flatten), spin * pow(max(r, 0.5), -1.5));
    float grains = noise(spun * 2.6 + seed);
    float density = (0.34 + 0.36 * grains) * fine * gap;
    float3 worldPoint = float3(rotate(point.xy, ring.x), point.z);
    float b = dot(worldPoint, sun);
    float discriminant = b * b - dot(worldPoint, worldPoint) + 1.0;
    float shadow = b < 0 ? 1.0 - smoothstep(-0.07, 0.04, discriminant) * 0.94 : 1.0;
    float edge = 0.65 + 0.35 * smoothstep(0.0, 0.25, radial);
    float3 color = tint * edge * shadow;
    return float4(color, mask * density);
}
}

[[ stitchable ]] half4 nbDeepSpace(float2 position, half4 source, float2 size,
                                  float time, float seed, float4 body, float4 ring,
                                  half4 darkColor, half4 lightColor, half4 airColor,
                                  float4 lighting) {
    using namespace deepSpace;
    float scale = max(min(size.x / 358.0, size.y / 470.0), 0.01);
    float2 p = (position - size * 0.5) / scale + float2(179.0, 235.0);
    // The plate is an LED screen at the same 4-unit pitch the printed loops use. The
    // scene is sampled once at the centre of each cell and then lit through a round
    // dot, so what reaches the eye is a lit grid rather than a photograph of a planet.
    // Sampling first is what makes it pixel art: a dot screen laid over a smooth render
    // only prints the render finer.
    float pitch = 4.0;
    float2 lamp = fract(p / pitch) * pitch - pitch * 0.5;
    p = (floor(p / pitch) + 0.5) * pitch;
    float2 uv = p / float2(358.0, 470.0);
    float3 air = float3(airColor.rgb);
    // The light is not nailed down. Swinging the sun a third of a radian either side of
    // the plate's authored angle walks the terminator across the disc and drags the
    // ring shadow with it, which is the one change a still frame cannot fake.
    float3 sun = normalize(lighting.xyz);
    // Half a radian either side, about seventy seconds a cycle. The terminator is the
    // highest-contrast edge on the plate and the only feature guaranteed to be several
    // cells wide, so walking it is what makes the light legibly change on a small body.
    sun.xy = rotate(sun.xy, 0.82 * sin(time * 0.088 + seed));
    sun = normalize(sun);

    // Dust is structured noise at astronomical depth, not animated Gaussian blobs.
    float2 sky = rotate((p - float2(179, 185)) / 210.0, -0.45 + seed * 0.13 + time * 0.0075);
    sky += float2(seed * 3.13, time * -0.016);
    float wisps = cloud(sky * float2(2.0, 3.8));
    // Recenter the lane independently of the noise's random seed offset.
    float lane = exp(-pow(rotate((p - float2(179, 175)) / 210.0, -0.45 + seed * 0.13).y * 1.35, 2.0));
    float dust = smoothstep(0.3, 0.78, wisps) * lane;
    // The filaments crawl within the cloud they belong to, an order of magnitude slower
    // than the cloud itself drifts, so the lane changes shape without ever boiling.
    float filaments = cloud(sky * 5.0 + wisps * 1.7 + float2(time * 0.030, time * -0.020));
    float3 color = float3(0.006, 0.008, 0.013);
    // The lane was authored to sit just above black, which through a dot screen meant it
    // sat at black: nothing to see, so nothing that could be seen to change. It carries
    // about two thirds again as much light now, and breathes a quarter either way.
    color += mix(float3(0.145, 0.170, 0.255), air * 0.32, 0.45)
           * dust * (0.3 + filaments * 0.8) * lighting.w
           * (0.76 + 0.24 * sin(time * 0.10 + seed * 2.1));
    color *= 1.0 - smoothstep(0.51, 0.75, filaments) * lane * 0.42;
    color += stars(p, time, seed, pitch);
    color += meteors(p, time, seed, pitch);

    // The camera glides a few points over a minute. There is no 3/8-second reset.
    float2 drift = float2(sin(time * 0.019 + seed) - sin(seed),
                          cos(time * 0.014 + seed) - cos(seed)) * float2(2.3, 3.2);
    float2 q = (p - body.xy - drift) / body.z;
    float rr = dot(q, q);
    float radius = sqrt(rr);
    float pixel = 0.65 / scale / body.z;
    float sphereMask = 1.0 - smoothstep(1.0 - pixel, 1.0 + pixel, radius);
    float sphereZ = rr < 1.0 ? sqrt(1.0 - rr) : -1.0;
    float atmosphere = exp(-max(radius - 1.0, 0.0) * 55.0)
                     * (1.0 - sphereMask) * step(radius, 1.25);
    float limbSun = pow(max(dot(normalize(float3(q, 0.08)), sun), 0.0), 2.0);
    color += air * atmosphere * limbSun * (body.w == 1.0 ? 0.018 : 0.20);
    if (sphereMask > 0.0) {
        float3 surface = sphere(q * body.z, body.z, body.w, ring.x * M_PI_F / 180.0, ring.y, float3(darkColor.rgb),
                                float3(lightColor.rgb), air, sun, time, seed);
        color = mix(color, surface, sphereMask);
    }
    if (ring.w > ring.z) {
        ring.x *= M_PI_F / 180.0;
        float4 r = rings(q, sphereZ, ring, sun,
                         mix(float3(lightColor.rgb), float3(0.73, 0.77, 0.82), 0.3), seed, pixel,
                         time * 0.11);
        color = mix(color, r.rgb, r.a);
    }

    // Readout clearance and filmic edge falloff. No grain that crawls frame-to-frame.
    float lower = 1.0 - smoothstep(0.58, 0.94, uv.y) * 0.94;
    float vignette = 1.0 - smoothstep(0.33, 0.79, length((uv - float2(0.5, 0.39)) * float2(0.9, 0.78))) * 0.6;
    color *= lower * vignette;
    color += (hash(p + seed) - 0.5) / 650.0;
    // A dot screen costs light. Multiplying that light back with a flat gain is what
    // clipped every lit surface to white — and a clipped disc has no gradient left for
    // the rotation to carry, which is why a planet that was demonstrably turning still
    // read as a frozen sticker. Compress into the headroom instead: shadows come up
    // about twice, the lit side lands just under white and keeps its own shading.
    color = color * 2.15 / (1.0 + 1.35 * color);
    // Every cell is one lamp: bright at its centre, down to the panel's own ink at the
    // seam. Grain goes in before this, so it is the cell that is noisy, not the glass.
    color *= 0.44 + 0.64 * exp(-dot(lamp, lamp) / (2.0 * 0.95 * 0.95));
    return half4(half3(clamp(color, 0.0, 1.0)), source.a);
}
