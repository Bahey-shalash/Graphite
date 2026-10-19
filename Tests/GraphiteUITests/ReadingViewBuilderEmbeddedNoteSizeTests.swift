import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// A note embedded in another is shown in full up to 1,048,576 bytes; a larger one is shown
/// as a link to it, so one huge note cannot freeze the reading view.
@MainActor
final class ReadingViewBuilderEmbeddedNoteSizeTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddedSizeVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func embeddedBodies(ofNoteWithBytes byteCount: Int) async throws -> (transclusionBodies: Int, bodyCharacterCount: Int) {
        try Data(String(repeating: "x", count: byteCount).utf8).write(to: vault.appendingPathComponent("Log.md"))
        let build = try await ReadingViewBuilder().build(source: "![[Log]]\n", note: try VaultPath("Note.md"), root: vault, index: index, configuration: ReadingConfiguration())
        var bodyCount = 0
        var characterCount = 0
        for block in build.blocks {
            if case .transclusion(_, _, _, let body) = block {
                bodyCount += 1
                for case .markdown(_, let text) in body { characterCount += text.count }
            }
        }
        return (bodyCount, characterCount)
    }

    func testANoteOfExactlyTheLimitIsEmbeddedInFull() async throws {
        let embedded = try await embeddedBodies(ofNoteWithBytes: NotePreviewDocument.maximumEmbeddedNoteBytes)
        XCTAssertEqual(embedded.transclusionBodies, 1)
        XCTAssertGreaterThanOrEqual(embedded.bodyCharacterCount, NotePreviewDocument.maximumEmbeddedNoteBytes, "All of the note's text is shown.")
    }

    func testANoteOneByteOverTheLimitIsNotEmbedded() async throws {
        let embedded = try await embeddedBodies(ofNoteWithBytes: NotePreviewDocument.maximumEmbeddedNoteBytes + 1)
        XCTAssertEqual(embedded.transclusionBodies, 0)
    }
}
