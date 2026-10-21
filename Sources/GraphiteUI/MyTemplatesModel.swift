import Foundation
import CoreGraphics
import Observation
import GraphiteCore
import GraphiteApple

/// What went wrong with the person's own paper templates, for the view to word.
enum MyTemplatesFailure: Error, Equatable {
    /// The templates folder could not be listed.
    case notListed
    /// The arrangement file was not Graphite's format; it was kept under this name beside the templates.
    case arrangementSetAside(keptCopyName: String)
    /// The arrangement file was not Graphite's format and could not be moved aside either.
    case arrangementUnreadable
    case couldNotKeep(templateName: String)
    case couldNotChange(templateName: String)
}

/// The person's own paper templates of the open vault: PDFs kept in `.obsidian/graphite-templates`,
/// listed in the order the person arranged them, with a picture of each page drawn for the tiles on
/// screen. A new vault gets a new list.
@MainActor @Observable
final class MyTemplatesModel {
    /// Where the templates are read from and kept; replaced when the vault changes.
    struct Source {
        let vaultIdentifier: UUID
        let store: VaultStore
    }

    /// Pictures kept at once; the ones drawn first go first. A template's picture is about a megabyte.
    static let maximumPreviewCount = 40
    /// A picture's longer side in pixels: enough for the large first page of the sheet.
    nonisolated static let previewPixels = 420

    private(set) var templates: [MyPaperTemplateList.Template] = []
    /// Whether the folder was listed at least once for this vault.
    private(set) var isListed = false
    private(set) var previews: [String: MyPaperTemplatePreview] = [:]
    private(set) var failure: MyTemplatesFailure?

    @ObservationIgnored private var source: Source?
    /// Templates whose picture waits to be drawn, oldest first, and the order the drawn ones were made in.
    @ObservationIgnored private var waitingPreviews: [String] = []
    @ObservationIgnored private var drawnPreviewOrder: [String] = []
    @ObservationIgnored private var previewWorker: Task<Void, Never>?
    /// The last change of the templates; the next one waits for it, so changes happen in the order asked.
    @ObservationIgnored private var lastChange: Task<Void, Never>?

    /// The templates the New Notebook sheet offers: the hidden ones are left out.
    var shownTemplates: [MyPaperTemplateList.Template] { templates.filter { template in !template.isHidden } }

    func use(_ newSource: Source?) {
        guard newSource?.vaultIdentifier != source?.vaultIdentifier else { return }
        source = newSource
        forgetPreviews()
        templates = []
        isListed = false
        failure = nil
        guard newSource != nil else { return }
        startChange { model in await model.list() }
    }

    func dismissFailure() { failure = nil }

    /// Gives the pictures back, as when the sheet closes.
    func forgetPreviews() {
        previewWorker?.cancel()
        previewWorker = nil
        waitingPreviews = []
        drawnPreviewOrder = []
        previews = [:]
    }

    // MARK: Listing

    /// Lists the folder again, for a sheet that opens (templates may have been put there by hand or by a synced device).
    func refresh() {
        startChange { model in await model.list() }
    }

    private func startChange(_ change: @escaping @MainActor (MyTemplatesModel) async -> Void) {
        let previousChange = lastChange
        lastChange = Task { [weak self] in
            await previousChange?.value
            guard let self else { return }
            await change(self)
        }
    }

    private func list() async {
        guard let source else { return }
        do {
            templates = try await source.store.myPaperTemplates()
            isListed = true
        } catch is MyPaperTemplateListError {
            do {
                let keptCopy = try await source.store.moveMyPaperTemplateListAside()
                failure = .arrangementSetAside(keptCopyName: keptCopy.name)
                templates = (try? await source.store.myPaperTemplates()) ?? [] // The arrangement is gone; a folder that still cannot be listed shows none.
                isListed = true
            } catch {
                failure = .arrangementUnreadable
            }
        } catch {
            failure = .notListed
        }
    }

    // MARK: Pictures

    /// Draws a template's picture when a tile for it comes on screen; the picture stays until the sheet closes or the budget is used.
    func requestPreview(of fileName: String) {
        guard previews[fileName] == nil, !waitingPreviews.contains(fileName) else { return }
        waitingPreviews.append(fileName)
        guard previewWorker == nil else { return }
        previewWorker = Task { [weak self] in await self?.drawWaitingPreviews() }
    }

    private func drawWaitingPreviews() async {
        while !waitingPreviews.isEmpty, let source {
            let fileName = waitingPreviews.removeFirst()
            let templatePath = try? VaultPath(MyPaperTemplateList.directory).appending(fileName) // A name no path can hold has no picture.
            let location = try? templatePath?.url(in: source.store.root) // A path outside the vault has no picture.
            guard let location else { continue }
            let preview = await Task.detached(priority: .userInitiated) {
                MyPaperTemplateNotebook.preview(ofTemplateAt: location, longerSidePixels: Self.previewPixels)
            }.value
            guard !Task.isCancelled else { return }
            if let preview { keep(preview, of: fileName) }
        }
        previewWorker = nil
    }

    private func keep(_ preview: MyPaperTemplatePreview, of fileName: String) {
        previews[fileName] = preview
        drawnPreviewOrder.append(fileName)
        while drawnPreviewOrder.count > Self.maximumPreviewCount { previews[drawnPreviewOrder.removeFirst()] = nil }
    }

    // MARK: Changing

    /// Keeps the chosen page or picture as a template named `name`, shown last.
    func add(_ draft: MyTemplateDraft, named name: String) {
        guard let source else { return }
        startChange { model in
            do {
                guard let templateData = await draft.templateData else { throw MyTemplatesFailure.couldNotKeep(templateName: name) }
                let added = try await source.store.addMyPaperTemplate(templateData, named: name)
                await model.list()
                model.requestPreview(of: added.fileName)
            } catch {
                model.failure = .couldNotKeep(templateName: name)
            }
        }
    }

    func rename(_ template: MyPaperTemplateList.Template, to name: String) {
        guard let source, name != template.name else { return }
        startChange { model in
            do {
                let renamed = try await source.store.renameMyPaperTemplate(template.fileName, to: name)
                model.moveKeptPreview(from: template.fileName, to: renamed.fileName)
                await model.list()
            } catch {
                model.failure = .couldNotChange(templateName: template.name)
            }
        }
    }

    func setHidden(_ isHidden: Bool, template: MyPaperTemplateList.Template) {
        guard let source else { return }
        startChange { model in
            do {
                try await source.store.updateMyPaperTemplateList { @Sendable list in list.setHidden(isHidden, fileName: template.fileName) }
                await model.list()
            } catch {
                model.failure = .couldNotChange(templateName: template.name)
            }
        }
    }

    /// Deletes the template's file for good; the PDF or picture it was made from is untouched.
    func delete(_ template: MyPaperTemplateList.Template) {
        guard let source else { return }
        startChange { model in
            do {
                try await source.store.deleteMyPaperTemplate(template.fileName)
                model.forgetPreview(of: template.fileName)
                await model.list()
            } catch {
                model.failure = .couldNotChange(templateName: template.name)
            }
        }
    }

    /// Moves templates as a list's drag does, and keeps the new order.
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let source else { return }
        let arranged = MyTemplateArrangement.moved(templates.map(\.fileName), fromOffsets: offsets, toOffset: destination)
        // Shown at once; the file confirms it.
        templates = MyPaperTemplateList.Template.arranged(templates, as: arranged)
        startChange { model in
            do {
                try await source.store.updateMyPaperTemplateList { @Sendable list in list.arrange(arranged) }
                await model.list()
            } catch {
                model.failure = .couldNotChange(templateName: "")
                await model.list()
            }
        }
    }

    private func moveKeptPreview(from oldFileName: String, to newFileName: String) {
        guard let preview = previews.removeValue(forKey: oldFileName) else { return }
        previews[newFileName] = preview
        drawnPreviewOrder = drawnPreviewOrder.map { fileName in fileName == oldFileName ? newFileName : fileName }
    }

    private func forgetPreview(of fileName: String) {
        previews[fileName] = nil
        drawnPreviewOrder.removeAll { drawnName in drawnName == fileName }
    }
}
