# Graphite compared with Obsidian mobile

What Obsidian's iPad and iPhone app offers that Graphite lacks, as of 2026-09-23. Five reviews each read Obsidian's help pages (obsidian.md/help) and Graphite's source for one area: core plugins, the editor and Markdown, the app shell, search and links, and media and PDFs. Every status below was checked against the code during that review, not assumed, and statuses have been updated as work landed since; the rows on aliases, custom task statuses, plain search and the scale notes were corrected against the code on 2026-09-25. `Docs/Coverage.md` remains the record of what Graphite does and how it is verified; this file is the list of what is missing.

## Bugs found during the review (fixed)

Defects in features Graphite already had. All were fixed and checked in the simulator on 2026-09-23; `Docs/Coverage.md` lists the tests.

- Search operators were searched as words (`-exam` found notes containing "exam"). Search now reads Obsidian's syntax; see Search below.
- `[[slides.pdf#page=3]]` opened page 1, and "Open in PDF View" from an embed started at page 1. Both open at the page now.
- The Heading button inserted `## ` at the cursor. Format › Heading › Heading 1–6 sets the whole line's level and removes it when repeated.
- The audio player kept showing Pause after playback ended.
- `![alt|150](image.png)` lost its size, and `|WxH` ignored the height.
- Tags starting with a digit (`#2026-exam`) were not recognized.
- Backlinks stopped silently at 2,000 linking rows.

Found while checking these: the iPad keyboard's curly quotes did not quote a search phrase; an embed inside backticks in a Live Preview callout was rewritten into a file path; the note jumped to its end after a Format command. All three are fixed.

## Where Graphite already goes further than Obsidian mobile

- PDF annotation (ink, highlight, underline, strikeout, bookmarks) and page management (insert, paper templates, rotate, move, import, export), including annotating a PDF embedded in a note. Obsidian's PDF viewer is read-only.
- Editable handwriting in notes (PNG, PDF or SVG drawings with an Edit button).
- Lecture recording that keeps running while you move between documents, with pause, resume and interruption handling.
- Bases map view built in (Obsidian needs its Maps plugin).
- Possible: several windows at once in Stage Manager, which Obsidian's iPad app does not support (Graphite does not either yet; see below).

## The gaps that matter most for studying on an iPad

Ranked by how often a student would hit them.

1. ~~**File management**~~ Done: new folder, rename (sidebar, sheet, or title bar) and move with link updates, "Update links?" as in Obsidian, delete following "Deleted files", make a copy, share, sort orders, reveal current file, collapse all, remembered open folders, drag and drop (not yet verified on a device). Renaming in the Files app instead still breaks links, as it does for Obsidian.
2. ~~**Getting around**~~ Done: quick switcher (fuzzy names, aliases, paths, recent files, create from the typed name), back and forward, command palette with recent commands.
3. ~~**Writing**~~ Done: smart lists, Tab and Shift-Tab indenting, auto-pairing brackets and Markdown, and a toolbar above the keyboard (undo, redo, heading, bold, italic, strikethrough, highlight, code, math, link, tag, lists, task, indent, outdent, move line, attach, draw, find). Not configurable yet.
4. ~~**`[[` autocompletion**~~ Done: notes, aliases and other files by fuzzy name, headings (`#`), blocks (`#^`, writing the `^id` into the note), `#tag` completion with counts, and creating a note by tapping an unresolved link.
5. ~~**Images into notes**~~ Done: camera, Photos (HEIC saved as JPEG), paste (as "Pasted image …"), drag and drop of images, files and sidebar items, Copy Image, and pasted web pages converted to Markdown ("Auto convert HTML"). Drops and the camera still need a device to verify.
6. ~~**Tabs and split view**~~ Done: tabs with pins, reopen closed tab and ⌘T ⌘W ⇧⌘T ⌃Tab ⌘1–9; a second side ("Split right", "Open to the Right") with a divider; a note's page links drive a PDF on the other side while the note keeps focus; tabs and the split are restored per vault. Undo does not survive a tab switch; a file is open in at most one tab.
7. ~~**Search operators**~~ Done: `path:`, `file:`, `content:`, `tag:` with nested tags, quotes, `-`, `OR`, parentheses, `[property:value]`, `line:`, `block:`, `section:`, `task:`, `task-todo:`, `task-done:`, `match-case:`, regular expressions, sort orders, and several matching lines per result.
8. ~~**Keyboard shortcuts**~~ Done: the window's commands are in the iPad menu bar (File, View, Go) with ⌘N ⌘T ⌘O ⌘W ⇧⌘T ⌘S ⌘, ⇧⌘F ⌘E ⌘P ⌃⌘S ⌘[ ⌘] ⌃Tab ⌘1–9; in the editor ⌘B ⌘I ⌘K ⌘L ⌘/ ⌘` ⇧⌘H ⇧⌘X ⌃⌘1–6 ⌥⌘↑↓ ⇧Tab, ⌘F find and ⌥⌘F replace, and ⌥Return, ⌘Return and ⌥⌘Return to follow the link at the cursor. Not configurable; checked only without a hardware keyboard so far.
9. ~~**PDF study tools**~~ Done: find in a PDF (the system find bar); Copy Link to Page, Copy as Quote, and "Quote in" the note on the other side from the text selection menu, and Copy Link to This Page from More; links written by Obsidian with `#page=N&selection=…` open at their page; password-protected PDFs open after asking for the password, read-only. Links point to the page, not to the selection within it.
10. ~~**Templates and daily notes**~~ Done: the Templates and Daily notes core plugins with their own settings files (`.obsidian/templates.json`, `.obsidian/daily-notes.json`); Insert › Template… and "Templates: Insert template" fill in `{{title}}`, `{{date}}` and `{{time}}` with Moment.js formats and add the template's properties to the note's; today's daily note is created from its template, opened at startup when asked, and the previous and next daily notes are one command away. No Calendar view.
11. ~~**Backlinks with context and unlinked mentions**~~ Done: the Backlinks panel lists linked mentions with the line of each link, and unlinked mentions (the note's name or aliases written as text, outside links, code, math, comments, tags and web addresses), each with a Link button that turns the words into a link, keeping them as written. A line opens its note there. At most 200 notes are read for either list; no filter or sort yet.
12. **Canvas**: `.canvas` files in existing vaults cannot be opened at all. Showing them read-only first, without ever rewriting them.

Next in line: ~~folding headings and lists~~ (done), ~~footnotes~~ (done), ~~block links and embeds (`#^id`)~~ (done earlier), ~~file recovery snapshots~~ (done), ~~the vault-wide Tags and Properties views~~ (done), ~~bookmarks~~ (done), ~~graph view (local, then global)~~ (done), share extension, ~~deep links~~ (done), ~~crash-safe recordings~~ (done).

## Complete list by area

Status: **Missing**, **Partial**, or **Done**. "Desktop only" items are left out.

### Core plugins

| Plugin | Status | Gap |
|---|---|---|
| Audio recorder | Done | Recordings survive Graphite being closed or crashing and are offered back at the next launch (tested with files cut off mid-write; not yet with a real microphone) |
| Backlinks | Done | Lines around each link, unlinked mentions with Link; no filter or sort, no "Show more context" |
| Bases | Partial | Kanban view, `mapTiles`, `html()`; see the Bases issues in `Coverage.md` |
| Bookmarks | Done | Obsidian's `bookmarks.json`: notes, headings, blocks, folders, searches and groups, opened from the left sidebar; bookmark from a note's More menu, the outline, Files and search; rename, remove, new group; follows renames. Graphs and web pages are listed and kept. No drag to reorder or into groups |
| Canvas | Missing | `.canvas` opens in the system preview |
| Command palette | Done | About 30 commands; no custom hotkeys or pinned commands |
| Daily notes | Done | Settings, template, startup, previous and next; no Calendar view |
| File explorer | Done | Drag and drop between folders not yet tried on a device |
| File recovery | Done | Copies before saves (at most once per interval), external changes and deletions, kept on the device outside the vault; restore (undoable when the note is open) or recreate a deleted note; per-note history from More, all notes from the command palette and Settings. No diff between versions |
| Footnotes view | Done | A right-sidebar panel; tapping a footnote shows its reference |
| Format converter | Missing | Low value |
| Graph view | Done | The whole vault full screen and each note's local graph in the right sidebar; Obsidian's filters and forces, arrows, drag, pinch, tap to open. No groups (colors by search), no animation over time, and a very large vault (100,000 notes) takes about half a minute to settle |
| Note composer | Missing | Merge notes, extract a selection to a new note |
| Outgoing links | Partial | Raw targets; unresolved links not marked; no unlinked mentions |
| Outline | Partial | No drag to reorder sections, no current-heading highlight |
| Page preview | Missing | Hover-based; limited use on touch |
| Properties view | Done | Every property in the vault with its type and count in the left sidebar; tap to search, change the type (written to `types.json`), rename in every note. No property autocompletion yet |
| Quick switcher | Done | |
| Random note | Missing | |
| Search | Partial | Operators, sort orders, several matches per file and property values done; no `query` embeds, "Explain search term", or "Copy results" |
| Slash commands | Missing | |
| Slides | Missing | |
| Tags view | Done | Every tag with its count in the left sidebar, nested or flat, sorted by name or frequency; tap to search. No tag renaming (Obsidian has none either) |
| Templates | Done | `{{title}}`, `{{date}}`, `{{time}}` with formats; properties merged; no Templater syntax |
| Unique note creator | Missing | |
| Word count | Done | Whitespace splitting miscounts Chinese, Japanese and Korean; no selection count |
| Workspaces | Missing | Tabs exist; saved named layouts do not |
| Publish, Sync | Missing | Paid Obsidian services; out of scope. Vaults sync through iCloud Drive or other file providers |

### Editor and Markdown

| Feature | Status | Gap |
|---|---|---|
| Toolbar above the keyboard | Done | Fixed set of buttons; not configurable |
| Undo and redo | Done | Toolbar buttons and ⌘Z; property edits from the properties panel cannot be undone |
| Smart lists, Tab indent | Done | |
| Auto-pair brackets and Markdown | Done | |
| Folding headings and lists | Done | Chevrons, Fold All, Unfold All, remembered per note on the device; list items fold only while editing, not in reading view |
| Move lines up and down | Done | Toolbar, command palette, ⌥⌘↑ ⌥⌘↓ |
| Paste images, paste HTML as Markdown, drag and drop files | Done | Drops not yet tried on a device |
| Table editing | Partial | Display only; add or move rows and columns needs the source |
| Link, tag and property autocompletion | Partial | Links and tags done; property names and values not yet |
| Block references (`^id`) | Done | Links scroll to the block, embeds show only it |
| Find and replace in a note | Done | The system find bar (⌘F or the toolbar); replace from its menu |
| Keyboard shortcuts | Done | ⌘B ⌘I ⌘K ⌘L ⌘/ ⌃⌘1–6 ⌥⌘↑↓ ⇧Tab ⌥⌘F and link following in the editor, plus the menu bar's; not configurable |
| Tick tasks in reading view | Missing | Live Preview ticks them |
| Custom task statuses (`[/]`, `[-]`, `[>]`) | Partial | Reading view draws any status as a checkbox, checked unless it is a space; Live Preview reads only `[ ]`, `[x]`, `[/]` and `[-]` as tasks; no per-status icons |
| Live Preview reveal | Partial | Whole line, not one element at a time |
| Embeds in the middle of a line (Live Preview) | Partial | Only whole-line embeds render |
| Nested embeds | Partial | One level deep |
| Unresolved links | Partial | Tapping creates the note; they still look like normal links |
| Footnotes (`[^1]`, `^[inline]`) | Done | Raised numbers and a list at the end when reading; raised labels in Live Preview (an undefined reference is styled there too); no back links from a footnote to its reference |
| HTML (`<u>`, `<br>`, `<details>`, `<span style>`) | Missing | Shown as text |
| Mermaid diagrams | Missing | Shown as code |
| Code highlighting while editing | Partial | Highlighted in reading view only; no copy button |
| Comments `%%` in Live Preview | Partial | Hidden in reading view; not dimmed while editing |
| Equation numbers (`\tag`) | Partial | Equations render; numbers are not drawn |
| Editor settings | Partial | No line numbers, indentation guides, right-to-left, fold settings, or "properties shown as source" |

### App shell

| Feature | Status | Gap |
|---|---|---|
| Tabs, pinned tabs, split view | Done | Two sides at most, side by side; undo history is lost when a tab's editor is rebuilt; a file in one tab at a time |
| Back and forward | Done | Toolbar buttons and ⌘[ ⌘] |
| Recent files | Done | In the quick switcher, remembered per vault |
| Right sidebar | Partial | Outline, backlinks, outgoing links, tags for Markdown notes; nothing for PDFs |
| Pull-down quick action, swipe gestures | Missing | |
| Hardware keyboard shortcuts | Done | In the iPad menu bar (File, View, Go) and the editor; not configurable, no Hotkeys settings page |
| Multiple windows (Stage Manager) | Missing | `UIApplicationSupportsMultipleScenes` is off |
| Share extension (share to Graphite) | Missing | |
| URL scheme and deep links | Done | `graphite://` with Obsidian's actions and parameters (`open` with `file` or `path`, `search`, `new` with `append`, `overwrite` and `silent`, `daily`, and `vault/…`), so an Obsidian link works once its scheme is changed; Copy Graphite URL from a note, a file, and the command palette. `obsidian://` links written in notes still go to Obsidian; no document types declared for "Open in Graphite" |
| Siri, Shortcuts, widgets | Missing | |
| Themes and CSS snippets | Partial | Light, dark and accent color; `.obsidian/appearance.json` not read |
| Fonts and Dynamic Type | Partial | One size slider; system text size ignored |
| Trash | Done | System trash, `.trash`, or permanent, as the vault's setting says |
| Vault switcher | Done | Rename or delete a vault in Files |
| Settings search, hotkey and toolbar settings | Missing | |
| Per-vault core plugin settings | Partial | Graphite's switches apply to every vault |

### Search and links

| Feature | Status | Gap |
|---|---|---|
| Plain search | Done | Matches the start of words (Obsidian also matches inside words), except Chinese, Japanese, Korean, Thai, Lao, Khmer and Myanmar text, which matches anywhere; sorted by name, modified or created time |
| `file:`, `path:`, `content:`, `tag:`, `line:`, `block:`, `section:`, `task:`, `[property]`, regex, case | Done | |
| `OR`, `-`, quotes, parentheses | Done | |
| Links to headings | Done | Nested `[[Note#H1#H2]]` fails |
| Link to a block | Done | Suggested and created while typing; following it scrolls to the block; `^id` hidden when not editing it |
| Rename updates links | Done | |
| Aliases | Done | Resolve links, found by the quick switcher and offered in `[[` completion, and searchable as text, since search reads the frontmatter |
| Graph view | Done | See Graph view under Core plugins |

Scale notes for 10,000–100,000 files: name matching uses `LIKE '%word%'` over the folded names, which reads every row per keystroke; backlinks select candidate rows through the indexed folded link targets and resolve each written target once per folder, reading every linking row; link positions are parsed but not stored, so backlink context needs the note text again.

### Media, PDFs and files

| Feature | Status | Gap |
|---|---|---|
| Image formats | Partial | avif and bmp not shown as images; SVGs from other apps not rendered; GIFs show one frame |
| Remote images `![](https://…)` | Missing | |
| Image size `\|WxH`, `![alt\|W](…)` | Done | |
| Camera and Photos into a note | Done | Camera not yet tried on a device |
| Audio playback | Done | No speed or ±15 s skip |
| Video playback | Done | webm, mkv, ogv not supported |
| PDF embeds with `#page=` and `#height=` | Done | |
| PDF page and selection links, copy as quote | Partial | Page links and quotes, quotes into the note on the other side; new links do not record the selection (`&selection=`), which opens at its page only |
| Find in PDF | Done | The system find bar; Obsidian mobile lacks it |
| Password-protected PDFs | Done | Read-only (no ink, markup or page changes); the password is asked each launch and never stored |
| Canvas | Missing | |
| Share notes, images or recordings out | Done | From each file's menu in the sidebar |
| Slides | Missing | |
