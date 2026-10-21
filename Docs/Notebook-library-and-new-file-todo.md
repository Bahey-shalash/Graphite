# Notebook-style library and choosing what to create: TODO

Created: 2026-10-19.

Status: first round built on the branch `notebook-library` (2026-10-19); see each part. Checked with automated tests on macOS; not yet tried in the app on an iPad or with Apple Pencil. Proposal from the owner, with Goodnotes 6 screenshots as the reference (folder grid, document grid with page previews, the New menu, the New Notebook sheet with its size and orientation menu, and the template sections).

## First: folders that look like Finder's (owner's top priority, 2026-10-21)

Before the other open items of this file. The look is Apple's own wherever an API gives it (see "The look is Apple's" below).

- [x] Customize a folder exactly as Finder does on macOS 27 (owner, 2026-10-21, with screenshots of Finder's popover). Built on the branch `finder-folder-icons` (2026-10-21): Customize Folder… in a folder tile's menu opens `FolderCustomizationPopover` (a sheet on the iPhone); see "Decisions for the Finder folder looks" below. Checked with automated tests on macOS and in the iPad simulator only. The popover from a folder's menu shows, from top to bottom:
  - a large preview of the folder as it will look, with its name under it;
  - one row of round color swatches: no color (a crossed-out tag), the folder's default, the tag colors, and a "+" for more; the chosen one is ringed;
  - a scrolling grid of symbols in sections with headings ("People", "Animals & Nature", …), each symbol drawn engraved on the folder when chosen;
  - two buttons at the bottom: Clear (dimmed when there is nothing to clear) and Emoji, which opens the system emoji picker; a chosen emoji is drawn in color on the folder and shown on the Emoji button.
  Copy Apple's own drawing wherever a public API gives it, instead of imitating it: on the Mac, `NSWorkspace.shared.icon(forFile:)` returns Finder's icon for a folder, including a color and symbol set in Finder, so the Mac tile should use it, and Graphite's own style only where Finder has none. iOS and iPadOS have no API for the Files app's folder icons, so there the tile keeps the SF Symbol `folder.fill` with the symbol or emoji engraved on it, matched to Files' proportions and colors side by side in screenshots. Find out first whether Finder's color and symbol are stored somewhere an app can read (extended attributes or tags) so the two stay the same on the Mac. File tiles follow the same rule: the system's icon or Quick Look thumbnail where there is one.
- [ ] The same look in Finder and in Graphite, both ways (owner, 2026-10-21). Built on the Mac (2026-10-21, see "Where Finder keeps a folder's look" below): Graphite reads Finder's look on every platform and writes it on the Mac, and the Mac's tile is the system's own icon wherever Finder draws the look. Not verified: iCloud Drive carrying it to the iPad, and the iPad reading it (the same code reads it there, untried on a device). Owner's description: a color, symbol or emoji chosen in Graphite shows on the folder in Finder, and one chosen in Finder shows in Graphite, on the Mac and, through iCloud Drive, on the iPad. Needs: where Finder stores its folder color and symbol (a tag color is the `com.apple.metadata:_kMDItemUserTags` attribute; the symbol's storage is unknown), whether iCloud Drive carries it, and whether iOS can read it. Graphite's `.obsidian/graphite-folder-styles.json` stays the fallback wherever the Finder data cannot be read or written.
- [x] Custom pictures as folder icons, as Finder shows them. Built 2026-10-21: the popover's Picture menu takes a picture from Photos, Files or the vault; it is kept as a PNG in `.obsidian/graphite-folder-icons/` and named in the style file; on the Mac it is also written as Finder's custom icon, and a custom icon set in Finder shows in the library. Not built: reading Finder's `Icon\r` on the iPad (the picture beside the style is what the iPad shows). Owner's description: (owner's screenshot: an "EPFL" folder with the school's logo, app folders with the app's icon on a blue folder). Finder keeps a custom icon in the folder's hidden `Icon\r` file, written on the Mac with `NSWorkspace.shared.setIcon(_:forFile:options:)` and read with `NSWorkspace.shared.icon(forFile:)`. In Graphite: choose a picture (Photos, Files, or an image in the vault) for a folder, show it on the folder tile, write it as Finder's custom icon on the Mac, and on the iPad read the icon Finder wrote if `Icon\r` syncs and can be read there; otherwise keep the picture beside the style in the vault.
- [x] An icon maker like Image2icon. Built 2026-10-21 (`FolderIconMaker`, see "The icon maker" below); Remove Background, Export's saved file and the Mac's folder drop not tried in the app. Owner's description (2026-10-21; [img2icnsapp.com](https://img2icnsapp.com), proprietary, so nothing of it can be copied): drop or pick a picture, choose a template (the picture placed on the folder as Finder draws app folders, or the picture as the whole icon), move and zoom it, choose a background, preview it at Finder's sizes, then apply it to the folder. Built on Graphite's own drawing with public APIs only; the result is the custom icon of the item above.

## Decisions for the Finder folder looks (2026-10-21, owner away)

Taken while building the first section above, each easy to change:

- The popover replaces the old Folder Look menu. Its color row is: No Color (the crossed-out tag) and Finder's seven tag colors (red, orange, yellow, green, blue, purple, gray). The "+" for any color, built first with the system color picker, was taken out the same day: Finder and the Files app can only show tag colors, and the owner ruled that Graphite and Files must never show a folder in different colors (bug report of 2026-10-21). Colors stored before (pink, indigo, teal, `#RRGGBB`) are written to the folder as the nearest tag color and ring that swatch. The "folder's default" of the owner's description is the No Color swatch: a folder without a color is drawn in the default folder color, so a second default swatch would do the same thing and was left out.
- Every choice applies at once, as Finder applies it; there is no Done button. Choosing the chosen symbol again takes it off.
- A folder has a symbol or an emoji, not both; choosing one replaces the other. When a file somehow has both, the symbol is drawn, as Finder does.
- The symbols are 171 SF Symbols in Finder's seven sections, all present on macOS 27 (checked by `FolderSymbolCatalogTests`); Finder's exact list is not public.
- Emoji: on iOS the Emoji button is a text field drawn as nothing that asks for the emoji keyboard (`textInputMode` is the input mode whose language is "emoji", the usual way, as no public switch exists); on the Mac a click opens the Character Viewer into a field drawn as nothing. The first emoji typed is taken (`FolderMark.firstEmoji`). A hardware keyboard on the iPad shows no software keyboard; the globe key's emoji picker still types into the field.
- Stored format: `.obsidian/graphite-folder-styles.json` keeps `color` (a name, `#RRGGBB` for any other color, or `none`), `symbol` and the new `emoji`. "No color" is written as `none` rather than left out, so the build already on TestFlight still reads the entry (as an unknown color, drawn blue) and keeps the symbol. Files written before keep reading the same (`FolderStyleListTests.testTheEarlierFormatStillReads`).
- Pictures: a folder's picture is a third kind of mark beside a symbol and an emoji (choosing one replaces the other). It is kept as a PNG of 512 by 512 pixels in `.obsidian/graphite-folder-icons/`, named after a hash of its content (the same picture is kept once), referenced from the style file as `"picture"` with `"pictureLayout"` (`onFolder` or `wholeIcon`). Only files in that folder are accepted as a folder's picture, so a hand-edited style file cannot point a tile at a note's picture. Pictures no style uses are deleted when the styles change, only those named as Graphite names them; a file put there by hand stays. The folder syncs with the vault wherever `.obsidian` syncs (iCloud Drive does; Obsidian Sync syncs it only with its "other file types" setting).
- Two layouts, as the owner asked: the picture placed on the folder (rounded, 42% of the folder's width, in the middle of its body, as Finder draws app folders) or the picture as the whole icon. A picture on a folder takes the folder's color in Graphite; on the Mac, Finder's custom icon is drawn on the system's own blue folder (no public API tints it), so a picture on a colored folder is drawn by Graphite in the library.
- On the Mac a picture is also written as Finder's custom icon (`NSWorkspace.setIcon`, the folder's picture composed on the system's folder icon at 1024 pixels for the On Folder layout). Choosing a symbol, an emoji, Clear, or a color with no mark in Graphite removes a custom icon set before, in Finder or Graphite, as choosing in Finder's popover replaces it; a rename or move never touches it.

## The icon maker (built 2026-10-21)

Following the owner's description of Image2icon's window (read only from its screenshot and the structure of its bundle; none of its artwork or code is used), built from Apple's art and public APIs:

- Opens after a picture is chosen in the folder popover (Photos, Files or the vault), as a page-sized sheet: a large preview on a round checkerboard, the templates in a column on the right (in a row on a narrow screen), and Export, Adjust and Remove Background under the preview; Cancel and Apply in the bar.
- Templates (`FolderIconTemplate`), each three layers: a back (Apple's folder art in the folder's color, `AppleFolderArt`), the picture clipped to a shape over the background color, and a top layer. Folder (Full): the picture fills the folder's front face (4% to 96% across, 26% to 87% down, measured on macOS 27's folder icon), with a light top edge. Folder (Center): small and rounded in the middle of the folder, as Finder draws app folders; kept as the picture alone so the folder keeps its art. Round, Squircle (the app-icon shape, 80% of the side, corners 22%) and Document (a page with a turned corner and a soft shadow). Every template's preview is live in the column.
- Adjust (a popover, as Image2icon's settings): Horizontal Offset, Vertical Offset, Zoom (0.25× to 5×), Rotation (−180° to 180°), Background (a color well and a clear button), Reset All. Dragging the preview moves the picture and pinching zooms it.
- Remove Background: Vision's `VNGenerateForegroundInstanceMaskRequest`, on the device. In the iPad simulator Vision is not available and the maker says so; it was not tried on a device or the Mac.
- Export: the icon at 1024 pixels as a PNG, saved with the system's file exporter. Apply: the made picture is kept in the vault (`.obsidian/graphite-folder-icons/`) and becomes the folder's look; on the Mac also Finder's custom icon.
- Drop: a picture file dropped on the maker replaces the picture; on the Mac a folder dropped on it gets the icon as Finder's custom icon (`NSWorkspace.setIcon`); iOS lets no app set another folder's icon and says so.
- Not built: Image2icon's other families (polaroid, stack, tilted, CD case, drive, watermark), per-size artwork (one drawing is scaled to every size), and a photo dragged straight from the Photos app (a file is needed).

## Where Finder keeps a folder's look (found 2026-10-21)

Found by reading the owner's folder `~/Desktop/test` (read only: `xattr -l`, `xattr -px`, `mdls`, `ls -lO@`), then writing the attributes on folders made in a scratch folder and asking the system for their icon (`NSWorkspace.shared.icon(forFile:)`, the drawing Finder uses) in a small command-line program; Finder's own window was not opened. Nothing here is documented by Apple: the attribute names are public strings in the system's frameworks, their format was read from what Finder wrote.

- **Symbol or emoji**: the extended attribute `com.apple.icon.folder#S`, a few bytes of JSON: `{"sym":"star.fill"}` for a symbol, `{"emoji":"🥸"}` for an emoji (the only two keys; `DesktopServicesPriv` names them). When both are there the symbol is drawn. It counts only while the custom-icon flag (`kHasCustomIcon`, `0x0400` of the flags in `com.apple.FinderInfo`, bytes 8 and 9, big-endian) is set; without the flag the system draws a plain folder. A symbol name the system does not have draws a plain folder.
- **Color**: not stored with the icon. It is the color of the folder's tags, `com.apple.metadata:_kMDItemUserTags`, a binary property list of strings `"Name\nN"`, where N is Finder's color number (1 gray, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange). The last tag with a color wins. Finder tints the folder only when it also has a symbol or emoji: a tag alone, or a color without a symbol, leaves the folder blue with the tag's dot beside the name (checked for every attribute combination tried; an emoji of a single space tints a bare folder, which Graphite does not use as it is not what Finder writes). Finder also keeps the legacy color label (bits 1 to 3 of byte 9 of `com.apple.FinderInfo`) equal to that color.
- **The owner's test folder** holds `{"emoji":"🥸"}`, the flag, and one tag `"Green\n1"`: a tag named Green with color 1, so the system draws that folder **gray**, not green (`NSWorkspace` draws it gray too; `mdls` reports label 1). On this Mac, the system's tag list knows only Green, Gray and Blue with colors (`URLResourceValues.tagNames = ["Orange"]` writes `"Orange\n0"`), so Graphite writes the tag strings with their color numbers itself rather than through that API.
- **Picture**: Finder's custom picture is the hidden file `Icon\r` inside the folder (its icon in the file's resource fork), with the same custom-icon flag; `NSWorkspace.shared.setIcon(_:forFile:options:)` writes both, `setIcon(nil, …)` removes both but leaves `com.apple.icon.folder#S`. The symbol attribute wins over `Icon\r` when both are there.
- **Public or not**: the reading and writing calls are public (`getxattr`, `setxattr`, `removexattr`, `NSWorkspace`), the `com.apple.icon.folder#S` format is not documented and may change with macOS. The tag format is the long-standing one Spotlight indexes.
- **iCloud Drive**: the `#S` suffix marks an attribute that file providers sync (the convention of `xattr_name_with_flags`), and the system's FileProvider framework lists `com.apple.icon.folder#S` among the attributes it handles, beside the tags. The Desktop folder holding the owner's test folder is in iCloud Drive. That a look made on one Mac arrives on another device was not tried.
- **iOS**: the Files app of iOS 27 reads the same attributes. In the iPad simulator, a folder given `"Red\n6"`, `{"emoji":"🍝"}` and the flag showed red with the emoji and a red tag dot in Files, and a look Graphite wrote there (green, airplane) showed in Files at once. An app reads and writes them with `getxattr` and `setxattr`, so Graphite does on iOS what it does on the Mac, except Finder's custom icon file (`NSWorkspace.setIcon` is Mac only; a picture stays Graphite's own on iOS). Whether iCloud Drive on a real iPad gives an app these attributes was not tried (no device in this work).
- **Apple's folder art on iOS**: `QLThumbnailGenerator` with the `.icon` representation, asked for a folder's URL, returns the Files app's own folder art with the folder's color and symbol or emoji; in the simulator it matched Files' folders side by side (`compare-files-app.png` and `compare-graphite-library.png` in the work's scratch folder). `UIDocumentInteractionController.icons`, the second candidate, was not needed.

Decisions taken from this:

- **One source of truth** (owner's bug report, 2026-10-21: Lab was red with ⚡ in Graphite and plain in Files, because looks chosen before Graphite wrote attributes lived only in its file). The folder's own attributes are what every app draws; every folder tile is the system's icon of the folder. Graphite's file mirrors them for devices and sync services that drop attributes. When the library lists a folder (`FolderLookReconciliation`, one folder at a time, off the main actor, only the folders listed): a style only in Graphite's file is written to a folder whose attributes are plain; when the attributes hold a different look, they changed after Graphite's (in Finder, Files or another device), so they win and Graphite's file takes their look. A folder whose write fails is reported once and not tried again while the vault is open. A picture on iOS cannot become the folder's icon, so only its color is compared there.
- A color alone is a tag. As observed, Finder on macOS 27 shows a folder with only a color tag as a plain folder with the tag's dot, while the Files app of iOS 27 in the simulator draws it in the tag's color (Journal, purple). Graphite shows exactly what the system draws on each, with the tag dots beside the name as both apps do.

- Which look a tile shows (`ShownFolderLook.resolve`): Finder's look wins when it changed after Graphite wrote the style (or only Finder has one); Graphite's stored style wins while Finder agrees with it or shows nothing (another device, a vault that is not in iCloud Drive, or a sync that drops attributes).
- On the Mac, choosing a look in Graphite writes Finder's attributes too: the color as a color tag (named with the system's own name for the color, replacing any other tag named after a tag color, keeping all other tags), the symbol or emoji attribute, the custom-icon flag and the label, under file coordination as a change of metadata only. A color no tag has (any color, pink, indigo, teal) writes no color tag. iOS writes them too since the Files app reads the same attributes (2026-10-21, after the simulator showed it).
- Apple's art everywhere (owner, 2026-10-21: Apple's folders look nicer than Graphite's): every folder tile is the system's own icon of the folder (Finder's on the Mac through `NSWorkspace.shared.icon(forFile:)`, the Files app's on iOS through Quick Look), so it is exactly what Finder and Files show. Previews in the popover and a look whose write is pending are Apple's art too: the system draws a stand-in folder in Graphite's temporary items carrying the attributes Graphite would write (`AppleFolderArtPlan`). (A first version tinted stand-ins for colors without a symbol, using an emoji of a single space that tints without drawing; it was dropped the same day with the one-source rule below, so Graphite never draws a color the folder itself does not show.) Only when the system gives no art at all does Graphite draw `folder.fill`.
- `.obsidian/graphite-folder-styles.json` stays the copy that syncs everywhere (Obsidian Sync, git, any provider); Finder's attributes are a second copy on the folder itself.

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
- [x] Accessibility (2026-10-21): a tile reads as name, kind and date (a folder: name, look and item count), its menu's actions are VoiceOver custom actions too, the selection is spoken by the selected trait and the favorite state once, as the tile's value. Checked at the largest text size in the iPad simulator (names wrap, nothing overlaps); not checked with VoiceOver itself. Folder tiles now say "N items" under the name, as the Files app does.

## Part 2: folder tiles

- [x] A folder tile: the system folder symbol in its color, an optional SF Symbol engraved on it, the name, the date, and a small star when bookmarked; its menu on touch and hold.
- [x] Choosing the color (10 system colors) and symbol (16) from the folder's menu (Folder Look). Not checked yet in dark mode on a device. Replaced on 2026-10-21 by Finder's popover (first section above).
- [x] Stored in the vault in `.obsidian/graphite-folder-styles.json` (decision above); a folder without a style is blue.
- [x] Renames, moves and deletions made in Graphite carry the folder's style with them. Renames made in another app lose it.

## Part 3: file tiles with previews

- [x] PDF: the first page with its ink annotations, through PDFKit, edged with a hairline as Files does. A chosen cover page is not built.
- [x] Image: scaled down with ImageIO while decoding.
- [x] Drawing: PNG drawings are images; SVG drawings show a picture symbol (not drawn yet).
- [x] Markdown: the first 4 KB drawn as a page of reading view (headings in their sizes, wrapped text with bold, italic and code, nested lists and tasks, quotes, callouts, code blocks, rules, the first picture where it sits), scaled down to the tile; never the source.
- [x] Canvas and Base: the kind's symbol on a gray tile, as other files without a preview (seen in the iPad simulator); a preview of a canvas or a base is not built.
- [x] Other files: a kind symbol (not the system's icon for the type).
- [x] Under each tile: name and modification date; touch and hold (or a secondary click) opens the file tree's own menu: new tab, other side, rename, move, copy, share, bookmark, delete, ….
- [x] Previews follow changes: a file listed with a new date or size gets a new preview. External changes reach the library when the workspace lists the vault again (`directoryVersion`).
- [x] Drag and drop: tiles onto folder tiles to move them; files from Files or the Finder into the grid to import them.
- [x] Selection mode for several tiles (2026-10-21, branch `notebook-library-leftovers`): Select in the view options menu, tap to choose, Select All, Move to…, Share, Make a Copy, Delete and Done in the library's top row, ⌘-click, ⇧-click and Select All on the Mac as in the Finder. Checked on macOS by tests and in the iPad simulator; not on the Mac app or a device (see `Coverage.md`).
- [x] Drag and drop everywhere in the library (owner, 2026-10-21): drag one tile or all chosen tiles onto a folder tile, onto the empty grid (into the folder shown) or onto the back button (up a level); the moves are the file tree's (link question, taken names, no folder into itself), and the tree and the library accept each other's drags. Files dropped from Files, the Finder, Photos, Safari or Mail are copied into the folder (text files become notes); a tile dragged out gives Files and the Finder the file. Rules and readers tested on macOS; the drags themselves were not seen (see `Coverage.md`). Not built: spring-loaded folders (a held drag opening a folder needs a clock injected into `LibraryModel` and a hover event SwiftUI's drop destination does not give), and a drop handler for Goodnotes and Notability files, whose place is `DroppedFileImporters.registered`.
- [x] Cloud files not downloaded are not read; their tile says "In iCloud".

## Part 4: one New menu that asks what to create

- [x] One New button in the library and in the iPad and iPhone sidebar, opening `NewItemPicker`: Notebook and Note as large choices, then Canvas, Base, Today's Daily Note (each while its core plugin is on), Import and Folder. The Mac's sidebar keeps its menu (a click makes a note), without Import.
- [x] Scan Documents, shown only where the device can scan (`VNDocumentCameraViewController.isSupported`: an iPhone or iPad with a camera, not the simulator or the Mac): the system scanner, then a new PDF notebook named "Scan 2026-10-21 14.05" in the folder shown (or the vault's location for new files), opened in a tab. Its pages are the scanned pictures at A4 width, with an invisible text layer from on-device recognition. Cancelling saves nothing; a failure is reported like other save errors. The same scanner is in a note's attach menu, Insert menu and context menu as "Scan Document", saving the PDF in the attachment folder and embedding it at the cursor. Not run on a device yet (see `Docs/Coverage.md`).
- [ ] Later entries, each once the feature exists: Image from Photos, Take Photo, Quick Record.
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
- [x] My Templates (2026-10-21, branch `notebook-library-leftovers`): a PDF page or a picture as paper, kept in the vault as an ordinary PDF in `.obsidian/graphite-templates/` (why there: `Architecture.md`), shown with its picture beside the built-in papers, with Edit to reorder, rename, hide and delete, and Add from Files or Photos. A notebook of it has the page as every page, copied as it is (vector stays vector). Checked on macOS by tests and in the iPad simulator; not on a device. Not built: inserting a template's page into an existing notebook.
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
