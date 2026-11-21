//  LouvreSpecular.metal
//  A traveling glint on one louvre blade. `specular` is 0 at the top of the
//  face and 1 at the bottom, the same offset LouvreVentMath.specular returns.
//  `intensity` is LouvreVentMath.specularIntensity.
//
//  Use with:
//    .colorEffect(louvreSpecular(size, specular, intensity))
//  The Canvas band is the fallback when this is unavailable, and under Reduce Motion.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 louvreSpecular(
    float2 position,
    half4 color,
    float2 size,
    float specular,
    float intensity
) {
    float y = position.y / max(size.y, 1.0);
    float x = position.x / max(size.x, 1.0);
    float dy = (y - specular) * 6.5;
    float band = exp(-dy * dy);
    float sheen = smoothstep(0.0, 0.18, x) * (1.0 - smoothstep(0.55, 0.96, x));
    half3 glint = half3(1.0, 0.985, 0.94);
    half3 rgb = color.rgb + glint * half(band * sheen * intensity);
    return half4(min(rgb, half3(1.0)), color.a);
}
