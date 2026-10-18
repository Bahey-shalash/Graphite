import SwiftUI
import GraphiteCore
import GraphiteApple

/// Settings › Read Aloud › Pronunciations: the vault's own way of saying terms, kept in the
/// ordinary file `.graphite/pronunciations.json` so it travels with the vault, and the
/// built-in terms said in full ("look-up table" for LUT), which the person can change here.
struct ReadAloudPronunciationEditor: View {
    let vaultRoot: URL?
    @State private var entries: [(term: String, say: String)] = []
    @State private var editing: PronunciationDraft?
    @State private var errorMessage: String?
    /// Why the vault's file is shown read-only, or nil when the whole file was read (or does not exist yet).
    @State private var readOnlyReason: String?
    @State private var sample = ReadAloudSession(preferences: UserDefaults(suiteName: "com.graphite.study.readAloudSample") ?? .standard)

    struct PronunciationDraft: Identifiable, Hashable {
        let id = UUID()
        var originalTerm: String?
        var term: String
        var say: String
    }

    private var fileLocation: URL? { vaultRoot?.appendingPathComponent(ReadAloudPronunciations.vaultFilePath) }

    private static let expansions = ReadAloudPronunciations.standard.terms
        .filter { _, pronunciation in pronunciation.isExpansion }
        .sorted { first, second in first.key < second.key }

    var body: some View {
        Form {
            sections
        }
        .navigationTitle("Pronunciations")
        .onAppear(perform: load)
        // Pushed inside Settings' own navigation: a sheet over the Settings sheet closed it.
        .navigationDestination(item: $editing) { draft in
            PronunciationDraftEditor(draft: draft, play: play) { saved in
                var updated = entries.filter { entry in entry.term != (draft.originalTerm ?? saved.term) && entry.term != saved.term }
                updated.append((saved.term, saved.say))
                save(updated)
            }
        }
        .alert("Pronunciations Not Saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            ForEach(entries, id: \.term) { entry in
                Button {
                    editing = PronunciationDraft(originalTerm: entry.term, term: entry.term, say: entry.say)
                } label: {
                    LabeledContent(entry.term) { Text(entry.say) }
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Edits how this term is said")
            }
            .onDelete { offsets in
                let removed = offsets.map { offset in entries[offset].term }
                save(entries.filter { entry in !removed.contains(entry.term) })
            }
            Button("Add Pronunciation…", systemImage: "plus") {
                editing = PronunciationDraft(term: "", say: "")
            }
            .disabled(vaultRoot == nil || readOnlyReason != nil)
        } header: {
            Text("This Vault")
        } footer: {
            Text(vaultRoot == nil
                 ? "Open a vault to add pronunciations."
                 : readOnlyReason
                    ?? "How this vault's terms are said, for example SIMDRAM as \"sim dee ram\". Kept in the vault's \(ReadAloudPronunciations.vaultFilePath).")
                .formFooterAlignment()
        }
        Section {
            ForEach(Self.expansions, id: \.key) { term, pronunciation in
                Button {
                    let current = entries.first { entry in entry.term == term }?.say ?? pronunciation.say
                    editing = PronunciationDraft(originalTerm: entries.contains { entry in entry.term == term } ? term : nil, term: term, say: current)
                } label: {
                    LabeledContent(term) { Text(entries.first { entry in entry.term == term }?.say ?? pronunciation.say) }
                }
                .foregroundStyle(.primary)
                .disabled(vaultRoot == nil || readOnlyReason != nil)
            }
        } header: {
            Text("Said in Full")
        } footer: {
            Text("These abbreviations are said as what they stand for. Tap one to say it differently, for example as letters.")
                .formFooterAlignment()
        }
    }

    private func load() {
        guard let fileLocation else { entries = []; readOnlyReason = nil; return }
        let reading = ReadAloudPronunciations.readVaultFile(at: fileLocation)
        readOnlyReason = Self.readOnlyReason(for: reading)
        if case .loaded(let loadedEntries, _) = reading {
            entries = loadedEntries.map { entry in (entry.term, entry.pronunciation.say) }
        } else {
            entries = []
        }
    }

    /// Why the file may not be rewritten, in words for the person, or nil when it may.
    private static func readOnlyReason(for reading: ReadAloudPronunciations.VaultFileReading) -> String? {
        let path = ReadAloudPronunciations.vaultFilePath
        switch reading {
        case .noFile:
            return nil
        case .readFailed:
            return "The vault's \(path) could not be read, for example because it is not downloaded yet. It is left untouched; try again once it is available."
        case .invalid(.notJSON):
            return "The vault's \(path) is not valid JSON. It is left untouched; fix it in a text editor to edit pronunciations here."
        case .invalid(.notAnObjectOfTerms):
            return "The vault's \(path) is not an object of terms. It is left untouched; fix it in a text editor to edit pronunciations here."
        case .invalid(.overSizeLimit):
            return "The vault's \(path) is larger than \(ReadAloudPronunciations.maximumFileBytes / 1_024) KiB. It is left untouched; shorten it in a text editor to edit pronunciations here."
        case .loaded(let entries, let termsInFile):
            guard entries.count != termsInFile else { return nil }
            return "Only \(entries.count) of the \(termsInFile) terms in the vault's \(path) can be shown. It is left untouched; edit it in a text editor."
        }
    }

    /// Writes the whole file at once, replacing it atomically; a failure keeps the old file. The
    /// file is read again first: it is only replaced when this list holds everything it holds.
    private func save(_ updated: [(term: String, say: String)]) {
        guard let fileLocation else { return }
        let reading = ReadAloudPronunciations.readVaultFile(at: fileLocation)
        guard reading.allowsRewriting else {
            readOnlyReason = Self.readOnlyReason(for: reading)
            errorMessage = readOnlyReason
            return
        }
        do {
            let data = try ReadAloudPronunciations.vaultFileData(for: updated)
            try FileManager.default.createDirectory(at: fileLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileLocation, options: .atomic)
            load()
        } catch {
            errorMessage = "The vault's pronunciation file could not be written: \(error.localizedDescription)"
        }
    }

    private func play(_ text: String) {
        guard let document = try? ReadAloudDocument.plainText(text) else { return }
        sample.refreshVoices()
        sample.load(document)
        sample.play()
    }
}

private struct PronunciationDraftEditor: View {
    @State var draft: ReadAloudPronunciationEditor.PronunciationDraft
    let play: (String) -> Void
    let save: (ReadAloudPronunciationEditor.PronunciationDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !draft.term.trimmingCharacters(in: .whitespaces).isEmpty && !draft.say.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.term.count <= 64 && draft.say.count <= 200
    }

    var body: some View {
        Form {
                Section {
                    TextField("Term, as written", text: $draft.term)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Say it as", text: $draft.say)
                        .autocorrectionDisabled()
                    Button("Play", systemImage: "play.circle") { play(draft.say) }
                        .disabled(draft.say.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Write it as it sounds: \"sim dee ram\", or letters apart: \"L U T\".")
                        .formFooterAlignment()
                }
            }
            .navigationTitle(draft.originalTerm == nil ? "New Pronunciation" : "Pronunciation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(draft); dismiss() }.disabled(!canSave)
                }
            }
    }
}
