//
//  BurnCanvas.swift
//

import SwiftUI

/// Colours for a character as it heats up and goes.
enum BurnPalette {
    static let ink = Color(red: 0.93, green: 0.91, blue: 0.87)

    private static let whiteHot = Color(red: 1.00, green: 0.97, blue: 0.86)
    private static let amber = Color(red: 1.00, green: 0.69, blue: 0.20)
    private static let emberRed = Color(red: 0.96, green: 0.36, blue: 0.09)
    private static let charred = Color(red: 0.44, green: 0.10, blue: 0.04)

    /// How a character should be drawn at a given heat.
    ///
    /// - `opacity` holds at 1 while it heats, then falls away as it chars.
    /// - `rise` and `scale` let a dying character lift and shrink, so it reads as
    ///   being carried off rather than simply switched off.
    /// - `bloom` drives an additive blurred pass underneath, which is what makes
    ///   the hot characters look lit rather than merely orange.
    static func glyph(heat: Double) -> (color: Color, opacity: Double, rise: Double, scale: Double, bloom: Double) {
        let heat = min(max(heat, 0), 1)

        let color: Color
        switch heat {
        case ..<0.001:
            color = ink
        case ..<0.3:
            color = blend(ink, whiteHot, heat / 0.3)
        case ..<0.55:
            color = blend(whiteHot, amber, (heat - 0.3) / 0.25)
        case ..<0.8:
            color = blend(amber, emberRed, (heat - 0.55) / 0.25)
        default:
            color = blend(emberRed, charred, (heat - 0.8) / 0.2)
        }

        // Fades only over the last stretch, so a character stays legible while
        // it is catching — you can see what you are about to lose.
        let fade = heat <= 0.62 ? 1.0 : 1 - (heat - 0.62) / 0.38
        let bloom = heat <= 0.02 ? 0 : sin(min(heat, 1) * .pi) * 0.9

        return (
            color: color,
            opacity: max(fade, 0),
            rise: heat <= 0.5 ? 0 : (heat - 0.5) * 26,
            scale: heat <= 0.5 ? 1 : 1 - (heat - 0.5) * 0.28,
            bloom: bloom
        )
    }

    static func emberColor(_ ember: FireModel.Ember) -> Color {
        let fade = 1 - ember.progress
        if ember.isSmoke {
            return Color(white: 0.62, opacity: 0.16 * fade)
        }
        // Cools from white-hot through orange to a dull red as it climbs.
        let cooled = blend(whiteHot, ember.progress < 0.5 ? amber : Color(red: 0.85, green: 0.22, blue: 0.05), ember.progress)
        return cooled.opacity(0.55 + 0.45 * fade)
    }

    private static func blend(_ from: Color, _ to: Color, _ amount: Double) -> Color {
        let amount = min(max(amount, 0), 1)
        let a = UIColor(from).components
        let b = UIColor(to).components
        return Color(
            red: a.r + (b.r - a.r) * amount,
            green: a.g + (b.g - a.g) * amount,
            blue: a.b + (b.b - a.b) * amount
        )
    }
}

private extension UIColor {
    var components: (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}

/// Draws the thought, character by character, plus the embers coming off it.
///
/// One `Canvas` rather than a view per character: the text and the fire are drawn
/// in the same pass, and 200-odd embers cost nothing extra. It also sidesteps
/// compositing a per-glyph shader, which is the fragile way to do this.
struct BurnCanvas: View {
    let layout: GlyphLayout
    let fire: FireModel
    let font: Font
    /// Offset of the layout inside the canvas, so the text sits where it did in
    /// the editor.
    let origin: CGPoint

    var body: some View {
        Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: false) { context, _ in
            draw(in: &context)
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext) {
        for index in layout.glyphs.indices {
            let glyph = layout.glyphs[index]
            guard !glyph.character.isWhitespace else { continue }

            let heat = fire.heat(at: index)
            guard heat < FireModel.consumed else { continue }

            let style = BurnPalette.glyph(heat: heat)
            let resolved = context.resolve(
                Text(String(glyph.character)).font(font).foregroundStyle(style.color)
            )
            let centre = CGPoint(
                x: origin.x + glyph.frame.midX,
                y: origin.y + glyph.frame.midY - style.rise
            )

            // The lit halo, underneath.
            if style.bloom > 0.02 {
                context.drawLayer { layer in
                    layer.opacity = style.opacity * style.bloom * 0.85
                    layer.addFilter(.blur(radius: 5 + 7 * style.bloom))
                    layer.blendMode = .plusLighter
                    layer.translateBy(x: centre.x, y: centre.y)
                    layer.scaleBy(x: style.scale, y: style.scale)
                    layer.draw(resolved, at: .zero, anchor: .center)
                }
            }

            context.drawLayer { layer in
                layer.opacity = style.opacity
                layer.translateBy(x: centre.x, y: centre.y)
                layer.scaleBy(x: style.scale, y: style.scale)
                layer.draw(resolved, at: .zero, anchor: .center)
            }
        }

        drawEmbers(in: &context)
    }

    private func drawEmbers(in context: inout GraphicsContext) {
        guard !fire.embers.isEmpty else { return }

        // Smoke first so sparks read on top of it.
        for ember in fire.embers where ember.isSmoke {
            fill(ember, in: &context, blend: .normal)
        }
        for ember in fire.embers where !ember.isSmoke {
            fill(ember, in: &context, blend: .plusLighter)
        }
    }

    private func fill(_ ember: FireModel.Ember, in context: inout GraphicsContext, blend: GraphicsContext.BlendMode) {
        // Sparks shrink as they cool; smoke swells as it disperses.
        let scale = ember.isSmoke ? 1 + ember.progress * 1.6 : 1 - ember.progress * 0.55
        let radius = ember.radius * scale
        guard radius > 0.05 else { return }

        let rect = CGRect(
            x: origin.x + ember.x - radius,
            y: origin.y + ember.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.drawLayer { layer in
            layer.blendMode = blend
            if ember.isSmoke { layer.addFilter(.blur(radius: radius * 0.9)) }
            layer.fill(Path(ellipseIn: rect), with: .color(BurnPalette.emberColor(ember)))
        }
    }
}
