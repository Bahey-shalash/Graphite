import XCTest
@testable import ShareInbox

final class SharedContentMarkdownTests: XCTestCase {
    private func address(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text)) }

    func testAWebPageIsALinkTitledWithThePageTitle() throws {
        XCTAssertEqual(SharedContentMarkdown.link(title: "Swift Concurrency", address: try address("https://swift.org/concurrency")),
                       "[Swift Concurrency](https://swift.org/concurrency)")
    }

    func testAPageWithoutATitleIsTitledWithItsHost() throws {
        XCTAssertEqual(SharedContentMarkdown.link(title: "  ", address: try address("https://example.com/a")), "[example.com](https://example.com/a)")
    }

    func testBracketsInTheTitleAndParenthesesInTheAddressKeepOneLink() throws {
        XCTAssertEqual(SharedContentMarkdown.link(title: "Arrays [part 1] \\ notes", address: try address("https://en.wikipedia.org/wiki/Set_(mathematics)")),
                       "[Arrays \\[part 1\\] \\\\ notes](<https://en.wikipedia.org/wiki/Set_(mathematics)>)")
    }

    func testPartsAreJoinedByOneBlankLineWithEmptyPartsLeftOut() {
        XCTAssertEqual(SharedContentMarkdown.combinedText(["  First\n", "", "\n", "Second"]), "First\n\nSecond")
        XCTAssertEqual(SharedContentMarkdown.combinedText([]), "")
    }

    func testTheTitleIsTheFirstCandidateLineWithText() {
        XCTAssertEqual(SharedContentMarkdown.suggestedTitle(from: [nil, "", "\n\n## Kirchhoff's laws\nThe sum of currents"]), "Kirchhoff's laws")
        XCTAssertNil(SharedContentMarkdown.suggestedTitle(from: [nil, " \n "]))
    }

    func testALongTitleIsCutAtAWord() {
        let line = String(repeating: "word ", count: 30)
        let title = SharedContentMarkdown.suggestedTitle(from: [line])
        XCTAssertEqual(title?.count, 59)
        XCTAssertEqual(title?.hasSuffix("word"), true)
    }

    func testAPageSharedTwiceWithAndWithoutItsTrailingSlashIsOnePage() throws {
        let identities = try ["https://docs.swift.org/latest/documentation", "https://Docs.Swift.org/latest/documentation/",
                              "https://docs.swift.org/latest/documentation#top"].map { text in SharedContentMarkdown.pageIdentity(of: try address(text)) }
        XCTAssertEqual(Set(identities).count, 1)
        XCTAssertNotEqual(SharedContentMarkdown.pageIdentity(of: try address("https://docs.swift.org/a")),
                          SharedContentMarkdown.pageIdentity(of: try address("https://docs.swift.org/b")))
    }
}
