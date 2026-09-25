import XCTest
import SwiftUI
import ImageIO
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI

@MainActor
final class UiRootSettingsTests: XCTestCase {
    /// XCTest makes a new instance for each test, so each test has its own directory.
    private let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("UiRootSettings-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: Image pane

    private func graphiteSVGData() throws -> Data {
        let stroke = (0...50).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step) * 4, y: 60), width: 6) }
        let shapes = [StrokeOutliner.shape(forSegments: [stroke], color: VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1))].compactMap { shape in shape }
        let drawing = VectorDrawing(size: CGSize(width: 400, height: 200), background: .white, shapes: shapes)
        return try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("strokes".utf8)))
    }

    func testGraphiteSVGShowsItsImageAndOffersEditing() async throws {
        let location = temporaryDirectory.appendingPathComponent("Drawing.svg")
        try graphiteSVGData().write(to: location)

        let content = await ImagePaneContent.load(from: location, fileExtension: "svg")

        XCTAssertNotNil(content.image)
        XCTAssertTrue(content.hasEditableStrokes)
        XCTAssertNil(content.message)
    }

    /// An SVG recoloured in another app cannot be drawn by Graphite. The pane used to say
    /// "The image is intact" over an empty area, hiding the error that explains it.
    func testSVGChangedInAnotherAppKeepsTheErrorThatExplainsTheEmptyPane() async throws {
        let location = temporaryDirectory.appendingPathComponent("Drawing.svg")
        let text = try XCTUnwrap(String(data: try graphiteSVGData(), encoding: .utf8))
        let recoloured = text.replacingOccurrences(of: "fill=\"#000000\"", with: "fill=\"#ff0000\"")
        XCTAssertNotEqual(recoloured, text)
        try Data(recoloured.utf8).write(to: location)

        let content = await ImagePaneContent.load(from: location, fileExtension: "svg")

        XCTAssertNil(content.image)
        XCTAssertFalse(content.hasEditableStrokes)
        let message = try XCTUnwrap(content.message)
        XCTAssertFalse(message.contains("intact"), message)
        XCTAssertTrue(message.contains("system preview"), message)
    }

    func testMissingImageReportsAnErrorAndNoPixels() async {
        let content = await ImagePaneContent.load(from: temporaryDirectory.appendingPathComponent("Missing.png"), fileExtension: "png")
        XCTAssertNil(content.image)
        XCTAssertFalse(content.hasEditableStrokes)
        XCTAssertNotNil(content.message)
    }

    // MARK: Embedded images

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoding.pngData(from: XCTUnwrap(context.makeImage()))
    }

    func testEmbeddedImageIsDecodedOnceForTheSameData() throws {
        let cache = DecodedImageCache()
        let firstData = try pngData(width: 8, height: 4)

        let firstImage = try XCTUnwrap(cache.image(for: firstData))
        let sameImage = try XCTUnwrap(cache.image(for: Data(firstData)))
        XCTAssertTrue(firstImage === sameImage, "Re-rendering the embed must not decode its image again.")

        let otherImage = try XCTUnwrap(cache.image(for: try pngData(width: 4, height: 8)))
        XCTAssertFalse(otherImage === firstImage)
        XCTAssertEqual(otherImage.size.height, 8)
    }

    // MARK: Sidebar

    func testToggleSidebarShowsTheSidebarFirstWhenAutomaticModeHidesIt() {
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: .automatic, automaticHidesSidebar: true), .all)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: .automatic, automaticHidesSidebar: false), .detailOnly)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: .detailOnly, automaticHidesSidebar: false), .all)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: .all, automaticHidesSidebar: true), .detailOnly)
    }

    // MARK: Drawings

    func testNewDrawingCanvasTakesTheNoteWidthLimit() throws {
        let newDrawing = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                              title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        XCTAssertEqual(newDrawing.resolvedCanvasWidth, 760)

        let existingDrawing = DrawingEditorRequest(target: .existingDrawing(path: try VaultPath("Drawing.png"), location: temporaryDirectory.appendingPathComponent("Drawing.png"),
                                                                            revision: .of(Data())),
                                                   title: "Drawing.png", initialStrokeData: Data(), canvasWidth: 1024, background: .white, format: .png)
        XCTAssertEqual(existingDrawing.resolvedCanvasWidth, 1024, "An existing drawing keeps the width it was drawn at.")
    }

    private func svgDrawingFile(width: Double, background: DrawingBackground, strokes: Data) throws -> Data {
        let drawing = VectorDrawing(size: CGSize(width: width, height: 200), background: background, shapes: [])
        return try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: width, height: 200, background: background, strokes: strokes))
    }

    func testDrawingDraftReopensWithItsStrokesUntilTheEditorCloses() async throws {
        let directory = temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true)
        let store = DrawingEditorDraftStore(directory: directory)
        let vaultIdentifier = UUID(), otherVaultIdentifier = UUID()
        let notePath = try VaultPath("Lectures/Signals.md")
        let request = DrawingEditorRequest(target: .newDrawing(notePath: notePath, insertionRange: NSRange(location: 12, length: 3)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .transparent, format: .png)
        let strokeData = Data("pencil strokes".utf8)
        let drawingFile = try svgDrawingFile(width: 760, background: .transparent, strokes: strokeData)

        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) { drawingFile }

        let otherVaultDrafts = await store.drafts(forVault: otherVaultIdentifier)
        XCTAssertTrue(otherVaultDrafts.isEmpty)
        let recoveredDrafts = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(recoveredDrafts.count, 1)
        let recoveredDraft = try XCTUnwrap(recoveredDrafts.first)

        // The unsaved work is an ordinary SVG drawing that any browser can show.
        let savedDrawing = try Data(contentsOf: directory.appendingPathComponent(request.id.uuidString).appendingPathExtension("svg"))
        XCTAssertTrue(XMLParser(data: savedDrawing).parse())

        let vaultRoot = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        let reopened = try recoveredDraft.editorRequest(inVaultAt: vaultRoot)
        XCTAssertEqual(reopened.id, request.id, "Closing the reopened editor must remove this draft.")
        XCTAssertTrue(reopened.isRecoveredDraft)
        XCTAssertEqual(reopened.initialStrokeData, strokeData)
        XCTAssertEqual(reopened.canvasWidth, 760)
        XCTAssertEqual(reopened.background, .transparent)
        XCTAssertEqual(reopened.format, .png, "The drawing is still saved in the format it was going to be saved in.")
        guard case .newDrawing(let reopenedNotePath, let insertionRange) = reopened.target else { return XCTFail("Expected a new drawing") }
        XCTAssertEqual(reopenedNotePath, notePath)
        XCTAssertEqual(insertionRange, NSRange(location: 12, length: 3))

        store.removeDraft(withIdentifier: request.id)
        let remainingDrafts = await store.drafts(forVault: vaultIdentifier)
        XCTAssertTrue(remainingDrafts.isEmpty)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(remainingFiles.isEmpty, "\(remainingFiles)")
    }

    func testRemovingADraftRightAfterWritingItLeavesNothing() async throws {
        let directory = temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true)
        let store = DrawingEditorDraftStore(directory: directory)
        let vaultIdentifier = UUID()
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .svg)
        let drawingFile = try svgDrawingFile(width: 760, background: .white, strokes: Data("strokes".utf8))

        // The app returns to the foreground and the user closes the editor while the
        // background copy is still being encoded.
        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) {
            try await Task.sleep(for: .milliseconds(50))
            return drawingFile
        }
        store.removeDraft(withIdentifier: request.id)

        let drafts = await store.drafts(forVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty)
    }

    func testExistingDrawingDraftKeepsItsRevisionForConflictChecks() async throws {
        let store = DrawingEditorDraftStore(directory: temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true))
        let vaultIdentifier = UUID()
        let path = try VaultPath("Attachments/Drawing.png")
        let revision = FileRevision.of(Data("original file".utf8))
        let vaultRoot = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        let request = DrawingEditorRequest(target: .existingDrawing(path: path, location: try path.url(in: vaultRoot), revision: revision),
                                           title: "Drawing.png", initialStrokeData: Data(), canvasWidth: 900, background: .white, format: .png)
        let drawingFile = try svgDrawingFile(width: 900, background: .white, strokes: Data("edited".utf8))

        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) { drawingFile }
        let recoveredDrafts = await store.drafts(forVault: vaultIdentifier)
        let reopened = try XCTUnwrap(recoveredDrafts.first).editorRequest(inVaultAt: vaultRoot)

        guard case .existingDrawing(let reopenedPath, let location, let reopenedRevision) = reopened.target else { return XCTFail("Expected an existing drawing") }
        XCTAssertEqual(reopenedPath, path)
        XCTAssertEqual(location, try path.url(in: vaultRoot))
        XCTAssertEqual(reopenedRevision, revision)
        XCTAssertEqual(reopened.canvasWidth, 900)
    }

    func testDraftThatFailedToEncodeIsNotOffered() async throws {
        let store = DrawingEditorDraftStore(directory: temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true))
        let vaultIdentifier = UUID()
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .svg)

        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) { throw GraphiteError.oversized("Too complex") }

        let drafts = await store.drafts(forVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty)
    }

    // MARK: Vault settings

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for the settings to be saved.")
    }

    /// Each settings control used to copy the saved settings and write them in its own
    /// task, so a second change made before the first was written started from the old copy.
    func testQuickSettingsChangesBuildOnEachOther() async throws {
        let store = VaultStore(root: temporaryDirectory)
        let workspace = WorkspaceModel()
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        let initialSettings = workspace.vaultSettings
        let changes = VaultSettingsChanges()

        // Two taps on the tab size stepper: each reads the value the pages show.
        for _ in 0..<2 {
            let nextTabSize = changes.settings(of: workspace).tabSize + 1
            changes.update(workspace) { settings in settings.tabSize = nextTabSize }
        }
        // Auto pair brackets off and back on, then another toggle.
        changes.update(workspace) { settings in settings.pairsBrackets = false }
        changes.update(workspace) { settings in settings.pairsBrackets = true }
        changes.update(workspace) { settings in settings.pairsMarkdown = false }
        XCTAssertEqual(changes.settings(of: workspace).tabSize, initialSettings.tabSize + 2, "The pages show every change before it is written.")

        try await waitUntil { workspace.vaultSettings.pairsMarkdown == false }
        let savedSettings = try await store.settings()
        XCTAssertEqual(savedSettings.tabSize, initialSettings.tabSize + 2)
        XCTAssertTrue(savedSettings.pairsBrackets)
        XCTAssertFalse(savedSettings.pairsMarkdown)
        XCTAssertEqual(workspace.vaultSettings, savedSettings)
        XCTAssertEqual(changes.settings(of: workspace), savedSettings)
    }

    func testRejectedSettingsChangeShowsTheSavedSettingsAgain() async throws {
        let store = VaultStore(root: temporaryDirectory)
        let workspace = WorkspaceModel()
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        let initialSettings = workspace.vaultSettings
        let changes = VaultSettingsChanges()

        changes.update(workspace) { settings in settings.attachmentLocation = .specifiedFolder("/Attachments") }
        changes.update(workspace) { settings in settings.usesWikilinks.toggle() }

        try await waitUntil { workspace.vaultSettings.usesWikilinks != initialSettings.usesWikilinks }
        XCTAssertNotNil(workspace.errorMessage, "The rejected folder must be reported.")
        XCTAssertEqual(workspace.vaultSettings.attachmentLocation, initialSettings.attachmentLocation)
        XCTAssertEqual(changes.settings(of: workspace), workspace.vaultSettings, "The later change is saved on its own.")
        let savedSettings = try await store.settings()
        XCTAssertEqual(savedSettings.usesWikilinks, !initialSettings.usesWikilinks)
    }

    // MARK: Folders typed in Files and links

    func testTypedFolderIsWrittenAsObsidianReadsItBack() throws {
        XCTAssertEqual(SettingsFolderPath.normalizedFolder(fromTypedText: " /Inbox/ "), "Inbox", "Obsidian accepts a leading slash.")
        XCTAssertEqual(SettingsFolderPath.normalizedFolder(fromTypedText: "Course/./Week 1"), "Course/Week 1")
        XCTAssertEqual(SettingsFolderPath.normalizedFolder(fromTypedText: "./assets"), "assets")
        XCTAssertEqual(SettingsFolderPath.normalizedFolder(fromTypedText: "."), "")
        XCTAssertNil(SettingsFolderPath.normalizedFolder(fromTypedText: "../Outside"))
        XCTAssertNil(SettingsFolderPath.normalizedFolder(fromTypedText: "Notes\\Inbox"))

        // "./assets" used to be written verbatim and read back as a folder beside each note.
        let typedAttachmentFolder = try XCTUnwrap(SettingsFolderPath.normalizedFolder(fromTypedText: "./assets"))
        let attachmentLocation = AttachmentLocation.specifiedFolder(typedAttachmentFolder)
        XCTAssertEqual(AttachmentLocation(obsidianValue: attachmentLocation.obsidianValue), attachmentLocation)
        // "/Attachments" used to be rejected when saved.
        let slashedAttachmentFolder = try XCTUnwrap(SettingsFolderPath.normalizedFolder(fromTypedText: "/Attachments"))
        XCTAssertNoThrow(try VaultPath(slashedAttachmentFolder))
    }

    /// "/Inbox" used to be kept as typed, so new notes went to the vault folder until the
    /// settings were read again.
    func testNewNoteFolderTypedWithASlashGoesToThatFolderBeforeAndAfterReading() async throws {
        let store = VaultStore(root: temporaryDirectory)
        var settings = try await store.settings()
        settings.newNoteLocation = .specifiedFolder(try XCTUnwrap(SettingsFolderPath.normalizedFolder(fromTypedText: "/Inbox")))
        XCTAssertEqual(try settings.newNoteLocation.directory(currentFile: nil), try VaultPath("Inbox"))

        try await store.saveSettings(settings)
        let savedSettings = try await store.settings()
        XCTAssertEqual(savedSettings.newNoteLocation, settings.newNoteLocation)
        XCTAssertEqual(try savedSettings.newNoteLocation.directory(currentFile: nil), try VaultPath("Inbox"))
    }

    // MARK: Colors palette

    func testPaletteNamesNotesCannotUseAreExplained() {
        let red = PaletteColor(name: "red", hex: "#e93147")
        let secondRed = PaletteColor(name: "red", hex: "#ff0000")
        let spaced = PaletteColor(name: "dark red", hex: "#800000")
        let hexLooking = PaletteColor(name: "cafe", hex: "#6f4e37")
        let unnamed = PaletteColor(name: "", hex: "#888888")
        let palette = [red, secondRed, spaced, hexLooking, unnamed]

        XCTAssertNil(PaletteColorNames.problem(with: red, in: palette))
        XCTAssertNotNil(PaletteColorNames.problem(with: secondRed, in: palette), "Notes use the first color with a name.")
        XCTAssertNotNil(PaletteColorNames.problem(with: spaced, in: palette))
        XCTAssertNotNil(PaletteColorNames.problem(with: hexLooking, in: palette))
        XCTAssertNotNil(PaletteColorNames.problem(with: unnamed, in: palette))

        // The name the problems describe is the one notes resolve.
        let sections = TextColorMarkup.sections(in: "~={red}warning=~" as NSString, paletteHexByName: ["red": red.hex])
        XCTAssertEqual(sections.first?.hexColor, red.hex)
    }

    func testAddedPaletteColorGetsANameNoOtherColorHas() {
        let palette = [PaletteColor(name: "color-1", hex: "#111111"), PaletteColor(name: "color-3", hex: "#333333")]
        // After deleting "color-2", counting colors alone gave "color-3" a second time.
        XCTAssertEqual(PaletteColorNames.unusedName(in: palette), "color-4")
        XCTAssertEqual(PaletteColorNames.unusedName(in: [PaletteColor(name: "red", hex: "#e93147")]), "color-2")
    }

    // MARK: New notebooks

    /// The create sheet used to close first and let the generator reject the size, so the
    /// user's entries were lost.
    func testCustomPaperSizeProblemMatchesWhatTheGeneratorAccepts() throws {
        for sideLength in [72.0, 612, 2880] {
            XCTAssertNil(CustomPaperSize.problem(with: CGSize(width: sideLength, height: 792)))
            XCTAssertNoThrow(try PDFTemplateGenerator.documentData(paper: PaperSpecification(width: sideLength, height: 792)))
        }
        for sideLength in [71.9, 2880.1, 50, 0, -10, 100_000, .infinity, .nan] {
            XCTAssertNotNil(CustomPaperSize.problem(with: CGSize(width: 612, height: sideLength)), "\(sideLength)")
            XCTAssertThrowsError(try PDFTemplateGenerator.documentData(paper: PaperSpecification(width: 612, height: sideLength)), "\(sideLength)")
        }
    }

    // MARK: Image decoding

    func testImagePreparedForDisplayKeepsItsSizeAndRejectsOtherData() async throws {
        let image = await DecodedPlatformImage.preparedForDisplay(from: try pngData(width: 12, height: 5))
        XCTAssertEqual(image?.size, CGSize(width: 12, height: 5))
        let notAnImage = await DecodedPlatformImage.preparedForDisplay(from: Data("not an image".utf8))
        XCTAssertNil(notAnImage)
    }
}
