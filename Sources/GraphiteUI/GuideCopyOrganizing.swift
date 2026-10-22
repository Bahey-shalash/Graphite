/**
 * File: GuideCopyOrganizing.swift
 * -------------------------------
 * Layer: UI
 * Description: The Guide's words for organizing a vault: folders, links, search, the command palette and bookmarks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import Foundation

/// The words of the Guide's Finding and Organizing section.
enum GuideOrganizingCopy {
    private static func forPlatform<Words>(touch: Words, mac: Words) -> Words {
        GuideBasicsCopy.forPlatform(touch: touch, mac: mac)
    }

    static let search = GuideTopicContent(
        systemImage: "magnifyingglass",
        title: "Search Your Vault",
        summary: "Search reads every note's name and text. Operators narrow it to a folder, a tag, a section or unfinished tasks.",
        steps: [
            GuideStep(forPlatform(touch: "Type in **Search** in the sidebar. With a keyboard, ⇧⌘F goes straight there.",
                                  mac: "Type in **Search** at the top right of the window, or press ⇧⌘F.")),
            GuideStep("Narrow the search with operators. The search field suggests them as you type:",
                      example: "path:VLSI\ntag:#exam\nsection:Coefficients\ntask-todo:\n[course:VLSI 3]"),
            GuideStep("Choose a result to open that note."),
            GuideStep("**Bookmark This Search** keeps a search you use often in the **Bookmarks** panel of the sidebar.")
        ],
        tips: [forPlatform(touch: "To search inside the open note, use **Find in note** on the bar above the keyboard.",
                           mac: "To search inside the open note, run **Search current file** in the Command Palette.")])

    static let quickSwitcherAndCommands = GuideTopicContent(
        systemImage: "command",
        title: "Quick Switcher and Commands",
        summary: "Two shortcuts reach almost everything: one opens a note by name, the other runs any command by name.",
        steps: [
            GuideStep("The **Quick Switcher** (⌘O) opens a note as you type part of its name. " +
                      "If no note matches, it offers to make one with that name."),
            GuideStep("The **Command Palette** (⌘P on the iPad, ⇧⌘P on the Mac) runs any command by name: " +
                      "insert a table, open the graph, start a recording, turn on Focus…"),
            GuideStep(forPlatform(
                touch: "Without a keyboard: on iPhone both are in the bar at the bottom; on iPad they are at the end of a document's **More** menu.",
                mac: "They are also in the menus: File › **Open Quick Switcher…** and View › **Command Palette…**."))
        ])

    static let tabsAndSplit = GuideTopicContent(
        systemImage: "rectangle.split.2x1",
        title: "Tabs, Split View and Focus",
        summary: "Keep several files open in tabs, put two side by side, or hide everything but the page.",
        steps: [
            GuideStep(forPlatform(
                touch: "On iPad, **New Tab** (+ at the end of the tab bar, ⌘T) opens another tab. " +
                       "On iPhone, the bottom bar's **Tabs** button lists your tabs and opens new ones.",
                mac: "**New Tab** (+ at the end of the tab bar, ⌘T) opens another tab.")),
            GuideStep("⌘ with a click on a link opens it in a new tab."),
            GuideStep(forPlatform(touch: "On iPad, **Split Right** shows two files side by side; **Close This Side** ends the split.",
                                  mac: "**Split Right** shows two files side by side; **Close This Side** ends the split.")),
            GuideStep(forPlatform(touch: "Touch and hold a tab to **Pin** it, close the others, or **Reveal in Sidebar**.",
                                  mac: "Right-click a tab to **Pin** it, close the others, or **Reveal in Sidebar**.")),
            GuideStep("**More** › **Focus** hides the sidebars and tabs. **Exit Focus** brings them back.")
        ],
        tips: ["With a keyboard: ⌘W closes a tab, ⇧⌘T reopens it, ⌃Tab goes to the next tab and ⌘1 to ⌘8 jump to one."])

    static let library = GuideTopicContent(
        systemImage: "square.grid.2x2",
        title: "List or Library",
        summary: "See your files as Obsidian's list, or as a library of folders and page thumbnails like the Files app.",
        steps: [
            GuideStep("Use the two buttons at the top of the sidebar, **Show Files As** List or Library."),
            GuideStep("In **Library**, open a folder to go in; the back arrow goes up again. Thumbnails show each note's and PDF's first page."),
            GuideStep("From a document, the house button at the start of the tab bar (**Library**) brings the library back."),
            GuideStep("The same choice is in Settings › Appearance › **Show Files As**.")
        ])

    static let bases = GuideTopicContent(
        systemImage: "square.grid.3x2",
        title: "Bases: Tables and Galleries of Notes",
        summary: "A base shows notes as a table, cards, a list, a board or a map, built from their properties. It is an Obsidian .base file.",
        steps: [
            GuideStep(forPlatform(touch: "Choose **New** › **Base** and name it. It starts as a table of your notes.",
                                  mac: "Open the menu of the **New Note** button › **New Base** and name it. It starts as a table of your notes.")),
            GuideStep("**View Options** › **Edit View…** chooses the **Layout** (Table, Cards, List, Kanban or Map), which properties show, the " +
                      "**Sort**, **Group By** and **Filters for This View**."),
            GuideStep("For a gallery, give each note a cover property, choose the **Cards** layout, and set **Cover Image** to that property:",
                      example: "---\ncover: \"[[switching-threshold.png]]\"\n---"),
            GuideStep("**New View** adds another view of the same notes. The view's name at the top switches between them."),
            GuideStep("Embed a base in any note to show it there:", example: "![[Lectures.base]]")
        ],
        tips: ["A filter keeps only some notes: file.hasProperty(\"lecture\") keeps the notes that have a lecture property."])

    static let canvas = GuideTopicContent(
        systemImage: "rectangle.3.group",
        title: "Canvas",
        summary: "A canvas is a board of cards, notes, pictures and links that you arrange and connect. It is an Obsidian .canvas file.",
        steps: forPlatform(touch: [
            GuideStep("Choose **New** › **Canvas** and name it. It opens ready for arranging."),
            GuideStep("The bar at the bottom adds things: **Add Text Card**, **Add Note from Vault**, **Add Media from Vault**, **Add Web Link** " +
                      "and **Add Group**."),
            GuideStep("Drag a card to move it, or its handles to resize it. " +
                      "To connect two cards, select one and drag from the dot on its side to the other."),
            GuideStep("With cards selected, the bar above them colors, duplicates, deletes and arranges them. " +
                      "**Zoom to Fit** shows the whole board."),
            GuideStep("The **pencil** button switches between arranging the board and only looking at it.")
        ], mac: [
            GuideStep("Open a .canvas file from the sidebar to see it. " +
                      "Drag to move around and pinch to zoom; **Zoom to Fit** shows the whole board."),
            GuideStep("Making and editing canvases is on iPad and iPhone for now. A canvas made there, or in Obsidian, opens here.")
        ]))

    static let graphAndMap = GuideTopicContent(
        systemImage: "point.3.connected.trianglepath.dotted",
        title: "Graph and Map",
        summary: "The graph draws every note and the links between them. The map shows notes that have a location.",
        steps: [
            GuideStep(forPlatform(touch: "Tap the **graph** button at the top of the file list (in its **…** menu when the list is narrow), " +
                                         "or press ⇧⌘G with a keyboard. The graph opens in a tab of its own.",
                                  mac: "Click the **graph** button above the file list, choose View › **Graph View**, or press ⇧⌘G. " +
                                       "The graph opens in a tab of its own.")),
            GuideStep(forPlatform(touch: "Tap a note in the graph to open it in the tab beside the graph, or on the other side of a split. " +
                                         "The graph stays open.",
                                  mac: "Click a note in the graph to open it in the tab beside the graph, or on the other side of a split. " +
                                       "The graph stays open.")),
            GuideStep(forPlatform(touch: "Touch and hold a tag in the **Tags** panel, or a folder in the file list, and choose **Show in Graph** " +
                                         "to see only its notes. The filter at the top of the graph takes tag:#name too.",
                                  mac: "Right-click a tag in the **Tags** panel, or a folder in the file list, and choose **Show in Graph** " +
                                       "to see only its notes. The filter at the top of the graph takes tag:#name too.")),
            GuideStep("The right sidebar's **Graph** panel shows only the open note and its neighbours: open it from the note's " +
                      "**More** menu, or with ⌥⌘G. Its **graph** button shows the note in the whole graph."),
            GuideStep("Give a note a location property to put it on the map:", example: "---\nlocation: \"46.5191, 6.5668\"\n---"),
            GuideStep(forPlatform(touch: "Run **Map view: Open map view**, or use the right sidebar's **Map** panel for the open note's places.",
                                  mac: "Choose View › **Map View**, or use the right sidebar's **Map** panel for the open note's places."))
        ])

    static let templatesAndDailyNotes = GuideTopicContent(
        systemImage: "calendar",
        title: "Templates and Daily Notes",
        summary: "A template is a note you copy into others. A daily note is one note per day, made from a template if you like.",
        steps: [
            GuideStep("Make a folder for templates, for example Templates, and write a note in it to copy from. " +
                      "It can fill in the title, date and time:",
                      example: "# {{title}}\nCreated {{date:YYYY-MM-DD}} at {{time}}"),
            GuideStep("Tell Graphite where it is: Settings › Templates › **Template folder location**."),
            GuideStep(forPlatform(touch: "In a note, choose **More** › **Insert** › **Template…** and pick one. It goes in at the cursor.",
                                  mac: "In a note, choose **Insert** › **Template…** in the toolbar, or Edit › **Insert Template…**, and pick " +
                                       "one. It goes in at the cursor.")),
            GuideStep(forPlatform(touch: "For today's note, choose **New** › **Today's Daily Note**. It opens the note, or makes it first.",
                                  mac: "For today's note, open the menu of the **New Note** button › **Today's Daily Note**, or Go › **Today's " +
                                       "Daily Note**.")),
            GuideStep("Settings › Daily Notes sets the folder, the date format, the template, and **Open Daily Note on Startup**.")
        ])
}
