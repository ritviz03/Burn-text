//
//  BurnCurve.swift
//

import Foundation

/// Shapes the burn's 0...1 timeline.
enum BurnCurve {
    /// Long enough to watch, short enough not to feel held up.
    static let duration: TimeInterval = 2.2
    /// Used when Reduce Motion is on — a quick fade rather than a performance.
    static let reducedMotionDuration: TimeInterval = 0.45

    /// Eased progress for a given elapsed time.
    ///
    /// Smoothstep: the page catches slowly, the front races through the middle,
    /// and the last embers settle instead of snapping off.
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(elapsed / duration, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
