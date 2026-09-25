import Foundation

/// Regular expression matching that gives up. A pattern with nested repetition, such as
/// `(a+)+$`, can backtrack for minutes on one line, and neither a search nor a base may
/// hang on one note. With `reportProgress`, Foundation calls back periodically during a
/// long match, not only once per match, so the time limit and the task's cancellation are
/// checked while the pattern runs.
public enum TimeLimitedRegularExpression {
    public static let maximumMatchDuration: Duration = .seconds(1)

    /// Why matching stopped before it finished.
    public enum Interruption: Error, Equatable, Sendable {
        case timeLimitExceeded
        case cancelled
    }

    /// The matches of `regularExpression` in `text`, in order, at most `maximumMatchCount`.
    /// Throws `Interruption` when matching runs longer than `maximumDuration` or the
    /// calling task is cancelled.
    public static func matches(of regularExpression: NSRegularExpression, in text: String, maximumMatchCount: Int = .max,
                               maximumDuration: Duration = maximumMatchDuration) throws -> [NSTextCheckingResult] {
        let clock = ContinuousClock()
        let startTime = clock.now
        var matches: [NSTextCheckingResult] = []
        var interruption: Interruption?
        regularExpression.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            if let match {
                matches.append(match)
                if matches.count >= maximumMatchCount { stop.pointee = true; return }
            }
            if Task.isCancelled {
                interruption = .cancelled
                stop.pointee = true
            } else if clock.now - startTime > maximumDuration {
                interruption = .timeLimitExceeded
                stop.pointee = true
            }
        }
        if let interruption { throw interruption }
        return matches
    }

    /// The first match of `regularExpression` in `text`, or nil. Throws as `matches` does.
    public static func firstMatch(of regularExpression: NSRegularExpression, in text: String,
                                  maximumDuration: Duration = maximumMatchDuration) throws -> NSTextCheckingResult? {
        try matches(of: regularExpression, in: text, maximumMatchCount: 1, maximumDuration: maximumDuration).first
    }
}
