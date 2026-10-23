import CoreGraphics

/// Lays a sequence diagram out in Pele's style: the participants side by side in the order they appear, as far apart
/// as the messages and notes between them need, each above its lifeline and again below it; then every message,
/// note, block and activation in a row of its own, top to bottom; the title above.
public enum SequenceLayoutEngine {
    public static func layout(_ diagram: SequenceDiagram, typography: DiagramTypography) throws(SequenceLayoutError) -> SequenceLayout {
        try layout(diagram, participantText: typography.nodeText, messageText: typography.edgeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SequenceDiagram, participantText: Measurer, messageText: Measurer,
                                                       font: DiagramFont) throws(SequenceLayoutError) -> SequenceLayout {
        guard diagram.statementsNotLaidOut.isEmpty else { throw .statementsNotLaidOut(diagram.statementsNotLaidOut) }
        let measurers = SequenceTextMeasurers(participantText: participantText, messageText: messageText)
        let columns = SequenceColumns(diagram: diagram, measurers: measurers)
        let extents = SequenceExtents(diagram: diagram, columns: columns, measurers: measurers)
        var rows = SequenceRows(diagram: diagram, columns: columns, extents: extents, measurers: measurers)
        rows.placeEvents()
        return assemble(rows, title: diagram.title.map { title in measurers.participantBlock(DiagramLabel(title)) }, font: font)
    }

    /// The participants above and below their lifelines, the title centered above everything, and the whole moved
    /// onto a page with Pele's padding around it.
    private static func assemble<Measurer>(_ rows: SequenceRows<Measurer>, title: DiagramTextBlock?, font: DiagramFont) -> SequenceLayout {
        var rows = rows
        let columns = rows.columns
        let lastRow = rows.y
        let footerHeight = columns.participantSizes.map(\.height).max() ?? 0
        if rows.extents.minimumX > rows.extents.maximumX { rows.extend(from: 0, to: max(title?.size.width ?? 0, emptyDiagramWidth)) }
        var topOfPage: CGFloat = 0
        var placedTitle = title.flatMap { block in block.lines.isEmpty ? nil : block }
        if let size = placedTitle?.size {
            let centerX = (rows.extents.minimumX + rows.extents.maximumX) / 2
            rows.extend(from: centerX - size.width / 2, to: centerX + size.width / 2)
            topOfPage = -size.height - SequenceSpacing.titleGap
            placedTitle?.center = CGPoint(x: centerX, y: topOfPage + size.height / 2)
        }
        let offset = CGVector(dx: SequenceSpacing.padding - rows.extents.minimumX, dy: SequenceSpacing.padding - topOfPage)
        let size = CGSize(width: (rows.extents.maximumX - rows.extents.minimumX + 2 * SequenceSpacing.padding).rounded(.up),
                          height: (lastRow + footerHeight - topOfPage + 2 * SequenceSpacing.padding).rounded(.up))
        return SequenceLayout(size: size, font: font,
                              participants: participants(rows, footerTop: lastRow).map { participant in participant.translated(by: offset) },
                              lifelines: columns.centers.map { center in
                                  SequenceLayoutLifeline(x: center, top: rows.lifelineTop, bottom: lastRow).translated(by: offset)
                              },
                              highlights: rows.highlights.reversed().map { highlight in highlight.translated(by: offset) },
                              activations: rows.activations.reversed().map { activation in activation.offsetBy(dx: offset.dx, dy: offset.dy) },
                              blocks: rows.blocks.map { block in block.translated(by: offset) },
                              messages: rows.messages.map { message in message.translated(by: offset) },
                              notes: rows.notes.map { note in note.translated(by: offset) },
                              title: placedTitle?.translated(by: offset))
    }

    /// Each participant above its lifeline, bottoms in line, then each below it from `footerTop`.
    private static func participants<Measurer>(_ rows: SequenceRows<Measurer>, footerTop: CGFloat) -> [SequenceLayoutParticipant] {
        let columns = rows.columns
        let kinds = rows.diagram.participants.map(\.kind)
        func placed(_ index: Int, top: CGFloat) -> SequenceLayoutParticipant {
            let size = columns.participantSizes[index]
            let frame = CGRect(x: columns.centers[index] - size.width / 2, y: top, width: size.width, height: size.height)
            var text = columns.participantTexts[index]
            text.center = SequenceParticipantGeometry.textCenter(of: kinds[index], in: frame, textHeight: text.size.height)
            return SequenceLayoutParticipant(kind: kinds[index], frame: frame, text: text)
        }
        let headers = kinds.indices.map { index in placed(index, top: rows.lifelineTop - columns.participantSizes[index].height) }
        return headers + kinds.indices.map { index in placed(index, top: footerTop) }
    }

    /// The width of a diagram with nothing in it, so that its title or its empty page has some room.
    private static var emptyDiagramWidth: CGFloat { 40 }
}
