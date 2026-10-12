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
            guard let currentVaultIdentifier else { return DocumentPlaceMemory() }
            return documentPlaceStore.memory(forVault: currentVaultIdentifier)
        }
        set {
            guard let currentVaultIdentifier else { return }
            documentPlaceStore.update(newValue, forVault: currentVaultIdentifier)
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

/// Where documents were left, for each vault: read from the device's preferences once per
/// vault, then kept in memory and written back only when it changes. Every workspace of the
/// app shares one store (`shared`), so two windows on one vault do not overwrite each
/// other's places with copies read earlier.
@MainActor
final class DocumentPlaceStore {
    static let shared = DocumentPlaceStore(defaults: .standard)

    private let defaults: UserDefaults
    private var memories: [UUID: DocumentPlaceMemory] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func memory(forVault vaultIdentifier: UUID) -> DocumentPlaceMemory {
        if let memory = memories[vaultIdentifier] { return memory }
        // Places another build wrote, or damaged ones, are only conveniences: lost, they
        // leave documents opening at their start.
        let memory = defaults.data(forKey: WorkspaceModel.placesKey(for: vaultIdentifier))
            .flatMap { storedPlaces in try? JSONDecoder().decode(DocumentPlaceMemory.self, from: storedPlaces) }
            ?? DocumentPlaceMemory()
        memories[vaultIdentifier] = memory
        return memory
    }

    func update(_ memory: DocumentPlaceMemory, forVault vaultIdentifier: UUID) {
        guard memory != self.memory(forVault: vaultIdentifier) else { return }
        memories[vaultIdentifier] = memory
        guard let encodedPlaces = try? JSONEncoder().encode(memory) else { return }
        defaults.set(encodedPlaces, forKey: WorkspaceModel.placesKey(for: vaultIdentifier))
    }

    /// Forgets a vault's places, in memory and on the device, as when the vault is removed.
    func forgetVault(_ vaultIdentifier: UUID) {
        memories[vaultIdentifier] = nil
        defaults.removeObject(forKey: WorkspaceModel.placesKey(for: vaultIdentifier))
    }
}
