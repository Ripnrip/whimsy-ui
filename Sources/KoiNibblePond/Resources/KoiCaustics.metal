//  KoiCaustics.metal
//  KoiNibblePond
//
//  A cheap caustic wash for the pond floor. SwiftUI supplies position and color.
//  Used as: ShaderLibrary.bundle(.module).koiCaustics(.float(time), .float2(width, height))

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 koiCaustics(float2 position, half4 color, float time, float2 pond) {
    float2 size = max(pond, float2(1.0));
    float2 uv = position / size;
    float a = sin(uv.x * 14.0 + time * 0.65) * sin(uv.y * 11.0 - time * 0.45);
    float b = sin((uv.x + uv.y) * 9.0 + time * 0.35);
    float c = sin((uv.x * 1.7 - uv.y) * 8.0 - time * 0.28);
    float w = (a * 0.5 + b * 0.3 + c * 0.2) * 0.5 + 0.5;
    half lift = half(0.05 + 0.16 * w);
    half3 tint = color.rgb + half3(lift * 0.45h, lift * 0.72h, lift * 0.62h);
    return half4(min(tint, half3(1.0h)), color.a);
}
