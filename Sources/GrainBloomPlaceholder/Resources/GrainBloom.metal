#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float grainHash(int2 cell, uint seed) {
    uint n = uint(cell.x) * 0x8DA6B343u ^ uint(cell.y) * 0xD8163841u ^ seed * 0xCB1AB31Fu;
    n ^= n >> 15;
    n *= 0x2C1B3C6Du;
    n ^= n >> 12;
    n *= 0x297A2D39u;
    n ^= n >> 15;
    return float(n) * (1.0 / 4294967296.0);
}

/// Film grain plus a dither veil. Canvas draws the same mask when this shader
/// is unavailable. `progress` is the resolve amount, 0...1.
[[ stitchable ]] half4 grainBloom(float2 position, half4 color, float seed, float progress, float cell) {
    int2 dot = int2(floor(position / max(cell, 1.0)));
    float n = grainHash(dot, uint(seed * 16777216.0));
    float veil = mix(0.35, 1.0, saturate(progress));
    half3 rgb = color.rgb * half(veil) + half3(n * 0.08);
    return half4(rgb, color.a);
}
