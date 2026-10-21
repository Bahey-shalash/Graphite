import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The files the drawing editor keeps for a drawing still open: where they are, what the
/// description holds for each target, how large a description may be, and the order the
/// store writes and removes in. The description is the synthesized `Codable` of
/// `DrawingEditorDraft`, so its enum cases and labels are the format.
@MainActor
final class DrawingEditorDraftStorePersistedFormatTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var draftDirectory: URL!
    private let vaultIdentifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let requestIdentifier = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    override func setUpWithError() throws {
        temporaryDirectory = try TemporaryVault.make(prefix: "DrawingEditorDraftStorePersistedFormatTests", for: self).root
        draftDirectory = temporaryDirectory.appendingPathComponent("Drawing Drafts", isDirectory: true)
    }

    private func draft(_ target: DrawingEditorRequest.Target, title: String = "Drawing") -> DrawingEditorDraft {
        let request = DrawingEditorRequest(id: requestIdentifier, target: target, title: title, initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .svg)
        return DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)
    }

    private func descriptionObject(of draft: DrawingEditorDraft) async throws -> NSDictionary {
        let store = DrawingEditorDraftStore(directory: draftDirectory)
        store.preserve(draft) { Data("<svg/>".utf8) }
        _ = await store.drafts(forVault: vaultIdentifier)
        let description = try Data(contentsOf: draftDirectory.appendingPathComponent("\(draft.requestIdentifier.uuidString).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: description) as? NSDictionary)
    }

    func testADraftIsTheRequestsUUIDAsASVGFileNextToADescriptionWithTheJSONExtension() async throws {
        let store = DrawingEditorDraftStore(directory: draftDirectory)
        store.preserve(try draft(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 3, length: 2)))) { Data("<svg/>".utf8) }
        _ = await store.drafts(forVault: vaultIdentifier)

        let fileNames = try FileManager.default.contentsOfDirectory(atPath: draftDirectory.path).sorted()
        XCTAssertEqual(fileNames, ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.svg"])
        XCTAssertEqual(try Data(contentsOf: draftDirectory.appendingPathComponent("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.svg")), Data("<svg/>".utf8))
        XCTAssertEqual(DrawingEditorDraftStore.directory(in: .system).lastPathComponent, "Drawing Drafts")
        XCTAssertEqual(DrawingEditorDraftStore.directory(in: .system).deletingLastPathComponent().standardizedFileURL,
                       URL.applicationSupportDirectory.standardizedFileURL)
    }

    func testTheDescriptionOfANewDrawingNamesItsNoteAndTheTextRangeItGoesInto() async throws {
        let object = try await descriptionObject(of: draft(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 3, length: 2)), title: "New Drawing"))
        XCTAssertEqual(object, [
            "requestIdentifier": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "vaultIdentifier": "11111111-2222-3333-4444-555555555555",
            "target": ["newDrawing": ["notePath": ["rawValue": "Note.md"], "insertionLocation": 3, "insertionLength": 2]],
            "title": "New Drawing", "format": "svg",
        ] as NSDictionary)
    }

    func testTheDescriptionOfAnExistingDrawingNamesItsPathAndTheRevisionItWasOpenedAt() async throws {
        let object = try await descriptionObject(of: draft(.existingDrawing(path: VaultPath("Drawings/Sketch.svg"), location: URL(fileURLWithPath: "/tmp/Sketch.svg"), revision: FileRevision.of(Data("abc".utf8)))))
        XCTAssertEqual(object["target"] as? NSDictionary, [
            "existingDrawing": ["path": ["rawValue": "Drawings/Sketch.svg"], "revision": ["digest": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "size": 3]],
        ] as NSDictionary)
    }

    func testTheDescriptionOfADrawingOnAnImageNamesTheImageAndLeavesOutAMissingNote() async throws {
        let withoutNote = try await descriptionObject(of: draft(.drawingOnImage(imagePath: VaultPath("Photo.png"), notePath: nil)))
        XCTAssertEqual(withoutNote["target"] as? NSDictionary, ["drawingOnImage": ["imagePath": ["rawValue": "Photo.png"]]] as NSDictionary)
        try? FileManager.default.removeItem(at: draftDirectory)
        let withNote = try await descriptionObject(of: draft(.drawingOnImage(imagePath: VaultPath("Photo.png"), notePath: VaultPath("Note.md"))))
        XCTAssertEqual(withNote["target"] as? NSDictionary,
                       ["drawingOnImage": ["imagePath": ["rawValue": "Photo.png"], "notePath": ["rawValue": "Note.md"]]] as NSDictionary)
    }

    /// A description is read back only up to 64 KiB; a larger file is left on disk untouched.
    func testADescriptionOfExactlySixtyFourKibibytesIsReadBackAndOneByteMoreIsNot() async throws {
        let drawing = VectorDrawing(size: CGSize(width: 760, height: 200), background: .white, shapes: [])
        let drawingFile = try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: 760, height: 200, background: .white, strokes: Data("strokes".utf8)))
        let store = DrawingEditorDraftStore(directory: draftDirectory)
        store.preserve(try draft(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)))) { drawingFile }
        let recoveredDrafts = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(recoveredDrafts.count, 1)

        let descriptionLocation = draftDirectory.appendingPathComponent("\(requestIdentifier.uuidString).json")
        let description = try Data(contentsOf: descriptionLocation)
        let sixtyFourKibibytes = 64 * 1024
        // Trailing whitespace keeps the JSON valid while the file grows to the size under test.
        try (description + Data(repeating: 0x20, count: sixtyFourKibibytes - description.count)).write(to: descriptionLocation)
        let atTheLimit = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(atTheLimit.count, 1)
        try (description + Data(repeating: 0x20, count: sixtyFourKibibytes + 1 - description.count)).write(to: descriptionLocation)
        let overTheLimit = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(overTheLimit.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptionLocation.path), "A draft that is not read back stays on disk.")
    }

    func testAWriteAskedForAfterARemovalIsNotOvertakenByIt() async throws {
        let store = DrawingEditorDraftStore(directory: draftDirectory)
        let first = try draft(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)), title: "First")
        let drawing = VectorDrawing(size: CGSize(width: 760, height: 200), background: .white, shapes: [])
        let drawingFile = try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: 760, height: 200, background: .white, strokes: Data("strokes".utf8)))
        store.preserve(first) { drawingFile }
        store.removeDraft(withIdentifier: requestIdentifier)
        let afterWriteThenRemoval = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(afterWriteThenRemoval.count, 0, "A removal after closing the editor is not overtaken by the earlier write.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: draftDirectory.path), [])

        store.removeDraft(withIdentifier: requestIdentifier)
        store.preserve(try draft(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)), title: "Second")) { drawingFile }
        let afterRemovalThenWrite = await store.drafts(forVault: vaultIdentifier)
        XCTAssertEqual(afterRemovalThenWrite.map(\.draft.title), ["Second"])
    }
}
