import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class LibraryFolderItemCountsTests: XCTestCase {
    private func counts(_ answers: [String: Int]) -> LibraryFolderItemCounts {
        LibraryFolderItemCounts { folder in answers[folder.rawValue] }
    }

    func testAFolderOnScreenGetsItsCount() async throws {
        let itemCounts = counts(["Course": 12])
        itemCounts.tileAppeared(try VaultPath("Course"))
        try await waitUntil { itemCounts.counts[try VaultPath("Course")] == 12 }
    }

    func testAFolderThatScrollsAwayForgetsItsCount() async throws {
        let itemCounts = counts(["Course": 3])
        let course = try VaultPath("Course")
        itemCounts.tileAppeared(course)
        try await waitUntil { itemCounts.counts[course] == 3 }
        itemCounts.tileDisappeared(course)
        XCTAssertNil(itemCounts.counts[course])
    }

    func testARebuiltGridKeepsTheCountUntilItsLastTileIsGone() async throws {
        let itemCounts = counts(["Course": 3])
        let course = try VaultPath("Course")
        itemCounts.tileAppeared(course)
        try await waitUntil { itemCounts.counts[course] == 3 }
        itemCounts.tileAppeared(course)
        itemCounts.tileDisappeared(course)
        XCTAssertEqual(itemCounts.counts[course], 3, "The new tile appeared before the old one went.")
        itemCounts.tileDisappeared(course)
        XCTAssertNil(itemCounts.counts[course])
    }

    func testAFolderThatCannotBeReadHasNoCount() async throws {
        let itemCounts = counts(["Course": 5])
        let missing = try VaultPath("Missing")
        let readable = try VaultPath("Course")
        itemCounts.tileAppeared(missing)
        itemCounts.tileAppeared(readable)
        try await waitUntil { itemCounts.counts[readable] == 5 }
        XCTAssertNil(itemCounts.counts[missing], "The folders are counted in turn: the one before it was counted, so this one was tried and failed.")
    }

    func testCancellingForgetsEverything() async throws {
        let itemCounts = counts(["Course": 3])
        let course = try VaultPath("Course")
        itemCounts.tileAppeared(course)
        try await waitUntil { itemCounts.counts[course] == 3 }
        itemCounts.cancelAll()
        XCTAssertTrue(itemCounts.counts.isEmpty)
    }
}
