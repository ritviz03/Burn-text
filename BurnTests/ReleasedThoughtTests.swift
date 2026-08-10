//
//  ReleasedThoughtTests.swift
//

import SwiftData
import XCTest

@testable import Burn

@MainActor
final class ReleasedThoughtTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReleasedThought.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    func testSavesAThought() throws {
        let context = try makeContext()
        context.insert(ReleasedThought(text: "I am not enough"))
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ReleasedThought>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.text, "I am not enough")
    }

    func testDeletesAThought() throws {
        let context = try makeContext()
        let thought = ReleasedThought(text: "Everyone will find out")
        context.insert(thought)
        try context.save()

        context.delete(thought)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ReleasedThought>()).isEmpty)
    }

    func testReadsBackNewestFirst() throws {
        let context = try makeContext()
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        context.insert(ReleasedThought(text: "older", releasedAt: old))
        context.insert(ReleasedThought(text: "newer", releasedAt: recent))
        try context.save()

        let descriptor = FetchDescriptor<ReleasedThought>(
            sortBy: [SortDescriptor(\.releasedAt, order: .reverse)]
        )
        XCTAssertEqual(try context.fetch(descriptor).map(\.text), ["newer", "older"])
    }

    func testClearsEverything() throws {
        let context = try makeContext()
        context.insert(ReleasedThought(text: "one"))
        context.insert(ReleasedThought(text: "two"))
        try context.save()

        try context.delete(model: ReleasedThought.self)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ReleasedThought>()).isEmpty)
    }
}
