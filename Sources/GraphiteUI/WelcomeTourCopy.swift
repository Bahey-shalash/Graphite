import Foundation

/// The words and pictures of each welcome tour page. Every place named here (a button, a
/// menu, a settings page) is named as the app labels it, so a reader can find it.
enum WelcomeTourCopy {
    static let sourceCodeAddress = URL(string: "https://github.com/Graphite-Note/Graphite")

    static let welcome = WelcomeTourPageContent(
        systemImage: "pencil.and.scribble",
        title: "Welcome to Graphite",
        summary: welcomeSummary,
        points: welcomePoints,
        pointLayout: .list,
        screenshots: [WelcomeTourScreenshot(label: "Note", assetName: "WelcomeTourNote",
                                            accessibilityDescription: "A lecture note on Fourier series with formulas and a callout, beside the " +
                                                                      "vault's folders.")])

    static let vaultIsAFolder = WelcomeTourPageContent(
        systemImage: "folder",
        title: "A vault is just a folder",
        summary: "Like Obsidian, Graphite works on a vault: an ordinary folder of notes, PDFs and attachments. " +
                 "An Obsidian vault opens as it is, and both apps can use it.",
        points: [
            WelcomeTourPoint(systemImage: "folder.badge.plus", title: .words("Create or open a vault"),
                             detail: "Start a new vault, or open any folder, such as your Obsidian vault in iCloud Drive. " +
                                     "Switch vaults from the vault name at the top of the sidebar."),
            WelcomeTourPoint(systemImage: "square.grid.2x2", title: .words("List or Library"),
                             detail: "See files as a list, as in Obsidian, or as a library of folders and page thumbnails, as in Files. " +
                                     "Switch with the two buttons at the top of the sidebar, or in Settings › Appearance › Files."),
            WelcomeTourPoint(systemImage: "plus", title: .words("Make something new"), detail: newItemDetail)
        ],
        pointLayout: .list,
        screenshots: vaultScreenshots)

    static let markdown = WelcomeTourPageContent(
        systemImage: "text.document",
        title: "Markdown notes, the Obsidian way",
        summary: "Write plain Markdown with everything Obsidian understands: headings, lists, tasks, tables, callouts, math, code, tags and " +
                 "properties.",
        points: [
            WelcomeTourPoint(systemImage: "link", title: .words("Links and backlinks"),
                             detail: "Type [[ to link to another note. The right sidebar shows the outline, backlinks, outgoing links and tags."),
            WelcomeTourPoint(systemImage: "book", title: .words("Read or write"),
                             detail: "The pencil button at the top right switches between reading and writing. " +
                                     "In the note's More menu, View picks Reading View, Live Preview or Source Mode."),
            WelcomeTourPoint(systemImage: "magnifyingglass", title: .words("Find anything"),
                             detail: "Search every file from the sidebar. The Quick Switcher (⌘O) opens a note by name, and the Command Palette " +
                                     "(⌘P) runs any command.")
        ],
        pointLayout: .list,
        screenshots: [WelcomeTourScreenshot(label: "Note", assetName: "WelcomeTourMarkdown",
                                            accessibilityDescription: "Formulas, a list and a colored example callout in a Markdown note.")])

    static let embeds = WelcomeTourPageContent(
        systemImage: "rectangle.on.rectangle",
        title: "Embed notes, sections and PDFs",
        summary: "An embed shows another file inside your note: the original, not a copy, so a change shows everywhere it is embedded.",
        points: [
            WelcomeTourPoint(systemImage: "doc.text", title: .syntax("![[Note]]"), detail: "The whole note."),
            WelcomeTourPoint(systemImage: "number", title: .syntax("![[Note#Heading]]"),
                             detail: "One section, shown in full. Add #^block for one paragraph."),
            WelcomeTourPoint(systemImage: "doc.richtext", title: .syntax("![[Slides.pdf#page=8&height=400]]"),
                             detail: "A PDF at page 8, 400 points tall. It scrolls and zooms inside the note."),
            WelcomeTourPoint(systemImage: "photo", title: .syntax("![[Figure.png|400]]"),
                             detail: "An image 400 points wide. ![[Lectures.base]] embeds a live table of notes.")
        ],
        pointLayout: .list,
        screenshots: [
            WelcomeTourScreenshot(label: "Section", assetName: "WelcomeTourEmbeddedNote",
                                  accessibilityDescription: "An exam review note embedding the Switching threshold section of a lecture note, with " +
                                                            "its graph."),
            WelcomeTourScreenshot(label: "PDF Page", assetName: "WelcomeTourEmbeddedPDF",
                                  accessibilityDescription: "A lecture slide embedded in a note, in a PDF viewer with page and zoom controls.")
        ])

    static let bases = WelcomeTourPageContent(
        systemImage: "square.grid.3x2",
        title: "Your notes as a gallery",
        summary: "A base turns notes into a table, cards, a list, a map or a board, from the properties at the top of each note. " +
                 "It is an Obsidian .base file, so Obsidian shows the same views.",
        points: [
            WelcomeTourPoint(systemImage: "photo.on.rectangle.angled", title: .words("Cards with covers"),
                             detail: "Give each note a cover image property and the cards view becomes a gallery, like these lectures."),
            WelcomeTourPoint(systemImage: "line.3.horizontal.decrease", title: .words("Filter and sort"),
                             detail: "Pick which notes appear and in what order. The view menu at the top switches views and makes new ones."),
            WelcomeTourPoint(systemImage: "map", title: .words("Maps and boards"),
                             detail: "Notes with a location go on a map; a board groups notes into columns by a property."),
            WelcomeTourPoint(systemImage: "plus", title: .words("Make one"),
                             detail: "New › Base makes one, and a note can embed it as it embeds another note.")
        ],
        pointLayout: .list,
        screenshots: [WelcomeTourScreenshot(label: "Gallery", assetName: "WelcomeTourBasesGallery",
                                            accessibilityDescription: "A base of lecture notes shown as cards, each with a figure from the lecture " +
                                                                      "as its cover.")])

    static let handwriting = WelcomeTourPageContent(
        systemImage: "pencil.tip.crop.circle",
        title: "Handwriting inside your notes",
        summary: "Put a drawing anywhere in a note: a derivation, a circuit, a sketch of a graph. " +
                 "The canvas is as wide as the note and grows downward as you write.",
        points: [
            WelcomeTourPoint(systemImage: "pencil.tip.crop.circle.badge.plus", title: .words("Start a drawing"),
                             detail: "While writing, tap Draw in the toolbar, or double-tap or squeeze Apple Pencil. " +
                                     "The drawing goes where the cursor is."),
            WelcomeTourPoint(systemImage: "photo.on.rectangle", title: .words("An ordinary image"),
                             detail: "Insert saves a PNG, PDF or SVG file in your attachments folder and embeds it. " +
                                     "Pick the format in Settings › Pencil Drawings › Save Drawings As."),
            WelcomeTourPoint(systemImage: "pencil.and.outline", title: .words("Change it later"),
                             detail: "Tap Edit on a drawing to open it again. The canvas's More menu has Draw Shapes, Paper, Draw with Finger and " +
                                     "Export a Copy.")
        ],
        pointLayout: .list,
        screenshots: [
            WelcomeTourScreenshot(label: "In the Note", assetName: "WelcomeTourDrawingInNote",
                                  accessibilityDescription: "A hand-drawn square wave and its first harmonic, embedded in a note under a callout."),
            WelcomeTourScreenshot(label: "Canvas", assetName: "WelcomeTourDrawingCanvas",
                                  accessibilityDescription: "The drawing canvas with the Apple Pencil tool palette at the bottom.")
        ])

    static let pdfs = WelcomeTourPageContent(
        systemImage: "doc.richtext",
        title: "Annotate PDFs and notebooks",
        summary: "Write on lecture slides, textbooks and worksheets. " +
                 "A notebook is a PDF too, printed on real paper: dotted, squared, ruled, Cornell and more.",
        points: [
            WelcomeTourPoint(systemImage: "applepencil", title: .words("Write on any page"),
                             detail: "Tap the pencil button at the top right and write. " +
                                     "Ink is saved as standard PDF annotations, so Preview and every PDF reader show it."),
            WelcomeTourPoint(systemImage: "highlighter", title: .words("Mark up the text"),
                             detail: "Select text to highlight, underline or strike it through, or to quote it in a note."),
            WelcomeTourPoint(systemImage: "square.grid.2x2", title: .words("Pages"),
                             detail: "Show Pages lists thumbnails to reorder, duplicate and rotate. " +
                                     "Add Page inserts new paper, or pages from another PDF."),
            WelcomeTourPoint(systemImage: "book.closed", title: .words("New notebooks"),
                             detail: "New › Notebook picks the paper, its color, the size and the orientation.")
        ],
        pointLayout: .list,
        screenshots: [
            WelcomeTourScreenshot(label: "Annotate", assetName: "WelcomeTourPDFFloatingPalette",
                                  accessibilityDescription: "Lecture slides with handwritten notes, and the Apple Pencil tool palette."),
            WelcomeTourScreenshot(label: "New Notebook", assetName: "WelcomeTourNewNotebook",
                                  accessibilityDescription: "The New Notebook sheet with its paper templates.")
        ])

    static let pencilTools = WelcomeTourPageContent(
        systemImage: "slider.horizontal.3",
        title: "Your Pencil tools, your way",
        summary: "Choose how the tools appear on iPad: the system's floating palette, which you can move or minimize, or a fixed bar in the tab " +
                 "bar, as in Goodnotes and Notability.",
        points: [
            WelcomeTourPoint(systemImage: "switch.2", title: .words("Pick a style"),
                             detail: "Settings › Pencil Drawings › Pencil Tools › Tools: Floating Palette or Fixed Bar. " +
                                     "On iPhone the palette is always used."),
            WelcomeTourPoint(systemImage: "hand.raised", title: .words("Palm rejection"),
                             detail: "A hand resting on the page does not scroll, zoom or tap while Apple Pencil writes."),
            WelcomeTourPoint(systemImage: "circle.and.line.horizontal", title: .words("Hold to make a shape"),
                             detail: "Draw a line, circle, triangle or rectangle and keep the Pencil still: it turns into a clean shape."),
            WelcomeTourPoint(systemImage: "hand.tap", title: .words("Double-tap or squeeze"),
                             detail: "Starts a drawing while you write a note. Switch it off in Settings › Pencil Drawings.")
        ],
        pointLayout: .list,
        screenshots: [
            WelcomeTourScreenshot(label: "Floating Palette", assetName: "WelcomeTourPDFFloatingPalette",
                                  accessibilityDescription: "The floating Apple Pencil palette over an annotated slide."),
            WelcomeTourScreenshot(label: "Fixed Bar", assetName: "WelcomeTourPDFFixedBar",
                                  accessibilityDescription: "The fixed bar of Pencil tools and colors in the tab bar, above an annotated slide."),
            WelcomeTourScreenshot(label: "Settings", assetName: "WelcomeTourPencilSettings",
                                  accessibilityDescription: "Settings › Pencil Drawings, with the Tools choice, shapes, highlighter and Apple " +
                                                            "Pencil options.")
        ])

    static let everythingElse = WelcomeTourPageContent(
        systemImage: "sparkles",
        title: "And there's more",
        summary: "Everything below works on the same ordinary files.",
        points: [
            WelcomeTourPoint(systemImage: "mic", title: .words("Record lectures"),
                             detail: "The microphone button records audio or video into the vault while you keep writing."),
            WelcomeTourPoint(systemImage: "rectangle.3.group", title: .words("Canvas"),
                             detail: canvasDetail),
            WelcomeTourPoint(systemImage: "point.3.connected.trianglepath.dotted", title: .words("Graph view"),
                             detail: "See how your notes link. Open it from the Command Palette, or the local graph in the right sidebar."),
            WelcomeTourPoint(systemImage: "rectangle.split.2x1", title: .words("Tabs and split view"),
                             detail: "Keep several files open in tabs, and two side by side with Split Right."),
            WelcomeTourPoint(systemImage: "calendar", title: .words("Templates and daily notes"),
                             detail: "Insert a template into a note, or open today's daily note from New."),
            WelcomeTourPoint(systemImage: "speaker.wave.2", title: .words("Read Aloud"),
                             detail: "Natural voices read notes and PDFs, highlighting each word, entirely on this device. " +
                                     "Turn it on in Settings › Core Plugins."),
            WelcomeTourPoint(systemImage: "puzzlepiece.extension", title: .words("Community plugins"),
                             detail: "Install Obsidian community plugins from Settings › Community Plugins. Early work: not every plugin runs yet.")
        ],
        pointLayout: .tiles,
        screenshots: [])

    static let settings = WelcomeTourPageContent(
        systemImage: "gearshape",
        title: "Make it yours",
        summary: settingsSummary,
        points: [
            WelcomeTourPoint(systemImage: "puzzlepiece", title: .words("Core Plugins"),
                             detail: "Turn features such as Backlinks, Bases, Canvas or Read Aloud on or off. " +
                                     "Turning one off never changes your notes."),
            WelcomeTourPoint(systemImage: "paintpalette", title: .words("Appearance"),
                             detail: "Light or dark, the accent color, fonts, the app icon, and your vault's Obsidian theme and snippets."),
            WelcomeTourPoint(systemImage: "character.cursor.ibeam", title: .words("Editor"),
                             detail: "The default view for new notes, Live Preview or Source Mode, readable line length and the code theme."),
            WelcomeTourPoint(systemImage: "link", title: .words("Files and Links"),
                             detail: "Where new notes and attachments go and how links are written, kept in your vault's Obsidian settings.")
        ],
        pointLayout: .list,
        screenshots: settingsScreenshots)

    static let gettingStarted = WelcomeTourPageContent(
        systemImage: "checkmark.seal",
        title: "Ready when you are",
        summary: "Open the vault you already have, or start a new one. You can see this tour again in Settings › General › Welcome Tour.",
        points: [
            WelcomeTourPoint(systemImage: "folder", title: .words("Open Folder as Vault"),
                             detail: "Pick an existing folder, such as an Obsidian vault in iCloud Drive."),
            WelcomeTourPoint(systemImage: "plus.rectangle.on.folder", title: .words("Create New Vault"),
                             detail: "Start in a new, empty folder, on this device or in iCloud Drive."),
            WelcomeTourPoint(systemImage: "book", title: .words("Learn step by step"), detail: guideLocationDetail),
            WelcomeTourPoint(systemImage: "exclamationmark.bubble", title: .words("This is a beta"), detail: betaFeedbackDetail)
        ],
        pointLayout: .list,
        screenshots: [])
}
