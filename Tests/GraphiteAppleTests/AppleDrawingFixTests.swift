import XCTest
import PDFKit
import ImageIO
import CoreGraphics
import CryptoKit
import Compression
import Darwin
import GraphiteCore
@testable import GraphiteApple
#if canImport(PencilKit) && canImport(AppKit)
import PencilKit
import AppKit
#endif

final class AppleDrawingFixTests: XCTestCase {
    private let standardColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Helpers

    /// Premultiplied sRGB RGBA bytes of an image, top row first.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        var pixelBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixelBytes
    }

    private func pixel(_ pixelBytes: [UInt8], width: Int, column: Int, row: Int) -> [Int] {
        let offset = (row * width + column) * 4
        return (0..<4).map { component in Int(pixelBytes[offset + component]) }
    }

    private func decodedImage(_ fileData: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(fileData as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Renders the first page of a PDF through Core Graphics, independent of Graphite.
    private func renderedFirstPage(_ fileData: Data, scale: Double) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let document = try XCTUnwrap(CGDataProvider(data: fileData as CFData).flatMap(CGPDFDocument.init))
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return (try pixels(of: XCTUnwrap(context.makeImage())), width, height)
    }

    private func peakFootprintMegabytes() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integers in task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), integers, &count) }
        }
        return result == KERN_SUCCESS ? Int(information.ledger_phys_footprint_peak) / 1_048_576 : 0
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppleDrawingFixTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func horizontalStroke(width strokeWidth: Double = 6, color: VectorInkColor = VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1)) -> VectorShape? {
        StrokeOutliner.shape(forSegments: [(0...100).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step) * 2, y: 50), width: strokeWidth) }], color: color)
    }

    private func sampleDrawing(size: CGSize = CGSize(width: 400, height: 200)) -> VectorDrawing {
        let highlighter = VectorInkColor(red: 1, green: 0.8, blue: 0, alpha: 0.4)
        let dot = StrokeOutliner.shape(forSegments: [[VectorStrokeSample(point: CGPoint(x: 300, y: 120), width: 10)]], color: highlighter)
        return VectorDrawing(size: size, background: .white, shapes: [horizontalStroke(), dot].compactMap { shape in shape })
    }

    private let samplePayload = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("pencil strokes".utf8))

    // MARK: PNG export (banded streaming encoder)

    func testBandEdgesFallOnWholePixelRowsAtFractionalScales() throws {
        for preferredScale in [1.0, 1.2345, 1.732, 1.999, 2.0] {
            let raster = try XCTUnwrap(BandedPNGEncoder.Raster(size: CGSize(width: 1000, height: 16000), preferredScale: preferredScale, isOpaque: true))
            XCTAssertLessThanOrEqual(raster.scale, preferredScale)
            XCTAssertGreaterThan(raster.scale, preferredScale - 1.0 / 1024)
            for bandIndex in 0..<raster.bandCount {
                let bandTopInPixels = raster.bandRectangle(at: bandIndex).minY * raster.scale
                XCTAssertEqual(bandTopInPixels, bandTopInPixels.rounded(), "Band \(bandIndex) at scale \(preferredScale) starts inside a pixel row.")
                XCTAssertEqual(Int(bandTopInPixels), bandIndex * raster.bandPixelHeight)
            }
        }
        XCTAssertNil(BandedPNGEncoder.Raster(size: CGSize(width: 100, height: Double.nan), preferredScale: 2, isOpaque: true))
    }

    /// Band images cut from one reference bitmap must reassemble into exactly that bitmap.
    private func assertBandedEncodingReproduces(_ truth: CGImage, isOpaque: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let raster = try XCTUnwrap(BandedPNGEncoder.Raster(size: CGSize(width: Double(truth.width) / 2, height: Double(truth.height) / 2), preferredScale: 2, isOpaque: isOpaque))
        XCTAssertEqual(raster.pixelWidth, truth.width, file: file, line: line)
        XCTAssertEqual(raster.pixelHeight, truth.height, file: file, line: line)
        let encoded = try BandedPNGEncoder.encode(raster) { bandIndex in
            let firstRow = bandIndex * raster.bandPixelHeight
            return try XCTUnwrap(truth.cropping(to: CGRect(x: 0, y: firstRow, width: truth.width, height: min(raster.bandPixelHeight, truth.height - firstRow))))
        }
        let decoded = try decodedImage(encoded.pngData)
        XCTAssertEqual(decoded.bitsPerComponent, 8, file: file, line: line)
        XCTAssertEqual(decoded.width, truth.width, file: file, line: line)
        XCTAssertEqual(decoded.height, truth.height, file: file, line: line)
        XCTAssertEqual(try pixels(of: decoded), try pixels(of: truth), "The streamed PNG differs from the bitmap it was cut from.", file: file, line: line)
        XCTAssertTrue(BandedPNGEncoder.decodedContentMatches(encoded.pngData, reference: encoded.reference), file: file, line: line)
    }

    private func stripedImage(width: Int, height: Int, isOpaque: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: standardColorSpace,
                                              bitmapInfo: (isOpaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue))
        if isOpaque {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        for row in stride(from: 3, to: height, by: 97) { context.fill(CGRect(x: row % max(1, width - 8), y: row, width: 8, height: 5)) }
        return try XCTUnwrap(context.makeImage())
    }

    func testStreamedPNGMatchesTheBitmapAcrossBands() throws {
        try assertBandedEncodingReproduces(stripedImage(width: 120, height: 5_000, isOpaque: true), isOpaque: true)
        try assertBandedEncodingReproduces(stripedImage(width: 120, height: 5_000, isOpaque: false), isOpaque: false)
    }

    /// A white drawing taller than 32,768 pixels once saved as a solid black PNG.
    func testPNGTallerThan32768RowsKeepsItsBackgroundAndInk() throws {
        try assertBandedEncodingReproduces(stripedImage(width: 24, height: 40_000, isOpaque: true), isOpaque: true)
    }

    func testDecoderVerificationRejectsAFileThatShowsSomethingElse() throws {
        let raster = try XCTUnwrap(BandedPNGEncoder.Raster(size: CGSize(width: 60, height: 900), preferredScale: 2, isOpaque: true))
        let white = try stripedImage(width: raster.pixelWidth, height: raster.pixelHeight, isOpaque: true)
        let encoded = try BandedPNGEncoder.encode(raster) { bandIndex in
            try XCTUnwrap(white.cropping(to: CGRect(x: 0, y: bandIndex * raster.bandPixelHeight, width: raster.pixelWidth, height: min(raster.bandPixelHeight, raster.pixelHeight - bandIndex * raster.bandPixelHeight))))
        }
        let blackContext = try XCTUnwrap(CGContext(data: nil, width: raster.pixelWidth, height: raster.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        blackContext.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        blackContext.fill(CGRect(x: 0, y: 0, width: raster.pixelWidth, height: raster.pixelHeight))
        let blackPNG = try ImageEncoding.pngData(from: XCTUnwrap(blackContext.makeImage()))
        XCTAssertTrue(BandedPNGEncoder.decodedContentMatches(encoded.pngData, reference: encoded.reference))
        XCTAssertFalse(BandedPNGEncoder.decodedContentMatches(blackPNG, reference: encoded.reference))
        XCTAssertFalse(BandedPNGEncoder.decodedContentMatches(Data("not an image".utf8), reference: encoded.reference))
    }

    func testBandRenderingFailureFailsTheEncode() throws {
        struct BandFailure: Error {}
        let raster = try XCTUnwrap(BandedPNGEncoder.Raster(size: CGSize(width: 10, height: 3_000), preferredScale: 1, isOpaque: true))
        let band = try stripedImage(width: raster.pixelWidth, height: raster.bandPixelHeight, isOpaque: true)
        XCTAssertThrowsError(try BandedPNGEncoder.encode(raster) { bandIndex in
            if bandIndex == 1 { throw BandFailure() }
            return band
        }) { error in XCTAssertTrue(error is BandFailure) }
    }

    // MARK: PDF stream bounds

    /// A zlib stream (header, raw DEFLATE, Adler-32 placeholder) of `byteCount` spaces,
    /// produced without holding the decoded bytes.
    private func compressedSpaces(byteCount: Int) throws -> Data {
        var compressed = Data([0x78, 0x9C])
        let filter = try OutputFilter(.compress, using: .zlib) { chunk in if let chunk { compressed.append(chunk) } }
        let block = Data(repeating: UInt8(ascii: " "), count: 1_048_576)
        var written = 0
        while written < byteCount {
            let chunkSize = min(block.count, byteCount - written)
            try filter.write(block.prefix(chunkSize))
            written += chunkSize
        }
        try filter.finalize()
        compressed.append(contentsOf: [0, 0, 0, 0])
        return compressed
    }

    /// A zlib stream of one space followed by `matchCount` copies of the longest DEFLATE
    /// match (258 bytes at distance 1), in one fixed-Huffman block: about 13 bits per 258
    /// decoded bytes, the ratio a decompression bomb uses. Built directly because
    /// compressing a gigabyte of spaces took most of a minute.
    private func deflateBomb(matchCount: Int) -> Data {
        var bytes: [UInt8] = [0x78, 0x01]
        var bitBuffer: UInt64 = 0, bitCount = 0
        func writeBits(_ bits: UInt64, count: Int) {
            bitBuffer |= bits << UInt64(bitCount)
            bitCount += count
            while bitCount >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: bitBuffer))
                bitBuffer >>= 8
                bitCount -= 8
            }
        }
        /// Huffman codes are packed starting from their most significant bit.
        func writeCode(_ code: UInt64, length: Int) {
            var reversed: UInt64 = 0
            for bitIndex in 0..<length where code & (1 << UInt64(bitIndex)) != 0 { reversed |= 1 << UInt64(length - 1 - bitIndex) }
            writeBits(reversed, count: length)
        }
        writeBits(0b011, count: 3) // Final block, fixed Huffman codes.
        writeCode(0x30 + UInt64(UInt8(ascii: " ")), length: 8)
        var match: UInt64 = 0
        for bitIndex in 0..<8 where UInt64(0b1100_0101) & (1 << UInt64(bitIndex)) != 0 { match |= 1 << UInt64(7 - bitIndex) } // Length code 285, then distance code 0.
        for _ in 0..<matchCount { writeBits(match, count: 13) }
        writeCode(0, length: 7) // End of block.
        if bitCount > 0 { writeBits(0, count: 8 - bitCount) }
        return Data(bytes + [0, 0, 0, 0])
    }

    private func deflateBomb(decodedByteCount: Int) -> Data { deflateBomb(matchCount: (decodedByteCount - 1 + 257) / 258) }

    /// A PDF whose catalog carries the given metadata stream and whose pages have the given
    /// content stream, with a correct cross-reference table.
    private func pdf(metadataDictionary: String, metadataStream: Data, contentDictionary: String? = nil, contentStream: Data? = nil, pageCount: Int = 1) -> Data {
        var file = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        func appendObject(_ body: Data) {
            offsets.append(file.count)
            file.append(Data("\(offsets.count) 0 obj\n".utf8))
            file.append(body)
            file.append(Data("\nendobj\n".utf8))
        }
        func streamObject(dictionary: String, stream: Data) -> Data {
            var object = Data("<< \(dictionary) >>\nstream\n".utf8)
            object.append(stream)
            object.append(Data("\nendstream".utf8))
            return object
        }
        let pageObjectNumbers = (0..<pageCount).map { pageIndex in 5 + pageIndex }
        appendObject(Data("<< /Type /Catalog /Pages 2 0 R /Metadata 3 0 R >>".utf8))
        appendObject(Data("<< /Type /Pages /Kids [\(pageObjectNumbers.map { objectNumber in "\(objectNumber) 0 R" }.joined(separator: " "))] /Count \(pageCount) >>".utf8))
        appendObject(streamObject(dictionary: "/Type /Metadata /Subtype /XML /Length \(metadataStream.count) \(metadataDictionary)", stream: metadataStream))
        appendObject(streamObject(dictionary: "/Length \(contentStream?.count ?? 0) \(contentDictionary ?? "")", stream: contentStream ?? Data()))
        for _ in pageObjectNumbers {
            appendObject(Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>".utf8))
        }
        let crossReferenceOffset = file.count
        var crossReference = "xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { crossReference += String(format: "%010d 00000 n \n", offset) }
        crossReference += "trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        file.append(Data(crossReference.utf8))
        return file
    }

    /// Replaces the first `/Length <count>` so the dictionary claims a much shorter stream.
    private func understatingLength(_ file: Data, of stream: Data) throws -> Data {
        var patched = file
        let declaration = try XCTUnwrap(patched.range(of: Data("/Length \(stream.count) ".utf8)))
        let understated = Data("/Length 40".utf8) + Data(repeating: UInt8(ascii: " "), count: declaration.count - 10)
        patched.replaceSubrange(declaration, with: understated)
        return patched
    }

    private func assertStaysWithinMemoryBudget(_ file: Data, name: String, file testFile: StaticString = #filePath, line: UInt = #line) async throws {
        XCTAssertNotNil(CGDataProvider(data: file as CFData).flatMap(CGPDFDocument.init), "\(name) must be a valid PDF.", file: testFile, line: line)
        let location = try temporaryDirectory().appendingPathComponent("\(name).pdf")
        try file.write(to: location)
        let peakBefore = peakFootprintMegabytes()
        let startTime = Date()
        let reading = PDFDrawingFile.readMetadata(file)
        let isDrawing = await ImageFileService().isEditableDrawingPDF(at: location)
        let hasStrokes = DrawingMetadataReader.hasEditableStrokes(at: location)
        XCTAssertNil(reading.payload, name, file: testFile, line: line)
        XCTAssertFalse(isDrawing, name, file: testFile, line: line)
        XCTAssertFalse(hasStrokes, name, file: testFile, line: line)
        XCTAssertLessThan(peakFootprintMegabytes() - peakBefore, 150, "\(name): decoding must stay within its budget.", file: testFile, line: line)
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 20, name, file: testFile, line: line)
    }

    /// Every note that embeds this small PDF used to inflate a gigabyte three times over.
    /// Core Graphics also reads past a `/Length` that understates the stream.
    func testCompressedMetadataBombIsNotInflatedPastTheBudget() async throws {
        let bombStream = deflateBomb(decodedByteCount: 1_073_741_824)
        let bomb = pdf(metadataDictionary: "/Filter /FlateDecode", metadataStream: bombStream)
        XCTAssertLessThan(bomb.count, 60_000_000)
        try await assertStaysWithinMemoryBudget(bomb, name: "Metadata bomb")
        try await assertStaysWithinMemoryBudget(understatingLength(bomb, of: bombStream), name: "Metadata bomb with a short length")
    }

    /// A metadata packet that passes every check up to the page content, whose content
    /// stream then expands past anything a drawing could hold.
    func testCompressedContentBombIsHashedWithinTheBudget() async throws {
        let payload = DrawingPayload(width: 200, height: 200, background: .white, strokes: Data("pencil strokes".utf8))
        let packet = Data("<x:xmpmeta><graphite:drawing>\(try payload.encoded().base64EncodedString())</graphite:drawing></x:xmpmeta>".utf8)
        for decodedByteCount in [200_000_000, 600_000_000] {
            let contentStream = deflateBomb(decodedByteCount: decodedByteCount)
            let bomb = pdf(metadataDictionary: "", metadataStream: packet, contentDictionary: "/Filter /FlateDecode", contentStream: contentStream)
            let reading = PDFDrawingFile.readMetadata(bomb)
            XCTAssertTrue(reading.metadataWasDiscarded, "The payload was read, so only the content check can have refused it.")
            // The content is really inflated, and hashed as it goes, up to the budget.
            let page = try XCTUnwrap(CGDataProvider(data: bomb as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
            var contentReference: CGPDFStreamRef?
            XCTAssertTrue(CGPDFDictionaryGetStream(try XCTUnwrap(page.dictionary), "Contents", &contentReference))
            var hash = SHA256()
            let hashedByteCount = PDFDrawingStreamDecoder.decode(try XCTUnwrap(contentReference), in: PDFFileBytes(byteCount: bomb.count, readBytes: { bomb }),
                                                                 maximumDecodedBytes: PDFDrawingFile.maximumDecodedPageContentBytes, into: &hash) { hash, chunk in hash.update(data: chunk) }
            if decodedByteCount <= PDFDrawingFile.maximumDecodedPageContentBytes {
                XCTAssertEqual(hashedByteCount, (decodedByteCount - 1 + 257) / 258 * 258 + 1)
            } else {
                XCTAssertNil(hashedByteCount)
            }
            try await assertStaysWithinMemoryBudget(bomb, name: "Content bomb of \(decodedByteCount) bytes")
            try await assertStaysWithinMemoryBudget(understatingLength(bomb, of: contentStream), name: "Content bomb of \(decodedByteCount) bytes with a short length")
        }
    }

    /// Base64 text longer than any payload Graphite writes is refused before decoding.
    func testOversizedPDFMetadataPayloadIsRefused() {
        let oversizedText = String(repeating: "A", count: DrawingMetadataReader.maximumBase64PayloadBytes + 4)
        let packet = Data("<x:xmpmeta><graphite:drawing>\(oversizedText)</graphite:drawing></x:xmpmeta>".utf8)
        let reading = PDFDrawingFile.readMetadata(pdf(metadataDictionary: "", metadataStream: packet, contentStream: Data("0 0 m".utf8)))
        XCTAssertNil(reading.payload)
        XCTAssertTrue(reading.metadataWasDiscarded)
    }

    /// Lecture PDFs are checked by every note that embeds them; their metadata is never
    /// decoded, however it is compressed.
    func testMultiplePagePDFMetadataIsNotDecoded() async throws {
        let lecture = pdf(metadataDictionary: "/Filter /FlateDecode", metadataStream: deflateBomb(decodedByteCount: 1_073_741_824), pageCount: 3)
        XCTAssertEqual(CGDataProvider(data: lecture as CFData).flatMap(CGPDFDocument.init)?.numberOfPages, 3)
        try await assertStaysWithinMemoryBudget(lecture, name: "Lecture")
        XCTAssertFalse(PDFDrawingFile.readMetadata(lecture).metadataWasDiscarded)
    }

    /// Streams of all but the smallest files are found in the file's bytes and inflated
    /// by Graphite; they must decode exactly as Core Graphics decodes them, in Graphite's
    /// files and in PDFKit's rewrites of them.
    func testStreamsFoundInTheFileDecodeAsCoreGraphicsDecodesThem() throws {
        var generator = SystemRandomNumberGenerator()
        let strokes = Data((0..<100_000).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let fileData = try PDFDrawingFile.encode(sampleDrawing(), payload: DrawingPayload(width: 400, height: 200, background: .white, strokes: strokes))
        let rewritten = try XCTUnwrap(PDFDocument(data: fileData)?.dataRepresentation())
        for candidateFile in [fileData, rewritten] {
            XCTAssertGreaterThan(candidateFile.count, 16_384, "The file must be too large for Core Graphics to decode it directly.")
            let document = try XCTUnwrap(CGDataProvider(data: candidateFile as CFData).flatMap(CGPDFDocument.init))
            var metadataStream: CGPDFStreamRef?, contentStream: CGPDFStreamRef?
            XCTAssertTrue(CGPDFDictionaryGetStream(try XCTUnwrap(document.catalog), "Metadata", &metadataStream))
            XCTAssertTrue(CGPDFDictionaryGetStream(try XCTUnwrap(document.page(at: 1)?.dictionary), "Contents", &contentStream))
            for stream in [try XCTUnwrap(metadataStream), try XCTUnwrap(contentStream)] {
                var format = CGPDFDataFormat.raw
                let expected = try XCTUnwrap(CGPDFStreamCopyData(stream, &format)) as Data
                let file = PDFFileBytes(byteCount: candidateFile.count, readBytes: { candidateFile })
                XCTAssertEqual(PDFDrawingStreamDecoder.decodedContents(of: stream, in: file, maximumDecodedBytes: 100_000_000), expected)
                XCTAssertNil(PDFDrawingStreamDecoder.decodedContents(of: stream, in: file, maximumDecodedBytes: expected.count - 1))
            }
        }
    }

    func testMetadataWithChainedOrUnknownFiltersIsIgnored() throws {
        let packet = Data("<graphite:drawing>AAAA</graphite:drawing>".utf8)
        let chained = pdf(metadataDictionary: "/Filter [/FlateDecode /FlateDecode]", metadataStream: packet)
        XCTAssertNil(PDFDrawingFile.readMetadata(chained).payload)
        XCTAssertFalse(PDFDrawingFile.readMetadata(chained).metadataWasDiscarded)
        let predicted = pdf(metadataDictionary: "/Filter /FlateDecode /DecodeParms << /Predictor 12 >>", metadataStream: packet)
        XCTAssertNil(PDFDrawingFile.readMetadata(predicted).payload)
    }

    func testBoundedInflateStopsAtItsLimitAndReadsRealStreams() throws {
        func inflatedByteCount(_ zlibStream: Data, maximumDecodedBytes: Int) -> Int? {
            var inflated = Data()
            let decodedByteCount = PDFDrawingStreamDecoder.inflate(zlibStream, maximumDecodedBytes: maximumDecodedBytes, into: &inflated) { inflated, chunk in inflated.append(chunk) }
            if let decodedByteCount { XCTAssertEqual(decodedByteCount, inflated.count) }
            return decodedByteCount
        }
        let stream = try compressedSpaces(byteCount: 3_000_000)
        XCTAssertEqual(inflatedByteCount(stream, maximumDecodedBytes: 3_000_000), 3_000_000)
        XCTAssertNil(inflatedByteCount(stream, maximumDecodedBytes: 2_999_999))
        XCTAssertNil(inflatedByteCount(Data([0x12, 0x34, 0x56]), maximumDecodedBytes: 100), "Not a zlib header.")
        // The hand-built bomb is ordinary DEFLATE that Core Graphics decodes too.
        let bomb = deflateBomb(matchCount: 1_000)
        XCTAssertEqual(inflatedByteCount(bomb, maximumDecodedBytes: 1_000_000), 258_001)
        let document = try XCTUnwrap(CGDataProvider(data: pdf(metadataDictionary: "/Filter /FlateDecode", metadataStream: bomb) as CFData).flatMap(CGPDFDocument.init))
        var metadataStream: CGPDFStreamRef?
        XCTAssertTrue(CGPDFDictionaryGetStream(try XCTUnwrap(document.catalog), "Metadata", &metadataStream))
        var format = CGPDFDataFormat.raw
        XCTAssertEqual(CGPDFStreamCopyData(try XCTUnwrap(metadataStream), &format).map(CFDataGetLength), 258_001)
    }

    /// Payloads too large for Core Graphics' own decoder within the budget are inflated
    /// from the file's bytes; they must still read, including after PDFKit rewrites the file.
    func testLargeCompressedMetadataStillReadsFromDataFilesAndPDFKitCopies() async throws {
        var generator = SystemRandomNumberGenerator()
        let strokes = Data((0..<600_000).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let payload = DrawingPayload(width: 400, height: 200, background: .white, strokes: strokes)
        let fileData = try PDFDrawingFile.encode(sampleDrawing(), payload: payload)
        XCTAssertEqual(PDFDrawingFile.readMetadata(fileData).payload?.strokes, strokes)
        let location = try temporaryDirectory().appendingPathComponent("Large drawing.pdf")
        try fileData.write(to: location)
        XCTAssertEqual(PDFDrawingFile.readMetadata(at: location).payload?.strokes, strokes)
        let isDrawing = await ImageFileService().isEditableDrawingPDF(at: location)
        XCTAssertTrue(isDrawing)
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: location))
        let rewritten = try XCTUnwrap(PDFDocument(data: fileData)?.dataRepresentation())
        XCTAssertEqual(PDFDrawingFile.readMetadata(rewritten).payload?.strokes, strokes)
    }

    // MARK: PDF change detection

    func testRotatedCroppedOrRestyledDrawingIsNoLongerEditable() throws {
        let fileData = try PDFDrawingFile.encode(sampleDrawing(), payload: samplePayload)
        XCTAssertNotNil(PDFDrawingFile.readMetadata(fileData).payload)
        let resaved = try XCTUnwrap(PDFDocument(data: fileData)?.dataRepresentation())
        XCTAssertNotNil(PDFDrawingFile.readMetadata(resaved).payload, "A plain rewrite without visible changes keeps the strokes editable.")

        let rotatedDocument = try XCTUnwrap(PDFDocument(data: fileData))
        rotatedDocument.page(at: 0)?.rotation = 90
        let rotated = PDFDrawingFile.readMetadata(try XCTUnwrap(rotatedDocument.dataRepresentation()))
        XCTAssertNil(rotated.payload)
        XCTAssertTrue(rotated.metadataWasDiscarded)

        let croppedDocument = try XCTUnwrap(PDFDocument(data: fileData))
        croppedDocument.page(at: 0)?.setBounds(CGRect(x: 0, y: 0, width: 200, height: 100), for: .cropBox)
        XCTAssertNil(PDFDrawingFile.readMetadata(try XCTUnwrap(croppedDocument.dataRepresentation())).payload)

        // The highlighter's transparency lives in a resource, not in the content stream.
        let opacityMarker = Data("/ca 0.4".utf8)
        let markerRange = try XCTUnwrap(fileData.range(of: opacityMarker))
        var opaque = fileData
        opaque.replaceSubrange(markerRange, with: Data("/ca 1.0".utf8))
        XCTAssertNotNil(CGDataProvider(data: opaque as CFData).flatMap(CGPDFDocument.init))
        let restyled = PDFDrawingFile.readMetadata(opaque)
        XCTAssertNil(restyled.payload)
        XCTAssertTrue(restyled.metadataWasDiscarded)
    }

    /// Rewriters reformat numbers and add or drop the obsolete `/ProcSet`; neither changes
    /// what the page shows, so neither may cost the user their editable strokes.
    func testResourceRewritesThatShowTheSameStayEditable() throws {
        let fileData = try PDFDrawingFile.encode(sampleDrawing(), payload: samplePayload)
        var rewritten = fileData
        // Same-length replacements keep the cross-reference offsets valid.
        for (original, replacement) in [("/ProcSet [ /PDF ]", String(repeating: " ", count: 17)), ("/ca 0.4", "/ca .40")] {
            let range = try XCTUnwrap(rewritten.range(of: Data(original.utf8)), "Core Graphics no longer writes \(original).")
            rewritten.replaceSubrange(range, with: Data(replacement.utf8))
        }
        XCTAssertNotEqual(rewritten, fileData)
        XCTAssertEqual(PDFDrawingFile.readMetadata(rewritten).payload?.strokes, samplePayload.strokes)
    }

    /// Drawings saved before resources were part of the digest stay editable, and still
    /// lose editability when rotated.
    func testDrawingsWrittenByTheEarlierDigestStayEditable() throws {
        let drawing = sampleDrawing()
        func render(metadata: Data?) throws -> Data {
            let output = NSMutableData()
            var mediaBox = CGRect(origin: .zero, size: drawing.size)
            let consumer = try XCTUnwrap(CGDataConsumer(data: output))
            let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextCreator as String: "Graphite"] as CFDictionary))
            if let metadata { context.addDocumentMetadata(metadata as CFData) }
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: drawing.size.height)
            context.scaleBy(x: 1, y: -1)
            VectorDrawingRenderer.draw(drawing, in: context)
            context.endPDFPage()
            context.closePDF()
            return output as Data
        }
        let withoutMetadata = try render(metadata: nil)
        let page = try XCTUnwrap(CGDataProvider(data: withoutMetadata as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
        let legacyDigest = try PDFDrawingFile.pageContentDigests(of: page, in: PDFFileBytes(byteCount: withoutMetadata.count, readBytes: { withoutMetadata })).withoutResources
        let encodedPayload = try samplePayload.replacingVisibleContentDigest(legacyDigest).encoded().base64EncodedString()
        let packet = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:graphite="urn:graphite:drawing:1"><graphite:drawing>\(encodedPayload)</graphite:drawing></rdf:Description>
        </rdf:RDF></x:xmpmeta><?xpacket end="w"?>
        """
        let legacyFile = try render(metadata: Data(packet.utf8))
        XCTAssertEqual(PDFDrawingFile.readMetadata(legacyFile).payload?.strokes, samplePayload.strokes)
        let rotatedDocument = try XCTUnwrap(PDFDocument(data: legacyFile))
        rotatedDocument.page(at: 0)?.rotation = 270
        XCTAssertNil(PDFDrawingFile.readMetadata(try XCTUnwrap(rotatedDocument.dataRepresentation())).payload)
    }

    // MARK: Previews

    func testRotatedPDFPreviewIsShownTheWayViewersShowIt() async throws {
        // A dark dot near the top-left corner of a landscape page.
        let dot = StrokeOutliner.shape(forSegments: [[VectorStrokeSample(point: CGPoint(x: 30, y: 30), width: 30)]], color: VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1))
        let drawing = VectorDrawing(size: CGSize(width: 400, height: 200), background: .white, shapes: [try XCTUnwrap(dot)])
        let document = try XCTUnwrap(PDFDocument(data: PDFDrawingFile.encode(drawing, payload: nil)))
        document.page(at: 0)?.rotation = 90
        let location = try temporaryDirectory().appendingPathComponent("Rotated.pdf")
        try XCTUnwrap(document.dataRepresentation()).write(to: location)
        let preview = try decodedImage(await ImageFileService().thumbnailData(at: location, maximumDimension: 400))
        XCTAssertEqual(preview.width, 200)
        XCTAssertEqual(preview.height, 400)
        // Turned a quarter clockwise, the top-left corner is shown at the top-right.
        let previewPixels = try pixels(of: preview)
        XCTAssertLessThan(pixel(previewPixels, width: preview.width, column: 170, row: 30)[0], 80)
        XCTAssertGreaterThan(pixel(previewPixels, width: preview.width, column: 30, row: 30)[0], 200)
        let displayed = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 400)
        XCTAssertEqual(try pixels(of: displayed), previewPixels)
    }

    func testDisplayImageHasTheThumbnailsPixels() async throws {
        let directory = try temporaryDirectory()
        let svgLocation = directory.appendingPathComponent("Drawing.svg"), pngLocation = directory.appendingPathComponent("Photo.png")
        try SVGDrawingFile.encode(sampleDrawing(), payload: samplePayload).write(to: svgLocation)
        try ImageEncoding.pngData(from: stripedImage(width: 3_000, height: 2_000, isOpaque: true)).write(to: pngLocation)
        for location in [svgLocation, pngLocation] {
            let thumbnail = try decodedImage(await ImageFileService().thumbnailData(at: location, maximumDimension: 1_000))
            let displayed = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 1_000)
            XCTAssertEqual(displayed.width, thumbnail.width)
            XCTAssertEqual(displayed.height, thumbnail.height)
            XCTAssertEqual(try pixels(of: displayed), try pixels(of: thumbnail))
        }
    }

    func testDecodingLimiterNeverExceedsItsBudget() async {
        actor ConcurrencyRecorder {
            var active = 0, maximumActive = 0
            func begin() { active += 1; maximumActive = max(maximumActive, active) }
            func end() { active -= 1 }
        }
        let limiter = ImageDecodingLimiter(maximumConcurrentDecodes: 2)
        let recorder = ConcurrencyRecorder()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await limiter.acquire()
                    await recorder.begin()
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    await recorder.end()
                    await limiter.release()
                }
            }
        }
        let maximumActive = await recorder.maximumActive
        XCTAssertEqual(maximumActive, 2)
    }

    func testDrawingPreviewWithANaNSideThrowsInsteadOfTrapping() {
        let drawing = VectorDrawing(size: CGSize(width: 100, height: Double.nan), background: .white, shapes: [])
        XCTAssertThrowsError(try VectorDrawingRenderer.pngData(for: drawing, maximumPixelDimension: 800))
        XCTAssertThrowsError(try VectorDrawingRenderer.pngData(for: VectorDrawing(size: CGSize(width: Double.infinity, height: 10), background: .white, shapes: []), maximumPixelDimension: 800))
    }

    // MARK: Colors

    func testVectorInkIsDrawnInSRGBInEveryFormat() throws {
        let systemBlue = VectorInkColor(red: 0, green: 122.0 / 255, blue: 1, alpha: 1)
        let square = VectorShape(subpaths: [[CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]], color: systemBlue)
        let drawing = VectorDrawing(size: CGSize(width: 100, height: 100), background: .white, shapes: [square])
        let preview = try decodedImage(VectorDrawingRenderer.pngData(for: drawing, maximumPixelDimension: 100))
        XCTAssertEqual(Array(pixel(try pixels(of: preview), width: preview.width, column: 50, row: 50).prefix(3)), [0, 122, 255])
        let page = try renderedFirstPage(PDFDrawingFile.encode(drawing, payload: nil), scale: 1)
        let pagePixel = pixel(page.pixels, width: page.width, column: 50, row: 50)
        XCTAssertEqual(pagePixel[0], 0, accuracy: 2)
        XCTAssertEqual(pagePixel[1], 122, accuracy: 2)
        XCTAssertEqual(pagePixel[2], 255, accuracy: 2)
        XCTAssertTrue(String(decoding: try SVGDrawingFile.encode(drawing, payload: nil), as: UTF8.self).contains("fill=\"#007aff\""))
    }

    func testWideGamutInkComponentsAreClamped() {
        let displayRed = VectorInkColor(clampingRed: 1.093, green: -0.227, blue: -0.150, alpha: 1.2)
        XCTAssertEqual(displayRed, VectorInkColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(VectorInkColor(clampingRed: .nan, green: 0.5, blue: 0.25, alpha: .nan), VectorInkColor(red: 0, green: 0.5, blue: 0.25, alpha: 0))
    }

    // MARK: Outlines

    func testAbsurdStrokeWidthsDoNotTrap() throws {
        let hugeDot = StrokeOutliner.subpaths(forSamples: [VectorStrokeSample(point: .zero, width: 1e19)])
        XCTAssertEqual(hugeDot.count, 1)
        XCTAssertEqual(hugeDot[0].count, 48)
        let hugeLine = StrokeOutliner.shape(forSegments: [[VectorStrokeSample(point: .zero, width: 1e300), VectorStrokeSample(point: CGPoint(x: 10, y: 0), width: 1e300)]], color: VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1))
        let drawing = VectorDrawing(size: CGSize(width: 100, height: 100), background: .white, shapes: [try XCTUnwrap(hugeLine)])
        XCTAssertNoThrow(try SVGDrawingFile.encode(drawing, payload: nil))
        XCTAssertEqual(SVGDrawingFile.formatted(1e300), "\(Int.max / 100).07")
        XCTAssertEqual(SVGDrawingFile.formatted(-.infinity), "-\(Int.max / 100).07")
        XCTAssertEqual(SVGDrawingFile.formatted(.nan), "0")
    }

    /// A 30 pt highlighter with a 10 pt pixel-eraser gap: round caps at the cut ends
    /// used to refill the whole gap.
    func testEraserMaskKeepsTheGapOpen() throws {
        let samples = (0...200).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step), y: 50), width: 30) }
        let visibleArea = CGMutablePath()
        visibleArea.addRect(CGRect(x: -100, y: -100, width: 215, height: 300))
        visibleArea.addRect(CGRect(x: 125, y: -100, width: 300, height: 300))
        let black = VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1)
        let shape = try XCTUnwrap(StrokeOutliner.shape(forSegments: [samples], color: black, clippedTo: visibleArea))
        let preview = try decodedImage(VectorDrawingRenderer.pngData(for: VectorDrawing(size: CGSize(width: 240, height: 100), background: .white, shapes: [shape]), maximumPixelDimension: 240))
        let previewPixels = try pixels(of: preview)
        for column in [117, 120, 123] { XCTAssertGreaterThan(pixel(previewPixels, width: preview.width, column: column, row: 50)[0], 200, "Column \(column) is in the erased gap.") }
        for column in [100, 112, 128, 140] { XCTAssertLessThan(pixel(previewPixels, width: preview.width, column: column, row: 50)[0], 60, "Column \(column) is visible ink.") }
        // An eraser pass that only trims the stroke's upper edge leaves its lower half.
        let lowerHalf = CGPath(rect: CGRect(x: -100, y: 50, width: 500, height: 100), transform: nil)
        let trimmed = try XCTUnwrap(StrokeOutliner.shape(forSegments: [samples], color: black, clippedTo: lowerHalf))
        let trimmedPreview = try decodedImage(VectorDrawingRenderer.pngData(for: VectorDrawing(size: CGSize(width: 240, height: 100), background: .white, shapes: [trimmed]), maximumPixelDimension: 240))
        let trimmedPixels = try pixels(of: trimmedPreview)
        XCTAssertGreaterThan(pixel(trimmedPixels, width: trimmedPreview.width, column: 120, row: 40)[0], 200)
        XCTAssertLessThan(pixel(trimmedPixels, width: trimmedPreview.width, column: 120, row: 60)[0], 60)
        XCTAssertNil(StrokeOutliner.shape(forSegments: [samples], color: black, clippedTo: CGPath(rect: CGRect(x: 500, y: 500, width: 10, height: 10), transform: nil)))
    }

    #if canImport(PencilKit) && canImport(AppKit)
    /// `PencilStrokeSampler.visibleArea` moves the mask with the stroke's transform. This
    /// checks PencilKit's own rendering does the same (drawings are always moved when
    /// cropped for export), while `maskedPathRanges` does not.
    func testPencilKitDrawsTheMaskInTheStrokesOwnSpace() throws {
        let points = (0...200).map { step in
            PKStrokePoint(location: CGPoint(x: Double(step), y: 0), timeOffset: Double(step) / 100, size: CGSize(width: 30, height: 30), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let mask = CGMutablePath()
        mask.addRect(CGRect(x: -100, y: -100, width: 195, height: 200))
        mask.addRect(CGRect(x: 105, y: -100, width: 200, height: 200))
        let stroke = PKStroke(ink: PKInk(.marker, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()),
                              transform: CGAffineTransform(translationX: 1000, y: 0), mask: NSBezierPath(cgPath: mask))
        let image = PKDrawing(strokes: [stroke]).image(from: CGRect(x: 1000, y: -20, width: 200, height: 40), scale: 1)
        var imageRectangle = CGRect(origin: .zero, size: image.size)
        let renderedPixels = try pixels(of: XCTUnwrap(image.cgImage(forProposedRect: &imageRectangle, context: nil, hints: nil)))
        let imageWidth = Int(image.size.width)
        XCTAssertEqual(pixel(renderedPixels, width: imageWidth, column: 100, row: 20)[3], 0, "PencilKit leaves the gap at the moved mask position.")
        XCTAssertGreaterThan(pixel(renderedPixels, width: imageWidth, column: 80, row: 20)[3], 200)
        XCTAssertTrue(stroke.maskedPathRanges.isEmpty, "maskedPathRanges ignores the transform; if this changes, revisit PencilStrokeSampler.")
    }
    #endif

    // MARK: SVG

    func testOversizedSVGMetadataIsRefused() throws {
        let fileData = try SVGDrawingFile.encode(sampleDrawing(), payload: samplePayload)
        var text = String(decoding: fileData, as: UTF8.self)
        let payloadEnd = try XCTUnwrap(text.range(of: "</graphite:drawing>"))
        text.insert(contentsOf: String(repeating: "A", count: DrawingMetadataReader.maximumBase64PayloadBytes), at: payloadEnd.lowerBound)
        let reading = SVGDrawingFile.readMetadata(Data(text.utf8))
        XCTAssertNil(reading.payload)
        XCTAssertTrue(reading.metadataWasDiscarded)
    }

    /// The previous writer, kept to prove the byte-buffer writer produces the same bytes;
    /// the digest of existing files covers every byte outside the metadata.
    func previousSVGEncoding(_ drawing: VectorDrawing, payload: DrawingPayload?) throws -> Data {
        func formatted(_ number: Double, fractionDigits: Int = 2) -> String {
            let multiplier = pow(10.0, Double(fractionDigits))
            let scaledNumber = Int((number * multiplier).rounded())
            let sign = scaledNumber < 0 ? "-" : ""
            let magnitude = abs(scaledNumber)
            let integerPart = magnitude / Int(multiplier)
            var fractionPart = String(magnitude % Int(multiplier))
            fractionPart = String(repeating: "0", count: fractionDigits - fractionPart.count) + fractionPart
            while fractionPart.hasSuffix("0") { fractionPart.removeLast() }
            return sign + String(integerPart) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        }
        func hexColor(_ color: VectorInkColor) -> String {
            func component(_ value: Double) -> String { String(format: "%02x", Int((min(max(value, 0), 1) * 255).rounded())) }
            return "#" + component(color.red) + component(color.green) + component(color.blue)
        }
        let width = formatted(drawing.size.width), height = formatted(drawing.size.height)
        var visibleHead = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        visibleHead += "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n"
        if drawing.background == .white { visibleHead += "<rect x=\"0\" y=\"0\" width=\"\(width)\" height=\"\(height)\" fill=\"#ffffff\"/>\n" }
        visibleHead += "<g fill-rule=\"nonzero\" stroke=\"none\">\n"
        for shape in drawing.shapes {
            visibleHead += "<path fill=\"\(hexColor(shape.color))\""
            if shape.color.alpha < 0.999 { visibleHead += " fill-opacity=\"\(formatted(shape.color.alpha, fractionDigits: 3))\"" }
            var pathText = ""
            for subpath in shape.subpaths {
                guard let firstPoint = subpath.first else { continue }
                pathText += "M\(formatted(firstPoint.x)) \(formatted(firstPoint.y))"
                for point in subpath.dropFirst() { pathText += "L\(formatted(point.x)) \(formatted(point.y))" }
                pathText += "Z"
            }
            visibleHead += " d=\"\(pathText)\"/>\n"
        }
        visibleHead += "</g>\n"
        let visibleTail = "\n</svg>\n"
        var document = visibleHead
        if let payload {
            var hash = SHA256()
            hash.update(data: Data(visibleHead.utf8))
            hash.update(data: Data(visibleTail.utf8))
            let encodedPayload = try payload.replacingVisibleContentDigest(Data(hash.finalize())).encoded().base64EncodedString()
            document += "<metadata id=\"graphite-drawing\"><graphite:drawing xmlns:graphite=\"urn:graphite:drawing:1\" encoding=\"base64-binary-property-list\">" + encodedPayload + "</graphite:drawing></metadata>"
        }
        document += visibleTail
        return Data(document.utf8)
    }

    func testSVGWriterBytesMatchThePreviousWriter() throws {
        var generator = SystemRandomNumberGenerator()
        let edgeNumbers: [Double] = [0, -0, 0.004, -0.004, 0.005, -0.005, 0.015, 1.005, 99.999, -99.995, 12.3, 1_000_000.126, -7.1]
        for trial in 0..<20 {
            let shapes = (0..<5).map { shapeIndex in
                let subpaths = (0..<3).map { _ in
                    (0..<40).map { pointIndex in
                        trial == 0 ? CGPoint(x: edgeNumbers[pointIndex % edgeNumbers.count], y: edgeNumbers[(pointIndex + shapeIndex) % edgeNumbers.count])
                            : CGPoint(x: Double.random(in: -50...900, using: &generator), y: Double.random(in: -50...900, using: &generator))
                    }
                }
                return VectorShape(subpaths: subpaths + [[]], color: VectorInkColor(red: Double.random(in: 0...1, using: &generator), green: 0.5, blue: 1, alpha: shapeIndex.isMultiple(of: 2) ? 1 : 0.3456))
            }
            let drawing = VectorDrawing(size: CGSize(width: 812.5, height: 1_024.25), background: trial.isMultiple(of: 2) ? .white : .transparent, shapes: shapes)
            XCTAssertEqual(try SVGDrawingFile.encode(drawing, payload: nil), try previousSVGEncoding(drawing, payload: nil))
            XCTAssertEqual(try SVGDrawingFile.encode(drawing, payload: samplePayload), try previousSVGEncoding(drawing, payload: samplePayload))
        }
    }

    // MARK: Editability checks for embeds

    func testPNGChunkWalkAnswersWithoutDecoding() throws {
        let directory = try temporaryDirectory()
        let ordinary = try ImageEncoding.pngData(from: stripedImage(width: 40, height: 30, isOpaque: true))
        let drawing = try GraphitePNG.encode(imageData: ordinary, drawing: DrawingPayload(width: 20, height: 15, background: .white, strokes: Data([1, 2, 3])))
        let ordinaryLocation = directory.appendingPathComponent("Photo.png"), drawingLocation = directory.appendingPathComponent("Drawing.png")
        let truncatedLocation = directory.appendingPathComponent("Truncated.png"), textLocation = directory.appendingPathComponent("Text.png")
        try ordinary.write(to: ordinaryLocation)
        try drawing.write(to: drawingLocation)
        try drawing.prefix(40).write(to: truncatedLocation)
        try Data("not a png".utf8).write(to: textLocation)
        XCTAssertFalse(DrawingMetadataReader.pngHasDrawingChunk(at: ordinaryLocation))
        XCTAssertTrue(DrawingMetadataReader.pngHasDrawingChunk(at: drawingLocation))
        XCTAssertFalse(DrawingMetadataReader.pngHasDrawingChunk(at: truncatedLocation))
        XCTAssertFalse(DrawingMetadataReader.pngHasDrawingChunk(at: textLocation))
        XCTAssertFalse(DrawingMetadataReader.hasEditableStrokes(at: ordinaryLocation))
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: drawingLocation))
        XCTAssertFalse(DrawingMetadataReader.hasEditableStrokes(at: truncatedLocation))
    }

    // MARK: Paper templates

    func testDottedNotebooksShareOneDotCellInsteadOfRepeatingEveryDot() throws {
        let thousandPages = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted), pageCount: 1_000)
        XCTAssertLessThan(thousandPages.count, 2_000_000, "A 1,000-page dotted notebook was 66 MB.")
        XCTAssertEqual(PDFDocument(data: thousandPages)?.pageCount, 1_000)
        let largePage = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted, width: 2_880, height: 2_880))
        XCTAssertLessThan(largePage.count, 50_000, "A single 40-inch dotted page was 1.2 MB.")
        // Dots are still real page content, at the margin and every `spacing` points.
        let page = try renderedFirstPage(PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted)), scale: 4)
        func darkness(atPagePoint point: CGPoint) -> Int {
            let column = Int((point.x * 4).rounded()), row = page.height - 1 - Int((point.y * 4).rounded())
            return 255 - pixel(page.pixels, width: page.width, column: column, row: row)[0]
        }
        for dot in [CGPoint(x: 30, y: 30), CGPoint(x: 48, y: 30), CGPoint(x: 30, y: 804), CGPoint(x: 552, y: 804)] {
            XCTAssertGreaterThan(darkness(atPagePoint: dot), 40, "Missing dot at \(dot).")
        }
        for gap in [CGPoint(x: 39, y: 39), CGPoint(x: 21, y: 30), CGPoint(x: 30, y: 821), CGPoint(x: 570, y: 804)] {
            XCTAssertLessThan(darkness(atPagePoint: gap), 5, "Unexpected dot at \(gap).")
        }
    }

    func testGridLinesEndAtTheLastCrossingLine() throws {
        for template in [PaperTemplate.grid, .engineering] {
            let page = try renderedFirstPage(PDFTemplateGenerator.documentData(paper: PaperSpecification(template: template)), scale: 2)
            func isInked(_ point: CGPoint) -> Bool {
                let column = Int((point.x * 2).rounded()), row = page.height - 1 - Int((point.y * 2).rounded())
                return pixel(page.pixels, width: page.width, column: column, row: row)[0] < 240
            }
            // On A4 with 18 pt spacing the last vertical line is at x 552 and the last
            // horizontal line at y 804; the margins are at 565.28 and 811.89.
            XCTAssertTrue(isInked(CGPoint(x: 545, y: 408)), "\(template): horizontal line inside the grid")
            XCTAssertFalse(isInked(CGPoint(x: 560, y: 408)), "\(template): stub past the last vertical line")
            XCTAssertTrue(isInked(CGPoint(x: 552, y: 790)), "\(template): vertical line inside the grid")
            XCTAssertFalse(isInked(CGPoint(x: 552, y: 809)), "\(template): stub past the last horizontal line")
        }
    }

    func testMatchingPagesAcceptEveryPageSizePDFAllows() throws {
        for (requestedSize, expectedSize) in [
            (CGSize(width: 2_383.94, height: 3_370.39), CGSize(width: 2_383.94, height: 3_370.39)),
            (CGSize(width: 2_480, height: 3_508), CGSize(width: 2_480, height: 3_508)),
            (CGSize(width: 60, height: 80), CGSize(width: 60, height: 80)),
            (CGSize(width: 20_000, height: 1), CGSize(width: 14_400, height: 3)),
        ] {
            let fileData = try PDFTemplateGenerator.pageData(template: .dotted, matching: requestedSize)
            let mediaBox = try XCTUnwrap(PDFDocument(data: fileData)?.page(at: 0)?.bounds(for: .mediaBox))
            XCTAssertEqual(mediaBox.width, expectedSize.width, accuracy: 0.01)
            XCTAssertEqual(mediaBox.height, expectedSize.height, accuracy: 0.01)
        }
        XCTAssertThrowsError(try PDFTemplateGenerator.pageData(template: .ruled, matching: CGSize(width: Double.nan, height: 100)))
        XCTAssertThrowsError(try PDFTemplateGenerator.documentData(paper: PaperSpecification(width: 2_383.94, height: 3_370.39)), "New notebooks keep their own size range.")
    }

    // MARK: Embed options

    func testEmbedOptionsSkipMalformedValues() {
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=3&page=abc"), PDFEmbedOptions(startPageNumber: 3))
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=3&page=0"), PDFEmbedOptions(startPageNumber: 3))
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=3&page=5"), PDFEmbedOptions(startPageNumber: 5))
        XCTAssertEqual(PDFEmbedOptions(fragment: "height=400&height=-1"), PDFEmbedOptions(height: 400))
        XCTAssertNil(PDFEmbedOptions(fragment: "height=0x10").height)
        XCTAssertNil(PDFEmbedOptions(fragment: "height=1e3").height)
        XCTAssertNil(PDFEmbedOptions(fragment: "height=inf").height)
        XCTAssertNil(PDFEmbedOptions(fragment: "height=.5").height)
        XCTAssertNil(PDFEmbedOptions(fragment: "height=5.").height)
        XCTAssertEqual(PDFEmbedOptions(fragment: "height=320.5").height, 320.5)
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=2&height=300"), PDFEmbedOptions(startPageNumber: 2, height: 300))
    }
}

