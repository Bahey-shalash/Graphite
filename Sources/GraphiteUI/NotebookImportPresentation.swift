import SwiftUI
import GraphiteCore

/// Shows a notebook import over the document area: its progress card at the top while it runs, and its report when
/// it ends.
struct NotebookImportPresentation: ViewModifier {
    let session: NotebookImportSession?
    let openNotebook: @MainActor (VaultPath) -> Void
    /// Closes the report; the workspace then lets the session go.
    let close: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            // At the top, below the tab bar: the Pencil palette takes the bottom of an open notebook.
            .overlay(alignment: .top) {
                if case .importing(let progress, let isCancelling)? = session?.state {
                    NotebookImportProgressCard(progress: progress, isCancelling: isCancelling) { session?.cancelImport() }
                }
            }
            .sheet(isPresented: Binding(get: { finishedSummary != nil }, set: { isPresented in if !isPresented { close() } })) {
                if let finishedSummary {
                    NotebookImportReportSheet(summary: finishedSummary, openNotebook: { path in
                        close()
                        openNotebook(path)
                    }, done: close)
                }
            }
    }

    private var finishedSummary: NotebookImportSummary? {
        if case .finished(let summary)? = session?.state { summary } else { nil }
    }
}
