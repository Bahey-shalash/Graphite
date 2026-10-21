import Foundation

/// A section of the Guide, the step-by-step how-to that starts from a first note and goes
/// through every feature. Sections are in the order a beginner meets them.
enum GuideSection: CaseIterable, Identifiable {
    case basics
    case writing
    case organizing
    case handwritingAndPDFs
    case studying
    case customizing

    var id: Self { self }

    var title: String {
        switch self {
        case .basics: "The Basics"
        case .writing: "Writing Notes"
        case .organizing: "Finding and Organizing"
        case .handwritingAndPDFs: GuideBasicsCopy.forPlatform(touch: "Handwriting and PDFs", mac: "PDFs")
        case .studying: "Studying"
        case .customizing: "Making It Yours"
        }
    }

    /// The topics of this section that this platform has.
    var topicsOnThisPlatform: [GuideTopic] {
        GuideTopic.allCases.filter { topic in topic.section == self && topic.isOnThisPlatform }
    }
}

/// One how-to of the Guide. Its words are in `content`; the Guide's search reads them too.
enum GuideTopic: CaseIterable, Identifiable {
    // The Basics
    case vaults
    case firstNote
    case readAndWrite
    case filesAndFolders
    // Writing Notes
    case formatting
    case links
    case embeds
    case listsAndTasks
    case tables
    case calloutsMathAndCode
    case imagesAndAttachments
    case propertiesAndTags
    // Finding and Organizing
    case search
    case quickSwitcherAndCommands
    case tabsAndSplit
    case library
    case bases
    case canvas
    case graphAndMap
    case templatesAndDailyNotes
    // Handwriting and PDFs
    case drawings
    case pencilTools
    case annotatingPDFs
    case notebooks
    // Studying
    case recording
    case readAloud
    // Making It Yours
    case appearance
    case corePlugins
    case communityPlugins
    case syncAndObsidian
    case fileRecovery
    case keyboardShortcuts
    case sourceCodeAndFeedback

    var id: Self { self }

    var section: GuideSection {
        switch self {
        case .vaults, .firstNote, .readAndWrite, .filesAndFolders: .basics
        case .formatting, .links, .embeds, .listsAndTasks, .tables, .calloutsMathAndCode, .imagesAndAttachments, .propertiesAndTags: .writing
        case .search, .quickSwitcherAndCommands, .tabsAndSplit, .library, .bases, .canvas, .graphAndMap, .templatesAndDailyNotes: .organizing
        case .drawings, .pencilTools, .annotatingPDFs, .notebooks: .handwritingAndPDFs
        case .recording, .readAloud: .studying
        case .appearance, .corePlugins, .communityPlugins, .syncAndObsidian, .fileRecovery, .keyboardShortcuts, .sourceCodeAndFeedback: .customizing
        }
    }

    /// Drawing and writing with Apple Pencil exist only on iPadOS and iOS, so the Mac's Guide
    /// leaves those topics out rather than describe what it cannot do.
    var needsApplePencilFeatures: Bool {
        switch self {
        case .drawings, .pencilTools, .notebooks: true
        case .annotatingPDFs, .vaults, .firstNote, .readAndWrite, .filesAndFolders, .formatting, .links, .embeds, .listsAndTasks, .tables,
             .calloutsMathAndCode, .imagesAndAttachments, .propertiesAndTags, .search, .quickSwitcherAndCommands, .tabsAndSplit,
             .library, .bases, .canvas, .graphAndMap, .templatesAndDailyNotes, .recording, .readAloud, .appearance, .corePlugins,
             .communityPlugins, .syncAndObsidian, .fileRecovery, .keyboardShortcuts, .sourceCodeAndFeedback: false
        }
    }

    var isOnThisPlatform: Bool {
        #if os(macOS)
        !needsApplePencilFeatures
        #else
        true
        #endif
    }

    /// Whether the topic's title, summary, steps or tips contain every word of `query`,
    /// ignoring case and accents. An empty query matches every topic.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let content = content
        let searchable = ([content.title, content.summary] + content.steps.flatMap { step in [step.text, step.example ?? ""] } + content.tips)
            .joined(separator: "\n")
        return words.allSatisfy { word in searchable.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// What one topic of the Guide says: a short summary, numbered steps, and tips.
struct GuideTopicContent {
    let systemImage: String
    let title: String
    let summary: String
    let steps: [GuideStep]
    var tips: [String] = []
}

/// One numbered step. Its text may use Markdown's **bold** for the names of controls; an
/// example is Markdown to type, shown as written below the step.
struct GuideStep {
    let text: String
    var example: String?

    init(_ text: String, example: String? = nil) {
        self.text = text
        self.example = example
    }
}
