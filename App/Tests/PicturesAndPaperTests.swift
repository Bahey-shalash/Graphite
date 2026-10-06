#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Pictures on PDF pages and on drawings, paper patterns, and the fixed tool bar, with
/// hosted views.
@MainActor
final class PicturesAndPaperTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
        UserDefaults.standard.removeObject(forKey: PencilToolbarStyle.preferenceKey)
    }

    // MARK: Pictures on PDF pages

    func testPictureOnAPDFPageIsPlacedMovedRemovedAndUndone() async throws {
        let session = try await openNotebook(pageCount: 2)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let cropBox = page.bounds(for: .cropBox)

        try await session.addPicture(imageData: try imageData(size: CGSize(width: 400, height: 200), color: .systemRed))
        XCTAssertNil(session.errorMessage)
        let placed = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(session.pictures(on: page).count, 1)
        XCTAssertEqual(placed.bounds.width, cropBox.width * 0.6, accuracy: 1)
        XCTAssertEqual(placed.bounds.width / placed.bounds.height, 2, accuracy: 0.05, "The picture keeps its proportions.")
        XCTAssertTrue(cropBox.contains(CGPoint(x: placed.bounds.midX, y: placed.bounds.midY)))
        let selection = try XCTUnwrap(session.selectedPicture, "A new picture is selected, to be moved into place.")
        XCTAssertEqual(selection.pictureName, placed.name)
        try await waitUntil { !self.descendants(of: controller.view, matching: SelectionFrameView.self).isEmpty }
        attachScreenshot(of: controller, named: "Picture placed on a PDF page")

        // Moving and resizing is one step each; the picture keeps its name and its bytes.
        let movedBounds = CGRect(x: cropBox.minX + 40, y: cropBox.minY + 60, width: 200, height: 100)
        endEvent(of: session)
        try session.movePicture(selection, to: movedBounds)
        let moved = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(moved.bounds, movedBounds)
        XCTAssertEqual(moved.name, placed.name)
        XCTAssertEqual(moved.imageData, placed.imageData)
        endEvent(of: session)
        session.undoAvailability.undo()
        XCTAssertEqual(session.pictures(on: page).first?.bounds, placed.bounds)
        session.undoAvailability.redo()
        XCTAssertEqual(session.pictures(on: page).first?.bounds, movedBounds)

        // The saved file shows the picture to any reader, and Graphite reads it back.
        try await session.save()
        let savedPage = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        let savedPicture = try XCTUnwrap(PDFPageManager.pictures(on: savedPage).first)
        XCTAssertEqual(savedPicture.name, placed.name)
        XCTAssertEqual(savedPicture.imageData, placed.imageData)
        XCTAssertEqual(savedPicture.bounds.width, movedBounds.width, accuracy: 0.01)
        let savedColor = try color(of: savedPage, atPagePoint: CGPoint(x: movedBounds.midX, y: movedBounds.midY))
        XCTAssertGreaterThan(savedColor.red, 0.7); XCTAssertLessThan(savedColor.green, 0.45)

        // Removing it, and getting it back exactly.
        endEvent(of: session)
        try session.removePicture(selection)
        XCTAssertTrue(session.pictures(on: page).isEmpty)
        XCTAssertNil(session.selectedPicture)
        endEvent(of: session)
        session.undoAvailability.undo()
        XCTAssertEqual(session.pictures(on: page).first, moved)
        XCTAssertNil(session.errorMessage)
    }

    func testPictureReadFromAFileIsSelectedByATapAndStaysUnderTheInk() async throws {
        let session = try await openNotebook(pageCount: 1)
        try await session.addPicture(imageData: try imageData(size: CGSize(width: 300, height: 300), color: .systemBlue))
        session.selectedPicture = nil
        try await session.save()

        // A new session reads the picture as an ordinary annotation with Graphite's keys.
        let reopened = try await PDFSession.open(session.location)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: reopened, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(reopened.document.page(at: 0))
        let picture = try XCTUnwrap(reopened.pictures(on: page).first)
        let pdfView = try XCTUnwrap(reopened.pdfView)
        let coordinator = try XCTUnwrap((pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        let canvas = try await editingCanvas(for: page, in: reopened)

        // Ink drawn after the picture is after it in the page's annotations.
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 120)])
        try await waitUntil { page.annotations.contains { annotation in annotation.type == "Ink" } }
        let annotationTypes = page.annotations.compactMap(\.type).filter { type in type == "Stamp" || type == "Ink" }
        XCTAssertEqual(annotationTypes.first, "Stamp")
        XCTAssertEqual(annotationTypes.last, "Ink")

        // A second picture goes under the ink as well, over the first picture.
        try await reopened.addPicture(imageData: try imageData(size: CGSize(width: 100, height: 100), color: .systemGreen))
        let typesWithSecondPicture = page.annotations.compactMap(\.type).filter { type in type == "Stamp" || type == "Ink" }
        XCTAssertEqual(typesWithSecondPicture, ["Stamp", "Stamp", "Ink"])
        XCTAssertEqual(canvas.drawing.strokes.count, 1, "The ink is still editable.")
        // Put the second picture in a corner of the first, so both can be pointed at.
        let secondSelection = try XCTUnwrap(reopened.selectedPicture)
        let cornerBounds = CGRect(x: picture.bounds.maxX - 40, y: picture.bounds.maxY - 40, width: 40, height: 40)
        try reopened.movePicture(secondSelection, to: cornerBounds)
        reopened.selectedPicture = nil
        try await Task.sleep(for: .milliseconds(100))

        let selectionController = try XCTUnwrap(coordinator.pictureSelectionController)
        let pointOnFirst = pdfView.convert(CGPoint(x: picture.bounds.minX + 4, y: picture.bounds.minY + 4), from: page)
        XCTAssertEqual(selectionController.picture(at: pointOnFirst)?.pictureName, picture.name, "A picture read from the file is found under a tap.")
        let pointOnBoth = pdfView.convert(CGPoint(x: cornerBounds.midX, y: cornerBounds.midY), from: page)
        XCTAssertEqual(selectionController.picture(at: pointOnBoth)?.pictureName, secondSelection.pictureName, "Where pictures overlap, the upper one is taken.")
        XCTAssertNil(selectionController.picture(at: pdfView.convert(CGPoint(x: 2, y: 2), from: page)))
        attachScreenshot(of: controller, named: "Pictures under ink on a PDF page")
    }

    // MARK: Paper and pictures in drawings

    func testDrawingWithPaperAndAPictureIsSavedAsItLooksAndReadBack() async throws {
        let picture = DrawingBackgroundImage(imageData: try imageData(size: CGSize(width: 400, height: 200), color: .systemGreen),
                                             frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let ink = PKDrawing(strokes: [stroke(atHeight: 150, width: 14)])
        let service = DrawingFileService()
        let shownPaper = DrawingPaper(pattern: .squared, appearsInSavedDrawing: true)
        let content = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, pictures: [picture], paper: shownPaper)
        let fileData = try await service.fileData(for: content, format: .png)

        // The saved region starts 24 points above the picture (the margin), moved up to the
        // paper's line at 72, so the picture is 28 points down in the file.
        let image = try XCTUnwrap(UIImage(data: fileData)?.cgImage)
        let fileWidth = 760.0
        let pictureColor = try color(of: image, atPoint: CGPoint(x: 280, y: 28 + 85), imageWidth: fileWidth)
        XCTAssertGreaterThan(pictureColor.green, 0.6); XCTAssertLessThan(pictureColor.red, 0.45)
        let inkColor = try color(of: image, atPoint: CGPoint(x: 120, y: 28 + 50), imageWidth: fileWidth)
        XCTAssertLessThan(inkColor.green, 0.3, "The ink is over the picture.")
        let lineColor = try color(of: image, atPoint: CGPoint(x: 500, y: 48), imageWidth: fileWidth)
        XCTAssertLessThan(lineColor.red, 0.9, "A line of the paper crosses here.")
        XCTAssertGreaterThan(lineColor.red, 0.6, "Paper lines are light.")
        let paperColor = try color(of: image, atPoint: CGPoint(x: 500, y: 60), imageWidth: fileWidth)
        XCTAssertGreaterThan(paperColor.red, 0.97, "Between the lines the paper is white.")

        // Graphite reads everything back, placed in the saved region.
        let payload = try XCTUnwrap(DrawingMetadataReader.readMetadata(fileData, format: .png).payload)
        XCTAssertEqual(payload.version, 3)
        XCTAssertEqual(payload.paper, shownPaper)
        XCTAssertEqual(payload.pictures.map(\.imageData), [picture.imageData])
        XCTAssertEqual(payload.pictures.first?.frame, CGRect(x: 100, y: 28, width: 200, height: 100))
        XCTAssertEqual(try PKDrawing(data: payload.strokes).strokes.count, 1)

        // As a guide, the paper is kept for the editor and is not in the picture.
        let guide = DrawingPaper(pattern: .squared, appearsInSavedDrawing: false)
        let guidedContent = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, paper: guide)
        let guidedData = try await service.fileData(for: guidedContent, format: .png)
        let guidedImage = try XCTUnwrap(UIImage(data: guidedData)?.cgImage)
        XCTAssertGreaterThan(try color(of: guidedImage, atPoint: CGPoint(x: 500, y: 48), imageWidth: fileWidth).red, 0.97, "No line in the saved drawing.")
        let guidedPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(guidedData, format: .png).payload)
        XCTAssertEqual(guidedPayload.version, 1)
        XCTAssertEqual(guidedPayload.paper, guide)

        // Vector drawings carry visible paper as shapes under the ink, and the pictures in
        // the same place as the PNG (`VectorDrawingPicturesTests` compares what they show).
        let paperOnly = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, paper: shownPaper)
        for format in [DrawingFormat.svg, .pdf] {
            let vectorData = try await service.fileData(for: paperOnly, format: format)
            XCTAssertEqual(try XCTUnwrap(DrawingMetadataReader.readMetadata(vectorData, format: format).payload).paper, shownPaper)
        }
        let svgDataWithPaper = try await service.fileData(for: paperOnly, format: .svg)
        let svgDataWithoutPaper = try await service.fileData(for: guidedContent, format: .svg)
        let svgWithPaper = try SVGDrawingFile.vectorDrawing(from: svgDataWithPaper)
        let svgWithoutPaper = try SVGDrawingFile.vectorDrawing(from: svgDataWithoutPaper)
        XCTAssertEqual(svgWithPaper.shapes.count, svgWithoutPaper.shapes.count + 1)
        XCTAssertEqual(svgWithPaper.shapes.first?.color, DrawingPaperRenderer.color(of: shownPaper, forDots: false))
        for format in [DrawingFormat.svg, .pdf] {
            let vectorData = try await service.fileData(for: content, format: format)
            let vectorPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(vectorData, format: format).payload)
            XCTAssertEqual(vectorPayload.pictures, payload.pictures)
            XCTAssertEqual(vectorPayload.paper, shownPaper)
        }
        // The draft kept while the app is in the background keeps the paper and the pictures.
        let draftData = try await service.draftFileData(for: content)
        let draftPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(draftData, format: .svg).payload)
        XCTAssertEqual(draftPayload.pictures, [picture])
        XCTAssertEqual(draftPayload.paper, shownPaper)
    }

    func testSavedDrawingsShowThePapersColorSpacingAndLinesInEveryFormat() async throws {
        let ink = PKDrawing(strokes: [stroke(atHeight: 150), stroke(atHeight: 400)])
        let paper = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true, spacing: .wide, lineColor: .blue, lineStrength: .strong)
        let content = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .ivory, paper: paper)
        let service = DrawingFileService()
        let lineColor = DrawingPaperRenderer.color(of: paper, forDots: false)
        let ivory = try XCTUnwrap(DrawingPaperRenderer.paperColor(of: .ivory))
        // The saved region starts on a line of the paper, 48 points apart when wide: the ink
        // at 150 less the margin moves it up to 96. Lines are then at 0, 48, 96, 144… in the
        // file, and nothing is where standard spacing would put a line (160).
        func checkPaper(of image: CGImage, width: Double, format: DrawingFormat) throws {
            let onLine = try color(of: image, atPoint: CGPoint(x: 500, y: 144), imageWidth: width)
            XCTAssertEqual(onLine.red, lineColor.red, accuracy: 0.12, "\(format): the line is strong blue")
            XCTAssertEqual(onLine.blue, lineColor.blue, accuracy: 0.12, "\(format)")
            for betweenLines in [CGPoint(x: 500, y: 120), CGPoint(x: 500, y: 160)] {
                let paperColor = try color(of: image, atPoint: betweenLines, imageWidth: width)
                XCTAssertEqual(paperColor.red, ivory.red, accuracy: 0.02, "\(format): ivory paper at \(betweenLines)")
                XCTAssertEqual(paperColor.blue, ivory.blue, accuracy: 0.02, "\(format): ivory paper at \(betweenLines)")
            }
        }

        let pngData = try await service.fileData(for: content, format: .png)
        try checkPaper(of: try XCTUnwrap(UIImage(data: pngData)?.cgImage), width: 760, format: .png)
        let pdfData = try await service.fileData(for: content, format: .pdf)
        let pdfPage = try XCTUnwrap(PDFDocument(data: pdfData)?.page(at: 0))
        let pageSize = pdfPage.bounds(for: .mediaBox).size
        XCTAssertEqual(pageSize.width, 760, accuracy: 0.5)
        let pageImage = try XCTUnwrap(pdfPage.thumbnail(of: CGSize(width: pageSize.width * 2, height: pageSize.height * 2), for: .mediaBox).cgImage)
        try checkPaper(of: pageImage, width: pageSize.width, format: .pdf)
        let svgData = try await service.fileData(for: content, format: .svg)
        let svgDrawing = try SVGDrawingFile.vectorDrawing(from: svgData)
        XCTAssertEqual(svgDrawing.background, .ivory)
        XCTAssertEqual(svgDrawing.shapes.first?.color, lineColor)
        XCTAssertTrue(String(decoding: svgData, as: UTF8.self).contains("fill=\"#fbf7ea\""))
        for (fileData, format) in [(pngData, DrawingFormat.png), (pdfData, .pdf), (svgData, .svg)] {
            let payload = try XCTUnwrap(DrawingMetadataReader.readMetadata(fileData, format: format).payload)
            XCTAssertEqual(payload.version, 4, "\(format)")
            XCTAssertEqual(payload.paper, paper, "\(format)")
            XCTAssertEqual(payload.background, .ivory, "\(format)")
        }
    }

    func testPicturesOnADrawingAreAddedMovedDeletedAndUndone() throws {
        let controller = DrawingCanvasController()
        controller.canvasWidth = 760
        let picture = DrawingBackgroundImage(imageData: try imageData(size: CGSize(width: 760, height: 380), color: .systemOrange),
                                             frame: CGRect(x: 0, y: 0, width: 760, height: 380))
        try controller.addPicture(picture)
        let placed = try XCTUnwrap(controller.pictures.first)
        XCTAssertEqual(placed.picture.frame.width, 456, accuracy: 1, "A new picture is 60% of the canvas wide.")
        XCTAssertEqual(placed.picture.frame.width / placed.picture.frame.height, 2, accuracy: 0.02)
        XCTAssertEqual(placed.picture.frame.midX, 380, accuracy: 1)
        XCTAssertTrue(controller.isArrangingPictures)
        XCTAssertEqual(controller.selectedPictureIdentifier, placed.id)
        XCTAssertTrue(controller.hasChanges)
        XCTAssertTrue(controller.hasContent, "A drawing with only a picture can be inserted.")

        endEvent(of: controller.history)
        let movedFrame = CGRect(x: 40, y: 300, width: 200, height: 100)
        controller.pictureFrameChangeDidEnd(placed.id, frame: movedFrame)
        XCTAssertEqual(controller.pictures.first?.picture.frame, movedFrame)
        endEvent(of: controller.history)
        controller.history.undo()
        XCTAssertEqual(controller.pictures.first?.picture.frame, placed.picture.frame)
        controller.history.redo()
        XCTAssertEqual(controller.pictures.first?.picture.frame, movedFrame)

        // A tap beside the pictures deselects, a second one ends arranging.
        controller.pictureWasTapped(nil)
        XCTAssertNil(controller.selectedPictureIdentifier)
        XCTAssertTrue(controller.isArrangingPictures)
        controller.pictureWasTapped(nil)
        XCTAssertFalse(controller.isArrangingPictures)
        controller.pictureWasTapped(placed.id)
        XCTAssertEqual(controller.selectedPictureIdentifier, placed.id)

        endEvent(of: controller.history)
        controller.deleteSelectedPicture()
        XCTAssertTrue(controller.pictures.isEmpty)
        XCTAssertFalse(controller.isArrangingPictures)
        endEvent(of: controller.history)
        controller.history.undo()
        XCTAssertEqual(controller.pictures.first?.picture.frame, movedFrame)
        XCTAssertEqual(controller.pictures.first?.id, placed.id)

        // A drawing holds a bounded number of pictures.
        let smallPicture = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        for _ in controller.pictures.count..<DrawingLimits.maximumPictureCount { try controller.addPicture(smallPicture) }
        XCTAssertThrowsError(try controller.addPicture(smallPicture))

        // Paper and background are changes to save, not steps to undo.
        let fresh = DrawingCanvasController()
        fresh.paper.pattern = .ruled
        XCTAssertTrue(fresh.hasChanges)
        XCTAssertFalse(fresh.history.canUndo)
        let other = DrawingCanvasController()
        other.background = .transparent
        XCTAssertTrue(other.hasChanges)
    }

    func testPicturesOnADrawingAreTurnedCroppedAndReorderedAsSteps() async throws {
        let controller = DrawingCanvasController()
        controller.canvasWidth = 760
        let twoColors = try twoColorImageData(size: CGSize(width: 400, height: 200))
        try controller.addPicture(DrawingBackgroundImage(imageData: twoColors, frame: CGRect(x: 0, y: 0, width: 400, height: 200)))
        try controller.addPicture(DrawingBackgroundImage(imageData: try imageData(size: CGSize(width: 100, height: 100), color: .systemTeal),
                                                         frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let first = controller.pictures[0], second = controller.pictures[1]
        endEvent(of: controller.history)

        // Turned about its middle, with its sides swapped and its bytes turned.
        controller.pictureWasTapped(first.id)
        try await controller.rotateSelectedPicture()
        let turned = try XCTUnwrap(controller.pictures.first)
        XCTAssertEqual(turned.id, first.id)
        XCTAssertEqual(turned.picture.frame.width, first.picture.frame.height, accuracy: 0.01)
        XCTAssertEqual(turned.picture.frame.midX, first.picture.frame.midX, accuracy: 0.01)
        XCTAssertEqual(turned.picture.frame.midY, first.picture.frame.midY, accuracy: 0.01)
        XCTAssertEqual(UIImage(data: turned.picture.imageData)?.size.width, UIImage(data: first.picture.imageData)?.size.height)
        XCTAssertEqual(controller.history.undoActionName, "Turn Image")
        endEvent(of: controller.history)
        controller.history.undo()
        XCTAssertEqual(controller.pictures.first?.picture, first.picture)
        controller.history.redo()
        endEvent(of: controller.history)

        // Cropped to its top half, which after the turn is the red side.
        let frame = turned.picture.frame
        try await controller.cropSelectedPicture(to: CGRect(x: frame.minX - 10, y: frame.minY - 10, width: frame.width + 20, height: frame.height / 2 + 10))
        let cropped = try XCTUnwrap(controller.pictures.first)
        XCTAssertEqual(cropped.picture.frame, CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2))
        let croppedImage = try XCTUnwrap(UIImage(data: cropped.picture.imageData)?.cgImage)
        XCTAssertEqual(Double(croppedImage.height) / Double(croppedImage.width), cropped.picture.frame.height / cropped.picture.frame.width,
                       accuracy: 0.02, "The kept part has the proportions of its frame.")
        XCTAssertEqual(controller.history.undoActionName, "Crop Image")
        endEvent(of: controller.history)

        // Over and under the other picture; nothing changes where it already is.
        controller.moveSelectedPictureInOrder(toFront: true)
        XCTAssertEqual(controller.pictures.map(\.id), [second.id, first.id])
        endEvent(of: controller.history)
        controller.moveSelectedPictureInOrder(toFront: true)
        XCTAssertEqual(controller.history.undoActionName, "Bring Image to Front")
        controller.moveSelectedPictureInOrder(toFront: false)
        XCTAssertEqual(controller.pictures.map(\.id), [first.id, second.id])
        endEvent(of: controller.history)
        controller.history.undo()
        XCTAssertEqual(controller.pictures.map(\.id), [second.id, first.id])

        // Cropping is a mode with its own way out.
        controller.beginCroppingPicture()
        XCTAssertTrue(controller.isCroppingPicture)
        controller.pictureWasTapped(nil)
        XCTAssertEqual(controller.selectedPictureIdentifier, first.id, "A tap while cropping does not deselect.")
        controller.cancelCroppingPicture()
        XCTAssertFalse(controller.isCroppingPicture)
        controller.beginCroppingPicture()
        controller.finishArrangingPictures()
        XCTAssertFalse(controller.isCroppingPicture)
    }

    /// Red on the left half, blue on the right.
    private func twoColorImageData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            UIColor.blue.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
        return try XCTUnwrap(image.pngData())
    }

    func testEditorShowsThePapersStyleAndColorAndPreviewsTheSavedLook() async throws {
        var request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: 760, background: .ivory, format: .png)
        let guide = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: false, spacing: .wide, lineColor: .blue, lineStrength: .strong)
        request.paper = guide
        let controller = try host(AnyView(DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        let paperView = try XCTUnwrap(descendants(of: canvas, matching: DrawingPaperView.self).first)
        try await waitUntil { paperView.paper == guide }
        XCTAssertEqual(paperView.paperColor, UIColor(graphiteHex: "#fbf7ea"), "Ivory paper while drawing.")
        XCTAssertFalse(paperView.isHidden)
        attachScreenshot(of: controller, named: "Ivory paper with wide, strong blue lines")

        // Shown as the note will show it: the guide goes, the paper's color stays, and no
        // paper at all shows as a checkerboard.
        canvas.showPaper(guide, background: .ivory, asSaved: true)
        XCTAssertEqual(paperView.paper.pattern, .plain)
        XCTAssertNotNil(paperView.paperColor)
        canvas.showPaper(guide, background: .transparent, asSaved: true)
        XCTAssertNil(paperView.paperColor)
        XCTAssertTrue(paperView.showsMissingPaper)
        // A pattern the note shows stays in the preview.
        var shown = guide
        shown.appearsInSavedDrawing = true
        canvas.showPaper(shown, background: .white, asSaved: true)
        XCTAssertEqual(paperView.paper, shown)
        canvas.showPaper(guide, background: .ivory, asSaved: false)
        XCTAssertEqual(paperView.paper, guide)
        XCTAssertFalse(paperView.showsMissingPaper)
    }

    func testWritingGuidesShowOnPDFPagesWhileWritingAndAreNeverSaved() async throws {
        UserDefaults.standard.set(DrawingPaperPattern.squared.rawValue, forKey: PDFAnnotationPreferenceKey.writingGuidePattern)
        defer { UserDefaults.standard.removeObject(forKey: PDFAnnotationPreferenceKey.writingGuidePattern) }
        let session = try await openNotebook(pageCount: 1)
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: page, in: session)
        try await waitUntil { canvas.writingGuides.pattern == .squared }
        XCTAssertEqual(canvas.writingGuides.lineStrength, .light)
        XCTAssertFalse(canvas.writingGuides.appearsInSavedDrawing)
        // Under the canvas, the size of the page: the canvas is enlarged to draw ink at its zoom.
        let overlayView = try XCTUnwrap(canvas.overlayView)
        let paperView = try XCTUnwrap(descendants(of: overlayView, matching: DrawingPaperView.self).first)
        XCTAssertFalse(paperView.isHidden)
        XCTAssertEqual(paperView.frame, overlayView.bounds)

        // Writing on the page saves the ink and nothing of the guides.
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await waitUntil { page.annotations.contains { annotation in annotation.type == "Ink" } }
        try await session.save()
        let savedPage = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        XCTAssertEqual(savedPage.annotations.map(\.type), ["Ink"])
        // Away from the ink the saved page is as white as the blank paper it was.
        XCTAssertEqual(try color(of: savedPage, atPagePoint: CGPoint(x: 300, y: 500)).red, 1, accuracy: 0.02)
        XCTAssertEqual(try color(of: savedPage, atPagePoint: CGPoint(x: 24, y: 24)).blue, 1, accuracy: 0.02)

        UserDefaults.standard.set(DrawingPaperPattern.plain.rawValue, forKey: PDFAnnotationPreferenceKey.writingGuidePattern)
        try await waitUntil { canvas.writingGuides.pattern == .plain }
        XCTAssertTrue(paperView.isHidden)
    }

    func testADrawingWithoutPaperShowsOnWhiteInADarkNote() async throws {
        // A transparent drawing: one black line across the middle.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let transparentDrawing = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 48, width: 200, height: 4))
        }
        let drawing = try XCTUnwrap(transparentDrawing.cgImage)
        func embeds(editable: Bool) -> AnyView {
            AnyView(EmbeddedImageView(image: drawing, aspectRatio: 2, displayWidth: 200, edit: editable ? {} : nil, view: {})
                .frame(width: 200, height: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.black))
        }
        for (isDrawing, expectedBrightness) in [(true, 1.0), (false, 0.0)] {
            let controller = try host(embeds(editable: isDrawing))
            controller.overrideUserInterfaceStyle = .dark
            try await Task.sleep(for: .milliseconds(300))
            let snapshot = try XCTUnwrap(UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }.cgImage)
            let origin = CGPoint(x: controller.view.safeAreaInsets.left, y: controller.view.safeAreaInsets.top)
            // Where the drawing has no ink, the page shows through: white for a drawing, the
            // note's dark background for another image.
            let clearPart = try color(of: snapshot, atPoint: CGPoint(x: origin.x + 100, y: origin.y + 20), imageWidth: controller.view.bounds.width)
            XCTAssertEqual(clearPart.red, expectedBrightness, accuracy: 0.1, isDrawing ? "A drawing" : "Another image")
            let ink = try color(of: snapshot, atPoint: CGPoint(x: origin.x + 100, y: origin.y + 50), imageWidth: controller.view.bounds.width)
            XCTAssertLessThan(ink.red, 0.2, "The ink stays black.")
            if isDrawing { attachScreenshot(of: controller, named: "A transparent drawing in a dark note") }
        }
    }

    func testEditorShowsPaperAndPicturesUnderTheInk() async throws {
        var request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: PKDrawing(strokes: [stroke(atHeight: 60)]).dataRepresentation(),
                                           canvasWidth: 760, background: .white, format: .svg)
        request.paper = DrawingPaper(pattern: .dotted, appearsInSavedDrawing: false)
        request.pictures = [DrawingBackgroundImage(imageData: try imageData(size: CGSize(width: 200, height: 100), color: .systemTeal),
                                                   frame: CGRect(x: 40, y: 120, width: 200, height: 100))]
        let controller = try host(AnyView(DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        try await waitUntil { canvas.zoomScale > 0 && canvas.bounds.width > 0 }

        XCTAssertEqual(canvas.paperPattern, .dotted)
        let paperView = try XCTUnwrap(descendants(of: canvas, matching: DrawingPaperView.self).first)
        XCTAssertFalse(paperView.isHidden)
        XCTAssertFalse(canvas.isOpaque, "Paper and pictures show through the canvas, under the ink.")
        let pictureView = try XCTUnwrap(descendants(of: canvas, matching: UIImageView.self).first { imageView in imageView.accessibilityLabel == "Image" })
        XCTAssertEqual(pictureView.frame.minX, 40 * canvas.zoomScale, accuracy: 0.5)
        XCTAssertEqual(pictureView.frame.width, 200 * canvas.zoomScale, accuracy: 0.5)
        // Below everything PencilKit draws: the paper first, then the picture.
        let subviews = canvas.subviews
        XCTAssertEqual(subviews.first, paperView)
        XCTAssertEqual(subviews.dropFirst().first, pictureView)
        XCTAssertTrue(canvas.isDrawingEnabled)
        XCTAssertEqual(canvas.picture(atContentPoint: CGPoint(x: 100 * canvas.zoomScale, y: 150 * canvas.zoomScale)) != nil, true)
        XCTAssertNil(canvas.picture(atContentPoint: CGPoint(x: 500 * canvas.zoomScale, y: 150 * canvas.zoomScale)))
        attachScreenshot(of: controller, named: "Drawing editor with dotted paper and a picture")
    }

    // MARK: Moving and resizing a picture

    func testSelectionFrameMovesWithinLimitsAndResizesInProportion() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(SelectionFrameView.moved(frame, by: CGPoint(x: 30, y: -20), keepingCenterIn: .infinite), CGRect(x: 130, y: 80, width: 200, height: 100))
        let limits = CGRect(x: 0, y: 0, width: 400, height: 300)
        let pushedOut = SelectionFrameView.moved(frame, by: CGPoint(x: 900, y: 900), keepingCenterIn: limits)
        XCTAssertEqual(CGPoint(x: pushedOut.midX, y: pushedOut.midY), CGPoint(x: 400, y: 300), "The middle stays on the page.")
        XCTAssertEqual(pushedOut.size, frame.size)

        // Dragging the bottom-right corner keeps the top-left corner and the proportions.
        let grown = SelectionFrameView.resized(frame, byDragging: CGPoint(x: 100, y: 10), pullsRight: true, pullsDown: true, minimumSideLength: 32)
        XCTAssertEqual(grown, CGRect(x: 100, y: 100, width: 300, height: 150))
        // Dragging the top-left corner keeps the bottom-right corner.
        let shrunk = SelectionFrameView.resized(frame, byDragging: CGPoint(x: 100, y: 50), pullsRight: false, pullsDown: false, minimumSideLength: 32)
        XCTAssertEqual(shrunk, CGRect(x: 200, y: 150, width: 100, height: 50))
        // Never smaller than the minimum side.
        let smallest = SelectionFrameView.resized(frame, byDragging: CGPoint(x: -1_000, y: -1_000), pullsRight: true, pullsDown: true, minimumSideLength: 32)
        XCTAssertEqual(smallest.height, 32, accuracy: 0.001)
        XCTAssertEqual(smallest.width, 64, accuracy: 0.001)
    }

    // MARK: Fixed tool bar

    func testFixedToolBarGivesCanvasesItsToolAndThePaletteTakesOverAgain() async throws {
        let toolbox = PencilToolbox.shared
        let toolInUseBefore = toolbox.toolInUse, presetInUseIndexBefore = toolbox.presetInUseIndex
        defer {
            toolbox.usePreset(at: presetInUseIndexBefore)
            toolbox.use(toolInUseBefore)
        }
        UserDefaults.standard.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        toolbox.usePreset(at: 0)
        let session = try await openNotebook(pageCount: 1)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: page, in: session)
        // Compact widths keep the floating palette whatever the setting says.
        guard controller.traitCollection.horizontalSizeClass == .regular else {
            XCTAssertTrue(canvas.followsToolPicker)
            return
        }
        XCTAssertFalse(canvas.followsToolPicker)
        let firstTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(firstTool.inkType, toolbox.presetInUse.ink.inkType)
        XCTAssertEqual(firstTool.width, CGFloat(toolbox.presetInUse.width), accuracy: 0.01)
        attachScreenshot(of: controller, named: "PDF with the fixed tool bar")

        let lastPresetIndex = toolbox.presets.count - 1
        toolbox.usePreset(at: lastPresetIndex)
        try await waitUntil { (canvas.tool as? PKInkingTool)?.inkType == toolbox.presets[lastPresetIndex].ink.inkType }
        toolbox.use(.eraser)
        try await waitUntil { canvas.tool is PKEraserTool }
        // The bar's lasso is Graphite's own: the canvas selects ink and stops drawing.
        toolbox.use(.lasso)
        try await waitUntil { canvas.selectsInk }
        XCTAssertFalse(canvas.isDrawingEnabled)
        toolbox.usePreset(at: 0)
        try await waitUntil { !canvas.selectsInk }
        XCTAssertTrue(canvas.isDrawingEnabled)

        // Back to the floating palette: the canvas follows the system's picker again.
        UserDefaults.standard.set(PencilToolbarStyle.floating.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        try await waitUntil { canvas.followsToolPicker }
    }

    func testApplePencilGesturesSwitchTheBarsToolsAndOpenItsPaletteAtTheTip() async throws {
        let toolbox = PencilToolbox.shared
        let toolInUseBefore = toolbox.toolInUse, presetInUseIndexBefore = toolbox.presetInUseIndex
        let toolbarStyleBefore = UserDefaults.standard.string(forKey: PencilToolbarStyle.preferenceKey)
        defer {
            toolbox.usePreset(at: presetInUseIndexBefore)
            toolbox.use(toolInUseBefore)
            UserDefaults.standard.set(toolbarStyleBefore, forKey: PencilToolbarStyle.preferenceKey)
        }
        // What Settings › Apple Pencil asks for.
        XCTAssertEqual(PencilGestureResponse(preferredAction: .switchEraser), .switchToEraser)
        XCTAssertEqual(PencilGestureResponse(preferredAction: .switchPrevious), .switchToPreviousTool)
        XCTAssertEqual(PencilGestureResponse(preferredAction: .showColorPalette), .showPalette)
        XCTAssertEqual(PencilGestureResponse(preferredAction: .showContextualPalette), .showPalette)
        XCTAssertEqual(PencilGestureResponse(preferredAction: .runSystemShortcut), .none, "The system runs it.")
        XCTAssertEqual(PencilGestureResponse(preferredAction: .ignore), .none)

        UserDefaults.standard.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        toolbox.usePreset(at: 0)
        let session = try await openNotebook(pageCount: 1)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        // Compact widths keep Apple's palette, which answers the Pencil itself.
        guard controller.traitCollection.horizontalSizeClass == .regular else { return }
        try await waitUntil { !descendants(of: controller.view, matching: PencilGestureReceiverView.self).isEmpty }
        let receiver = try XCTUnwrap(descendants(of: controller.view, matching: PencilGestureReceiverView.self).first)
        let firstGesture = Date.timeIntervalSinceReferenceDate

        receiver.respond(.switchToEraser, at: firstGesture, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .eraser)
        receiver.respond(.switchToEraser, at: firstGesture, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .eraser, "One double tap, heard twice, switches once.")
        receiver.respond(.switchToEraser, at: firstGesture + 1, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertEqual(toolbox.presetInUseIndex, 0)
        receiver.respond(.switchToPreviousTool, at: firstGesture + 2, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .eraser)
        receiver.respond(.none, at: firstGesture + 3, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .eraser)

        // A squeeze opens the palette where the Pencil's tip hovers.
        let tip = receiver.convert(CGPoint(x: controller.view.bounds.midX, y: controller.view.bounds.midY), from: controller.view)
        receiver.respond(.showPalette, at: firstGesture + 4, hoverLocation: tip)
        try await waitUntil { controller.presentedViewController is PencilPaletteController }
        let palette = try XCTUnwrap(controller.presentedViewController as? PencilPaletteController)
        XCTAssertEqual(palette.popoverPresentationController?.sourceView, receiver)
        XCTAssertEqual(palette.popoverPresentationController?.sourceRect, CGRect(origin: tip, size: .zero))
        try await Task.sleep(for: .milliseconds(600))
        attachScreenshot(of: controller, named: "The palette of Apple Pencil's squeeze")
        // Choosing a tool closes it.
        toolbox.usePreset(at: 1)
        try await waitUntil { controller.presentedViewController == nil }
        XCTAssertEqual(toolbox.presetInUseIndex, 1)

        // Without hovering, it opens under the bar, and a second squeeze closes it.
        receiver.respond(.showPalette, at: firstGesture + 5, hoverLocation: nil)
        try await waitUntil { controller.presentedViewController is PencilPaletteController }
        XCTAssertEqual(controller.presentedViewController?.popoverPresentationController?.permittedArrowDirections, .up)
        receiver.respond(.showPalette, at: firstGesture + 6, hoverLocation: nil)
        try await waitUntil { controller.presentedViewController == nil }
    }

    func testTheToolsGoInTheTabBarWhereItHasRoomAndInARowOfTheirOwnWhereItHasNot() async throws {
        UserDefaults.standard.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ToolsInTabBar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        locations.append(directory)
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled)).write(to: directory.appendingPathComponent("Notebook.pdf"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Notebook.pdf"), placement: .currentTab)
        let controller = try host(AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        guard controller.traitCollection.horizontalSizeClass == .regular else { return }
        func toolRows() -> [PencilGestureReceiverView] {
            descendants(of: controller.view, matching: PencilGestureReceiverView.self).filter { row in row.window != nil && row.bounds.height > 0 }
        }
        func pdfViewTop() -> CGFloat? {
            descendants(of: controller.view, matching: PDFView.self).first { pdfView in pdfView.window != nil }.map { pdfView in pdfView.convert(pdfView.bounds, to: nil).minY }
        }
        // The tab bar's row is 40 points high; the bar of its own, 44.
        try await waitUntil { toolRows().count == 1 && abs((toolRows().first?.bounds.height ?? 0) - 40) < 0.5 }
        let tabBarRow = try XCTUnwrap(toolRows().first).convert(try XCTUnwrap(toolRows().first).bounds, to: nil)
        let pageTop = try XCTUnwrap(pdfViewTop())
        XCTAssertLessThan(pageTop - tabBarRow.maxY, 2, "Nothing but the tab bar's divider lies between the tools and the page.")
        attachScreenshot(of: controller, named: "Tools in the tab bar")

        // Half of the width has no room beside the tabs and Read/Write: the tools get their row back.
        let notebookTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Notebook.pdf")))
        let notebookSide = try XCTUnwrap(workspace.layout.group(containing: notebookTab)?.id)
        workspace.splitRight()
        // The tools are the focused side's.
        workspace.focusGroup(notebookSide)
        try await waitUntil { toolRows().count == 1 && abs((toolRows().first?.bounds.height ?? 0) - PencilToolbarMetrics.height) < 0.5 }
        attachScreenshot(of: controller, named: "Tools in a row of their own beside a split")
    }

    func testEveryInkOfTheBarIsAPencilKitInkAtAWidthItDraws() throws {
        XCTAssertEqual(Set(PencilInk.availableInks.map(\.inkType)).count, PencilInk.availableInks.count, "No two inks of the bar are the same PencilKit ink.")
        for ink in PencilInk.availableInks {
            // The widths the bar and its slider offer are ones PencilKit accepts as they are.
            let validWidths = ink.inkType.validWidthRange
            XCTAssertGreaterThanOrEqual(CGFloat(ink.widthRange.lowerBound), validWidths.lowerBound - 0.01, ink.title)
            XCTAssertLessThanOrEqual(CGFloat(ink.widthRange.upperBound), validWidths.upperBound + 0.01, ink.title)
            var preset = InkPreset(ink: ink)
            preset.colorHex = "#e93147"
            preset.opacity = 0.5
            let tool = preset.inkingTool
            XCTAssertEqual(tool.inkType, ink.inkType, ink.title)
            XCTAssertEqual(tool.width, CGFloat(ink.mediumWidth), accuracy: 0.01, ink.title)
            var alpha: CGFloat = 0
            tool.color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 0.5, accuracy: 0.01, ink.title)

            // The sample in the ink's options is drawn, not empty.
            let sample = PencilInkSample.image(of: ink, colorHex: "#e93147", colorScheme: .light, displayScale: 2)
            XCTAssertEqual(sample.size, PencilInkSample.size, ink.title)
            let samplePixels = try pixels(of: try XCTUnwrap(sample.cgImage))
            XCTAssertTrue(samplePixels.contains { pixel in pixel.alpha > 40 && pixel.red > pixel.blue + 30 }, "\(ink.title) draws in the preset's color.")
        }

        // The eraser takes whole strokes, or the ink under it at one of three sizes.
        var selection = PencilToolbox(defaults: try XCTUnwrap(UserDefaults(suiteName: "EveryInk-\(UUID().uuidString)"))).selection
        selection.kind = .eraser
        XCTAssertEqual((selection.tool as? PKEraserTool)?.eraserType, .vector)
        selection.erasesWholeStrokes = false
        for width in PencilToolbox.eraserWidthChoices {
            selection.eraserWidth = width
            let eraser = try XCTUnwrap(selection.tool as? PKEraserTool)
            XCTAssertEqual(eraser.eraserType, .fixedWidthBitmap)
            XCTAssertEqual(eraser.width, CGFloat(width), accuracy: 0.01)
        }
    }

    private func pixels(of image: CGImage) throws -> [(red: Int, green: Int, blue: Int, alpha: Int)] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
        }
    }

    // MARK: Helpers

    private func openNotebook(pageCount: Int) async throws -> PDFSession {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("Pictures-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
        locations.append(location)
        return try await PDFSession.open(location)
    }

    private func host(_ rootView: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func editingCanvas(for page: PDFPage, in session: PDFSession) async throws -> PDFPageCanvasView {
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        return try XCTUnwrap(coordinator()?.editingCanvas(for: page))
    }

    private func stroke(atHeight height: CGFloat, width: CGFloat = 4) -> PKStroke {
        let points = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: CGFloat(50 + pointIndex * 10), y: height), timeOffset: Double(pointIndex) / 10,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func imageData(size: CGSize, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    /// The color a reader shows at a point of the page, given in the page's coordinates.
    private func color(of page: PDFPage, atPagePoint pagePoint: CGPoint) throws -> (red: Double, green: Double, blue: Double) {
        let cropBox = page.bounds(for: .cropBox)
        let image = try XCTUnwrap(page.thumbnail(of: cropBox.size, for: .cropBox).cgImage)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let scaleX = Double(image.width) / cropBox.width, scaleY = Double(image.height) / cropBox.height
        // Page coordinates count up from the bottom, as Core Graphics does.
        context.draw(image, in: CGRect(x: -(pagePoint.x - cropBox.minX) * scaleX, y: -(pagePoint.y - cropBox.minY) * scaleY,
                                       width: Double(image.width), height: Double(image.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// Steps made in code arrive within one turn of the run loop, in one undo group.
    private func endEvent(of session: PDFSession) {
        endEvent(of: session.undoManager)
    }

    private func endEvent(of history: UndoManager) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(history.groupingLevel, 0)
    }

    /// The color of a saved drawing at a point given in drawing points from its top-left corner.
    private func color(of image: CGImage, atPoint point: CGPoint, imageWidth: Double) throws -> (red: Double, green: Double, blue: Double) {
        let pixelsPerPoint = Double(image.width) / imageWidth
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Rows count up from the bottom in Core Graphics.
        context.draw(image, in: CGRect(x: -point.x * pixelsPerPoint, y: -(Double(image.height) - point.y * pixelsPerPoint - 1),
                                       width: Double(image.width), height: Double(image.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted workspace did not reach the expected state.")
    }
}
#endif
