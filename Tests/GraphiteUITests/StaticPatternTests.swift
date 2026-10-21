import Foundation
import XCTest
@testable import GraphiteUI
import GraphiteCore

/// Compiles every regular expression written in GraphiteUI's source (FR-62), so a
/// malformed pattern fails here instead of stopping the app at its first use.
final class StaticPatternTests: XCTestCase {
    func testEveryConstantPatternCompiles() {
        assertEveryCaseCompiles(LivePreviewTextPattern.self)
        assertEveryCaseCompiles(ObsidianMarkdownParserPattern.self)
        assertEveryCaseCompiles(ParagraphEditingPattern.self)
        assertEveryCaseCompiles(PropertyDateTextPattern.self)
    }

    private func assertEveryCaseCompiles<PatternSet: StaticPatternSet>(_ patternSet: PatternSet.Type) {
        for pattern in PatternSet.allCases {
            XCTAssertNoThrow(try NSRegularExpression(pattern: pattern.rawValue, options: pattern.options), "\(PatternSet.self).\(pattern)")
        }
    }
}
