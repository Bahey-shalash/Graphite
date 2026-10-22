import SwiftUI
import GraphiteCore

/// Settings › Appearance › Obsidian Theme and CSS Snippets: Obsidian's theme and snippet
/// settings, stored in the vault's `.obsidian/appearance.json`. They style notes and community
/// plugins' panels; Graphite's buttons, menus and Settings keep their look.
struct ThemeSettingsSection: View {
    @Bindable var workspace: WorkspaceModel
    @State private var snippets: [ObsidianSnippet] = []

    private var appearance: ObsidianAppearance { workspace.vaultAppearance }

    var body: some View {
        Section {
            NavigationLink {
                ThemeChoicePage(workspace: workspace)
            } label: {
                LabeledContent("Theme", value: appearance.cssTheme.isEmpty ? "Default" : appearance.cssTheme)
            }
            if !appearance.cssTheme.isEmpty || !appearance.enabledCssSnippets.isEmpty {
                Toggle(isOn: Binding(get: { workspace.preferences.usesVaultTheme }, set: { isOn in workspace.preferences.usesVaultTheme = isOn })) {
                    Text("Use the Vault's Obsidian Theme")
                    Text("Notes take the colors, headings, callouts and spacing of the theme and the snippets turned on below. Turn off to keep Graphite's look on this device.")
                }
            }
        } header: {
            Text("Obsidian Theme")
        } footer: {
            Text("Saved in the vault, so Obsidian uses the same theme. Buttons, menus and Settings keep Graphite's look.")
                .formFooterAlignment()
        }
        .task(id: "\(workspace.directoryVersion)-\(appearance.cssTheme)") { await reload() }
        if !snippets.isEmpty {
            Section {
                ForEach(snippets, id: \.name) { snippet in snippetToggle(snippet) }
            } header: {
                Text("CSS Snippets")
            } footer: {
                Text(snippetsFooter)
                    .formFooterAlignment()
            }
        }
    }

    private var snippetsFooter: String {
        let explanation = "Style files in the vault's .obsidian/snippets folder, each changing how part of your notes looks. The line under a name is the comment at the top of its file. This is Obsidian's list of CSS snippets: turning one on here turns it on in Obsidian too."
        return workspace.preferences.usesVaultTheme ? explanation : explanation + " Notes show them only while Use the Vault's Obsidian Theme is on."
    }

    private func snippetToggle(_ snippet: ObsidianSnippet) -> some View {
        Toggle(isOn: Binding(get: { appearance.enabledCssSnippets.contains(snippet.name) }, set: { isOn in
            workspace.updateVaultAppearance { appearance in
                appearance.enabledCssSnippets.removeAll { name in name == snippet.name }
                if isOn { appearance.enabledCssSnippets.append(snippet.name) }
            }
        })) {
            Text(snippet.name)
            Text(snippet.description ?? "Its file has no comment at the top saying what it does.")
        }
    }

    private func reload() async {
        guard let store = workspace.store else { return }
        snippets = await store.snippets()
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
                Text("A theme styles notes and community plugins' panels, and Style Settings and the theme's own settings plugin can change it. Buttons, menus and Settings keep Graphite's look.")
                    .formFooterAlignment()
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
