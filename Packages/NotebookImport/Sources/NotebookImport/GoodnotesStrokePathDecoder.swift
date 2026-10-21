import CoreGraphics
import Foundation

/// Decodes a stroke's tpl image into its path, for the four layouts Goodnotes writes (`Docs/Goodnotes-format.md`,
/// Strokes). The values of each layout are read first, then their codes are interpreted; a layout that is not one of
/// the four keeps its format string, for the caller to report.
enum GoodnotesStrokePathDecoder {
    private static let constantWidthFormat = "vuA(v)A(S(uu))A(S(uuuu))vA(f)"
    private static let varyingWidthFormat = "vA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
    private static let olderVaryingWidthFormat = "vuA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
    private static let pencilFormat = "vuA(v)A(S(uuuuu))A(S(uuuuuuuuuuu))A(S(uu))A(v)A(S(uu))A(S(uuuu))A(u)"
    private static let startCode: UInt16 = 0
    private static let curveCode: UInt16 = 1
    private static let expectedConstantWidthVersion: UInt16 = 2
    private static let expectedConstantWidthFlag: UInt16 = 1
    private static let pencilStartValues = 5
    private static let pencilCurveValues = 11

    static func path(of image: TplImage, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesStrokePath {
        switch image.formatString {
        case constantWidthFormat:
            return .constantWidth(try constantWidthPath(try readValues(image, layout: .constantWidth), issues: &issues))
        case varyingWidthFormat:
            let values = try readValues(image, layout: .varyingWidth)
            return .varyingWidth(GoodnotesVaryingWidthPath(centerLine: try GoodnotesOutlineDecoder.centerLine(values),
                                                           outline: try GoodnotesOutlineDecoder.outline(values, isOlderLayout: false)))
        case olderVaryingWidthFormat:
            let values = try readValues(image, layout: .olderVaryingWidth)
            return .olderVaryingWidth(GoodnotesOlderVaryingWidthPath(width: float(values.widthBits),
                                                                     outline: try GoodnotesOutlineDecoder.outline(values, isOlderLayout: true)))
        case pencilFormat:
            return .pencil(try pencilPath(try readValues(image, layout: .pencil), issues: &issues))
        default:
            return .unknownLayout(formatString: image.formatString)
        }
    }

    /// The values of one image, in the order of its layout; arrays of structures are flattened.
    struct LayoutValues {
        var version: UInt16 = 0
        var widthBits: UInt32 = 0
        var codes: [UInt16] = []
        var starts: [UInt32] = []
        var curves: [UInt32] = []
        var flag: UInt16 = 0
        var dashPattern: [UInt64] = []
        var outlineCodes: [UInt16] = []
        var outlineStarts: [UInt32] = []
        var outlinePoints: [UInt32] = []
        var capRecords: [UInt32] = []
        var hasTrailingValues = false
    }

    private enum Layout { case constantWidth, varyingWidth, olderVaryingWidth, pencil }

    private static func readValues(_ image: TplImage, layout: Layout) throws(GoodnotesReadingError) -> LayoutValues {
        var cursor = image.valueCursor()
        var values = LayoutValues()
        do throws(TplImageError) {
            values.version = try cursor.uint16()
            switch layout {
            case .constantWidth:
                values.widthBits = try cursor.uint32()
                values.codes = try cursor.uint16Array()
                values.starts = try cursor.uint32Array(valuesPerElement: 2)
                values.curves = try cursor.uint32Array(valuesPerElement: 4)
                values.flag = try cursor.uint16()
                values.dashPattern = try cursor.uint64Array()
            case .varyingWidth, .olderVaryingWidth:
                if layout == .olderVaryingWidth { values.widthBits = try cursor.uint32() }
                try readVaryingWidthArrays(&cursor, into: &values)
            case .pencil:
                values.widthBits = try cursor.uint32()
                values.codes = try cursor.uint16Array()
                values.starts = try cursor.uint32Array(valuesPerElement: pencilStartValues)
                values.curves = try cursor.uint32Array(valuesPerElement: pencilCurveValues)
                values.hasTrailingValues = try readPencilTrailingArraysHoldValues(&cursor)
            }
            try cursor.finish()
        } catch {
            throw .tplImage(error)
        }
        return values
    }

    /// Center-line codes, start and curves, then the outline: commands per segment (unused), codes, starts, an
    /// array that is empty in every sample, points, cap records and one value per cap record (unused).
    private static func readVaryingWidthArrays(_ cursor: inout TplValueCursor, into values: inout LayoutValues) throws(TplImageError) {
        values.codes = try cursor.uint16Array()
        values.starts = try cursor.uint32Array(valuesPerElement: 1)
        values.curves = try cursor.uint32Array(valuesPerElement: 1)
        _ = try cursor.uint16Array()
        values.outlineCodes = try cursor.uint16Array()
        values.outlineStarts = try cursor.uint32Array(valuesPerElement: 1)
        _ = try cursor.uint32Array(valuesPerElement: 1)
        values.outlinePoints = try cursor.uint32Array(valuesPerElement: 1)
        values.capRecords = try cursor.uint32Array(valuesPerElement: 1)
        _ = try cursor.uint16Array()
    }

    /// The five arrays after a pencil path's curves, empty in every sample.
    private static func readPencilTrailingArraysHoldValues(_ cursor: inout TplValueCursor) throws(TplImageError) -> Bool {
        let counts = [try cursor.uint32Array(valuesPerElement: 2).count, try cursor.uint16Array().count,
                      try cursor.uint32Array(valuesPerElement: 2).count, try cursor.uint32Array(valuesPerElement: 4).count,
                      try cursor.uint32Array(valuesPerElement: 1).count]
        return counts.contains { count in count > 0 }
    }

    private static func constantWidthPath(_ values: LayoutValues,
                                          issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesConstantWidthPath {
        if values.version != expectedConstantWidthVersion || values.flag != expectedConstantWidthFlag {
            issues.report(.strokePathHeaderNotKnown(version: values.version, flag: values.flag))
        }
        let subpaths = try subpaths(codes: values.codes, startCount: values.starts.count / 2, curveCount: values.curves.count / 4) {
            startIndex in point(values.starts, at: 2 * startIndex)
        } curve: { curveIndex in
            GoodnotesQuadraticCurve(control: point(values.curves, at: 4 * curveIndex), end: point(values.curves, at: 4 * curveIndex + 2))
        }
        // Each dash value is a 32-bit float in the low half of a tpl double.
        let dashPattern = values.dashPattern.map { bits in Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits))) }
        return GoodnotesConstantWidthPath(width: float(values.widthBits), subpaths: subpaths.map { subpath in
            GoodnotesSubpath(start: subpath.start, curves: subpath.curves)
        }, dashPattern: dashPattern)
    }

    private static func pencilPath(_ values: LayoutValues, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesPencilPath {
        if values.hasTrailingValues { issues.report(.pencilPathTrailingArrayNotEmpty) }
        let subpaths = try subpaths(codes: values.codes, startCount: values.starts.count / pencilStartValues,
                                    curveCount: values.curves.count / pencilCurveValues) { startIndex in
            pencilSample(values.starts, at: pencilStartValues * startIndex)
        } curve: { curveIndex in
            let curveStart = pencilCurveValues * curveIndex
            return GoodnotesPencilCurve(control: pencilSample(values.curves, at: curveStart + 1), end: pencilSample(values.curves, at: curveStart + 6),
                                        leadingValue: values.curves[curveStart])
        }
        return GoodnotesPencilPath(width: float(values.widthBits), subpaths: subpaths.map { subpath in
            GoodnotesPencilSubpath(start: subpath.start, curves: subpath.curves)
        })
    }

    /// Splits a path's codes into subpaths: 0 starts a subpath with the next start, 1 adds the next curve to the
    /// current one. A code with no start or curve left for it, or a curve before any start, fails.
    private static func subpaths<Start, Curve>(codes: [UInt16], startCount: Int, curveCount: Int, start: (Int) -> Start,
                                               curve: (Int) -> Curve) throws(GoodnotesReadingError) -> [(start: Start, curves: [Curve])] {
        var subpaths: [(start: Start, curves: [Curve])] = []
        var startIndex = 0, curveIndex = 0
        for code in codes {
            if code == startCode && startIndex < startCount {
                subpaths.append((start(startIndex), []))
                startIndex += 1
            } else if code == curveCode && !subpaths.isEmpty && curveIndex < curveCount {
                subpaths[subpaths.count - 1].curves.append(curve(curveIndex))
                curveIndex += 1
            } else {
                throw .pathCodeOutOfPlace(code: code)
            }
        }
        return subpaths
    }

    /// x, y, then the Apple Pencil's azimuth, altitude and force.
    private static func pencilSample(_ values: [UInt32], at offset: Int) -> GoodnotesPencilSample {
        GoodnotesPencilSample(point: point(values, at: offset), azimuthRadians: float(values[offset + 2]),
                              altitudeRadians: float(values[offset + 3]), force: float(values[offset + 4]))
    }

    /// Two consecutive values as a point; callers index only within the counts they checked.
    static func point(_ values: [UInt32], at offset: Int) -> CGPoint {
        CGPoint(x: float(values[offset]), y: float(values[offset + 1]))
    }

    /// The 32-bit float whose bits a tpl `u` holds.
    static func float(_ bits: UInt32) -> Double { Double(Float(bitPattern: bits)) }
}
