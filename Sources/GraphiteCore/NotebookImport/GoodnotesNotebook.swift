import CoreGraphics
import Foundation

/// What a Goodnotes notebook holds apart from its pages' elements, read from its event log
/// (`Docs/Goodnotes-format.md`). Each page's elements are read separately, one page at a time, by
/// `GoodnotesNotebookReader.page(at:)`.
public struct GoodnotesNotebook: Sendable, Equatable {
    /// The `schema.pb` version: 24, 25, 26, 27 or 35 in the samples; nil when the file has none.
    public let schemaVersion: UInt64?
    public let title: String
    /// The pages in order: sorted by position, deleted pages left out.
    public let pages: [GoodnotesPageDescriptor]
    /// Pages the event log marks deleted; their records stay in the file.
    public let deletedPageCount: Int
    /// Outline entries in their order.
    public let outlineEntries: [GoodnotesOutlineEntry]
    /// Recordings that were not deleted, in the order the log first names them.
    public let recordings: [GoodnotesRecording]
    /// What the event log holds that this reader does not know, or could not read.
    public let issues: [GoodnotesReadingIssue]
}

/// One page as the event log describes it: its identity, paper and marks. Its elements are in `GoodnotesPage`.
public struct GoodnotesPageDescriptor: Sendable, Equatable {
    public let identifier: String
    /// The page's ink layer, `notes/<layer identifier>` in the archive: the page identifier with 1 added to its last
    /// byte, without carry. Nil when the page identifier does not end in a hexadecimal byte.
    public let layerIdentifier: String?
    public let paper: GoodnotesPaper?
    /// "Add to Favorites" in Goodnotes.
    public let isBookmarked: Bool
    /// Event kind 63 names the page; what Goodnotes means by it is not known.
    public let isFlagged: Bool
}

/// A file in the notebook's `attachments/` folder, as an attachment record names it.
public struct GoodnotesAttachment: Sendable, Equatable {
    public let identifier: String
    /// `attachments/<file identifier>`; nil when the record's file identifier is not one safe file name (reported). The
    /// identifier itself is not kept: nothing reaches the notebook's files but a checked path.
    public let file: NotebookArchivePath?
    public let byteCount: UInt64?
    /// The number of pages when the file is a PDF.
    public let pdfPageCount: UInt64?
}

/// A page's background: always a PDF page from an attachment, template paper as well as an imported PDF.
public struct GoodnotesPaper: Sendable, Equatable {
    /// One Goodnotes unit is 6/11 of a PDF point.
    public static let unitsPerPoint = 11.0 / 6.0

    public let identifier: String
    public let attachment: GoodnotesAttachment?
    /// The page of the attachment, from 1.
    public let pdfPageNumber: UInt64
    public let sizeInUnits: CGSize
    /// Nil for an imported PDF page, which has no template.
    public let template: GoodnotesTemplateIdentifier?

    public var sizeInPoints: CGSize {
        CGSize(width: sizeInUnits.width / Self.unitsPerPoint, height: sizeInUnits.height / Self.unitsPerPoint)
    }
}

/// A template id, `<catalogue UUID>_<size>_<orientation>_<design>`, decoded once; the raw id is kept.
public struct GoodnotesTemplateIdentifier: Sendable, Equatable {
    public enum Size: Sendable, Equatable {
        case a4, a3, standard
        case unknown(String)
    }

    public enum Orientation: Sendable, Equatable {
        case portrait, landscape
        case unknown(String)
    }

    public let rawIdentifier: String
    /// Nil when the id does not have the four parts.
    public let catalogueIdentifier: String?
    public let size: Size?
    public let orientation: Orientation?
    /// A number and a colour (`2 - White`) or a UUID.
    public let design: String?

    public init(rawIdentifier: String) {
        self.rawIdentifier = rawIdentifier
        let parts = rawIdentifier.split(separator: "_", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            catalogueIdentifier = nil
            size = nil
            orientation = nil
            design = nil
            return
        }
        catalogueIdentifier = parts[0]
        size = Self.size(parts[1])
        orientation = Self.orientation(parts[2])
        design = parts[3]
    }

    private static func size(_ rawSize: String) -> Size {
        switch rawSize {
        case "a4": .a4
        case "a3": .a3
        case "standard": .standard
        default: .unknown(rawSize)
        }
    }

    private static func orientation(_ rawOrientation: String) -> Orientation {
        switch rawOrientation {
        case "1": .portrait
        case "2": .landscape
        default: .unknown(rawOrientation)
        }
    }
}

/// An outline entry. Its target names no record in the samples, so it is kept as read.
public struct GoodnotesOutlineEntry: Sendable, Equatable {
    public let title: String
    /// A fractional index; entries sort by it, byte by byte.
    public let orderKey: String
    public let pointOnTargetPage: CGPoint
    public let targetIdentifier: String
}

/// An audio recording and the time at which each element was written during it.
public struct GoodnotesRecording: Sendable, Equatable {
    /// Recording times are stored in flicks, 1/705,600,000 of a second.
    public static let flicksPerSecond = 705_600_000.0

    public struct ElementTiming: Sendable, Equatable {
        /// The element written; it may since have been erased.
        public let elementIdentifier: String
        public let secondsFromStart: Double
        public let pageIdentifier: String
    }

    public let identifier: String
    /// The MP4 audio; nil when the attachment it names is not in the log.
    public let audio: GoodnotesAttachment?
    public let durationSeconds: Double
    public let elementTimings: [ElementTiming]
}
