import Foundation
import Observation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif
import GraphiteCore
import GraphiteApple

private struct ReadAloudMarkdownRequest {
    let sourceText: String
    let path: VaultPath
    let selectedRange: NSRange?
    let scopeDescription: String
    let paletteHexByName: [String: String]
    var hiddenRanges: [NSRange] = []
}

private struct ReadAloudPDFRequest {
    let lastPageIndex: Int
    let range: PDFReadAloudRange?
}

/// One reading session per window, independent of document navigation. Only a
/// selected PDF page's text is retained; the next page is loaded after completion.
@MainActor @Observable
final class ReadAloudController {
    let session: ReadAloudSession
    var showsReader = false
    var followsReading = true
    /// The open vault's folder, where `.graphite/pronunciations.json` may add pronunciations.
    @ObservationIgnored var vaultRoot: URL?
    private(set) var stopIdentifier = UUID()
    private(set) var isPreparing = false
    private(set) var title = "Read Aloud"
    private(set) var scopeDescription = ""
    private(set) var sourceIdentifier: String?
    private(set) var sourcePageIndex: Int?
    private(set) var errorMessage: String?
    private(set) var sourceHighlightNotice: String?
    private(set) var mathematicalStyle: MathematicalSpeechStyle
    private(set) var pdfReadingOrder: PDFReadingOrder
    private(set) var recognizedPDFPage: PDFReadAloudPage?
    private(set) var recognizedPageIdentifier: UUID?
    private(set) var recognizedWordRange: ClosedRange<Int>?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let markdownPreparation = ReadAloudMarkdownPreparation()
    @ObservationIgnored private var markdownRequest: ReadAloudMarkdownRequest?
    @ObservationIgnored private var pdfRequest: ReadAloudPDFRequest?
    private var pdfSource: PDFReadAloudSource?
    private weak var sourcePDF: PDFSession?
    @ObservationIgnored private var sourcePDFRevision: Int?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var preparationIdentifier: UUID?
    @ObservationIgnored private var pdfContinuation: (() -> Void)?
    @ObservationIgnored private var foldPreparationIdentifier: UUID?
    /// Footer and header text found on the pages read so far, skipped on the following ones.
    @ObservationIgnored private var pdfRunningText: [String] = []
    /// In the app a chosen passage starts as soon as it is ready, like Play in any audio app;
    /// tests prepare first and play explicitly. Rebuilding a passage for a new math or PDF
    /// reading order, and a scanned page that needs review, still wait for Play.
    @ObservationIgnored private let playsWhenPrepared: Bool
    @ObservationIgnored private var playsCurrentPreparation = false
    /// The lock screen entry and media controls, used by the app only so tests never touch
    /// the system's shared Now Playing state.
    @ObservationIgnored private let nowPlaying: ReadAloudNowPlaying?

    init(session: ReadAloudSession = ReadAloudSession(), preferences: UserDefaults = .standard, playsWhenPrepared: Bool = false) {
        self.session = session
        self.preferences = preferences
        self.playsWhenPrepared = playsWhenPrepared
        nowPlaying = playsWhenPrepared ? ReadAloudNowPlaying() : nil
        mathematicalStyle = preferences.string(forKey: "readAloudMathematicalStyle").flatMap(MathematicalSpeechStyle.init(rawValue:)) ?? .concise
        pdfReadingOrder = preferences.string(forKey: "readAloudPDFReadingOrder").flatMap(PDFReadingOrder.init(rawValue:)) ?? .layout
        session.didFinishDocument = { [weak self] in self?.continuePDFIfNeeded() ?? false }
        if nowPlaying != nil { followSessionForNowPlaying() }
    }

    func readMarkdown(_ markdown: String, path: VaultPath, range: NSRange? = nil,
                      scope: String = "Whole note", paletteHexByName: [String: String] = [:], startsPlaying: Bool = true,
                      hiddenRanges: [NSRange] = []) {
        begin(title: path.stem, sourceIdentifier: path.rawValue, scope: scope)
        playsCurrentPreparation = playsWhenPrepared && startsPlaying
        markdownRequest = ReadAloudMarkdownRequest(sourceText: markdown, path: path, selectedRange: range,
                                                  scopeDescription: scope, paletteHexByName: paletteHexByName, hiddenRanges: hiddenRanges)
        let identifier = preparationIdentifier
        let mathematicalStyle = mathematicalStyle
        let markdownPreparation = markdownPreparation
        let vaultRoot = vaultRoot
        preparation = Task { [weak self] in
            let worker = Task(priority: .userInitiated) {
                try await markdownPreparation.prepare(markdown, selectedRange: range, paletteHexByName: paletteHexByName,
                                                      mathematicalStyle: mathematicalStyle, vaultRoot: vaultRoot, hiddenRanges: hiddenRanges)
            }
            do {
                let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, identifier == self.preparationIdentifier, !Task.isCancelled else { return }
                self.finishPreparing(document)
            } catch { self?.failed(error, identifier: identifier) }
        }
    }

    /// The person folded or unfolded part of the note being read: the passage is prepared again
    /// without what is now hidden, and reading goes on from where it was, so a section folded
    /// ahead is skipped and one unfolded ahead is read.
    func foldsDidChange(in path: VaultPath, hiddenRanges: [NSRange]) {
        guard let request = markdownRequest, request.path == path, request.hiddenRanges != hiddenRanges,
              session.document != nil || isPreparing else { return }
        let wasSpeaking = session.state == .speaking
        let position = session.sourceRange?.location
            ?? session.currentPassage?.spans.map(\.sourceRange.location).min() ?? 0
        let identifier = UUID()
        foldPreparationIdentifier = identifier
        let markdownPreparation = markdownPreparation
        let mathematicalStyle = mathematicalStyle
        let vaultRoot = vaultRoot
        markdownRequest?.hiddenRanges = hiddenRanges
        Task { [weak self] in
            guard let document = try? await markdownPreparation.prepare(request.sourceText, selectedRange: request.selectedRange,
                                                                        paletteHexByName: request.paletteHexByName,
                                                                        mathematicalStyle: mathematicalStyle, vaultRoot: vaultRoot,
                                                                        hiddenRanges: hiddenRanges),
                  let self, self.foldPreparationIdentifier == identifier, self.markdownRequest?.path == path else { return }
            let resumeIndex = document.passages.firstIndex { passage in
                (passage.spans.map { span in NSMaxRange(span.sourceRange) }.max() ?? 0) > position
            } ?? max(0, document.passages.count - 1)
            self.session.load(document)
            self.session.move(to: resumeIndex)
            if wasSpeaking { self.session.play() }
        }
    }

    func chooseMathematicalStyle(_ style: MathematicalSpeechStyle) {
        guard mathematicalStyle != style else { return }
        mathematicalStyle = style
        preferences.set(style.rawValue, forKey: "readAloudMathematicalStyle")
        guard let request = markdownRequest else { return }
        readMarkdown(request.sourceText, path: request.path, range: request.selectedRange,
                     scope: request.scopeDescription, paletteHexByName: request.paletteHexByName, startsPlaying: false,
                     hiddenRanges: request.hiddenRanges)
    }

    func prepareVoiceSample() async throws -> ReadAloudDocument {
        try await markdownPreparation.prepare("## A moment to study\n\nRead at a comfortable pace. Pause between ideas, and follow each word. For example, $x^2$ means x squared, and $\\frac{a+b}{c}$ is a fraction.",
                                              mathematicalStyle: mathematicalStyle)
    }

    func choosePDFReadingOrder(_ readingOrder: PDFReadingOrder) {
        guard pdfReadingOrder != readingOrder else { return }
        pdfReadingOrder = readingOrder
        preferences.set(readingOrder.rawValue, forKey: "readAloudPDFReadingOrder")
        guard let pdf = sourcePDF, let request = pdfRequest, let pageIndex = sourcePageIndex else { return }
        guard sourcePDFRevision == pdf.changeVersion else { documentDidChange(pdf.location.path); return }
        begin(title: title, sourceIdentifier: pdf.location.path, scope: scopeDescription)
        playsCurrentPreparation = false
        sourcePDF = pdf
        sourcePDFRevision = pdf.changeVersion
        pdfRequest = request
        loadPDFPage(pdf, pageIndex: pageIndex, lastPageIndex: request.lastPageIndex, range: request.range)
    }

    func correctRecognizedPDFWords(_ corrections: [Int: String], pageIdentifier: UUID) {
        applyRecognizedPDFReview(corrections, words: recognizedWordRange, pageIdentifier: pageIdentifier)
    }

    func applyRecognizedPDFReview(_ corrections: [Int: String], words: ClosedRange<Int>?, pageIdentifier: UUID) {
        guard pageIdentifier == recognizedPageIdentifier, let snapshot = recognizedPDFPage,
              let pdf = sourcePDF, let request = pdfRequest, let pageIndex = sourcePageIndex else { return }
        guard sourcePDFRevision == pdf.changeVersion else { documentDidChange(pdf.location.path); return }
        stop()
        session.clear()
        errorMessage = nil
        pdfSource = nil
        recognizedPageIdentifier = nil
        isPreparing = true
        preparationIdentifier = UUID()
        let identifier = preparationIdentifier
        let revision = pdf.changeVersion
        preparation = Task { [weak self] in
            do {
                let worker = Task.detached(priority: .userInitiated) { try snapshot.correctingRecognizedWords(corrections) }
                let corrected = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self else { return }
                try await self.preparePDFSnapshot(corrected, pdf: pdf, pageIndex: pageIndex,
                    lastPageIndex: words == nil ? request.lastPageIndex : pageIndex, range: request.range, playsWhenReady: false,
                    identifier: identifier, revision: revision, recognizedWords: words)
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
        sourcePDFRevision = pdf.changeVersion
        pdfRequest = ReadAloudPDFRequest(lastPageIndex: lastPageIndex, range: nil)
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
        sourcePDFRevision = pdf.changeVersion
        let revision = pdf.changeVersion
        let identifier = preparationIdentifier
        preparation = Task { [weak self] in
            do {
                let vaultRoot = self?.vaultRoot
                let worker = Task.detached(priority: .userInitiated) {
                    try ReadAloudDocument.pageText(source.text, pronunciations: ReadAloudMarkdownPreparation.pronunciations(vaultRoot: vaultRoot))
                }
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
        guard pdf.document.allowsCopying else {
            failed(GraphiteError.unavailable("This PDF does not allow text extraction."), identifier: preparationIdentifier); return
        }
        guard !pdf.document.isEncrypted else {
            failed(GraphiteError.unavailable("Choose Read Selection for an unlocked encrypted PDF. Page-range extraction is unavailable."), identifier: preparationIdentifier); return
        }
        guard start.revision == pdf.changeVersion, end == nil || end?.revision == pdf.changeVersion else {
            failed(GraphiteError.unavailable("The PDF changed. Choose the reading start and end again."), identifier: preparationIdentifier); return
        }
        let lastPageIndex = end?.pageIndex ?? pdf.pageCount - 1
        guard start.pageIndex >= 0, start.pageIndex < pdf.pageCount, start.offset >= 0,
              lastPageIndex >= start.pageIndex, lastPageIndex < pdf.pageCount,
              end == nil || (end?.offset ?? 0) > 0 else {
            failed(ReadAloudError.emptyRange, identifier: preparationIdentifier); return
        }
        if pdfReadingOrder == .file, lastPageIndex == start.pageIndex,
           let end, end.offset <= start.offset {
            failed(ReadAloudError.emptyRange, identifier: preparationIdentifier); return
        }
        sourcePDF = pdf
        sourcePDFRevision = pdf.changeVersion
        let range = PDFReadAloudRange(start: start, end: end)
        pdfRequest = ReadAloudPDFRequest(lastPageIndex: lastPageIndex, range: range)
        loadPDFPage(pdf, pageIndex: start.pageIndex, lastPageIndex: lastPageIndex, range: range)
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
        markdownRequest = nil
        pdfRequest = nil
        recognizedPDFPage = nil
        recognizedPageIdentifier = nil
        recognizedWordRange = nil
        stop()
        session.clear()
        errorMessage = "The document changed. Choose the passage again to read the current version."
    }

    func stop() {
        stopIdentifier = UUID()
        preparationIdentifier = nil
        preparation?.cancel()
        preparation = nil
        isPreparing = false
        pdfContinuation = nil
        session.stop()
    }

    func clear() {
        stop(); session.clear()
        markdownRequest = nil
        pdfRequest = nil
        sourcePDF = nil
        sourcePDFRevision = nil
        pdfSource = nil
        recognizedPDFPage = nil
        recognizedPageIdentifier = nil
        recognizedWordRange = nil
        sourceIdentifier = nil
        sourcePageIndex = nil
        errorMessage = nil
        showsReader = false
    }

    /// Starts preparing the next PDF page after the last word of this one; true when it did.
    @discardableResult
    func continuePDFIfNeeded() -> Bool {
        guard session.state == .finished, let continuation = pdfContinuation else { return false }
        pdfContinuation = nil
        continuation()
        return true
    }

    func highlight(in path: VaultPath) -> NSRange? {
        guard sourceIdentifier == path.rawValue, session.state == .speaking || session.state == .paused else { return nil }
        return session.sourceRange
    }

    func highlights(in pdf: PDFSession) -> [PDFReadAloudHighlight] {
        guard sourcePDF === pdf, session.state == .speaking || session.state == .paused,
              sourcePDFRevision == pdf.changeVersion,
              let range = session.sourceRange else { return [] }
        if let view = pdf.pdfView, view.document !== pdf.document { return [] }
        return pdfSource?.highlights(for: range) ?? []
    }

    /// Re-publishes the lock screen entry whenever the reading state, passage or title changes.
    private func followSessionForNowPlaying() {
        withObservationTracking {
            updateNowPlaying()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followSessionForNowPlaying() }
        }
    }

    private func updateNowPlaying() {
        guard let nowPlaying else { return }
        let hasPassage = session.document != nil
        let passageCount = session.document?.passages.count ?? 0
        let progress = passageCount > 0 ? Double(session.passageIndex) / Double(passageCount) : nil
        nowPlaying.update(title: hasPassage || isPreparing ? title : nil, detail: scopeDescription, state: session.state,
                          progress: progress, commands: ReadAloudNowPlaying.Commands(
            play: { [weak self] in
                guard let self, self.session.document != nil, self.session.state != .speaking else { return false }
                self.session.play()
                return true
            },
            pause: { [weak self] in
                guard let self, self.session.state == .speaking else { return false }
                self.session.pause()
                return true
            },
            nextSentence: { [weak self] in
                guard let self, self.session.canMoveToNextSentence else { return false }
                self.session.moveToNextSentence()
                return true
            },
            previousSentence: { [weak self] in
                guard let self, self.session.canMoveToPreviousSentence else { return false }
                self.session.moveToPreviousSentence()
                return true
            }))
    }

    /// The PDF being read, if any, and the last page of the read: for the player's page steps.
    var readingPDF: PDFSession? { sourcePDF }
    /// The note being read, as written, for showing its headings in the player.
    var readingSourceText: String? { markdownRequest?.sourceText }
    var readingPDFLastPageIndex: Int? { pdfRequest?.lastPageIndex }

    /// A passage is loaded, being prepared, or could not be prepared and says why.
    var isActive: Bool { session.document != nil || isPreparing || errorMessage != nil }

    /// A person's own scroll pauses following; it comes back by itself a few seconds after
    /// the last scroll, or at once from Follow Reading in the controls.
    func suspendFollowing() {
        followsReading = false
        followResumption?.cancel()
        followResumption = Task { [weak self] in
            try? await Task.sleep(for: Self.followResumptionDelay)
            guard let self, !Task.isCancelled, self.session.state == .speaking else { return }
            self.followsReading = true
        }
    }

    func suspendFollowing(in identifier: String) {
        if sourceIdentifier == identifier, session.document != nil { suspendFollowing() }
    }

    static let followResumptionDelay = Duration.seconds(5)
    @ObservationIgnored private var followResumption: Task<Void, Never>?

    func shouldFollow(_ path: VaultPath) -> Bool {
        sourceIdentifier == path.rawValue && followsReading && session.state == .speaking
    }

    func shouldFollow(_ pdf: PDFSession) -> Bool {
        sourcePDF === pdf && followsReading && session.state == .speaking
    }

    /// The passage is text selected in a PDF rather than whole pages.
    var pdfSourceIsSelection: Bool { sourcePageIndex == nil && sourcePDF != nil }

    var canShowPDFPassage: Bool {
        guard let pdf = sourcePDF, let view = pdf.pdfView else { return false }
        return view.document === pdf.document && pdfSource != nil && !isPreparing && errorMessage == nil
    }

    /// Explicit navigation leaves manual scrolling alone during narration.
    func showPDFPassage() -> Bool {
        guard canShowPDFPassage, let pdf = sourcePDF, let view = pdf.pdfView else { return false }
        if let highlight = highlights(in: pdf).first, case .recognizedText = highlight.location,
           let page = pdf.document.page(at: highlight.pageIndex), let bounds = highlight.pageBounds(in: pdf.document) {
            view.go(to: bounds.insetBy(dx: -16, dy: -40).intersection(page.bounds(for: view.displayBox)), on: page)
            return true
        }
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
        pdfRunningText = []
        markdownRequest = nil
        pdfRequest = nil
        self.title = title
        self.sourceIdentifier = sourceIdentifier
        scopeDescription = scope
        sourcePageIndex = nil
        sourcePDF = nil
        sourcePDFRevision = nil
        pdfSource = nil
        sourceHighlightNotice = nil
        recognizedPDFPage = nil
        recognizedPageIdentifier = nil
        recognizedWordRange = nil
        errorMessage = nil
        isPreparing = true
        // The app keeps the page in view and shows the controls in the toolbar; the options
        // sheet opens by itself only when something needs the person's attention.
        showsReader = !playsWhenPrepared
        playsCurrentPreparation = playsWhenPrepared
        preparationIdentifier = UUID()
        session.refreshVoices()
    }

    private func loadPDFPage(_ pdf: PDFSession, pageIndex: Int, lastPageIndex: Int,
                             range: PDFReadAloudRange? = nil, playsWhenReady: Bool = false) {
        guard sourcePDFRevision == pdf.changeVersion else { documentDidChange(pdf.location.path); return }
        let identifier = preparationIdentifier
        let revision = pdf.changeVersion
        let readingOrder = pdfReadingOrder
        isPreparing = true
        pdfSource = nil
        recognizedPDFPage = nil
        recognizedPageIdentifier = nil
        recognizedWordRange = nil
        sourcePageIndex = pageIndex
        scopeDescription = "Page \(pageIndex + 1) · reading through page \(lastPageIndex + 1)"
        preparation = Task { [weak self] in
            // Between two pages there is a moment without sound; in the background the system
            // could suspend the app right then, so the next page is prepared as a task it allows.
            let backgroundTask = ReadAloudBackgroundTask.begin(named: "Prepare the next page to read aloud")
            defer { backgroundTask.end() }
            do {
                let pageSnapshot = try await pdf.readAloudPage(pageIndex: pageIndex, readingOrder: readingOrder)
                guard let self else { return }
                try await self.preparePDFSnapshot(pageSnapshot, pdf: pdf, pageIndex: pageIndex, lastPageIndex: lastPageIndex,
                    range: range, playsWhenReady: playsWhenReady, identifier: identifier, revision: revision)
            } catch { self?.failed(error, identifier: identifier) }
        }
    }

    private func preparePDFSnapshot(_ snapshot: PDFReadAloudPage, pdf: PDFSession, pageIndex: Int, lastPageIndex: Int,
                                    range: PDFReadAloudRange?, playsWhenReady: Bool, identifier: UUID?, revision: Int,
                                    recognizedWords: ClosedRange<Int>? = nil) async throws {
        guard identifier == preparationIdentifier, !Task.isCancelled else { return }
        // The page's own number and its printed label, to recognize a running footer or header.
        let pageLabels = [String(pageIndex + 1)] + (pdf.document.page(at: pageIndex)?.label.map { label in [label] } ?? [])
        let knownRunningText = pdfRunningText
        let vaultRoot = vaultRoot
        let hyphenationWords = ReadAloudSpelling.dictionaryWords(among: ReadAloudDocument.hyphenationCandidates(in: snapshot.text),
                                                                 language: String(session.readingLanguage.prefix(2)))
        let worker = Task.detached(priority: .userInitiated) {
            let selectedRange: NSRange?
            if let recognizedWords {
                selectedRange = try snapshot.recognizedTextRange(words: recognizedWords)
            } else if let range {
                selectedRange = try snapshot.selectedRange(startOffset: pageIndex == range.start.pageIndex ? range.start.offset : nil,
                    endOffset: pageIndex == range.end?.pageIndex ? range.end?.offset : nil)
            } else { selectedRange = nil }
            return try ReadAloudDocument.pageText(snapshot.text, selectedRange: selectedRange, pageLabels: pageLabels,
                                                  knownRunningText: knownRunningText,
                                                  pronunciations: ReadAloudMarkdownPreparation.pronunciations(vaultRoot: vaultRoot),
                                                  hyphenationDictionaryWords: hyphenationWords)
        }
        let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard identifier == preparationIdentifier, !Task.isCancelled else { return }
        guard revision == pdf.changeVersion else { documentDidChange(pdf.location.path); return }
        guard let page = pdf.document.page(at: pageIndex), !document.passages.isEmpty else { throw ReadAloudError.noReadableText }
        for text in document.runningText where !pdfRunningText.contains(text) { pdfRunningText = Array((pdfRunningText + [text]).suffix(8)) }
        let hasSafeCoordinates: Bool
        var alignedSource: PDFReadAloudSource?
        if let recognition = snapshot.recognition {
            hasSafeCoordinates = page.bounds(for: .mediaBox) == recognition.geometry.mediaBounds && page.bounds(for: .cropBox) == recognition.geometry.cropBounds &&
                page.rotation == recognition.geometry.rotation
            recognizedPDFPage = snapshot
            recognizedPageIdentifier = UUID()
            recognizedWordRange = recognizedWords
            if let recognizedWords {
                scopeDescription = "Page \(pageIndex + 1) · words \(recognizedWords.lowerBound + 1)–\(recognizedWords.upperBound + 1)"
                pdfRequest = ReadAloudPDFRequest(lastPageIndex: pageIndex, range: nil)
            }
        } else {
            alignedSource = PDFReadAloudSource.page(snapshot, pageIndex: pageIndex, livePageText: page.string ?? "")
            hasSafeCoordinates = alignedSource != nil
        }
        if hasSafeCoordinates {
            pdfSource = alignedSource ?? .page(snapshot, pageIndex: pageIndex)
            sourceHighlightNotice = snapshot.layoutNotice
        } else {
            if range != nil { throw ReadAloudError.sourceMappingUnavailable }
            sourceHighlightNotice = "This page’s text positions could not be matched safely. Follow the highlighted transcript instead."
        }
        if pageIndex < lastPageIndex {
            pdfContinuation = { [weak self, pdf] in self?.loadPDFPage(pdf, pageIndex: pageIndex + 1, lastPageIndex: lastPageIndex,
                range: range, playsWhenReady: true) }
        }
        // Recognized text has not been reviewed simply because the previous page
        // finished. Each scan waits for an explicit Play after preparation.
        finishPreparing(document, needsReview: snapshot.recognition != nil)
        if playsWhenReady && snapshot.recognition == nil && session.state != .speaking { session.play() }
    }

    private func finishPreparing(_ document: ReadAloudDocument, needsReview: Bool = false) {
        isPreparing = false
        preparation = nil
        session.load(document)
        let plays = playsCurrentPreparation && !needsReview
        playsCurrentPreparation = false
        if plays { session.play() }
        if needsReview || session.message != nil { showsReader = true }
    }

    private func failed(_ error: Error, identifier: UUID?) {
        guard identifier == preparationIdentifier, !Task.isCancelled else { return }
        isPreparing = false
        preparation = nil
        pdfContinuation = nil
        playsCurrentPreparation = false
        errorMessage = error.localizedDescription
        showsReader = true
        // A PDF whose next page failed keeps no audio session or lock screen controls.
        if session.state == .finished { session.stop() }
    }
}

extension PDFSession {
    func readAloudPage(pageIndex: Int, readingOrder: PDFReadingOrder) async throws -> PDFReadAloudPage {
        guard document.allowsCopying else { throw GraphiteError.unavailable("This PDF does not allow text extraction.") }
        let pageBytes = try await export(pages: [pageIndex])
        return try await PDFReadAloudExtraction().page(in: pageBytes, readingOrder: readingOrder)
    }
}

/// Background time for preparing the next PDF page while reading continues off screen.
struct ReadAloudBackgroundTask {
    #if canImport(UIKit)
    private let identifier: UIBackgroundTaskIdentifier

    @MainActor static func begin(named name: String) -> ReadAloudBackgroundTask {
        ReadAloudBackgroundTask(identifier: UIApplication.shared.beginBackgroundTask(withName: name))
    }

    @MainActor func end() {
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
    #else
    @MainActor static func begin(named name: String) -> ReadAloudBackgroundTask { ReadAloudBackgroundTask() }
    @MainActor func end() {}
    #endif
}
