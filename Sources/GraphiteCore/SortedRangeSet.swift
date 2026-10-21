import Foundation

/// Ranges merged into sorted, disjoint intervals, so an overlap test is a binary search
/// instead of a scan of every range, which would make parsing quadratic in link-dense notes.
struct SortedRangeSet {
    /// Sorted by location; each interval ends before the next one starts.
    private var intervals: [NSRange] = []

    init(_ ranges: [NSRange]) {
        for range in ranges.filter({ range in range.length > 0 }).sorted(by: { first, second in first.location < second.location }) {
            if let last = intervals.last, range.location <= NSMaxRange(last) {
                intervals[intervals.count - 1] = NSUnionRange(last, range)
            } else {
                intervals.append(range)
            }
        }
    }

    /// Whether `range` shares at least one position with a stored range.
    func intersects(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        // The last interval starting before `range` ends is the only candidate: the
        // intervals are disjoint and sorted, so it also ends last among them.
        var lowerIndex = 0, upperIndex = intervals.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if intervals[middleIndex].location < NSMaxRange(range) { lowerIndex = middleIndex + 1 } else { upperIndex = middleIndex }
        }
        guard lowerIndex > 0 else { return false }
        return NSMaxRange(intervals[lowerIndex - 1]) > range.location
    }
}
