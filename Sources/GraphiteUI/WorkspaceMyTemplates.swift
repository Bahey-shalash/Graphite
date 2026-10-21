import Foundation
import GraphiteCore
import GraphiteApple

/// The person's own paper templates, and notebooks made of them.
extension WorkspaceModel {
    /// Where the open vault's templates are kept; nil with no vault open.
    var myTemplatesSource: MyTemplatesModel.Source? {
        guard let vaultIdentifier = currentVaultIdentifier, let store else { return nil }
        return MyTemplatesModel.Source(vaultIdentifier: vaultIdentifier, store: store)
    }

    /// Writes a new notebook of the sheet's options at `path`: `options.pageCount` copies of the
    /// chosen template's page, or pages of the chosen paper.
    func writeNotebook(_ options: NewNotebookOptions, at path: VaultPath, store: VaultStore, root: URL) async throws {
        let service = PDFFileService(writer: store.writer)
        let destination = try path.url(in: root)
        if let templateFileName = options.myTemplateFileName {
            let templateLocation = try VaultPath(MyPaperTemplateList.directory).appending(templateFileName).url(in: root)
            _ = try await service.create(templateAt: templateLocation, pageCount: options.pageCount, at: destination)
        } else {
            _ = try await service.create(paper: options.paper, pageCount: options.pageCount, at: destination)
        }
    }
}
