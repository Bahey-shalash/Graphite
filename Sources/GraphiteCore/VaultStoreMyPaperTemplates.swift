import Foundation

/// The person's own paper templates, kept as ordinary one-page PDFs in the vault's
/// `.obsidian/graphite-templates` folder (see `MyPaperTemplateList`).
extension VaultStore {
    /// The arrangement saved beside the templates; none when the file is missing.
    public func myPaperTemplateList() throws -> MyPaperTemplateList {
        try MyPaperTemplateList(configurationData: configurationData(at: MyPaperTemplateList.configurationPath))
    }

    /// The templates in the order they are shown, hidden ones included, with the arrangement they were listed by.
    public func myPaperTemplates() throws -> [MyPaperTemplateList.Template] {
        let list = try myPaperTemplateList()
        let directory = try VaultPath(MyPaperTemplateList.directory)
        guard try fileExists(directory) else { return [] }
        let fileNames = try children(of: directory)
            .filter { entry in !entry.isDirectory && (entry.path.name as NSString).pathExtension.lowercased() == MyPaperTemplateList.fileExtension }
            .map(\.path.name)
        return list.templates(listing: fileNames)
    }

    /// Changes the arrangement, keeping what other builds wrote. A vault gets the file only once
    /// there is something to keep; an unchanged arrangement leaves the file as it was.
    @discardableResult
    public func updateMyPaperTemplateList(_ change: (inout MyPaperTemplateList) -> Void) throws -> MyPaperTemplateList {
        var updated = MyPaperTemplateList()
        if try configurationData(at: MyPaperTemplateList.configurationPath) == nil {
            change(&updated)
            if updated == MyPaperTemplateList() { return updated }
            updated = MyPaperTemplateList()
        }
        try saveConfiguration(at: MyPaperTemplateList.configurationPath) { existingData in
            let existing = try MyPaperTemplateList(configurationData: existingData)
            updated = existing
            change(&updated)
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }

    /// Keeps a one-page PDF as a template named `name`, under a free file name, shown last.
    public func addMyPaperTemplate(_ pdfData: Data, named name: String) throws -> MyPaperTemplateList.Template {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = FileNameRules.problem(with: trimmedName, isNote: false) { throw GraphiteError.unavailable(problem) }
        let directory = try VaultPath(MyPaperTemplateList.directory)
        try createDirectory(directory)
        let path = try uniquePath(directory: directory, stem: trimmedName, extension: MyPaperTemplateList.fileExtension)
        _ = try save(pdfData, at: path, expecting: .absent)
        let fileName = path.name
        // Shown last: the arrangement is fixed to what is shown now, with the new template at the end.
        let otherFileNames = try myPaperTemplates().map(\.fileName).filter { listedName in listedName != fileName }
        try updateMyPaperTemplateList { list in list.arrange(otherFileNames + [fileName]) }
        return MyPaperTemplateList.Template(fileName: fileName, isHidden: false)
    }

    /// Renames a template; its place and hidden state stay. Never replaces another template.
    public func renameMyPaperTemplate(_ fileName: String, to name: String) throws -> MyPaperTemplateList.Template {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = FileNameRules.problem(with: trimmedName, isNote: false) { throw GraphiteError.unavailable(problem) }
        let directory = try VaultPath(MyPaperTemplateList.directory)
        let newFileName = trimmedName + "." + MyPaperTemplateList.fileExtension
        if newFileName != fileName { try move(directory.appending(fileName), to: directory.appending(newFileName)) }
        let list = try updateMyPaperTemplateList { list in list.rename(fileName, to: newFileName) }
        return MyPaperTemplateList.Template(fileName: newFileName, isHidden: list.hiddenFileNames.contains(newFileName))
    }

    /// Deletes a template's file for good: it is Graphite's own copy of a page, and the file it
    /// was made from is untouched.
    public func deleteMyPaperTemplate(_ fileName: String) throws {
        _ = try delete(VaultPath(MyPaperTemplateList.directory).appending(fileName), method: .permanent)
        try updateMyPaperTemplateList { list in list.forget(fileName) }
    }

    /// Moves an arrangement this build cannot read to a free name beside it, so it is kept as it
    /// is and Graphite can start a new one. Returns where it went.
    public func moveMyPaperTemplateListAside() throws -> VaultPath {
        let path = try VaultPath(MyPaperTemplateList.configurationPath)
        let keptCopy = try uniquePath(directory: path.parent, stem: MyPaperTemplateList.unreadableCopyStem, extension: "json")
        try move(path, to: keptCopy)
        return keptCopy
    }
}
