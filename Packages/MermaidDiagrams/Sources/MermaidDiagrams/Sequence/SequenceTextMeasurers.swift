import CoreGraphics

/// The three text sizes of a sequence diagram, Pele's: participants in the note's size; messages, notes and block
/// texts seven eighths of it; the keywords in block tabs and the message numbers three quarters of it.
struct SequenceTextMeasurers<Measurer: DiagramTextMeasuring> {
    let participantText: Measurer
    let messageText: Measurer
    let smallestText: SequenceScaledTextMeasurer<Measurer>

    /// The smallest size as a fraction of the participants', rounded, as in Pele.
    static var smallestTextScale: CGFloat { 0.75 }

    init(participantText: Measurer, messageText: Measurer) {
        self.participantText = participantText
        self.messageText = messageText
        smallestText = SequenceScaledTextMeasurer(base: messageText, fontSize: (participantText.fontSize * Self.smallestTextScale).rounded())
    }

    func participantBlock(_ label: DiagramLabel) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: participantText, maximumWidth: .greatestFiniteMagnitude)
    }

    /// A message's, note's or block's text, wrapped at `wrappingWidth` when it is given.
    func messageBlock(_ label: DiagramLabel, wrappingWidth: CGFloat?) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: messageText, maximumWidth: wrappingWidth ?? .greatestFiniteMagnitude)
    }

    func smallestBlock(_ text: String) -> DiagramTextBlock {
        DiagramTextBlock(label: DiagramLabel(text), measurer: smallestText, maximumWidth: .greatestFiniteMagnitude)
    }
}

/// Measures text at a smaller size than another measurer, in proportion: a font's advances scale with its size, so
/// the smallest text of a diagram needs no font of its own read. Sizes with their own optical design can differ by a
/// fraction of a point, which the padding around such text absorbs.
struct SequenceScaledTextMeasurer<Base: DiagramTextMeasuring>: DiagramTextMeasuring {
    let base: Base
    let fontSize: CGFloat

    init(base: Base, fontSize: CGFloat) {
        self.base = base
        self.fontSize = fontSize
    }

    var lineHeight: CGFloat {
        (base.lineHeight * fontSize / base.fontSize).rounded()
    }

    func width(of text: String) -> CGFloat {
        base.width(of: text) * fontSize / base.fontSize
    }
}
