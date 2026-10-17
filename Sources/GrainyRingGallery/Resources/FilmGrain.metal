//  FilmGrain.metal
//  GrainyRingGallery
//
//  SwiftUI color-effect shader (iOS 17 / macOS 14+).
//  Used via: ShaderLibrary.bundle(.module).filmGrain(.float(seed), .float(amount), .float(size))
//  SwiftUI supplies `position` and `color`; the remaining parameters map, in order, to the
//  Shader.Argument values passed from Swift. The seed changes 12 times a second (quantised by
//  RingGalleryModel.grainSeed), so the grain flickers like projected film, not like TV static.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Integer hash of a grain cell → [0, 1). Bit-mixing (no sin()), so it is stable for large
/// coordinates and identical on every GPU. The web preview ports it with Math.imul.
static float grainHash(int2 cell, uint seed) {
    uint n = uint(cell.x) * 0x8DA6B343u ^ uint(cell.y) * 0xD8163841u ^ seed * 0xCB1AB31Fu;
    n ^= n >> 15;
    n *= 0x2C1B3C6Du;
    n ^= n >> 12;
    n *= 0x297A2D39u;
    n ^= n >> 15;
    return float(n) * (1.0 / 4294967296.0);
}

/// Monochrome film grain.
///
/// - position: pixel position in the view's user space (points).
/// - color:    current premultiplied colour of the pixel.
/// - seed:     0..<1, from RingGalleryModel.grainSeed(at:); one value per 1/12 s.
/// - amount:   grain strength (≈ 0.08 subtle … 0.2 heavy).
/// - size:     grain cell size in points (≈ 1–1.5).
[[ stitchable ]] half4 filmGrain(float2 position, half4 color, float seed, float amount, float size) {
    if (color.a <= 0.0h) {
        return color;
    }
    int2 cell = int2(floor(position / max(size, 0.25)));
    uint s = uint(seed * 16777216.0);
    // Sum of two uniforms: a triangular distribution in -1...1, softer than flat noise.
    float g = grainHash(cell, s) + grainHash(cell + int2(7919, 104729), s ^ 0x9E3779B9u) - 1.0;

    half3 straight = color.rgb / max(color.a, 0.001h);
    half luminance = dot(straight, half3(0.299h, 0.587h, 0.114h));
    // Real grain is strongest in the midtones and fades in deep shadows and highlights.
    half weight = half(amount) * (0.45h + 2.2h * luminance * (1.0h - luminance));
    half3 grained = clamp(straight + half(g) * weight, 0.0h, 1.0h);
    return half4(grained * color.a, color.a);
}
