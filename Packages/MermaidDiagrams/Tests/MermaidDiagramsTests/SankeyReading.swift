@testable import MermaidDiagrams

/// Reads a Sankey diagram for a test, from its whole text, through `MermaidDiagramReader`.
enum SankeyReading {
    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> SankeyDiagram {
        guard case .sankey(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// Each link as its source's and target's names and its value.
    static func rows(_ diagram: SankeyDiagram) -> [String] {
        diagram.links.map { link in
            "\(diagram.nodes[link.sourceIndex].name) → \(diagram.nodes[link.targetIndex].name): \(link.value.map { value in "\(value)" } ?? "none")"
        }
    }
}
