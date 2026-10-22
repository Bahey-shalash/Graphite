import CoreGraphics

/// The three sizes an entity relationship diagram's text is measured in, as Pele's: names at the font's size;
/// attribute rows and relationship labels at seven eighths of it (the flowchart's edge text); keys at three
/// quarters of it.
struct EntityRelationshipTextMeasurers<Measurer: DiagramTextMeasuring> {
    let name: Measurer
    let row: Measurer
    let key: EntityRelationshipKeyTextMeasurer<Measurer>

    /// Keys are three quarters of the names' size, rounded, as in Pele.
    static var keyTextScale: CGFloat { 0.75 }

    init(name: Measurer, row: Measurer) {
        self.name = name
        self.row = row
        key = EntityRelationshipKeyTextMeasurer(rowText: row, fontSize: (name.fontSize * Self.keyTextScale).rounded())
    }
}

/// Measures keys (`PK, FK`) at their own size from the widths the rows' measurer gives, in proportion to the two
/// sizes, so that no third font is read for a handful of capital letters. The column the keys sit in is followed
/// by a 16-point gap, which absorbs the difference from measuring them at their size.
struct EntityRelationshipKeyTextMeasurer<RowMeasurer: DiagramTextMeasuring>: DiagramTextMeasuring {
    let rowText: RowMeasurer
    let fontSize: CGFloat

    var lineHeight: CGFloat {
        (fontSize * CoreTextDiagramTextMeasurer.lineHeightRatio).rounded()
    }

    func width(of text: String) -> CGFloat {
        rowText.width(of: text) * fontSize / rowText.fontSize
    }
}
