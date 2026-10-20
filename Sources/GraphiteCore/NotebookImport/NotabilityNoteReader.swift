import CoreGraphics
import Foundation

/// A Notability note (`.note`, session format 9) read from the bytes of its ZIP archive, as described in
/// `Docs/Notability-format.md` and as `scripts/notability-reader.py` reads it. Opening reads `Session.plist` and the
/// recordings library and checks the packed curve arrays; curves stay in those arrays, slices of `Session.plist`'s
/// bytes, until `curve(at:)` or `page(number:)` decodes them. Pictures, PDFs and recordings are read on request
/// with `contents(ofFileAt:)`. What the note holds that the format description does not account for is listed
/// in `issues`, never guessed at.
public struct NotabilityNoteReader: Sendable {
    public let note: NotabilityNote
    public let issues: [NotabilityReadingIssue]
    /// The pages the content reaches, as the reference reader counts them: the page of the largest y of any curve
    /// point or picture bottom, at least 1. Nil when the page height is unknown (a reflowable note, an unknown paper
    /// size) or that page number is beyond `Int`.
    public let pageCount: Int?

    private let zipArchive: ZipArchive
    private let folderName: String
    private let ink: NotabilityInk

    public var curveCount: Int { ink.curveCount }

    public init(archiveBytes: Data, limits: NotebookImportLimits) throws(NotabilityReadingError) {
        do throws(ZipArchiveError) {
            zipArchive = try ZipArchive(archiveBytes: archiveBytes, limits: limits)
        } catch {
            throw .archive(error)
        }
        let folderNames = Set(zipArchive.entries.compactMap { entry in
            entry.name.firstIndex(of: "/").map { separator in String(entry.name[..<separator]) }
        })
        guard folderNames.count == 1, let folderName = folderNames.first else { throw .topLevelFolderCount(folderNames.count) }
        self.folderName = folderName
        let sessionBytes = try Self.entryBytes(named: folderName + "/Session.plist", in: zipArchive)
        let archive: KeyedArchive
        do throws(KeyedArchiveError) {
            archive = try KeyedArchive(archiveBytes: sessionBytes[...], limits: limits)
        } catch {
            throw .session(error)
        }
        var reading = NotabilitySessionReading(archive: archive, limits: limits)
        let content = try reading.content()
        let recordings = Self.recordings(inFolder: folderName, of: zipArchive, limits: limits, issues: &reading.issues)
        note = NotabilityNote(name: content.name, sessionFormatVersion: content.sessionFormatVersion,
                              applicationVersion: content.applicationVersion, paper: content.paper, reflowState: content.reflowState,
                              pageGeometry: content.pageGeometry, shapes: content.shapes, pictures: content.pictures,
                              typedText: content.typedText, importedPDFPages: content.importedPDFPages, recordings: recordings,
                              playbackEvents: content.playbackEvents)
        ink = content.ink
        issues = reading.issues.issues
        pageCount = NotabilityPagePlacement(geometry: content.pageGeometry).pageCount(inkBottomY: content.ink.highestY, pictures: content.pictures)
    }

    /// The recordings of `Recordings/library.plist`; none when the note has no library, and none with an issue when the
    /// library cannot be read, so that a damaged library never costs the note its ink.
    private static func recordings(inFolder folderName: String, of zipArchive: ZipArchive, limits: NotebookImportLimits,
                                   issues: inout NotabilityReadingIssues) -> [NotabilityRecording] {
        let libraryName = folderName + "/Recordings/library.plist"
        guard zipArchive.entry(named: libraryName) != nil else { return [] }
        do throws(NotabilityReadingError) {
            let library = try NotabilityRecordingsLibrary.recordings(fromLibraryBytes: entryBytes(named: libraryName, in: zipArchive)[...],
                                                                     limits: limits)
            for path in library.invalidPaths { issues.report(.archivePathNotValid(path: path)) }
            return library.recordings
        } catch {
            issues.report(.recordingsSkipped(error))
            return []
        }
    }

    public func isHighlighter(curveIndex: Int) throws(NotabilityReadingError) -> Bool {
        try checkCurveIndex(curveIndex)
        return ink.isHighlighter(curveIndex: curveIndex)
    }

    /// The curve at this index of the drawing order, decoded from the packed arrays.
    public func curve(at curveIndex: Int) throws(NotabilityReadingError) -> NotabilityCurve {
        try checkCurveIndex(curveIndex)
        return ink.curve(at: curveIndex)
    }

    /// What export page `pageNumber` (from 1) shows. A curve is on every page its points' vertical extent touches, and
    /// a shape on every page between its lowest and highest point (start, end and control point), so a stroke that
    /// crosses a page is drawn there; the reference reader lists an element only on pages that hold one of its
    /// points. A picture is on every page its turned bounding box touches. Only that page's curves are decoded.
    public func page(number pageNumber: Int) throws(NotabilityReadingError) -> NotabilityPage {
        let geometry = note.pageGeometry
        guard let pageCount, let pageHeight = geometry.pageHeightInUnits else { throw .pageCountUnknown }
        guard pageNumber >= 1, pageNumber <= pageCount else { throw .pageNumberOutOfRange(pageNumber: pageNumber, pageCount: pageCount) }
        let placement = NotabilityPagePlacement(geometry: geometry)
        let curves = ink.curveIndices(onPage: pageNumber, placement: placement).map { curveIndex in ink.curve(at: curveIndex) }
        let shapes = note.shapes.filter { shape in
            let extent = NotabilityPagePlacement.verticalExtent(of: shape)
            return placement.isOnPage(pageNumber, lowestY: extent.lowest, highestY: extent.highest)
        }
        let pictures = note.pictures.filter { picture in
            let extent = NotabilityPagePlacement.verticalExtent(of: picture)
            return placement.isOnPage(pageNumber, lowestY: extent.lowest, highestY: extent.highest)
        }
        return NotabilityPage(pageNumber: pageNumber, topInUnits: Double(pageNumber - 1) * pageHeight, curves: curves, shapes: shapes,
                              pictures: pictures)
    }

    /// A file of the note, by its path relative to the note's folder: a picture's `file`, an imported PDF's `pdfFile`, a
    /// recording's `file`. A stored file is a slice of the archive's bytes, not a copy (`ZipArchive.data(of:)`).
    public func contents(ofFileAt path: NotebookArchivePath) throws(NotabilityReadingError) -> Data {
        let name = folderName + "/" + path.text
        guard let entry = zipArchive.entry(named: name) else { throw .archive(.entryMissing(name: name)) }
        do throws(ZipArchiveError) { return try zipArchive.data(of: entry) } catch { throw .archive(error) }
    }

    /// Hands a file of the note to `consume` in pieces (`ZipArchive.copy(_:chunkByteCount:to:)`), for a file too large
    /// to hold whole, such as a recording.
    public func copy<DestinationError: Error>(fileAt path: NotebookArchivePath, chunkByteCount: Int = ZipArchive.standardCopyChunkByteCount,
                                               to consume: (UnsafeRawBufferPointer) throws(DestinationError) -> Void)
        throws(ZipEntryCopyError<DestinationError>) {
        let name = folderName + "/" + path.text
        guard let entry = zipArchive.entry(named: name) else { throw .archive(.entryMissing(name: name)) }
        try zipArchive.copy(entry, chunkByteCount: chunkByteCount, to: consume)
    }

    private func checkCurveIndex(_ curveIndex: Int) throws(NotabilityReadingError) {
        guard curveIndex >= 0, curveIndex < ink.curveCount else {
            throw .curveIndexOutOfRange(curveIndex: curveIndex, curveCount: ink.curveCount)
        }
    }

    private static func entryBytes(named name: String, in zipArchive: ZipArchive) throws(NotabilityReadingError) -> [UInt8] {
        do throws(ZipArchiveError) {
            return try zipArchive.contents(ofEntryNamed: name)
        } catch {
            throw .archive(error)
        }
    }
}
