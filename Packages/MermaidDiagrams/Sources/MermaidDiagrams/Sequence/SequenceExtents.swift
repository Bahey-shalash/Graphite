import CoreGraphics

/// How far across the page each note, block and the whole diagram reach, worked out before the rows are placed as
/// Pele does: a block wraps what it holds with padding, widens to the right for its texts, and widens the block
/// around it. A text that wraps (`wrap:`) wraps again to the room its message or note has.
struct SequenceExtents {
    /// Each event's text when it is a message or a note, wrapped to its room; nil otherwise.
    private(set) var eventTexts: [DiagramTextBlock?]
    /// Each note's left edge and width, before activations move a note beside a lifeline; zero for other events.
    private(set) var noteLefts: [CGFloat]
    private(set) var noteWidths: [CGFloat]
    /// The blocks in the order they start.
    private(set) var frames: [SequenceFrameExtent] = []
    /// For each event, the index in `frames` of the block it starts, divides or ends; nil for other events.
    private(set) var frameIndexOfEvent: [Int?]
    private(set) var minimumX: CGFloat = .infinity
    private(set) var maximumX: CGFloat = -.infinity

    init<Measurer>(diagram: SequenceDiagram, columns: SequenceColumns, measurers: SequenceTextMeasurers<Measurer>) {
        eventTexts = columns.eventTexts
        noteLefts = Array(repeating: 0, count: diagram.events.count)
        noteWidths = noteLefts
        frameIndexOfEvent = Array(repeating: nil, count: diagram.events.count)
        for (index, size) in columns.participantSizes.enumerated() {
            extend(from: columns.centers[index] - size.width / 2, to: columns.centers[index] + size.width / 2)
        }
        var openFrameIndices: [Int] = []
        for (eventIndex, event) in diagram.events.enumerated() {
            switch event {
            case .blockStart(let kind, let label):
                frameIndexOfEvent[eventIndex] = frames.count
                openFrameIndices.append(frames.count)
                frames.append(SequenceFrameExtent(kind: kind, labels: [label]))
            case .blockSection(let label):
                guard let open = openFrameIndices.last else { continue }
                frameIndexOfEvent[eventIndex] = open
                frames[open].labels.append(label)
            case .blockEnd:
                guard let closed = openFrameIndices.popLast() else { continue }
                frameIndexOfEvent[eventIndex] = closed
                close(frameAt: closed, around: openFrameIndices.last, centers: columns.centers, measurers: measurers)
            case .message(let message):
                let (left, right) = placeMessage(message, at: eventIndex, columns: columns, measurers: measurers)
                include(from: left, to: right, in: openFrameIndices.last)
            case .note(let note):
                let (left, right) = placeNote(note, at: eventIndex, centers: columns.centers, measurers: measurers)
                include(from: left, to: right, in: openFrameIndices.last)
            case .activationStart, .activationEnd, .numbering:
                continue
            }
        }
    }

    mutating func extend(from left: CGFloat, to right: CGFloat) {
        minimumX = min(minimumX, left)
        maximumX = max(maximumX, right)
    }

    /// The reach of a message across the page; a message that wraps wraps again to the room between its lifelines.
    private mutating func placeMessage<Measurer>(_ message: SequenceMessage, at eventIndex: Int, columns: SequenceColumns,
                                                 measurers: SequenceTextMeasurers<Measurer>) -> (CGFloat, CGFloat) {
        let source = columns.centers[message.sourceIndex]
        let target = columns.centers[message.targetIndex]
        if message.sourceIndex == message.targetIndex {
            let textWidth = eventTexts[eventIndex]?.size.width ?? 0
            return (source, source + SequenceSpacing.activationWidth + SequenceSpacing.selfLoopWidth + SequenceSpacing.selfLoopTextGap + textWidth
                        + columns.numberWidths[eventIndex])
        }
        let left = min(source, target)
        let right = max(source, target)
        if message.wrapsText {
            let room = right - left - 2 * SequenceSpacing.messagePadding - SequenceSpacing.activationWidth
            eventTexts[eventIndex] = measurers.messageBlock(message.text, wrappingWidth: max(SequenceSpacing.wrappingWidth, room))
        }
        return (left, right)
    }

    /// Where a note goes across the page: beside its lifeline, centered over it, or across the lifelines it spans
    /// with an overhang, wider for its text.
    private mutating func placeNote<Measurer>(_ note: SequenceNote, at eventIndex: Int, centers: [CGFloat],
                                              measurers: SequenceTextMeasurers<Measurer>) -> (CGFloat, CGFloat) {
        var width = (eventTexts[eventIndex]?.size.width ?? 0) + 2 * SequenceSpacing.notePadding
        let left: CGFloat
        switch note.placement {
        case .leftOf(let index): left = centers[index] - SequenceSpacing.noteGap - width
        case .rightOf(let index): left = centers[index] + SequenceSpacing.noteGap
        case .over(let first, let last) where first == last: left = centers[first] - width / 2
        case .over(let first, let last):
            let start = min(centers[first], centers[last]) - SequenceSpacing.noteOverhang
            let end = max(centers[first], centers[last]) + SequenceSpacing.noteOverhang
            if note.wrapsText {
                let room = end - start - 2 * SequenceSpacing.notePadding
                let wrapped = measurers.messageBlock(note.text, wrappingWidth: max(SequenceSpacing.wrappingWidth, room))
                eventTexts[eventIndex] = wrapped
                width = wrapped.size.width + 2 * SequenceSpacing.notePadding
            }
            width = max(end - start, width)
            left = (start + end - width) / 2
        }
        noteLefts[eventIndex] = left
        noteWidths[eventIndex] = width
        return (left, left + width)
    }

    /// Widens the diagram, and the innermost open block with its padding, to reach from `left` to `right`.
    private mutating func include(from left: CGFloat, to right: CGFloat, in frameIndex: Int?) {
        extend(from: left, to: right)
        guard let frameIndex else { return }
        frames[frameIndex].left = min(frames[frameIndex].left, left - SequenceSpacing.framePadding)
        frames[frameIndex].right = max(frames[frameIndex].right, right + SequenceSpacing.framePadding)
    }

    /// A block's reach once everything in it is known: across every lifeline when it holds nothing, then wider to
    /// the right for its texts, which wrap at the room they have or at the block text width.
    private mutating func close<Measurer>(frameAt index: Int, around parentIndex: Int?, centers: [CGFloat], measurers: SequenceTextMeasurers<Measurer>) {
        var frame = frames[index]
        if frame.left > frame.right {
            let emptyDiagramWidth: CGFloat = 120
            frame.left = centers.first.map { first in first - SequenceSpacing.framePadding } ?? 0
            frame.right = centers.last.map { last in last + SequenceSpacing.framePadding } ?? emptyDiagramWidth
        }
        if let keyword = frame.kind.keyword {
            let keywordBlock = measurers.smallestBlock(keyword)
            frame.keyword = keywordBlock
            frame.tabWidth = keywordBlock.size.width + SequenceSpacing.tabExtraWidth
            for (labelIndex, label) in frame.labels.enumerated() {
                let besideTab = labelIndex == 0 ? frame.tabWidth + SequenceSpacing.frameTextInset : 0
                let room = frame.right - frame.left - 2 * SequenceSpacing.frameTextInset - besideTab
                let text = Self.bracketed(label).map { bracketed in
                    measurers.messageBlock(bracketed, wrappingWidth: max(room, SequenceSpacing.frameTextWidth))
                }
                if let width = text?.size.width, width > room { frame.right += width - room }
                frame.texts.append(text)
            }
        }
        frames[index] = frame
        extend(from: frame.left, to: frame.right)
        guard let parentIndex else { return }
        frames[parentIndex].left = min(frames[parentIndex].left, frame.left - SequenceSpacing.frameNesting)
        frames[parentIndex].right = max(frames[parentIndex].right, frame.right + SequenceSpacing.frameNesting)
    }

    /// A block's text in brackets, as Pele draws it (`[Every minute]`); nil when the block has none.
    private static func bracketed(_ label: DiagramLabel) -> DiagramLabel? {
        guard !label.isEmpty else { return nil }
        var lines = label.lines
        lines[0] = "[" + lines[0]
        lines[lines.count - 1] += "]"
        return DiagramLabel(lines: lines)
    }
}

/// A block's reach across the page and its texts, while the diagram is laid out.
struct SequenceFrameExtent {
    let kind: SequenceBlockKind
    /// The text after the block's keyword, then the text of each section after the first.
    var labels: [DiagramLabel]
    var left: CGFloat = .infinity
    var right: CGFloat = -.infinity
    var tabWidth: CGFloat = 0
    /// The keyword in the tab; nil for a highlight.
    var keyword: DiagramTextBlock?
    /// For each label, its text in brackets, measured; nil for an empty label. Empty for a highlight.
    var texts: [DiagramTextBlock?] = []

    init(kind: SequenceBlockKind, labels: [DiagramLabel]) {
        self.kind = kind
        self.labels = labels
    }
}
