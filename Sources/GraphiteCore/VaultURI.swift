import Foundation

/// Links that open Graphite from other apps, as Obsidian's `obsidian://` links do, with the
/// same actions and parameters: `graphite://open?vault=Physics&file=Lecture%201`. A link
/// written for Obsidian works once its scheme is changed; `obsidian://` links given to
/// Graphite directly (pasted, or shared) are read the same way.
public struct VaultURI: Equatable, Sendable {
    public static let scheme = "graphite"

    public enum Action: Equatable, Sendable {
        /// Opens a note or file. `file` resolves as a link does (`Lecture 1`, `Course/Lecture 1`,
        /// `Lecture 1#Heading`); `path` is a full file system path inside a vault.
        case open(file: String?, path: String?)
        /// Shows the search with this query.
        case search(query: String)
        /// Creates a note. `name` goes in the new-note folder, `file` is a vault path.
        case new(name: String?, file: String?, content: String, opensNote: Bool, mode: NewNoteMode)
        /// Opens today's daily note.
        case daily
    }

    /// What `new` does when the note exists already.
    public enum NewNoteMode: Equatable, Sendable {
        /// Makes a note with a free name beside it, as Obsidian does.
        case unique
        case append
        case overwrite
    }

    /// The vault's name, or its identifier; nil means the vault that is open.
    public let vault: String?
    public let action: Action

    public init(vault: String?, action: Action) {
        self.vault = vault
        self.action = action
    }

    /// Reads a `graphite://` or `obsidian://` link; nil for anything else, or an action
    /// missing what it needs.
    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme || scheme == "obsidian",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] where parameters[item.name.lowercased()] == nil {
            parameters[item.name.lowercased()] = item.value ?? ""
        }
        func nonEmpty(_ key: String) -> String? { parameters[key].flatMap { value in value.isEmpty ? nil : value } }
        func flag(_ key: String) -> Bool { parameters[key].map { value in value.isEmpty || value.lowercased() == "true" } ?? false }
        // `obsidian://open?…` puts the action in the host; `obsidian:open?…` in the path.
        let host = components.host?.lowercased() ?? ""
        let actionName = host.isEmpty ? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() : host
        switch actionName {
        case "open":
            let file = nonEmpty("file"), path = nonEmpty("path")
            // The vault alone opens it, as in Obsidian.
            self.init(vault: nonEmpty("vault"), action: .open(file: file, path: path))
        case "search":
            self.init(vault: nonEmpty("vault"), action: .search(query: parameters["query"] ?? ""))
        case "new":
            let name = nonEmpty("name"), file = nonEmpty("file")
            let mode: NewNoteMode = flag("overwrite") ? .overwrite : (flag("append") ? .append : .unique)
            self.init(vault: nonEmpty("vault"), action: .new(name: name, file: file, content: parameters["content"] ?? "", opensNote: !flag("silent"), mode: mode))
        case "daily":
            self.init(vault: nonEmpty("vault"), action: .daily)
        case "vault":
            // `obsidian://vault/Physics/Course/Lecture 1`: the vault, then the file.
            let parts = components.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard let vaultName = parts.first else { return nil }
            self.init(vault: vaultName, action: .open(file: parts.count > 1 ? parts[1] : nil, path: nil))
        default:
            return nil
        }
    }

    /// A link that opens `path` in the vault named `vaultName`, written as Obsidian writes
    /// them: spaces as `%20`, a note without `.md`.
    public static func openingLink(to path: VaultPath, inVaultNamed vaultName: String) -> String {
        let file = DocumentKind(path: path) == .markdown ? (path.rawValue as NSString).deletingPathExtension : path.rawValue
        return "\(scheme)://open?vault=\(encoded(vaultName))&file=\(encoded(file))"
    }

    /// `content` added at the end of a note, on a line of its own, for `new` with `append`.
    public static func appending(_ content: String, to text: String) -> String {
        guard !text.isEmpty, !content.isEmpty else { return text + content }
        return text + (text.hasSuffix("\n") ? "" : "\n") + content
    }

    /// Percent-encodes everything but unreserved characters and `/`, as `encodeURIComponent`
    /// does apart from the slash, which Obsidian leaves readable in paths.
    static func encoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~/")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
