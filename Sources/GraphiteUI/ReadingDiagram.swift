import SwiftUI
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws.
enum ReadingDiagram: Sendable {
    /// A flowchart drawn natively.
    case flowchart(ReadingFlowchart)
    /// A diagram of a type drawn natively whose text could not be read or laid out: its source is shown with why.
    case unreadable(source: String, failure: ReadingDiagramFailure)
    /// A state diagram drawn natively.
    case stateDiagram(ReadingStateDiagram)
    /// A class diagram drawn natively.
    case classDiagram(ReadingClassDiagram)
    /// A sequence diagram drawn natively.
    case sequence(ReadingSequence)
    /// An entity relationship diagram drawn natively.
    case entityRelationship(ReadingEntityRelationshipDiagram)
    /// A mindmap drawn natively.
    case mindmap(ReadingMindmap)
    /// A timeline drawn natively.
    case timeline(ReadingTimeline)

    /// The diagram a block's text describes, laid out in `typography`, or nil when its type is not drawn natively
    /// yet (`MermaidDiagramReadError.unsupportedDiagramType`, a flowchart with subgraphs, a state diagram with
    /// composite states): the block is then shown as code, as it was before diagrams were drawn.
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
        case .stateDiagram(let stateDiagram):
            do {
                let layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard)
                self = .stateDiagram(ReadingStateDiagram(diagram: stateDiagram, layout: layout))
            } catch .compositeStatesNotLaidOut {
                return nil
            } catch {
                self = .unreadable(source: source, failure: .stateLayout(error))
            }
        case .classDiagram(let classDiagram):
            do {
                self = .classDiagram(ReadingClassDiagram(diagram: classDiagram,
                                                         layout: try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard)))
            } catch .namespacesNotLaidOut {
                return nil
            } catch {
                self = .unreadable(source: source, failure: .classLayout(error))
            }
        case .sequence(let sequence):
            do {
                self = .sequence(ReadingSequence(diagram: sequence, layout: try SequenceLayoutEngine.layout(sequence, typography: typography)))
            } catch {
                // `SequenceLayoutError.statementsNotLaidOut`, its one case: the diagram stays code.
                return nil
            }
        case .entityRelationship(let entityRelationship):
            guard let drawn = Self.drawnEntityRelationship(entityRelationship, source: source, typography: typography) else { return nil }
            self = drawn
        case .mindmap(let mindmap):
            self = .mindmap(ReadingMindmap(diagram: mindmap, layout: MindmapLayoutEngine.layout(mindmap, typography: typography)))
        case .timeline(let timeline):
            self = .timeline(ReadingTimeline(diagram: timeline, layout: TimelineLayoutEngine.layout(timeline, typography: typography)))
        }
    }
}

/// Why a diagram drawn natively was not drawn.
enum ReadingDiagramFailure: Equatable, Sendable {
    case reading(MermaidDiagramReadError)
    case layout(FlowchartLayoutError)
    case stateLayout(StateDiagramLayoutError)
    case classLayout(ClassDiagramLayoutError)
    case entityRelationshipLayout(EntityRelationshipLayoutError)
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
