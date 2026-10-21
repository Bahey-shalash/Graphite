import SwiftUI
import GraphiteApple

/// Presents the document scanner and turns what it returns into a saved PDF through
/// `processing`. Where the device cannot scan (a Mac, the simulator) it presents nothing,
/// and the views offer no control that would ask it to.
struct DocumentScanPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let processing: DocumentScanProcessing
    let save: @MainActor (ScannedDocumentPDF, Date) async -> Void
    let report: @MainActor (String) -> Void

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.fullScreenCover(isPresented: $isPresented) {
            DocumentScanner { outcome in finish(outcome) }
                .ignoresSafeArea()
        }
        #else
        content
        #endif
    }

    #if canImport(UIKit)
    private func finish(_ outcome: DocumentScanner.Outcome) {
        switch outcome {
        case .scanned(let pageImages):
            let report = report
            let task = processing.process(pageImages: pageImages, save: save, report: { error in report(DocumentScanProcessing.message(for: error)) })
            // The pages of a second scan must not be dropped without a word.
            if task == nil { report("Another scan is still being prepared. Scan the document again when it is done.") }
        case .failed:
            report("The scan could not be read. Scan the document again.")
        }
    }
    #endif
}

/// The scanner of a note: the PDF it makes is saved as the note's attachment and embedded at
/// the cursor, with a cover over the note while the PDF is made.
struct NoteDocumentScanPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let save: @MainActor (ScannedDocumentPDF, Date) async -> Void
    let report: @MainActor (String) -> Void
    @State private var processing = DocumentScanProcessing(wordRecognizer: .onDevice)

    func body(content: Content) -> some View {
        content
            .modifier(DocumentScanPresentation(isPresented: $isPresented, processing: processing, save: save, report: report))
            .overlay { DocumentScanProgressOverlay(processing: processing) }
    }
}

/// Covers a note while its scan becomes a PDF, with the one way out: Cancel stops the work
/// and saves nothing.
struct DocumentScanProgressOverlay: View {
    let processing: DocumentScanProcessing

    var body: some View {
        if processing.isProcessing {
            ZStack {
                Color.black.opacity(0.12)
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparing the scan…")
                        .font(.headline)
                    Text("Recognizing the text so the PDF can be searched.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cancel", role: .cancel) { processing.cancel() }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: 320)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)
        }
    }
}
