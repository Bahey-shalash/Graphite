import Foundation
import GraphiteCore
import GraphiteApple

/// Saving a document scan: as a PDF attachment of a note, or as a new PDF notebook.
extension WorkspaceModel {
    /// Saves the scan as "Scan 2026-10-21 14.05.pdf" in the note's attachment folder (the
    /// vault's attachment setting) and embeds it at the cursor, as a photo from the camera is.
    func insertScannedDocument(_ scan: ScannedDocumentPDF, scannedAt: Date, into session: MarkdownSession) async {
        await saveAttachment(scan.data, stem: Self.scannedDocumentStem(scannedAt: scannedAt), fileExtension: "pdf", into: session)
        reportPagesWithoutRecognizedText(in: scan)
    }

    /// Saves the scan as a new PDF notebook named from its date in `directory` (the vault's
    /// location for new files when nil) and opens it in a tab, like a new notebook.
    func createScannedNotebook(_ scan: ScannedDocumentPDF, scannedAt: Date, in directory: VaultPath?) async {
        guard let store else { return }
        do {
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let path = try await saveUnderFreeName(scan.data, in: directory, stem: Self.scannedDocumentStem(scannedAt: scannedAt),
                                                   fileExtension: "pdf", store: store)
            refreshIndex(for: [path])
            await refreshDirectory()
            await open(path)
            reportPagesWithoutRecognizedText(in: scan)
        } catch {
            errorMessage = "The scan could not be saved. Scan the document again."
        }
    }

    /// Whether this device can scan paper documents with its camera: an iPhone or iPad, not a
    /// Mac or the simulator. Controls that start a scan are offered only where this is true.
    static var canScanDocuments: Bool {
        #if canImport(UIKit)
        DocumentScanner.isSupported
        #else
        false
        #endif
    }

    /// What a New menu does with a finished scan, or nil where the device cannot scan, which
    /// leaves Scan Documents out of the menu.
    func scannedNotebookSaver() -> (@MainActor (ScannedDocumentPDF, Date, VaultPath?) async -> Void)? {
        guard Self.canScanDocuments else { return nil }
        return { [weak self] scan, scannedAt, directory in
            await self?.createScannedNotebook(scan, scannedAt: scannedAt, in: directory)
        }
    }

    static func scannedDocumentStem(scannedAt: Date) -> String {
        ScannedDocumentName.stem(createdAt: scannedAt, calendar: Calendar(identifier: .gregorian))
    }

    /// The scan is saved either way; a page without text still shows, but cannot be searched or selected.
    private func reportPagesWithoutRecognizedText(in scan: ScannedDocumentPDF) {
        guard !scan.pageIndicesWithoutRecognizedText.isEmpty, errorMessage == nil else { return }
        errorMessage = scan.pageIndicesWithoutRecognizedText.count == scan.pageCount
            ? "The scan was saved, but its text could not be recognized, so it cannot be searched."
            : "The scan was saved, but the text on some pages could not be recognized, so those pages cannot be searched."
    }
}
