import Foundation
import GraphiteCore

/// A clock whose time moves only when a test says so (`advance(by:)`). A task that sleeps on
/// it stays suspended until the test has moved time to or past its deadline, and then resumes.
/// A delay of 900 ms is then tested at 899 ms and at 900 ms, without waiting. Tasks that one
/// `advance(by:)` wakes together run in no fixed order, as with a real clock; a test that needs
/// an order advances to each deadline in turn.
///
/// Time advances in one step: a task that resumes and sleeps again is given a deadline
/// counted from the new time, as a real clock would give it a moment later. To run a repeating
/// timer through several periods, advance one period at a time and let the task run between.
///
/// `@unchecked Sendable`: every mutable property is behind `lock`, and continuations are
/// resumed only after the lock is released.
public final class ManualClock: ApplicationClock, @unchecked Sendable {
    private struct Sleeper {
        let identifier: Int
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentTime: Duration
    private var sleepers: [Sleeper] = []
    private var nextSleeperIdentifier = 0

    public init(startingAt startTime: Duration = .zero) {
        currentTime = startTime
    }

    public var now: Duration { lock.withLock { currentTime } }

    /// How many tasks are suspended in `sleep(for:)` now.
    public var pendingSleepCount: Int { lock.withLock { sleepers.count } }

    /// How much longer each suspended task has to sleep, in the order they would resume.
    public var pendingSleepDurations: [Duration] {
        lock.withLock { sleepers.sorted(by: Self.resumesBefore).map { $0.deadline - currentTime } }
    }

    private static func resumesBefore(_ left: Sleeper, _ right: Sleeper) -> Bool {
        left.deadline != right.deadline ? left.deadline < right.deadline : left.identifier < right.identifier
    }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else { return }
        let identifier = lock.withLock { () -> Int in
            nextSleeperIdentifier += 1
            return nextSleeperIdentifier
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                // The check is made under the lock that `onCancel` takes, so a cancellation
                // that arrives first is seen here and one that arrives later finds the sleeper.
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers.append(Sleeper(identifier: identifier, deadline: currentTime + duration, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            let cancelledSleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.identifier == identifier }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelledSleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and resumes, in deadline order, every task whose deadline is now
    /// reached. The resumed tasks run later, on their own executors; a test that needs their
    /// effect waits for it (`waitUntil`) or lets them run (`letResumedTasksRun`).
    public func advance(by duration: Duration) {
        precondition(duration >= .zero, "Time on a ManualClock does not move backwards.")
        let dueSleepers: [Sleeper] = lock.withLock {
            currentTime += duration
            let due = sleepers.filter { $0.deadline <= currentTime }.sorted(by: Self.resumesBefore)
            sleepers.removeAll { sleeper in due.contains { $0.identifier == sleeper.identifier } }
            return due
        }
        for sleeper in dueSleepers { sleeper.continuation.resume() }
    }

    /// Returns once at least `count` tasks are suspended in `sleep(for:)`. A task that was
    /// just started has not necessarily reached its sleep, and a test that advanced time
    /// before it did would move time past a deadline that does not exist yet.
    public func awaitPendingSleepers(count: Int = 1, file: StaticString = #filePath, line: UInt = #line,
                                     isolation: isolated (any Actor)? = #isolation) async throws {
        // The task that will sleep is usually one turn away; yielding lets it run without a delay.
        var turnsYielded = 0
        while pendingSleepCount < count, turnsYielded < Self.turnsToYieldBeforePolling {
            await Task.yield()
            turnsYielded += 1
        }
        try await waitUntil("\(count) task(s) to be sleeping on the manual clock (\(pendingSleepCount) are)", file: file, line: line) {
            self.pendingSleepCount >= count
        }
    }

    private static let turnsToYieldBeforePolling = 100

    /// Lets the tasks that `advance(by:)` just resumed, and the work they start without
    /// suspending on anything else, run before a test checks that something did not happen.
    public static func letResumedTasksRun(isolation: isolated (any Actor)? = #isolation) async {
        for _ in 0..<turnsToYieldBeforePolling { await Task.yield() }
    }
}
