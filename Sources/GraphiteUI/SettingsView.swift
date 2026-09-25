import SwiftUI
import GraphiteCore

/// Settings laid out like Obsidian's: options on the left, one page per area or plugin.
struct SettingsView: View {
    @Bindable var workspace: WorkspaceModel
    let manageVaults: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPage: SettingsPage? = .general
    @State private var vaultSettingsChanges = VaultSettingsChanges()

    enum SettingsPage: Hashable {
        case general, editor, filesAndLinks, appearance, corePlugins
        case plugin(CorePlugin)
    }

    /// Plugins that have options of their own, like Obsidian's plugin tabs.
    private static let configurablePlugins: [CorePlugin] = [.colors, .drawings, .audioRecorder, .templates, .dailyNotes, .fileRecovery]

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section("Options") {
                    Label("General", systemImage: "gearshape").tag(SettingsPage.general)
                    Label("Editor", systemImage: "pencil.line").tag(SettingsPage.editor)
                    Label("Files and links", systemImage: "folder").tag(SettingsPage.filesAndLinks)
                    Label("Appearance", systemImage: "paintbrush").tag(SettingsPage.appearance)
                    Label("Core plugins", systemImage: "puzzlepiece.extension").tag(SettingsPage.corePlugins)
                }
                let enabledConfigurablePlugins = Self.configurablePlugins.filter(workspace.preferences.isEnabled)
                if !enabledConfigurablePlugins.isEmpty {
                    Section("Core plugins") {
                        ForEach(enabledConfigurablePlugins) { plugin in
                            Label(plugin.title, systemImage: plugin.systemImage).tag(SettingsPage.plugin(plugin))
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } detail: {
            NavigationStack {
                page
                    .formStyle(.grouped)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
        // The root view's alert cannot appear over this sheet, and a setting that failed to
        // save must say so while its page is still open.
        .alert("Graphite", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { isPresented in if !isPresented { workspace.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(workspace.errorMessage ?? "") }
    }

    @ViewBuilder private var page: some View {
        switch selectedPage ?? .general {
        case .general: GeneralSettingsPage(workspace: workspace) { dismiss(); manageVaults() }
        case .editor: EditorSettingsPage(workspace: workspace, preferences: workspace.preferences, vaultSettingsChanges: vaultSettingsChanges)
        case .filesAndLinks: FilesAndLinksSettingsPage(workspace: workspace, vaultSettingsChanges: vaultSettingsChanges)
        case .appearance: AppearanceSettingsPage(preferences: workspace.preferences)
        case .corePlugins: CorePluginsSettingsPage(preferences: workspace.preferences)
        case .plugin(.colors): ColorsSettingsPage(preferences: workspace.preferences)
        case .plugin(.drawings): DrawingsSettingsPage(preferences: workspace.preferences)
        case .plugin(.audioRecorder): AudioRecorderSettingsPage(preferences: workspace.preferences)
        case .plugin(.templates): TemplatesSettingsPage(workspace: workspace)
        case .plugin(.dailyNotes): DailyNotesSettingsPage(workspace: workspace)
        case .plugin(.fileRecovery): FileRecoverySettingsPage(workspace: workspace, preferences: workspace.preferences) { dismiss() }
        case .plugin: CorePluginsSettingsPage(preferences: workspace.preferences)
        }
    }
}

private struct GeneralSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    let manageVaults: () -> Void

    var body: some View {
        Form {
            Section {
                if let identifier = workspace.currentVaultIdentifier, let vault = workspace.vaultLibrary.vault(withIdentifier: identifier) {
                    LabeledContent("Vault", value: vault.name)
                    LabeledContent("Location", value: workspace.vaultLibrary.readableLocation(of: vault))
                }
                Button("Manage Vaults…", systemImage: "folder.badge.gearshape") { manageVaults() }
            } header: {
                Text("Vault")
            } footer: {
                Text("A vault is an ordinary folder. Graphite edits its files in place, so Obsidian and other apps see the same notes. Switch vaults from the vault name at the bottom of the sidebar.")
            }
            if workspace.store != nil {
                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            if workspace.isIndexing { ProgressView().controlSize(.small) }
                            Text(workspace.indexingMessage.isEmpty ? "Not indexed yet" : workspace.indexingMessage).foregroundStyle(.secondary)
                        }
                    }
                    Button("Rebuild Search Index", systemImage: "arrow.clockwise") { Task { await workspace.rebuildIndex() } }
                        .disabled(workspace.isIndexing)
                } header: {
                    Text("Search")
                } footer: {
                    Text("The search index is a disposable cache stored outside your vault. Rebuilding it never changes your files.")
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build")
            }
        }
        .navigationTitle("General")
    }
}

private struct EditorSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var preferences: GraphitePreferences
    let vaultSettingsChanges: VaultSettingsChanges

    private var vaultSettings: ObsidianSettings { vaultSettingsChanges.settings(of: workspace) }

    /// A setting stored in the vault's `.obsidian/app.json`.
    private func vaultSetting<Value>(_ keyPath: WritableKeyPath<ObsidianSettings, Value> & Sendable) -> Binding<Value> {
        Binding(get: { vaultSettings[keyPath: keyPath] }, set: { newValue in
            vaultSettingsChanges.update(workspace) { settings in settings[keyPath: keyPath] = newValue }
        })
    }

    var body: some View {
        Form {
            Section {
                Picker("Default view for new notes", selection: $preferences.defaultNoteView) {
                    ForEach(DefaultNoteView.allCases) { view in Text(view.title).tag(view) }
                }
                Picker("Default editing mode", selection: $preferences.defaultEditingMode) {
                    ForEach(EditingMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("Live Preview hides Markdown syntax except where your cursor is and shows tables, math, properties, and embeds in place. Source mode shows every character.")
            }
            Section {
                Toggle("Readable line length", isOn: $preferences.usesReadableLineLength)
                Toggle("Spellcheck", isOn: $preferences.usesSpellChecking)
                if workspace.store != nil {
                    Toggle("Strict line breaks", isOn: vaultSetting(\.usesStrictLineBreaks))
                }
            } header: {
                Text("Display")
            } footer: {
                Text("With strict line breaks off, a single line break starts a new line when reading, as in Obsidian. This option is stored in the vault's .obsidian/app.json.")
            }
            // Only the iPad editor continues lists, pairs characters, and indents as you
            // type; the Mac editor has none of these, so they would do nothing there.
            #if canImport(UIKit)
            if workspace.store != nil {
                Section {
                    Toggle("Smart indent lists", isOn: vaultSetting(\.continuesLists))
                    Toggle("Auto pair brackets", isOn: vaultSetting(\.pairsBrackets))
                    Toggle("Auto pair Markdown syntax", isOn: vaultSetting(\.pairsMarkdown))
                    Toggle("Indent using tabs", isOn: vaultSetting(\.indentsWithTabs))
                    if !vaultSettings.indentsWithTabs {
                        Stepper("Tab indent size: \(vaultSettings.tabSize)", value: vaultSetting(\.tabSize), in: 1...8)
                    }
                } header: {
                    Text("Typing")
                } footer: {
                    Text("Return continues a list, a task list, or a quote, and Tab indents it. Brackets and quotes are typed in pairs, and *, _, ~, =, ` or $ wrap selected text. Shared with Obsidian in .obsidian/app.json.")
                }
            }
            #endif
        }
        .navigationTitle("Editor")
    }
}

private struct AppearanceSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            #if os(iOS)
            AppIconSettingsSection()
            #endif
            Section("Theme") {
                Picker("Base color scheme", selection: $preferences.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }
            Section {
                AccentColorGrid(selectedHex: $preferences.accentHex)
                ColorPicker("Custom color", selection: Binding(get: { preferences.accentColor }, set: { color in
                    if let hex = color.sRGBHex { preferences.accentHex = hex }
                }), supportsOpacity: false)
                if preferences.accentHex != GraphiteTheme.defaultAccentHex {
                    Button("Restore Default Accent", systemImage: "arrow.uturn.backward") { preferences.accentHex = GraphiteTheme.defaultAccentHex }
                }
            } header: {
                Text("Accent color")
            } footer: {
                Text("Used for links, checkboxes, selections, and buttons. Purple matches Obsidian's default.")
            }
            Section {
                Toggle("Show inline title", isOn: $preferences.showsInlineTitle)
            } header: {
                Text("Interface")
            } footer: {
                Text("Shows the note's file name as a large title above its content, with its extension when Files and links › Show file extensions is on.")
            }
            Section {
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $preferences.textSize, in: GraphitePreferences.textSizeRange, step: 1).frame(maxWidth: 240)
                        Text("\(Int(preferences.textSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("The quick brown fox jumps over the lazy dog.").font(.system(size: preferences.textSize))
            } header: {
                Text("Font")
            } footer: {
                Text("Applies to notes when editing and reading.")
            }
        }
        .navigationTitle("Appearance")
    }
}

/// Swatches for the preset accents, like the color choices in Obsidian's Appearance settings.
private struct AccentColorGrid: View {
    @Binding var selectedHex: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(GraphiteTheme.accentPresets, id: \.hex) { preset in
                let isSelected = selectedHex == preset.hex
                Button { selectedHex = preset.hex } label: {
                    Circle()
                        .fill(Color(graphiteHex: preset.hex) ?? .gray)
                        .frame(width: 32, height: 32)
                        .overlay { if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } }
                        .padding(4)
                        .overlay { Circle().strokeBorder(isSelected ? Color.primary.opacity(0.5) : .clear, lineWidth: 2) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CorePluginsSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            Section {
                ForEach(CorePlugin.allCases) { plugin in
                    Toggle(isOn: Binding(get: { preferences.isEnabled(plugin) }, set: { isEnabled in preferences.setEnabled(plugin, isEnabled) })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.title)
                                Text(plugin.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: plugin.systemImage) }
                    }
                }
            } footer: {
                Text("Turning a plugin off hides it in Graphite. It never changes your notes.")
            }
        }
        .navigationTitle("Core plugins")
    }
}

private struct ColorsSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            Section {
                ForEach($preferences.colorPalette) { $color in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            ColorPicker("Color", selection: Binding(get: { Color(graphiteHex: color.hex) ?? .red }, set: { newColor in
                                if let hex = newColor.sRGBHex { color.hex = hex }
                            }), supportsOpacity: false)
                            .labelsHidden()
                            TextField("Name", text: $color.name)
                                .autocorrectionDisabled()
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                #endif
                            Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let problem = PaletteColorNames.problem(with: color, in: preferences.colorPalette) {
                            Text(problem).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                .onDelete { offsets in preferences.colorPalette.remove(atOffsets: offsets) }
                .onMove { offsets, destination in preferences.colorPalette.move(fromOffsets: offsets, toOffset: destination) }
                Button("Add Color", systemImage: "plus") {
                    preferences.colorPalette.append(PaletteColor(name: PaletteColorNames.unusedName(in: preferences.colorPalette), hex: "#888888"))
                }
                Button("Restore Default Palette", systemImage: "arrow.counterclockwise") { preferences.colorPalette = PaletteColor.defaultPalette }
            } header: {
                Text("Palette")
            } footer: {
                Text("Format › Color writes the hex color, as the Colors plugin for Obsidian does (`~={#e93147}text=~`), so notes look the same in both apps. A note written with a name, as in `~={red}text=~`, takes the color of that name here, so renaming or removing a color changes it.")
            }
        }
        .navigationTitle("Colors")
    }
}

/// Which palette names a note can refer to, as in `~={red}text=~`.
enum PaletteColorNames {
    /// Why notes cannot use this color's name, or nil when they can.
    static func problem(with color: PaletteColor, in palette: [PaletteColor]) -> String? {
        let name = color.name
        if name.isEmpty { return "Name this color to use it in notes and menus." }
        if name.contains(where: { character in character.isWhitespace || character == "}" }) { return "Notes cannot use a name with spaces or “}”." }
        if TextColorMarkup.canonicalHex(name) != nil { return "Notes read this name as a hex color, not as this color." }
        if palette.first(where: { paletteColor in paletteColor.name == name })?.id != color.id { return "Another color above has this name, and notes use that one." }
        return nil
    }

    /// A name no color in the palette has yet.
    static func unusedName(in palette: [PaletteColor]) -> String {
        let usedNames = Set(palette.map(\.name))
        var number = palette.count + 1
        while usedNames.contains("color-\(number)") { number += 1 }
        return "color-\(number)"
    }
}

private struct DrawingsSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            Section {
                Picker("Save drawings as", selection: $preferences.drawingFormat) {
                    ForEach(DrawingFormat.allCases) { format in Text(format.title).tag(format) }
                }
                Picker("Background", selection: $preferences.drawingBackground) {
                    ForEach(DrawingBackground.allCases) { background in Text(background.title).tag(background) }
                }
            } header: {
                Text("New drawings")
            } footer: {
                Text("\(preferences.drawingFormat.summary) Every format opens in other apps, and Graphite can edit the strokes again later. An existing drawing keeps its format; use Export a Copy in the drawing editor for another one.")
            }
        }
        .navigationTitle("Pencil drawings")
    }
}

private struct AudioRecorderSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            Section {
                Toggle("Embed recordings in the current note", isOn: $preferences.embedsRecordingsInNote)
            } footer: {
                Text("Recordings are saved as ordinary .m4a files in the attachment folder of the note you were in, like Obsidian's audio recorder. When this is on, the recording is also embedded at your cursor when you stop.")
            }
        }
        .navigationTitle("Audio recorder")
    }
}

/// Obsidian's File recovery options. The copies are on this device, outside the vault.
private struct FileRecoverySettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var preferences: GraphitePreferences
    let closeSettings: () -> Void
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Stepper("Snapshot interval: \(preferences.snapshotIntervalMinutes) min", value: $preferences.snapshotIntervalMinutes, in: 1...60)
                Stepper("History length: \(preferences.snapshotHistoryDays) days", value: $preferences.snapshotHistoryDays, in: 1...365)
            } footer: {
                Text("A copy of a note is kept before a save changes it, at most once per interval, and before the note is deleted. Copies stay on this device, outside the vault, so they never sync.")
            }
            Section {
                Button("View Snapshots", systemImage: "clock.arrow.circlepath") {
                    closeSettings()
                    workspace.fileRecoveryRequest = FileRecoveryRequest(path: nil)
                }
                Button("Delete All Snapshots", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
            }
        }
        .navigationTitle("File recovery")
        .confirmationDialog("Delete every snapshot of this vault?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Delete All Snapshots", role: .destructive) {
                guard let fileRecovery = workspace.fileRecovery else { return }
                Task.detached(priority: .userInitiated) { try? fileRecovery.removeAllSnapshots() }
            }
        } message: {
            Text("The notes themselves are not changed.")
        }
    }
}

/// Obsidian's Templates options, kept in the vault's `.obsidian/templates.json`.
private struct TemplatesSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    @State private var draft = TemplateSettings()

    var body: some View {
        Form {
            Section {
                SettingsTextField(title: "Template folder location", prompt: "Templates", text: $draft.folder, submit: save)
            } footer: {
                Text(folderFooter)
            }
            Section {
                SettingsTextField(title: "Date format", prompt: MomentDateFormat.defaultDateFormat, text: $draft.dateFormat, submit: save)
                SettingsTextField(title: "Time format", prompt: MomentDateFormat.defaultTimeFormat, text: $draft.timeFormat, submit: save)
            } footer: {
                Text("{{date}} is written as “\(MomentDateFormat.string(from: .now, format: draft.dateFormat.isEmpty ? MomentDateFormat.defaultDateFormat : draft.dateFormat))” and {{time}} as “\(MomentDateFormat.string(from: .now, format: draft.timeFormat.isEmpty ? MomentDateFormat.defaultTimeFormat : draft.timeFormat))”. A variable can take its own format, as in {{date:dddd, MMMM Do}}. Formats use Moment.js tokens, as in Obsidian.")
            }
        }
        .navigationTitle("Templates")
        .onAppear { draft = workspace.templateSettings }
        .onDisappear(perform: save)
    }

    private var folderFooter: String {
        let folder = draft.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if folder.isEmpty { return "Templates are notes in this folder. Insert one with Insert › Template… or “Templates: Insert template” in the command palette; {{title}}, {{date}} and {{time}} are filled in, and its properties are added to the note's." }
        return workspace.isDirectory((try? VaultPath(folder)) ?? .root) ? "Templates come from “\(folder)”." : "There is no folder “\(folder)” in this vault yet."
    }

    private func save() {
        var settings = draft
        settings.folder = settings.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if settings.dateFormat.trimmingCharacters(in: .whitespaces).isEmpty { settings.dateFormat = MomentDateFormat.defaultDateFormat }
        if settings.timeFormat.trimmingCharacters(in: .whitespaces).isEmpty { settings.timeFormat = MomentDateFormat.defaultTimeFormat }
        Task { await workspace.updateTemplateSettings(settings) }
    }
}

/// Obsidian's Daily notes options, kept in the vault's `.obsidian/daily-notes.json`.
private struct DailyNotesSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    @State private var draft = DailyNoteSettings()

    var body: some View {
        Form {
            Section {
                SettingsTextField(title: "Date format", prompt: MomentDateFormat.defaultDateFormat, text: $draft.format, submit: save)
                SettingsTextField(title: "New file location", prompt: "Vault folder", text: $draft.folder, submit: save)
                SettingsTextField(title: "Template file location", prompt: "Templates/Daily", text: $draft.template, submit: save)
            } footer: {
                Text(pathFooter)
            }
            Section {
                Toggle("Open daily note on startup", isOn: Binding(get: { draft.opensOnStartup }, set: { opensOnStartup in
                    draft.opensOnStartup = opensOnStartup
                    save()
                }))
            } footer: {
                Text("Today's note opens when the vault opens. Open it any time from the New menu in the sidebar or “Daily notes: Open today's daily note” in the command palette, which also moves to the previous and next daily notes.")
            }
        }
        .navigationTitle("Daily notes")
        .onAppear { draft = workspace.dailyNoteSettings }
        .onDisappear(perform: save)
    }

    private var pathFooter: String {
        var settings = draft
        if settings.format.trimmingCharacters(in: .whitespaces).isEmpty { settings.format = MomentDateFormat.defaultDateFormat }
        settings.folder = settings.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let example = (try? settings.notePath(for: .now).rawValue) ?? "an invalid path"
        var footer = "Today's note is “\(example)”. A “/” in the format makes folders, as in YYYY/MM/YYYY-MM-DD."
        if let templatePath = settings.templatePath, (try? templatePath.url(in: workspace.folderAccess?.root ?? URL(fileURLWithPath: "/"))).map({ location in FileManager.default.fileExists(atPath: location.path) }) != true {
            footer += " There is no note “\(templatePath.rawValue)” in this vault yet."
        }
        return footer
    }

    private func save() {
        var settings = draft
        if settings.format.trimmingCharacters(in: .whitespaces).isEmpty { settings.format = MomentDateFormat.defaultDateFormat }
        settings.folder = settings.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        settings.template = settings.template.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        Task { await workspace.updateDailyNoteSettings(settings) }
    }
}

/// A labeled text field for a setting, saved on Return.
private struct SettingsTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let submit: () -> Void

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(submit)
        }
    }
}

/// The options Obsidian calls "Files and links". Changes are written to the vault's
/// `.obsidian/app.json`, so Obsidian and Graphite always agree.
private struct FilesAndLinksSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    let vaultSettingsChanges: VaultSettingsChanges
    @State private var locationChoice = AttachmentLocationChoice.vaultFolder
    @State private var folderName = ""
    @State private var newNoteFolder = ""

    var body: some View {
        Form {
            Section {
                Toggle("Show file extensions", isOn: Binding(get: { workspace.preferences.showsFileExtensions },
                                                              set: { showsFileExtensions in workspace.preferences.showsFileExtensions = showsFileExtensions }))
            } footer: {
                Text("Shows names such as “Lecture.md” in the sidebar, search, links and the title bar. When off, notes are shown without “.md”.")
            }
            if workspace.store == nil {
                Section { Text("Open a vault to change its files and links settings.").foregroundStyle(.secondary) }
            } else {
                fileSection
                attachmentSection
            }
        }
        .navigationTitle("Files and links")
        .onAppear {
            loadNewNoteFolder()
            loadAttachmentLocation()
        }
        // Only a field whose saved value changed is reloaded, so a folder name still being
        // typed survives another setting's change.
        .onChange(of: workspace.vaultSettings) { oldSettings, newSettings in
            if oldSettings.newNoteLocation != newSettings.newNoteLocation { loadNewNoteFolder() }
            if oldSettings.attachmentLocation != newSettings.attachmentLocation { loadAttachmentLocation() }
        }
        .onChange(of: locationChoice) { _, newChoice in
            if !newChoice.needsFolderName || !folderName.isEmpty { commitAttachmentLocation() }
        }
        .onDisappear {
            commitNewNoteFolder()
            commitAttachmentLocation()
        }
    }

    private var vaultSettings: ObsidianSettings { vaultSettingsChanges.settings(of: workspace) }

    private func updateSettings(_ change: @escaping @MainActor (inout ObsidianSettings) -> Void) {
        vaultSettingsChanges.update(workspace, change)
    }

    private var fileSection: some View {
        Section {
            Picker("Default location for new notes", selection: Binding(get: { NewNoteLocationChoice(vaultSettings.newNoteLocation) }, set: { choice in
                let folder = newNoteFolder
                updateSettings { settings in settings.newNoteLocation = choice.location(folder: folder) }
            })) {
                ForEach(NewNoteLocationChoice.allCases) { choice in Text(choice.title).tag(choice) }
            }
            if case .specifiedFolder = vaultSettings.newNoteLocation {
                TextField("Folder path, for example Inbox", text: $newNoteFolder)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(commitNewNoteFolder)
            }
            Toggle("Automatically update internal links", isOn: Binding(get: { vaultSettings.updatesLinksAutomatically }, set: { updatesLinks in
                updateSettings { settings in settings.updatesLinksAutomatically = updatesLinks }
            }))
            Picker("Deleted files", selection: Binding(get: { vaultSettings.deletionMethod }, set: { method in
                updateSettings { settings in settings.deletionMethod = method }
            })) {
                ForEach(DeletionMethod.allCases) { method in Text(method.title).tag(method) }
            }
            Toggle("Confirm file deletion", isOn: Binding(get: { vaultSettings.confirmsDeletion }, set: { confirms in
                updateSettings { settings in settings.confirmsDeletion = confirms }
            }))
        } footer: {
            Text("When a file is renamed or moved, links to it are updated in every note. With automatic updates off, Graphite asks each time.")
        }
    }

    private var attachmentSection: some View {
        Section {
            Picker("Default location for new attachments", selection: $locationChoice) {
                ForEach(AttachmentLocationChoice.allCases) { choice in Text(choice.title).tag(choice) }
            }
            if locationChoice.needsFolderName {
                TextField(locationChoice == .specifiedFolder ? "Folder path, for example Attachments" : "Subfolder name, for example attachments", text: $folderName)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(commitAttachmentLocation)
                if folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type a folder name to use this location. Until then, new attachments go where they went before.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            LabeledContent("New files go to") {
                Text(pendingAttachmentLocation.map { attachmentLocation in
                    var settings = vaultSettings
                    settings.attachmentLocation = attachmentLocation
                    return workspace.attachmentDirectoryDescription(for: workspace.markdownSession?.path, settings: settings)
                } ?? "Invalid folder name")
                .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            Picker("New link format", selection: Binding(get: { vaultSettings.linkFormat }, set: { linkFormat in
                updateSettings { settings in settings.linkFormat = linkFormat }
            })) {
                ForEach(LinkFormat.allCases) { linkFormat in Text(linkFormat.title).tag(linkFormat) }
            }
            Toggle("Use [[Wikilinks]]", isOn: Binding(get: { vaultSettings.usesWikilinks }, set: { usesWikilinks in
                updateSettings { settings in settings.usesWikilinks = usesWikilinks }
            }))
        } header: {
            Text("Files and links")
        } footer: {
            Text("Shared with Obsidian through this vault's .obsidian/app.json. Drawings, images, recordings, and other attachments you add are saved to this location and embedded where your cursor is.")
        }
    }

    /// The location the page shows: the saved one while no folder name is typed, and nil
    /// when the typed name is not a folder inside the vault.
    private var pendingAttachmentLocation: AttachmentLocation? {
        guard locationChoice.needsFolderName else { return locationChoice.location(folderName: "") }
        if folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return vaultSettings.attachmentLocation }
        guard let folder = SettingsFolderPath.normalizedFolder(fromTypedText: folderName) else { return nil }
        // As Obsidian reads it back: a folder named "." is the vault or the note's folder.
        return AttachmentLocation(obsidianValue: locationChoice.location(folderName: folder).obsidianValue)
    }

    private func loadNewNoteFolder() {
        if case .specifiedFolder(let folder) = workspace.vaultSettings.newNoteLocation { newNoteFolder = folder }
    }

    private func loadAttachmentLocation() {
        switch workspace.vaultSettings.attachmentLocation {
        case .vaultFolder: locationChoice = .vaultFolder
        case .specifiedFolder(let folder): locationChoice = .specifiedFolder; folderName = folder
        case .sameFolderAsNote: locationChoice = .sameFolderAsNote
        case .subfolderUnderNote(let folder): locationChoice = .subfolderUnderNote; folderName = folder
        }
    }

    private func commitAttachmentLocation() {
        guard workspace.store != nil else { return }
        if locationChoice.needsFolderName && folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        guard let attachmentLocation = pendingAttachmentLocation else {
            workspace.errorMessage = "“\(folderName.trimmingCharacters(in: .whitespacesAndNewlines))” is not a folder inside this vault. New attachments still go where they went before."
            return
        }
        guard attachmentLocation != vaultSettings.attachmentLocation else { return }
        updateSettings { settings in settings.attachmentLocation = attachmentLocation }
    }

    /// Saves the typed folder on Return, and when the page closes without one.
    private func commitNewNoteFolder() {
        guard workspace.store != nil, case .specifiedFolder(let savedFolder) = vaultSettings.newNoteLocation else { return }
        guard let folder = SettingsFolderPath.normalizedFolder(fromTypedText: newNoteFolder) else {
            workspace.errorMessage = "“\(newNoteFolder.trimmingCharacters(in: .whitespacesAndNewlines))” is not a folder inside this vault. New notes still go to “\(savedFolder.isEmpty ? "the vault folder" : savedFolder)”."
            return
        }
        guard folder != savedFolder else { return }
        updateSettings { settings in settings.newNoteLocation = .specifiedFolder(folder) }
    }
}

/// Vault settings changes from the Settings pages, written to `.obsidian/app.json` one
/// after another. Each change is applied to what the previous one saved, and the pages show
/// the result before it is written, so quick taps build on each other instead of each
/// starting from the same stale copy.
@MainActor @Observable
final class VaultSettingsChanges {
    private var pendingSettings: ObsidianSettings?
    private var latestChangeNumber = 0
    private var savingTask: Task<Void, Never>?

    /// The settings as the user last set them, saved or still being written.
    func settings(of workspace: WorkspaceModel) -> ObsidianSettings {
        pendingSettings ?? workspace.vaultSettings
    }

    func update(_ workspace: WorkspaceModel, _ change: @escaping @MainActor (inout ObsidianSettings) -> Void) {
        var shownSettings = settings(of: workspace)
        change(&shownSettings)
        pendingSettings = shownSettings
        latestChangeNumber += 1
        let changeNumber = latestChangeNumber
        let previousSave = savingTask
        savingTask = Task {
            await previousSave?.value
            var settings = workspace.vaultSettings
            change(&settings)
            await workspace.updateVaultSettings(settings)
            // A failed save leaves the saved settings, and the pages show those again.
            if changeNumber == latestChangeNumber { pendingSettings = nil }
        }
    }
}

private enum AttachmentLocationChoice: String, CaseIterable, Identifiable {
    case vaultFolder, specifiedFolder, sameFolderAsNote, subfolderUnderNote
    var id: String { rawValue }

    var title: String {
        switch self {
        case .vaultFolder: "Vault folder"
        case .specifiedFolder: "In the folder specified below"
        case .sameFolderAsNote: "Same folder as current file"
        case .subfolderUnderNote: "In subfolder under current folder"
        }
    }

    var needsFolderName: Bool { self == .specifiedFolder || self == .subfolderUnderNote }

    func location(folderName: String) -> AttachmentLocation {
        switch self {
        case .vaultFolder: .vaultFolder
        case .specifiedFolder: .specifiedFolder(folderName)
        case .sameFolderAsNote: .sameFolderAsNote
        case .subfolderUnderNote: .subfolderUnderNote(folderName)
        }
    }
}

/// The choices of Obsidian's "Default location for new notes".
private enum NewNoteLocationChoice: String, CaseIterable, Identifiable {
    case vaultFolder, sameFolderAsCurrentFile, specifiedFolder
    var id: String { rawValue }

    init(_ location: NewNoteLocation) {
        switch location {
        case .vaultFolder: self = .vaultFolder
        case .sameFolderAsCurrentFile: self = .sameFolderAsCurrentFile
        case .specifiedFolder: self = .specifiedFolder
        }
    }

    var title: String {
        switch self {
        case .vaultFolder: "Vault folder"
        case .sameFolderAsCurrentFile: "Same folder as current file"
        case .specifiedFolder: "In the folder specified below"
        }
    }

    func location(folder: String) -> NewNoteLocation {
        switch self {
        case .vaultFolder: .vaultFolder
        case .sameFolderAsCurrentFile: .sameFolderAsCurrentFile
        case .specifiedFolder: .specifiedFolder(SettingsFolderPath.normalizedFolder(fromTypedText: folder) ?? "")
        }
    }
}

/// A folder typed in Files and links, written as Obsidian reads it back, so the setting
/// means the same after `.obsidian/app.json` is read again.
enum SettingsFolderPath {
    /// The folder's path inside the vault, empty for the vault folder, or nil when the text
    /// leads outside the vault or cannot be a path. Surrounding slashes are dropped, as
    /// Obsidian does when it reads the setting, and `.` steps are resolved, so `./assets`
    /// is not read back as a folder beside each note.
    ///
    /// A backslash is refused although `VaultPath` accepts one in existing names: Obsidian on
    /// Windows reads it as a separator, and new names never contain one (`FileNameRules`).
    static func normalizedFolder(fromTypedText typedText: String) -> String? {
        let folder = typedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard !folder.contains("\\") else { return nil }
        return (try? VaultPath(folder))?.rawValue
    }
}

extension DeletionMethod {
    var title: String {
        switch self {
        case .systemTrash: "Move to system trash"
        case .vaultTrash: "Move to Obsidian trash (.trash folder)"
        case .permanent: "Permanently delete"
        }
    }
}
