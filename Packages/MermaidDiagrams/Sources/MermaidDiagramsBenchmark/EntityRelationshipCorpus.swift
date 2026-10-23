import Foundation

/// Entity relationship diagrams to read and lay out: the 25 examples of Mermaid's documentation, as Pele's corpus
/// collects them, and a schema generated at any size.
enum EntityRelationshipCorpus {
    /// A database schema: each table with a key, a name, a key of its parent table and a date, under its parent in a
    /// tree of three children per table, and every seventh table also related to a table further on by a
    /// non-identifying many-to-many relationship.
    static func schema(entityCount: Int) -> String {
        var source = "erDiagram\n"
        for entity in 0..<entityCount {
            source += "  TABLE_\(entity) {\n    int id PK\n    string name \"Shown name\"\n    int parent_id FK\n    date created\n  }\n"
            if entity > 0 { source += "  TABLE_\((entity - 1) / 3) ||--o{ TABLE_\(entity) : has\n" }
            if entity.isMultiple(of: 7), entity + 5 < entityCount { source += "  TABLE_\(entity) }o..o{ TABLE_\(entity + 5) : \"refers to\"\n" }
        }
        return source
    }

    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "er-docs", withExtension: "json", subdirectory: "Resources") else {
            throw MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// The documentation examples are not in the module's resources.
    struct MissingResource: Error {}
}
