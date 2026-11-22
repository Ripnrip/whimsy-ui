// swift-tools-version: 6.0
import PackageDescription

// The Metal shaders (PopTherapy, GrainyRingGallery, LiquidMetalCompass, ClothPoster, HoloFoilCard, OilPaintRestore, ChannelFlipCard, RippleToHide, KoiNibblePond, GooMergeDrops) are compiled by Xcode into each module's
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
        .library(name: "TiltPhotoGrid", targets: ["TiltPhotoGrid"]),
        .library(name: "ScrollSpinWatch", targets: ["ScrollSpinWatch"]),
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
        .library(name: "TiltGridCore", targets: ["TiltGridCore"]),
        .library(name: "SpinWatchCore", targets: ["SpinWatchCore"]),
        .library(name: "BoutiqueBurst", targets: ["BoutiqueBurst"]),
        .library(name: "BoutiqueCore", targets: ["BoutiqueCore"]),
        .library(name: "PeelableSticker", targets: ["PeelableSticker"]),
        .library(name: "PeelCore", targets: ["PeelCore"]),
        .library(name: "FrostCard", targets: ["FrostCard"]),
        .library(name: "FrostCore", targets: ["FrostCore"]),
        .library(name: "HoloFoilCard", targets: ["HoloFoilCard"]),
        .library(name: "HoloCore", targets: ["HoloCore"]),
        .library(name: "OilPaintRestore", targets: ["OilPaintRestore"]),
        .library(name: "PaintCore", targets: ["PaintCore"]),
        .library(name: "WiggleMatchSearch", targets: ["WiggleMatchSearch"]),
        .library(name: "WiggleCore", targets: ["WiggleCore"]),
        .library(name: "PourOpenMenu", targets: ["PourOpenMenu"]),
        .library(name: "PourCore", targets: ["PourCore"]),
        .library(name: "OctoDoneChecklist", targets: ["OctoDoneChecklist"]),
        .library(name: "OctoCore", targets: ["OctoCore"]),
        .library(name: "AsciiNowPlaying", targets: ["AsciiNowPlaying"]),
        .library(name: "AsciiCore", targets: ["AsciiCore"]),
        .library(name: "DogEarPeelCard", targets: ["DogEarPeelCard"]),
        .library(name: "DogEarCore", targets: ["DogEarCore"]),
        .library(name: "ColorFigureGumball", targets: ["ColorFigureGumball"]),
        .library(name: "ColorFigureCore", targets: ["ColorFigureCore"]),
        .library(name: "ChannelFlipCard", targets: ["ChannelFlipCard"]),
        .library(name: "ChannelFlipCore", targets: ["ChannelFlipCore"]),
        .library(name: "ContourInkLoader", targets: ["ContourInkLoader"]),
        .library(name: "ContourInkCore", targets: ["ContourInkCore"]),
        .library(name: "ShelfPull", targets: ["ShelfPull"]),
        .library(name: "ShelfPullCore", targets: ["ShelfPullCore"]),
        .library(name: "StarJar", targets: ["StarJar"]),
        .library(name: "StarJarCore", targets: ["StarJarCore"]),
        .library(name: "HoldToFanDock", targets: ["HoldToFanDock"]),
        .library(name: "HoldToFanCore", targets: ["HoldToFanCore"]),
        .library(name: "TiltScatterRestore", targets: ["TiltScatterRestore"]),
        .library(name: "TiltScatterCore", targets: ["TiltScatterCore"]),
        .library(name: "NeighborBouncePicker", targets: ["NeighborBouncePicker"]),
        .library(name: "NeighborBounceCore", targets: ["NeighborBounceCore"]),
        .library(name: "RubberBandCardHand", targets: ["RubberBandCardHand"]),
        .library(name: "RubberBandCore", targets: ["RubberBandCore"]),
        .library(name: "CrumpleToDelete", targets: ["CrumpleToDelete"]),
        .library(name: "CrumpleCore", targets: ["CrumpleCore"]),
        .library(name: "RippleToHide", targets: ["RippleToHide"]),
        .library(name: "RippleToHideCore", targets: ["RippleToHideCore"]),
        .library(name: "VelocityGlyphScatter", targets: ["VelocityGlyphScatter"]),
        .library(name: "VelocityGlyphCore", targets: ["VelocityGlyphCore"]),
        .library(name: "PinataReward", targets: ["PinataReward"]),
        .library(name: "PinataCore", targets: ["PinataCore"]),
        .library(name: "CardToPillGlassMorph", targets: ["CardToPillGlassMorph"]),
        .library(name: "GlassMorphCore", targets: ["GlassMorphCore"]),
        .library(name: "OnAirLampToggle", targets: ["OnAirLampToggle"]),
        .library(name: "OnAirCore", targets: ["OnAirCore"]),
        .library(name: "ReededGlassSyncHero", targets: ["ReededGlassSyncHero"]),
        .library(name: "SlatSyncCore", targets: ["SlatSyncCore"]),
        .library(name: "RotaryDialPasscode", targets: ["RotaryDialPasscode"]),
        .library(name: "RotaryDialCore", targets: ["RotaryDialCore"]),
        .library(name: "GlassDropPourMenu", targets: ["GlassDropPourMenu"]),
        .library(name: "GlassPourCore", targets: ["GlassPourCore"]),
        .library(name: "GrainBloomPlaceholder", targets: ["GrainBloomPlaceholder"]),
        .library(name: "GrainBloomCore", targets: ["GrainBloomCore"]),
        .library(name: "KoiNibblePond", targets: ["KoiNibblePond"]),
        .library(name: "KoiPondCore", targets: ["KoiPondCore"]),
        .library(name: "GooMergeDrops", targets: ["GooMergeDrops"]),
        .library(name: "GooMergeCore", targets: ["GooMergeCore"]),
        .library(name: "BoltStreak", targets: ["BoltStreak"]),
        .library(name: "BoltStreakCore", targets: ["BoltStreakCore"]),
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

        .target(name: "TiltGridCore", dependencies: ["WhimsyCore"]),
        .target(name: "TiltPhotoGrid", dependencies: ["TiltGridCore"]),

        .target(name: "SpinWatchCore", dependencies: ["WhimsyCore"]),
        .target(name: "ScrollSpinWatch", dependencies: ["SpinWatchCore"]),
        .target(name: "BoutiqueCore", dependencies: ["WhimsyCore"]),
        .target(name: "BoutiqueBurst", dependencies: ["BoutiqueCore"]),
        .target(name: "PeelCore", dependencies: ["WhimsyCore"]),
        .target(name: "PeelableSticker", dependencies: ["PeelCore"]),

        .target(name: "FrostCore", dependencies: ["WhimsyCore"]),
        .target(name: "FrostCard", dependencies: ["FrostCore"]),

        .target(name: "HoloCore", dependencies: ["WhimsyCore"]),
        .target(name: "HoloFoilCard", dependencies: ["HoloCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "PaintCore", dependencies: ["WhimsyCore"]),
        .target(name: "OilPaintRestore", dependencies: ["PaintCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "WiggleCore", dependencies: ["WhimsyCore"]),
        .target(name: "WiggleMatchSearch", dependencies: ["WiggleCore"]),

        .target(name: "PourCore", dependencies: ["WhimsyCore"]),
        .target(name: "PourOpenMenu", dependencies: ["PourCore"]),

        .target(name: "OctoCore", dependencies: ["WhimsyCore"]),
        .target(name: "OctoDoneChecklist", dependencies: ["OctoCore"]),

        .target(name: "AsciiCore", dependencies: ["WhimsyCore"]),
        .target(name: "AsciiNowPlaying", dependencies: ["AsciiCore"]),
        .target(name: "DogEarCore", dependencies: ["PeelCore"]),
        .target(name: "DogEarPeelCard", dependencies: ["DogEarCore"]),
        .target(name: "ColorFigureCore", dependencies: ["WhimsyCore"]),
        .target(name: "ColorFigureGumball", dependencies: ["ColorFigureCore"]),

        .target(name: "ChannelFlipCore", dependencies: ["WhimsyCore"]),
        .target(name: "ChannelFlipCard", dependencies: ["ChannelFlipCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "ContourInkCore", dependencies: ["WhimsyCore"]),
        .target(name: "ContourInkLoader", dependencies: ["ContourInkCore"]),

        .target(name: "ShelfPullCore", dependencies: ["WhimsyCore"]),
        .target(name: "ShelfPull", dependencies: ["ShelfPullCore"]),

        .target(name: "StarJarCore", dependencies: ["WhimsyCore"]),
        .target(name: "StarJar", dependencies: ["StarJarCore"]),

        .target(name: "HoldToFanCore", dependencies: ["WhimsyCore"]),
        .target(name: "HoldToFanDock", dependencies: ["HoldToFanCore"]),

        .target(name: "TiltScatterCore", dependencies: ["WhimsyCore"]),
        .target(name: "TiltScatterRestore", dependencies: ["TiltScatterCore"]),

        .target(name: "NeighborBounceCore", dependencies: ["WhimsyCore"]),
        .target(name: "NeighborBouncePicker", dependencies: ["NeighborBounceCore"]),

        .target(name: "RubberBandCore", dependencies: ["WhimsyCore"]),
        .target(name: "RubberBandCardHand", dependencies: ["RubberBandCore"]),

        .target(name: "CrumpleCore", dependencies: ["WhimsyCore"]),
        .target(name: "CrumpleToDelete", dependencies: ["CrumpleCore"]),

        .target(name: "RippleToHideCore", dependencies: ["WhimsyCore"]),
        .target(name: "RippleToHide", dependencies: ["RippleToHideCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "VelocityGlyphCore", dependencies: ["WhimsyCore"]),
        .target(name: "VelocityGlyphScatter", dependencies: ["VelocityGlyphCore"]),

        .target(name: "PinataCore", dependencies: ["WhimsyCore"]),
        .target(name: "PinataReward", dependencies: ["PinataCore"]),

        .target(name: "GlassMorphCore", dependencies: ["WhimsyCore"]),
        .target(name: "CardToPillGlassMorph", dependencies: ["GlassMorphCore"]),

        .target(name: "OnAirCore", dependencies: ["WhimsyCore"]),
        .target(name: "OnAirLampToggle", dependencies: ["OnAirCore"]),

        .target(name: "SlatSyncCore", dependencies: ["WhimsyCore"]),
        .target(name: "ReededGlassSyncHero", dependencies: ["SlatSyncCore"]),

        .target(name: "RotaryDialCore", dependencies: ["WhimsyCore"]),
        .target(name: "RotaryDialPasscode", dependencies: ["RotaryDialCore"]),

        .target(name: "GlassPourCore", dependencies: ["WhimsyCore"]),
        .target(name: "GlassDropPourMenu", dependencies: ["GlassPourCore"]),

        .target(name: "GrainBloomCore", dependencies: ["WhimsyCore"]),
        .target(name: "GrainBloomPlaceholder", dependencies: ["GrainBloomCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "KoiPondCore", dependencies: ["WhimsyCore"]),
        .target(name: "KoiNibblePond", dependencies: ["KoiPondCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "GooMergeCore", dependencies: ["WhimsyCore"]),
        .target(name: "GooMergeDrops", dependencies: ["GooMergeCore"],
                exclude: metalExclude, resources: metalResources),

        .target(name: "BoltStreakCore", dependencies: ["WhimsyCore"]),
        .target(name: "BoltStreak", dependencies: ["BoltStreakCore"]),

        .target(name: "WhimsyGallery", dependencies: [
            "PopTherapy", "MagneticBeadSlider", "EraserDelete", "ShutterReveal", "AliveEyes", "ScatterRegroup", "SolarFlareLike", "FlyingButton",
            "GrainyRingGallery", "LiquidMetalCompass", "SweaterRail", "FontCollection", "FollowBlobHero", "MoonPhaseScrubber", "ClothPoster", "TiltPhotoGrid", "ScrollSpinWatch", "BoutiqueBurst", "PeelableSticker", "FrostCard", "HoloFoilCard", "OilPaintRestore", "WiggleMatchSearch", "PourOpenMenu", "OctoDoneChecklist", "AsciiNowPlaying", "DogEarPeelCard", "ColorFigureGumball", "ChannelFlipCard", "ContourInkLoader", "ShelfPull", "StarJar", "HoldToFanDock", "TiltScatterRestore", "NeighborBouncePicker", "RubberBandCardHand",             "CrumpleToDelete", "RippleToHide", "VelocityGlyphScatter", "PinataReward", "CardToPillGlassMorph", "OnAirLampToggle", "ReededGlassSyncHero", "GlassDropPourMenu", "RotaryDialPasscode", "GrainBloomPlaceholder",
            "KoiNibblePond",
            "GooMergeDrops",
            "BoltStreak",
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
        .testTarget(name: "TiltGridCoreTests", dependencies: ["TiltGridCore"]),
        .testTarget(name: "SpinWatchCoreTests", dependencies: ["SpinWatchCore"]),
        .testTarget(name: "BoutiqueCoreTests", dependencies: ["BoutiqueCore"]),
        .testTarget(name: "PeelCoreTests", dependencies: ["PeelCore"]),
        .testTarget(name: "FrostCoreTests", dependencies: ["FrostCore"]),
        .testTarget(name: "HoloCoreTests", dependencies: ["HoloCore"]),
        .testTarget(name: "PaintCoreTests", dependencies: ["PaintCore"]),
        .testTarget(name: "WiggleCoreTests", dependencies: ["WiggleCore"]),
        .testTarget(name: "PourCoreTests", dependencies: ["PourCore"]),
        .testTarget(name: "OctoCoreTests", dependencies: ["OctoCore"]),
        .testTarget(name: "AsciiCoreTests", dependencies: ["AsciiCore"]),
        .testTarget(name: "DogEarCoreTests", dependencies: ["DogEarCore"]),
        .testTarget(name: "ColorFigureCoreTests", dependencies: ["ColorFigureCore"]),
        .testTarget(name: "ChannelFlipCoreTests", dependencies: ["ChannelFlipCore"]),
        .testTarget(name: "ContourInkCoreTests", dependencies: ["ContourInkCore"]),
        .testTarget(name: "ShelfPullCoreTests", dependencies: ["ShelfPullCore"]),
        .testTarget(name: "StarJarCoreTests", dependencies: ["StarJarCore"]),
        .testTarget(name: "HoldToFanCoreTests", dependencies: ["HoldToFanCore"]),
        .testTarget(name: "TiltScatterCoreTests", dependencies: ["TiltScatterCore"]),
        .testTarget(name: "NeighborBounceCoreTests", dependencies: ["NeighborBounceCore"]),
        .testTarget(name: "RubberBandCoreTests", dependencies: ["RubberBandCore"]),
        .testTarget(name: "CrumpleCoreTests", dependencies: ["CrumpleCore"]),
        .testTarget(name: "RippleToHideCoreTests", dependencies: ["RippleToHideCore"]),
        .testTarget(name: "VelocityGlyphCoreTests", dependencies: ["VelocityGlyphCore"]),
        .testTarget(name: "PinataCoreTests", dependencies: ["PinataCore"]),
        .testTarget(name: "GlassMorphCoreTests", dependencies: ["GlassMorphCore"]),
        .testTarget(name: "OnAirCoreTests", dependencies: ["OnAirCore"], exclude: ["Fixtures"]),
        .testTarget(name: "SlatSyncCoreTests", dependencies: ["SlatSyncCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "RotaryDialCoreTests", dependencies: ["RotaryDialCore"]),
        .testTarget(name: "GlassPourCoreTests", dependencies: ["GlassPourCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "GrainBloomCoreTests", dependencies: ["GrainBloomCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "KoiPondCoreTests", dependencies: ["KoiPondCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "GooMergeCoreTests", dependencies: ["GooMergeCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "BoltStreakCoreTests", dependencies: ["BoltStreakCore"],
                    exclude: ["Fixtures"]),
    ]
)
