import Foundation
import GraphiteCore

/// The order of the templates after a list's drag, as pure values.
enum MyTemplateArrangement {
    /// `fileNames` with the items at `offsets` moved to just before `destination` (an index in the
    /// list before the move), as a list's move gesture reports it.
    static func moved(_ fileNames: [String], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [String] {
        let movedNames = offsets.sorted().filter { offset in fileNames.indices.contains(offset) }.map { offset in fileNames[offset] }
        var remaining = fileNames.enumerated().filter { position, _ in !offsets.contains(position) }.map(\.element)
        let removedBefore = offsets.filter { offset in offset < destination }.count
        let insertionPoint = min(max(destination - removedBefore, 0), remaining.count)
        remaining.insert(contentsOf: movedNames, at: insertionPoint)
        return remaining
    }
}

extension MyPaperTemplateList.Template {
    /// `templates` in the order of `fileNames`; templates not named keep their order after them.
    static func arranged(_ templates: [MyPaperTemplateList.Template], as fileNames: [String]) -> [MyPaperTemplateList.Template] {
        let byFileName = Dictionary(templates.map { template in (template.fileName, template) }) { firstTemplate, _ in firstTemplate }
        let arranged = fileNames.compactMap { fileName in byFileName[fileName] }
        let arrangedNames = Set(arranged.map(\.fileName))
        return arranged + templates.filter { template in !arrangedNames.contains(template.fileName) }
    }
}
