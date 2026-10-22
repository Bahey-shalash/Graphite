import CryptoKit
import Foundation
import GraphiteCore
import GraphiteIndex

/// What a note's row holds, apart from its digests: the part whose digest tells whether the
/// row in the database is still the note.
struct MirroredNoteContent: Encodable {
    let path: String
    let name: String
    let folder: String
    let created: Date
    let modified: Date
    let sizeBytes: Int
    let tags: [String]
    let aliases: [String]
    let properties: [String: MirroredPropertyValue]
    let latitude: Double?
    let longitude: Double?

    private enum CodingKeys: String, CodingKey {
        case path, name, folder, created, modified, sizeBytes = "size_bytes", tags, aliases, properties, latitude, longitude
    }

    /// The note as the mirror copies it. Each property is named as the vault names it across
    /// notes (`columnsByKey`, by lowercased name), so `Cours` and `cours` are one key, and typed
    /// as the vault types it; `placePropertyNames` give the note's latitude and longitude, as
    /// the Map View reads them.
    init(note: IndexedNote, columnsByKey: [String: MirroredPropertyColumn], placePropertyNames: [String]) {
        let record = note.record
        path = record.path.rawValue
        name = record.path.stem
        folder = record.path.parent.rawValue
        created = record.createdDate
        modified = record.modifiedDate
        sizeBytes = record.size
        tags = record.tags
        aliases = note.aliases
        var properties: [String: MirroredPropertyValue] = [:]
        for entry in record.properties {
            let column = columnsByKey[entry.key.lowercased()]
            let propertyName = column?.propertyName ?? entry.key
            // Two capitalizations of one property in a note: the first written is kept, as Obsidian reads it.
            guard properties[propertyName] == nil else { continue }
            let propertyType = column?.propertyType ?? NoteProperties.type(ofKey: entry.key, sampleValues: [entry.node], declaredTypes: [:])
            properties[propertyName] = MirroredPropertyValue(node: entry.node, type: propertyType)
        }
        self.properties = properties
        let coordinate = PlacedNote.coordinate(in: record.properties, propertyNames: placePropertyNames, source: record.path)
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
    }
}

/// One row of `notes`, as `PostgreSQLMirrorStatements.noteUpsert` reads it from JSON.
struct MirroredNoteRow: Encodable {
    let content: MirroredNoteContent
    let digests: CopiedNoteDigests

    private enum DigestKeys: String, CodingKey {
        case contentDigest = "content_digest", linksDigest = "links_digest"
    }

    func encode(to encoder: any Encoder) throws {
        try content.encode(to: encoder)
        var container = encoder.container(keyedBy: DigestKeys.self)
        try container.encode(digests.contentDigest, forKey: .contentDigest)
        try container.encode(digests.linksDigest, forKey: .linksDigest)
    }
}

/// One row of `links`, as `PostgreSQLMirrorStatements.linkInsertion` reads it from JSON.
struct MirroredLinkRow: Encodable {
    let sourcePath: String
    /// The link's place among the note's links, from 1.
    let linkNumber: Int
    let target: String
    let targetPath: String?
    let isEmbed: Bool
    let isInProperties: Bool

    private enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path", linkNumber = "link_number", target, targetPath = "target_path"
        case isEmbed = "is_embed", isInProperties = "is_in_properties"
    }

    static func rows(for links: [ResolvedNoteLink], from sourcePath: String) -> [MirroredLinkRow] {
        links.enumerated().map { offset, link in
            MirroredLinkRow(sourcePath: sourcePath, linkNumber: offset + 1, target: link.target, targetPath: link.destination?.rawValue,
                            isEmbed: link.isEmbed, isInProperties: link.isInProperties)
        }
    }
}

/// One row of `property_columns`.
struct MirroredPropertyColumnRow: Encodable {
    let propertyName: String
    let propertyType: String
    let noteCount: Int

    private enum CodingKeys: String, CodingKey {
        case propertyName = "property_name", propertyType = "property_type", noteCount = "note_count"
    }
}

/// JSON as the mirror writes it: keys sorted, so equal rows give equal digests, and dates as
/// ISO 8601, which PostgreSQL reads as `timestamptz`.
enum MirrorJSON {
    static func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func encodedText(_ value: some Encodable) throws -> String {
        String(decoding: try encoded(value), as: UTF8.self)
    }

    /// The first 128 bits of the SHA-256 of `value`'s JSON, in hexadecimal.
    static func digest(of value: some Encodable) throws -> String {
        SHA256.hash(data: try encoded(value)).prefix(16).map { byte in String(format: "%02x", byte) }.joined()
    }
}

extension MirroredPropertyColumn {
    /// The vault's properties, one per name whatever its capitals (SQLite's grouping folds
    /// only ASCII letters), each with the type the Properties view gives it.
    static func columns(from usages: [PropertyUsage], declaredTypes: [String: PropertyType]) -> [MirroredPropertyColumn] {
        var usagesByKey: [String: [PropertyUsage]] = [:]
        for usage in usages { usagesByKey[usage.key.lowercased(), default: []].append(usage) }
        return usagesByKey.values.map { groupedUsages in
            let mostUsed = groupedUsages.max { leftUsage, rightUsage in leftUsage.fileCount < rightUsage.fileCount } ?? groupedUsages[0]
            let samples = groupedUsages.flatMap(\.sampleValues)
            return MirroredPropertyColumn(propertyName: mostUsed.key,
                                          propertyType: NoteProperties.type(ofKey: mostUsed.key, sampleValues: samples, declaredTypes: declaredTypes),
                                          noteCount: groupedUsages.reduce(0) { total, usage in total + usage.fileCount })
        }.sorted { leftColumn, rightColumn in leftColumn.propertyName < rightColumn.propertyName }
    }
}
