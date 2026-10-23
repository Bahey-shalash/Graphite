import CoreGraphics

/// Places a Gantt chart's rows and axis, as Pele's renderer does, once the chart is scheduled: the time scale across
/// the plot, each task's bar or milestone and its text, the axis' dates and grid lines, the section bands and names,
/// the excluded days and today's line. `extent` grows to the right edge of whatever is placed.
struct GanttPlotBuilder<Measurer: DiagramTextMeasuring> {
    let metrics: GanttMetrics
    let scale: GanttTimeScale
    let top: CGFloat
    let bottom: CGFloat
    private(set) var extent: CGFloat
    private(set) var tasks: [GanttLayoutTask] = []
    private(set) var gridLineOffsets: [CGFloat] = []
    private(set) var axisDates: [DiagramTextBlock] = []
    private let chart: GanttChart
    private let schedule: [GanttSchedule.Entry]
    private let span: GanttTimeSpan
    private let zone: GanttTimeZone
    private let measurers: GanttMeasurers<Measurer>
    private let sections: GanttSectionRows

    init(chart: GanttChart, schedule: [GanttSchedule.Entry], span: GanttTimeSpan, zone: GanttTimeZone, measurers: GanttMeasurers<Measurer>,
         top titleBottom: CGFloat) {
        self.chart = chart
        self.schedule = schedule
        self.span = span
        self.zone = zone
        self.measurers = measurers
        metrics = GanttMetrics(rowFontSize: measurers.row.fontSize, axisFontSize: measurers.axis.fontSize)
        sections = GanttSectionRows(tasks: chart.tasks, measurer: measurers.row)
        let axisFormat = chart.axisFormat.isEmpty ? (chart.dateFormat == "D" ? "%d" : "%Y-%m-%d") : chart.axisFormat
        let sampleWidth = [span.start, span.stop].map { time in measurers.axis.width(of: GanttAxisFormat.format(axisFormat, time, zone: zone)) }.max() ?? 0
        let left = GanttLayoutEngine.padding + max(sections.widestName > 0 ? sections.widestName + GanttLayoutEngine.sectionGap : 0, sampleWidth / 2)
        let rightPadding = max(GanttLayoutEngine.minimumRightPadding, sampleWidth / 2)
        let plotWidth = max(GanttLayoutEngine.minimumPlotWidth, GanttLayoutEngine.pageWidth - left - rightPadding - GanttLayoutEngine.padding)
        scale = GanttTimeScale(span: span, left: left, width: plotWidth, rightPadding: rightPadding, axisFormat: axisFormat, sampleWidth: sampleWidth)
        top = titleBottom + (chart.showsTopAxis ? metrics.tickHeight : 0)
        bottom = top + CGFloat(max(chart.tasks.count, 1)) * metrics.rowHeight
        extent = scale.right + rightPadding
    }

    /// Each task's shape and text, in its row.
    mutating func placeTasks() {
        for (row, task) in chart.tasks.enumerated() {
            let name = DiagramLabelDecoder.label(from: task.name, form: .plain).lines.joined(separator: " ")
            var label = DiagramTextBlock(label: DiagramLabel(name), measurer: measurers.row, maximumWidth: GanttLayoutEngine.wrappingWidth)
            let rowMiddle = top + CGFloat(row) * metrics.rowHeight + metrics.rowHeight / 2
            let placed = GanttBarPlacement(task: task, entry: schedule[row], labelWidth: label.size.width, scale: scale, barHeight: metrics.barHeight)
            label.center = CGPoint(x: placed.labelCenter, y: rowMiddle)
            if !placed.isLabelInside { extent = max(extent, placed.labelCenter + label.size.width / 2) }
            tasks.append(GanttLayoutTask(shape: placed.shape(rowMiddle: rowMiddle), paint: GanttTaskPaint(task: task), label: label,
                                         labelColor: placed.labelColor))
        }
    }

    /// The axis' grid lines and dates, a date left out where it would run into the one before it or repeat it.
    mutating func placeAxis() {
        let fittingCount = Int((scale.width / (scale.sampleWidth + GanttLayoutEngine.tickSpacing)).rounded(.down))
        let tickCount = min(max(fittingCount, GanttLayoutEngine.tickCountRange.lowerBound), GanttLayoutEngine.tickCountRange.upperBound)
        var lastRight = -CGFloat.greatestFiniteMagnitude
        var lastText = ""
        let intervalLimit = Int((scale.width / GanttLayoutEngine.intervalTickWidth).rounded(.up))
        let ticks = GanttAxisTicks.interval(chart.tickInterval, weekStart: chart.weekStart, from: span.start, to: span.stop, limit: intervalLimit)
            ?? GanttAxisTicks.automatic(from: span.start, to: span.stop, count: tickCount)
        for tick in ticks {
            let offset = scale.offset(of: tick)
            gridLineOffsets.append(offset)
            let text = GanttAxisFormat.format(scale.axisFormat, tick, zone: zone)
            let width = measurers.axis.width(of: text)
            guard offset - width / 2 >= lastRight + GanttLayoutEngine.labelGap, text != lastText else { continue }
            lastRight = offset + width / 2
            lastText = text
            extent = max(extent, lastRight)
            let distance = metrics.tickHeight / 2 + GanttLayoutEngine.axisDateGap
            let middles = [bottom + distance] + (chart.showsTopAxis ? [top - distance] : [])
            for middle in middles {
                var date = DiagramTextBlock(label: DiagramLabel(text), measurer: measurers.axis, maximumWidth: GanttLayoutEngine.wrappingWidth)
                date.center = CGPoint(x: offset, y: middle)
                axisDates.append(date)
            }
        }
    }

    /// The plot, with the section bands across the whole page, the excluded days and today's line.
    func finished(pageWidth: CGFloat, now: GanttTime) -> GanttPlot {
        let (bands, names) = sections.bandsAndNames(top: top, rowHeight: metrics.rowHeight, pageWidth: pageWidth)
        let isTodayShown = chart.todayMarker != .hidden && span.start < span.stop && now >= span.start && now <= span.stop
        return GanttPlot(frame: CGRect(x: scale.left, y: top, width: scale.width, height: bottom - top), showsTopAxis: chart.showsTopAxis,
                         sectionBands: bands, sectionNames: names, excludedDays: excludedDayRuns(), gridLineOffsets: gridLineOffsets,
                         axisDates: axisDates, tasks: tasks, todayOffset: isTodayShown ? scale.offset(of: now) : nil)
    }

    /// The runs of excluded days from the chart's start to its end, each from its first day's midnight to its last
    /// day's end, within the plot; none when the chart spans six years or more.
    private func excludedDayRuns() -> [CGRect] {
        let excludedDays = GanttExcludedDays(chart: chart, zone: zone)
        guard !excludedDays.isEmpty, let shadedSpanEnd = span.start.addingMonths(GanttLayoutEngine.excludedDaySpanMonths),
              shadedSpanEnd > span.stop else { return [] }
        var runs: [CGRect] = []
        var run: (first: GanttTime, last: GanttTime)?
        func closeRun() {
            guard let (first, last) = run else { return }
            run = nil
            let left = max(scale.left, scale.offset(of: first.startOfDay))
            let right = min(scale.right, scale.offset(of: GanttTime(milliseconds: last.startOfDay.milliseconds + GanttTime.millisecondsPerDay - 1)))
            if right > left { runs.append(CGRect(x: left, y: top, width: right - left, height: bottom - top)) }
        }
        var day: GanttTime? = span.start
        while let current = day, current <= span.stop {
            if excludedDays.isExcluded(current) { run = (run?.first ?? current, current) } else { closeRun() }
            day = current.addingDays(1)
        }
        closeRun()
        return runs
    }
}

/// The heights of a Gantt chart's rows and axis, from its text sizes, as Pele derives them.
struct GanttMetrics {
    let barHeight: CGFloat
    let rowHeight: CGFloat
    /// The height the axis' dates take below the rows.
    let tickHeight: CGFloat

    static let barHeightScale: CGFloat = 1.85
    /// The gap between rows, as a share of the bar's height.
    static let rowGapShare: CGFloat = 0.25
    static let tickHeightScale: CGFloat = 1.75

    init(rowFontSize: CGFloat, axisFontSize: CGFloat) {
        barHeight = (rowFontSize * Self.barHeightScale).rounded()
        rowHeight = barHeight + (barHeight * Self.rowGapShare).rounded()
        tickHeight = (axisFontSize * Self.tickHeightScale).rounded()
    }
}

/// Where a time falls across a Gantt chart's plot.
struct GanttTimeScale {
    let start: GanttTime
    let left: CGFloat
    let width: CGFloat
    /// The axis' format, in d3's specifiers.
    let axisFormat: String
    /// The width of the widest of the axis' first and last dates.
    let sampleWidth: CGFloat
    /// Points per millisecond, or zero when the chart spans no time and everything is at the middle.
    private let pointsPerMillisecond: CGFloat
    let rightPadding: CGFloat

    init(span: GanttTimeSpan, left: CGFloat, width: CGFloat, rightPadding: CGFloat, axisFormat: String, sampleWidth: CGFloat) {
        start = span.start
        self.left = left
        self.width = width
        self.rightPadding = rightPadding
        self.axisFormat = axisFormat
        self.sampleWidth = sampleWidth
        let duration = span.stop.milliseconds - span.start.milliseconds
        pointsPerMillisecond = duration > 0 ? width / CGFloat(duration) : 0
    }

    var right: CGFloat { left + width }

    func offset(of time: GanttTime) -> CGFloat {
        pointsPerMillisecond == 0 ? left + width / 2 : left + CGFloat(time.milliseconds - start.milliseconds) * pointsPerMillisecond
    }
}
