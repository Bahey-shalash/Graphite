import Foundation

/// What an import report entry tells the person importing, for grouping and ordering a report.
public enum ImportReportCategory: Sendable, Hashable, CaseIterable {
    /// Kept, but not as the source shows it: a highlighter drawn normally, a shape drawn as ink.
    case simplified
    /// Not in the imported notebook: tape, text boxes, a picture whose file is missing, a whole page.
    case leftOut
    /// Something the reader does not know or could not read; the rest of the notebook was read.
    case readingIssue
}

/// An `ImportReportEntry` without its count: entries of one kind on several pages are one line of a report's summary.
public enum ImportReportEntryKind: Sendable, Hashable {
    case highlighterNotMultiplied, pencilTextureNotKept, tapeLeftOut, olderVaryingWidthInkLeftOut, shapesDrawnAsInk, dashesNotKept
    case elementsNotYetConverted(ImportElementKind)
    case picturesMovedUnderInk, animatedPicturesKeptStill, pictureFilesMissing, picturesNotDecodable
    case recordingFilesMissing, recordingTimingNotKept
    case paperRulingNotDrawn, pageWithoutPaper, backgroundFileMissing, pageGeometryUnknown
    case goodnotesReadingIssue(GoodnotesReadingIssue)
    case notabilityReadingIssue(NotabilityReadingIssue)

    public var category: ImportReportCategory {
        switch self {
        case .highlighterNotMultiplied, .pencilTextureNotKept, .shapesDrawnAsInk, .dashesNotKept, .picturesMovedUnderInk, .animatedPicturesKeptStill,
             .paperRulingNotDrawn:
            .simplified
        case .tapeLeftOut, .olderVaryingWidthInkLeftOut, .elementsNotYetConverted, .pictureFilesMissing, .picturesNotDecodable, .recordingFilesMissing,
             .recordingTimingNotKept, .pageWithoutPaper, .backgroundFileMissing, .pageGeometryUnknown:
            .leftOut
        case .goodnotesReadingIssue, .notabilityReadingIssue:
            .readingIssue
        }
    }
}

extension ImportReportEntry {
    public var kind: ImportReportEntryKind {
        switch self {
        case .highlighterNotMultiplied: .highlighterNotMultiplied
        case .pencilTextureNotKept: .pencilTextureNotKept
        case .tapeLeftOut: .tapeLeftOut
        case .olderVaryingWidthInkLeftOut: .olderVaryingWidthInkLeftOut
        case .shapesDrawnAsInk: .shapesDrawnAsInk
        case .dashesNotKept: .dashesNotKept
        case .elementsNotYetConverted(let elementKind, _): .elementsNotYetConverted(elementKind)
        case .picturesMovedUnderInk: .picturesMovedUnderInk
        case .animatedPicturesKeptStill: .animatedPicturesKeptStill
        case .pictureFilesMissing: .pictureFilesMissing
        case .picturesNotDecodable: .picturesNotDecodable
        case .recordingFilesMissing: .recordingFilesMissing
        case .recordingTimingNotKept: .recordingTimingNotKept
        case .paperRulingNotDrawn: .paperRulingNotDrawn
        case .pageWithoutPaper: .pageWithoutPaper
        case .backgroundFileMissing: .backgroundFileMissing
        case .pageGeometryUnknown: .pageGeometryUnknown
        case .goodnotesReadingIssue(let issue): .goodnotesReadingIssue(issue)
        case .notabilityReadingIssue(let issue): .notabilityReadingIssue(issue)
        }
    }

    /// How many strokes, elements, pictures or recordings the entry is about; nil for an entry that is about the page or
    /// the notebook as a whole.
    public var count: Int? {
        switch self {
        case .highlighterNotMultiplied(let count), .pencilTextureNotKept(let count), .tapeLeftOut(let count), .olderVaryingWidthInkLeftOut(let count),
             .shapesDrawnAsInk(let count), .dashesNotKept(let count), .elementsNotYetConverted(_, let count), .picturesMovedUnderInk(let count),
             .animatedPicturesKeptStill(let count), .pictureFilesMissing(let count), .picturesNotDecodable(let count),
             .recordingFilesMissing(let count), .recordingTimingNotKept(let count):
            count
        case .paperRulingNotDrawn, .pageWithoutPaper, .backgroundFileMissing, .pageGeometryUnknown, .goodnotesReadingIssue, .notabilityReadingIssue:
            nil
        }
    }
}
