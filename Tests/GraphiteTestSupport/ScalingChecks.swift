import Foundation
import XCTest

/// Checks that a piece of work costs time in proportion to its input, which holds on any machine, instead of finishing
/// within a number of seconds, which holds only on the machine the number was chosen on. A bug that makes the work
/// quadratic (a scan from every position, a search repeated per item) shows as a ratio far above the size ratio on a
/// slow virtual machine as on a fast one. A bug that costs a large constant per item is not seen by a ratio; a test of
/// that kind counts the work or compares against a plain pass over the input (`assertNoSlowerThan`).
public enum ScalingChecks {
    /// How many times each size is run; the best time counts, because noise on a shared machine only adds time.
    public static let runsPerSize = 3
    /// Below this the clock and the scheduler are as large as the work, so the smaller size is counted as this long.
    public static let smallestMeaningfulSeconds = 0.02
    /// A run of the larger size that ends in less than this is fast enough whatever the ratio.
    public static let fastEnoughSeconds = 0.1

    /// Runs `work(size)` for `smallSize` and for `largeSize` (a few times each, after one warm-up) and fails when the
    /// larger takes more than `maximumRatio` times the smaller, by default twice the ratio of the sizes: 8 for 4 times
    /// the input, where linear work gives 4 and quadratic work 16.
    public static func assertScalesLinearly(smallSize: Int, largeSize: Int, maximumRatio: Double? = nil, _ description: String = "",
                                            fastEnoughSeconds: Double = ScalingChecks.fastEnoughSeconds,
                                            smallestMeaningfulSeconds: Double = ScalingChecks.smallestMeaningfulSeconds,
                                            file: StaticString = #filePath, line: UInt = #line, work: (Int) throws -> Void) rethrows {
        precondition(largeSize > smallSize && smallSize > 0, "The larger size must be larger.")
        try work(smallSize)
        let smallSeconds = try bestSeconds(of: smallSize, work: work)
        let largeSeconds = try bestSeconds(of: largeSize, work: work)
        verify(smallSeconds: smallSeconds, largeSeconds: largeSeconds, sizeRatio: Double(largeSize) / Double(smallSize),
               maximumRatio: maximumRatio, description: description, fastEnoughSeconds: fastEnoughSeconds,
               smallestMeaningfulSeconds: smallestMeaningfulSeconds, file: file, line: line)
    }

    /// The same for work that waits on other tasks.
    public static func assertAsyncWorkScalesLinearly(smallSize: Int, largeSize: Int, maximumRatio: Double? = nil, _ description: String = "",
                                                     fastEnoughSeconds: Double = ScalingChecks.fastEnoughSeconds,
                                                     smallestMeaningfulSeconds: Double = ScalingChecks.smallestMeaningfulSeconds,
                                                     file: StaticString = #filePath, line: UInt = #line,
                                                     work: (Int) async throws -> Void) async rethrows {
        precondition(largeSize > smallSize && smallSize > 0, "The larger size must be larger.")
        try await work(smallSize)
        var smallSeconds = Double.infinity, largeSeconds = Double.infinity
        for _ in 0..<runsPerSize { smallSeconds = min(smallSeconds, try await seconds(of: { try await work(smallSize) })) }
        for _ in 0..<runsPerSize { largeSeconds = min(largeSeconds, try await seconds(of: { try await work(largeSize) })) }
        verify(smallSeconds: smallSeconds, largeSeconds: largeSeconds, sizeRatio: Double(largeSize) / Double(smallSize),
               maximumRatio: maximumRatio, description: description, fastEnoughSeconds: fastEnoughSeconds,
               smallestMeaningfulSeconds: smallestMeaningfulSeconds, file: file, line: line)
    }

    /// Fails when `work` takes more than `factor` times as long as `reference`, a plain pass over the same input made on
    /// the same machine a moment before: the machine's speed is in both. Best of a few runs, as above.
    public static func assertNoSlowerThan(factor: Double, reference: () throws -> Void, _ description: String = "",
                                          fastEnoughSeconds: Double = ScalingChecks.fastEnoughSeconds,
                                          file: StaticString = #filePath, line: UInt = #line, work: () throws -> Void) rethrows {
        try reference(); try work()
        let referenceSeconds = max(try bestSeconds(of: reference), 0.001)
        let workSeconds = try bestSeconds(of: work)
        print("Scaling check \(description): \(String(format: "%.3f", workSeconds)) s of work, \(String(format: "%.3f", referenceSeconds)) s of plain pass (\(String(format: "%.1f", workSeconds / referenceSeconds))x, limit \(factor)x)")
        if workSeconds < fastEnoughSeconds { return }
        XCTAssertLessThan(workSeconds / referenceSeconds, factor, "\(description): \(workSeconds) s against \(referenceSeconds) s for a plain pass.", file: file, line: line)
    }

    private static func verify(smallSeconds: Double, largeSeconds: Double, sizeRatio: Double, maximumRatio: Double?, description: String,
                               fastEnoughSeconds: Double, smallestMeaningfulSeconds: Double, file: StaticString, line: UInt) {
        let limit = maximumRatio ?? 2 * sizeRatio
        let ratio = largeSeconds / max(smallSeconds, smallestMeaningfulSeconds)
        print("Scaling check \(description): \(String(format: "%.3f", smallSeconds)) s, then \(String(format: "%.3f", largeSeconds)) s for \(sizeRatio)x the input (ratio \(String(format: "%.1f", ratio)), limit \(limit))")
        if largeSeconds < fastEnoughSeconds { return }
        XCTAssertLessThan(ratio, limit, "\(description): \(sizeRatio)x the input took \(String(format: "%.1f", ratio))x as long (linear is \(sizeRatio), quadratic \(sizeRatio * sizeRatio)).", file: file, line: line)
    }

    private static func bestSeconds(of size: Int, work: (Int) throws -> Void) rethrows -> Double {
        try bestSeconds(of: { try work(size) })
    }

    private static func bestSeconds(of work: () throws -> Void) rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runsPerSize { best = min(best, try seconds(of: work)) }
        return best
    }

    private static func seconds(of work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        return durationSeconds(ContinuousClock.now - start)
    }

    private static func seconds(of work: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await work()
        return durationSeconds(ContinuousClock.now - start)
    }

    private static func durationSeconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
