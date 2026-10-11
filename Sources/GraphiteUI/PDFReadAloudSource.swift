import Foundation
import PDFKit
import GraphiteCore

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
        let pageRange: NSRange
    }

    let text: String
    let segments: [Segment]

    static func page(_ text: String, pageIndex: Int) -> PDFReadAloudSource {
        let range = NSRange(location: 0, length: text.utf16.count)
        return PDFReadAloudSource(text: text, segments: [Segment(textRange: range, pageIndex: pageIndex, pageRange: range)])
    }

    @MainActor
    static func endpoint(in pdf: PDFSession, isEnd: Bool) throws -> PDFReadAloudEndpoint {
        guard pdf.document.allowsCopying else { throw GraphiteError.unavailable("This PDF does not allow text extraction.") }
        guard let selection = pdf.readAloudSelection else { throw ReadAloudError.emptyRange }
        let source = try Self.selection(selection, in: pdf.document)
        guard let segment = isEnd ? source.segments.last : source.segments.first else { throw ReadAloudError.emptyRange }
        return PDFReadAloudEndpoint(pageIndex: segment.pageIndex,
            offset: isEnd ? NSMaxRange(segment.pageRange) : segment.pageRange.location, revision: pdf.changeVersion)
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
            return PDFReadAloudHighlight(pageIndex: segment.pageIndex,
                characterRange: NSRange(location: segment.pageRange.location + intersection.location - segment.textRange.location, length: intersection.length),
                expectedText: source.substring(with: intersection))
        }
    }
}

struct PDFReadAloudHighlight: Equatable, Sendable {
    let pageIndex: Int
    let characterRange: NSRange
    let expectedText: String

    @MainActor
    func selection(in document: PDFDocument) -> PDFSelection? {
        guard let page = document.page(at: pageIndex), let pageText = page.string else { return nil }
        let source = pageText as NSString
        let range = characterRange
        guard page.numberOfCharacters == source.length, range.location >= 0, range.location <= source.length,
              range.length > 0, range.length <= source.length - range.location,
              source.rangeOfComposedCharacterSequences(for: range) == range,
              source.substring(with: range) == expectedText,
              let selection = page.selection(for: range), selection.string == expectedText else { return nil }
        return selection
    }
}

/// Owns only the temporary selections it adds. Search highlights and the user's
/// native selection survive updates and teardown; no PDF annotations are made.
@MainActor
final class PDFReadAloudHighlighter {
    private var selections: [PDFSelection] = []
    private var previousHighlights: [PDFReadAloudHighlight] = []

    func update(_ highlights: [PDFReadAloudHighlight], in view: PDFView, followsReading: Bool = false) {
        let existingSelections = view.highlightedSelections ?? []
        if highlights == previousHighlights,
           selections.allSatisfy({ readingSelection in existingSelections.contains { $0 === readingSelection } }) {
            if followsReading { revealWordIfNeeded(in: view) }
            return
        }
        var remainingSelections = existingSelections.filter { selection in !selections.contains { $0 === selection } }
        selections = highlights.compactMap { highlight in
            guard let document = view.document, let selection = highlight.selection(in: document) else { return nil }
            selection.color = .systemYellow.withAlphaComponent(0.4)
            return selection
        }
        previousHighlights = highlights
        remainingSelections.append(contentsOf: selections)
        view.highlightedSelections = remainingSelections.isEmpty ? nil : remainingSelections
        if followsReading { revealWordIfNeeded(in: view) }
    }

    func clear(in view: PDFView) { update([], in: view) }

    private func revealWordIfNeeded(in view: PDFView) {
        guard let selection = selections.first, let page = selection.pages.first,
              view.bounds.width > 32, view.bounds.height > 80,
              view.scaleFactor.isFinite, view.scaleFactor > 0 else { return }
        let wordBounds = view.convert(selection.bounds(for: page), from: page)
        if !view.bounds.insetBy(dx: 16, dy: 40).contains(wordBounds) {
            // go(to: selection) can leave the last pixels against the viewport's
            // edge. Request surrounding page space for comfortable screen margins.
            let destination = selection.bounds(for: page)
                .insetBy(dx: -16 / view.scaleFactor, dy: -40 / view.scaleFactor)
                .intersection(page.bounds(for: view.displayBox))
            if !destination.isEmpty { view.go(to: destination, on: page) }
        }
    }
}
