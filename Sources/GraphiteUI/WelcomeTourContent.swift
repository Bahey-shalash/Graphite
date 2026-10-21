import Foundation

/// One page of the welcome tour that Graphite shows the first time it starts, and again
/// from Settings › General › Welcome Tour or the welcome screen. The pages walk a new user
/// from the basics (a vault is a folder of ordinary files) to the features and where to find
/// them. Each page's words and pictures are its `content`.
enum WelcomeTourPage: CaseIterable, Identifiable {
    case welcome
    case vaultIsAFolder
    case markdown
    case embeds
    case bases
    case handwriting
    case pdfs
    case pencilTools
    case everythingElse
    case settings
    case gettingStarted

    var id: Self { self }

    /// The pages this platform shows. The Mac has no Pencil drawing or PDF ink, so its tour
    /// leaves those pages out rather than describe what it cannot do.
    static var pagesOnThisPlatform: [WelcomeTourPage] {
        #if os(macOS)
        allCases.filter { page in !page.needsApplePencilFeatures }
        #else
        allCases
        #endif
    }

    /// Pages about drawing and writing with Apple Pencil, which only iPadOS and iOS have.
    var needsApplePencilFeatures: Bool {
        switch self {
        case .handwriting, .pdfs, .pencilTools: true
        case .welcome, .vaultIsAFolder, .markdown, .embeds, .bases, .everythingElse, .settings, .gettingStarted: false
        }
    }

    var content: WelcomeTourPageContent {
        switch self {
        case .welcome: WelcomeTourCopy.welcome
        case .vaultIsAFolder: WelcomeTourCopy.vaultIsAFolder
        case .markdown: WelcomeTourCopy.markdown
        case .embeds: WelcomeTourCopy.embeds
        case .bases: WelcomeTourCopy.bases
        case .handwriting: WelcomeTourCopy.handwriting
        case .pdfs: WelcomeTourCopy.pdfs
        case .pencilTools: WelcomeTourCopy.pencilTools
        case .everythingElse: WelcomeTourCopy.everythingElse
        case .settings: WelcomeTourCopy.settings
        case .gettingStarted: WelcomeTourCopy.gettingStarted
        }
    }
}

/// What one page of the tour says and shows.
struct WelcomeTourPageContent {
    let systemImage: String
    let title: String
    let summary: String
    let points: [WelcomeTourPoint]
    /// How the points are laid out: a list beside the screenshots, or a grid of tiles.
    let pointLayout: WelcomeTourPointLayout
    /// Screenshots of Graphite on iPad; with more than one, a segmented control picks one.
    let screenshots: [WelcomeTourScreenshot]
}

enum WelcomeTourPointLayout {
    case list
    case tiles

    /// How wide a page with this layout grows when its parts stack: a list reads best in a
    /// column, while tiles spread across a wide window.
    var maximumStackedWidth: CGFloat {
        switch self {
        case .list: 760
        case .tiles: 1100
        }
    }
}

/// One thing a page explains: what it is, and where to find it.
struct WelcomeTourPoint: Identifiable {
    let systemImage: String
    let title: WelcomeTourPointTitle
    let detail: String
    /// A web page the point opens, such as Graphite's source code.
    var destination: URL?

    var id: String { title.text }
}

enum WelcomeTourPointTitle {
    case words(String)
    /// Markdown to type, shown in a monospaced font.
    case syntax(String)

    var text: String {
        switch self {
        case .words(let words): words
        case .syntax(let markdown): markdown
        }
    }
}

/// A picture of Graphite from the app's `WelcomeTour` asset catalog, with a light and a dark
/// appearance. The pictures were taken in a demo vault of lecture notes.
struct WelcomeTourScreenshot: Identifiable {
    /// The name in the segmented control when a page has several screenshots.
    let label: String
    let assetName: String
    /// What the picture shows, read by VoiceOver.
    let accessibilityDescription: String

    var id: String { assetName }
}
