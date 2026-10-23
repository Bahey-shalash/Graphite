import CoreGraphics

/// Text in a box of fixed width, as Pele fits a timeline's: wrapped at spaces, and a word too wide for the box cut
/// between characters where it reaches the box's edge.
enum TimelineTextFitting {
    /// The label measured and wrapped at `maximumWidth`, without cutting a word.
    static func wrapped(_ label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
    }

    /// The label measured and wrapped at `maximumWidth`, a word wider than that cut into pieces that fit.
    static func fitted(_ label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock {
        let block = wrapped(label, measurer: measurer, maximumWidth: maximumWidth)
        guard block.size.width > maximumWidth else { return block }
        let cutLines = label.lines.flatMap { line in cut(line, measurer: measurer, maximumWidth: maximumWidth) }
        return wrapped(DiagramLabel(lines: cutLines), measurer: measurer, maximumWidth: maximumWidth)
    }

    /// The line broken before any character that would take a run of characters without a space past
    /// `maximumWidth`; a space starts a new run.
    private static func cut(_ line: String, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        var runWidth: CGFloat = 0
        for character in line {
            if character.isWhitespace {
                runWidth = 0
            } else {
                let width = measurer.width(of: String(character))
                if runWidth > 0, runWidth + width > maximumWidth {
                    lines.append(current)
                    current = ""
                    runWidth = 0
                }
                runWidth += width
            }
            current.append(character)
        }
        lines.append(current)
        return lines
    }
}
