//  LiquidRepGlass.metal
//  A navy glass disc with a lime spill that follows the fill. `fill` and `glow`
//  are the dial's displayed fraction and glow. `meniscus` is the leading-edge
//  wobble, −1…1, and it brightens the rim while the liquid is moving.
//
//  Use with:
//    .colorEffect(liquidRepGlass(size, fill, glow, meniscus))
//  The Canvas highlight is the fallback when this is unavailable.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 liquidRepGlass(
    float2 position,
    half4 color,
    float2 size,
    float fill,
    float glow,
    float meniscus
) {
    float2 uv = position / max(size, float2(1.0));
    float2 c = uv - 0.5;
    float r = length(c) * 2.0;
    float rim = smoothstep(0.62, 0.84, r) * (1.0 - smoothstep(0.96, 1.08, r));
    float sheen = smoothstep(0.0, 0.55, 0.42 - c.y) * (1.0 - smoothstep(0.15, 0.95, r));
    float wobble = 0.85 + 0.15 * clamp(meniscus, -1.0, 1.0);
    half3 lime = half3(0.70, 0.96, 0.32);
    half3 glass = half3(0.62, 0.74, 0.88);
    half amount = half(rim * glow * wobble * (0.35 + 0.65 * clamp(fill, 0.0, 1.0)));
    half3 rgb = color.rgb;
    rgb += lime * amount;
    rgb += glass * half(sheen * 0.22);
    return half4(min(rgb, half3(1.0)), color.a);
}
