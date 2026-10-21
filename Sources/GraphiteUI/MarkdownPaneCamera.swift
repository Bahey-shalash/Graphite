import SwiftUI
import GraphiteCore

/// How a note takes in what the camera sees: a photo, or the pages of a scanned document.
extension MarkdownPane {
    /// The scanner that Scan Document asks for; the PDF it makes is saved as the note's
    /// attachment and embedded at the cursor.
    func documentScanPresentation(isPresented: Binding<Bool>) -> NoteDocumentScanPresentation {
        NoteDocumentScanPresentation(isPresented: isPresented,
                                     save: { [workspace, session] scan, scannedAt in
                                         await workspace.insertScannedDocument(scan, scannedAt: scannedAt, into: session)
                                     },
                                     report: { [workspace] message in workspace.errorMessage = message })
    }

    #if canImport(UIKit)
    /// A full-resolution camera photo takes long enough to encode that it is done off the
    /// main thread.
    func insertCameraPhoto(_ image: UIImage) async {
        let photoData = await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 0.85) }.value
        guard let photoData else {
            workspace.errorMessage = "The photo could not be saved. Take it again."
            return
        }
        await workspace.saveAttachment(photoData, stem: CameraCapture.photoStem(), fileExtension: "jpg", into: session)
    }
    #endif
}
