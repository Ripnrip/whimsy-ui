//  ChannelFlip.metal
//  The CRT channel-change look for ChannelFlipCard, as one layer effect: the picture is torn sideways in
//  horizontal bands (a different tear on every frame), red and blue are pulled apart, scanlines dim
//  alternate rows, a head-switch bar rolls down the card with `progress`, static crackles over it all, and
//  at the peak the picture brightens and flashes toward white. Mirrors ChannelFlipShading in ChannelFlipCore
//  line for line (a test checks the constants match). With intensity 0 it returns the layer unchanged.
//
//  Use with: .layerEffect(channelFlip(size, progress, intensity, seed, noiseAmount),
//                         maxSampleOffset: CGSize(width: size.width, height: 0))
//    size         card size in points
//    progress     quantized progress through the change, 0…1 (moves the rolling bar)
//    intensity    0…1 (from the envelope and the swipe strength)
//    seed         changes every frame, so every frame tears differently
//    noiseAmount  0 turns the static off, 1 is full static

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float kBandHeight = 7.0;
constant float kMaxShift = 0.14;
constant float kBandChance = 0.3;
constant float kBandChanceGain = 0.6;
constant float kSplit = 0.04;
constant float kFlash = 0.55;
constant float kGain = 0.3;
constant float kNoise = 0.35;
constant float kNoiseCell = 2.0;
constant float kScanDepth = 0.12;
constant float kScanRow = 2.0;
constant float kBarHalf = 0.07;
constant float kBarBoost = 1.5;

// lowbias32 — same as ChannelHash.hash32 and the web port.
static uint hash32(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}
static float unit01(uint x) { return float(x & 0xFFFFFFu) / 16777216.0; }
static float wrapX(float x, float w) { return x - w * floor(x / w); }

static float bandOffset(uint band, uint s, float intensity, float width, bool forced) {
    if (!(intensity > 0.0)) return 0.0;
    uint h = hash32((band * 0x9E3779B1u) ^ s);
    bool active = forced || unit01(hash32(h ^ 0xA511E9B3u)) < kBandChance + kBandChanceGain * intensity;
    return active ? (2.0 * unit01(h) - 1.0) * kMaxShift * width * intensity : 0.0;
}

[[ stitchable ]] half4 channelFlip(float2 position, SwiftUI::Layer layer, float2 size,
                                   float progress, float intensity, float seed, float noiseAmount) {
    uint seedBits = uint(seed);
    uint band = uint(floor(position.y / kBandHeight));
    float bar = 1.0 - smoothstep(0.0, kBarHalf * size.y, abs(position.y - progress * size.y));
    float boost = 1.0 + kBarBoost * bar;
    float dx = bandOffset(band, hash32(seedBits), intensity, size.x, bar > 0.5) * boost;
    float split = intensity * kSplit * size.x;
    float x0 = position.x + dx;
    float cr = float(layer.sample(float2(wrapX(x0 - split, size.x), position.y)).r);
    float cg = float(layer.sample(float2(wrapX(x0, size.x), position.y)).g);
    float cb = float(layer.sample(float2(wrapX(x0 + split, size.x), position.y)).b);
    float a = float(layer.sample(float2(wrapX(x0, size.x), position.y)).a);
    float3 c = float3(cr, cg, cb);
    // The card is opaque, so the sampled colour is used as is.
    uint row = uint(floor(position.y / kScanRow));
    float scan = (row & 1u) == 1u ? 1.0 - kScanDepth * intensity : 1.0;
    c *= (1.0 + kGain * intensity) * scan;
    uint cx = uint(floor(position.x / kNoiseCell)), cy = uint(floor(position.y / kNoiseCell));
    float n = unit01(hash32((cx * 0x1F123BB5u) ^ (cy * 0x9E3779B1u) ^ hash32(seedBits + 0x77u)));
    c += (n - 0.5) * 2.0 * kNoise * noiseAmount * intensity * boost;
    c = clamp(c, 0.0, 1.0);
    c = clamp(c + (1.0 - c) * (kFlash * intensity * intensity), 0.0, 1.0);
    return half4(half3(c), half(a));
}
