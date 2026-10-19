//  LiquidChrome.metal
//  LiquidMetalCompass
//
//  SwiftUI layer-effect shader (iOS 17 / macOS 14+).
//  Used via: ShaderLibrary.bundle(.module).liquidChrome(.float(spin), .float(glow))
//  applied with .layerEffect(_, maxSampleOffset: CGSize(width: 8, height: 8)).
//
//  The layer it shades is the blob drawn as a *height field*: filled with a dome-shaped grey
//  gradient and blurred, so premultiplied red ≈ height × coverage. The shader
//    1. cuts a crisp, anti-aliased edge at the 50% coverage iso-line (a metaball-style
//       contour, so the stretched tip stays rounded and liquid),
//    2. takes the surface normal from the height gradient (central differences),
//    3. reflects a procedural studio environment (sky, dark floor, a crisp horizon and two
//       softbox strips) that rotates with `spin`, the device heading, as a real chrome
//       object would reflect a fixed room while you turn,
//    4. adds a specular hot spot, a soft rim, and a warm tint while aligned (`glow`).
//  The web preview (webports/liquidcompass.html) ports this function line for line.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float heightAt(SwiftUI::Layer layer, float2 p) {
    return float(layer.sample(p).r);
}

static float3 studio(float3 r, float spin) {
    // Screen up is -y. The +0.3·r.z tilt is a camera looking slightly down at the blob, so the
    // flat-on centre reflects sky and the horizon falls on the curved lower flank, where the
    // normals change fast (a flat-on horizon would shimmer with every 1/255 height step).
    float up = -r.y + 0.3 * r.z;
    float3 sky = mix(float3(0.50, 0.56, 0.66), float3(0.97, 0.98, 1.00), smoothstep(0.0, 0.75, up));
    float3 floorC = mix(float3(0.06, 0.06, 0.08), float3(0.30, 0.28, 0.27), smoothstep(-0.95, -0.05, up));
    float3 base = mix(floorC, sky, smoothstep(-0.05, 0.05, up));
    // Two softbox strips around the vertical axis, turning with the heading.
    float ang = atan2(r.x, up) + spin;
    float strips = pow(0.5 + 0.5 * cos(2.0 * ang), 28.0) * smoothstep(0.25, 0.7, length(r.xy));
    return base + strips * 0.85;
}

[[ stitchable ]] half4 liquidChrome(float2 position, SwiftUI::Layer layer, float spin, float glow) {
    float coverage = float(layer.sample(position).a);
    float mask = smoothstep(0.44, 0.56, coverage);
    if (mask <= 0.0) {
        return half4(0.0h);
    }
    // Central differences averaged over ±3.5 pt and ±7 pt. Wide taps matter: the layer is
    // usually 8-bit, and a 1–2 pt tap turns the height field's 1/255 steps into visible rings.
    float2 g = float2(0.0);
    for (int k = 1; k <= 2; k++) {
        float e = 3.5 * float(k);
        g.x += (heightAt(layer, position + float2(e, 0)) - heightAt(layer, position - float2(e, 0))) / (2.0 * e);
        g.y += (heightAt(layer, position + float2(0, e)) - heightAt(layer, position - float2(0, e))) / (2.0 * e);
    }
    g *= 0.5;                 // mean slope, height units per point
    const float bump = 21.0;  // height units → surface slope
    float3 n = normalize(float3(-g.x * bump, -g.y * bump, 1.0));
    float3 r = reflect(float3(0.0, 0.0, -1.0), n);
    float3 col = studio(r, spin);

    // Specular hot spot from a key light up and to the left.
    float3 L = normalize(float3(-0.45, -0.65, 0.62));
    col += pow(max(dot(r, L), 0.0), 70.0) * 1.2;
    // Edges turn away from the viewer: darken slightly, then a thin cool rim.
    col *= 0.82 + 0.18 * n.z;
    col += float3(0.55, 0.65, 0.8) * pow(1.0 - n.z, 4.0) * 0.35;
    // Aligned: a warm, gold-ish tint.
    col = mix(col, col * float3(1.05, 0.9, 0.62) + float3(0.06, 0.04, 0.0), clamp(glow, 0.0, 1.0) * 0.5);

    col = clamp(col, 0.0, 1.0);
    return half4(half3(col * mask), half(mask));
}
