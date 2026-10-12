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
    /// A page whose text was extracted from an exported copy. PDFKit often extracts a page's
    /// text a little differently once it is saved again (a figure's labels in another order,
    /// a space more or less), and an exact comparison then disabled every highlight on the
    /// page: the owner's papers showed no word highlight at all. The exported text is aligned
    /// to the live page's text instead; every word whose characters are unchanged keeps its
    /// exact place, and only the changed stretches lose their highlight. Nil when too little
    /// of the page matches to trust it.
    static func page(_ snapshot: PDFReadAloudPage, pageIndex: Int, livePageText: String) -> PDFReadAloudSource? {
        if snapshot.recognition != nil || livePageText == snapshot.originalText { return page(snapshot, pageIndex: pageIndex) }
        let exported = Array(snapshot.originalText.utf16)
        let live = Array(livePageText.utf16)
        guard exported.count <= 200_000, live.count <= 200_000 else { return nil }
        // Unchanged characters of the exported text, paired with their live offsets.
        var liveOffsetByExportedOffset = [Int](repeating: -1, count: exported.count)
        let difference = live.difference(from: exported)
        var removedExported = Set<Int>()
        var insertedLive = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedExported.insert(offset)
            case .insert(let offset, _, _): insertedLive.insert(offset)
            }
        }
        var liveOffset = 0
        for exportedOffset in exported.indices where !removedExported.contains(exportedOffset) {
            while insertedLive.contains(liveOffset) { liveOffset += 1 }
            liveOffsetByExportedOffset[exportedOffset] = liveOffset
            liveOffset += 1
        }
        let matched = liveOffsetByExportedOffset.filter { offset in offset >= 0 }.count
        guard !exported.isEmpty, Double(matched) / Double(exported.count) >= 0.8 else { return nil }
        var segments: [Segment] = []
        for segment in snapshot.segments {
            // Split each piece into runs that map to consecutive live characters.
            var runStart: Int?
            func closeRun(at end: Int) {
                guard let start = runStart else { return }
                let pageStart = segment.pageRange.location + start
                let livePageStart = liveOffsetByExportedOffset[pageStart]
                segments.append(Segment(textRange: NSRange(location: segment.textRange.location + start, length: end - start),
                                        pageIndex: pageIndex, pageRange: NSRange(location: livePageStart, length: end - start)))
                runStart = nil
            }
            for offset in 0..<segment.pageRange.length {
                let exportedOffset = segment.pageRange.location + offset
                let mapped = exportedOffset < exported.count ? liveOffsetByExportedOffset[exportedOffset] : -1
                if mapped < 0 {
                    closeRun(at: offset)
                } else if let start = runStart, liveOffsetByExportedOffset[segment.pageRange.location + offset - 1] + 1 != mapped || offset == start {
                    if offset != start { closeRun(at: offset); runStart = offset }
                } else if runStart == nil {
                    runStart = offset
                }
            }
            closeRun(at: segment.pageRange.length)
        }
        return PDFReadAloudSource(text: snapshot.text, segments: segments)
    }

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
              let selection = page.selection(for: range),
              // Across a line break PDFKit may return the selection's text with other spacing.
              selection.string.map(Self.withoutWhitespace) == Self.withoutWhitespace(expectedText) else { return nil }
        return selection
    }

    private static func withoutWhitespace(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in !CharacterSet.whitespacesAndNewlines.contains(scalar) })
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

    /// The word being read, in the view's coordinates.
    func highlightFrame(in view: PDFView) -> CGRect? {
        guard let document = view.document, let highlight = previousHighlights.first,
              let page = document.page(at: highlight.pageIndex), let bounds = highlight.pageBounds(in: document) else { return nil }
        return view.convert(bounds, from: page)
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
