# Open/closed principle across Graphite (OCP)
Snapshot: b13dec3 (main, 2026-10-18).

Scope: every `OCP-*` finding of the twelve area audits and the cross-cutting audit (52 findings: 3 High, 30 Medium, 19 Low, from [findings-index.md](../findings-index.md)), with the evidence of the three High findings and of every systemic pattern re-read in the snapshot. Area links: [SHELL](../areas/shell.md), [EDITOR](../areas/editor.md), [READING](../areas/reading.md), [MDCORE](../areas/mdcore.md), [VAULT](../areas/vault.md), [BASES](../areas/bases.md), [CANVAS](../areas/canvas.md), [INK](../areas/ink.md), [LECTURE](../areas/lecture.md), [VOICE](../areas/voice.md), [PLUGIN](../areas/plugin.md), [RUNTIME](../areas/runtime.md), [ARCH](../cross-cutting/architecture.md).

What the principle means here: adding a document kind, a block kind, a command, a panel, a format, a message or a per-vault store must be one new declaration in the module that owns it, and the compiler (or a generator) must find every other place. Graphite meets this where a closed Swift enum is switched exhaustively and fails it where the same concept is a raw string, a hand-kept list, or an enum switched with `default:`.

## 1. Verdict by area

| Area | Area verdict (O) | High | Medium | Low | Reason, with numbers |
| --- | --- | ---: | ---: | ---: | --- |
| SHELL | Weak | 1 | 4 | 2 | Adding the canvas kind touched 13 UI files plus `DocumentKind`. 27 commands are declared twice, and what can be created is listed 7 times. 3 `default:` branches over `DocumentKind` hide new kinds. |
| EDITOR | Mixed | 0 | 2 | 2 | A new rendered-block kind touches 6 switches (1 behind `default:`), and a new formatting command touches 7 places. The styling engine and layout fragment are already one implementation for both platforms. |
| READING | Mixed | 0 | 1 | 4 | A new reading block kind touches 6 switches in `MarkdownPreview.swift`, 3 of them behind `default:`. Callout types live in 4 tables, and media extensions in 2 lists that disagree. |
| MDCORE | Mixed | 0 | 2 | 1 | The 26 code languages are one data table, but formatting compares language names in 12 places. A new block syntax must be taught to 5 scanners. |
| VAULT | Mixed | 0 | 2 | 2 | `DocumentKind` is the one extension table. Bookmark kinds are 18 string-literal sites in 2 modules, settings files have 4 JSON writers, and 2 of 4 `SearchScope` switches use `default:`. |
| BASES | Weak | 0 | 3 | 2 | A new view type touches 10 places in 6 files. The expression vocabulary lives in 14 string switches. `BaseEvaluator.swift` has 23 `default:` branches over the app's own enums. |
| CANVAS | Mixed | 0 | 2 | 1 | Card kinds are an exhaustive enum. File-card dispatch is repeated in 4 places (2 with `default:`), and the JSON Canvas vocabulary is spelled in 3 places. |
| INK | Mixed | 0 | 3 | 1 | A drawing format is dispatched at 5 places. Graphite's canvas tools are 3 parallel booleans in 5 places. VoiceOver actions dispatch on 7 menu titles. |
| LECTURE | Mixed | 0 | 3 | 2 | 3 `default:` branches over `PDFEdit`, audio/video branching in 9 `RecordingController` members, and Graphite's 10 annotation keys listed twice. `PDFEdit` itself is one closed command vocabulary. |
| VOICE | Mixed | 0 | 1 | 1 | A new neural model family is wired in 7 places across 3 files, 3 of them silent equality tests. The quality, mode and passage-audio policies are closed enums with pure deciders. |
| PLUGIN | Weak | 1 | 2 | 1 | 44 JavaScript→Swift and 39 Swift→JavaScript operation names are string literals in 3 Swift switches and 9 JavaScript files. An unknown operation from the runtime is answered as a success. |
| RUNTIME | Mixed | 1 | 2 | 0 | The same 83 message names are typed by hand in the runtime, the Swift host and the Node test host. Feature files join the runtime by mutating shared objects in script order. |
| ARCH | Weak | 0 | 3 | 0 | A new document kind with its own session touches at least 16 places in 14 files, 5 of them behind `default:`. Commands are declared twice, with 12 shortcuts written twice. The coordinator calls each feature's move, delete and vault-removal code by name. |
| **All** | | **3** | **30** | **19** | 52 findings |

**App-wide verdict: Weak.** Graphite has the right raw material (closed Swift enums such as `DocumentKind`, `PDFEdit`, `CanvasNode.Content`, `BaseValue` and `DrawingFormat`), but every concept that grows is wired by hand at 4 to 16 sites and hidden from the compiler by 263 `default:` branches app-wide ([metrics.md](../metrics.md)). The two worst cases are the plugin message protocol (83 untyped names, where an unknown operation succeeds) and document-kind dispatch (16 places in 14 files); together they hold all three High findings.

## 2. Systemic patterns across the whole app

The patterns are ordered by cost: silent wrong behaviour in shipped paths first, then data-loss risk, then maintenance cost.

### 2.1 Vocabularies shared with JavaScript, CSS and scripts are typed by hand on each side

**What it is.** A vocabulary that crosses a language boundary (operation names, payload fields, theme-probe keys, value-type names, callout types, diagnostic kinds) is written as string literals in Swift, again in JavaScript or CSS, and a third time in the Node test host or a shell script. Nothing generates one side from the other, and no test checks that each name has a handler.

**Where.** `OCP-PLUGIN-01` (High), `OCP-RUNTIME-01` (High), `OCP-PLUGIN-02`, `OCP-PLUGIN-03`, `OCP-RUNTIME-02`, `OCP-BASES-05`, `OCP-READING-02`, `OCP-LECTURE-05`. Systemic in PLUGIN, RUNTIME, BASES, READING and LECTURE.

**Evidence.**
- Swift answers incoming operations in `answerHostOperation`'s 9 cases. Its `default:` passes everything else to `receiveNotification` ([CommunityPluginHost.swift:910-912](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L910-L912)), whose `default: break` returns nothing ([CommunityPluginHost.swift:1050-1051](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1050-L1051)). The caller then answers `[:]`, so a misspelt operation is reported to the plugin as a success.
- The JavaScript side refuses an unknown operation with `unknownOperation` ([community-plugin-runtime-plugins.js:1541-1543](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1543)), and so does the vault bridge in Swift ([CommunityPluginVaultBridge.swift:75-76](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L75-L76)). The three receivers apply two different rules.
- The Node test host answers `{}` to any operation it does not name ([test-vault-host.js:126-128](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L126-L128)), so the tests pass whatever name the runtime sends.
- The bridge claims every name with the prefix `vault.` ([CommunityPluginVaultBridge.swift:30](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L30)). The prefix is the routing rule, and it is not typed.
- The 27 callout types are a JavaScript array ([theme-probe.js:8-10](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L8-L10)) and the keys of a Swift dictionary ([VaultThemeTokens.swift:410-419](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L410-L419)). The 11 code token classes are another JavaScript array ([theme-probe.js:12](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L12)).

**Cost.**
- A renamed operation or field compiles, passes the Node tests and does nothing in the app. `LSP-RUNTIME-01` and `LSP-PLUGIN-01` show that the copies have already drifted.
- One new operation costs 3 to 5 edits: a Swift switch, a JavaScript call site, often a stored property and its reset (the step `OCP-PLUGIN-02` says gets forgotten), and the fake host.
- A theme key renamed on one side reads as "the theme leaves it alone", so the theme silently stops applying.

**Shared fix direction.**
- Declare each cross-language vocabulary once: either a Swift enum with `String` raw values, or one JSON schema resource for messages and their payloads (`community-plugin-messages.json`, as the RUNTIME blueprint proposes).
- A build step generates the JavaScript constant table and the fake host's switch from that declaration.
- Each incoming case decodes a `Decodable` payload, as `CommunityPluginVaultBridge` already does.
- An explicit `unknown(String)` case answers `unknownOperation` on every receiver.
- A contract test asserts that every declared operation has a handler on its receiving side.

### 2.2 A new kind is wired by hand at many sites

**What it is.** A concept that grows (document kind, sidebar panel, inspector panel, creatable item, settings page, block kind, Bases view type, drawing format, neural model family, recording kind, paper template, core plugin) has an enum, but its behaviour is spread over parallel switches, `if/else` chains, optional fields and hand-kept lists in many files. No descriptor holds a kind's behaviour in one place.

**Where.** `OCP-SHELL-01` (High), `OCP-ARCH-01`, `OCP-SHELL-03`, `OCP-SHELL-04`, `OCP-SHELL-05`, `OCP-READING-01`, `OCP-READING-05`, `OCP-EDITOR-01`, `OCP-BASES-02`, `OCP-CANVAS-01`, `OCP-INK-01`, `OCP-VOICE-01`, `OCP-LECTURE-02`, `OCP-LECTURE-04`, `OCP-PLUGIN-04`, `OCP-VAULT-04`, `OCP-MDCORE-03`. Systemic in all thirteen areas except RUNTIME.

**Evidence.**
- `TabDocument` holds one optional session per kind ([WorkspaceTabs.swift:13-15](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L13-L15)). `hasUnsavedChanges`, `unload` and `save` each repeat the three sessions ([WorkspaceTabs.swift:35-48](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L35-L48)).
- Loading switches on `DocumentKind` and ends in `default:` ([WorkspaceTabs.swift:345-377](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L345-L377)). The pane does the same ([WorkspacePanes.swift:520-555](../../../Sources/GraphiteUI/WorkspacePanes.swift#L520-L555)).
- The external-change check names each session in turn ([WorkspaceModel.swift:1363-1365](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1363-L1365)).
- A move collects unsaved paths from two hand-named session types ([WorkspaceFileManagement.swift:105-106](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L105-L106)). A new kind left out of this list is moved before its typed links are indexed.
- Settings pages: `configurablePlugins` is a hand-kept list ([SettingsView.swift:22](../../../Sources/GraphiteUI/SettingsView.swift#L22)), and the page switch's catch-all `case .plugin:` shows Core Plugins for any plugin missing from it ([SettingsView.swift:116](../../../Sources/GraphiteUI/SettingsView.swift#L116)).
- The sidebar list is an `if/else` chain whose last branch is the file tree ([VaultSidebar.swift:366-383](../../../Sources/GraphiteUI/VaultSidebar.swift#L366-L383)), so a panel missing from the chain shows the file tree under its own icon.
- The inspector's empty-state text lists 4 of the 7 `InspectorPanel` cases ([MarkdownPane.swift:936-957](../../../Sources/GraphiteUI/MarkdownPane.swift#L936-L957)).
- Drawing formats are dispatched by `switch format` in several functions, for example [DrawingFileService.swift:45-53](../../../Sources/GraphiteApple/DrawingFileService.swift#L45-L53) and [DrawingFileService.swift:117-123](../../../Sources/GraphiteApple/DrawingFileService.swift#L117-L123).

**Cost.**

| Concept | Places a new case touches | Finding |
| --- | ---: | --- |
| Document kind with a session | 16 places in 14 files | `OCP-ARCH-01`, `OCP-SHELL-01` |
| Bases view type | 10 places in 6 files, plus 2 map-only checks | `OCP-BASES-02` |
| Neural model family | 7 places in 3 files, 3 of them silent | `OCP-VOICE-01` |
| Creatable item | 7 lists, 5 of them repeating the plugin gate | `OCP-SHELL-05` |
| Sidebar panel | 7 branch sites in 4 files | `OCP-SHELL-03` |
| Reading block kind | 6 switches, 3 behind `default:` | `OCP-READING-01` |
| Live Preview block kind | 6 switches, 1 behind `default:` | `OCP-EDITOR-01` |
| Drawing format | 5 places | `OCP-INK-01` |
| Block syntax | 5 independent scanners | `OCP-MDCORE-03` |
| Recording kind | 9 `RecordingController` members | `OCP-LECTURE-02` |
| File-card kind on a canvas | 4 places, 2 behind `default:` | `OCP-CANVAS-01` |
| Inspector panel | 4 places | `OCP-READING-05` |
| Paper template | 3 places, all exhaustive | `OCP-LECTURE-04` |
| Kinds that hold links | 3 places | `OCP-VAULT-04` |

A missed site compiles and fails at run time: the wrong page, the file tree, a file preview, a skipped index refresh.

**Shared fix direction.**
- Use one enum case plus one descriptor per kind, registered in one table by the module that owns the kind: `DocumentKindDescriptor`, `SidebarPanelDescriptor`, `CreationCatalogue`, `BaseViewKind`, `DrawingFileFormat`, `NeuralVoiceModelFamily` descriptor, `CanvasFileCardKind`, `LivePreviewBlockKindTraits`.
- Every other list (menus, empty-state text, "types the user can create") is derived from the table.
- Where the kinds carry a real substitution, a small protocol with a shared contract suite earns its place under RULES.md: `DocumentSession` (seven kinds today, plugin views as an eighth), `DrawingFileFormat` (3 formats), `RecordingSession` (2 kinds).
- Everything else stays a value-type descriptor reached through one exhaustive switch.

### 2.3 Cross-cutting duties are calls from the coordinator to each feature

**What it is.** Moving a path, deleting a path, removing a vault and switching vaults are duties every per-path or per-vault store shares. `WorkspaceModel` calls each store by name, so a new store is cleaned up only if someone remembers to add a line. Feature caches also live on the aggregate itself.

**Where.** `OCP-ARCH-03`, `OCP-SHELL-06`, `OCP-CANVAS-03`, `OCP-PLUGIN-02`. Systemic in ARCH, SHELL, CANVAS and PLUGIN.

**Evidence.**
- A move calls 7 feature functions by name ([WorkspaceModel.swift:1201-1213](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1213)), and a deletion calls 5 ([WorkspaceModel.swift:1216-1222](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1216-L1222)).
- Vault removal names recovery copies, the index, plugin consent, three key families and the place store ([WorkspaceModel.swift:244-258](../../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258)). It does not name the folds key, which is `private` in another file.
- Graph and map caches are stored on the workspace ([WorkspaceModel.swift:146-154](../../../Sources/GraphiteUI/WorkspaceModel.swift#L146-L154)) and reset by name at vault switch.
- In the plugin host, each contributed capability has a declaration, a decode and a reset written separately (`OCP-PLUGIN-02`).

**Cost.** This pattern has already produced defects:
- `BUG-SHELL-02` and `BUG-ARCH-06`: removing a vault leaves its folds in the device's preferences.
- `BUG-CANVAS-06`: a graph or map from the previous vault can be shown after a vault switch.

Each new per-path store (bookmarks were added this way, [WorkspaceModel.swift:1208](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1208)) repeats the risk of losing a fold, place or bookmark on rename.

**Shared fix direction.**
- Define the observer conformances `VaultPathMoveObserver` (`followMove(from:to:)`, `forget(inside:)`) and `VaultLifecycleObserver` (`vaultWillClose()`, `vaultWasRemoved(identifier:)`), registered at composition. The coordinator iterates the registered list and names no feature.
- Per-vault device keys live in one typed registry (`VaultDeviceMemory`).
- Feature caches move into the feature's own per-vault model.
- Plugin contributions become one `Decodable` value replaced whole, with an `empty` value.

### 2.4 `default:` over the app's own enums hides new cases from the compiler

**What it is.** A `switch` over an enum Graphite declares ends in `default:`, a catch-all `case .x:`, or a `case .x where condition` followed by `default:`. A new case then compiles and takes the fallback without anyone deciding. Some `default:` arms stand for exactly one named case, and one mapping is wrong by construction.

**Where.** `OCP-BASES-03`, `OCP-LECTURE-01`, `OCP-MDCORE-02`, `OCP-INK-04`, `OCP-READING-01`, `OCP-READING-04`, `OCP-VAULT-03`, `OCP-EDITOR-01`, `OCP-EDITOR-02`, `OCP-CANVAS-01`, `OCP-SHELL-01`, `OCP-SHELL-04`, `OCP-ARCH-01`. Systemic in eleven areas.

**Evidence.**
- `PDFEdit.changesPageTree`, `changesOutline` and `changedPageIndex` all end in `default:` ([PDFPageManager.swift:50-73](../../../Sources/GraphiteApple/PDFPageManager.swift#L50-L73)). `changesPageTree` decides whether Graphite's keys are re-set before PDFKit rewrites the page tree, so a new page-moving edit that falls into `default` drops stroke data at the next save.
- In `BaseEvaluator`, `default:` stands for `>=` ([BaseEvaluator.swift:542](../../../Sources/GraphiteCore/BaseEvaluator.swift#L542)) and for `%` ([BaseEvaluator.swift:639](../../../Sources/GraphiteCore/BaseEvaluator.swift#L639)). `case .and, .or` at [BaseEvaluator.swift:547](../../../Sources/GraphiteCore/BaseEvaluator.swift#L547) is unreachable.
- `hasReadingSession` admits 3 block kinds and refuses every other kind through `default: return false` ([LivePreviewWidgets.swift:104-108](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L104-L108)), so a new kind is silently left out of Read Aloud.
- `.canvas where preferences.isEnabled(.canvas)` followed by `default:` ([WorkspaceTabs.swift:373-376](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L373-L376)) hides every kind not named. The same shape appears at [WorkspacePanes.swift:553](../../../Sources/GraphiteUI/WorkspacePanes.swift#L553), [ConflictVersionsSheet.swift:354](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L354), [CanvasPane.swift:202](../../../Sources/GraphiteUI/CanvasPane.swift#L202) and [CanvasCardViews.swift:281](../../../Sources/GraphiteUI/CanvasCardViews.swift#L281).
- `PencilToolGlyph.Tool.init(kind:)` maps `.ink` to `.eraser` ([PencilToolButtons.swift:114-120](../../../Sources/GraphiteUI/PencilToolButtons.swift#L114-L120)).

**Cost.** The areas' counts of `default:` over their own enums:

| Area | Sites | Finding |
| --- | ---: | --- |
| BASES (`BaseEvaluator.swift` only) | 23 (20 `BaseValue`, 3 `BaseBinaryOperator`) | `OCP-BASES-03` |
| READING | 7 | `OCP-READING-01`, `OCP-READING-04` |
| ARCH (`DocumentKind`) | 5 | `OCP-ARCH-01` |
| LECTURE | 5 (3 `PDFEdit`, 2 `RecordingState`) | `OCP-LECTURE-01` |
| INK | 4 | `OCP-INK-04` |
| EDITOR | 3 | `OCP-EDITOR-01`, `OCP-EDITOR-02` |
| MDCORE | 3 | `OCP-MDCORE-02` |
| VAULT (`SearchScope`) | 2 | `OCP-VAULT-03` |
| CANVAS | 2 | `OCP-CANVAS-01` |

When `.html` was added to `BaseValue`, all 20 `BaseValue` switches with `default:` had to be found by reading. The compiler flagged none of them (`OCP-BASES-03`).

**Shared fix direction.**
- List every case. Name each operator. Split short-circuit operators into their own enum so the dead arm disappears.
- `where` conditions on a case move into the case's body, so the switch stays exhaustive.
- A script in CI lists `default:` in switches whose subject type is declared in `Sources/`. `RecordingControls.swift:64`, `RecordingController.swift:540` and `MarkdownTextStyler.swift:736` are such sites outside any finding, and the cleanup must take them too.

### 2.5 Commands and actions are declared once per surface

**What it is.** A command (title, symbol, shortcut, availability, action) is written separately in the palette, the menu bar, the toolbars, the empty tab, the keyboard toolbar, the context menu and the hardware key commands. Shortcut labels are typed as text beside `.keyboardShortcut` bindings, and VoiceOver actions dispatch on menu titles.

**Where.** `OCP-SHELL-02`, `OCP-ARCH-02`, `OCP-SHELL-05`, `OCP-EDITOR-02`, `OCP-EDITOR-03`, `OCP-INK-03`. Systemic in SHELL, ARCH, EDITOR and INK.

**Evidence.**
- The palette writes `shortcut: "⌘O"` and `shortcut: "⌘N"` as text ([WorkspaceCommands.swift:26-28](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L26-L28)). The menu bar binds `.keyboardShortcut("n", modifiers: .command)` and `.keyboardShortcut("o", modifiers: .command)` ([GraphiteCommands.swift:62-75](../../../Sources/GraphiteUI/GraphiteCommands.swift#L62-L75)).
- Both registries repeat the `isEnabled(.bases)` and `isEnabled(.canvas)` gates ([WorkspaceCommands.swift:36-41](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L36-L41), [GraphiteCommands.swift:65-70](../../../Sources/GraphiteUI/GraphiteCommands.swift#L65-L70)).
- The ink selection turns every `UIAction` into a VoiceOver action that calls `performMenuAction(named: action.title)`, which switches on 7 English titles with `default: break` ([InkSelection.swift:957-978](../../../Sources/GraphiteUI/InkSelection.swift#L957-L978)).

**Cost.**
- 27 commands exist twice and 12 shortcuts are written twice.
- Enablement already drifts: `next-tab` and Toggle Source have different rules in the palette and the menu.
- Editor titles drift: "Inline math" and "Inline Math"; "Link to note" and "Add Link" for one command.
- Localizing or renaming a menu title silently turns the VoiceOver action into a no-op, and recolouring is unreachable for VoiceOver users of the frame.
- Palette identifiers are persisted in the recent-commands list, so renaming one in code loses users' recent lists.

**Shared fix direction.**
- Each surface's commands are declared once: `WorkspaceCommand` for the workspace, `EditorCommandDescriptor` for the editor, `InkSelectionAction` for the ink selection. Each declaration holds identifier, title, symbol, `KeyboardShortcut`, availability, placement and action.
- The palette, the menu bar, the bars, the context menus, the key commands and the accessibility actions are generated from it.
- Shortcut labels are derived from the `KeyboardShortcut` value.
- Persisted identifiers are the cases' raw values.
- The editor's platform-neutral context-menu model (section 4) is the template.

### 2.6 External file-format vocabularies are compared as strings inside Swift

**What it is.** Values that come from a file format or a manifest (bookmark `type`, JSON Canvas node types and keys, code-language names, Bases function and method names, voice platforms) are kept as `String` and compared with literals wherever they are used. They are never mapped once at the boundary.

**Where.** `OCP-VAULT-01`, `OCP-SHELL-07`, `OCP-CANVAS-02`, `OCP-MDCORE-01`, `OCP-BASES-01`, `OCP-VOICE-02`. Systemic in VAULT, SHELL, CANVAS, MDCORE, BASES and VOICE.

**Evidence.**
- `Bookmark.type` is a raw `String` ([Bookmarks.swift:54](../../../Sources/GraphiteCore/Bookmarks.swift#L54)), switched with literals in Core ([Bookmarks.swift:93-104](../../../Sources/GraphiteCore/Bookmarks.swift#L93-L104)) and again in two UI files (for example [VaultSidebarPanels.swift:352](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L352)).
- JSON Canvas node types are matched by literal in the reader ([CanvasFile.swift:293-310](../../../Sources/GraphiteCore/CanvasFile.swift#L293-L310)) and spelled again in the writer and the link extractor.
- Code formatting picks a style by `switch language.name` with `default: return nil` ([CodeFormatting.swift:54-85](../../../Sources/GraphiteCore/CodeFormatting.swift#L54-L85)). It repeats the keyword-language list by hand ([CodeFormatting.swift:350](../../../Sources/GraphiteCore/CodeFormatting.swift#L350)) as a second copy of the cases at lines 66 and 70.

**Cost.**
- A typo compiles. For example, a language added to the `.keywords` style but not to the list at line 350 formats with brackets only.
- A new bookmark kind (Obsidian's `heading` or `block`) needs edits in two modules with no compiler help.
- A misspelt canvas key writes a file Obsidian reads differently.

**Shared fix direction.**
- Map once at the Core boundary to an enum with an explicit `unknown(String)` case: `BookmarkKind`, `CanvasNodeType` with a `CanvasKey` enum, `NeuralVoicePlatform`, `BaseFunctionName` and `BaseMethodName` (each case carrying arity and null-receiver result).
- Keep the raw fields as the stored truth so unknown values round-trip. `Bookmark.fields` and `CanvasNode.Content.unknown` already do this.
- Per-language formatting becomes data on the `CodeLanguage` descriptor (`formatting: CodeFormattingStyle?`, `blockKeywords:`), and no code compares names.

### 2.7 One fact is kept in hand-maintained copies

**What it is.** A rule or table that should be derived from one declaration is copied, often with a comment saying the copies must match: sort ranks, annotation key lists, media extensions, readable-column width, inserted templates, "which files hold links", and JSON writers for settings files.

**Where.** `OCP-BASES-04`, `OCP-LECTURE-03`, `OCP-READING-03`, `OCP-EDITOR-03`, `OCP-EDITOR-04`, `OCP-VAULT-02`, `OCP-VAULT-04`, `OCP-MDCORE-03`. Systemic in BASES, LECTURE, READING, EDITOR, VAULT and MDCORE.

**Evidence.**
- `BaseValue.sortRank` ([BaseValue.swift:477-489](../../../Sources/GraphiteCore/BaseValue.swift#L477-L489)) and `BaseQueryEngine.sortingKind` with the literal `textSortingKind = 4` ([BaseQuery.swift:259-275](../../../Sources/GraphiteCore/BaseQuery.swift#L259-L275)) are two copies of one ranking.
- `storedPictureKeys` is declared as "the one place that lists them" ([PDFPageManager.swift:92-94](../../../Sources/GraphiteApple/PDFPageManager.swift#L92-L94)), yet the page-tree preservation list types all 10 keys again ([PDFPageManager.swift:315-316](../../../Sources/GraphiteApple/PDFPageManager.swift#L315-L316)).
- `MediaFileKind` lists 4 video and 7 audio extensions ([MarkdownPreview.swift:232-235](../../../Sources/GraphiteUI/MarkdownPreview.swift#L232-L235)), while `DocumentKind` lists 6 media extensions ([VaultPath.swift:168](../../../Sources/GraphiteCore/VaultPath.swift#L168)). `.ogg`, `.flac`, `.webm`, `.m4v` and `.3gp` play inside a note but classify as `.other`; `BUG-ARCH-01` follows from this.

**Cost.**
- A key missing from the preservation list is dropped by PDFKit whenever pages move.
- A rank changed in one copy gives formula `sort()` and row sorting different orders.
- Three of the four settings writers reorder keys alphabetically on the first change, so a synced vault sees whole-file churn.

**Shared fix direction.**
- Derive, never copy: `enum PDFAnnotationKey: String, CaseIterable` with preservation iterating `allCases`; one `BaseValue.sortKind` (Comparable); one media classification in Core (`DocumentKind.media(MediaKind)`); `DocumentKind.holdsLinks`; one `MarkdownBlockTemplate`; `EditorConfiguration.readableColumnWidth`.
- Write every `.obsidian/*.json` file through the member-preserving writer, renamed `ObsidianJSONObjectFile`, with each file declared in one `ObsidianConfigurationFile` enum.
- Block finders share one line-classification layer (`MarkdownLineSyntax`).

## 3. Largest offenders

Ranked by places one extension touches, weighted by how silently a missed place fails.

| # | Type or function | Numbers | What one extension costs | Findings |
| ---: | --- | --- | --- | --- |
| 1 | Plugin message protocol: `CommunityPluginHost.answerHostOperation` and `receiveNotification`, `CommunityPluginVaultBridge.respond`, the runtime's `messageHandlers` | 83 operation names (44 incoming in 3 Swift switches: 9 + 9 + 26; 39 outgoing answered in 3 JavaScript files: 28 + 2 + 9); 70 JavaScript call sites in 9 files; 1 fake host with its own copy | 3 to 5 places per operation; an unknown incoming operation answers `[:]` ([CommunityPluginHost.swift:910-912](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L910-L912)) | `OCP-PLUGIN-01`, `OCP-RUNTIME-01` |
| 2 | `DocumentKind` dispatch: `TabDocument`, `WorkspaceModel.load`, `TabDocumentView`, creation, icons, canvas cards, conflict preview, index | 16 places in 14 files; 5 `default:`; 3 optional sessions on `TabDocument` ([WorkspaceTabs.swift:13-15](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L13-L15)) | adding canvas touched 13 UI files plus Core | `OCP-SHELL-01`, `OCP-ARCH-01` |
| 3 | `BaseEvaluator` | 14 string switches over function and method names (12 in the evaluator, 2 in the prefilter); 41 `default:` lines, 23 over its own enums, 3 standing for one named case | a new function or method means finding every string; a new `BaseValue` case means reading 20 switches | `OCP-BASES-01`, `OCP-BASES-03` |
| 4 | `WorkspaceCommandList` and `GraphiteCommands` | 27 commands declared twice; 12 shortcuts written twice (text and `.keyboardShortcut`); Back/Forward declared 4 times | up to 4 places per command or shortcut; enablement already differs for `next-tab` and Toggle Source | `OCP-SHELL-02`, `OCP-ARCH-02` |
| 5 | `WorkspaceModel` cross-cutting coordinators: `followMoveInNavigation`, `forgetInNavigation`, `removeFromVaultList`, vault switch | 7 named calls per move, 5 per deletion, 5 stores per vault removal ([WorkspaceModel.swift:244-258](../../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258), [:1201-1222](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1222)); 5 graph and map properties on the aggregate | every new per-path or per-vault store edits the coordinator; one is already missing (folds) | `OCP-ARCH-03`, `OCP-SHELL-06`, `OCP-CANVAS-03` |
| 6 | Creation lists: `CreationKind`, the root's dispatch, sidebar New menu, folder menu, empty tab, palette, menu bar | 7 lists; the `isEnabled(.bases)`/`isEnabled(.canvas)` gate is repeated in 5; icons differ for one kind ("doc.text" against "square.and.pencil") | 7 edits per creatable item | `OCP-SHELL-05` |
| 7 | `BaseViewType` | 10 places in 6 files plus 2 map-only checks; 2 hand-kept lists of "types the user can create" | Kanban needed all of them | `OCP-BASES-02` |
| 8 | Theme probe vocabulary: `theme-probe.js` and `VaultThemeTokens.readValues` | 68 key forms, 159 keys once expanded; 27 callout types and 11 token classes each written in JavaScript and Swift; callout types in 5 places in total | a key renamed on one side silently stops the theme applying | `OCP-PLUGIN-03`, `OCP-READING-02` |
| 9 | Bookmark kinds (`Bookmark.type: String`) | 18 sites in `Bookmarks.swift` and `WorkspaceBookmarks.swift`, plus 6 in `VaultSidebarPanels.swift`; 2 modules; UI switches ending in `default:` | a new Obsidian kind needs edits in 3 files with no compiler help | `OCP-VAULT-01`, `OCP-SHELL-07` |
| 10 | Block-kind dispatch: reading `RenderedBlock`, Live Preview `LivePreviewBlock.Kind`, and the 5 Core block scanners | 6 switches with 3 `default:` (reading) + 6 switches with 1 `default:` (Live Preview) + 5 scanners with copied patterns | a new block kind or syntax touches 17 places; containers silently lose media, missing-embed rebuilds and Read Aloud | `OCP-READING-01`, `OCP-EDITOR-01`, `OCP-MDCORE-03` |

## 4. What to keep for this principle

These designs already meet the principle. The cleanup must imitate them and must not replace them.

| Design | Evidence | Why it meets the principle | Area |
| --- | --- | --- | --- |
| `DocumentKind` is the one extension table that maps file extensions to kinds | [VaultPath.swift:155-171](../../../Sources/GraphiteCore/VaultPath.swift#L155-L171) | One declaration classifies every file. Descriptors attach to this enum; no second classification is added (`MediaFileKind` folds into it). | VAULT, ARCH |
| `PDFEdit` is one closed command vocabulary, applied live and replayed on a baseline in an actor | [PDFPageManager.swift:21-24](../../../Sources/GraphiteApple/PDFPageManager.swift#L21-L24), [:331-351](../../../Sources/GraphiteApple/PDFPageManager.swift#L331-L351) | A new edit is one case. Only its three derived properties need exhaustive switches (`OCP-LECTURE-01`). | LECTURE |
| `CanvasNode.Content` carries an explicit `unknown(type:)` case, switched without `default:` | [CanvasFile.swift:88-96](../../../Sources/GraphiteCore/CanvasFile.swift#L88-L96), [:308-309](../../../Sources/GraphiteCore/CanvasFile.swift#L308-L309) | This is the "map once at the boundary, keep `unknown(raw)`" rule already in place. Plugin card types survive and are never synthesised. | CANVAS |
| `BaseValue.==` switches over the left value alone so the switch stays exhaustive | [BaseValue.swift:342-345](../../../Sources/GraphiteCore/BaseValue.swift#L342-L345) | The comment states the rule: a new case is a compile error, not a silent default. The 23 evaluator switches follow this pattern. | BASES |
| `DrawingFormat` and `PaperTemplate` switches without `default:` | [DrawingFileService.swift:45-53](../../../Sources/GraphiteApple/DrawingFileService.swift#L45-L53), [:117-123](../../../Sources/GraphiteApple/DrawingFileService.swift#L117-L123); `PDFTemplateGenerator.swift:108-144` | The compiler finds every site. These enums are the keys the `DrawingFileFormat` descriptors and `PaperPattern` values hang from. | INK, LECTURE |
| `CodeLanguage` is a data table with a `Features` option set | [CodeLanguages.swift:159-162](../../../Sources/GraphiteCore/CodeLanguages.swift#L159-L162); `CodeLanguages.swift:5-162` | A lexical language is data, not code. Formatting rules join this descriptor instead of comparing names (`OCP-MDCORE-01`). | MDCORE |
| Platform-neutral editor context-menu model rendered by a UIKit and an AppKit builder | [EditorContextMenu.swift:35-59](../../../Sources/GraphiteUI/EditorContextMenu.swift#L35-L59) | One list of entries serves both platforms and is tested on the Mac. It is the template for `WorkspaceCommand`, `EditorCommandDescriptor` and `InkSelectionAction`. | EDITOR |
| Vault bridge requests decoded into `Decodable` structs; an unknown operation is a typed failure | [CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44), [:75-76](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L75-L76) | This is the shape `OCP-PLUGIN-01` extends to the whole host: typed payloads and refusal of unknown names. | PLUGIN |
| `runtime.receive` never throws; unknown operations and handler failures become `{failure: {kind, message}}` | [community-plugin-runtime-plugins.js:1541-1550](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1550) | The JavaScript receiver already applies the rule the Swift host must adopt. | RUNTIME |
| ES5 plugins extend ES2015 classes through `callableClass` with exact `instanceof` | `community-plugin-runtime-plugins.js:47-85` (RUNTIME section 6, item 10) | Obsidian's class hierarchy is open for plugin subclasses without patching plugin code. | RUNTIME |
| A new runtime page per vault start, so every module-level registry lives exactly one session | [CommunityPluginHost.swift:371-375](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L371-L375) | Vault-switch cleanup in the runtime needs no per-feature code. This is the property `VaultLifecycleObserver` gives the Swift side. | RUNTIME |
| `Bookmark.fields` and `JSONValue` keep every field, so unknown kinds round-trip | `Bookmarks.swift:5-48` (VAULT section 6, item 9) | The stored truth stays raw while a typed `BookmarkKind` is added on top. | VAULT |
| `app.json` and `appearance.json` written member by member by a writer that preserves unknown keys | `ObsidianSettings.swift:264-330` (VAULT section 6, item 7) | The one writer every `.obsidian/*.json` file must use (`OCP-VAULT-02`). | VAULT, PLUGIN |
| Read Aloud quality, mode and passage-audio policies are closed enums with pure deciders | `ReadAloudQualityMode.swift`, `ReadAloudAudioCachePolicy.swift:8-70` (VOICE section 6, item 9) | Each policy is inputs-in, value-out over an exhaustive enum. The model-family descriptor follows the same shape. | VOICE |
| Narrow ports where the substitution is real: `MarkdownStyledTextView` (5 members), `RetainableMarkdownEditor` (3), `VideoCaptureSource`, the passage renderer and aligner seams | `MarkdownEditorStyling.swift:12-22`, `MarkdownEditorRetention.swift:10-18`, `VideoCapture.swift:81-102`, `ReadAloudPassagePreparation.swift:8-13` | Each is extended by adding an implementation, and each has two implementations or a stated test reason. This is the RULES.md test that `DocumentSession`, `DrawingFileFormat` and `RecordingSession` must pass. | EDITOR, LECTURE, VOICE |
| `DocumentPlaceStore.forgetVault` and `VaultLibrary`'s tolerant list | `WorkspacePlaces.swift:79-112`, `VaultLibrary.swift:67-109` (SHELL section 6) | A per-vault store that owns its own forgetting. `VaultLifecycleObserver` generalises this so the coordinator stops naming stores. | SHELL |

## 5. Index of findings

52 findings (3 High, 30 Medium, 19 Low), taken from [findings-index.md](../findings-index.md) and ordered by severity, then ID. Severities are the auditors' own; section 7 records where this synthesis weighs one differently.

| ID | Area | Severity | Title |
| --- | --- | --- | --- |
| [OCP-PLUGIN-01](../areas/plugin.md#ocp-plugin-01-the-runtime-message-protocol-is-83-untyped-operation-names-in-parallel-switches-unknown-operations-succeed) | PLUGIN | High | The runtime message protocol is 83 untyped operation names in parallel switches; unknown operations succeed |
| [OCP-RUNTIME-01](../areas/runtime.md#ocp-runtime-01-83-message-names-and-their-payloads-are-literals-kept-in-step-by-hand-in-three-places) | RUNTIME | High | 83 message names and their payloads are literals kept in step by hand in three places |
| [OCP-SHELL-01](../areas/shell.md#ocp-shell-01-a-new-document-kind-touches-13-ui-files-and-three-default-branches-hide-it-from-the-compiler) | SHELL | High | A new document kind touches 13 UI files, and three `default:` branches hide it from the compiler |
| [OCP-ARCH-01](../cross-cutting/architecture.md#ocp-arch-01-a-new-document-kind-touches-at-least-16-places-in-14-files-five-of-which-hide-it-behind-default) | ARCH | Medium | A new document kind touches at least 16 places in 14 files, five of which hide it behind `default:` |
| [OCP-ARCH-02](../cross-cutting/architecture.md#ocp-arch-02-commands-are-declared-twice-with-shortcuts-written-once-as-key-equivalents-and-once-as-display-text) | ARCH | Medium | Commands are declared twice, with shortcuts written once as key equivalents and once as display text |
| [OCP-ARCH-03](../cross-cutting/architecture.md#ocp-arch-03-cross-cutting-duties-are-coded-as-calls-from-the-coordinator-to-each-feature) | ARCH | Medium | Cross-cutting duties are coded as calls from the coordinator to each feature |
| [OCP-BASES-01](../areas/bases.md#ocp-bases-01-the-expression-vocabulary-is-spread-across-14-string-switches) | BASES | Medium | The expression vocabulary is spread across 14 string `switch`es |
| [OCP-BASES-02](../areas/bases.md#ocp-bases-02-a-new-view-type-touches-10-places-in-6-files) | BASES | Medium | A new view type touches 10 places in 6 files |
| [OCP-BASES-03](../areas/bases.md#ocp-bases-03-default-over-the-apps-own-enums-hides-new-cases-in-23-places-of-the-evaluator) | BASES | Medium | `default:` over the app's own enums hides new cases in 23 places of the evaluator |
| [OCP-CANVAS-01](../areas/canvas.md#ocp-canvas-01-file-card-kind-dispatch-is-repeated-in-four-places-two-with-default) | CANVAS | Medium | File-card kind dispatch is repeated in four places, two with `default:` |
| [OCP-CANVAS-02](../areas/canvas.md#ocp-canvas-02-the-json-canvas-vocabulary-is-spelled-in-three-independent-places) | CANVAS | Medium | The JSON Canvas vocabulary is spelled in three independent places |
| [OCP-EDITOR-01](../areas/editor.md#ocp-editor-01-a-new-rendered-block-kind-touches-six-switches-one-of-which-hides-it) | EDITOR | Medium | A new rendered-block kind touches six switches, one of which hides it |
| [OCP-EDITOR-02](../areas/editor.md#ocp-editor-02-a-new-formatting-command-touches-seven-places-with-drifting-titles) | EDITOR | Medium | A new formatting command touches seven places with drifting titles |
| [OCP-INK-01](../areas/ink.md#ocp-ink-01-a-drawing-format-is-dispatched-at-five-places-and-adding-one-touches-all-of-them) | INK | Medium | A drawing format is dispatched at five places, and adding one touches all of them |
| [OCP-INK-02](../areas/ink.md#ocp-ink-02-graphites-canvas-tools-are-three-parallel-booleans-in-five-places) | INK | Medium | Graphite's canvas tools are three parallel booleans in five places |
| [OCP-INK-03](../areas/ink.md#ocp-ink-03-voiceover-actions-are-dispatched-by-menu-titles) | INK | Medium | VoiceOver actions are dispatched by menu titles |
| [OCP-LECTURE-01](../areas/lecture.md#ocp-lecture-01-pdfedits-derived-properties-use-default-so-a-new-edit-case-is-silently-treated-as-no-page-tree-change-and-no-changed-page) | LECTURE | Medium | `PDFEdit`'s derived properties use `default:`, so a new edit case is silently treated as no page-tree change and no changed page |
| [OCP-LECTURE-02](../areas/lecture.md#ocp-lecture-02-audio-and-video-are-branched-by-hand-in-9-recordingcontroller-members) | LECTURE | Medium | Audio and video are branched by hand in 9 `RecordingController` members |
| [OCP-LECTURE-03](../areas/lecture.md#ocp-lecture-03-graphites-annotation-keys-are-declared-once-but-re-listed-by-hand-for-page-tree-preservation) | LECTURE | Medium | Graphite's annotation keys are declared once but re-listed by hand for page-tree preservation |
| [OCP-MDCORE-01](../areas/mdcore.md#ocp-mdcore-01-code-formatting-identifies-languages-by-name-strings-in-12-places) | MDCORE | Medium | Code formatting identifies languages by name strings in 12 places |
| [OCP-MDCORE-03](../areas/mdcore.md#ocp-mdcore-03-a-new-block-syntax-has-to-be-taught-to-five-independent-scanners) | MDCORE | Medium | A new block syntax has to be taught to five independent scanners |
| [OCP-PLUGIN-02](../areas/plugin.md#ocp-plugin-02-each-plugin-contributed-capability-is-added-in-four-places) | PLUGIN | Medium | Each plugin-contributed capability is added in four places |
| [OCP-PLUGIN-03](../areas/plugin.md#ocp-plugin-03-the-theme-probes-vocabulary-is-declared-twice-in-javascript-and-in-swift) | PLUGIN | Medium | The theme probe's vocabulary is declared twice, in JavaScript and in Swift |
| [OCP-READING-01](../areas/reading.md#ocp-reading-01-a-new-reading-block-kind-touches-six-switches-in-one-file-three-hidden-behind-default) | READING | Medium | A new reading block kind touches six switches in one file, three hidden behind `default:` |
| [OCP-RUNTIME-02](../areas/runtime.md#ocp-runtime-02-adding-a-listener-gated-plugin-event-touches-four-places) | RUNTIME | Medium | Adding a listener-gated plugin event touches four places |
| [OCP-RUNTIME-03](../areas/runtime.md#ocp-runtime-03-feature-files-join-the-runtime-by-mutating-other-files-objects-in-script-order) | RUNTIME | Medium | Feature files join the runtime by mutating other files' objects in script order |
| [OCP-SHELL-02](../areas/shell.md#ocp-shell-02-27-commands-are-declared-twice-in-the-palette-and-in-the-menu-bar-and-shortcut-labels-are-typed-in-three-places) | SHELL | Medium | 27 commands are declared twice, in the palette and in the menu bar, and shortcut labels are typed in three places |
| [OCP-SHELL-03](../areas/shell.md#ocp-shell-03-a-new-sidebar-panel-touches-7-branch-sites-in-4-files-and-the-list-falls-back-to-the-file-tree-silently) | SHELL | Medium | A new sidebar panel touches 7 branch sites in 4 files, and the list falls back to the file tree silently |
| [OCP-SHELL-05](../areas/shell.md#ocp-shell-05-what-can-be-created-is-listed-seven-times-each-copy-repeating-the-plugin-gating) | SHELL | Medium | What can be created is listed seven times, each copy repeating the plugin gating |
| [OCP-SHELL-06](../areas/shell.md#ocp-shell-06-forget-a-removed-vault-names-its-per-vault-state-by-hand-so-new-per-vault-state-is-not-forgotten) | SHELL | Medium | "Forget a removed vault" names its per-vault state by hand, so new per-vault state is not forgotten |
| [OCP-VAULT-01](../areas/vault.md#ocp-vault-01-bookmark-kinds-are-a-stringly-typed-vocabulary-repeated-in-18-places) | VAULT | Medium | Bookmark kinds are a stringly-typed vocabulary repeated in 18 places |
| [OCP-VAULT-02](../areas/vault.md#ocp-vault-02-obsidian-settings-files-are-written-by-four-different-json-writers) | VAULT | Medium | Obsidian settings files are written by four different JSON writers |
| [OCP-VOICE-01](../areas/voice.md#ocp-voice-01-a-new-neural-model-family-is-wired-in-7-places-across-3-files) | VOICE | Medium | A new neural model family is wired in 7 places across 3 files |
| [OCP-BASES-04](../areas/bases.md#ocp-bases-04-two-hand-kept-copies-of-the-cross-type-sort-rank) | BASES | Low | Two hand-kept copies of the cross-type sort rank |
| [OCP-BASES-05](../areas/bases.md#ocp-bases-05-the-value-type-vocabulary-sent-to-the-plugin-runtime-is-a-second-hand-kept-list) | BASES | Low | The value-type vocabulary sent to the plugin runtime is a second hand-kept list |
| [OCP-CANVAS-03](../areas/canvas.md#ocp-canvas-03-graph-and-map-features-add-their-caches-and-reset-lines-to-workspacemodel) | CANVAS | Low | Graph and map features add their caches and reset lines to `WorkspaceModel` |
| [OCP-EDITOR-03](../areas/editor.md#ocp-editor-03-inserted-block-templates-have-two-owners) | EDITOR | Low | Inserted block templates have two owners |
| [OCP-EDITOR-04](../areas/editor.md#ocp-editor-04-the-readable-column-and-image-type-tables-are-repeated-per-platform-and-per-call) | EDITOR | Low | The readable column and image-type tables are repeated per platform and per call |
| [OCP-INK-04](../areas/ink.md#ocp-ink-04-default-over-the-apps-own-enums-hides-new-cases-and-one-mapping-is-wrong-by-construction) | INK | Low | `default:` over the app's own enums hides new cases, and one mapping is wrong by construction |
| [OCP-LECTURE-04](../areas/lecture.md#ocp-lecture-04-a-paper-template-is-added-in-three-places) | LECTURE | Low | A paper template is added in three places |
| [OCP-LECTURE-05](../areas/lecture.md#ocp-lecture-05-diagnostic-record-kinds-are-free-strings-shared-with-tests-and-a-shell-script) | LECTURE | Low | Diagnostic record kinds are free strings shared with tests and a shell script |
| [OCP-MDCORE-02](../areas/mdcore.md#ocp-mdcore-02-three-default-branches-cover-the-projects-own-enums) | MDCORE | Low | Three `default:` branches cover the project's own enums |
| [OCP-PLUGIN-04](../areas/plugin.md#ocp-plugin-04-core-plugin-descriptions-for-the-runtime-are-a-hard-coded-list) | PLUGIN | Low | Core plugin descriptions for the runtime are a hard-coded list |
| [OCP-READING-02](../areas/reading.md#ocp-reading-02-callout-type-vocabulary-is-declared-in-four-places) | READING | Low | Callout type vocabulary is declared in four places |
| [OCP-READING-03](../areas/reading.md#ocp-reading-03-media-extensions-are-listed-twice-and-the-lists-disagree) | READING | Low | Media extensions are listed twice, and the lists disagree |
| [OCP-READING-04](../areas/reading.md#ocp-reading-04-propertyvalue-is-switched-in-six-places-of-the-properties-editor-three-with-default) | READING | Low | `PropertyValue` is switched in six places of the properties editor, three with `default:` |
| [OCP-READING-05](../areas/reading.md#ocp-reading-05-inspector-panels-are-declared-in-four-places-and-the-empty-state-text-names-four-of-seven) | READING | Low | Inspector panels are declared in four places and the empty-state text names four of seven |
| [OCP-SHELL-04](../areas/shell.md#ocp-shell-04-a-configurable-plugins-settings-page-needs-a-list-entry-and-a-switch-case-a-missed-case-shows-core-plugins-silently) | SHELL | Low | A configurable plugin's settings page needs a list entry and a switch case; a missed case shows Core Plugins silently |
| [OCP-SHELL-07](../areas/shell.md#ocp-shell-07-bookmark-kinds-are-compared-as-strings-in-9-places) | SHELL | Low | Bookmark kinds are compared as strings in 9 places |
| [OCP-VAULT-03](../areas/vault.md#ocp-vault-03-adding-a-search-operator-touches-four-parallel-switches-two-of-which-hide-new-cases-behind-default) | VAULT | Low | Adding a search operator touches four parallel switches, two of which hide new cases behind `default:` |
| [OCP-VAULT-04](../areas/vault.md#ocp-vault-04-which-files-hold-links-is-decided-in-three-places) | VAULT | Low | "Which files hold links" is decided in three places |
| [OCP-VOICE-02](../areas/voice.md#ocp-voice-02-voice-quality-groups-and-platform-names-are-display-strings-used-as-identities) | VOICE | Low | Voice-quality groups and platform names are display strings used as identities |

## 6. Rules for new code

Each rule can be checked in code review or by a script. "Own enum" means an enum declared under `Sources/`. RULES.md's limit on protocols applies to every rule: a protocol is added only where two or more implementations, or a stated test or isolation need, exist.

**OCP 1 — One case, one descriptor, one table.** Adding a document kind, sidebar or inspector panel, creatable item, settings page, Bases view type, block kind, drawing format, neural model family or core plugin must be one enum case plus one descriptor value, registered in one table by the module that owns the feature. Menus, pickers, empty-state text and "what can be created" lists must be derived from that table.
- *How to check:* the diff that adds a case touches the enum's file, the new descriptor and nothing else. Grep the enum name for parallel `switch`es, `if kind == .x` chains or literal arrays of its cases outside the descriptor file; each hit fails review.
- *Answers:* `OCP-SHELL-01`, `OCP-ARCH-01`, `OCP-SHELL-03`, `OCP-SHELL-04`, `OCP-SHELL-05`, `OCP-READING-05`, `OCP-BASES-02`, `OCP-CANVAS-01`, `OCP-INK-01`, `OCP-VOICE-01`, `OCP-PLUGIN-04`, `OCP-EDITOR-01`, `OCP-LECTURE-04`.

**OCP 2 — No `default:` over an own enum.** A `switch` over an own enum must name every case: no `default:`, no catch-all `case .x:` for an enum with associated values, and no `case .x where condition` followed by `default:`. A condition belongs inside the case body. An `if/else` chain over an enum's cases ending in a fallback branch is a `switch` with a hidden `default:` and is refused for the same reason.
- *How to check:* a CI script lists every `default:` whose switch subject's type is declared under `Sources/` and fails on any hit not on an allow-list with a same-line reason. Review rejects `if panel == .a … else if panel == .b … else`.
- *Answers:* `OCP-BASES-03`, `OCP-LECTURE-01`, `OCP-MDCORE-02`, `OCP-INK-04`, `OCP-READING-01`, `OCP-READING-04`, `OCP-VAULT-03`, `OCP-EDITOR-01`, `OCP-EDITOR-02`, `OCP-CANVAS-01`, `OCP-SHELL-01`, `OCP-SHELL-03`, `OCP-SHELL-04`, `OCP-ARCH-01`.

**OCP 3 — Per-kind behaviour is data on the descriptor, not an identity test.** A decision that differs by kind (acronym policy, sentence grouping, formatting style, keyword rules, stop rule, size bound, "reads the index", "holds links") must be a property of the kind's descriptor, read through one exhaustive switch. It must never be an equality test such as `== .pocketTTS`, `language.name == "shell"` or `if let videoRecording` repeated across members.
- *How to check:* grep `== \.` and `!= \.` against own enums with more than two cases, and `.name ==` or `.contains(language.name)`. Each hit outside the descriptor fails review.
- *Answers:* `OCP-VOICE-01`, `OCP-MDCORE-01`, `OCP-LECTURE-02`, `OCP-EDITOR-01`, `OCP-VAULT-04`.

**OCP 4 — External strings are mapped once, at the boundary, to an enum with `unknown(raw)`.** A value read from a file format, manifest or settings file (bookmark kind, canvas node type and keys, voice platform, Bases function and method names, search operator) must be decoded once in Core into an own enum with an explicit `unknown(String)` case. The raw fields stay the stored truth so unknown values round-trip. No code outside the mapping compares the raw string.
- *How to check:* grep `== "` and `case "` in `Sources/`. A literal from an external vocabulary appears only in the file that declares the mapping enum.
- *Answers:* `OCP-VAULT-01`, `OCP-SHELL-07`, `OCP-CANVAS-02`, `OCP-VOICE-02`, `OCP-BASES-01`, `OCP-MDCORE-01`, `OCP-VAULT-03`.

**OCP 5 — A vocabulary shared with JavaScript, CSS or a script is generated from one declaration.** Message operation names and payload fields, theme-probe keys, callout types, code token classes, `BaseValue` wire types and diagnostic record kinds must be declared once: a Swift enum with `String` raw values, or one JSON schema resource. The JavaScript constants, CSS rule lists and the Node fake host's switch must be generated from it, and CI must regenerate and diff.
- *How to check:* no operation-name or probe-key string literal in Swift outside the declaring enum, and no literal operation name in runtime JavaScript (only generated constants). A contract test asserts that each declared operation has a handler on its receiving side.
- *Answers:* `OCP-PLUGIN-01`, `OCP-RUNTIME-01`, `OCP-PLUGIN-03`, `OCP-BASES-05`, `OCP-READING-02`, `OCP-RUNTIME-02`, `OCP-LECTURE-05`.

**OCP 6 — An unknown operation is a failure, never a success.** Every receiver of a message protocol (the Swift host, the vault bridge, the runtime, the fake host) must answer an operation it does not know with the typed `unknownOperation` failure. Routing must be by the decoded enum, not by a name prefix.
- *How to check:* the decoding `switch` has an `unknown` case that returns the failure; no receiver returns `[:]` or `{}` from a fallback. Grep `hasPrefix("` used for routing.
- *Answers:* `OCP-PLUGIN-01`, `OCP-RUNTIME-01`.

**OCP 7 — Each command surface's commands are declared once and rendered everywhere.** The workspace (`WorkspaceCommand`), the editor (`EditorCommandDescriptor`) and the ink selection (`InkSelectionAction`) each declare a command once: identifier, title, symbol, `KeyboardShortcut`, availability, placement and action. The palette, menu bar, toolbars, empty tab, context menus, key commands and accessibility actions must be built from that declaration. Persisted identifiers must be the cases' raw values.
- *How to check:* `.keyboardShortcut(` and shortcut glyph text (`"⌘`) appear only where the catalogue is rendered. No `Button("…")` or `PaletteCommand(id:` duplicates a catalogue entry. No dispatch on `action.title` or any other display string.
- *Answers:* `OCP-SHELL-02`, `OCP-ARCH-02`, `OCP-SHELL-05`, `OCP-EDITOR-02`, `OCP-EDITOR-03`, `OCP-INK-03`.

**OCP 8 — Cross-cutting duties are opt-in by conformance; the coordinator names no feature.** A store that keeps state per path or per vault must conform to `VaultPathMoveObserver` (`followMove(from:to:)`, `forget(inside:)`) and/or `VaultLifecycleObserver` (`vaultWillClose()`, `vaultWasRemoved(identifier:)`), registered at composition. Move, delete, vault switch, vault removal and memory release must iterate the registered list.
- *How to check:* `followMoveInNavigation`, `forgetInNavigation`, `removeFromVaultList` and the vault switch contain a loop over observers and no feature-named calls. A new store's diff adds a conformance and a registration, never a line in the coordinator.
- *Answers:* `OCP-ARCH-03`, `OCP-SHELL-06`, `OCP-CANVAS-03`, `OCP-PLUGIN-02`.

**OCP 9 — A feature's state lives in the feature, not in the application aggregate.** A feature or core-plugin view (graph, map, plugin contributions) must keep its caches and presentation state in its own model, owned per vault. It must not add stored properties to `WorkspaceModel` or reset lines to its vault switch. Plugin contributions are one `Decodable` value replaced whole.
- *How to check:* the diff of a new feature adds no stored property to `WorkspaceModel` and no line to `openVault`. Grep for new `var` declarations in `WorkspaceModel.swift`.
- *Answers:* `OCP-CANVAS-03`, `OCP-PLUGIN-02`, `OCP-SHELL-06`.

**OCP 10 — One fact, one declaration; lists of an enum's members come from `allCases`.** A table that restates another (sort ranks, annotation keys to preserve, media extensions, readable-column width, inserted block templates, kinds that hold links, settings-file writers, block-syntax patterns) must be derived from the one declaration through `CaseIterable`, a computed property or a shared function. Two copies that "must match" are refused.
- *How to check:* grep a literal array of an enum's cases or of extension strings; it appears once. A comment saying "must match" or "keep in step with" fails review.
- *Answers:* `OCP-BASES-04`, `OCP-LECTURE-03`, `OCP-READING-03`, `OCP-EDITOR-03`, `OCP-EDITOR-04`, `OCP-VAULT-02`, `OCP-VAULT-04`, `OCP-MDCORE-03`.

**OCP 11 — Mutually exclusive modes are one enum.** A set of modes of which only one is on (canvas tools, presentations, view modes) must be one enum property changed through intent methods. Parallel `Bool` properties that clear each other in `didSet` are refused.
- *How to check:* review rejects two or more `Bool` properties whose `didSet` assigns `false` to the others. A new mode is one new case.
- *Answers:* `OCP-INK-02`.

**OCP 12 — Extension by registration, never by mutating another file's objects or relying on load order.** A runtime feature file must add its handlers through one registration call (`HostMessageRouter.register`) that is valid whenever it runs before `runtime.start`. It must not copy into, assign into or patch another file's objects or prototypes.
- *How to check:* grep `Object.assign(messageHandlers`, `runtime.messageHandlers[`, `runtime.basesMessageHandlers` and `.prototype.<member> =` across runtime files. The script order in `index.html` changes no handler table.
- *Answers:* `OCP-RUNTIME-03`, `OCP-RUNTIME-02`.

**OCP 13 — Identities and persisted values never come from display text.** A grouping key, dispatch key, persisted identifier or user-facing title must not be derived from words shown to the user, and words must not be derived from a persisted raw value. Forbidden examples: grouping voices by `qualityDescription`, dispatching on a menu title, `rawValue.capitalized` as a title. Titles come from the string catalogue keyed by the case.
- *How to check:* grep `.capitalized` on `rawValue`, `Dictionary(grouping:` by a description string, and `switch` over `title`.
- *Answers:* `OCP-VOICE-02`, `OCP-INK-03`, `OCP-LECTURE-04`, `OCP-ARCH-02`.

**OCP 14 — A descriptor protocol earns its place with a shared contract suite.** Where kinds carry a real substitution (`DocumentSession` for tab sessions, `DrawingFileFormat` for PNG/SVG/PDF, `RecordingSession` for audio/video), the protocol must stay small (at most about 7 members). One parameterised contract test suite must run every conforming type. Kinds without such a substitution stay value-type descriptors behind one exhaustive switch.
- *How to check:* each new protocol has two or more conformers, or a stated test need, and one contract suite under the test-support module that every conformer runs. Count the protocol's requirements.
- *Answers:* `OCP-ARCH-01`, `OCP-SHELL-01`, `OCP-INK-01`, `OCP-LECTURE-02`.

Rules from the starting set that are kept as written: "adding a screen/feature/source = one enum case + one descriptor" (OCP 1), "no `default:` over the app's own enums; external values mapped once to `unknown(raw)`; shared vocabularies generated from one typed enum" (OCP 2, 4, 5), "cross-cutting duties opt-in by conformance" (OCP 8), "one declaration per concept; every other list derived" (OCP 10). They are sharpened by the findings: OCP 2 adds `where`-guarded cases and `if/else` chains, OCP 6 and OCP 12 are new, and the "more than one implementation needs a contract suite" rule is applied to descriptors in OCP 14.

## 7. Corrections

| # | Disagreement | What the snapshot shows | Settled |
| ---: | --- | --- | --- |
| 1 | `OCP-SHELL-01` counts a new document kind as 13 UI files with 3 `default:` branches (High). `OCP-ARCH-01` counts 16 places in 14 files with 5 `default:` branches (Medium). | SHELL's three `default:` sites are at [WorkspaceTabs.swift:376](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L376), [WorkspacePanes.swift:553](../../../Sources/GraphiteUI/WorkspacePanes.swift#L553) and [ConflictVersionsSheet.swift:354](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L354). ARCH adds [CanvasPane.swift:202](../../../Sources/GraphiteUI/CanvasPane.swift#L202) and [CanvasCardViews.swift:281](../../../Sources/GraphiteUI/CanvasCardViews.swift#L281), which SHELL's method excluded as canvas-feature files. ARCH also counts `VaultPath.swift`, `MarkdownPreview.swift` and `VaultIndex.swift`. A missed site compiles and changes behaviour silently: a kind missing from [WorkspaceFileManagement.swift:105-106](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L105-L106) is moved before its typed links are indexed. | The complete count is ARCH's: 16 places in 14 files, 5 `default:`. This synthesis weighs the finding as High, as SHELL does, because of the silent run-time failure. The index keeps each auditor's severity. |
| 2 | `OCP-VAULT-01` counts bookmark kinds as 18 places; `OCP-SHELL-07` counts 9. | VAULT counts 15 sites in [Bookmarks.swift](../../../Sources/GraphiteCore/Bookmarks.swift#L93-L104) plus 3 in `WorkspaceBookmarks.swift:63-74`. SHELL counts 6 sites in `VaultSidebarPanels.swift` (for example [VaultSidebarPanels.swift:352](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L352)) plus `WorkspaceBookmarks.swift`. Each covers a different subset; `WorkspaceBookmarks.swift` is in both. | Both counts are right for their scope. The vocabulary spans 3 files in 2 modules: 18 + 6 = 24 sites with `WorkspaceBookmarks.swift` counted once. |
| 3 | `OCP-READING-02` says callout types are declared in 4 places. | `OCP-PLUGIN-03` shows a fifth copy: the 27-name array at [theme-probe.js:8-10](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L8-L10), the same names as the keys of [VaultThemeTokens.swift:410-419](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L410-L419). | 5 places. The fix (`ObsidianCalloutType` in Core) must also generate the theme probe's list. |
| 4 | `OCP-RUNTIME-01` cites `receiveNotification` as [CommunityPluginHost.swift:938-1000](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L938-L1000); `OCP-PLUGIN-01` cites 938-1052. | The switch runs to its `default: break` at [CommunityPluginHost.swift:1050-1051](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1050-L1051). | PLUGIN's range is right. The count of 26 notification names stands. |
| 5 | The BASES verdict row says 12 string switches and 20 `default:` over own enums. `OCP-BASES-01` and `OCP-BASES-03` say 14 and 23. | 12 switches are in `BaseEvaluator.swift` and 2 in `BaseRecordPrefilter.swift`. 20 `default:` branches cover `BaseValue` and 3 cover `BaseBinaryOperator` (for example [BaseEvaluator.swift:542](../../../Sources/GraphiteCore/BaseEvaluator.swift#L542), [:639](../../../Sources/GraphiteCore/BaseEvaluator.swift#L639)). | The finding titles (14 and 23) are the app-level counts; the verdict row counts subsets. |
| 6 | The LECTURE verdict counts 3 `default:` branches over own enums (`PDFEdit`); the LECTURE metrics table counts 5. | The two extra sites switch over `RecordingState`: `RecordingControls.swift:64` and `RecordingController.swift:540` (read). No finding names them. | 5 sites. They fall under OCP 2 and must be cleaned with `OCP-LECTURE-01`. |
