import SwiftUI

/// Library or List, in Settings › Appearance; the same switch is where files are browsed.
struct LibrarySettingsSection: View {
    @Bindable var preferences: NotebookLibraryPreferences
    private static let explanation = "Library shows folders and files as pictures of their pages; List shows Obsidian's file tree. "
        + "The switch beside your files changes it too."

    var body: some View {
        Section {
            Picker("Show Files As", selection: $preferences.presentation) {
                ForEach(LibraryPresentation.allCases) { presentation in Label(presentation.title, systemImage: presentation.systemImage).tag(presentation) }
            }
        } header: {
            Text("Files")
        } footer: {
            Text(Self.explanation)
                .formFooterAlignment()
        }
    }
}

/// The top of Settings › Appearance: the app's icon, where a phone or an iPad offers a
/// choice of icons, then how files are shown.
struct AppIconAndFilesSections: View {
    let library: NotebookLibraryPreferences

    var body: some View {
        #if os(iOS)
        AppIconSettingsSection()
        #endif
        LibrarySettingsSection(preferences: library)
    }
}
