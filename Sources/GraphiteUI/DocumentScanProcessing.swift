import CoreGraphics
import Foundation
import GraphiteApple
import Observation

/// Makes the PDF of a document scan while the person waits, and hands it to the caller to
/// save. It owns the one task doing that, so a cancelled or abandoned scan stops at the next
/// page and leaves nothing behind: the PDF only exists in memory until `save` runs.
@MainActor
@Observable
final class DocumentScanProcessing {
    /// True from the scanner's result until the PDF has been saved, reported as failed or cancelled.
    private(set) var isProcessing = false

    @ObservationIgnored private let wordRecognizer: ScannedPageWordRecognizer
    @ObservationIgnored private var processingTask: Task<Void, Never>?

    init(wordRecognizer: ScannedPageWordRecognizer) {
        self.wordRecognizer = wordRecognizer
    }

    /// Builds the PDF of `pageImages` off the main actor, then calls `save` with it and the
    /// moment the scan finished (which names the file). A failure is passed to `report`.
    /// Does nothing while another scan is processing; the views offer no scan until it ends.
    /// Returns the task, so a caller can wait for the scan to be saved or reported.
    @discardableResult
    func process(pageImages: [CGImage], save: @escaping @MainActor (ScannedDocumentPDF, Date) async -> Void,
                 report: @escaping @MainActor (any Error) -> Void) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        isProcessing = true
        // The one read of the wall clock for scanning: the time the scanner returned names the file.
        let scannedAt = Date.now
        let builder = ScannedDocumentPDFBuilder(wordRecognizer: wordRecognizer)
        let task = Task { [weak self] in
            do {
                let scan = try await builder.build(pageImages: pageImages)
                try Task.checkCancellation()
                await save(scan, scannedAt)
            } catch is CancellationError {
                // Cancelled by the person: nothing was written.
            } catch {
                report(error)
            }
            // A cancelled scan was already ended by `cancel()`; a newer scan must keep its state.
            if !Task.isCancelled { self?.finishProcessing() }
        }
        processingTask = task
        return task
    }

    /// Stops the scan being processed. Nothing is saved.
    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    private func finishProcessing() {
        processingTask = nil
        isProcessing = false
    }

    /// What the person is told when a scan could not become a saved file.
    static func message(for error: any Error) -> String {
        switch error as? ScannedDocumentError {
        case .noPages: "The scan has no pages. Scan the document again."
        case .pageHasNoPixels, .pageImageEncodingFailed, .pdfWritingFailed, nil: "The scan could not be saved. Scan the document again."
        }
    }
}
