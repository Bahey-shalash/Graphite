import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteIndex
import GraphiteVoices
@testable import GraphiteUI
import GraphiteTestSupport

/// Where the app keeps its own files outside the vault. Each location is pinned by its path
/// below the platform's folder, so moving one means moving the files people already have.
@MainActor
final class ApplicationStorageLocationsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = try TemporaryVault.make(prefix: "ApplicationStorageLocationsTests", for: self).root
    }

    func testFileRecoveryCopiesAreKeptInApplicationSupportOneFolderPerVault() throws {
        let vaultIdentifier = try XCTUnwrap(UUID(uuidString: "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10"))

        let store = try FileRecoveryStore.forVault(identifier: vaultIdentifier)

        XCTAssertTrue(store.directory.path.hasSuffix("/Library/Application Support/Graphite/File Recovery/7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10"), store.directory.path)
    }

    func testAVaultsIndexIsKeptInCachesNamedAfterTheVaultIdentifier() throws {
        let vaultIdentifier = try XCTUnwrap(UUID(uuidString: "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10"))

        let location = try VaultIndex.cacheURL(forVault: vaultIdentifier, legacyRoot: URL(fileURLWithPath: "/Volumes/Vault"), in: temporaryDirectory)

        XCTAssertEqual(location.path, temporaryDirectory.appendingPathComponent("Graphite/Indexes/7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10.sqlite").path)
    }

    func testTheIndexOfEarlierVersionsIsNamedAfterTheSHA256OfTheVaultPath() throws {
        let location = try VaultIndex.cacheURL(for: URL(fileURLWithPath: "/Volumes/Vault"))

        XCTAssertTrue(location.path.hasSuffix("/Library/Caches/Graphite/Indexes/8e4ae2cf3bfae1a91fe72f94cf298b89a7e9038e8e46a621cdbcf1dbdffbe498.sqlite"), location.path)
    }

    func testResolvedThemesAreKeptInCachesUnderThemeTokens() throws {
        let folder = try XCTUnwrap(ThemeTokenResolver.cacheFolder)

        XCTAssertTrue(folder.path.hasSuffix("/Library/Caches/Graphite/ThemeTokens"), folder.path)
    }

    func testRenderedReadAloudAudioIsKeptInCachesUnderReadAloudAudio() throws {
        let folder = try ReadAloudAudioCache.defaultFolder()

        XCTAssertTrue(folder.path.hasSuffix("/Library/Caches/ReadAloudAudio"), folder.path)
    }

    func testDiagnosticRecordsAreKeptInTheLibraryFolderNamedDiagnostics() throws {
        let folder = try XCTUnwrap(DiagnosticRecords.folder)

        XCTAssertEqual(DiagnosticRecords.folderName, "Diagnostics")
        XCTAssertTrue(folder.path.hasSuffix("/Library/Diagnostics"), folder.path)
    }

    func testBaselineCopiesOfOpenPDFsAreTemporaryFilesWithTheGraphiteOpenPDFPrefix() {
        XCTAssertEqual(PDFBaselineSnapshot.filenamePrefix, "Graphite-OpenPDF-")
    }

    func testDrawingDraftsAreKeptInApplicationSupportUnderDrawingDrafts() {
        let directory = DrawingEditorDraftStore.directory(in: .system)
        XCTAssertTrue(directory.path.hasSuffix("/Library/Application Support/Drawing Drafts"), directory.path)
    }

    func testADrawingDraftIsAnSVGAndAJSONDescriptionNamedAfterTheRequestIdentifier() async throws {
        let store = DrawingEditorDraftStore(directory: temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true))
        let vaultIdentifier = UUID()
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        let drawing = VectorDrawing(size: CGSize(width: 760, height: 200), background: .white, shapes: [])
        let drawingFile = try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: 760, height: 200, background: .white, strokes: Data("pencil strokes".utf8)))

        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) { drawingFile }
        _ = await store.drafts(forVault: vaultIdentifier)

        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
        XCTAssertEqual(names, ["\(request.id.uuidString).json", "\(request.id.uuidString).svg"])
    }
}
