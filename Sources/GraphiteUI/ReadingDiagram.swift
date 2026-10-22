import SwiftUI
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws.
enum ReadingDiagram: Sendable {
    /// A flowchart drawn natively.
    case flowchart(ReadingFlowchart)
    /// A diagram of a type drawn natively whose text could not be read or laid out: its source is shown with why.
    case unreadable(source: String, failure: ReadingDiagramFailure)

    /// The diagram a block's text describes, laid out in `typography`, or nil when its type is not drawn natively
    /// yet (`MermaidDiagramReadError.unsupportedDiagramType`, a flowchart with subgraphs): the block is then shown
    /// as code, as it was before diagrams were drawn.
    init?(source: String, typography: DiagramTypography) {
        let diagram: MermaidDiagram
        do {
            diagram = try MermaidDiagramReader.read(source, limits: .standard)
        } catch .unsupportedDiagramType {
            return nil
        } catch {
            self = .unreadable(source: source, failure: .reading(error))
            return
        }
        switch diagram {
        case .flowchart(let flowchart):
            do {
                self = .flowchart(ReadingFlowchart(diagram: flowchart, layout: try FlowchartLayoutEngine.layout(flowchart, typography: typography,
                                                                                                            limits: .standard)))
            } catch .subgraphsNotLaidOut {
                return nil
            } catch {
                self = .unreadable(source: source, failure: .layout(error))
            }
        case .stateDiagram:
            return nil
        }
    }
}

/// Why a diagram drawn natively was not drawn.
enum ReadingDiagramFailure: Equatable, Sendable {
    case reading(MermaidDiagramReadError)
    case layout(FlowchartLayoutError)
}

/// A flowchart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingFlowchart: Sendable {
    let layout: FlowchartLayout
    let shapes: ReadingFlowchartShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The text of each node, in the order the diagram names them.
    let nodeTexts: [String]

    init(diagram: FlowchartDiagram, layout: FlowchartLayout) {
        self.layout = layout
        shapes = ReadingFlowchartShapes(parts: FlowchartDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        nodeTexts = diagram.nodes.map(\.label.spokenText)
    }
}
