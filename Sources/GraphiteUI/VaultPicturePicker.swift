import SwiftUI
import CoreGraphics
import GraphiteCore
import GraphiteApple

/// A picture chosen for a folder, before it is applied; each choice is its own sheet.
final class PickedFolderPicture: Identifiable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
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
