//  OilPaint.metal
//  Two small layer effects for OilPaintRestore, mirrored by PaintShading in PaintCore (a test
//  checks the constants match):
//    paintSmear — averages a few samples trailing behind the brush, so wet paint looks dragged.
//    paintGloss — treats the wet bristle layer's alpha as an impasto height field and lights it:
//                 a specular glint on the ridges plus a faint wet sheen, as premultiplied warm white.
//
//  Use with: .layerEffect(paintSmear(smear), maxSampleOffset: 4×4)
//            .layerEffect(paintGloss(strength), maxSampleOffset: 2×2)

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float kSmearLength = 3.0;
constant int kSmearTaps = 4;
constant float kHeightScale = 4.0;
constant float kShininess = 18.0;
constant float kGlossStrength = 0.85;
constant float kSheen = 0.10;

[[ stitchable ]] half4 paintSmear(float2 position, SwiftUI::Layer layer, float2 smear) {
    // smear is already scaled (≤ kSmearLength); taps run from the pixel back along the stroke.
    half4 sum = half4(0.0h);
    for (int k = 0; k < kSmearTaps; k++) {
        sum += layer.sample(position - smear * (float(k) / float(kSmearTaps - 1)));
    }
    return sum / half(kSmearTaps);
}

[[ stitchable ]] half4 paintGloss(float2 position, SwiftUI::Layer layer, float strength) {
    float a = float(layer.sample(position).a);
    float l = float(layer.sample(position - float2(1.0, 0.0)).a);
    float r = float(layer.sample(position + float2(1.0, 0.0)).a);
    float u = float(layer.sample(position - float2(0.0, 1.0)).a);
    float d = float(layer.sample(position + float2(0.0, 1.0)).a);
    float gx = (r - l) * 0.5 * kHeightScale;
    float gy = (d - u) * 0.5 * kHeightScale;
    float3 n = normalize(float3(-gx, -gy, 1.0));
    float3 lightDir = normalize(float3(-0.45, -0.6, 0.66));
    float3 h = normalize(lightDir + float3(0.0, 0.0, 1.0));
    float flat = pow(h.z, kShininess);
    float spec = clamp((pow(max(dot(n, h), 0.0), kShininess) - flat) / (1.0 - flat), 0.0, 1.0);
    float v = clamp((kGlossStrength * spec + kSheen * a) * strength, 0.0, 1.0);
    return half4(half3(1.0h, 0.98h, 0.94h) * half(v), half(v));
}
