import CoreGraphics

/// The three sizes of an XY chart's text, as Pele's: the title in bold at the text size, the axes and the legend at
/// seven eighths of it, and point labels at three quarters.
struct XYChartText<Measurer: DiagramTextMeasuring> {
    let titleText: Measurer
    let smallText: Measurer
    let tinyText: Measurer

    func title(_ label: DiagramLabel, maximumWidth: CGFloat) -> DiagramTextBlock? {
        block(label, measurer: titleText, maximumWidth: maximumWidth)
    }

    /// Text at the axes' size, or nil when the label is empty.
    func small(_ label: DiagramLabel, maximumWidth: CGFloat) -> DiagramTextBlock? {
        block(label, measurer: smallText, maximumWidth: maximumWidth)
    }

    /// Text at the axes' size, with no lines when the label is empty.
    func smallBlock(_ label: DiagramLabel, maximumWidth: CGFloat) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: smallText, maximumWidth: maximumWidth)
    }

    /// A point label, on lines as written.
    func tinyBlock(_ label: DiagramLabel) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: tinyText, maximumWidth: XYChartScaleMarks.unwrappedWidth)
    }

    private func block(_ label: DiagramLabel, measurer: Measurer, maximumWidth: CGFloat) -> DiagramTextBlock? {
        let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
        return block.lines.isEmpty ? nil : block
    }
}
