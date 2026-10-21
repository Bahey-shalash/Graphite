import Foundation
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#endif

/// Pictures made from the New menu: a photo from the photo library or one just taken becomes
/// an ordinary image file in the folder shown, and opens in a tab. No note is made around it: the
/// picture is the file, and a note can embed it afterwards.
extension WorkspaceModel {
    /// Whether this device has a camera for Take Photo: an iPhone or iPad, not a Mac or the simulator.
    static var canTakePhotos: Bool {
        #if canImport(UIKit)
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        false
        #endif
    }

    /// What the New menu does with a picture: saves it as "Photo 2026-10-21 14.05" in `directory`
    /// (the vault's location for new files when nil) and opens it.
    func pictureSaver() -> @MainActor (Data, Date, VaultPath?) async -> Void {
        { [weak self] pictureData, takenAt, directory in
            await self?.createPicture(pictureData, takenAt: takenAt, in: directory)
        }
    }

    func createPicture(_ pictureData: Data, takenAt: Date, in directory: VaultPath?) async {
        guard let store else { return }
        guard let contents = PictureFileEncoding.fileContents(of: pictureData) else {
            errorMessage = "This is not a picture Graphite can save."
            return
        }
        do {
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let stem = PhotoFileName.stem(createdAt: takenAt, calendar: Calendar(identifier: .gregorian))
            let path = try await saveUnderFreeName(contents.data, in: directory, stem: stem, fileExtension: contents.fileExtension, store: store)
            refreshIndex(for: [path])
            await refreshDirectory()
            await open(path)
        } catch {
            errorMessage = "The picture could not be saved. Choose or take it again."
        }
    }
}
