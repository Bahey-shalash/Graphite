import Foundation

/// The parts of the welcome tour's words that differ between iPad and iPhone and the Mac,
/// or that several pages share.
extension WelcomeTourCopy {
    static let yourFolderPoint = WelcomeTourPoint(
        systemImage: "folder", title: .words("Your folder, your files"),
        detail: "Notes are Markdown, notebooks are PDFs, drawings are images. Obsidian, Files and Preview open every one of them.")

    static let openSourcePoint = WelcomeTourPoint(
        systemImage: "chevron.left.forwardslash.chevron.right", title: .words("Open source"),
        detail: "Every line of Graphite is public on GitHub: read it, build it, improve it.", destination: sourceCodeAddress)

    /// On the Mac, what sets Graphite apart is that it is a Mac app through and through, open
    /// and light; on iPad and iPhone it is Apple Pencil next to ordinary files. The speed
    /// point names only what the code does and what was measured (Docs/Coverage.md,
    /// 2026-10-15: a vault of 36,392 files opens on the Mac).
    static var welcomeSummary: String {
        #if os(macOS)
        "A native Mac app for Markdown notes and PDFs: open source, light on memory and fast on large vaults. " +
        "Everything is an ordinary file in a folder you own."
        #else
        "Markdown notes, Apple Pencil handwriting, annotated PDFs and lecture recordings, in one app. " +
        "Everything is an ordinary file in a folder you own."
        #endif
    }

    static var welcomePoints: [WelcomeTourPoint] {
        #if os(macOS)
        [
            WelcomeTourPoint(systemImage: "macwindow", title: .words("Native, not a web page"),
                             detail: "Written in Swift with SwiftUI and AppKit: real Mac menus, shortcuts, windows and text. " +
                                     "No browser engine draws your notes; one starts only for community plugins you turn on."),
            openSourcePoint,
            WelcomeTourPoint(systemImage: "gauge.with.dots.needle.33percent", title: .words("Fast and light"),
                             detail: "A vault opens without waiting for a full scan, search reads an index kept on disk, " +
                                     "and the whole vault is never loaded into memory. Tried on a vault of 36,000 files."),
            yourFolderPoint
        ]
        #else
        [
            yourFolderPoint,
            WelcomeTourPoint(systemImage: "lock.shield", title: .words("No account, no server"),
                             detail: "Your notes stay on this device, or in iCloud Drive if you keep the vault there. " +
                                     "Graphite never uploads them."),
            openSourcePoint
        ]
        #endif
    }

    /// Canvases are edited on iPad and iPhone; the Mac shows them.
    static var canvasDetail: String {
        #if os(macOS)
        "Boards of notes, images and cards, saved as Obsidian .canvas files. Open them here; arrange them on iPad and iPhone."
        #else
        "Arrange notes, images and cards on a board, saved as an Obsidian .canvas file."
        #endif
    }

    /// The Mac's New Note button has a menu and no Import.
    static var newItemDetail: String {
        #if os(macOS)
        "The New Note button and its menu make a note, a notebook, a base, a canvas, today's daily note or a folder."
        #else
        "The New button makes a note, a notebook, a canvas, a base or today's daily note, and imports PDFs and images."
        #endif
    }

    static var guideLocationDetail: String {
        #if os(macOS)
        "The Guide goes from your first note to every feature, one step at a time. Open it from Help › Graphite Guide."
        #else
        "The Guide goes from your first note to every feature, one step at a time. Open it from Settings › General › Guide."
        #endif
    }

    static var betaFeedbackDetail: String {
        #if os(macOS)
        "Things will break. In the TestFlight app, choose Graphite Note, then Send Beta Feedback, to tell the developer, " +
        "or open an issue on GitHub."
        #else
        "Things will break. Take a screenshot and share it with TestFlight to send your feedback straight to the developer, " +
        "or open an issue on GitHub."
        #endif
    }

    static var settingsSummary: String {
        #if os(macOS)
        "Open Settings from the Graphite menu, or with ⌘,. As in Obsidian, every feature is a core plugin you can switch off."
        #else
        "Settings is the gear at the top of the sidebar, or ⌘, with a keyboard. As in Obsidian, every feature is a core plugin you can switch off."
        #endif
    }

    /// The Mac's New button is a menu, which the iPad's New picture does not show.
    static var vaultScreenshots: [WelcomeTourScreenshot] {
        let library = WelcomeTourScreenshot(label: "Library", assetName: "WelcomeTourLibrary",
                                            accessibilityDescription: "The vault shown as a library: course folders, a note's thumbnail and a base.")
        #if os(macOS)
        return [library]
        #else
        return [library, WelcomeTourScreenshot(label: "New", assetName: "WelcomeTourNewItem",
                                               accessibilityDescription: "The New menu: Notebook, Note, Canvas, Base, Today's Daily Note, Import " +
                                                                         "and Folder.")]
        #endif
    }

    static var settingsScreenshots: [WelcomeTourScreenshot] {
        let corePlugins = WelcomeTourScreenshot(label: "Core Plugins", assetName: "WelcomeTourCorePlugins",
                                                accessibilityDescription: "Settings › Core Plugins, a switch for each feature.")
        #if os(macOS)
        return [corePlugins]
        #else
        return [corePlugins, WelcomeTourScreenshot(label: "Pencil", assetName: "WelcomeTourPencilSettings",
                                                   accessibilityDescription: "Settings › Pencil Drawings, with the Tools choice and the Apple " +
                                                                             "Pencil options.")]
        #endif
    }
}
