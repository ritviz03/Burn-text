//
//  AutoSizingText.swift
//

import SwiftUI

/// Draws text at the largest size that still fits the space it is given.
///
/// Used for the burning copy of a thought. The editor in `ComposeView` runs the
/// same `FontFitter` against the same box, so the type does not jump when the
/// fire takes over.
struct AutoSizingText: View {
    let text: String
    var fitter = FontFitter()

    var body: some View {
        GeometryReader { proxy in
            let size = fitter.fittedSize(for: text, in: proxy.size)
            Text(text)
                .font(fitter.swiftUIFont(ofSize: size))
                .multilineTextAlignment(.center)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

#Preview {
    VStack {
        AutoSizingText(text: "I am not enough")
            .frame(height: 260)
        Divider()
        AutoSizingText(text: String(repeating: "This thought keeps circling back. ", count: 6))
            .frame(height: 260)
    }
    .padding()
    .preferredColorScheme(.dark)
}
