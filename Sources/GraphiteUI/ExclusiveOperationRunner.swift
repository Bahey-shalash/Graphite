import Foundation

/// Runs one asynchronous operation at a time, for work that reads a value, awaits, and then
/// writes the result back (a picture turned or cropped). A second operation started while
/// one runs is not run, so it can never start from the value the first is about to replace.
/// The running task is owned here, and `cancel()` stops it when its screen closes.
@MainActor @Observable
final class ExclusiveOperationRunner {
    private(set) var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Starts `operation` unless one is already running. Returns whether it was started.
    @discardableResult
    func start(_ operation: @escaping @MainActor () async throws -> Void, onFailure: @escaping @MainActor (Error) -> Void) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        generation += 1
        let startedGeneration = generation
        task = Task { [weak self] in
            do { try await operation() } catch is CancellationError {} catch { onFailure(error) }
            // A cancelled operation has already freed the runner for the next one.
            guard let self, self.generation == startedGeneration else { return }
            self.isRunning = false
        }
        return true
    }

    /// Stops the running operation and lets the next one start.
    func cancel() {
        task?.cancel()
        generation += 1
        isRunning = false
    }

    /// Waits for the running operation to end.
    func finishCurrentOperation() async {
        await task?.value
    }
}
