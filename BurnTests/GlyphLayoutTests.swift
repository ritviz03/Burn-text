//
//  GlyphLayoutTests.swift
//

import UIKit
import XCTest

@testable import Burn

final class GlyphLayoutTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)

    private func layout(_ text: String, width: CGFloat = 300) -> GlyphLayout {
        GlyphLayout.make(text: text, font: font, maxWidth: width)
    }

    func testEmptyTextLaysOutNothing() {
        XCTAssertTrue(layout("").glyphs.isEmpty)
    }

    func testZeroWidthLaysOutNothing() {
        XCTAssertTrue(layout("hello", width: 0).glyphs.isEmpty)
    }

    func testEveryCharacterIsPlacedOnce() {
        let text = "burn negative thought"
        let laid = layout(text)
        XCTAssertEqual(laid.glyphs.count, text.count)
        XCTAssertEqual(laid.glyphs.map(\.character), Array(text))
        // Indices map back to the original string, in order.
        XCTAssertEqual(laid.glyphs.map(\.index), Array(0..<text.count))
    }

    func testShortTextStaysOnOneLine() {
        let laid = layout("burn")
        XCTAssertEqual(laid.glyphs.map(\.line).max(), 0)
        XCTAssertEqual(laid.size.height, laid.lineHeight, accuracy: 0.01)
    }

    func testLongTextWraps() {
        let laid = layout(String(repeating: "negative thoughts ", count: 12))
        guard let lines = laid.glyphs.map(\.line).max() else {
            return XCTFail("nothing was laid out")
        }
        XCTAssertGreaterThan(lines, 2, "a long paragraph should occupy several lines")
        XCTAssertEqual(laid.size.height, CGFloat(lines + 1) * laid.lineHeight, accuracy: 0.01)
    }

    func testNothingOverflowsTheWidth() {
        let width: CGFloat = 220
        let laid = layout(String(repeating: "worry ", count: 40), width: width)
        for glyph in laid.glyphs where !glyph.character.isWhitespace {
            XCTAssertLessThanOrEqual(glyph.frame.maxX, width + 0.5, "\(glyph.character) spills off the page")
            XCTAssertGreaterThanOrEqual(glyph.frame.minX, -0.5)
        }
    }

    /// A single run with no break opportunity still has to fit.
    func testUnbreakableWordIsBrokenRatherThanOverflowing() {
        let width: CGFloat = 120
        let laid = layout(String(repeating: "x", count: 90), width: width)
        XCTAssertGreaterThan(laid.glyphs.map(\.line).max() ?? 0, 0, "it should have been split across lines")
        for glyph in laid.glyphs {
            XCTAssertLessThanOrEqual(glyph.frame.maxX, width + 0.5)
        }
    }

    func testCharactersAdvanceLeftToRightWithinALine() {
        let laid = layout("burn negative thought")
        let byLine = Dictionary(grouping: laid.glyphs, by: \.line)
        for (_, glyphs) in byLine {
            let sorted = glyphs.sorted { $0.index < $1.index }
            for (previous, next) in zip(sorted, sorted.dropFirst()) {
                XCTAssertEqual(previous.frame.maxX, next.frame.minX, accuracy: 0.01,
                               "characters should sit flush against each other")
            }
        }
    }

    func testLinesAreCentred() {
        let width: CGFloat = 300
        let laid = layout("burn", width: width)
        let left = laid.glyphs.map(\.frame.minX).min() ?? 0
        let right = laid.glyphs.map(\.frame.maxX).max() ?? 0
        XCTAssertEqual(left, width - right, accuracy: 0.5, "equal space either side")
    }

    /// Trimming only the trailing side left a line that *starts* with spaces
    /// sitting too far right by exactly the width of those spaces.
    func testLeadingWhitespaceDoesNotShoveTextOffCentre() {
        let width: CGFloat = 300
        let plain = layout("centred", width: width)
        let padded = layout("   centred", width: width)

        let plainLeft = plain.burnable.map(\.frame.minX).min() ?? 0
        let paddedLeft = padded.burnable.map(\.frame.minX).min() ?? 0
        XCTAssertEqual(plainLeft, paddedLeft, accuracy: 0.5,
                       "the visible word should land in the same place either way")
    }

    func testWhitespaceOnlyTextDoesNotCrash() {
        let laid = layout("   ")
        XCTAssertEqual(laid.glyphs.count, 3)
        XCTAssertTrue(laid.burnable.isEmpty)
    }

    /// Newlines take part in the layout — they end their line — but they are still
    /// characters, and dropping them silently broke the index mapping.
    func testNewlinesAreStillAccountedFor() {
        let text = "a\nb"
        let laid = layout(text)
        XCTAssertEqual(laid.glyphs.count, text.count)
        XCTAssertEqual(laid.glyphs.map(\.index), Array(0..<text.count))
        XCTAssertEqual(laid.burnable.count, 2, "a newline is not burnable")
    }

    func testNewlineForcesABreak() {
        let laid = layout("a\nb")
        let a = laid.glyphs.first { $0.character == "a" }
        let b = laid.glyphs.first { $0.character == "b" }
        XCTAssertEqual(a?.line, 0)
        XCTAssertEqual(b?.line, 1)
    }

    func testBurnableSkipsWhitespace() {
        let laid = layout("a b")
        XCTAssertEqual(laid.glyphs.count, 3)
        XCTAssertEqual(laid.burnable.count, 2)
        XCTAssertFalse(laid.burnable.contains { $0.character.isWhitespace })
    }
}
