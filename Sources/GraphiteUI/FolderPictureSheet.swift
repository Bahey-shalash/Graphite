import SwiftUI
import CoreGraphics
import GraphiteCore
import GraphiteApple

/// A picture chosen for a folder, before it is applied; each choice is its own sheet.
final class PickedFolderPicture: Identifiable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}

/// Makes a folder's picture: the picture placed on the folder, as Finder draws app folders,
/// or as the whole icon, shown large as the folder will look before it is applied.
struct FolderPictureSheet: View {
    let picture: CGImage
    let folderName: String
    let folderColor: FolderColor?
    /// Applies the framed picture, a square of `FolderIconRenderer.outputPixels`.
    let apply: (CGImage, FolderPictureLayout) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var layout = FolderPictureLayout.onFolder
    @State private var framedPicture: CGImage?

    private static let previewSymbolPoints: CGFloat = 150

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Style", selection: $layout) {
                    Text("On Folder").tag(FolderPictureLayout.onFolder)
                    Text("Whole Icon").tag(FolderPictureLayout.wholeIcon)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                LibraryFolderArtwork(style: previewStyle, picture: framedPicture, symbolPointSize: Self.previewSymbolPoints)
                    .frame(height: Self.previewSymbolPoints * 1.15)
                Text(folderName).font(.headline)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Folder Picture")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let framedPicture else { return }
                        apply(framedPicture, layout)
                        dismiss()
                    }
                    .disabled(framedPicture == nil)
                }
            }
            .task(id: layout) { await frame() }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    /// The look being made, for the preview; its picture path is never read, the framed
    /// picture is handed to the drawing directly.
    private var previewStyle: FolderStyle {
        FolderStyle(color: folderColor, mark: .picture(FolderPicture(path: .root, layout: layout)))
    }

    /// Frames the picture off the main actor: filling the square, as the tile shows it.
    private func frame() async {
        let picture = picture
        let layout = layout
        framedPicture = await Task.detached(priority: .userInitiated) {
            FolderIconRenderer.framedPicture(picture, framing: .filling, layout: layout, background: .none)
        }.value
    }
}

/// Chooses a picture of the vault by name; recent pictures are listed until something is typed.
struct VaultPicturePicker: View {
    let findPictures: (String) async -> [VaultPath]
    let choose: (VaultPath) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paths: [VaultPath] = []

    var body: some View {
        NavigationStack {
            List(paths) { path in
                Button {
                    choose(path)
                    dismiss()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path.name)
                            if !path.parent.rawValue.isEmpty { Text(path.parent.rawValue).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: "photo") }
                }
            }
            .overlay {
                if paths.isEmpty {
                    ContentUnavailableView("Find a Picture", systemImage: "photo", description: Text("Type part of its name."))
                }
            }
            .searchable(text: $query, prompt: "Find a picture in the vault")
            .navigationTitle("Picture from Vault")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) { paths = await findPictures(query.trimmingCharacters(in: .whitespaces)) }
        }
        .frame(minWidth: 340, minHeight: 450)
    }
}
