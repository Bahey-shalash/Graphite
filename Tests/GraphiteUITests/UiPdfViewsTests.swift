import XCTest
import PDFKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteApple
@testable import GraphiteUI

#if os(macOS)
import AppKit

@MainActor
final class UiPdfViewsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("UiPdfViews-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: Current page on the Mac

    /// The Mac viewer used to leave the session on the first page, so the page menu's
    /// Delete Page removed page 1 while the user looked at page 8.
    func testMacViewerKeepsTheCurrentPageOnThePageScrolledTo() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Lecture.pdf", pageCount: 20))
        let window = try host(GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)))
        defer { window.close() }
        let pdfView = try XCTUnwrap(session.pdfView)

        pdfView.go(to: try XCTUnwrap(session.document.page(at: 7)))
        try await waitUntil { session.currentPageIndex == 7 }
        XCTAssertEqual(session.currentPageIndex, 7)

        pdfView.go(to: try XCTUnwrap(session.document.page(at: 12)))
        try await waitUntil { session.currentPageIndex == 12 }
        XCTAssertEqual(session.currentPageIndex, 12)
    }

    // MARK: Form fields

    /// A value typed into a form field changed only the live document; the save replays
    /// recorded edits on the file, so the value was dropped without a word.
    func testFormFieldsOnShownPagesAreReadOnlyAndTheFileIsUntouched() async throws {
        let location = temporaryDirectory.appendingPathComponent("Worksheet.pdf")
        let worksheet = PDFDocument()
        worksheet.insert(PDFPage(), at: 0)
        let field = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "Name"
        worksheet.page(at: 0)?.addAnnotation(field)
        XCTAssertTrue(worksheet.write(to: location))
        let originalBytes = try Data(contentsOf: location)

        let session = try await PDFSession.open(location)
        let window = try host(GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)))
        defer { window.close() }
        let liveField = try XCTUnwrap(session.document.page(at: 0)?.annotations.first { annotation in annotation.type == "Widget" })
        try await waitUntil { liveField.isReadOnly }

        XCTAssertTrue(liveField.isReadOnly)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
    }

    // MARK: Thumbnails

    /// Page content is now drawn off the main actor from the Core Graphics page, with the
    /// annotations drawn over it; the result must match PDFKit's own drawing at every turn.
    func testThumbnailsMatchPDFKitDrawingForEveryRotation() async throws {
        for rotation in [0, 90, 180, 270] {
            let document = try XCTUnwrap(PDFDocument(url: try makePDF(named: "Rotated \(rotation).pdf", pageCount: 1, pageSize: CGSize(width: 300, height: 500))))
            let page = try XCTUnwrap(document.page(at: 0))
            page.rotation = rotation
            let highlight = PDFAnnotation(bounds: CGRect(x: 200, y: 40, width: 80, height: 60), forType: .square, withProperties: nil)
            highlight.color = .red
            highlight.interiorColor = .red
            page.addAnnotation(highlight)
            // Ink under a live Pencil canvas is hidden in the document and still shown.
            let hiddenInk = PDFAnnotation(bounds: CGRect(x: 30, y: 300, width: 60, height: 60), forType: .square, withProperties: nil)
            hiddenInk.color = .blue
            hiddenInk.interiorColor = .blue
            hiddenInk.setValue("GraphitePageInkV1", forAnnotationKey: PDFPageManager.groupKey)
            hiddenInk.shouldDisplay = false
            page.addAnnotation(hiddenInk)

            let renderer = PDFThumbnailRenderer()
            let thumbnail = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
            let renderedImage = try XCTUnwrap(thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let referenceImage = try XCTUnwrap(pdfKitDrawing(of: page, hiddenInk: [hiddenInk], width: renderedImage.width, height: renderedImage.height))

            let differingFraction = try fractionOfDifferingPixels(renderedImage, referenceImage)
            XCTAssertLessThan(differingFraction, 0.02, "rotation \(rotation): \(differingFraction)")
        }
    }

    /// A scanned page decoded its full-size image on the main thread for every row. The
    /// main thread now only draws the annotations while the content renders elsewhere.
    func testScannedPageThumbnailRendersWithoutBlockingTheMainThread() async throws {
        let scannedLocation = try makeScannedPDF()
        let referenceDocument = try XCTUnwrap(PDFDocument(url: scannedLocation))
        let referencePage = try XCTUnwrap(referenceDocument.page(at: 0))
        let clock = ContinuousClock()
        let synchronousDuration = clock.measure { _ = referencePage.thumbnail(of: CGSize(width: 150, height: 200), for: .cropBox) }

        let document = try XCTUnwrap(PDFDocument(url: scannedLocation))
        let page = try XCTUnwrap(document.page(at: 0))
        let renderer = PDFThumbnailRenderer()
        var isFinished = false
        let renderTask = Task { @MainActor in
            let image = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
            isFinished = true
            return image
        }
        var longestMainThreadGap = Duration.zero
        var lastWake = clock.now
        let start = clock.now
        while !isFinished, clock.now - start < .seconds(20) {
            try await Task.sleep(for: .milliseconds(2))
            let now = clock.now
            longestMainThreadGap = max(longestMainThreadGap, now - lastWake)
            lastWake = now
        }
        let image = await renderTask.value
        XCTAssertNotNil(image)
        print("UiPdfViews scanned thumbnail: synchronous \(synchronousDuration), longest main-thread gap while rendering \(longestMainThreadGap)")
        if synchronousDuration > .milliseconds(40) {
            XCTAssertLessThan(longestMainThreadGap, synchronousDuration / 2)
        }
    }

    /// The cache retained its page keys, so a released PDF's pages stayed alive with it.
    func testThumbnailCacheKeepsNoPageOfAReleasedPDFAlive() async throws {
        let location = try makePDF(named: "Released.pdf", pageCount: 2)
        let renderer = PDFThumbnailRenderer()
        weak var releasedDocument: PDFDocument?
        weak var releasedPage: PDFPage?
        do {
            let document = try XCTUnwrap(PDFDocument(url: location))
            let page = try XCTUnwrap(document.page(at: 0))
            let thumbnail = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
            XCTAssertNotNil(thumbnail)
            releasedDocument = document
            releasedPage = page
        }
        try await waitUntil { releasedPage == nil && releasedDocument == nil }
        XCTAssertNil(releasedPage)
        XCTAssertNil(releasedDocument)
    }

    /// A drag preview's small image was reused for the row, stretched and blurry.
    func testThumbnailsOfEachSizeAreCachedSeparately() async throws {
        let document = try XCTUnwrap(PDFDocument(url: try makePDF(named: "Sizes.pdf", pageCount: 1)))
        let page = try XCTUnwrap(document.page(at: 0))
        let renderer = PDFThumbnailRenderer()

        let renderedDragPreview = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 75, height: 100), scale: 2)
        let renderedRow = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
        let dragPreview = try XCTUnwrap(renderedDragPreview)
        let row = try XCTUnwrap(renderedRow)
        XCTAssertEqual(dragPreview.size.width, 75)
        XCTAssertEqual(row.size.width, 150)
        XCTAssertEqual(row.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 300)

        let cachedRow = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
        let cachedDragPreview = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 75, height: 100), scale: 2)
        XCTAssertTrue(cachedRow === row)
        XCTAssertTrue(cachedDragPreview === dragPreview)
        let sharperRow = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 3)
        XCTAssertEqual(sharperRow?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 450)
    }

    /// An embed that released its PDF kept up to the whole cache budget of thumbnails.
    func testRemovingThumbnailsDropsOnlyThatViewersImages() async throws {
        let document = try XCTUnwrap(PDFDocument(url: try makePDF(named: "Removed.pdf", pageCount: 2)))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let secondPage = try XCTUnwrap(document.page(at: 1))
        let embedRenderer = PDFThumbnailRenderer()
        let paneRenderer = PDFThumbnailRenderer()
        let size = CGSize(width: 150, height: 200)
        let embedThumbnail = await embedRenderer.thumbnail(for: firstPage, version: 0, fitting: size, scale: 2)
        let paneThumbnail = await paneRenderer.thumbnail(for: secondPage, version: 0, fitting: size, scale: 2)

        embedRenderer.removeThumbnails()

        let embedThumbnailAgain = await embedRenderer.thumbnail(for: firstPage, version: 0, fitting: size, scale: 2)
        let paneThumbnailAgain = await paneRenderer.thumbnail(for: secondPage, version: 0, fitting: size, scale: 2)
        XCTAssertNotNil(embedThumbnailAgain)
        XCTAssertFalse(embedThumbnailAgain === embedThumbnail)
        XCTAssertTrue(paneThumbnailAgain === paneThumbnail)
    }

    /// Pages of the open file are drawn from a separate copy, so their decoded content does
    /// not stay in the live document; the copy is mapped before a save removes the file.
    func testPageContentIsDrawnFromTheMappedFileAfterTheFileIsRemoved() async throws {
        let snapshotLocation = try makePDF(named: "Snapshot.pdf", pageCount: 3)
        let document = try XCTUnwrap(PDFDocument(url: snapshotLocation))
        let renderer = PDFThumbnailRenderer()
        renderer.prepare(for: document)
        try FileManager.default.removeItem(at: snapshotLocation)
        document.exchangePage(at: 0, withPageAt: 2)

        for pageIndex in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let thumbnail = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
            let renderedImage = try XCTUnwrap(thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let referenceImage = try XCTUnwrap(pdfKitDrawing(of: page, hiddenInk: [], width: renderedImage.width, height: renderedImage.height))
            let differingFraction = try fractionOfDifferingPixels(renderedImage, referenceImage)
            XCTAssertLessThan(differingFraction, 0.02, "page \(pageIndex): \(differingFraction)")
        }
    }

    func testContentRendererDrawsFromItsSourceOnlyWhenTheSourceIsThatFile() async throws {
        let livePage = try XCTUnwrap(PDFDocument(url: try makePDF(named: "Live.pdf", pageCount: 1))?.page(at: 0))
        let sourceData = try NSData(contentsOf: try makeFilledPDF(named: "Source.pdf", pageCount: 1, gray: 0), options: .alwaysMapped)
        let contentRenderer = PDFPageContentRenderer()
        let size = CGSize(width: 150, height: 200)

        let matchingSource = PDFPageContentSource(fileData: sourceData, pageNumber: 1, filePageCount: 1)
        let matchingContent = try XCTUnwrap(PDFPageContent(page: livePage, fitting: size, scale: 2, source: matchingSource))
        let renderedFromSource = await contentRenderer.render(matchingContent)
        XCTAssertLessThan(try averageBrightness(of: try XCTUnwrap(renderedFromSource)), 0.1)

        let otherFileSource = PDFPageContentSource(fileData: sourceData, pageNumber: 1, filePageCount: 2)
        let otherFileContent = try XCTUnwrap(PDFPageContent(page: livePage, fitting: size, scale: 2, source: otherFileSource))
        let renderedFromLivePage = await contentRenderer.render(otherFileContent)
        XCTAssertGreaterThan(try averageBrightness(of: try XCTUnwrap(renderedFromLivePage)), 0.5)
    }

    /// A page without a Core Graphics page is drawn whole on the main actor; ink hidden
    /// under a Pencil canvas still shows, on the Mac as on iPad.
    func testPageWithoutCoreGraphicsPageShowsItsHiddenInk() async throws {
        let page = PDFPage()
        XCTAssertNil(page.pageRef)
        let pageBounds = page.bounds(for: .cropBox)
        let hiddenInk = PDFAnnotation(bounds: pageBounds, forType: .square, withProperties: nil)
        hiddenInk.color = .blue
        hiddenInk.interiorColor = .blue
        hiddenInk.setValue("GraphitePageInkV1", forAnnotationKey: PDFPageManager.groupKey)
        hiddenInk.shouldDisplay = false
        page.addAnnotation(hiddenInk)

        let thumbnail = await PDFThumbnailRenderer().thumbnail(for: page, version: 0, fitting: CGSize(width: 150, height: 200), scale: 2)
        let image = try XCTUnwrap(thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixels = try rgbaPixels(of: image)
        let centerStart = ((image.height / 2) * image.width + image.width / 2) * 4
        XCTAssertLessThan(pixels[centerStart], 80)
        XCTAssertGreaterThan(pixels[centerStart + 2], 180)
    }

    // MARK: Embeds of one PDF

    /// Two embeds of one PDF each had their own copy; after one saved, the other's save
    /// was refused as a change made "in another app".
    func testAnnotatingASecondEmbedSavesTheFirstAndReadsTheFileAgain() async throws {
        let location = try makePDF(named: "Slides.pdf", pageCount: 3)
        let sessions = EmbeddedPDFSessions()
        let firstEmbedSession = try await PDFSession.open(location)
        let secondEmbedSession = try await PDFSession.open(location)
        sessions.add(firstEmbedSession)
        sessions.add(secondEmbedSession)

        let firstAnnotated = try await sessions.prepareToAnnotate(firstEmbedSession)
        XCTAssertTrue(firstAnnotated === firstEmbedSession)
        try firstEmbedSession.addBookmark(pageIndex: 0)
        secondEmbedSession.currentPageIndex = 2

        let secondAnnotated = try await sessions.prepareToAnnotate(secondEmbedSession)
        XCTAssertFalse(firstEmbedSession.hasUnsavedChanges)
        XCTAssertFalse(secondAnnotated === secondEmbedSession)
        XCTAssertEqual(secondAnnotated.currentPageIndex, 2)
        XCTAssertEqual(sessions.annotatingSession(at: location), ObjectIdentifier(secondAnnotated))
        XCTAssertEqual(sessions.otherSessions(showing: location, besides: secondAnnotated).map(ObjectIdentifier.init), [ObjectIdentifier(firstEmbedSession)])

        try secondAnnotated.addBookmark(pageIndex: 2)
        try await secondAnnotated.saveBeforeClosing()
        XCTAssertFalse(secondAnnotated.hasExternalConflict)
        XCTAssertEqual(PDFDocument(url: location)?.outlineRoot?.numberOfChildren, 2)
    }

    func testASessionWhoseClosingSaveFailedIsKeptForTheNextEmbedOfItsPDF() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let sessions = EmbeddedPDFSessions()
        let session = try await PDFSession.open(location)
        sessions.add(session)
        sessions.remove(session)
        sessions.keep(session)

        XCTAssertNil(sessions.takeKeptSession(at: temporaryDirectory.appendingPathComponent("Other.pdf")))
        XCTAssertTrue(sessions.takeKeptSession(at: location) === session)
        XCTAssertNil(sessions.takeKeptSession(at: location))
    }

    // MARK: Helpers

    private func makePDF(named name: String, pageCount: Int, pageSize: CGSize = CGSize(width: 612, height: 792)) throws -> URL {
        let location = temporaryDirectory.appendingPathComponent(name)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            // A dark block in the top-left corner shows which way the page is turned.
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: 20, y: pageSize.height - 120, width: 100 + CGFloat(pageIndex % 5) * 10, height: 100))
            context.setFillColor(CGColor(red: 0, green: 0.6, blue: 0, alpha: 1))
            context.fill(CGRect(x: pageSize.width / 2, y: 20, width: pageSize.width / 2 - 20, height: 40))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func makeFilledPDF(named name: String, pageCount: Int, gray: CGFloat) throws -> URL {
        let location = temporaryDirectory.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func averageBrightness(of image: CGImage) throws -> Double {
        let pixels = try rgbaPixels(of: image)
        var total = 0
        for pixelStart in stride(from: 0, to: pixels.count, by: 4) { total += Int(pixels[pixelStart]) + Int(pixels[pixelStart + 1]) + Int(pixels[pixelStart + 2]) }
        return Double(total) / Double(max(1, pixels.count / 4) * 3 * 255)
    }

    /// A page that draws a 2550×3300 JPEG, like a 300-dpi scan.
    private func makeScannedPDF() throws -> URL {
        let width = 2550
        let height = 3300
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let pixelBytes = try XCTUnwrap(bitmap.data)
        arc4random_buf(pixelBytes, width * height * 4)
        let noiseImage = try XCTUnwrap(bitmap.makeImage())
        let jpegData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, noiseImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpegData, nil))
        let scanImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let location = temporaryDirectory.appendingPathComponent("Scan.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.draw(scanImage, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return location
    }

    private func host(_ view: GraphitePDFView) throws -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: view)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// PDFKit's own drawing of the page, as the renderer drew it before.
    private func pdfKitDrawing(of page: PDFPage, hiddenInk: [PDFAnnotation], width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cropBox = page.bounds(for: .cropBox)
        let displayedWidth = page.rotation % 180 == 0 ? cropBox.width : cropBox.height
        let scale = CGFloat(width) / displayedWidth
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        for annotation in hiddenInk { annotation.draw(with: .cropBox, in: context) }
        return context.makeImage()
    }

    private func fractionOfDifferingPixels(_ firstImage: CGImage, _ secondImage: CGImage) throws -> Double {
        XCTAssertEqual(firstImage.width, secondImage.width)
        XCTAssertEqual(firstImage.height, secondImage.height)
        let firstPixels = try rgbaPixels(of: firstImage)
        let secondPixels = try rgbaPixels(of: secondImage)
        var differingPixelCount = 0
        for pixelStart in stride(from: 0, to: min(firstPixels.count, secondPixels.count), by: 4) {
            let isDifferent = (0..<3).contains { channel in abs(Int(firstPixels[pixelStart + channel]) - Int(secondPixels[pixelStart + channel])) > 64 }
            if isDifferent { differingPixelCount += 1 }
        }
        return Double(differingPixelCount) / Double(max(1, firstPixels.count / 4))
    }

    private func rgbaPixels(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(didDraw)
        return pixels
    }
}
#endif
