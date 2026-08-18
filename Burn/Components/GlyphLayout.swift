//
//  GlyphLayout.swift
//

import CoreGraphics
import UIKit

/// Where every character sits on the page.
///
/// The burn is now driven by a flame the user drags, so the app has to answer
/// "which characters is the fire touching?" every frame. `Text` cannot tell us
/// that — it draws a paragraph as one opaque block — so the text is laid out here
/// instead, character by character, and drawn from these frames.
///
/// Because measurement and drawing both come from this one layout, they agree by
/// construction. The cost is that per-character advances ignore kerning between
/// pairs, so the result is a hair looser than `Text` would be; consistent, just
/// slightly wider.
///
/// A plain value type with no view attached, so the wrapping arithmetic can be
/// tested without rendering.
struct GlyphLayout {
    struct Glyph {
        let character: Character
        /// Index into the original string's `Array(text)`, so callers can map a
        /// glyph back to what the user typed.
        let index: Int
        let frame: CGRect
        /// 0-based line number, for effects that want to sweep or stagger.
        let line: Int
    }

    var glyphs: [Glyph] = []
    /// The area the laid-out text actually occupies.
    var size: CGSize = .zero
    var lineHeight: CGFloat = 0

    /// Whitespace is laid out (it takes up room) but never drawn or burned —
    /// setting fire to a space should not count as progress.
    var burnable: [Glyph] { glyphs.filter { !$0.character.isWhitespace } }

    // MARK: - Layout

    /// Lays `text` out centred, wrapping at `maxWidth`.
    ///
    /// Greedy word wrapping: words are kept whole, and a single word longer than
    /// the line is broken across lines rather than allowed to overflow.
    static func make(text: String, font: UIFont, maxWidth: CGFloat) -> GlyphLayout {
        guard maxWidth > 1, !text.isEmpty else { return GlyphLayout() }

        let characters = Array(text)
        let lineHeight = font.lineHeight

        // One measurement per distinct character, reused across repeats.
        var widthCache: [Character: CGFloat] = [:]
        func width(of character: Character) -> CGFloat {
            if let cached = widthCache[character] { return cached }
            let measured = String(character).size(withAttributes: [.font: font]).width
            widthCache[character] = measured
            return measured
        }

        // Split into tokens of "word + the spaces that follow it". Keeping the
        // trailing spaces attached is what lets a line break land *after* them.
        var tokens: [[Int]] = []
        var current: [Int] = []
        var sawWord = false
        for index in characters.indices {
            let character = characters[index]
            if character.isNewline {
                if !current.isEmpty { tokens.append(current) }
                tokens.append([index])  // a token of its own: forces a break
                current = []
                sawWord = false
                continue
            }
            if character.isWhitespace {
                current.append(index)
                sawWord = false
            } else {
                if !sawWord && current.contains(where: { characters[$0].isWhitespace }) {
                    // A new word begins after spaces — start a fresh token.
                    tokens.append(current)
                    current = []
                }
                current.append(index)
                sawWord = true
            }
        }
        if !current.isEmpty { tokens.append(current) }

        // Greedy wrap into lines of character indices.
        var lines: [[Int]] = []
        var line: [Int] = []
        var lineWidth: CGFloat = 0

        func endLine() {
            lines.append(line)
            line = []
            lineWidth = 0
        }

        for token in tokens {
            if token.count == 1, characters[token[0]].isNewline {
                // Kept on the line it ends, so every character in the string is
                // accounted for. It is whitespace, so it is never drawn or burned.
                line.append(token[0])
                endLine()
                continue
            }

            let tokenWidth = token.reduce(CGFloat.zero) { $0 + width(of: characters[$1]) }

            if !line.isEmpty && lineWidth + tokenWidth > maxWidth {
                endLine()
            }

            if tokenWidth > maxWidth {
                // A single unbreakable run wider than the line: break it by
                // character so it never spills off the page.
                for index in token {
                    let advance = width(of: characters[index])
                    if !line.isEmpty && lineWidth + advance > maxWidth { endLine() }
                    line.append(index)
                    lineWidth += advance
                }
            } else {
                line.append(contentsOf: token)
                lineWidth += tokenWidth
            }
        }
        if !line.isEmpty { endLine() }

        // Place each line, centred.
        var glyphs: [Glyph] = []
        var widest: CGFloat = 0

        for (lineIndex, lineIndices) in lines.enumerated() {
            // Centre on the visible span only. Whitespace at either end must not
            // shove the text off-centre — trimming just the trailing side leaves a
            // line that starts with spaces sitting too far right.
            let first = lineIndices.firstIndex { !characters[$0].isWhitespace }
            let last = lineIndices.lastIndex { !characters[$0].isWhitespace }

            var x: CGFloat = 0
            if let first, let last {
                let visibleWidth = lineIndices[first...last]
                    .reduce(CGFloat.zero) { $0 + width(of: characters[$1]) }
                let leading = lineIndices[lineIndices.startIndex..<first]
                    .reduce(CGFloat.zero) { $0 + width(of: characters[$1]) }
                widest = max(widest, visibleWidth)
                x = (maxWidth - visibleWidth) / 2 - leading
            }

            let y = CGFloat(lineIndex) * lineHeight

            for index in lineIndices {
                let advance = width(of: characters[index])
                glyphs.append(
                    Glyph(
                        character: characters[index],
                        index: index,
                        frame: CGRect(x: x, y: y, width: advance, height: lineHeight),
                        line: lineIndex
                    )
                )
                x += advance
            }
        }

        return GlyphLayout(
            glyphs: glyphs,
            size: CGSize(width: widest, height: CGFloat(lines.count) * lineHeight),
            lineHeight: lineHeight
        )
    }
}
