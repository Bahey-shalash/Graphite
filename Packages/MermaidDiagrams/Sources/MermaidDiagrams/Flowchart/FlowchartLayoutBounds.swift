import CoreGraphics

/// The rectangle a flowchart's drawing covers: its shapes, its lines with their curves' control points, its marks
/// and its texts with the patches behind them.
enum FlowchartLayoutBounds {
    static func union(nodes: [FlowchartLayoutNode], edges: [FlowchartLayoutEdge]) -> CGRect {
        var bounds = CGRect.null
        for node in nodes { bounds = bounds.union(node.frame) }
        for edge in edges {
            bounds = bounds.union(CGRect(origin: edge.path.start, size: .zero))
            for segment in edge.path.segments {
                switch segment {
                case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
                case .curve(let end, let firstControl, let secondControl):
                    bounds = bounds.union(CGRect(origin: end, size: .zero)).union(CGRect(origin: firstControl, size: .zero))
                        .union(CGRect(origin: secondControl, size: .zero))
                }
            }
            for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) {
                bounds = bounds.union(CGRect(origin: mark.tip, size: .zero).insetBy(dx: -DiagramEdgeMark.arrowLength, dy: -DiagramEdgeMark.arrowLength))
            }
            if let text = edge.text {
                let room = FlowchartLayoutEngine.edgeTextRoom
                bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
            }
        }
        return bounds.isNull ? .zero : bounds
    }
}
