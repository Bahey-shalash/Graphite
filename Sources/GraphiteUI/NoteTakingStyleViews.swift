import SwiftUI

/// "How do you take notes?", asked once on the iPad. The answer only sets defaults.
struct NoteTakingStyleQuestion: View {
    let preferences: NotebookLibraryPreferences
    private static let explanation =
        "Graphite sets itself up for it. Notebooks, notes and both ways of showing files stay available whatever you choose, and Settings › General changes it."
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How do you take notes?")
                    .font(.title2.weight(.semibold))
                Text(Self.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(NoteTakingStyle.allCases) { style in
                    Button {
                        preferences.choose(style)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: style.systemImage)
                                .font(.title2)
                                .frame(width: 36)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).font(.headline)
                                Text(style.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 480)
        .interactiveDismissDisabled()
        .presentationSizing(.fitted)
    }
}

/// The answer and the file presentation, in Settings › General.
struct NoteTakingSettingsSection: View {
    @Bindable var preferences: NotebookLibraryPreferences
    private static let explanation = "Library shows folders and files as pictures of their pages, as notebook apps do; List shows Obsidian's file tree. "
        + "The New menu offers notebooks first unless you take notes with a keyboard."

    var body: some View {
        Section {
            Picker("I Take Notes With", selection: Binding(get: { preferences.noteTakingStyle }, set: { style in
                if let style { preferences.choose(style) }
            })) {
                if preferences.noteTakingStyle == nil { Text("Not Chosen").tag(NoteTakingStyle?.none) }
                ForEach(NoteTakingStyle.allCases) { style in Text(style.title).tag(Optional(style)) }
            }
            Picker("Show Files As", selection: $preferences.presentation) {
                ForEach(LibraryPresentation.allCases) { presentation in Label(presentation.title, systemImage: presentation.systemImage).tag(presentation) }
            }
        } header: {
            Text("Notes and Notebooks")
        } footer: {
            Text(Self.explanation)
                .formFooterAlignment()
        }
    }
}

/// Asks "How do you take notes?" once on the iPad, when a vault is open and it was never answered.
struct NoteTakingQuestionPresentation: ViewModifier {
    let preferences: NotebookLibraryPreferences
    let vaultIdentifier: UUID?
    /// False for root views made in tests.
    let isAsking: Bool
    @State private var showsQuestion = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showsQuestion) { NoteTakingStyleQuestion(preferences: preferences) }
            .onChange(of: vaultIdentifier, initial: true) {
                #if canImport(UIKit)
                if isAsking, UIDevice.current.userInterfaceIdiom == .pad, vaultIdentifier != nil, preferences.noteTakingStyle == nil { showsQuestion = true }
                #endif
            }
    }
}
