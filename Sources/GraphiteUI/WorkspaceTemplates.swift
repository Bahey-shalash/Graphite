import Foundation
import GraphiteCore

/// Obsidian's Templates and Daily notes core plugins, with the vault's own settings files.
extension WorkspaceModel {
    /// The Templates settings shown in Settings; Obsidian's defaults while the file cannot be read.
    var templateSettings: TemplateSettings { templateSettingsReading.settings ?? TemplateSettings() }
    /// The Daily notes settings shown in Settings; Obsidian's defaults while the file cannot be read.
    var dailyNoteSettings: DailyNoteSettings { dailyNoteSettingsReading.settings ?? DailyNoteSettings() }

    /// What the person is told when the Templates or Daily notes settings file of the open
    /// vault cannot be read, or nil when both were read.
    var unreadableSettingsMessage: String? {
        let reasons = [templateSettingsReading.unreadableReason, dailyNoteSettingsReading.unreadableReason].compactMap { reason in reason }
        guard !reasons.isEmpty else { return nil }
        return "Graphite could not read the Templates or Daily notes settings in this vault, so templates and daily notes "
            + "are not used until it can. " + reasons.joined(separator: " ")
    }

    /// What `read` gives for one settings file: its settings, or why it could not be read.
    static func settingsReading<Settings>(_ read: () async throws -> Settings) async -> VaultSettingsReading<Settings> {
        do {
            return .read(try await read())
        } catch {
            return .unreadable(reason: error.localizedDescription)
        }
    }

    /// Notes in the Templates folder, by name; none while the Templates settings cannot be read.
    func templateFiles() -> [VaultPath] {
        guard let root = folderAccess?.root, let folder = templateSettingsReading.settings?.folderPath,
              let location = try? folder.url(in: root) else { return [] }
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
        guard let settings = templateSettingsReading.settings else {
            errorMessage = unreadableSettingsMessage
            return
        }
        do {
            let snapshot = try await store.read(template, maximumBytes: MarkdownSession.maximumEditableBytes)
            guard let templateText = String(data: snapshot.data, encoding: .utf8) else { throw GraphiteError.invalidFile("“\(template.name)” is not UTF-8 text.") }
            let rendered = TemplateRenderer.render(templateText, title: session.path.stem, date: .now, dateFormat: settings.dateFormat, timeFormat: settings.timeFormat)
            let declaredTypes = await store.propertyTypes()
            session.apply(TemplateInsertion.edit(inserting: rendered, into: session.text, at: session.selection, declaredTypes: declaredTypes))
        } catch { errorMessage = Self.templatesFailureMessage(error) }
    }

    /// Opens the daily note of `date`, creating it from the daily note template first when
    /// it does not exist yet. Refused while the Daily notes settings cannot be read.
    func openDailyNote(for date: Date = .now, placement: TabPlacement = .currentTab) async {
        guard let store else { return }
        guard let settings = dailyNoteSettingsReading.settings else {
            errorMessage = unreadableSettingsMessage
            return
        }
        do {
            let path = try settings.notePath(for: date)
            let isCreated = try await DailyNoteCreation.createIfMissing(path, for: date, settings: settings, timeFormat: templateSettings.timeFormat,
                                                                         maximumTemplateBytes: MarkdownSession.maximumEditableBytes, timeZone: .current, store: store)
            if isCreated {
                refreshIndex(for: [path])
                await refreshDirectory()
            }
            await open(path, placement: placement)
        } catch { errorMessage = Self.templatesFailureMessage(error) }
    }

    /// What the person is told when a template or a daily note cannot be used.
    nonisolated static func templatesFailureMessage(_ error: any Error) -> String {
        guard case DailyNoteCreation.Failure.templateMissing(let templatePath) = error else { return error.localizedDescription }
        return "The daily note template “\(templatePath.rawValue)” is not in this vault. Choose another in Settings › Daily Notes."
    }

    /// The daily note before or after the one open, or before or after today when the open
    /// file is not a daily note, skipping days without a note, as Obsidian does.
    func openAdjacentDailyNote(forward: Bool) async {
        guard let index else { return }
        guard let settings = dailyNoteSettingsReading.settings else {
            errorMessage = unreadableSettingsMessage
            return
        }
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
        } catch { errorMessage = Self.templatesFailureMessage(error) }
    }

    func updateTemplateSettings(_ settings: TemplateSettings) async {
        guard let store, settings != templateSettings else { return }
        do {
            try await store.saveTemplateSettings(settings)
            templateSettingsReading = .read(settings)
        } catch { errorMessage = Self.templatesFailureMessage(error) }
    }

    func updateDailyNoteSettings(_ settings: DailyNoteSettings) async {
        guard let store, settings != dailyNoteSettings else { return }
        do {
            try await store.saveDailyNoteSettings(settings)
            dailyNoteSettingsReading = .read(settings)
        } catch { errorMessage = Self.templatesFailureMessage(error) }
    }
}
