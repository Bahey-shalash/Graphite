import CoreGraphics

/// A laid-out Gantt chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`GanttRenderer`) or by a view's own shapes. Back to front, as Pele draws: the section
/// bands, the excluded days, the grid and the axis' line, today's line, the tasks' shapes, then the text.
public struct GanttDrawingParts {
    /// The bands behind every other section, filled in the surface color.
    public let sectionBands: CGPath
    /// The runs of excluded days, filled in the alternate surface color.
    public let excludedDays: CGPath
    /// The grid lines at the axis' dates, stroked one point wide in dots of 1 and gaps of 3, in the border color.
    public let gridLines: CGPath
    /// The axis' line under the rows, and above them with `topAxis`, stroked one point wide in the border color.
    public let axisLines: CGPath
    /// Today's line, stroked two points wide in the accent color; empty when it is not drawn.
    public let todayLine: CGPath
    /// The small triangle on top of today's line, filled in the accent color.
    public let todayMark: CGPath
    /// The tasks' bars and milestones, by fill; a faint fill is its color at a quarter of its opacity.
    public let taskFills: [GanttTaskFill: CGPath]
    /// The tasks' bars and milestones, by outline color, stroked one point wide with round joins.
    public let taskOutlines: [GanttTaskStroke: CGPath]
    /// Task text by its color.
    public let taskTexts: [GanttLabelColor: [DiagramTextBlock]]
    /// The sections' names, in the text color.
    public let sectionNames: [DiagramTextBlock]
    /// The axis' dates, in the muted color.
    public let axisDates: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let todayLineWidth: CGFloat = 2
    public static let gridDashLengths: [CGFloat] = [1, 3]
    /// The opacity of an active task's fill.
    public static let faintFillOpacity: CGFloat = 0.25
    /// Half the width of the triangle on top of today's line.
    static let todayMarkHalfWidth: CGFloat = 4
    /// How far above the plot the triangle's top is, and how far into it its point reaches.
    static let todayMarkRise: CGFloat = 5
    static let todayMarkReach: CGFloat = 1

    public init(layout: GanttLayout) {
        title = layout.title
        let frame = layout.plot?.frame ?? .zero
        let todayOffsets = layout.plot?.todayOffset.map { offset in [offset] } ?? []
        sectionBands = Self.rectangles(layout.plot?.sectionBands ?? [])
        excludedDays = Self.rectangles(layout.plot?.excludedDays ?? [])
        gridLines = Self.verticalLines(at: layout.plot?.gridLineOffsets ?? [], from: frame.minY, to: frame.maxY)
        let axes = CGMutablePath()
        let axisHeights = layout.plot.map { plot in [frame.maxY] + (plot.showsTopAxis ? [frame.minY] : []) } ?? []
        for height in axisHeights {
            axes.move(to: CGPoint(x: frame.minX, y: height))
            axes.addLine(to: CGPoint(x: frame.maxX, y: height))
        }
        axisLines = axes
        todayLine = Self.verticalLines(at: todayOffsets, from: frame.minY, to: frame.maxY)
        let mark = CGMutablePath()
        for offset in todayOffsets { mark.addPath(Self.todayMark(at: offset, top: frame.minY)) }
        todayMark = mark
        let tasks = layout.plot?.tasks ?? []
        (taskFills, taskOutlines) = Self.taskShapes(tasks)
        taskTexts = Dictionary(grouping: tasks, by: \.labelColor).mapValues { grouped in grouped.map(\.label) }
        sectionNames = layout.plot?.sectionNames ?? []
        axisDates = layout.plot?.axisDates ?? []
    }

    /// A task's outline: a bar with Pele's rounded corners, or a milestone's diamond; nil for a task without one.
    static func outline(of shape: GanttTaskShape) -> CGPath? {
        switch shape {
        case .bar(let frame):
            let radius = min(GanttLayoutEngine.barCornerRadius, frame.width / 2, frame.height / 2)
            return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .milestone(let frame):
            let diamond = CGMutablePath()
            diamond.addLines(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.midX, y: frame.maxY),
                                       CGPoint(x: frame.minX, y: frame.midY)])
            diamond.closeSubpath()
            return diamond
        case .unscheduled: return nil
        }
    }

    private static func taskShapes(_ tasks: [GanttLayoutTask]) -> ([GanttTaskFill: CGPath], [GanttTaskStroke: CGPath]) {
        var fills: [GanttTaskFill: CGMutablePath] = [:]
        var outlines: [GanttTaskStroke: CGMutablePath] = [:]
        for task in tasks {
            guard let outline = outline(of: task.shape) else { continue }
            // The paths are references: each is stored when first made, then added to.
            let fill = fills[task.paint.fill] ?? CGMutablePath()
            fills[task.paint.fill] = fill
            fill.addPath(outline)
            let stroke = outlines[task.paint.stroke] ?? CGMutablePath()
            outlines[task.paint.stroke] = stroke
            stroke.addPath(outline)
        }
        return (fills, outlines)
    }

    private static func rectangles(_ frames: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        path.addRects(frames)
        return path
    }

    private static func verticalLines(at offsets: [CGFloat], from top: CGFloat, to bottom: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for offset in offsets {
            path.move(to: CGPoint(x: offset, y: top))
            path.addLine(to: CGPoint(x: offset, y: bottom))
        }
        return path
    }

    /// Pele's triangle pointing down onto the top of today's line.
    private static func todayMark(at offset: CGFloat, top: CGFloat) -> CGPath {
        let mark = CGMutablePath()
        let markTop = top - todayMarkRise
        mark.addLines(between: [CGPoint(x: offset - todayMarkHalfWidth, y: markTop), CGPoint(x: offset + todayMarkHalfWidth, y: markTop),
                                CGPoint(x: offset, y: top + todayMarkReach)])
        mark.closeSubpath()
        return mark
    }
}
