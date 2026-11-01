import Testing
import Foundation
@testable import ChannelFlipCore

@Suite struct SceneTests {
    @Test func sixNamedScenesThatWrap() {
        #expect(ChannelScenes.count == 6 && ChannelScenes.all.count == 6)
        #expect(ChannelScenes.scene(6) == ChannelScenes.scene(0))
        #expect(ChannelScenes.scene(-1) == ChannelScenes.scene(5))
        #expect(Set(ChannelScenes.all.map(\.name)).count == 6)
    }

    @Test func areDeterministic() {
        for i in 0..<6 { #expect(ChannelScenes.scene(i) == ChannelScenes.scene(i)) }
    }

    @Test func everyPhotoStartsWithABackgroundGradientAndHasPlentyOfDetail() {
        for s in ChannelScenes.all {
            #expect(s.ops.first?.kind == .gradient)
            #expect(s.ops.count > 12)
        }
    }

    @Test func photosLookDifferent() {
        func sig(_ s: ChannelScene) -> [UInt32] { s.ops.map(\.color) }
        let sigs = ChannelScenes.all.map(sig)
        for i in 0..<6 { for j in (i + 1)..<6 { #expect(sigs[i] != sigs[j]) } }
        // different top-of-sky colours too
        #expect(Set(ChannelScenes.all.map { $0.ops[0].color }).count == 6)
    }

    @Test func usesMoreThanOneKindOfShape() {
        for s in ChannelScenes.all { #expect(Set(s.ops.map(\.kind)).count >= 3) }
    }

    @Test func geometryStaysNearTheCard() {
        for s in ChannelScenes.all {
            for op in s.ops {
                for p in op.points {
                    #expect(p.x.isFinite && p.y.isFinite)
                    #expect(p.x > -200 && p.x < 500 && p.y > -80 && p.y < 500)
                }
                #expect(op.alpha >= 0 && op.alpha <= 1 && op.size >= 0)
                switch op.kind {
                case .gradient: #expect(op.points.isEmpty)
                case .rect, .line: #expect(op.points.count == 2)
                case .circle, .radial: #expect(op.points.count == 1 && op.size > 0)
                case .poly: #expect(op.points.count >= 3)
                }
            }
        }
    }

    @Test func colorsAreRGBHex() {
        for s in ChannelScenes.all { for op in s.ops { #expect(op.color <= 0xFFFFFF && op.color2 <= 0xFFFFFF) } }
    }

    @Test func hashIsTheLowbias32Reference() {
        // Known values of the lowbias32 integer hash; the shader and the web port use the same one.
        #expect(ChannelHash.hash32(0) == 0)
        #expect(ChannelHash.hash32(1) == 0x688990C0)
        #expect(ChannelHash.hash32(2) == 0xD1132181)
        #expect(ChannelHash.hash32(12345) == 0x912EFCF7)
        #expect(ChannelHash.hash32(0xFFFF_FFFF) == ChannelHash.hash32(0xFFFF_FFFF))
        #expect(ChannelHash.unit(0xFFFF_FFFF) < 1 && ChannelHash.unit(0) == 0)
        var seen = Set<UInt32>()
        for i in 0..<5000 { seen.insert(ChannelHash.hash32(UInt32(i))) }
        #expect(seen.count == 5000)
    }
}

@Suite struct MetalShaderTests {
    private static var source: String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/ChannelFlipCard/Resources/ChannelFlip.metal").standardized
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static var constants: [String: Double] {
        var out: [String: Double] = [:]
        for line in source.split(separator: "\n") where line.hasPrefix("constant float ") {
            let parts = line.dropFirst("constant float ".count).split(separator: "=")
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
            if let v = Double(value) { out[name] = v }
        }
        return out
    }

    @Test func shaderFileIsThere() { #expect(Self.source.contains("channelFlip")) }

    @Test func constantsMatchTheCore() {
        let c = Self.constants
        #expect(c["kBandHeight"] == ChannelFlipShading.bandHeight)
        #expect(c["kMaxShift"] == ChannelFlipShading.maxShift)
        #expect(c["kBandChance"] == ChannelFlipShading.bandChance)
        #expect(c["kBandChanceGain"] == ChannelFlipShading.bandChanceGain)
        #expect(c["kSplit"] == ChannelFlipShading.split)
        #expect(c["kFlash"] == ChannelFlipShading.flash)
        #expect(c["kGain"] == ChannelFlipShading.gain)
        #expect(c["kNoise"] == ChannelFlipShading.noise)
        #expect(c["kNoiseCell"] == ChannelFlipShading.noiseCell)
        #expect(c["kScanDepth"] == ChannelFlipShading.scanDepth)
        #expect(c["kScanRow"] == ChannelFlipShading.scanRow)
        #expect(c["kBarHalf"] == ChannelFlipShading.barHalf)
        #expect(c["kBarBoost"] == ChannelFlipShading.barBoost)
        #expect(c.count == 13)
    }

    @Test func signatureMatchesWhatTheViewPasses() {
        // The view passes float2 size, then progress, intensity, seed, noiseAmount.
        #expect(Self.source.contains("[[ stitchable ]] half4 channelFlip(float2 position, SwiftUI::Layer layer, float2 size,"))
        for u in ["float progress", "float intensity", "float seed", "float noiseAmount"] { #expect(Self.source.contains(u)) }
    }

    @Test func hashConstantsMatch() {
        for k in ["0x7feb352du", "0x846ca68bu", "0x9E3779B1u", "0xA511E9B3u", "0x1F123BB5u"] { #expect(Self.source.contains(k)) }
    }
}
