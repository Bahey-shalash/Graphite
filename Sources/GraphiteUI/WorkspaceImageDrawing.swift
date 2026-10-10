#if canImport(UIKit)
import Foundation
import GraphiteCore
import GraphiteApple

/// Drawing on an image, from a note's embed or from the image itself.
///
/// The image file is never changed. The drawing is saved as a new ordinary drawing file in
/// the format new drawings take, the picture with the ink over it, named after the image
/// ("Diagram annotated.png"); its editing metadata keeps the picture, so the ink can be
/// edited again later. A note's embeds of the image then show the new file, written in the
/// style they were written in (a bare name, a path, a Markdown link, with any size or
/// alias), as one edit that can be undone.
extension WorkspaceModel {
    /// Bound on an image read to be drawn on; the picture kept is far smaller.
    static let maximumImageBytesToDrawOn = 64 * 1_048_576

    /// Opens the drawing editor over the image. A Graphite drawing opens as itself, with its
    /// strokes editable.
    func beginDrawingOnImage(at imagePath: VaultPath, fromNote notePath: VaultPath?) async {
        guard let store, let root = folderAccess?.root else { return }
        do {
            let location = try imagePath.url(in: root)
            let isDrawing = await Task.detached(priority: .userInitiated) { DrawingMetadataReader.hasEditableStrokes(at: location) }.value
            if isDrawing {
                await beginEditingDrawing(at: imagePath)
                return
            }
            let snapshot = try await store.read(imagePath, maximumBytes: Self.maximumImageBytesToDrawOn)
            let canvasWidth = DrawingEditorRequest.newDrawingCanvasWidth
            let picture = try await Task.detached(priority: .userInitiated) {
                try DrawingPictures.picture(from: snapshot.data, canvasWidth: canvasWidth)
            }.value
            drawingEditorRequest = DrawingEditorRequest(
                target: .drawingOnImage(imagePath: imagePath, notePath: notePath), title: imagePath.name, initialStrokeData: Data(),
                canvasWidth: canvasWidth, background: .white, format: preferences.drawingFormat, backgroundImage: picture)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// What an Apple Pencil double-tap starts: the drawing under the cursor opens for
    /// editing, an image under it is drawn on, and anywhere else a new drawing starts.
    /// While a drawing is open the double-tap is its tools', and never replaces it.
    func beginDrawingAtCursor(in session: MarkdownSession) async {
        guard drawingEditorRequest == nil else { return }
        guard let root = folderAccess?.root,
              let embed = EmbedLocator.embed(at: session.selection.location, in: session.text as NSString),
              let path = await resolveLink(embed.target, from: session.path, isWiki: embed.isWiki),
              let location = try? path.url(in: root) else {
            beginNewDrawing(in: session)
            return
        }
        let isEditableDrawing = DrawingFormat(fileExtension: path.fileExtension) == nil ? false
            : await Task.detached(priority: .userInitiated) { DrawingMetadataReader.hasEditableStrokes(at: location) }.value
        if isEditableDrawing {
            await beginEditingDrawing(at: path)
        } else if DrawableImages.canDrawOn(path) {
            await beginDrawingOnImage(at: path, fromNote: session.path)
        } else {
            beginNewDrawing(in: session)
        }
    }

    /// Saves the new drawing where the note's attachments go, or beside a standalone image,
    /// then points the note's embeds at it, or opens it when there is no note.
    func saveDrawingOnImage(_ content: DrawingContent, format: DrawingFormat, imagePath: VaultPath, notePath: VaultPath?,
                            service: DrawingFileService) async throws {
        guard let store, let root = folderAccess?.root else { throw GraphiteError.unavailable("Open a vault first.") }
        let directory: VaultPath
        if let notePath {
            let settings = try await store.settings()
            directory = try resolver.directory(for: settings.attachmentLocation, note: notePath)
        } else {
            directory = imagePath.parent
        }
        try await store.createDirectory(directory)
        let stem = (imagePath.name as NSString).deletingPathExtension + " annotated"
        let path = try await store.uniquePath(directory: directory, stem: stem, extension: format.fileExtension)
        _ = try await service.save(content, format: format, to: path.url(in: root), expecting: .absent)
        if let notePath {
            if let session = openMarkdownSession(at: notePath), !session.hasExternalConflict {
                let replacedCount = await replaceEmbeds(of: imagePath, with: path, in: session)
                if replacedCount == 0 {
                    errorMessage = "The drawing was saved as “\(path.rawValue)”, but the note no longer embeds “\(imagePath.name)”, so nothing in it changed."
                }
            } else {
                errorMessage = "The drawing was saved as “\(path.rawValue)”, but its note is not open or was changed in another app, so the note still shows the original image."
            }
        }
        refreshIndex(for: [path])
        if notePath == nil { await open(path) }
    }

    /// Rewrites every embed of `imagePath` in the note to show `newPath`, keeping how each
    /// was written, as one undoable edit. Returns how many embeds changed.
    @discardableResult
    func replaceEmbeds(of imagePath: VaultPath, with newPath: VaultPath, in session: MarkdownSession) async -> Int {
        let text = session.text
        guard let links = try? NoteLinkScanner.links(in: text) else { return 0 }
        let isNewNameUnique = await isNameUnique(newPath, from: session.path)
        var replacements: [(range: NSRange, text: String)] = []
        let source = text as NSString
        for link in links where link.isEmbed && link.length > 0 {
            guard await resolveLink(link.target, from: session.path, isWiki: link.isWiki) == imagePath else { continue }
            let pathPart = LinkRewriter.pathPart(linkingTo: newPath, from: session.path, writtenPath: LinkRewriter.writtenPath(of: link),
                                                 isWiki: link.isWiki, previousTarget: imagePath, previousSource: session.path,
                                                 isNameUnique: isNewNameUnique)
            guard NSMaxRange(link.range) <= source.length,
                  let replacement = LinkRewriter.replacingPath(inLinkText: source.substring(with: link.range), isWiki: link.isWiki, newPathPart: pathPart) else { continue }
            replacements.append((link.range, replacement))
        }
        // The text may have changed while links were resolved; the edit is made only on the text read.
        guard !replacements.isEmpty, session.text == text,
              let firstRange = replacements.first?.range, let lastRange = replacements.last?.range else { return 0 }
        let spannedRange = NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location)
        let spannedText = source.substring(with: spannedRange)
        let shiftedReplacements = replacements.map { replacement in
            (range: NSRange(location: replacement.range.location - spannedRange.location, length: replacement.range.length), text: replacement.text)
        }
        let newSpannedText = LinkRewriter.applying(shiftedReplacements, to: spannedText)
        session.apply(MarkdownTextEdit(range: spannedRange, replacement: newSpannedText,
                                       selectionAfter: NSRange(location: spannedRange.location + (newSpannedText as NSString).length, length: 0)))
        return replacements.count
    }
}
#endif
