import Foundation
import CoreGraphics
import PDFKit
import Vision
import GraphiteCore

public enum PDFReadingOrder: String, CaseIterable, Sendable {
    case layout
    case file
}

public struct PDFReadingPageGeometry: Equatable, Sendable {
    public let mediaBounds: CGRect
    public let cropBounds: CGRect
    public let rotation: Int

    public init(mediaBounds: CGRect, cropBounds: CGRect, rotation: Int) {
        self.mediaBounds = mediaBounds
        self.cropBounds = cropBounds
        self.rotation = rotation
    }
}

public struct PDFRecognizedReading: Sendable {
    public struct Word: Sendable {
        public let textRange: NSRange
        public let pageBounds: CGRect
        public let confidence: Float
        public let isCorrected: Bool
    }
    public let geometry: PDFReadingPageGeometry
    public let words: [Word]
}

/// A disposable page snapshot. Speech ranges refer to `text`; each segment keeps
/// the original PDFKit coordinates, even when paragraphs change reading order.
public struct PDFReadAloudPage: Sendable {
    public struct Segment: Sendable {
        public let textRange: NSRange
        public let pageRange: NSRange
    }

    public let originalText: String
    public let text: String
    public let segments: [Segment]
    public let layoutNotice: String?
    public let usesLayout: Bool
    public let recognition: PDFRecognizedReading?

    init(originalText: String, text: String, segments: [Segment], layoutNotice: String?, usesLayout: Bool,
         recognition: PDFRecognizedReading? = nil) {
        self.originalText = originalText
        self.text = text
        self.segments = segments
        self.layoutNotice = layoutNotice
        self.usesLayout = usesLayout
        self.recognition = recognition
    }

    public func correctingRecognizedWords(_ corrections: [Int: String]) throws -> Self {
        guard let recognition else { throw ReadAloudError.sourceMappingUnavailable }
        guard corrections.keys.allSatisfy({ recognition.words.indices.contains($0) }) else { throw ReadAloudError.emptyRange }
        let source = text as NSString
        var correctedText = ""
        var correctedWords: [PDFRecognizedReading.Word] = []
        var sourceOffset = 0
        var correctedOffset = 0
        for (wordIndex, word) in recognition.words.enumerated() {
            try Task.checkCancellation()
            let separator = source.substring(with: NSRange(location: sourceOffset, length: word.textRange.location - sourceOffset))
            correctedText.append(separator)
            correctedOffset += separator.utf16.count
            let replacement = corrections[wordIndex]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? source.substring(with: word.textRange)
            guard !replacement.isEmpty, corrections[wordIndex] == nil || (replacement.utf16.count <= 256 &&
                  !replacement.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) })) else {
                throw GraphiteError.unavailable("Enter a word or short phrase on one line.")
            }
            guard correctedOffset <= ReadAloudDocument.maximumSourceUTF16Count - replacement.utf16.count else {
                throw ReadAloudError.passageTooLarge
            }
            correctedWords.append(.init(textRange: NSRange(location: correctedOffset, length: replacement.utf16.count),
                pageBounds: word.pageBounds, confidence: word.confidence, isCorrected: word.isCorrected || corrections[wordIndex] != nil))
            correctedText.append(replacement)
            correctedOffset += replacement.utf16.count
            sourceOffset = NSMaxRange(word.textRange)
        }
        correctedText.append(source.substring(from: sourceOffset))
        correctedOffset += source.length - sourceOffset
        guard correctedOffset <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        return Self(originalText: originalText, text: correctedText, segments: [], layoutNotice: layoutNotice,
                    usesLayout: usesLayout, recognition: .init(geometry: recognition.geometry, words: correctedWords))
    }

    /// Word identities survive temporary corrections, including replacements
    /// longer than the recognized word. Offsets belong to this exact snapshot.
    public func recognizedTextRange(words selectedWords: ClosedRange<Int>) throws -> NSRange {
        guard let recognition, recognition.words.indices.contains(selectedWords.lowerBound),
              recognition.words.indices.contains(selectedWords.upperBound) else { throw ReadAloudError.emptyRange }
        let first = recognition.words[selectedWords.lowerBound].textRange
        let last = recognition.words[selectedWords.upperBound].textRange
        guard first.location >= 0, NSMaxRange(last) <= text.utf16.count, NSMaxRange(last) > first.location else {
            throw ReadAloudError.sourceMappingUnavailable
        }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    public func selectedRange(startOffset: Int?, endOffset: Int?) throws -> NSRange {
        if recognition != nil {
            guard startOffset == nil, endOffset == nil else {
                throw GraphiteError.unavailable("A scanned page has no native text endpoints. Choose a passage in the recognized transcript.")
            }
            return NSRange(location: 0, length: text.utf16.count)
        }
        func boundary(_ originalOffset: Int, isEnd: Bool) throws -> Int {
            guard originalOffset >= 0, originalOffset <= originalText.utf16.count else {
                throw ReadAloudError.sourceMappingUnavailable
            }
            if !usesLayout { return originalOffset }
            let characterOffset = isEnd ? originalOffset - 1 : originalOffset
            guard let segment = segments.first(where: { NSLocationInRange(characterOffset, $0.pageRange) }) else {
                throw ReadAloudError.sourceMappingUnavailable
            }
            return segment.textRange.location + originalOffset - segment.pageRange.location
        }
        let start = try startOffset.map { try boundary($0, isEnd: false) } ?? 0
        let end = try endOffset.map { try boundary($0, isEnd: true) } ?? text.utf16.count
        guard end > start else { throw ReadAloudError.emptyRange }
        return NSRange(location: start, length: end - start)
    }

    fileprivate static func fileOrder(_ text: String, notice: String? = nil) -> Self {
        let range = NSRange(location: 0, length: text.utf16.count)
        return Self(originalText: text, text: text, segments: [Segment(textRange: range, pageRange: range)],
                    layoutNotice: notice, usesLayout: false)
    }
}

/// Owns all mutable PDFKit objects on its executor. Only one exported page and a
/// bounded raster are examined; no recognized words replace original PDF text.
public actor PDFReadAloudExtraction {
    private static let maximumRasterDimensionPixels = 2_048
    private static let maximumNativeWordCount = 16_384
    private static let maximumDetectedLineCount = 2_048

    private struct NativeWord {
        let range: NSRange
        let imageBounds: CGRect
    }

    private struct PageRaster {
        let image: CGImage
        let drawingTransform: CGAffineTransform
        let geometry: PDFReadingPageGeometry
    }

    public init() {}

    public func page(in pageBytes: Data, readingOrder: PDFReadingOrder) async throws -> PDFReadAloudPage {
        try Task.checkCancellation()
        guard let document = PDFDocument(data: pageBytes) else { throw ReadAloudError.noReadableText }
        guard document.allowsCopying else { throw GraphiteError.unavailable("This PDF does not allow text extraction.") }
        guard let page = document.page(at: 0) else { throw ReadAloudError.noReadableText }
        let text = page.string ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await recognizedPage(page, originalText: text, readingOrder: readingOrder)
        }
        guard text.utf16.count <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        guard readingOrder == .layout else { return .fileOrder(text) }
        do {
            return try await layoutPage(page, originalText: text)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return .fileOrder(text, notice: "This page’s layout could not be matched safely. It uses the file’s text order; review the transcript or select a passage.")
        }
    }

    private func layoutPage(_ page: PDFPage, originalText: String) async throws -> PDFReadAloudPage {
        guard page.numberOfCharacters == originalText.utf16.count else {
            throw ReadAloudError.sourceMappingUnavailable
        }
        let raster = try render(page)
        let image = raster.image
        let imageWidth = image.width
        let imageHeight = image.height
        let words = try nativeWords(in: page, text: originalText, drawingTransform: raster.drawingTransform)
        var request = RecognizeDocumentsRequest()
        request.barcodeDetectionOptions.enabled = false
        request.textRecognitionOptions.useLanguageCorrection = false
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        guard observations.count == 1, let observation = observations.first,
              observation.document.tables.isEmpty else { throw ReadAloudError.sourceMappingUnavailable }
        let lines = observation.document.paragraphs.flatMap(\.lines)
        guard !lines.isEmpty, lines.count <= Self.maximumDetectedLineCount else { throw ReadAloudError.sourceMappingUnavailable }
        let lineBounds = lines.map { line in
            line.boundingBox.toImageCoordinates(CGSize(width: imageWidth, height: imageHeight))
        }
        var lineWords = [[NativeWord]](repeating: [], count: lines.count)
        for word in words {
            try Task.checkCancellation()
            let area = word.imageBounds.width * word.imageBounds.height
            guard area.isFinite, area > 0 else { throw ReadAloudError.sourceMappingUnavailable }
            let matches = lineBounds.enumerated().compactMap { lineIndex, bounds -> (Int, CGFloat)? in
                let overlap = bounds.insetBy(dx: -2, dy: -2).intersection(word.imageBounds)
                guard !overlap.isNull, !overlap.isEmpty else { return nil }
                return (lineIndex, overlap.width * overlap.height / area)
            }.sorted { $0.1 > $1.1 }
            guard let best = matches.first, best.1 >= 0.5,
                  matches.count == 1 || best.1 > matches[1].1 * 1.5 else { throw ReadAloudError.sourceMappingUnavailable }
            lineWords[best.0].append(word)
        }
        // Every native token must occur once. Unmatched/ambiguous content or a
        // detected table falls back as a whole, rather than silently disappearing.
        let source = originalText as NSString
        var orderedText = ""
        var segments: [PDFReadAloudPage.Segment] = []
        var textLength = 0
        for paragraph in lineWords where !paragraph.isEmpty {
            if !orderedText.isEmpty { orderedText.append("\n"); textLength += 1 }
            for (wordIndex, word) in paragraph.sorted(by: { $0.range.location < $1.range.location }).enumerated() {
                if wordIndex > 0 { orderedText.append(" "); textLength += 1 }
                segments.append(.init(textRange: NSRange(location: textLength, length: word.range.length), pageRange: word.range))
                orderedText.append(source.substring(with: word.range))
                textLength += word.range.length
            }
        }
        guard segments.count == words.count, textLength <= ReadAloudDocument.maximumSourceUTF16Count else {
            throw ReadAloudError.sourceMappingUnavailable
        }
        return PDFReadAloudPage(originalText: originalText, text: orderedText, segments: segments,
                               layoutNotice: "Layout reading uses on-device paragraph detection and the PDF’s original words. Review columns and equations before playing.",
                               usesLayout: true)
    }

    private func render(_ page: PDFPage, ignoringPageRotation: Bool = false) throws -> PageRaster {
        try Task.checkCancellation()
        guard let pageReference = page.pageRef else { throw ReadAloudError.sourceMappingUnavailable }
        let cropBounds = pageReference.getBoxRect(.cropBox)
        guard cropBounds.origin.x.isFinite, cropBounds.origin.y.isFinite,
              cropBounds.width.isFinite, cropBounds.height.isFinite,
              cropBounds.width > 0, cropBounds.height > 0 else { throw ReadAloudError.sourceMappingUnavailable }
        let isQuarterTurn = !ignoringPageRotation && abs(page.rotation % 180) == 90
        let width = isQuarterTurn ? cropBounds.height : cropBounds.width
        let height = isQuarterTurn ? cropBounds.width : cropBounds.height
        let scale = CGFloat(Self.maximumRasterDimensionPixels) / max(width, height)
        guard scale.isFinite else { throw ReadAloudError.sourceMappingUnavailable }
        let imageWidth = max(1, min(Self.maximumRasterDimensionPixels, Int(ceil(width * scale))))
        let imageHeight = max(1, min(Self.maximumRasterDimensionPixels, Int(ceil(height * scale))))
        let imageBounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        guard let context = CGContext(data: nil, width: imageWidth, height: imageHeight, bitsPerComponent: 8,
                                      bytesPerRow: imageWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ReadAloudError.sourceMappingUnavailable
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(imageBounds)
        // getDrawingTransform centers small pages without enlarging them. Apply
        // raster resolution explicitly, retaining its crop/rotation transform.
        let pageTransform = pageReference.getDrawingTransform(.cropBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: ignoringPageRotation ? Int32(-(page.rotation % 360)) : 0, preserveAspectRatio: true)
        let drawingTransform = pageTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        context.concatenate(drawingTransform)
        context.drawPDFPage(pageReference)
        guard let image = context.makeImage() else { throw ReadAloudError.sourceMappingUnavailable }
        return PageRaster(image: image, drawingTransform: drawingTransform,
            geometry: .init(mediaBounds: page.bounds(for: .mediaBox), cropBounds: page.bounds(for: .cropBox), rotation: page.rotation))
    }

    private func recognizedPage(_ page: PDFPage, originalText: String, readingOrder: PDFReadingOrder) async throws -> PDFReadAloudPage {
        // Cancel the display rotation for recognition; inverse geometry still
        // returns unrotated PDF page coordinates for PDFView to display correctly.
        let raster = try render(page, ignoringPageRotation: true)
        let lines: [RecognizedTextObservation]
        let usesLayout: Bool
        if readingOrder == .layout {
            var request = RecognizeDocumentsRequest()
            request.barcodeDetectionOptions.enabled = false
            request.textRecognitionOptions.useLanguageCorrection = false
            let observations = try await request.perform(on: raster.image)
            lines = observations.first?.document.text.lines ?? []
            usesLayout = true
        } else {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            lines = try await request.perform(on: raster.image)
            usesLayout = false
        }
        try Task.checkCancellation()
        guard !lines.isEmpty else { throw ReadAloudError.noReadableText }
        guard lines.count <= Self.maximumDetectedLineCount else { throw ReadAloudError.passageTooLarge }
        let imageSize = CGSize(width: raster.image.width, height: raster.image.height)
        let inverseTransform = raster.drawingTransform.inverted()
        let expression = try NSRegularExpression(pattern: "\\S+")
        var recognizedText = ""
        var textLength = 0
        var words: [PDFRecognizedReading.Word] = []
        for line in lines {
            try Task.checkCancellation()
            guard let candidate = line.topCandidates(1).first else { throw ReadAloudError.noReadableText }
            let lineText = candidate.string
            guard textLength + lineText.utf16.count + 1 <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
            if !recognizedText.isEmpty { recognizedText.append("\n"); textLength += 1 }
            for match in expression.matches(in: lineText, range: NSRange(location: 0, length: lineText.utf16.count)) {
                guard words.count < Self.maximumNativeWordCount, let stringRange = Range(match.range, in: lineText),
                      let region = candidate.boundingBox(for: stringRange) else { throw ReadAloudError.sourceMappingUnavailable }
                let normalizedBounds = region.boundingBox.cgRect
                let imageBounds = CGRect(x: normalizedBounds.minX * imageSize.width, y: normalizedBounds.minY * imageSize.height,
                    width: normalizedBounds.width * imageSize.width, height: normalizedBounds.height * imageSize.height)
                let pageBounds = imageBounds.applying(inverseTransform).intersection(raster.geometry.cropBounds)
                guard !pageBounds.isNull, !pageBounds.isEmpty, pageBounds.origin.x.isFinite, pageBounds.origin.y.isFinite,
                      pageBounds.width.isFinite, pageBounds.height.isFinite,
                      candidate.confidence.isFinite, (0...1).contains(candidate.confidence) else {
                    throw ReadAloudError.sourceMappingUnavailable
                }
                words.append(.init(textRange: NSRange(location: textLength + match.range.location, length: match.range.length),
                                   pageBounds: pageBounds, confidence: candidate.confidence, isCorrected: false))
            }
            recognizedText.append(lineText)
            textLength += lineText.utf16.count
        }
        guard !words.isEmpty else { throw ReadAloudError.noReadableText }
        return PDFReadAloudPage(originalText: originalText, text: recognizedText, segments: [],
            layoutNotice: "Text recognized on this device from a scanned page. Check the transcript before Play; every scanned page pauses for review. Equations may be incorrect. Corrections stay temporary." +
                (usesLayout ? "" : " Recognized line order is used; check columns carefully."),
            usesLayout: usesLayout, recognition: .init(geometry: raster.geometry, words: words))
    }

    private func nativeWords(in page: PDFPage, text: String, drawingTransform: CGAffineTransform) throws -> [NativeWord] {
        var words: [NativeWord] = []
        let source = text as NSString
        // Whitespace boundaries retain punctuation, signs and non-Latin text.
        // Foundation word segmentation alone would discard mathematical symbols.
        let expression = try NSRegularExpression(pattern: "\\S+")
        var extractionError: Error?
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            do {
                try Task.checkCancellation()
                guard let range = match?.range, words.count < Self.maximumNativeWordCount,
                      source.rangeOfComposedCharacterSequences(for: range) == range,
                      let selection = page.selection(for: range), selection.string == source.substring(with: range) else {
                    throw ReadAloudError.sourceMappingUnavailable
                }
                let bounds = selection.bounds(for: page).applying(drawingTransform)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                    throw ReadAloudError.sourceMappingUnavailable
                }
                words.append(NativeWord(range: range, imageBounds: bounds))
            } catch { extractionError = error; stop.pointee = true }
        }
        if let extractionError { throw extractionError }
        return words
    }
}
