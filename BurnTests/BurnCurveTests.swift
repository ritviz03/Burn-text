//
//  BurnCurveTests.swift
//

import XCTest

@testable import Burn

final class BurnCurveTests: XCTestCase {
    func testStartsAtZeroAndEndsAtOne() {
        XCTAssertEqual(BurnCurve.progress(elapsed: 0, duration: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(BurnCurve.progress(elapsed: 2, duration: 2), 1, accuracy: 0.0001)
    }

    func testClampsOutsideTheWindow() {
        XCTAssertEqual(BurnCurve.progress(elapsed: -5, duration: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(BurnCurve.progress(elapsed: 99, duration: 2), 1, accuracy: 0.0001)
    }

    func testNeverGoesBackwards() {
        var previous = -1.0
        for step in 0...40 {
            let value = BurnCurve.progress(elapsed: Double(step) / 20, duration: 2)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testZeroDurationIsAlreadyFinished() {
        XCTAssertEqual(BurnCurve.progress(elapsed: 0, duration: 0), 1)
    }
}

final class BurnFieldTests: XCTestCase {
    func testFireArrivesLaterFurtherAcrossThePage() {
        XCTAssertLessThan(
            BurnField.ignition(x: 0.1, y: 0.5),
            BurnField.ignition(x: 0.9, y: 0.5)
        )
    }

    func testEverySparkIgnitesWithinTheBurn() {
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            for y in stride(from: 0.0, through: 1.0, by: 0.1) {
                let value = BurnField.ignition(x: x, y: y)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
    }
}
