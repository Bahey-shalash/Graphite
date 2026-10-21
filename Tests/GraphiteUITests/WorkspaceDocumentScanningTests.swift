import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

/// Saving a document scan into a note and as a notebook, against real vault folders.
@MainActor
final class WorkspaceDocumentScanningTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var vaults: [URL] = []

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        for vault in vaults { try? FileManager.default.removeItem(at: vault) }
    }

    private static let scannedAt = Date(timeIntervalSince1970: 1_792_591_530)
    private static let scanNamePattern = #"^Scan \d{4}-\d{2}-\d{2} \d{2}\.\d{2}( \d+)?\.pdf$"#

    private func openedWorkspace(files: [String: String] = [:], folders: [String] = []) async throws -> (workspace: WorkspaceModel, vault: URL) {
        let vault = try TemporaryVault.make(prefix: "ScanVault", for: self).root
        vaults.append(vault)
        for folder in folders {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        for (path, contents) in files {
            let location = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let resolvedVault = vault.resolvingSymlinksInPath()
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(resolvedVault)
        return (workspace, resolvedVault)
    }

    private func scan(pageCount: Int, recognizer: ScannedPageWordRecognizer? = nil) async throws -> ScannedDocumentPDF {
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        let image = try XCTUnwrap(context.makeImage())
        let words = [ScannedPageWord(text: "scanned", normalizedBounds: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.05))]
        let builder = ScannedDocumentPDFBuilder(wordRecognizer: recognizer ?? ScannedPageWordRecognizer { _ in words })
        return try await builder.build(pageImages: Array(repeating: image, count: pageCount))
    }

    private func scanFileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { name in name.hasPrefix("Scan ") }.sorted()
    }

    // MARK: In a note

    func testScanInNoteIsSavedAsAPDFAttachmentAndEmbeddedAtTheCursor() async throws {
        let (workspace, vault) = try await openedWorkspace(files: ["Note.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let finishedScan = try await scan(pageCount: 2)

        await workspace.insertScannedDocument(finishedScan, scannedAt: Self.scannedAt, into: session)

        XCTAssertNil(workspace.errorMessage)
        let names = try scanFileNames(in: vault)
        XCTAssertEqual(names.count, 1)
        let name = try XCTUnwrap(names.first)
        XCTAssertNotNil(name.range(of: Self.scanNamePattern, options: .regularExpression), name)
        let savedBytes = try Data(contentsOf: vault.appendingPathComponent(name))
        XCTAssertEqual(savedBytes, finishedScan.data)
        XCTAssertEqual(PDFDocument(data: savedBytes)?.pageCount, 2)
        XCTAssertTrue(session.text.contains("![[\(name)]]"), session.text)
    }

    func testScanInNoteFollowsTheVaultsAttachmentFolder() async throws {
        let (workspace, vault) = try await openedWorkspace(files: ["Note.md": "", ".obsidian/app.json": #"{"attachmentFolderPath":"Scans"}"#])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)

        await workspace.insertScannedDocument(try await scan(pageCount: 1), scannedAt: Self.scannedAt, into: session)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try scanFileNames(in: vault), [])
        XCTAssertEqual(try scanFileNames(in: vault.appendingPathComponent("Scans")).count, 1)
    }

    func testTwoScansInTheSameMinuteKeepBothFiles() async throws {
        let (workspace, vault) = try await openedWorkspace(files: ["Note.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let finishedScan = try await scan(pageCount: 1)

        await workspace.insertScannedDocument(finishedScan, scannedAt: Self.scannedAt, into: session)
        await workspace.insertScannedDocument(finishedScan, scannedAt: Self.scannedAt, into: session)

        XCTAssertEqual(try scanFileNames(in: vault).count, 2)
    }

    func testPagesWithoutRecognizedTextAreReportedAfterTheScanIsSaved() async throws {
        struct RecognitionFailure: Error {}
        let (workspace, vault) = try await openedWorkspace(files: ["Note.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let scanWithoutText = try await scan(pageCount: 1, recognizer: ScannedPageWordRecognizer { _ in throw RecognitionFailure() })

        await workspace.insertScannedDocument(scanWithoutText, scannedAt: Self.scannedAt, into: session)

        XCTAssertEqual(try scanFileNames(in: vault).count, 1)
        XCTAssertNotNil(workspace.errorMessage)
    }

    // MARK: As a notebook

    func testScanBecomesAPDFNotebookInTheFolderAndOpens() async throws {
        let (workspace, vault) = try await openedWorkspace(folders: ["Course"])

        await workspace.createScannedNotebook(try await scan(pageCount: 3), scannedAt: Self.scannedAt, in: try VaultPath("Course"))

        XCTAssertNil(workspace.errorMessage)
        let names = try scanFileNames(in: vault.appendingPathComponent("Course"))
        XCTAssertEqual(names.count, 1)
        XCTAssertNotNil(names.first?.range(of: Self.scanNamePattern, options: .regularExpression))
        XCTAssertEqual(workspace.pdfSession?.pageCount, 3)
        XCTAssertEqual(workspace.selection?.rawValue, "Course/" + (names.first ?? ""))
    }

    func testScanWithoutAFolderGoesToTheVaultsLocationForNewFiles() async throws {
        let (workspace, vault) = try await openedWorkspace()

        await workspace.createScannedNotebook(try await scan(pageCount: 1), scannedAt: Self.scannedAt, in: nil)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try scanFileNames(in: vault).count, 1)
    }

    func testScanThatCannotBeWrittenIsReportedAndLeavesNothingBehind() async throws {
        let (workspace, vault) = try await openedWorkspace(files: ["Occupied": "a file where the folder should be"])

        await workspace.createScannedNotebook(try await scan(pageCount: 1), scannedAt: Self.scannedAt, in: try VaultPath("Occupied/Scans"))

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in !name.hasPrefix(".") }, ["Occupied"])
    }
}
