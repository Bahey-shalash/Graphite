/// The text of a node, an edge or a group, as plain lines: Markdown markers, HTML tags and entity codes are already
/// read, and a line ends where the diagram breaks it (`<br>`, or a new line in a Markdown string). Lines are never
/// interpreted again: they are drawn as the characters they hold.
public struct DiagramLabel: Equatable, Sendable {
    public let lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    /// One line of text.
    init(_ text: String) {
        self.lines = [text]
    }

    /// Whether the label has nothing to draw.
    public var isEmpty: Bool {
        lines.allSatisfy(\.isEmpty)
    }

    /// The lines joined by spaces, as a screen reader reads them.
    public var spokenText: String {
        lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }
}
