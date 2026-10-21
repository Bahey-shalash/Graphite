import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class NavigationTests: XCTestCase {
    func testFuzzyMatchingPrefersWordStartsAndRuns() throws {
        XCTAssertNil(FuzzyMatcher.match("xyz", in: "Lecture notes"))
        let wordStarts = try XCTUnwrap(FuzzyMatcher.match("ln", in: "Lecture notes"))
        let scattered = try XCTUnwrap(FuzzyMatcher.match("ln", in: "Balance sheet"))
        XCTAssertGreaterThan(wordStarts.score, scattered.score)
        XCTAssertEqual(wordStarts.matchedRanges, [0..<1, 8..<9])
        let prefix = try XCTUnwrap(FuzzyMatcher.match("lec", in: "Lecture 3"))
        let inside = try XCTUnwrap(FuzzyMatcher.match("lec", in: "Collection of lectures"))
        XCTAssertGreaterThan(prefix.score, inside.score)
        XCTAssertNotNil(FuzzyMatcher.match("ubung", in: "Übungsblatt 2"), "Accents are ignored.")
        XCTAssertEqual(FuzzyMatcher.match("💡i", in: "💡 Ideas")?.matchedRanges, [0..<2, 3..<4])
    }

    func testHistoryGoesBackAndForwardLikeABrowser() throws {
        var history = NavigationHistory()
        let first = try VaultPath("A.md"), second = try VaultPath("B.md"), third = try VaultPath("C.md")
        history.visit(first); history.visit(second); history.visit(third)
        XCTAssertEqual(history.goBack(), second)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.goForward(), second)
        history.visit(try VaultPath("D.md"))
        XCTAssertFalse(history.canGoForward, "Visiting drops what was ahead.")
        XCTAssertEqual(history.entries.map(\.name), ["A.md", "B.md", "D.md"])
        history.replacePrefix(second, with: try VaultPath("Folder/B2.md"))
        XCTAssertEqual(history.entries.map(\.rawValue), ["A.md", "Folder/B2.md", "D.md"])
        history.remove(inside: try VaultPath("D.md"))
        XCTAssertEqual(history.current?.rawValue, "Folder/B2.md")
        history.visit(first)
        history.remove(inside: try VaultPath("Folder"))
        XCTAssertEqual(history.entries.map(\.name), ["A.md"], "A.md, then A.md again once B2 is gone, is one step.")
    }

    func testRecentFilesKeepNewestFirstWithoutRepeats() throws {
        var recent = RecentFiles()
        for name in ["A.md", "B.md", "A.md"] { recent.record(try VaultPath(name)) }
        XCTAssertEqual(recent.paths.map(\.name), ["A.md", "B.md"])
        recent.replacePrefix(try VaultPath("B.md"), with: try VaultPath("A.md"))
        XCTAssertEqual(recent.paths.map(\.name), ["A.md"])
    }
}
