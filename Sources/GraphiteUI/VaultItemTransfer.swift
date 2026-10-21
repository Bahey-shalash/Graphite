import SwiftUI
import UniformTypeIdentifiers

/// A file or folder dragged in the sidebar or the library.
struct VaultItemTransfer: Codable, Transferable {
    let path: String
    /// Where the file is on disk, so a drag out of Graphite gives Files, the Finder or another app
    /// the file itself. Not encoded: a drop inside Graphite needs the vault path only.
    var fileLocation: URL?

    init(path: String, fileLocation: URL? = nil) {
        self.path = path
        self.fileLocation = fileLocation
    }

    private enum CodingKeys: String, CodingKey { case path }

    static var transferRepresentation: some TransferRepresentation {
        // The vault item first: a drop in Graphite moves it. Other apps take the file.
        CodableRepresentation(contentType: .graphiteVaultItem)
        FileRepresentation(exportedContentType: .item) { transfer in
            guard let fileLocation = transfer.fileLocation else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(fileLocation, allowAccessingOriginalFile: true)
        }
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteVaultItem = UTType(exportedAs: "com.graphite.study.vault-item")
}
