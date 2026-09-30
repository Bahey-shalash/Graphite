import SwiftUI

/// Remembers the panel layout for one window while its documents stay mounted.
struct WorkspaceFocusMode {
    private(set) var isActive = false
    private var previousColumnVisibility = NavigationSplitViewVisibility.automatic
    private var previouslyShowedInspector = false

    mutating func enter(columnVisibility: inout NavigationSplitViewVisibility, showsInspector: inout Bool) {
        guard !isActive else { return }
        previousColumnVisibility = columnVisibility
        previouslyShowedInspector = showsInspector
        isActive = true
        columnVisibility = .detailOnly
        showsInspector = false
    }

    mutating func leave(columnVisibility: inout NavigationSplitViewVisibility, showsInspector: inout Bool) {
        guard isActive else { return }
        isActive = false
        columnVisibility = previousColumnVisibility
        showsInspector = previouslyShowedInspector
    }
}
