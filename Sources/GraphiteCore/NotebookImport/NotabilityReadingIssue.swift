import Foundation

/// Something a note holds that the reader does not know, or an element it skipped: reported, never guessed at.
/// `NotabilityNoteReader.issues` lists each issue once, in the order first met.
public enum NotabilityReadingIssue: Hashable, Sendable {
    case unknownKey(NotabilityKeyContext, key: String)
    /// `sessionFormatVersion` is not 9, the only format read so far; nil when it is absent or not an integer.
    case sessionFormatNotSupported(version: Int64?)
    /// The note stores no page width, and its reflow state is not `NBReflowStateReflowable`.
    case reflowStateUnknown(className: String?)
    case curveStyleUnknown(rawStyle: UInt8)
    case shapeKindUnknown(rawKind: String)
    /// A media object that is not an `ImageMediaObject`; it is still read as a picture when it can be.
    case mediaClassUnknown(className: String)
    case playbackEventWithoutCurve(curveUUID: UUID)
    /// The paper's size is absent (nil) or not one whose export size is known, so the page size is not known.
    case paperSizeUnknown(rawSize: String?)
    case pictureSkipped(mediaIndex: Int, NotabilityElementFailure)
    /// The `shapes` property list could not be read, so the note has no shapes.
    case shapesSkipped(NotabilityElementFailure)
    case shapeSkipped(shapeIndex: Int, NotabilityElementFailure)
    /// A per-knot Pencil array (altitude or azimuth) that is not data of one entry per knot, so knots have none;
    /// the byte count is nil when the value is not data.
    case perKnotArrayIgnored(NotabilityPackedArray, byteCount: Int?)
    case textRunColorNotReadable(runIndex: Int)
}

/// Where an unknown key was found.
public enum NotabilityKeyContext: Hashable, Sendable {
    /// The `NoteTakingSession` root.
    case session
    /// `richText`, the `FormattedString` of the page content.
    case richText
    /// The `InkedSpatialHash` that holds the curves.
    case ink
    case picture
    /// A text run's `subRangeOtherAttributesKey`.
    case textAttributes
    case shape
    /// An entry of `richText.pageLayoutArray`.
    case pageLayout
}

/// Why one picture or shape was skipped.
public enum NotabilityElementFailure: Error, Hashable, Sendable {
    case archive(KeyedArchiveError)
    case propertyList(PropertyListDocumentError)
    /// A value is absent, of another kind, or a geometry string without the numbers it needs.
    case valueNotReadable(key: String)
    /// The `shapes`, `kinds` and `indices` arrays differ in length.
    case shapeArraysDiffer(shapeCount: Int, kindCount: Int, indexCount: Int)
}

/// The issues of one read, each kept once in the order first reported.
struct NotabilityReadingIssues {
    private(set) var list: [NotabilityReadingIssue] = []
    private var reported: Set<NotabilityReadingIssue> = []

    mutating func report(_ issue: NotabilityReadingIssue) {
        if reported.insert(issue).inserted { list.append(issue) }
    }

    mutating func reportUnknownKeys(_ keys: [String], in context: NotabilityKeyContext, known knownKeys: Set<String>) {
        for key in keys where !knownKeys.contains(key) { report(.unknownKey(context, key: key)) }
    }
}
