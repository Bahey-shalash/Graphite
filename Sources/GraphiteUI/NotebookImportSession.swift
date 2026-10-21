import Foundation
import Observation
import GraphiteCore
import GraphiteApple
import NotebookImport

/// One import of Goodnotes and Notability notebooks into the open vault, from the moment the person chooses them until
/// they close its report. It owns the import's work, which runs away from the main actor (`NotebookImportRun`), and
/// shows its progress, then its summary. The workspace makes one only when notebooks are imported and lets it go when
/// its report is closed, so the import holds nothing while it is not used.
@MainActor @Observable
final class NotebookImportSession {
    enum State: Equatable {
        case importing(NotebookImportProgress, isCancelling: Bool)
        case finished(NotebookImportSummary)
    }

    private(set) var state: State = .importing(.listing, isCancelling: false)

    @ObservationIgnored private var importTask: Task<NotebookImportSummary, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    var isImporting: Bool {
        if case .importing = state { true } else { false }
    }

    /// Starts converting `sources` (notebook files and folders of them, chosen by the person) into `destination`.
    init(sources: [URL], destination: VaultPath, run: NotebookImportRun) {
        let (progressUpdates, continuation) = AsyncStream.makeStream(of: NotebookImportProgress.self, bufferingPolicy: .bufferingNewest(1))
        let importTask = Task.detached(priority: .utility) {
            let summary = await run.run(sources: sources, into: destination, progress: continuation)
            continuation.finish()
            return summary
        }
        self.importTask = importTask
        progressTask = Task { [weak self] in
            for await progress in progressUpdates { self?.show(progress) }
            let summary = await importTask.value
            self?.state = .finished(summary)
        }
    }

    /// Stops the import at the next page. The notebooks written so far stay; the report says what was not imported.
    func cancelImport() {
        guard case .importing(let progress, _) = state else { return }
        state = .importing(progress, isCancelling: true)
        importTask?.cancel()
    }

    /// Stops the import, if it runs, and the task that follows it: the session's end, when the workspace lets it go.
    func stopImportAndObservation() {
        importTask?.cancel()
        progressTask?.cancel()
    }

    private func show(_ progress: NotebookImportProgress) {
        guard case .importing(_, let isCancelling) = state else { return }
        state = .importing(progress, isCancelling: isCancelling)
    }
}
