import Foundation

/// Ranges merged into sorted, disjoint intervals, so an overlap test is a binary search
/// instead of a scan of every range, which would make a pass quadratic in the links, code
/// spans or formulas of a note or line. Ranges that overlap or touch merge; empty ranges
/// are left out, as they overlap nothing.
package struct SortedRangeSet: Sendable {
    /// Sorted by location; each interval ends before the next one starts.
    package private(set) var intervals: [NSRange] = []

    package init() {}

    package init(_ ranges: [NSRange]) {
        for range in ranges.filter({ range in range.length > 0 }).sorted(by: { first, second in first.location < second.location }) {
            if let last = intervals.last, range.location <= NSMaxRange(last) {
                intervals[intervals.count - 1] = NSUnionRange(last, range)
            } else {
                intervals.append(range)
            }
        }
    }

    package var isEmpty: Bool { intervals.isEmpty }

    /// Whether `range` shares at least one position with a stored range.
    package func intersects(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        // The last interval starting before `range` ends is the only candidate: the
        // intervals are disjoint and sorted, so it also ends last among them.
        let candidateIndex = firstIndex { interval in interval.location >= NSMaxRange(range) } - 1
        return candidateIndex >= 0 && NSMaxRange(intervals[candidateIndex]) > range.location
    }

    /// Adds `range`, merged with the intervals it overlaps or touches, for a caller that
    /// claims ranges one at a time and asks about each new one first.
    package mutating func insert(_ range: NSRange) {
        guard range.length > 0 else { return }
        let firstMergedIndex = firstIndex { interval in NSMaxRange(interval) >= range.location }
        var endIndex = firstMergedIndex
        var merged = range
        while endIndex < intervals.count, intervals[endIndex].location <= NSMaxRange(range) {
            merged = NSUnionRange(merged, intervals[endIndex])
            endIndex += 1
        }
        if firstMergedIndex == endIndex {
            intervals.insert(merged, at: firstMergedIndex)
        } else {
            intervals[firstMergedIndex] = merged
            intervals.removeSubrange((firstMergedIndex + 1)..<endIndex)
        }
    }

    /// The index of the first interval for which `isAtOrAfter` holds, or the interval count;
    /// `isAtOrAfter` must hold for every interval after one it holds for.
    private func firstIndex(where isAtOrAfter: (NSRange) -> Bool) -> Int {
        var lowerIndex = 0, upperIndex = intervals.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if isAtOrAfter(intervals[middleIndex]) { upperIndex = middleIndex } else { lowerIndex = middleIndex + 1 }
        }
        return lowerIndex
    }
}
