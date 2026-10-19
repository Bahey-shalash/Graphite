import Foundation

/// Reads a Goodnotes notebook (`.goodnotes`, `Docs/Goodnotes-format.md`) from its archive bytes, one page at a
/// time. Opening reads only the schema and the event log; `page(at:)` decompresses and decodes that page's layer and
/// nothing else, so a notebook of any length never sits in memory decoded. Pass memory-mapped bytes for a large file.
/// The reader holds only immutable values, so pages can be read from any task.
public struct GoodnotesNotebookReader: Sendable {
    /// The schema versions the format document describes.
    public static let describedSchemaVersions: Set<UInt64> = [24, 25, 26, 27, 35]
    private static let schemaEntryName = "schema.pb"
    private static let eventLogEntryName = "index.events.pb"
    private static let layerFolder = "notes/"
    private static let attachmentFolder = "attachments/"

    public let notebook: GoodnotesNotebook
    private let archive: ZipArchive
    private let limits: NotebookImportLimits
    private let attachments: [String: GoodnotesAttachment]
    private let layerMembers: [String: Set<String>]

    public init(archiveBytes: Data, limits: NotebookImportLimits) throws(GoodnotesReadingError) {
        let archive: ZipArchive
        do throws(ZipArchiveError) { archive = try ZipArchive(archiveBytes: archiveBytes, limits: limits) } catch { throw .archive(error) }
        guard archive.entry(named: Self.schemaEntryName) != nil else { throw .notAGoodnotesNotebook }
        let schemaVersion = try GoodnotesRecordFields(parsing: try Self.contents(of: Self.schemaEntryName, in: archive)[...]).varint(1)
        var log = GoodnotesEventLog()
        if !(schemaVersion.map(Self.describedSchemaVersions.contains) ?? false) { log.issues.report(.schemaVersionNotKnown(schemaVersion)) }
        let (records, framingFailure) = ProtocolBufferMessage.lengthPrefixedRecords(in: try Self.contents(of: Self.eventLogEntryName, in: archive)[...])
        for record in records {
            do throws(GoodnotesReadingError) { try log.apply(record: record) } catch { log.issues.report(.eventSkipped(error)) }
        }
        if let framingFailure { log.issues.report(.recordsTruncated(.protocolBuffer(framingFailure))) }
        let ordered = log.orderedPages()
        for issue in ordered.issues { log.issues.report(issue) }
        notebook = GoodnotesNotebook(schemaVersion: schemaVersion, title: log.titleText, pages: ordered.pages, deletedPageCount: ordered.deletedPageCount,
                                     outlineEntries: log.sortedOutlineEntries, recordings: log.liveRecordings, issues: log.issues.issues)
        self.archive = archive
        self.limits = limits
        attachments = log.attachments
        layerMembers = log.layerMembers
    }

    public var pageCount: Int { notebook.pages.count }

    /// The page at `pageIndex` (from 0) with its elements that are not erased, in drawing order. A page whose layer
    /// cannot be read fully is returned as far as it was read, with its issues saying what was skipped.
    public func page(at pageIndex: Int) throws(GoodnotesReadingError) -> GoodnotesPage {
        guard notebook.pages.indices.contains(pageIndex) else { throw .pageIndexOutOfRange(pageIndex) }
        let descriptor = notebook.pages[pageIndex]
        var issues = GoodnotesIssueList()
        guard let layerIdentifier = descriptor.layerIdentifier else {
            issues.report(.layerIdentifierNotDerivable(pageIdentifier: descriptor.identifier))
            return GoodnotesPage(descriptor: descriptor, elements: [], issues: issues.issues)
        }
        let layerBytes: [UInt8]
        do throws(GoodnotesReadingError) {
            layerBytes = try Self.contents(of: Self.layerFolder + layerIdentifier, in: archive)
        } catch {
            issues.report(.layerUnreadable(error))
            return GoodnotesPage(descriptor: descriptor, elements: [], issues: issues.issues)
        }
        let reader = GoodnotesLayerReader(decoder: GoodnotesElementDecoder(limits: limits, attachments: attachments),
                                          members: layerMembers[layerIdentifier])
        let elements = reader.elements(inLayer: layerBytes[...], issues: &issues)
        return GoodnotesPage(descriptor: descriptor, elements: elements, issues: issues.issues)
    }

    /// The bytes of an attachment's file: a template or imported PDF, a picture or a recording.
    public func contents(of attachment: GoodnotesAttachment) throws(GoodnotesReadingError) -> [UInt8] {
        do throws(ZipArchiveError) { return try archive.contents(ofEntryNamed: Self.attachmentFolder + attachment.fileIdentifier) } catch {
            throw .archive(error)
        }
    }

    /// An entry's bytes; a missing entry reads as empty, as a page with no content has an empty or no layer file.
    private static func contents(of entryName: String, in archive: ZipArchive) throws(GoodnotesReadingError) -> [UInt8] {
        guard let entry = archive.entry(named: entryName) else { return [] }
        do throws(ZipArchiveError) { return try archive.contents(of: entry) } catch { throw .archive(error) }
    }
}
