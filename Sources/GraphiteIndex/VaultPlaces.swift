import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// Every note a `coordinates` or `location` property places (`PlacedNote.propertyNames`),
    /// for the map view. Only those properties' rows are read, through the index on their
    /// key, so the cost follows the number of placed notes rather than the vault's size.
    public func placedNotes() throws -> [PlacedNote] {
        let names = PlacedNote.propertyNames
        return try databaseQueue.read { database in
            let condition = names.map { _ in "key = ? COLLATE NOCASE" }.joined(separator: " OR ")
            let rows = try Row.fetchAll(database, sql: "SELECT path, key, node FROM properties WHERE \(condition) ORDER BY path, position",
                                        arguments: StatementArguments(names))
            let decoder = JSONDecoder()
            var entriesByPath: [String: [BaseFrontmatterEntry]] = [:]
            var orderedPaths: [String] = []
            for row in rows {
                let encodedNode: String = row["node"]
                // A row that does not decode is a stale cache entry; that property is skipped.
                guard let node = Self.decodedScalarNode(encodedNode) ?? (try? decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8))) else { continue }
                let pathText: String = row["path"]
                if entriesByPath[pathText] == nil { orderedPaths.append(pathText) }
                entriesByPath[pathText, default: []].append(BaseFrontmatterEntry(key: row["key"], node: node))
            }
            return orderedPaths.compactMap { pathText in
                guard let path = try? VaultPath(pathText),
                      let coordinate = PlacedNote.coordinate(in: entriesByPath[pathText] ?? [], source: path) else { return nil }
                return PlacedNote(path: path, coordinate: coordinate)
            }
        }
    }
}
