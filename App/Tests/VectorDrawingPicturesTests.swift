#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import WebKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Drawings with pictures saved as PDF and SVG, through the drawing service and the
/// workspace: they show what the PNG shows, in the same place, to readers that know nothing
/// of Graphite, and they open again with the same pictures.
@MainActor
final class VectorDrawingPicturesTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []
    /// The format new drawings take on this device, put back after a test changes it.
    private var drawingFormatBeforeTest: DrawingFormat?

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
        if let drawingFormatBeforeTest { GraphitePreferences().drawingFormat = drawingFormatBeforeTest }
    }

    // MARK: The same drawing in every format

    private enum Seen: Equatable { case photo, cutOut, ink, paperLine, white }

    private func seen(_ color: (red: Double, green: Double, blue: Double)) -> Seen? {
        let red = color.red * 255, green = color.green * 255, blue = color.blue * 255
        if red < 70, green < 70, blue < 70 { return .ink }
        if red > 190, green < 90, blue < 90 { return .photo }
        if blue > 190, red < 90, green < 120 { return .cutOut }
        if red > 243, green > 243, blue > 243 { return .white }
        // The ruled paper's `#ccd4e0`, or part of it where the one-point line is smoothed.
        if (185...243).contains(red), blue >= red + 4 { return .paperLine }
        return nil
    }

    func testPNGPDFAndSVGOfADrawingWithPicturesAndPaperShowTheSame() async throws {
        let photo = DrawingBackgroundImage(imageData: try jpegData(size: CGSize(width: 240, height: 160), color: .red), frame: CGRect(x: 60, y: 100, width: 240, height: 160))
        let cutOut = DrawingBackgroundImage(imageData: try halfTransparentPNGData(size: CGSize(width: 200, height: 100)), frame: CGRect(x: 400, y: 100, width: 240, height: 120))
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 60, y: 150), CGPoint(x: 180, y: 150), CGPoint(x: 300, y: 150)], width: 10),
                                      stroke(through: [CGPoint(x: 40, y: 400), CGPoint(x: 380, y: 400), CGPoint(x: 720, y: 400)], width: 10)])
        let paper = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true)
        let content = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, pictures: [photo, cutOut], paper: paper)
        let service = DrawingFileService()
        let pngData = try await service.fileData(for: content, format: .png)
        let pdfData = try await service.fileData(for: content, format: .pdf)
        let svgData = try await service.fileData(for: content, format: .svg)

        // Every format saves the same region and the same record.
        let pngPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(pngData, format: .png).payload)
        for (fileData, format) in [(pdfData, DrawingFormat.pdf), (svgData, .svg)] {
            let vectorPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(fileData, format: format).payload)
            XCTAssertEqual(vectorPayload.pictures, pngPayload.pictures, "\(format)")
            XCTAssertEqual(vectorPayload.width, pngPayload.width); XCTAssertEqual(vectorPayload.height, pngPayload.height)
            XCTAssertEqual(try PKDrawing(data: vectorPayload.strokes).strokes.count, 2)
        }
        XCTAssertEqual(pngPayload.pictures.map(\.imageData), [photo.imageData, cutOut.imageData], "The pictures' own bytes.")
        let savedPhotoFrame = try XCTUnwrap(pngPayload.pictures.first?.frame)
        // The saved region starts on a paper line above the content, so points move by that much.
        let origin = CGPoint(x: photo.frame.minX - savedPhotoFrame.minX, y: photo.frame.minY - savedPhotoFrame.minY)
        XCTAssertEqual(origin.y.truncatingRemainder(dividingBy: DrawingPaperGeometry.ruledLineSpacing), 0)
        let drawingSize = CGSize(width: pngPayload.width, height: pngPayload.height)

        let pngImage = try XCTUnwrap(UIImage(data: pngData)?.cgImage)
        let pdfImage = try pdfPageImage(pdfData)
        let previewImage = try VectorDrawingRenderer.image(for: SVGDrawingFile.vectorDrawing(from: svgData), maximumPixelDimension: 1_520)
        let webKitImage = try await webKitImage(ofSVG: svgData, size: drawingSize) { image in
            (try? self.seen(self.color(of: image, atPoint: CGPoint(x: 120 - origin.x, y: 112 - origin.y), drawingSize: drawingSize))) == .photo
        }
        let expectations: [(canvasPoint: CGPoint, seen: Seen, reason: String)] = [
            (CGPoint(x: 120, y: 112), .photo, "the photo"),
            (CGPoint(x: 120, y: 128), .photo, "the photo over a paper line"),
            (CGPoint(x: 180, y: 150), .ink, "the ink over the photo"),
            (CGPoint(x: 430, y: 128), .cutOut, "the cut-out over a paper line"),
            (CGPoint(x: 600, y: 128), .paperLine, "the paper through the cut-out's transparent half"),
            (CGPoint(x: 600, y: 112), .white, "white between the lines"),
            (CGPoint(x: 380, y: 400), .ink, "the ink"),
            (CGPoint(x: 700, y: 320), .paperLine, "a paper line"),
            (CGPoint(x: 700, y: 336), .white, "white between the lines"),
        ]
        for (reader, image) in [("PNG", pngImage), ("PDF", pdfImage), ("Graphite's SVG preview", previewImage), ("WebKit", webKitImage)] {
            for expectation in expectations {
                let point = CGPoint(x: expectation.canvasPoint.x - origin.x, y: expectation.canvasPoint.y - origin.y)
                let color = try color(of: image, atPoint: point, drawingSize: drawingSize)
                XCTAssertEqual(seen(color), expectation.seen, "\(reader): \(expectation.reason) at \(point), \(color)")
            }
        }
        attach(pngImage, named: "PNG"); attach(pdfImage, named: "PDF"); attach(webKitImage, named: "SVG in WebKit")
    }

    func testExportedCopiesOfADrawingWithPicturesHoldThem() async throws {
        let photo = DrawingBackgroundImage(imageData: try jpegData(size: CGSize(width: 200, height: 100), color: .red), frame: CGRect(x: 0, y: 0, width: 760, height: 380))
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 100, y: 200), CGPoint(x: 660, y: 200)], width: 10)])
        let content = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, backgroundImage: photo)
        let workspace = WorkspaceModel()
        for format in DrawingFormat.allCases {
            let exported = try await workspace.exportDrawingCopy(content, format: format, title: "Diagram annotated.png")
            locations.append(exported)
            XCTAssertEqual(exported.lastPathComponent, "Diagram annotated.\(format.fileExtension)")
            let payload = try XCTUnwrap(DrawingMetadataReader.readMetadata(try Data(contentsOf: exported), format: format).payload)
            XCTAssertEqual(payload.backgroundImage, photo, "\(format)")
        }
    }

    // MARK: Through the workspace

    func testDrawingOnANotesImageIsSavedAsSVGAndOpensAgainWithItsPicture() async throws {
        let (workspace, directory) = try await makeWorkspace(notes: ["Lecture.md": "# Lecture\n\n![[Diagram.png|300]]\n"])
        let originalImage = try jpegData(size: CGSize(width: 900, height: 600), color: .red)
        try originalImage.write(to: directory.appendingPathComponent("Diagram.png"))
        let notePath = try VaultPath("Lecture.md"), imagePath = try VaultPath("Diagram.png")
        await workspace.open(notePath)
        let session = try XCTUnwrap(workspace.markdownSession)
        choose(.svg, in: workspace)

        await workspace.beginDrawingOnImage(at: imagePath, fromNote: notePath)
        let request = try XCTUnwrap(workspace.drawingEditorRequest)
        XCTAssertEqual(request.format, .svg, "A drawing on an image takes the format new drawings take.")
        let picture = try XCTUnwrap(request.backgroundImage)
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 80, y: 250), CGPoint(x: 400, y: 250), CGPoint(x: 680, y: 250)], width: 10)])
        try await workspace.saveDrawing(DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, backgroundImage: picture),
                                        format: request.format, for: request)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Diagram.png")), originalImage, "The original image is never changed.")
        let savedLocation = directory.appendingPathComponent("Diagram annotated.svg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedLocation.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Diagram annotated.png").path))
        XCTAssertEqual(session.text, "# Lecture\n\n![[Diagram annotated.svg|300]]\n")

        // What a note shows: the picture with the ink over it, as a drawing it can edit.
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: savedLocation))
        let shown = try await ImageFileService().displayImage(at: savedLocation, maximumPixelDimension: 760)
        let drawingSize = CGSize(width: 760, height: picture.frame.height)
        XCTAssertEqual(seen(try color(of: shown, atPoint: CGPoint(x: 380, y: 100), drawingSize: drawingSize)), .photo)
        XCTAssertEqual(seen(try color(of: shown, atPoint: CGPoint(x: 380, y: 250), drawingSize: drawingSize)), .ink)

        workspace.drawingEditorRequest = nil
        await workspace.beginEditingDrawing(at: try VaultPath("Diagram annotated.svg"))
        let editingRequest = try XCTUnwrap(workspace.drawingEditorRequest)
        XCTAssertEqual(editingRequest.format, .svg)
        XCTAssertEqual(editingRequest.backgroundImage, picture, "The same bytes in the same frame.")
        XCTAssertEqual(try PKDrawing(data: editingRequest.initialStrokeData).strokes.count, 1)
    }

    func testDrawingOnAStandaloneImageIsSavedAsPDFBesideIt() async throws {
        let (workspace, directory) = try await makeWorkspace(notes: [:])
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Scans"), withIntermediateDirectories: true)
        try jpegData(size: CGSize(width: 400, height: 400), color: .red).write(to: directory.appendingPathComponent("Scans/Page.jpg"))
        choose(.pdf, in: workspace)
        await workspace.beginDrawingOnImage(at: try VaultPath("Scans/Page.jpg"), fromNote: nil)
        let request = try XCTUnwrap(workspace.drawingEditorRequest)
        let picture = try XCTUnwrap(request.backgroundImage)
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 80, y: 380), CGPoint(x: 680, y: 380)], width: 10)])
        try await workspace.saveDrawing(DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, backgroundImage: picture),
                                        format: request.format, for: request)
        let savedPath = try VaultPath("Scans/Page annotated.pdf")
        XCTAssertEqual(workspace.layout.activeTab.path, savedPath, "The drawing opens in place of the image.")
        let savedLocation = directory.appendingPathComponent(savedPath.rawValue)
        let savedData = try Data(contentsOf: savedLocation)
        let pageImage = try pdfPageImage(savedData)
        XCTAssertEqual(seen(try color(of: pageImage, atPoint: CGPoint(x: 380, y: 100), drawingSize: CGSize(width: 760, height: 760))), .photo)
        XCTAssertEqual(seen(try color(of: pageImage, atPoint: CGPoint(x: 380, y: 380), drawingSize: CGSize(width: 760, height: 760))), .ink)
        // Notes show a PDF inline as a drawing only when its record verifies.
        let isDrawing = await ImageFileService().isEditableDrawingPDF(at: savedLocation)
        XCTAssertTrue(isDrawing)
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: savedLocation))
        let shown = try await ImageFileService().displayImage(at: savedLocation, maximumPixelDimension: 760)
        XCTAssertEqual(seen(try color(of: shown, atPoint: CGPoint(x: 380, y: 100), drawingSize: CGSize(width: 760, height: 760))), .photo)
        XCTAssertNotNil(savedData.range(of: picture.imageData), "The photo is in the PDF as its own JPEG bytes.")

        workspace.drawingEditorRequest = nil
        await workspace.beginEditingDrawing(at: savedPath)
        XCTAssertEqual(try XCTUnwrap(workspace.drawingEditorRequest).backgroundImage, picture)
    }

    func testExistingSVGDrawingTakesAPictureAndStaysAnSVG() async throws {
        let (workspace, directory) = try await makeWorkspace(notes: [:])
        let store = try XCTUnwrap(workspace.store)
        let sketchPath = try VaultPath("Sketch.svg")
        let firstInk = PKDrawing(strokes: [stroke(through: [CGPoint(x: 80, y: 60), CGPoint(x: 680, y: 60)], width: 8)])
        _ = try await DrawingFileService(writer: store.writer).save(DrawingContent(strokeData: firstInk.dataRepresentation(), canvasWidth: 760, background: .white),
                                                                     format: .svg, to: directory.appendingPathComponent("Sketch.svg"), expecting: .absent)
        await workspace.beginEditingDrawing(at: sketchPath)
        let request = try XCTUnwrap(workspace.drawingEditorRequest)
        XCTAssertEqual(request.format, .svg)
        XCTAssertTrue(request.pictures.isEmpty)

        // A picture placed below the ink, as the editor places one.
        let savedInk = try PKDrawing(data: request.initialStrokeData)
        let picture = DrawingBackgroundImage(imageData: try jpegData(size: CGSize(width: 300, height: 150), color: .red),
                                             frame: CGRect(x: 200, y: savedInk.bounds.maxY + 40, width: 300, height: 150))
        let content = DrawingContent(strokeData: request.initialStrokeData, canvasWidth: request.resolvedCanvasWidth, background: request.background, pictures: [picture])
        try await workspace.saveDrawing(content, format: request.format, for: request)
        XCTAssertNil(workspace.errorMessage)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { name in !name.hasPrefix("index.sqlite") }
        XCTAssertEqual(files, ["Sketch.svg"], "The drawing keeps its name and format; notes embed it by its name.")

        workspace.drawingEditorRequest = nil
        await workspace.beginEditingDrawing(at: sketchPath)
        let reopened = try XCTUnwrap(workspace.drawingEditorRequest)
        let reopenedPicture = try XCTUnwrap(reopened.pictures.first)
        XCTAssertEqual(reopenedPicture.imageData, picture.imageData)
        XCTAssertEqual(reopenedPicture.frame.size, picture.frame.size)
        let reopenedInk = try PKDrawing(data: reopened.initialStrokeData)
        XCTAssertEqual(reopenedPicture.frame.minX - reopenedInk.bounds.minX, picture.frame.minX - savedInk.bounds.minX, accuracy: 0.01)
        XCTAssertEqual(reopenedPicture.frame.minY - reopenedInk.bounds.minY, picture.frame.minY - savedInk.bounds.minY, accuracy: 0.01,
                       "The picture stays where it was put relative to the ink.")
    }

    // MARK: Helpers

    private func choose(_ format: DrawingFormat, in workspace: WorkspaceModel) {
        if drawingFormatBeforeTest == nil { drawingFormatBeforeTest = workspace.preferences.drawingFormat }
        workspace.preferences.drawingFormat = format
    }

    private func makeWorkspace(notes: [String: String]) async throws -> (WorkspaceModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPictures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        locations.append(directory)
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        return (workspace, directory)
    }

    private func stroke(through locations: [CGPoint], width: CGFloat) -> PKStroke {
        let points = locations.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: Double(pointIndex) / 60, size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func jpegData(size: CGSize, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    /// Blue on the left half, nothing on the right half.
    private func halfTransparentPNGData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        return try XCTUnwrap(image.pngData())
    }

    /// The first page as Core Graphics draws it, over white, at twice its size.
    private func pdfPageImage(_ fileData: Data) throws -> CGImage {
        let page = try XCTUnwrap(CGDataProvider(data: fileData as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(box.width * 2), height: Int(box.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: box.width * 2, height: box.height * 2))
        context.scaleBy(x: 2, y: 2)
        context.drawPDFPage(page)
        return try XCTUnwrap(context.makeImage())
    }

    /// The color over white at a point given in drawing points from the top-left corner.
    private func color(of image: CGImage, atPoint point: CGPoint, drawingSize: CGSize) throws -> (red: Double, green: Double, blue: Double) {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel: [UInt8] = [255, 255, 255, 255]
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let column = (point.x / drawingSize.width * Double(image.width)).rounded(.down)
        let rowFromTop = (point.y / drawingSize.height * Double(image.height)).rounded(.down)
        // Core Graphics counts rows from the bottom.
        context.draw(image, in: CGRect(x: -column, y: -(Double(image.height) - rowFromTop - 1), width: Double(image.width), height: Double(image.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// The SVG as WebKit shows it in a page's `<img>`, the way Obsidian embeds an SVG.
    /// Pictures in data URIs are decoded after the page loads, so snapshots are taken until
    /// `isComplete` accepts one.
    private func webKitImage(ofSVG svgData: Data, size: CGSize, isComplete: @escaping (CGImage) -> Bool) async throws -> CGImage {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPicturesWeb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        locations.append(directory)
        try svgData.write(to: directory.appendingPathComponent("Drawing.svg"))
        let page = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html, body { margin: 0; padding: 0; background: white; } img { display: block; }</style></head>
        <body><img src="Drawing.svg" width="\(Int(size.width))" height="\(Int(size.height))"></body></html>
        """
        let pageLocation = directory.appendingPathComponent("Page.html")
        try Data(page.utf8).write(to: pageLocation)

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
        // Otherwise the page starts below the window's status bar, not at the snapshot's top.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        controller.view.addSubview(webView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { connectedScene in connectedScene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        let navigationWaiter = NavigationWaiter()
        webView.navigationDelegate = navigationWaiter
        webView.loadFileURL(pageLocation, allowingReadAccessTo: directory)
        try await navigationWaiter.waitForLoad()
        var lastImage: CGImage?
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: size)
            let snapshot = try await webView.takeSnapshot(configuration: configuration)
            let image = try XCTUnwrap(snapshot.cgImage)
            lastImage = image
            if isComplete(image) { break }
        }
        return try XCTUnwrap(lastImage)
    }

    @MainActor
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, any Error>?
        private var outcome: Result<Void, any Error>?

        func waitForLoad() async throws {
            if let outcome { return try outcome.get() }
            try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
        }

        private func finish(_ result: Result<Void, any Error>) {
            if let continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else {
                outcome = result
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    }

    private func attach(_ image: CGImage, named name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
