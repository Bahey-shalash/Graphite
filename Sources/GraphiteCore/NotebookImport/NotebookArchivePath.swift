import Foundation

/// A path inside a notebook's archive, read from the notebook itself and checked once: relative, made of non-empty
/// components separated by `/`, none of them `.` or `..`, and free of backslashes and control characters. A path
/// that passes cannot climb out of the folder it is joined to, so a converter can name a file after it.
public struct NotebookArchivePath: Sendable, Hashable {
    /// The path as stored, components joined by `/`.
    public let text: String

    /// Nil when the text is not a safe relative path.
    public init?(validating text: String) {
        let components = text.split(separator: "/", omittingEmptySubsequences: false)
        guard !text.isEmpty, !text.hasPrefix("/"),
              components.allSatisfy({ component in !component.isEmpty && component != "." && component != ".." }),
              !text.unicodeScalars.contains(where: { scalar in scalar == "\\" || scalar.properties.generalCategory == .control })
        else { return nil }
        self.text = text
    }

    /// The path's last component, the file's own name.
    public var fileName: String { text.split(separator: "/").last.map(String.init) ?? text }

    /// The file `name` in `folder`, both read from a notebook; nil when the name is not one safe component.
    public static func file(named name: String, inFolder folder: String) -> NotebookArchivePath? {
        guard !name.contains("/") else { return nil }
        return NotebookArchivePath(validating: folder + "/" + name)
    }
}
