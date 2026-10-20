import Foundation
import GraphiteCore
import GraphiteApple

/// The paper and page size the last notebook was made with, which the next New Notebook
/// sheet starts from. Spacing and colors stay in `GraphitePreferences`, as Settings shows them.
struct NotebookCreationDefaults {
    private enum Key {
        static let paperChoice = "GraphiteNewNotebookPaperChoice"
        static let pageSize = "GraphiteNewNotebookPageSize"
        static let orientation = "GraphiteNewNotebookOrientation"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var paperChoice: NotebookPaperChoice {
        defaults.string(forKey: Key.paperChoice).flatMap(NotebookPaperChoice.init(rawValue:)) ?? .dotted
    }

    /// A named size; a custom size is not remembered, as Goodnotes does not remember one.
    var pageSize: NotebookPageSizeChoice {
        let size = defaults.string(forKey: Key.pageSize).flatMap(NotebookPageSize.init(rawValue:)) ?? .a4
        let orientation = defaults.string(forKey: Key.orientation).flatMap(PageOrientation.init(rawValue:)) ?? .portrait
        return .named(size, orientation)
    }

    func remember(_ options: NewNotebookOptions) {
        defaults.set(options.paperChoice.rawValue, forKey: Key.paperChoice)
        if case .named(let size, let orientation) = options.pageSize {
            defaults.set(size.rawValue, forKey: Key.pageSize)
            defaults.set(orientation.rawValue, forKey: Key.orientation)
        }
    }

    /// The options a new sheet starts with: the last paper and size, with the spacing and
    /// colors Settings has.
    func initialOptions() -> NewNotebookOptions {
        NewNotebookOptions(paperChoice: paperChoice, paperStyle: GraphitePreferences.storedNotebookPaper(template: .blank, in: defaults), pageSize: pageSize)
    }
}
