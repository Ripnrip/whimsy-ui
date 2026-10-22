// swift-tools-version: 6.0
import PackageDescription

// The Metal shaders (PopTherapy, GrainyRingGallery, LiquidMetalCompass, ClothPoster) are compiled by Xcode into each module's
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
        .library(name: "LiquidMetalCompass", targets: ["LiquidMetalCompass"]),
        .library(name: "SweaterRail", targets: ["SweaterRail"]),
        .library(name: "FontCollection", targets: ["FontCollection"]),
        .library(name: "FollowBlobHero", targets: ["FollowBlobHero"]),
        .library(name: "MoonPhaseScrubber", targets: ["MoonPhaseScrubber"]),
        .library(name: "ClothPoster", targets: ["ClothPoster"]),
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
        .library(name: "LiquidCompassCore", targets: ["LiquidCompassCore"]),
        .library(name: "SweaterRailCore", targets: ["SweaterRailCore"]),
        .library(name: "FontCollectionCore", targets: ["FontCollectionCore"]),
        .library(name: "FollowBlobCore", targets: ["FollowBlobCore"]),
        .library(name: "MoonPhaseCore", targets: ["MoonPhaseCore"]),
        .library(name: "ClothPosterCore", targets: ["ClothPosterCore"]),
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

        .target(name: "LiquidCompassCore", dependencies: ["WhimsyCore"]),
        .target(name: "LiquidMetalCompass", dependencies: ["LiquidCompassCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "SweaterRailCore", dependencies: ["WhimsyCore"]),
        .target(name: "SweaterRail", dependencies: ["SweaterRailCore"]),

        .target(name: "FontCollectionCore", dependencies: ["WhimsyCore"]),
        .target(name: "FontCollection", dependencies: ["FontCollectionCore"]),

        .target(name: "FollowBlobCore", dependencies: ["WhimsyCore"]),
        .target(name: "FollowBlobHero", dependencies: ["FollowBlobCore"]),

        .target(name: "MoonPhaseCore", dependencies: ["WhimsyCore"]),
        .target(name: "MoonPhaseScrubber", dependencies: ["MoonPhaseCore"]),

        .target(name: "ClothPosterCore", dependencies: ["WhimsyCore"]),
        .target(name: "ClothPoster", dependencies: ["ClothPosterCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "WhimsyGallery", dependencies: [
            "PopTherapy", "MagneticBeadSlider", "EraserDelete", "ShutterReveal", "AliveEyes", "ScatterRegroup", "SolarFlareLike", "FlyingButton",
            "GrainyRingGallery", "LiquidMetalCompass", "SweaterRail", "FontCollection", "FollowBlobHero", "MoonPhaseScrubber", "ClothPoster",
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
        .testTarget(name: "LiquidCompassCoreTests", dependencies: ["LiquidCompassCore"]),
        .testTarget(name: "SweaterRailCoreTests", dependencies: ["SweaterRailCore"]),
        .testTarget(name: "FontCollectionCoreTests", dependencies: ["FontCollectionCore"]),
        .testTarget(name: "FollowBlobCoreTests", dependencies: ["FollowBlobCore"]),
        .testTarget(name: "MoonPhaseCoreTests", dependencies: ["MoonPhaseCore"]),
        .testTarget(name: "ClothPosterCoreTests", dependencies: ["ClothPosterCore"]),
    ]
)
