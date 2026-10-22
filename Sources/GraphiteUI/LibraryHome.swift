import SwiftUI
import GraphiteCore

/// The library as the window's home in Library mode on the iPad and the Mac: a house
/// button leads the first side's tab bar, and the library covers that side until a tab
/// is chosen. Documents stay open beneath it.
struct LibraryHomeButton: View {
    let library: LibraryModel
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            Task { await library.showHome() }
        } label: {
            Image(systemName: library.isShownAsHome ? "house.fill" : "house")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(library.isShownAsHome ? accent : Color.secondary)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library")
        .accessibilityAddTraits(library.isShownAsHome ? .isSelected : [])
        .help("Library")
    }
}

/// Folds the sidebar away when the library takes over files, so the window is either a
/// library and tabs or Obsidian's tree and tabs, as the switch in each chooses. Search in
/// all files may still open it, for its results; nothing else does.
struct LibraryModeSidebarVisibility: ViewModifier {
    let presentation: LibraryPresentation
    let isCompactWidth: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    func body(content: Content) -> some View {
        content.onChange(of: presentation, initial: true) { previousPresentation, presentation in
            guard !isCompactWidth else { return }
            switch presentation {
            case .library: columnVisibility = .detailOnly
            // Switching to List opens the file tree it switched to; a launch in List keeps
            // the window's own choice.
            case .list: columnVisibility = previousPresentation == .library ? .all : .automatic
            }
        }
    }
}

/// What the library's top row offers of the window once the sidebar is gone: finding a
/// file, the vaults, and Settings.
struct LibraryWindowActions {
    let showSearch: () -> Void
    let showSettings: () -> Void
    let showVaults: () -> Void
}

extension EnvironmentValues {
    /// Nil outside a window that provides them; the library then offers none of them.
    @Entry var libraryWindowActions: LibraryWindowActions?
}

extension WorkspaceModel {
    /// Where a file chosen in the library opens: in the active tab when it is empty, as
    /// there is nothing to keep there, else in a tab of its own.
    var libraryOpeningPlacement: TabPlacement {
        layout.activeTab.path == nil && layout.activeTab.coreView == nil && activeDocument.pluginViewIdentifier == nil ? .currentTab : .newTab
    }
}
