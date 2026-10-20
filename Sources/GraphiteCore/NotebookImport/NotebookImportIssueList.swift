import Foundation

/// The issues of one read, each kept once, in the order first reported.
struct NotebookImportIssueList<Issue: Hashable & Sendable>: Sendable {
    private(set) var issues: [Issue] = []
    private var reported: Set<Issue> = []

    mutating func report(_ issue: Issue) {
        if reported.insert(issue).inserted { issues.append(issue) }
    }
}

typealias GoodnotesIssueList = NotebookImportIssueList<GoodnotesReadingIssue>
typealias NotabilityReadingIssues = NotebookImportIssueList<NotabilityReadingIssue>

extension NotebookImportIssueList where Issue == NotabilityReadingIssue {
    mutating func reportUnknownKeys(_ keys: [String], in context: NotabilityKeyContext, known knownKeys: Set<String>) {
        for key in keys where !knownKeys.contains(key) { report(.unknownKey(context, key: key)) }
    }
}
