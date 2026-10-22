import SwiftUI
import MermaidDiagrams

/// An entity relationship diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingEntityRelationshipDiagram: Sendable {
    let layout: EntityRelationshipLayout
    let shapes: ReadingEntityRelationshipShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// What a screen reader reads without a description: each entity's text, then each relationship as its two
    /// entities around its label ("CUSTOMER places ORDER").
    let summary: [String]

    init(diagram: EntityRelationshipDiagram, layout: EntityRelationshipLayout) {
        self.layout = layout
        shapes = ReadingEntityRelationshipShapes(parts: EntityRelationshipDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        let entityTexts = diagram.entities.map(\.label.spokenText)
        summary = entityTexts + diagram.relationships.map { relationship in
            [entityTexts[relationship.firstEntityIndex], relationship.label.spokenText, entityTexts[relationship.secondEntityIndex]]
                .filter { part in !part.isEmpty }.joined(separator: " ")
        }
    }
}

extension ReadingDiagram {
    /// An entity relationship diagram laid out in `typography`, the source with why when it cannot be laid out, or
    /// nil while it has subgraphs, which are not laid out yet: the block is then shown as code.
    static func drawnEntityRelationship(_ diagram: EntityRelationshipDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram? {
        do {
            let layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            return .entityRelationship(ReadingEntityRelationshipDiagram(diagram: diagram, layout: layout))
        } catch .subgraphsNotLaidOut {
            return nil
        } catch {
            return .unreadable(source: source, failure: .entityRelationshipLayout(error))
        }
    }
}
