import Foundation

/// The words of the Guide's first two sections, The Basics and Writing Notes. Every control
/// is named as the app labels it; where iPad and iPhone differ from the Mac, `forPlatform`
/// picks the words for this one.
enum GuideBasicsCopy {
    static let vaults = GuideTopicContent(
        systemImage: "folder",
        title: "Make or Open a Vault",
        summary: "A vault is the folder Graphite works in. " +
                 "Every note, PDF and picture in it is an ordinary file, and it can be a vault you already use in Obsidian.",
        steps: [
            GuideStep("When no vault is open, Graphite shows its welcome screen. " +
                      "Choose **Create New Vault** to start fresh, or **Open Folder as Vault** to use a folder you already have."),
            GuideStep(forPlatform(
                touch: "For a new vault, type a **Vault name**. It goes in Graphite's own folder, which the Files app shows; **Choose Folder…** " +
                       "puts it somewhere else, such as iCloud Drive.",
                mac: "For a new vault, type a **Vault name** and use **Choose Folder…** to say where it goes, such as iCloud Drive.")),
            GuideStep("To use an Obsidian vault, choose **Open Folder as Vault** and pick its folder, for example iCloud Drive › Obsidian › your " +
                      "vault. Graphite changes nothing until you edit."),
            GuideStep(forPlatform(
                touch: "To switch vaults, tap the vault's name at the top of the sidebar (on iPhone, the title of the file list) and pick " +
                       "another. **Manage Vaults…** adds or removes vaults.",
                mac: "To switch vaults, click the vault's name at the bottom of the sidebar and pick another. " +
                     "**Manage Vaults…** adds or removes vaults."))
        ],
        tips: ["**Remove from List** only forgets a vault: its folder and files stay where they are."])

    static let firstNote = GuideTopicContent(
        systemImage: "square.and.pencil",
        title: "Make Your First Note",
        summary: "A note is a Markdown file. Make one, give it a name, and start typing: Graphite saves as you go.",
        steps: [
            GuideStep(forPlatform(touch: "Tap **New** at the top of the sidebar, then **Note**.",
                                  mac: "Click **New Note** at the top of the sidebar, or press ⌘N.")),
            GuideStep("Type a **Note name** and choose **Create**. The note opens, ready for typing."),
            GuideStep("Write something. A heading, some bold text and a list look like this in Markdown:",
                      example: "# My first note\n\nSome **bold** text, and a list:\n\n- one\n- two"),
            GuideStep("There is no Save button to remember: every change is saved as you type."),
            GuideStep("Your note is now a file called My first note.md in the vault. Obsidian, the Files app and any text editor can open it.")
        ],
        tips: [
            "Other quick ways: **Create new note** in an empty tab, the Quick Switcher (type a name that does not exist yet, then create it), or " +
            "a folder's menu › **New Note**.",
            "Where new notes go: Settings › Files and Links › **Default Location for New Notes**."
        ])

    static let readAndWrite = GuideTopicContent(
        systemImage: "book",
        title: "Read, Write and See the Source",
        summary: "Graphite shows Markdown formatted as you type. You can also read a note without editing it, or see its plain text.",
        steps: [
            GuideStep("While you write, the note is in **Live Preview**: a heading looks like a heading, and its # marks show only on the line " +
                      "you are editing."),
            GuideStep(forPlatform(
                touch: "To read without editing, tap the **pencil** button at the top right of the note. Tap it again to write. " +
                       "With a keyboard, ⌘E does the same.",
                mac: "To read without editing, click the **pencil** button at the top right of the note, or press ⌘E (View › Read Note). " +
                     "Do it again to write.")),
            GuideStep("To see the plain Markdown, open the note's **More** menu (…) › **View** › **Source Mode**. " +
                      "**Live Preview** brings the formatting back."),
            GuideStep("To choose how notes open, go to Settings › Editor › **Default View for New Notes** and **Default Editing Mode**.")
        ])

    static let filesAndFolders = GuideTopicContent(
        systemImage: "folder.badge.gearshape",
        title: "Rename, Move and Delete",
        summary: "Every file and folder in the sidebar has a menu for renaming, moving, copying and deleting it.",
        steps: [
            GuideStep(forPlatform(touch: "Touch and hold a file or folder in the sidebar to see its menu.",
                                  mac: "Right-click a file or folder in the sidebar to see its menu.")),
            GuideStep("**Rename…** changes its name. If other notes link to it, Graphite offers to update those links."),
            GuideStep("**Move to…** picks another folder. You can also drag the file onto a folder."),
            GuideStep("**Make a Copy** duplicates it. **Delete** removes it after asking."),
            GuideStep(forPlatform(touch: "To make a folder, choose **New** › **Folder**.",
                                  mac: "To make a folder, open the menu of the **New Note** button › **New Folder**."))
        ],
        tips: ["Deleted files go to the system trash. Settings › Files and Links › **Deleted Files** can use Obsidian's .trash folder instead."])

    static let formatting = GuideTopicContent(
        systemImage: "bold.italic.underline",
        title: "Format Text",
        summary: "Type Markdown, or select words and use the formatting buttons. Live Preview shows the result as you type.",
        steps: forPlatform(touch: [
            GuideStep("Select words, then use the bar above the keyboard: **Bold**, **Italic**, **Strikethrough**, **Highlight**, **Code** and " +
                      "**Heading**."),
            GuideStep("Or type the Markdown yourself:", example: "**bold**  *italic*  ~~struck through~~  ==highlighted==  `code`"),
            GuideStep("More choices are in the note's **More** menu › **Format**: Comment, Color, lists, Table, Math Block and Callout."),
            GuideStep("With a keyboard: ⌘B bold, ⌘I italic, ⇧⌘H highlight, ⇧⌘X strikethrough, ⌃⌘1 to ⌃⌘6 for headings.")
        ], mac: [
            GuideStep("Select words, then use the **Format** menu in the note's toolbar: Bold, Italic, Strikethrough, Highlight, Code, Heading " +
                      "and more."),
            GuideStep("Or type the Markdown yourself:", example: "**bold**  *italic*  ~~struck through~~  ==highlighted==  `code`"),
            GuideStep("Right-click selected text for **Format**, **Paragraph** (lists, headings, quote) and **Insert**.")
        ]),
        tips: ["**Format** › **Color** colors text. It writes ~={#hex}text=~, which the Colors plugin for Obsidian reads too."])

    static let links = GuideTopicContent(
        systemImage: "link",
        title: "Link Notes Together",
        summary: "A link between two notes is their name in double brackets. Links turn a folder of notes into something you can walk through.",
        steps: [
            GuideStep(forPlatform(touch: "Type [[ and start typing a note's name, then pick it from the suggestions.",
                                  mac: "Type the note's name between double brackets."),
                      example: "[[Fourier Series]]"),
            GuideStep("To link to a heading or a single paragraph inside a note, add # or #^ after the name:",
                      example: "[[Fourier Series#Coefficients]]"),
            GuideStep("Tap (on the Mac, click) a link to open it. ⌘ with the click opens it in a new tab."),
            GuideStep("A link to a note that does not exist yet makes that note when you follow it."),
            GuideStep(forPlatform(
                touch: "To see which notes link to this one, open the right sidebar (**Sidebar** at the top right on iPad, **More** › **Links and " +
                       "Outline** on iPhone) and choose **Backlinks**.",
                mac: "To see which notes link to this one, open the right sidebar with **Sidebar** at the top right of the note and choose " +
                     "**Backlinks**."))
        ],
        tips: ["Backlinks also lists **Unlinked mentions**: places a note's name appears without a link. **Link** turns one into a link."])

    static let embeds = GuideTopicContent(
        systemImage: "rectangle.on.rectangle",
        title: "Embed Notes, Sections and PDFs",
        summary: "An ! before a link shows the file itself inside your note. It is the original, not a copy.",
        steps: [
            GuideStep("Embed a whole note:", example: "![[Fourier Series]]"),
            GuideStep("Embed one section, or one paragraph that has a block " +
                      "ID:", example: "![[Fourier Series#Coefficients]]\n![[Fourier Series#^key-idea]]"),
            GuideStep("Embed a PDF at a page, with its viewer's height in points. The viewer scrolls and zooms inside the note:",
                      example: "![[Lecture 3.pdf#page=12&height=420]]"),
            GuideStep("Embed an image at a width:", example: "![[circuit.png|400]]"),
            GuideStep("Embed a base to show a live table or gallery of notes:", example: "![[Lectures.base]]")
        ],
        tips: [
            "An embedded note is shown in full. Change the original and every note that embeds it shows the change.",
            "Embeds go one level deep: a note embedded inside an embedded note shows as a link."
        ])

    static let listsAndTasks = GuideTopicContent(
        systemImage: "checklist",
        title: "Lists and Tasks",
        summary: "Bullets, numbered lists and checkboxes are a character or two at the start of a line.",
        steps: [
            GuideStep("Start a line with - for a bullet, 1. for a numbered list, or - [ ] for a task:",
                      example: "- milk\n1. first step\n- [ ] read chapter 4\n- [x] hand in homework"),
            GuideStep("Tap (on the Mac, click) a task's checkbox to tick it, in Live Preview, in reading view and inside embeds."),
            GuideStep(forPlatform(
                touch: "The bar above the keyboard has **Bulleted list**, **Numbered list**, **Task**, **Indent** and **Outdent**. " +
                       "With a keyboard, ⌘L ticks a task.",
                mac: "**Format** › **Bulleted List**, **Numbered List** and **Task** in the note's toolbar make them.")),
            GuideStep("To find unfinished tasks in the whole vault, search for task-todo: followed by any words:", example: "task-todo: homework")
        ])

    static let tables = GuideTopicContent(
        systemImage: "tablecells",
        title: "Tables",
        summary: "Tables are edited in place: tap a cell and type, or use a cell's menu to add and move rows and columns.",
        steps: [
            GuideStep(forPlatform(touch: "Choose **More** › **Format** › **Table**, or run **Insert table** in the Command Palette.",
                                  mac: "Choose **Format** › **Table** in the note's toolbar, or run **Insert table** in the Command Palette.")),
            GuideStep(forPlatform(touch: "Tap a cell to type in it. With a keyboard, Tab and ⇧Tab move between cells.",
                                  mac: "Click a cell to type in it.")),
            GuideStep(forPlatform(touch: "Touch and hold a cell for **Row** and **Column**: add, move, align or delete them.",
                                  mac: "Right-click a cell for **Row** and **Column**: add, move, align or delete them.")),
            GuideStep("**Edit Source** shows the table's Markdown, which looks like this:",
                      example: "| Signal | Coefficients |\n| --- | --- |\n| x(t - t0) | a_k e^(-jkω0t0) |")
        ])

    static let calloutsMathAndCode = GuideTopicContent(
        systemImage: "function",
        title: "Callouts, Math and Code",
        summary: "Boxes that stand out, formulas written in LaTeX, and code with colors, all in plain Markdown.",
        steps: [
            GuideStep("A callout is a quote with a type, such as note, tip, warning, example or question:",
                      example: "> [!tip] Remember\n> Only the odd harmonics survive."),
            GuideStep("Add - after the type and the callout starts folded, to hide an answer until you open it:",
                      example: "> [!example]- Solution\n> a_0 = 1/2"),
            GuideStep("Math is LaTeX: between $ inside a line, between $$ on lines of its own:",
                      example: "The average is $a_0$.\n\n$$\nx(t) = \\sum_k a_k e^{jk\\omega_0 t}\n$$"),
            GuideStep("Code goes between three backticks, with its language for colors:", example: "```python\nprint(\"hello\")\n```"),
            GuideStep(forPlatform(
                touch: "**More** › **Format** has **Callout** and **Math Block**. Touch and hold in the text for **Insert** › **Code Block**.",
                mac: "**Format** has **Callout** and **Math Block**. Right-click in the text for **Insert** › **Code Block**."))
        ],
        tips: ["Settings › Editor › **Code Theme** picks the colors of code blocks."])

    static let imagesAndAttachments = GuideTopicContent(
        systemImage: "photo",
        title: "Pictures and Files",
        summary: "Add photos, pictures and other files to a note. Each is saved in the vault and embedded where the cursor is.",
        steps: [
            GuideStep(forPlatform(
                touch: "Use the **Attach** menu above the keyboard: **Take Photo**, **Photo Library**, **Choose File** or **New Notebook**.",
                mac: "Use **Insert** › **Attachment…** in the note's toolbar.")),
            GuideStep("You can also paste a picture, or drop a file onto the note."),
            GuideStep("Graphite saves the file and adds an embed for it:", example: "![[Pasted image 20261021120000.png]]"),
            GuideStep("Choose where these files go in Settings › Files and Links › **Default Location for New Attachments**.")
        ])

    static let propertiesAndTags = GuideTopicContent(
        systemImage: "tag",
        title: "Properties and Tags",
        summary: "Properties are facts about a note, such as its course or date. Tags group notes across folders.",
        steps: [
            GuideStep("Properties are the lines between --- at the very top of a note:",
                      example: "---\ncourse: VLSI 3\nlecture: 3\ntags:\n  - cmos\n---"),
            GuideStep("Once a note has them, they show as a panel. " +
                      "**Add Property** adds one; a property's menu has **Change Type** and **Remove Property**."),
            GuideStep("Tag a note by writing #tag anywhere in its text, or by listing tags in its tags property."),
            GuideStep("The left sidebar's **Tags** and **Properties** panels list every tag and property in the vault. " +
                      "Choose one to find the notes that have it.")
        ],
        tips: ["Bases and the Map use properties: a base can show them as columns, and a location property puts a note on the map."])

    /// The words for this platform: iPad and iPhone are used by touch, the Mac by clicks and menus.
    static func forPlatform<Words>(touch: Words, mac: Words) -> Words {
        #if os(macOS)
        mac
        #else
        touch
        #endif
    }
}
