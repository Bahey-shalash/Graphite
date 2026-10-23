import SwiftUI
import MermaidDiagrams

/// A Gantt chart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `GanttDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on screen
/// and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingGanttChartShapes: Sendable {
    let sectionBands: Path
    let excludedDays: Path
    let gridLines: Path
    let axisLines: Path
    let todayLine: Path
    let todayMark: Path
    /// The tasks' shapes by fill, in a fixed order so that painting them is the same each time.
    let taskFills: [(fill: GanttTaskFill, path: Path)]
    /// The tasks' outlines by color, in a fixed order.
    let taskOutlines: [(stroke: GanttTaskStroke, path: Path)]
    /// Text inside the bars of planned tasks, drawn in the page's color.
    let backgroundTextLines: [ReadingDiagramTextLine]
    /// Text beside the bars, the sections' names and the title (bold, last), drawn in the text color.
    let foregroundTextLines: [ReadingDiagramTextLine]
    /// The axis' dates and the text of done or unscheduled tasks, drawn in the muted color.
    let mutedTextLines: [ReadingDiagramTextLine]

    private static let fillOrder: [GanttTaskFill] = [.alternateSurface, .faintAccent, .faintCritical, .accent, .critical]
    private static let strokeOrder: [GanttTaskStroke] = [.border, .accent, .critical]

    init(parts: GanttDrawingParts, font: DiagramFont) {
        sectionBands = Path(parts.sectionBands)
        excludedDays = Path(parts.excludedDays)
        gridLines = Path(parts.gridLines)
        axisLines = Path(parts.axisLines)
        todayLine = Path(parts.todayLine)
        todayMark = Path(parts.todayMark)
        taskFills = Self.fillOrder.compactMap { fill in parts.taskFills[fill].map { path in (fill, Path(path)) } }
        taskOutlines = Self.strokeOrder.compactMap { stroke in parts.taskOutlines[stroke].map { path in (stroke, Path(path)) } }
        func lines(_ blocks: [DiagramTextBlock]) -> [ReadingDiagramTextLine] {
            blocks.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        }
        backgroundTextLines = lines(parts.taskTexts[.background] ?? [])
        foregroundTextLines = lines((parts.taskTexts[.foreground] ?? []) + parts.sectionNames)
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        mutedTextLines = lines((parts.taskTexts[.muted] ?? []) + parts.axisDates)
    }
}
