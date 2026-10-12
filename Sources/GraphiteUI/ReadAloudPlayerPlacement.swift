import SwiftUI

/// Where the floating player can sit: at the top or bottom edge, leading, centered or
/// trailing. The bottom center is where it starts.
enum ReadAloudPlayerPosition: String, CaseIterable {
    case topLeading, top, topTrailing, bottomLeading, bottom, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    var isTop: Bool { self == .topLeading || self == .top || self == .topTrailing }

    /// The same place at the other edge.
    var flipped: ReadAloudPlayerPosition {
        switch self {
        case .topLeading: .bottomLeading
        case .top: .bottom
        case .topTrailing: .bottomTrailing
        case .bottomLeading: .topLeading
        case .bottom: .top
        case .bottomTrailing: .topTrailing
        }
    }

    /// The others at the same edge, nearest first.
    var neighborsAtSameEdge: [ReadAloudPlayerPosition] {
        switch self {
        case .topLeading: [.top, .topTrailing]
        case .top: [.topLeading, .topTrailing]
        case .topTrailing: [.top, .topLeading]
        case .bottomLeading: [.bottom, .bottomTrailing]
        case .bottom: [.bottomLeading, .bottomTrailing]
        case .bottomTrailing: [.bottom, .bottomLeading]
        }
    }

    /// Where a drag that ends at a point leaves the player: the window's thirds across and
    /// halves down.
    static func nearest(to point: CGPoint, in container: CGRect) -> ReadAloudPlayerPosition {
        guard container.width > 0, container.height > 0 else { return .bottom }
        let isTop = point.y < container.midY
        let third = (point.x - container.minX) / container.width
        switch (isTop, third) {
        case (true, ..<(1.0 / 3)): return .topLeading
        case (true, ...(2.0 / 3)): return .top
        case (true, _): return .topTrailing
        case (false, ..<(1.0 / 3)): return .bottomLeading
        case (false, ...(2.0 / 3)): return .bottom
        default: return .bottomTrailing
        }
    }
}

/// Places the floating player so it never covers the line being read: at its chosen place
/// while the highlighted words are clear of it, otherwise at the other edge, otherwise
/// beside it at the same edge.
enum ReadAloudPlayerPlacement {
    static let panelWidth: CGFloat = 340
    /// Room around the panel: from the window's edges, below the toolbar and tab strip at
    /// the top, and for the close button on its corner.
    static let sideMargin: CGFloat = 20
    static let topInset: CGFloat = 70
    static let bottomInset: CGFloat = 18
    /// How close the highlighted words may come to the panel.
    static let clearance: CGFloat = 16

    static func insets(for position: ReadAloudPlayerPosition) -> EdgeInsets {
        EdgeInsets(top: position.isTop ? topInset : 0, leading: sideMargin, bottom: position.isTop ? 0 : bottomInset, trailing: sideMargin)
    }

    /// The panel's frame at a position, in the container's coordinates.
    static func frame(for position: ReadAloudPlayerPosition, panelSize: CGSize, in container: CGRect) -> CGRect {
        let insets = insets(for: position)
        let x: CGFloat
        switch position {
        case .topLeading, .bottomLeading: x = container.minX + insets.leading
        case .top, .bottom: x = container.midX - panelSize.width / 2
        case .topTrailing, .bottomTrailing: x = container.maxX - insets.trailing - panelSize.width
        }
        let y = position.isTop ? container.minY + insets.top : container.maxY - insets.bottom - panelSize.height
        return CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    static func position(saved: ReadAloudPlayerPosition, panelSize: CGSize, in container: CGRect, avoiding highlight: CGRect?) -> ReadAloudPlayerPosition {
        guard let highlight, !highlight.isEmpty, panelSize.width > 0, container.width > 0 else { return saved }
        func isClear(_ position: ReadAloudPlayerPosition) -> Bool {
            !frame(for: position, panelSize: panelSize, in: container).insetBy(dx: -clearance, dy: -clearance).intersects(highlight)
        }
        let candidates = [saved, saved.flipped] + saved.neighborsAtSameEdge + saved.flipped.neighborsAtSameEdge
        return candidates.first(where: isClear) ?? saved.flipped
    }
}
