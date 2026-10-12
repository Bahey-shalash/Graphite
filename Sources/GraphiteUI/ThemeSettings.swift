import SwiftUI
import GraphiteCore

/// Settings › Appearance › Themes and Snippets: Obsidian's theme and CSS snippet settings,
/// stored in the vault's `.obsidian/appearance.json`. For now they style community plugins'
/// panels, blocks and views; Graphite's own notes keep their look.
struct ThemeSettingsSection: View {
    @Bindable var workspace: WorkspaceModel
    @State private var snippetNames: [String] = []

    private var appearance: ObsidianAppearance { workspace.vaultAppearance }

    var body: some View {
        Section {
            NavigationLink {
                ThemeChoicePage(workspace: workspace)
            } label: {
                LabeledContent("Theme", value: appearance.cssTheme.isEmpty ? "Default" : appearance.cssTheme)
            }
            ForEach(snippetNames, id: \.self) { snippetName in
                Toggle(snippetName, isOn: Binding(get: { appearance.enabledCssSnippets.contains(snippetName) }, set: { isOn in
                    workspace.updateVaultAppearance { appearance in
                        appearance.enabledCssSnippets.removeAll { name in name == snippetName }
                        if isOn { appearance.enabledCssSnippets.append(snippetName) }
                    }
                }))
            }
        } header: {
            Text("Themes and Snippets")
        } footer: {
            Text(snippetNames.isEmpty
                 ? "Shared with Obsidian through .obsidian/appearance.json. The theme styles community plugins' panels, blocks and views; notes keep Graphite's look for now. CSS snippets in .obsidian/snippets appear here."
                 : "Shared with Obsidian through .obsidian/appearance.json. The theme and snippets style community plugins' panels, blocks and views; notes keep Graphite's look for now.")
        }
        .task(id: "\(workspace.directoryVersion)-\(appearance.cssTheme)") { await reload() }
    }

    private func reload() async {
        guard let store = workspace.store else { return }
        snippetNames = await store.snippetNames()
    }
}

/// The installed themes with Default first, and Obsidian's community themes to install.
struct ThemeChoicePage: View {
    @Bindable var workspace: WorkspaceModel
    @State private var installedThemes: [String] = []
    @State private var directory: [ObsidianThemeDirectoryEntry] = []
    @State private var searchText = ""
    @State private var isLoadingDirectory = false
    @State private var installingTheme: String?
    @State private var directoryError: String?

    private var chosenTheme: String { workspace.vaultAppearance.cssTheme }

    var body: some View {
        List {
            Section {
                themeRow("Default", isChosen: chosenTheme.isEmpty) { choose("") }
                ForEach(installedThemes, id: \.self) { themeName in
                    themeRow(themeName, isChosen: chosenTheme == themeName) { choose(themeName) }
                }
            } header: {
                Text("Installed Themes")
            } footer: {
                Text("A theme styles community plugins' panels, blocks and views, and lets Style Settings and the theme's own settings plugin change it. Notes keep Graphite's look for now.")
            }
            Section("Community Themes") {
                if isLoadingDirectory && directory.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let directoryError {
                    Text(directoryError).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await loadDirectory() } }
                } else {
                    ForEach(ObsidianThemeDirectoryEntry.search(directory, for: searchText).prefix(200)) { entry in
                        directoryRow(entry)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Themes")
        .navigationTitle("Theme")
        .task { await reloadInstalled(); await loadDirectory() }
    }

    private func themeRow(_ title: String, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                if isChosen { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func directoryRow(_ entry: ObsidianThemeDirectoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(entry.modes.isEmpty ? "By \(entry.author)" : "By \(entry.author) · \(entry.modes.joined(separator: " and "))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if installingTheme == entry.name {
                ProgressView()
            } else if installedThemes.contains(entry.name) {
                Button(chosenTheme == entry.name ? "In Use" : "Use") { choose(entry.name) }
                    .buttonStyle(.bordered)
                    .disabled(chosenTheme == entry.name)
            } else {
                // One quiet button per row; a column of filled buttons would compete with the list.
                Button("Install and Use") { Task { await install(entry) } }
                    .buttonStyle(.bordered)
                    .disabled(installingTheme != nil)
            }
        }
        .frame(minHeight: 44)
    }

    private func choose(_ themeName: String) {
        workspace.updateVaultAppearance { appearance in appearance.cssTheme = themeName }
    }

    private func reloadInstalled() async {
        guard let store = workspace.store else { return }
        installedThemes = await store.installedThemeNames()
    }

    private func loadDirectory() async {
        guard let store = workspace.store, directory.isEmpty else { return }
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }
        do { directory = try await ObsidianThemeInstaller(store: store).directory() }
        catch { directoryError = "Obsidian's list of themes could not be loaded. " + error.localizedDescription }
    }

    private func install(_ entry: ObsidianThemeDirectoryEntry) async {
        guard let store = workspace.store else { return }
        installingTheme = entry.name
        defer { installingTheme = nil }
        do {
            try await ObsidianThemeInstaller(store: store).install(entry)
            await reloadInstalled()
            choose(entry.name)
            // The theme's file is new; the page reads it even when the choice was already this theme.
            workspace.communityPlugins.vaultStylesDidChange()
        } catch {
            workspace.errorMessage = "“\(entry.name)” could not be installed. " + error.localizedDescription
        }
    }
}
