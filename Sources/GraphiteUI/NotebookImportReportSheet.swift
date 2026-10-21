import SwiftUI
import GraphiteCore
import NotebookImport

/// The report shown when an import ends: how many notebooks were imported, and for each where it went, what was
/// simplified or left out and why, or why it was not imported.
struct NotebookImportReportSheet: View {
    let summary: NotebookImportSummary
    let openNotebook: @MainActor (VaultPath) -> Void
    let done: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(NotebookImportWording.headline(of: summary))
                    ForEach(NotebookImportWording.folderNotes(of: summary), id: \.self) { note in
                        Text(note).foregroundStyle(.secondary)
                    }
                }
                Section("Notebooks") {
                    ForEach(summary.outcomes) { outcome in
                        NotebookImportOutcomeRow(outcome: outcome, openNotebook: openNotebook)
                    }
                }
            }
            .navigationTitle(NotebookImportWording.title(of: summary))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

/// One notebook of the report: its status, and what its import simplified or left out.
private struct NotebookImportOutcomeRow: View {
    let outcome: NotebookImportOutcome
    let openNotebook: @MainActor (VaultPath) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.sourceName).font(.body.weight(.medium))
                    Text(NotebookImportWording.status(of: outcome)).font(.callout).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(symbolColor)
            }
            if let notebook = outcome.importedNotebook {
                ForEach(Array(notebook.report.summary.enumerated()), id: \.offset) { _, line in
                    Text(NotebookImportWording.line(line)).font(.caption).foregroundStyle(.secondary).padding(.leading, 36)
                }
                Button("Open", systemImage: "book") { openNotebook(notebook.pdf) }
                    .font(.callout)
                    .padding(.leading, 36)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch outcome.result {
        case .imported(let notebook): notebook.report.isComplete ? "checkmark.circle.fill" : "checkmark.circle"
        case .failed: "xmark.octagon"
        case .notStarted: "minus.circle"
        }
    }

    private var symbolColor: Color {
        switch outcome.result {
        case .imported: .green
        case .failed: .red
        case .notStarted: .secondary
        }
    }
}
