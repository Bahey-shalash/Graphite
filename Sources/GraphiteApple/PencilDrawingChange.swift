#if canImport(UIKit)
import Foundation
import PencilKit

/// One change to a page's drawing, kept as the strokes it removed and added with their
/// places in the drawing, so the change can be undone and redone without keeping whole
/// drawings. A step of a PDF's undo history holds one; its memory grows with the strokes
/// the change touched, not with the page.
///
/// Strokes are told apart by `PDFStrokeFingerprint`, so a stroke the lasso moved or
/// recolored, or the pixel eraser cut, counts as removed and added again. When the strokes
/// the change kept stay in their order, only the strokes that differ are stored;
/// otherwise the run between the unchanged first and last strokes is stored whole.
public struct PencilDrawingChange {
    struct PlacedStroke {
        let index: Int
        let stroke: PKStroke
        let fingerprint: PDFStrokeFingerprint
    }

    /// Positions in the drawing before the change, ascending.
    let removedStrokes: [PlacedStroke]
    /// Positions in the drawing after the change, ascending.
    let addedStrokes: [PlacedStroke]
    public let strokeCountBefore: Int
    public let strokeCountAfter: Int

    /// Nil when the two drawings show the same strokes in the same order.
    public init?(from drawingBefore: PKDrawing, to drawingAfter: PKDrawing) {
        let strokesBefore = drawingBefore.strokes
        let strokesAfter = drawingAfter.strokes
        let fingerprintsBefore = strokesBefore.map(PDFStrokeFingerprint.init(stroke:))
        let fingerprintsAfter = strokesAfter.map(PDFStrokeFingerprint.init(stroke:))
        var removedPositions: [Int]
        var addedPositions: [Int]
        if let (unmatchedBefore, unmatchedAfter) = Self.unmatchedPositionsKeepingOrder(fingerprintsBefore, fingerprintsAfter) {
            removedPositions = unmatchedBefore
            addedPositions = unmatchedAfter
        } else {
            let commonPrefixLength = zip(fingerprintsBefore, fingerprintsAfter).prefix { pair in pair.0 == pair.1 }.count
            let longestSuffix = min(fingerprintsBefore.count, fingerprintsAfter.count) - commonPrefixLength
            let commonSuffixLength = zip(fingerprintsBefore.reversed(), fingerprintsAfter.reversed()).prefix(longestSuffix).prefix { pair in pair.0 == pair.1 }.count
            removedPositions = Array(commonPrefixLength..<(fingerprintsBefore.count - commonSuffixLength))
            addedPositions = Array(commonPrefixLength..<(fingerprintsAfter.count - commonSuffixLength))
        }
        guard !removedPositions.isEmpty || !addedPositions.isEmpty else { return nil }
        removedStrokes = removedPositions.map { index in PlacedStroke(index: index, stroke: strokesBefore[index], fingerprint: fingerprintsBefore[index]) }
        addedStrokes = addedPositions.map { index in PlacedStroke(index: index, stroke: strokesAfter[index], fingerprint: fingerprintsAfter[index]) }
        strokeCountBefore = strokesBefore.count
        strokeCountAfter = strokesAfter.count
    }

    /// How many strokes the change removed and added together.
    public var changedStrokeCount: Int { removedStrokes.count + addedStrokes.count }

    /// The position of the one stroke the change added after all the others, as when a
    /// stroke has just been drawn; nil for any other change.
    public var appendedStrokeIndex: Int? {
        guard removedStrokes.isEmpty, addedStrokes.count == 1, let added = addedStrokes.first,
              added.index == strokeCountAfter - 1 else { return nil }
        return added.index
    }

    /// The drawing as it was before the change, from the drawing the change produced; nil
    /// when `drawing` is not that drawing, as after a change the history did not record.
    public func reverting(_ drawing: PKDrawing) -> PKDrawing? {
        Self.replacing(addedStrokes, with: removedStrokes, in: drawing, expectedStrokeCount: strokeCountAfter)
    }

    /// The drawing after the change, from the drawing before it; nil when `drawing` is
    /// not that drawing.
    public func reapplying(to drawing: PKDrawing) -> PKDrawing? {
        Self.replacing(removedStrokes, with: addedStrokes, in: drawing, expectedStrokeCount: strokeCountBefore)
    }

    private static func replacing(_ outgoingStrokes: [PlacedStroke], with incomingStrokes: [PlacedStroke], in drawing: PKDrawing,
                                  expectedStrokeCount: Int) -> PKDrawing? {
        var strokes = drawing.strokes
        guard strokes.count == expectedStrokeCount else { return nil }
        for placed in outgoingStrokes {
            guard placed.index < strokes.count, PDFStrokeFingerprint(stroke: strokes[placed.index]) == placed.fingerprint else { return nil }
        }
        for placed in outgoingStrokes.reversed() { strokes.remove(at: placed.index) }
        // Ascending: each stroke's position counts the strokes before it once those are back.
        for placed in incomingStrokes {
            guard placed.index <= strokes.count else { return nil }
            strokes.insert(redrawn(placed.stroke), at: placed.index)
        }
        return PKDrawing(strokes: strokes)
    }

    /// The same stroke as a new one. PencilKit tells strokes apart by an identity of their
    /// own, and a canvas keeps showing the version it already shows: a stroke the lasso
    /// moved is the same stroke to PencilKit, so putting the earlier one back left the
    /// canvas unchanged. A stroke built from its parts is a new stroke that looks the same.
    private static func redrawn(_ stroke: PKStroke) -> PKStroke {
        PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }

    /// Matches equal strokes of the two drawings, earliest first. Returns the positions
    /// left unmatched on each side, or nil when the matched strokes changed order, which
    /// removing and inserting single strokes could not reproduce.
    private static func unmatchedPositionsKeepingOrder(_ fingerprintsBefore: [PDFStrokeFingerprint],
                                                       _ fingerprintsAfter: [PDFStrokeFingerprint]) -> (before: [Int], after: [Int])? {
        var positionsBeforeByFingerprint: [PDFStrokeFingerprint: [Int]] = [:]
        for (index, fingerprint) in fingerprintsBefore.enumerated() { positionsBeforeByFingerprint[fingerprint, default: []].append(index) }
        var nextCandidateByFingerprint: [PDFStrokeFingerprint: Int] = [:]
        var isMatchedBefore = [Bool](repeating: false, count: fingerprintsBefore.count)
        var unmatchedAfter: [Int] = []
        var lastMatchedPositionBefore = -1
        for (indexAfter, fingerprint) in fingerprintsAfter.enumerated() {
            let nextCandidate = nextCandidateByFingerprint[fingerprint, default: 0]
            guard let candidates = positionsBeforeByFingerprint[fingerprint], nextCandidate < candidates.count else {
                unmatchedAfter.append(indexAfter)
                continue
            }
            let positionBefore = candidates[nextCandidate]
            nextCandidateByFingerprint[fingerprint] = nextCandidate + 1
            guard positionBefore > lastMatchedPositionBefore else { return nil }
            lastMatchedPositionBefore = positionBefore
            isMatchedBefore[positionBefore] = true
        }
        let unmatchedBefore = isMatchedBefore.indices.filter { index in !isMatchedBefore[index] }
        return (unmatchedBefore, unmatchedAfter)
    }
}
#endif
