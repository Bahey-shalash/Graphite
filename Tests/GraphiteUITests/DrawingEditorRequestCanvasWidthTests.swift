import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// What the drawing editor's request decides before any canvas exists: the width a new
/// drawing is drawn at, and which targets need ink or a picture before they are saved.
/// Closing without saving is decided by the editor's view and is not reached from here.
final class DrawingEditorRequestCanvasWidthTests: XCTestCase {
    private func request(_ target: DrawingEditorRequest.Target, canvasWidth: Double? = nil) throws -> DrawingEditorRequest {
        DrawingEditorRequest(target: target, title: "Drawing", initialStrokeData: Data(), canvasWidth: canvasWidth, background: .white, format: .svg)
    }

    func testANewDrawingIsSevenHundredAndSixtyPointsWideAndAnExistingOneKeepsItsOwnWidth() throws {
        XCTAssertEqual(DrawingEditorRequest.newDrawingCanvasWidth, 760)
        let newDrawing = try request(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)))
        XCTAssertEqual(newDrawing.resolvedCanvasWidth, 760)
        let existing = try request(.existingDrawing(path: VaultPath("Drawing.svg"), location: URL(fileURLWithPath: "/tmp/Drawing.svg"),
                                                    revision: FileRevision.of(Data())), canvasWidth: 512)
        XCTAssertEqual(existing.resolvedCanvasWidth, 512)
    }

    func testANewDrawingAndADrawingOnAnImageNeedContentToBeSavedAndAnExistingDrawingDoesNot() throws {
        let newDrawing = try request(.newDrawing(notePath: VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)))
        let onImage = try request(.drawingOnImage(imagePath: VaultPath("Photo.png"), notePath: nil))
        let existing = try request(.existingDrawing(path: VaultPath("Drawing.svg"), location: URL(fileURLWithPath: "/tmp/Drawing.svg"),
                                                    revision: FileRevision.of(Data())))
        XCTAssertTrue(newDrawing.requiresContent, "Cancelling a new drawing with nothing on it creates no file.")
        XCTAssertTrue(onImage.requiresContent)
        XCTAssertFalse(existing.requiresContent)
        XCTAssertEqual(newDrawing.confirmationTitle, "Insert")
        XCTAssertEqual(onImage.confirmationTitle, "Done")
        XCTAssertEqual(existing.confirmationTitle, "Done")
    }
}
