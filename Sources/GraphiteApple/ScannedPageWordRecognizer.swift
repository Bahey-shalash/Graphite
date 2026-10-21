import CoreGraphics
import Foundation
import Vision

/// One recognized word of a scanned page, located on the page.
public struct ScannedPageWord: Equatable, Sendable {
    public let text: String
    /// The word's box as fractions of the page's width and height, measured from the page's
    /// bottom left, the same orientation as a PDF page.
    public let normalizedBounds: CGRect

    public init(text: String, normalizedBounds: CGRect) {
        self.text = text
        self.normalizedBounds = normalizedBounds
    }
}

/// Finds the words on one scanned page image. A struct of one closure because the builder
/// needs exactly one capability: tests give it a recognizer with known words, so the PDF's
/// text layer is checked without the machine's text models (`FR-53`).
public struct ScannedPageWordRecognizer: Sendable {
    /// Most words one page keeps, so a page of noise cannot grow the text layer without bound.
    public static let maximumWordsPerPage = 20_000

    public let recognizeWords: @Sendable (CGImage) async throws -> [ScannedPageWord]

    public init(recognizeWords: @escaping @Sendable (CGImage) async throws -> [ScannedPageWord]) {
        self.recognizeWords = recognizeWords
    }

    /// Vision's on-device recognition at the accurate level with language correction, the
    /// language detected from the page. Throws when recognition itself fails, and
    /// `CancellationError` when the calling task is cancelled.
    public static let onDevice = ScannedPageWordRecognizer { pageImage in
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let lines = try await request.perform(on: pageImage)
        var words: [ScannedPageWord] = []
        for line in lines {
            try Task.checkCancellation()
            guard let candidate = line.topCandidates(1).first else { continue }
            let lineText = candidate.string
            for wordRange in wordRanges(in: lineText) {
                guard words.count < maximumWordsPerPage else { return words }
                guard let region = candidate.boundingBox(for: wordRange) else { continue }
                let normalizedBounds = region.boundingBox.cgRect
                guard normalizedBounds.origin.x.isFinite, normalizedBounds.origin.y.isFinite,
                      normalizedBounds.width.isFinite, normalizedBounds.height.isFinite else { continue }
                words.append(ScannedPageWord(text: String(lineText[wordRange]), normalizedBounds: normalizedBounds))
            }
        }
        return words
    }

    /// The runs of characters between whitespace, so punctuation stays with its word and the
    /// text layer reads like the page.
    static func wordRanges(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var wordStart: String.Index?
        for index in line.indices {
            if line[index].isWhitespace {
                if let start = wordStart { ranges.append(start..<index) }
                wordStart = nil
            } else if wordStart == nil {
                wordStart = index
            }
        }
        if let start = wordStart { ranges.append(start..<line.endIndex) }
        return ranges
    }
}
