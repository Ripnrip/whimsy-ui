//  ClothPoster.metal
//  Cloth ripples for ClothPoster: a distortion that pulls each pixel along the radius from the
//  touch by the ripple height, and a colour effect that shades the slopes and adds a specular
//  sheen on the crests. The wave and lighting mirror ClothWave / ClothShading in ClothPosterCore.
//
//  Use with: .colorEffect(clothSheen(touch, time, amplitude))
//            .distortionEffect(clothRipple(touch, time, amplitude), maxSampleOffset: 12×12)

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float kWavelength = 52.0;
constant float kSpeed = 230.0;
constant float kDecay = 240.0;
constant float kSoftness = 36.0;
constant float kShininess = 24.0;

// Unit-amplitude height at distance d from the source, t seconds after it started.
static float clothHeight(float d, float t) {
    if (t <= 0.0) return 0.0;
    d = max(d, 0.0);
    float k = 2.0 * M_PI_F / kWavelength;
    float w = k * kSpeed;
    float front = kSpeed * t;
    float gate = 1.0 - smoothstep(front - kSoftness, front, d);
    return sin(k * d - w * t) * gate * exp(-d / kDecay);
}

static float clothSlope(float d, float t) {
    const float e = 0.75;
    float lo = max(d - e, 0.0);
    return (clothHeight(d + e, t) - clothHeight(lo, t)) / (d + e - lo);
}

[[ stitchable ]] float2 clothRipple(float2 position, float2 touch, float time, float amplitude) {
    float2 v = position - touch;
    float d = length(v);
    if (d < 1e-3) return position;
    return position - (v / d) * (clothHeight(d, time) * amplitude);
}

[[ stitchable ]] half4 clothSheen(float2 position, half4 color, float2 touch, float time, float amplitude) {
    float2 v = position - touch;
    float d = length(v);
    if (d < 1e-3 || color.a == 0.0h) return color;
    float2 g = (v / d) * (clothSlope(d, time) * amplitude);
    float3 n = normalize(float3(-g.x, -g.y, 1.0));
    float3 l = normalize(float3(-0.45, -0.6, 0.66));
    float3 h = normalize(l + float3(0.0, 0.0, 1.0));
    float flat = pow(h.z, kShininess);
    float spec = clamp((pow(max(dot(n, h), 0.0), kShininess) - flat) / (1.0 - flat), 0.0, 1.0);
    float shade = dot(n, l) - l.z;
    // Colour is premultiplied: scale the shading, add the sheen in proportion to coverage.
    half3 rgb = color.rgb * half(1.0 + 0.9 * shade) + half3(half(0.55 * spec)) * color.a;
    return half4(min(rgb, half3(color.a)), color.a);
}
