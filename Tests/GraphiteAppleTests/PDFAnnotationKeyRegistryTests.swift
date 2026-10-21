import XCTest
import PDFKit
import GraphiteCore
@testable import GraphiteApple

/// The key names Graphite writes into PDF annotations. Files saved by earlier builds, and
/// by other readers that keep unknown keys, are found again only by these exact names.
final class PDFAnnotationKeyRegistryTests: XCTestCase {
    func testGraphiteKeysAreExactlyTheseThirteenNames() {
        let keysByName: [(key: PDFAnnotationKey, name: String)] = [
            (PDFPageManager.drawingKey, "GraphitePencilDrawingV1"),
            (PDFPageManager.groupKey, "GraphiteInkGroup"),
            (PDFPageManager.strokeNamesKey, "GraphiteInkStrokeNamesV1"),
            (PDFPageManager.annotationNameKey, "GraphiteAnnotationName"),
            (PDFPageManager.pictureKey, "GraphitePictureV1"),
            (PDFPageManager.turnedPictureKey, "GraphitePictureV2"),
            (PDFPageManager.pictureTurnsKey, "GraphitePictureTurns"),
            (PDFPageManager.pictureRotationKey, "GraphitePictureRotation"),
            (PDFPageManager.pictureWidthKey, "GraphitePictureWidth"),
            (PDFPageManager.pictureHeightKey, "GraphitePictureHeight"),
            (PDFPageManager.textBoxRecordKey, "GraphiteTextBoxV1"),
            (PDFPageManager.textBoxRichTextKey, "GraphiteRichTextV1"),
            (PDFPageManager.textBoxLinkOwnerKey, "GraphiteTextBoxLinkOwner"),
        ]
        for (key, name) in keysByName { XCTAssertEqual(key.rawValue, name) }
        XCTAssertEqual(Set(keysByName.map(\.name)).count, 13)
        XCTAssertEqual(PDFPageManager.defaultStyleKey.rawValue, "/DS", "The standard keys of a text box PDFKit keeps but does not read.")
        XCTAssertEqual(PDFPageManager.rotateKey.rawValue, "/Rotate")
        XCTAssertEqual(PDFPageManager.storedPictureKeys.map(\.rawValue), ["GraphitePictureV2", "GraphitePictureV1"],
                       "A turned picture's key is read first.")
    }

    func testDefaultInkGroupNameAndTheBoundsOnItsRecord() {
        XCTAssertEqual(PDFInkGroups.defaultGroup, "GraphitePageInkV1")
        XCTAssertEqual(PDFInkGroups.maximumEncodedDrawingBytes, DrawingLimits.maximumPayloadBytes * 2)
        XCTAssertEqual(PDFInkGroups.maximumEncodedDrawingBytes, 71_303_168)
        XCTAssertEqual(PDFInkGroups.maximumEncodedStrokeNameBytes, 16_777_216)
    }

    // MARK: A file written by an earlier build

    /// A PDF written object by object with a correct cross-reference table.
    private static func handWrittenPDF(objects: [String]) -> Data {
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }

    /// Ink and pictures as b13dec3 wrote them, byte for byte in the keys and values that
    /// matter, with a correct cross-reference table: a two-stroke group whose record is on
    /// its first annotation, an upright picture, and a picture turned by hand under the key
    /// of the first build that turned pictures.
    private func fileWrittenByAnEarlierBuild() -> Data {
        let drawingRecord = Data([1, 2, 3, 4]).base64EncodedString()
        let uprightPicture = "base64:" + Data("upright picture bytes".utf8).base64EncodedString()
        let turnedPicture = "base64:" + Data("turned picture bytes".utf8).base64EncodedString()
        return Self.handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [4 0 R 5 0 R 6 0 R 7 0 R] >>",
            "<< /Type /Annot /Subtype /Ink /Rect [10 10 110 60] /InkList [[1 1 99 1]] /C [0 0 0] /F 4 /NM (stroke-a) "
                + "/GraphiteAnnotationName (stroke-a) /GraphiteInkGroup (GraphitePageInkV1) /GraphitePencilDrawingV1 (\(drawingRecord)) "
                + "/GraphiteInkStrokeNamesV1 (2:stroke-a,stroke-b) >>",
            "<< /Type /Annot /Subtype /Ink /Rect [10 100 110 160] /InkList [[1 1 99 1]] /C [0 0 0] /F 4 /NM (stroke-b) "
                + "/GraphiteAnnotationName (stroke-b) /GraphiteInkGroup (GraphitePageInkV1) >>",
            "<< /Type /Annot /Subtype /Stamp /Rect [20 200 120 250] /F 4 /NM (picture-upright) /GraphiteAnnotationName (picture-upright) "
                + "/GraphitePictureV1 (\(uprightPicture)) /GraphitePictureTurns 1 >>",
            "<< /Type /Annot /Subtype /Stamp /Rect [145 275 195 375] /F 4 /NM (picture-turned) /GraphiteAnnotationName (picture-turned) "
                + "/GraphitePictureV1 (\(turnedPicture)) /GraphitePictureTurns 0 /GraphitePictureRotation 1.5707963267948966 "
                + "/GraphitePictureWidth 100 /GraphitePictureHeight 50 >>",
        ])
    }

    func testInkWrittenByAnEarlierBuildIsEditableWithItsRecord() throws {
        let document = try XCTUnwrap(PDFDocument(data: fileWrittenByAnEarlierBuild()))
        let page = try XCTUnwrap(document.page(at: 0))
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: page))
        XCTAssertEqual(group.group, "GraphitePageInkV1")
        XCTAssertEqual(group.record, PDFEditableInkRecord(drawingData: Data([1, 2, 3, 4]), strokeNames: ["stroke-a", "stroke-b"]))
        XCTAssertTrue(group.hasStrokeNames)
    }

    func testPicturesWrittenByAnEarlierBuildAreReadWithTheirTurnsAndAngles() throws {
        let document = try XCTUnwrap(PDFDocument(data: fileWrittenByAnEarlierBuild()))
        let pictures = PDFPageManager.pictures(on: try XCTUnwrap(document.page(at: 0)))
        XCTAssertEqual(pictures.map(\.name), ["picture-upright", "picture-turned"])
        XCTAssertEqual(pictures[0].imageData, Data("upright picture bytes".utf8))
        XCTAssertEqual(pictures[0].quarterTurns, 1)
        XCTAssertFalse(pictures[0].isTurned)
        XCTAssertEqual(pictures[1].imageData, Data("turned picture bytes".utf8))
        XCTAssertEqual(pictures[1].quarterTurns, 0)
        XCTAssertEqual(pictures[1].rotationRadians, .pi / 2, accuracy: 0.0001, "A turned picture under the first key still reads turned.")
        XCTAssertEqual(pictures[1].bounds.width, 100, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.height, 50, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.midX, 170, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.midY, 325, accuracy: 0.01)
    }

    func testKeysOfAnEarlierBuildSurviveASaveThatAlsoChangesPages() throws {
        let document = try XCTUnwrap(PDFDocument(data: fileWrittenByAnEarlierBuild()))
        let blankPage = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))
        try PDFPageManager.replay([.insert(data: blankPage, at: 0)], on: document)
        let rewritten = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let page = try XCTUnwrap(rewritten.page(at: 1))
        XCTAssertEqual(PDFInkGroups.editableGroup(on: page)?.record.strokeNames, ["stroke-a", "stroke-b"])
        XCTAssertEqual(PDFPageManager.pictures(on: page).map(\.name), ["picture-upright", "picture-turned"])
    }
}
