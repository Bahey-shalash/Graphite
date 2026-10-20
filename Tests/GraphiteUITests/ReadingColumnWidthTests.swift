import XCTest
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteUI

/// The reading view's column and the Live Preview column it must line up with: 730 points of
/// text with at least 33 points beside it, against the editor's 740-point column and the
/// 5-point padding of its text container and 28-point inset.
@MainActor
final class ReadingColumnWidthTests: XCTestCase {
    func testTheReadingColumnIsSevenHundredThirtyPointsWithAtLeastThirtyThreeBesideIt() {
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, 730)
        XCTAssertEqual(ReadingConfiguration.minimumHorizontalMargin, 33)
    }

    func testTheReadingColumnIsTheEditorsColumnLessTheTextContainersPaddingOnBothSides() {
        let textContainerPadding = NSTextContainer().lineFragmentPadding
        XCTAssertEqual(textContainerPadding, 5)
        #if os(macOS)
        XCTAssertEqual(MarkdownMacTextView.graphiteReadableColumnWidth, 740)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, MarkdownMacTextView.graphiteReadableColumnWidth - 2 * textContainerPadding)
        XCTAssertEqual(MarkdownMacTextView.minimumHorizontalInset, 32, "The Mac editor's inset is 32, not the 28 of the iPad editor the reading margin follows.")
        #endif
        #if canImport(UIKit)
        XCTAssertEqual(MarkdownTextView.readableColumnWidth, 740)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, MarkdownTextView.readableColumnWidth - 2 * textContainerPadding)
        XCTAssertEqual(MarkdownTextView.minimumHorizontalInset, 28)
        XCTAssertEqual(ReadingConfiguration.minimumHorizontalMargin, MarkdownTextView.minimumHorizontalInset + textContainerPadding)
        #endif
    }

    func testAThemesLineWidthIsScaledByTheTextSizeOverSixteenAndNeverBelowAnElevenPointText() {
        var light = ThemeModeTokens()
        light.lineWidth = 640
        let style = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: ThemeModeTokens()))
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 16), 640)
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 17), 640 * 17 / 16)
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 8), 640 * 11 / 16, "A very small text size is treated as 11.")
        let withoutWidth = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: ThemeModeTokens(), dark: ThemeModeTokens()))
        XCTAssertNil(withoutWidth.readableColumnWidth(forTextSize: 16), "Without a theme width the reading view keeps its 730 points.")
    }
}
