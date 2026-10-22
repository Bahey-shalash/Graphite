import CoreGraphics

/// How `SequenceRows` places a message: a straight line from the source's lifeline, or the edge of its activation, to
/// the target's, its text above it; or, to the participant itself, a loop out to the right and back, its text beside it.
extension SequenceRows {
    mutating func placeMessage(_ message: SequenceMessage, at eventIndex: Int) {
        let startingActivationCount = activationsStarting(after: eventIndex, for: message.targetIndex)
        let placed = message.sourceIndex == message.targetIndex
            ? placeLoop(message, at: eventIndex, startingActivationCount: startingActivationCount)
            : placeLine(message, at: eventIndex, startingActivationCount: startingActivationCount)
        messages.append(placed.message)
        moveDown(to: placed.bottom)
    }

    /// How many activations of `participantIndex` the events right after a message start: a `+` belongs to the
    /// message, so its arrow stops at the new activation's edge.
    private func activationsStarting(after eventIndex: Int, for participantIndex: Int) -> Int {
        var count = 0
        for event in diagram.events[(eventIndex + 1)...] {
            switch event {
            case .activationStart(let index): if index == participantIndex { count += 1 }
            case .activationEnd: continue
            case .message, .note, .blockStart, .blockSection, .blockEnd, .numbering: return count
            }
        }
        return count
    }

    private mutating func placeLine(_ message: SequenceMessage, at eventIndex: Int,
                                    startingActivationCount: Int) -> (message: SequenceLayoutMessage, bottom: CGFloat) {
        let text = extents.eventTexts[eventIndex]
        let textHeight = text.map { block in block.lines.isEmpty ? 0 : block.size.height } ?? 0
        let lineY = y + SequenceSpacing.messageGap + (textHeight > 0 ? textHeight + SequenceSpacing.textRoom : SequenceSpacing.messageWithoutTextHeight)
        let direction: CGFloat = columns.centers[message.targetIndex] > columns.centers[message.sourceIndex] ? 1 : -1
        var start = direction > 0 ? rightEdge(of: message.sourceIndex) : leftEdge(of: message.sourceIndex)
        let end = direction > 0 ? leftEdge(of: message.targetIndex, extra: startingActivationCount)
                                : rightEdge(of: message.targetIndex, extra: startingActivationCount)
        let number = numberBadge(at: eventIndex, center: CGPoint(x: start, y: lineY))
        if let number { start += direction * number.frame.width / 2 }
        var heads: [SequenceLayoutArrowhead] = []
        let trim = Self.lineTrim(for: message.arrow.head)
        var lineStart = start
        if message.arrow.pointsBothWays, message.arrow.head != .none {
            heads.append(SequenceLayoutArrowhead(kind: message.arrow.head, tip: CGPoint(x: start, y: lineY), direction: CGVector(dx: -direction, dy: 0)))
            lineStart += direction * trim
        }
        if message.arrow.head != .none {
            heads.append(SequenceLayoutArrowhead(kind: message.arrow.head, tip: CGPoint(x: end, y: lineY), direction: CGVector(dx: direction, dy: 0)))
        }
        let path = DiagramPath(start: CGPoint(x: lineStart, y: lineY), segments: [.line(to: CGPoint(x: end - direction * trim, y: lineY))])
        var placedText: DiagramTextBlock?
        var patch: CGRect?
        if var block = text, block.size.width > 0 {
            block.center = CGPoint(x: (start + end) / 2, y: lineY - SequenceSpacing.messageTextGap - block.size.height / 2)
            extend(from: block.frame.minX, to: block.frame.maxX)
            patch = textPatch(around: block.center, size: block.size)
            placedText = block
        }
        return (SequenceLayoutMessage(stroke: message.arrow.stroke, path: path, heads: heads, text: placedText, textPatch: patch, number: number), lineY)
    }

    /// A message to the participant itself: out to the right of its activations at the top, down, and back in with
    /// rounded corners at the bottom; the text beside the loop, and the next row under the loop or the text.
    private mutating func placeLoop(_ message: SequenceMessage, at eventIndex: Int,
                                    startingActivationCount: Int) -> (message: SequenceLayoutMessage, bottom: CGFloat) {
        let text = extents.eventTexts[eventIndex]
        let textSize = text?.size ?? .zero
        let top = y + SequenceSpacing.messageGap + max(0, (textSize.height - SequenceSpacing.selfLoopHeight) / 2)
        let bottom = top + SequenceSpacing.selfLoopHeight
        var start = rightEdge(of: message.sourceIndex)
        let end = rightEdge(of: message.sourceIndex, extra: startingActivationCount)
        let numberWidth = columns.numberWidths[eventIndex]
        let outside = max(start, end) + SequenceSpacing.selfLoopWidth + numberWidth / 2
        let number = numberBadge(at: eventIndex, center: CGPoint(x: start, y: top))
        start += numberWidth / 2
        let trim = Self.lineTrim(for: message.arrow.head)
        var heads: [SequenceLayoutArrowhead] = []
        let leftward = CGVector(dx: -1, dy: 0)
        let pointsAtStart = message.arrow.pointsBothWays && message.arrow.head != .none
        if pointsAtStart { heads.append(SequenceLayoutArrowhead(kind: message.arrow.head, tip: CGPoint(x: start, y: top), direction: leftward)) }
        if message.arrow.head != .none { heads.append(SequenceLayoutArrowhead(kind: message.arrow.head, tip: CGPoint(x: end, y: bottom), direction: leftward)) }
        let path = Self.loopPath(from: CGPoint(x: start + (pointsAtStart ? trim : 0), y: top), outsideX: outside, bottom: bottom, endX: end + trim)
        let textLeft = outside + SequenceSpacing.selfLoopTextGap
        extend(from: columns.centers[message.sourceIndex], to: textLeft + textSize.width)
        var placedText: DiagramTextBlock?
        if var block = text, textSize.width > 0 {
            block.center = CGPoint(x: textLeft + textSize.width / 2, y: (top + bottom) / 2)
            placedText = block
        }
        let message = SequenceLayoutMessage(stroke: message.arrow.stroke, path: path, heads: heads, text: placedText, textPatch: nil, number: number)
        return (message, max(bottom, (top + bottom) / 2 + textSize.height / 2))
    }

    /// The loop's path: right along the top, a quarter circle down, down the side, a quarter circle back, and left
    /// along the bottom. Quarter circles are cubic curves.
    private static func loopPath(from start: CGPoint, outsideX: CGFloat, bottom: CGFloat, endX: CGFloat) -> DiagramPath {
        let radius = SequenceSpacing.selfLoopCornerRadius
        let control = radius * quarterCircleControlRatio
        let top = start.y
        return DiagramPath(start: start, segments: [
            .line(to: CGPoint(x: outsideX - radius, y: top)),
            .curve(to: CGPoint(x: outsideX, y: top + radius), control1: CGPoint(x: outsideX - radius + control, y: top),
                   control2: CGPoint(x: outsideX, y: top + radius - control)),
            .line(to: CGPoint(x: outsideX, y: bottom - radius)),
            .curve(to: CGPoint(x: outsideX - radius, y: bottom), control1: CGPoint(x: outsideX, y: bottom - radius + control),
                   control2: CGPoint(x: outsideX - radius + control, y: bottom)),
            .line(to: CGPoint(x: endX, y: bottom)),
        ])
    }

    /// The message's number badge centered at `center`, or nil when it shows no number.
    private func numberBadge(at eventIndex: Int, center: CGPoint) -> SequenceLayoutNumber? {
        guard let number = columns.numberTexts[eventIndex] else { return nil }
        let width = columns.numberWidths[eventIndex]
        var text = measurers.smallestBlock(number)
        text.center = center
        let height = SequenceSpacing.numberHeight
        return SequenceLayoutNumber(frame: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), text: text)
    }

    /// How much of the line a head takes, Pele's: an arrow all but a point of its length, a cross up to its center.
    static func lineTrim(for head: SequenceArrowhead) -> CGFloat {
        switch head {
        case .none, .open: 0
        case .arrow: DiagramEdgeMark.lineTrim(for: .arrow)
        case .cross: DiagramEdgeMark.lineTrim(for: .cross)
        }
    }

    /// The control-point distance, as a fraction of the radius, that makes a cubic curve follow a quarter circle.
    private static var quarterCircleControlRatio: CGFloat { 0.5523 }
}
