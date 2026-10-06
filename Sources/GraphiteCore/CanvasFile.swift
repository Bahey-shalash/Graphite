import Foundation
import CoreGraphics

/// A card's or connection's color, as JSON Canvas writes it: one of six presets, which
/// each app shows in its own shades, or a color of its own.
public enum CanvasColor: Hashable, Sendable {
    /// 1 red, 2 orange, 3 yellow, 4 green, 5 cyan, 6 purple.
    case preset(Int)
    case custom(red: UInt8, green: UInt8, blue: UInt8)

    public static let presets: [CanvasColor] = (1...6).map(CanvasColor.preset)

    /// Reads `"1"` to `"6"` and `#rrggbb` (or the short `#rgb`); anything else is no color.
    public init?(text: String) {
        if let presetNumber = Int(text), (1...6).contains(presetNumber), text.count == 1 {
            self = .preset(presetNumber)
            return
        }
        guard text.hasPrefix("#") else { return nil }
        var digits = Array(text.dropFirst())
        if digits.count == 3 { digits = digits.flatMap { digit in [digit, digit] } }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), digits.allSatisfy(\.isASCII),
              let red = UInt8(String(digits[0..<2]), radix: 16), let green = UInt8(String(digits[2..<4]), radix: 16),
              let blue = UInt8(String(digits[4..<6]), radix: 16) else { return nil }
        self = .custom(red: red, green: green, blue: blue)
    }

    /// The color as a canvas file writes it.
    public var text: String {
        switch self {
        case .preset(let presetNumber): String(presetNumber)
        case .custom(let red, let green, let blue): String(format: "#%02x%02x%02x", red, green, blue)
        }
    }

    /// What the color is called where it is chosen and read aloud, so a color is never
    /// the only way to tell it.
    public var name: String {
        switch self {
        case .preset(1): "Red"
        case .preset(2): "Orange"
        case .preset(3): "Yellow"
        case .preset(4): "Green"
        case .preset(5): "Cyan"
        case .preset(6): "Purple"
        case .preset: "Color"
        case .custom: "Custom color \(text)"
        }
    }
}

public enum CanvasSide: String, CaseIterable, Sendable {
    case top, right, bottom, left
}

/// The shape at one end of a connection.
public enum CanvasEdgeEnd: String, Sendable {
    case none, arrow
}

/// How a group's background image fills it.
public enum CanvasGroupBackgroundStyle: String, Sendable {
    /// Fills the group, cropping the image.
    case cover
    /// Shows the whole image, keeping its proportions.
    case ratio
    /// Tiles the image.
    case `repeat`
}

/// One card of a canvas.
public struct CanvasNode: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        /// - Parameter subpath: A heading, a block or a PDF page, starting with `#`.
        case file(path: String, subpath: String?)
        case link(address: String)
        case group(label: String?, background: String?, backgroundStyle: CanvasGroupBackgroundStyle)
        /// A type this version of the format does not define. It is shown as a plain
        /// card and kept in the file as it is.
        case unknown(type: String)
    }

    /// Unique among the cards Graphite shows. It is the card's `id` in the file, except
    /// for a card whose `id` another card before it already has.
    public let id: String
    /// The card's `id` as the file writes it, which connections name.
    public let identifierInFile: String
    public var content: Content
    public var frame: CGRect
    public var color: CanvasColor?

    public init(id: String, content: Content, frame: CGRect, color: CanvasColor? = nil) {
        self.id = id; identifierInFile = id; self.content = content; self.frame = frame; self.color = color
    }

    init(id: String, identifierInFile: String, content: Content, frame: CGRect, color: CanvasColor?) {
        self.id = id; self.identifierInFile = identifierInFile; self.content = content; self.frame = frame; self.color = color
    }

    public var isGroup: Bool {
        if case .group = content { return true }
        return false
    }
}

/// One connection between two cards.
public struct CanvasEdge: Identifiable, Equatable, Sendable {
    /// Unique among the connections Graphite shows, as `CanvasNode.id` is.
    public let id: String
    /// The `id` of the card it starts at, as the file writes it.
    public var fromNode: String
    public var toNode: String
    /// The side it leaves the card by; nil lets the app choose.
    public var fromSide: CanvasSide?
    public var toSide: CanvasSide?
    public var fromEnd: CanvasEdgeEnd
    public var toEnd: CanvasEdgeEnd
    public var color: CanvasColor?
    public var label: String?

    public init(id: String, fromNode: String, toNode: String, fromSide: CanvasSide? = nil, toSide: CanvasSide? = nil,
                fromEnd: CanvasEdgeEnd = .none, toEnd: CanvasEdgeEnd = .arrow, color: CanvasColor? = nil, label: String? = nil) {
        self.id = id; self.fromNode = fromNode; self.toNode = toNode; self.fromSide = fromSide; self.toSide = toSide
        self.fromEnd = fromEnd; self.toEnd = toEnd; self.color = color; self.label = label
    }
}

/// A `.canvas` file (JSON Canvas 1.0) as read: its cards and connections, and the bytes
/// they were read from. The bytes are the file; the cards and connections are only what
/// Graphite understood of them. An edit replaces the bytes it changes and nothing else,
/// so keys, card types and formatting Graphite does not know stay exactly as written.
public struct CanvasFile: Sendable {
    public static let maximumSourceBytes = 16 * 1_048_576
    public static let maximumNodeCount = 50_000
    public static let maximumEdgeCount = 100_000
    /// Positions beyond this, in either direction, are not shown: drawing arithmetic
    /// stays exact well within it.
    static let maximumCoordinate = 10_000_000.0
    static let maximumSideLength = 1_000_000.0

    let bytes: [UInt8]
    let root: CanvasJSONValue
    /// The file's cards in the order it lists them: the first is drawn beneath all others
    /// and the last on top.
    public let nodes: [CanvasNode]
    public let edges: [CanvasEdge]
    /// For each of `nodes`, its place in the file's `nodes` list.
    let nodeElementIndexes: [Int]
    let edgeElementIndexes: [Int]
    /// Entries of `nodes` in the file that are not cards Graphite can show: no `id`, or
    /// no usable position and size. They stay in the file.
    public let unreadableNodeCount: Int
    public let unreadableEdgeCount: Int
    private let nodeIndexesByIdentifier: [String: Int]
    private let edgeIndexesByIdentifier: [String: Int]
    private let nodeIndexesByIdentifierInFile: [String: Int]

    /// The file's bytes, exactly.
    public var data: Data { Data(bytes) }

    /// An empty canvas as Obsidian creates it.
    public static let emptyFileData = Data("{}".utf8)

    public init(data: Data) throws {
        guard data.count <= Self.maximumSourceBytes else { throw CanvasFileError.oversized }
        guard String(validating: data, as: UTF8.self) != nil else { throw CanvasFileError.notUTF8 }
        try self.init(validatedBytes: Array(data))
    }

    init(validatedBytes: [UInt8]) throws {
        bytes = validatedBytes
        // A file with nothing in it is a canvas with nothing on it; Obsidian opens it too.
        let isBlank = validatedBytes.allSatisfy { byte in byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }
        root = isBlank ? CanvasJSONValue(content: .object([]), range: 0..<0) : try CanvasJSONParser.parse(validatedBytes)
        guard case .object = root.content else { throw CanvasFileError.notAnObject }

        let nodeValues = try Self.list(named: "nodes", in: root)
        let edgeValues = try Self.list(named: "edges", in: root)
        guard nodeValues.count <= Self.maximumNodeCount else { throw CanvasFileError.tooManyCards }
        guard edgeValues.count <= Self.maximumEdgeCount else { throw CanvasFileError.tooManyConnections }

        var readNodes: [CanvasNode] = [], readNodeElementIndexes: [Int] = []
        var nodeIndexesByIdentifier: [String: Int] = [:], nodeIndexesByIdentifierInFile: [String: Int] = [:]
        for (elementIndex, value) in nodeValues.enumerated() {
            guard let identifierInFile = value.member("id")?.value.string, let frame = Self.frame(of: value) else { continue }
            var identifier = identifierInFile
            if nodeIndexesByIdentifier[identifier] != nil { identifier = Self.distinctIdentifier(identifierInFile, elementIndex: elementIndex, taken: nodeIndexesByIdentifier) }
            nodeIndexesByIdentifier[identifier] = readNodes.count
            if nodeIndexesByIdentifierInFile[identifierInFile] == nil { nodeIndexesByIdentifierInFile[identifierInFile] = readNodes.count }
            readNodes.append(CanvasNode(id: identifier, identifierInFile: identifierInFile, content: Self.content(of: value), frame: frame,
                                        color: value.member("color")?.value.string.flatMap(CanvasColor.init(text:))))
            readNodeElementIndexes.append(elementIndex)
        }

        var readEdges: [CanvasEdge] = [], readEdgeElementIndexes: [Int] = []
        var edgeIndexesByIdentifier: [String: Int] = [:]
        for (elementIndex, value) in edgeValues.enumerated() {
            guard let identifierInFile = value.member("id")?.value.string, let fromNode = value.member("fromNode")?.value.string,
                  let toNode = value.member("toNode")?.value.string else { continue }
            var identifier = identifierInFile
            if edgeIndexesByIdentifier[identifier] != nil { identifier = Self.distinctIdentifier(identifierInFile, elementIndex: elementIndex, taken: edgeIndexesByIdentifier) }
            edgeIndexesByIdentifier[identifier] = readEdges.count
            readEdges.append(CanvasEdge(
                id: identifier, fromNode: fromNode, toNode: toNode,
                fromSide: value.member("fromSide")?.value.string.flatMap(CanvasSide.init(rawValue:)),
                toSide: value.member("toSide")?.value.string.flatMap(CanvasSide.init(rawValue:)),
                fromEnd: value.member("fromEnd")?.value.string.flatMap(CanvasEdgeEnd.init(rawValue:)) ?? .none,
                toEnd: value.member("toEnd")?.value.string.flatMap(CanvasEdgeEnd.init(rawValue:)) ?? .arrow,
                color: value.member("color")?.value.string.flatMap(CanvasColor.init(text:)),
                label: value.member("label")?.value.string))
            readEdgeElementIndexes.append(elementIndex)
        }

        nodes = readNodes; nodeElementIndexes = readNodeElementIndexes
        edges = readEdges; edgeElementIndexes = readEdgeElementIndexes
        unreadableNodeCount = nodeValues.count - readNodes.count
        unreadableEdgeCount = edgeValues.count - readEdges.count
        self.nodeIndexesByIdentifier = nodeIndexesByIdentifier
        self.edgeIndexesByIdentifier = edgeIndexesByIdentifier
        self.nodeIndexesByIdentifierInFile = nodeIndexesByIdentifierInFile
    }

    // MARK: Lookup

    public func node(withIdentifier identifier: String) -> CanvasNode? {
        nodeIndexesByIdentifier[identifier].map { index in nodes[index] }
    }

    public func edge(withIdentifier identifier: String) -> CanvasEdge? {
        edgeIndexesByIdentifier[identifier].map { index in edges[index] }
    }

    /// The card a connection's `fromNode` or `toNode` names: the first card with that
    /// `id` in the file.
    public func node(named identifierInFile: String) -> CanvasNode? {
        nodeIndexesByIdentifierInFile[identifierInFile].map { index in nodes[index] }
    }

    func nodeIndex(withIdentifier identifier: String) -> Int? { nodeIndexesByIdentifier[identifier] }
    func edgeIndex(withIdentifier identifier: String) -> Int? { edgeIndexesByIdentifier[identifier] }

    /// The file's `nodes` list as written; empty when it has none.
    var nodeValues: [CanvasJSONValue] { root.member("nodes")?.value.elements ?? [] }
    var edgeValues: [CanvasJSONValue] { root.member("edges")?.value.elements ?? [] }

    /// Every `id` the file uses, for cards and connections, so a new one differs from all.
    var identifiersInFile: Set<String> {
        Set((nodeValues + edgeValues).compactMap { value in value.member("id")?.value.string })
    }

    // MARK: Reading

    private static func list(named listName: String, in root: CanvasJSONValue) throws -> [CanvasJSONValue] {
        guard let member = root.member(listName) else { return [] }
        if case .null = member.value.content { return [] }
        guard let elements = member.value.elements else { throw CanvasFileError.listIsNotAnArray(listName: listName) }
        return elements
    }

    /// A key for a card or connection whose `id` another one already has. A control
    /// character keeps it apart from every `id` Obsidian writes.
    private static func distinctIdentifier(_ identifierInFile: String, elementIndex: Int, taken: [String: Int]) -> String {
        var candidate = identifierInFile + "\u{1}" + String(elementIndex)
        while taken[candidate] != nil { candidate += "\u{1}" }
        return candidate
    }

    /// The card's position and size, or nil when it has none Graphite can draw.
    private static func frame(of value: CanvasJSONValue) -> CGRect? {
        guard let horizontalPosition = value.member("x")?.value.number, let verticalPosition = value.member("y")?.value.number,
              let width = value.member("width")?.value.number, let height = value.member("height")?.value.number,
              abs(horizontalPosition) <= maximumCoordinate, abs(verticalPosition) <= maximumCoordinate,
              width > 0, height > 0, width <= maximumSideLength, height <= maximumSideLength else { return nil }
        return CGRect(x: horizontalPosition, y: verticalPosition, width: width, height: height)
    }

    private static func content(of value: CanvasJSONValue) -> CanvasNode.Content {
        let type = value.member("type")?.value.string ?? ""
        switch type {
        case "text":
            return .text(value.member("text")?.value.string ?? "")
        case "file":
            let subpath = value.member("subpath")?.value.string
            return .file(path: value.member("file")?.value.string ?? "", subpath: subpath?.isEmpty == false ? subpath : nil)
        case "link":
            return .link(address: value.member("url")?.value.string ?? "")
        case "group":
            let label = value.member("label")?.value.string
            let background = value.member("background")?.value.string
            return .group(label: label?.isEmpty == false ? label : nil, background: background?.isEmpty == false ? background : nil,
                          backgroundStyle: value.member("backgroundStyle")?.value.string.flatMap(CanvasGroupBackgroundStyle.init(rawValue:)) ?? .cover)
        default:
            return .unknown(type: type)
        }
    }
}
