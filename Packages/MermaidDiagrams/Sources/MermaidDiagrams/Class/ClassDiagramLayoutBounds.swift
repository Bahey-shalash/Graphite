import CoreGraphics

/// The rectangle a class diagram's drawing covers: its boxes, notes and interface names, its lines with their
/// curves' control points, room for the longest mark around each tip, and its texts with the patches behind them.
enum ClassDiagramLayoutBounds {
    static func union(frames: [CGRect], edges: [ClassDiagramLayoutEdge]) -> CGRect {
        var bounds = frames.reduce(CGRect.null) { bounds, frame in bounds.union(frame) }
        for edge in edges {
            for point in points(of: edge.path) { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
            for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) {
                let reach = ClassDiagramMarkGeometry.longestMark
                bounds = bounds.union(CGRect(origin: mark.tip, size: .zero).insetBy(dx: -reach, dy: -reach))
            }
            if let text = edge.text {
                let room = ClassDiagramLayoutEngine.edgeTextRoom
                bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
            }
            for cardinality in [edge.sourceCardinality, edge.targetCardinality].compactMap({ cardinality in cardinality }) {
                bounds = bounds.union(cardinality.frame)
            }
        }
        return bounds.isNull ? .zero : bounds
    }

    private static func points(of path: DiagramPath) -> [CGPoint] {
        [path.start] + path.segments.flatMap { segment in
            switch segment {
            case .line(let end): [end]
            case .curve(let end, let firstControl, let secondControl): [end, firstControl, secondControl]
            }
        }
    }
}
