/**
 * File: NotePageFlow.swift
 * ------------------------
 * Layer: Core
 * Description: Lays a note's blocks out on pages for a PDF: page breaks between blocks, a heading kept with what
 *              follows it, a list, table, code block or callout divided between its items, and a block taller than
 *              a page cut only where no line is, or scaled to fit for a picture.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation

/// Decides where each block of a note goes on the pages of a PDF. It measures nothing
/// itself: heights and the places a block may be cut come from `Measurements`, so the
/// decisions are tested with plain numbers.
public enum NotePageFlow {
    /// One block of the note, in reading order.
    public struct Block: Equatable, Sendable {
        /// Items the block can be divided between (a list's items, a table's rows, a code
        /// block's lines, a callout's blocks); 1 for a block that is never divided.
        public let unitCount: Int
        /// The room above the block when something is above it on its page.
        public let spacingBefore: Double
        /// A heading, which never ends a page.
        public let keepsWithNext: Bool
        /// A picture, which is scaled down to fit a page rather than cut.
        public let scalesToFit: Bool

        public init(unitCount: Int = 1, spacingBefore: Double, keepsWithNext: Bool = false, scalesToFit: Bool = false) {
            self.unitCount = max(1, unitCount)
            self.spacingBefore = spacingBefore
            self.keepsWithNext = keepsWithNext
            self.scalesToFit = scalesToFit
        }
    }

    /// What the flow asks of the drawn blocks; drawing a block to measure it may take turns
    /// of the main actor, so the answers are awaited.
    public struct Measurements {
        /// The height of a block drawn with only `units` of its items.
        public let height: (_ blockIndex: Int, _ units: Range<Int>) async -> Double
        /// Offsets from the top of a block drawn with `units`, at which it can be cut
        /// without cutting through a line of text, in increasing order.
        public let cutOffsets: (_ blockIndex: Int, _ units: Range<Int>) async -> [Double]

        public init(height: @escaping (_ blockIndex: Int, _ units: Range<Int>) async -> Double,
                    cutOffsets: @escaping (_ blockIndex: Int, _ units: Range<Int>) async -> [Double]) {
            self.height = height
            self.cutOffsets = cutOffsets
        }
    }

    /// A block, or part of one, on a page: the block drawn with `units`, of which the band
    /// from `sliceTop` to `sliceBottom` shows, scaled by `scale`, `top` below the top of
    /// the page's text.
    public struct Placement: Equatable, Sendable {
        public let blockIndex: Int
        public let units: Range<Int>
        public let sliceTop: Double
        public let sliceBottom: Double
        public let scale: Double
        public let pageIndex: Int
        public let top: Double

        public var height: Double { (sliceBottom - sliceTop) * scale }
    }

    /// Where every block goes, page by page. It runs on the caller's actor, where the
    /// measurements draw the blocks (`nonisolated(nonsending)`).
    /// - Parameter pageHeight: The height of a page's text, in the units of the measurements.
    nonisolated(nonsending) public static func placements(of blocks: [Block], pageHeight: Double, measurements: Measurements) async -> [Placement] {
        guard pageHeight > 0 else { return [] }
        var flow = Flow(blocks: blocks, pageHeight: pageHeight, measurements: measurements)
        for blockIndex in blocks.indices { await flow.place(blockIndex) }
        return flow.placements
    }

    /// The flow's state while it places blocks: the page being filled and how far down it is.
    private struct Flow {
        let blocks: [Block]
        let pageHeight: Double
        let measurements: Measurements
        var placements: [Placement] = []
        var pageIndex = 0
        /// How far down the current page's text is filled; 0 on an empty page.
        var filledHeight: Double = 0

        var isPageEmpty: Bool { filledHeight == 0 }
        var availableHeight: Double { pageHeight - filledHeight }

        mutating func startNewPage() {
            pageIndex += 1
            filledHeight = 0
        }

        mutating func append(_ blockIndex: Int, units: Range<Int>, sliceTop: Double, sliceBottom: Double, scale: Double = 1) {
            let spacing = isPageEmpty ? 0 : blocks[blockIndex].spacingBefore
            let placement = Placement(blockIndex: blockIndex, units: units, sliceTop: sliceTop, sliceBottom: sliceBottom, scale: scale,
                                      pageIndex: pageIndex, top: filledHeight + spacing)
            placements.append(placement)
            filledHeight = placement.top + placement.height
        }

        /// What is left of a block to place: its parts from `firstUnit`, the first of them
        /// already shown down to `shownOffset` when it was cut.
        struct Remainder {
            var firstUnit = 0
            var shownOffset: Double = 0
        }

        /// Places one block, over as many pages as it needs.
        nonisolated(nonsending) mutating func place(_ blockIndex: Int) async {
            var remainder = Remainder()
            while remainder.firstUnit < blocks[blockIndex].unitCount {
                guard let next = await placeWhatFits(of: blockIndex, remainder) else { return }
                remainder = next
            }
        }

        /// Places as much of the rest of the block as the page takes; nil once it is all placed.
        nonisolated(nonsending) mutating func placeWhatFits(of blockIndex: Int, _ remainder: Remainder) async -> Remainder? {
            let block = blocks[blockIndex]
            let remainingUnits = remainder.firstUnit..<block.unitCount
            let spacing = isPageEmpty ? 0 : block.spacingBefore
            let remainingHeight = await measurements.height(blockIndex, remainingUnits)
            if block.keepsWithNext, !isPageEmpty, remainder.firstUnit == 0,
               spacing + remainingHeight + (await leadingHeight(after: blockIndex)) > availableHeight {
                startNewPage()
                return remainder
            }
            if spacing + remainingHeight - remainder.shownOffset <= availableHeight {
                append(blockIndex, units: remainingUnits, sliceTop: remainder.shownOffset, sliceBottom: remainingHeight)
                return nil
            }
            if block.scalesToFit, block.unitCount == 1 {
                placeScaled(blockIndex, height: remainingHeight)
                return nil
            }
            if remainder.shownOffset == 0, remainingUnits.count > 1 {
                let fittingCount = await largestFittingUnitCount(blockIndex, from: remainder.firstUnit, availableHeight: availableHeight - spacing)
                if fittingCount > 0 {
                    let fittingUnits = remainder.firstUnit..<(remainder.firstUnit + fittingCount)
                    append(blockIndex, units: fittingUnits, sliceTop: 0, sliceBottom: await measurements.height(blockIndex, fittingUnits))
                    startNewPage()
                    return Remainder(firstUnit: fittingUnits.upperBound)
                }
            }
            guard isPageEmpty else {
                startNewPage()
                return remainder
            }
            return await placeUnitAloneOnPage(of: blockIndex, remainder)
        }

        /// Alone on a page, the next part is still taller than the page: it is cut where no
        /// line is, as low on the page as it can be.
        nonisolated(nonsending) mutating func placeUnitAloneOnPage(of blockIndex: Int, _ remainder: Remainder) async -> Remainder {
            let unit = remainder.firstUnit..<(remainder.firstUnit + 1)
            let unitHeight = await measurements.height(blockIndex, unit)
            if unitHeight - remainder.shownOffset <= pageHeight {
                append(blockIndex, units: unit, sliceTop: remainder.shownOffset, sliceBottom: unitHeight)
                return Remainder(firstUnit: unit.upperBound)
            }
            let lowestCut = await measurements.cutOffsets(blockIndex, unit).last { offset in
                offset > remainder.shownOffset && offset <= remainder.shownOffset + pageHeight
            }
            // With no place free of text, the page is filled: a line is cut only then.
            let cut = lowestCut ?? remainder.shownOffset + pageHeight
            append(blockIndex, units: unit, sliceTop: remainder.shownOffset, sliceBottom: cut)
            startNewPage()
            return Remainder(firstUnit: remainder.firstUnit, shownOffset: cut)
        }

        /// A picture taller than the room left: on a page of its own, scaled down if it is
        /// taller than a page.
        mutating func placeScaled(_ blockIndex: Int, height: Double) {
            if !isPageEmpty { startNewPage() }
            let scale = height > pageHeight ? pageHeight / height : 1
            append(blockIndex, units: 0..<1, sliceTop: 0, sliceBottom: height, scale: scale)
        }

        /// The most items of the block, from `firstUnit`, that fit in `availableHeight`;
        /// heights grow with the number of items, so it is found by halving.
        nonisolated(nonsending) func largestFittingUnitCount(_ blockIndex: Int, from firstUnit: Int, availableHeight: Double) async -> Int {
            var fitting = 0
            var notFitting = blocks[blockIndex].unitCount - firstUnit
            while notFitting - fitting > 1 {
                let candidate = (fitting + notFitting) / 2
                if await measurements.height(blockIndex, firstUnit..<(firstUnit + candidate)) <= availableHeight {
                    fitting = candidate
                } else {
                    notFitting = candidate
                }
            }
            return fitting
        }

        /// The room what follows a heading needs on the heading's page: its spacing and the
        /// first part of the next block that cannot be divided (its first item, its first
        /// lines, or all of it), with the next heading's own followers; never more than a page.
        nonisolated(nonsending) func leadingHeight(after blockIndex: Int) async -> Double {
            let nextIndex = blockIndex + 1
            guard blocks.indices.contains(nextIndex) else { return 0 }
            let next = blocks[nextIndex]
            let firstUnit = 0..<1
            var leading = await measurements.height(nextIndex, firstUnit)
            if leading > pageHeight, next.unitCount == 1, !next.scalesToFit {
                leading = await measurements.cutOffsets(nextIndex, firstUnit).first ?? pageHeight
            }
            if next.keepsWithNext { leading += await leadingHeight(after: nextIndex) }
            return min(next.spacingBefore + leading, pageHeight)
        }
    }
}
