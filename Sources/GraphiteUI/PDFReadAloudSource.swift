import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

struct PDFReadAloudEndpoint: Equatable, Sendable {
    let pageIndex: Int
    /// UTF-16 boundary, inclusive for a start and exclusive for an end.
    let offset: Int
    let revision: Int
}

struct PDFReadAloudRange: Sendable {
    let start: PDFReadAloudEndpoint
    let end: PDFReadAloudEndpoint?
}

/// Immutable coordinates captured before narration. Each piece refers to the
/// actual selected occurrence, never a later search for matching words.
struct PDFReadAloudSource: Sendable {
    struct Segment: Sendable {
        let textRange: NSRange
        let pageIndex: Int
        let location: PDFReadAloudHighlight.Location

        var pageRange: NSRange? {
            if case .characters(let range) = location { return range }
            return nil
        }

        init(textRange: NSRange, pageIndex: Int, pageRange: NSRange) {
            self.textRange = textRange
            self.pageIndex = pageIndex
            location = .characters(pageRange)
        }

        init(textRange: NSRange, pageIndex: Int, location: PDFReadAloudHighlight.Location) {
            self.textRange = textRange
            self.pageIndex = pageIndex
            self.location = location
        }
    }

    let text: String
    let segments: [Segment]

    static func page(_ text: String, pageIndex: Int) -> PDFReadAloudSource {
        let range = NSRange(location: 0, length: text.utf16.count)
        return PDFReadAloudSource(text: text, segments: [Segment(textRange: range, pageIndex: pageIndex, pageRange: range)])
    }

    static func page(_ snapshot: PDFReadAloudPage, pageIndex: Int) -> PDFReadAloudSource {
        if let recognition = snapshot.recognition {
            return PDFReadAloudSource(text: snapshot.text, segments: recognition.words.map { word in
                Segment(textRange: word.textRange, pageIndex: pageIndex,
                        location: .recognizedText(word.pageBounds, recognition.geometry))
            })
        }
        return PDFReadAloudSource(text: snapshot.text, segments: snapshot.segments.map { segment in
            Segment(textRange: segment.textRange, pageIndex: pageIndex, pageRange: segment.pageRange)
        })
    }

    @MainActor
    static func endpoint(in pdf: PDFSession, isEnd: Bool) throws -> PDFReadAloudEndpoint {
        guard pdf.document.allowsCopying else { throw GraphiteError.unavailable("This PDF does not allow text extraction.") }
        guard let selection = pdf.readAloudSelection else { throw ReadAloudError.emptyRange }
        let source = try Self.selection(selection, in: pdf.document)
        guard let segment = isEnd ? source.segments.last : source.segments.first,
              let pageRange = segment.pageRange else { throw ReadAloudError.emptyRange }
        return PDFReadAloudEndpoint(pageIndex: segment.pageIndex,
            offset: isEnd ? NSMaxRange(pageRange) : pageRange.location, revision: pdf.changeVersion)
    }

    @MainActor
    static func selection(_ selection: PDFSelection, in document: PDFDocument) throws -> PDFReadAloudSource {
        // A native selection can cover an entire book. Bound the capture as well
        // as the eventual speech text, and retain no live PDFKit objects.
        guard selection.pages.count <= 256 else { throw ReadAloudError.passageTooLarge }
        var text = ""
        var textLength = 0
        var segments: [Segment] = []
        for page in selection.pages {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound, let pageText = page.string else { throw ReadAloudError.sourceMappingUnavailable }
            let source = pageText as NSString
            guard source.length <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
            // PDFKit's character indexing can differ for unusual encodings. Do
            // not treat those coordinates as UTF-16 without checking them.
            guard page.numberOfCharacters == source.length else { throw ReadAloudError.sourceMappingUnavailable }
            let rangeCount = selection.numberOfTextRanges(on: page)
            guard rangeCount <= 4_096, segments.count <= 4_096 - rangeCount else { throw ReadAloudError.passageTooLarge }
            for rangeIndex in 0..<rangeCount {
                let range = selection.range(at: rangeIndex, on: page)
                guard range.location >= 0, range.location <= source.length, range.length > 0,
                      range.length <= source.length - range.location,
                      source.rangeOfComposedCharacterSequences(for: range) == range else { throw ReadAloudError.sourceMappingUnavailable }
                let selectedText = source.substring(with: range)
                guard page.selection(for: range)?.string == selectedText else { throw ReadAloudError.sourceMappingUnavailable }
                let separatorLength = text.isEmpty ? 0 : 1
                guard textLength + separatorLength <= ReadAloudDocument.maximumSourceUTF16Count - range.length else { throw ReadAloudError.passageTooLarge }
                if separatorLength > 0 { text.append("\n"); textLength += 1 }
                segments.append(Segment(textRange: NSRange(location: textLength, length: range.length), pageIndex: pageIndex, pageRange: range))
                text.append(selectedText)
                textLength += range.length
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReadAloudError.noReadableText }
        return PDFReadAloudSource(text: text, segments: segments)
    }

    func highlights(for range: NSRange) -> [PDFReadAloudHighlight] {
        let source = text as NSString
        guard range.location >= 0, range.location <= source.length, range.length > 0,
              range.length <= source.length - range.location else { return [] }
        return segments.compactMap { segment in
            let intersection = NSIntersectionRange(range, segment.textRange)
            guard intersection.length > 0 else { return nil }
            switch segment.location {
            case .characters(let pageRange):
                return PDFReadAloudHighlight(pageIndex: segment.pageIndex,
                    characterRange: NSRange(location: pageRange.location + intersection.location - segment.textRange.location, length: intersection.length),
                    expectedText: source.substring(with: intersection))
            case .recognizedText:
                return PDFReadAloudHighlight(pageIndex: segment.pageIndex, location: segment.location,
                    expectedText: source.substring(with: segment.textRange))
            }
        }
    }
}

struct PDFReadAloudHighlight: Equatable, Sendable {
    enum Location: Equatable, Sendable {
        case characters(NSRange)
        case recognizedText(CGRect, PDFReadingPageGeometry)
    }
    let pageIndex: Int
    let location: Location
    let expectedText: String

    var characterRange: NSRange? {
        if case .characters(let range) = location { return range }
        return nil
    }

    init(pageIndex: Int, characterRange: NSRange, expectedText: String) {
        self.init(pageIndex: pageIndex, location: .characters(characterRange), expectedText: expectedText)
    }

    init(pageIndex: Int, location: Location, expectedText: String) {
        self.pageIndex = pageIndex
        self.location = location
        self.expectedText = expectedText
    }

    @MainActor
    func selection(in document: PDFDocument) -> PDFSelection? {
        guard let range = characterRange, let page = document.page(at: pageIndex), let pageText = page.string else { return nil }
        let source = pageText as NSString
        guard page.numberOfCharacters == source.length, range.location >= 0, range.location <= source.length,
              range.length > 0, range.length <= source.length - range.location,
              source.rangeOfComposedCharacterSequences(for: range) == range,
              source.substring(with: range) == expectedText,
              let selection = page.selection(for: range), selection.string == expectedText else { return nil }
        return selection
    }

    @MainActor
    func pageBounds(in document: PDFDocument) -> CGRect? {
        guard let page = document.page(at: pageIndex) else { return nil }
        switch location {
        case .characters: return selection(in: document)?.bounds(for: page)
        case .recognizedText(let bounds, let geometry):
            // PDFKit may populate transient Live Text after showing a scan.
            // Image anchors depend on the validated page revision/geometry,
            // rather than whether PDFKit currently exposes recognized text.
            guard page.bounds(for: .mediaBox) == geometry.mediaBounds, page.bounds(for: .cropBox) == geometry.cropBounds,
                  page.rotation == geometry.rotation, !bounds.isEmpty, !bounds.isNull,
                  bounds.origin.x.isFinite, bounds.origin.y.isFinite, bounds.width.isFinite, bounds.height.isFinite,
                  geometry.cropBounds.contains(bounds) else { return nil }
            return bounds
        }
    }
}

/// Owns only the temporary selections it adds. Search highlights and the user's
/// native selection survive updates and teardown; no PDF annotations are made.
@MainActor
final class PDFReadAloudHighlighter {
    private var selections: [PDFSelection] = []
    private var previousHighlights: [PDFReadAloudHighlight] = []
    private var recognizedOverlay: PDFRecognizedReadingOverlay?
    private weak var highlightedDocument: PDFDocument?

    func update(_ highlights: [PDFReadAloudHighlight], in view: PDFView, followsReading: Bool = false) {
        let existingSelections = view.highlightedSelections ?? []
        if highlights == previousHighlights, highlightedDocument === view.document,
           selections.allSatisfy({ readingSelection in existingSelections.contains { $0 === readingSelection } }) {
            refreshGeometry(in: view)
            if followsReading { revealWordIfNeeded(in: view) }
            return
        }
        var remainingSelections = existingSelections.filter { selection in !selections.contains { $0 === selection } }
        selections = highlights.compactMap { highlight in
            guard let document = view.document, let selection = highlight.selection(in: document) else { return nil }
            selection.color = ReadAloudHighlightStyle.fill
            return selection
        }
        previousHighlights = highlights
        highlightedDocument = view.document
        remainingSelections.append(contentsOf: selections)
        view.highlightedSelections = remainingSelections.isEmpty ? nil : remainingSelections
        let recognizedHighlights = highlights.filter { if case .recognizedText = $0.location { return true }; return false }
        if recognizedHighlights.isEmpty {
            recognizedOverlay?.removeFromSuperview()
            recognizedOverlay = nil
        } else {
            let overlay = recognizedOverlay ?? PDFRecognizedReadingOverlay()
            recognizedOverlay = overlay
            overlay.update(recognizedHighlights, in: view)
        }
        if followsReading { revealWordIfNeeded(in: view) }
    }

    func clear(in view: PDFView) { update([], in: view) }

    func refreshGeometry(in view: PDFView) {
        guard highlightedDocument === view.document else {
            recognizedOverlay?.removeFromSuperview()
            recognizedOverlay = nil
            return
        }
        recognizedOverlay?.update(previousHighlights.filter { if case .recognizedText = $0.location { return true }; return false }, in: view)
    }

    private func revealWordIfNeeded(in view: PDFView) {
        guard let document = view.document, let highlight = previousHighlights.first,
              let page = document.page(at: highlight.pageIndex), let bounds = highlight.pageBounds(in: document),
              view.bounds.width > 32, view.bounds.height > 80,
              view.scaleFactor.isFinite, view.scaleFactor > 0 else { return }
        let wordBounds = view.convert(bounds, from: page)
        if !view.bounds.insetBy(dx: 16, dy: 40).contains(wordBounds) {
            // go(to: selection) can leave the last pixels against the viewport's
            // edge. Request surrounding page space for comfortable screen margins.
            let destination = bounds
                .insetBy(dx: -16 / view.scaleFactor, dy: -40 / view.scaleFactor)
                .intersection(page.bounds(for: view.displayBox))
            if !destination.isEmpty { view.go(to: destination, on: page) }
        }
    }
}
