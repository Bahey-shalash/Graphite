import Foundation

/// One of Obsidian's graph groups: the files a search matches take its color. Its fields
/// are kept as stored, known or not, so a group written by a newer Graphite keeps what this
/// one does not read.
public struct GraphColorGroup: Hashable, Sendable, Identifiable {
    public private(set) var fields: [String: JSONValue]

    init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    /// A new group with a search and a color.
    public init(identifier: UUID, query: String, colorHex: String) {
        fields = ["id": .string(identifier.uuidString), "query": .string(query), "color": .string(colorHex)]
    }

    /// The identifier written when the group was made. A list gives a group stored without
    /// one an identifier of its own when it is read (`GraphColorGroupList.init(decoding:)`).
    public var id: String { fields["id"]?.stringValue ?? "" }

    /// Obsidian's search words, as the graph's filter reads them (`path:"Courses/VLSI"`,
    /// `tag:#vlsi`). A group without words colors nothing.
    public var query: String {
        get { fields["query"]?.stringValue ?? "" }
        set { fields["query"] = .string(newValue) }
    }

    /// The color, as canonical `#rrggbb`; nil when the stored color is not one.
    public var colorHex: String? {
        get { fields["color"]?.stringValue.flatMap(TextColorMarkup.canonicalHex) }
        set { fields["color"] = newValue.flatMap(TextColorMarkup.canonicalHex).map(JSONValue.string) }
    }
}

/// A vault's graph groups in their order, which is the order they win in: a file takes the
/// color of the first group whose search it matches, as in Obsidian. Kept as the JSON array
/// it was read from: an element that is not a group stays where it is and is written back
/// as it was.
public struct GraphColorGroupList: Equatable, Sendable {
    private var elements: [JSONValue]

    public init() {
        elements = []
    }

    /// The groups kept in `storedList`, a JSON array; nil when it is not one, so that the
    /// caller keeps it aside rather than writing over it. A group stored without an
    /// identifier is given one, written with the list's next change.
    public init?(decoding storedList: Data, makeIdentifier: () -> UUID) {
        let storedValue: JSONValue
        do {
            storedValue = try JSONDecoder().decode(JSONValue.self, from: storedList)
        } catch {
            return nil
        }
        guard case .array(let elements) = storedValue else { return nil }
        self.elements = elements.map { element in
            guard case .object(var fields) = element, fields["id"]?.stringValue?.isEmpty ?? true else { return element }
            fields["id"] = .string(makeIdentifier().uuidString)
            return .object(fields)
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(JSONValue.array(elements))
    }

    /// The groups, without the elements that are not groups.
    public var groups: [GraphColorGroup] {
        elements.compactMap { element in
            guard case .object(let fields) = element else { return nil }
            return GraphColorGroup(fields: fields)
        }
    }

    public mutating func append(_ group: GraphColorGroup) {
        elements.append(.object(group.fields))
    }

    /// Replaces the group with the same identifier; nothing when there is none.
    public mutating func replace(_ group: GraphColorGroup) {
        guard let position = position(ofGroup: group.id) else { return }
        elements[position] = .object(group.fields)
    }

    public mutating func removeGroup(identifiedBy identifier: String) {
        guard let position = position(ofGroup: identifier) else { return }
        elements.remove(at: position)
    }

    private func position(ofGroup identifier: String) -> Int? {
        elements.firstIndex { element in
            guard case .object(let fields) = element else { return false }
            return GraphColorGroup(fields: fields).id == identifier
        }
    }
}
