# Notebook-style library and choosing what to create: TODO

Created: 2026-10-19.

Status: first round built on the branch `notebook-library` (2026-10-19); see each part. Checked with automated tests on macOS; not yet tried in the app on an iPad or with Apple Pencil. Proposal from the owner, with Goodnotes 6 screenshots as the reference (folder grid, document grid with page previews, the New menu, the New Notebook sheet with its size and orientation menu, and the template sections).

## First: folders that look like Finder's (owner's top priority, 2026-10-21)

Before the other open items of this file. The look is Apple's own wherever an API gives it (see "The look is Apple's" below).

- [ ] Customize a folder exactly as Finder does on macOS 27 (owner, 2026-10-21, with screenshots of Finder's popover). The popover from a folder's menu shows, from top to bottom:
  - a large preview of the folder as it will look, with its name under it;
  - one row of round color swatches: no color (a crossed-out tag), the folder's default, the tag colors, and a "+" for more; the chosen one is ringed;
  - a scrolling grid of symbols in sections with headings ("People", "Animals & Nature", …), each symbol drawn engraved on the folder when chosen;
  - two buttons at the bottom: Clear (dimmed when there is nothing to clear) and Emoji, which opens the system emoji picker; a chosen emoji is drawn in color on the folder and shown on the Emoji button.
  Copy Apple's own drawing wherever a public API gives it, instead of imitating it: on the Mac, `NSWorkspace.shared.icon(forFile:)` returns Finder's icon for a folder, including a color and symbol set in Finder, so the Mac tile should use it, and Graphite's own style only where Finder has none. iOS and iPadOS have no API for the Files app's folder icons, so there the tile keeps the SF Symbol `folder.fill` with the symbol or emoji engraved on it, matched to Files' proportions and colors side by side in screenshots. Find out first whether Finder's color and symbol are stored somewhere an app can read (extended attributes or tags) so the two stay the same on the Mac. File tiles follow the same rule: the system's icon or Quick Look thumbnail where there is one.
- [ ] The same look in Finder and in Graphite, both ways (owner, 2026-10-21): a color, symbol or emoji chosen in Graphite shows on the folder in Finder, and one chosen in Finder shows in Graphite, on the Mac and, through iCloud Drive, on the iPad. Needs: where Finder stores its folder color and symbol (a tag color is the `com.apple.metadata:_kMDItemUserTags` attribute; the symbol's storage is unknown), whether iCloud Drive carries it, and whether iOS can read it. Graphite's `.obsidian/graphite-folder-styles.json` stays the fallback wherever the Finder data cannot be read or written.
- [ ] Custom pictures as folder icons, as Finder shows them (owner's screenshot: an "EPFL" folder with the school's logo, app folders with the app's icon on a blue folder). Finder keeps a custom icon in the folder's hidden `Icon\r` file, written on the Mac with `NSWorkspace.shared.setIcon(_:forFile:options:)` and read with `NSWorkspace.shared.icon(forFile:)`. In Graphite: choose a picture (Photos, Files, or an image in the vault) for a folder, show it on the folder tile, write it as Finder's custom icon on the Mac, and on the iPad read the icon Finder wrote if `Icon\r` syncs and can be read there; otherwise keep the picture beside the style in the vault.
- [ ] An icon maker like Image2icon (owner, 2026-10-21; [img2icnsapp.com](https://img2icnsapp.com), proprietary, so nothing of it can be copied): drop or pick a picture, choose a template (the picture placed on the folder as Finder draws app folders, or the picture as the whole icon), move and zoom it, choose a background, preview it at Finder's sizes, then apply it to the folder. Built on Graphite's own drawing with public APIs only; the result is the custom icon of the item above.

## Request

Offer, as an option the user chooses, a library that looks like Goodnotes or Notability: folders as large colored folder tiles and files as tiles that show a preview of their content. It is meant for people who think in Apple Pencil and notebooks more than in Markdown, and is especially useful on the iPad.

When creating something, Graphite should ask what the user wants, in the way Goodnotes does: a notebook (PDF) or a note (Markdown). Inside a note, the user can also create a notebook, and then chooses whether it lives in the folder structure as its own file or is embedded in the note.

The aim: one app for someone who today uses Goodnotes or Notability and Obsidian side by side. Graphite is the bridge, with ordinary files underneath and a familiar notebook experience on top. This joins [Goodnotes-and-Notability-import-todo.md](Goodnotes-and-Notability-import-todo.md), which brings the existing notebooks across.

## What Graphite had before this work (checked in the code on 2026-10-19)

- The vault is browsed in `VaultSidebar` as a tree list, Obsidian style. There is no grid presentation of folders or files, no folder color or symbol, and no file preview in the browser.
- `CreationKind` offers New Note, New Notebook, New Base and New Canvas (`GraphiteCommands`, the sidebar). Each is a separate command; nothing asks which kind the user wants.
- `CreateDocumentSheet` (in `GraphiteRootView.swift`) creates a notebook with: a name, eight paper templates (`PaperTemplate`: blank, dotted, grid, ruled, Cornell, engineering, isometric, music), paper spacing and colors from Settings, A4, US Letter or a custom size, landscape, and a page count. The templates are listed by name, without a picture of each.
- `PDFThumbnailRenderer` renders PDF page thumbnails for the pages sidebar; it is not used for the vault browser.
- Drawings (PNG, SVG, PDF) can be created inside a note and are embedded at the cursor. A PDF embedded in a note can be annotated in place. A new paged notebook cannot be created from inside a note.
- Bookmarks (`GraphiteCore/Bookmarks.swift`) exist and read Obsidian's bookmarks; they are the natural source of "Favorites".
- No document scanning (`VNDocumentCameraViewController` is not used anywhere).

## Decisions taken when building started (2026-10-19)

The owner chose the first two; the rest are defaults taken to start building, each easy to change:

- Built on the branch `notebook-library`, in its own worktree, apart from the SOLID audit work.
- Folder colors and symbols are saved in the vault, in the optional file `.obsidian/graphite-folder-styles.json`. Obsidian ignores it; deleting it only resets the colors.
- The List or Library choice is per device.
- Where the library shows (owner, 2026-10-19): a window is either Goodnotes-shaped or Obsidian-shaped, as Settings chooses, never a library beside a file tree. In Library mode on the iPad and the Mac the file tree's sidebar folds away, a house button leads the tab bar, and the library is the home that covers the first side until a tab is chosen; documents open as tabs. On the iPhone, where the sidebar is the whole screen, the sidebar's file list becomes the library.
- The look is Apple's, not Goodnotes' (owner, 2026-10-19): Files' grid, the system folder symbol in system colors with the folder's symbol engraved as the Finder does, plain toolbar buttons, no star on every tile.
- The first page is the cover; no separate cover page yet.
- Undoing an inserted notebook removes the embed or link and keeps the new PDF.
- "New Linked Note", scanning, photos and quick record are not built in this round.

## Rules every part must follow

- Ordinary files stay authoritative (`OBJECTIVE.md`, `RULES.md`). A notebook is a PDF, a note is Markdown. No new document format, no required sidecar, no application database as the only copy of anything.
- Previews and thumbnails are disposable derived data stored outside the vault, rebuilt when missing, with a size budget.
- The library must stay fast on a 100,000-file vault: lazy grid, previews rendered only for visible tiles, off the main thread, cancelled when scrolled away, never one task per file. Cloud placeholders are not downloaded just to make a preview; they show a kind icon and the cloud state.
- Every control does something real. The New menu lists only kinds Graphite can create; scanning, for example, appears once it exists.
- Screen space over chrome: fold the view choice and the New button into existing bars, check iPad portrait and iPhone.
- Both presentations are views of the same vault. Switching never moves, renames or rewrites a file.
- Keep what already works in notes exactly as it is (owner, 2026-10-19): creating a drawing (PNG, SVG, PDF) inside a note, embedded at the cursor, and writing on a PDF embedded in a note in place. Part 6 adds paged notebooks beside these; it does not replace, rename, move or hide them, and their regression tests must keep passing.

## Part 1: the library presentation choice

- [x] A choice per device: a Library | List switch in the library's top row and beside the List sidebar's panels, and Settings › Appearance › Files. In Library mode on the iPad and the Mac there is no sidebar and no sidebar button (owner, 2026-10-19); the library's top row has Settings and Find a File buttons, and Vaults in its options menu.
- [x] Library view of one folder at a time, with a back button and the folder's name. Opening a folder tile enters it; a file opens as a tab on the iPad and the Mac, and the house button brings the library back; on the iPhone it opens in place.
- [x] Sort (the vault's sort order: name, modified, created) and filter (all, notebooks and PDFs, notes, pictures and drawings, canvases and bases).
- [x] Favorites are Obsidian's bookmarks: Bookmark in an item's menu adds or removes it, and a bookmarked item shows a small star by its date. Not built: a Favorites section of its own in the library (the Bookmarks panel lists them).
- [x] Layout: adaptive columns; tiles keep the page's aspect ratio. Not checked yet: four columns on a landscape iPad, two on the iPhone.
- [ ] Accessibility: each tile reads as name, kind and date, and its menu is the context menu; the favorite state is read by the star button only. Not checked with VoiceOver or at the largest text sizes.

## Part 2: folder tiles

- [x] A folder tile: the system folder symbol in its color, an optional SF Symbol engraved on it, the name, the date, and a small star when bookmarked; its menu on touch and hold.
- [x] Choosing the color (10 system colors) and symbol (16) from the folder's menu (Folder Look). Not checked yet in dark mode on a device.
- [x] Stored in the vault in `.obsidian/graphite-folder-styles.json` (decision above); a folder without a style is blue.
- [x] Renames, moves and deletions made in Graphite carry the folder's style with them. Renames made in another app lose it.

## Part 3: file tiles with previews

- [x] PDF: the first page with its ink annotations, through PDFKit, edged with a hairline as Files does. A chosen cover page is not built.
- [x] Image: scaled down with ImageIO while decoding.
- [x] Drawing: PNG drawings are images; SVG drawings show a picture symbol (not drawn yet).
- [x] Markdown: the first 4 KB drawn as a page of reading view (headings in their sizes, wrapped text with bold, italic and code, nested lists and tasks, quotes, callouts, code blocks, rules, the first picture where it sits), scaled down to the tile; never the source.
- [ ] Canvas and Base: a kind symbol for now.
- [x] Other files: a kind symbol (not the system's icon for the type).
- [x] Under each tile: name and modification date; touch and hold (or a secondary click) opens the file tree's own menu: new tab, other side, rename, move, copy, share, bookmark, delete, ….
- [x] Previews follow changes: a file listed with a new date or size gets a new preview. External changes reach the library when the workspace lists the vault again (`directoryVersion`).
- [x] Drag and drop: tiles onto folder tiles to move them; files from Files or the Finder into the grid to import them.
- [ ] Selection mode for several tiles.
- [x] Cloud files not downloaded are not read; their tile says "In iCloud".

## Part 4: one New menu that asks what to create

- [x] One New button in the library and in the iPad and iPhone sidebar, opening `NewItemPicker`: Notebook and Note as large choices, then Canvas, Base, Today's Daily Note (each while its core plugin is on), Import and Folder. The Mac's sidebar keeps its menu (a click makes a note), without Import.
- [ ] Later entries, each once the feature exists: Scan Documents, Image from Photos, Take Photo, Quick Record.
- [x] Notebook first in Library mode, Note first in List mode. ⌘N still makes a note.
- [x] The new file goes into the folder shown, or the vault's location for new files.

## Part 5: the New Notebook sheet

- [x] A large picture of the first page, drawn from the PDF the generator would write.
- [x] Name; empty means "Untitled Notebook", made unique in the folder.
- [ ] Cover: not built; the first page is the cover (decision above).
- [x] Paper as a grid of pictures in sections: Essentials (blank, dotted, squared, ruled narrow, ruled wide), Study (Cornell, engineering, isometric), Music. Planners and more templates are not built.
- [x] Color dots under each paper. The colors are Graphite's four paper colors (white, ivory, yellow, gray); dark paper is not offered, since ink colors would need to change with it.
- [x] Ruled narrow (6 mm) and ruled wide (8 mm); the other spacings, line color and strength under Lines.
- [x] Size: A3, A4, A5, A6, A7 (iPhone), Letter, Tabloid and Custom, with Portrait and Landscape in the same menu; custom 1 to 40 inches.
- [x] Paper color menu.
- [ ] My Templates (a PDF or image as paper, kept in the vault), with Edit to reorder and hide.
- [x] The last paper and size are remembered; spacing and colors start as Settings has them.
- [ ] Not checked yet: the sheet at iPad portrait and landscape and on the iPhone.
- [ ] Handwriting language (only with handwriting recognition).

## Part 6: creating a notebook from inside a note

- [x] New Notebook in the keyboard toolbar's Attach menu, More › Insert, and the command palette ("Notebooks: Insert new notebook"). No slash command (the editor has none).
  - [x] Embedded in this note: saved where the note's attachments go, embedded at the cursor.
  - [x] In a folder: the note's folder or one above it, with a link (default) or an embed.
- [x] New Drawing stays exactly as it was, beside New Notebook.
- [x] Undo of the insert is the editor's undo of the inserted text; the PDF is kept. Not tested by an automated test.
- [ ] "New Linked Note" from a notebook.

## Part 7: choosing how you take notes

- Removed (owner, 2026-10-19). "How do you take notes?" only picked Library or List and the New menu's order, which the Library | List switch now decides directly; the question and its setting are gone.

## Verification

- [ ] Hosted tests: library grid model (sorting, filtering, favorites from bookmarks), preview cache budget and invalidation on file change, unique names, notebook size presets in points, template preview equal to the generated first page, insert-notebook placement for each attachment setting.
- [ ] A 100,000-file vault in the simulator: scrolling the library stays smooth, memory stays within budget, no preview work for tiles not shown, cloud placeholders not downloaded.
- [ ] On the owner's iPad with Apple Pencil: create a notebook from the library and from inside a note in both placements, write in it, reopen, and check the tile preview updates.
- [ ] The created PDFs open correctly in Preview, Files, Obsidian and Goodnotes; the notes' embeds and links work in Obsidian.
- [ ] Folder colors and symbols survive a restart, and (if stored in the vault) a second device.
- [ ] `Architecture.md`, `Coverage.md` and `Obsidian-mobile-gaps.md` updated as each part lands, with the checks that ran.

## Open questions

- Where folder colors and symbols are stored (Part 2, options A to C), and whether they should match an Obsidian plugin so Obsidian shows them too.
- Library presentation per device only, or also per vault or per folder (a course folder as a grid, a reference folder as a list)?
- A real cover page in the PDF, or the first page as the cover?
- Undo of "insert new notebook" in a note: keep the new PDF or delete it?
- Is "New Linked Note" from a notebook wanted?
- Should the library also be offered on the Mac, or only iPad and iPhone?
- Which later New menu entries come first: scanning, photos, or quick record?
