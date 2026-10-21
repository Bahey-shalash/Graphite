/**
 * File: NotePDFOptionsTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The page geometry of the Export to PDF options, and the options' stored format.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import XCTest
@testable import GraphiteCore

final class NotePDFOptionsTests: XCTestCase {
    func testDefaultsAreObsidiansA4PortraitWithTheFileNameAsTitle() {
        let options = NotePDFOptions()
        XCTAssertEqual(options.pagePointSize.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(options.pagePointSize.height, 841.89, accuracy: 0.01)
        XCTAssertTrue(options.includesFileNameAsTitle)
        XCTAssertFalse(options.includesProperties)
        XCTAssertEqual(options.downscalePercent, 100)
    }

    func testTheNoteIsLaidOutWiderThanThePaperAndScaledToPrintSize() {
        var options = NotePDFOptions()
        XCTAssertEqual(options.layoutScale, 0.75)
        XCTAssertEqual(options.layoutWidth * options.layoutScale, options.contentRect.width, accuracy: 0.001)
        options.downscalePercent = 50
        XCTAssertEqual(options.layoutScale, 0.375)
        options.downscalePercent = 10
        XCTAssertEqual(options.layoutScale, 0.375, "Below the range counts as its lowest value.")
    }

    func testLandscapeTurnsThePageAndMarginsInsetIt() {
        var options = NotePDFOptions()
        options.pageSize = .legal
        options.orientation = .landscape
        options.margins = .none
        XCTAssertEqual(options.pagePointSize, CGSize(width: 1008, height: 612))
        XCTAssertEqual(options.contentRect, CGRect(x: 0, y: 0, width: 1008, height: 612))
        options.margins = .standard
        XCTAssertEqual(options.contentRect, CGRect(x: 54, y: 54, width: 900, height: 504))
    }

    func testStoredOptionsKeepTheirFormat() throws {
        var options = NotePDFOptions()
        options.pageSize = .letter
        options.margins = .small
        let stored = String(decoding: try JSONEncoder.sortedKeys.encode(options), as: UTF8.self)
        XCTAssertEqual(stored, #"{"downscalePercent":100,"includesFileNameAsTitle":true,"includesProperties":false,"#
                       + #""margins":"small","orientation":"portrait","pageSize":"letter"}"#)
    }

    func testOptionsStoredWithoutALaterChoiceTakeItsDefault() throws {
        let decoded = try JSONDecoder().decode(NotePDFOptions.self, from: Data(#"{"pageSize":"a3","margins":"none"}"#.utf8))
        XCTAssertEqual(decoded.pageSize, .a3)
        XCTAssertEqual(decoded.margins, NotePDFMargins.none)
        XCTAssertTrue(decoded.includesFileNameAsTitle)
        XCTAssertEqual(decoded.downscalePercent, 100)
    }
}

private extension JSONEncoder {
    static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
