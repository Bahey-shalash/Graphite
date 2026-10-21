/**
 * File: PrintedLineGaps.swift
 * ---------------------------
 * Layer: Core
 * Description: Where a drawn block can be cut between two pages without cutting a line of text: the bands of a
 *              rendering in which every row of pixels is the same as the one above it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation
import CoreGraphics

/// Finds the gaps between lines in a rendering of a block. Between two lines of text, or
/// two rows of a table, a band of rows repeats the row above it (the page, a background, a
/// column's border); inside a line no two rows in a row are all alike for long.
public enum PrintedLineGaps {
    /// Rows a band must have, past its first row, to count as a gap; at two pixels per
    /// point, a gap of one and a half points.
    public static let minimumRepeatedRows = 3

    /// The offsets, in points from the top, of the middle of every gap, in increasing order.
    /// - Parameters:
    ///   - rowRepeatsPrevious: For each row of pixels from the top, whether it is the same
    ///     as the row above it; the first row's value is not used.
    ///   - pixelsPerPoint: Rows of pixels per point of the block.
    public static func cutOffsets(rowRepeatsPrevious: [Bool], pixelsPerPoint: Double) -> [Double] {
        guard pixelsPerPoint > 0 else { return [] }
        var offsets: [Double] = []
        var bandStart: Int?
        for (row, repeatsPrevious) in rowRepeatsPrevious.enumerated() {
            if row > 0, repeatsPrevious {
                if bandStart == nil { bandStart = row - 1 }
                continue
            }
            if let start = bandStart { appendGap(from: start, to: row, into: &offsets, pixelsPerPoint: pixelsPerPoint) }
            bandStart = nil
        }
        // A gap that runs to the bottom ends the block; cutting there leaves nothing below.
        return offsets
    }

    /// The gaps in a picture of a block, compared row by row in 8-bit RGBA; a picture that
    /// cannot be read has none.
    public static func cutOffsets(in picture: CGImage, pixelsPerPoint: Double) -> [Double] {
        guard let rowRepeats = rowRepeatsPrevious(in: picture) else { return [] }
        return cutOffsets(rowRepeatsPrevious: rowRepeats, pixelsPerPoint: pixelsPerPoint)
    }

    /// For each row of the picture from the top, whether its pixels are those of the row above.
    static func rowRepeatsPrevious(in picture: CGImage) -> [Bool]? {
        let width = picture.width, height = picture.height
        let bytesPerRow = width * 4
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }
        // A bitmap context's memory starts with the picture's top row.
        return pixels.withUnsafeBytes { buffer -> [Bool]? in
            guard let start = buffer.baseAddress else { return nil }
            return (0..<height).map { row in
                row > 0 && memcmp(start + row * bytesPerRow, start + (row - 1) * bytesPerRow, bytesPerRow) == 0
            }
        }
    }

    private static func appendGap(from startRow: Int, to endRow: Int, into offsets: inout [Double], pixelsPerPoint: Double) {
        guard endRow - startRow > minimumRepeatedRows else { return }
        offsets.append(Double(startRow + endRow) / 2 / pixelsPerPoint)
    }
}
