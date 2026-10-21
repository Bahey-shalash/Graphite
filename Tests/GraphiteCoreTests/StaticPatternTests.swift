/**
 * File: StaticPatternTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Compiles every constant regular expression of GraphiteCore, so a malformed pattern fails here.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

/// Compiles every regular expression written in GraphiteCore's source (FR-62), so a
/// malformed pattern fails here instead of stopping the app at its first use.
final class StaticPatternTests: XCTestCase {
    func testEveryConstantPatternCompiles() {
        assertEveryCaseCompiles(BaseDateParsingPattern.self)
        assertEveryCaseCompiles(BaseDurationParsingPattern.self)
        assertEveryCaseCompiles(BaseFrontmatterPattern.self)
        assertEveryCaseCompiles(BasePropertyEditingPattern.self)
        assertEveryCaseCompiles(BaseQueryEnginePattern.self)
        assertEveryCaseCompiles(CommunityPluginCompatibilityPattern.self)
        assertEveryCaseCompiles(CommunityPluginMarkdownRenderingPattern.self)
        assertEveryCaseCompiles(EmbedLocatorPattern.self)
        assertEveryCaseCompiles(FootnotesPattern.self)
        assertEveryCaseCompiles(FrontmatterLocatorPattern.self)
        assertEveryCaseCompiles(FrontmatterRegionPattern.self)
        assertEveryCaseCompiles(MarkdownSectionUnitsPattern.self)
        assertEveryCaseCompiles(HTMLToMarkdownPattern.self)
        assertEveryCaseCompiles(LaTeXCompatibilityPattern.self)
        assertEveryCaseCompiles(LinkLocatorPattern.self)
        assertEveryCaseCompiles(MarkdownBlockIdentifierSyntaxPattern.self)
        assertEveryCaseCompiles(MarkdownHeadingSyntaxPattern.self)
        assertEveryCaseCompiles(MarkdownInlineMathPattern.self)
        assertEveryCaseCompiles(MarkdownLinkSourcePattern.self)
        assertEveryCaseCompiles(MarkdownListSyntaxPattern.self)
        assertEveryCaseCompiles(MarkdownQuoteSyntaxPattern.self)
        assertEveryCaseCompiles(MarkdownSemanticsPattern.self)
        assertEveryCaseCompiles(MarkdownStyleScannerPattern.self)
        assertEveryCaseCompiles(MarkdownTableEditingPattern.self)
        assertEveryCaseCompiles(MentionsPattern.self)
        assertEveryCaseCompiles(NoteLinkScannerPattern.self)
        assertEveryCaseCompiles(NotePreviewDocumentPattern.self)
        assertEveryCaseCompiles(PropertyRenamingPattern.self)
        assertEveryCaseCompiles(ReadAloudDocumentPattern.self)
        assertEveryCaseCompiles(ReadAloudPronunciationsPattern.self)
        assertEveryCaseCompiles(ReadingInlineMarkingPattern.self)
        assertEveryCaseCompiles(ReadingMathPreparationPattern.self)
        assertEveryCaseCompiles(ReadingTasksPattern.self)
        assertEveryCaseCompiles(TagSyntaxPattern.self)
        assertEveryCaseCompiles(TemplateRendererPattern.self)
        assertEveryCaseCompiles(TextColorMarkupPattern.self)
    }

    /// `numberWithUnit` spells out the unit table; a unit added to one must be added to the other.
    func testNumberWithUnitPatternSpellsOutEveryUnit() {
        let symbols = ReadAloudPronunciations.units.keys
            .sorted { first, second in first.count != second.count ? first.count > second.count : first < second }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        XCTAssertTrue(ReadAloudPronunciationsPattern.numberWithUnit.rawValue.contains("(" + symbols + ")"))
    }

    private func assertEveryCaseCompiles<PatternSet: StaticPatternSet>(_ patternSet: PatternSet.Type) {
        for pattern in PatternSet.allCases {
            XCTAssertNoThrow(try NSRegularExpression(pattern: pattern.rawValue, options: pattern.options), "\(PatternSet.self).\(pattern)")
        }
    }
}
