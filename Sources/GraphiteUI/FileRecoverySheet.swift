import SwiftUI
import GraphiteCore

/// What the File recovery sheet opens on: one note's history, or every note with copies.
struct FileRecoveryRequest: Identifiable {
    let id = UUID()
    /// Nil lists every note with copies, deleted ones included.
    let path: VaultPath?
}

/// Obsidian's File recovery: notes with copies, a note's copies by time, and a copy's text,
/// which can be restored or copied.
struct FileRecoverySheet: View {
    @Bindable var workspace: WorkspaceModel
    let request: FileRecoveryRequest
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath: [VaultPath] = []
    @State private var notes: [FileRecoveryStore.RecoverableNote] = []
    @State private var query = ""
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if hasLoaded && notes.isEmpty {
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
            guard let fileRecovery = workspace.fileRecovery else { hasLoaded = true; return }
            notes = await Task.detached(priority: .userInitiated) { (try? fileRecovery.recoverableNotes()) ?? [] }.value
            hasLoaded = true
        }
    }

    private var filteredNotes: [FileRecoveryStore.RecoverableNote] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return notes }
        return notes.filter { note in FuzzyMatcher.match(trimmedQuery, in: note.path.rawValue) != nil }
    }
}

/// A note's copies, newest first; each opens its text.
private struct NoteSnapshotList: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    let close: () -> Void
    @State private var snapshots: [FileRecoveryStore.Snapshot] = []
    @State private var hasLoaded = false

    var body: some View {
        List {
            if hasLoaded && snapshots.isEmpty {
                ContentUnavailableView("No Snapshots of This Note", systemImage: "clock.arrow.circlepath",
                                       description: Text("A copy is kept before a save changes the note, at most every \(workspace.preferences.snapshotIntervalMinutes) minutes."))
            }
            ForEach(snapshots) { snapshot in
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
        .task {
            guard let fileRecovery = workspace.fileRecovery else { hasLoaded = true; return }
            let path = path
            snapshots = await Task.detached(priority: .userInitiated) { (try? fileRecovery.snapshots(for: path)) ?? [] }.value
            hasLoaded = true
        }
    }
}

/// A copy's text, read-only, with Restore and Copy.
private struct SnapshotPreview: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    let snapshot: FileRecoveryStore.Snapshot
    let close: () -> Void
    @State private var text: String?
    @State private var isConfirmingRestore = false

    var body: some View {
        ScrollView {
            Text(text ?? "")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .overlay { if text == nil { ProgressView() } }
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
        .task {
            guard let fileRecovery = workspace.fileRecovery else { return }
            let snapshot = snapshot
            text = await Task.detached(priority: .userInitiated) { try? fileRecovery.text(of: snapshot) }.value
        }
    }

    private var restoreQuestion: String {
        workspace.isInVault(path) ? "Replace “\(path.name)” with this version?" : "Recreate “\(path.name)” from this version?"
    }

    private var restoreExplanation: String {
        if workspace.isInVault(path) { return "The current version is kept as a snapshot too, so this can be undone from here." }
        return path.parent == .root ? "The note is created again at the top of the vault." : "The note is created again in “\(path.parent.rawValue)”."
    }
}
