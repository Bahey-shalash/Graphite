import Foundation
import ImageIO
import CoreGraphics
import GraphiteCore
#if canImport(UIKit)
import UIKit
import PencilKit
#endif

/// What the drawing editor produces: PencilKit strokes on a canvas of a fixed width.
public struct DrawingContent: Sendable {
    public let strokeData: Data
    public let canvasWidth: Double
    public let background: DrawingBackground
    public init(strokeData: Data, canvasWidth: Double, background: DrawingBackground) {
        self.strokeData = strokeData
        self.canvasWidth = canvasWidth
        self.background = background
    }
}

/// A drawing file whose embedded stroke data is current and can be edited again.
public struct EditableDrawing: Sendable {
    public let format: DrawingFormat
    public let payload: DrawingPayload
    public let revision: FileRevision
}

public enum DrawingMetadataReader {
    /// Base64 text of the largest payload `DrawingPayload.encoded()` produces. Metadata
    /// text longer than this is refused before it is decoded.
    static let maximumBase64PayloadBytes = (DrawingLimits.maximumPayloadBytes + 2) / 3 * 4

    /// Reads editing metadata from any supported drawing format, by file extension.
    public static func readMetadata(_ fileData: Data, format: DrawingFormat) throws -> DrawingMetadataReading {
        switch format {
        case .png:
            let decodedImage = try GraphitePNG.decode(fileData)
            return DrawingMetadataReading(payload: decodedImage.drawing, metadataWasDiscarded: decodedImage.metadataWasDiscarded)
        case .svg: return SVGDrawingFile.readMetadata(fileData)
        case .pdf: return PDFDrawingFile.readMetadata(fileData)
        }
    }

    /// Whether the file is a Graphite drawing whose strokes can still be edited. Reads the
    /// file synchronously; call it off the main actor.
    ///
    /// Embeds call this for every image they show, so it avoids reading what cannot
    /// matter: a PNG without a `grPK` chunk is answered from its chunk headers, a PDF is
    /// opened lazily, and no revision digest is computed because nothing is written.
    public static func hasEditableStrokes(at location: URL) -> Bool {
        readMetadata(at: location)?.payload != nil
    }

    /// The editing metadata of a drawing file, read as cheaply as `hasEditableStrokes(at:)`
    /// reads it. Nil when the file is not a drawing format or cannot be read. Reads the
    /// file synchronously; call it off the main actor.
    public static func readMetadata(at location: URL) -> DrawingMetadataReading? {
        guard let format = DrawingFormat(fileExtension: location.pathExtension) else { return nil }
        var reading: DrawingMetadataReading?
        var coordinationError: NSError?
        AtomicFileWriter().makeCoordinator().coordinate(readingItemAt: location, options: [], error: &coordinationError) { readableLocation in
            reading = readMetadata(atCoordinatedLocation: readableLocation, format: format)
        }
        return coordinationError == nil ? reading : nil
    }

    private static func readMetadata(atCoordinatedLocation location: URL, format: DrawingFormat) -> DrawingMetadataReading? {
        guard let fileSize = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maximumFileBytes(for: format) else { return nil }
        switch format {
        case .pdf:
            return PDFDrawingFile.readMetadata(at: location)
        case .png:
            guard pngHasDrawingChunk(at: location) else { return DrawingMetadataReading(payload: nil, metadataWasDiscarded: false) }
            fallthrough
        case .svg:
            guard let fileData = try? Data(contentsOf: location) else { return nil }
            return try? readMetadata(fileData, format: format)
        }
    }

    /// Walks the PNG chunk headers, seeking past chunk data, and reports whether a `grPK`
    /// chunk comes before `IEND`. False only where `GraphitePNG.decode` would also find no
    /// editing data, so it can short-circuit the full read.
    static func pngHasDrawingChunk(at location: URL) -> Bool {
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let chunkHeaderLength = 8, chunkLengthAndChecksumLength: UInt64 = 12, maximumChunkCount = 100_000
        guard let fileHandle = try? FileHandle(forReadingFrom: location) else { return false }
        defer { try? fileHandle.close() }
        guard let fileSignature = try? fileHandle.read(upToCount: signature.count), fileSignature == signature else { return false }
        var chunkOffset = UInt64(signature.count)
        for _ in 0..<maximumChunkCount {
            guard let header = try? fileHandle.read(upToCount: chunkHeaderLength), header.count == chunkHeaderLength else { return false }
            let dataLength = header.prefix(4).reduce(UInt64(0)) { total, byte in total << 8 | UInt64(byte) }
            switch String(decoding: header.suffix(4), as: UTF8.self) {
            case "grPK": return true
            case "IEND": return false
            default: break
            }
            chunkOffset += chunkLengthAndChecksumLength + dataLength
            guard (try? fileHandle.seek(toOffset: chunkOffset)) != nil else { return false }
        }
        return false
    }

    public static func maximumFileBytes(for format: DrawingFormat) -> Int {
        switch format {
        case .png: GraphitePNG.maximumFileBytes
        case .svg: SVGDrawingFile.maximumFileBytes
        case .pdf: PDFDrawingFile.maximumFileBytes
        }
    }
}

#if canImport(UIKit)
public actor DrawingFileService {
    private let writer: AtomicFileWriter
    public init(writer: AtomicFileWriter = AtomicFileWriter()) { self.writer = writer }

    /// Encodes a complete, ordinary file with optional re-editing metadata.
    public func fileData(for content: DrawingContent, format: DrawingFormat) throws -> Data {
        guard content.canvasWidth.isFinite, content.canvasWidth > 0, content.canvasWidth <= DrawingLimits.maximumCanvasWidth,
              content.strokeData.count <= DrawingLimits.maximumStrokeBytes else {
            throw GraphiteError.oversized("This drawing exceeds the supported canvas size. Your strokes are still open.")
        }
        let originalDrawing = try PKDrawing(data: content.strokeData)
        let exportBounds = DrawingCanvasGeometry.exportBounds(inkBounds: originalDrawing.strokes.isEmpty ? nil : originalDrawing.bounds, canvasWidth: content.canvasWidth)
        guard exportBounds.width <= DrawingLimits.maximumCanvasWidth, exportBounds.height <= DrawingLimits.maximumCanvasHeight else {
            throw GraphiteError.oversized("This drawing is taller than Graphite can save as one file. Your strokes are still open.")
        }
        // Store strokes relative to the saved region so re-editing shows what was saved.
        let drawing = originalDrawing.transformed(using: CGAffineTransform(translationX: -exportBounds.minX, y: -exportBounds.minY))
        let payload = DrawingPayload(width: exportBounds.width, height: exportBounds.height, background: content.background, strokes: drawing.dataRepresentation())
        switch format {
        case .png:
            let encodedImage = try pngImage(for: drawing, size: exportBounds.size, background: content.background)
            let fileData = try GraphitePNG.encode(imageData: encodedImage.pngData, drawing: payload)
            // An ordinary decoder must see the same picture, not merely accept the file:
            // an extended-range bitmap taller than 32,768 pixels once encoded as solid black.
            guard BandedPNGEncoder.decodedContentMatches(fileData, reference: encodedImage.reference) else {
                throw GraphiteError.invalidFile("The drawing failed ordinary PNG decoder verification. Nothing was saved.")
            }
            try verifyEditingData(in: fileData, format: format, payload: payload)
            return fileData
        case .svg:
            let fileData = try SVGDrawingFile.encode(PencilVectorConverter.vectorDrawing(from: drawing, size: exportBounds.size, background: content.background), payload: payload)
            try verifyEditingData(in: fileData, format: format, payload: payload)
            return fileData
        case .pdf:
            // `encode` reads the finished file back and checks its strokes and digest.
            return try PDFDrawingFile.encode(PencilVectorConverter.vectorDrawing(from: drawing, size: exportBounds.size, background: content.background), payload: payload)
        }
    }

    private func verifyEditingData(in fileData: Data, format: DrawingFormat, payload: DrawingPayload) throws {
        guard try DrawingMetadataReader.readMetadata(fileData, format: format).payload?.strokes == payload.strokes else {
            throw GraphiteError.invalidFile("The drawing's editing data could not be verified. Nothing was saved.")
        }
    }

    public func save(_ content: DrawingContent, format: DrawingFormat, to destination: URL, expecting: WriteExpectation) throws -> FileRevision {
        let encodedFile = try fileData(for: content, format: format)
        return try writer.write(encodedFile, to: destination, expecting: expecting)
    }

    /// Opens a drawing for editing, or explains why its strokes cannot be edited.
    public func openForEditing(_ location: URL) throws -> EditableDrawing {
        guard let format = DrawingFormat(fileExtension: location.pathExtension) else {
            throw GraphiteError.unavailable("Graphite drawings are PNG, PDF, or SVG files.")
        }
        let snapshot = try writer.read(location, maximumBytes: DrawingMetadataReader.maximumFileBytes(for: format))
        let reading = try DrawingMetadataReader.readMetadata(snapshot.data, format: format)
        guard let payload = reading.payload else {
            throw GraphiteError.unavailable(reading.metadataWasDiscarded
                ? "This drawing was changed by another app, so its Pencil strokes can no longer be edited. The file itself is intact."
                : "This file has no editable Pencil strokes. It is an ordinary \(format.rawValue.uppercased()) file.")
        }
        return EditableDrawing(format: format, payload: payload, revision: snapshot.revision)
    }

    /// Renders one horizontal band at a time and streams it into the PNG encoder, so peak
    /// memory is about one band rather than the whole bitmap (up to 192 MB at 48 MP).
    private func pngImage(for drawing: PKDrawing, size: CGSize, background: DrawingBackground) throws -> BandedPNGEncoder.EncodedImage {
        guard let scale = DrawingCanvasGeometry.pngScale(for: size),
              let raster = BandedPNGEncoder.Raster(size: size, preferredScale: scale, isOpaque: background == .white) else {
            throw GraphiteError.oversized("This drawing is too large for a sharp PNG. Save it as PDF or SVG instead. Your strokes are still open.")
        }
        let lightAppearance = UITraitCollection(userInterfaceStyle: .light)
        return try BandedPNGEncoder.encode(raster) { bandIndex in
            var bandImage: CGImage?
            autoreleasepool {
                lightAppearance.performAsCurrent {
                    bandImage = drawing.image(from: raster.bandRectangle(at: bandIndex), scale: raster.scale).cgImage
                }
            }
            guard let bandImage else { throw GraphiteError.invalidFile("Cannot encode the drawing image. Your strokes are still open.") }
            return bandImage
        }
    }
}
#endif

public actor ImageFileService {
    public init() {}

    /// Downsampled display pixels as PNG data, rather than a potentially enormous source
    /// image. PDF and SVG drawings created by Graphite are rendered from their vector content.
    public func thumbnailData(at location: URL, maximumDimension: Int = 1800) async throws -> Data {
        let limit = PreviewPixelLimit(maximumPixelDimension: maximumDimension)
        return try await withDecodingSlot {
            try ImageEncoding.pngData(from: previewImage(at: location, limit: limit))
        }
    }

    /// The same pixels as `thumbnailData`, already decoded for display. Views should
    /// prefer this: encoding a preview to PNG and decoding it again took most of the
    /// time of showing a photo.
    public func displayImage(at location: URL, maximumPixelDimension: Int) async throws -> CGImage {
        try await displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: maximumPixelDimension))
    }

    /// Decoded pixels no larger than the place the image is shown needs: an embed shown at
    /// the width of a note's column is decoded at that width, not at the longest side the
    /// limit allows.
    public func displayImage(at location: URL, limit: PreviewPixelLimit) async throws -> CGImage {
        try await withDecodingSlot { try previewImage(at: location, limit: limit) }
    }

    /// Whether a PDF is a Graphite drawing (and so should be shown inline like an image).
    public func isEditableDrawingPDF(at location: URL) -> Bool {
        PDFDrawingFile.readMetadata(at: location).payload != nil
    }

    /// Each `ImageFileService` is its own actor, and a note creates one per embed, so the
    /// decode budget is shared through `ImageDecodingLimiter`.
    private func withDecodingSlot<Output>(_ decode: () throws -> Output) async throws -> Output {
        await ImageDecodingLimiter.shared.acquire()
        let outcome: Result<Output, any Error> = Task.isCancelled ? .failure(CancellationError()) : Result { try decode() }
        await ImageDecodingLimiter.shared.release()
        return try outcome.get()
    }

    private func previewImage(at location: URL, limit: PreviewPixelLimit) throws -> CGImage {
        switch location.pathExtension.lowercased() {
        case "svg":
            let fileData = try AtomicFileWriter().read(location, maximumBytes: SVGDrawingFile.maximumFileBytes).data
            let drawing = try SVGDrawingFile.vectorDrawing(from: fileData)
            return try VectorDrawingRenderer.image(for: drawing, maximumPixelDimension: limit.longestPixelSide(forWidth: drawing.size.width, height: drawing.size.height))
        case "pdf":
            return try firstPDFPageImage(at: location, limit: limit)
        default:
            // Decoding immediately keeps the work here, off the main actor, instead of at
            // first draw.
            guard let source = CGImageSourceCreateWithURL(location as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.longestPixelSide(of: source, limit: limit),
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw GraphiteError.invalidFile("Cannot preview this image.") }
            return image
        }
    }

    /// The longest side to decode a raster image with, from its header: its width and height
    /// as shown, after its EXIF orientation, which the thumbnail applies.
    private static func longestPixelSide(of source: CGImageSource, limit: PreviewPixelLimit) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let storedHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            return limit.maximumPixelDimension
        }
        // Orientations 5 to 8 turn the image a quarter, so its stored width is shown as height.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let isQuarterTurned = (5...8).contains(orientation)
        return limit.longestPixelSide(forWidth: isQuarterTurned ? storedHeight : storedWidth, height: isQuarterTurned ? storedWidth : storedHeight)
    }

    /// The first page as every PDF viewer shows it: its crop box, turned by its `/Rotate`.
    private func firstPDFPageImage(at location: URL, limit: PreviewPixelLimit) throws -> CGImage {
        guard let document = CGPDFDocument(location as CFURL), let page = document.page(at: 1) else {
            throw GraphiteError.invalidFile("Cannot preview this PDF.")
        }
        let pageBox = page.getBoxRect(.cropBox)
        let isQuarterTurned = (((Int(page.rotationAngle) % 360) + 360) % 360) % 180 != 0
        let displayedSize = isQuarterTurned ? CGSize(width: pageBox.height, height: pageBox.width) : pageBox.size
        let longestSide = max(displayedSize.width, displayedSize.height)
        guard longestSide > 0 else { throw GraphiteError.invalidFile("This PDF page has no size.") }
        let maximumPixelDimension = limit.longestPixelSide(forWidth: displayedSize.width, height: displayedSize.height)
        let scale = min(2, Double(maximumPixelDimension) / longestSide)
        let pixelWidth = max(1, Int((displayedSize.width * scale).rounded())), pixelHeight = max(1, Int((displayedSize.height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GraphiteError.unavailable("Cannot allocate the PDF preview.")
        }
        context.scaleBy(x: scale, y: scale)
        // A target exactly the displayed size makes this transform only the page's
        // rotation and crop-box offset; it never scales up, so scaling is applied above.
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: displayedSize), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw GraphiteError.unavailable("Cannot render the PDF preview.") }
        return image
    }
}

/// How many pixels a preview is decoded with. A preview needs no more pixels than the place
/// it is shown: a photo shown across a note's column needs the column's width in pixels,
/// and decoding it larger only costs time and memory.
public struct PreviewPixelLimit: Hashable, Sendable {
    /// Below this, a preview is too coarse to show, even as a thumbnail.
    static let smallestPixelDimension = 64
    /// Above this, a preview costs more memory than any screen needs.
    static let largestPixelDimension = 4096

    /// The longest side, in pixels, whatever the image's shape.
    public let maximumPixelDimension: Int
    /// The widest the image is shown, in pixels; nil when only the longest side is bounded.
    public let displayPixelWidth: Int?

    public init(maximumPixelDimension: Int, displayPixelWidth: Int? = nil) {
        self.maximumPixelDimension = min(max(maximumPixelDimension, Self.smallestPixelDimension), Self.largestPixelDimension)
        self.displayPixelWidth = displayPixelWidth.map { width in max(width, 1) }
    }

    /// The longest side to decode an image of this shape with. An image shown at
    /// `displayPixelWidth` needs that width, so a tall one needs a longer side than a wide
    /// one; the result never exceeds `maximumPixelDimension`.
    public func longestPixelSide(forWidth width: Double, height: Double) -> Int {
        guard let displayPixelWidth, width.isFinite, height.isFinite, width > 0, height > 0 else { return maximumPixelDimension }
        let longestSideAtDisplayWidth = (Double(displayPixelWidth) * max(width, height) / width).rounded(.up)
        guard longestSideAtDisplayWidth < Double(maximumPixelDimension) else { return maximumPixelDimension }
        return max(Self.smallestPixelDimension, Int(longestSideAtDisplayWidth))
    }
}

/// Bounds how many previews decode at once across the app. Opening a note full of photos
/// started every decode together (20 photos peaked at 1.4 GB), and quality of service
/// alone is not a memory budget.
actor ImageDecodingLimiter {
    static let shared = ImageDecodingLimiter(maximumConcurrentDecodes: 2)

    private let maximumConcurrentDecodes: Int
    private var activeDecodeCount = 0
    private var waitingDecodes: [CheckedContinuation<Void, Never>] = []

    init(maximumConcurrentDecodes: Int) {
        self.maximumConcurrentDecodes = max(1, maximumConcurrentDecodes)
    }

    func acquire() async {
        guard activeDecodeCount >= maximumConcurrentDecodes else {
            activeDecodeCount += 1
            return
        }
        await withCheckedContinuation { continuation in waitingDecodes.append(continuation) }
    }

    /// Hands the slot straight to the longest-waiting decode, if any.
    func release() {
        if waitingDecodes.isEmpty {
            activeDecodeCount -= 1
        } else {
            waitingDecodes.removeFirst().resume()
        }
    }
}
