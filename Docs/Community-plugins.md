# Obsidian community plugins in Graphite

Graphite runs Obsidian community plugins: the same `main.js`, `manifest.json`, `styles.css` and `data.json` Obsidian uses, from the vault's `.obsidian/plugins` folder, without a Graphite version of the plugin. This file describes how, what works, what does not yet, and how each claim was checked.

Started on 2026-10-10, at the owner's request, ahead of the order `OBJECTIVE.md` had set. Universal compatibility is the goal, not the state: plugins that need Obsidian's desktop app, its CodeMirror editor, or its reading view's HTML are reported as such, and the gaps below are the work that remains.

## How it works

**A web view runs the plugins.** Obsidian's iPad and iPhone app is a web view (Capacitor); its plugins expect a browser's DOM and JavaScript. Graphite gives them the same: one `WKWebView` per open vault, running Graphite's own implementation of the `obsidian` module (`Sources/GraphiteUI/Resources/CommunityPluginRuntime`). WebKit runs the JavaScript in its content process, never on the app's main thread, so plugins cannot stall typing or Pencil input. Each vault has its own website data store (`WKWebsiteDataStore(forIdentifier:)`), so a plugin's `localStorage` stays with its vault.

**Plugins load as Obsidian loads them.** `main.js` is evaluated as a CommonJS module with Obsidian's `require`: `obsidian` is the runtime's module; `@codemirror/*` and `@lezer/*` are the real CodeMirror 6 and Lezer libraries, at the versions Obsidian 1.14.4 declares (vendored in `Vendor/`, see `Vendor/VERSIONS.md` and `Vendor/Licenses/`); Node.js and Electron modules (`fs`, `path`, `electron`, …) are refused with the reason, as on Obsidian mobile. The plugin's class is constructed with the `App` and its manifest, and `onload` is awaited. A plugin that throws is unloaded and its error kept. `styles.css` is added to the page and removed when the plugin unloads.

**The runtime talks to Graphite in messages.** Graphite sends messages to `GraphitePluginRuntime.receive` (`callAsyncJavaScript`); the runtime posts to the `graphitePlugins` message handler, which answers each message (`WKScriptMessageHandlerWithReply`). Vault operations go to `CommunityPluginVaultBridge` (GraphiteCore); the rest to `CommunityPluginHost` (GraphiteUI).

| From the runtime | Answered by | What happens |
| --- | --- | --- |
| `vault.list`, `vault.listFolder`, `vault.stat` | `CommunityPluginVaultBridge` | The vault's files without hidden folders (`vault.list`, at most 250,000 entries), or a folder's direct children including hidden ones (the adapter's `list`). |
| `vault.read`, `vault.write` | `CommunityPluginVaultBridge` | Through `VaultStore`: paths and symbolic links stay inside the vault, writes are coordinated and atomic. A write names the revision the plugin read; a file changed since is not overwritten (see Files below). |
| `vault.createFolder`, `vault.remove`, `vault.rename`, `vault.copy` | `CommunityPluginVaultBridge` | Through `VaultStore`; removal follows the vault's "Deleted files" setting when the plugin asks for the vault's choice (`fileManager.trashFile`). |
| `workspace.openFile`, `workspace.openLinkText` | `CommunityPluginHost` → `WorkspaceModel.open`, `follow` | Opens in Graphite's tabs; a link to a missing note creates it, as Obsidian does. |
| `workspace.renameFile` | `WorkspaceModel.move` | `fileManager.renameFile`: links to the file are rewritten as the vault's "Automatically update internal links" says, asking first when it is off. |
| `editor.apply` | `CommunityPluginHost` → `MarkdownSession.apply` | A plugin's change to the open note, as one undoable edit (see Editor below). |
| `network.request` | `CommunityPluginNetworkRequest` | `requestUrl`: made by Graphite, so not bound by the page's cross-origin rules, as on Obsidian mobile; https, 64 MB and 60 seconds at most. Plain http is refused by iOS's App Transport Security, which Graphite does not relax. |
| `markdown.render` | `CommunityPluginMarkdownRendering` | `MarkdownRenderer.render` in plugin views: CommonMark HTML from swift-markdown; the runtime turns `[[links]]` into internal links and runs the plugins' post-processors. |
| `menu.show` | `CommunityPluginHost` | A plugin's `Menu` as a native dialog; the chosen item's callback runs. |
| `notice.*`, `surface.*`, `commands.changed`, `ribbon.changed`, `views.changed`, `plugin.*`, `secrets.set`, `settings.open`, `plugins.setEnabled` | `CommunityPluginHost` | Notices shown by Graphite; the plugin panel shown or hidden; the palette's plugin commands; problems and unsupported features kept per plugin; secrets kept in the keychain. |

The Node tests answer the same messages from a folder on disk (`Tests/CommunityPluginRuntimeTests/support/test-vault-host.js`); the two must keep the same operations, answers and failure kinds.

**Files.** Plugins write like another app would: the bridge's `VaultStore` coordinates with the runtime's own file presenter, so Graphite's workspace presenter hears of plugin writes and its usual handling applies (open notes reload, or keep unsaved edits and report the conflict; the index and sidebar refresh). Graphite's own saves and other apps' changes reach the plugins as `create`, `modify`, `delete` and `rename` events. `vault.modify` and the adapter's `write` send the revision the plugin last read; a file that changed since is refused, the plugin's promise rejects, and Graphite shows a notice. `vault.process` reads and transforms again on such a conflict (three times at most). A note that starts with a UTF-8 byte order mark keeps it. Plugins can read and write anywhere inside the vault, hidden folders included, as in Obsidian; never outside it.

**Metadata.** `MetadataCache` reads every note once in the background (four at a time, at most 4 MB each), then again when it changes, and keeps only the metadata: headings, links, embeds, tags, frontmatter and its links, sections, list items with tasks, blocks and footnotes, with Obsidian's positions in UTF-16 code units, and the vault's `resolvedLinks` and `unresolvedLinks`, resolved as Obsidian resolves them (beside the note, then from the root, then by name or the end of a path, ignoring case). Notes iCloud or another provider keeps only in the cloud are not read, so plugins never download the vault.

**Editor.** When a command runs or the focused note changes, the runtime receives the note's text and selection. The `Editor` a plugin gets (`getValue`, `getLine`, `replaceSelection`, `replaceRange`, `transaction`, `setCursor`, `exec` for line commands, …) works on that copy; edits made together are sent back as one change once the plugin's code returns. `CommunityPluginEditorChange` (GraphiteCore) turns it into the smallest `MarkdownTextEdit`, which the note's session applies through its editor, so Undo takes it back. The change is refused, with a notice, when the note no longer has the text the plugin saw; a note in reading view cannot be edited by a plugin. Positions are lines and UTF-16 columns, which JavaScript, CodeMirror and `NSString` all count alike.

**Interface.** A plugin's modals, suggestion lists, settings tabs and views are drawn in the web view, which Graphite shows as the plugin panel: a sheet over the workspace, or inline on the plugin's page in Settings. Settings tabs draw either with `display()` or, for plugins written for Obsidian 1.13, from `getSettingDefinitions()` (controls, validation, `visible` and `disabled` predicates, groups, lists and pages). Notices appear as Graphite's own toasts and menus as native dialogs. Commands appear in the command palette with Obsidian's names ("Plugin: Command"); editor commands only while a note is open for editing. Ribbon buttons and open plugin views are listed in the palette too. Icons are Lucide's, as in Obsidian, with Obsidian's older icon names mapped. The panel uses Obsidian's CSS variables, so plugin styles apply, in Graphite's colors and Apple's system font, light and dark.

**Settings and consent.** Settings › Community plugins has Obsidian's "Turn on community plugins" switch, per vault and per device, off until the person turns it on, with a warning that plugins run code with access to the vault and the network. Which plugins are on is `.obsidian/community-plugins.json`, written as Obsidian writes it and merged with changes Obsidian made, so Obsidian and Graphite agree. Each plugin's settings stay in its `data.json`, written as Obsidian writes it (`JSON.stringify(data, null, 2)`). A plugin whose `data.json` changes elsewhere hears of it (`onExternalSettingsChange`). Secrets (`app.secretStorage`) are kept in the device's keychain, outside the vault. Each installed plugin shows its state, the modules it asks for that Graphite lacks, the unsupported features it reached while running, and its recent errors.

**Installing.** Settings › Community plugins › Browse lists Obsidian's community directory (`obsidianmd/obsidian-releases`), searchable. Installing reads the plugin's current `manifest.json` from its repository and downloads that GitHub release's `main.js`, `manifest.json` and `styles.css` into `.obsidian/plugins/<id>/`, never touching `data.json`, so an update keeps the settings. When the newest release needs a newer plugin API than Graphite provides, the newest release whose `minAppVersion` fits is chosen from the repository's `versions.json`, as Obsidian does. A plugin can also be installed from any GitHub repository (`owner/name`), and a plugin folder copied into `.obsidian/plugins` by Obsidian, Files or another app is found as it is.

**Compatibility before running.** `CommunityPluginCompatibility` reads the manifest and the code without running it: a plugin marked `isDesktopOnly`, or needing a newer API than the one Graphite provides (`1.14.4`, the version of `obsidian.d.ts` the runtime follows), is not loaded, as Obsidian mobile would not load it; the modules its code mentions that Graphite lacks are listed, since a plugin may reach them only on desktop.

## What works

Checked in the Node tests (jsdom, not WebKit; see How it was verified):

- Loading and unloading, with everything a plugin registered removed: commands, ribbon buttons, views, setting tabs, styles, events, intervals, DOM listeners.
- `loadData` and `saveData`; the vault, its adapter (hidden files and binary data included) and `FileManager` (`processFrontMatter`, `generateMarkdownLink`, `getAvailablePathForAttachment` following the vault's attachment setting, `getNewFileParent`, `renameFile`, `trashFile`).
- The metadata cache and link resolution described above, `resolveSubpath`, `getAllTags`, `parseFrontMatter*`, `getFrontMatterInfo`.
- Commands (`callback`, `checkCallback`, `editorCallback`, `editorCheckCallback`), editor changes as one edit, the active file and `MarkdownView`, `openLinkText`.
- Modals, `SuggestModal` and `FuzzySuggestModal` with the keyboard, settings tabs with text, toggle, dropdown, slider and button controls, declarative settings with validation and `visible` predicates, menus, notices, icons.
- `requestUrl`, `moment`, `parseYaml` and `stringifyYaml`, `debounce`, fuzzy and simple search, `htmlToMarkdown`, `sanitizeHTMLToDom`, base64 and hex helpers, `Platform` (mobile, iOS, tablet or phone).

Nine real plugins, among the most used in Obsidian's directory, built from their sources at fixed commits (`Tests/CommunityPluginRuntimeTests/compatibility/compatibility-plugins.json`) and run in the same tests:

| Plugin | Commit | What was checked |
| --- | --- | --- |
| Sample Plugin (obsidianmd) | `07ceb81d` | Loads; its three commands; its modal opens; its editor command replaces the selection in the note; its settings tab draws; its ribbon button. Nothing reported unsupported. |
| Natural Language Dates | `ab5701a8` | Loads; eight commands; "Insert the current date" writes today's date at the cursor through the editor change; its settings tab draws seven settings. Its typing suggestions (`EditorSuggest`) are reported unsupported. |
| Templater | `c51cf118` | Loads with CodeMirror; four commands; its settings draw; "Replace templates in the active file" rewrites `<% tp.date.now() %>` in a note through the vault. Its CodeMirror 5 highlighting mode is reported unsupported. |
| QuickAdd | `2201fa7c` | Loads; seven commands; its Obsidian 1.13 declarative settings, with its Svelte choice list, draw. Its command-line handler is reported unsupported. |
| Tag Wrangler | `5930a242` | Loads without errors. It works through tag context menus, which Graphite does not offer plugins yet, so it does nothing visible; hover previews are reported unsupported. |
| Dataview | `5ad0994f` | Loads with CodeMirror, with a Web Worker stand-in and an in-memory IndexedDB in jsdom (WebKit has both). Its query code blocks and editor extensions are reported unsupported: it cannot yet show queries in notes. |
| Tasks | `84704d3d` | Loads; "Toggle task done" turns `- [ ] Write the report` into `- [x] Write the report ✅` and today's date through the editor change; its declarative settings draw. Its query code blocks, reading-view changes, editor extensions and typing suggestions are reported unsupported. |
| Outliner | `b51918d4` | Loads; seven commands; its settings draw. Its commands work on CodeMirror's editor view (`editor.cm`), so running one fails, saying so, and leaves the note unchanged. |
| Kanban | `5134c05a` | Refused at load, saying why: it builds its cards' editor from Obsidian's own CodeMirror note editor (`app.embedRegistry`). |

Coverage of Obsidian's published API (`Docs/Community-plugin-API-coverage.md`, generated against `obsidian.d.ts` 1.14.4): all 103 exported classes, 422 of 442 class methods, 51 of 56 exported functions and constants. The five missing constants are CodeMirror state fields of Obsidian's own editor. Presence is not behavior: several present methods report themselves as unsupported when called.

## What does not work yet

Each of these is reported to the person, per plugin, when a plugin uses it (Settings › Community plugins), or refused with the reason:

- **CodeMirror editor extensions.** The libraries load, so plugins that define extensions load, but Graphite's editor is native TextKit and the extensions do not run: Live Preview decorations and widgets, editor keymaps and autocompletion of plugins such as Outliner, Advanced Tables, Various Complements, or the editor parts of Tasks and Dataview.
- **Reading view changes.** `registerMarkdownPostProcessor` and `registerMarkdownCodeBlockProcessor` run only in plugin views (`MarkdownRenderer`), not in Graphite's native reading view: Dataview and Tasks queries, charts, diagrams and other code blocks from plugins do not render in notes.
- **Typing suggestions** (`EditorSuggest`) and **live editor events** (`editor-change`, `editor-paste`, `editor-drop`): the plugin's editor holds the note as it was when a command ran or the note was focused.
- **Context menus.** `file-menu`, `files-menu`, `editor-menu` and `url-menu` events: Graphite's own menus do not ask plugins for items yet (Tag Wrangler, many file plugins).
- **Where views appear.** Plugin views open on the plugin panel, not as Graphite tabs or sidebar panels; views for other file types (`registerExtensions`) are not offered for those files; Bases views from plugins (`registerBasesView`).
- **Hover previews**, pop-out windows, several selections at once (the main one is kept), `Editor.undo` and `redo` (Graphite's Undo works), setting file times on write, `vault.setConfig` (change shared settings in Graphite's Settings), `FileSystemAdapter`, `getFullPath`, Obsidian's bundled MathJax, Mermaid, Prism and PDF.js loaders.
- **Desktop-only plugins** (`isDesktopOnly`), and code that needs Node.js or Electron: refused, as on Obsidian mobile.
- **Obsidian's undocumented internals.** The most used are provided (`app.plugins`, `app.commands`, `app.internalPlugins` with the Daily notes and Templates settings, `app.setting`, `app.metadataTypeManager` over `.obsidian/types.json`, `vault.getConfig`, `metadataCache.getCachedFiles`, `getTags`, `getBacklinksForFile`, `workspace.registerHoverLinkSource`). Obsidian's CodeMirror editor view (`editor.cm`) and its embedded note editor (`app.embedRegistry`) report themselves as unsupported (Outliner's commands, Kanban). Others are missing, and a plugin calling one fails with a JavaScript error that its row in Settings shows.
- **Themes and CSS snippets** are not plugins and do not restyle Graphite's native interface.
- Obsidian mobile has no status bar; neither does Graphite: `addStatusBarItem` returns an element that is not shown.

## How it was verified

On 2026-10-10, in a Linux container without Xcode or a Swift compiler.

- **JavaScript runtime:** 45 Node tests in `Tests/CommunityPluginRuntimeTests` (`npm test`), all passing: the vault and its conflicts, metadata and link resolution, editor commands, plugin loading and unloading, settings tabs, modals, suggestion lists, menus, and the nine real plugins above. They run in jsdom 26, not WebKit. jsdom cannot parse CSS nesting (its errors are recorded apart from the plugins'), and has no Web Workers or IndexedDB: the Dataview test fills in a worker that never answers and fake-indexeddb, an in-memory IndexedDB; what Dataview's worker does was not exercised.
- **Swift:** not compiled. Every new and changed Swift file parses without errors with tree-sitter-swift 0.6.0 (which reports false errors on 305 places in existing code that compiles, so it proves syntax only). A separate review checked every call against its declaration in the project and the iOS 18 and macOS 15 SDKs. It found two certain compile errors (a method that already existed, and an initializer Core did not make public) and two likely Swift 6 errors (a closure sent to the vault's actor, and a view helper outside the main actor), all fixed. Its logic findings are fixed too: a menu's choice was lost to the dismissal, a refused edit left the plugin's editor on the old text, a rename was reported cancelled while its link question was answered, a page that failed to load left the start waiting, a plugin's date in a message could crash the app, and vault answers were decoded on the main thread (they now go back as JSON text for the page to parse). The Node harness talks to the runtime through the same WebKit connection script, with vault answers as text. `Tests/GraphiteCoreTests/CommunityPluginTests.swift` (manifests, `community-plugins.json`, inventory, the vault bridge, editor changes, installation helpers, Markdown rendering) was written and not run.
- **Not established:** that the app builds; anything in WebKit or on a device (the plugin panel, the message handler, the scheme handler, the keychain, `WKWebsiteDataStore(forIdentifier:)`, content-process restarts); installation from GitHub (this container could not reach github.com's releases); memory and start-up time of the runtime with real vaults; behavior with 10,000 or 100,000 notes (the metadata cache keeps every note's metadata, as Obsidian does).

## Running the checks

```bash
cd Tests/CommunityPluginRuntimeTests
npm ci
npm test                                  # the runtime's tests
npm run build-compatibility-plugins       # clones and builds the real plugins (needs GitHub and npm)
npm test                                  # again, now with the real plugins
npm run api-coverage -- --markdown        # Docs/Community-plugin-API-coverage.md
npm run build-vendored-libraries          # regenerates Vendor/ from the pinned versions
```

`swift test` runs `CommunityPluginTests` with the other Core tests.

## Next

In order of what it unlocks for daily use:

1. Build and run on a Mac and an iPad; run `swift test` and the Node tests; use a real vault with the plugins above.
2. Code blocks and post-processors in the reading view: render a plugin's code block in a web view of its own inside the note, so Dataview, Tasks and chart plugins show their output.
3. Context menus: let the file list's and the editor's menus include plugins' items.
4. Typing: send editor changes to plugins that listen for them, and offer `EditorSuggest` suggestions through Graphite's completion list.
5. Plugin views as tabs and sidebar panels, and plugin views for other file types.
6. More real plugins in the tests, starting from the most downloaded in Obsidian's directory, and measurements on a device.
