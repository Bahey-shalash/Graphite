import CoreGraphics

/// Where each participant's lifeline runs across the page, as Pele places them: neighbours at least their boxes'
/// half widths and the participant gap apart, and further where a message or a note between them needs the room. A
/// message across several lifelines widens each gap it crosses by an equal share of what is missing.
struct SequenceColumns {
    let participantTexts: [DiagramTextBlock]
    let participantSizes: [CGSize]
    /// Each lifeline's x, the first at 0.
    let centers: [CGFloat]
    /// Each event's text when it is a message or a note, measured and wrapped as its text asks; nil otherwise.
    let eventTexts: [DiagramTextBlock?]
    /// Each event's number under `autonumber`, or nil.
    let numberTexts: [String?]
    /// The width of each event's number badge, or 0.
    let numberWidths: [CGFloat]

    init<Measurer>(diagram: SequenceDiagram, measurers: SequenceTextMeasurers<Measurer>) {
        participantTexts = diagram.participants.map { participant in measurers.participantBlock(participant.label) }
        participantSizes = zip(diagram.participants, participantTexts).map { participant, text in
            SequenceParticipantGeometry.size(of: participant.kind, textSize: text.size, fontSize: measurers.participantText.fontSize)
        }
        numberTexts = SequenceMessageNumbers(events: diagram.events).numberTexts
        numberWidths = numberTexts.map { text in
            text.map { number in max(SequenceSpacing.numberHeight, measurers.smallestText.width(of: number) + SequenceSpacing.numberExtraWidth) } ?? 0
        }
        var requirements = WidthRequirements(participantCount: diagram.participants.count)
        var eventTexts: [DiagramTextBlock?] = []
        eventTexts.reserveCapacity(diagram.events.count)
        for (eventIndex, event) in diagram.events.enumerated() {
            switch event {
            case .note(let note):
                let text = measurers.messageBlock(note.text, wrappingWidth: note.wrapsText ? SequenceSpacing.wrappingWidth : nil)
                requirements.addNote(note.placement, width: text.size.width + 2 * SequenceSpacing.notePadding)
                eventTexts.append(text)
            case .message(let message):
                let text = measurers.messageBlock(message.text, wrappingWidth: message.wrapsText ? SequenceSpacing.wrappingWidth : nil)
                requirements.addMessage(from: message.sourceIndex, to: message.targetIndex, textWidth: text.size.width,
                                        numberWidth: numberWidths[eventIndex])
                eventTexts.append(text)
            case .activationStart, .activationEnd, .blockStart, .blockSection, .blockEnd, .numbering:
                eventTexts.append(nil)
            }
        }
        self.eventTexts = eventTexts
        centers = requirements.centers(participantWidths: participantSizes.map(\.width))
    }

    /// The width each gap between lifelines, or each run of gaps, must have at least.
    private struct WidthRequirements {
        let participantCount: Int
        /// By the first and last lifeline of the run (`first * participantCount + last`).
        private var widthByRun: [Int: CGFloat] = [:]

        init(participantCount: Int) {
            self.participantCount = participantCount
        }

        mutating func addNote(_ placement: SequenceNotePlacement, width: CGFloat) {
            let besideWidth = width + 2 * SequenceSpacing.noteGap + SequenceSpacing.activationWidth
            switch placement {
            case .leftOf(let index): require(from: index - 1, to: index, width: besideWidth)
            case .rightOf(let index): require(from: index, to: index + 1, width: besideWidth)
            case .over(let first, let last) where first == last:
                require(from: first - 1, to: first, width: width / 2 + SequenceSpacing.noteGap)
                require(from: first, to: first + 1, width: width / 2 + SequenceSpacing.noteGap)
            case .over(let first, let last):
                require(from: min(first, last), to: max(first, last), width: width - 2 * SequenceSpacing.noteOverhang)
            }
        }

        mutating func addMessage(from source: Int, to target: Int, textWidth: CGFloat, numberWidth: CGFloat) {
            if source == target {
                require(from: source, to: source + 1, width: SequenceSpacing.selfLoopWidth + SequenceSpacing.selfLoopTextGap + textWidth
                            + SequenceSpacing.selfLoopTextRoom + SequenceSpacing.activationWidth + numberWidth)
            } else {
                require(from: min(source, target), to: max(source, target),
                        width: textWidth + 2 * SequenceSpacing.messagePadding + SequenceSpacing.activationWidth + numberWidth)
            }
        }

        private mutating func require(from first: Int, to last: Int, width: CGFloat) {
            guard first >= 0, last < participantCount else { return }
            let key = first * participantCount + last
            widthByRun[key] = max(widthByRun[key] ?? 0, width)
        }

        /// Each lifeline's x: each gap is the wider of its boxes' needs and its own requirement, then each run of
        /// several gaps, the narrowest runs first, shares out what it still lacks.
        func centers(participantWidths: [CGFloat]) -> [CGFloat] {
            guard participantCount > 1 else { return participantWidths.map { _ in 0 } }
            var gaps = (0..<(participantCount - 1)).map { gapIndex in
                max(participantWidths[gapIndex] / 2 + participantWidths[gapIndex + 1] / 2 + SequenceSpacing.participantGap,
                    widthByRun[gapIndex * participantCount + gapIndex + 1] ?? 0)
            }
            let runs = widthByRun.compactMap { key, width -> (first: Int, last: Int, width: CGFloat)? in
                let first = key / participantCount
                let last = key % participantCount
                return last - first > 1 ? (first, last, width) : nil
            }.sorted { left, right in
                left.last - left.first != right.last - right.first ? left.last - left.first < right.last - right.first : left.first < right.first
            }
            for run in runs {
                let total = gaps[run.first..<run.last].reduce(0, +)
                guard total < run.width else { continue }
                let share = (run.width - total) / CGFloat(run.last - run.first)
                for gapIndex in run.first..<run.last { gaps[gapIndex] += share }
            }
            var centers = [CGFloat(0)]
            centers.reserveCapacity(participantCount)
            for gap in gaps { centers.append(centers[centers.count - 1] + gap) }
            return centers
        }
    }
}
