import CoreGraphics

/// A class's box measured around its text, in Pele's measurements: the title compartment (annotations above the
/// name) 8 points from its top and bottom, then the attributes and the methods, each 6 points from its lines or
/// 10 points tall when empty, 12 points of padding on each side and 64 points wide at least.
struct ClassDiagramBox {
    static let titlePadding: CGFloat = 8
    static let sectionPadding: CGFloat = 6
    static let emptySectionHeight: CGFloat = 10
    static let horizontalPadding: CGFloat = 12
    static let minimumWidth: CGFloat = 64
    static let markRowHeightRatio: CGFloat = 1.4
    /// The name's row is at least one line of the name's font: 1.5 times its size, rounded.
    static let nameRowHeightRatio: CGFloat = 1.5

    /// Widened later when many relations meet one of its sides.
    var size: CGSize
    private let annotations: [DiagramTextBlock]
    private let name: DiagramTextBlock
    private let attributes: [ClassDiagramLayoutMember]
    private let methods: [ClassDiagramLayoutMember]
    private let titleHeight: CGFloat
    private let attributesHeight: CGFloat
    private let markRowHeight: CGFloat
    private let memberLineHeight: CGFloat

    init<Measurer: DiagramTextMeasuring>(_ declared: ClassDiagramClass, measurers: ClassDiagramTextMeasurers<Measurer>) {
        func line(_ text: String, _ measurer: Measurer) -> DiagramTextBlock {
            DiagramTextBlock(label: DiagramLabel(text), measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
        }
        annotations = declared.annotations.map { annotation in
            line("«" + ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(annotation)) + "»", measurers.marks)
        }
        name = DiagramTextBlock(label: declared.displayedName, measurer: measurers.names, maximumWidth: .greatestFiniteMagnitude)
        attributes = declared.attributes.map { member in ClassDiagramLayoutMember(text: line(member.text, measurers.members), classifier: member.classifier) }
        methods = declared.methods.map { member in ClassDiagramLayoutMember(text: line(member.text, measurers.members), classifier: member.classifier) }
        markRowHeight = measurers.markRowHeight
        memberLineHeight = measurers.members.lineHeight
        let nameHeight = max(name.size.height, (measurers.names.fontSize * Self.nameRowHeightRatio).rounded())
        titleHeight = 2 * Self.titlePadding + CGFloat(annotations.count) * markRowHeight + nameHeight
        attributesHeight = Self.sectionHeight(lineCount: attributes.count, lineHeight: memberLineHeight)
        let methodsHeight = Self.sectionHeight(lineCount: methods.count, lineHeight: memberLineHeight)
        let widest = (annotations.map(\.size.width) + [name.size.width] + (attributes + methods).map(\.text.size.width)).max() ?? 0
        size = CGSize(width: max(widest + 2 * Self.horizontalPadding, Self.minimumWidth), height: titleHeight + attributesHeight + methodsHeight)
    }

    private static func sectionHeight(lineCount: Int, lineHeight: CGFloat) -> CGFloat {
        lineCount > 0 ? 2 * sectionPadding + CGFloat(lineCount) * lineHeight : emptySectionHeight
    }

    /// The box at `center`: annotations centered from the top padding down, the name centered in the rest of the
    /// title, and each member left-aligned in its row.
    func placed(at center: CGPoint) -> ClassDiagramLayoutClass {
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        var y = frame.minY + Self.titlePadding
        let placedAnnotations = annotations.map { annotation in
            defer { y += markRowHeight }
            return centered(annotation, at: CGPoint(x: frame.midX, y: y + markRowHeight / 2))
        }
        let titleBottom = frame.minY + titleHeight
        let placedName = centered(name, at: CGPoint(x: frame.midX, y: (y + titleBottom - Self.titlePadding) / 2))
        let methodsTop = titleBottom + attributesHeight
        let members = leftAligned(attributes, top: titleBottom, left: frame.minX) + leftAligned(methods, top: methodsTop, left: frame.minX)
        return ClassDiagramLayoutClass(frame: frame, dividerYs: [titleBottom, methodsTop], annotations: placedAnnotations, name: placedName, members: members)
    }

    private func leftAligned(_ lines: [ClassDiagramLayoutMember], top: CGFloat, left: CGFloat) -> [ClassDiagramLayoutMember] {
        lines.enumerated().map { index, member in
            let center = CGPoint(x: left + Self.horizontalPadding + member.text.size.width / 2,
                                 y: top + Self.sectionPadding + (CGFloat(index) + 0.5) * memberLineHeight)
            return ClassDiagramLayoutMember(text: centered(member.text, at: center), classifier: member.classifier)
        }
    }

    private func centered(_ block: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = block
        placed.center = center
        return placed
    }
}
