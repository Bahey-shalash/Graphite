@testable import MermaidDiagrams

/// Reads an entity relationship diagram for a test, from just after the first `erDiagram` of its text, so that front
/// matter before it is passed over; lines count from the start of the text.
enum EntityRelationshipReading {
    static let keyword = Array("erDiagram".utf8)

    struct MissingKeyword: Error {}

    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> EntityRelationshipDiagram {
        let bytes = Array(source.utf8)
        guard let keywordOffset = bytes.indices.first(where: { offset in bytes[offset...].starts(with: keyword) }) else { throw MissingKeyword() }
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: keywordOffset + keyword.count)
        return try EntityRelationshipParser.parse(cursor, limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch let error as MermaidDiagramReadError {
            return error
        } catch {
            return .noDiagram
        }
    }
}
