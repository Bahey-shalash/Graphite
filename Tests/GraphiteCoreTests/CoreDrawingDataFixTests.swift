import XCTest
import CryptoKit
import ImageIO
import zlib
@testable import GraphiteCore

/// PNG drawing metadata under malformed, sliced, and externally edited files, recording
/// state rules, and page coordinate mapping as the PDF overlay uses it.
final class CoreDrawingDataFixTests: XCTestCase {
    // MARK: PNG files

    func testOrdinaryPNGDecodesToTheSameBytesWithoutMetadata() throws {
        let ordinary = try PNGFixture.ordinaryImage()
        let decoded = try GraphitePNG.decode(ordinary)
        XCTAssertEqual(decoded.imageData, ordinary)
        XCTAssertNil(decoded.drawing)
        XCTAssertFalse(decoded.metadataWasDiscarded)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(ordinary as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), "The fixture must be a real PNG")
    }

    func testSlicedFileDataDecodesAndEncodesLikeTheWholeFile() throws {
        let editable = try GraphitePNG.encode(imageData: PNGFixture.ordinaryImage(), drawing: PNGFixture.payload)
        for paddingLength in [2, 20] {
            let padded = Data(repeating: 0xAB, count: paddingLength) + editable + Data([0xCD])
            let slice = padded[paddingLength..<(padded.count - 1)]
            XCTAssertEqual(slice.startIndex, paddingLength)
            let decoded = try GraphitePNG.decode(slice)
            XCTAssertEqual(decoded.drawing?.strokes, PNGFixture.payload.strokes)
            XCTAssertEqual(decoded.imageData, try GraphitePNG.decode(editable).imageData)
            XCTAssertEqual(try GraphitePNG.encode(imageData: slice, drawing: PNGFixture.payload), editable)

            let ordinary = try PNGFixture.ordinaryImage()
            let paddedOrdinary = Data(repeating: 0, count: paddingLength) + ordinary
            let ordinaryDecoded = try GraphitePNG.decode(paddedOrdinary[paddingLength...])
            XCTAssertEqual(ordinaryDecoded.imageData, ordinary)
            XCTAssertEqual(ordinaryDecoded.imageData.startIndex, 0)
        }
    }

    func testMetadataOnlyEditsThatChangeTheDisplayedImageMakeStrokesStale() throws {
        let editable = try GraphitePNG.encode(imageData: PNGFixture.ordinaryImage(), drawing: PNGFixture.payload)
        XCTAssertNotNil(try GraphitePNG.decode(editable).drawing)
        // TIFF header, one entry: Orientation (0x0112), SHORT, count 1, value 6 (rotated 90°).
        let rotation = Data([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, 0x00, 0x01,
                             0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
                             0x00, 0x00, 0x00, 0x00])
        let displayChanges: [(type: String, payload: Data)] = [
            ("eXIf", rotation),
            ("gAMA", PNGFixture.bigEndian(20_000)),
            ("sRGB", Data([0])),
            ("acTL", PNGFixture.bigEndian(2) + PNGFixture.bigEndian(0)),
        ]
        for change in displayChanges {
            let edited = try PNGFixture.inserting(PNGFixture.chunk(change.type, change.payload), afterHeaderOf: editable)
            let decoded = try GraphitePNG.decode(edited)
            XCTAssertNil(decoded.drawing, "\(change.type) changes what viewers show")
            XCTAssertTrue(decoded.metadataWasDiscarded)
        }
        let rotated = try PNGFixture.inserting(PNGFixture.chunk("eXIf", rotation), afterHeaderOf: editable)
        let rotatedSource = try XCTUnwrap(CGImageSourceCreateWithData(rotated as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(rotatedSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6, "ImageIO shows the edited file rotated")

        let described = try PNGFixture.inserting(PNGFixture.chunk("tEXt", Data("Comment\u{0}Lecture 4".utf8)), afterHeaderOf: editable)
        XCTAssertEqual(try GraphitePNG.decode(described).drawing, try GraphitePNG.decode(editable).drawing,
                       "A text description does not change the drawing")
    }

    func testDrawingsSavedWithThePixelOnlyDigestStayEditable() throws {
        let ordinary = try PNGFixture.ordinaryImage()
        var pixelHash = SHA256()
        for chunk in try PNGFixture.chunks(of: ordinary) where ["IHDR", "PLTE", "IDAT", "tRNS"].contains(chunk.type) {
            pixelHash.update(data: Data(chunk.type.utf8)); pixelHash.update(data: chunk.payload)
        }
        let legacyPayload = PNGFixture.payload.replacingVisibleContentDigest(Data(pixelHash.finalize()))
        let legacyFile = try PNGFixture.inserting(PNGFixture.chunk("grPK", legacyPayload.encoded()), beforeEndOf: ordinary)
        let decoded = try GraphitePNG.decode(legacyFile)
        XCTAssertEqual(decoded.drawing, legacyPayload)
        XCTAssertFalse(decoded.metadataWasDiscarded)
        XCTAssertEqual(decoded.imageData, ordinary)
        // Saving again upgrades the record to the digest that covers every display chunk.
        let resaved = try GraphitePNG.encode(imageData: legacyFile, drawing: PNGFixture.payload)
        XCTAssertNotEqual(try GraphitePNG.decode(resaved).drawing?.visibleContentDigest, legacyPayload.visibleContentDigest)
        XCTAssertNotNil(try GraphitePNG.decode(resaved).drawing)
    }

    func testMalformedPNGsThrowOrDiscardMetadataWithoutCrashing() throws {
        let ordinary = try PNGFixture.ordinaryImage()
        let editable = try GraphitePNG.encode(imageData: ordinary, drawing: PNGFixture.payload)

        for length in 0..<editable.count {
            XCTAssertThrowsError(try GraphitePNG.decode(editable.prefix(length)), "Truncated to \(length) bytes")
        }
        var badSignature = editable
        badSignature[badSignature.startIndex + 1] = 0
        XCTAssertThrowsError(try GraphitePNG.decode(badSignature))

        var oversizedLength = editable
        oversizedLength.replaceSubrange(8..<12, with: PNGFixture.bigEndian(UInt32.max))
        XCTAssertThrowsError(try GraphitePNG.decode(oversizedLength))

        let endChunk = PNGFixture.chunk("IEND", Data())
        XCTAssertThrowsError(try GraphitePNG.decode(editable.prefix(editable.count - endChunk.count)), "Missing IEND")
        XCTAssertThrowsError(try GraphitePNG.decode(editable + Data([0])), "Bytes after IEND")

        let metadataChunk = try PNGFixture.chunk("grPK", PNGFixture.payload.encoded())
        let duplicated = try PNGFixture.inserting(metadataChunk, beforeEndOf: editable)
        let duplicatedDecoded = try GraphitePNG.decode(duplicated)
        XCTAssertNil(duplicatedDecoded.drawing)
        XCTAssertTrue(duplicatedDecoded.metadataWasDiscarded)
        XCTAssertEqual(duplicatedDecoded.imageData, ordinary)

        var damagedPixels = editable
        let imageDataMarker = try XCTUnwrap(damagedPixels.range(of: Data("IDAT".utf8)))
        damagedPixels[imageDataMarker.upperBound] ^= 0xFF
        XCTAssertThrowsError(try GraphitePNG.decode(damagedPixels), "A bad CRC on image data is damage, not stale metadata")

        var generator = SeededGenerator(seed: 0x9E37_79B9)
        for _ in 0..<2_000 {
            var flipped = editable
            let index = Int.random(in: 0..<flipped.count, using: &generator)
            flipped[index] ^= UInt8.random(in: 1...255, using: &generator)
            if let decoded = try? GraphitePNG.decode(flipped), decoded.drawing != nil {
                XCTAssertEqual(decoded.drawing, try GraphitePNG.decode(editable).drawing)
            }
        }
    }

    func testDeeplyNestedMetadataInsidePNGIsDiscardedOnASmallStack() throws {
        let ordinary = try PNGFixture.ordinaryImage()
        let depth = 5_000
        let nestedXML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>version</key>"
            + String(repeating: "<array>", count: depth) + String(repeating: "</array>", count: depth) + "</dict></plist>"
        let hostile = try PNGFixture.inserting(PNGFixture.chunk("grPK", Data(nestedXML.utf8)), beforeEndOf: ordinary)
        let outcome = onConcurrencySizedStack { () -> (hasDrawing: Bool, discarded: Bool)? in
            guard let decoded = try? GraphitePNG.decode(hostile) else { return nil }
            return (decoded.drawing != nil, decoded.metadataWasDiscarded)
        }
        let decodedOutcome = try XCTUnwrap(outcome.flatMap { decoded in decoded }, "The image itself is valid")
        XCTAssertFalse(decodedOutcome.hasDrawing)
        XCTAssertTrue(decodedOutcome.discarded)
    }

    // MARK: Recording state

    /// `.failed` may still hold a recording that was not saved; RecordingController adds
    /// that check (`canStartRecording`), because only it knows whether audio was retained.
    func testRecordingStatePermitsOnlyTheIntendedActions() {
        struct Expected { let canStart, canResume, canStop, isActive: Bool }
        let expectations: [RecordingState: Expected] = [
            .idle: Expected(canStart: true, canResume: false, canStop: false, isActive: false),
            .requestingPermission: Expected(canStart: false, canResume: false, canStop: false, isActive: true),
            .recording: Expected(canStart: false, canResume: false, canStop: true, isActive: true),
            .paused: Expected(canStart: false, canResume: true, canStop: true, isActive: true),
            .interrupted: Expected(canStart: false, canResume: true, canStop: true, isActive: true),
            .finalizing: Expected(canStart: false, canResume: false, canStop: false, isActive: true),
            .failed: Expected(canStart: true, canResume: false, canStop: false, isActive: false),
        ]
        for (state, expected) in expectations {
            XCTAssertEqual(state.canStart, expected.canStart, "\(state).canStart")
            XCTAssertEqual(state.canResume, expected.canResume, "\(state).canResume")
            XCTAssertEqual(state.canStop, expected.canStop, "\(state).canStop")
            XCTAssertEqual(state.isActive, expected.isActive, "\(state).isActive")
        }
    }

    // MARK: Page coordinates

    /// PDFKit rotates the page overlay itself, so on a page with any /Rotate value the
    /// overlay is the unrotated crop box, scaled. Each crop box corner must land on the
    /// matching overlay corner whatever the scale in each direction.
    func testOverlayMappingPlacesEveryCropBoxCornerForUnevenScales() throws {
        let cropBoxes = [CGRect(x: 31, y: 72, width: 595, height: 842), CGRect(x: -18, y: 40, width: 1_200, height: 600)]
        for cropBox in cropBoxes {
            for scale in [CGSize(width: 2, height: 2), CGSize(width: 0.5, height: 1.5)] {
                let overlaySize = CGSize(width: cropBox.width * scale.width, height: cropBox.height * scale.height)
                let coordinates = try PageCoordinates(cropBox: cropBox, overlaySize: overlaySize)
                let corners: [(overlay: CGPoint, pdf: CGPoint)] = [
                    (CGPoint(x: 0, y: 0), CGPoint(x: cropBox.minX, y: cropBox.maxY)),
                    (CGPoint(x: overlaySize.width, y: 0), CGPoint(x: cropBox.maxX, y: cropBox.maxY)),
                    (CGPoint(x: 0, y: overlaySize.height), CGPoint(x: cropBox.minX, y: cropBox.minY)),
                    (CGPoint(x: overlaySize.width, y: overlaySize.height), CGPoint(x: cropBox.maxX, y: cropBox.minY)),
                ]
                for corner in corners {
                    let pdfPoint = coordinates.pdfPoint(fromOverlay: corner.overlay)
                    XCTAssertEqual(pdfPoint.x, corner.pdf.x, accuracy: 0.0001)
                    XCTAssertEqual(pdfPoint.y, corner.pdf.y, accuracy: 0.0001)
                    let overlayPoint = coordinates.overlayPoint(fromPDF: corner.pdf)
                    XCTAssertEqual(overlayPoint.x, corner.overlay.x, accuracy: 0.0001)
                    XCTAssertEqual(overlayPoint.y, corner.overlay.y, accuracy: 0.0001)
                }
            }
        }
        XCTAssertThrowsError(try PageCoordinates(cropBox: CGRect(x: 0, y: 0, width: 0, height: 10), overlaySize: CGSize(width: 10, height: 10)))
        XCTAssertThrowsError(try PageCoordinates(cropBox: CGRect(x: 0, y: 0, width: 10, height: 10), overlaySize: CGSize(width: CGFloat.nan, height: 10)))
    }

    // MARK: Helpers

    /// Runs `work` on a thread with the 512 KB stack that Swift concurrency threads have,
    /// which is where embedded drawings are checked for editable strokes.
    private func onConcurrencySizedStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value? {
        let resultBox = DrawingResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        return resultBox.value
    }
}

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class DrawingResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

/// A deterministic generator so a failing byte flip reproduces.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

/// Builds PNG files byte by byte so tests control every chunk.
private enum PNGFixture {
    static let payload = DrawingPayload(width: 320, height: 240, background: .white, strokes: Data([1, 2, 3, 4]))
    static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])

    /// A 2x2 opaque RGB image with a real zlib stream, readable by ImageIO.
    static func ordinaryImage() throws -> Data {
        var header = bigEndian(2) + bigEndian(2)
        header.append(contentsOf: [8, 2, 0, 0, 0])
        // Each scanline starts with filter type 0, then three bytes per pixel.
        let scanlines = Data([0, 200, 30, 30, 30, 200, 30, 0, 30, 30, 200, 250, 250, 250])
        var compressedLength = compressBound(uLong(scanlines.count))
        var compressed = Data(count: Int(compressedLength))
        let status = compressed.withUnsafeMutableBytes { destination in
            scanlines.withUnsafeBytes { source in
                compress(destination.bindMemory(to: Bytef.self).baseAddress, &compressedLength,
                         source.bindMemory(to: Bytef.self).baseAddress, uLong(scanlines.count))
            }
        }
        guard status == Z_OK else { throw GraphiteError.invalidFile("zlib could not compress the fixture.") }
        compressed.count = Int(compressedLength)
        return signature + chunk("IHDR", header) + chunk("IDAT", compressed) + chunk("IEND", Data())
    }

    static func bigEndian(_ number: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: number >> 24), UInt8(truncatingIfNeeded: number >> 16), UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)])
    }

    static func chunk(_ type: String, _ chunkPayload: Data) -> Data {
        let typeAndPayload = Data(type.utf8) + chunkPayload
        let checksum = typeAndPayload.withUnsafeBytes { buffer in
            crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
        }
        return bigEndian(UInt32(chunkPayload.count)) + typeAndPayload + bigEndian(UInt32(truncatingIfNeeded: checksum))
    }

    static func chunks(of fileData: Data) throws -> [(type: String, payload: Data)] {
        var parsed: [(type: String, payload: Data)] = []
        var offset = signature.count
        while offset + 12 <= fileData.count {
            let length = Int(fileData[offset..<offset + 4].reduce(UInt32(0)) { accumulated, byte in (accumulated << 8) | UInt32(byte) })
            parsed.append((String(decoding: fileData[offset + 4..<offset + 8], as: UTF8.self), Data(fileData[offset + 8..<offset + 8 + length])))
            offset += length + 12
        }
        return parsed
    }

    /// Inserts a chunk directly after IHDR, where colour and orientation chunks belong.
    static func inserting(_ newChunk: Data, afterHeaderOf fileData: Data) throws -> Data {
        let headerLength = 12 + 13
        var edited = fileData
        edited.insert(contentsOf: newChunk, at: signature.count + headerLength)
        return edited
    }

    static func inserting(_ newChunk: Data, beforeEndOf fileData: Data) throws -> Data {
        var edited = fileData
        edited.insert(contentsOf: newChunk, at: fileData.count - chunk("IEND", Data()).count)
        return edited
    }
}

