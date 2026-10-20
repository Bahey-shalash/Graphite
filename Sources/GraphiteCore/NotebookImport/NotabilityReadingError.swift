import Foundation

/// Why a Notability note could not be read at all. Problems with one picture or shape are not errors: the element is
/// skipped and reported as a `NotabilityReadingIssue`.
public enum NotabilityReadingError: Error, Hashable, Sendable {
    case archive(ZipArchiveError)
    /// The archive does not hold exactly one top-level folder; the number it holds.
    case topLevelFolderCount(Int)
    /// `Session.plist` is not a keyed archive, or lacks a value the note cannot be read without.
    case session(KeyedArchiveError)
    /// A count the note stores (`numcurves`, `numpoints`, `numfractionalwidths`, a playback event count) is negative.
    case countNegative(key: String, count: Int64)
    /// A packed array whose length is not its value count times its value size.
    case packedArrayLengthWrong(NotabilityPackedArray, byteCount: Int, expectedValueCount: Int64)
    /// The curves' point counts do not add up to `numpoints`.
    case curvePointCountsDisagree(sumOfCurvePointCounts: Int64, declaredPointCount: Int64)
    case curvePointCountNotThreeKPlusOne(curveIndex: Int, pointCount: Int)
    /// The curves' knot counts do not add up to `numfractionalwidths`.
    case knotCountsDisagree(sumOfCurveKnotCounts: Int64, declaredKnotCount: Int64)
    /// A text run's `subRangeRangeKey` is not two whole numbers.
    case textRunRangeNotReadable(runIndex: Int)
    case textRunOutsideText(runIndex: Int, utf16Location: Int, utf16Length: Int, textUTF16Length: Int)
    case recordingsLibrary(PropertyListDocumentError)
    /// `Recordings/library.plist` has no `recordings` dictionary, or a recording that is not a dictionary.
    case recordingsLibraryLayoutNotRecognised
    case curveIndexOutOfRange(curveIndex: Int, curveCount: Int)
    case pageNumberOutOfRange(pageNumber: Int, pageCount: Int)
    /// The note's page height is not known (a reflowable note, or an unknown paper size), or its content lies
    /// beyond the pages an `Int` counts, so it has no pages to read.
    case pageCountUnknown
}

/// The packed little-endian arrays of a note, under the keys the note stores them by.
public enum NotabilityPackedArray: String, Sendable, Hashable, CaseIterable {
    case curvePointCounts = "curvesnumpoints"
    case curvePoints = "curvespoints"
    case curveWidths = "curveswidth"
    case curveColors = "curvescolors"
    case curveStyles = "curvesstyles"
    case curveUUIDs = "curveUUIDs"
    case knotWidthFactors = "curvesfractionalwidths"
    case knotForces = "curvesforces"
    case knotAltitudeAngles = "curvesaltitudeangles"
    case knotAzimuthUnitVectors = "curvesazimuthunitvector"
    case eventCurveUUIDs = "NBCPTimeManagerSOAEventUUIDsKey"
    case eventTimestamps = "NBCPTimeManagerSOATimestampsKey"
    case eventRecordingIdentifiers = "NBCPTimeManagerSOARecordingIDsKey"
    case eventDurations = "NBCPTimeManagerSOADurationsKey"

    /// The bytes of one entry: per curve, point, knot or event.
    var entryByteCount: Int {
        switch self {
        case .curveStyles: 1
        case .curvePointCounts, .curveWidths, .curveColors, .knotWidthFactors, .knotForces, .knotAltitudeAngles, .eventTimestamps,
             .eventRecordingIdentifiers, .eventDurations: 4
        case .curvePoints, .knotAzimuthUnitVectors: 8
        case .curveUUIDs, .eventCurveUUIDs: 16
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
