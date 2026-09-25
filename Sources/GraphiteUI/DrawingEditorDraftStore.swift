import Foundation
import GraphiteCore
import GraphiteApple

/// Where the strokes of a drawing still open in the editor belong, kept when the app
/// leaves the foreground. iPadOS may end a suspended app without warning, and until they
/// are saved the strokes exist only in the canvas.
struct DrawingEditorDraft: Codable, Equatable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        case newDrawing(notePath: VaultPath, insertionLocation: Int, insertionLength: Int)
        case existingDrawing(path: VaultPath, revision: FileRevision)
    }

    let requestIdentifier: UUID
    let vaultIdentifier: UUID
    let target: Target
    let title: String
    let background: DrawingBackground
    /// The format the drawing is saved in; the draft itself is always an SVG drawing.
    let format: DrawingFormat

    init(request: DrawingEditorRequest, vaultIdentifier: UUID) {
        requestIdentifier = request.id
        self.vaultIdentifier = vaultIdentifier
        switch request.target {
        case .newDrawing(let notePath, let insertionRange):
            target = .newDrawing(notePath: notePath, insertionLocation: insertionRange.location, insertionLength: insertionRange.length)
        case .existingDrawing(let path, _, let revision):
            target = .existingDrawing(path: path, revision: revision)
        }
        title = request.title
        background = request.background
        format = request.format
    }
}

/// A draft read back with the strokes from its drawing file.
struct RecoveredDrawingDraft: Sendable {
    let draft: DrawingEditorDraft
    let payload: DrawingPayload

    /// The editor request that reopens these strokes in the vault at `root`. It keeps the
    /// draft's identifier, so saving or closing the editor removes the draft.
    func editorRequest(inVaultAt root: URL) throws -> DrawingEditorRequest {
        let requestTarget: DrawingEditorRequest.Target
        switch draft.target {
        case .newDrawing(let notePath, let insertionLocation, let insertionLength):
            requestTarget = .newDrawing(notePath: notePath, insertionRange: NSRange(location: max(insertionLocation, 0), length: max(insertionLength, 0)))
        case .existingDrawing(let path, let revision):
            requestTarget = .existingDrawing(path: path, location: try path.url(in: root), revision: revision)
        }
        return DrawingEditorRequest(id: draft.requestIdentifier, target: requestTarget, title: draft.title, initialStrokeData: payload.strokes,
                                    canvasWidth: payload.width, background: draft.background, format: draft.format, isRecoveredDraft: true)
    }
}

/// Keeps drawing drafts in the app's own Application Support folder, never inside a
/// vault. Each draft is an ordinary SVG drawing, with its Pencil strokes in the standard
/// metadata element, next to a small description of where it belongs. They are the
/// user's unsaved work, not a cache.
@MainActor
final class DrawingEditorDraftStore {
    static let shared = DrawingEditorDraftStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Drawing Drafts", isDirectory: true))

    let directory: URL
    /// Writes and removals run one after another in the order they were asked for, so a
    /// removal after closing the editor cannot be overtaken by an earlier write.
    private var latestOperation: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
    }

    /// Writes the draft's drawing file, encoded off the main actor by `drawingFile`, then
    /// its description. A draft that fails to encode is skipped: the editor still has the
    /// strokes, and nothing in the vault changes.
    func preserve(_ draft: DrawingEditorDraft, drawingFile: @escaping @Sendable () async throws -> Data) {
        let directory = directory
        let drawingLocation = Self.drawingLocation(for: draft.requestIdentifier, in: directory)
        let descriptionLocation = Self.descriptionLocation(for: draft.requestIdentifier, in: directory)
        enqueue {
            do {
                let fileData = try await drawingFile()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileData.write(to: drawingLocation, options: .atomic)
                try JSONEncoder().encode(draft).write(to: descriptionLocation, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: descriptionLocation)
            }
        }
    }

    func removeDraft(withIdentifier requestIdentifier: UUID) {
        let drawingLocation = Self.drawingLocation(for: requestIdentifier, in: directory)
        let descriptionLocation = Self.descriptionLocation(for: requestIdentifier, in: directory)
        enqueue {
            try? FileManager.default.removeItem(at: descriptionLocation)
            try? FileManager.default.removeItem(at: drawingLocation)
        }
    }

    /// The drafts left for one vault, read after every write and removal asked for so far.
    /// A draft whose drawing no longer carries its strokes is left on disk, untouched.
    func drafts(forVault vaultIdentifier: UUID) async -> [RecoveredDrawingDraft] {
        await latestOperation?.value
        let directory = directory
        return await Task.detached(priority: .userInitiated) {
            let locations = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return locations.filter { location in location.pathExtension == "json" }.compactMap { descriptionLocation -> RecoveredDrawingDraft? in
                guard let descriptionData = try? AtomicFileWriter().read(descriptionLocation, maximumBytes: 64 * 1024).data,
                      let draft = try? JSONDecoder().decode(DrawingEditorDraft.self, from: descriptionData),
                      draft.vaultIdentifier == vaultIdentifier,
                      let fileData = try? AtomicFileWriter().read(Self.drawingLocation(for: draft.requestIdentifier, in: directory),
                                                                  maximumBytes: DrawingMetadataReader.maximumFileBytes(for: .svg)).data,
                      let payload = try? DrawingMetadataReader.readMetadata(fileData, format: .svg).payload else { return nil }
                return RecoveredDrawingDraft(draft: draft, payload: payload)
            }
        }.value
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previousOperation = latestOperation
        latestOperation = Task {
            await previousOperation?.value
            await operation()
        }
    }

    private nonisolated static func drawingLocation(for requestIdentifier: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(requestIdentifier.uuidString).appendingPathExtension("svg")
    }

    private nonisolated static func descriptionLocation(for requestIdentifier: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(requestIdentifier.uuidString).appendingPathExtension("json")
    }
}
