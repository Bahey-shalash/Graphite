import Foundation

/// The words of the Guide's Making It Yours section, and which words belong to which topic.
enum GuideCustomizingCopy {
    private static func forPlatform<Words>(touch: Words, mac: Words) -> Words {
        GuideBasicsCopy.forPlatform(touch: touch, mac: mac)
    }

    private static var openSettings: String {
        forPlatform(touch: "Open Settings with the gear at the top of the sidebar (⌘, with a keyboard).",
                    mac: "Open Settings from the Graphite menu, or press ⌘,.")
    }

    static var appearance: GuideTopicContent {
        GuideTopicContent(
            systemImage: "paintpalette",
            title: "Appearance",
            summary: "Light or dark, your accent color, your fonts, and your vault's Obsidian theme.",
            steps: [
                GuideStep(openSettings + " Choose **Appearance**."),
                GuideStep("**Base Color Scheme**: **Adapt to System**, **Light** or **Dark**."),
                GuideStep("**Accent Color**: pick a color, a **Custom Color**, or **Use the Vault's Obsidian Accent**."),
                GuideStep(forPlatform(
                    touch: "**Font**: the interface, text and monospace fonts, and **Quick Font Size Adjustment** to change the size with a pinch " +
                           "over the note.",
                    mac: "**Font**: the interface, text and monospace fonts, and **Quick Font Size Adjustment** to change the size by " +
                         "Control-scrolling over the note.")),
                GuideStep("**Use the Vault's Obsidian Theme** draws notes in the theme and snippets your vault uses in Obsidian."),
                GuideStep(forPlatform(touch: "**App Icon** picks Graphite's icon on the Home Screen.",
                                      mac: "**Show Inline Title** shows or hides the note's name above its text."))
            ])
    }

    static var corePlugins: GuideTopicContent {
        GuideTopicContent(
            systemImage: "puzzlepiece",
            title: "Turn Features On and Off",
            summary: "As in Obsidian, every feature is a core plugin with a switch. Turn off what you do not use.",
            steps: [
                GuideStep(openSettings + " Choose **Core Plugins**."),
                GuideStep("Turn a feature on or off with its switch: Backlinks, Outline, Tags View, Word Count, Colors, Pencil Drawings, Audio " +
                          "Recorder, Read Aloud, Bases, Templates, Daily Notes, Graph View, Map View, Canvas and more."),
                GuideStep("Features that have options get their own page under **Core Plugins** in the Settings sidebar.")
            ],
            tips: ["Turning a feature off hides it in Graphite. It never changes your notes."])
    }

    static var communityPlugins: GuideTopicContent {
        GuideTopicContent(
            systemImage: "puzzlepiece.extension",
            title: "Community Plugins",
            summary: "Graphite can install and run many of Obsidian's community plugins. This is early work: not every plugin runs yet.",
            steps: [
                GuideStep(openSettings + " Choose **Community Plugins** and **Turn On Community Plugins**."),
                GuideStep("**Browse Community Plugins…** lists Obsidian's directory. " +
                          "Choose **Install** on the one you want, or install one from its GitHub repository."),
                GuideStep("Turn it on with its switch under **Installed Plugins**. **Options** opens its settings; **Remove** uninstalls it.")
            ],
            tips: ["Plugins already in your vault's .obsidian folder, installed by Obsidian, show up here too."])
    }

    static let syncAndObsidian = GuideTopicContent(
        systemImage: "icloud",
        title: "Your Devices and Obsidian",
        summary: "Graphite has no account and no sync service of its own. " +
                 "Your vault syncs the way its folder does, for example through iCloud Drive.",
        steps: [
            GuideStep("Keep the vault in iCloud Drive: when you make it, use **Choose Folder…** and pick a folder in iCloud Drive."),
            GuideStep("On your other devices, choose **Open Folder as Vault** and pick the same folder."),
            GuideStep("To use the vault in Obsidian too, keep it where Obsidian looks, such as iCloud Drive › Obsidian. " +
                      "Both apps then read and write the same files."),
            GuideStep("If a note is changed in two places at once, Graphite notices and shows both versions rather than overwriting one.")
        ],
        tips: ["Search indexes and thumbnails are kept outside the vault. The vault holds only your own files."])

    static let fileRecovery = GuideTopicContent(
        systemImage: "clock.arrow.circlepath",
        title: "Undo and File Recovery",
        summary: "Undo the last changes, or bring back an older version of a note from Graphite's snapshots.",
        steps: [
            GuideStep(forPlatform(touch: "**Undo** and **Redo** are at the top of a note on iPad, and above the keyboard on iPhone. " +
                                         "Touch and hold **Undo** for **Move Through Changes…**.",
                                  mac: "Edit › **Undo** and **Redo** (⌘Z and ⇧⌘Z) undo recent changes.")),
            GuideStep("Graphite also keeps snapshots of your notes on this device. Open them with **More** › **File Recovery…**."),
            GuideStep("Pick a time to see that version, then **Restore This Version**."),
            GuideStep("Settings › File Recovery sets how often snapshots are taken and how long they are kept; **View Snapshots** lists them all.")
        ])

    static var keyboardShortcuts: GuideTopicContent {
        GuideTopicContent(
            systemImage: "keyboard",
            title: "Keyboard Shortcuts",
            summary: forPlatform(touch: "With a keyboard attached to iPad, these shortcuts work. Hold ⌘ to see them listed.",
                                 mac: "The shortcuts that work everywhere in Graphite."),
            steps: [
                GuideStep("Notes and files: ⌘N new note, ⌘O Quick Switcher, ⌘P Command Palette (⇧⌘P on the Mac, where ⌘P prints), ⇧⌘F search all files, ⌘E read or write, ⌘S save."),
                GuideStep("Tabs: ⌘T new tab, ⌘W close tab, ⇧⌘T reopen it, ⌃Tab next tab, ⌘1 to ⌘8 a tab, ⌘9 the last tab, ⌘[ and ⌘] back and " +
                          "forward."),
                GuideStep(forPlatform(
                    touch: "Writing: ⌘B bold, ⌘I italic, ⇧⌘H highlight, ⇧⌘X strikethrough, ⌃⌘C code, ⌘/ comment, ⌘K link, ⌘L tick a task, ⌃⌘1 to " +
                           "⌃⌘6 headings, ⌥⌘↑ and ⌥⌘↓ move a line.",
                    mac: "Writing: use the **Format** and **Insert** menus in the note's toolbar, or right-click the text.")),
                GuideStep("Text size, with **Quick Font Size Adjustment** on: ⌘+ bigger, ⌘- smaller, ⌘0 back to normal."),
                GuideStep(forPlatform(touch: "Settings: ⌘,.", mac: "Settings: ⌘,. This Guide: ⌘?."))
            ])
    }

    static var sourceCodeAndFeedback: GuideTopicContent {
        GuideTopicContent(
            systemImage: "chevron.left.forwardslash.chevron.right",
            title: "Source Code and Feedback",
            summary: "Graphite is open source under the Apache License 2.0. Its code and issues are on GitHub at " +
                     "[github.com/Graphite-Note/Graphite](https://github.com/Graphite-Note/Graphite).",
            steps: [
                GuideStep("Settings › General › About has **Source Code**, which opens the repository, and **Report a Problem**, which opens " +
                          "its issues."),
                GuideStep("To report a problem, choose **New issue**, then **Bug report**, and say what you did, what you expected and what " +
                          "happened. A small sample file helps more than a personal note."),
                GuideStep(forPlatform(
                    touch: "Testing through TestFlight? Take a screenshot and share it with TestFlight to send feedback straight to the developer.",
                    mac: "Testing through TestFlight? In the TestFlight app, choose Graphite Note, then **Send Beta Feedback**."))
            ],
            tips: ["Report a security problem privately: on the repository's **Security** tab, choose **Report a vulnerability**.",
                   "To build Graphite yourself, follow **Building** in the repository's README."])
    }
}

extension GuideTopic {
    var content: GuideTopicContent {
        switch self {
        case .vaults: GuideBasicsCopy.vaults
        case .firstNote: GuideBasicsCopy.firstNote
        case .readAndWrite: GuideBasicsCopy.readAndWrite
        case .filesAndFolders: GuideBasicsCopy.filesAndFolders
        case .formatting: GuideBasicsCopy.formatting
        case .links: GuideBasicsCopy.links
        case .embeds: GuideBasicsCopy.embeds
        case .listsAndTasks: GuideBasicsCopy.listsAndTasks
        case .tables: GuideBasicsCopy.tables
        case .calloutsMathAndCode: GuideBasicsCopy.calloutsMathAndCode
        case .imagesAndAttachments: GuideBasicsCopy.imagesAndAttachments
        case .propertiesAndTags: GuideBasicsCopy.propertiesAndTags
        case .search: GuideOrganizingCopy.search
        case .quickSwitcherAndCommands: GuideOrganizingCopy.quickSwitcherAndCommands
        case .tabsAndSplit: GuideOrganizingCopy.tabsAndSplit
        case .library: GuideOrganizingCopy.library
        case .bases: GuideOrganizingCopy.bases
        case .canvas: GuideOrganizingCopy.canvas
        case .graphAndMap: GuideOrganizingCopy.graphAndMap
        case .templatesAndDailyNotes: GuideOrganizingCopy.templatesAndDailyNotes
        case .drawings: GuidePencilCopy.drawings
        case .pencilTools: GuidePencilCopy.pencilTools
        case .annotatingPDFs: GuidePencilCopy.annotatingPDFs
        case .notebooks: GuidePencilCopy.notebooks
        case .recording: GuidePencilCopy.recording
        case .readAloud: GuidePencilCopy.readAloud
        case .appearance: GuideCustomizingCopy.appearance
        case .corePlugins: GuideCustomizingCopy.corePlugins
        case .communityPlugins: GuideCustomizingCopy.communityPlugins
        case .syncAndObsidian: GuideCustomizingCopy.syncAndObsidian
        case .fileRecovery: GuideCustomizingCopy.fileRecovery
        case .keyboardShortcuts: GuideCustomizingCopy.keyboardShortcuts
        case .sourceCodeAndFeedback: GuideCustomizingCopy.sourceCodeAndFeedback
        }
    }
}
