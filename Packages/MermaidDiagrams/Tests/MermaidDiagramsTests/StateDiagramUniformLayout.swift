import CoreGraphics
@testable import MermaidDiagrams

/// Lays a state diagram out with uniform-width text: 8 points a character for names, 7 for the smaller text.
enum StateDiagramUniformLayout {
    static func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> StateDiagramLayout {
        try StateDiagramLayoutEngine.layout(StateDiagramReading.stateDiagram(source), nameText: UniformWidthTextMeasurer(),
                                            smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                            font: UniformWidthLayout.font, limits: limits)
    }
}
