import Foundation

/// What an import did with a notebook, as plain values for the import's caller to show: every source page, written or
/// left out, with its entries; what concerns the notebook as a whole (its recordings, what the reader could not read
/// outside the pages); and a summary with one line per kind of entry. The words are the presenter's.
public struct NotebookImportReport: Sendable, Equatable {
    public enum Source: Sendable, Hashable {
        case goodnotes, notability
    }

    public let source: Source
    /// Every source page, in source page order.
    public let pages: [ImportedPageReport]
    /// Entries about the notebook as a whole, such as `recordingTimingNotKept` and the reader's notebook-level issues.
    public let notebookEntries: [ImportReportEntry]
    /// The recordings kept as `.m4a` files.
    public let recordingCount: Int

    public init(source: Source, pages: [ImportedPageReport], notebookEntries: [ImportReportEntry], recordingCount: Int) {
        self.source = source
        self.pages = pages.enumerated().sorted { first, second in
            (first.element.sourcePageNumber, first.offset) < (second.element.sourcePageNumber, second.offset)
        }.map(\.element)
        self.notebookEntries = notebookEntries
        self.recordingCount = recordingCount
    }

    /// The notebook-level entries of a Goodnotes notebook: its recordings' report, then the issues the reader found
    /// outside the pages.
    public static func notebookEntries(of notebook: GoodnotesNotebook, recordings: ImportedRecordingsPlan) -> [ImportReportEntry] {
        recordings.report + notebook.issues.map(ImportReportEntry.goodnotesReadingIssue)
    }

    /// The notebook-level entries of a Notability note: `pageGeometryUnknown` when the note cannot be cut into pages
    /// (it then has none to report), its recordings' report, then the issues the reader found outside the pages.
    public static func notebookEntries(of reader: NotabilityNoteReader, recordings: ImportedRecordingsPlan) -> [ImportReportEntry] {
        (reader.pageCount == nil ? [.pageGeometryUnknown] : []) + recordings.report + reader.issues.map(ImportReportEntry.notabilityReadingIssue)
    }

    public var writtenPageCount: Int { pages.count { page in page.written != nil } }
    public var leftOutPageNumbers: [Int] { pages.filter { page in page.written == nil }.map(\.sourcePageNumber) }
    /// True when at least one page was written and nothing was simplified, left out or unreadable.
    public var isComplete: Bool {
        !pages.isEmpty && pages.allSatisfy { page in page.written != nil && page.entries.isEmpty } && notebookEntries.isEmpty
    }

    /// One line per kind of entry, in the order the kinds first appear (pages first, then the notebook's entries), with
    /// the counts added up and the pages it occurs on. Reading issues of one case are one line whatever element or
    /// record each names (a notebook can have thousands of one case); the line's `kind` is the first of them.
    public var summary: [ImportReportSummaryLine] {
        var lines: [ImportReportSummaryLine] = []
        var lineIndexByGroup: [SummaryGroup: Int] = [:]
        func add(_ entry: ImportReportEntry, pageNumber: Int?) {
            let group = SummaryGroup(entry.kind)
            let lineIndex = lineIndexByGroup[group] ?? {
                lines.append(ImportReportSummaryLine(kind: entry.kind, totalCount: nil, occurrenceCount: 0, pageNumbers: []))
                lineIndexByGroup[group] = lines.count - 1
                return lines.count - 1
            }()
            lines[lineIndex].record(count: entry.count, pageNumber: pageNumber)
        }
        for page in pages {
            for entry in page.entries { add(entry, pageNumber: page.sourcePageNumber) }
        }
        for entry in notebookEntries { add(entry, pageNumber: nil) }
        return lines
    }

    /// What one summary line gathers: a kind, or for a reading issue only its case, named as Swift names it.
    private enum SummaryGroup: Hashable {
        case kind(ImportReportEntryKind)
        case goodnotesReadingIssue(caseName: String)
        case notabilityReadingIssue(caseName: String)

        init(_ kind: ImportReportEntryKind) {
            switch kind {
            case .goodnotesReadingIssue(let issue): self = .goodnotesReadingIssue(caseName: Self.caseName(of: issue))
            case .notabilityReadingIssue(let issue): self = .notabilityReadingIssue(caseName: Self.caseName(of: issue))
            case .highlighterNotMultiplied, .pencilTextureNotKept, .tapeLeftOut, .olderVaryingWidthInkLeftOut, .shapesDrawnAsInk, .dashesNotKept,
                 .elementsNotYetConverted, .picturesMovedUnderInk, .animatedPicturesKeptStill, .pictureFilesMissing, .picturesNotDecodable,
                 .recordingFilesMissing, .recordingsNotCopied, .recordingTimingNotKept, .outlineEntriesWithoutPage, .paperRulingNotDrawn, .pageWithoutPaper,
                 .backgroundFileMissing, .pageGeometryUnknown, .textStylesNotKept, .fontsReplaced, .stickyNotesAsTextBoxes, .textBoxesNotPlaced,
                 .pageWidthAssumed:
                self = .kind(kind)
            }
        }

        /// A case with associated values reflects as one child labelled with the case's name; one without, as its name.
        private static func caseName(of issue: some Hashable) -> String {
            Mirror(reflecting: issue).children.first?.label ?? String(describing: issue)
        }
    }
}

/// One kind of entry across a notebook: how many strokes, elements or pictures it covers in all (nil for a kind
/// without a count), how many entries it gathers, and the pages it occurs on (empty for the notebook as a whole).
public struct ImportReportSummaryLine: Sendable, Equatable {
    public let kind: ImportReportEntryKind
    public private(set) var totalCount: Int?
    public private(set) var occurrenceCount: Int
    public private(set) var pageNumbers: [Int]

    public var category: ImportReportCategory { kind.category }

    public init(kind: ImportReportEntryKind, totalCount: Int?, occurrenceCount: Int, pageNumbers: [Int]) {
        self.kind = kind
        self.totalCount = totalCount
        self.occurrenceCount = occurrenceCount
        self.pageNumbers = pageNumbers
    }

    mutating func record(count: Int?, pageNumber: Int?) {
        if let count { totalCount = (totalCount ?? 0) + count }
        occurrenceCount += 1
        if let pageNumber, pageNumbers.last != pageNumber { pageNumbers.append(pageNumber) }
    }
}
