import XCTest
import PDFKit
import GraphiteCore
@testable import GraphiteApple

/// Pencil ink as it is written into a PDF: standard `/Ink` annotations every reader shows,
/// and one re-editing record on the first annotation of the page's ink group.
final class PDFInkAnnotationFileFormatTests: XCTestCase {
    private func blankDocument() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
    }

    private func outline(around points: [CGPoint]) -> [[CGPoint]] {
        let minimumX = points.map(\.x).min() ?? 0, maximumX = points.map(\.x).max() ?? 0
        let minimumY = points.map(\.y).min() ?? 0, maximumY = points.map(\.y).max() ?? 0
        return [[CGPoint(x: minimumX, y: minimumY - 5), CGPoint(x: maximumX, y: minimumY - 5),
                 CGPoint(x: maximumX, y: maximumY + 5), CGPoint(x: minimumX, y: maximumY + 5)]]
    }

    private func stroke(named name: String?, segments: [[CGPoint]], width: Double = 2) -> PortableInkStroke {
        PortableInkStroke(name: name, segments: segments, width: width, red: 0, green: 0, blue: 0, alpha: 1,
                          outline: outline(around: Array(segments.joined())))
    }

    private func writtenData(_ document: PDFDocument) throws -> Data {
        try XCTUnwrap(document.dataRepresentation())
    }

    private func inkUpdate(group: String = PDFInkGroups.defaultGroup, removal: PDFInkUpdate.Removal = .strokes([]), strokes: [PortableInkStroke],
                           record: PDFEditableInkRecord?) -> PDFEdit {
        .updateInk(PDFInkUpdate(pageIndex: 0, group: group, removal: removal, addedStrokes: strokes, editableRecord: record))
    }

    // MARK: Standard ink (M-11)

    func testEachVisibleSegmentIsOneInkListPathAndALoneTapGetsASecondPointBesideIt() throws {
        let document = try blankDocument()
        let segments = [[CGPoint(x: 100, y: 400), CGPoint(x: 200, y: 450)], [CGPoint(x: 300, y: 500)], [CGPoint(x: 100, y: 600), CGPoint(x: 150, y: 650)]]
        try PDFPageManager.apply(inkUpdate(strokes: [stroke(named: "split", segments: segments)], record: nil), to: document, drawsInkOutlines: true)

        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(document)) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1)
            let annotation = dictionaries[0]
            XCTAssertEqual(PDFAnnotationDictionaryReading.name("Subtype", in: annotation), "Ink")
            let paths = try XCTUnwrap(PDFAnnotationDictionaryReading.numberArrays("InkList", in: annotation))
            XCTAssertEqual(paths.count, 3, "One path for each visible segment, so erased gaps are not bridged.")
            XCTAssertEqual(paths[0].count, 4)
            XCTAssertEqual(paths[1].count, 4, "A one-point segment gets a second point.")
            XCTAssertEqual(paths[1][2] - paths[1][0], 0.01, accuracy: 0.0005, "0.01 point to the right of the first.")
            XCTAssertEqual(paths[1][3], paths[1][1], accuracy: 0.0005)
            XCTAssertEqual(paths[2].count, 4)
        }
    }

    func testTheAppearanceIsTheFilledOutlineAndTheInkIsPrintable() throws {
        let document = try blankDocument()
        try PDFPageManager.apply(inkUpdate(strokes: [stroke(named: "filled", segments: [[CGPoint(x: 100, y: 400), CGPoint(x: 300, y: 400)]])],
                                           record: nil), to: document, drawsInkOutlines: true)

        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(document)) { dictionaries in
            let annotation = try XCTUnwrap(dictionaries.first)
            let appearance = try XCTUnwrap(PDFAnnotationDictionaryReading.normalAppearanceContent(of: annotation))
            XCTAssertNotNil(appearance.range(of: #"(^|\s)f\*?(\s|$)"#, options: .regularExpression), "The outline is filled: \(appearance.prefix(200))")
            let flags = try XCTUnwrap(PDFAnnotationDictionaryReading.integer("F", in: annotation))
            XCTAssertEqual(flags & 4, 4, "The print flag is set.")
        }
        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: writtenData(document))?.page(at: 0)?.annotations.first).shouldPrint)
    }

    func testTheBorderWidthIsTheStrokeWidthButAtLeastHalfAPoint() throws {
        for (strokeWidth, expectedBorderWidth) in [(0.1, 0.5), (0.5, 0.5), (3.0, 3.0), (7.25, 7.25)] {
            let document = try blankDocument()
            try PDFPageManager.apply(inkUpdate(strokes: [stroke(named: "width", segments: [[CGPoint(x: 100, y: 400), CGPoint(x: 300, y: 400)]], width: strokeWidth)],
                                               record: nil), to: document, drawsInkOutlines: true)
            let annotation = try XCTUnwrap(PDFDocument(data: writtenData(document))?.page(at: 0)?.annotations.first)
            XCTAssertEqual(annotation.border?.lineWidth ?? -1, expectedBorderWidth, accuracy: 0.001, "Stroke width \(strokeWidth)")
        }
    }

    // MARK: The re-editing record (M-12)

    private func replayedPage(strokeNames: [String]) throws -> PDFPage {
        let document = try blankDocument()
        let strokes = strokeNames.enumerated().map { index, name in
            stroke(named: name.isEmpty ? nil : name, segments: [[CGPoint(x: 50, y: 100 + 100 * Double(index)), CGPoint(x: 150, y: 100 + 100 * Double(index))]])
        }
        let record = PDFEditableInkRecord(drawingData: Data([9, 8, 7]), strokeNames: strokeNames)
        try PDFPageManager.replay([inkUpdate(strokes: strokes, record: record)], on: document)
        return try XCTUnwrap(PDFDocument(data: writtenData(document))?.page(at: 0))
    }

    func testTheRecordIsOnTheGroupsFirstAnnotationOnlyAndNamesAreCountThenCommaJoined() throws {
        let page = try replayedPage(strokeNames: ["alpha", "beta", "gamma"])
        let carriers = page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.drawingKey) != nil }
        XCTAssertEqual(carriers.count, 1)
        XCTAssertTrue(carriers[0] === page.annotations[0], "The first annotation of the group carries it.")
        XCTAssertEqual(carriers[0].value(forAnnotationKey: PDFPageManager.drawingKey) as? String, Data([9, 8, 7]).base64EncodedString())
        XCTAssertEqual(carriers[0].value(forAnnotationKey: PDFPageManager.strokeNamesKey) as? String, "3:alpha,beta,gamma")
        XCTAssertEqual(page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.strokeNamesKey) != nil }.count, 1)
    }

    func testStrokeNamesKeepEmptyNamesInTheirPlace() {
        XCTAssertEqual(PDFInkGroups.encodeStrokeNames(["alpha", "", "gamma"]), "3:alpha,,gamma")
        XCTAssertEqual(PDFInkGroups.encodeStrokeNames([""]), "1:")
        XCTAssertEqual(PDFInkGroups.encodeStrokeNames([]), "0:")
        XCTAssertEqual(PDFInkGroups.decodeStrokeNames("3:alpha,,gamma"), ["alpha", "", "gamma"])
        XCTAssertEqual(PDFInkGroups.decodeStrokeNames("1:"), [""])
    }

    func testReplayingTheSameEditsTwiceWritesTheRecordIdentically() throws {
        let names = ["alpha", "", "gamma"]
        var writtenRecords: [[String]] = []
        for _ in 0..<2 {
            let data = try {
                let document = try blankDocument()
                let strokes = [stroke(named: "alpha", segments: [[CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]]),
                               stroke(named: "gamma", segments: [[CGPoint(x: 50, y: 300), CGPoint(x: 150, y: 300)]])]
                try PDFPageManager.replay([inkUpdate(strokes: strokes, record: PDFEditableInkRecord(drawingData: Data([5, 6]), strokeNames: names))], on: document)
                return try writtenData(document)
            }()
            var records: [String] = []
            try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: data) { dictionaries in
                for dictionary in dictionaries {
                    records.append([PDFAnnotationDictionaryReading.string("NM", in: dictionary),
                                    PDFAnnotationDictionaryReading.string("GraphitePencilDrawingV1", in: dictionary),
                                    PDFAnnotationDictionaryReading.string("GraphiteInkStrokeNamesV1", in: dictionary),
                                    PDFAnnotationDictionaryReading.string("GraphiteInkGroup", in: dictionary)].map { $0 ?? "-" }.joined(separator: "|"))
                }
            }
            writtenRecords.append(records)
        }
        XCTAssertEqual(writtenRecords[0], writtenRecords[1])
        XCTAssertEqual(writtenRecords[0], [
            "alpha|\(Data([5, 6]).base64EncodedString())|3:alpha,,gamma|GraphitePageInkV1",
            "gamma|-|-|GraphitePageInkV1",
        ])
    }

    func testTheRecordMovesToTheNewFirstAnnotationWhenTheFirstStrokeIsRemoved() throws {
        let document = try blankDocument()
        let first = [stroke(named: "A", segments: [[CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]]),
                     stroke(named: "B", segments: [[CGPoint(x: 50, y: 200), CGPoint(x: 150, y: 200)]])]
        try PDFPageManager.apply(inkUpdate(strokes: first, record: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"])), to: document)
        try PDFPageManager.apply(inkUpdate(removal: .strokes(["A"]), strokes: [], record: PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B"])), to: document)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertEqual(page.annotations[0].value(forAnnotationKey: PDFPageManager.strokeNamesKey) as? String, "1:B")
        XCTAssertEqual(page.annotations[0].value(forAnnotationKey: PDFPageManager.drawingKey) as? String, Data([2]).base64EncodedString())
    }

    // MARK: Groups (M-13)

    func testANewGroupIsTheDefaultOneUnlessThePageAlreadyHasIt() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFInkGroups.newGroup(on: page), "GraphitePageInkV1")
        try PDFPageManager.apply(inkUpdate(strokes: [stroke(named: "A", segments: [[CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]])], record: nil), to: document)
        let anotherGroup = PDFInkGroups.newGroup(on: page)
        XCTAssertTrue(anotherGroup.hasPrefix("GraphitePageInk-"), anotherGroup)
        XCTAssertNotNil(UUID(uuidString: String(anotherGroup.dropFirst("GraphitePageInk-".count))))
        XCTAssertNotEqual(PDFInkGroups.newGroup(on: page), anotherGroup, "Every call makes its own.")
    }

    func testAGroupIsEditableOnlyWhenItsNamesAndAnnotationsMatchOneToOne() throws {
        func page(editing change: (PDFPage) throws -> Void) throws -> PDFPage {
            let document = try blankDocument()
            let strokes = [stroke(named: "A", segments: [[CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]]),
                           stroke(named: "B", segments: [[CGPoint(x: 50, y: 200), CGPoint(x: 150, y: 200)]])]
            try PDFPageManager.apply(inkUpdate(strokes: strokes, record: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"])), to: document)
            let inkPage = try XCTUnwrap(document.page(at: 0))
            try change(inkPage)
            return inkPage
        }
        XCTAssertNotNil(PDFInkGroups.editableGroup(on: try page { _ in }))
        XCTAssertNil(PDFInkGroups.editableGroup(on: try page { inkPage in
            inkPage.removeAnnotation(try XCTUnwrap(inkPage.annotations.last))
        }), "An annotation removed in another tool.")
        XCTAssertNil(PDFInkGroups.editableGroup(on: try page { inkPage in
            let added = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), forType: .ink, withProperties: nil)
            added.setPersistentName("C")
            added.setValue(PDFInkGroups.defaultGroup, forAnnotationKey: PDFPageManager.groupKey)
            inkPage.addAnnotation(added)
        }), "An annotation added in another tool.")
        XCTAssertNil(PDFInkGroups.editableGroup(on: try page { inkPage in
            try XCTUnwrap(inkPage.annotations.last).setPersistentName("A")
        }), "Two annotations of one name.")
        XCTAssertNil(PDFInkGroups.editableGroup(on: try page { inkPage in
            try XCTUnwrap(inkPage.annotations.last).setValue("", forAnnotationKey: PDFPageManager.annotationNameKey)
            try XCTUnwrap(inkPage.annotations.last).setValue("", forAnnotationKey: .name)
        }), "An annotation with no name.")
    }

    func testARecordLargerThanTheBoundsIsNotRead() throws {
        func pageWithRecord(drawing: String, names: String) throws -> PDFPage {
            let document = try blankDocument()
            try PDFPageManager.apply(inkUpdate(strokes: [stroke(named: "A", segments: [[CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]])], record: nil), to: document)
            let page = try XCTUnwrap(document.page(at: 0))
            let carrier = try XCTUnwrap(page.annotations.first)
            carrier.setValue(drawing, forAnnotationKey: PDFPageManager.drawingKey)
            carrier.setValue(names, forAnnotationKey: PDFPageManager.strokeNamesKey)
            return page
        }
        XCTAssertNotNil(PDFInkGroups.editableGroup(on: try pageWithRecord(drawing: Data([1]).base64EncodedString(), names: "1:A")))
        let oversizedDrawing = String(repeating: "A", count: PDFInkGroups.maximumEncodedDrawingBytes + 4)
        XCTAssertNil(PDFInkGroups.editableGroup(on: try pageWithRecord(drawing: oversizedDrawing, names: "1:A")))
        let oversizedNames = "1:" + String(repeating: "A", count: PDFInkGroups.maximumEncodedStrokeNameBytes)
        XCTAssertNil(PDFInkGroups.editableGroup(on: try pageWithRecord(drawing: Data([1]).base64EncodedString(), names: oversizedNames)))
    }
}
