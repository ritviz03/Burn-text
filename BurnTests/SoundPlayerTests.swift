//
//  SoundPlayerTests.swift
//

import XCTest

@testable import Burn

final class SoundPlayerLeadInTests: XCTestCase {
    func testNormalBurnGetsTheFullLeadIn() {
        XCTAssertEqual(
            SoundPlayer.leadIn(for: BurnCurve.duration),
            SoundPlayer.burnLeadIn,
            accuracy: 0.0001
        )
    }

    /// The bug this guards: a flat 0.8s lead-in is longer than the 0.45s Reduce
    /// Motion burn, so the sound would be scheduled for after the burn had ended
    /// and never be heard at all.
    func testShortBurnStillGetsHeard() {
        let duration = BurnCurve.reducedMotionDuration
        let leadIn = SoundPlayer.leadIn(for: duration)
        XCTAssertGreaterThan(leadIn, 0)
        XCTAssertLessThan(leadIn, duration)
    }

    func testLeadInNeverOutlastsAnyBurn() {
        for duration in stride(from: 0.05, through: 5.0, by: 0.05) {
            XCTAssertLessThan(
                SoundPlayer.leadIn(for: duration),
                duration,
                "a \(duration)s burn would never hear its own sound"
            )
        }
    }

    func testLeadInIsNeverNegative() {
        XCTAssertGreaterThanOrEqual(SoundPlayer.leadIn(for: 0), 0)
    }

    func testVolumeLeavesHeadroom() {
        XCTAssertGreaterThan(SoundPlayer.volume, 0)
        XCTAssertLessThan(SoundPlayer.volume, 1)
    }
}
