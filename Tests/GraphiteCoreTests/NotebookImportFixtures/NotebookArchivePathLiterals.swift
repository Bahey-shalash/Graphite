@testable import GraphiteCore

extension NotebookArchivePath {
    /// A path the test writes as a literal; a literal that is not a safe path is a mistake in the test.
    static func fixture(_ text: String) -> NotebookArchivePath {
        guard let path = NotebookArchivePath(validating: text) else { preconditionFailure("not a safe archive path: \(text)") }
        return path
    }
}
