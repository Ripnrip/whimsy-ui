//  RippleToHide.metal
//  Stitchable distortion for RippleToHide. The displacement is the same expression as
//  RippleWave.displacement in RippleToHideCore, and the constants are RippleRules.*Default.
//
//  time is seconds since the trip started. The view passes `duration - elapsed` to run the
//  wave back toward the tap. amplitude is the peak radial offset in points.
//
//  Use with: .distortionEffect(rippleToHide(tap, time, amplitude), maxSampleOffset: 16×16)

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float kWavelength = 44.0;
constant float kSpeed = 240.0;
constant float kSpatialDecay = 150.0;
constant float kTimeDamping = 0.48;
constant float kFrontSoftness = 20.0;

static float rippleDisplacement(float d, float t) {
    if (t <= 0.0) return 0.0;
    d = max(d, 0.0);
    float k = 2.0 * M_PI_F / kWavelength;
    float w = k * kSpeed;
    float front = kSpeed * t;
    float gate = 1.0 - smoothstep(front - kFrontSoftness, front, d);
    return sin(k * d - w * t) * gate * exp(-t / kTimeDamping) * exp(-d / kSpatialDecay);
}

[[ stitchable ]] float2 rippleToHide(float2 position, float2 tap, float time, float amplitude) {
    float2 v = position - tap;
    float d = length(v);
    if (d < 1e-3) return position;
    return position - (v / d) * (rippleDisplacement(d, time) * amplitude);
}
