//
//  FontFitterTests.swift
//

import XCTest

@testable import Burn

final class FontFitterTests: XCTestCase {
    private let box = CGSize(width: 320, height: 480)
    private let fitter = FontFitter()

    func testShortThoughtGetsLargerTypeThanLongOne() {
        let short = fitter.fittedSize(for: "Fear", in: box)
        let long = fitter.fittedSize(
            for: String(repeating: "This thought keeps circling back. ", count: 8),
            in: box
        )
        XCTAssertGreaterThan(short, long)
    }

    func testTypeGrowsToFillABiggerBox() {
        let thought = "I am not enough for this"
        let cramped = fitter.fittedSize(for: thought, in: CGSize(width: 200, height: 200))
        let roomy = fitter.fittedSize(for: thought, in: CGSize(width: 400, height: 700))
        XCTAssertGreaterThan(roomy, cramped)
    }

    func testEmptyTextUsesThePromptSize() {
        XCTAssertEqual(fitter.fittedSize(for: "", in: box), fitter.emptySize)
        XCTAssertEqual(fitter.fittedSize(for: "  \n  ", in: box), fitter.emptySize)
    }

    func testResultAlwaysStaysWithinBounds() {
        let wall = String(repeating: "unrelenting ", count: 400)
        let size = fitter.fittedSize(for: wall, in: box)
        XCTAssertGreaterThanOrEqual(size, fitter.minimumSize)
        XCTAssertLessThanOrEqual(size, fitter.maximumSize)
    }

    func testTheChosenSizeActuallyFits() {
        let thought = "Everyone will find out I have no idea what I am doing"
        let size = fitter.fittedSize(for: thought, in: box)
        XCTAssertTrue(
            fitter.fits(thought, at: size, in: box),
            "fittedSize returned \(size), which does not fit \(box)"
        )
    }

    func testOneMorePointWouldNotFit() {
        // The search should land on the boundary, not well short of it.
        let thought = "Everyone will find out I have no idea what I am doing"
        let size = fitter.fittedSize(for: thought, in: box)
        guard size < fitter.maximumSize else { return } // capped, nothing to prove
        XCTAssertFalse(fitter.fits(thought, at: size + 1, in: box))
    }

    func testDegenerateBoxFallsBackToTheMinimum() {
        XCTAssertEqual(fitter.fittedSize(for: "anything", in: .zero), fitter.minimumSize)
    }
}
