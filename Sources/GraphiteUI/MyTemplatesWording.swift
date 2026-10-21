import Foundation

extension MyTemplatesFailure {
    var title: String {
        switch self {
        case .notListed, .arrangementSetAside, .arrangementUnreadable: "My Templates"
        case .couldNotKeep: "Template Not Added"
        case .couldNotChange: "Template Not Changed"
        }
    }

    var message: String {
        switch self {
        case .notListed:
            "Graphite could not list the templates in “.obsidian/graphite-templates”. They may not be available on this device."
        case .arrangementSetAside(let keptCopyName):
            "The order of the templates was not in a form Graphite can read, so it was kept as “\(keptCopyName)” and the templates are shown by name."
        case .arrangementUnreadable:
            "“.obsidian/graphite-templates/templates.json” is not in a form Graphite can read, so the templates are not shown. The file is left as it is."
        case .couldNotKeep(let templateName):
            "“\(templateName)” could not be kept as a template. Nothing was added."
        case .couldNotChange(let templateName):
            templateName.isEmpty ? "The templates could not be rearranged." : "“\(templateName)” could not be changed."
        }
    }
}

extension MyTemplateDraftError {
    var message: String {
        switch self {
        case .unreadable: "Graphite could not read this file."
        case .tooLarge: "This file is too large to make a template of."
        case .unsupported: "Choose a PDF or a picture."
        case .locked: "This PDF is locked. Unlock it first, then choose it again."
        }
    }
}
