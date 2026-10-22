import SwiftUI
import GraphiteCore

/// A file sheet the sidebar or a document asks for.
enum FileSheet: Identifiable {
    case rename(VaultPath)
    case move(VaultPath)
    /// Several items chosen in the library, moved into one folder.
    case moveItems([VaultPath])
    case newFolder(in: VaultPath)

    var id: String {
        switch self {
        case .rename(let path): "rename|" + path.rawValue
        case .move(let path): "move|" + path.rawValue
        case .moveItems(let paths): "moveItems|" + paths.map(\.rawValue).joined(separator: "|")
        case .newFolder(let directory): "folder|" + directory.rawValue
        }
    }
}

/// The sheets and questions of file management, attached once at the root.
struct FileManagementPresentation: ViewModifier {
    @Bindable var workspace: WorkspaceModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $workspace.fileSheet) { sheet in
                Group {
                    switch sheet {
                    case .rename(let path): RenameSheet(workspace: workspace, path: path)
                    case .move(let path): MoveSheet(workspace: workspace, paths: [path])
                    case .moveItems(let paths): MoveSheet(workspace: workspace, paths: paths)
                    case .newFolder(let directory): NewFolderSheet(workspace: workspace, directory: directory)
                    }
                }
                .tint(workspace.preferences.accentColor)
            }
            .sheet(item: $workspace.conflictVersionsRequest) { request in
                ConflictVersionsSheet(workspace: workspace, request: request)
                    .tint(workspace.preferences.accentColor)
            }
            .confirmationDialog("Update links?", isPresented: Binding(get: { workspace.pendingMove != nil }, set: { isPresented in
                if !isPresented { workspace.pendingMove = nil }
            }), titleVisibility: .visible, presenting: workspace.pendingMove) { pendingMove in
                Button("Update Links") { Task { await workspace.resolve(pendingMove, updatesLinks: true) } }
                Button("Always Update Links") { Task { await workspace.resolve(pendingMove, updatesLinks: true, alwaysUpdates: true) } }
                Button("Don't Update") { Task { await workspace.resolve(pendingMove, updatesLinks: false) } }
                Button("Cancel", role: .cancel) {}
            } message: { pendingMove in
                let linkCount = pendingMove.plan.changedLinkCount, noteCount = pendingMove.plan.updates.count
                let change = pendingMove.path.parent == pendingMove.destination.parent
                    ? "Renaming “\(pendingMove.path.name)” to “\(pendingMove.destination.name)”"
                    : "Moving “\(pendingMove.path.name)” to “\(pendingMove.destination.parent.rawValue.isEmpty ? workspace.title : pendingMove.destination.parent.rawValue)”"
                Text("\(change) changes \(linkCount == 1 ? "1 link" : "\(linkCount) links") in \(noteCount == 1 ? "1 note" : "\(noteCount) notes"). Without the update, those links stop working.")
            }
            .confirmationDialog("Delete “\(workspace.pendingDeletion?.name ?? "")”?", isPresented: Binding(get: { workspace.pendingDeletion != nil }, set: { isPresented in
                if !isPresented { workspace.pendingDeletion = nil }
            }), titleVisibility: .visible, presenting: workspace.pendingDeletion) { path in
                Button("Delete", role: .destructive) { Task { await workspace.delete(path) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(workspace.vaultSettings.deletionMethod.confirmationExplanation(itemCount: 1))
            }
    }
}

private struct RenameSheet: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// The whole name starts selected, so typing replaces it.
    @State private var nameSelection: TextSelection?
    @FocusState private var isNameFocused: Bool

    private var isFolder: Bool { workspace.isDirectory(path) }
    private var fileExtension: String { isFolder ? "" : (path.name as NSString).pathExtension }
    private var newName: String { RenamedFileName.withoutTypedExtension(name, fileExtension: fileExtension) }
    private var problem: String? { FileNameRules.problem(with: newName, isNote: !isFolder && DocumentKind(path: path) == .markdown) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 4) {
                        TextField("Name", text: $name, selection: $nameSelection)
                            .literalTextEntry()
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(rename)
                        if !fileExtension.isEmpty { Text("." + fileExtension).foregroundStyle(.secondary) }
                    }
                } footer: {
                    if let problem, !name.isEmpty { Text(problem).foregroundStyle(.red) }
                    else if !isFolder && DocumentKind(path: path) == .markdown { Text("Links to this note are updated as the vault's settings say.") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isFolder ? "Rename Folder" : "Rename File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rename", action: rename).disabled(problem != nil) }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .onAppear {
            name = originalName
            isNameFocused = true
        }
        .task {
            // The text field puts the cursor at the end when it takes focus, so the whole
            // name is selected just after that, unless typing has already begun.
            try? await Task.sleep(for: .milliseconds(350))
            guard name == originalName else { return }
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private var originalName: String { isFolder ? path.name : path.stem }

    private func rename() {
        guard problem == nil else { return }
        let chosenName = newName
        dismiss()
        Task { await workspace.rename(path, to: chosenName) }
    }
}

/// The name a file is renamed to from what was typed.
enum RenamedFileName {
    /// Renaming keeps the file's extension, so a typed copy of it (as in a pasted
    /// "Lecture.md") is dropped rather than doubled, as the title bar's rename does.
    static func withoutTypedExtension(_ typedName: String, fileExtension: String) -> String {
        let trimmedName = typedName.trimmingCharacters(in: .whitespaces)
        guard !fileExtension.isEmpty, trimmedName.lowercased().hasSuffix("." + fileExtension.lowercased()) else { return trimmedName }
        return String(trimmedName.dropLast(fileExtension.count + 1))
    }
}

private struct NewFolderSheet: View {
    @Bindable var workspace: WorkspaceModel
    let directory: VaultPath
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    private var problem: String? { FileNameRules.problem(with: name, isNote: false) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $name).literalTextEntry().focused($isNameFocused).submitLabel(.done).onSubmit(create)
                } footer: {
                    if let problem, !name.isEmpty { Text(problem).foregroundStyle(.red) }
                    else { Text("In “\(directory.rawValue.isEmpty ? workspace.title : directory.rawValue)”") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).disabled(problem != nil) }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard problem == nil else { return }
        let folderName = name
        dismiss()
        Task { await workspace.createFolder(named: folderName, in: directory) }
    }
}

/// Obsidian's "Move file to…": every folder in the vault, searchable.
private struct MoveSheet: View {
    @Bindable var workspace: WorkspaceModel
    /// The items to move; one from a menu, several from the library's selection.
    let paths: [VaultPath]
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [VaultPath] = []
    @State private var query = ""
    @State private var isLoading = true
    /// Folders listed at most; in a vault with more, the others are found by searching.
    private static let maximumListedFolderCount = 5_000

    private var matchingFolders: [VaultPath] {
        let candidates = [VaultPath.root] + folders
        // A folder cannot go into itself, and a folder every item is already in changes nothing.
        let movable = candidates.filter { folder in
            !paths.contains { path in folder.isInside(path) } && !paths.allSatisfy { path in folder == path.parent }
        }
        guard !query.isEmpty else { return Array(movable.prefix(Self.maximumListedFolderCount)) }
        return Array(movable.lazy.filter { folder in folder.rawValue.localizedCaseInsensitiveContains(query) }.prefix(Self.maximumListedFolderCount))
    }

    var body: some View {
        let listedFolders = matchingFolders
        NavigationStack {
            List(listedFolders, id: \.rawValue) { folder in
                Button {
                    dismiss()
                    Task { for path in paths { await workspace.move(path, into: folder) } }
                } label: {
                    Label {
                        Text(folder.rawValue.isEmpty ? workspace.title : folder.rawValue).foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: folder.rawValue.isEmpty ? "building.columns" : "folder")
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
                else if listedFolders.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "Find a folder")
            .navigationTitle(paths.count == 1 ? "Move “\(paths[0].name)”" : "Move \(paths.count) Items")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .frame(minWidth: 380, minHeight: 480)
        .task {
            guard let root = workspace.folderAccess?.root else { return }
            folders = await Task.detached(priority: .userInitiated) { Self.folders(in: root) }.value
            isLoading = false
        }
    }

    /// Every visible folder, found without reading any file.
    nonisolated private static func folders(in root: URL) -> [VaultPath] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs]) else { return [] }
        var folders: [VaultPath] = []
        while let location = enumerator.nextObject() as? URL {
            guard let values = try? location.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
            if values.isDirectory == true, let folder = try? VaultPath(location.relativePath) { folders.append(folder) }
        }
        return folders.sorted { leftFolder, rightFolder in leftFolder.rawValue.localizedStandardCompare(rightFolder.rawValue) == .orderedAscending }
    }
}
