import CoreGraphics

/// A laid-out entity relationship diagram's geometry grouped by how it is painted, so that drawing it in any colors is
/// a handful of fills and strokes, by Core Graphics (`EntityRelationshipRenderer`) or by a view's own shapes. Back to
/// front, as Pele draws: the lines and their marks, the labels on their patches, the boxes with their striped rows,
/// outlines and header dividers, the boxes' text, the title.
public struct EntityRelationshipDrawingParts {
    /// Identifying relationships, stroked one point wide with round caps.
    public let identifyingLines: CGPath
    /// Non-identifying relationships, stroked one point wide in dashes of 4 and gaps of 3.
    public let nonIdentifyingLines: CGPath
    /// The rings and diamonds of the cardinality marks, filled in the background color so that the line does not show
    /// through them.
    public let markFills: CGPath
    /// Every mark's bars, feet, rings and diamonds, stroked one point wide in the line color, solid on any line.
    public let markOutlines: CGPath
    /// The patches behind the labels, filled in the background color.
    public let labelPatches: CGPath
    public let labels: [DiagramTextBlock]
    /// The boxes, filled in the surface color.
    public let boxFills: CGPath
    /// The first attribute row of each box and every second one after it, filled in the background color.
    public let rowStripes: CGPath
    /// The boxes' outlines and the lines under their headers, stroked one point wide in the border color.
    public let boxOutlines: CGPath
    /// The entities' names and their attributes' names, in the text color.
    public let entityTexts: [DiagramTextBlock]
    /// The attributes' types, keys and comments, in the muted text color.
    public let attributeDetails: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let nonIdentifyingDashLengths: [CGFloat] = [4, 3]
    /// The opacity of the text color that types, keys and comments are drawn at: Pele's muted gray (#6e6e6e) is its
    /// text (#1f1f1f) at this opacity over its white page.
    public static let mutedTextOpacity: CGFloat = 0.647

    /// The corner radius of a box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    /// The corner radius of the patch behind a label.
    static let labelPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a label is.
    static let labelPatchExtraWidth: CGFloat = 8

    public init(layout: EntityRelationshipLayout) {
        let identifyingLines = CGMutablePath()
        let nonIdentifyingLines = CGMutablePath()
        let markFills = CGMutablePath()
        let markOutlines = CGMutablePath()
        let labelPatches = CGMutablePath()
        for relationship in layout.relationships {
            let line = DiagramEdgeDrawing.path(relationship.path)
            switch relationship.identification {
            case .identifying: identifyingLines.addPath(line)
            case .nonIdentifying: nonIdentifyingLines.addPath(line)
            }
            for mark in [relationship.firstEntityMark, relationship.secondEntityMark] {
                EntityRelationshipCardinalityDrawing.addMark(mark, fills: markFills, outlines: markOutlines)
            }
            if let label = relationship.label {
                labelPatches.addPath(CGPath(roundedRect: label.frame.insetBy(dx: -Self.labelPatchExtraWidth / 2, dy: 0),
                                            cornerWidth: Self.labelPatchCornerRadius, cornerHeight: Self.labelPatchCornerRadius, transform: nil))
            }
        }
        self.identifyingLines = identifyingLines
        self.nonIdentifyingLines = nonIdentifyingLines
        self.markFills = markFills
        self.markOutlines = markOutlines
        self.labelPatches = labelPatches
        labels = layout.relationships.compactMap(\.label)
        let boxes = BoxPaths(entities: layout.entities)
        boxFills = boxes.fills
        rowStripes = boxes.stripes
        boxOutlines = boxes.outlines
        entityTexts = layout.entities.flatMap { entity in [entity.name] + entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: false) } }
        attributeDetails = layout.entities.flatMap { entity in entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: true) } }
        title = layout.title
    }

    /// The row's attribute name (`inMutedColor` false), or its type, keys and comment.
    private static func texts(of row: EntityRelationshipLayoutRow, inMutedColor: Bool) -> [DiagramTextBlock] {
        row.texts.filter { cell in
            switch cell.column {
            case .name: !inMutedColor
            case .type, .keys, .comment: inMutedColor
            }
        }.map(\.text)
    }

    /// The boxes to fill, the rows striped over them, and their outlines and header dividers.
    private struct BoxPaths {
        let fills = CGMutablePath()
        let stripes = CGMutablePath()
        let outlines = CGMutablePath()

        init(entities: [EntityRelationshipLayoutEntity]) {
            let radius = EntityRelationshipDrawingParts.boxCornerRadius
            for entity in entities {
                let box = CGPath(roundedRect: entity.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                fills.addPath(box)
                outlines.addPath(box)
                if let firstRow = entity.rows.first {
                    outlines.move(to: CGPoint(x: entity.frame.minX, y: firstRow.frame.minY))
                    outlines.addLine(to: CGPoint(x: entity.frame.maxX, y: firstRow.frame.minY))
                }
                for (index, row) in entity.rows.enumerated() where index.isMultiple(of: 2) {
                    addStripe(row.frame, isLast: index == entity.rows.count - 1)
                }
            }
        }

        /// A row's band; the last one follows the box's rounded bottom corners: a rounded rectangle, squared off on top.
        private func addStripe(_ frame: CGRect, isLast: Bool) {
            guard isLast else { return stripes.addRect(frame) }
            let radius = min(EntityRelationshipDrawingParts.boxCornerRadius, frame.height / 2)
            stripes.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            stripes.addRect(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2))
        }
    }
}
