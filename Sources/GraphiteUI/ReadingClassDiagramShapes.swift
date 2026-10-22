import SwiftUI
import MermaidDiagrams

/// A class diagram's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `ClassDiagramDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingClassDiagramShapes: Sendable {
    let solidLines: Path
    let dashedLines: Path
    let dottedLines: Path
    let filledMarks: Path
    let strokedMarks: Path
    let edgeTextPatches: Path
    let classFills: Path
    let noteFills: Path
    let outlines: Path
    /// Relation text, drawn over the patches and under the boxes.
    let edgeTextLines: [ReadingDiagramTextLine]
    /// Cardinalities, drawn in the muted color under the boxes.
    let cardinalityLines: [ReadingDiagramTextLine]
    /// Annotations, drawn in the muted color in their boxes.
    let annotationLines: [ReadingDiagramTextLine]
    /// The classes' names, in bold.
    let nameLines: [ReadingDiagramTextLine]
    let memberLines: [ReadingClassDiagramMemberLine]
    /// The notes' text, the interfaces' names and the title, drawn last.
    let noteTextLines: [ReadingDiagramTextLine]

    init(parts: ClassDiagramDrawingParts, font: DiagramFont) {
        solidLines = Path(parts.solidLines)
        dashedLines = Path(parts.dashedLines)
        dottedLines = Path(parts.dottedLines)
        filledMarks = Path(parts.filledMarks)
        strokedMarks = Path(parts.strokedMarks)
        edgeTextPatches = Path(parts.edgeTextPatches)
        classFills = Path(parts.classFills)
        noteFills = Path(parts.noteFills)
        outlines = Path(parts.outlines)
        func lines(_ blocks: [DiagramTextBlock], isBold: Bool) -> [ReadingDiagramTextLine] {
            blocks.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: isBold) }
        }
        edgeTextLines = lines(parts.edgeTexts, isBold: false)
        cardinalityLines = lines(parts.cardinalities, isBold: false)
        annotationLines = lines(parts.annotations, isBold: false)
        nameLines = lines(parts.names, isBold: true)
        memberLines = parts.members.compactMap { member in ReadingClassDiagramMemberLine(member: member, font: font) }
        noteTextLines = lines(parts.noteTexts, isBold: false) + lines(parts.title.map { title in [title] } ?? [], isBold: true)
    }
}

/// A line of a class's attributes or methods: what it says, where its measured width is centered, and how it is
/// set. It is drawn from the left of that width, as it was laid out.
struct ReadingClassDiagramMemberLine: Sendable {
    let text: String
    let center: CGPoint
    let width: CGFloat
    let font: DiagramFont
    /// An abstract member, drawn in italics.
    let isItalic: Bool
    /// A static member, drawn underlined.
    let isUnderlined: Bool

    /// The member's line, or nil when it has no text.
    init?(member: ClassDiagramLayoutMember, font: DiagramFont) {
        guard let line = member.text.lines.first, let width = member.text.lineWidths.first else { return nil }
        text = line
        center = member.text.center
        self.width = width
        self.font = DiagramFont(postScriptName: font.postScriptName, size: member.text.fontSize)
        switch member.classifier {
        case .plain: (isItalic, isUnderlined) = (false, false)
        case .static: (isItalic, isUnderlined) = (false, true)
        case .abstract: (isItalic, isUnderlined) = (true, false)
        }
    }

    /// The SwiftUI font the line was measured in: the system font, or the installed font by its PostScript name.
    var swiftUIFont: Font {
        font.postScriptName.map { name in Font.custom(name, fixedSize: font.size) } ?? .system(size: font.size)
    }
}
