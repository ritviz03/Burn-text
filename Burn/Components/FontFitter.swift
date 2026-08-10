//
//  FontFitter.swift
//

import SwiftUI
import UIKit

/// Finds the largest point size at which a string still fits inside a box.
///
/// `Text.minimumScaleFactor` only ever *shrinks* type. A thought should also
/// grow — one word should fill the screen, a long paragraph should step down to
/// meet it — so we measure candidate sizes and binary search instead.
///
/// This is a plain struct rather than a `View` so the arithmetic can be tested
/// without rendering anything.
struct FontFitter {
    /// Never go below this, even if the text has to clip.
    var minimumSize: CGFloat = 15
    /// Never go above this, however short the thought.
    var maximumSize: CGFloat = 110
    /// Size used when there is nothing to measure yet, so an empty canvas still
    /// shows an invitingly large prompt.
    var emptySize: CGFloat = 44
    var design: UIFontDescriptor.SystemDesign = .serif
    var weight: UIFont.Weight = .regular
    /// Binary-search steps. 12 lands within ~0.03pt across the default range.
    var refinements: Int = 12

    func fittedSize(for text: String, in box: CGSize) -> CGFloat {
        guard box.width > 1, box.height > 1 else { return minimumSize }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Clamp, so a caller with a small `maximumSize` still gets a sane prompt.
            return min(max(emptySize, minimumSize), maximumSize)
        }
        guard fits(text, at: minimumSize, in: box) else { return minimumSize }
        if fits(text, at: maximumSize, in: box) { return maximumSize }

        var low = minimumSize   // known to fit
        var high = maximumSize  // known not to fit
        for _ in 0..<refinements {
            let mid = (low + high) / 2
            if fits(text, at: mid, in: box) {
                low = mid
            } else {
                high = mid
            }
        }
        // Settle on a half point: sub-pixel sizes make the type jitter as it grows.
        return (low * 2).rounded(.down) / 2
    }

    func fits(_ text: String, at size: CGFloat, in box: CGSize) -> Bool {
        let measured = measure(text, at: size, width: box.width)
        // Allow a hair of slack on width — an unbreakable long word can report
        // marginally wider than the box it was laid out in.
        return measured.height.rounded(.up) <= box.height.rounded(.up)
            && measured.width.rounded(.up) <= box.width.rounded(.up) + 0.5
    }

    func measure(_ text: String, at size: CGFloat, width: CGFloat) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(ofSize: size),
            .paragraphStyle: paragraph,
        ]

        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return bounds.size
    }

    /// The measuring font, matched to what SwiftUI will actually draw.
    func font(ofSize size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The SwiftUI font for a fitted size, so measurement and drawing agree.
    func swiftUIFont(ofSize size: CGFloat) -> Font {
        .system(size: size, weight: weight.fontWeight, design: design.fontDesign)
    }
}

extension UIFont.Weight {
    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

extension UIFontDescriptor.SystemDesign {
    var fontDesign: Font.Design {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
    }
}
