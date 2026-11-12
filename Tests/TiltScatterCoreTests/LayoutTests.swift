import Testing
import Foundation
@testable import TiltScatterCore

@Suite("Glyph layout") struct LayoutTests {
    @Test func catalogHasFiveShortLines() {
        #expect(TiltScatterCatalog.tasks.count == 5)
        #expect(TiltScatterCatalog.tasks.map(\.title) == [
            "Water the fern", "Buy walnut ink", "Post the letter", "Trim the press", "Steep the tea",
        ])
    }

    @Test func spacesAreGapsAndLettersKeepOrder() {
        let glyphs = TiltScatterLayout.glyphs(title: "Buy walnut ink", row: 1)
        let letters = glyphs.map(\.glyph).joined()
        #expect(letters == "Buywalnutink")
        #expect(glyphs.count == 12)
        #expect(glyphs.map(\.index) == Array(0..<12))
        for pair in zip(glyphs, glyphs.dropFirst()) {
            #expect(pair.0.home.x < pair.1.home.x)
        }
    }

    @Test func homesSitOnTheRowAndInsideTheCard() {
        for row in 0..<5 {
            let glyphs = TiltScatterLayout.glyphs(title: TiltScatterCatalog.tasks[row].title, row: row)
            let y = TiltScatterLayout.rowCenterY(row)
            for glyph in glyphs {
                #expect(glyph.home.y == y)
                #expect(glyph.home.x > TiltScatterLayout.rowX)
                #expect(glyph.home.x + glyph.width / 2 < TiltScatterLayout.rowX + TiltScatterLayout.rowWidth)
                #expect(glyph.width > 0)
            }
        }
    }

    @Test func rowsStackDownTheCard() {
        var last = 0.0
        for i in 0..<5 {
            let top = TiltScatterLayout.rowTop(i)
            #expect(top > last)
            last = top
            #expect(top + TiltScatterLayout.rowHeight < TiltScatterLayout.trayTop)
        }
    }

    @Test func aLongLineScalesToFit() {
        let title = String(repeating: "M", count: 40)
        let glyphs = TiltScatterLayout.glyphs(title: title, row: 0)
        #expect(glyphs.count == 40)
        let right = TiltScatterLayout.rowX + TiltScatterLayout.rowWidth - TiltScatterLayout.titleRightPad
        #expect(glyphs.last!.home.x + glyphs.last!.width / 2 <= right + 0.01)
        let natural = TiltScatterLayout.fontSize * TiltScatterLayout.unitAdvance(Unicode.Scalar("M")) * 40
        #expect(natural > TiltScatterLayout.rowWidth)
    }

    @Test func emptyAndWhitespaceMakeNoChips() {
        #expect(TiltScatterLayout.glyphs(title: "", row: 0).isEmpty)
        #expect(TiltScatterLayout.glyphs(title: "   \t", row: 0).isEmpty)
    }

    @Test func punctuationIsAChip() {
        let glyphs = TiltScatterLayout.glyphs(title: "Go!", row: 0)
        #expect(glyphs.map(\.glyph) == ["G", "o", "!"])
    }

    @Test func narrowLettersAreNarrowerThanM() {
        #expect(TiltScatterLayout.unitAdvance(Unicode.Scalar("i")) < TiltScatterLayout.unitAdvance(Unicode.Scalar("n")))
        #expect(TiltScatterLayout.unitAdvance(Unicode.Scalar("M")) > TiltScatterLayout.unitAdvance(Unicode.Scalar("n")))
    }

    @Test func layoutIsStable() {
        let a = TiltScatterLayout.glyphs(title: "Post the letter", row: 2)
        let b = TiltScatterLayout.glyphs(title: "Post the letter", row: 2)
        #expect(a == b)
    }

    @Test func grainStaysOnTheSheet() {
        let specks = TiltScatterLayout.grain()
        #expect(specks.count == 42)
        for speck in specks {
            #expect(speck.x >= 0 && speck.x <= TiltScatterLayout.cardWidth)
            #expect(speck.y >= 0 && speck.y <= TiltScatterLayout.cardHeight)
        }
        #expect(TiltScatterLayout.grain() == specks)
    }

    @Test func paletteIsInkOnPaper() {
        #expect(TiltScatterPalette.ink.r < TiltScatterPalette.paper.r)
        #expect(TiltScatterPalette.wax.r > TiltScatterPalette.wax.g)
        #expect(TiltScatterPalette.wax.r > TiltScatterPalette.wax.b)
        #expect(TiltScatterPalette.tray.r < TiltScatterPalette.paper.r)
    }
}
