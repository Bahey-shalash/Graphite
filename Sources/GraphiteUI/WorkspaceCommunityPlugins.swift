import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// The editor session of a note open in any tab, for a plugin's change to it.
    func openMarkdownSession(at path: VaultPath) -> MarkdownSession? {
        tabDocuments.values.lazy.compactMap(\.markdownSession).first { session in session.path == path }
    }
}
