//  HoloFoil.metal
//  Holographic foil for HoloFoilCard: a rainbow diffraction band that sweeps across the card with
//  the tilt, a faint all-over foil tint, a soft glare that slides opposite the tilt, and sparkles that
//  only light inside their own angle window. Mirrors HoloShading in HoloCore line for line (a test
//  checks the constants match).
//
//  Use with: .colorEffect(holoFoil(size, tilt, strength))   — tilt normalised to −1…1 (yaw, pitch)

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float kSweep = 0.7;
constant float kYawWeight = 0.6;
constant float kPitchWeight = 0.4;
constant float kBandWidth = 0.16;
constant float kBandStrength = 0.55;
constant float kHueSpread = 0.35;
constant float kFoilStrength = 0.08;
constant float kGlareStrength = 0.22;
constant float kGlareSize = 0.08;
constant float kSparkleCell = 14.0;
constant float kSparkleDensity = 0.5;
constant float kSparkleWindow = 0.35;
constant float kSparkleStrength = 0.9;

static float3 rainbow(float hue) {
    const float t = 2.0 * M_PI_F;
    return 0.5 + 0.5 * cos(t * (hue + float3(0.0, 0.33, 0.67)));
}

// lowbias32 — same as HoloShading.hash32 and the web port.
static uint hash32(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}
static float unit01(uint x) { return float(x & 0xFFFFFFu) / 16777216.0; }

static float glint(float2 d, float r) {
    float ax = abs(d.x), ay = abs(d.y);
    float core = exp(-dot(d, d) / (1.4 * 1.4));
    float arms = exp(-ay / 0.8) * max(0.0, 1.0 - ax / r) + exp(-ax / 0.8) * max(0.0, 1.0 - ay / r);
    return core + 0.6 * arms;
}

static float sparkleLight(float2 p, float2 n) {
    int cx = int(floor(p.x / kSparkleCell)), cy = int(floor(p.y / kSparkleCell));
    float total = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            int x = cx + i, y = cy + j;
            if (x < 0 || y < 0) continue;
            uint base = hash32(uint(x) + hash32(uint(y) + 0x9E37u));
            if (unit01(base) >= kSparkleDensity) continue;
            float2 o = float2(0.2 + 0.6 * unit01(hash32(base ^ 1u)), 0.2 + 0.6 * unit01(hash32(base ^ 2u)));
            float2 w = float2(2.0 * unit01(hash32(base ^ 3u)) - 1.0, 2.0 * unit01(hash32(base ^ 4u)) - 1.0);
            float r = 3.0 + 3.0 * unit01(hash32(base ^ 5u));
            float g = 1.0 - smoothstep(kSparkleWindow * 0.4, kSparkleWindow, length(n - w));
            if (g <= 0.0) continue;
            total += g * glint(p - (float2(x, y) + o) * kSparkleCell, r);
        }
    }
    return total;
}

[[ stitchable ]] half4 holoFoil(float2 position, half4 color, float2 size, float2 tilt, float strength) {
    float a = float(color.a);
    if (a <= 0.0) return color;
    float2 n = clamp(tilt, -1.0, 1.0);
    float2 uv = position / size;
    float2 axis = normalize(float2(1.0, 0.6));
    float band0 = kSweep * (kYawWeight * n.x - kPitchWeight * n.y);
    float x = (dot(uv - 0.5, axis) - band0) / kBandWidth;
    float band = exp(-x * x);
    float hue = x * kHueSpread + 0.15 * (n.x + n.y) + 0.25 * uv.y;
    float foilHue = 0.6 * (uv.x + uv.y) + 0.3 * n.x - 0.2 * n.y;
    float2 g = uv - float2(0.5 - 0.45 * n.x, 0.5 + 0.45 * n.y);
    float glare = kGlareStrength * exp(-dot(g, g) / kGlareSize);
    float sp = kSparkleStrength * sparkleLight(position, n);
    float3 light = rainbow(hue) * (kBandStrength * band) + rainbow(foilHue) * kFoilStrength
                 + float3(glare) + float3(1.0, 0.97, 0.9) * sp;
    // Premultiplied: add light in proportion to coverage, capped so it never exceeds alpha.
    float3 rgb = min(float3(color.rgb) + light * (strength * a), float3(a));
    return half4(half3(rgb), color.a);
}
