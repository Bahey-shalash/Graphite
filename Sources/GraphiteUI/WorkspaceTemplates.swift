import Foundation
import GraphiteCore

/// Obsidian's Templates and Daily notes core plugins, with the vault's own settings files.
extension WorkspaceModel {
    /// Notes in the Templates folder, by name.
    func templateFiles() -> [VaultPath] {
        guard let root = folderAccess?.root, let folder = templateSettings.folderPath, let location = try? folder.url(in: root) else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: location, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var templates: [VaultPath] = []
        while let fileLocation = enumerator.nextObject() as? URL, templates.count < Self.maximumTemplateCount {
            guard let values = try? fileLocation.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true, values.isDirectory != true,
                  fileLocation.pathExtension.lowercased() == "md", let path = vaultPath(for: fileLocation) else { continue }
            templates.append(path)
        }
        return templates.sorted { leftPath, rightPath in leftPath.rawValue.localizedStandardCompare(rightPath.rawValue) == .orderedAscending }
    }

    private static var maximumTemplateCount: Int { 500 }

    /// Inserts a template at the cursor of `session`'s note, as Obsidian's "Insert template":
    /// `{{title}}`, `{{date}}` and `{{time}}` are filled in, and the template's properties
    /// are added to the note's.
    func insertTemplate(_ template: VaultPath, into session: MarkdownSession) async {
        guard let store else { return }
        do {
            let snapshot = try await store.read(template, maximumBytes: MarkdownSession.maximumEditableBytes)
            guard let templateText = String(data: snapshot.data, encoding: .utf8) else { throw GraphiteError.invalidFile("“\(template.name)” is not UTF-8 text.") }
            let settings = templateSettings
            let rendered = TemplateRenderer.render(templateText, title: session.path.stem, date: .now, dateFormat: settings.dateFormat, timeFormat: settings.timeFormat)
            let declaredTypes = await store.propertyTypes()
            session.apply(TemplateInsertion.edit(inserting: rendered, into: session.text, at: session.selection, declaredTypes: declaredTypes))
        } catch { errorMessage = error.localizedDescription }
    }

    /// Opens the daily note of `date`, creating it from the daily note template first when
    /// it does not exist yet.
    func openDailyNote(for date: Date = .now, placement: TabPlacement = .currentTab) async {
        guard let store else { return }
        let settings = dailyNoteSettings
        do {
            let path = try settings.notePath(for: date)
            if try await !store.fileExists(path) {
                var content = ""
                if let templatePath = settings.templatePath {
                    guard try await store.fileExists(templatePath) else {
                        throw GraphiteError.unavailable("The daily note template “\(templatePath.rawValue)” is not in this vault. Choose another in Settings › Daily notes.")
                    }
                    let snapshot = try await store.read(templatePath, maximumBytes: MarkdownSession.maximumEditableBytes)
                    let templateText = String(data: snapshot.data, encoding: .utf8) ?? ""
                    // The note's own date, not today's, so earlier and later notes are right.
                    content = TemplateRenderer.render(templateText, title: path.stem, date: date,
                                                      dateFormat: settings.format, timeFormat: templateSettings.timeFormat)
                }
                try await store.createDirectory(path.parent)
                _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
                refreshIndex(for: [path])
                await refreshDirectory()
            }
            await open(path, placement: placement)
        } catch { errorMessage = error.localizedDescription }
    }

    /// The daily note before or after the one open, or before or after today when the open
    /// file is not a daily note, skipping days without a note, as Obsidian does.
    func openAdjacentDailyNote(forward: Bool) async {
        guard let index else { return }
        let settings = dailyNoteSettings
        let calendar = Calendar(identifier: .gregorian)
        let reference = selection.flatMap { path in settings.date(ofNoteAt: path) } ?? calendar.startOfDay(for: .now)
        let folder = settings.folder.isEmpty ? VaultPath.root : ((try? VaultPath(settings.folder)) ?? .root)
        do {
            let candidates = try await index.paths(inside: folder)
            let dated = candidates.compactMap { path in settings.date(ofNoteAt: path).map { date in (path, date) } }
            let adjacent = forward
                ? dated.filter { _, date in date > reference }.min { first, second in first.1 < second.1 }
                : dated.filter { _, date in date < reference }.max { first, second in first.1 < second.1 }
            guard let (path, _) = adjacent else {
                errorMessage = forward ? "There is no later daily note." : "There is no earlier daily note."
                return
            }
            await open(path)
        } catch { errorMessage = error.localizedDescription }
    }

    func updateTemplateSettings(_ settings: TemplateSettings) async {
        guard let store, settings != templateSettings else { return }
        do {
            try await store.saveTemplateSettings(settings)
            templateSettings = settings
        } catch { errorMessage = error.localizedDescription }
    }

    func updateDailyNoteSettings(_ settings: DailyNoteSettings) async {
        guard let store, settings != dailyNoteSettings else { return }
        do {
            try await store.saveDailyNoteSettings(settings)
            dailyNoteSettings = settings
        } catch { errorMessage = error.localizedDescription }
    }
}
