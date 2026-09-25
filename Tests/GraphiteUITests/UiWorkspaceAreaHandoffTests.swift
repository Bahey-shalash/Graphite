import XCTest
import Observation
import os
import PDFKit
import AVFoundation
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI
#if canImport(AppKit)
import AppKit
#endif

/// PDF session behavior that other groups' fixes asked the workspace area to complete.
@MainActor
final class UiWorkspaceAreaPDFHandoffTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceAreaPDF-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePDF(named filename: String, pageSize: CGSize = CGSize(width: 612, height: 792), pageCount: Int = 1) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func highlight(named name: String = UUID().uuidString) -> PDFMarkup {
        PDFMarkup(name: name, kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 100, y: 600, width: 200, height: 14)])
    }

    private func markupCount(onPage pageIndex: Int, ofFileAt location: URL) throws -> Int {
        let page = try XCTUnwrap(PDFDocument(url: location)?.page(at: pageIndex))
        return page.annotations.filter { annotation in PDFMarkupKind(annotationType: annotation.type) != nil }.count
    }

    /// A 300 dpi A4 scan whose pixels became points is larger than the sizes offered for new
    /// notebooks. Inserting a page used to fail with "Choose a paper size from 1 to 40 inches".
    func testInsertingPaperIntoAScanSizedPDFMatchesItsPageSize() async throws {
        let scanSize = CGSize(width: 2480, height: 3508)
        let session = try await PDFSession.open(try makePDF(named: "Scan.pdf", pageSize: scanSize))

        try await session.insertPaper(.dotted, at: 1)

        XCTAssertEqual(session.pageCount, 2)
        let insertedBounds = try XCTUnwrap(session.document.page(at: 1)).bounds(for: .cropBox)
        XCTAssertEqual(insertedBounds.width, scanSize.width, accuracy: 0.5)
        XCTAssertEqual(insertedBounds.height, scanSize.height, accuracy: 0.5)
    }

    /// Saving, exporting and page-structure changes write the ink records Pencil canvases
    /// deferred, first; until then the page's ink reads back as not editable.
    func testDeferredInkRecordsAreWrittenBeforeSavesExportsAndPageChanges() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 2)
        let session = try await PDFSession.open(location)
        let owner = NSObject()
        var writeCount = 0
        session.registerPendingInkRecordWriter(for: owner) { [unowned session] in
            writeCount += 1
            // The first request stands for a canvas's deferred record: an edit the save must include.
            if writeCount == 1 { try? session.apply(.addMarkup(page: 0, markup: self.highlight(named: "Deferred"))) }
        }

        try session.apply(.rotate(page: 1, clockwise: true))
        XCTAssertEqual(writeCount, 0, "An edit that keeps the pages in place does not need the records.")
        try await session.save()
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 1, "The record written for the save is in the saved file.")
        XCTAssertFalse(session.hasUnsavedChanges)

        try session.apply(.duplicate(page: 0))
        XCTAssertEqual(writeCount, 2)
        _ = try await session.export(pages: [0])
        XCTAssertEqual(writeCount, 3)

        session.unregisterPendingInkRecordWriter(for: owner)
        try session.apply(.duplicate(page: 0))
        XCTAssertEqual(writeCount, 3)
    }

    #if canImport(AppKit)
    private func attachView(to session: PDFSession) throws -> (window: NSWindow, undoManager: UndoManager) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        let pdfView = PDFView()
        window.contentView = pdfView
        session.pdfView = pdfView
        let undoManager = try XCTUnwrap(pdfView.undoManager)
        undoManager.groupsByEvent = false
        return (window, undoManager)
    }

    /// Undoing a color change on another app's orange highlight used to bring back the
    /// nearest palette color instead of the orange.
    func testUndoingAColorChangeRestoresTheExactColorOfAnotherAppsMarkup() async throws {
        let location = try makePDF(named: "Slides.pdf")
        let document = try XCTUnwrap(PDFDocument(url: location))
        let page = try XCTUnwrap(document.page(at: 0))
        let orangeHighlight = PDFAnnotation(bounds: CGRect(x: 100, y: 600, width: 200, height: 14), forType: .highlight, withProperties: nil)
        orangeHighlight.color = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        page.addAnnotation(orangeHighlight)
        XCTAssertTrue(document.write(to: location))

        let session = try await PDFSession.open(location)
        let (window, undoManager) = try attachView(to: session)
        let sessionPage = try XCTUnwrap(session.document.page(at: 0))
        let annotation = try XCTUnwrap(sessionPage.annotations.first { annotation in PDFMarkupKind(annotationType: annotation.type) == .highlight })
        undoManager.beginUndoGrouping()
        try session.recolorMarkup(annotation, on: sessionPage, to: .green)
        undoManager.endUndoGrouping()

        undoManager.undo()

        XCTAssertNil(session.errorMessage)
        let restoredColor = try XCTUnwrap(annotation.color.usingColorSpace(.sRGB))
        XCTAssertEqual(restoredColor.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(restoredColor.greenComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(restoredColor.blueComponent, 0, accuracy: 0.01)
        withExtendedLifetime(window) {}
    }

    /// Markup whose name an older build's page rewrite dropped is still found by its type
    /// and rectangle when a removal is redone.
    func testRedoingARemovalFindsTheMarkupAfterItsNameWasLost() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Notes.pdf"))
        let (window, undoManager) = try attachView(to: session)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try session.apply(.addMarkup(page: 0, markup: highlight(named: "Result")))
        let annotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == "Result" })
        undoManager.beginUndoGrouping()
        try session.removeMarkup(annotation, on: page)
        undoManager.endUndoGrouping()
        undoManager.undo()
        let restored = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == "Result" })
        restored.removeValue(forAnnotationKey: .name)
        restored.removeValue(forAnnotationKey: PDFPageManager.annotationNameKey)
        XCTAssertNil(restored.persistentName)

        undoManager.redo()

        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(page.annotations.contains { annotation in PDFMarkupKind(annotationType: annotation.type) != nil })
        withExtendedLifetime(window) {}
    }
    #endif
}

/// Workspace, search, recording, file management and Bases behavior that other groups'
/// fixes asked the workspace area to complete, run against real vault folders.
@MainActor
final class UiWorkspaceAreaHandoffTests: XCTestCase {
    private var temporaryFolders: [URL] = []
    private var savedGraphitePreferences: [String: Any] = [:]
    private var vaultIdentifiersBeforeTest: Set<UUID> = []

    override func setUp() async throws {
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
        vaultIdentifiersBeforeTest = Set(VaultLibrary().vaults.map(\.id))
    }

    override func tearDown() async throws {
        for vault in VaultLibrary().vaults where !vaultIdentifiersBeforeTest.contains(vault.id) {
            VaultIndex.removeIndex(forVault: vault.id)
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Graphite") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, storedValue) in savedGraphitePreferences { UserDefaults.standard.set(storedValue, forKey: key) }
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: Helpers

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder.resolvingSymlinksInPath()
    }

    private func makeVault(files: [String: String] = [:]) throws -> URL {
        let vault = try makeFolder("WorkspaceAreaVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault
    }

    /// A workspace on `vault` whose index has read it, without a vault monitor, so files
    /// changed by a test are not reloaded behind its back.
    private func indexedWorkspace(_ vault: URL, marksScanComplete: Bool = true) async throws -> WorkspaceModel {
        let indexFolder = try makeFolder("WorkspaceAreaIndex")
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.index = index
        workspace.vaultSettings = try await store.settings()
        workspace.hasCompletedIndexScan = marksScanComplete
        return workspace
    }

    private func waitUntil(timeoutSeconds: Double = 20, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("The condition did not become true in time.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func fileText(_ relativePath: String, in vault: URL) -> String? {
        (try? Data(contentsOf: vault.appendingPathComponent(relativePath))).flatMap { data in String(data: data, encoding: .utf8) }
    }

    // MARK: Search

    /// An invalid pattern used to be reported as an alert; excluded, it would list every file.
    func testInvalidRegularExpressionIsExplainedInsteadOfSearched() async throws {
        let workspace = try await indexedWorkspace(try makeVault(files: ["Note.md": "foo", "Other.md": "bar"]))
        workspace.searchResults = [SearchResult(path: try VaultPath("Stale.md"), title: "Stale", matches: [], matchCount: 0)]

        workspace.searchQuery = "-/(foo/"
        await workspace.search()

        XCTAssertEqual(workspace.searchQueryProblem, "/(foo/ is not a valid regular expression.")
        XCTAssertTrue(workspace.searchResults.isEmpty)
        XCTAssertNil(workspace.errorMessage)

        workspace.searchQuery = "foo"
        XCTAssertNil(workspace.searchQueryProblem)
        await workspace.search()
        XCTAssertEqual(workspace.searchResults.map(\.path.rawValue), ["Note.md"])
    }

    /// The sidebar cancels a search as the query changes; that used to show an error alert.
    func testCancelledSearchReportsNoError() async throws {
        let workspace = try await indexedWorkspace(try makeVault(files: ["Note.md": "foo"]))
        workspace.searchQuery = "foo"
        let search = Task { @MainActor in await workspace.search() }
        search.cancel()
        await search.value
        XCTAssertNil(workspace.errorMessage)
    }

    // MARK: Backslashes in typed folders

    func testLinkToAFolderWithABackslashCreatesNothing() async throws {
        let vault = try makeVault(files: ["Source.md": "[[A\\B/Note]]"])
        let workspace = try await indexedWorkspace(vault)

        await workspace.createNote(forLink: "A\\B/Note", from: try VaultPath("Source.md"), isWiki: true)

        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("cannot contain"), message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("A\\B").path))
    }

    func testAttachmentFolderWithABackslashIsRefused() async throws {
        let vault = try makeVault()
        let workspace = try await indexedWorkspace(vault)
        for attachmentLocation in [AttachmentLocation.specifiedFolder("Files\\Images"), .subfolderUnderNote("Files\\Images")] {
            workspace.errorMessage = nil
            var settings = workspace.vaultSettings
            settings.attachmentLocation = attachmentLocation
            await workspace.updateVaultSettings(settings)
            XCTAssertNotNil(workspace.errorMessage)
            XCTAssertNotEqual(workspace.vaultSettings.attachmentLocation, attachmentLocation)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/app.json").path))
    }

    // MARK: Settings

    /// A settings read after Obsidian changed a key refreshed the store's baseline; saving
    /// the settings screen's older copy then wrote that key back.
    func testSavingSettingsKeepsAKeyObsidianChangedMeanwhile() async throws {
        let vault = try makeVault(files: [".obsidian/app.json": "{\"useMarkdownLinks\": false}"])
        let workspace = try await indexedWorkspace(vault)
        XCTAssertTrue(workspace.vaultSettings.usesWikilinks)
        try Data("{\"useMarkdownLinks\": true}".utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))
        let store = try XCTUnwrap(workspace.store)
        _ = try await store.settings()

        var settings = workspace.vaultSettings
        settings.updatesLinksAutomatically = true
        await workspace.updateVaultSettings(settings)

        XCTAssertNil(workspace.errorMessage)
        let savedSettings = try await VaultStore(root: vault).settings()
        XCTAssertFalse(savedSettings.usesWikilinks, "Obsidian's change is kept.")
        XCTAssertTrue(savedSettings.updatesLinksAutomatically)
    }

    // MARK: Moving

    func testMovingWaitsUntilTheIndexHasReadTheVault() async throws {
        let vault = try makeVault(files: ["A.md": "a", "Linker.md": "[a](A.md)"])
        let workspace = try await indexedWorkspace(vault, marksScanComplete: false)
        workspace.vaultSettings.updatesLinksAutomatically = true

        await workspace.rename(try VaultPath("A.md"), to: "Renamed")

        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("still reading the vault"), message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("A.md").path))
        XCTAssertEqual(fileText("Linker.md", in: vault), "[a](A.md)")
    }

    /// A link typed just before a rename is saved and indexed before the links are planned.
    func testLinkTypedJustBeforeARenameIsUpdated() async throws {
        let vault = try makeVault(files: ["A.md": "a", "Linker.md": ""])
        let workspace = try await indexedWorkspace(vault)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let linkerPath = try VaultPath("Linker.md")
        await workspace.open(linkerPath)
        let session = try XCTUnwrap(workspace.openMarkdownSession(at: linkerPath))
        session.text = "[a](A.md)"

        await workspace.rename(try VaultPath("A.md"), to: "Renamed")

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(fileText("Linker.md", in: vault), "[a](Renamed.md)")
    }

    func testNotesNotUpdatedAreListedWithTheirOwnReasons() throws {
        let message = WorkspaceModel.describeNotesNotUpdated([
            try VaultPath("Large.md"): .tooLarge,
            try VaultPath("Edited.md"): .changedSincePlanning
        ], movedItemName: "Renamed.md")
        XCTAssertTrue(message.contains("2 notes"), message)
        XCTAssertTrue(message.contains("“Edited.md” (it changed elsewhere in the meantime)"), message)
        XCTAssertTrue(message.contains("“Large.md” (it is too large to update)"), message)
    }

    // MARK: Recording

    /// Half a second of a quiet tone, as AAC in M4A, the format the recorder publishes.
    private func makeRecoveryRecording() throws -> URL {
        let recordingURL = try makeFolder("WorkspaceAreaRecovery").appendingPathComponent("\(UUID().uuidString).m4a")
        let audioFile = try AVAudioFile(forWriting: recordingURL, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1
        ])
        let frameCount = AVAudioFrameCount(22_050)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frameIndex in 0..<Int(frameCount) { samples[frameIndex] = sin(Float(frameIndex) * 0.06) * 0.2 }
        try audioFile.write(from: buffer)
        audioFile.close()
        return recordingURL
    }

    /// While a failed recording waits, starting another one used to overwrite the note its
    /// embed goes into and create an attachment folder for nothing.
    func testStartingWhileAFailedRecordingWaitsChangesNothing() async throws {
        let vault = try makeVault(files: ["Lecture.md": "", ".obsidian/app.json": "{\"attachmentFolderPath\": \"Recordings\"}"])
        let workspace = try await indexedWorkspace(vault)
        let recordingURL = try makeRecoveryRecording()
        workspace.recording.adoptRecording(at: recordingURL, destination: vault.appendingPathComponent("Earlier.m4a"), state: .failed, message: "Saving failed.")
        await workspace.open(try VaultPath("Lecture.md"))

        await workspace.startRecording()

        XCTAssertNil(workspace.recordingNotePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Recordings").path))
        XCTAssertEqual(workspace.recording.recoveryURL, recordingURL)
    }

    /// Saving again used to retry the destination fixed at the start, which fails forever
    /// once its folder is renamed.
    func testSavingARecordingAgainUsesAFreshDestinationInTheVault() async throws {
        let vault = try makeVault(files: ["Lecture.m4a": "someone else's file"])
        let workspace = try await indexedWorkspace(vault)
        workspace.recording.adoptRecording(at: try makeRecoveryRecording(), destination: vault.appendingPathComponent("Renamed away/Lecture.m4a"),
                                           state: .failed, message: "Saving failed.")

        await workspace.retryRecordingPublication()

        XCTAssertEqual(workspace.recording.state, .idle, workspace.recording.message ?? "")
        let savedLocation = try XCTUnwrap(workspace.recording.lastCompletedURL)
        XCTAssertEqual(savedLocation.deletingLastPathComponent().resolvingSymlinksInPath(), vault)
        XCTAssertNotEqual(savedLocation.lastPathComponent, "Lecture.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedLocation.path))
        XCTAssertEqual(fileText("Lecture.m4a", in: vault), "someone else's file")
    }

    // MARK: Vault folder moves

    func testMovedVaultFolderIsOpenedAgainAtItsNewPlace() async throws {
        let vault = try makeVault(files: ["Note.md": "text"])
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        let movedVault = vault.deletingLastPathComponent().appendingPathComponent("Moved-\(UUID().uuidString)", isDirectory: true)
        temporaryFolders.append(movedVault)

        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: vault, options: .forMoving, writingItemAt: movedVault, options: .forReplacing, error: &coordinationError) { source, destination in
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            } catch { moveError = error }
        }
        XCTAssertNil(coordinationError)
        XCTAssertNil(moveError)

        try await waitUntil { workspace.folderAccess?.root.resolvingSymlinksInPath().path == movedVault.resolvingSymlinksInPath().path }
        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(workspace.rootEntries.contains { entry in entry.path.rawValue == "Note.md" })
    }

    func testDeletedVaultFolderAsksToOpenItAgain() async throws {
        let workspace = try await indexedWorkspace(try makeVault())
        await workspace.vaultFolderDidMove(to: nil)
        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("moved or deleted"), message)
    }

    // MARK: Images

    /// The image pane gets decoded pixels, not PNG data to decode again, and answers an
    /// ordinary photo's editability from its chunk headers.
    func testImagePaneShowsAnOrdinaryPNGDecodedWithoutEditing() async throws {
        let vault = try makeVault()
        let location = vault.appendingPathComponent("Photo.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 3_000, height: 1_000, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 1_000))
        try ImageEncoding.pngData(from: XCTUnwrap(context.makeImage())).write(to: location)

        let reading = try XCTUnwrap(DrawingMetadataReader.readMetadata(at: location))
        XCTAssertNil(reading.payload)
        XCTAssertFalse(reading.metadataWasDiscarded)

        let content = await ImagePaneContent.load(from: location, fileExtension: "png")
        let image = try XCTUnwrap(content.image)
        XCTAssertEqual(image.width, ImagePaneContent.maximumPixelDimension)
        XCTAssertFalse(content.hasEditableStrokes)
        XCTAssertNil(content.message)
        XCTAssertEqual(content.fileVersion, ImageFileVersion.of(location))
    }

    // MARK: Bases

    /// Partly read filters were offered for editing, and saving them dropped the rest.
    func testPartlyReadFiltersAreNotOfferedForEditing() throws {
        let definition = try BaseDefinition.parse("""
        views:
          - type: table
            name: Mixed
            filters:
              and:
                - 'status == "done"'
              or:
                - 'status == "open"'
          - type: table
            name: Plain
            filters:
              and:
                - 'status == "done"'
        """)
        let mixedView = try XCTUnwrap(definition.views.first { view in view.name == "Mixed" })
        XCTAssertTrue(mixedView.hasUnreadableFilters)
        XCTAssertNil(BaseViewDraft(view: mixedView).filterExpressions)
        let plainView = try XCTUnwrap(definition.views.first { view in view.name == "Plain" })
        XCTAssertEqual(BaseViewDraft(view: plainView).filterExpressions, ["status == \"done\""])
    }

    /// A lookup the database failed used to read as a missing link, and the base showed
    /// values computed from it.
    func testADatabaseErrorDuringABaseQueryIsReported() async throws {
        let vault = try makeVault(files: [
            "Note.md": "text",
            "Links.base": "formulas:\n  target: 'link(\"Missing\").asFile()'\nviews:\n  - type: table\n    name: Table\n    order:\n      - file.name\n      - formula.target\n"
        ])
        let indexFolder = try makeFolder("WorkspaceAreaBaseIndex")
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        try await index.databaseQueue.write { database in try database.execute(sql: "DROP TABLE aliases") }
        let path = try VaultPath("Links.base")
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: VaultStore(root: vault), index: index)

        await model.reload()
        try await waitUntil { !model.isLoading }

        XCTAssertNotNil(model.actionErrorMessage)
    }
}

// MARK: Bases opened and edited from the workspace

extension UiWorkspaceAreaHandoffTests {
    private static let galleryBaseYAML = "views:\n  - type: table\n    name: Table\n  - type: cards\n    name: Gallery\n"

    /// A property set from a base is saved by Graphite's own coordinated write, which sends
    /// no change notice; an open tab of that note kept its old text and its next save conflicted.
    func testAnOpenNoteAdoptsAPropertySetFromABase() async throws {
        let vault = try makeVault(files: ["Note.md": "---\nstatus: draft\n---\nBody\n", "Home.md": "Home"])
        let workspace = try await indexedWorkspace(vault)
        let notePath = try VaultPath("Note.md")
        await workspace.open(notePath)
        let session = try XCTUnwrap(workspace.markdownSession)
        let model = BaseDocumentModel(source: .inline(Self.galleryBaseYAML), contextPath: try VaultPath("Home.md"),
                                      store: try XCTUnwrap(workspace.store), index: try XCTUnwrap(workspace.index),
                                      didSaveFile: { [weak workspace] path in workspace?.filesSavedOutsideEditors([path]) })

        let didSave = await model.setProperty(.note("status"), of: notePath, to: .text("done"))

        XCTAssertTrue(didSave)
        try await waitUntil { session.text.contains("status: done") }
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    /// `[[Books.base#Gallery]]` used to open the base on its first view.
    func testABaseLinkWithAViewNameOpensThatView() async throws {
        let vault = try makeVault(files: ["Books.base": Self.galleryBaseYAML, "Note.md": "[[Books.base#Gallery]]"])
        let workspace = try await indexedWorkspace(vault)
        let basePath = try VaultPath("Books.base"), notePath = try VaultPath("Note.md")
        await workspace.open(notePath)

        await workspace.follow("Books.base#Gallery", from: notePath)

        XCTAssertEqual(workspace.selection, basePath)
        let tabID = workspace.layout.activeTab.id
        XCTAssertEqual(workspace.document(for: tabID).baseViewRequest, BaseViewRequest(path: basePath, viewName: "Gallery"))

        await workspace.follow("Books.base", from: notePath)
        XCTAssertNil(workspace.document(for: tabID).baseViewRequest, "A link without a view name shows the first view.")
    }

    /// An embedded base's Open Base passes its view's name, which was dropped, and bases
    /// scrolled out of a note lost their results because no model cache reached them.
    func testEmbeddedBasesOpenTheirViewAndKeepTheirModels() async throws {
        let vault = try makeVault(files: ["Books.base": Self.galleryBaseYAML, "Note.md": "![[Books.base#Gallery]]"])
        let workspace = try await indexedWorkspace(vault)
        let basePath = try VaultPath("Books.base")
        let context = try XCTUnwrap(workspace.baseEmbedContext(for: try VaultPath("Note.md")))
        XCTAssertTrue(context.modelCache === workspace.embeddedBaseModelCache)
        let openBase = try XCTUnwrap(context.openBase)

        openBase(basePath, "Gallery")

        try await waitUntil { workspace.selection == basePath }
        XCTAssertEqual(workspace.document(for: workspace.layout.activeTab.id).baseViewRequest, BaseViewRequest(path: basePath, viewName: "Gallery"))
    }

    /// The cell editor keeps links, embeds and dates as written only when it is given the
    /// property's text from the note, which a base value cannot carry.
    func testThePropertyEditorIsGivenThePropertyAsWritten() async throws {
        let vault = try makeVault(files: [
            "Note.md": "---\ncover: \"![[cover.png]]\"\nSite: \"[Home](https://example.org)\"\n---\nBody\n",
            "Plain.md": "No properties"
        ])
        let workspace = try await indexedWorkspace(vault)
        let notePath = try VaultPath("Note.md")
        let model = BaseDocumentModel(source: .inline(Self.galleryBaseYAML), contextPath: try VaultPath("Plain.md"),
                                      store: try XCTUnwrap(workspace.store), index: try XCTUnwrap(workspace.index))

        let coverNode = await model.writtenPropertyNode(.note("cover"), of: notePath)
        XCTAssertEqual(coverNode, .scalar(text: "![[cover.png]]", isPlain: false))
        let siteNode = await model.writtenPropertyNode(.note("site"), of: notePath)
        XCTAssertEqual(siteNode, .scalar(text: "[Home](https://example.org)", isPlain: false), "Found as settingProperty finds it, ignoring case.")
        let missingNode = await model.writtenPropertyNode(.note("status"), of: notePath)
        XCTAssertNil(missingNode)
        let plainNode = await model.writtenPropertyNode(.note("cover"), of: try VaultPath("Plain.md"))
        XCTAssertNil(plainNode)
    }
}

// MARK: Tabs, PDFs and the sidebar

extension UiWorkspaceAreaHandoffTests {
    /// A load that failed for any reason, such as a read error, erased a valid history entry.
    func testGoingBackToAFileThatCannotBeReadKeepsItsHistoryEntry() async throws {
        let vault = try makeVault(files: ["A.md": "first", "B.md": "second"])
        let workspace = try await indexedWorkspace(vault)
        let firstPath = try VaultPath("A.md"), secondPath = try VaultPath("B.md")
        await workspace.open(firstPath)
        await workspace.open(secondPath)
        let firstLocation = vault.appendingPathComponent("A.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: firstLocation.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: firstLocation.path) }

        await workspace.goBack()

        XCTAssertEqual(workspace.selection, secondPath)
        XCTAssertTrue(workspace.history.canGoBack, "The file is still there, so its entry is kept.")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: firstLocation.path)
        workspace.errorMessage = nil
        await workspace.goBack()
        XCTAssertEqual(workspace.selection, firstPath)

        await workspace.goForward()
        XCTAssertEqual(workspace.selection, secondPath)
        try FileManager.default.removeItem(at: firstLocation)
        await workspace.goBack()
        XCTAssertEqual(workspace.selection, secondPath)
        XCTAssertFalse(workspace.history.canGoBack, "An entry whose file is gone is dropped.")
    }

    /// A tab's PDF saves through the vault's presenter-aware writer, so its own saves, and
    /// a separate copy saved beside it, reach the index only through `didSave`.
    func testATabsPDFReportsTheFilesItSavesToTheIndex() async throws {
        let vault = try makeVault(files: ["Note.md": "text"])
        let pdfLocation = vault.appendingPathComponent("Slides.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(pdfLocation as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        let workspace = try await indexedWorkspace(vault)
        await workspace.open(try VaultPath("Slides.pdf"))
        let session = try XCTUnwrap(workspace.pdfSession)
        let didSave = try XCTUnwrap(session.didSave)
        let index = try XCTUnwrap(workspace.index)

        let copyLocation = vault.appendingPathComponent("Slides copy.pdf")
        try FileManager.default.copyItem(at: pdfLocation, to: copyLocation)
        didSave(copyLocation)

        let deadline = Date.now.addingTimeInterval(20)
        while try await index.fileCount(named: "Slides copy.pdf") == 0 {
            guard Date.now < deadline else { return XCTFail("The saved copy was not indexed.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A text view taking focus activates its tab; for the tab that already had focus this
    /// still rewrote `layout` and redrew every view that reads it.
    func testActivatingTheFocusedTabLeavesLayoutObserversAlone() async throws {
        let vault = try makeVault(files: ["A.md": "first", "B.md": "second"])
        let workspace = try await indexedWorkspace(vault)
        let firstTabIDResult = await workspace.open(try VaultPath("A.md"))
        let firstTabID = try XCTUnwrap(firstTabIDResult)
        let secondTabIDResult = await workspace.open(try VaultPath("B.md"), placement: .otherGroup)
        let secondTabID = try XCTUnwrap(secondTabIDResult)
        XCTAssertEqual(workspace.layout.activeTab.id, secondTabID)

        let layoutChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = workspace.layout
        } onChange: {
            layoutChanged.withLock { changed in changed = true }
        }
        workspace.activateTab(secondTabID)
        XCTAssertFalse(layoutChanged.withLock { changed in changed })

        workspace.activateTab(firstTabID)
        XCTAssertTrue(layoutChanged.withLock { changed in changed }, "The other side's tab still takes focus.")
        XCTAssertEqual(workspace.layout.activeTab.id, firstTabID)
        XCTAssertEqual(workspace.selection, try VaultPath("A.md"))
    }

    /// Search in all files from the palette or ⇧⌘F only asked for focus; with the sidebar
    /// hidden, nothing appeared.
    func testShowingSearchRevealsAHiddenSidebar() {
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(revealing: .detailOnly, automaticHidesSidebar: false), .all)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(revealing: .automatic, automaticHidesSidebar: true), .all)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(revealing: .automatic, automaticHidesSidebar: false), .automatic)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(revealing: .all, automaticHidesSidebar: true), .all)
    }
}
