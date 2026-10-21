import SwiftUI
import PhotosUI
import GraphiteCore
import GraphiteApple

/// The photo library's picker and the camera that the New menu's Image from Photos and Take Photo
/// open. A picture chosen or taken goes to `save`, with the moment it was made, which names the file.
struct NewItemPicturePresentation: ViewModifier {
    @Binding var showsPhotoPicker: Bool
    @Binding var showsCamera: Bool
    /// The folder the picture is saved in; nil for the vault's location for new files.
    let directory: VaultPath?
    let save: @MainActor (Data, Date, VaultPath?) async -> Void
    @State private var pickedPhoto: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, photo in
                guard let photo else { return }
                pickedPhoto = nil
                Task { await saveChosen(photo) }
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showsCamera) {
                CameraCapture { image in Task { await saveTaken(image) } }
                    .ignoresSafeArea()
            }
            #endif
    }

    /// The moment the photo was chosen names the file.
    private func saveChosen(_ photo: PhotosPickerItem) async {
        let chosenAt = WallClock.currentDate()
        let pictureData = try? await photo.loadTransferable(type: Data.self) // A photo that cannot be read saves nothing: choose it again.
        guard let pictureData else { return }
        await save(pictureData, chosenAt, directory)
    }

    #if canImport(UIKit)
    private func saveTaken(_ image: UIImage) async {
        let takenAt = WallClock.currentDate()
        guard let cgImage = image.cgImage, let pictureData = PictureFileEncoding.jpegData(of: cgImage) else { return }
        await save(pictureData, takenAt, directory)
    }
    #endif
}
