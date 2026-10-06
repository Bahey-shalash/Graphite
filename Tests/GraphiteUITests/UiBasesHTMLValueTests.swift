import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The text a cell shows for an `html()` value: formatting as attributes, links only to
/// web and mail addresses.
@MainActor
final class UiBasesHTMLValueTests: XCTestCase {
    private func attributedText(_ source: String) -> AttributedString {
        BaseHTMLValueView.attributedText(for: BaseHTMLText(source: source), accent: .blue)
    }

    func testFormattingBecomesTextAttributes() {
        let text = attributedText("<b>Bold</b> <i>italic</i> <code>code</code> <u>under</u> <s>gone</s> <mark>marked</mark>")
        XCTAssertEqual(String(text.characters), "Bold italic code under gone marked")
        func run(containing word: String) -> AttributedString.Runs.Run? {
            text.runs.first { run in String(text[run.range].characters).contains(word) }
        }
        XCTAssertEqual(run(containing: "Bold")?.inlinePresentationIntent, .stronglyEmphasized)
        XCTAssertEqual(run(containing: "italic")?.inlinePresentationIntent, .emphasized)
        XCTAssertEqual(run(containing: "code")?.inlinePresentationIntent, .code)
        XCTAssertNotNil(run(containing: "under")?.swiftUI.underlineStyle)
        XCTAssertNotNil(run(containing: "gone")?.swiftUI.strikethroughStyle)
        XCTAssertNotNil(run(containing: "marked")?.swiftUI.backgroundColor)
        XCTAssertNil(run(containing: "Bold")?.swiftUI.backgroundColor)
    }

    func testColorsAndLinks() {
        let text = attributedText("<span style=\"color: #ff0000\">red</span> <a href=\"https://obsidian.md\">site</a> <a href=\"javascript:alert(1)\">script</a>")
        func run(containing word: String) -> AttributedString.Runs.Run? {
            text.runs.first { run in String(text[run.range].characters).contains(word) }
        }
        XCTAssertEqual(run(containing: "red")?.swiftUI.foregroundColor, Color(red: 1, green: 0, blue: 0, opacity: 1))
        XCTAssertEqual(run(containing: "site")?.link, URL(string: "https://obsidian.md"))
        XCTAssertNil(run(containing: "script")?.link, "Only web and mail addresses are links.")
        XCTAssertFalse(text.runs.contains { run in run.link?.scheme == "javascript" })
    }

    func testRaisedAndLoweredTextIsSmallerAndOffTheBaseline() {
        let text = attributedText("E = mc<sup>2</sup>, H<sub>2</sub>O")
        let raised = text.runs.first { run in String(text[run.range].characters) == "2" }
        XCTAssertEqual(raised?.swiftUI.baselineOffset, 4)
        XCTAssertEqual(raised?.swiftUI.font, .caption)
        XCTAssertEqual(text.runs.filter { run in run.swiftUI.baselineOffset == -2 }.count, 1)
    }

    func testAListOfValuesShowsMarkupAsItsText() {
        XCTAssertEqual(BaseValueView.summaryText(.html("<b>Done</b> &amp; dusted")), "Done & dusted")
    }
}
