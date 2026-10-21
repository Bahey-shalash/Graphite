import Foundation

/// Why `.obsidian/graphite-templates/templates.json` is refused rather than read; the file is
/// then left as it is, never overwritten.
public enum MyPaperTemplateListError: Error, Equatable {
    case notAJSONObject
    case fieldNotAnArray(String)
}

/// The arrangement of the person's own paper templates (My Templates in the New Notebook sheet).
/// A template is an ordinary one-page PDF in `directory`; its file name, without the extension,
/// is its name. Graphite's optional `templates.json` beside them only says in which order they
/// are shown and which are hidden, so a PDF put in the folder by hand shows up (last, by name)
/// and a template without the file loses nothing. Keys and entries this build does not
/// understand are kept as they were.
public struct MyPaperTemplateList: Equatable, Sendable {
    public static let directory = ".obsidian/graphite-templates"
    public static let configurationPath = directory + "/templates.json"
    /// The name a file this build cannot read is kept under, beside `configurationPath`.
    public static let unreadableCopyStem = "templates.unreadable"
    public static let fileExtension = "pdf"

    private enum FieldName {
        static let order = "order"
        static let hidden = "hidden"
    }

    /// File names in the order the person arranged them; templates not named here come after them.
    public private(set) var order: [String]
    public private(set) var hiddenFileNames: Set<String>
    /// Entries of the two lists that are not file names, and keys beside them, kept as they were.
    private var unreadableOrderEntries: [JSONValue]
    private var unreadableHiddenEntries: [JSONValue]
    private var otherFields: [String: JSONValue]

    /// One template as the sheet lists it.
    public struct Template: Equatable, Sendable, Identifiable {
        public let fileName: String
        public let isHidden: Bool

        public var id: String { fileName }
        public var name: String { (fileName as NSString).deletingPathExtension }

        public init(fileName: String, isHidden: Bool) {
            self.fileName = fileName
            self.isHidden = isHidden
        }
    }

    public init() {
        order = []
        hiddenFileNames = []
        unreadableOrderEntries = []
        unreadableHiddenEntries = []
        otherFields = [:]
    }

    /// Reads the file's data; nothing means no arrangement. Throws for a file that is not this
    /// format, so it is never overwritten.
    public init(configurationData: Data?) throws {
        self.init()
        guard let configurationData, !configurationData.isEmpty else { return }
        let decoded = try? JSONDecoder().decode(JSONValue.self, from: configurationData) // Not JSON is refused below.
        guard case .object(var object) = decoded else { throw MyPaperTemplateListError.notAJSONObject }
        (order, unreadableOrderEntries) = try Self.fileNames(in: object.removeValue(forKey: FieldName.order), field: FieldName.order)
        let hiddenNames: [String]
        (hiddenNames, unreadableHiddenEntries) = try Self.fileNames(in: object.removeValue(forKey: FieldName.hidden), field: FieldName.hidden)
        hiddenFileNames = Set(hiddenNames)
        otherFields = object
    }

    private static func fileNames(in value: JSONValue?, field: String) throws -> (names: [String], unreadable: [JSONValue]) {
        switch value {
        case .array(let entries):
            var names: [String] = []
            var unreadable: [JSONValue] = []
            for entry in entries {
                if case .string(let name) = entry, !name.isEmpty { names.append(name) } else { unreadable.append(entry) }
            }
            return (names, unreadable)
        case nil, .null:
            return ([], [])
        default:
            throw MyPaperTemplateListError.fieldNotAnArray(field)
        }
    }

    public func configurationData() throws -> Data {
        var object = otherFields
        object[FieldName.order] = .array(order.map(JSONValue.string) + unreadableOrderEntries)
        object[FieldName.hidden] = .array(hiddenFileNames.sorted().map(JSONValue.string) + unreadableHiddenEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(object))
    }

    /// The templates of the PDFs found in the folder: those arranged first, in their order, then
    /// the others by name.
    public func templates(listing fileNames: [String]) -> [Template] {
        let listedNames = Set(fileNames)
        var seenNames: Set<String> = []
        let arranged = order.filter { fileName in listedNames.contains(fileName) && seenNames.insert(fileName).inserted }
        let unarranged = fileNames.filter { fileName in !seenNames.contains(fileName) }
            .sorted { leftName, rightName in leftName.localizedStandardCompare(rightName) == .orderedAscending }
        return (arranged + unarranged).map { fileName in Template(fileName: fileName, isHidden: hiddenFileNames.contains(fileName)) }
    }

    /// Fixes the order to `fileNames`, as the sheet shows them after a move.
    public mutating func arrange(_ fileNames: [String]) {
        order = fileNames
    }

    public mutating func setHidden(_ isHidden: Bool, fileName: String) {
        if isHidden { hiddenFileNames.insert(fileName) } else { hiddenFileNames.remove(fileName) }
    }

    /// Keeps the place and the hidden state of a renamed template.
    public mutating func rename(_ oldFileName: String, to newFileName: String) {
        order = order.map { fileName in fileName == oldFileName ? newFileName : fileName }
        if hiddenFileNames.remove(oldFileName) != nil { hiddenFileNames.insert(newFileName) }
    }

    /// Forgets a deleted template.
    public mutating func forget(_ fileName: String) {
        order.removeAll { listedName in listedName == fileName }
        hiddenFileNames.remove(fileName)
    }
}
