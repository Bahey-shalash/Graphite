import Foundation
import GraphiteCore

/// Where each note and PDF was left, remembered per vault on the device as folds are, never
/// in the vault (`DocumentPlaceMemory`). A document opens where it was left: after Graphite
/// quits, or after iOS ends it in the background, as when its tab is shown again.
extension WorkspaceModel {
    static func placesKey(for vaultIdentifier: UUID) -> String {
        "GraphiteDocumentPlaces." + vaultIdentifier.uuidString
    }

    private var placeMemory: DocumentPlaceMemory {
        get {
            guard let currentVaultIdentifier, let storedPlaces = UserDefaults.standard.data(forKey: Self.placesKey(for: currentVaultIdentifier)) else {
                return DocumentPlaceMemory()
            }
            // Places another build wrote, or damaged ones, are only conveniences: lost, they
            // leave documents opening at their start.
            return (try? JSONDecoder().decode(DocumentPlaceMemory.self, from: storedPlaces)) ?? DocumentPlaceMemory()
        }
        set {
            guard let currentVaultIdentifier, let encodedPlaces = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(encodedPlaces, forKey: Self.placesKey(for: currentVaultIdentifier))
        }
    }

    /// Remembers where every open document is shown, as Graphite leaves the screen or the
    /// vault: iOS may end the app in the background without telling it.
    func rememberPlacesOfOpenDocuments() {
        rememberPlaces(of: Array(tabDocuments.values))
    }

    /// Remembers where documents are shown, as they leave their tabs.
    func rememberPlaces(of documents: [TabDocument]) {
        var memory = placeMemory
        let now = Date()
        var hasChanged = false
        for document in documents {
            guard let path = document.loadedPath, let place = Self.placeToRemember(of: document) else { continue }
            memory.remember(place, of: path, at: now)
            hasChanged = true
        }
        if hasChanged { placeMemory = memory }
    }

    private static func placeToRemember(of document: TabDocument) -> DocumentPlace? {
        if let markdownSession = document.markdownSession { return .note(markdownSession.placeToRemember()) }
        if let pdfSession = document.pdfSession { return .pdf(pdfSession.placeToRemember()) }
        return nil
    }

    /// Opens a note just loaded where it was left.
    func returnToRememberedPlace(of session: MarkdownSession) {
        guard case .note(let place) = placeMemory.place(of: session.path) else { return }
        session.returnTo(place)
    }

    /// Where a PDF just loaded was left, within its pages; nil when it opens at its start.
    func rememberedPlace(ofPDFAt path: VaultPath, pageCount: Int) -> PDFPagePlace? {
        guard case .pdf(let place) = placeMemory.place(of: path), place.pageIndex >= 0, place.pageIndex < pageCount else { return nil }
        return place
    }

    /// Keeps places with their documents when a file or folder is renamed or moved.
    func followMoveInPlaces(from oldPath: VaultPath, to newPath: VaultPath) {
        var memory = placeMemory
        memory.followMove(from: oldPath, to: newPath)
        placeMemory = memory
    }

    func forgetPlaces(inside removedPath: VaultPath) {
        var memory = placeMemory
        memory.forget(inside: removedPath)
        placeMemory = memory
    }
}
