import SwiftUI
import GraphiteCore

/// What the File recovery sheet opens on: one note's history, or every note with copies.
struct FileRecoveryRequest: Identifiable {
    let id = UUID()
    /// Nil lists every note with copies, deleted ones included.
    let path: VaultPath?
}

/// A list or a copy's text that the File recovery sheet reads: still being read, read, or
/// not readable with the reason. A failed read is never shown as an empty list.
enum FileRecoveryReading<Value: Sendable>: Sendable {
    case reading
    case read(Value)
    case failed(String)

    var value: Value? {
        if case .read(let value) = self { return value }
        return nil
    }

    /// Reads away from the main thread. A vault whose store could not be opened, and any
    /// error the store throws, is a failure that names the reason.
    static func load(from fileRecovery: FileRecoveryStore?, _ reading: @escaping @Sendable (FileRecoveryStore) throws -> Value) async -> FileRecoveryReading<Value> {
        guard let fileRecovery else { return .failed("Graphite could not open the folder where this vault's file recovery copies are kept.") }
        return await Task.detached(priority: .userInitiated) {
            do { return FileRecoveryReading.read(try reading(fileRecovery)) } catch { return FileRecoveryReading.failed(error.localizedDescription) }
        }.value
    }
}

/// What the sheet shows when a list or a copy could not be read: the reason and Try Again.
private struct FileRecoveryReadFailure: View {
    let title: String
    let reason: String
    let tryAgain: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("Try Again") { Task { await tryAgain() } }
        }
    }
}

/// Obsidian's File recovery: notes with copies, a note's copies by time, and a copy's text,
/// which can be restored or copied.
struct FileRecoverySheet: View {
    @Bindable var workspace: WorkspaceModel
    let request: FileRecoveryRequest
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath: [VaultPath] = []
    @State private var notes = FileRecoveryReading<[FileRecoveryStore.RecoverableNote]>.reading
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if case .failed(let reason) = notes {
                    FileRecoveryReadFailure(title: "Snapshots Could Not Be Read", reason: reason) { await loadNotes() }
                } else if notes.value?.isEmpty == true {
                    ContentUnavailableView("No Snapshots Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Graphite keeps a copy of a note before a save changes it, at most every \(workspace.preferences.snapshotIntervalMinutes) minutes, and before it is deleted."))
                }
                ForEach(filteredNotes) { note in
                    NavigationLink(value: note.path) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(workspace.preferences.displayName(for: note.path)).lineLimit(1)
                                if !workspace.isInVault(note.path) {
                                    Text("Deleted").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                                }
                            }
                            Text(note.path.parent.rawValue.isEmpty ? note.latestSnapshotDate.formatted(.relative(presentation: .named))
                                 : note.path.parent.rawValue + " · " + note.latestSnapshotDate.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Find a note")
            .navigationTitle("File Recovery")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: VaultPath.self) { path in
                NoteSnapshotList(workspace: workspace, path: path) { dismiss() }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .task {
            if let path = request.path { navigationPath = [path] }
            await loadNotes()
        }
    }

    private func loadNotes() async {
        notes = .reading
        notes = await FileRecoveryReading.load(from: workspace.fileRecovery) { fileRecovery in try fileRecovery.recoverableNotes() }
    }

    private var filteredNotes: [FileRecoveryStore.RecoverableNote] {
        let readNotes = notes.value ?? []
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return readNotes }
        return readNotes.filter { note in FuzzyMatcher.match(trimmedQuery, in: note.path.rawValue) != nil }
    }
}

/// A note's copies, newest first; each opens its text.
private struct NoteSnapshotList: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    let close: () -> Void
    @State private var snapshots = FileRecoveryReading<[FileRecoveryStore.Snapshot]>.reading

    var body: some View {
        List {
            if case .failed(let reason) = snapshots {
                FileRecoveryReadFailure(title: "This Note's Snapshots Could Not Be Read", reason: reason) { await loadSnapshots() }
            } else if snapshots.value?.isEmpty == true {
                ContentUnavailableView("No Snapshots of This Note", systemImage: "clock.arrow.circlepath",
                                       description: Text("A copy is kept before a save changes the note, at most every \(workspace.preferences.snapshotIntervalMinutes) minutes."))
            }
            ForEach(snapshots.value ?? []) { snapshot in
                NavigationLink {
                    SnapshotPreview(workspace: workspace, path: path, snapshot: snapshot, close: close)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.date.formatted(date: .abbreviated, time: .standard))
                        Text(snapshot.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(workspace.preferences.displayName(for: path))
        .task { await loadSnapshots() }
    }

    private func loadSnapshots() async {
        let path = path
        snapshots = .reading
        snapshots = await FileRecoveryReading.load(from: workspace.fileRecovery) { fileRecovery in try fileRecovery.snapshots(for: path) }
    }
}

/// A copy's text, read-only, with Restore and Copy.
private struct SnapshotPreview: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    let snapshot: FileRecoveryStore.Snapshot
    let close: () -> Void
    @State private var reading = FileRecoveryReading<String>.reading
    @State private var isConfirmingRestore = false

    private var text: String? { reading.value }

    var body: some View {
        ScrollView {
            Text(text ?? "")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .overlay {
            switch reading {
            case .reading: ProgressView()
            case .failed(let reason): FileRecoveryReadFailure(title: "This Snapshot Could Not Be Read", reason: reason) { await loadText() }
            case .read: EmptyView()
            }
        }
        .navigationTitle(snapshot.date.formatted(date: .abbreviated, time: .shortened))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") { if let text { Pasteboard.copy(text) } }
                    .disabled(text == nil)
                Button("Restore", systemImage: "arrow.uturn.backward") { isConfirmingRestore = true }
                    .disabled(text == nil)
            }
        }
        .confirmationDialog(restoreQuestion, isPresented: $isConfirmingRestore, titleVisibility: .visible) {
            Button("Restore This Version") {
                close()
                Task { await workspace.restore(snapshot, of: path) }
            }
        } message: {
            Text(restoreExplanation)
        }
        .task { await loadText() }
    }

    private func loadText() async {
        let snapshot = snapshot
        reading = .reading
        reading = await FileRecoveryReading.load(from: workspace.fileRecovery) { fileRecovery in try fileRecovery.text(of: snapshot) }
    }

    private var restoreQuestion: String {
        workspace.isInVault(path) ? "Replace “\(path.name)” with this version?" : "Recreate “\(path.name)” from this version?"
    }

    private var restoreExplanation: String {
        if workspace.isInVault(path) { return "The current version is kept as a snapshot too, so this can be undone from here." }
        return path.parent == .root ? "The note is created again at the top of the vault." : "The note is created again in “\(path.parent.rawValue)”."
    }
}
