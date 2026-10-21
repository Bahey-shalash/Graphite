/**
 * File: MarkdownSectionUnitsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Lists, tables and code blocks divided into the parts a printed page may end between, and the
 *              Markdown of each run of parts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import XCTest
@testable import GraphiteCore

final class MarkdownSectionUnitsTests: XCTestCase {
    func testAListIsDividedByItsTopLevelItemsWithTheirNestedLines() throws {
        let units = try XCTUnwrap(MarkdownSectionUnits.units(of: "- One\n  - Nested\n- Two\n- Three\n  continued"))
        XCTAssertEqual(units.kind, .listItems)
        XCTAssertEqual(units.unitCount, 3)
        XCTAssertEqual(units.markdown(forUnits: 0..<1), "- One\n  - Nested")
        XCTAssertEqual(units.markdown(forUnits: 1..<3), "- Two\n- Three\n  continued")
    }

    func testARunInsideAnOrderedListCountsOnFromTheRunBefore() throws {
        let units = try XCTUnwrap(MarkdownSectionUnits.units(of: "3. Third\n1. Fourth\n1. Fifth\n1. Sixth"))
        XCTAssertEqual(units.markdown(forUnits: 0..<2), "3. Third\n1. Fourth", "The first run keeps the list's own start.")
        XCTAssertEqual(units.markdown(forUnits: 2..<4), "5. Fifth\n1. Sixth", "CommonMark numbers a list from its first item.")
    }

    func testATableRepeatsItsHeaderInEveryRun() throws {
        let table = "| Name | Value |\n| --- | ---: |\n| a | 1 |\n| b | 2 |\n| c | 3 |"
        let units = try XCTUnwrap(MarkdownSectionUnits.units(of: table))
        XCTAssertEqual(units.kind, .tableRows)
        XCTAssertEqual(units.unitCount, 3)
        XCTAssertEqual(units.markdown(forUnits: 1..<3), "| Name | Value |\n| --- | ---: |\n| b | 2 |\n| c | 3 |")
    }

    func testAFencedCodeBlockRepeatsItsFencesInEveryRun() throws {
        let units = try XCTUnwrap(MarkdownSectionUnits.units(of: "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```"))
        XCTAssertEqual(units.kind, .codeLines)
        XCTAssertEqual(units.unitCount, 3)
        XCTAssertEqual(units.markdown(forUnits: 1..<2), "```swift\nlet b = 2\n```")
    }

    func testAnUnclosedFenceIsDividedWithoutAClosingFence() throws {
        let units = try XCTUnwrap(MarkdownSectionUnits.units(of: "~~~\none\ntwo"))
        XCTAssertEqual(units.markdown(forUnits: 1..<2), "~~~\ntwo")
    }

    func testParagraphsQuotesAndSingleItemsAreNotDivided() {
        XCTAssertNil(MarkdownSectionUnits.units(of: "A paragraph\nthat runs over two lines."))
        XCTAssertNil(MarkdownSectionUnits.units(of: "> A quote\n> on two lines"))
        XCTAssertNil(MarkdownSectionUnits.units(of: "- Only item\n  with a second line"))
        XCTAssertNil(MarkdownSectionUnits.units(of: "Text\n\n- Item\n- Item"), "Two sections are divided by the reading view first.")
    }

    func testEveryRunOfAllPartsIsTheSectionItself() throws {
        for section in ["- a\n- b", "| h |\n| - |\n| 1 |\n| 2 |", "```\nx\ny\n```"] {
            let units = try XCTUnwrap(MarkdownSectionUnits.units(of: section))
            XCTAssertEqual(units.markdown(forUnits: 0..<units.unitCount), section)
        }
    }
}
