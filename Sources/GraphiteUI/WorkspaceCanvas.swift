import Foundation
import GraphiteCore

/// Canvases in the workspace: opening a `.canvas` file in a tab, and creating one.
extension WorkspaceModel {
    /// The focused tab's canvas, once loaded.
    var canvasSession: CanvasSession? { activeDocument.loadedPath == selection ? activeDocument.canvasSession : nil }

    /// Reads a canvas for a tab. A file that is not a readable canvas throws, and the tab
    /// says why; the file is not touched.
    func openCanvasSession(at path: VaultPath, store: VaultStore) async throws -> CanvasSession {
        let snapshot = try await store.read(path, maximumBytes: CanvasFile.maximumSourceBytes)
        let session = try CanvasSession(path: path, snapshot: snapshot, store: store) { [weak self] savedPath in self?.refreshIndex(for: [savedPath]) }
        #if canImport(UIKit)
        // As for notes: "Default view for new tabs" decides between reading and editing.
        session.isWriting = preferences.initialNoteViewMode != .reading
        #endif
        return session
    }

    /// A new, empty `.canvas` file as Obsidian creates one, opened ready to add cards.
    func createCanvas(named name: String, in directory: VaultPath? = nil) async {
        guard let store else { return }
        do {
            if let problem = FileNameRules.problem(with: name, isNote: false) { throw GraphiteError.unavailable(problem) }
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: name, extension: "canvas")
            _ = try await store.save(CanvasFile.emptyFileData, at: path, expecting: .absent)
            refreshIndex(for: [path])
            await refreshDirectory()
            await open(path)
            #if canImport(UIKit)
            if let session = canvasSession, session.path == path { session.isWriting = true }
            #endif
        } catch { errorMessage = error.localizedDescription }
    }
}
