import Foundation
import CoreGraphics

/// A heading a jump keeps at the top of the view while the rendered blocks above it settle
/// their heights. A base above the heading can take seconds to load its rows and then grows
/// by thousands of points, so the pin holds while such a block has not reported its height,
/// and for a moment after the heading last moved or such a block last reported, up to
/// `longestHoldSeconds` after the jump. Scrolling or starting to edit ends it sooner (the
/// editor drops the pin).
struct HeadingJumpPin: Equatable {
    /// How long the heading stays pinned after the jump, or after the blocks above it last
    /// were unsettled.
    static let settleSeconds: TimeInterval = 1.5
    /// The longest a jump holds the heading, so a block that never reports its height
    /// cannot keep the view from moving.
    static let longestHoldSeconds: TimeInterval = 10

    /// The heading's line, as a character location in the note.
    let location: Int
    let pinnedAtUptime: TimeInterval
    private(set) var lastUnsettledAtUptime: TimeInterval
    private var wasBlockAboveAwaitingHeight = false

    init(location: Int, pinnedAtUptime: TimeInterval) {
        self.location = location
        self.pinnedAtUptime = pinnedAtUptime
        lastUnsettledAtUptime = pinnedAtUptime
    }

    /// Records that the blocks above moved the heading and it was put back at the top.
    mutating func recordMove(atUptime uptime: TimeInterval) {
        lastUnsettledAtUptime = uptime
    }

    /// Takes in a layout pass and tells whether the heading is still kept at the top.
    /// Layout passes stop while a base loads, so the first one after it reports its height
    /// can come long after the previous one; that pass is the one the base's new height
    /// moves the heading in, so it counts as unsettled too.
    /// - Parameter isBlockAboveAwaitingHeight: Whether a rendered block on screen above the
    ///   heading has not reported its height yet, as a base still loading its rows.
    mutating func holds(atUptime uptime: TimeInterval, isBlockAboveAwaitingHeight: Bool) -> Bool {
        guard uptime < pinnedAtUptime + Self.longestHoldSeconds else { return false }
        if isBlockAboveAwaitingHeight || wasBlockAboveAwaitingHeight { lastUnsettledAtUptime = uptime }
        wasBlockAboveAwaitingHeight = isBlockAboveAwaitingHeight
        return uptime < lastUnsettledAtUptime + Self.settleSeconds
    }
}

/// Whether the lines TextKit laid out for the viewport cover the part of the note on
/// screen. UIKit lays the viewport out after the text view's own layout pass, so after a
/// jump or a block changing its height the pass can find the viewport laid out for the
/// offset before: its lines then start below the top of the view or end above its bottom,
/// and rendered blocks and fold chevrons in the gap are missing until the next scroll.
enum ViewportLayoutCoverage {
    /// - Parameters:
    ///   - laidOutTop: The top of the first fragment laid out for the viewport.
    ///   - laidOutBottom: The bottom of the last fragment laid out for the viewport.
    ///   - visibleTop: The top of the view, in the same text container coordinates.
    ///   - visibleBottom: The bottom of the view, in the same coordinates.
    ///   - startsAtDocumentStart: Whether the viewport starts at the note's first character,
    ///     above which there is nothing to lay out.
    ///   - endsAtDocumentEnd: Whether the viewport ends at the note's end.
    static func leavesVisibleTextUncovered(laidOutTop: CGFloat, laidOutBottom: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat,
                                           startsAtDocumentStart: Bool, endsAtDocumentEnd: Bool) -> Bool {
        let leavesTopUncovered = !startsAtDocumentStart && laidOutTop > visibleTop + 1
        let leavesBottomUncovered = !endsAtDocumentEnd && laidOutBottom < visibleBottom - 1
        return leavesTopUncovered || leavesBottomUncovered
    }
}
