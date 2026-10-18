import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

final class DrawingEditorDraftStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("DrawingEditorDraftStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// The editor request was made with the original paper; the draft file holds the paper
    /// the person chose afterwards, and that is the one the recovered editor must show.
    @MainActor
    func testRecoveredDraftReopensWithThePaperColourChosenBeforeTheAppWasEnded() async throws {
        let store = DrawingEditorDraftStore(directory: temporaryDirectory.appendingPathComponent("Drafts", isDirectory: true))
        let vaultIdentifier = UUID()
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        let chosenBackground = DrawingBackground.yellow
        let drawing = VectorDrawing(size: CGSize(width: 760, height: 200), background: chosenBackground, shapes: [])
        let drawingFile = try SVGDrawingFile.encode(drawing, payload: DrawingPayload(width: 760, height: 200, background: chosenBackground,
                                                                                    strokes: Data("pencil strokes".utf8)))

        store.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) { drawingFile }
        let recoveredDrafts = await store.drafts(forVault: vaultIdentifier)
        let reopened = try XCTUnwrap(recoveredDrafts.first).editorRequest(inVaultAt: temporaryDirectory)

        XCTAssertEqual(reopened.background, chosenBackground)
    }

    /// Drafts written by earlier versions also described the paper; that copy is ignored.
    func testDraftDescriptionWrittenWithAnEarlierPaperFieldStillDecodes() throws {
        let requestIdentifier = UUID(), vaultIdentifier = UUID()
        let description = """
        {"requestIdentifier":"\(requestIdentifier.uuidString)","vaultIdentifier":"\(vaultIdentifier.uuidString)",
         "target":{"newDrawing":{"notePath":{"rawValue":"Note.md"},"insertionLocation":0,"insertionLength":0}},
         "title":"New Drawing","background":"white","format":"png"}
        """

        let draft = try JSONDecoder().decode(DrawingEditorDraft.self, from: Data(description.utf8))

        XCTAssertEqual(draft.requestIdentifier, requestIdentifier)
        XCTAssertEqual(draft.format, .png)
    }
}
