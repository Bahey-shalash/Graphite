import Foundation
import GraphiteCore

/// A clock for the hosted iPad tests whose sleeps end when the test says so: a task that
/// sleeps on it stays suspended until `endSleeps()`, and a test reads what it was asked to
/// wait for (`requestedDurations`). The package's `ManualClock` (in the test-support target,
/// which this target cannot import) moves time instead and does the same job for the package
/// tests; this one needs no more than "the wait is over now".
///
/// `@unchecked Sendable`: every mutable property is behind `lock`, and continuations are
/// resumed only after the lock is released.
final class HostedControlledClock: ApplicationClock, @unchecked Sendable {
    private struct Sleeper {
        let identifier: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var sleepers: [Sleeper] = []
    private var durations: [Duration] = []
    private var nextIdentifier = 0
    private let origin = ContinuousClock.now

    var now: Duration { origin.duration(to: ContinuousClock.now) }

    /// How long each task that sleeps now was asked to sleep.
    var requestedDurations: [Duration] { lock.withLock { durations } }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let identifier = lock.withLock { () -> Int in
            nextIdentifier += 1
            return nextIdentifier
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers.append(Sleeper(identifier: identifier, continuation: continuation))
                durations.append(duration)
                lock.unlock()
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.identifier == identifier }) else { return nil }
                durations.remove(at: index)
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Ends every wait now suspended.
    func endSleeps() {
        let ended: [Sleeper] = lock.withLock {
            defer { sleepers = []; durations = [] }
            return sleepers
        }
        for sleeper in ended { sleeper.continuation.resume() }
    }
}
