import Foundation

/// A task's data after its colon, read as Mermaid reads it: comma-separated fields, the first ones tags (`active`,
/// `done`, `crit`, `milestone`, `vert`), then an identifier, a start and an end (three fields), a start and an end
/// (two), or an end (one).
struct GanttTaskFields {
    private(set) var isDone = false
    private(set) var isActive = false
    private(set) var isCritical = false
    private(set) var isMilestone = false
    private(set) var isVerticalMarker = false
    /// The identifier written, or nil when the task has fewer than three fields.
    let identifier: String?
    let startText: String?
    let endText: String

    /// The most fields after the tags: an identifier, a start and an end.
    static let maximumFieldCount = 3

    init(name: String, data: String, line: Int) throws(MermaidDiagramReadError) {
        var fields = data.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        while let first = fields.first, let tag = Self.tag(first) {
            switch tag {
            case "active": isActive = true
            case "done": isDone = true
            case "crit": isCritical = true
            case "milestone": isMilestone = true
            case "vert": isVerticalMarker = true
            default: break
            }
            fields.removeFirst()
        }
        guard let last = fields.last else { throw .invalidSyntax(line: line, problem: .taskWithoutEnd(task: name)) }
        guard fields.count <= Self.maximumFieldCount else { throw .invalidSyntax(line: line, problem: .taskWithTooManyFields(task: name)) }
        let trimmedFields = fields.map { field in field.trimmingCharacters(in: .whitespacesAndNewlines) }
        identifier = fields.count == Self.maximumFieldCount ? trimmedFields[0] : nil
        startText = fields.count > 1 ? trimmedFields[fields.count - 2] : nil
        endText = last.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tag a field is, spaces around it allowed, or nil.
    private static func tag(_ field: String) -> String? {
        let word = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return tags.contains(word) ? word : nil
    }

    private static let tags: Set<String> = ["active", "done", "crit", "milestone", "vert"]
}
