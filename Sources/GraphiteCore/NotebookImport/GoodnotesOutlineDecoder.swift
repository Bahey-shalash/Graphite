import CoreGraphics
import Foundation

/// Interprets the arrays of a varying-width stroke: the center line with a width at each point, and the outline
/// Goodnotes fills, one closed shape per center-line segment.
enum GoodnotesOutlineDecoder {
    private enum OutlineCommandKind { case move, cubic, arc, flatCap }

    private static let centerLineStartCodes: Set<UInt16> = [0, 4]
    private static let centerLineCurveCodes: Set<UInt16> = [1, 5]
    /// Tape adds values after these: one after the start, three after each curve.
    private static let centerLineStartValues = 3
    private static let centerLineCurveValues = 6
    private static let minimumCapRecordValues = 5
    private static let cubicValues = 6

    /// Nil when the path has no center-line codes (the older layout's codes are not interpreted).
    static func centerLine(_ values: GoodnotesStrokePathDecoder.LayoutValues) throws(GoodnotesReadingError) -> GoodnotesCenterLine? {
        guard let firstCode = values.codes.first else { return nil }
        guard centerLineStartCodes.contains(firstCode), values.codes.dropFirst().allSatisfy(centerLineCurveCodes.contains) else {
            throw .centerLineCodesNotKnown
        }
        let curveCount = values.codes.count - 1
        let valuesPerCurve = curveCount == 0 ? centerLineCurveValues : values.curves.count / curveCount
        guard values.starts.count >= centerLineStartValues, valuesPerCurve >= centerLineCurveValues,
              valuesPerCurve * curveCount == values.curves.count else { throw .centerLineValuesUneven }
        let curves = (0..<curveCount).map { curveIndex in
            GoodnotesWidthCurve(control: widthPoint(values.curves, at: curveIndex * valuesPerCurve),
                                end: widthPoint(values.curves, at: curveIndex * valuesPerCurve + 3))
        }
        return GoodnotesCenterLine(start: widthPoint(values.starts, at: 0), curves: curves)
    }

    /// The outline's commands, a new closed outline at each move. Codes are 0 move, 2 cubic, 3 arc and 6 flat cap;
    /// in the older layout 2 move and 4 cubic. Each arc and flat cap takes the next cap record.
    static func outline(_ values: GoodnotesStrokePathDecoder.LayoutValues, isOlderLayout: Bool) throws(GoodnotesReadingError) -> [[GoodnotesOutlineCommand]] {
        let kinds = values.outlineCodes.map { code in commandKind(code, isOlderLayout: isOlderLayout) }
        let recordCommandCount = kinds.filter { kind in kind == .arc || kind == .flatCap }.count
        let recordValues = recordCommandCount == 0 ? 0 : values.capRecords.count / recordCommandCount
        if recordCommandCount > 0 && (recordValues < minimumCapRecordValues || recordValues * recordCommandCount != values.capRecords.count) {
            throw .capRecordsUneven
        }
        var outline: [[GoodnotesOutlineCommand]] = []
        var startIndex = 0, pointIndex = 0, recordIndex = 0
        for (code, kind) in zip(values.outlineCodes, kinds) {
            switch kind {
            case .move?:
                guard 2 * startIndex + 2 <= values.outlineStarts.count else { throw .outlineValuesRunOut }
                outline.append([.move(to: GoodnotesStrokePathDecoder.point(values.outlineStarts, at: 2 * startIndex))])
                startIndex += 1
            case .cubic? where !outline.isEmpty:
                guard pointIndex + cubicValues <= values.outlinePoints.count else { throw .outlineValuesRunOut }
                outline[outline.count - 1].append(cubic(values.outlinePoints, at: pointIndex))
                pointIndex += cubicValues
            case .arc? where !outline.isEmpty, .flatCap? where !outline.isEmpty:
                let record = recordIndex * recordValues
                outline[outline.count - 1].append(kind == .arc ? arc(values.capRecords, at: record) : flatCap(values.capRecords, at: record))
                recordIndex += 1
            case .cubic?, .arc?, .flatCap?, nil:
                throw .outlineCodeOutOfPlace(code: code)
            }
        }
        return outline
    }

    private static func commandKind(_ code: UInt16, isOlderLayout: Bool) -> OutlineCommandKind? {
        switch (isOlderLayout, code) {
        case (false, 0), (true, 2): .move
        case (false, 2), (true, 4): .cubic
        case (false, 3): .arc
        case (false, 6): .flatCap
        default: nil
        }
    }

    private static func widthPoint(_ values: [UInt32], at offset: Int) -> GoodnotesWidthPoint {
        GoodnotesWidthPoint(point: GoodnotesStrokePathDecoder.point(values, at: offset), width: GoodnotesStrokePathDecoder.float(values[offset + 2]))
    }

    private static func cubic(_ values: [UInt32], at offset: Int) -> GoodnotesOutlineCommand {
        .cubic(control1: GoodnotesStrokePathDecoder.point(values, at: offset), control2: GoodnotesStrokePathDecoder.point(values, at: offset + 2),
               end: GoodnotesStrokePathDecoder.point(values, at: offset + 4))
    }

    /// Center x and y, radius, start and end angle.
    private static func arc(_ values: [UInt32], at offset: Int) -> GoodnotesOutlineCommand {
        .arc(center: GoodnotesStrokePathDecoder.point(values, at: offset), radius: GoodnotesStrokePathDecoder.float(values[offset + 2]),
             startAngleRadians: GoodnotesStrokePathDecoder.float(values[offset + 3]),
             endAngleRadians: GoodnotesStrokePathDecoder.float(values[offset + 4]))
    }

    /// Tape's record has seven values; the first two are the point the flat edge crosses.
    private static func flatCap(_ values: [UInt32], at offset: Int) -> GoodnotesOutlineCommand {
        .flatCap(through: GoodnotesStrokePathDecoder.point(values, at: offset))
    }
}
