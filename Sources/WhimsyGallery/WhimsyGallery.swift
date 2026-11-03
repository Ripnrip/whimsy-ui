//  WhimsyGallery.swift
//  A demo gallery listing every whimsy-ui component, built only from their public APIs.

#if canImport(SwiftUI)
import SwiftUI
import PopTherapy
import MagneticBeadSlider
import EraserDelete
import ShutterReveal
import AliveEyes
import ScatterRegroup
import SolarFlareLike
import FlyingButton
import GrainyRingGallery
import LiquidMetalCompass
import SweaterRail
import FontCollection
import FollowBlobHero
import MoonPhaseScrubber
import ClothPoster
import TiltPhotoGrid
import ScrollSpinWatch
import BoutiqueBurst
import PeelableSticker
import FrostCard
import HoloFoilCard
import OilPaintRestore
import WiggleMatchSearch
import PourOpenMenu
import OctoDoneChecklist
import AsciiNowPlaying
import DogEarPeelCard
import ColorFigureGumball
import ChannelFlipCard
import ContourInkLoader
import ShelfPull

/// A navigation list of all thirty-one components with a small live demo of each.
/// Drop `WhimsyGallery()` into a scene to browse them.
public struct WhimsyGallery: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List(GalleryItem.allCases) { item in
                NavigationLink(value: item) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.symbol).foregroundStyle(.tint)
                    }
                }
            }
            .navigationTitle("Whimsy")
            .navigationDestination(for: GalleryItem.self) { item in
                item.demo
                    .navigationTitle(item.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
    }
}

enum GalleryItem: String, CaseIterable, Identifiable, Hashable {
    case popTherapy, magneticBeads, eraserDelete, shutterReveal, aliveEyes, scatterRegroup, solarFlare, flyingButton, ringGallery, liquidCompass, sweaterRail, fontCollection, followBlob, moonPhase, clothPoster, tiltGrid, spinWatch, boutique, peelSticker, frostCard, holoFoilCard, oilPaintRestore, wiggleMatchSearch, pourOpenMenu, octoDoneChecklist, asciiNowPlaying, dogEarPeelCard, colorFigureGumball, channelFlipCard, contourInkLoader, shelfPull
    var id: String { rawValue }

    var title: String {
        switch self {
        case .popTherapy: "Pop Therapy"
        case .magneticBeads: "Magnetic Bead Slider"
        case .eraserDelete: "Eraser Delete"
        case .shutterReveal: "Shutter Reveal"
        case .aliveEyes: "Alive Eyes"
        case .scatterRegroup: "Scatter & Regroup"
        case .solarFlare: "Solar Flare Like"
        case .flyingButton: "Flying Button"
        case .ringGallery: "Grainy Ring Gallery"
        case .liquidCompass: "Liquid Metal Compass"
        case .sweaterRail: "Sweater Rail"
        case .fontCollection: "Font Collection"
        case .followBlob: "Follow Blob Hero"
        case .moonPhase: "Moon Phase Scrubber"
        case .clothPoster: "Cloth Poster"
        case .tiltGrid: "Tilt Photo Grid"
        case .spinWatch: "Scroll Spin Watch"
        case .boutique: "Boutique Burst"
        case .peelSticker: "Peelable Sticker"
        case .frostCard: "Frost Card"
        case .holoFoilCard: "Holo Foil Card"
        case .oilPaintRestore: "Oil Paint Restore"
        case .wiggleMatchSearch: "Wiggle Match Search"
        case .pourOpenMenu: "Pour Open Menu"
        case .octoDoneChecklist: "Octo Done Checklist"
        case .asciiNowPlaying: "ASCII Now Playing"
        case .dogEarPeelCard: "Dog-Ear Peel Card"
        case .colorFigureGumball: "Color Figure Gumball"
        case .channelFlipCard: "Channel Flip Card"
        case .contourInkLoader: "Contour Ink Loader"
        case .shelfPull: "Shelf Pull"
        }
    }

    var subtitle: String {
        switch self {
        case .popTherapy: "Bubble wrap with squish, haptics and a gift"
        case .magneticBeads: "Beads that trail the thumb like a chain"
        case .eraserDelete: "Delete by rubbing it out"
        case .shutterReveal: "Camera-iris reveal with springy blades"
        case .aliveEyes: "Eyes with saccades, blinks and squints"
        case .scatterRegroup: "Tiles fling out and ripple back home"
        case .solarFlare: "A like button that erupts"
        case .flyingButton: "Press and hold for liftoff"
        case .ringGallery: "Spin a 3D ring of photos under film grain"
        case .liquidCompass: "A chrome blob that leans toward a friend"
        case .sweaterRail: "A Dock-style clothes rail with a hero page"
        case .fontCollection: "A flip-board font showcase with specimen cards"
        case .followBlob: "A neon blob that chases your finger"
        case .moonPhase: "Scrub a lunation; snaps to the eight phases"
        case .clothPoster: "Drag to send cloth ripples across a poster"
        case .tiltGrid: "Kinetic type, then a tilting masonry grid"
        case .spinWatch: "A layered watch turned over by scrolling"
        case .boutique: "A serif word that bursts into a crowd of looks"
        case .peelSticker: "Peel an emoji sticker off a card"
        case .frostCard: "Hold to frost it over, let go to melt"
        case .holoFoilCard: "Drag to tilt a holographic card"
        case .oilPaintRestore: "Paint colour back into a faded photo"
        case .wiggleMatchSearch: "Fuzzy search with wavy match underlines"
        case .pourOpenMenu: "A sort pill that melts into goo drops"
        case .octoDoneChecklist: "Done rows get eaten by halftone ink"
        case .asciiNowPlaying: "Album art made of breathing, scrambling text"
        case .dogEarPeelCard: "Peel a card's corner to find the note under it"
        case .colorFigureGumball: "A hand-inked gumball machine you can turn and open"
        case .channelFlipCard: "A photo card that changes picture like a CRT TV changing channel"
        case .contourInkLoader: "A loader that sketches a topographic map, then sends a red dot up to the peak"
        case .shelfPull: "Pull a book off the shelf, watch it turn, and read its card"
        }
    }

    var symbol: String {
        switch self {
        case .popTherapy: "circle.grid.3x3.fill"
        case .magneticBeads: "slider.horizontal.3"
        case .eraserDelete: "eraser.fill"
        case .shutterReveal: "camera.aperture"
        case .aliveEyes: "eyes"
        case .scatterRegroup: "square.grid.3x3.square"
        case .solarFlare: "heart.fill"
        case .flyingButton: "airplane.departure"
        case .ringGallery: "rotate.3d"
        case .liquidCompass: "location.north.circle.fill"
        case .sweaterRail: "tshirt.fill"
        case .fontCollection: "textformat"
        case .followBlob: "drop.fill"
        case .moonPhase: "moonphase.first.quarter"
        case .clothPoster: "water.waves"
        case .tiltGrid: "square.grid.3x3.square"
        case .spinWatch: "applewatch"
        case .boutique: "bag"
        case .peelSticker: "seal"
        case .frostCard: "snowflake"
        case .holoFoilCard: "sparkles.rectangle.stack"
        case .oilPaintRestore: "paintbrush.pointed"
        case .wiggleMatchSearch: "magnifyingglass"
        case .pourOpenMenu: "chevron.down.circle"
        case .octoDoneChecklist: "checklist"
        case .asciiNowPlaying: "music.note"
        case .dogEarPeelCard: "doc.richtext"
        case .colorFigureGumball: "circle.hexagongrid.fill"
        case .channelFlipCard: "tv"
        case .contourInkLoader: "map"
        case .shelfPull: "books.vertical"
        }
    }

    @MainActor @ViewBuilder var demo: some View {
        switch self {
        case .popTherapy: PopTherapyView().padding()
        case .magneticBeads: BeadsDemo()
        case .eraserDelete: EraserDemo()
        case .shutterReveal: ShutterDemo()
        case .aliveEyes: EyesDemo()
        case .scatterRegroup: ScatterDemo()
        case .solarFlare: FlareDemo()
        case .flyingButton: FlyingDemo()
        case .ringGallery: GrainyRingGallery(cards: RingPhotoCard.samples)
        case .liquidCompass: CompassDemo()
        case .sweaterRail: SweaterRail()
        case .fontCollection: FontCollection()
        case .followBlob: FollowBlobHero()
        case .moonPhase: MoonPhaseScrubber()
        case .clothPoster: ClothPoster()
        case .tiltGrid: TiltPhotoGrid(useDeviceMotion: false)
        case .spinWatch: ScrollSpinWatch()
        case .boutique: BoutiqueBurst()
        case .peelSticker: PeelableSticker()
        case .frostCard: FrostCard()
        case .holoFoilCard: HoloFoilCard()
        case .oilPaintRestore: OilPaintRestore()
        case .wiggleMatchSearch: WiggleMatchSearch()
        case .pourOpenMenu: PourOpenMenu()
        case .octoDoneChecklist: OctoDoneChecklist()
        case .asciiNowPlaying: AsciiNowPlaying()
        case .dogEarPeelCard: DogEarPeelCard()
        case .colorFigureGumball: ColorFigureGumball()
        case .channelFlipCard: ChannelFlipCard()
        case .contourInkLoader: ContourInkLoader()
        case .shelfPull: ShelfPull()
        }
    }
}

private struct BeadsDemo: View {
    @State private var stepped = 0.4
    @State private var smooth = 0.25
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Stepped · \(Int((stepped * 100).rounded()))%").font(.subheadline).foregroundStyle(.secondary)
            MagneticBeadSlider(value: $stepped, steps: 10)
            Text("Continuous · \(Int((smooth * 100).rounded()))%").font(.subheadline).foregroundStyle(.secondary)
            MagneticBeadSlider(value: $smooth, steps: 0)
        }
        .padding(24)
    }
}

private struct EraserDemo: View {
    private struct Note: Identifiable { let id = UUID(); let text: String }
    @State private var notes = ["Buy oat milk", "Call the dentist", "Water the ferns", "Book train tickets"]
        .map { Note(text: $0) }
    @State private var erasing: Set<UUID> = []

    var body: some View {
        List {
            ForEach(notes) { note in
                ErasableCard(
                    isErasing: Binding(
                        get: { erasing.contains(note.id) },
                        set: { if $0 { erasing.insert(note.id) } else { erasing.remove(note.id) } }
                    ),
                    onErased: { notes.removeAll { $0.id == note.id } }
                ) {
                    Text(note.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.yellow.opacity(0.35), in: .rect(cornerRadius: 12))
                }
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button("Erase", systemImage: "eraser") { erasing.insert(note.id) }.tint(.pink)
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct ShutterDemo: View {
    @State private var isOpen = false
    var body: some View {
        VStack(spacing: 24) {
            LinearGradient(colors: [.indigo, .pink, .orange], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottomLeading) {
                    Text("Golden hour").font(.title2.bold()).foregroundStyle(.white).padding(20)
                }
                .frame(width: 300, height: 380)
                .shutterRevealOnTap(isOpen: $isOpen)
                .clipShape(.rect(cornerRadius: 28))
            Button(isOpen ? "Close" : "Open") { isOpen.toggle() }.buttonStyle(.borderedProminent)
        }
    }
}

private struct EyesDemo: View {
    @State private var squints = 0
    private let face = Color(red: 0.98, green: 0.80, blue: 0.56)
    var body: some View {
        VStack(spacing: 20) {
            AliveEyesView(lidColor: face, squintTrigger: squints)
                .frame(height: 260)
                .background(face, in: .rect(cornerRadius: 36))
                .padding(.horizontal)
            Button("Squint") { squints += 1 }.buttonStyle(.borderedProminent)
        }
    }
}

private struct ScatterDemo: View {
    @State private var isScattered = false
    var body: some View {
        VStack(spacing: 16) {
            ScatterRegroupGrid(isScattered: $isScattered)
                .aspectRatio(0.68, contentMode: .fit)
                .padding(.horizontal)
            Text(isScattered ? "Tap to regroup" : "Tap to scatter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FlareDemo: View {
    @State private var isLiked = false
    var body: some View {
        VStack(spacing: 56) {
            // The flare reaches ~1.25× the heart size from its centre; leave it room.
            SolarFlareLikeButton(isLiked: $isLiked, size: 72)
            Text(isLiked ? "Liked" : "Tap the heart").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct FlyingDemo: View {
    @State private var taps = 0
    var body: some View {
        VStack(spacing: 64) {
            // The plume and shadow draw ~40 pt below the capsule; leave them room.
            FlyingButton("Launch") { taps += 1 }
            Text(taps == 0 ? "Tap, or press and hold" : "Tapped \(taps)×")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompassDemo: View {
    @State private var distance = 1_480.0
    var body: some View {
        // On an iPhone this follows the real compass; elsewhere, drag sideways to turn.
        LiquidMetalCompass(friendName: "Maya", friendBearing: 62, distance: distance)
            .overlay(alignment: .bottom) {
                Button("Walk closer") { distance = max(distance * 0.82 - 20, 0) }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.bottom, 24)
            }
    }
}

#Preview("Whimsy Gallery") {
    WhimsyGallery()
}
#endif
