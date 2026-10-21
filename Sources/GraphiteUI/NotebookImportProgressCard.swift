import SwiftUI

/// The import's progress while the vault stays usable: a small card at the top of the document area with the
/// notebook being converted, a bar, and Cancel.
struct NotebookImportProgressCard: View {
    let progress: NotebookImportProgress
    let isCancelling: Bool
    let cancel: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isCancelling ? "Stopping the Import…" : "Importing Notebooks").font(.callout.weight(.semibold))
                if progress.notebookCount > 0 {
                    ProgressView(value: progress.fractionCompleted)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(NotebookImportWording.progressDetail(progress))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Button("Cancel", action: cancel)
                .disabled(isCancelling)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 480)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}
