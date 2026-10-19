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

/// How the person takes notes, asked once. It only sets defaults: every feature stays
/// reachable whatever the answer.
enum NoteTakingStyle: String, CaseIterable, Identifiable {
    case pencil, keyboard, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: "Apple Pencil"
        case .keyboard: "Keyboard"
        case .both: "Both"
        }
    }

    var subtitle: String {
        switch self {
        case .pencil: "Handwritten notebooks first, files as a library"
        case .keyboard: "Markdown notes first, files as a list"
        case .both: "Notebooks and notes side by side"
        }
    }

    var systemImage: String {
        switch self {
        case .pencil: "applepencil.tip"
        case .keyboard: "keyboard"
        case .both: "square.and.pencil"
        }
    }

    /// The library suits notebooks; the tree suits Markdown.
    var defaultPresentation: LibraryPresentation {
        switch self {
        case .pencil, .both: .library
        case .keyboard: .list
        }
    }

    /// What the New menu offers first.
    var firstCreatedKind: CreationKind {
        switch self {
        case .pencil, .both: .notebook
        case .keyboard: .note
        }
    }
}

/// The library's settings on this device: the presentation and the note-taking answer.
@MainActor @Observable
final class NotebookLibraryPreferences {
    private enum Key {
        static let presentation = "GraphiteLibraryPresentation"
        static let noteTakingStyle = "GraphiteNoteTakingStyle"
    }

    private let defaults: UserDefaults

    var presentation: LibraryPresentation { didSet { defaults.set(presentation.rawValue, forKey: Key.presentation) } }
    /// Nil until the person answers "How do you take notes?".
    private(set) var noteTakingStyle: NoteTakingStyle?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        presentation = defaults.string(forKey: Key.presentation).flatMap(LibraryPresentation.init(rawValue:)) ?? .list
        noteTakingStyle = defaults.string(forKey: Key.noteTakingStyle).flatMap(NoteTakingStyle.init(rawValue:))
    }

    /// Records the answer and takes its presentation, which stays changeable.
    func choose(_ style: NoteTakingStyle) {
        noteTakingStyle = style
        defaults.set(style.rawValue, forKey: Key.noteTakingStyle)
        presentation = style.defaultPresentation
    }

    /// What the New menu offers first: a notebook unless the person writes with a keyboard.
    var firstCreatedKind: CreationKind {
        noteTakingStyle?.firstCreatedKind ?? (presentation == .library ? .notebook : .note)
    }
}
