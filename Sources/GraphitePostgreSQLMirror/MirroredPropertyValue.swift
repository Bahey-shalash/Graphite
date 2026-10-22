import Foundation
import GraphiteCore

/// A property value as the mirror stores it in a note's `properties` JSON: typed as the vault
/// types the property, the type the Properties view shows for it.
public indirect enum MirroredPropertyValue: Hashable, Sendable, Encodable {
    case null
    case boolean(Bool)
    case number(Double)
    case text(String)
    case list([MirroredPropertyValue])
    case object([String: MirroredPropertyValue])

    /// `node` read as a property of `type`. A list's items follow YAML's own types (numbers
    /// stay numbers), except in tags and aliases, whose items are names. A mapping is kept as
    /// an object, its values typed by YAML alone.
    public init(node: BaseFrontmatterNode, type: PropertyType?) {
        switch node {
        case .scalar(let text, let isPlain):
            self.init(NoteProperties.value(ofScalarText: text, isPlain: isPlain, declaredType: type))
        case .sequence(let items):
            let itemType: PropertyType? = type == .tags || type == .aliases ? .text : nil
            self = .list(items.map { itemNode in MirroredPropertyValue(node: itemNode, type: itemType) })
        case .mapping(let entries):
            var members: [String: MirroredPropertyValue] = [:]
            // YAML forbids a repeated key; were one written, the first is kept, as Obsidian reads it.
            for entry in entries where members[entry.key] == nil {
                members[entry.key] = MirroredPropertyValue(node: entry.node, type: nil)
            }
            self = .object(members)
        }
    }

    init(_ propertyValue: PropertyValue) {
        switch propertyValue {
        case .empty: self = .null
        case .text(let text): self = .text(text)
        case .list(let items): self = .list(items.map(MirroredPropertyValue.text))
        // JSON has no infinity or NaN; YAML's spelling of them is kept as text.
        case .number(let number): self = number.isFinite ? .number(number) : .text(propertyValue.displayText)
        case .checkbox(let isChecked): self = .boolean(isChecked)
        // Dates stay as written (`2026-09-23`, `2026-09-23T14:30`), which PostgreSQL reads as dates.
        case .date(let text), .dateTime(let text): self = .text(text)
        case .unsupported(let yaml): self = .text(yaml)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .boolean(let isTrue): try container.encode(isTrue)
        case .number(let number): try container.encode(number)
        case .text(let text): try container.encode(text)
        case .list(let items): try container.encode(items)
        case .object(let members): try container.encode(members)
        }
    }
}
