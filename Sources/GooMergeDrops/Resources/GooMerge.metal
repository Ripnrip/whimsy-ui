//  GooMerge.metal
//  Signed-distance field for GooMergeDrops. Five circles packed as float4
//  (x, y, radius, 1 = live). The blend is the same polynomial smooth-min as
//  GooMergeField.smoothMin, with GooMergeTuning.smoothK.
//
//  Use with:
//    .layerEffect(gooMergeSDF(d0, d1, d2, d3, d4, smoothK, glow, morph),
//                 maxSampleOffset: CGSize(width: 1, height: 1))
//  The Canvas blur + alphaThreshold path is the fallback when this is unavailable.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float gooSmoothMin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / max(k, 1e-4);
    return min(a, b) - h * h * k * 0.25;
}

static float circleSDF(float2 position, float4 drop) {
    if (drop.w < 0.5) return 1e6;
    return length(position - drop.xy) - drop.z;
}

[[ stitchable ]] half4 gooMergeSDF(
    float2 position,
    SwiftUI::Layer layer,
    float4 d0,
    float4 d1,
    float4 d2,
    float4 d3,
    float4 d4,
    float smoothK,
    float glow,
    float morph
) {
    float s = circleSDF(position, d0);
    s = gooSmoothMin(s, circleSDF(position, d1), smoothK);
    s = gooSmoothMin(s, circleSDF(position, d2), smoothK);
    s = gooSmoothMin(s, circleSDF(position, d3), smoothK);
    s = gooSmoothMin(s, circleSDF(position, d4), smoothK);

    float alpha = 1.0 - smoothstep(-1.4, 1.4, s);
    half4 under = layer.sample(position);
    if (alpha <= 0.001) return half4(under.rgb, 0.0);

    float rim = smoothstep(-12.0, -1.2, s);
    half3 honey = half3(0.96, 0.62, 0.28);
    half3 crust = half3(0.42, 0.16, 0.06);
    half3 color = mix(honey, crust, rim * 0.9);
    color += half3(1.0, 0.75, 0.42) * glow * (1.0 - rim) * 0.45;
    color = mix(color, half3(0.98, 0.95, 0.90), saturate(morph));
    return half4(color, half(alpha));
}
