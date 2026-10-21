import SwiftUI
import ImageIO
import ShareInbox

/// The share sheet, after Obsidian's: a title, what was shared (its text editable), where
/// it goes (a new note or today's daily note) and, with several vaults, which vault.
struct ShareComposeView: View {
    @Bindable var model: ShareComposeModel
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Graphite")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!model.canSave) }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Preparing…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            ContentUnavailableView("Can't Share to Graphite", systemImage: "exclamationmark.triangle", description: Text(reason))
        case .ready:
            form
        }
    }

    private var form: some View {
        Form {
            if model.destination == .newNote {
                Section {
                    TextField("Untitled", text: $model.title)
                        .font(.headline)
                }
            }
            Section {
                TextEditor(text: $model.noteText)
                    .frame(minHeight: 120)
                    .font(.body)
                ForEach(model.attachments) { attachment in
                    SharedAttachmentRow(attachment: attachment)
                }
            } footer: {
                if let loadingProblem = model.loadingProblem { Text(loadingProblem) }
            }
            Section {
                Picker("Save To", selection: $model.destination) {
                    Text("New Note").tag(ShareDestinationChoice.newNote)
                    Text("Today's Daily Note").tag(ShareDestinationChoice.dailyNote)
                }
                if model.vaults.count > 1 {
                    Picker("Vault", selection: $model.chosenVaultIdentifier) {
                        ForEach(model.vaults) { vault in Text(vault.name).tag(Optional(vault.id)) }
                    }
                }
            } footer: {
                Text(destinationExplanation)
            }
        }
    }

    private var destinationExplanation: String {
        let vaultPhrase = model.chosenVaultName.map { name in "“\(name)”" } ?? "the vault open in Graphite"
        return "Graphite adds this to \(vaultPhrase) the next time you open it. Files go to the vault's attachment folder."
    }
}

/// A shared file: a small picture of an image, or the file's icon, and its name.
private struct SharedAttachmentRow: View {
    /// The longest side of a preview, in pixels: small enough for an extension's memory limit.
    private nonisolated static let thumbnailMaximumPixels = 160

    let attachment: SharedAttachmentPreview
    @State private var thumbnail: UIImage?

    var body: some View {
        Label {
            Text(attachment.fileName).lineLimit(1).truncationMode(.middle)
        } icon: {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 6))
            } else {
                Image(systemName: attachment.isImage ? "photo" : "doc").frame(width: 40, height: 40)
            }
        }
        .task(id: attachment.location) {
            guard attachment.isImage else { return }
            let location = attachment.location
            thumbnail = await Task.detached(priority: .userInitiated) { Self.thumbnail(of: location) }.value
        }
    }

    private nonisolated static func thumbnail(of location: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(location as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumPixels]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { image in UIImage(cgImage: image) }
    }
}
