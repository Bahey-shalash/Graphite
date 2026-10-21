import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why scanned pages could not become a PDF.
public enum ScannedDocumentError: Error, Equatable, Sendable {
    case noPages
    case pageHasNoPixels(pageIndex: Int)
    case pageImageEncodingFailed(pageIndex: Int)
    case pdfWritingFailed
}

/// A finished scan: the PDF's bytes and what happened to each page's text.
public struct ScannedDocumentPDF: Sendable {
    public let data: Data
    public let pageCount: Int
    public let recognizedWordCount: Int
    /// The pages whose text recognition failed. They are in the PDF as pictures only, so a
    /// search cannot find their words.
    public let pageIndicesWithoutRecognizedText: [Int]
}

/// Turns the pages of a document scan into one ordinary PDF: each page is the scanned
/// picture, JPEG-compressed, at A4 width and the picture's own proportions, with an invisible
/// text layer from on-device recognition laid over the words. Any PDF reader can select and
/// search that text; Graphite's vault index does not read PDF text yet.
///
/// An actor, so recognition, JPEG encoding and PDF writing run on its own executor and never
/// on the main actor (`FR-103`); the work stops at the next page when the calling task is
/// cancelled, and nothing is written anywhere: the caller receives the bytes.
public actor ScannedDocumentPDFBuilder {
    public static let pageWidthPoints: CGFloat = 595
    /// PDF readers do not handle pages taller than this (the PDF 1.7 limit of 200 inches).
    public static let maximumPageHeightPoints: CGFloat = 14_400
    public static let jpegCompressionQuality: CGFloat = 0.8

    private static let textFontName = "Helvetica"
    /// How much of a word's box height the letters fill, and how far above the box's bottom
    /// their baseline sits, so selecting the text highlights roughly the printed word.
    private static let letterHeightFraction: CGFloat = 0.8
    private static let baselineHeightFraction: CGFloat = 0.2

    private let wordRecognizer: ScannedPageWordRecognizer

    public init(wordRecognizer: ScannedPageWordRecognizer) {
        self.wordRecognizer = wordRecognizer
    }

    public func build(pageImages: [CGImage]) async throws -> ScannedDocumentPDF {
        guard !pageImages.isEmpty else { throw ScannedDocumentError.noPages }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: nil,
                                      [kCGPDFContextCreator: "Graphite"] as CFDictionary) else {
            throw ScannedDocumentError.pdfWritingFailed
        }
        var recognizedWordCount = 0
        var pageIndicesWithoutText: [Int] = []
        for (pageIndex, pageImage) in pageImages.enumerated() {
            try Task.checkCancellation()
            let words = try await recognizedWords(on: pageImage)
            try Task.checkCancellation()
            if let words { recognizedWordCount += words.count } else { pageIndicesWithoutText.append(pageIndex) }
            try Self.writePage(of: pageImage, pageIndex: pageIndex, words: words ?? [], to: context)
        }
        context.closePDF()
        return ScannedDocumentPDF(data: output as Data, pageCount: pageImages.count, recognizedWordCount: recognizedWordCount,
                                  pageIndicesWithoutRecognizedText: pageIndicesWithoutText)
    }

    /// The page's words, or nil when recognition failed: the page is then written as a picture
    /// without text rather than losing the scan. Cancellation is not a failure and propagates.
    private func recognizedWords(on pageImage: CGImage) async throws -> [ScannedPageWord]? {
        do {
            return try await wordRecognizer.recognizeWords(pageImage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    // MARK: Writing a page

    private static func writePage(of pageImage: CGImage, pageIndex: Int, words: [ScannedPageWord], to context: CGContext) throws {
        let pageSize = try self.pageSize(for: pageImage, pageIndex: pageIndex)
        let compressedPicture = try compressedPicture(of: pageImage, pageIndex: pageIndex)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        context.beginPage(mediaBox: &mediaBox)
        // A picture made from JPEG bytes goes into the PDF as those bytes, not re-encoded.
        context.draw(compressedPicture, in: mediaBox)
        drawInvisibleText(for: words, pageSize: pageSize, in: context)
        context.endPage()
    }

    /// A4's width and the picture's proportions, so a landscape or oddly cropped scan is not
    /// squeezed onto a sheet of another shape.
    static func pageSize(for pageImage: CGImage, pageIndex: Int) throws -> CGSize {
        guard pageImage.width > 0, pageImage.height > 0 else { throw ScannedDocumentError.pageHasNoPixels(pageIndex: pageIndex) }
        let height = pageWidthPoints * CGFloat(pageImage.height) / CGFloat(pageImage.width)
        return CGSize(width: pageWidthPoints, height: min(max(height, 1), maximumPageHeightPoints))
    }

    private static func compressedPicture(of pageImage: CGImage, pageIndex: Int) throws -> CGImage {
        let jpegData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil),
              let opaqueImage = opaqueCopy(of: pageImage) else {
            throw ScannedDocumentError.pageImageEncodingFailed(pageIndex: pageIndex)
        }
        CGImageDestinationAddImage(destination, opaqueImage,
                                   [kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: jpegData),
              let compressedPicture = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                              intent: .defaultIntent) else {
            throw ScannedDocumentError.pageImageEncodingFailed(pageIndex: pageIndex)
        }
        return compressedPicture
    }

    /// JPEG has no transparency: a picture with an alpha channel is flattened onto white first.
    private static func opaqueCopy(of pageImage: CGImage) -> CGImage? {
        switch pageImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return pageImage
        case .premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly: break
        @unknown default: break
        }
        guard let context = CGContext(data: nil, width: pageImage.width, height: pageImage.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pageImage.width, height: pageImage.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(pageImage, in: bounds)
        return context.makeImage()
    }

    // MARK: The invisible text layer

    /// Draws each word in the invisible text rendering mode (it marks nothing, but is real
    /// text for readers), as tall as the printed word and spaced so it is as wide: the font
    /// size comes from the box's height and the letters are spread (or squeezed) with a kern.
    /// A text matrix that stretches the glyphs does not do it: the glyph positions CoreText
    /// lays out stay unscaled, and PDFKit then selects only the unstretched width.
    private static func drawInvisibleText(for words: [ScannedPageWord], pageSize: CGSize, in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for word in words {
            let wordBox = CGRect(x: word.normalizedBounds.minX * pageSize.width, y: word.normalizedBounds.minY * pageSize.height,
                                 width: word.normalizedBounds.width * pageSize.width, height: word.normalizedBounds.height * pageSize.height)
            guard wordBox.width >= 1, wordBox.height >= 1, wordBox.minX.isFinite, wordBox.minY.isFinite else { continue }
            let font = CTFontCreateWithName(textFontName as CFString, wordBox.height * letterHeightFraction, nil)
            let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
            let naturalLine = CTLineCreateWithAttributedString(NSAttributedString(string: word.text, attributes: [fontAttribute: font]))
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(naturalLine, nil, nil, nil))
            let letterGapCount = word.text.count - 1
            // The kern follows every letter, so the last one is left out to end on the box's edge.
            let kern = letterGapCount > 0 ? (wordBox.width - naturalWidth) / CGFloat(letterGapCount) : 0
            let spacedLine = CTLineCreateWithAttributedString(NSAttributedString(string: word.text, attributes: [
                fontAttribute: font, NSAttributedString.Key(kCTKernAttributeName as String): kern,
            ]))
            context.textMatrix = CGAffineTransform(translationX: wordBox.minX, y: wordBox.minY + wordBox.height * baselineHeightFraction)
            CTLineDraw(spacedLine, context)
        }
        context.restoreGState()
    }
}
