#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// 02 · 05 CONNECTED · two hands, printed, then printed brighter.
//
// The picture is one photograph of two hands reaching across a black ground, split along
// the anti-diagonal through the point where the fingertips meet. Each half is sampled at
// an offset along the diagonal, so the hands start apart and slide in as `approach` runs
// 0→1. Everything is a print: cells quantised through the 8×8 Bayer matrix, the same
// screen the globe and the AI panel use — the picture is never a photograph on this
// screen. Before the touch it is a sparse print in lime. At the touch a ring leaves the
// contact point, and inside it the print is denser and runs up through pale to white.
// Once the whole frame is lit, a slow pulse keeps leaving the same point.
//
// The output has alpha: the ground is clear, so whatever sits behind the picture (the
// burst's rays) shows through between the cells.

constant int HR_BAYER8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

static float hr_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float hr_gray(half4 c) {
    float g = dot(float3(c.rgb), float3(0.299, 0.587, 0.114));
    // JPEG black is not black; floor it so the ground prints as nothing.
    return smoothstep(0.035, 1.0, g);
}

// The lit print's ramp: deep lime → lime → pale → white, per level.
static half3 hr_ramp(float t, half3 lime, half3 pale, half3 white) {
    // Four stops, not three: the shadow end runs from a third of the lime up to lime, so
    // the levels below the mid-tone are visibly darker rather than all reading as "lime".
    half3 shadow = lime * 0.30h;
    half3 deep = lime * 0.62h;
    if (t < 0.30) return mix(shadow, deep, half(t / 0.30));
    if (t < 0.62) return mix(deep, lime, half((t - 0.30) / 0.32));
    if (t < 0.86) return mix(lime, pale, half((t - 0.62) / 0.24));
    return mix(pale, white, half((t - 0.86) / 0.14));
}

// Which hand a point belongs to: top-right of the anti-diagonal through the touch is +1.
static float hr_side(float2 p, float2 touch) {
    return (p.x - touch.x) - (p.y - touch.y) > 0.0 ? 1.0 : -1.0;
}

/// `size` is the layer in points. `cell` is the print cell in points. `print` 0…1 brings
/// the cells in; `approach` 0…1 closes the hands; `reveal` is the ring radius in points
/// (≤ 0 before the touch); `gapMax` is how far each hand starts from rest, along the
/// diagonal; `touch` is the contact point in points; `spark` 0…1 is the flash at contact;
/// `pulse` 0…1 is the after-pulse's phase (radius fraction), ≤ 0 when there is none.
[[ stitchable ]] half4 nbHandsReveal(float2 position, SwiftUI::Layer layer,
                                     float2 size, float cell, float time,
                                     float print, float approach, float reveal,
                                     float gapMax, float2 touch, float spark, float pulse,
                                     half4 ink, half4 lime, half4 pale, half4 white) {
    // The top hand travels down-left to the meeting point; the bottom hand the reverse.
    const float2 A = float2(-0.70710678, 0.70710678);
    float gap = gapMax * (1.0 - approach);

    // Everything below is computed for the cell, so every pixel in a cell agrees and the
    // picture — ring, flash and pulse included — is made of cells.
    float2 cellIndex = floor(position / cell);
    float2 pc = (cellIndex + 0.5) * cell;

    float maxR = length(size) * 0.62;
    float dist = length(pc - touch);
    float2 dir = dist > 0.5 ? (pc - touch) / dist : float2(0.0);
    // Light leaves the picture's bottom edge softly rather than crossing the lines under it.
    float below = 1.0 - smoothstep(0.0, 44.0, pc.y - size.y);

    // The ring: alive from the touch until it has left the frame.
    float ringAlive = reveal > 0.0
        ? smoothstep(0.0, 40.0, reveal) * (1.0 - smoothstep(0.75 * maxR, maxR, reveal))
        : 0.0;
    float ringK = exp(-pow((dist - reveal) / 70.0, 2.0)) * ringAlive;

    // Heat shimmer on the sparse print, gone once the picture is lit.
    float litness = reveal > 0.0 ? smoothstep(0.0, maxR, reveal) : 0.0;
    float2 wave = float2(sin(pc.y * 0.021 + time * 1.3),
                         sin(pc.x * 0.017 + time * 0.9)) * 1.6 * (1.0 - litness);

    // Sample the hand this cell belongs to, displaced along the diagonal, refracted a
    // little just ahead of the ring.
    float side = hr_side(pc, touch);
    float2 s = pc + side * A * gap + wave + dir * ringK * 12.0;
    // While the hands are apart a cell must only ever show its own hand: sampling across
    // the seam would print the other hand's fingertip twice.
    float own = gap > 0.5 ? (hr_side(s, touch) == side ? 1.0 : 0.0) : 1.0;
    float g = hr_gray(layer.sample(s)) * own;

    // The hand must read as a drawing, not as a filled shape. Two things print: the
    // contour, taken as the difference across a cell in each direction, and the specular
    // highlights along the rim. Everything between them — the wide even mid-tone down the
    // forearm — is pushed under the first level, so the print stays open.
    float gx = abs(hr_gray(layer.sample(s + float2(cell, 0.0)))
                 - hr_gray(layer.sample(s - float2(cell, 0.0))));
    float gy = abs(hr_gray(layer.sample(s + float2(0.0, cell)))
                 - hr_gray(layer.sample(s - float2(0.0, cell))));
    float edge = clamp((gx + gy) * 1.9, 0.0, 1.0) * own;

    // Ordered dither, the matrix drifting so the grain crawls.
    int shift = int(floor(time * 3.0));
    int mx = (int(cellIndex.x) + shift) & 7;
    int my = (int(cellIndex.y) + shift) & 7;
    // The top threshold stays under a half, so pure black never prints a cell.
    float m = float(HR_BAYER8[my * 8 + mx]) / 64.0 - 0.5;

    // Each cell is born at its own moment while the print comes in.
    float born = hr_hash(cellIndex * 0.37 + 3.1);
    float on = step(born, print);

    // The forearms leave through the corners, and a frame edge cutting one straight across
    // reads as a severed hand. Near the edges a cell survives only by chance, and the odds
    // fall to nothing at the edge itself — so what leaves the picture is grain, not a stump.
    float fade = min(min(smoothstep(0.0, 96.0, pc.y), smoothstep(0.0, 150.0, size.y - pc.y)),
                     min(smoothstep(0.0, 44.0, pc.x), smoothstep(0.0, 44.0, size.x - pc.x)));
    float alive = step(hr_hash(cellIndex * 1.71 + 9.37), fade);

    // Sparse print · five levels in lime. The contour, and the modelling behind it: the
    // shadowed side of a forearm keeps a level or two so it is a round thing in the dark.
    float vPrint = max(edge * 0.55, pow(g, 2.8) * 0.85);
    const float L0 = 5.0;
    float i0 = clamp(round(vPrint * (L0 - 1.0) + m), 0.0, L0 - 1.0);
    float f0 = i0 / (L0 - 1.0) * on;
    half3 printed = lime.rgb * half(f0);
    float a0 = f0;

    // Lit print · eight levels up the ramp, and the gamma is gentle enough that the light
    // running down a forearm lands on four or five different levels instead of pinning
    // every cell to the top. That gradient is the whole difference between a lit arm and
    // a flat blade of colour. White is the specular alone; the contour sits mid-ramp.
    float vLit = max(edge * 0.46, pow(g, 1.60));
    const float L1 = 8.0;
    float i1 = clamp(round(vLit * (L1 - 1.0) + m), 0.0, L1 - 1.0);
    float f1 = i1 / (L1 - 1.0);
    float a1 = f1 > 0.0 ? 1.0 : 0.0;
    half3 lit = hr_ramp(f1, lime.rgb, pale.rgb, white.rgb) * half(a1);

    // Inside the ring the sparse print gives way to the lit one.
    float soft = 60.0;
    float inside = reveal > 0.0 ? 1.0 - smoothstep(reveal - soft, reveal + soft, dist) : 0.0;
    half3 rgb = mix(printed, lit, half(inside)) * half(alive);
    float alpha = mix(a0, a1, inside) * alive;

    // The hand has a body, and the body is ink. It is all but invisible against the panel,
    // but it is opaque — which is what puts the burst's rays behind the hands rather than
    // through the gaps between their cells.
    float body = smoothstep(0.09, 0.24, g) * own * alive * (on > 0.0 ? 1.0 : print);
    float bodyA = body * 0.94;
    rgb += ink.rgb * half(bodyA * (1.0 - alpha));
    alpha = alpha + bodyA * (1.0 - alpha);

    // The ring itself: a bright line, its glow reaching a little ahead.
    float line = exp(-pow((dist - reveal) / 9.0, 2.0)) * ringAlive;
    float halo = exp(-pow((dist - reveal) / 34.0, 2.0)) * ringAlive;
    float ringLight = (halo * 0.28 + line * 0.85) * below;
    rgb += (pale.rgb * half(halo * 0.28) + white.rgb * half(line * 0.85)) * half(below);

    // The flash at the contact point.
    float flash = exp(-(dist * dist) / (2.0 * 42.0 * 42.0)) * spark * 0.9;
    rgb += mix(lime.rgb, white.rgb, half(spark)) * half(flash);

    // The after-pulse: a faint ring leaving the same point, again and again.
    float pk = 0.0;
    if (pulse > 0.0) {
        float pr = pulse * maxR;
        pk = exp(-pow((dist - pr) / 30.0, 2.0)) * (1.0 - pulse) * (1.0 - pulse) * 0.22 * below;
        rgb += lime.rgb * half(pk);
    }

    // Premultiplied out: the ground is clear, light is opaque, and the ring, flash and
    // pulse add their own weight so they still show over nothing.
    alpha = clamp(alpha + ringLight + flash + pk, 0.0, 1.0);
    rgb = min(rgb, half3(1.0h));
    return half4(rgb, half(alpha));
}
