//
//  BurnField.swift
//

import Foundation

/// Swift mirror of the `constant` declarations at the top of `Burn.metal`.
///
/// The shader decides *when* each pixel catches fire; the particle layer needs
/// the same answer so sparks appear on the front instead of drifting up from
/// wherever. Change a value here and change it there.
enum BurnField {
    static let sweepX = 0.72
    static let sweepY = 0.18
    /// Share of the field taken by the sweep rather than the noise.
    static let sweepWeight = 0.55
    /// Width of the glowing band, in field units.
    static let edgeBand = 0.16

    /// The progress value at which the point `(x, y)` — each 0...1 across the
    /// view — catches fire.
    ///
    /// Inverts the shader's threshold, which advances from `-edgeBand` to
    /// `1 + edgeBand` as progress runs 0...1. The shader's per-pixel noise is
    /// replaced by its mean of 0.5: individual sparks are jittered by the caller,
    /// and using the mean keeps the field's *scale* honest. Dropping the noise
    /// term entirely would stretch the gradient by 1/sweepWeight and make sparks
    /// lead the flame on one side and trail it on the other.
    static func ignition(x: Double, y: Double) -> Double {
        let sweep = x * sweepX + y * sweepY
        let field = sweepWeight * sweep + (1 - sweepWeight) * 0.5
        return (field + edgeBand) / (1 + 2 * edgeBand)
    }
}
