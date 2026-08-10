//
//  BurnView.swift
//

import SwiftUI

/// The thought, on fire.
///
/// One clock drives everything. `TimelineView` ticks each frame, the elapsed
/// time becomes an eased 0...1 progress, and that single number feeds both the
/// shader's dissolve threshold and the ember field — so the fire and the sparks
/// always agree on where the burn front is.
struct BurnView: View {
    let text: String
    let startedAt: Date
    let duration: TimeInterval
    let seed: Double
    var fitter = FontFitter()
    /// When Reduce Motion is on, skip the shader and the sparks and simply fade.
    var reducesMotion = false

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = BurnCurve.progress(elapsed: elapsed, duration: duration)
            burning(progress: progress)
        }
    }

    @ViewBuilder
    private func burning(progress: Double) -> some View {
        if reducesMotion {
            AutoSizingText(text: text, fitter: fitter)
                .opacity(1 - progress)
        } else {
            ZStack {
                dissolving(progress: progress)
                EmberParticles(progress: progress, seed: seed)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dissolving(progress: Double) -> some View {
        AutoSizingText(text: text, fitter: fitter)
            // Flatten the glyphs into one layer first: the shader erases alpha,
            // and it should erase the rendered paragraph rather than each run.
            .drawingGroup()
            .visualEffect { view, proxy in
                view.colorEffect(
                    ShaderLibrary.burn(
                        .float2(proxy.size),
                        .float(Float(progress)),
                        .float(Float(seed)),
                        .float(Float(BurnField.edgeBand))
                    )
                )
            }
    }
}

#Preview {
    BurnView(
        text: "I am not enough",
        startedAt: .now,
        duration: 6,
        seed: 12
    )
    .padding()
    .background(.black)
}
