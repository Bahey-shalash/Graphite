/**
 * File: PrintedLineGapsTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The gaps between lines found in a picture of a block, where a page may cut it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteCore

final class PrintedLineGapsTests: XCTestCase {
    func testAGapIsABandOfRowsThatRepeatTheRowAbove() {
        // Rows 0–3 a line, 4–9 the same row six times, 10–13 a line, 14–15 a band too short.
        var repeats = Array(repeating: false, count: 18)
        for row in 5...9 { repeats[row] = true }
        repeats[15] = true
        XCTAssertEqual(PrintedLineGaps.cutOffsets(rowRepeatsPrevious: repeats, pixelsPerPoint: 2), [3.5], "The middle of rows 4 to 9, at 2 pixels per point.")
    }

    func testAPictureOfTwoLinesHasItsGapBetweenThem() throws {
        let width = 40, height = 40
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Two "lines" of text, drawn as rows of glyph-like marks that change from row to row.
        for (top, bottom) in [(4, 14), (26, 36)] {
            for row in top..<bottom { context.fill(CGRect(x: row % 7, y: height - row - 1, width: 3 + row % 5, height: 1)) }
        }
        let picture = try XCTUnwrap(context.makeImage())
        let offsets = PrintedLineGaps.cutOffsets(in: picture, pixelsPerPoint: 1)
        XCTAssertTrue(offsets.contains { offset in offset > 14 && offset < 26 }, "A cut between the lines: \(offsets)")
        XCTAssertFalse(offsets.contains { offset in (4...14).contains(offset) || (26...36).contains(offset) }, "No cut inside a line: \(offsets)")
    }
}
