import CoreGraphics
import XCTest
@testable import NotebookImport

final class NotabilityNoteReaderTests: XCTestCase {
    private let limits = NotebookImportLimits.standard
    private let pageHeight = 803.25 / (612.0 / 572.0)

    /// A note with three curves over two pages, two shapes, a picture, two text runs, a PDF page, three recordings
    /// and two timed curves, one of which names no curve.
    static func completeNote() -> NotabilityNoteBuilder {
        var builder = NotabilityNoteBuilder()
        builder.curves = [
            .pen([(10, 10), (20, 15), (30, 20), (40, 25)], uuidByte: 1),
            .pen([(50, 700), (60, 720), (70, 740), (80, 760), (90, 780), (95, 790), (99, 800)], uuidByte: 2),
            .pen([(100, 900)], uuidByte: 3),
        ]
        builder.curves[1].style = 4
        builder.curves[1].color = [250, 220, 0, 107]
        var shapesWriter = BinaryPropertyListWriter()
        let shapes = shapesWriter.add(tree: .dictionary([
            ("shapes", .array([
                .dictionary([("startPt", .array([.real(1), .real(2)])), ("endPt", .array([.real(3), .real(4)])),
                             ("controlPoint1", .array([.real(5), .real(6)])), ("options", .integer(0)), ("uuid", .data([UInt8](repeating: 7, count: 16))),
                             ("appearance", .dictionary([("strokeColor", .dictionary([("rgba", .array([.real(1), .integer(0), .real(0), .real(1)]))])),
                                                         ("strokeWidth", .real(2)), ("style", .integer(3))]))]),
                .dictionary([("startPt", .array([.real(10), .real(760)])), ("endPt", .array([.real(20), .real(770)])),
                             ("appearance", .dictionary([("strokeColor", .dictionary([("rgba", .array([.real(0), .real(0), .real(1), .real(0.5)]))])),
                                                         ("strokeWidth", .real(1)),
                                                         ("dashStyle", .dictionary([("pattern", .array([.real(2), .real(3)]))]))]))]),
            ])),
            ("kinds", .array([.string("line"), .string("line")])),
            ("indices", .array([.integer(0), .integer(2)])),
        ]))
        builder.shapesPropertyList = shapesWriter.bytes(topObjectIndex: shapes)
        builder.pictures = [SyntheticNotabilityPicture(origin: "{-14.8, 20}", size: "{200, 150}", cropRectangle: "{{0, 0}, {400, 300}}",
                                                       rotationRadians: 0.443, zIndex: 0)]
        builder.text = "Hello\nWorld é"
        builder.textRuns = [SyntheticNotabilityTextRun(range: "{0, 6}"),
                            SyntheticNotabilityTextRun(range: "{6, 7}", fontName: "HelveticaNeue-Bold", fontSize: 20, color: "0.9,0.2,0.1,1.0",
                                                       otherAttributes: [("NSUnderline", .integer(1)), ("NSStrikethrough", .integer(0)),
                                                                         ("line-spacing", .real(1.5)), ("NSBaselineOffset", .real(2))])]
        builder.importedPDFFileNames = ["ABC.pdf"]
        builder.recordingsLibraryXML = NotabilityNoteBuilder.recordingsLibraryXML([
            (key: "2", identifier: 2, filePath: "Recording 2.m4a", durationSeconds: 3, name: "Recording 2"),
            (key: "10", identifier: 10, filePath: "Recording 10.m4a", durationSeconds: 4, name: "Recording 10"),
            (key: "1", identifier: 1, filePath: "Recording 1.m4a", durationSeconds: 18.9, name: "Recording 1"),
        ])
        builder.playbackEvents = [
            SyntheticNotabilityPlaybackEvent(curveUUID: [UInt8](repeating: 1, count: 16), secondsFromRecordingStart: 10.8, recordingIdentifier: 1,
                                             durationSeconds: 0.5),
            SyntheticNotabilityPlaybackEvent(curveUUID: [UInt8](repeating: 9, count: 16), secondsFromRecordingStart: 15.4, recordingIdentifier: 1,
                                             durationSeconds: 0.3),
        ]
        builder.extraFiles = [("Images/Image 1.png", [0x89, 0x50, 0x4E, 0x47]), ("PDFs/ABC.pdf", Array("%PDF-1.7".utf8))]
        builder.extraSessionFields = [("futureKey", .integer(1))]
        return builder
    }

    private func reader(_ builder: NotabilityNoteBuilder) throws -> NotabilityNoteReader {
        try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
    }

    private static func uuid(repeating byte: UInt8) -> UUID {
        UUID(uuid: (byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte))
    }

    func testDocumentValuesOfACompleteNote() throws {
        let reader = try reader(Self.completeNote())
        let note = reader.note
        XCTAssertEqual(note.name, "Synthetic Note")
        XCTAssertEqual(note.sessionFormatVersion, 9)
        XCTAssertEqual(note.applicationVersion, "16.13")
        XCTAssertEqual(note.paper, NotabilityPaper(identifier: .legacyWhite, size: .letter, orientation: .portrait,
                                                   sizingBehaviour: .lockedWidth(width: 572, device: "Mac"),
                                                   lineStyle: .lines(parameters: ["false", "false", "0.5"])))
        XCTAssertEqual(note.reflowState, .locked(pageWidth: 572, device: "Mac"))
        XCTAssertEqual(note.pageGeometry.pageWidthInUnits, 572)
        XCTAssertEqual(note.pageGeometry.exportPageSizeInPoints, CGSize(width: 612, height: 803.25))
        XCTAssertEqual(note.pageGeometry.pointsPerUnit, 612.0 / 572.0)
        XCTAssertEqual(note.pageGeometry.pageHeightInUnits, pageHeight)
        XCTAssertEqual(reader.curveCount, 3)
        XCTAssertEqual(reader.pageCount, 2)
        XCTAssertEqual(reader.issues, [.unknownKey(.session, key: "futureKey"), .playbackEventWithoutCurve(curveUUID: Self.uuid(repeating: 9))])
    }

    func testCurvesAreDecodedWithTheirPointsAndKnotValues() throws {
        let reader = try reader(Self.completeNote())
        let first = try reader.curve(at: 0)
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.uuid, Self.uuid(repeating: 1))
        XCTAssertEqual(first.style, .pen)
        XCTAssertEqual(first.width, 2.5)
        XCTAssertEqual(first.color, NotebookImportColor(red: 10 / 255, green: 20 / 255, blue: 30 / 255, alpha: 1))
        XCTAssertEqual(first.points, [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15), CGPoint(x: 30, y: 20), CGPoint(x: 40, y: 25)])
        XCTAssertEqual(first.knots, [
            NotabilityKnot(widthFactor: 0.5, force: 1, altitudeAngle: 1.5, azimuthUnitVector: NotabilityAzimuthVector(horizontal: 1, vertical: 0)),
            NotabilityKnot(widthFactor: 0.75, force: 2, altitudeAngle: 1.375, azimuthUnitVector: NotabilityAzimuthVector(horizontal: 0, vertical: 1)),
        ])
        let highlighter = try reader.curve(at: 1)
        XCTAssertEqual(highlighter.style, .highlighter)
        XCTAssertEqual(highlighter.color.alpha, 107 / 255)
        XCTAssertEqual(highlighter.points.count, 7)
        XCTAssertEqual(highlighter.knots.count, 3)
        XCTAssertTrue(try reader.isHighlighter(curveIndex: 1))
        XCTAssertEqual(try reader.curve(at: 2).points, [CGPoint(x: 100, y: 900)])
        XCTAssertThrowsError(try reader.curve(at: 3)) { error in
            XCTAssertEqual(error as? NotabilityReadingError, .curveIndexOutOfRange(curveIndex: 3, curveCount: 3))
        }
    }

    func testShapesPicturesTextPDFPagesAndRecordings() throws {
        let note = try reader(Self.completeNote()).note
        XCTAssertEqual(note.shapes, [
            NotabilityShape(kind: .line, drawnBeforeCurveIndex: 0, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4),
                            quadraticControlPoint: CGPoint(x: 5, y: 6), width: 2, color: NotebookImportColor(red: 1, green: 0, blue: 0, alpha: 1),
                            dashPattern: nil),
            NotabilityShape(kind: .line, drawnBeforeCurveIndex: 2, start: CGPoint(x: 10, y: 760), end: CGPoint(x: 20, y: 770),
                            quadraticControlPoint: nil, width: 1, color: NotebookImportColor(red: 0, green: 0, blue: 1, alpha: 0.5), dashPattern: [2, 3]),
        ])
        XCTAssertEqual(note.pictures, [
            NotabilityPicture(file: .fixture("Images/Image 1.png"), origin: CGPoint(x: -14.8, y: 20), size: CGSize(width: 200, height: 150),
                              rotationRadiansClockwise: 0.443, zIndex: 0, cropRectangle: CGRect(x: 0, y: 0, width: 400, height: 300),
                              isFlippedHorizontally: false, isFlippedVertically: true),
        ])
        XCTAssertEqual(note.pictures.first?.unitsPerImagePixel, 0.5)
        XCTAssertEqual(note.typedText, NotabilityTypedText(text: "Hello\nWorld é", runs: [
            NotabilityTextRun(utf16Location: 0, utf16Length: 6, fontName: "HelveticaNeue", fontSize: 12,
                              color: NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1), isUnderlined: false, isStruckThrough: false,
                              lineSpacing: 1, baselineOffset: 0),
            NotabilityTextRun(utf16Location: 6, utf16Length: 7, fontName: "HelveticaNeue-Bold", fontSize: 20,
                              color: NotebookImportColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1), isUnderlined: true, isStruckThrough: false,
                              lineSpacing: 1.5, baselineOffset: 2),
        ]))
        XCTAssertEqual(note.importedPDFPages, [NotabilityImportedPDFPage(documentPageNumber: 1, pdfFile: .fixture("PDFs/ABC.pdf"), pdfPageNumber: 1,
                                                                         isBookmarked: true)])
        XCTAssertEqual(note.recordings.map(\.identifier), [1, 10, 2], "sorted by key as text")
        XCTAssertEqual(note.recordings.first, NotabilityRecording(identifier: 1, file: .fixture("Recordings/Recording 1.m4a"), durationSeconds: 18.9,
                                                                  name: "Recording 1"))
        XCTAssertEqual(note.playbackEvents, [
            NotabilityPlaybackEvent(curveIndex: 0, curveUUID: Self.uuid(repeating: 1), recordingIdentifier: 1,
                                    secondsFromRecordingStart: Double(Float(10.8)), durationSeconds: Double(Float(0.5))),
            NotabilityPlaybackEvent(curveIndex: nil, curveUUID: Self.uuid(repeating: 9), recordingIdentifier: 1,
                                    secondsFromRecordingStart: Double(Float(15.4)), durationSeconds: Double(Float(0.3))),
        ])
    }

    func testPagesHoldWhatTheirExtentTouches() throws {
        let reader = try reader(Self.completeNote())
        let firstPage = try reader.page(number: 1)
        XCTAssertEqual(firstPage.topInUnits, 0)
        XCTAssertEqual(firstPage.curves.map(\.index), [0, 1])
        XCTAssertEqual(firstPage.shapes.map(\.drawnBeforeCurveIndex), [0])
        XCTAssertEqual(firstPage.pictures.count, 1)
        let secondPage = try reader.page(number: 2)
        XCTAssertEqual(secondPage.topInUnits, pageHeight)
        XCTAssertEqual(secondPage.curves.map(\.index), [1, 2], "the highlighter crosses the page break")
        XCTAssertEqual(secondPage.shapes.map(\.drawnBeforeCurveIndex), [2])
        XCTAssertEqual(secondPage.pictures, [])
        for pageNumber in [0, 3, -1] {
            XCTAssertThrowsError(try reader.page(number: pageNumber)) { error in
                XCTAssertEqual(error as? NotabilityReadingError, .pageNumberOutOfRange(pageNumber: pageNumber, pageCount: 2))
            }
        }
    }

    /// SRP-IMPORT-01: one extent rule for a picture, its turned frame, serves the page count and the pages' contents.
    func testAPictureTurnedPastTheLastPageAddsAPageThatHoldsIt() throws {
        var builder = Self.completeNote()
        let top = 2 * pageHeight - 100
        builder.pictures.append(SyntheticNotabilityPicture(relativePath: "Images/Image 1.png", origin: "{10, \(top)}", size: "{400, 20}",
                                                           rotationRadians: Double.pi / 2))
        let turned = try reader(builder)
        XCTAssertEqual(turned.pageCount, 3, "turned upright, the 400-unit picture reaches past the second page")
        XCTAssertEqual(try turned.page(number: 3).pictures.count, 1)
        XCTAssertEqual(try turned.page(number: 2).pictures.count, 1)
        builder.pictures[builder.pictures.count - 1].rotationRadians = 0
        XCTAssertEqual(try reader(builder).pageCount, 2, "lying flat, it ends on the second page")
    }

    func testFileBytesAreReadFromTheNoteFolder() throws {
        let reader = try reader(Self.completeNote())
        XCTAssertEqual(Array(try reader.contents(ofFileAt: .fixture("Images/Image 1.png"))), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(Array(try reader.contents(ofFileAt: .fixture("PDFs/ABC.pdf"))), Array("%PDF-1.7".utf8))
        XCTAssertThrowsError(try reader.contents(ofFileAt: .fixture("Images/Missing.png"))) { error in
            XCTAssertEqual(error as? NotabilityReadingError, .archive(.entryMissing(name: "Synthetic Note/Images/Missing.png")))
        }
    }

    func testAReflowableNoteHasNoPageGeometry() throws {
        var builder = NotabilityNoteBuilder()
        builder.reflowStateClassName = "NBReflowStateReflowable"
        builder.storedPageWidth = nil
        builder.paperFields = [("paperIdentifier", "Legacy:13"), ("paperSize", "letter"), ("paperSizingBehavior", "deviceBasedWidth"),
                               ("lineStyle2", "No Lines")]
        let reader = try reader(builder)
        XCTAssertEqual(reader.note.reflowState, .reflowable)
        XCTAssertEqual(reader.note.paper.sizingBehaviour, .deviceBasedWidth)
        XCTAssertEqual(reader.note.paper.lineStyle, .noLines)
        XCTAssertNil(reader.note.pageGeometry.pageWidthInUnits)
        XCTAssertNil(reader.note.pageGeometry.pageHeightInUnits)
        XCTAssertNil(reader.pageCount)
        XCTAssertEqual(reader.issues, [])
        XCTAssertThrowsError(try reader.page(number: 1)) { error in XCTAssertEqual(error as? NotabilityReadingError, .pageCountUnknown) }
    }

    func testUnknownsAreReportedNotGuessed() throws {
        var builder = NotabilityNoteBuilder()
        builder.reflowStateClassName = "NBReflowStateFuture"
        builder.storedPageWidth = nil
        builder.sessionFormatVersion = 10
        builder.paperFields = [("paperIdentifier", "Legacy:99"), ("paperSize", "tabloid"), ("paperSizingBehavior", "futureWidth"),
                               ("lineStyle2", "Dots:1")]
        builder.curves = [.pen([(1, 1)], uuidByte: 4)]
        builder.curves[0].style = 7
        builder.curves[0].altitudeAngles = []
        var shapesWriter = BinaryPropertyListWriter()
        let shapes = shapesWriter.add(tree: .dictionary([("shapes", .array([.dictionary([("startPt", .array([.real(0), .real(0)])),
            ("endPt", .array([.real(1), .real(1)])), ("corners", .integer(4)),
            ("appearance", .dictionary([("strokeColor", .dictionary([("rgba", .array([.real(0), .real(0), .real(0), .real(1)]))]))]))])])),
            ("kinds", .array([.string("ellipse")])), ("indices", .array([.integer(0)]))]))
        builder.shapesPropertyList = shapesWriter.bytes(topObjectIndex: shapes)
        builder.textRuns = [SyntheticNotabilityTextRun(range: "{0, 0}", color: "red", otherAttributes: [("NSShadow", .integer(1))])]
        let reader = try reader(builder)
        XCTAssertEqual(reader.note.paper, NotabilityPaper(identifier: .unknown("Legacy:99"), size: .unknown("tabloid"), orientation: nil,
                                                          sizingBehaviour: .unknown("futureWidth"), lineStyle: .unknown("Dots:1")))
        XCTAssertEqual(reader.note.reflowState, .unknown(className: "NBReflowStateFuture"))
        XCTAssertEqual(Set(reader.issues), [
            .sessionFormatNotSupported(version: 10), .reflowStateUnknown(className: "NBReflowStateFuture"), .paperSizeUnknown(rawSize: "tabloid"),
            .perKnotArrayIgnored(.knotAltitudeAngles, byteCount: 0), .curveStyleUnknown(rawStyle: 7), .shapeKindUnknown(rawKind: "ellipse"),
            .unknownKey(.shape, key: "corners"), .unknownKey(.textAttributes, key: "NSShadow"), .textRunColorNotReadable(runIndex: 0),
        ])
        XCTAssertEqual(reader.issues.count, 9, "each issue once")
        XCTAssertNil(try reader.curve(at: 0).knots[0].altitudeAngle)
        XCTAssertEqual(try reader.curve(at: 0).style, .unknown(7))
        XCTAssertEqual(reader.note.shapes.map(\.kind), [.unknown("ellipse")])
    }

    func testAPictureThatCannotBeReadIsSkippedAndTheOthersKept() throws {
        var builder = NotabilityNoteBuilder()
        builder.pictures = [SyntheticNotabilityPicture(cropRectangle: "{{0, 0}, {0, 300}}"),
                            SyntheticNotabilityPicture(relativePath: "Images/Second.jpg", className: "VideoMediaObject"),
                            SyntheticNotabilityPicture(size: "{1}")]
        let reader = try reader(builder)
        XCTAssertEqual(reader.note.pictures.map(\.file.text), ["Images/Second.jpg"])
        XCTAssertEqual(reader.issues, [.pictureSkipped(mediaIndex: 0, .valueNotReadable(key: "FigureCropRectKey")),
                                       .mediaClassUnknown(className: "VideoMediaObject"),
                                       .pictureSkipped(mediaIndex: 2, .valueNotReadable(key: "unscaledContentSize"))])
    }

    func testAShapeThatCannotBeReadIsSkippedAndAnUnreadableListCostsOnlyTheShapes() throws {
        var builder = NotabilityNoteBuilder()
        var shapesWriter = BinaryPropertyListWriter()
        let shapes = shapesWriter.add(tree: .dictionary([("shapes", .array([.dictionary([("startPt", .array([.real(0)]))])])),
                                                         ("kinds", .array([.string("line")])), ("indices", .array([.integer(0)]))]))
        builder.shapesPropertyList = shapesWriter.bytes(topObjectIndex: shapes)
        XCTAssertEqual(try reader(builder).issues, [.shapeSkipped(shapeIndex: 0, .valueNotReadable(key: "appearance"))])
        builder.shapesPropertyList = Array("bplist00 too short".utf8)
        XCTAssertEqual(try reader(builder).issues, [.shapesSkipped(.propertyList(.binary(.notBinaryPropertyList)))])
        var unevenWriter = BinaryPropertyListWriter()
        let uneven = unevenWriter.add(tree: .dictionary([("shapes", .array([])), ("kinds", .array([.string("line")]))]))
        builder.shapesPropertyList = unevenWriter.bytes(topObjectIndex: uneven)
        XCTAssertEqual(try reader(builder).issues, [.shapesSkipped(.shapeArraysDiffer(shapeCount: 0, kindCount: 1, indexCount: 0))])
    }
}
