import XCTest
@testable import GraphiteCore

/// Damaged and hostile notes: each fails with a typed error, or reports a skipped element, and never traps or hangs.
final class NotabilityNoteReaderMalformedInputTests: XCTestCase {
    private let limits = NotebookImportLimits.standard

    private func readingError(_ archiveBytes: Data, file: StaticString = #filePath, line: UInt = #line) -> NotabilityReadingError? {
        do throws(NotabilityReadingError) {
            _ = try NotabilityNoteReader(archiveBytes: archiveBytes, limits: limits)
            XCTFail("the note was read", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    private func readingError(_ builder: NotabilityNoteBuilder, file: StaticString = #filePath, line: UInt = #line) -> NotabilityReadingError? {
        readingError(builder.noteArchiveBytes(), file: file, line: line)
    }

    private func noteWithOneCurve() -> NotabilityNoteBuilder {
        var builder = NotabilityNoteBuilder()
        builder.curves = [.pen([(1, 1), (2, 2), (3, 3), (4, 4)], uuidByte: 1)]
        return builder
    }

    func testBytesThatAreNotAZipArchiveAreRefused() {
        XCTAssertEqual(readingError(Data("not a zip archive".utf8)), .archive(.endOfCentralDirectoryMissing))
        XCTAssertEqual(readingError(Data()), .archive(.endOfCentralDirectoryMissing))
    }

    func testAnArchiveWithoutExactlyOneFolderIsRefused() {
        var twoFolders = ZipArchiveBuilder()
        twoFolders.addEntry(named: "First/Session.plist", contents: [1], compression: .stored)
        twoFolders.addEntry(named: "Second/Session.plist", contents: [1], compression: .stored)
        XCTAssertEqual(readingError(twoFolders.archiveBytes()), .topLevelFolderCount(2))
        var noFolder = ZipArchiveBuilder()
        noFolder.addEntry(named: "Session.plist", contents: [1], compression: .stored)
        XCTAssertEqual(readingError(noFolder.archiveBytes()), .topLevelFolderCount(0))
    }

    func testAMissingOrForeignSessionIsRefused() {
        var missing = ZipArchiveBuilder()
        missing.addEntry(named: "Note/metadata.plist", contents: [1], compression: .stored)
        XCTAssertEqual(readingError(missing.archiveBytes()), .archive(.entryMissing(name: "Note/Session.plist")))
        let builder = NotabilityNoteBuilder()
        XCTAssertEqual(readingError(builder.noteArchiveBytes(sessionPlistBytes: Array("<plist></plist>".utf8))),
                       .session(.propertyList(.notBinaryPropertyList)))
        var writer = BinaryPropertyListWriter()
        let topObjectIndex = writer.add(tree: .array([.integer(1)]))
        let plainList = writer.bytes(topObjectIndex: topObjectIndex)
        XCTAssertEqual(readingError(builder.noteArchiveBytes(sessionPlistBytes: plainList)), .session(.notKeyedArchive))
    }

    func testTruncatedArchivesAreRefusedAtEveryCut() {
        let complete = NotabilityNoteReaderTests.completeNote().noteArchiveBytes()
        for cut in stride(from: 0, to: complete.count, by: 7) {
            guard case .archive? = readingError(complete.prefix(cut)) else { return XCTFail("cut at \(cut) is not an archive error") }
        }
    }

    func testCountsThatDisagreeWithThePackedArraysAreRefused() {
        var builder = noteWithOneCurve()
        builder.inkFieldOverrides = ["numcurves": .integer(1 << 31)]
        XCTAssertEqual(readingError(builder), .packedArrayLengthWrong(.curvePointCounts, byteCount: 4, expectedValueCount: 1 << 31))
        builder.inkFieldOverrides = ["numcurves": .integer(Int64.max)]
        XCTAssertEqual(readingError(builder), .packedArrayLengthWrong(.curvePointCounts, byteCount: 4, expectedValueCount: Int64.max))
        builder.inkFieldOverrides = ["numcurves": .integer(-1)]
        XCTAssertEqual(readingError(builder), .countNegative(key: "numcurves", count: -1))
        builder.inkFieldOverrides = ["numpoints": .integer(5)]
        XCTAssertEqual(readingError(builder), .curvePointCountsDisagree(sumOfCurvePointCounts: 4, declaredPointCount: 5))
        builder.inkFieldOverrides = ["numfractionalwidths": .integer(3)]
        XCTAssertEqual(readingError(builder), .knotCountsDisagree(sumOfCurveKnotCounts: 2, declaredKnotCount: 3))
        builder.inkFieldOverrides = ["curvespoints": .data([0, 0, 0])]
        XCTAssertEqual(readingError(builder), .packedArrayLengthWrong(.curvePoints, byteCount: 3, expectedValueCount: 4))
        builder.inkFieldOverrides = ["curveUUIDs": .data([])]
        XCTAssertEqual(readingError(builder), .packedArrayLengthWrong(.curveUUIDs, byteCount: 0, expectedValueCount: 1))
        builder.inkFieldOverrides = ["numcurves": nil]
        XCTAssertEqual(readingError(builder), .session(.keyMissing(key: "numcurves")))
        builder.inkFieldOverrides = ["curvesforces": .integer(1)]
        guard case .session(.valueNotOfExpectedKind(expected: .data, _))? = readingError(builder) else { return XCTFail("forces are not data") }
    }

    func testAPointCountThatIsNotThreeKPlusOneIsRefused() {
        var builder = NotabilityNoteBuilder()
        builder.curves = [.pen([(1, 1), (2, 2)], uuidByte: 1)]
        XCTAssertEqual(readingError(builder), .curvePointCountNotThreeKPlusOne(curveIndex: 0, pointCount: 2))
        builder.curves = [.pen([(1, 1)], uuidByte: 1)]
        builder.curves[0].points = []
        XCTAssertEqual(readingError(builder), .curvePointCountNotThreeKPlusOne(curveIndex: 0, pointCount: 0))
    }

    func testCyclicGraphsEndInTypedErrorsOrSkippedElements() throws {
        var backReference = noteWithOneCurve()
        backReference.handwritingOverlayNamesRichText = true
        XCTAssertEqual(readingError(backReference), .session(.keyMissing(key: "SpatialHash")))
        var loopingName = noteWithOneCurve()
        loopingName.nameIsAUIDLoop = true
        guard case .session(.referenceCycle)? = readingError(loopingName) else { return XCTFail("the UID loop is not a cycle") }
        var selfContainingMedia = noteWithOneCurve()
        selfContainingMedia.mediaObjectsContainThemselves = true
        let reader = try NotabilityNoteReader(archiveBytes: selfContainingMedia.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.note.pictures, [])
        XCTAssertEqual(reader.issues, [.mediaClassUnknown(className: "NSArray"), .unknownKey(.picture, key: "NS.objects"),
                                       .pictureSkipped(mediaIndex: 0, .archive(.keyMissing(key: "figure")))])
    }

    func testShapesNestedTooDeeplyOrSharedTooOftenCostOnlyTheShapes() throws {
        var deepWriter = BinaryPropertyListWriter()
        var deep = deepWriter.add(.integer(0))
        for _ in 0..<100 { deep = deepWriter.add(.array([deep])) }
        var builder = noteWithOneCurve()
        builder.shapesPropertyList = deepWriter.bytes(topObjectIndex: deep)
        XCTAssertEqual(try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits).issues,
                       [.shapesSkipped(.propertyList(.binary(.nestingTooDeep(limit: 64))))])
        var sharedWriter = BinaryPropertyListWriter()
        var shared = sharedWriter.add(.integer(0))
        for _ in 0..<50 { shared = sharedWriter.add(.array([shared, shared])) }
        let sharedBytes = sharedWriter.bytes(topObjectIndex: shared)
        builder.shapesPropertyList = sharedBytes
        XCTAssertEqual(try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits).issues,
                       [.shapesSkipped(.propertyList(.binary(.valueCountOverBudget(budget: sharedBytes.count))))])
    }

    /// BUG-IMPORT-02: a negative stored page width gave a page count below 1.
    func testAPageWidthThatIsNotFiniteAndPositiveGivesNoPagesAndAnIssue() throws {
        for storedWidth in [-572.0, 0, Double.infinity, Double.nan] {
            var builder = noteWithOneCurve()
            builder.storedPageWidth = storedWidth
            let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
            XCTAssertNil(reader.pageCount, "width \(storedWidth)")
            XCTAssertNil(reader.note.pageGeometry.pointsPerUnit, "width \(storedWidth)")
            XCTAssertTrue(reader.issues.contains { issue in
                if case .pageWidthNotUsable = issue { true } else { false }
            }, "width \(storedWidth)")
            XCTAssertEqual(reader.curveCount, 1)
        }
    }

    /// CC-IMPORT-08: one damaged text run or recordings library used to fail the whole note, ink included.
    func testDamagedTextRunsAndLibrariesAreSkippedAndTheInkIsStillRead() throws {
        var builder = noteWithOneCurve()
        builder.text = "abc"
        builder.textRuns = [SyntheticNotabilityTextRun(range: "{2, 5}"), SyntheticNotabilityTextRun(range: "{0, 3}")]
        var reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.issues, [.textRunSkipped(runIndex: 0, .textRunOutsideText(runIndex: 0, utf16Location: 2, utf16Length: 5,
                                                                                          textUTF16Length: 3))])
        XCTAssertEqual(reader.note.typedText.runs.map(\.utf16Length), [3])
        XCTAssertEqual(reader.curveCount, 1)
        builder.textRuns = [SyntheticNotabilityTextRun(range: "{2}")]
        reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.issues, [.textRunSkipped(runIndex: 0, .textRunRangeNotReadable(runIndex: 0))])
        builder.textRuns = []
        builder.recordingsLibraryXML = "<plist><dict>"
        reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.issues, [.recordingsSkipped(.recordingsLibrary(.xmlNotReadable))])
        XCTAssertEqual(reader.curveCount, 1)
        builder.recordingsLibraryXML = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>recordings</key><array/></dict></plist>"
        reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.issues, [.recordingsSkipped(.recordingsLibraryLayoutNotRecognised)])
    }

    /// CC-IMPORT-08: a `pageLayoutArray` entry that is not an object used to fail the whole note.
    func testAPageLayoutEntryThatIsNotAnObjectIsSkippedAndTheOtherPagesAreRead() throws {
        var builder = noteWithOneCurve()
        builder.importedPDFFileNames = ["first.pdf"]
        builder.pageLayoutStrings = ["not a layout"]
        let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.note.importedPDFPages.map(\.pdfFile?.text), ["PDFs/first.pdf"])
        XCTAssertEqual(reader.issues.count, 1)
        guard case .pageLayoutSkipped(layoutIndex: 1, _)? = reader.issues.first else { return XCTFail("expected the second layout skipped") }
        XCTAssertEqual(reader.curveCount, 1)
    }

    /// CC-IMPORT-10: a PDF name or recording path that climbs out of the note was passed on as a plain string.
    func testPathsThatClimbOutOfTheNoteAreReportedAndNotUsed() throws {
        var builder = noteWithOneCurve()
        builder.importedPDFFileNames = ["../../escape.pdf"]
        builder.recordingsLibraryXML = NotabilityNoteBuilder.recordingsLibraryXML([(key: "1", identifier: 1, filePath: "../../escape.m4a", durationSeconds: 1, name: "x")])
        let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.note.importedPDFPages.map(\.pdfFile), [nil])
        XCTAssertEqual(reader.note.recordings.map(\.file), [nil])
        XCTAssertEqual(reader.issues, [.archivePathNotValid(path: "PDFs/../../escape.pdf"), .archivePathNotValid(path: "Recordings/../../escape.m4a")])
    }

    /// CC-IMPORT-08: stroke timing arrays of the wrong length used to fail the whole note.
    func testPlaybackArraysOfTheWrongLengthAreSkippedAndTheInkIsStillRead() throws {
        var builder = noteWithOneCurve()
        builder.playbackEvents = [SyntheticNotabilityPlaybackEvent(curveUUID: [1, 2, 3], secondsFromRecordingStart: 1, recordingIdentifier: 1,
                                                                   durationSeconds: 1)]
        let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: limits)
        XCTAssertEqual(reader.issues, [.playbackEventsSkipped(.packedArrayLengthWrong(.eventCurveUUIDs, byteCount: 3, expectedValueCount: 1))])
        XCTAssertEqual(reader.note.playbackEvents, [])
        XCTAssertEqual(reader.curveCount, 1)
    }

    /// Every truncation of `Session.plist`, and thousands of copies with bytes changed at positions a seeded generator
    /// picks: each read returns or throws, and a note that is read can have all its curves and first pages read.
    func testDamagedSessionsNeverTrap() {
        let builder = NotabilityNoteReaderTests.completeNote()
        let session = builder.sessionPlistBytes()
        var outcomes = (read: 0, refused: 0)
        func attempt(_ damagedSession: [UInt8]) {
            do throws(NotabilityReadingError) {
                let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(sessionPlistBytes: damagedSession), limits: limits)
                for curveIndex in 0..<reader.curveCount { _ = try reader.curve(at: curveIndex) }
                for pageIndex in 0..<max(0, min(reader.pageCount ?? 0, 3)) { _ = try reader.page(number: pageIndex + 1) }
                outcomes.read += 1
            } catch {
                outcomes.refused += 1
            }
        }
        for cut in 0..<session.count { attempt(Array(session[..<cut])) }
        XCTAssertEqual(outcomes.refused, session.count, "a session without its trailer is never read")
        var generator = SeededGenerator(seed: 0x5EED_1234)
        for _ in 0..<3_000 {
            var damaged = session
            for _ in 0...(generator.next() % 4) {
                damaged[Int(generator.next() % UInt64(damaged.count))] = UInt8(truncatingIfNeeded: generator.next())
            }
            attempt(damaged)
        }
        XCTAssertEqual(outcomes.read + outcomes.refused, session.count + 3_000)
        XCTAssertGreaterThan(outcomes.read, 0, "some changed bytes leave the note readable")
    }
}

/// SplitMix64: a fixed sequence for a seed, so a failing damaged input can be found again.
private struct SeededGenerator {
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
