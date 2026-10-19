import CoreGraphics
import Foundation

/// A note's curves (`InkedSpatialHash`) as the packed arrays of `Session.plist`, kept as slices of its bytes, and a
/// light index: where each curve's points and knots start and its vertical extent. Opening checks every array's
/// length against the counts the note stores; a curve is decoded into a value only when asked for.
struct NotabilityInk: Sendable {
    private struct CurveLocation: Sendable {
        let firstPointIndex: Int
        let pointCount: Int
        let firstKnotIndex: Int
        /// The extent of the curve's finite points; +∞ and −∞ when it has none.
        var lowestY = Double.infinity
        var highestY = -Double.infinity

        var knotCount: Int { (pointCount - 1) / 3 + 1 }
        var hasFinitePoint: Bool { lowestY <= highestY }
    }

    private struct Arrays: Sendable {
        let points: PackedLittleEndianValues
        let widths: PackedLittleEndianValues
        let colors: PackedLittleEndianValues
        let styles: PackedLittleEndianValues
        let uuids: PackedLittleEndianValues
        let widthFactors: PackedLittleEndianValues
        let forces: PackedLittleEndianValues
        let altitudeAngles: PackedLittleEndianValues?
        let azimuthUnitVectors: PackedLittleEndianValues?
    }

    private static let maximumColorComponent = 255.0

    let curveCount: Int
    private let locations: [CurveLocation]
    private let arrays: Arrays
    /// The curves with a finite point, sorted by their lowest y, and the tallest of their extents: the curves on a
    /// page are found by a binary search instead of a pass over every curve.
    private let curveIndicesByLowestY: [Int]
    private let tallestVerticalExtent: Double
    /// The largest y of any curve's finite points; nil when no curve has one.
    let highestY: Double?

    init(fields: KeyedArchiveFields, archive: KeyedArchive, issues: inout NotabilityReadingIssues) throws(NotabilityReadingError) {
        let curveCount = try Self.count(named: "numcurves", in: fields, archive: archive)
        let pointCount = try Self.count(named: "numpoints", in: fields, archive: archive)
        let knotCount = try Self.count(named: "numfractionalwidths", in: fields, archive: archive)
        let pointCounts = try Self.packedValues(.curvePointCounts, entryCount: curveCount, in: fields, archive: archive)
        var locations = try Self.curveLocations(pointCounts: pointCounts, curveCount: Int(curveCount), declaredPointCount: pointCount,
                                                declaredKnotCount: knotCount)
        func required(_ array: NotabilityPackedArray, _ entryCount: Int64) throws(NotabilityReadingError) -> PackedLittleEndianValues {
            try Self.packedValues(array, entryCount: entryCount, in: fields, archive: archive)
        }
        let points = try required(.curvePoints, pointCount)
        let widths = try required(.curveWidths, curveCount)
        let colors = try required(.curveColors, curveCount)
        let styles = try required(.curveStyles, curveCount)
        let widthFactors = try required(.knotWidthFactors, knotCount)
        let forces = try required(.knotForces, knotCount)
        let uuids = try required(.curveUUIDs, curveCount)
        arrays = Arrays(points: points, widths: widths, colors: colors, styles: styles, uuids: uuids, widthFactors: widthFactors, forces: forces,
                        altitudeAngles: Self.knotValues(.knotAltitudeAngles, knotCount: knotCount, in: fields, archive: archive, issues: &issues),
                        azimuthUnitVectors: Self.knotValues(.knotAzimuthUnitVectors, knotCount: knotCount, in: fields, archive: archive,
                                                            issues: &issues))
        for curveIndex in locations.indices {
            Self.measureVerticalExtent(of: &locations[curveIndex], points: points)
            let style = NotabilityCurveStyle(rawStyle: styles.byte(at: curveIndex))
            if case .unknown(let rawStyle) = style { issues.report(.curveStyleUnknown(rawStyle: rawStyle)) }
        }
        self.curveCount = locations.count
        self.locations = locations
        let measuredCurveIndices = locations.indices.filter { curveIndex in locations[curveIndex].hasFinitePoint }
        curveIndicesByLowestY = measuredCurveIndices.sorted { leftIndex, rightIndex in
            (locations[leftIndex].lowestY, leftIndex) < (locations[rightIndex].lowestY, rightIndex)
        }
        tallestVerticalExtent = measuredCurveIndices.map { curveIndex in locations[curveIndex].highestY - locations[curveIndex].lowestY }.max() ?? 0
        highestY = measuredCurveIndices.map { curveIndex in locations[curveIndex].highestY }.max()
    }

    /// The curve at an index the caller checked against `curveCount`.
    func curve(at curveIndex: Int) -> NotabilityCurve {
        let location = locations[curveIndex]
        let points = (location.firstPointIndex..<(location.firstPointIndex + location.pointCount)).map { pointIndex in
            CGPoint(x: arrays.points.float(at: 2 * pointIndex), y: arrays.points.float(at: 2 * pointIndex + 1))
        }
        let knots = (location.firstKnotIndex..<(location.firstKnotIndex + location.knotCount)).map { knotIndex in
            NotabilityKnot(widthFactor: arrays.widthFactors.float(at: knotIndex), force: arrays.forces.float(at: knotIndex),
                           altitudeAngle: arrays.altitudeAngles?.float(at: knotIndex),
                           azimuthUnitVector: arrays.azimuthUnitVectors.map { vectors in
                               NotabilityAzimuthVector(horizontal: vectors.float(at: 2 * knotIndex), vertical: vectors.float(at: 2 * knotIndex + 1))
                           })
        }
        let colorComponents = (0..<4).map { component in Double(arrays.colors.byte(at: 4 * curveIndex + component)) / Self.maximumColorComponent }
        return NotabilityCurve(index: curveIndex, uuid: arrays.uuids.uuid(at: curveIndex),
                               style: NotabilityCurveStyle(rawStyle: arrays.styles.byte(at: curveIndex)), width: arrays.widths.float(at: curveIndex),
                               color: NotebookImportColor(red: colorComponents[0], green: colorComponents[1], blue: colorComponents[2],
                                                          alpha: colorComponents[3]),
                               points: points, knots: knots)
    }

    func isHighlighter(curveIndex: Int) -> Bool {
        NotabilityCurveStyle(rawStyle: arrays.styles.byte(at: curveIndex)) == .highlighter
    }

    /// Each curve's index by its UUID; when two curves share a UUID, the later one.
    func curveIndicesByUUID() -> [UUID: Int] {
        var indicesByUUID: [UUID: Int] = [:]
        for curveIndex in 0..<curveCount { indicesByUUID[arrays.uuids.uuid(at: curveIndex)] = curveIndex }
        return indicesByUUID
    }

    /// The curves, in drawing order, whose points' vertical extent touches the page: from the page of its lowest y
    /// to the page of its highest y.
    func curveIndices(onPage pageNumber: Int, geometry: NotabilityPageGeometry) -> [Int] {
        guard let pageHeight = geometry.pageHeightInUnits else { return [] }
        let page = Double(pageNumber)
        // One page of slack covers the rounding of the floor division that assigns a position to a page.
        let earliestLowestY = (page - 2) * pageHeight - tallestVerticalExtent
        var low = 0
        var high = curveIndicesByLowestY.count
        while low < high {
            let middle = (low + high) / 2
            if locations[curveIndicesByLowestY[middle]].lowestY < earliestLowestY { low = middle + 1 } else { high = middle }
        }
        var onPage: [Int] = []
        for curveIndex in curveIndicesByLowestY[low...] {
            let location = locations[curveIndex]
            guard let firstPage = geometry.pagePosition(ofVerticalPosition: location.lowestY), firstPage <= page else { break }
            if let lastPage = geometry.pagePosition(ofVerticalPosition: location.highestY), lastPage >= page { onPage.append(curveIndex) }
        }
        return onPage.sorted()
    }

    private static func count(named key: String, in fields: KeyedArchiveFields, archive: KeyedArchive) throws(NotabilityReadingError) -> Int64 {
        let count = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.integer(archive.requiredValue(named: key, in: fields))
        }
        guard count >= 0 else { throw .countNegative(key: key, count: count) }
        return count
    }

    static func packedValues(_ array: NotabilityPackedArray, entryCount: Int64, in fields: KeyedArchiveFields,
                             archive: KeyedArchive) throws(NotabilityReadingError) -> PackedLittleEndianValues {
        let bytes = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.data(archive.requiredValue(named: array.rawValue, in: fields))
        }
        let expectedByteCount = entryCount.multipliedReportingOverflow(by: Int64(array.entryByteCount))
        guard !expectedByteCount.overflow, Int64(bytes.count) == expectedByteCount.partialValue else {
            throw .packedArrayLengthWrong(array, byteCount: bytes.count, expectedValueCount: entryCount)
        }
        return PackedLittleEndianValues(bytes: bytes)
    }

    /// Where each curve's points and knots start, checked in the reference reader's order: the point counts add up
    /// to `numpoints`, each is 3k + 1, and the knots add up to `numfractionalwidths`.
    private static func curveLocations(pointCounts: PackedLittleEndianValues, curveCount: Int, declaredPointCount: Int64,
                                       declaredKnotCount: Int64) throws(NotabilityReadingError) -> [CurveLocation] {
        var locations: [CurveLocation] = []
        locations.reserveCapacity(curveCount)
        var nextPointIndex = 0
        var nextKnotIndex = 0
        var firstMalformedCurve: (curveIndex: Int, pointCount: Int)?
        for curveIndex in 0..<curveCount {
            let pointCount = Int(pointCounts.uint32(at: curveIndex))
            let location = CurveLocation(firstPointIndex: nextPointIndex, pointCount: pointCount, firstKnotIndex: nextKnotIndex)
            if pointCount % 3 != 1, firstMalformedCurve == nil { firstMalformedCurve = (curveIndex, pointCount) }
            nextPointIndex += pointCount
            nextKnotIndex += location.knotCount
            locations.append(location)
        }
        guard Int64(nextPointIndex) == declaredPointCount else {
            throw .curvePointCountsDisagree(sumOfCurvePointCounts: Int64(nextPointIndex), declaredPointCount: declaredPointCount)
        }
        if let firstMalformedCurve {
            throw .curvePointCountNotThreeKPlusOne(curveIndex: firstMalformedCurve.curveIndex, pointCount: firstMalformedCurve.pointCount)
        }
        guard Int64(nextKnotIndex) == declaredKnotCount else {
            throw .knotCountsDisagree(sumOfCurveKnotCounts: Int64(nextKnotIndex), declaredKnotCount: declaredKnotCount)
        }
        return locations
    }

    /// A per-knot Pencil array, when it is data of one entry per knot; otherwise none, reported unless it is absent.
    private static func knotValues(_ array: NotabilityPackedArray, knotCount: Int64, in fields: KeyedArchiveFields, archive: KeyedArchive,
                                   issues: inout NotabilityReadingIssues) -> PackedLittleEndianValues? {
        guard fields.reference(named: array.rawValue) != nil else { return nil }
        do throws(NotabilityReadingError) {
            return try packedValues(array, entryCount: knotCount, in: fields, archive: archive)
        } catch {
            if case .packedArrayLengthWrong(_, let byteCount, _) = error {
                issues.report(.perKnotArrayIgnored(array, byteCount: byteCount))
            } else {
                issues.report(.perKnotArrayIgnored(array, byteCount: nil))
            }
            return nil
        }
    }

    private static func measureVerticalExtent(of location: inout CurveLocation, points: PackedLittleEndianValues) {
        for pointIndex in location.firstPointIndex..<(location.firstPointIndex + location.pointCount) {
            let verticalPosition = points.float(at: 2 * pointIndex + 1)
            guard verticalPosition.isFinite else { continue }
            location.lowestY = min(location.lowestY, verticalPosition)
            location.highestY = max(location.highestY, verticalPosition)
        }
    }
}

extension NotabilityReadingError {
    /// A read of a value the note cannot be read without, its archive error wrapped as `session`.
    static func readingSession<Value>(_ read: () throws(KeyedArchiveError) -> Value) throws(NotabilityReadingError) -> Value {
        do throws(KeyedArchiveError) {
            return try read()
        } catch {
            throw .session(error)
        }
    }
}
