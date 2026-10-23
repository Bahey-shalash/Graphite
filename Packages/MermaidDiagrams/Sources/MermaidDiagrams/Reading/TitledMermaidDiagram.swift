/// A diagram whose title is its own `title` statement's, else the front matter's: every type `MermaidDiagramReader` reads.
protocol TitledMermaidDiagram {
    var title: String? { get set }
}

extension FlowchartDiagram: TitledMermaidDiagram {}
extension StateDiagram: TitledMermaidDiagram {}
extension ClassDiagram: TitledMermaidDiagram {}
extension SequenceDiagram: TitledMermaidDiagram {}
extension EntityRelationshipDiagram: TitledMermaidDiagram {}
extension MindmapDiagram: TitledMermaidDiagram {}
extension TimelineDiagram: TitledMermaidDiagram {}
extension PieChart: TitledMermaidDiagram {}
extension GanttChart: TitledMermaidDiagram {}
extension GitGraphDiagram: TitledMermaidDiagram {}
extension UserJourneyDiagram: TitledMermaidDiagram {}
extension QuadrantChart: TitledMermaidDiagram {}
