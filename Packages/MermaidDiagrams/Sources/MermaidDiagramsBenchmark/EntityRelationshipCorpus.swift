import Foundation

/// Entity relationship diagrams to read and lay out: the 25 examples of Mermaid's documentation, as Pele's corpus
/// collects them.
enum EntityRelationshipCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "er-docs", withExtension: "json", subdirectory: "Resources") else {
            throw MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// The documentation examples are not in the module's resources.
    struct MissingResource: Error {}
}
