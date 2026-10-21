import Foundation

/// The words of the Guide's Handwriting and PDFs section, which only iPad and iPhone show, and
/// of its Studying section.
enum GuidePencilCopy {
    private static func forPlatform<Words>(touch: Words, mac: Words) -> Words {
        GuideBasicsCopy.forPlatform(touch: touch, mac: mac)
    }

    static let drawings = GuideTopicContent(
        systemImage: "pencil.tip.crop.circle",
        title: "Draw in a Note",
        summary: "Put a drawing anywhere in a note: a derivation, a circuit, a sketch. It is saved as an ordinary picture.",
        steps: [
            GuideStep("While writing, put the cursor where the drawing should go and tap **Draw**, in the toolbar or in the bar above the " +
                      "keyboard. With Apple Pencil, double-tap or squeeze it."),
            GuideStep("Draw. The canvas is as wide as the note and grows downward as you write."),
            GuideStep("Tap **Insert**. Graphite saves the drawing and embeds it in the note. **Cancel** leaves the note as it was."),
            GuideStep("To change it later, tap the drawing's **Edit** button. On a photo, **Draw on Image** draws on it."),
            GuideStep("The canvas's **Drawing Options** menu has **Paper**, **Add Image**, **Draw with Finger** and **Export a Copy**.")
        ],
        tips: [
            "Settings › Pencil Drawings › **Save Drawings As**: PNG keeps every brush exactly, PDF and SVG stay sharp at any size.",
            "On iPhone, turn on **Draw with Finger** in **Drawing Options**."
        ])

    static let pencilTools = GuideTopicContent(
        systemImage: "slider.horizontal.3",
        title: "Your Pencil Tools",
        summary: "Choose how the tools look, and how Apple Pencil and your hand behave on the page.",
        steps: [
            GuideStep("Settings › Pencil Drawings › Pencil Tools › **Tools**: **Floating Palette** (the system's, which you can move or make " +
                      "smaller) or **Fixed Bar** (in the tab bar, like Goodnotes). On iPhone the palette is always used."),
            GuideStep("Tap the tool in use again to change its width, opacity or color."),
            GuideStep("**Hold to Make a Shape**: draw a line, circle, triangle or rectangle and keep the Pencil still at the end. " +
                      "It becomes a clean shape."),
            GuideStep("**Palm Rejection** keeps a hand resting on the page from scrolling, zooming or tapping while Apple Pencil writes."),
            GuideStep("**Double-Tap or Squeeze to Draw in Notes** starts a drawing from a note where the cursor is.")
        ],
        tips: ["The palette's **More** (…) menu has **Select Ink**, to move, resize or recolor strokes, the **Laser Pointer** and **Draw Shapes**."])

    /// The Mac reads PDFs and changes their pages; writing on them is on iPad and iPhone.
    static var annotatingPDFs: GuideTopicContent {
        GuideTopicContent(
            systemImage: "doc.richtext",
            title: forPlatform(touch: "Annotate PDFs", mac: "PDFs"),
            summary: forPlatform(touch: "Write on slides, papers and textbooks. Your ink is saved inside the PDF, so every PDF app shows it.",
                                 mac: "Read PDFs, bookmark them, and add, move or remove their pages."),
            steps: forPlatform(touch: [
                GuideStep("Bring a PDF in with **New** › **Import**, or put it in the vault's folder with the Files app."),
                GuideStep("Open it and tap the **pencil** button at the top right to write. To write with a finger, choose **More** › **Draw with Finger**."),
                GuideStep("Select text to **Highlight** it (pick a color), **Underline** it, **Strikethrough** it, **Copy as Quote**, or quote it in a note."),
                GuideStep("**Show Pages** (the grid button) lists the pages. A page's menu bookmarks, rotates, duplicates, exports or deletes it."),
                GuideStep("**Add Page** inserts blank, dotted, grid, ruled, Cornell and other paper, or pages from another PDF.")
            ], mac: [
                GuideStep("Put a PDF in the vault's folder with the Finder. It appears in the sidebar."),
                GuideStep("**Show Pages** lists the pages. A page's menu bookmarks, rotates, duplicates, exports or deletes it."),
                GuideStep("**Add Page** inserts blank, dotted, grid, ruled, Cornell and other paper, or pages from another PDF."),
                GuideStep("Writing and highlighting on PDFs is on iPad and iPhone. Ink written there shows here, as in any PDF app.")
            ]),
            tips: ["Show one page of a PDF inside a note with ![[Slides.pdf#page=3]]."])
    }

    static let notebooks = GuideTopicContent(
        systemImage: "book.closed",
        title: "Handwritten Notebooks",
        summary: "A notebook is a PDF with real paper on its pages: blank, dotted, squared, ruled, Cornell and more.",
        steps: [
            GuideStep("Choose **New** › **Notebook**."),
            GuideStep("Name it, pick its **Size**, **Color** and number of **Pages**, and a paper from **Paper Templates**."),
            GuideStep("Tap the checkmark to make it, then write. **Add Page** adds pages with the same or another paper."),
            GuideStep("From inside a note, **Insert** › **New Notebook…** makes one without leaving the note.")
        ],
        tips: ["Settings › Pencil Drawings › **Notebook Paper** sets the line spacing and colors of new notebooks."])

    static let recording = GuideTopicContent(
        systemImage: "mic",
        title: "Record a Lecture",
        summary: "Record audio or video while you take notes. The recording keeps going as you write, draw and change files.",
        steps: [
            GuideStep(forPlatform(
                touch: "Tap the **microphone** button at the top right (**Record Lecture**) and choose **Record Audio** or **Record Video**. " +
                       "On iPhone, run **Audio recorder: Start recording** in the Command Palette.",
                mac: "Click the **microphone** button at the top right (**Record Lecture**) and choose **Record Audio** or **Record Video**.")),
            GuideStep("Keep working. The timer at the top shows the recording while you move between notes and PDFs."),
            GuideStep("Open the timer for **Pause**, **Resume**, **Stop and Save** or **Cancel**."),
            GuideStep("The recording is saved with the open note's attachments as an ordinary .m4a or .mp4 file, named after the note and the time."),
            GuideStep("To embed it in the note when you stop, turn on Settings › Audio Recorder › **Embed Recordings in the Current Note**.")
        ])

    static let readAloud = GuideTopicContent(
        systemImage: "speaker.wave.2",
        title: "Read Aloud",
        summary: "Have notes and PDFs read to you with a natural voice, each word highlighted as it is read, entirely on this device.",
        steps: [
            GuideStep("Turn it on: Settings › Core Plugins › **Read Aloud**."),
            GuideStep("In a note's **More** menu › **Read Aloud**: **Read Document**, **Choose Section…**, **Read Selection** or **Read From " +
                      "Here**."),
            GuideStep("In a PDF, the same menu has **Read This Page**, **Choose Page Range…** and more."),
            GuideStep("The player has play and pause, the previous and next sentence, the speed, and a list of the sections."),
            GuideStep("For the most natural voices, go to Settings › Read Aloud › **High Quality Voices**, **Download** one, then **Use This " +
                      "Voice**.")
        ])
}
