import Foundation

/// The one source of time for logic that waits or measures: how long a save took, how long
/// to wait after the last edit before saving. Code that depends on it can be tested by
/// moving time by hand (`ManualClock` in `GraphiteTestSupport`) instead of sleeping.
///
/// Only `LiveApplicationClock` reads the system clock. A model receives the clock through
/// its initializer and has no default (`FR-47`, `FR-50`).
public protocol ApplicationClock: Sendable {
    /// Monotonic time since an origin that is the same for every reading of one clock.
    /// Only the difference between two readings means anything; it never goes backwards
    /// and does not change when the wall clock is set.
    var now: Duration { get }

    /// Suspends for `duration` of this clock's time. Throws `CancellationError` as soon as
    /// the calling task is cancelled, so a replaced timer ends at once instead of waiting
    /// out its delay.
    func sleep(for duration: Duration) async throws
}

/// The system's monotonic clock, which keeps counting while the device sleeps.
public struct LiveApplicationClock: ApplicationClock {
    /// One origin for the whole process, so readings of different instances can be compared.
    private static let processOrigin = ContinuousClock.now

    public init() {}

    public var now: Duration { Self.processOrigin.duration(to: ContinuousClock.now) }

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
