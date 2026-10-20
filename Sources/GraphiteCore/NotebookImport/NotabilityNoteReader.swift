import CoreGraphics
import Foundation

/// A Notability note (`.note`, session format 9) read from the bytes of its ZIP archive, as described in
/// `Docs/Notability-format.md` and as `scripts/notability-reader.py` reads it. Opening reads `Session.plist` and the
/// recordings library and checks the packed curve arrays; curves stay in those arrays, slices of `Session.plist`'s
/// bytes, until `curve(at:)` or `page(number:)` decodes them. Pictures, PDFs and recordings are read on request
/// with `fileBytes(_:)`. What the note holds that the format description does not account for is listed
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
        issues = reading.issues.list
        pageCount = Self.pageCount(ink: content.ink, pictures: content.pictures, geometry: content.pageGeometry)
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
        let curves = ink.curveIndices(onPage: pageNumber, geometry: geometry).map { curveIndex in ink.curve(at: curveIndex) }
        let shapes = note.shapes.filter { shape in
            let verticalPositions = [shape.start.y, shape.end.y] + (shape.quadraticControlPoint.map { point in [point.y] } ?? [])
            return Self.extent(lowest: verticalPositions.min() ?? 0, highest: verticalPositions.max() ?? 0, touches: pageNumber, geometry: geometry)
        }
        let pictures = note.pictures.filter { picture in
            let center = picture.origin.y + picture.size.height / 2
            let halfHeight = abs(picture.size.width / 2 * sin(picture.rotationRadiansClockwise))
                + abs(picture.size.height / 2 * cos(picture.rotationRadiansClockwise))
            return Self.extent(lowest: center - halfHeight, highest: center + halfHeight, touches: pageNumber, geometry: geometry)
        }
        return NotabilityPage(pageNumber: pageNumber, topInUnits: Double(pageNumber - 1) * pageHeight, curves: curves, shapes: shapes,
                              pictures: pictures)
    }

    /// The bytes of a file of the note, by its path relative to the note's folder: a picture's `file`, an imported PDF's
    /// `pdfFile`, a recording's `file`.
    public func fileBytes(_ path: NotebookArchivePath) throws(NotabilityReadingError) -> [UInt8] {
        try Self.entryBytes(named: folderName + "/" + path.text, in: zipArchive)
    }

    private func checkCurveIndex(_ curveIndex: Int) throws(NotabilityReadingError) {
        guard curveIndex >= 0, curveIndex < ink.curveCount else {
            throw .curveIndexOutOfRange(curveIndex: curveIndex, curveCount: ink.curveCount)
        }
    }

    private static func extent(lowest: Double, highest: Double, touches pageNumber: Int, geometry: NotabilityPageGeometry) -> Bool {
        guard let firstPage = geometry.pagePosition(ofVerticalPosition: lowest),
              let lastPage = geometry.pagePosition(ofVerticalPosition: highest) else { return false }
        return firstPage <= Double(pageNumber) && Double(pageNumber) <= lastPage
    }

    private static func pageCount(ink: NotabilityInk, pictures: [NotabilityPicture], geometry: NotabilityPageGeometry) -> Int? {
        let pictureBottoms = pictures.map { picture in Double(picture.origin.y + picture.size.height) }
        let lowestContent = ((ink.highestY.map { highestY in [highestY] } ?? []) + pictureBottoms + [0]).max() ?? 0
        return geometry.pagePosition(ofVerticalPosition: lowestContent).flatMap(NotabilityPageGeometry.pageNumber(fromPagePosition:))
    }

    private static func entryBytes(named name: String, in zipArchive: ZipArchive) throws(NotabilityReadingError) -> [UInt8] {
        do throws(ZipArchiveError) {
            return try zipArchive.contents(ofEntryNamed: name)
        } catch {
            throw .archive(error)
        }
    }
}
