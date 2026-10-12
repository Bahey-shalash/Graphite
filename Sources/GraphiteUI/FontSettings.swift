import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// One of Obsidian's three font settings in Settings › Appearance › Font.
enum VaultFontRole: String, CaseIterable, Identifiable {
    case interface, text, monospace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interface: "Interface Font"
        case .text: "Text Font"
        case .monospace: "Monospace Font"
        }
    }

    /// What the font is used for, as Obsidian's descriptions say it, for Graphite.
    var summary: String {
        switch self {
        case .interface: "File list, outline, tab titles, search results and backlinks."
        case .text: "Notes when editing and reading."
        case .monospace: "Code blocks, inline code and properties shown as source."
        }
    }

    /// Where the setting lives in `appearance.json`.
    var keyPath: WritableKeyPath<ObsidianAppearance, FontFamilyList> {
        switch self {
        case .interface: \.interfaceFontFamilies
        case .text: \.textFontFamilies
        case .monospace: \.monospaceFontFamilies
        }
    }

    /// The font Graphite uses when none is chosen.
    var defaultFamily: ResolvedFontFamily {
        self == .monospace ? .system(.monospaced) : .system(.standard)
    }

    func resolvedFamily(in typography: NoteTypography) -> ResolvedFontFamily {
        switch self {
        case .interface: typography.interfaceFamily
        case .text: typography.textFamily
        case .monospace: typography.monospaceFamily
        }
    }
}

/// Settings › Appearance › Font: Obsidian's five font settings, stored in the vault's
/// `.obsidian/appearance.json` so Obsidian and Graphite show the vault alike.
struct FontSettingsSection: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The size under the slider while it is dragged; written when the drag ends.
    @State private var draggedFontSize: Double?

    private var shownFontSize: Int { draggedFontSize.map { size in Int(size.rounded()) } ?? workspace.noteBaseFontSize }

    var body: some View {
        Section {
            ForEach(VaultFontRole.allCases) { role in
                NavigationLink {
                    FontFamilyPickerPage(workspace: workspace, role: role)
                } label: {
                    LabeledContent {
                        Text(fontName(for: role))
                    } label: {
                        Text(role.title)
                        Text(role.summary)
                    }
                }
            }
            fontSizeRow
            Toggle(isOn: Binding(get: { workspace.vaultAppearance.adjustsFontSizeQuickly }, set: { isOn in
                workspace.updateVaultAppearance { appearance in appearance.adjustsFontSizeQuickly = isOn }
            })) {
                Text("Quick Font Size Adjustment")
                Text(Self.quickAdjustmentSummary)
            }
            preview
        } header: {
            Text("Font")
        } footer: {
            Text("Shared with Obsidian through this vault's .obsidian/appearance.json. Notes also grow and shrink with the system text size. Buttons, menus, alerts and Settings keep the system font, so controls stay familiar and legible.")
        }
    }

    /// The chosen family's name, or Default; a vault naming only fonts this device lacks says so.
    private func fontName(for role: VaultFontRole) -> String {
        if workspace.vaultAppearance[keyPath: role.keyPath].isEmpty { return "Default" }
        if isDefaultBecauseMissing(role) { return "Default (Not Installed)" }
        return role.resolvedFamily(in: workspace.noteTypography).displayName
    }

    /// Whether the vault names fonts for this role and none of them is installed here.
    private func isDefaultBecauseMissing(_ role: VaultFontRole) -> Bool {
        let list = workspace.vaultAppearance[keyPath: role.keyPath]
        return !list.isEmpty && list.firstAvailableFamily { name in InstalledFontFamilies.family(named: name) } == nil
    }

    private static var quickAdjustmentSummary: String {
        #if os(macOS)
        "Control-scroll or pinch on the trackpad over a note, or press ⌘+, ⌘– and ⌘0."
        #else
        "Pinch a note with two fingers, or press ⌘+, ⌘– and ⌘0 on a keyboard."
        #endif
    }

    private var fontSizeRow: some View {
        LabeledContent {
            HStack(spacing: 12) {
                Slider(value: Binding(get: { draggedFontSize ?? Double(workspace.noteBaseFontSize) }, set: { size in draggedFontSize = size }),
                       in: Double(NoteFontSize.adjustableRange.lowerBound)...Double(NoteFontSize.adjustableRange.upperBound), step: 1) { isEditing in
                    guard !isEditing, let draggedFontSize else { return }
                    workspace.setNoteBaseFontSize(Int(draggedFontSize.rounded()))
                    self.draggedFontSize = nil
                }
                .frame(maxWidth: 240)
                .accessibilityLabel("Font Size")
                .accessibilityValue("\(shownFontSize) points")
                Text("\(shownFontSize)").monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
                    .accessibilityHidden(true)
                Button("Restore Default Font Size", systemImage: "arrow.counterclockwise") { workspace.resetNoteBaseFontSize() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(shownFontSize == NoteFontSize.defaultSize)
                    .help("Restore the default size, 16")
            }
        } label: {
            Text("Font Size")
            Text("\(NoteFontSize.defaultSize) by default.")
        }
    }

    /// A line in the note's text font at the note's size, as notes will show it.
    private var preview: some View {
        let typography = workspace.noteTypography
        let size = GraphitePreferences.noteTextSize(Double(shownFontSize), for: dynamicTypeSize)
        return VStack(alignment: .leading, spacing: 6) {
            Text("The quick brown fox jumps over the lazy dog.")
                .font(typography.textSwiftUIFont(size: size))
            Text("let answer = 42")
                .font(typography.monospaceSwiftUIFont(size: size * 0.9))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview in \(typography.textFamily.displayName) and \(typography.monospaceFamily.displayName)")
    }
}

/// The installed font families, each in its own face, with Default first: Obsidian's font
/// list, choosing one family. Fonts another app installed through Settings › General ›
/// Fonts are added with the system's font picker, which is the way apps reach them.
struct FontFamilyPickerPage: View {
    @Bindable var workspace: WorkspaceModel
    let role: VaultFontRole
    @State private var searchText = ""
    @State private var families: [String] = []
    @State private var showsSystemFontPicker = false

    private var chosenFamily: ResolvedFontFamily { role.resolvedFamily(in: workspace.noteTypography) }
    private var isDefaultChosen: Bool { workspace.vaultAppearance[keyPath: role.keyPath].isEmpty }

    private var shownFamilies: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return families }
        return families.filter { family in family.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    choiceRow(title: "Default", detail: role.defaultFamily.displayName, font: NoteTypography.swiftUIFont(role.defaultFamily, size: 17),
                              isChosen: isDefaultChosen) {
                        choose(FontFamilyList())
                    }
                } footer: {
                    if isDefaultChosen {
                        Text("No custom font is applied right now. Choose one below.")
                    } else if !missingFamilies.isEmpty {
                        Text("This vault also names \(missingFamilies.formatted(.list(type: .and))), not installed on this device.")
                    }
                }
            }
            Section("Installed Fonts") {
                ForEach(shownFamilies, id: \.self) { family in
                    choiceRow(title: family, detail: nil, font: .custom(family, size: 17, relativeTo: .body),
                              isChosen: !isDefaultChosen && chosenFamily == .installed(family)) {
                        choose(FontFamilyList(families: [family]))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Fonts")
        .navigationTitle(role.title)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Fonts Installed in Settings…") { showsSystemFontPicker = true }
                    .help("Choose a font installed through Settings › General › Fonts")
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showsSystemFontPicker) {
            SystemFontPicker { family in
                showsSystemFontPicker = false
                guard let family else { return }
                InstalledFontFamilies.refresh()
                families = InstalledFontFamilies.all
                choose(FontFamilyList(families: [family]))
            }
            .ignoresSafeArea()
        }
        #endif
        .task { families = InstalledFontFamilies.all }
    }

    private var missingFamilies: [String] {
        workspace.vaultAppearance[keyPath: role.keyPath].missingFamilies { name in InstalledFontFamilies.family(named: name) }
    }

    private func choose(_ list: FontFamilyList) {
        workspace.updateVaultAppearance { appearance in appearance[keyPath: role.keyPath] = list }
    }

    /// A family's name in its own face; VoiceOver reads the name and whether it is chosen.
    private func choiceRow(title: String, detail: String?, font: Font, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(font).foregroundStyle(Color.primary)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                if isChosen { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.map { detail in "\(title), \(detail)" } ?? title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

#if os(iOS)
/// The system's font picker, which lists fonts other apps installed through Settings ›
/// General › Fonts and makes the chosen one available to Graphite. Calls `finish` with the
/// chosen family, or nil when cancelled.
private struct SystemFontPicker: UIViewControllerRepresentable {
    let finish: (String?) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = false
        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIFontPickerViewController, context: Context) {
        context.coordinator.finish = finish
    }

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        var finish: (String?) -> Void

        init(finish: @escaping (String?) -> Void) { self.finish = finish }

        func fontPickerViewControllerDidPickFont(_ picker: UIFontPickerViewController) {
            let family = picker.selectedFontDescriptor?.object(forKey: .family) as? String
            finish(family)
        }

        func fontPickerViewControllerDidCancel(_ picker: UIFontPickerViewController) {
            finish(nil)
        }
    }
}
#endif
