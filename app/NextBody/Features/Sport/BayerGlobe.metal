#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// 14 · LIVE SESSION · the turning world, ordered-dithered.
//
// Inside the disc the screen offsets are two components of the surface normal and the
// third is whatever makes the length one. Longitude and latitude are read off that
// normal, so a noise field cut at one level wraps the sphere as land and slides off the
// limb as it turns. Coasts are lit a shade brighter than the interior — that is what
// separates a coast from a smudge. Every cell is then quantised through an 8×8 Bayer
// matrix, the same printed-not-lit idea as the panel's dot screen, in lime on the panel's ink.

// The threshold map. Neighbouring cells are as far apart in the sequence as possible,
// which is what makes the grain read as even rather than clumped.
constant int BAYER8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

static float nb_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float nb_noise(float2 p) {
    float2 i = floor(p);
    float2 f = p - i;
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = nb_hash(i);
    float b = nb_hash(i + float2(1, 0));
    float c = nb_hash(i + float2(0, 1));
    float d = nb_hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Three octaves. A fourth costs a third more and shows almost nothing at this cell size.
static float nb_fbm(float2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 3; i++) {
        v += nb_noise(p) * amp;
        p *= float2(2.03, 2.01);
        amp *= 0.5;
    }
    return v;
}

/// `effort` is 0…1 — where the heart sits in its range. It moves the palette: lime at an
/// easy pace, warming through the amber the product uses for "we need you to move" as the
/// rate climbs, and the coasts and the halo swell harder on each beat with it.
/// `center` and `radius` are in the view's own points. `cell` is the dither cell size in
/// points; every screen pixel inside a cell samples the cell's centre, so the picture is
/// made of square cells, never of anti-aliased edges. `beat` is 0…1 — the heart's pulse,
/// swelling the halo and the coasts for a moment.
[[ stitchable ]] half4 nbBayerGlobe(float2 position, half4 color,
                                    float2 center, float radius, float cell,
                                    float time, float spin, float beat,
                                    float landLevel, float levels, float glowReach,
                                    float effort,
                                    half4 ink, half4 lime, half4 hot, half4 ember) {
    float2 cellIndex = floor(position / cell);
    float2 p = (cellIndex + 0.5) * cell;
    float dx = p.x - center.x;
    float dy = p.y - center.y;
    float rr = sqrt(dx * dx + dy * dy);
    float R = max(1.0, radius);

    // A fixed key light from the upper left, the same lamp the standby planet is lit by.
    float3 L = normalize(float3(-0.5, -0.4, 1.0));

    float v;
    if (rr < R) {
        float nx = dx / R, ny = dy / R;
        float nz = sqrt(max(0.0, 1.0 - nx * nx - ny * ny));
        float lam = max(0.0, nx * L.x + ny * L.y + nz * L.z);
        float lon = atan2(nx, nz) + spin;
        float lat = asin(clamp(ny, -1.0, 1.0));
        float land = nb_fbm(float2(lon * 1.6 + 10.0, lat * 2.2 + 5.0));
        bool isLand = land > landLevel;
        float coast = abs(land - landLevel) < 0.035 ? 0.22 + 0.14 * beat : 0.0;
        // Lit from the key light with an ambient floor, so the dark side is a body and not
        // a hole — the panel is printed, and print has no black.
        float lit = 0.30 + 0.80 * lam;
        v = lit * (isLand ? 1.0 : 0.56) + coast;
        // The limb catches the halo, brighter on a beat and harder the harder the heart works.
        float limb = smoothstep(0.80, 1.0, rr / R);
        v += limb * (0.08 + (0.10 + 0.14 * effort) * beat);
    } else {
        // The halo: a thin bright rim that falls away over `glowReach` radii, and swells
        // with the heart. Outside it the ground is the panel's own ink.
        float d = (rr - R) / (R * glowReach);
        float halo = max(0.0, 1.0 - d);
        float rim = exp(-(rr - R) / (R * 0.06));
        v = halo * halo * halo * (0.085 + (0.07 + 0.10 * effort) * beat)
          + rim * (0.24 + (0.18 + 0.22 * effort) * beat);
    }

    // Ordered dithering: the threshold is where the cell sits in the 8×8 matrix, and the
    // matrix's origin drifts with time so the grain crawls instead of sitting fixed.
    int shift = int(floor(time * 4.0));
    int mx = (int(cellIndex.x) + shift) & 7;
    int my = (int(cellIndex.y) + shift) & 7;
    float m = float(BAYER8[my * 8 + mx]) / 64.0 - 0.5;

    float last = max(1.0, levels - 1.0);
    float idx = clamp(round(v * last + m), 0.0, last);
    float f = idx / last;
    // The palette answers effort: the lime cools into amber past the middle of the range.
    half4 tone = mix(lime, ember, half(smoothstep(0.35, 0.95, effort)));
    half4 to = (idx >= last && levels > 2.0) ? hot : tone;
    half4 out = mix(ink, to, half(f));
    out.a = 1.0h;
    return out;
}
