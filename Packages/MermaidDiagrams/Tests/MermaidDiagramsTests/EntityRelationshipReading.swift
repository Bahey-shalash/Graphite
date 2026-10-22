@testable import MermaidDiagrams

/// Reads an entity relationship diagram for a test, as `MermaidDiagramReader` reads it.
enum EntityRelationshipReading {
    struct NotAnEntityRelationshipDiagram: Error {}

    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> EntityRelationshipDiagram {
        guard case .entityRelationship(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAnEntityRelationshipDiagram() }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}

/// Lays an entity relationship diagram out with uniform-width text: names at 8 points a character in 16-point text,
/// rows and labels at 7 in 14-point text, and keys at 6 in 12-point text.
enum EntityRelationshipUniformLayout {
    static let font = DiagramFont(postScriptName: nil, size: 16)

    static func layout(_ diagram: EntityRelationshipDiagram, limits: MermaidDiagramLimits = .standard) throws -> EntityRelationshipLayout {
        try EntityRelationshipLayoutEngine.layout(diagram, nameText: UniformWidthTextMeasurer(),
                                                  rowText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21), font: font, limits: limits)
    }

    static func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> EntityRelationshipLayout {
        try layout(EntityRelationshipReading.diagram(source), limits: limits)
    }
}
