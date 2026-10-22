import CoreGraphics

/// Places a sequence diagram's events top to bottom, as Pele does while it draws: each message, note, block line
/// and activation takes the next row under the one before, and the participants are drawn above the first row and
/// mirrored under the last. Coordinates are relative to the first lifeline and the participants' top; the layout
/// moves them onto the page once everything is placed.
struct SequenceRows<Measurer: DiagramTextMeasuring> {
    let diagram: SequenceDiagram
    let columns: SequenceColumns
    let measurers: SequenceTextMeasurers<Measurer>
    private(set) var extents: SequenceExtents
    /// Where the next row starts.
    private(set) var y: CGFloat
    /// Where the participants above the lifelines end and the lifelines start.
    let lifelineTop: CGFloat
    /// For each participant, where each of its open activations started, innermost last.
    private(set) var activationStarts: [[CGFloat]]
    /// For each block, where its frame starts.
    private var frameTops: [CGFloat]
    /// For each block, its sections so far.
    private var frameSections: [[SequenceLayoutBlockSection]]
    private var frameTextPatches: [[CGRect]]
    /// What is placed, in the order it closes; the layout turns activations and highlights back to front.
    private(set) var activations: [CGRect] = []
    private(set) var highlights: [SequenceLayoutHighlight] = []
    private(set) var blocks: [SequenceLayoutBlock] = []
    var messages: [SequenceLayoutMessage] = []
    private(set) var notes: [SequenceLayoutNote] = []

    init(diagram: SequenceDiagram, columns: SequenceColumns, extents: SequenceExtents, measurers: SequenceTextMeasurers<Measurer>) {
        self.diagram = diagram
        self.columns = columns
        self.extents = extents
        self.measurers = measurers
        lifelineTop = columns.participantSizes.map(\.height).max() ?? 0
        y = lifelineTop + SequenceSpacing.firstRowGap
        activationStarts = Array(repeating: [], count: diagram.participants.count)
        frameTops = Array(repeating: 0, count: extents.frames.count)
        frameSections = Array(repeating: [], count: extents.frames.count)
        frameTextPatches = frameSections.map { _ in [] }
    }

    /// Places every event, then ends the activations still open under the last row.
    mutating func placeEvents() {
        for (eventIndex, event) in diagram.events.enumerated() {
            switch event {
            case .activationStart(let participantIndex): activationStarts[participantIndex].append(y)
            case .activationEnd(let participantIndex):
                if !activationStarts[participantIndex].isEmpty { y = max(y, endActivation(of: participantIndex, at: y)) }
            case .blockStart: startFrame(extents.frameIndexOfEvent[eventIndex])
            case .blockSection: addSection(to: extents.frameIndexOfEvent[eventIndex])
            case .blockEnd: endFrame(extents.frameIndexOfEvent[eventIndex])
            case .note(let note): placeNote(note, at: eventIndex)
            case .message(let message): placeMessage(message, at: eventIndex)
            case .numbering: continue
            }
        }
        y += SequenceSpacing.lastRowGap
        for participantIndex in diagram.participants.indices {
            while !activationStarts[participantIndex].isEmpty { _ = endActivation(of: participantIndex, at: y) }
        }
    }

    mutating func extend(from left: CGFloat, to right: CGFloat) {
        extents.extend(from: left, to: right)
    }

    mutating func moveDown(to row: CGFloat) {
        y = max(y, row)
    }

    // MARK: Activations

    /// The left side of a participant's activations, or its lifeline when it has none; `extra` counts activations
    /// about to start.
    func leftEdge(of participantIndex: Int, extra: Int = 0) -> CGFloat {
        let center = columns.centers[participantIndex]
        return activationStarts[participantIndex].count + extra > 0 ? center - SequenceSpacing.activationWidth / 2 : center
    }

    /// The right side of a participant's innermost activation, or its lifeline when it has none.
    func rightEdge(of participantIndex: Int, extra: Int = 0) -> CGFloat {
        let depth = activationStarts[participantIndex].count + extra
        let center = columns.centers[participantIndex]
        return depth > 0 ? center + SequenceSpacing.activationWidth / 2 + CGFloat(depth - 1) * SequenceSpacing.activationStep : center
    }

    /// Ends the innermost activation at `end`, at least its minimum height below its start, and returns its bottom.
    private mutating func endActivation(of participantIndex: Int, at end: CGFloat) -> CGFloat {
        guard let start = activationStarts[participantIndex].popLast() else { return end }
        let bottom = max(end, start + SequenceSpacing.activationMinimumHeight)
        let left = columns.centers[participantIndex] - SequenceSpacing.activationWidth / 2
            + CGFloat(activationStarts[participantIndex].count) * SequenceSpacing.activationStep
        extend(from: left, to: left + SequenceSpacing.activationWidth)
        activations.append(CGRect(x: left, y: start, width: SequenceSpacing.activationWidth, height: bottom - start))
        return bottom
    }

    // MARK: Notes

    /// A note under the row before, beside its lifeline past any activation, or over its lifelines.
    private mutating func placeNote(_ note: SequenceNote, at eventIndex: Int) {
        let text = extents.eventTexts[eventIndex]
        let textHeight = text?.size.height ?? 0
        let height = textHeight + 2 * SequenceSpacing.noteVerticalPadding
        let top = y + SequenceSpacing.noteGapAbove
        var left = extents.noteLefts[eventIndex]
        switch note.placement {
        case .rightOf(let participantIndex): left += rightEdge(of: participantIndex) - columns.centers[participantIndex]
        case .leftOf(let participantIndex): left += leftEdge(of: participantIndex) - columns.centers[participantIndex]
        case .over: break
        }
        let frame = CGRect(x: left, y: top, width: extents.noteWidths[eventIndex], height: height)
        extend(from: frame.minX, to: frame.maxX)
        var placedText = text ?? measurers.messageBlock(DiagramLabel(lines: []), wrappingWidth: nil)
        placedText.center = CGPoint(x: frame.midX, y: frame.midY)
        notes.append(SequenceLayoutNote(frame: frame, text: placedText))
        y = frame.maxY
    }

    // MARK: Blocks

    private mutating func startFrame(_ frameIndex: Int?) {
        guard let frameIndex else { return }
        let frame = extents.frames[frameIndex]
        guard frame.kind.keyword != nil else {
            frameTops[frameIndex] = y + SequenceSpacing.highlightGap
            y = frameTops[frameIndex]
            return
        }
        frameTops[frameIndex] = y + SequenceSpacing.frameGap
        let titleHeight = frame.texts.first.flatMap { text in text?.size.height } ?? 0
        y = frameTops[frameIndex] + max(SequenceSpacing.tabHeight, titleHeight + SequenceSpacing.textRoom)
    }

    /// `else`, `and` or `option`: a dashed line across the block, its text under it.
    private mutating func addSection(to frameIndex: Int?) {
        guard let frameIndex else { return }
        let frame = extents.frames[frameIndex]
        let lineY = y + SequenceSpacing.frameGap
        let sectionNumber = frameSections[frameIndex].count + 1
        var text = sectionNumber < frame.texts.count ? frame.texts[sectionNumber] : nil
        if let width = text?.size.width, let height = text?.size.height {
            let center = CGPoint(x: frame.left + SequenceSpacing.frameTextInset + width / 2, y: lineY + SequenceSpacing.textRoom + height / 2)
            text?.center = center
            if let patch = textPatch(around: center, size: CGSize(width: width, height: height)) { frameTextPatches[frameIndex].append(patch) }
        }
        frameSections[frameIndex].append(SequenceLayoutBlockSection(lineY: lineY, text: text))
        y += SequenceSpacing.frameGap + (text?.size.height ?? 0)
    }

    private mutating func endFrame(_ frameIndex: Int?) {
        guard let frameIndex else { return }
        let extent = extents.frames[frameIndex]
        let top = frameTops[frameIndex]
        let bottom = y + SequenceSpacing.frameGap
        let frame = CGRect(x: extent.left, y: top, width: extent.right - extent.left, height: bottom - top)
        y = bottom
        guard var keyword = extent.keyword else {
            if case .highlight(let color) = extent.kind { highlights.append(SequenceLayoutHighlight(frame: frame, color: color)) }
            return
        }
        let tab = CGRect(x: frame.minX, y: top, width: extent.tabWidth, height: SequenceSpacing.tabHeight)
        keyword.center = CGPoint(x: tab.midX, y: tab.midY)
        var title = extent.texts.first ?? nil
        if let size = title?.size {
            let center = CGPoint(x: tab.maxX + SequenceSpacing.frameTextInset + size.width / 2, y: top + max(SequenceSpacing.tabHeight, size.height) / 2)
            title?.center = center
            if let patch = textPatch(around: center, size: size) { frameTextPatches[frameIndex].append(patch) }
        }
        blocks.append(SequenceLayoutBlock(frame: frame, tab: tab, keyword: keyword, title: title, sections: frameSections[frameIndex],
                                          textPatches: frameTextPatches[frameIndex]))
    }

    // MARK: Text patches

    /// A patch of the background behind text centered at `center`, when a lifeline runs across the text; nil otherwise.
    func textPatch(around center: CGPoint, size: CGSize) -> CGRect? {
        guard size.width > 0, isCrossedByALifeline(from: center.x - size.width / 2, to: center.x + size.width / 2) else { return nil }
        return CGRect(x: center.x - size.width / 2 - SequenceSpacing.textPatchOutset, y: center.y - size.height / 2 + SequenceSpacing.textPatchInset,
                      width: size.width + 2 * SequenceSpacing.textPatchOutset, height: size.height - 2 * SequenceSpacing.textPatchInset)
    }

    /// Whether a lifeline runs strictly between `left` and `right`, by binary search over the ordered lifelines.
    private func isCrossedByALifeline(from left: CGFloat, to right: CGFloat) -> Bool {
        let centers = columns.centers
        var low = 0
        var high = centers.count
        while low < high {
            let middle = (low + high) / 2
            if centers[middle] <= left { low = middle + 1 } else { high = middle }
        }
        return low < centers.count && centers[low] < right
    }
}
