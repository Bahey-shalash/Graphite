import XCTest
import PDFKit
import CoreGraphics
import ImageIO
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteApple

/// Pictures placed on PDF pages: what the open document shows, what the saved file shows
/// in any reader, and what Graphite reads back to move or restore them.
final class PDFPictureTests: XCTestCase {
    private static let pageSize = CGSize(width: 200, height: 300)

    /// A picture whose left half is red and right half blue, so its orientation shows.
    private static func twoColorImageData(width: Int = 40, height: Int = 20, isOpaque: Bool = false) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let alphaInfo = isOpaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: alphaInfo.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private static func blankDocument(rotation: Int) throws -> PDFDocument {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let consumer = try XCTUnwrap(CGDataConsumer(data: pageData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: pageData as Data))
        try XCTUnwrap(document.page(at: 0)).rotation = rotation
        return document
    }

    private enum SeenColor: Equatable { case red, blue, white, other(Int, Int, Int) }

    /// The color at a point of the page as it is shown, counted from its top-left corner.
    private func color(of page: PDFPage, atShownPoint point: CGPoint) throws -> SeenColor {
        let isSideways = page.rotation % 180 != 0
        let shownSize = isSideways ? CGSize(width: Self.pageSize.height, height: Self.pageSize.width) : Self.pageSize
        let thumbnail = page.thumbnail(of: shownSize, for: .cropBox)
        #if canImport(UIKit)
        let image = try XCTUnwrap(thumbnail.cgImage)
        #else
        let image = try XCTUnwrap(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #endif
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let scaleX = Double(image.width) / shownSize.width, scaleY = Double(image.height) / shownSize.height
        // Draw the image so the wanted pixel lands on the context's single pixel; rows count up.
        context.draw(image, in: CGRect(x: -point.x * scaleX, y: -(shownSize.height - point.y) * scaleY + 1, width: Double(image.width), height: Double(image.height)))
        let red = Int(pixel[0]), green = Int(pixel[1]), blue = Int(pixel[2])
        if red > 200, green < 80, blue < 80 { return .red }
        if blue > 200, red < 80, green < 80 { return .blue }
        if red > 235, green > 235, blue > 235 { return .white }
        return .other(red, green, blue)
    }

    // MARK: What is shown

    func testPictureIsUprightAndInPlaceOnPagesOfEveryRotationInTheOpenAndTheSavedDocument() throws {
        // Where the picture's bounds (20, 200, 100, 50) are on the page as it is shown, and
        // a point in its left and its right half as the reader sees them.
        let expectations: [(rotation: Int, leftHalf: CGPoint, rightHalf: CGPoint, outside: CGPoint)] = [
            (0, CGPoint(x: 40, y: 75), CGPoint(x: 100, y: 75), CGPoint(x: 160, y: 200)),
            (90, CGPoint(x: 210, y: 70), CGPoint(x: 240, y: 70), CGPoint(x: 100, y: 100)),
            (180, CGPoint(x: 100, y: 225), CGPoint(x: 160, y: 225), CGPoint(x: 40, y: 75)),
            (270, CGPoint(x: 60, y: 130), CGPoint(x: 90, y: 130), CGPoint(x: 200, y: 100)),
        ]
        for expectation in expectations {
            let picture = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50),
                                     quarterTurns: expectation.rotation / 90)
            let openDocument = try Self.blankDocument(rotation: expectation.rotation)
            try PDFPageManager.apply(.addPicture(page: 0, picture: picture), to: openDocument)
            let writtenDocument = try Self.blankDocument(rotation: expectation.rotation)
            try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: writtenDocument)
            let savedDocument = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation())))
            for (label, document) in [("open", openDocument), ("saved", savedDocument)] {
                let page = try XCTUnwrap(document.page(at: 0))
                let context = "\(label) document, page turned \(expectation.rotation)°"
                XCTAssertEqual(try color(of: page, atShownPoint: expectation.leftHalf), .red, "Left half in the \(context)")
                XCTAssertEqual(try color(of: page, atShownPoint: expectation.rightHalf), .blue, "Right half in the \(context)")
                XCTAssertEqual(try color(of: page, atShownPoint: expectation.outside), .white, "Beside the picture in the \(context)")
            }
        }
    }

    // MARK: What is read back

    func testSavedPictureIsReadBackExactlyAlsoWhenItIsAJPEG() throws {
        // Opaque pictures are prepared as JPEG, whose base64 text starts with a slash.
        let prepared = try DrawingPictures.picture(from: try Self.twoColorImageData(width: 600, height: 400, isOpaque: true), canvasWidth: 300)
        XCTAssertTrue(prepared.imageData.starts(with: [0xFF, 0xD8]))
        XCTAssertTrue(prepared.imageData.base64EncodedString().hasPrefix("/"))
        let pictures = [PDFPicture(imageData: prepared.imageData, bounds: CGRect(x: 20, y: 100, width: 150, height: 100), quarterTurns: 1),
                        PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 10, y: 10, width: 40, height: 20), quarterTurns: 0)]
        let writtenDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay(pictures.map { picture in .addPicture(page: 0, picture: picture) }, on: writtenDocument)
        let savedPage = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation()))?.page(at: 0))
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage), pictures)
        // Any reader sees standard stamp annotations.
        XCTAssertEqual(savedPage.annotations.map(\.type), ["Stamp", "Stamp"])
        // Another application's stamp is not one of Graphite's pictures.
        let foreignStamp = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), forType: .stamp, withProperties: nil)
        XCTAssertNil(PDFPicture(annotation: foreignStamp))
    }

    func testMovingAPictureKeepsItsNameAndBytesAndRemovingItLeavesTheOthers() throws {
        let first = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0)
        let second = PDFPicture(imageData: try Self.twoColorImageData(width: 20, height: 20), bounds: CGRect(x: 10, y: 10, width: 40, height: 40), quarterTurns: 0)
        let newBounds = CGRect(x: 60, y: 100, width: 50, height: 25)
        let edits: [PDFEdit] = [.addPicture(page: 0, picture: first), .addPicture(page: 0, picture: second),
                                .movePicture(first.reference(onPageAt: 0), to: newBounds)]
        let writtenDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay(edits, on: writtenDocument)
        let savedDocument = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation())))
        let savedPage = try XCTUnwrap(savedDocument.page(at: 0))
        var moved = first
        moved.bounds = newBounds
        // The picture moved last is over the other one.
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage), [second, moved])
        XCTAssertEqual(try color(of: savedPage, atShownPoint: CGPoint(x: 70, y: 300 - 112)), .red, "The picture is shown at its new place and size.")
        XCTAssertEqual(try color(of: savedPage, atShownPoint: CGPoint(x: 40, y: 75)), .white, "Nothing is left at its old place.")

        // A picture read from a file moves and is removed by its name as well.
        try PDFPageManager.apply(.movePicture(moved.reference(onPageAt: 0), to: first.bounds), to: savedDocument)
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage).last, first)
        try PDFPageManager.apply(.removeAnnotation(first.reference(onPageAt: 0)), to: savedDocument)
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage), [second])
        XCTAssertThrowsError(try PDFPageManager.apply(.movePicture(first.reference(onPageAt: 0), to: newBounds), to: savedDocument))
    }

    // MARK: Turning, cropping and ordering

    /// The color at a point of a picture's own image, counted in fractions from its top-left corner.
    private func color(ofImage imageData: Data, atFraction fraction: CGPoint) throws -> SeenColor {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let column = Double(image.width) * fraction.x, rowFromTop = Double(image.height) * fraction.y
        context.draw(image, in: CGRect(x: -column, y: -(Double(image.height) - rowFromTop - 1), width: Double(image.width), height: Double(image.height)))
        let red = Int(pixel[0]), green = Int(pixel[1]), blue = Int(pixel[2])
        if red > 200, green < 80, blue < 80 { return .red }
        if blue > 200, red < 80, green < 80 { return .blue }
        if red > 235, green > 235, blue > 235 { return .white }
        return .other(red, green, blue)
    }

    private func pixelSize(of imageData: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    func testAPictureTurnsClockwiseAndKeepsItsKindOfFile() throws {
        // Red on the left, blue on the right; turned clockwise, red is on top.
        let picture = try Self.twoColorImageData(width: 40, height: 20)
        let turned = try PictureEditing.rotatedClockwise(picture)
        XCTAssertEqual(try pixelSize(of: turned), CGSize(width: 20, height: 40))
        XCTAssertEqual(try color(ofImage: turned, atFraction: CGPoint(x: 0.5, y: 0.25)), .red)
        XCTAssertEqual(try color(ofImage: turned, atFraction: CGPoint(x: 0.5, y: 0.75)), .blue)
        XCTAssertTrue(turned.starts(with: [0x89, 0x50, 0x4E, 0x47]), "A PNG stays a PNG.")
        // Four turns bring it back.
        var turnedFourTimes = picture
        for _ in 0..<4 { turnedFourTimes = try PictureEditing.rotatedClockwise(turnedFourTimes) }
        XCTAssertEqual(try pixelSize(of: turnedFourTimes), CGSize(width: 40, height: 20))
        XCTAssertEqual(try color(ofImage: turnedFourTimes, atFraction: CGPoint(x: 0.2, y: 0.5)), .red)
        // A photograph stays a JPEG.
        let photograph = try DrawingPictures.picture(from: try Self.twoColorImageData(width: 600, height: 400, isOpaque: true), canvasWidth: 300).imageData
        XCTAssertTrue(try PictureEditing.rotatedClockwise(photograph).starts(with: [0xFF, 0xD8]))
        XCTAssertThrowsError(try PictureEditing.rotatedClockwise(Data("not an image".utf8)))
    }

    func testACropKeepsThePartInsideAndRefusesACropTooSmall() throws {
        let picture = try Self.twoColorImageData(width: 40, height: 20)
        let rightHalf = try PictureEditing.cropped(picture, to: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(try pixelSize(of: rightHalf), CGSize(width: 20, height: 20))
        XCTAssertEqual(try color(ofImage: rightHalf, atFraction: CGPoint(x: 0.1, y: 0.5)), .blue)
        // A crop reaching past the picture keeps only what is in it.
        let overhanging = try PictureEditing.cropped(picture, to: CGRect(x: -0.5, y: -1, width: 1, height: 3))
        XCTAssertEqual(try pixelSize(of: overhanging), CGSize(width: 20, height: 20))
        XCTAssertEqual(try color(ofImage: overhanging, atFraction: CGPoint(x: 0.9, y: 0.5)), .red)
        XCTAssertThrowsError(try PictureEditing.cropped(picture, to: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.9)), "Two pixels wide is too small.")
        XCTAssertThrowsError(try PictureEditing.cropped(picture, to: CGRect(x: 2, y: 2, width: 1, height: 1)), "Nothing inside.")
    }

    func testACropOnScreenIsTheRightPartOfAPictureShownTurned() {
        // The top-left quarter of what is shown.
        let shownTopLeft = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: shownTopLeft, turnedClockwise: 0), shownTopLeft)
        // Turned clockwise a quarter, the shown top-left is the image's bottom-left.
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: shownTopLeft, turnedClockwise: 1), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: shownTopLeft, turnedClockwise: 2), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: shownTopLeft, turnedClockwise: 3), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: shownTopLeft, turnedClockwise: -1), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        // A strip along the shown top, turned a quarter, is a strip along the image's left side.
        XCTAssertEqual(PictureEditing.imageRegion(forDisplayedRegion: CGRect(x: 0, y: 0, width: 1, height: 0.25), turnedClockwise: 1),
                       CGRect(x: 0, y: 0, width: 0.25, height: 1))
    }

    func testAReplacedPictureTakesItsPlaceAmongThePicturesUnderTheInk() throws {
        let first = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0)
        let second = PDFPicture(imageData: try Self.twoColorImageData(width: 20, height: 20), bounds: CGRect(x: 10, y: 10, width: 40, height: 40), quarterTurns: 0)
        let third = PDFPicture(imageData: try Self.twoColorImageData(width: 30, height: 30), bounds: CGRect(x: 100, y: 10, width: 40, height: 40), quarterTurns: 0)
        let document = try Self.blankDocument(rotation: 0)
        let page = try XCTUnwrap(document.page(at: 0))
        // Another application's note, which Graphite leaves where it is.
        let foreignNote = PDFAnnotation(bounds: CGRect(x: 150, y: 250, width: 20, height: 20), forType: .text, withProperties: nil)
        page.addAnnotation(foreignNote)
        try PDFPageManager.replay([first, second, third].map { picture in .addPicture(page: 0, picture: picture) }, on: document)

        // Turned in place: same name and position among the pictures, new bytes and bounds.
        var turned = first
        turned.imageData = try PictureEditing.rotatedClockwise(first.imageData)
        turned.bounds = CGRect(x: 45, y: 175, width: 50, height: 100)
        try PDFPageManager.apply(.replacePicture(first.reference(onPageAt: 0), with: turned, order: .unchanged), to: document)
        XCTAssertEqual(PDFPageManager.pictures(on: page), [turned, second, third])
        XCTAssertTrue(page.annotations.contains { annotation in annotation === foreignNote })

        try PDFPageManager.apply(.replacePicture(turned.reference(onPageAt: 0), with: turned, order: .front), to: document)
        XCTAssertEqual(PDFPageManager.pictures(on: page).map(\.name), [second.name, third.name, turned.name])
        try PDFPageManager.apply(.replacePicture(third.reference(onPageAt: 0), with: third, order: .back), to: document)
        XCTAssertEqual(PDFPageManager.pictures(on: page).map(\.name), [third.name, second.name, turned.name])
        try PDFPageManager.apply(.replacePicture(turned.reference(onPageAt: 0), with: turned, order: .position(1)), to: document)
        XCTAssertEqual(PDFPageManager.pictures(on: page).map(\.name), [third.name, turned.name, second.name])

        // The same edits on the file give the same page, shown turned.
        let written = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay([first, second, third].map { picture in .addPicture(page: 0, picture: picture) }
                                  + [.replacePicture(first.reference(onPageAt: 0), with: turned, order: .unchanged)], on: written)
        let savedPage = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(written.dataRepresentation()))?.page(at: 0))
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage), [turned, second, third])
        // Red on top, blue under it, as the turned picture is shown.
        XCTAssertEqual(try color(of: savedPage, atShownPoint: CGPoint(x: 70, y: 300 - 250)), .red)
        XCTAssertEqual(try color(of: savedPage, atShownPoint: CGPoint(x: 70, y: 300 - 200)), .blue)
        XCTAssertThrowsError(try PDFPageManager.apply(.replacePicture(PDFAnnotationReference(pageIndex: 0, name: "gone", annotationType: "Stamp",
                                                                                             bounds: .zero), with: turned, order: .unchanged), to: document))
    }

    // MARK: Drawn smoothly after the PDF is opened again

    /// A zone plate: rings that grow finer away from the middle, an opaque gray picture that
    /// shows moiré wherever it is shown much smaller than its pixels without filtering.
    private static func ringPatternImageData(width: Int = 600, height: Int = 400) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            for column in 0..<width {
                let horizontalDistance = Double(column - width / 2), verticalDistance = Double(row - height / 2)
                let squaredDistance = horizontalDistance * horizontalDistance + verticalDistance * verticalDistance
                let gray = UInt8(127.5 + 127.5 * cos(squaredDistance * 0.004))
                let offset = row * width * 4 + column * 4
                pixels[offset] = gray; pixels[offset + 1] = gray; pixels[offset + 2] = gray; pixels[offset + 3] = 255
            }
        }
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    /// The page's gray levels as drawn, at one pixel per point, into a context with the
    /// lowest image interpolation.
    private func grayLevelsDrawnWithoutInterpolation(of page: PDFPage) throws -> [UInt8] {
        let box = page.bounds(for: .cropBox)
        let width = Int(box.width), height = Int(box.height)
        var grayLevels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(CGContext(data: &grayLevels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        page.draw(with: .cropBox, to: context)
        return grayLevels
    }

    private func rootMeanSquareDifference(_ firstLevels: [UInt8], _ secondLevels: [UInt8]) -> Double {
        guard firstLevels.count == secondLevels.count, !firstLevels.isEmpty else { return .infinity }
        let squaredSum = zip(firstLevels, secondLevels).reduce(0.0) { sum, levels in
            let difference = Double(levels.0) - Double(levels.1)
            return sum + difference * difference
        }
        return (squaredSum / Double(firstLevels.count)).squareRoot()
    }

    /// PDFKit draws a stamp read from a file from its saved appearance, which follows the
    /// interpolation of the context it is drawn into; PDFView draws pages with low
    /// interpolation on iOS, where a picture made small showed moiré once the PDF was
    /// opened again. In a document prepared for display, the stamp draws the picture from
    /// its own bytes, as while it is edited, and the file's annotation stays as it was.
    func testAPictureOfAReopenedPDFIsDrawnAsSmoothlyAsWhileItIsEdited() throws {
        let ringPattern = try Self.ringPatternImageData()
        for rotation in [0, 90] {
            for rotationRadians in [0, Double.pi / 6] {
                let context = "page turned \(rotation)°, picture turned \(rotationRadians) radians"
                // 600 pixels shown 120 points wide: five pixels to a point.
                let picture = PDFPicture(imageData: ringPattern, bounds: CGRect(x: 30, y: 120, width: 120, height: 80), quarterTurns: rotation / 90,
                                         rotationRadians: rotationRadians)
                let editedDocument = try Self.blankDocument(rotation: rotation)
                try PDFPageManager.apply(.addPicture(page: 0, picture: picture), to: editedDocument)
                let writtenDocument = try Self.blankDocument(rotation: rotation)
                try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: writtenDocument)
                let fileData = try XCTUnwrap(writtenDocument.dataRepresentation())
                let reopenedDocument = try XCTUnwrap(PDFDocument(data: fileData))
                PDFPageManager.prepareForDisplay(reopenedDocument)
                let unpreparedDocument = try XCTUnwrap(PDFDocument(data: fileData))

                let editedLevels = try grayLevelsDrawnWithoutInterpolation(of: try XCTUnwrap(editedDocument.page(at: 0)))
                let reopenedPage = try XCTUnwrap(reopenedDocument.page(at: 0))
                let reopenedDifference = rootMeanSquareDifference(try grayLevelsDrawnWithoutInterpolation(of: reopenedPage), editedLevels)
                let unpreparedDifference = rootMeanSquareDifference(try grayLevelsDrawnWithoutInterpolation(of: try XCTUnwrap(unpreparedDocument.page(at: 0))),
                                                                    editedLevels)
                XCTAssertLessThan(reopenedDifference, 0.5, "Opened again, the picture looks as it did while edited, \(context).")
                XCTAssertGreaterThan(unpreparedDifference, 3, "The saved appearance drawn without interpolation is what showed moiré, \(context).")
                // Graphite still reads the picture from the annotation the file has.
                let reopenedAnnotation = try XCTUnwrap(reopenedPage.annotations.first)
                XCTAssertTrue(reopenedAnnotation is PDFPictureAnnotation, context)
                let readBack = try XCTUnwrap(PDFPageManager.pictures(on: reopenedPage).first)
                XCTAssertEqual(readBack.name, picture.name)
                XCTAssertEqual(readBack.imageData, picture.imageData)
                XCTAssertEqual(readBack.rotationRadians, picture.rotationRadians, accuracy: 0.0001)
                assertEqual(readBack.bounds, picture.bounds, context)
            }
        }
    }

    /// Pages put back by undo come from a written PDF too; other annotations are read as
    /// PDFKit reads them without Graphite, and a stamp of another application is drawn
    /// from its own appearance.
    func testPicturesOfInsertedPagesAreDrawnTooAndOtherAnnotationsAreReadAsBefore() throws {
        let picture = PDFPicture(imageData: try Self.ringPatternImageData(), bounds: CGRect(x: 30, y: 120, width: 120, height: 80), quarterTurns: 0)
        let writtenDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: writtenDocument)
        let writtenPage = try XCTUnwrap(writtenDocument.page(at: 0))
        let foreignStamp = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 40), forType: .stamp, withProperties: nil)
        foreignStamp.stampName = "Approved"
        writtenPage.addAnnotation(foreignStamp)
        let link = PDFAnnotation(bounds: CGRect(x: 150, y: 250, width: 40, height: 20), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com")
        writtenPage.addAnnotation(link)
        let note = PDFAnnotation(bounds: CGRect(x: 150, y: 220, width: 20, height: 20), forType: .text, withProperties: nil)
        writtenPage.addAnnotation(note)
        let fileData = try XCTUnwrap(writtenDocument.dataRepresentation())

        let shownDocument = try Self.blankDocument(rotation: 0)
        PDFPageManager.prepareForDisplay(shownDocument)
        try PDFPageManager.apply(.insert(data: fileData, at: 0), to: shownDocument)
        let insertedPage = try XCTUnwrap(shownDocument.page(at: 0))
        let unpreparedDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.apply(.insert(data: fileData, at: 0), to: unpreparedDocument)
        let unpreparedPage = try XCTUnwrap(unpreparedDocument.page(at: 0))
        let annotationClasses = { (page: PDFPage) in page.annotations.map { annotation in String(describing: type(of: annotation)) } }
        let insertedClasses = annotationClasses(insertedPage), unpreparedClasses = annotationClasses(unpreparedPage)
        XCTAssertEqual(insertedClasses.count, 4)
        XCTAssertEqual(insertedClasses.first, String(describing: PDFPictureAnnotation.self))
        XCTAssertEqual(Array(insertedClasses.dropFirst(2)), Array(unpreparedClasses.dropFirst(2)), "A link and a note are read as before.")

        // The foreign stamp is drawn as PDFKit draws it: compared on a page without the picture.
        let pictureReference = picture.reference(onPageAt: 0)
        try PDFPageManager.apply(.removeAnnotation(pictureReference), to: shownDocument)
        try PDFPageManager.apply(.removeAnnotation(pictureReference), to: unpreparedDocument)
        let stampLevels = try grayLevelsDrawnWithoutInterpolation(of: insertedPage)
        XCTAssertTrue(stampLevels.contains { level in level < 200 }, "The foreign stamp is drawn.")
        XCTAssertEqual(rootMeanSquareDifference(stampLevels, try grayLevelsDrawnWithoutInterpolation(of: unpreparedPage)), 0)
    }

    // MARK: Turned by hand

    private func assertEqual(_ rectangle: CGRect?, _ expected: CGRect, accuracy: CGFloat = 0.01, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let rectangle else { return XCTFail("No rectangle. \(message)", file: file, line: line) }
        for (measuredEdge, expectedEdge) in zip([rectangle.minX, rectangle.minY, rectangle.width, rectangle.height], [expected.minX, expected.minY, expected.width, expected.height]) {
            XCTAssertEqual(measuredEdge, expectedEdge, accuracy: accuracy, "\(rectangle) is not \(expected). \(message)", file: file, line: line)
        }
    }

    func testAPictureTurnedByHandIsShownTurnedAndReadBackWithItsFrameAndAngle() throws {
        // Red on the left, blue on the right, at (20, 200, 100, 50). Turned a quarter
        // clockwise about its middle (70, 225), red is on top and the picture stands from
        // y 175 to 275, 50 points wide.
        let picture = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0,
                                 rotationRadians: .pi / 2)
        assertEqual(picture.annotationBounds, CGRect(x: 45, y: 175, width: 50, height: 100), "The annotation's rectangle is the box around it.")
        XCTAssertTrue(picture.contains(CGPoint(x: 70, y: 260)))
        XCTAssertFalse(picture.contains(CGPoint(x: 30, y: 225)), "Where its left end was before it turned.")

        let openDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.apply(.addPicture(page: 0, picture: picture), to: openDocument)
        let writtenDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: writtenDocument)
        let savedDocument = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation())))
        for (label, document) in [("open", openDocument), ("saved", savedDocument)] {
            let page = try XCTUnwrap(document.page(at: 0))
            XCTAssertEqual(try color(of: page, atShownPoint: CGPoint(x: 70, y: 300 - 260)), .red, "Its left end, on top, in the \(label) document")
            XCTAssertEqual(try color(of: page, atShownPoint: CGPoint(x: 70, y: 300 - 190)), .blue, "Its right end, below, in the \(label) document")
            XCTAssertEqual(try color(of: page, atShownPoint: CGPoint(x: 30, y: 300 - 225)), .white, "Nothing where it was upright, in the \(label) document")
        }

        // Graphite reads back the frame before the turn and the angle; any reader sees a stamp.
        let savedPage = try XCTUnwrap(savedDocument.page(at: 0))
        XCTAssertEqual(savedPage.annotations.map(\.type), ["Stamp"])
        assertEqual(savedPage.annotations.first?.bounds, CGRect(x: 45, y: 175, width: 50, height: 100))
        let readBack = try XCTUnwrap(PDFPageManager.pictures(on: savedPage).first)
        XCTAssertEqual(readBack.name, picture.name)
        XCTAssertEqual(readBack.imageData, picture.imageData)
        XCTAssertEqual(readBack.rotationRadians, .pi / 2, accuracy: 0.0001)
        assertEqual(readBack.bounds, picture.bounds)

        // Moving and resizing keep the angle; the bounds are the frame before the turn.
        let newBounds = CGRect(x: 40, y: 100, width: 50, height: 25)
        try PDFPageManager.apply(.movePicture(readBack.reference(onPageAt: 0), to: newBounds), to: savedDocument)
        let moved = try XCTUnwrap(PDFPageManager.pictures(on: savedPage).first)
        XCTAssertEqual(moved.rotationRadians, .pi / 2, accuracy: 0.0001)
        assertEqual(moved.bounds, newBounds)
        assertEqual(moved.annotationBounds, CGRect(x: 52.5, y: 87.5, width: 25, height: 50))
    }

    func testAnUprightPictureWritesNoAngleAndAResizedTurnedStampKeepsItsProportions() throws {
        let upright = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0)
        let document = try Self.blankDocument(rotation: 0)
        try PDFPageManager.apply(.addPicture(page: 0, picture: upright), to: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let uprightAnnotation = try XCTUnwrap(page.annotations.first)
        XCTAssertNil(uprightAnnotation.value(forAnnotationKey: PDFPageManager.pictureRotationKey), "Pictures placed before turning was possible stay as they were.")
        XCTAssertNil(uprightAnnotation.value(forAnnotationKey: PDFPageManager.pictureWidthKey))

        // Another application doubled the turned picture's rectangle: the picture fills it,
        // in its own proportions.
        let turned = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 100, width: 100, height: 50), quarterTurns: 0,
                                rotationRadians: .pi / 2)
        try PDFPageManager.apply(.addPicture(page: 0, picture: turned), to: document)
        let turnedAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == turned.name })
        turnedAnnotation.bounds = CGRect(x: 20, y: 25, width: 100, height: 200)
        let readBack = try XCTUnwrap(PDFPageManager.pictures(on: page).first { picture in picture.name == turned.name })
        assertEqual(readBack.bounds, CGRect(x: -30, y: 75, width: 200, height: 100))
    }

    /// A turned picture is stored under a key builds before turning do not read, so they
    /// leave it as another application's stamp instead of stretching it upright; an upright
    /// picture stays under the key they read. Files of the first build that turned pictures,
    /// with a turned picture under the old key, are still read turned.
    func testATurnedPictureIsStoredUnderItsOwnKeyAndOlderFilesAreStillRead() throws {
        let upright = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0)
        let turned = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 20, y: 100, width: 100, height: 50), quarterTurns: 0,
                                rotationRadians: .pi / 2)
        let writtenDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: upright), .addPicture(page: 0, picture: turned)], on: writtenDocument)
        let savedDocument = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation())))
        let savedPage = try XCTUnwrap(savedDocument.page(at: 0))
        let uprightAnnotation = try XCTUnwrap(savedPage.annotations.first { annotation in annotation.persistentName == upright.name })
        let turnedAnnotation = try XCTUnwrap(savedPage.annotations.first { annotation in annotation.persistentName == turned.name })
        XCTAssertNotNil(uprightAnnotation.value(forAnnotationKey: PDFPageManager.pictureKey))
        XCTAssertNil(uprightAnnotation.value(forAnnotationKey: PDFPageManager.turnedPictureKey))
        XCTAssertNil(turnedAnnotation.value(forAnnotationKey: PDFPageManager.pictureKey), "A build that reads only the old key does not take it for its own.")
        XCTAssertNotNil(turnedAnnotation.value(forAnnotationKey: PDFPageManager.turnedPictureKey))
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage).map(\.name), [upright.name, turned.name])

        // Turned back upright, the picture returns to the old key.
        var straightened = try XCTUnwrap(PDFPageManager.pictures(on: savedPage).last)
        straightened.rotationRadians = 0
        try PDFPageManager.replay([.replacePicture(turned.reference(onPageAt: 0), with: straightened, order: .unchanged)], on: savedDocument)
        let straightenedAnnotation = try XCTUnwrap(savedPage.annotations.first { annotation in annotation.persistentName == turned.name })
        XCTAssertNotNil(straightenedAnnotation.value(forAnnotationKey: PDFPageManager.pictureKey))
        XCTAssertNil(straightenedAnnotation.value(forAnnotationKey: PDFPageManager.turnedPictureKey))

        // A turned picture written under the old key, as on 2026-10-11, reads turned.
        let olderDocument = try Self.blankDocument(rotation: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: turned)], on: olderDocument)
        let olderAnnotation = try XCTUnwrap(olderDocument.page(at: 0)?.annotations.first)
        olderAnnotation.setValue(try XCTUnwrap(olderAnnotation.value(forAnnotationKey: PDFPageManager.turnedPictureKey)), forAnnotationKey: PDFPageManager.pictureKey)
        olderAnnotation.removeValue(forAnnotationKey: PDFPageManager.turnedPictureKey)
        let olderPage = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(olderDocument.dataRepresentation()))?.page(at: 0))
        let olderPicture = try XCTUnwrap(PDFPageManager.pictures(on: olderPage).first)
        XCTAssertEqual(olderPicture.rotationRadians, .pi / 2, accuracy: 0.0001)
        assertEqual(olderPicture.bounds, turned.bounds)

        // The new key is kept when a save also rewrites the page tree.
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(writtenDocument.dataRepresentation())))
        let blankPage = try XCTUnwrap(try Self.blankDocument(rotation: 0).dataRepresentation())
        try PDFPageManager.replay([.insert(data: blankPage, at: 0)], on: reopened)
        let rewrittenPage = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(reopened.dataRepresentation()))?.page(at: 1))
        let rewrittenTurned = try XCTUnwrap(PDFPageManager.pictures(on: rewrittenPage).first { picture in picture.name == turned.name })
        XCTAssertEqual(rewrittenTurned.rotationRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(rewrittenTurned.imageData, turned.imageData)
    }

    func testPicturesThatCannotBePlacedAreRefused() throws {
        let document = try Self.blankDocument(rotation: 0)
        let notAnImage = PDFPicture(imageData: Data("not an image".utf8), bounds: CGRect(x: 0, y: 0, width: 10, height: 10), quarterTurns: 0)
        XCTAssertThrowsError(try PDFPageManager.apply(.addPicture(page: 0, picture: notAnImage), to: document))
        let withoutSize = PDFPicture(imageData: try Self.twoColorImageData(), bounds: CGRect(x: 0, y: 0, width: 0, height: 10), quarterTurns: 0)
        XCTAssertFalse(withoutSize.hasValidGeometry)
        XCTAssertThrowsError(try PDFPageManager.apply(.addPicture(page: 0, picture: withoutSize), to: document))
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)).annotations.isEmpty)
        XCTAssertEqual(PDFPicture(imageData: Data([1]), bounds: .zero, quarterTurns: -1).quarterTurns, 3)
    }
}
