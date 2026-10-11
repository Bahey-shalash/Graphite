import Foundation
import Observation
import PDFKit
import GraphiteCore
import GraphiteApple

/// One reading session per window, independent of document navigation. Only a
/// selected PDF page's text is retained; the next page is loaded after completion.
@MainActor @Observable
final class ReadAloudController {
    let session: ReadAloudSession
    var showsReader = false
    var followsReading = true
    private(set) var isPreparing = false
    private(set) var title = "Read Aloud"
    private(set) var scopeDescription = ""
    private(set) var sourceIdentifier: String?
    private(set) var sourcePageIndex: Int?
    private(set) var errorMessage: String?
    private(set) var sourceHighlightNotice: String?
    private var pdfSource: PDFReadAloudSource?
    private weak var sourcePDF: PDFSession?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var preparationIdentifier: UUID?
    @ObservationIgnored private var pdfContinuation: (() -> Void)?

    init(session: ReadAloudSession = ReadAloudSession()) {
        self.session = session
        session.didFinishDocument = { [weak self] in self?.continuePDFIfNeeded() }
    }

    func readMarkdown(_ markdown: String, path: VaultPath, range: NSRange? = nil,
                      scope: String = "Whole note", paletteHexByName: [String: String] = [:]) {
        begin(title: path.stem, sourceIdentifier: path.rawValue, scope: scope)
        let identifier = preparationIdentifier
        preparation = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try ReadAloudDocument.markdown(markdown, selectedRange: range, paletteHexByName: paletteHexByName)
            }
            do {
                let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, identifier == self.preparationIdentifier, !Task.isCancelled else { return }
                self.finishPreparing(document)
            } catch { self?.failed(error, identifier: identifier) }
        }
    }

    func readPDF(_ pdf: PDFSession, firstPageIndex: Int, lastPageIndex: Int) {
        begin(title: pdf.location.deletingPathExtension().lastPathComponent,
              sourceIdentifier: pdf.location.path, scope: "Pages \(firstPageIndex + 1)–\(lastPageIndex + 1)")
        guard firstPageIndex >= 0, lastPageIndex >= firstPageIndex, lastPageIndex < pdf.pageCount else {
            failed(ReadAloudError.emptyRange, identifier: preparationIdentifier); return
        }
        guard pdf.document.allowsCopying else {
            failed(GraphiteError.unavailable("This PDF does not allow text extraction."), identifier: preparationIdentifier); return
        }
        guard !pdf.document.isEncrypted else {
            failed(GraphiteError.unavailable("Page reading for encrypted PDFs is not available yet. Select text in the unlocked PDF and choose Read Selection."), identifier: preparationIdentifier); return
        }
        sourcePDF = pdf
        loadPDFPage(pdf, pageIndex: firstPageIndex, lastPageIndex: lastPageIndex)
    }

    func readPDFSelection(_ pdf: PDFSession) {
        begin(title: pdf.location.deletingPathExtension().lastPathComponent,
              sourceIdentifier: pdf.location.path, scope: "Selected PDF text")
        guard pdf.document.allowsCopying else {
            failed(GraphiteError.unavailable("This PDF does not allow text extraction."), identifier: preparationIdentifier); return
        }
        let source: PDFReadAloudSource
        do {
            guard let selection = pdf.readAloudSelection else { throw ReadAloudError.emptyRange }
            source = try PDFReadAloudSource.selection(selection, in: pdf.document)
        } catch { failed(error, identifier: preparationIdentifier); return }
        sourcePDF = pdf
        let revision = pdf.changeVersion
        let identifier = preparationIdentifier
        preparation = Task { [weak self] in
            do {
                let worker = Task.detached(priority: .userInitiated) { try ReadAloudDocument.plainText(source.text) }
                let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, identifier == self.preparationIdentifier, !Task.isCancelled else { return }
                guard revision == pdf.changeVersion else { self.documentDidChange(pdf.location.path); return }
                self.pdfSource = source
                self.finishPreparing(document)
            } catch { self?.failed(error, identifier: identifier) }
        }
    }

    func readPDFRange(_ pdf: PDFSession, start: PDFReadAloudEndpoint, end: PDFReadAloudEndpoint? = nil) {
        begin(title: pdf.location.deletingPathExtension().lastPathComponent, sourceIdentifier: pdf.location.path,
              scope: end == nil ? "From selected word to end" : "Chosen start and end")
        guard pdf.document.allowsCopying, !pdf.document.isEncrypted else {
            failed(GraphiteError.unavailable("Choose Read Selection for an unlocked encrypted PDF. Page-range extraction is unavailable."), identifier: preparationIdentifier); return
        }
        guard start.revision == pdf.changeVersion, end == nil || end?.revision == pdf.changeVersion else {
            failed(GraphiteError.unavailable("The PDF changed. Choose the reading start and end again."), identifier: preparationIdentifier); return
        }
        let lastPageIndex = end?.pageIndex ?? pdf.pageCount - 1
        guard start.pageIndex >= 0, start.pageIndex < pdf.pageCount, start.offset >= 0,
              lastPageIndex >= start.pageIndex, lastPageIndex < pdf.pageCount,
              end == nil || (end?.offset ?? 0) > 0,
              lastPageIndex != start.pageIndex || (end?.offset ?? Int.max) > start.offset else {
            failed(ReadAloudError.emptyRange, identifier: preparationIdentifier); return
        }
        sourcePDF = pdf
        loadPDFPage(pdf, pageIndex: start.pageIndex, lastPageIndex: lastPageIndex, range: PDFReadAloudRange(start: start, end: end))
    }

    func readPDFFromSelection(_ pdf: PDFSession) {
        do { readPDFRange(pdf, start: try PDFReadAloudSource.endpoint(in: pdf, isEnd: false)) }
        catch {
            begin(title: pdf.location.deletingPathExtension().lastPathComponent, sourceIdentifier: pdf.location.path, scope: "From selected word")
            failed(error, identifier: preparationIdentifier)
        }
    }

    func documentDidChange(_ identifier: String) {
        guard sourceIdentifier == identifier else { return }
        stop()
        session.clear()
        errorMessage = "The document changed. Choose the passage again to read the current version."
    }

    func stop() {
        preparationIdentifier = nil
        preparation?.cancel()
        preparation = nil
        isPreparing = false
        pdfContinuation = nil
        session.stop()
    }

    func clear() { stop(); session.clear(); sourceIdentifier = nil; sourcePageIndex = nil; showsReader = false }

    func continuePDFIfNeeded() {
        guard session.state == .finished, let continuation = pdfContinuation else { return }
        pdfContinuation = nil
        continuation()
    }

    func highlight(in path: VaultPath) -> NSRange? {
        guard sourceIdentifier == path.rawValue, session.state == .speaking || session.state == .paused else { return nil }
        return session.sourceRange
    }

    func highlights(in pdf: PDFSession) -> [PDFReadAloudHighlight] {
        guard sourcePDF === pdf, session.state == .speaking || session.state == .paused,
              let range = session.sourceRange else { return [] }
        return pdfSource?.highlights(for: range) ?? []
    }

    func suspendFollowing() { followsReading = false }

    func shouldFollow(_ pdf: PDFSession) -> Bool {
        sourcePDF === pdf && followsReading && session.state == .speaking
    }

    var canShowPDFPassage: Bool {
        guard let pdf = sourcePDF, let view = pdf.pdfView else { return false }
        return view.document === pdf.document && pdfSource != nil && !isPreparing && errorMessage == nil
    }

    /// Explicit navigation leaves manual scrolling alone during narration.
    func showPDFPassage() -> Bool {
        guard canShowPDFPassage, let pdf = sourcePDF, let view = pdf.pdfView else { return false }
        let selection = PDFSelection(document: pdf.document)
        for highlight in highlights(in: pdf) {
            if let word = highlight.selection(in: pdf.document) { selection.add(word) }
        }
        if !selection.pages.isEmpty {
            view.go(to: selection)
        } else if let pageIndex = pdfSource?.segments.first?.pageIndex, let page = pdf.document.page(at: pageIndex) {
            view.go(to: page)
        } else { return false }
        return true
    }

    private func begin(title: String, sourceIdentifier: String, scope: String) {
        stop()
        session.clear()
        self.title = title
        self.sourceIdentifier = sourceIdentifier
        scopeDescription = scope
        sourcePageIndex = nil
        sourcePDF = nil
        pdfSource = nil
        sourceHighlightNotice = nil
        errorMessage = nil
        isPreparing = true
        showsReader = true
        preparationIdentifier = UUID()
        session.refreshVoices()
    }

    private func loadPDFPage(_ pdf: PDFSession, pageIndex: Int, lastPageIndex: Int,
                             range: PDFReadAloudRange? = nil, playsWhenReady: Bool = false) {
        let identifier = preparationIdentifier
        let revision = pdf.changeVersion
        isPreparing = true
        pdfSource = nil
        sourcePageIndex = pageIndex
        scopeDescription = "Page \(pageIndex + 1) · reading through page \(lastPageIndex + 1)"
        preparation = Task { [weak self] in
            do {
                let pageText = try await pdf.readAloudText(pageIndex: pageIndex)
                let worker = Task.detached(priority: .userInitiated) {
                    let selectedRange: NSRange?
                    if let range {
                        let startOffset = pageIndex == range.start.pageIndex ? range.start.offset : 0
                        let endOffset = pageIndex == range.end?.pageIndex ? range.end?.offset ?? 0 : pageText.utf16.count
                        guard endOffset > startOffset else { throw ReadAloudError.emptyRange }
                        selectedRange = NSRange(location: startOffset, length: endOffset - startOffset)
                    } else { selectedRange = nil }
                    return try ReadAloudDocument.plainText(pageText, selectedRange: selectedRange)
                }
                let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, identifier == self.preparationIdentifier, !Task.isCancelled else { return }
                guard revision == pdf.changeVersion else { self.documentDidChange(pdf.location.path); return }
                guard !document.passages.isEmpty else { throw ReadAloudError.noReadableText }
                // The export is read off the main actor. Verify its coordinates
                // against this one live page before permitting source highlights.
                if let page = pdf.document.page(at: pageIndex), page.numberOfCharacters == pageText.utf16.count, page.string == pageText {
                    self.pdfSource = .page(pageText, pageIndex: pageIndex)
                    self.sourceHighlightNotice = nil
                } else {
                    if range != nil { throw ReadAloudError.sourceMappingUnavailable }
                    self.sourceHighlightNotice = "This page’s text positions could not be matched safely. Follow the highlighted transcript instead."
                }
                if pageIndex < lastPageIndex {
                    self.pdfContinuation = { [weak self, pdf] in self?.loadPDFPage(pdf, pageIndex: pageIndex + 1, lastPageIndex: lastPageIndex, range: range, playsWhenReady: true) }
                }
                self.finishPreparing(document)
                if playsWhenReady { self.session.play() }
            } catch { self?.failed(error, identifier: identifier) }
        }
    }

    private func finishPreparing(_ document: ReadAloudDocument) {
        isPreparing = false
        preparation = nil
        session.load(document)
        // The user reviews the range and voice first. Reading begins with Play.
    }

    private func failed(_ error: Error, identifier: UUID?) {
        guard identifier == preparationIdentifier, !Task.isCancelled else { return }
        isPreparing = false
        preparation = nil
        pdfContinuation = nil
        errorMessage = error.localizedDescription
    }
}

private actor PDFReadAloudExtraction {
    func text(in bytes: Data) throws -> String {
        try Task.checkCancellation()
        guard let document = PDFDocument(data: bytes), let page = document.page(at: 0), let text = page.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReadAloudError.noReadableText }
        guard text.utf16.count <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        return text
    }
}

extension PDFSession {
    func readAloudText(pageIndex: Int) async throws -> String {
        guard document.allowsCopying else { throw GraphiteError.unavailable("This PDF does not allow text extraction.") }
        let pageBytes = try await export(pages: [pageIndex])
        return try await PDFReadAloudExtraction().text(in: pageBytes)
    }
}
