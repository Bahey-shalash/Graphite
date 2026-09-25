import Foundation
import CoreGraphics
import CryptoKit
import GraphiteCore

/// Vector drawings as a one-page PDF. Stroke data for re-editing is stored in the
/// document's standard XMP metadata stream, which PDF viewers do not display.
/// A digest of the page content detects later edits by other applications.
public enum PDFDrawingFile {
    public static let maximumFileBytes = 128 * 1_048_576
    /// The XMP packet around the largest payload, plus room for fields and padding that
    /// other applications add when they rewrite the packet.
    static let maximumMetadataBytes = DrawingMetadataReader.maximumBase64PayloadBytes + 262_144
    /// Decoded page content of the largest drawing Graphite writes is well under this;
    /// anything larger is not a Graphite drawing. Content is hashed as it is inflated, so
    /// this bounds time, not memory.
    static let maximumDecodedPageContentBytes = 4 * maximumFileBytes
    private static let payloadStart = "<graphite:drawing>"
    private static let payloadEnd = "</graphite:drawing>"
    /// A cropped drawing's size is whole points, so the page and payload sizes match exactly.
    private static let pageSizeTolerance = 0.01

    public static func encode(_ drawing: VectorDrawing, payload: DrawingPayload?) throws -> Data {
        let documentWithoutMetadata = try render(drawing, metadata: nil)
        guard let payload else { return documentWithoutMetadata }
        let digest = try pageContentDigests(of: documentWithoutMetadata).withResources
        let digestedPayload = payload.replacingVisibleContentDigest(digest)
        let encodedPayload = try digestedPayload.encoded().base64EncodedString()
        let documentWithMetadata = try render(drawing, metadata: Data(metadataPacket(encodedPayload: encodedPayload).utf8))
        guard documentWithMetadata.count <= maximumFileBytes else { throw GraphiteError.oversized("This drawing is too complex for a PDF file.") }
        // Core Graphics writes the same page content for the same drawing commands. Reading
        // the finished file back the way every later open does checks that and the
        // metadata together, so callers need not verify it again.
        guard readMetadata(documentWithMetadata).payload == digestedPayload else {
            throw GraphiteError.invalidFile("The PDF drawing could not be verified. Nothing was saved.")
        }
        return documentWithMetadata
    }

    public static func readMetadata(_ fileData: Data) -> DrawingMetadataReading {
        guard fileData.count <= maximumFileBytes,
              let provider = CGDataProvider(data: fileData as CFData),
              let document = CGPDFDocument(provider) else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: false)
        }
        return readMetadata(from: document, file: PDFFileBytes(byteCount: fileData.count, readBytes: { fileData }))
    }

    /// Core Graphics reads PDF objects lazily, so checking a large lecture PDF this way
    /// touches only its catalog and page tree. Only a one-page file is read further.
    static func readMetadata(at location: URL) -> DrawingMetadataReading {
        guard let fileSize = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize <= maximumFileBytes,
              let document = CGPDFDocument(location as CFURL) else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: false)
        }
        // Mapped rather than copied, and read only if a stream must be inflated from it.
        // A file that cannot be read is not an editable drawing.
        return readMetadata(from: document, file: PDFFileBytes(byteCount: fileSize, readBytes: { try? Data(contentsOf: location, options: .mappedIfSafe) }))
    }

    private static func readMetadata(from document: CGPDFDocument, file: PDFFileBytes) -> DrawingMetadataReading {
        let noMetadata = DrawingMetadataReading(payload: nil, metadataWasDiscarded: false)
        // Graphite writes one page. Checking that first keeps lecture PDFs, which every
        // embed checks, from having their metadata decoded or their bytes searched.
        guard document.numberOfPages == 1, let catalog = document.catalog else { return noMetadata }
        var metadataStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &metadataStream), let metadataStream,
              let metadataBytes = PDFDrawingStreamDecoder.decodedContents(of: metadataStream, in: file, maximumDecodedBytes: maximumMetadataBytes),
              let startRange = metadataBytes.range(of: Data(payloadStart.utf8)),
              let endRange = metadataBytes.range(of: Data(payloadEnd.utf8), in: startRange.upperBound..<metadataBytes.endIndex) else {
            return noMetadata
        }
        let encodedPayload = metadataBytes[startRange.upperBound..<endRange.lowerBound]
        // The payload is decoded and matched to the page before any page content is
        // decoded, so only a file that really looks like a Graphite drawing pays for that.
        guard encodedPayload.count <= DrawingMetadataReader.maximumBase64PayloadBytes,
              let page = document.page(at: 1), !hasAnnotations(page),
              let payloadData = Data(base64Encoded: Data(encodedPayload)),
              let payload = DrawingPayload.decodeIfValid(payloadData),
              matchesPageSize(payload, page: page),
              let digests = try? pageContentDigests(of: page, in: file),
              payload.visibleContentDigest == digests.withResources || payload.visibleContentDigest == digests.withoutResources else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: true)
        }
        return DrawingMetadataReading(payload: payload, metadataWasDiscarded: false)
    }

    private static func matchesPageSize(_ payload: DrawingPayload, page: CGPDFPage) -> Bool {
        let mediaBox = page.getBoxRect(.mediaBox)
        return abs(mediaBox.width - payload.width) <= pageSizeTolerance && abs(mediaBox.height - payload.height) <= pageSizeTolerance
    }

    private static func render(_ drawing: VectorDrawing, metadata: Data?) throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: drawing.size)
        let documentInformation = [kCGPDFContextCreator as String: "Graphite"] as CFDictionary
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, documentInformation) else {
            throw GraphiteError.unavailable("Could not create the PDF drawing.")
        }
        if let metadata { context.addDocumentMetadata(metadata as CFData) }
        context.beginPDFPage(nil)
        // PDF pages have a bottom-left origin; drawings use a top-left one.
        context.translateBy(x: 0, y: drawing.size.height)
        context.scaleBy(x: 1, y: -1)
        VectorDrawingRenderer.draw(drawing, in: context)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    private static func metadataPacket(encodedPayload: String) -> String {
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:graphite="urn:graphite:drawing:1">
        <xmp:CreatorTool>Graphite</xmp:CreatorTool>
        \(payloadStart)\(encodedPayload)\(payloadEnd)
        </rdf:Description>
        </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    /// Digests of what a page shows. Drawings saved before resources were covered store
    /// `withoutResources`; newer ones store `withResources`. Both include any rotation,
    /// crop, or user unit another application added, so those edits are always detected.
    struct PageContentDigests {
        let withoutResources: Data
        let withResources: Data
    }

    private static func pageContentDigests(of fileData: Data) throws -> PageContentDigests {
        guard let provider = CGDataProvider(data: fileData as CFData), let document = CGPDFDocument(provider),
              document.numberOfPages == 1, let page = document.page(at: 1) else {
            throw GraphiteError.invalidFile("The PDF drawing could not be reopened.")
        }
        return try pageContentDigests(of: page, in: PDFFileBytes(byteCount: fileData.count, readBytes: { fileData }))
    }

    /// SHA-256 of the page box, any non-default display geometry, and the decoded content
    /// streams; then also of the resources those streams draw with (transparency, color
    /// spaces), which change what is visible without changing the content stream.
    static func pageContentDigests(of page: CGPDFPage, in file: PDFFileBytes) throws -> PageContentDigests {
        guard let pageDictionary = page.dictionary else { throw GraphiteError.invalidFile("The PDF page is unreadable.") }
        var hash = SHA256()
        let mediaBox = page.getBoxRect(.mediaBox)
        hash.update(data: Data("\(mediaBox.minX) \(mediaBox.minY) \(mediaBox.width) \(mediaBox.height)".utf8))
        // Only a non-default geometry is added, so files written before it was covered keep
        // their digest.
        if let geometryDescription = nonDefaultDisplayGeometry(of: page, pageDictionary: pageDictionary) {
            hash.update(data: Data(geometryDescription.utf8))
        }
        var decodedContentBytes = 0
        func hashContent(of stream: CGPDFStreamRef) throws {
            // The running total stops a page that decodes to more than any drawing could.
            guard let decodedByteCount = PDFDrawingStreamDecoder.decode(stream, in: file, maximumDecodedBytes: maximumDecodedPageContentBytes - decodedContentBytes,
                                                                        into: &hash, append: { hash, contentChunk in hash.update(data: contentChunk) }) else {
                throw GraphiteError.invalidFile("The PDF page content is unreadable.")
            }
            decodedContentBytes += decodedByteCount
        }
        var contentStream: CGPDFStreamRef?
        var contentArray: CGPDFArrayRef?
        if CGPDFDictionaryGetStream(pageDictionary, "Contents", &contentStream), let contentStream {
            try hashContent(of: contentStream)
        } else if CGPDFDictionaryGetArray(pageDictionary, "Contents", &contentArray), let contentArray {
            for streamIndex in 0..<CGPDFArrayGetCount(contentArray) {
                var arrayStream: CGPDFStreamRef?
                guard CGPDFArrayGetStream(contentArray, streamIndex, &arrayStream), let arrayStream else {
                    throw GraphiteError.invalidFile("The PDF page content is unreadable.")
                }
                try hashContent(of: arrayStream)
            }
        }
        let withoutResources = Data(hash.finalize())
        var resourceDescription = PDFObjectDescription()
        for key in ["Resources", "Group"] {
            var object: CGPDFObjectRef?
            guard CGPDFDictionaryGetObject(pageDictionary, key, &object), let object else { continue }
            resourceDescription.appendText("/\(key) ")
            try resourceDescription.append(object)
        }
        hash.update(data: resourceDescription.bytes)
        return PageContentDigests(withoutResources: withoutResources, withResources: Data(hash.finalize()))
    }

    /// Rotation, crop box, and user unit as text when any differs from what Graphite writes.
    private static func nonDefaultDisplayGeometry(of page: CGPDFPage, pageDictionary: CGPDFDictionaryRef) -> String? {
        let rotation = ((Int(page.rotationAngle) % 360) + 360) % 360
        let mediaBox = page.getBoxRect(.mediaBox), cropBox = page.getBoxRect(.cropBox)
        var userUnit: CGPDFReal = 1
        if !CGPDFDictionaryGetNumber(pageDictionary, "UserUnit", &userUnit) { userUnit = 1 }
        guard rotation != 0 || cropBox != mediaBox || userUnit != 1 else { return nil }
        return " rotation \(rotation) crop \(cropBox.minX) \(cropBox.minY) \(cropBox.width) \(cropBox.height) unit \(userUnit)"
    }

    private static func hasAnnotations(_ page: CGPDFPage) -> Bool {
        guard let pageDictionary = page.dictionary else { return false }
        var annotations: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations) && annotations.map { annotationArray in CGPDFArrayGetCount(annotationArray) > 0 } == true
    }
}

/// A canonical text form of a PDF object graph, for digests. Dictionary keys are sorted,
/// references are followed (Core Graphics resolves them), and numbers are rounded so a
/// rewrite that only reformats reals does not look like an edit. Stream dictionaries are
/// described without their data: decoding arbitrary resource streams (images, fonts)
/// could be unbounded, and Graphite's own resources hold only an ICC profile there.
/// Encoding keys (`Length`, `Filter`) are skipped because re-saving may recompress.
struct PDFObjectDescription {
    private(set) var bytes = Data()
    /// A crafted file can nest or share objects without end; Graphite's own resources are
    /// a few dozen objects, three levels deep.
    private var remainingObjectCount = 10_000
    private let maximumDepth = 16
    private static let encodingKeys: Set<String> = ["Length", "Filter", "DecodeParms", "DL"]
    /// Obsolete since PDF 1.4 and ignored by every renderer; writers add or drop it freely.
    private static let ignoredKeys: Set<String> = ["ProcSet"]

    mutating func appendText(_ text: String) {
        bytes.append(contentsOf: text.utf8)
    }

    mutating func append(_ object: CGPDFObjectRef) throws {
        try append(object, depth: 0)
    }

    private mutating func append(_ object: CGPDFObjectRef, depth: Int) throws {
        remainingObjectCount -= 1
        guard remainingObjectCount >= 0, depth <= maximumDepth else {
            throw GraphiteError.invalidFile("The PDF page resources are too complex.")
        }
        switch CGPDFObjectGetType(object) {
        case .null:
            appendText("null ")
        case .boolean:
            var boolean: CGPDFBoolean = 0
            _ = CGPDFObjectGetValue(object, .boolean, &boolean)
            appendText(boolean == 0 ? "false " : "true ")
        case .integer, .real:
            // Core Graphics reads an integer as a real too; describing both the same way
            // keeps a rewrite that writes `1` as `1.0` from looking like an edit.
            var number: CGPDFReal = 0
            _ = CGPDFObjectGetValue(object, .real, &number)
            appendText(String(format: "%.4f ", Double(number)))
        case .name:
            var name: UnsafePointer<CChar>?
            _ = CGPDFObjectGetValue(object, .name, &name)
            appendText("/" + (name.map { namePointer in String(cString: namePointer) } ?? "") + " ")
        case .string:
            var string: CGPDFStringRef?
            _ = CGPDFObjectGetValue(object, .string, &string)
            appendText("(")
            if let string, let bytePointer = CGPDFStringGetBytePtr(string) {
                bytes.append(bytePointer, count: CGPDFStringGetLength(string))
            }
            appendText(") ")
        case .array:
            var array: CGPDFArrayRef?
            _ = CGPDFObjectGetValue(object, .array, &array)
            appendText("[ ")
            if let array {
                for elementIndex in 0..<CGPDFArrayGetCount(array) {
                    var element: CGPDFObjectRef?
                    if CGPDFArrayGetObject(array, elementIndex, &element), let element { try append(element, depth: depth + 1) }
                }
            }
            appendText("] ")
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            _ = CGPDFObjectGetValue(object, .dictionary, &dictionary)
            if let dictionary { try append(dictionary, excludingKeys: [], depth: depth) }
        case .stream:
            var stream: CGPDFStreamRef?
            _ = CGPDFObjectGetValue(object, .stream, &stream)
            appendText("stream ")
            if let stream, let dictionary = CGPDFStreamGetDictionary(stream) {
                try append(dictionary, excludingKeys: Self.encodingKeys, depth: depth)
            }
        @unknown default:
            appendText("unknown ")
        }
    }

    private mutating func append(_ dictionary: CGPDFDictionaryRef, excludingKeys: Set<String>, depth: Int) throws {
        var entries: [(key: String, value: CGPDFObjectRef)] = []
        CGPDFDictionaryApplyBlock(dictionary, { keyPointer, value, _ in
            entries.append((String(cString: keyPointer), value))
            return true
        }, nil)
        appendText("<< ")
        for entry in entries.sorted(by: { first, second in first.key < second.key }) where !excludingKeys.contains(entry.key) && !Self.ignoredKeys.contains(entry.key) {
            appendText("/\(entry.key) ")
            try append(entry.value, depth: depth + 1)
        }
        appendText(">> ")
    }
}
