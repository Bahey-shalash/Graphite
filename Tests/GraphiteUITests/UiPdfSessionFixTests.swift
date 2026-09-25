import XCTest
import PDFKit
import Observation
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
#if canImport(AppKit)
import AppKit
#endif

/// Records whether an observation fired; the change handler may run on any thread.
private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false
    func fire() { lock.withLock { hasFired = true } }
    var didFire: Bool { lock.withLock { hasFired } }
}

@MainActor
final class UiPdfSessionFixTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFSessionFix-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    private func makePDF(named filename: String, pageCount: Int, auxiliaryInfo: [CFString: Any] = [:]) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInfo as CFDictionary))
        for pageNumber in 1...pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: 40, width: 20 * pageNumber, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    /// A minimal one-page PDF with the given form. Objects 4 and later are `additionalObjects`.
    private func makeFormPDF(named filename: String, form: String, additionalObjects: [String] = []) throws -> URL {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm \(form) >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"
        ] + additionalObjects
        var fileText = "%PDF-1.7\n"
        var objectOffsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            objectOffsets.append(fileText.utf8.count)
            fileText += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = fileText.utf8.count
        fileText += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for objectOffset in objectOffsets { fileText += String(format: "%010d 00000 n \n", objectOffset) }
        fileText += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        let location = directory.appendingPathComponent(filename)
        try Data(fileText.utf8).write(to: location)
        return location
    }

    private func highlight(named name: String = UUID().uuidString) -> PDFMarkup {
        PDFMarkup(name: name, kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 100, y: 600, width: 200, height: 14)])
    }

    private func markupCount(onPage pageIndex: Int, ofFileAt location: URL) throws -> Int {
        let savedDocument = try XCTUnwrap(PDFDocument(url: location))
        let page = try XCTUnwrap(savedDocument.page(at: pageIndex))
        return page.annotations.filter { annotation in PDFMarkupKind(annotationType: annotation.type) != nil }.count
    }

    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: Saving (baseline replay, merging, overlapping saves, conflicts, failures)

    func testLaterSavesReplayOnlyEditsMadeSinceTheLastSave() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 2)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try await session.save()
        try session.apply(.addMarkup(page: 1, markup: highlight()))
        try await session.save()

        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 1, "The first edit must not be replayed twice.")
        XCTAssertEqual(try markupCount(onPage: 1, ofFileAt: location), 1)
    }

    func testOverlappingSavesWithEditsInBetweenKeepEveryEdit() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 3)
        let session = try await PDFSession.open(location)
        for pageIndex in 0..<3 {
            try session.apply(.addMarkup(page: pageIndex, markup: highlight()))
            let overlappingSaves = (0..<3).map { _ in Task { @MainActor in try await session.save() } }
            await Task.yield()
            try session.apply(.addMarkup(page: pageIndex, markup: highlight()))
            for overlappingSave in overlappingSaves { try await overlappingSave.value }
        }
        try await session.save()

        XCTAssertFalse(session.isSaving)
        XCTAssertFalse(session.hasUnsavedChanges)
        for pageIndex in 0..<3 { XCTAssertEqual(try markupCount(onPage: pageIndex, ofFileAt: location), 2) }
    }

    func testInkStrokesAddedWhileASaveRunsAreNotMergedIntoTheSavedEdit() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        func stroke(named name: String, atHeight height: Double) -> PortableInkStroke {
            PortableInkStroke(name: name, segments: [[CGPoint(x: 100, y: height), CGPoint(x: 300, y: height)]],
                              width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        }
        func update(adding addedStroke: PortableInkStroke) -> PDFInkUpdate {
            PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [addedStroke], editableRecord: nil)
        }
        try session.apply(.updateInk(update(adding: stroke(named: "first", atHeight: 500))))
        try session.apply(.updateInk(update(adding: stroke(named: "second", atHeight: 450))))
        let runningSave = Task { @MainActor in try await session.save() }
        for _ in 0..<5 { await Task.yield() }
        try session.apply(.updateInk(update(adding: stroke(named: "third", atHeight: 400))))
        try await runningSave.value
        try await session.save()

        let savedPage = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        let savedNames = Set(savedPage.annotations.compactMap(\.persistentName))
        XCTAssertEqual(savedNames, ["first", "second", "third"])
    }

    func testAnExternalChangeUnderUnsavedEditsIsAConflict() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        let changedBeforeExternalWrite = try await session.hasChangedExternally()
        XCTAssertFalse(changedBeforeExternalWrite)

        _ = try makePDF(named: "Notes.pdf", pageCount: 2)
        try session.apply(.addMarkup(page: 0, markup: highlight()))

        let changedAfterExternalWrite = try await session.hasChangedExternally()
        XCTAssertTrue(changedAfterExternalWrite)
        XCTAssertTrue(session.hasExternalConflict)
        do {
            try await session.save()
            XCTFail("Saving over another app's change must fail.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(PDFDocument(url: location)?.pageCount, 2, "The other app's version is kept.")
    }

    func testOwnSaveIsNotAnExternalChange() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try await session.save()
        let changedAfterOwnSave = try await session.hasChangedExternally()
        XCTAssertFalse(changedAfterOwnSave)
        XCTAssertFalse(session.hasExternalConflict)
    }

    /// A check made while another app writes the PDF waits for that write, so it never
    /// hashes a partly written file and reports a change that is not there.
    func testExternalChangeCheckWaitsForAWriteInProgress() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        let originalData = try Data(contentsOf: location)
        let writeStarted = ObservationFlag()
        let writeFinished = ObservationFlag()
        Thread.detachNewThread {
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: location, options: [], error: &coordinationError) { coordinatedLocation in
                try? Data("%PDF-1.7 partly written".utf8).write(to: coordinatedLocation)
                writeStarted.fire()
                Thread.sleep(forTimeInterval: 0.5)
                try? originalData.write(to: coordinatedLocation)
            }
            writeFinished.fire()
        }
        let didStartWriting = try await waitUntil(timeout: .seconds(5)) { writeStarted.didFire }
        XCTAssertTrue(didStartWriting)

        let changed = try await session.hasChangedExternally()

        XCTAssertTrue(writeFinished.didFire, "The check must wait for the coordinated write.")
        XCTAssertFalse(changed, "The write restored the original bytes, so nothing changed.")
        XCTAssertFalse(session.hasExternalConflict)
    }

    /// A save that fails for another reason than a conflict keeps the edits, and the pane
    /// offers a copy or discarding them, so the tab can still be left.
    func testFailedSaveKeepsTheEditsAndIsReportedUntilASaveSucceeds() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        do {
            try await session.save()
            XCTFail("The folder is read-only, so the save must fail.")
        } catch {
            XCTAssertNotEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertTrue(session.hasFailedSave)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertFalse(session.hasExternalConflict)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try await session.save()
        XCTAssertFalse(session.hasFailedSave)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 1)
    }

    func testFailedAutosaveIsRetriedWithoutAnotherEdit() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        try session.apply(.addMarkup(page: 0, markup: highlight()))

        let didFail = try await waitUntil(timeout: .seconds(10)) { session.hasFailedSave }
        XCTAssertTrue(didFail, "The first autosave should have run and failed.")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let didSave = try await waitUntil(timeout: .seconds(15)) { !session.hasUnsavedChanges }
        XCTAssertTrue(didSave, "The retry should save the edit.")
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 1)
    }

    func testAutosaveWaitsLongerAfterSlowSavesAndAfterFailures() {
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .milliseconds(50), consecutiveFailures: 0), .seconds(2))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .milliseconds(800), consecutiveFailures: 0), .seconds(8))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(7), consecutiveFailures: 0), .seconds(30))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .zero, consecutiveFailures: 1), .seconds(4))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .zero, consecutiveFailures: 3), .seconds(16))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .zero, consecutiveFailures: 40), .seconds(60))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(7), consecutiveFailures: 1), .seconds(30))
    }

    /// Saves coordinate with the vault's file presenter, so they do not come back as
    /// external changes that hash the whole PDF and refresh the vault again.
    func testSavesThroughTheVaultWriterAreNotReportedToTheVaultPresenter() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let reportedChanges = ObservationFlag()
        let monitor = VaultMonitor(root: directory) { changedLocation in
            if changedLocation?.lastPathComponent == "Notes.pdf" { reportedChanges.fire() }
        }
        defer { monitor.stop() }
        let session = try await PDFSession.open(location, writer: AtomicFileWriter(filePresenter: monitor))
        var savedLocations: [URL] = []
        session.didSave = { savedLocation in savedLocations.append(savedLocation) }

        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try await session.save()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(reportedChanges.didFire)
        XCTAssertEqual(savedLocations, [location])

        // The monitor does report a write made without it.
        _ = try AtomicFileWriter().write(Data(contentsOf: location), to: location, expecting: .revision(FileRevision.read(location)))
        let didReportOtherWrite = try await waitUntil(timeout: .seconds(5)) { reportedChanges.didFire }
        XCTAssertTrue(didReportOtherWrite)
    }

    // MARK: Protected and signed PDFs

    func testPermissionRestrictedPDFIsShownWithoutChanges() async throws {
        let restrictedPermissions = CGPDFAccessPermissions([.allowsLowQualityPrinting, .allowsHighQualityPrinting, .allowsContentCopying])
        let location = try makePDF(named: "Slides.pdf", pageCount: 2, auxiliaryInfo: [
            kCGPDFContextOwnerPassword: "owner",
            kCGPDFContextUserPassword: "",
            kCGPDFContextAccessPermissions: restrictedPermissions.rawValue
        ])
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.isPasswordProtected)
        XCTAssertTrue(session.isProtected)
        XCTAssertThrowsError(try session.apply(.addMarkup(page: 0, markup: highlight())))
        XCTAssertThrowsError(try session.apply(.rotate(page: 0, clockwise: true)))
        XCTAssertFalse(session.hasUnsavedChanges, "A refused edit must not be recorded as unsaved work.")
    }

    /// A minimal PDF whose form says its signatures break unless changes are appended (`/SigFlags 3`).
    private func makeSignedPDF(named filename: String) throws -> URL {
        try makeFormPDF(named: filename, form: "<< /Fields [] /SigFlags 3 >>")
    }

    func testSignedPDFIsShownWithoutChangesUntilTheUserAcceptsInvalidatingTheSignature() async throws {
        let signedLocation = try makeSignedPDF(named: "Contract.pdf")
        XCTAssertTrue(PDFSignatureDetection.hasDigitalSignatures(at: signedLocation))
        XCTAssertFalse(PDFSignatureDetection.hasDigitalSignatures(at: try makePDF(named: "Plain.pdf", pageCount: 1)))

        let session = try await PDFSession.open(signedLocation)
        XCTAssertTrue(session.hasDigitalSignatures)
        XCTAssertFalse(session.isPasswordProtected)
        XCTAssertTrue(session.isProtected)
        XCTAssertThrowsError(try session.apply(.addMarkup(page: 0, markup: highlight())))
        XCTAssertFalse(session.hasUnsavedChanges)

        session.acceptsSignatureInvalidation = true
        XCTAssertFalse(session.isProtected)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    /// A form with an empty signature field is waiting to be signed, and stays editable.
    /// A field whose type comes from its parent and that has a value has been signed.
    func testOnlySignedSignatureFieldsCountAsSignatures() throws {
        let blankFormLocation = try makeFormPDF(named: "Blank form.pdf", form: "<< /Fields [4 0 R] /SigFlags 1 >>",
                                                additionalObjects: ["<< /FT /Sig /T (Signature) >>"])
        XCTAssertFalse(PDFSignatureDetection.hasDigitalSignatures(at: blankFormLocation))

        let signedFormLocation = try makeFormPDF(named: "Signed form.pdf", form: "<< /Fields [4 0 R] /SigFlags 1 >>", additionalObjects: [
            "<< /FT /Sig /T (Signatures) /Kids [5 0 R] >>",
            "<< /Parent 4 0 R /T (Buyer) /V 6 0 R >>",
            "<< /Type /Sig /Filter /Adobe.PPKLite /Contents <00> >>"
        ])
        XCTAssertTrue(PDFSignatureDetection.hasDigitalSignatures(at: signedFormLocation))

        let plainFormLocation = try makeFormPDF(named: "Plain form.pdf", form: "<< /Fields [] >>")
        XCTAssertFalse(PDFSignatureDetection.hasDigitalSignatures(at: plainFormLocation))
    }

    // MARK: Temporary baselines

    func testBaselinesOfEndedProcessesAreRemovedAndThoseOfRunningOnesKept() throws {
        let prefix = PDFBaselineSnapshot.filenamePrefix
        let runningProcessCopy = "\(prefix)\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).pdf"
        let endedProcessCopy = "\(prefix)99999999-\(UUID().uuidString).pdf"
        // Named before copies carried a process identifier; its UUID starts with a letter.
        let unnamedProcessCopy = "\(prefix)E621E1F8-C36C-495A-93FC-0C247A3E6E5F.pdf"
        let unrelatedFile = "Lecture.pdf"
        for filename in [runningProcessCopy, endedProcessCopy, unnamedProcessCopy, unrelatedFile] {
            try Data("%PDF".utf8).write(to: directory.appendingPathComponent(filename))
        }

        PDFBaselineSnapshot.removeStaleBaselines(in: directory)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(remaining, [runningProcessCopy, unrelatedFile])
    }

    func testNewBaselinesNameTheirProcess() {
        let filename = PDFBaselineSnapshot.makeLocation().lastPathComponent
        XCTAssertTrue(filename.hasPrefix("\(PDFBaselineSnapshot.filenamePrefix)\(ProcessInfo.processInfo.processIdentifier)-"))
    }

    // MARK: Importing

    func testImportingAnOversizedPDFIsRefusedBeforeReadingIt() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        let oversizedLocation = directory.appendingPathComponent("Huge.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversizedLocation.path, contents: nil))
        // A sparse file: its size is over the limit without writing the bytes.
        let handle = try FileHandle(forWritingTo: oversizedLocation)
        try handle.truncate(atOffset: UInt64(PDFSession.maximumImportedPDFBytes) + 1)
        try handle.close()

        do {
            try await session.importPages(from: oversizedLocation, at: 1)
            XCTFail("An import over the limit must be refused.")
        } catch {
            guard case .oversized = error as? GraphiteError else { return XCTFail("Unexpected error \(error)") }
        }
        XCTAssertEqual(session.pageCount, 1)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    // MARK: Markup undo after page changes

    #if canImport(AppKit)
    func testUndoingARemovedHighlightRestoresItOnItsPageAfterAPageIsInsertedBefore() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 3)
        let insertedPageData = try Data(contentsOf: try makePDF(named: "Paper.pdf", pageCount: 1))
        let session = try await PDFSession.open(location)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        let pdfView = PDFView()
        window.contentView = pdfView
        session.pdfView = pdfView
        let undoManager = try XCTUnwrap(pdfView.undoManager)
        undoManager.groupsByEvent = false

        let highlightedPage = try XCTUnwrap(session.document.page(at: 2))
        try session.apply(.addMarkup(page: 2, markup: highlight(named: "Result")))
        let annotation = try XCTUnwrap(highlightedPage.annotations.first { annotation in annotation.persistentName == "Result" })
        undoManager.beginUndoGrouping()
        try session.removeMarkup(annotation, on: highlightedPage)
        undoManager.endUndoGrouping()
        try session.apply(.insert(data: insertedPageData, at: 0))
        XCTAssertEqual(session.document.index(for: highlightedPage), 3)

        undoManager.undo()

        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(highlightedPage.annotations.contains { annotation in annotation.persistentName == "Result" })
        let pageNowAtOldIndex = try XCTUnwrap(session.document.page(at: 2))
        XCTAssertFalse(pageNowAtOldIndex.annotations.contains { annotation in annotation.persistentName == "Result" })

        // Redo removes it from the same page, wherever it is now.
        try session.movePage(from: 3, to: 0)
        undoManager.redo()
        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(highlightedPage.annotations.contains { annotation in annotation.persistentName == "Result" })
        withExtendedLifetime(window) {}
    }
    #endif

    // MARK: Observation

    /// A stroke changes one page. Rows showing other pages, the page count, and the current
    /// page must not be invalidated by it.
    func testChangingOnePageDoesNotNotifyObserversOfOtherPages() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 3)
        let session = try await PDFSession.open(location)
        let observedPage = try XCTUnwrap(session.document.page(at: 0))
        let otherPageChange = ObservationFlag()
        withObservationTracking {
            _ = session.appearanceVersion(of: observedPage)
            _ = session.pageCount
            _ = session.currentPageIndex
        } onChange: { otherPageChange.fire() }
        try session.apply(.rotate(page: 1, clockwise: true))
        XCTAssertFalse(otherPageChange.didFire)

        let samePageChange = ObservationFlag()
        withObservationTracking { _ = session.appearanceVersion(of: observedPage) } onChange: { samePageChange.fire() }
        try session.apply(.rotate(page: 0, clockwise: true))
        XCTAssertTrue(samePageChange.didFire)
        XCTAssertEqual(session.appearanceVersion(of: observedPage), 1)
    }

    // MARK: Sidebar selection, bookmarks, drags

    func testSelectionFollowsItsPagesThroughDuplicationAndDeletion() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 5)
        let session = try await PDFSession.open(location)
        let document = session.document
        var selection = PDFPageSelection()
        selection.toggle(try XCTUnwrap(document.page(at: 1)))
        selection.toggle(try XCTUnwrap(document.page(at: 3)))

        for pageIndex in selection.pageIndices(in: document).sorted(by: >) { try session.apply(.duplicate(page: pageIndex)) }
        // A B B' C D D' E: the selected pages B and D are now at 1 and 4.
        XCTAssertEqual(selection.pageIndices(in: document), [1, 4])

        try session.apply(.delete(pages: selection.pageIndices(in: document)))
        selection.removePages(notIn: document)
        XCTAssertEqual(selection.pageIndices(in: document), [])

        let pageToToggle = try XCTUnwrap(document.page(at: 0))
        selection.toggle(pageToToggle)
        XCTAssertTrue(selection.contains(pageToToggle))
        selection.toggle(pageToToggle)
        XCTAssertFalse(selection.contains(pageToToggle))
    }

    func testOnlyEntriesLabeledLikeGraphiteBookmarksAreBookmarks() async throws {
        XCTAssertFalse(PDFOutlineEntry(path: [0], label: "Results", pageIndex: 4, hasChildren: false).isBookmark)
        XCTAssertTrue(PDFOutlineEntry(path: [0], label: "Page 5", pageIndex: 4, hasChildren: false).isBookmark)
        XCTAssertFalse(PDFOutlineEntry(path: [0, 1], label: "Page 5", pageIndex: 4, hasChildren: false).isBookmark)

        let location = try makePDF(named: "Notes.pdf", pageCount: 3)
        let session = try await PDFSession.open(location)
        try session.addBookmark(pageIndex: 2)
        XCTAssertEqual(session.bookmarkedPageIndices, [2])
    }

    func testPageDragsUseGraphitesOwnType() {
        XCTAssertEqual(UTType.graphitePDFPage.identifier, "com.graphite.study.pdf-page")
        XCTAssertFalse(UTType.graphitePDFPage.conforms(to: .pdf), "Other apps must not receive the payload as a PDF.")
        XCTAssertNotEqual(UTType.graphitePDFPage, .data)
    }

    // MARK: Page field and export names

    func testPageNumberAcceptsDecimalDigitsOfAnyScript() {
        XCTAssertEqual(PDFPageJumpField.pageNumber(from: "12", pageCount: 20), 12)
        XCTAssertEqual(PDFPageJumpField.pageNumber(from: " 3 ", pageCount: 20), 3)
        XCTAssertEqual(PDFPageJumpField.pageNumber(from: "٣", pageCount: 20), 3)
        XCTAssertEqual(PDFPageJumpField.pageNumber(from: "۵", pageCount: 20), 5)
        XCTAssertEqual(PDFPageJumpField.pageNumber(from: "１２", pageCount: 20), 12)
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "21", pageCount: 20))
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "0", pageCount: 20))
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "", pageCount: 20))
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "-2", pageCount: 20))
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "½", pageCount: 20))
        XCTAssertNil(PDFPageJumpField.pageNumber(from: "99999999999999999999999", pageCount: 20))
    }

    func testExportNamesDescribeTheSelectedPages() {
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [4]), "Notes page 5")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 1, 2]), "Notes pages 1-3")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 2, 9]), "Notes pages 1, 3, 10")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 1, 2, 6, 7]), "Notes pages 1-3, 7-8")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: Array(stride(from: 0, to: 60, by: 2))), "Notes 30 pages")
    }
}
