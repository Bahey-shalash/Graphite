import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class LinkLocatorTests: XCTestCase {
    func testFindsTheLinkAroundACharacter() throws {
        let line = "See [[Lab notebook#Result|the result]] and [the slides](Slides.pdf#page=3), or ![[Diagram.png]] and [a site](https://example.com)."
        let source = line as NSString
        let wikilinkStart = source.range(of: "[[Lab").location
        XCTAssertEqual(LinkLocator.link(in: line, at: wikilinkStart + 5, includesEnd: false), .note(target: "Lab notebook#Result", isWiki: true),
                       "The alias is not part of the target.")
        let markdownStart = source.range(of: "[the slides]").location
        XCTAssertEqual(LinkLocator.link(in: line, at: markdownStart + 2, includesEnd: false), .note(target: "Slides.pdf#page=3", isWiki: false))
        XCTAssertNil(LinkLocator.link(in: line, at: source.range(of: "Diagram").location, includesEnd: false), "An embed is not a link to follow.")
        XCTAssertEqual(LinkLocator.link(in: line, at: source.range(of: "a site").location, includesEnd: false), .web(try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(LinkLocator.link(in: line, at: 1, includesEnd: false))
    }

    func testTheCursorRightAfterALinkCountsOnlyWhenAsked() {
        let line = "Read [[Zebra note]]"
        let end = (line as NSString).length
        XCTAssertNil(LinkLocator.link(in: line, at: end, includesEnd: false))
        XCTAssertEqual(LinkLocator.link(in: line, at: end, includesEnd: true), .note(target: "Zebra note", isWiki: true))
    }
}
