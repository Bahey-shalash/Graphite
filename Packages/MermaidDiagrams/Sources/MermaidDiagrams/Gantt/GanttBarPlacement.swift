import CoreGraphics

/// Where a task's bar or milestone goes across its row, and its text: inside the bar when it fits with room on both
/// sides, else after the bar, or before it when only that side has room; a task without a start and an end has its
/// text at the plot's left.
struct GanttBarPlacement {
    /// The bar's left and right, or nil for a task without a start and an end.
    let span: ClosedRange<CGFloat>?
    let isMilestone: Bool
    let labelCenter: CGFloat
    let isLabelInside: Bool
    let labelColor: GanttLabelColor
    private let barHeight: CGFloat

    init(task: GanttTask, entry: GanttSchedule.Entry, labelWidth: CGFloat, scale: GanttTimeScale, barHeight: CGFloat) {
        self.barHeight = barHeight
        isMilestone = task.isMilestone
        let gap = GanttLayoutEngine.labelGap
        guard let start = entry.start, let end = entry.end else {
            span = nil
            labelCenter = scale.left + gap + labelWidth / 2
            isLabelInside = false
            labelColor = .muted
            return
        }
        var left = scale.offset(of: start)
        var right = max(scale.offset(of: entry.drawnEnd ?? end), left + (task.isMilestone ? 0 : GanttLayoutEngine.minimumBarWidth))
        if task.isMilestone {
            let middle = left + (scale.offset(of: end) - left) / 2
            left = middle - barHeight / 2
            right = middle + barHeight / 2
        }
        span = left...right
        isLabelInside = !task.isMilestone && labelWidth + 2 * gap <= right - left
        if isLabelInside {
            labelCenter = (left + right) / 2
        } else {
            let fitsAfter = right + gap + labelWidth <= scale.right + scale.rightPadding
            let fitsBefore = left - gap - labelWidth >= scale.left
            labelCenter = fitsAfter || !fitsBefore ? right + gap + labelWidth / 2 : left - gap - labelWidth / 2
        }
        labelColor = Self.labelColor(task: task, isInside: isLabelInside)
    }

    func shape(rowMiddle: CGFloat) -> GanttTaskShape {
        guard let span else { return .unscheduled }
        let frame = CGRect(x: span.lowerBound, y: rowMiddle - barHeight / 2, width: span.upperBound - span.lowerBound, height: barHeight)
        return isMilestone ? .milestone(frame) : .bar(frame)
    }

    /// The page's color on a bar of a task neither done nor active; muted beside a done task; else the text's color.
    private static func labelColor(task: GanttTask, isInside: Bool) -> GanttLabelColor {
        if isInside { return task.isActive || task.isDone ? .foreground : .background }
        return task.isDone && !task.isActive ? .muted : .foreground
    }
}

extension GanttTaskPaint {
    /// Pele's colors for a task: active before done, critical in place of the accent.
    init(task: GanttTask) {
        if task.isActive {
            fill = task.isCritical ? .faintCritical : .faintAccent
            stroke = task.isCritical ? .critical : .accent
        } else if task.isDone {
            fill = .alternateSurface
            stroke = task.isCritical ? .critical : .border
        } else {
            fill = task.isCritical ? .critical : .accent
            stroke = task.isCritical ? .critical : .accent
        }
    }
}
