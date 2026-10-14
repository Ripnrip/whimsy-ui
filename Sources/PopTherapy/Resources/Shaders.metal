//  Shaders.metal
//  PopTherapy
//
//  SwiftUI color-effect shader (iOS 17 / macOS 14+).
//  Used via: ShaderLibrary.bundle(.module).glossSweep(.boundingRect, .float(time))
//  SwiftUI supplies `position` and `color`; the remaining parameters map, in order,
//  to the Shader.Argument values passed from Swift.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// A soft diagonal gloss band that drifts across the bubble sheet, plus a faint shimmer.
/// Only bright (glossy, un-popped) pixels pick up much highlight; dull popped plastic
/// and the darker backing sheet stay mostly untouched.
///
/// - position: pixel position in the view's user space (points).
/// - color:    current premultiplied colour of the pixel.
/// - bounds:   view bounding rect (x, y, width, height) from `.boundingRect`.
/// - time:     seconds, driven by TimelineView.
[[ stitchable ]] half4 glossSweep(float2 position, half4 color, float4 bounds, float time) {
    if (color.a <= 0.0h) {
        return color;
    }

    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));

    // Diagonal band: travels from top-left to bottom-right about every 4.5 seconds.
    float sweep = fract(time * 0.22) * 2.6 - 0.8;
    float d = (uv.x * 0.75 + uv.y * 0.55) - sweep;
    float band = exp(-(d * d) / 0.004);

    // Slow, low-amplitude shimmer so the plastic never looks perfectly static.
    float shimmer = 0.5 + 0.5 * sin(time * 1.6 + uv.x * 9.0 + uv.y * 6.0);

    // Un-premultiply to estimate brightness of the underlying material.
    half3 straight = color.rgb / max(color.a, 0.001h);
    half luminance = dot(straight, half3(0.299h, 0.587h, 0.114h));
    half glossiness = smoothstep(0.45h, 0.85h, luminance);

    half strength = half(band * 0.5 + shimmer * 0.05) * glossiness;
    half3 lit = min(color.rgb + strength * color.a, half3(color.a));
    return half4(lit, color.a);
}
