import XCTest
import PDFKit
import ImageIO
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Apple-framework services that earlier tests did not reach: folder monitoring, raster
/// thumbnails, drawing detection, PDF copies, refused PDF saves, and recording controls.
final class TestsExistingAppleServiceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppleServices-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let payload = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("pencil strokes".utf8))

    private func makeDrawing() throws -> VectorDrawing {
        let stroke = (0...50).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step) * 4, y: 50), width: 6) }
        let shape = try XCTUnwrap(StrokeOutliner.shape(forSegments: [stroke], color: VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1)))
        return VectorDrawing(size: CGSize(width: 400, height: 200), background: .white, shapes: [shape])
    }

    /// A white image whose top half is black.
    private func twoToneImageData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Core Graphics y grows upward, so the upper half starts at half the height.
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return try ImageEncoding.pngData(from: XCTUnwrap(context.makeImage()))
    }

    private func writePDF(to location: URL, auxiliaryInformation: [CFString: Any]) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInformation as CFDictionary))
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 20, y: 20, width: 40, height: 40))
        context.endPDFPage()
        context.closePDF()
    }

    // MARK: Folder monitoring

    func testVaultMonitorReportsCoordinatedWritesInsideTheVault() async throws {
        let noteChanged = expectation(description: "The monitor reports the new note.")
        noteChanged.assertForOverFulfill = false
        let monitor = VaultMonitor(root: folder) { location in
            if location?.lastPathComponent == "Note.md" { noteChanged.fulfill() }
        }
        defer { monitor.stop() }
        try AtomicFileWriter().write(Data("# Note\n".utf8), to: folder.appendingPathComponent("Note.md"), expecting: .absent)
        await fulfillment(of: [noteChanged], timeout: 10)
    }

    func testVaultMonitorIsSilentAfterStopping() async throws {
        let unexpectedChange = expectation(description: "A stopped monitor reports nothing.")
        unexpectedChange.isInverted = true
        let monitor = VaultMonitor(root: folder) { _ in unexpectedChange.fulfill() }
        monitor.stop()
        try AtomicFileWriter().write(Data("# Note\n".utf8), to: folder.appendingPathComponent("Note.md"), expecting: .absent)
        await fulfillment(of: [unexpectedChange], timeout: 1)
    }

    @MainActor
    func testFolderAccessOpensTheVaultInsideTheGrantedFolder() throws {
        let vaultFolder = folder.appendingPathComponent("Vault", isDirectory: true)
        let access = FolderAccess(root: vaultFolder, scopedFolder: folder)
        XCTAssertEqual(access.root, vaultFolder)
    }

    // MARK: Raster thumbnails and drawing detection

    func testRasterThumbnailIsDownsampledAndUpright() async throws {
        let location = folder.appendingPathComponent("Photo.png")
        try twoToneImageData(width: 1_000, height: 500).write(to: location)
        let thumbnail = try await ImageFileService().thumbnailData(at: location, maximumDimension: 200)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil).flatMap { source in CGImageSourceCreateImageAtIndex(source, 0, nil) })
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 500, y: 400), pageHeight: 500), "The black half stays at the top.")
        XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 500, y: 100), pageHeight: 500), "The white half stays at the bottom.")
    }

    func testCorruptImageAndOrdinaryPDFAreReportedAsSuch() async throws {
        let brokenImage = folder.appendingPathComponent("Broken.png")
        try Data("not an image".utf8).write(to: brokenImage)
        let service = ImageFileService()
        do {
            _ = try await service.thumbnailData(at: brokenImage)
            XCTFail("A corrupt image has no thumbnail.")
        } catch {}
        let ordinaryPDF = folder.appendingPathComponent("Slides.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification()).write(to: ordinaryPDF)
        let ordinaryIsDrawing = await service.isEditableDrawingPDF(at: ordinaryPDF)
        XCTAssertFalse(ordinaryIsDrawing)
        let imageIsDrawing = await service.isEditableDrawingPDF(at: brokenImage)
        XCTAssertFalse(imageIsDrawing)
    }

    func testEditableStrokesAreFoundInEveryDrawingFormatOnly() throws {
        let ordinaryPNGData = try twoToneImageData(width: 40, height: 20)
        let files: [(name: String, contents: Data, isEditable: Bool)] = [
            ("Drawing.png", try GraphitePNG.encode(imageData: ordinaryPNGData, drawing: payload), true),
            ("Photo.png", ordinaryPNGData, false),
            ("Drawing.svg", try SVGDrawingFile.encode(makeDrawing(), payload: payload), true),
            ("Exported.svg", try SVGDrawingFile.encode(makeDrawing(), payload: nil), false),
            ("Drawing.pdf", try PDFDrawingFile.encode(makeDrawing(), payload: payload), true),
            ("Slides.pdf", try PDFTemplateGenerator.documentData(paper: PaperSpecification()), false),
            ("Notes.txt", Data("text".utf8), false),
        ]
        for file in files {
            let location = folder.appendingPathComponent(file.name)
            try file.contents.write(to: location)
            XCTAssertEqual(DrawingMetadataReader.hasEditableStrokes(at: location), file.isEditable, file.name)
        }
        XCTAssertFalse(DrawingMetadataReader.hasEditableStrokes(at: folder.appendingPathComponent("Missing.png")))
    }

    // MARK: PDF copies and refused saves

    func testSaveCopyWritesTheEditedCopyAndKeepsTheOriginal() async throws {
        let original = folder.appendingPathComponent("Original.pdf"), copy = folder.appendingPathComponent("Copy.pdf")
        let originalData = try PDFTemplateGenerator.documentData(paper: PaperSpecification(), pageCount: 2)
        try originalData.write(to: original)
        let service = PDFFileService()
        let copyRevision = try await service.saveCopy(baselineURL: original, edits: [.rotate(page: 1, clockwise: true)], destination: copy)
        XCTAssertEqual(try FileRevision.read(copy), copyRevision)
        let copiedDocument = try XCTUnwrap(PDFDocument(url: copy))
        XCTAssertEqual(copiedDocument.pageCount, 2)
        XCTAssertEqual(copiedDocument.page(at: 0)?.rotation, 0)
        XCTAssertEqual(copiedDocument.page(at: 1)?.rotation, 90)
        XCTAssertEqual(try Data(contentsOf: original), originalData, "The original is not changed.")
        do {
            _ = try await service.saveCopy(baselineURL: original, edits: [], destination: copy)
            XCTFail("A copy never replaces an existing file.")
        } catch {}
        XCTAssertEqual(try FileRevision.read(copy), copyRevision)
    }

    func testSavingAPasswordProtectedPDFIsRefusedAndTheFileIsKept() async throws {
        let location = folder.appendingPathComponent("Protected.pdf")
        try writePDF(to: location, auxiliaryInformation: [kCGPDFContextUserPassword: "reader", kCGPDFContextOwnerPassword: "owner"])
        XCTAssertEqual(PDFDocument(url: location)?.isLocked, true)
        let originalData = try Data(contentsOf: location)
        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.of(originalData), edits: [.rotate(page: 0, clockwise: true)])
            XCTFail("A locked PDF cannot be saved.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: location), originalData)
    }

    func testSavingAPDFThatForbidsChangesIsRefusedAndTheFileIsKept() async throws {
        let location = folder.appendingPathComponent("Restricted.pdf")
        let restrictedDocument = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification())))
        XCTAssertTrue(restrictedDocument.write(to: location, withOptions: [.ownerPasswordOption: "owner", .accessPermissionsOption: NSNumber(value: PDFAccessPermissions.allowsHighQualityPrinting.rawValue)]))
        let reopened = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertFalse(reopened.isLocked, "Anyone can read it; only changes need the owner password.")
        XCTAssertFalse(reopened.allowsDocumentChanges)
        let originalData = try Data(contentsOf: location)
        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.of(originalData), edits: [.rotate(page: 0, clockwise: true)])
            XCTFail("A PDF whose permissions forbid changes cannot be saved.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: location), originalData)
    }

    /// A folder that refuses new files, as a full or read-only file provider does, makes the
    /// staging write fail before the original is touched.
    func testFailedStagingWriteKeepsTheOriginalPDF() async throws {
        let readOnlyFolder = folder.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyFolder, withIntermediateDirectories: true)
        let location = readOnlyFolder.appendingPathComponent("Slides.pdf")
        let originalData = try PDFTemplateGenerator.documentData(paper: PaperSpecification())
        try originalData.write(to: location)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyFolder.path) }
        try XCTSkipIf(FileManager.default.isWritableFile(atPath: readOnlyFolder.path), "This user can write to read-only folders.")
        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.of(originalData), edits: [.rotate(page: 0, clockwise: true)])
            XCTFail("A PDF whose staging copy cannot be written is not saved.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: location), originalData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: readOnlyFolder.path), ["Slides.pdf"])
    }

    /// The saved snapshot is copied from the staging file before the replacement, so a failed
    /// copy abandons the save instead of leaving an edited file without its baseline.
    func testFailedSnapshotCopyKeepsTheOriginalPDF() async throws {
        let location = folder.appendingPathComponent("Slides.pdf")
        let originalData = try PDFTemplateGenerator.documentData(paper: PaperSpecification())
        try originalData.write(to: location)
        let unreachableSnapshot = folder.appendingPathComponent("Missing folder/Snapshot.pdf")
        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.of(originalData), edits: [.rotate(page: 0, clockwise: true)], savedSnapshotDestination: unreachableSnapshot)
            XCTFail("A save whose snapshot cannot be written is abandoned.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: location), originalData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Slides.pdf"])
    }

    // MARK: Recording

    func testRecordingStateTransitions() {
        let startable: Set<RecordingState> = [.idle, .failed]
        let resumable: Set<RecordingState> = [.paused, .interrupted]
        let stoppable: Set<RecordingState> = [.recording, .paused, .interrupted]
        for state in [RecordingState.idle, .requestingPermission, .recording, .paused, .interrupted, .finalizing, .failed] {
            XCTAssertEqual(state.canStart, startable.contains(state), state.rawValue)
            XCTAssertEqual(state.canResume, resumable.contains(state), state.rawValue)
            XCTAssertEqual(state.canStop, stoppable.contains(state), state.rawValue)
            XCTAssertEqual(state.isActive, !startable.contains(state), state.rawValue)
        }
    }

    /// Controls pressed before a recording exists must not leave the idle state or claim a file.
    @MainActor
    func testRecordingControlsDoNothingBeforeRecordingStarts() async {
        let controller = RecordingController()
        controller.pause()
        controller.resume()
        controller.stop()
        await controller.retryPublication()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.message)
        XCTAssertNil(controller.destination)
        XCTAssertNil(controller.lastCompletedURL)
        XCTAssertNil(controller.recoveryURL)
        XCTAssertEqual(controller.elapsedSeconds, 0)
    }
}
