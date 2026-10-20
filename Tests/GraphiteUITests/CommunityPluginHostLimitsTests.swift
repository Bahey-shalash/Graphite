import XCTest
import GraphiteCore
@testable import GraphiteUI

private extension CommunityPluginHost {
    /// Delivers a message as WebKit would hand it over.
    func deliver(_ message: [String: Any]) async -> Any { await answer(message) }
}

/// How much `CommunityPluginHost` keeps: copies of drawn blocks, notices and a plugin's
/// recent problems.
@MainActor
final class CommunityPluginHostLimitsTests: XCTestCase {
    private func request(_ number: Int) throws -> CommunityPluginReadingBlockRequest {
        CommunityPluginReadingBlockRequest(kind: .codeBlock(language: "chart"), source: "block \(number)", note: try VaultPath("Note.md"), firstLine: number, lineCount: 3)
    }

    // MARK: Copies of drawn blocks

    func testTheHostKeepsAtMostSixtyFourBlockCopiesAndForgetsTheOldestFirst() throws {
        let host = CommunityPluginHost()
        XCTAssertEqual(CommunityPluginHost.maximumKeptCopies, 64)

        for number in 0..<70 { host.keepCopy(CommunityPluginCodeBlockCopy(html: "copy \(number)", height: 10), for: try request(number)) }

        XCTAssertEqual(host.lastCodeBlockCopies.count, 64)
        XCTAssertNil(host.lastCodeBlockCopies[try request(5)], "The six least recently drawn are gone.")
        XCTAssertEqual(host.lastCodeBlockCopies[try request(6)]?.html, "copy 6")
        XCTAssertEqual(host.lastCodeBlockCopies[try request(69)]?.html, "copy 69")
        XCTAssertEqual(host.keptCopyOrder, try (6..<70).map(request))
    }

    func testDrawingABlockAgainMakesItTheMostRecentlyDrawnSoItOutlastsOlderOnes() throws {
        let host = CommunityPluginHost()
        for number in 0..<64 { host.keepCopy(CommunityPluginCodeBlockCopy(html: "copy \(number)", height: 10), for: try request(number)) }

        host.keepCopy(CommunityPluginCodeBlockCopy(html: "drawn again", height: 20), for: try request(0))
        host.keepCopy(CommunityPluginCodeBlockCopy(html: "copy 64", height: 10), for: try request(64))

        XCTAssertEqual(host.lastCodeBlockCopies.count, 64)
        XCTAssertEqual(host.lastCodeBlockCopies[try request(0)]?.html, "drawn again")
        XCTAssertNil(host.lastCodeBlockCopies[try request(1)], "The block that went longest without being drawn is the one forgotten.")
    }

    // MARK: Notices

    func testAtMostFourNoticesAreShownAndANewOneDisplacesTheOldest() async {
        let host = CommunityPluginHost()

        for number in 1...6 {
            _ = await host.deliver(["operation": "notice.show", "noticeIdentifier": "n\(number)", "message": "Notice \(number)", "durationMilliseconds": 0])
        }

        XCTAssertEqual(host.notices.map(\.id), ["n3", "n4", "n5", "n6"])
    }

    func testANoticeShowsAtMostThreeActionButtons() async {
        let host = CommunityPluginHost()

        _ = await host.deliver(["operation": "notice.show", "noticeIdentifier": "n1", "message": "Choose", "actions": ["A", "B", "C", "D", "E"], "durationMilliseconds": 0])

        XCTAssertEqual(host.notices.first?.actions, ["A", "B", "C"])
    }

    func testGraphitesOwnNoticesGetIdentifiersPrefixedGraphiteAndTheFourNoticeLimitAppliesToThemToo() {
        let host = CommunityPluginHost()

        for number in 1...5 { host.showNotice("Problem \(number)", pluginIdentifier: nil) }

        XCTAssertEqual(host.notices.map(\.message), ["Problem 2", "Problem 3", "Problem 4", "Problem 5"])
        XCTAssertTrue(host.notices.allSatisfy { notice in notice.id.hasPrefix("graphite-") })
        XCTAssertEqual(Set(host.notices.map(\.id)).count, 4, "Each has its own identifier.")
    }

    func testAnUnchangedMessageFromTheSamePluginIsShownOnlyOnce() {
        let host = CommunityPluginHost()

        host.showNotice("Same problem", pluginIdentifier: nil)
        host.showNotice("Same problem", pluginIdentifier: nil)

        XCTAssertEqual(host.notices.count, 1)
    }

    func testTappingAGraphiteNoticeRemovesItWithoutAskingAPlugin() {
        let host = CommunityPluginHost()
        host.showNotice("Problem", pluginIdentifier: nil)
        let identifier = host.notices[0].id

        host.tapNotice(identifier, actionIndex: nil)

        XCTAssertEqual(host.notices, [])
    }

    // MARK: A plugin's problems

    func testOnlyTheLastFiveRuntimeProblemsOfAPluginAreKept() async {
        let host = CommunityPluginHost()

        for number in 1...8 { _ = await host.deliver(["operation": "plugin.failure", "pluginIdentifier": "p", "message": "Problem \(number)"]) }
        _ = await host.deliver(["operation": "plugin.failure", "pluginIdentifier": "q", "message": "Other plugin's problem"])

        XCTAssertEqual(host.runtimeProblems["p"], (4...8).map { number in "Problem \(number)" })
        XCTAssertEqual(host.runtimeProblems["q"], ["Other plugin's problem"], "The limit is per plugin.")
    }
}
