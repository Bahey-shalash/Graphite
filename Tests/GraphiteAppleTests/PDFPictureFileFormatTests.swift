import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Pictures as they are written into a PDF: `/Stamp` annotations that keep the picture's
/// own bytes as prefixed base64 text, upright ones under the key every build reads.
final class PDFPictureFileFormatTests: XCTestCase {
    private static let pageSize = CGSize(width: 200, height: 300)

    private func imageData(width: Int = 8, height: Int = 4) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func blankDocument() throws -> PDFDocument {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let consumer = try XCTUnwrap(CGDataConsumer(data: pageData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: pageData as Data))
    }

    private func writtenData(placing picture: PDFPicture) throws -> Data {
        let document = try blankDocument()
        try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: document)
        return try XCTUnwrap(document.dataRepresentation())
    }

    func testAnUprightPictureIsAStampWithItsBytesUnderTheFirstKeyAndNoAngle() throws {
        let bytes = try imageData()
        let picture = PDFPicture(name: "upright-1", imageData: bytes, bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 3)
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(placing: picture)) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1)
            let stamp = dictionaries[0]
            XCTAssertEqual(PDFAnnotationDictionaryReading.name("Subtype", in: stamp), "Stamp")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("NM", in: stamp), "upright-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteAnnotationName", in: stamp), "upright-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphitePictureV1", in: stamp), "base64:" + bytes.base64EncodedString())
            XCTAssertEqual(PDFAnnotationDictionaryReading.integer("GraphitePictureTurns", in: stamp), 3)
            XCTAssertFalse(PDFAnnotationDictionaryReading.hasKey("GraphitePictureV2", in: stamp))
            for key in ["GraphitePictureRotation", "GraphitePictureWidth", "GraphitePictureHeight"] {
                XCTAssertFalse(PDFAnnotationDictionaryReading.hasKey(key, in: stamp), "\(key) is written only for turned pictures.")
            }
            XCTAssertEqual(PDFAnnotationDictionaryReading.integer("F", in: stamp).map { $0 & 4 }, 4)
        }
    }

    func testATurnedPictureIsUnderTheSecondKeyWithItsAngleWidthAndHeight() throws {
        let bytes = try imageData()
        let picture = PDFPicture(name: "turned-1", imageData: bytes, bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0,
                                 rotationRadians: .pi / 2)
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(placing: picture)) { dictionaries in
            let stamp = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphitePictureV2", in: stamp), "base64:" + bytes.base64EncodedString())
            XCTAssertFalse(PDFAnnotationDictionaryReading.hasKey("GraphitePictureV1", in: stamp))
            XCTAssertEqual(PDFAnnotationDictionaryReading.integer("GraphitePictureTurns", in: stamp), 0)
            XCTAssertEqual(try XCTUnwrap(PDFAnnotationDictionaryReading.number("GraphitePictureRotation", in: stamp)), .pi / 2, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(PDFAnnotationDictionaryReading.number("GraphitePictureWidth", in: stamp)), 100, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(PDFAnnotationDictionaryReading.number("GraphitePictureHeight", in: stamp)), 50, accuracy: 0.0001)
        }
    }

    func testAPictureWhoseBytesStartWithASlashIsStoredAsTextNotAsAName() throws {
        // A JPEG's base64 text starts with "/9j/", which PDFKit would write as a name.
        let jpegStart = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        XCTAssertTrue(jpegStart.base64EncodedString().hasPrefix("/"))
        let annotation = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), forType: .stamp, withProperties: nil)
        annotation.setPersistentName("jpeg-1")
        annotation.setValue("base64:" + jpegStart.base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
        XCTAssertEqual(PDFPicture(annotation: annotation)?.imageData, jpegStart)
        XCTAssertNil(PDFPicture(annotation: {
            let withoutPrefix = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), forType: .stamp, withProperties: nil)
            withoutPrefix.setPersistentName("bare-1")
            withoutPrefix.setValue(jpegStart.base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
            return withoutPrefix
        }()), "Text without the prefix is not one of Graphite's pictures.")
    }

    func testAPictureLargerThanEightMebibytesIsRefusedAndOneWithinTheBoundIsKept() throws {
        XCTAssertEqual(PDFPicture.maximumImageBytes, 8_388_608)
        let oversized = PDFPicture(imageData: Data(count: PDFPicture.maximumImageBytes + 1), bounds: CGRect(x: 0, y: 0, width: 10, height: 10), quarterTurns: 0)
        XCTAssertFalse(oversized.hasValidGeometry)
        XCTAssertThrowsError(try PDFPageManager.apply(.addPicture(page: 0, picture: oversized), to: blankDocument()))
        let atTheBound = PDFPicture(imageData: Data(count: PDFPicture.maximumImageBytes), bounds: CGRect(x: 0, y: 0, width: 10, height: 10), quarterTurns: 0)
        XCTAssertTrue(atTheBound.hasValidGeometry)

        // A stored text longer than eight mebibytes of bytes is not read back either.
        let annotation = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), forType: .stamp, withProperties: nil)
        annotation.setPersistentName("large-1")
        annotation.setValue("base64:" + Data(count: PDFPicture.maximumImageBytes).base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
        XCTAssertEqual(PDFPicture(annotation: annotation)?.imageData.count, PDFPicture.maximumImageBytes)
        annotation.setValue("base64:" + Data(count: PDFPicture.maximumImageBytes + 3).base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
        XCTAssertNil(PDFPicture(annotation: annotation))
    }

    func testATurnedPictureStoredUnderTheFirstKeyReadsTurned() throws {
        let bytes = try imageData()
        let annotation = PDFAnnotation(bounds: CGRect(x: 45, y: 175, width: 50, height: 100), forType: .stamp, withProperties: nil)
        annotation.setPersistentName("older-1")
        annotation.setValue("base64:" + bytes.base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
        annotation.setValue(NSNumber(value: 0), forAnnotationKey: PDFPageManager.pictureTurnsKey)
        annotation.setValue(NSNumber(value: Double.pi / 2), forAnnotationKey: PDFPageManager.pictureRotationKey)
        annotation.setValue(NSNumber(value: 100.0), forAnnotationKey: PDFPageManager.pictureWidthKey)
        annotation.setValue(NSNumber(value: 50.0), forAnnotationKey: PDFPageManager.pictureHeightKey)
        let picture = try XCTUnwrap(PDFPicture(annotation: annotation))
        XCTAssertEqual(picture.rotationRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(picture.bounds.width, 100, accuracy: 0.01)
        XCTAssertEqual(picture.bounds.height, 50, accuracy: 0.01)
        XCTAssertTrue(picture.isTurned)
    }
}
