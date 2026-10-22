import CoreGraphics
@testable import MermaidDiagrams

/// Measures every character as `characterWidth` wide, so that layout tests do not depend on installed fonts.
struct UniformWidthTextMeasurer: DiagramTextMeasuring {
    var characterWidth: CGFloat = 8
    var fontSize: CGFloat = 16
    var lineHeight: CGFloat = 24

    func width(of text: String) -> CGFloat {
        CGFloat(text.count) * characterWidth
    }
}

/// Lays a flowchart out with uniform-width text, nodes and edges alike.
enum UniformWidthLayout {
    static let font = DiagramFont(postScriptName: nil, size: 16)

    static func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> FlowchartLayout {
        let diagram = try FlowchartReading.flowchart(source)
        return try FlowchartLayoutEngine.layout(diagram, nodeText: UniformWidthTextMeasurer(), edgeText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                font: font, limits: limits)
    }
}
