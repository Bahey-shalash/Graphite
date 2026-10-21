# iPhone Duo layout

Request (owner, 2026-10-21): get the app ready, layout-wise, for iPhone Duo, which Xcode 27.1 supports (iOS 27.1 SDK and a simulator for its poses and orientations). Apple's guidance is "Designing for iPhone Duo" in the Human Interface Guidelines.

Decisions:

- Graphite keeps one layout per size class. The outer display is a compact width (the phone layout) and the inner display a regular one. The system stands toolbars and the bottom bar on the side, and Graphite does not override where it puts them.
- On iOS a document's More commands go into the system's overflow menu, so the bar never shows two "•••" buttons. The Mac keeps its More menu.
- Graphite's own views follow a partly folded display through the system's division regions (iOS 27.1). The deployment target stays iOS 27.0, and the fold code does nothing before 27.1.

## 1. Layout on the Duo's displays and around the fold

- [x] Done 2026-10-21: the Tabs button is a numbered-square symbol titled "Tabs" (`TabCountLabel`), so the system moves it with the bar to the side instead of keeping it at the bottom of the outer display. Checked on the Duo simulator's outer display.
- [x] Done 2026-10-21: the phone's bottom bar is separate toolbar items and groups with flexible spacers. Finding a file, a new note and the tabs have a high visibility priority. Checked on the Duo simulator's outer display and on iPhone 17 Pro, where the bar looks as before.
- [x] Done 2026-10-21: on iOS, the note's, PDF's, canvas's and window's More commands are in the system's overflow menu (`ToolbarOverflowMenu`). Checked on the Duo simulator's outer display (one "•••" holding the Command Palette and the note's commands) and on iPad Pro 11-inch (the window's menu).
- [x] Done 2026-10-21: the policy for placing content around a fold (`DisplayFoldLayout` in Core: the largest region beside it, the split fraction on it, even columns over it), pinned by `DisplayFoldLayoutTests`.
- [x] Done 2026-10-21: in code, the two-sided workspace's divider is held on a fold, and the palettes, the notice banner and the Read Aloud floating player are placed beside it. Library mode's grid takes an even number of columns over a fold. Built for the Duo simulator; the folded behaviour is checked in section 2.
- [x] Done 2026-10-21: a phone's keyboard toolbar shows Undo and Redo only in a compact width, so the inner display, whose note toolbar has them, does not show two pairs. Built; checked in section 2.

## 2. Checks on the inner display and folded poses

- [ ] The inner display, open flat, in portrait and landscape: the sidebar and documents split, the tab bar and document controls, a note, a PDF with the Pencil palette, the library. Device Hub's pose buttons did not change the simulator's pose in the session that built section 1.
- [ ] Partly folded like a book: the workspace's divider on the fold with two sides, the quick switcher, the command palette, a notice banner and the Read Aloud player beside the fold, and the library grid's even columns.
- [ ] The keyboard toolbar on the inner display: Undo and Redo only in the note's toolbar.
- [ ] Decide what a single document does across the fold with the sidebar hidden (a note's reading column and a PDF page run across it today).
