import CoreGraphics

/// Lines of text placed in a diagram: each line's width in the font it was measured in, and where the block's center is.
/// Lines are drawn centered on the block's center, one `lineHeight` apart.
public struct DiagramTextBlock: Equatable, Sendable {
    public let lines: [String]
    public let lineWidths: [CGFloat]
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public internal(set) var center: CGPoint

    public var size: CGSize {
        CGSize(width: lineWidths.max() ?? 0, height: CGFloat(lines.count) * lineHeight)
    }

    /// Measures `label` in `measurer`'s font, wrapping each line at spaces where it is wider than `maximumWidth`. A
    /// word wider than that stays whole on its own line. An empty label has no lines.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) {
        var lines: [String] = []
        var widths: [CGFloat] = []
        if !label.isEmpty {
            for line in label.lines {
                for (wrappedLine, width) in Self.wrapped(line, measurer: measurer, maximumWidth: maximumWidth) {
                    lines.append(wrappedLine)
                    widths.append(width)
                }
            }
        }
        self.lines = lines
        self.lineWidths = widths
        self.fontSize = measurer.fontSize
        self.lineHeight = measurer.lineHeight
        self.center = .zero
    }

    private static func wrapped(_ line: String, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> [(String, CGFloat)] {
        let width = measurer.width(of: line)
        guard width > maximumWidth, line.contains(" ") else { return [(line, width)] }
        var wrapped: [(String, CGFloat)] = []
        var current = ""
        var currentWidth: CGFloat = 0
        for word in line.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            let candidateWidth = measurer.width(of: candidate)
            if candidateWidth > maximumWidth, !current.isEmpty {
                wrapped.append((current, currentWidth))
                current = String(word)
                currentWidth = measurer.width(of: current)
            } else {
                current = candidate
                currentWidth = candidateWidth
            }
        }
        wrapped.append((current, currentWidth))
        return wrapped
    }
}

extension DiagramTextBlock {
    func translated(by offset: CGVector) -> DiagramTextBlock {
        var moved = self
        moved.center = center.translated(by: offset)
        return moved
    }

    /// The block's rectangle around its center.
    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
