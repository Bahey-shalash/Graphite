import Foundation
import ImageIO

/// Removes the objects nothing refers to from a PDF that PDFKit wrote, and stores the
/// pictures Graphite placed as the JPEG they are.
///
/// PDFKit writes every object of the file it read, whether or not anything still refers
/// to it, unless the page tree changed. A picture moved, turned or cropped on a page, an
/// erased stroke or removed markup therefore stayed in the file as an unreachable copy,
/// and each save of a re-read file added more: four moves of one 200 KB photo left 4.4 MB
/// of copies in a 5.5 MB file. Compaction copies only the objects reachable from the
/// trailer, byte for byte, so everything any reader can see or use (pages, annotations of
/// every application, outline, links, forms, page labels, metadata, Graphite's own keys)
/// stays exactly as PDFKit wrote it.
///
/// PDFKit also writes the appearance of a picture's stamp as inflated pixels with an
/// opaque soft mask, several times the size of the JPEG it was drawn from. When the
/// picture's own bytes (kept under `PDFPageManager.pictureKey`) are a JPEG of exactly the
/// appearance image's size and color components, and the soft mask is fully opaque, the
/// image is written as that JPEG (`DCTDecode`), as Core Graphics itself writes a JPEG in a
/// newly made PDF, with the same color space. The copy of the picture's bytes PDFKit puts
/// in its own markup data is removed too (see `PictureMarkupCopyRemoval`).
///
/// Only the single-section, uncompressed cross-reference table PDFKit writes is
/// understood. Anything else (an incremental update, a cross-reference stream, an
/// encrypted file, a syntax error) leaves the file as PDFKit wrote it.
public enum PDFObjectCompaction {
    public struct Report: Sendable, Equatable {
        public let removedObjectCount: Int
        /// Bytes of removed objects, before the JPEG pictures are counted.
        public let removedByteCount: Int
        public let picturesStoredAsJPEG: Int
        /// Pictures whose bytes PDFKit had also copied into its own markup data.
        public let pictureMarkupCopiesRemoved: Int
    }

    /// Writes the compacted PDF to `destination` and reports what changed. Returns nil, and
    /// creates nothing, when nothing would change or the file is not in the form PDFKit
    /// writes.
    public static func compact(fileAt source: URL, writingTo destination: URL) throws -> Report? {
        let fileBytes = try Data(contentsOf: source, options: .alwaysMapped)
        guard let plan = fileBytes.withUnsafeBytes({ buffer in CompactionPlanner(bytes: buffer).plan() }) else { return nil }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var sink = FileSink(handle: handle)
        try plan.write(from: fileBytes, into: &sink)
        try sink.flush()
        return plan.report
    }

    /// The compacted PDF, or nil when nothing would change or the data is not in the form
    /// PDFKit writes.
    public static func compacted(_ pdfData: Data) -> (data: Data, report: Report)? {
        guard let plan = pdfData.withUnsafeBytes({ buffer in CompactionPlanner(bytes: buffer).plan() }) else { return nil }
        var sink = DataSink()
        // A data sink cannot fail.
        try? plan.write(from: pdfData, into: &sink)
        return (sink.data, plan.report)
    }
}

// MARK: Writing

private protocol CompactionSink {
    mutating func write(_ bytes: Data) throws
}

private struct DataSink: CompactionSink {
    var data = Data()
    mutating func write(_ bytes: Data) { data.append(bytes) }
}

/// Collects small writes, so thousands of small objects are not as many system calls.
private struct FileSink: CompactionSink {
    private static let bufferByteCount = 1_048_576
    let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) { self.handle = handle }

    mutating func write(_ bytes: Data) throws {
        if buffer.count + bytes.count > Self.bufferByteCount { try flush() }
        if bytes.count >= Self.bufferByteCount { try handle.write(contentsOf: bytes) } else { buffer.append(bytes) }
    }

    mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

/// What the compacted file holds, found without writing anything.
private struct CompactionPlan {
    struct KeptObject {
        let number: Int
        let generation: Int
        /// The object's bytes in the source, from its header to the next object.
        let sourceRange: Range<Int>
        /// The object's new bytes, for a picture image written as its JPEG.
        let replacement: Data?
    }

    /// The bytes before the first object: the header and its binary comment.
    let headerRange: Range<Int>
    let keptObjects: [KeptObject]
    let crossReferenceSize: Int
    /// The generation each number that is free in the written file is next used with.
    let freeGenerations: [Int: Int]
    let trailerDictionaryRange: Range<Int>
    let report: PDFObjectCompaction.Report

    func write<Sink: CompactionSink>(from source: Data, into sink: inout Sink) throws {
        var writtenByteCount = 0
        func write(_ bytes: Data) throws {
            try sink.write(bytes)
            writtenByteCount += bytes.count
        }
        func sourceBytes(_ range: Range<Int>) -> Data { source[(source.startIndex + range.lowerBound)..<(source.startIndex + range.upperBound)] }
        try write(sourceBytes(headerRange))
        var offsets: [Int: (offset: Int, generation: Int)] = [:]
        // Neighbouring kept objects are copied as one run.
        var pendingRun: Range<Int>?
        func writePendingRun() throws {
            if let run = pendingRun { try write(sourceBytes(run)) }
            pendingRun = nil
        }
        for object in keptObjects {
            if let replacement = object.replacement {
                try writePendingRun()
                offsets[object.number] = (writtenByteCount, object.generation)
                try write(replacement)
            } else if let run = pendingRun, run.upperBound == object.sourceRange.lowerBound {
                offsets[object.number] = (writtenByteCount + run.count, object.generation)
                pendingRun = run.lowerBound..<object.sourceRange.upperBound
            } else {
                try writePendingRun()
                offsets[object.number] = (writtenByteCount, object.generation)
                pendingRun = object.sourceRange
            }
        }
        try writePendingRun()
        let crossReferenceOffset = writtenByteCount
        var table = "xref\n0 \(crossReferenceSize)\n"
        table.reserveCapacity(table.utf8.count + crossReferenceSize * 20)
        // Free entries form a list through their offset fields, from entry 0 back to 0.
        let freeNumbers = (0..<crossReferenceSize).filter { number in offsets[number] == nil }
        var nextFreeNumber: [Int: Int] = [:]
        for (position, number) in freeNumbers.enumerated() { nextFreeNumber[number] = position + 1 < freeNumbers.count ? freeNumbers[position + 1] : 0 }
        for number in 0..<crossReferenceSize {
            if let entry = offsets[number] {
                table += Self.entry(entry.offset, entry.generation, kind: "n")
            } else {
                let generation = number == 0 ? 65_535 : freeGenerations[number] ?? 0
                table += Self.entry(nextFreeNumber[number] ?? 0, generation, kind: "f")
            }
        }
        try write(Data(table.utf8))
        try write(Data("trailer\n".utf8))
        try write(sourceBytes(trailerDictionaryRange))
        try write(Data("\nstartxref\n\(crossReferenceOffset)\n%%EOF\n".utf8))
    }

    /// One 20-byte cross-reference entry.
    private static func entry(_ offset: Int, _ generation: Int, kind: Character) -> String {
        let offsetText = String(offset), generationText = String(generation)
        return String(repeating: "0", count: max(0, 10 - offsetText.count)) + offsetText + " "
            + String(repeating: "0", count: max(0, 5 - generationText.count)) + generationText + " \(kind)\r\n"
    }
}

// MARK: Planning

/// Reads the cross-reference table, the trailer and each object's references, and decides
/// what the compacted file holds.
private struct CompactionPlanner {
    private struct SourceObject {
        let generation: Int
        let range: Range<Int>
        let references: [Int]
        /// Whether the object is a dictionary with a Graphite picture's bytes.
        let isPictureCandidate: Bool
    }

    /// The most objects or cross-reference entries read, bounding memory for a damaged file.
    private static let maximumObjectCount = 10_000_000
    /// How far from the end `startxref` is searched for.
    private static let trailerSearchDistance = 4_096

    let bytes: UnsafeRawBufferPointer

    func plan() -> CompactionPlan? {
        var scanner = PDFSyntaxScanner(bytes: bytes)
        guard let crossReferenceOffset = findCrossReferenceOffset(), crossReferenceOffset < bytes.count else { return nil }
        scanner.position = crossReferenceOffset
        guard scanner.readKeyword() == "xref" else { return nil }
        var entries: [Int: (offset: Int, generation: Int, inUse: Bool)] = [:]
        // Subsections until the trailer.
        while true {
            let keywordStart = scanner.position
            if scanner.readKeyword() == "trailer" { break }
            scanner.position = keywordStart
            guard let firstNumber = scanner.readUnsignedInteger(), let count = scanner.readUnsignedInteger(),
                  entries.count + count <= Self.maximumObjectCount else { return nil }
            for entryIndex in 0..<count {
                guard let offset = scanner.readUnsignedInteger(), let generation = scanner.readUnsignedInteger() else { return nil }
                let kind = scanner.readKeyword()
                guard kind == "n" || kind == "f" else { return nil }
                entries[firstNumber + entryIndex] = (offset, generation, kind == "n")
            }
        }
        let trailerStart = scanner.skipWhitespaceAndComments()
        guard case .dictionary(let trailer)? = scanner.readValue() else { return nil }
        let trailerRange = trailerStart..<scanner.position
        // An incremental update, a hybrid file or an encrypted one is left as it is.
        guard trailer.entries["Prev"] == nil, trailer.entries["XRefStm"] == nil, trailer.entries["Encrypt"] == nil,
              case .integer(let crossReferenceSize)? = trailer.entries["Size"], crossReferenceSize > 0, crossReferenceSize <= Self.maximumObjectCount,
              entries.keys.allSatisfy({ number in number < crossReferenceSize }) else { return nil }

        let inUseEntries = entries.filter { _, entry in entry.inUse && entry.offset < crossReferenceOffset }
        guard inUseEntries.count == entries.filter({ _, entry in entry.inUse }).count else { return nil }
        let orderedNumbers = inUseEntries.keys.sorted { leftNumber, rightNumber in inUseEntries[leftNumber]!.offset < inUseEntries[rightNumber]!.offset }
        guard let firstNumber = orderedNumbers.first else { return nil }
        var objects: [Int: SourceObject] = [:]
        objects.reserveCapacity(orderedNumbers.count)
        for (position, number) in orderedNumbers.enumerated() {
            let entry = inUseEntries[number]!
            let end = position + 1 < orderedNumbers.count ? inUseEntries[orderedNumbers[position + 1]]!.offset : crossReferenceOffset
            guard end > entry.offset else { return nil }
            scanner.position = entry.offset
            // Each entry must point at its own object's header.
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == entry.generation, scanner.readKeyword() == "obj",
                  let value = scanner.readValue(), scanner.position <= end else { return nil }
            var references: [Int] = []
            value.collectReferences(into: &references)
            var isPictureCandidate = false
            if case .dictionary(let dictionary) = value { isPictureCandidate = dictionary.entries["GraphitePictureV1"] != nil }
            objects[number] = SourceObject(generation: entry.generation, range: entry.offset..<end, references: references,
                                           isPictureCandidate: isPictureCandidate)
        }

        var trailerReferences: [Int] = []
        PDFSyntaxValue.dictionary(trailer).collectReferences(into: &trailerReferences)
        var reachable = Self.reachableNumbers(from: trailerReferences) { number in objects[number]?.references ?? [] }
        let pictureCandidates = reachable.filter { number in objects[number]?.isPictureCandidate == true }
        let objectLocations = { (number: Int) in objects[number].map { object in (generation: object.generation, range: object.range) } }
        let pictureImages = PictureImageReplacement.find(in: pictureCandidates, objects: objectLocations, bytes: bytes)
        let picturesWithoutMarkupCopy = PictureMarkupCopyRemoval.find(in: pictureCandidates, objects: objectLocations, bytes: bytes)
        if !pictureImages.isEmpty {
            // A picture image written as its JPEG no longer refers to its soft mask.
            reachable = Self.reachableNumbers(from: trailerReferences) { number in
                pictureImages[number]?.references ?? objects[number]?.references ?? []
            }
        }
        let removedNumbers = objects.keys.filter { number in !reachable.contains(number) }
        guard !removedNumbers.isEmpty || !pictureImages.isEmpty || !picturesWithoutMarkupCopy.isEmpty else { return nil }

        var freeGenerations: [Int: Int] = [:]
        for (number, entry) in entries where !entry.inUse { freeGenerations[number] = entry.generation }
        for number in removedNumbers { freeGenerations[number] = min((objects[number]?.generation ?? 0) + 1, 65_535) }
        let keptObjects = orderedNumbers.filter(reachable.contains).compactMap { number -> CompactionPlan.KeptObject? in
            guard let object = objects[number] else { return nil }
            return CompactionPlan.KeptObject(number: number, generation: object.generation, sourceRange: object.range,
                                             replacement: pictureImages[number]?.objectBytes ?? picturesWithoutMarkupCopy[number])
        }
        let removedByteCount = removedNumbers.reduce(0) { total, number in total + (objects[number]?.range.count ?? 0) }
        let headerEnd = inUseEntries[firstNumber]!.offset
        return CompactionPlan(headerRange: 0..<headerEnd, keptObjects: keptObjects, crossReferenceSize: crossReferenceSize,
                              freeGenerations: freeGenerations, trailerDictionaryRange: trailerRange,
                              report: .init(removedObjectCount: removedNumbers.count, removedByteCount: removedByteCount,
                                            picturesStoredAsJPEG: pictureImages.count, pictureMarkupCopiesRemoved: picturesWithoutMarkupCopy.count))
    }

    private static func reachableNumbers(from roots: [Int], references: (Int) -> [Int]) -> Set<Int> {
        var reachable: Set<Int> = []
        var pending = roots
        while let number = pending.popLast() {
            guard reachable.insert(number).inserted else { continue }
            pending.append(contentsOf: references(number))
        }
        return reachable
    }

    /// The offset `startxref` names, found near the end of the file.
    private func findCrossReferenceOffset() -> Int? {
        let keyword = Array("startxref".utf8)
        let searchStart = max(0, bytes.count - Self.trailerSearchDistance)
        var candidate = bytes.count - keyword.count
        while candidate >= searchStart {
            if (0..<keyword.count).allSatisfy({ index in bytes[candidate + index] == keyword[index] }) {
                var scanner = PDFSyntaxScanner(bytes: bytes)
                scanner.position = candidate + keyword.count
                return scanner.readUnsignedInteger()
            }
            candidate -= 1
        }
        return nil
    }
}

// MARK: Pictures

/// A picture's appearance image written as the JPEG the picture was placed from.
private struct PictureImageReplacement {
    let objectBytes: Data
    /// What the image still refers to: its color space's profile.
    let references: [Int]

    /// Bounds the soft mask inflated to check that it is fully opaque.
    private static let maximumMaskPixelCount = 64 * 1_048_576

    /// Replacements by image object number, for the pictures among the candidates that qualify.
    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?,
                     bytes: UnsafeRawBufferPointer) -> [Int: PictureImageReplacement] {
        func parsedObject(_ number: Int) -> (value: PDFSyntaxValue, streamDataStart: Int?)? {
            guard let object = objects(number) else { return nil }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj",
                  let value = scanner.readValue() else { return nil }
            return (value, scanner.streamDataStart(before: object.range.upperBound))
        }
        func dictionary(_ value: PDFSyntaxValue?) -> PDFSyntaxDictionary? {
            switch value {
            case .dictionary(let dictionary)?: dictionary
            case .reference(let number)?: parsedObject(number).flatMap { object in dictionary(object.value) }
            default: nil
            }
        }

        var replacements: [Int: PictureImageReplacement] = [:]
        for number in candidates.sorted() {
            guard case .dictionary(let annotation)? = parsedObject(number)?.value,
                  annotation.entries["Subtype"] == .name("Stamp"),
                  case .string(let storedPicture)? = annotation.entries["GraphitePictureV1"],
                  let jpegData = Self.jpegData(fromStoredPicture: storedPicture),
                  let appearance = dictionary(annotation.entries["AP"]),
                  case .reference(let formNumber)? = appearance.entries["N"],
                  let form = dictionary(.reference(formNumber)),
                  let resources = dictionary(form.entries["Resources"]),
                  let images = dictionary(resources.entries["XObject"]), images.entries.count == 1,
                  case .reference(let imageNumber)? = images.entries.values.first,
                  replacements[imageNumber] == nil, let imageObject = parsedObject(imageNumber),
                  case .dictionary(let image) = imageObject.value,
                  let replacement = replacement(for: image, number: imageNumber, generation: objects(imageNumber)?.generation ?? 0,
                                                jpegData: jpegData, dictionary: dictionary, parsedObject: parsedObject, bytes: bytes)
            else { continue }
            replacements[imageNumber] = replacement
        }
        return replacements
    }

    private static func jpegData(fromStoredPicture storedPicture: Data) -> Data? {
        let prefix = Data(PDFPicture.storedImagePrefix.utf8)
        guard storedPicture.starts(with: prefix),
              let pictureData = Data(base64Encoded: storedPicture.dropFirst(prefix.count), options: .ignoreUnknownCharacters),
              pictureData.starts(with: [0xFF, 0xD8]) else { return nil }
        return pictureData
    }

    private static func replacement(for image: PDFSyntaxDictionary, number: Int, generation: Int, jpegData: Data,
                                    dictionary: (PDFSyntaxValue?) -> PDFSyntaxDictionary?,
                                    parsedObject: (Int) -> (value: PDFSyntaxValue, streamDataStart: Int?)?,
                                    bytes: UnsafeRawBufferPointer) -> PictureImageReplacement? {
        // Only a plain 8-bit image with no decoding, masking or filter parameters of its own.
        guard image.entries["Subtype"] == .name("Image"), image.entries["Filter"] == .name("FlateDecode"),
              image.entries["BitsPerComponent"] == .integer(8),
              case .integer(let width)? = image.entries["Width"], case .integer(let height)? = image.entries["Height"],
              ["Decode", "DecodeParms", "Mask", "ImageMask", "SMaskInData", "Alternates", "OC"].allSatisfy({ key in image.entries[key] == nil }),
              let colorSpaceRange = image.sourceRanges["ColorSpace"],
              let componentCount = componentCount(of: image.entries["ColorSpace"], dictionary: dictionary),
              let jpeg = jpegProperties(jpegData), jpeg.width == width, jpeg.height == height, jpeg.componentCount == componentCount
        else { return nil }
        if let softMask = image.entries["SMask"] {
            guard case .reference(let maskNumber) = softMask, isFullyOpaque(maskNumber, width: width, height: height, parsedObject: parsedObject, bytes: bytes) else {
                return nil
            }
        }
        let colorSpaceText = Data(UnsafeRawBufferPointer(rebasing: bytes[colorSpaceRange]))
        var colorSpaceReferences: [Int] = []
        image.entries["ColorSpace"]?.collectReferences(into: &colorSpaceReferences)
        var objectBytes = Data("\(number) \(generation) obj\n<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace ".utf8)
        objectBytes.append(colorSpaceText)
        let interpolation = image.entries["Interpolate"] == .boolean(true) ? " /Interpolate true" : ""
        objectBytes.append(Data(" /BitsPerComponent 8\(interpolation) /Filter /DCTDecode /Length \(jpegData.count) >>\nstream\n".utf8))
        objectBytes.append(jpegData)
        objectBytes.append(Data("\nendstream\nendobj\n".utf8))
        return PictureImageReplacement(objectBytes: objectBytes, references: colorSpaceReferences)
    }

    /// The color components of a device or ICC-based color space; nil for any other.
    private static func componentCount(of colorSpace: PDFSyntaxValue?, dictionary: (PDFSyntaxValue?) -> PDFSyntaxDictionary?) -> Int? {
        switch colorSpace {
        case .name("DeviceRGB")?: return 3
        case .name("DeviceGray")?: return 1
        case .array(let elements)? where elements.count == 2 && elements[0] == .name("ICCBased"):
            guard case .integer(let componentCount)? = dictionary(elements[1])?.entries["N"], componentCount == 1 || componentCount == 3 else { return nil }
            return componentCount
        default: return nil
        }
    }

    private static func jpegProperties(_ jpegData: Data) -> (width: Int, height: Int, componentCount: Int)? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue == 8,
              let colorModel = properties[kCGImagePropertyColorModel] as? String else { return nil }
        // CMYK and Lab JPEGs need decode arrays or color spaces of their own; they keep their pixels.
        if colorModel == kCGImagePropertyColorModelRGB as String { return (width, height, 3) }
        if colorModel == kCGImagePropertyColorModelGray as String { return (width, height, 1) }
        return nil
    }

    /// Whether a soft mask is one gray byte of 255 per pixel, so dropping it changes nothing.
    private static func isFullyOpaque(_ maskNumber: Int, width: Int, height: Int,
                                      parsedObject: (Int) -> (value: PDFSyntaxValue, streamDataStart: Int?)?, bytes: UnsafeRawBufferPointer) -> Bool {
        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow, pixelCount.partialValue <= maximumMaskPixelCount,
              let mask = parsedObject(maskNumber), case .dictionary(let maskDictionary) = mask.value, let dataStart = mask.streamDataStart,
              maskDictionary.entries["Filter"] == .name("FlateDecode"), maskDictionary.entries["DecodeParms"] == nil,
              maskDictionary.entries["Decode"] == nil, maskDictionary.entries["Matte"] == nil,
              maskDictionary.entries["BitsPerComponent"] == .integer(8), maskDictionary.entries["ColorSpace"] == .name("DeviceGray"),
              maskDictionary.entries["Width"] == .integer(width), maskDictionary.entries["Height"] == .integer(height),
              case .integer(let length)? = maskDictionary.entries["Length"], length > 0, dataStart + length <= bytes.count else { return false }
        let compressedMask = Data(UnsafeRawBufferPointer(rebasing: bytes[dataStart..<(dataStart + length)]))
        var isOpaque = true
        let decodedByteCount = PDFDrawingStreamDecoder.inflate(compressedMask, maximumDecodedBytes: pixelCount.partialValue, into: &isOpaque) { isOpaque, chunk in
            if isOpaque, chunk.contains(where: { byte in byte != 255 }) { isOpaque = false }
        }
        return decodedByteCount == pixelCount.partialValue && isOpaque
    }
}

/// A picture's annotation without the copy of the picture's bytes in PDFKit's markup data.
///
/// PDFKit writes an `/AAPL:AKExtras` dictionary into every annotation it creates, with a
/// copy of the whole annotation dictionary for Apple's markup tools, Graphite's picture
/// key included: the picture's base64 text was in the file twice. Readers, PDFKit
/// included, read the annotation's own keys, and PDFKit does not put the copy back when it
/// writes the annotation again. Apple's markup tools, should they rebuild the annotation
/// from their copy, would turn it into an ordinary stamp that still shows the picture.
private enum PictureMarkupCopyRemoval {
    private static let markupDataKey = "AAPL:AKExtras"
    private static let annotationCopyKey = "AAPL:AKPDFAnnotationDictionary"

    /// The annotations' new bytes, by object number.
    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?, bytes: UnsafeRawBufferPointer) -> [Int: Data] {
        var replacements: [Int: Data] = [:]
        for number in candidates {
            guard let object = objects(number) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj",
                  case .dictionary(let annotation)? = scanner.readValue(), scanner.streamDataStart(before: object.range.upperBound) == nil,
                  annotation.entries["GraphitePictureV1"] != nil,
                  case .dictionary(let markupData)? = annotation.entries[markupDataKey],
                  case .dictionary(let annotationCopy)? = markupData.entries[annotationCopyKey],
                  case .string? = annotationCopy.entries["GraphitePictureV1"],
                  let copyRange = annotationCopy.entryRanges["GraphitePictureV1"],
                  object.range.contains(copyRange.lowerBound), copyRange.upperBound <= object.range.upperBound else { continue }
            var objectBytes = Data(UnsafeRawBufferPointer(rebasing: bytes[object.range.lowerBound..<copyRange.lowerBound]))
            objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copyRange.upperBound..<object.range.upperBound])))
            replacements[number] = objectBytes
        }
        return replacements
    }
}

// MARK: Syntax

/// A PDF value as far as compaction needs it: strings keep their decoded bytes, numbers
/// that are not integers are not kept.
private indirect enum PDFSyntaxValue: Equatable {
    case integer(Int)
    case otherNumber
    case boolean(Bool)
    case null
    case name(String)
    case string(Data)
    case array([PDFSyntaxValue])
    case dictionary(PDFSyntaxDictionary)
    /// An indirect reference, by object number.
    case reference(Int)

    func collectReferences(into references: inout [Int]) {
        switch self {
        case .reference(let number): references.append(number)
        case .array(let elements): for element in elements { element.collectReferences(into: &references) }
        case .dictionary(let dictionary): for value in dictionary.entries.values { value.collectReferences(into: &references) }
        default: break
        }
    }
}

private struct PDFSyntaxDictionary: Equatable {
    var entries: [String: PDFSyntaxValue] = [:]
    /// Where each value's text is in the file.
    var sourceRanges: [String: Range<Int>] = [:]
    /// Where each key and its value are in the file, together.
    var entryRanges: [String: Range<Int>] = [:]
}

/// Reads PDF tokens and values from the file's bytes (ISO 32000-1, section 7.2 and 7.3).
private struct PDFSyntaxScanner {
    /// Arrays and dictionaries nested deeper than this are refused, so a damaged file
    /// cannot exhaust the stack.
    private static let maximumNesting = 256

    let bytes: UnsafeRawBufferPointer
    var position = 0

    init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 || byte == 0x0C || byte == 0x00
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "["), UInt8(ascii: "]"),
             UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "/"), UInt8(ascii: "%"): true
        default: false
        }
    }

    private static func isRegular(_ byte: UInt8) -> Bool { !isWhitespace(byte) && !isDelimiter(byte) }

    /// Moves past whitespace and comments and returns the new position.
    @discardableResult
    mutating func skipWhitespaceAndComments() -> Int {
        while position < bytes.count {
            let byte = bytes[position]
            if Self.isWhitespace(byte) {
                position += 1
            } else if byte == UInt8(ascii: "%") {
                while position < bytes.count, bytes[position] != 0x0A, bytes[position] != 0x0D { position += 1 }
            } else {
                break
            }
        }
        return position
    }

    /// The run of regular characters at the position, as text.
    mutating func readKeyword() -> String? {
        skipWhitespaceAndComments()
        let start = position
        while position < bytes.count, Self.isRegular(bytes[position]) { position += 1 }
        guard position > start else { return nil }
        return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<position]), as: UTF8.self)
    }

    mutating func readUnsignedInteger() -> Int? {
        skipWhitespaceAndComments()
        let start = position
        var number = 0
        while position < bytes.count, bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "9") {
            let (product, multiplicationOverflowed) = number.multipliedReportingOverflow(by: 10)
            let (sum, additionOverflowed) = product.addingReportingOverflow(Int(bytes[position] - UInt8(ascii: "0")))
            guard !multiplicationOverflowed, !additionOverflowed else { return nil }
            number = sum
            position += 1
        }
        guard position > start, position == bytes.count || !Self.isRegular(bytes[position]) else { return nil }
        return number
    }

    /// After an object's value: where its stream data starts, if a `stream` keyword follows.
    func streamDataStart(before end: Int) -> Int? {
        var scanner = self
        guard scanner.readKeyword() == "stream", scanner.position < end else { return nil }
        // The keyword is followed by CRLF or LF (a lone CR is tolerated).
        if scanner.position < end, bytes[scanner.position] == 0x0D { scanner.position += 1 }
        if scanner.position < end, bytes[scanner.position] == 0x0A { scanner.position += 1 }
        return scanner.position
    }

    mutating func readValue(nesting: Int = 0) -> PDFSyntaxValue? {
        guard nesting < Self.maximumNesting else { return nil }
        skipWhitespaceAndComments()
        guard position < bytes.count else { return nil }
        let byte = bytes[position]
        switch byte {
        case UInt8(ascii: "/"):
            return .name(readName())
        case UInt8(ascii: "("):
            return readLiteralString().map(PDFSyntaxValue.string)
        case UInt8(ascii: "<"):
            if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") { return readDictionary(nesting: nesting) }
            return readHexadecimalString().map(PDFSyntaxValue.string)
        case UInt8(ascii: "["):
            position += 1
            var elements: [PDFSyntaxValue] = []
            while true {
                skipWhitespaceAndComments()
                guard position < bytes.count else { return nil }
                if bytes[position] == UInt8(ascii: "]") { position += 1; return .array(elements) }
                guard let element = readValue(nesting: nesting + 1) else { return nil }
                elements.append(element)
            }
        default:
            return readNumberReferenceOrKeyword()
        }
    }

    private mutating func readDictionary(nesting: Int) -> PDFSyntaxValue? {
        position += 2
        var dictionary = PDFSyntaxDictionary()
        while true {
            skipWhitespaceAndComments()
            guard position + 1 < bytes.count else { return nil }
            if bytes[position] == UInt8(ascii: ">"), bytes[position + 1] == UInt8(ascii: ">") {
                position += 2
                return .dictionary(dictionary)
            }
            guard bytes[position] == UInt8(ascii: "/") else { return nil }
            let keyStart = position
            let key = readName()
            let valueStart = skipWhitespaceAndComments()
            guard let value = readValue(nesting: nesting + 1) else { return nil }
            dictionary.entries[key] = value
            dictionary.sourceRanges[key] = valueStart..<position
            dictionary.entryRanges[key] = keyStart..<position
        }
    }

    /// A name without its slash, with `#xx` escapes decoded.
    private mutating func readName() -> String {
        position += 1
        var nameBytes: [UInt8] = []
        while position < bytes.count, Self.isRegular(bytes[position]) {
            if bytes[position] == UInt8(ascii: "#"), position + 2 < bytes.count,
               let high = Self.hexadecimalDigit(bytes[position + 1]), let low = Self.hexadecimalDigit(bytes[position + 2]) {
                nameBytes.append(high << 4 | low)
                position += 3
            } else {
                nameBytes.append(bytes[position])
                position += 1
            }
        }
        return String(decoding: nameBytes, as: UTF8.self)
    }

    private static func hexadecimalDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// A parenthesized string, with balanced parentheses and escapes decoded.
    private mutating func readLiteralString() -> Data? {
        position += 1
        var stringBytes = Data()
        var depth = 1
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            switch byte {
            case UInt8(ascii: "("):
                depth += 1
                stringBytes.append(byte)
            case UInt8(ascii: ")"):
                depth -= 1
                if depth == 0 { return stringBytes }
                stringBytes.append(byte)
            case UInt8(ascii: "\\"):
                guard position < bytes.count else { return nil }
                let escaped = bytes[position]
                position += 1
                switch escaped {
                case UInt8(ascii: "n"): stringBytes.append(0x0A)
                case UInt8(ascii: "r"): stringBytes.append(0x0D)
                case UInt8(ascii: "t"): stringBytes.append(0x09)
                case UInt8(ascii: "b"): stringBytes.append(0x08)
                case UInt8(ascii: "f"): stringBytes.append(0x0C)
                case 0x0D:
                    // A line break after a backslash continues the string on the next line.
                    if position < bytes.count, bytes[position] == 0x0A { position += 1 }
                case 0x0A:
                    break
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var octalValue = Int(escaped - UInt8(ascii: "0"))
                    for _ in 0..<2 {
                        guard position < bytes.count, bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "7") else { break }
                        octalValue = octalValue * 8 + Int(bytes[position] - UInt8(ascii: "0"))
                        position += 1
                    }
                    stringBytes.append(UInt8(truncatingIfNeeded: octalValue))
                default:
                    stringBytes.append(escaped)
                }
            default:
                stringBytes.append(byte)
            }
        }
        return nil
    }

    private mutating func readHexadecimalString() -> Data? {
        position += 1
        var stringBytes = Data()
        var pendingHighDigit: UInt8?
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: ">") {
                if let pendingHighDigit { stringBytes.append(pendingHighDigit << 4) }
                return stringBytes
            }
            if Self.isWhitespace(byte) { continue }
            guard let digit = Self.hexadecimalDigit(byte) else { return nil }
            if let highDigit = pendingHighDigit {
                stringBytes.append(highDigit << 4 | digit)
                pendingHighDigit = nil
            } else {
                pendingHighDigit = digit
            }
        }
        return nil
    }

    /// A number, `true`, `false`, `null`, or a reference `12 0 R`.
    private mutating func readNumberReferenceOrKeyword() -> PDFSyntaxValue? {
        let start = position
        guard let token = readKeyword() else { return nil }
        switch token {
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        case "null": return .null
        default: break
        }
        guard let number = Int(token) else {
            // A real number; anything else (such as `R` or `obj` out of place) is not a value.
            guard token.allSatisfy({ character in character.isNumber || character == "." || character == "-" || character == "+" }),
                  token.contains(where: \.isNumber) else {
                position = start
                return nil
            }
            return .otherNumber
        }
        // A reference is two unsigned integers and `R`.
        guard number >= 0, !token.hasPrefix("+") else { return .integer(number) }
        let afterNumber = position
        if readUnsignedInteger() != nil, readKeyword() == "R" { return .reference(number) }
        position = afterNumber
        return .integer(number)
    }
}
