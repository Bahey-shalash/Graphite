import Foundation
import Observation

/// How the vault's files are shown: Obsidian's tree, or Goodnotes' grid of folders and
/// pages.
enum LibraryPresentation: String, CaseIterable, Identifiable {
    case list, library
    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet.indent"
        case .library: "square.grid.2x2"
        }
    }
}

/// How this device shows the vault's files: Library or List.
@MainActor @Observable
final class NotebookLibraryPreferences {
    private enum Key {
        static let presentation = "GraphiteLibraryPresentation"
    }

    private let defaults: UserDefaults

    var presentation: LibraryPresentation { didSet { defaults.set(presentation.rawValue, forKey: Key.presentation) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        presentation = defaults.string(forKey: Key.presentation).flatMap(LibraryPresentation.init(rawValue:)) ?? .list
    }

    /// What the New menu offers first: a notebook beside the library, a note beside the list.
    var firstCreatedKind: CreationKind {
        switch presentation {
        case .library: .notebook
        case .list: .note
        }
    }
}
