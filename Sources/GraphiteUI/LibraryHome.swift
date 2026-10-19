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
            library.showHome()
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

/// Folds the file tree's sidebar away when the library takes over files, so the window is
/// either Goodnotes' library and tabs or Obsidian's tree and tabs, as Settings chooses.
struct LibraryModeSidebarVisibility: ViewModifier {
    let presentation: LibraryPresentation
    let isCompactWidth: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    func body(content: Content) -> some View {
        content.onChange(of: presentation, initial: true) { _, presentation in
            guard !isCompactWidth else { return }
            switch presentation {
            case .library: columnVisibility = .detailOnly
            case .list: columnVisibility = .automatic
            }
        }
    }
}

extension WorkspaceModel {
    /// Where a file chosen in the library opens: in the active tab when it is empty, as
    /// there is nothing to keep there, else in a tab of its own.
    var libraryOpeningPlacement: TabPlacement {
        layout.activeTab.path == nil && activeDocument.pluginViewIdentifier == nil ? .currentTab : .newTab
    }
}
