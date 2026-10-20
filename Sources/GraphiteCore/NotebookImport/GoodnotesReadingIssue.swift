import Foundation

/// Why a Goodnotes notebook, or a part of it, could not be read.
public enum GoodnotesReadingError: Error, Hashable, Sendable {
    case archive(ZipArchiveError)
    case protocolBuffer(ProtocolBufferError)
    case compressedPayload(AppleLZ4Error)
    case tplImage(TplImageError)
    /// The archive has no `schema.pb`: it is not a Goodnotes notebook.
    case notAGoodnotesNotebook
    /// The archive has a schema but no event log (`index.events.pb`), so its pages, paper and title cannot be known.
    case eventLogMissing
    case pageIndexOutOfRange(Int)
    /// The attachment names no safe file (see `GoodnotesReadingIssue.attachmentPathNotValid`).
    case attachmentFileNotValid(attachmentIdentifier: String)
    case emptyRecord
    /// An event record names an entity and has other than exactly one body.
    case eventBodyCount(Int)
    /// A stroke path code where its layout has no start or curve left for it, or before any start.
    case pathCodeOutOfPlace(code: UInt16)
    /// A varying-width center line whose codes are not a start followed by curves.
    case centerLineCodesNotKnown
    /// A varying-width center line whose values do not divide evenly into its curves.
    case centerLineValuesUneven
    /// Cap records that do not divide evenly into the outline's arcs and flat caps.
    case capRecordsUneven
    /// An outline code this layout does not have, or a drawing command before the outline's first move.
    case outlineCodeOutOfPlace(code: UInt16)
    /// The outline's starts or points run out before its commands do.
    case outlineValuesRunOut
}

/// Something in a notebook the reader does not know, or skipped: reported, never guessed. The cases up to
/// `elementMissingFromMemberList` mirror the "unknown" report of `scripts/goodnotes-reader.py`; the cases after it name
/// what the reader left out or skipped where the reference reader drops it silently or stops with an error.
public enum GoodnotesReadingIssue: Hashable, Sendable {
    case schemaVersionNotKnown(UInt64?)
    case eventKindNotKnown(Int)
    case elementHeaderFieldNotKnown(Int)
    /// An element of a kind this reader does not know; it is kept as `GoodnotesElementContent.unknown`.
    case elementKindNotKnown(kind: Int, elementIdentifier: String)
    case elementFieldNotKnown(elementKind: Int, fieldNumber: Int)
    /// A stroke whose path layout this reader does not know; it is kept with `GoodnotesStrokePath.unknownLayout`.
    case strokePathFormatNotKnown(formatString: String, elementIdentifier: String)
    /// A constant-width path whose leading version is not 2 or whose flag is not 1.
    case strokePathHeaderNotKnown(version: UInt16, flag: UInt16)
    case pencilPathTrailingArrayNotEmpty
    case shapeFieldNotKnown(Int)
    case bodyWithoutHeader(elementIdentifier: String)
    case elementMissingFromMemberList(elementIdentifier: String)
    /// The page identifier does not end in a hexadecimal byte, so its layer cannot be named.
    case layerIdentifierNotDerivable(pageIdentifier: String)
    /// An attachment whose file identifier is not one safe file name (empty, absolute, or climbing with `..`); its file
    /// is not used.
    case attachmentPathNotValid(attachmentIdentifier: String)
    /// A picture, paper or recording names an attachment the event log does not have; its file is not known.
    case attachmentNotInLog(attachmentIdentifier: String)
    /// A page names a paper the event log does not have; its size and background are not known.
    case paperNotInLog(pageIdentifier: String)
    /// A page whose position register holds no bytes, so it has no place in the order; it is left out.
    case pagePositionNotReadable(pageIdentifier: String)
    /// An event record that could not be read; the rest of the log was read.
    case eventSkipped(GoodnotesReadingError)
    /// The log or layer stops in the middle of a record; the records before it were read.
    case recordsTruncated(GoodnotesReadingError)
    /// A layer record that could not be read; the rest of the layer was read.
    case recordSkipped(GoodnotesReadingError)
    /// An element that could not be read; the rest of the page was read.
    case elementSkipped(elementIdentifier: String, GoodnotesReadingError)
    /// The page's layer entry could not be read from the archive; the page is returned without elements.
    case layerUnreadable(GoodnotesReadingError)
}

/// Issues in first-reported order, each once.
struct GoodnotesIssueList {
    private(set) var issues: [GoodnotesReadingIssue] = []
    private var reported: Set<GoodnotesReadingIssue> = []

    mutating func report(_ issue: GoodnotesReadingIssue) {
        if reported.insert(issue).inserted { issues.append(issue) }
    }
}
