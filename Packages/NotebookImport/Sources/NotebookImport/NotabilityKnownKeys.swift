import Foundation

/// The keys of each part of a note that the format description accounts for; any other key is reported as
/// `NotabilityReadingIssue.unknownKey`. They are the reference reader's lists, without its `$cls` (an archived
/// object's `$class` is never one of its keys here). Each set is built once from the cases of the part's key enum,
/// so a key a reader reads is always one of them.
enum NotabilityKnownKeys {
    static let session = NotabilitySessionKey.knownKeys
    static let richText = NotabilityRichTextKey.knownKeys
    static let picture = NotabilityPictureKey.knownKeys
    static let textAttributes = NotabilityTextAttributeKey.knownKeys
    static let shape = NotabilityShapeKey.knownKeys
    static let pageLayout = NotabilityPageLayoutKey.knownKeys
    /// The ink's own keys and the keys of its packed arrays.
    static let ink = NotabilityInkKey.knownKeys.union(NotabilityPackedArray.allCases.filter(\.isStoredInInk).map(\.rawValue))
}

extension NotabilityPackedArray {
    /// Whether the array is stored in the ink (the curves and their knots) rather than in the playback event manager.
    var isStoredInInk: Bool {
        switch self {
        case .curvePointCounts, .curvePoints, .curveWidths, .curveColors, .curveStyles, .curveUUIDs, .knotWidthFactors, .knotForces,
             .knotAltitudeAngles, .knotAzimuthUnitVectors: true
        case .eventCurveUUIDs, .eventTimestamps, .eventRecordingIdentifiers, .eventDurations: false
        }
    }
}
