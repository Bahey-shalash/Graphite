import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

/// The Goodnotes reader on small synthetic notebooks built in the test (no sample or personal content).
final class GoodnotesNotebookReaderTests: XCTestCase {
    private static let firstPage = "0A1B2C3D-0000-0000-0000-0000000025FF"
    private static let secondPage = "0A1B2C3D-0000-0000-0000-00000000000A"
    private static let deletedPage = "0A1B2C3D-0000-0000-0000-000000000033"
    private static let firstLayer = "0A1B2C3D-0000-0000-0000-000000002500"
    private static let secondLayer = "0A1B2C3D-0000-0000-0000-00000000000B"

    // MARK: Event log

    func testTheTitleIsTheRegisterWithTheHighestCounter() throws {
        var builder = Self.notebookWithTwoPages()
        builder.events.append(GoodnotesRecord.event(entity: "DOCUMENT", kind: 30, body: ProtocolBufferWriter.message { message in
            message.message(2, GoodnotesRecord.register(text: "First title", counter: 2))
        }))
        builder.events.append(GoodnotesRecord.event(entity: "DOCUMENT", kind: 31, body: ProtocolBufferWriter.message { message in
            message.message(2, GoodnotesRecord.register(text: "Renamed", counter: 5))
        }))
        builder.events.append(GoodnotesRecord.event(entity: "DOCUMENT", kind: 31, body: ProtocolBufferWriter.message { message in
            message.message(2, GoodnotesRecord.register(text: "Older rename", counter: 3))
        }))
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.title, "Renamed")
        XCTAssertEqual(reader.notebook.schemaVersion, 24)
        XCTAssertEqual(reader.notebook.issues, [])
    }

    func testPagesAreSortedByPositionByteByByteWithDeletedPagesLeftOut() throws {
        var builder = Self.notebookWithTwoPages()
        builder.addPage(Self.deletedPage, position: "0", paper: "PAPER")
        builder.events.append(GoodnotesRecord.event(entity: Self.deletedPage, kind: 56, body: ProtocolBufferWriter.message { message in
            message.message(3, GoodnotesRecord.register(number: 1, counter: 2))
        }))
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.pages.map(\.identifier), [Self.secondPage, Self.firstPage])
        XCTAssertEqual(reader.notebook.deletedPageCount, 1)
    }

    func testAMoveWithAHigherCounterGivesThePageItsNewPosition() throws {
        var builder = Self.notebookWithTwoPages()
        builder.events.append(GoodnotesRecord.event(entity: Self.firstPage, kind: 55, body: ProtocolBufferWriter.message { message in
            message.message(3, GoodnotesRecord.register(text: "4!Wfh", counter: 7))
        }))
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.pages.map(\.identifier), [Self.firstPage, Self.secondPage])
    }

    func testAPageLayerIsThePageIdentifierWithOneAddedToItsLastByteWithoutCarry() throws {
        let reader = try GoodnotesNotebookReader(archiveBytes: Self.notebookWithTwoPages().archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.pages.map(\.layerIdentifier), [Self.secondLayer, Self.firstLayer])
        XCTAssertNil(GoodnotesEventLog.layerIdentifier(forPage: "PAGE-ZZ"))
    }

    func testThePaperNamesItsAttachmentSizeAndDecodedTemplate() throws {
        let reader = try GoodnotesNotebookReader(archiveBytes: Self.notebookWithTwoPages().archiveBytes(), limits: .standard)
        let paper = try XCTUnwrap(reader.notebook.pages.first?.paper)
        XCTAssertEqual(paper.attachment?.file?.text, "attachments/TEMPLATEFILE")
        XCTAssertEqual(paper.attachment?.pdfPageCount, 1)
        XCTAssertEqual(paper.pdfPageNumber, 1)
        XCTAssertEqual(paper.sizeInUnits, CGSize(width: 1100, height: 1650))
        XCTAssertEqual(paper.sizeInPoints, CGSize(width: 600, height: 900))
        let template = try XCTUnwrap(paper.template)
        XCTAssertEqual(template.catalogueIdentifier, "CATALOGUE")
        XCTAssertEqual(template.size, .a4)
        XCTAssertEqual(template.orientation, .landscape)
        XCTAssertEqual(template.design, "2 - White")
        XCTAssertEqual(GoodnotesTemplateIdentifier(rawIdentifier: "CATALOGUE_letter_3_x").size, .unknown("letter"))
        XCTAssertNil(GoodnotesTemplateIdentifier(rawIdentifier: "no parts").catalogueIdentifier)
        XCTAssertEqual(Array(try reader.contents(of: try XCTUnwrap(paper.attachment))), Array("%PDF-1.7 template".utf8))
    }

    func testBookmarksOutlineEntriesAndRecordingsAreRead() throws {
        var builder = Self.notebookWithTwoPages()
        builder.events.append(GoodnotesRecord.event(entity: Self.firstPage, kind: 57, body: ProtocolBufferWriter.message { message in
            message.message(3, GoodnotesRecord.register(number: 1, counter: 2))
        }))
        for (title, orderKey) in [("Second", "b"), ("First", "a")] {
            builder.events.append(GoodnotesRecord.event(entity: "OUTLINE-\(title)", kind: 62, body: ProtocolBufferWriter.message { message in
                message.string(2, "TARGET")
                message.message(3, ProtocolBufferWriter.message { target in target.message(1, GoodnotesRecord.point(10, 20)) })
                message.string(5, title)
                message.string(6, orderKey)
            }))
        }
        builder.addAttachment("AUDIO", fileIdentifier: "AUDIOFILE", contents: [1, 2, 3], pdfPageCount: nil)
        for recording in ["KEPT", "REMOVED"] {
            builder.events.append(GoodnotesRecord.event(entity: recording, kind: 160, body: Self.recordingBody()))
        }
        builder.events.append(GoodnotesRecord.event(entity: "REMOVED", kind: 163, body: ProtocolBufferWriter()))
        let notebook = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).notebook
        XCTAssertEqual(notebook.pages.map(\.isBookmarked), [false, true])
        XCTAssertEqual(notebook.outlineEntries.map(\.title), ["First", "Second"])
        XCTAssertEqual(notebook.outlineEntries.first?.pointOnTargetPage, CGPoint(x: 10, y: 20))
        XCTAssertEqual(notebook.recordings.map(\.identifier), ["KEPT"])
        let recording = try XCTUnwrap(notebook.recordings.first)
        XCTAssertEqual(recording.audio?.file?.text, "attachments/AUDIOFILE")
        XCTAssertEqual(recording.durationSeconds, 2, accuracy: 1e-9)
        XCTAssertEqual(recording.elementTimings, [GoodnotesRecording.ElementTiming(elementIdentifier: "STROKE", secondsFromStart: 0.5,
                                                                                   pageIdentifier: Self.firstPage)])
    }

    func testAnUnknownEventKindAndSchemaVersionAreReported() throws {
        var builder = Self.notebookWithTwoPages()
        builder.schemaVersion = 99
        builder.events.append(GoodnotesRecord.event(entity: "SOMETHING", kind: 77, body: ProtocolBufferWriter()))
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.issues, [.schemaVersionNotKnown(99), .eventKindNotKnown(77)])
        XCTAssertEqual(reader.pageCount, 2)
    }

    // MARK: Elements

    func testElementsAreInDrawingOrderAndErasedElementsAreLeftOut() throws {
        var builder = Self.notebookWithTwoPages()
        let path = GoodnotesRecord.constantWidthPath(width: 2, subpaths: [((1, 1), [(2, 2, 3, 3)])])
        builder.layers[Self.firstLayer] = [
            GoodnotesRecord.header("LATE"), GoodnotesRecord.stroke("LATE", path: path, position: (5, 0)),
            GoodnotesRecord.header("ERASED", isDeleted: true), GoodnotesRecord.stroke("ERASED", path: path, position: (1, 0)),
            GoodnotesRecord.header("EARLY"), GoodnotesRecord.stroke("EARLY", path: path, position: (2, 9)),
            GoodnotesRecord.header("EARLIEST"), GoodnotesRecord.stroke("EARLIEST", path: path, position: (2, 1)),
        ]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.elements.map(\.identifier), ["EARLIEST", "EARLY", "LATE"])
        XCTAssertEqual(page.elements.first?.drawingPosition, GoodnotesDrawingPosition(counter: 2, replica: 1))
        XCTAssertEqual(page.issues, [])
    }

    func testAConstantWidthStrokeKeepsItsSubpathsWidthDashOffsetColourAndGroup() throws {
        var builder = Self.notebookWithTwoPages()
        let path = GoodnotesRecord.constantWidthPath(width: 2.5, subpaths: [((1, 2), [(3, 4, 5, 6), (7, 8, 9, 10)]), ((11, 12), [])],
                                                     dashPattern: [4, 2])
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("PEN"), GoodnotesRecord.stroke("PEN", path: path, position: (1, 1)) { message in
            message.message(4, GoodnotesRecord.color(1, 0.5, 0, 0.5))
            message.varint(5, 1)
            message.message(6, GoodnotesRecord.point(10, -5))
            message.string(10, "GROUP")
            message.lengthDelimited(20, [])
        }]
        let stroke = try Self.onlyStroke(of: builder)
        XCTAssertEqual(stroke.ink, .ballPenOrHighlighter)
        XCTAssertEqual(stroke.color, NotebookImportColor(red: 1, green: 0.5, blue: 0, alpha: 0.5))
        XCTAssertTrue(stroke.isHighlighter)
        XCTAssertFalse(stroke.isTape)
        XCTAssertEqual(stroke.groupIdentifier, "GROUP")
        XCTAssertEqual(stroke.offset, CGVector(dx: 10, dy: -5))
        XCTAssertNil(stroke.shape)
        let expected = GoodnotesConstantWidthPath(width: 2.5, subpaths: [
            GoodnotesSubpath(start: CGPoint(x: 1, y: 2), curves: [
                GoodnotesQuadraticCurve(control: CGPoint(x: 3, y: 4), end: CGPoint(x: 5, y: 6)),
                GoodnotesQuadraticCurve(control: CGPoint(x: 7, y: 8), end: CGPoint(x: 9, y: 10)),
            ]),
            GoodnotesSubpath(start: CGPoint(x: 11, y: 12), curves: []),
        ], dashPattern: [4, 2])
        XCTAssertEqual(stroke.path, .constantWidth(expected))
    }

    func testAVaryingWidthStrokeHasItsCenterLineAndOutlineWithArcsAndFlatCaps() throws {
        var builder = Self.notebookWithTwoPages()
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("FOUNTAIN"),
                                           GoodnotesRecord.stroke("FOUNTAIN", path: Self.varyingWidthPath(), position: (1, 1)) { message in
            message.varint(3, 1)
            message.lengthDelimited(20, ProtocolBufferWriter.message { tape in tape.string(1, "") }.bytes)
        }]
        let stroke = try Self.onlyStroke(of: builder)
        XCTAssertEqual(stroke.ink, .fountainPenBrushPenOrTape)
        XCTAssertTrue(stroke.isTape)
        guard case .varyingWidth(let path) = stroke.path else { return XCTFail("not a varying-width path") }
        XCTAssertEqual(path.centerLine, GoodnotesCenterLine(
            start: GoodnotesWidthPoint(point: CGPoint(x: 1, y: 1), width: 2),
            curves: [GoodnotesWidthCurve(control: GoodnotesWidthPoint(point: CGPoint(x: 2, y: 2), width: 3),
                                         end: GoodnotesWidthPoint(point: CGPoint(x: 4, y: 4), width: 1))]))
        XCTAssertEqual(path.outline, [[
            .move(to: CGPoint(x: 0, y: 0)),
            .cubic(control1: CGPoint(x: 1, y: 0), control2: CGPoint(x: 2, y: 0), end: CGPoint(x: 3, y: 0)),
            .arc(center: CGPoint(x: 3, y: 1), radius: 1, startAngleRadians: -1.5, endAngleRadians: 1.5),
            .cubic(control1: CGPoint(x: 2, y: 2), control2: CGPoint(x: 1, y: 2), end: CGPoint(x: 0, y: 2)),
            .flatCap(through: CGPoint(x: 0, y: 1)),
        ]])
    }

    func testAPencilStrokeCarriesAzimuthAltitudeAndForceAtEachPoint() throws {
        var builder = Self.notebookWithTwoPages()
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("PENCIL"),
                                           GoodnotesRecord.stroke("PENCIL", path: Self.pencilPath(), position: (1, 1)) { message in message.varint(3, 5) }]
        let stroke = try Self.onlyStroke(of: builder)
        XCTAssertEqual(stroke.ink, .pencil)
        XCTAssertEqual(stroke.path, .pencil(GoodnotesPencilPath(width: 4.5, subpaths: [GoodnotesPencilSubpath(
            start: GoodnotesPencilSample(point: CGPoint(x: 1, y: 2), azimuthRadians: 0.5, altitudeRadians: 1, force: 0.25),
            curves: [GoodnotesPencilCurve(
                control: GoodnotesPencilSample(point: CGPoint(x: 3, y: 4), azimuthRadians: 0.5, altitudeRadians: 0.75, force: 1),
                end: GoodnotesPencilSample(point: CGPoint(x: 5, y: 6), azimuthRadians: -0.5, altitudeRadians: 0.25, force: 2),
                leadingValue: 0xDEAD_BEEF)])])))
    }

    func testAShapeAndItsFillAreReadWithTheirGeometry() throws {
        var builder = Self.notebookWithTwoPages()
        let emptyPath = GoodnotesRecord.constantWidthPath(width: 1, subpaths: [])
        let ellipse = ProtocolBufferWriter.message { shape in
            shape.message(4, ProtocolBufferWriter.message { geometry in
                geometry.message(1, GoodnotesRecord.point(50, 60))
                geometry.message(2, GoodnotesRecord.point(20, 10))
                geometry.float(3, 0.5)
            })
            shape.float(15, 3)
        }
        builder.layers[Self.firstLayer] = [
            GoodnotesRecord.header("SHAPE"), GoodnotesRecord.stroke("SHAPE", path: emptyPath, position: (1, 1)) { message in message.message(9, ellipse) },
            GoodnotesRecord.header("FILL"), GoodnotesRecord.body(kind: 9, ProtocolBufferWriter.message { fill in
                fill.string(1, "FILL")
                fill.message(3, GoodnotesRecord.position(counter: 2, replica: 1))
                fill.message(4, ProtocolBufferWriter.message { shape in
                    shape.message(1, ProtocolBufferWriter.message { polygon in
                        for (x, y) in [(0, 0), (10, 0), (10, 10)] as [(Float, Float)] { polygon.message(1, GoodnotesRecord.point(x, y)) }
                    })
                })
                fill.string(5, "SHAPE")
                fill.message(7, GoodnotesRecord.color(0, 0, 1, 0.1))
            }),
        ]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.elements.count, 2)
        guard case .stroke(let stroke)? = page.elements.first?.content, case .shapeFill(let fill)? = page.elements.last?.content else {
            return XCTFail("expected a shape stroke and a fill")
        }
        XCTAssertEqual(stroke.shape, GoodnotesShape(geometry: .ellipse(center: CGPoint(x: 50, y: 60), radii: CGSize(width: 20, height: 10),
                                                                       angleRadians: 0.5), width: 3))
        XCTAssertEqual(fill.shape?.geometry, .polyline([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]))
        XCTAssertEqual(fill.outlineStrokeIdentifiers, ["SHAPE"])
        XCTAssertEqual(fill.color.alpha, 0.1, accuracy: 1e-6)
    }

    func testAPictureNamesItsAttachmentPlacementTurnAndKind() throws {
        var builder = Self.notebookWithTwoPages()
        builder.addAttachment("PICTURE", fileIdentifier: "PICTUREFILE", contents: [0x89, 0x50], pdfPageCount: nil)
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("PICTURE"), GoodnotesRecord.body(kind: 1, ProtocolBufferWriter.message { picture in
            picture.string(1, "PICTURE")
            picture.message(2, ProtocolBufferWriter.message { box in
                box.message(1, GoodnotesRecord.point(5, 6))
                box.message(2, GoodnotesRecord.point(70, 80))
            })
            picture.message(3, ProtocolBufferWriter.message { placement in
                placement.message(1, GoodnotesRecord.point(40, 46))
                placement.message(2, GoodnotesRecord.point(60, 40))
                placement.float(3, 0.5)
            })
            picture.string(4, "PICTURE")
            picture.message(5, GoodnotesRecord.position(counter: 1, replica: 1))
            picture.varint(6, 5)
        })]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        guard case .picture(let picture)? = page.elements.first?.content else { return XCTFail("expected a picture") }
        XCTAssertEqual(picture.attachment?.file?.text, "attachments/PICTUREFILE")
        XCTAssertEqual(picture.boundingBox, CGRect(x: 5, y: 6, width: 70, height: 80))
        XCTAssertEqual(picture.center, CGPoint(x: 40, y: 46))
        XCTAssertEqual(picture.size, CGSize(width: 60, height: 40))
        XCTAssertEqual(picture.rotationRadians, 0.5)
        XCTAssertEqual(picture.kind, .animatedGIF)
    }

    func testATextBoxDecompressesItsRichTextWithFontSizeColourAndLink() throws {
        var builder = Self.notebookWithTwoPages()
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("TEXT"), GoodnotesRecord.body(kind: 21, ProtocolBufferWriter.message { textBox in
            textBox.string(1, "TEXT")
            textBox.message(7, GoodnotesRecord.position(counter: 1, replica: 1))
            textBox.message(20, ProtocolBufferWriter.message { placement in
                placement.message(1, GoodnotesRecord.point(100, 200))
                placement.float(2, -0.75)
                placement.float(3, 2.5)
            })
            textBox.message(32, Self.richTextContainer(text: "Graphite one", size: 24, extra: { layout in
                layout.message(2, GoodnotesRecord.point(140, 29))
                layout.message(10, ProtocolBufferWriter.message { insets in for side in 1...4 { insets.float(side, 10) } })
            }))
        })]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        guard case .textBox(let textBox)? = page.elements.first?.content else { return XCTFail("expected a text box") }
        XCTAssertEqual(textBox.origin, CGPoint(x: 100, y: 200))
        XCTAssertEqual(textBox.rotationRadians, -0.75)
        XCTAssertEqual(textBox.scale, 2.5)
        XCTAssertEqual(textBox.size, CGSize(width: 140, height: 29))
        XCTAssertEqual(textBox.insets, [10, 10, 10, 10])
        XCTAssertEqual(textBox.richText.text, "Graphite one")
        XCTAssertEqual(textBox.richText.runs, [GoodnotesRichText.Attributes(
            color: NotebookImportColor(red: 1, green: 0, blue: 0, alpha: 1), link: "https://example.com/graphite", fontName: "Georgia", sizeInUnits: 24)])
        XCTAssertEqual(textBox.richText.defaultAttributes, GoodnotesRichText.Attributes(color: nil, link: nil, fontName: "HelveticaNeue",
                                                                                        sizeInUnits: nil))
    }

    func testStickyNotesAndRTFTextBoxesAreRead() throws {
        var builder = Self.notebookWithTwoPages()
        builder.layers[Self.firstLayer] = [
            GoodnotesRecord.header("NOTE"), GoodnotesRecord.body(kind: 20, ProtocolBufferWriter.message { note in
                note.string(1, "NOTE")
                note.message(7, GoodnotesRecord.position(counter: 1, replica: 1))
                note.message(20, ProtocolBufferWriter.message { placement in placement.message(1, GoodnotesRecord.point(10, 10)) })
                note.message(21, ProtocolBufferWriter.message { size in size.message(2, GoodnotesRecord.point(256, 256)) })
                note.message(30, GoodnotesRecord.color(1, 1, 0.5, 1))
                note.message(31, Self.richTextContainer(text: "Remember", size: -404, extra: { _ in }))
                note.string(33, "Author")
            }),
            GoodnotesRecord.header("RTF"), GoodnotesRecord.body(kind: 8, ProtocolBufferWriter.message { box in
                box.string(1, "RTF")
                box.message(2, ProtocolBufferWriter.message { frame in
                    frame.message(1, GoodnotesRecord.point(0, 0))
                    frame.message(2, GoodnotesRecord.point(100, 50))
                })
                box.message(5, GoodnotesRecord.position(counter: 2, replica: 1))
                box.string(6, "{\\rtf1 Hello}")
            }),
        ]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        guard case .stickyNote(let note)? = page.elements.first?.content, case .rtfTextBox(let box)? = page.elements.last?.content else {
            return XCTFail("expected a sticky note and an RTF text box")
        }
        XCTAssertEqual(note.size, CGSize(width: 256, height: 256))
        XCTAssertEqual(note.richText.text, "Remember")
        XCTAssertNil(note.richText.runs.first?.sizeInUnits)
        XCTAssertEqual(note.authorName, "Author")
        XCTAssertEqual(box.frame, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(box.rtf, "{\\rtf1 Hello}")
    }

    func testUnknownKindsFieldsAndPathFormatsAreReportedNotGuessed() throws {
        var builder = Self.notebookWithTwoPages()
        var unknownImage = TplImageWriter(formatString: "vA(u)")
        unknownImage.uint16(2)
        unknownImage.floatArray([], elementCount: 0)
        let path = GoodnotesRecord.constantWidthPath(width: 1, subpaths: [((0, 0), [])])
        builder.layers[Self.firstLayer] = [
            GoodnotesRecord.header("NEWKIND"), GoodnotesRecord.body(kind: 44, ProtocolBufferWriter.message { body in body.string(1, "NEWKIND") }),
            GoodnotesRecord.header("NEWFORMAT"), GoodnotesRecord.stroke("NEWFORMAT", path: unknownImage.bytes, position: (1, 1)),
            GoodnotesRecord.header("NEWFIELD"), GoodnotesRecord.stroke("NEWFIELD", path: path, position: (2, 1)) { message in message.varint(99, 1) },
            GoodnotesRecord.stroke("ORPHAN", path: path, position: (3, 1)),
        ]
        builder.events.append(GoodnotesRecord.event(entity: Self.firstLayer, kind: 106, body: ProtocolBufferWriter.message { members in
            for member in ["NEWKIND", "NEWFORMAT"] { members.message(2, GoodnotesRecord.register(text: member, counter: 1)) }
        }))
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        // OCP-IMPORT-01: elements of an unknown kind or path layout used to be dropped, reported once per kind.
        XCTAssertEqual(page.elements.map(\.identifier), ["NEWFORMAT", "NEWFIELD", "NEWKIND"])
        XCTAssertEqual(page.elements.last?.content, .unknown(kind: 44, fieldNumbers: [1]))
        XCTAssertEqual(page.elements.last?.drawingPosition, .unknown)
        guard case .stroke(let unknownLayoutStroke)? = page.elements.first?.content else { return XCTFail("expected the stroke kept") }
        XCTAssertEqual(unknownLayoutStroke.path, .unknownLayout(formatString: "vA(u)"))
        XCTAssertEqual(page.issues, [
            .elementKindNotKnown(kind: 44, elementIdentifier: "NEWKIND"), .strokePathFormatNotKnown(formatString: "vA(u)", elementIdentifier: "NEWFORMAT"),
            .elementMissingFromMemberList(elementIdentifier: "NEWFIELD"), .elementFieldNotKnown(elementKind: 7, fieldNumber: 99),
            .bodyWithoutHeader(elementIdentifier: "ORPHAN"),
        ])
    }

    // MARK: Damaged and hostile files

    func testBytesThatAreNotAZipArchiveFailWithATypedError() {
        XCTAssertThrowsError(try GoodnotesNotebookReader(archiveBytes: Data("not a notebook at all, just text".utf8), limits: .standard)) { error in
            XCTAssertEqual(error as? GoodnotesReadingError, .archive(.endOfCentralDirectoryMissing))
        }
    }

    func testAZipArchiveWithoutASchemaIsNotAGoodnotesNotebook() {
        var archive = ZipArchiveBuilder()
        archive.addEntry(named: "index.events.pb", contents: [])
        XCTAssertThrowsError(try GoodnotesNotebookReader(archiveBytes: archive.archiveBytes(), limits: .standard)) { error in
            XCTAssertEqual(error as? GoodnotesReadingError, .notAGoodnotesNotebook)
        }
    }

    /// CC-IMPORT-10: an attachment's file identifier was used as a path as stored, `../` included.
    func testAnAttachmentWhoseFileClimbsOutIsReportedAndItsFileIsNotRead() throws {
        var builder = Self.notebookWithTwoPages()
        builder.events.append(GoodnotesRecord.event(entity: "ESCAPE", kind: 6, body: ProtocolBufferWriter.message { message in
            message.string(1, "ESCAPE")
            message.string(2, "../../escape")
        }))
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.issues, [.attachmentPathNotValid(attachmentIdentifier: "ESCAPE")])
        XCTAssertEqual(reader.notebook.pages.first?.paper?.attachment?.file?.text, "attachments/TEMPLATEFILE")
    }

    /// CC-IMPORT-09: a paper, picture or recording whose attachment is not in the log read as nil with no issue.
    func testAttachmentsAndPapersMissingFromTheLogAreReported() throws {
        var builder = Self.notebookWithTwoPages()
        builder.addPage(Self.deletedPage, position: "c", paper: "NO-SUCH-PAPER")
        builder.events.append(GoodnotesRecord.event(entity: "RECORDING", kind: 160, body: ProtocolBufferWriter.message { recording in
            recording.string(2, "NO-SUCH-AUDIO")
        }))
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("PICTURE"), GoodnotesRecord.body(kind: 1, ProtocolBufferWriter.message { picture in
            picture.string(1, "PICTURE")
            picture.string(4, "NO-SUCH-PICTURE")
            picture.message(5, GoodnotesRecord.position(counter: 1, replica: 1))
        })]
        let reader = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.issues, [.paperNotInLog(pageIdentifier: Self.deletedPage),
                                                .attachmentNotInLog(attachmentIdentifier: "NO-SUCH-AUDIO")])
        XCTAssertEqual(try reader.page(at: 1).issues, [.attachmentNotInLog(attachmentIdentifier: "NO-SUCH-PICTURE")])
    }

    /// BUG-IMPORT-01: a notebook whose event log is missing read as an empty notebook with no issue.
    func testANotebookWithoutItsEventLogFailsWithATypedErrorInsteadOfReadingAsEmpty() {
        var archive = ZipArchiveBuilder()
        archive.addEntry(named: "schema.pb", contents: ProtocolBufferWriter.message { message in message.varint(1, 24) }.bytes)
        archive.addEntry(named: "notes/\(Self.firstLayer)", contents: [])
        XCTAssertThrowsError(try GoodnotesNotebookReader(archiveBytes: archive.archiveBytes(), limits: .standard)) { error in
            XCTAssertEqual(error as? GoodnotesReadingError, .eventLogMissing)
        }
    }

    /// CC-IMPORT-08: an unreadable `schema.pb`, which holds only the version, failed the whole notebook.
    func testAnUnreadableSchemaIsReportedAndTheNotebookStillReads() throws {
        let builder = Self.notebookWithTwoPages()
        var archive = ZipArchiveBuilder()
        archive.addEntry(named: "schema.pb", contents: [0x0A, 0x05, 0x01])
        archive.addEntry(named: "index.events.pb", contents: GoodnotesRecord.lengthPrefixed(builder.events))
        let reader = try GoodnotesNotebookReader(archiveBytes: archive.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.schemaVersion, nil)
        XCTAssertEqual(reader.notebook.issues, [.schemaVersionNotKnown(nil)])
        XCTAssertEqual(reader.pageCount, 2)
    }

    func testATruncatedEventLogKeepsTheEventsBeforeTheCut() throws {
        var builder = Self.notebookWithTwoPages()
        builder.events.append([0x0A, 0x05, 0x41])
        var archive = ZipArchiveBuilder()
        archive.addEntry(named: "schema.pb", contents: ProtocolBufferWriter.message { message in message.varint(1, 24) }.bytes)
        archive.addEntry(named: "index.events.pb", contents: GoodnotesRecord.lengthPrefixed(builder.events) + [0x7F, 0x01])
        let reader = try GoodnotesNotebookReader(archiveBytes: archive.archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.pageCount, 2)
        XCTAssertEqual(reader.notebook.issues, [.eventSkipped(.protocolBuffer(.truncated)), .recordsTruncated(.protocolBuffer(.truncated))])
    }

    func testAnUnreadableStrokeIsSkippedAndTheRestOfThePageIsRead() throws {
        var builder = Self.notebookWithTwoPages()
        let path = GoodnotesRecord.constantWidthPath(width: 1, subpaths: [((0, 0), [])])
        var hugeArray = TplImageWriter(formatString: "vuA(v)A(S(uu))A(S(uuuu))vA(f)")
        hugeArray.uint16(2)
        hugeArray.float(1)
        hugeArray.rawUInt32Array([], elementCount: Int(Int32.max))
        builder.layers[Self.firstLayer] = [
            GoodnotesRecord.header("GOOD"), GoodnotesRecord.stroke("GOOD", path: path, position: (1, 1)),
            GoodnotesRecord.header("HUGE"), GoodnotesRecord.stroke("HUGE", path: hugeArray.bytes, position: (2, 1)),
            GoodnotesRecord.header("BADCODE"), GoodnotesRecord.stroke("BADCODE", path: Self.pathWithCurveBeforeStart(), position: (3, 1)),
            GoodnotesRecord.header("NOTLZ4"), GoodnotesRecord.body(kind: 7, ProtocolBufferWriter.message { stroke in
                stroke.string(1, "NOTLZ4")
                stroke.lengthDelimited(2, Array("xxxx".utf8))
            }),
        ]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.elements.map(\.identifier), ["GOOD"])
        XCTAssertEqual(page.issues, [
            .elementSkipped(elementIdentifier: "HUGE", .tplImage(.valueOutsideImage)),
            .elementSkipped(elementIdentifier: "BADCODE", .pathCodeOutOfPlace(code: 1)),
            .elementSkipped(elementIdentifier: "NOTLZ4", .compressedPayload(.blockKindNotKnown)),
        ])
    }

    func testACompressedPathOverTheLimitIsSkippedWithoutBeingDecoded() throws {
        var builder = Self.notebookWithTwoPages()
        let declaredHuge = Array("bv41".utf8) + LittleEndianEncoding.bytes(UInt32.max) + LittleEndianEncoding.bytes(UInt32(0)) + Array("bv4$".utf8)
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("BOMB"), GoodnotesRecord.body(kind: 7, ProtocolBufferWriter.message { stroke in
            stroke.string(1, "BOMB")
            stroke.lengthDelimited(2, declaredHuge)
        })]
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.issues, [.elementSkipped(elementIdentifier: "BOMB", .compressedPayload(.decodedSizeOverLimit(limitBytes: 64 * 1_048_576)))])
    }

    func testATruncatedLayerReturnsTheElementsBeforeTheCut() throws {
        var builder = Self.notebookWithTwoPages()
        let path = GoodnotesRecord.constantWidthPath(width: 1, subpaths: [((0, 0), [])])
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("KEPT"), GoodnotesRecord.stroke("KEPT", path: path, position: (1, 1)), []]
        var archive = ZipArchiveBuilder()
        archive.addEntry(named: "schema.pb", contents: ProtocolBufferWriter.message { message in message.varint(1, 24) }.bytes)
        archive.addEntry(named: "index.events.pb", contents: GoodnotesRecord.lengthPrefixed(builder.events))
        let layer = GoodnotesRecord.lengthPrefixed([GoodnotesRecord.header("KEPT"), GoodnotesRecord.stroke("KEPT", path: path, position: (1, 1))])
        archive.addEntry(named: "notes/\(Self.firstLayer)", contents: layer + [0x40, 0x0A])
        let page = try GoodnotesNotebookReader(archiveBytes: archive.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.elements.map(\.identifier), ["KEPT"])
        XCTAssertEqual(page.issues, [.recordsTruncated(.protocolBuffer(.truncated))])
    }

    func testAPageIndexOutsideTheNotebookThrows() throws {
        let reader = try GoodnotesNotebookReader(archiveBytes: Self.notebookWithTwoPages().archiveBytes(), limits: .standard)
        XCTAssertThrowsError(try reader.page(at: 2)) { error in XCTAssertEqual(error as? GoodnotesReadingError, .pageIndexOutOfRange(2)) }
        XCTAssertEqual(try reader.page(at: 0).elements, [])
    }

    /// Every cut and many byte changes of a valid notebook either read or fail with a typed error; none traps or hangs.
    func testDamagedCopiesOfANotebookReadOrFailCleanly() {
        var builder = Self.notebookWithTwoPages()
        builder.layers[Self.firstLayer] = [GoodnotesRecord.header("PEN"),
                                           GoodnotesRecord.stroke("PEN", path: Self.varyingWidthPath(), position: (1, 1)),
                                           GoodnotesRecord.header("PENCIL"), GoodnotesRecord.stroke("PENCIL", path: Self.pencilPath(), position: (2, 1))]
        let original = [UInt8](builder.archiveBytes())
        var generator = GoodnotesDamageGenerator(seed: 0x6E0D_0E5)
        for cut in stride(from: 0, to: original.count, by: 7) { Self.readEveryPage(of: Data(original.prefix(cut))) }
        for _ in 0..<3_000 {
            var damaged = original
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            Self.readEveryPage(of: Data(damaged))
        }
    }

    // MARK: Fixtures

    private static func readEveryPage(of archiveBytes: Data) {
        do {
            let reader = try GoodnotesNotebookReader(archiveBytes: archiveBytes, limits: .standard)
            for pageIndex in 0..<reader.pageCount { _ = try reader.page(at: pageIndex) }
        } catch {
            XCTAssertNotNil(error as? GoodnotesReadingError)
        }
    }

    /// Two pages on template paper, positions "b" (first page) and "a" (second page), and no elements.
    private static func notebookWithTwoPages() -> GoodnotesNotebookBuilder {
        var builder = GoodnotesNotebookBuilder()
        builder.addAttachment("TEMPLATE", fileIdentifier: "TEMPLATEFILE", contents: Array("%PDF-1.7 template".utf8), pdfPageCount: 1)
        builder.addPaper("PAPER", attachment: "TEMPLATE", width: 1100, height: 1650, template: "CATALOGUE_a4_2_2 - White")
        builder.addPage(firstPage, position: "b", paper: "PAPER")
        builder.addPage(secondPage, position: "a", paper: "PAPER")
        return builder
    }

    private static func onlyStroke(of builder: GoodnotesNotebookBuilder) throws -> GoodnotesStroke {
        let page = try GoodnotesNotebookReader(archiveBytes: builder.archiveBytes(), limits: .standard).page(at: 1)
        XCTAssertEqual(page.issues, [])
        guard page.elements.count == 1, case .stroke(let stroke)? = page.elements.first?.content else {
            throw GoodnotesReadingError.emptyRecord
        }
        return stroke
    }

    private static func recordingBody() -> ProtocolBufferWriter {
        let flicksPerSecond = UInt64(GoodnotesRecording.flicksPerSecond)
        return ProtocolBufferWriter.message { recording in
            recording.string(2, "AUDIO")
            recording.varint(4, 2 * flicksPerSecond)
            recording.message(5, ProtocolBufferWriter.message { timings in
                timings.message(1, ProtocolBufferWriter.message { timing in
                    timing.string(1, "STROKE")
                    timing.message(2, ProtocolBufferWriter.message { moment in
                        moment.varint(1, flicksPerSecond / 2)
                        moment.string(2, firstPage)
                    })
                })
            })
        }
    }

    /// `{1: {2: compressed rich text}, 5: {1: default attributes}}` with one run.
    private static func richTextContainer(text: String, size: Float, extra: (inout ProtocolBufferWriter) -> Void) -> ProtocolBufferWriter {
        let run = ProtocolBufferWriter.message { attributes in
            attributes.message(3, GoodnotesRecord.color(1, 0, 0, 1))
            attributes.string(4, "https://example.com/graphite")
            attributes.string(30, "Georgia")
            attributes.float(40, size)
        }
        let richText = ProtocolBufferWriter.message { container in
            container.message(1, ProtocolBufferWriter.message { body in
                body.string(1, text)
                body.message(2, run)
            })
        }
        return ProtocolBufferWriter.message { layout in
            layout.message(1, ProtocolBufferWriter.message { content in content.lengthDelimited(2, appleLZ4StoredPayload(richText.bytes)) })
            layout.message(5, ProtocolBufferWriter.message { defaults in
                defaults.message(1, ProtocolBufferWriter.message { attributes in
                    attributes.string(30, "HelveticaNeue")
                    attributes.float(40, -404)
                })
            })
            extra(&layout)
        }
    }

    /// One center-line curve and one closed outline: move, cubic, arc, cubic, flat cap.
    private static func varyingWidthPath() -> [UInt8] {
        var image = TplImageWriter(formatString: "vA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)")
        image.uint16(2)
        image.uint16Array([0, 1])
        image.floatArray([1, 1, 2], elementCount: 3)
        image.floatArray([2, 2, 3, 4, 4, 1], elementCount: 6)
        image.uint16Array([5])
        image.uint16Array([0, 2, 3, 2, 6])
        image.floatArray([0, 0], elementCount: 2)
        image.floatArray([], elementCount: 0)
        image.floatArray([1, 0, 2, 0, 3, 0, 2, 2, 1, 2, 0, 2], elementCount: 12)
        image.floatArray([3, 1, 1, -1.5, 1.5, 0, 0, 0, 1, 0, 0, 0, 0, 0], elementCount: 14)
        image.uint16Array([1, 1])
        return image.bytes
    }

    private static func pencilPath() -> [UInt8] {
        var image = TplImageWriter(formatString: "vuA(v)A(S(uuuuu))A(S(uuuuuuuuuuu))A(S(uu))A(v)A(S(uu))A(S(uuuu))A(u)")
        image.uint16(1)
        image.float(4.5)
        image.uint16Array([0, 1])
        image.floatArray([1, 2, 0.5, 1, 0.25], elementCount: 1)
        image.rawUInt32Array([0xDEAD_BEEF] + [3, 4, 0.5, 0.75, 1, 5, 6, -0.5, 0.25, 2].map { (number: Float) in number.bitPattern }, elementCount: 1)
        image.floatArray([], elementCount: 0)
        image.uint16Array([])
        image.floatArray([], elementCount: 0)
        image.floatArray([], elementCount: 0)
        image.floatArray([], elementCount: 0)
        return image.bytes
    }

    private static func pathWithCurveBeforeStart() -> [UInt8] {
        var image = TplImageWriter(formatString: "vuA(v)A(S(uu))A(S(uuuu))vA(f)")
        image.uint16(2)
        image.float(1)
        image.uint16Array([1])
        image.floatArray([], elementCount: 0)
        image.floatArray([1, 1, 2, 2], elementCount: 1)
        image.uint16(1)
        image.doubleArray([])
        return image.bytes
    }
}

/// SplitMix64, so that the damaged copies are the same on every run.
private struct GoodnotesDamageGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
