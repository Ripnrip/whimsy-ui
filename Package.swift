// swift-tools-version: 6.0
import PackageDescription

// The Metal shaders (PopTherapy, GrainyRingGallery) are compiled by Xcode into each module's
// default.metallib. SwiftPM on Linux/Windows has no Metal compiler, so the resources are
// skipped there (the SwiftUI targets compile to empty modules on those platforms anyway).
#if os(Linux) || os(Windows)
let metalResources: [Resource] = []
let metalExclude = ["Resources"]
#else
let metalResources: [Resource] = [.process("Resources")]
let metalExclude: [String] = []
#endif

let package = Package(
    name: "whimsy-ui",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // One product per component (SwiftUI view + its core).
        .library(name: "PopTherapy", targets: ["PopTherapy"]),
        .library(name: "MagneticBeadSlider", targets: ["MagneticBeadSlider"]),
        .library(name: "EraserDelete", targets: ["EraserDelete"]),
        .library(name: "ShutterReveal", targets: ["ShutterReveal"]),
        .library(name: "AliveEyes", targets: ["AliveEyes"]),
        .library(name: "ScatterRegroup", targets: ["ScatterRegroup"]),
        .library(name: "SolarFlareLike", targets: ["SolarFlareLike"]),
        .library(name: "FlyingButton", targets: ["FlyingButton"]),
        .library(name: "GrainyRingGallery", targets: ["GrainyRingGallery"]),
        // The pure-Swift cores on their own (no SwiftUI; build anywhere).
        .library(name: "PopTherapyCore", targets: ["PopTherapyCore"]),
        .library(name: "MagneticBeadCore", targets: ["MagneticBeadCore"]),
        .library(name: "EraserDeleteCore", targets: ["EraserDeleteCore"]),
        .library(name: "ShutterRevealCore", targets: ["ShutterRevealCore"]),
        .library(name: "AliveEyesCore", targets: ["AliveEyesCore"]),
        .library(name: "ScatterRegroupCore", targets: ["ScatterRegroupCore"]),
        .library(name: "SolarFlareCore", targets: ["SolarFlareCore"]),
        .library(name: "FlyingButtonCore", targets: ["FlyingButtonCore"]),
        .library(name: "RingGalleryCore", targets: ["RingGalleryCore"]),
        // A demo gallery listing every component.
        .library(name: "WhimsyGallery", targets: ["WhimsyGallery"]),
    ],
    targets: [
        // Shared Vec2 + SeededRandom.
        .target(name: "WhimsyCore"),

        .target(name: "PopTherapyCore"),
        .target(name: "PopTherapy", dependencies: ["PopTherapyCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "MagneticBeadCore"),
        .target(name: "MagneticBeadSlider", dependencies: ["MagneticBeadCore"]),

        .target(name: "EraserDeleteCore", dependencies: ["WhimsyCore"]),
        .target(name: "EraserDelete", dependencies: ["EraserDeleteCore"]),

        .target(name: "ShutterRevealCore", dependencies: ["WhimsyCore"]),
        .target(name: "ShutterReveal", dependencies: ["ShutterRevealCore"]),

        .target(name: "AliveEyesCore", dependencies: ["WhimsyCore"]),
        .target(name: "AliveEyes", dependencies: ["AliveEyesCore"]),

        .target(name: "ScatterRegroupCore", dependencies: ["WhimsyCore"]),
        .target(name: "ScatterRegroup", dependencies: ["ScatterRegroupCore"]),

        .target(name: "SolarFlareCore", dependencies: ["WhimsyCore"]),
        .target(name: "SolarFlareLike", dependencies: ["SolarFlareCore"]),

        .target(name: "FlyingButtonCore", dependencies: ["WhimsyCore"]),
        .target(name: "FlyingButton", dependencies: ["FlyingButtonCore"]),

        .target(name: "RingGalleryCore", dependencies: ["WhimsyCore"]),
        .target(name: "GrainyRingGallery", dependencies: ["RingGalleryCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "WhimsyGallery", dependencies: [
            "PopTherapy", "MagneticBeadSlider", "EraserDelete", "ShutterReveal", "AliveEyes", "ScatterRegroup", "SolarFlareLike", "FlyingButton",
            "GrainyRingGallery",
        ]),

        .testTarget(name: "WhimsyCoreTests", dependencies: ["WhimsyCore"]),
        .testTarget(name: "PopTherapyCoreTests", dependencies: ["PopTherapyCore"]),
        .testTarget(name: "MagneticBeadCoreTests", dependencies: ["MagneticBeadCore"]),
        .testTarget(name: "EraserDeleteCoreTests", dependencies: ["EraserDeleteCore"]),
        .testTarget(name: "ShutterRevealCoreTests", dependencies: ["ShutterRevealCore"]),
        .testTarget(name: "AliveEyesCoreTests", dependencies: ["AliveEyesCore"]),
        .testTarget(name: "ScatterRegroupCoreTests", dependencies: ["ScatterRegroupCore"]),
        .testTarget(name: "SolarFlareCoreTests", dependencies: ["SolarFlareCore"]),
        .testTarget(name: "FlyingButtonCoreTests", dependencies: ["FlyingButtonCore"]),
        .testTarget(name: "RingGalleryCoreTests", dependencies: ["RingGalleryCore"]),
    ]
)
