//
//  MatchStick.swift
//

import SwiftUI

/// A flame silhouette.
///
/// Same profile as the app icon (`Tools/make_app_icon.py`): a fast swell off the
/// base tapering to a point, from `t**rise * (1-t)**fall`. One smooth curve, so
/// the outline never kinks.
struct FlameShape: Shape {
    var rise: Double = 0.75
    var fall: Double = 1.70
    /// Outline resolution. 28 is smooth at the sizes this is drawn.
    var steps: Int = 28

    func path(in rect: CGRect) -> Path {
        let peak = rise / (rise + fall)
        let normal = pow(peak, rise) * pow(1 - peak, fall)
        guard normal > 0 else { return Path() }

        func halfWidth(at t: Double) -> Double {
            guard t > 0, t < 1 else { return 0 }
            return pow(t, rise) * pow(1 - t, fall) / normal * (rect.width / 2)
        }

        // t runs 0 at the base to 1 at the tip.
        func point(_ t: Double, mirrored: Bool) -> CGPoint {
            let half = halfWidth(at: t)
            return CGPoint(
                x: rect.midX + (mirrored ? half : -half),
                y: rect.maxY - t * rect.height
            )
        }

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        for step in 0...steps {
            path.addLine(to: point(Double(step) / Double(steps), mirrored: false))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: point(Double(step) / Double(steps), mirrored: true))
        }
        path.closeSubpath()
        return path
    }
}

/// The match the user drags over their words.
///
/// Laid out so the flame tip sits at a known point (`MatchStick.tip`) inside a
/// fixed frame — `ComposeView` positions the view from that, so the hot point and
/// the drawn flame are the same place by construction.
///
/// The tip is held well above the fingertip: on a phone the hand covers whatever
/// it touches, and you need to see the word you are about to lose.
struct MatchStick: View {
    /// 0...1, walked forward every frame. Drives the flicker.
    var phase: Double
    var isLit: Bool

    static let size = CGSize(width: 92, height: 156)
    /// Where the flame tip sits inside `size`.
    static let tip = CGPoint(x: 46, y: 16)
    /// How far above the finger to hold the tip.
    static let reach: CGFloat = 52

    /// The view centre that puts the tip at `point`.
    static func centre(forTipAt point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x + (size.width / 2 - tip.x),
            y: point.y + (size.height / 2 - tip.y)
        )
    }

    private var flicker: Double {
        // Two out-of-step waves, so it never looks like a loop.
        sin(phase * 11.0) * 0.5 + sin(phase * 6.3 + 1.7) * 0.5
    }

    var body: some View {
        ZStack(alignment: .top) {
            stick
            if isLit { flame }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(nil, value: phase)
    }

    // MARK: - Pieces

    private var stick: some View {
        VStack(spacing: 0) {
            // The burnt end, just under the flame.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(red: 0.32, green: 0.20, blue: 0.13)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 8, height: 22)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.87, green: 0.74, blue: 0.50),
                            Color(red: 0.71, green: 0.56, blue: 0.35),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 7)
        }
        .frame(height: Self.size.height - Self.tip.y - 6)
        .padding(.top, Self.tip.y + 6)
        .rotationEffect(.degrees(4), anchor: .top)
        .shadow(color: .black.opacity(0.55), radius: 5, y: 3)
    }

    private var flame: some View {
        ZStack {
            // Glow first, so the flame sits inside its own light.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.12).opacity(0.55),
                            Color(red: 1.0, green: 0.30, blue: 0.05).opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 46
                    )
                )
                .frame(width: 108, height: 108)
                .blendMode(.plusLighter)
                .scaleEffect(1 + flicker * 0.06)

            FlameShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.85, blue: 0.42),
                            Color(red: 0.98, green: 0.42, blue: 0.08),
                            Color(red: 0.80, green: 0.16, blue: 0.04),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 26, height: 46)
                .scaleEffect(x: 1 + flicker * 0.05, y: 1 + flicker * 0.09, anchor: .bottom)

            FlameShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 1.0), Color(red: 1.0, green: 0.93, blue: 0.72)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 12, height: 24)
                .offset(y: 11)
                .scaleEffect(x: 1, y: 1 + flicker * 0.12, anchor: .bottom)
                .blendMode(.plusLighter)
        }
        // Sit the flame so its tip lands on `tip`.
        .frame(width: 108, height: 108, alignment: .center)
        .offset(y: Self.tip.y - 108 / 2 + 23)
    }
}
