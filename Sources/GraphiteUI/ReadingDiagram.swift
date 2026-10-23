import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws.
enum ReadingDiagram: Sendable {
    /// A flowchart drawn natively.
    case flowchart(ReadingFlowchart)
    /// A pie chart drawn natively.
    case pieChart(ReadingPieChart)
    /// A Gantt chart drawn natively.
    case ganttChart(ReadingGanttChart)
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
    /// An XY chart drawn natively.
    case xyChart(ReadingXYChart)

    /// The diagram a block's text describes, laid out in `typography`, or nil when its type is not drawn natively
    /// yet (`MermaidDiagramReadError.unsupportedDiagramType`) or it holds what its type does not lay out yet (a
    /// flowchart's collapsed group, a state diagram's composite state, a class diagram's namespace, a sequence
    /// diagram's box): the block is then shown as code, as it was before diagrams were drawn.
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
        guard let drawn = Self.drawn(diagram, source: source, typography: typography) else { return nil }
        self = drawn
    }

    /// `diagram` laid out in `typography`, `unreadable` when its layout fails, or nil when it holds what its type does
    /// not lay out yet.
    private static func drawn(_ diagram: MermaidDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram? {
        switch diagram {
        case .flowchart(let flowchart): drawnFlowchart(flowchart, source: source, typography: typography)
        case .stateDiagram(let stateDiagram): drawnStateDiagram(stateDiagram, source: source, typography: typography)
        case .classDiagram(let classDiagram): drawnClassDiagram(classDiagram, source: source, typography: typography)
        case .sequence(let sequence): drawnSequence(sequence, typography: typography)
        case .entityRelationship(let entityRelationship): drawnEntityRelationship(entityRelationship, source: source, typography: typography)
        case .mindmap(let mindmap): .mindmap(ReadingMindmap(diagram: mindmap, layout: MindmapLayoutEngine.layout(mindmap, typography: typography)))
        case .timeline(let timeline): .timeline(ReadingTimeline(diagram: timeline, layout: TimelineLayoutEngine.layout(timeline, typography: typography)))
        case .pieChart(let chart): .pieChart(ReadingPieChart(chart: chart, layout: PieChartLayoutEngine.layout(chart, typography: typography)))
        case .ganttChart(let chart):
            ReadingGanttChart.diagram(source: source, chart: chart, typography: typography, now: WallClock.currentDate(),
                                      timeZone: WallClock.currentTimeZone())
        case .xyChart(let chart): ReadingXYChart.diagram(source: source, chart: chart, typography: typography)
        }
    }

    private static func drawnFlowchart(_ flowchart: FlowchartDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram? {
        do {
            return .flowchart(ReadingFlowchart(diagram: flowchart, layout: try FlowchartLayoutEngine.layout(flowchart, typography: typography,
                                                                                                          limits: .standard)))
        } catch .subgraphsNotLaidOut {
            return nil
        } catch {
            return .unreadable(source: source, failure: .layout(error))
        }
    }

    private static func drawnStateDiagram(_ stateDiagram: StateDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram? {
        do {
            let layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard)
            return .stateDiagram(ReadingStateDiagram(diagram: stateDiagram, layout: layout))
        } catch .compositeStatesNotLaidOut {
            return nil
        } catch {
            return .unreadable(source: source, failure: .stateLayout(error))
        }
    }

    private static func drawnClassDiagram(_ classDiagram: ClassDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram? {
        do {
            let layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard)
            return .classDiagram(ReadingClassDiagram(diagram: classDiagram, layout: layout))
        } catch .namespacesNotLaidOut {
            return nil
        } catch {
            return .unreadable(source: source, failure: .classLayout(error))
        }
    }

    /// A sequence diagram, or nil for `SequenceLayoutError.statementsNotLaidOut`.
    private static func drawnSequence(_ sequence: SequenceDiagram, typography: DiagramTypography) -> ReadingDiagram? {
        guard let layout = try? SequenceLayoutEngine.layout(sequence, typography: typography) else { return nil } // A statement not laid out yet: code.
        return .sequence(ReadingSequence(diagram: sequence, layout: layout))
    }
}

/// Why a diagram drawn natively was not drawn.
enum ReadingDiagramFailure: Equatable, Sendable {
    case reading(MermaidDiagramReadError)
    case layout(FlowchartLayoutError)
    case stateLayout(StateDiagramLayoutError)
    case classLayout(ClassDiagramLayoutError)
    case entityRelationshipLayout(EntityRelationshipLayoutError)
    case ganttLayout(GanttLayoutError)
    case xyChartLayout(XYChartLayoutError)
}

/// A flowchart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingFlowchart: Sendable {
    let layout: FlowchartLayout
    let shapes: ReadingFlowchartShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The text of each node drawn, in the order the diagram names them, then each group's title.
    let nodeTexts: [String]

    init(diagram: FlowchartDiagram, layout: FlowchartLayout) {
        self.layout = layout
        shapes = ReadingFlowchartShapes(parts: FlowchartDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        let groupNodes = Set(diagram.subgraphs.compactMap(\.representingNodeIndex))
        nodeTexts = diagram.nodes.indices.filter { node in !groupNodes.contains(node) }.map { node in diagram.nodes[node].label.spokenText }
            + diagram.subgraphs.map(\.title.spokenText).filter { title in !title.isEmpty }
    }
}
