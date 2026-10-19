# Vault storage, paths, settings, links, search query, index and file operations (VAULT)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteCore/` (26 files: storage, paths, settings, links, search query, navigation, properties, templates), `Sources/GraphiteIndex/` (5 files: index, search, graph, places, file operations), `Sources/GraphiteApple/FileVersionConflicts.swift`, `Sources/GraphiteApple/FolderAccess.swift`, `Sources/GraphiteBenchmarks/main.swift`; 34 files, 9789 physical lines, 7303 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Mixed | Most files hold one small value type with one rule, but `VaultStore` carries 10 responsibilities in 340 code lines and `VaultIndex` spreads 12 responsibilities over 633 code lines plus 4 extension files. |
| O | Mixed | `DocumentKind` is the one extension table, but bookmark kinds are 18 string-literal sites in 2 modules, Obsidian settings files use 4 different JSON writers, and 4 parallel switches over `SearchScope` (2 with `default:`) must change for a new operator. |
| L | Mostly strong | One protocol (`ConflictVersionStore`) with a test fake that differs from production in 4 places; two implementations of "how many files share this name" disagree for non-ASCII capitals (BUG-VAULT-01). |
| I | Mixed | `VaultStore` exposes 24 public methods (plus 8 in 3 extension files) while `MarkdownSession` uses 5 and `CanvasSession` 4; `ConflictVersionStore` mixes 3 discovery and 3 destructive requirements. |
| D | Mixed | Core value types are pure and take their inputs, but logic reaches `FileManager.default` 68 times (reconnaissance count), constructs `AtomicFileWriter()` inline 5 times, and reads `Date.now` and `TimeZone.current` through defaults. |
| Clean code | Mixed | Comments state current rules almost everywhere, but 13 functions exceed 40 code lines, the frontmatter regular expression exists in 4 copies, SHA-256 hex formatting in 5, and 44 thrown error sentences carry user-visible English from Core, Index and Apple code. |

## 1. Summary

**What the area does.** This area is Graphite's storage contract with the user's folder and the derived data built from it. Five parts:

- **Vault I/O.** `VaultPath` validates and normalizes every path. `AtomicFileWriter` stages, flushes, revision-checks and replaces files under `NSFileCoordinator`. `VaultStore` (an actor) lists folders, reads and writes files, moves, copies and deletes them, and reads and writes six Obsidian settings files.
- **Folder access and versions** (GraphiteApple). `FolderAccess` and `VaultLocator` handle security-scoped bookmarks. `VaultMonitor` is the vault's `NSFilePresenter`. `FileProviderConflictVersions` wraps `NSFileVersion`.
- **Pure Obsidian-compatible rules** (Core value types). Settings (`ObsidianSettings`, `AttachmentResolver`), links (`NoteLinkScanner`, `LinkRewriter`, `LinkCompletion`, `Mentions`, `LinkGraph`), properties (`NoteProperties`, `PropertyRenaming`), search syntax and matching (`SearchQuery.swift`), navigation state (`TabLayout`, `NavigationHistory`, `DocumentPlaceMemory`, `VaultList`), templates and dates (`Templates.swift`, `MomentDateFormat`), and recovery snapshots (`FileRecoveryStore`).
- **The disposable index** (`VaultIndex`, a GRDB/SQLite actor). It scans, refreshes, resolves links, finds backlinks, searches and builds the graph.
- **Link-preserving moves** (`VaultFileOperations`). It plans link rewrites through the index and applies them with revision checks.

**Shape.** Three files are large: `SearchQuery.swift` (944 code lines, 7 concepts), `VaultIndex.swift` (633) and `VaultSearch.swift` (559). Two types have grown into hubs: `VaultStore` and `VaultIndex`. The remaining 28 files are small, focused and mostly pure.

**The three biggest problems.**
1. **Two implementations of one rule disagree, and a rename breaks links because of it.** `VaultFileOperations` counts files with a name through `name_key COLLATE NOCASE`, which folds ASCII only ([VaultFileOperations.swift:389-395](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L389-L395)). The resolver matches names through `folded_name`, which folds every letter ([VaultIndex.swift:393](../../../Sources/GraphiteIndex/VaultIndex.swift#L393)). A rename to `Éclair.md` beside an existing `éclair.md` therefore rewrites links to a bare name that the resolver then finds ambiguous (BUG-VAULT-01). The same pattern recurs elsewhere: `GraphLinkResolver` re-implements `resolvedPaths` in memory, and the frontmatter regular expression exists 4 times.
2. **`VaultStore` and `VaultIndex` are hubs.** `VaultStore` mixes file management, folder listing, naming policy and six settings-file formats behind one 24-method public surface, and every session receives all of it. `VaultIndex` owns schema, cache placement, scanning, refresh, link queries, search, quick switcher, tags, properties, graph and places. Its scan state is a boolean, an optional and a dictionary that must be reset together ([VaultIndex.swift:56-63](../../../Sources/GraphiteIndex/VaultIndex.swift#L56-L63), [VaultIndex.swift:577-581](../../../Sources/GraphiteIndex/VaultIndex.swift#L577-L581)).
3. **A failed read of a settings file becomes "nothing configured".** `VaultStore.configurationData` swallows read errors with `try?` ([VaultStore.swift:254-257](../../../Sources/GraphiteCore/VaultStore.swift#L254-L257)). An unreadable or over-1-MiB `bookmarks.json` therefore shows as no bookmarks with no error (BUG-VAULT-02). `propertyTypes`, `templateSettings`, `dailyNoteSettings` and `communityPluginList` read the same way.

**The three best parts.**
1. **`AtomicFileWriter` is a complete safe-write primitive** ([AtomicFileWriter.swift:67-127](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L67-L127)). It stages outside the vault on the destination volume, orders the bytes with `F_BARRIERFSYNC`, compares the full-content revision inside the coordinated write accessor, replaces atomically and flushes with `F_FULLFSYNC`. Every vault write, including settings files and link rewrites, goes through it.
2. **`VaultPath` closes path escapes at construction.** It normalizes to NFC, splits on `/` scalars and refuses `..` beyond the root ([VaultPath.swift:40-53](../../../Sources/GraphiteCore/VaultPath.swift#L40-L53)). Resolution walks symbolic links component by component and checks containment byte by byte ([VaultPath.swift:84-121](../../../Sources/GraphiteCore/VaultPath.swift#L84-L121)). Decoding re-validates stored paths ([VaultPath.swift:33-36](../../../Sources/GraphiteCore/VaultPath.swift#L33-L36)).
3. **Obsidian files are merged, never overwritten.** `app.json` is rewritten member by member, keeping every other value's text, position and duplicate-key semantics ([ObsidianSettings.swift:224-233](../../../Sources/GraphiteCore/ObsidianSettings.swift#L224-L233), [ObsidianSettings.swift:264-330](../../../Sources/GraphiteCore/ObsidianSettings.swift#L264-L330)). Frontmatter edits splice only the changed properties and verify the result reads back ([NoteProperties.swift:344-417](../../../Sources/GraphiteCore/NoteProperties.swift#L344-L417)). Link rewrites keep each link's written style and refuse to touch a note whose links they cannot locate ([VaultFileOperations.swift:168-199](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L168-L199)).

**Earlier-pass claims (`Docs/SOLID.md` 2026-09-30, `Docs/Architecture.md`).**

| Claim | Holds? | Evidence |
| --- | --- | --- |
| SOLID.md: `AtomicFileWriter` owns coordinated revision checks and publication | Holds | [AtomicFileWriter.swift:76-91](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L76-L91) |
| SOLID.md: `AttachmentResolver` owns attachment policy | Holds for the folder; the link-format rule (shortest/relative/absolute) is implemented twice | [AttachmentResolver.swift:19-25](../../../Sources/GraphiteCore/AttachmentResolver.swift#L19-L25) and [LinkCompletion.swift:359-366](../../../Sources/GraphiteCore/LinkCompletion.swift#L359-L366) |
| SOLID.md: `DocumentKind` centralizes extension classification | Mostly holds; 4 local `.md` checks remain | [VaultPath.swift:155-171](../../../Sources/GraphiteCore/VaultPath.swift#L155-L171); local checks at [Templates.swift:81](../../../Sources/GraphiteCore/Templates.swift#L81), [Templates.swift:92](../../../Sources/GraphiteCore/Templates.swift#L92), [Mentions.swift:18](../../../Sources/GraphiteCore/Mentions.swift#L18), [SearchQuery.swift:903](../../../Sources/GraphiteCore/SearchQuery.swift#L903) |
| SOLID.md: `ConflictVersionStore` specifies revision protection, absent destinations and selective removal | Holds | [FileVersionConflicts.swift:12-31](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L12-L31) |
| SOLID.md: the conflict test store does not match production failure handling | Holds; the divergences are still present | `try outcome?.get()` at [TestConflictVersionStore.swift:87](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L87); removal without coordination at [TestConflictVersionStore.swift:98-100](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L98-L100); production versions at [FileVersionConflicts.swift:159-169](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L159-L169) |
| SOLID.md: the Bases lookup-failure check sits outside the protocol | Holds | `throwIfLookupFailed` at [BaseRecordQueries.swift:241-267](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L241-L267), called by [BaseDocumentModel.swift:215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L215) |
| SOLID.md: sessions receive the whole `VaultStore` | Holds; `MarkdownSession` uses 5 members, `CanvasSession` 4 | [MarkdownSession.swift:160-255](../../../Sources/GraphiteUI/MarkdownSession.swift#L160-L255), [CanvasSession.swift:329-393](../../../Sources/GraphiteUI/CanvasSession.swift#L329-L393) |
| SOLID.md: conflict discovery receives the interface that can replace and remove | Holds | [FileVersionConflicts.swift:15-30](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L15-L30) |
| Architecture.md:173: writes stage outside the vault, use barriers, check revisions inside coordination and flush | Holds | [AtomicFileWriter.swift:98-127](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L98-L127) |
| Architecture.md:120: links match names case-insensitively for every letter | Holds for resolution; fails for the rename uniqueness count | BUG-VAULT-01 |
| Architecture.md:146: "Attachments and unread notes have no indexed text, so no content condition matches them" | Fails for canvases with regular expressions that match empty text | BUG-VAULT-03 |
| Architecture.md:131: bookmarks keep everything and apply changes to the file as it is | Holds for writes; an unreadable file reads as empty | BUG-VAULT-02 |
| Architecture.md:132: indexes unused for 30 days are deleted | Holds; the code comment says "by vaults removed or moved", but the code also deletes listed vaults' indexes | [VaultIndex.swift:207-210](../../../Sources/GraphiteIndex/VaultIndex.swift#L207-L210) against [VaultIndex.swift:237-248](../../../Sources/GraphiteIndex/VaultIndex.swift#L237-L248) |
| Architecture.md:157: copies of `FileRecoveryStore` share one mutation lock | Holds; the struct holds a reference-type lock | [FileRecovery.swift:30-32](../../../Sources/GraphiteCore/FileRecovery.swift#L30-L32) |

## 2. File inventory

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [GraphiteApple/FileVersionConflicts.swift](../../../Sources/GraphiteApple/FileVersionConflicts.swift) | 178 | 121 | `ConflictVersionStore` protocol and its `NSFileVersion` adapter |
| [GraphiteApple/FolderAccess.swift](../../../Sources/GraphiteApple/FolderAccess.swift) | 190 | 139 | Security-scoped folder access, saved vault locations, the vault's file presenter |
| [GraphiteBenchmarks/main.swift](../../../Sources/GraphiteBenchmarks/main.swift) | 116 | 96 | Synthetic index, search and graph benchmark executable |
| [GraphiteCore/AtomicFileWriter.swift](../../../Sources/GraphiteCore/AtomicFileWriter.swift) | 156 | 123 | Revision-checked coordinated atomic replace, copy, read, folder creation |
| [GraphiteCore/AttachmentResolver.swift](../../../Sources/GraphiteCore/AttachmentResolver.swift) | 43 | 31 | Attachment folder, embed text and drawing file stem |
| [GraphiteCore/Bookmarks.swift](../../../Sources/GraphiteCore/Bookmarks.swift) | 264 | 209 | `JSONValue`, `Bookmark` and `BookmarkList` for `.obsidian/bookmarks.json` |
| [GraphiteCore/ConflictVersions.swift](../../../Sources/GraphiteCore/ConflictVersions.swift) | 152 | 104 | Conflict version facts, change stamps, conflicted-copy names, line comparison |
| [GraphiteCore/DocumentPlaces.swift](../../../Sources/GraphiteCore/DocumentPlaces.swift) | 98 | 69 | Where notes and PDFs were left, bounded per vault |
| [GraphiteCore/FileRecovery.swift](../../../Sources/GraphiteCore/FileRecovery.swift) | 207 | 158 | Note snapshots in Application Support |
| [GraphiteCore/LinkCompletion.swift](../../../Sources/GraphiteCore/LinkCompletion.swift) | 399 | 296 | What the cursor is typing (`[[…`, `#tag`); link target text; link under the cursor |
| [GraphiteCore/LinkGraph.swift](../../../Sources/GraphiteCore/LinkGraph.swift) | 201 | 160 | Graph nodes, edges, filters, local neighborhood |
| [GraphiteCore/LinkRewriter.swift](../../../Sources/GraphiteCore/LinkRewriter.swift) | 641 | 489 | Link scanning with frontmatter and reference definitions, CommonMark link syntax, path rewriting, nested replacements |
| [GraphiteCore/Mentions.swift](../../../Sources/GraphiteCore/Mentions.swift) | 106 | 82 | Backlink candidates and unlinked mentions |
| [GraphiteCore/MomentDateFormat.swift](../../../Sources/GraphiteCore/MomentDateFormat.swift) | 216 | 194 | Moment.js date formatting and parsing |
| [GraphiteCore/Navigation.swift](../../../Sources/GraphiteCore/Navigation.swift) | 297 | 226 | Fuzzy matcher, navigation history, recent files |
| [GraphiteCore/NoteProperties.swift](../../../Sources/GraphiteCore/NoteProperties.swift) | 521 | 395 | Frontmatter property typing, serialization and splicing |
| [GraphiteCore/ObsidianSettings.swift](../../../Sources/GraphiteCore/ObsidianSettings.swift) | 428 | 331 | `app.json` settings model and its layout-preserving JSON member writer |
| [GraphiteCore/ReadingTasks.swift](../../../Sources/GraphiteCore/ReadingTasks.swift) | 210 | 142 | Task checkbox locations and toggles from reading view |
| [GraphiteCore/SearchQuery.swift](../../../Sources/GraphiteCore/SearchQuery.swift) | 1214 | 944 | Search expression, parser, unicode61 tokens, matcher, content parts, excerpts |
| [GraphiteCore/TabLayout.swift](../../../Sources/GraphiteCore/TabLayout.swift) | 444 | 320 | Tabs, groups, split, closed tabs, saved layout |
| [GraphiteCore/TagsAndProperties.swift](../../../Sources/GraphiteCore/TagsAndProperties.swift) | 144 | 113 | Tag tree, list sort order, property renaming |
| [GraphiteCore/Templates.swift](../../../Sources/GraphiteCore/Templates.swift) | 261 | 207 | Templates and daily-notes settings files, template rendering and insertion |
| [GraphiteCore/TimeLimitedRegularExpression.swift](../../../Sources/GraphiteCore/TimeLimitedRegularExpression.swift) | 48 | 34 | Regular expression matching with time limit and cancellation |
| [GraphiteCore/VaultList.swift](../../../Sources/GraphiteCore/VaultList.swift) | 135 | 94 | Known vaults, saved locations, readable location text |
| [GraphiteCore/VaultPath.swift](../../../Sources/GraphiteCore/VaultPath.swift) | 172 | 123 | `GraphiteError`, `VaultPath`, `DocumentKind` |
| [GraphiteCore/VaultStore.swift](../../../Sources/GraphiteCore/VaultStore.swift) | 456 | 340 | Vault file actor: listing, I/O, settings files, file management, naming |
| [GraphiteCore/VaultURI.swift](../../../Sources/GraphiteCore/VaultURI.swift) | 121 | 82 | `graphite://` and `obsidian://` deep links |
| [GraphiteCore/WholeNumberConversion.swift](../../../Sources/GraphiteCore/WholeNumberConversion.swift) | 16 | 10 | Trap-free `Double` to `Int` |
| [GraphiteCore/YAMLAliasExpansionLimits.swift](../../../Sources/GraphiteCore/YAMLAliasExpansionLimits.swift) | 104 | 62 | Bounds on YAML anchors and alias expansion |
| [GraphiteIndex/VaultFileOperations.swift](../../../Sources/GraphiteIndex/VaultFileOperations.swift) | 396 | 276 | Link-update planning and move execution; three index queries |
| [GraphiteIndex/VaultGraph.swift](../../../Sources/GraphiteIndex/VaultGraph.swift) | 139 | 113 | Whole-vault link graph and in-memory link resolver |
| [GraphiteIndex/VaultIndex.swift](../../../Sources/GraphiteIndex/VaultIndex.swift) | 924 | 633 | Schema, cache placement, row writing, link queries, scan, refresh |
| [GraphiteIndex/VaultPlaces.swift](../../../Sources/GraphiteIndex/VaultPlaces.swift) | 33 | 28 | Notes placed on the map |
| [GraphiteIndex/VaultSearch.swift](../../../Sources/GraphiteIndex/VaultSearch.swift) | 759 | 559 | Search paging and SQL compiler, regular-expression SQL function, quick switcher, tags, property usage |
| **Total (34 files)** | **9789** | **7303** | |

## 3. Responsibility maps of the major types

### 3.1 `VaultStore` (actor, [VaultStore.swift:66-456](../../../Sources/GraphiteCore/VaultStore.swift#L66-L456), 340 code lines in the file, plus 8 methods in 3 extension files)

**Stored state (4):**
- `root` (nonisolated, [:67](../../../Sources/GraphiteCore/VaultStore.swift#L67)).
- `writer: AtomicFileWriter` (nonisolated, public, [:68](../../../Sources/GraphiteCore/VaultStore.swift#L68)).
- `settingsBaseline` ([:74](../../../Sources/GraphiteCore/VaultStore.swift#L74)).
- `appearanceBaseline` ([:76](../../../Sources/GraphiteCore/VaultStore.swift#L76)).

Statics: `applicationConfigurationPath`, `maximumConfigurationBytes` (1 MiB), `propertyTypesPath`.

**Functions by responsibility:**

| Responsibility | Members |
| --- | --- |
| Folder listing | `children(of:sortedBy:)` [:83-95](../../../Sources/GraphiteCore/VaultStore.swift#L83-L95) |
| Plain file I/O | `read` [:97](../../../Sources/GraphiteCore/VaultStore.swift#L97), `save` [:101](../../../Sources/GraphiteCore/VaultStore.swift#L101), `fileExists` [:105](../../../Sources/GraphiteCore/VaultStore.swift#L105), `regularFileExists` [:110](../../../Sources/GraphiteCore/VaultStore.swift#L110), `createDirectory` [:297](../../../Sources/GraphiteCore/VaultStore.swift#L297) |
| `app.json` with baseline | `settings()` [:115](../../../Sources/GraphiteCore/VaultStore.swift#L115), `saveSettings` [:278-295](../../../Sources/GraphiteCore/VaultStore.swift#L278-L295) |
| `appearance.json` with baseline | `appearance()` [:224](../../../Sources/GraphiteCore/VaultStore.swift#L224), `saveAppearance` [:239-251](../../../Sources/GraphiteCore/VaultStore.swift#L239-L251) |
| `types.json` | `propertyTypes` [:126](../../../Sources/GraphiteCore/VaultStore.swift#L126), `setPropertyType` [:137](../../../Sources/GraphiteCore/VaultStore.swift#L137), `movePropertyType` [:145](../../../Sources/GraphiteCore/VaultStore.swift#L145), `updatePropertyTypeAssignments` [:155-175](../../../Sources/GraphiteCore/VaultStore.swift#L155-L175) |
| `bookmarks.json` | `bookmarks` [:178](../../../Sources/GraphiteCore/VaultStore.swift#L178), `updateBookmarks` [:185-202](../../../Sources/GraphiteCore/VaultStore.swift#L185-L202) |
| `templates.json`, `daily-notes.json` | `templateSettings`, `saveTemplateSettings`, `dailyNoteSettings`, `saveDailyNoteSettings` [:205-220](../../../Sources/GraphiteCore/VaultStore.swift#L205-L220) |
| Generic settings-file read and merge | `configurationData(at:)` [:254](../../../Sources/GraphiteCore/VaultStore.swift#L254), `saveConfiguration(at:merge:)` [:261-269](../../../Sources/GraphiteCore/VaultStore.swift#L261-L269) |
| File management | `move` [:307-337](../../../Sources/GraphiteCore/VaultStore.swift#L307-L337), `isSameItem` [:339](../../../Sources/GraphiteCore/VaultStore.swift#L339), `duplicate` [:346-366](../../../Sources/GraphiteCore/VaultStore.swift#L346-L366), `createFolder` [:369](../../../Sources/GraphiteCore/VaultStore.swift#L369), `delete` [:378-403](../../../Sources/GraphiteCore/VaultStore.swift#L378-L403), `moveToVaultTrash` [:406](../../../Sources/GraphiteCore/VaultStore.swift#L406), `coordinateDeletion` [:417](../../../Sources/GraphiteCore/VaultStore.swift#L417) |
| Free-name policy | `availablePath` [:429-444](../../../Sources/GraphiteCore/VaultStore.swift#L429-L444), `uniquePath` [:450-455](../../../Sources/GraphiteCore/VaultStore.swift#L450-L455); `FileNameRules` [:35-64](../../../Sources/GraphiteCore/VaultStore.swift#L35-L64) in the same file |
| Extensions elsewhere | `communityPluginList`, `updateCommunityPluginList` ([CommunityPluginList.swift:51-78](../../../Sources/GraphiteCore/CommunityPluginList.swift#L51-L78)); `installedCommunityPlugins`, `communityPluginPackage` ([CommunityPluginInventory.swift:121-157](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L121-L157)); `installedThemeNames`, `snippetNames`, `themeStyleSheet`, `snippetStyleSheet` ([ObsidianThemes.swift:82-116](../../../Sources/GraphiteCore/ObsidianThemes.swift#L82-L116)) |

**Calls that cross responsibilities (a split must keep them working):**
- Every settings writer calls `saveConfiguration`, which calls `createDirectory` (file I/O) for `.obsidian` ([:264](../../../Sources/GraphiteCore/VaultStore.swift#L264)).
- `delete(.systemTrash)` falls back to `moveToVaultTrash`, which calls `move` and `availablePath` ([:395](../../../Sources/GraphiteCore/VaultStore.swift#L395), [:411-413](../../../Sources/GraphiteCore/VaultStore.swift#L411-L413)).
- `duplicate` and `uniquePath` share `availablePath`. `createFolder` uses `FileNameRules` and `createDirectory`.
- `updateBookmarks` and `updateCommunityPluginList` both read through `configurationData` first, then merge through `saveConfiguration`.

**Lifecycle and ordering rules:**
- `settings()` must run before `saveSettings(_:changedFrom: nil)`. Otherwise the baseline is nil and the merge starts from the file's current values ([ObsidianSettings.swift:228](../../../Sources/GraphiteCore/ObsidianSettings.swift#L228)). Every key whose read-back value differs from its text is then rewritten (for example `tabSize` 12, read as 8 at [ObsidianSettings.swift:212](../../../Sources/GraphiteCore/ObsidianSettings.swift#L212)). `appearance()` and `saveAppearance` follow the same rule.
- The baseline must be reset after every successful save ([:250](../../../Sources/GraphiteCore/VaultStore.swift#L250), [:294](../../../Sources/GraphiteCore/VaultStore.swift#L294)).
- `delete(.systemTrash)` runs the coordinated deletion before `trashItem` and outside it. Nesting deadlocks on iPadOS ([:385-391](../../../Sources/GraphiteCore/VaultStore.swift#L385-L391)).
- `move` checks that the destination is not inside the source, by name and then by file identity, before any coordination ([:309-322](../../../Sources/GraphiteCore/VaultStore.swift#L309-L322)).
- Actor isolation keeps every synchronous file operation of one vault off the main actor and serialized.

**Verdict.** The class mixes 10 responsibilities, and the baseline coupling between `settings()` and `saveSettings` is an implicit "call X before Y" rule. Each method is short and correct, so the cost is reach, not quality: every consumer receives every capability (ISP-VAULT-01).

**Proposed split.** Keep one actor as the serialization point, or move the shared executor into a small `VaultFileSystem` actor that the others hold:
- `VaultFiles` (root, writer): `read`, `save`, `fileExists`, `regularFileExists`, `createDirectory`, `children`, `uniquePath`. This is the capability sessions need.
- `VaultFileManagement` (holds `VaultFiles`): `move`, `duplicate`, `createFolder`, `delete`, `moveToVaultTrash`, `coordinateDeletion`, `isSameItem`.
- `FreeFileName`, a pure function: `availablePath` with a `isTaken: (VaultPath) -> Bool` input. `FileNameRules` moves to its own file.
- `ObsidianConfigurationFiles` (holds `VaultFiles`): `configurationData`, `saveConfiguration`, and the readers and writers for `types.json`, `bookmarks.json`, `templates.json`, `daily-notes.json` and `community-plugins.json`. Each file declares its path once.
- `ObsidianSettingsStore`: `settings`, `saveSettings`, `appearance`, `saveAppearance` and both baselines. The baselines become one `[ConfigurationFile: Snapshot]` map, set inside the read call, so no separate step can be forgotten.

### 3.2 `VaultIndex` (actor, [VaultIndex.swift:47-923](../../../Sources/GraphiteIndex/VaultIndex.swift#L47-L923), 600 code lines in the declaration; extensions in `VaultSearch.swift`, `VaultGraph.swift`, `VaultPlaces.swift`, `VaultFileOperations.swift:367-396`, `BaseRecordQueries.swift`)

**Stored state (4 instance properties):**
- `databaseQueue` ([:55](../../../Sources/GraphiteIndex/VaultIndex.swift#L55)).
- `isScanning` ([:56](../../../Sources/GraphiteIndex/VaultIndex.swift#L56)).
- `activeScanGeneration` ([:59](../../../Sources/GraphiteIndex/VaultIndex.swift#L59)).
- `pathsRefreshedDuringScan` ([:63](../../../Sources/GraphiteIndex/VaultIndex.swift#L63)).

There are 15 static constants and tables across the declaration and `VaultSearch.swift`, counted by reading.

**Functions by responsibility (public functions: 13 in `VaultIndex.swift`, 7 in `VaultSearch.swift`, 1 each in `VaultGraph.swift` and `VaultPlaces.swift`, 2 in `VaultFileOperations.swift`):**

| Responsibility | Members |
| --- | --- |
| A. Schema and connection | `init` with 9 migrations [:71-188](../../../Sources/GraphiteIndex/VaultIndex.swift#L71-L188), `foldedKey`, `foldedKeyFunction` [:192-199](../../../Sources/GraphiteIndex/VaultIndex.swift#L192-L199), registration of `RegularExpressionFunction` [:77](../../../Sources/GraphiteIndex/VaultIndex.swift#L77) |
| B. Cache placement (static) | `cacheURL(for:)` [:201](../../../Sources/GraphiteIndex/VaultIndex.swift#L201), `cacheURL(forVault:legacyRoot:in:)` [:211-228](../../../Sources/GraphiteIndex/VaultIndex.swift#L211-L228), `removeIndex` [:231](../../../Sources/GraphiteIndex/VaultIndex.swift#L231), `removeUnusedIndexes` [:237-249](../../../Sources/GraphiteIndex/VaultIndex.swift#L237-L249) |
| C. Row preparation and writing | `PreparedFile`, `readsText`, `prepared` [:252-287](../../../Sources/GraphiteIndex/VaultIndex.swift#L252-L287), `update` [:289](../../../Sources/GraphiteIndex/VaultIndex.swift#L289), `write` [:294-354](../../../Sources/GraphiteIndex/VaultIndex.swift#L294-L354), `storedLinkTarget` [:506-521](../../../Sources/GraphiteIndex/VaultIndex.swift#L506-L521), `markSeen` [:916](../../../Sources/GraphiteIndex/VaultIndex.swift#L916), `removeAllEntries` [:910](../../../Sources/GraphiteIndex/VaultIndex.swift#L910) |
| D. Link queries | `resolve`, `resolvedPaths`, `lookupPathPart` [:361-411](../../../Sources/GraphiteIndex/VaultIndex.swift#L361-L411), `fileCount` ×2 [:414-423](../../../Sources/GraphiteIndex/VaultIndex.swift#L414-L423), `outgoingLinks`, `backlinks`, `foldedLinkTargetCandidates`, `backlinkSources` [:425-498](../../../Sources/GraphiteIndex/VaultIndex.swift#L425-L498); `paths(inside:)`, `linkingNotes`, `fileCount(named:excluding:)` [VaultFileOperations.swift:367-396](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L367-L396) |
| E. Full scan | `reconcile` [:572-640](../../../Sources/GraphiteIndex/VaultIndex.swift#L572-L640), `checkScannedFiles`, `writeBatch`, `storedContentStates`, `isNotDownloaded`, `readAndPrepare`, `readNotes`, `readNoteData`, `noteReading`, `writeScanBatch`, `isSupersededByRefresh` [:644-808](../../../Sources/GraphiteIndex/VaultIndex.swift#L644-L808); types `ScannedFile`, `ScanBatchEntry`, `NoteReading`, `ScanState` [:524-567](../../../Sources/GraphiteIndex/VaultIndex.swift#L524-L567) |
| F. Incremental refresh | `refresh` [:818-869](../../../Sources/GraphiteIndex/VaultIndex.swift#L818-L869), `refreshedFile`, `isExistingIndexableDirectory`, `locationWithoutSymbolicLinks` [:873-907](../../../Sources/GraphiteIndex/VaultIndex.swift#L873-L907) |
| G. Search | `search`, `searchPage`, `validateRegularExpressions`, `matches`, `searchableFiles` [VaultSearch.swift:118-276](../../../Sources/GraphiteIndex/VaultSearch.swift#L118-L276) |
| H. Quick switcher | `quickSwitcherMatches`, `switcherName` ×2, `switcherPathText` [VaultSearch.swift:484-535](../../../Sources/GraphiteIndex/VaultSearch.swift#L484-L535) |
| I. Tags and properties | `tags(matching:)`, `nestedTagCounts`, `propertyUsages`, `paths(withPropertyKey:)` [VaultSearch.swift:659-758](../../../Sources/GraphiteIndex/VaultSearch.swift#L659-L758) |
| J. Graph | `linkGraph`, `graphLinkResolver`, `isExternalLink` [VaultGraph.swift:10-57](../../../Sources/GraphiteIndex/VaultGraph.swift#L10-L57) |
| K. Map places | `placedNotes` [VaultPlaces.swift:9-32](../../../Sources/GraphiteIndex/VaultPlaces.swift#L9-L32) |
| L. Base records | `BaseRecordQueries.swift` (another area) |

**Calls that cross responsibilities:**
- E and F both write through C (`write`), and they share the 3 scan fields.
- E's `writeScanBatch` consults F's `pathsRefreshedDuringScan` through `isSupersededByRefresh` ([:773](../../../Sources/GraphiteIndex/VaultIndex.swift#L773)).
- D's `resolvedPaths` is reused by `backlinkSources` and by L.
- J re-implements D in memory (`GraphLinkResolver`, LSP-VAULT-03).
- G uses `foldedKey` (A) and `escapedForLike`.
- The file-operations planner calls D's `linkingNotes`, `resolve` and `fileCount(named:excluding:)`.

**Lifecycle and ordering rules:**
1. Migrations run in registration order, and their names are persisted in GRDB's migration table. A rename or reorder re-runs or skips schema changes (VAULT-INV-17).
2. `prepareDatabase` registers `graphite_regexp` on every connection before any search ([:74-78](../../../Sources/GraphiteIndex/VaultIndex.swift#L74-L78)). Migration 8 registers `graphite_folded_key` only while it runs ([:160-161](../../../Sources/GraphiteIndex/VaultIndex.swift#L160-L161)).
3. `reconcile` sets `isScanning` and `activeScanGeneration` together and resets them, with `pathsRefreshedDuringScan`, in one `defer` ([:573-581](../../../Sources/GraphiteIndex/VaultIndex.swift#L573-L581)).
4. During a scan, `refresh` writes with the scan's generation and records each written path before the scan writes its own batches ([:820](../../../Sources/GraphiteIndex/VaultIndex.swift#L820), [:826-828](../../../Sources/GraphiteIndex/VaultIndex.swift#L826-L828), [:849-851](../../../Sources/GraphiteIndex/VaultIndex.swift#L849-L851)).
5. Pruning runs only after the last batch is written, and only when enumeration reported no error ([:627-638](../../../Sources/GraphiteIndex/VaultIndex.swift#L627-L638)).
6. Unchanged files are marked seen per chunk ([:667](../../../Sources/GraphiteIndex/VaultIndex.swift#L667)). Files whose read or write failed are marked seen so the prune keeps them ([:793](../../../Sources/GraphiteIndex/VaultIndex.swift#L793)).

**Verdict.** The algorithms are careful and well commented. The type is a god object by breadth: 12 responsibilities, more than 24 public functions, and 3 mutable fields that encode one scan state.

**Proposed split.** The read queries already run `nonisolated` on the queue, so they move out without changing concurrency.
- `IndexDatabase`: opens the queue, registers functions, runs `IndexSchemaMigrations`.
- `IndexLocation`: an enum holding B.
- `IndexRowWriter`: C.
- `LinkIndexQueries`: D. It is the one resolver; `GraphLinkResolver` becomes its in-memory table form behind one shared rule.
- `VaultScanner`: an actor holding E and F, with `enum ScanPhase { case idle; case scanning(generation: String, refreshedPaths: [String: Date]) }`.
- `IndexSearch`: G and H.
- `TagAndPropertyQueries`: I.
- `GraphQueries`: J.
- `PlacedNoteQueries`: K.

`VaultIndex` stays as the composition that owns one `IndexDatabase` and hands these out.

### 3.3 `NoteProperties` (enum, [NoteProperties.swift:47-501](../../../Sources/GraphiteCore/NoteProperties.swift#L47-L501), 347 code lines)

No stored state.

| Responsibility | Members |
| --- | --- |
| Reading and typing values | `parse` [:51](../../../Sources/GraphiteCore/NoteProperties.swift#L51), `mappingEntries` [:137-146](../../../Sources/GraphiteCore/NoteProperties.swift#L137-L146), `value(of:)`, `unsupportedValue`, `type(ofKey:)`, `value(ofScalar:)`, `isReadByValue`, `value(ofScalarText:)`, `tagNames`, `coreSchemaNumber`, `looksLikeDate`, `dateValue`, `isSameValue`, `defaultType` [:124-267](../../../Sources/GraphiteCore/NoteProperties.swift#L124-L267) |
| Writing YAML | `serialize` [:60](../../../Sources/GraphiteCore/NoteProperties.swift#L60), `formatted` [:111](../../../Sources/GraphiteCore/NoteProperties.swift#L111), `serializedLines`, `quotedIfNeeded`, `needsQuotes`, `mustBeEscaped` [:271-337](../../../Sources/GraphiteCore/NoteProperties.swift#L271-L337) |
| Splicing into a note | `replacingFrontmatter` [:72-91](../../../Sources/GraphiteCore/NoteProperties.swift#L72-L91), `rewrittenYAML` [:96-109](../../../Sources/GraphiteCore/NoteProperties.swift#L96-L109), `splicedYAML` [:344-417](../../../Sources/GraphiteCore/NoteProperties.swift#L344-L417), `valueLinesEnd`, `trailingComment`, `isCommentOrBlank`, `yamlLines`, `isYAMLLineBreak`, `lineContent`, `textWithoutLastLineBreak`, `firstLineEnding` [:421-500](../../../Sources/GraphiteCore/NoteProperties.swift#L421-L500); `FrontmatterRegion` [:504-521](../../../Sources/GraphiteCore/NoteProperties.swift#L504-L521) |

**Crossings.** Splicing verifies its own output by calling `parse` and `serialize` ([:408-415](../../../Sources/GraphiteCore/NoteProperties.swift#L408-L415)). The three parts must agree on typing, which is why they live together today.

**Verdict.** The type is cohesive around one rule ("properties round-trip exactly"). It is large because the splicing is careful, not because it mixes concerns.

**Split by file only:** `PropertyValueReading.swift`, `PropertyYAMLWriting.swift`, `FrontmatterSplicing.swift`, with `FrontmatterRegion` replaced by the shared frontmatter locator (CC-VAULT-03).

### 3.4 File maps of the two multi-concept files

`SearchQuery.swift` (944 code lines) holds 7 concepts:

| Concept | Lines |
| --- | --- |
| `SearchExpression`, `SearchTerm`, `SearchScope` | [:6-45](../../../Sources/GraphiteCore/SearchQuery.swift#L6-L45), [:323-363](../../../Sources/GraphiteCore/SearchQuery.swift#L323-L363) |
| `SearchQueryParser` | [:49-321](../../../Sources/GraphiteCore/SearchQuery.swift#L49-L321) |
| `SearchableFile` and `SearchTextTokens` (unicode61 emulation) | [:368-733](../../../Sources/GraphiteCore/SearchQuery.swift#L368-L733) |
| `SearchMatcher` | [:737-979](../../../Sources/GraphiteCore/SearchQuery.swift#L737-L979) |
| `NumericComparison` | [:982-993](../../../Sources/GraphiteCore/SearchQuery.swift#L982-L993) |
| `SearchContentParts` | [:996-1095](../../../Sources/GraphiteCore/SearchQuery.swift#L996-L1095) |
| `SearchMatch` and `SearchExcerpts` | [:1100-1214](../../../Sources/GraphiteCore/SearchQuery.swift#L1100-L1214) |

Each concept is already a separate type with one job, so the split is one file per concept with no type changes.

`LinkRewriter.swift` (489 code lines) holds 5 concepts:

| Concept | Lines |
| --- | --- |
| `NoteLinkScanner` | [:12-139](../../../Sources/GraphiteCore/LinkRewriter.swift#L12-L139) |
| `YAMLQuotedValue` | [:142-232](../../../Sources/GraphiteCore/LinkRewriter.swift#L142-L232) |
| `MarkdownLinkSyntax` | [:238-434](../../../Sources/GraphiteCore/LinkRewriter.swift#L238-L434) |
| `LinkRewriter` | [:438-600](../../../Sources/GraphiteCore/LinkRewriter.swift#L438-L600) |
| `LinkReplacementGroup` | [:602-641](../../../Sources/GraphiteCore/LinkRewriter.swift#L602-L641) |

The split is the same: one file per concept.

`TabLayout` ([TabLayout.swift:44-401](../../../Sources/GraphiteCore/TabLayout.swift#L44-L401)) has 6 stored properties and one job (the layout's invariants: at least one tab per group, at most 2 groups, a file in at most one tab). It needs no split. The restore-only field `pluginViewsToRestore` ([:59](../../../Sources/GraphiteCore/TabLayout.swift#L59)) is the one foreign member: it is written once by `init(saved:)` and read once by the UI ([CommunityPluginViews.swift:272](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L272)). It belongs in a value that `init(saved:)` returns beside the layout.

## 4. Findings by principle

### S

#### SRP-VAULT-01 `VaultStore` is one actor for file I/O, file management, naming policy and six Obsidian settings files
- **Severity:** Medium
- **Evidence:**
  - 10 responsibility groups in one actor (section 3.1). Its 24 public methods were counted by reading [VaultStore.swift:83-455](../../../Sources/GraphiteCore/VaultStore.swift#L83-L455).
  - 8 more methods sit in 3 other files ([CommunityPluginList.swift:51-78](../../../Sources/GraphiteCore/CommunityPluginList.swift#L51-L78), [CommunityPluginInventory.swift:121-157](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L121-L157), [ObsidianThemes.swift:82-116](../../../Sources/GraphiteCore/ObsidianThemes.swift#L82-L116)).
  - Settings baselines are actor state that only `settings()`/`appearance()` set and only `saveSettings`/`saveAppearance` read ([VaultStore.swift:74-76](../../../Sources/GraphiteCore/VaultStore.swift#L74-L76), [:120](../../../Sources/GraphiteCore/VaultStore.swift#L120), [:229](../../../Sources/GraphiteCore/VaultStore.swift#L229), [:240](../../../Sources/GraphiteCore/VaultStore.swift#L240), [:282](../../../Sources/GraphiteCore/VaultStore.swift#L282)).
- **Why it matters:**
  - Every new Obsidian settings file adds methods to this actor; the theme and plugin files already reach in through `extension VaultStore`.
  - Every consumer receives move, delete and every settings writer (ISP-VAULT-01).
  - The baseline makes `saveSettings(changedFrom: nil)` correct only after a prior `settings()` call on the same actor.
- **Fix direction:** Split as in section 3.1 into `VaultFiles`, `VaultFileManagement`, `ObsidianConfigurationFiles` and `ObsidianSettingsStore`, sharing one writer and root. Make the baseline part of the value `settings()` returns, so a save cannot run without it.

#### SRP-VAULT-02 `VaultIndex` owns schema, cache placement, scanning, refresh and five query families
- **Severity:** Medium
- **Evidence:**
  - 12 responsibility groups (section 3.2) over [VaultIndex.swift](../../../Sources/GraphiteIndex/VaultIndex.swift) (633 code lines), [VaultSearch.swift](../../../Sources/GraphiteIndex/VaultSearch.swift) (559), [VaultGraph.swift](../../../Sources/GraphiteIndex/VaultGraph.swift), [VaultPlaces.swift](../../../Sources/GraphiteIndex/VaultPlaces.swift) and [VaultFileOperations.swift:367-396](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L367-L396).
  - Static cache-folder policy (choosing `Caches/Graphite/Indexes`, migrating legacy names, deleting after 30 days) lives on the database actor ([VaultIndex.swift:201-249](../../../Sources/GraphiteIndex/VaultIndex.swift#L201-L249)).
- **Why it matters:**
  - Search, graph and file-operation changes all edit the same type.
  - Tests reach private resolution through test hooks (`graphLinkResolver()` at [VaultGraph.swift:47-50](../../../Sources/GraphiteIndex/VaultGraph.swift#L47-L50)).
  - Cache placement cannot be tested without the real Caches folder unless a directory is passed, and only two of the three cache functions accept one.
- **Fix direction:** Keep `VaultIndex` as the owner of one `IndexDatabase` and move each query family into its own type over the shared `DatabaseQueue` (section 3.2). Move cache placement into an `IndexLocation` enum that takes the caches folder and the current time as inputs.

#### SRP-VAULT-03 The scan's state is a boolean, an optional and a dictionary that must change together
- **Severity:** Medium
- **Evidence:**
  - `isScanning`, `activeScanGeneration` and `pathsRefreshedDuringScan` are declared at [VaultIndex.swift:56-63](../../../Sources/GraphiteIndex/VaultIndex.swift#L56-L63). They are set together at [:574-576](../../../Sources/GraphiteIndex/VaultIndex.swift#L574-L576) and reset together at [:577-581](../../../Sources/GraphiteIndex/VaultIndex.swift#L577-L581).
  - `refresh` tests `activeScanGeneration != nil` as "a scan runs" at [:826](../../../Sources/GraphiteIndex/VaultIndex.swift#L826) and [:849](../../../Sources/GraphiteIndex/VaultIndex.swift#L849), while `reconcile` tests `isScanning` at [:573](../../../Sources/GraphiteIndex/VaultIndex.swift#L573). These are two spellings of one fact.
- **Why it matters:** A change that sets one field without the others (an early return before the `defer`, a second entry point) leaves `refresh` writing with a stale generation or recording paths no scan will read. The pruning then deletes or keeps the wrong rows.
- **Fix direction:** Replace the three fields with `enum ScanPhase { case idle; case scanning(generation: String, refreshedPaths: [String: Date]) }`, changed only through `beginScan()`, `recordRefresh(_:)` and `endScan()`.

#### SRP-VAULT-04 `SearchQuery.swift` and `LinkRewriter.swift` hold 7 and 5 concepts in one file each
- **Severity:** Low
- **Evidence:** The file maps in section 3.4. [SearchQuery.swift](../../../Sources/GraphiteCore/SearchQuery.swift) is 944 code lines; [LinkRewriter.swift](../../../Sources/GraphiteCore/LinkRewriter.swift) is 489.
- **Why it matters:** The unicode61 tokenizer emulation (366 lines, [SearchQuery.swift:368-733](../../../Sources/GraphiteCore/SearchQuery.swift#L368-L733)) and the CommonMark link grammar ([LinkRewriter.swift:238-434](../../../Sources/GraphiteCore/LinkRewriter.swift#L238-L434)) are reused outside their files, by `LinkCompletion` and the index. Readers cannot find them by name.
- **Fix direction:** One file per type, named after it. No type or behaviour change.

#### SRP-VAULT-05 `VaultIndex.reconcile` mixes enumeration, failure policy and pruning SQL in 56 lines
- **Severity:** Low
- **Evidence:** [VaultIndex.swift:572-640](../../../Sources/GraphiteIndex/VaultIndex.swift#L572-L640) holds four steps: the enumerator setup with its error flag ([:591](../../../Sources/GraphiteIndex/VaultIndex.swift#L591)), per-item classification with two failure paths ([:597-624](../../../Sources/GraphiteIndex/VaultIndex.swift#L597-L624)), batching, and five prune statements ([:630-637](../../../Sources/GraphiteIndex/VaultIndex.swift#L630-L637)). The same multi-table deletion appears again in `refresh` ([:853-866](../../../Sources/GraphiteIndex/VaultIndex.swift#L853-L866)).
- **Why it matters:** The rule "a file's rows are removed from `search`, the 5 per-file tables, `links` and `files` together" is written twice, in two SQL shapes.
- **Fix direction:** `IndexRowWriter.removeRows(where:)` owns the multi-table deletion. `reconcile` becomes enumerate, then classify, then write, then `pruneUnseen(generation:)`.

### O

#### OCP-VAULT-01 Bookmark kinds are a stringly-typed vocabulary repeated in 18 places
- **Severity:** Medium
- **Evidence:**
  - `type` is a raw `String` ([Bookmarks.swift:54](../../../Sources/GraphiteCore/Bookmarks.swift#L54)). The literals `"file"`, `"folder"`, `"search"`, `"group"`, `"url"` and `"graph"` are compared or written at [Bookmarks.swift:94](../../../Sources/GraphiteCore/Bookmarks.swift#L94), [:100-103](../../../Sources/GraphiteCore/Bookmarks.swift#L100-L103), [:109](../../../Sources/GraphiteCore/Bookmarks.swift#L109), [:116](../../../Sources/GraphiteCore/Bookmarks.swift#L116), [:122](../../../Sources/GraphiteCore/Bookmarks.swift#L122), [:128](../../../Sources/GraphiteCore/Bookmarks.swift#L128), [:141](../../../Sources/GraphiteCore/Bookmarks.swift#L141) (twice), [:146](../../../Sources/GraphiteCore/Bookmarks.swift#L146), [:201](../../../Sources/GraphiteCore/Bookmarks.swift#L201), [:205](../../../Sources/GraphiteCore/Bookmarks.swift#L205), [:209](../../../Sources/GraphiteCore/Bookmarks.swift#L209), and in the UI at [WorkspaceBookmarks.swift:63](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L63), [:70](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L70), [:74](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L74). That is 18, counted by reading.
  - The UI switch ends in `default: break` ([WorkspaceBookmarks.swift:76-77](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L76-L77)).
- **Why it matters:** A misspelled kind compiles. A new kind, such as Obsidian's `heading` or `block` when they become first-class, needs edits in two modules with no compiler help.
- **Fix direction:** Add `enum BookmarkKind { case file, folder, search, group, graph, url, unknown(String) }`, mapped once from `fields["type"]`. Keep `fields` as the stored truth so unknown kinds still round-trip.

#### OCP-VAULT-02 Obsidian settings files are written by four different JSON writers
- **Severity:** Medium
- **Evidence:**
  - `app.json` and `appearance.json` use the member-preserving `ApplicationConfigurationObject` ([ObsidianSettings.swift:264-330](../../../Sources/GraphiteCore/ObsidianSettings.swift#L264-L330); `ObsidianAppearance` per [ObsidianAppearance.swift:187](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L187)).
  - `types.json` uses `JSONSerialization` with `.prettyPrinted, .sortedKeys` ([VaultStore.swift:173](../../../Sources/GraphiteCore/VaultStore.swift#L173)), and so do `templates.json` and `daily-notes.json` ([Templates.swift:116](../../../Sources/GraphiteCore/Templates.swift#L116)).
  - `bookmarks.json` uses `JSONEncoder` with sorted keys ([Bookmarks.swift:188-190](../../../Sources/GraphiteCore/Bookmarks.swift#L188-L190)).
  - `community-plugins.json` has its own writer ([CommunityPluginList.swift:47](../../../Sources/GraphiteCore/CommunityPluginList.swift#L47)).
- **Why it matters:** Only the first writer keeps Obsidian's key order and layout. The other three reorder keys alphabetically on the first change, so a synced or versioned vault sees whole-file churn. A new settings file means choosing among four behaviours. The comment at [ObsidianSettings.swift:264-267](../../../Sources/GraphiteCore/ObsidianSettings.swift#L264-L267) states the rule (only changed lines differ) that the other writers break.
- **Fix direction:** Write every `.obsidian/*.json` object through `ApplicationConfigurationObject`, renamed `ObsidianJSONObjectFile`, as members set by key. Declare each file's path and owned keys in one place (`ObsidianConfigurationFile` enum).

#### OCP-VAULT-03 Adding a search operator touches four parallel switches, two of which hide new cases behind `default:`
- **Severity:** Low
- **Evidence:**
  - `SearchMatcher.evaluate(_ scope:)` at [SearchQuery.swift:800-831](../../../Sources/GraphiteCore/SearchQuery.swift#L800-L831).
  - `SearchSQLCompiler.condition` at [VaultSearch.swift:313-328](../../../Sources/GraphiteIndex/VaultSearch.swift#L313-L328).
  - `SearchContentParts.parts` with `default: return [content]` at [SearchQuery.swift:999-1010](../../../Sources/GraphiteCore/SearchQuery.swift#L999-L1010).
  - `SearchExcerpts.collectHighlightedTerms` with `default:` at [SearchQuery.swift:1206-1211](../../../Sources/GraphiteCore/SearchQuery.swift#L1206-L1211).
- **Why it matters:** A new content-part operator compiles and silently reads the whole note in `SearchContentParts` and highlights wrongly in excerpts.
- **Fix direction:** Spell every `SearchScope` case in all four switches, or give `SearchScope` a `contentPart: ContentPartKind?` property that the matcher, compiler and parts reader all read.

#### OCP-VAULT-04 "Which files hold links" is decided in three places
- **Severity:** Low
- **Evidence:** `VaultIndex.readsText` ([VaultIndex.swift:267-270](../../../Sources/GraphiteIndex/VaultIndex.swift#L267-L270)), `VaultFileOperations.holdsLinks` ([VaultFileOperations.swift:146-149](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L146-L149)), and the inline `isMarkdown`/`isCanvas` pair in the scan ([VaultIndex.swift:623-624](../../../Sources/GraphiteIndex/VaultIndex.swift#L623-L624)).
- **Why it matters:** A new linkable kind, such as `.base` links, must be added in three places, or renames and the index disagree about which files to read.
- **Fix direction:** Add `DocumentKind.holdsLinks` next to the extension table in [VaultPath.swift:155-171](../../../Sources/GraphiteCore/VaultPath.swift#L155-L171).

### L

#### LSP-VAULT-01 Two implementations of "how many files share this name" disagree on non-ASCII capitals
- **Severity:** High
- **Evidence:**
  - `fileCount(named:)` compares `folded_name` (every letter folded, [VaultIndex.swift:419-423](../../../Sources/GraphiteIndex/VaultIndex.swift#L419-L423)). `fileCount(named:excluding:)` compares `name_key = ? COLLATE NOCASE` (ASCII folded only, [VaultFileOperations.swift:389-395](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L389-L395)).
  - Its doc comment claims "Names compare as `fileCount(named:)` and the Wikilink resolver compare them" ([:387-388](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L387-L388)), which is false.
  - The index's own comment records that NOCASE folds ASCII only ([VaultIndex.swift:155-156](../../../Sources/GraphiteIndex/VaultIndex.swift#L155-L156)).
- **Why it matters:** The rename planner decides "unique, so write a bare name" by one rule and the resolver resolves by the other. This produces BUG-VAULT-01.
- **Fix direction:** Implement the count once, through `folded_name` with the exclusion list, and delete the `name_key` query. Add a contract test that the planner's count equals the number of paths `resolvedPaths` returns for the bare name.

#### LSP-VAULT-02 The conflict-version test store succeeds where production fails
- **Severity:** Medium
- **Evidence:** Four divergences, counted by reading:
  - `replaceFile` treats a missing coordination outcome as success (`try outcome?.get()`, [TestConflictVersionStore.swift:87](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L87)). Production throws ([FileVersionConflicts.swift:167](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L167)).
  - `replaceFile` writes bytes with `Data.write(options: .atomic)` and removes the version after the coordinated write ends ([TestConflictVersionStore.swift:83-88](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L83-L88)). Production calls `NSFileVersion.replaceItem` and removes the version inside the accessor ([FileVersionConflicts.swift:97-102](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L97-L102)).
  - `removeVersions` runs without a coordinated write ([TestConflictVersionStore.swift:98-100](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L98-L100)). Production coordinates and can fail there ([FileVersionConflicts.swift:127-129](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L127-L129)).
  - `keepVersion` copies bytes ([TestConflictVersionStore.swift:94](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L94)). Production lets `NSFileVersion.replaceItem` write the staged file and corrects the extension it chooses ([FileVersionConflicts.swift:113-119](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L113-L119)).
- **Why it matters:** Workspace tests built on the fake cannot see a provider refusing coordination or a removal failing. RULES.md forbids a test adapter that makes an operation look safer.
- **Fix direction:** Move the fake to a test-support module. Make it require a coordination outcome and coordinate removals. Run one shared contract suite against both stores (local `NSFileVersion` objects with `.everyOtherVersion` for production).

#### LSP-VAULT-03 `GraphLinkResolver` re-implements `resolvedPaths`, kept equal only by a test
- **Severity:** Medium
- **Evidence:** [VaultGraph.swift:103-134](../../../Sources/GraphiteIndex/VaultGraph.swift#L103-L134) against [VaultIndex.swift:365-402](../../../Sources/GraphiteIndex/VaultIndex.swift#L365-L402). The two order the 50-result cap differently: Swift `sorted()` ([VaultGraph.swift:131](../../../Sources/GraphiteIndex/VaultGraph.swift#L131)) against SQL `ORDER BY path` byte order ([VaultIndex.swift:393](../../../Sources/GraphiteIndex/VaultIndex.swift#L393)). The test hook `graphLinkResolver()` exists only to compare them ([VaultGraph.swift:47-50](../../../Sources/GraphiteIndex/VaultGraph.swift#L47-L50)).
- **Why it matters:** Each change to link resolution (aliases, rooted paths, dots in names) must be made twice. A missed change shows a graph edge that backlinks do not report, or the reverse.
- **Fix direction:** Express the resolution steps once over a `LinkNameTable` protocol with two implementations (SQL lookups, in-memory dictionaries). Here the substitution need is real. Both run one shared contract test.

#### LSP-VAULT-04 Identity and equality differ in four identifiable types; one identity changes on rename
- **Severity:** Medium
- **Evidence:**
  - `Bookmark.id` joins type, `ctime`, then path, query, url or title ([Bookmarks.swift:85-87](../../../Sources/GraphiteCore/Bookmarks.swift#L85-L87)). A group's identity therefore includes its title and changes when `rename` sets it ([:226-228](../../../Sources/GraphiteCore/Bookmarks.swift#L226-L228)). Two bookmarks of the same file and heading with the same `ctime` share an id, and `remove(id:)` removes the first ([:250-254](../../../Sources/GraphiteCore/Bookmarks.swift#L250-L254)).
  - `Bookmark` equality compares all `fields` (synthesized `Hashable`, [:47](../../../Sources/GraphiteCore/Bookmarks.swift#L47)).
  - `VaultEntry.id` is the path, while equality compares size and dates ([VaultStore.swift:3-15](../../../Sources/GraphiteCore/VaultStore.swift#L3-L15)).
  - `SearchResult.id` is the path ([VaultSearch.swift:12](../../../Sources/GraphiteIndex/VaultSearch.swift#L12)).
  - `QuickSwitcherMatch.id` is path plus alias ([VaultSearch.swift:474](../../../Sources/GraphiteIndex/VaultSearch.swift#L474)).
- **Why it matters:** SwiftUI lists keyed by `id` treat a renamed group as a new row. An id that two bookmarks share makes "remove" act on the wrong one.
- **Fix direction:** Give `Bookmark` an identity that does not change on edit: its index path in the list plus `ctime`, or a session-only UUID assigned at load. Document that `VaultEntry` and search results are identified by path and compare by snapshot.

### I

#### ISP-VAULT-01 Consumers that need four or five file operations receive all 32 `VaultStore` methods
- **Severity:** Medium
- **Evidence:**
  - `MarkdownSession` holds `VaultStore` ([MarkdownSession.swift:9](../../../Sources/GraphiteUI/MarkdownSession.swift#L9)) and uses `save`, `read`, `fileExists`, `uniquePath` and `propertyTypes` ([MarkdownSession.swift:160-255](../../../Sources/GraphiteUI/MarkdownSession.swift#L160-L255)).
  - `CanvasSession` uses `save`, `read`, `fileExists` and `uniquePath` ([CanvasSession.swift:329-393](../../../Sources/GraphiteUI/CanvasSession.swift#L329-L393)).
  - `VaultStore` is stored or passed in 11 files across UI, Core and Index (grep `(let|var) store: VaultStore|store: VaultStore[,)]` over `Sources/**`, 27 matching lines).
- **Why it matters:** A session or a plugin bridge can move or delete any vault item. Tests of a session must build a real store over a real folder.
- **Fix direction:** Give sessions a `DocumentFileAccess` value with `read`, `save`, `fileExists` and `uniquePath`, implemented by `VaultFiles` (section 3.1). Pass property types as a value loaded by the workspace.

#### ISP-VAULT-02 `ConflictVersionStore` joins discovery and destruction in one six-member protocol
- **Severity:** Low
- **Evidence:** The read requirements are `hasConflictVersions`, `conflictVersions` and `contentsLocation`. The write requirements are `replaceFile`, `keepVersion` and `removeVersions` ([FileVersionConflicts.swift:12-31](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L12-L31)).
- **Why it matters:** The background discovery that scans up to 5,000 files holds a value that can remove versions.
- **Fix direction:** Split into `ConflictVersionDiscovery` (3 reads) and `ConflictVersionResolution` (3 writes). `FileProviderConflictVersions` conforms to both.

#### ISP-VAULT-03 Untyped `[String: Any]` crosses the settings boundary
- **Severity:** Low
- **Evidence:** `types.json` ([VaultStore.swift:130](../../../Sources/GraphiteCore/VaultStore.swift#L130), [:155-173](../../../Sources/GraphiteCore/VaultStore.swift#L155-L173)), templates and daily notes ([Templates.swift:20](../../../Sources/GraphiteCore/Templates.swift#L20), [:58](../../../Sources/GraphiteCore/Templates.swift#L58), [:107-117](../../../Sources/GraphiteCore/Templates.swift#L107-L117)), and `ApplicationConfigurationObject.value(named:) -> Any?` ([ObsidianSettings.swift:310-313](../../../Sources/GraphiteCore/ObsidianSettings.swift#L310-L313)). The reconnaissance counted 12 `[String: Any]` in scope.
- **Why it matters:** `as? Int` on `tabSize` ([ObsidianSettings.swift:212](../../../Sources/GraphiteCore/ObsidianSettings.swift#L212)) and `as? Bool` on the flags read through Foundation's `NSNumber` bridging, so the JSON type in the file does not decide the reading.
- **Fix direction:** Read members as the existing `JSONValue` enum ([Bookmarks.swift:5-42](../../../Sources/GraphiteCore/Bookmarks.swift#L5-L42)), which already keeps whole numbers whole, and map to typed settings once.

### D

#### DIP-VAULT-01 Logic constructs its own writer and reaches the file system and clock directly
- **Severity:** Low
- **Evidence:**
  - `AtomicFileWriter()` is constructed inline at [FileRecovery.swift:65](../../../Sources/GraphiteCore/FileRecovery.swift#L65), [FileRecovery.swift:133](../../../Sources/GraphiteCore/FileRecovery.swift#L133), [VaultIndex.swift:745](../../../Sources/GraphiteIndex/VaultIndex.swift#L745), [VaultIndex.swift:819](../../../Sources/GraphiteIndex/VaultIndex.swift#L819) and [FolderAccess.swift:100](../../../Sources/GraphiteApple/FolderAccess.swift#L100). That is 5, counted by reading.
  - `FileManager.default` appears on 21 lines of `VaultStore.swift` and 13 lines of the index files (grep `FileManager\.default`).
  - The time is read as `Date.now` in the index-cleanup policy ([VaultIndex.swift:240](../../../Sources/GraphiteIndex/VaultIndex.swift#L240)), and `.now` is a default argument at [FileRecovery.swift:49](../../../Sources/GraphiteCore/FileRecovery.swift#L49), [:97](../../../Sources/GraphiteCore/FileRecovery.swift#L97) and [Bookmarks.swift:108-127](../../../Sources/GraphiteCore/Bookmarks.swift#L108-L127).
- **Why it matters:**
  - The 30-day index cleanup cannot be tested without waiting or touching real modification dates.
  - Recovery snapshots and index reads cannot run against a fake file system, so the tests use real temporary folders.
  - The writers built without the vault presenter are correct today: they write outside the vault or only read. Nothing in the type records that this is required.
- **Fix direction:** Pass `now` into `removeUnusedIndexes`. Inject the writer into `FileRecoveryStore` and the index scanner from the composition root. Keep `FileManager` inside the adapters (`VaultFiles`, `IndexLocation`, `FileRecoveryStore`); those are the I/O boundary, and no port is needed beyond them.

#### DIP-VAULT-02 The index's cache folder is chosen inside the database type
- **Severity:** Low
- **Evidence:**
  - `cacheURL(forVault:)` defaults to `FileManager.default.url(for: .cachesDirectory…)` ([VaultIndex.swift:212](../../../Sources/GraphiteIndex/VaultIndex.swift#L212)), and so does `removeIndex` ([:232](../../../Sources/GraphiteIndex/VaultIndex.swift#L232)).
  - The legacy `cacheURL(for:)` always uses the real folder ([:201-205](../../../Sources/GraphiteIndex/VaultIndex.swift#L201-L205)).
  - The workspace calls `cacheURL(forVault:legacyRoot:)` without a folder ([WorkspaceModel.swift:287](../../../Sources/GraphiteUI/WorkspaceModel.swift#L287)).
- **Why it matters:**
  - Workspace tests write their indexes into the real Caches folder and clean up by vault identifier ([UiWorkspaceModelFixTests.swift:24-28](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L24-L28)).
  - The same teardown also deletes `cacheURL(for:)`, a name production no longer creates ([:34](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L34)), so that line deletes nothing.
- **Fix direction:** Build an `IndexLocation` value once, with the caches folder, at the composition root. Delete `cacheURL(for:)` (CC-VAULT-07).

### Clean code

#### CC-VAULT-01 A failed read of an Obsidian settings file is returned as "nothing configured"
- **Severity:** Medium
- **Evidence:**
  - `configurationData(at:)` turns every read failure into `nil` ([VaultStore.swift:254-257](../../../Sources/GraphiteCore/VaultStore.swift#L254-L257)). It applies `try?` to the path and to the coordinated read, which includes the 1 MiB size check.
  - Four readers then treat `nil` as a missing file: `bookmarks` ([:178-180](../../../Sources/GraphiteCore/VaultStore.swift#L178-L180)), `templateSettings` and `dailyNoteSettings` ([:205-216](../../../Sources/GraphiteCore/VaultStore.swift#L205-L216)), and `communityPluginList` ([CommunityPluginList.swift:53-55](../../../Sources/GraphiteCore/CommunityPluginList.swift#L53-L55)).
  - `propertyTypes` returns `[:]` for a missing, unreadable or malformed `types.json` ([VaultStore.swift:126-133](../../../Sources/GraphiteCore/VaultStore.swift#L126-L133)).
  - `TemplateSettings(configurationData:)` and `DailyNoteSettings(configurationData:)` return defaults for malformed JSON ([Templates.swift:20](../../../Sources/GraphiteCore/Templates.swift#L20), [:58](../../../Sources/GraphiteCore/Templates.swift#L58)).
  - The writers are safe. `saveConfiguration` re-reads with `try` and throws ([VaultStore.swift:265](../../../Sources/GraphiteCore/VaultStore.swift#L265)), and the merges refuse non-objects ([VaultStore.swift:159-166](../../../Sources/GraphiteCore/VaultStore.swift#L159-L166), [Templates.swift:110-112](../../../Sources/GraphiteCore/Templates.swift#L110-L112)).
- **Why it matters:** The user sees an empty bookmarks panel, no enabled plugins, or default template folders with no message (BUG-VAULT-02). `settings()` and `appearance()` throw for the same conditions, so the files behave inconsistently.
- **Fix direction:** `configurationData` returns `ConfigurationFileState` (`missing`, `contents(Data)`, `unreadable(Error)`). Readers map `unreadable` to a thrown error that the presenter shows. Only `missing` means defaults.

#### CC-VAULT-02 `GraphiteError` carries prose instead of facts, and one case covers ten different failures
- **Severity:** Medium
- **Evidence:**
  - `GraphiteError` has four cases whose payload is a user sentence (`invalidPath`, `invalidFile`, `oversized`, `unavailable`) and an `errorDescription` in English ([VaultPath.swift:3-14](../../../Sources/GraphiteCore/VaultPath.swift#L3-L14)).
  - `.unavailable(String)` stands for all of these:
    - "already exists" ([VaultStore.swift:321](../../../Sources/GraphiteCore/VaultStore.swift#L321), [:372](../../../Sources/GraphiteCore/VaultStore.swift#L372)).
    - "no longer in the vault" ([:312](../../../Sources/GraphiteCore/VaultStore.swift#L312), [:349](../../../Sources/GraphiteCore/VaultStore.swift#L349), [:381](../../../Sources/GraphiteCore/VaultStore.swift#L381)).
    - "moved into itself" ([:309](../../../Sources/GraphiteCore/VaultStore.swift#L309), [:317](../../../Sources/GraphiteCore/VaultStore.swift#L317)).
    - Provider refusal ([:335](../../../Sources/GraphiteCore/VaultStore.swift#L335), [:360](../../../Sources/GraphiteCore/VaultStore.swift#L360), [:424](../../../Sources/GraphiteCore/VaultStore.swift#L424), [AtomicFileWriter.swift:57](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L57), [:93](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L93), [:141](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L141), [:153](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L153)).
    - No free name ([VaultStore.swift:443](../../../Sources/GraphiteCore/VaultStore.swift#L443)).
    - Version gone ([FileVersionConflicts.swift:143](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L143)).
    - Folder not found ([FolderAccess.swift:75](../../../Sources/GraphiteApple/FolderAccess.swift#L75)).
    - Scan already running ([VaultIndex.swift:573](../../../Sources/GraphiteIndex/VaultIndex.swift#L573)).
    - Cannot enumerate ([:592](../../../Sources/GraphiteIndex/VaultIndex.swift#L592)).
  - `invalidFile` is used for invalid vault names ([VaultList.swift:94-99](../../../Sources/GraphiteCore/VaultList.swift#L94-L99)), an occupied folder name ([FolderAccess.swift:95](../../../Sources/GraphiteApple/FolderAccess.swift#L95)) and benchmark mismatches ([GraphiteBenchmarks/main.swift:57](../../../Sources/GraphiteBenchmarks/main.swift#L57), [:71](../../../Sources/GraphiteBenchmarks/main.swift#L71)).
  - The synthesized `Equatable` compares the sentences.
  - 44 thrown sentences in scope (grep `GraphiteError\.(invalidFile|unavailable|invalidPath|oversized)\("` per directory): 33 in 8 Core files, 4 in `VaultIndex.swift`, 5 in GraphiteApple, 2 in the benchmark.
- **Why it matters:** Callers can branch only on `.conflict` and `.oversized` ([VaultFileOperations.swift:107](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L107), [:246](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L246), [FileRecovery.swift:184](../../../Sources/GraphiteCore/FileRecovery.swift#L184)). "The name is taken" and "the provider refused" cannot be told apart without parsing English. Tests that assert on messages break when copy changes. A localization pass must touch domain code.
- **Fix direction:** Typed cases with facts (`.alreadyExists(VaultPath)`, `.missing(VaultPath)`, `.movesIntoItself`, `.coordinationRefused(Operation)`, `.noFreeName`, `.tooLarge(limitBytes: Int)`) and one presenter in the UI that turns them into words. The same applies to `LinkUpdateFailure.explanation` ([VaultFileOperations.swift:38-48](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L38-L48)) and `SearchError.errorDescription` ([VaultSearch.swift:92-97](../../../Sources/GraphiteIndex/VaultSearch.swift#L92-L97)).

#### CC-VAULT-03 The frontmatter regular expression is written four times
- **Severity:** Medium
- **Evidence:** [MarkdownSemantics.swift:29](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L29), [MarkdownSemantics.swift:625](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L625) (`FrontmatterLocator`), [NoteProperties.swift:505](../../../Sources/GraphiteCore/NoteProperties.swift#L505) (`FrontmatterRegion`, whose comment says it must match "the way `FrontmatterLocator` matches it", [:503](../../../Sources/GraphiteCore/NoteProperties.swift#L503)), and [BasePropertyEditing.swift:6](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L6). Found with grep `\\A---`.
- **Why it matters:** Property edits, the parser, link scanning (`FrontmatterLocator.length`, [LinkRewriter.swift:21](../../../Sources/GraphiteCore/LinkRewriter.swift#L21)) and base cell edits must agree on where frontmatter ends. A fix to one copy (for example a byte order mark before `---`) silently splits them, and a property edit then writes into the body.
- **Fix direction:** One `FrontmatterLocator` returning a `FrontmatterRegion` (whole range, YAML range, line ending). All four call sites use it.

#### CC-VAULT-04 Facts and small algorithms are duplicated across files
- **Severity:** Low
- **Evidence (counted by reading):**

| Fact or algorithm | Copies |
| --- | --- |
| SHA-256 as lowercase hex | [AtomicFileWriter.swift:8](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L8), [:19](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L19), [FileRecovery.swift:153](../../../Sources/GraphiteCore/FileRecovery.swift#L153), [VaultIndex.swift:203](../../../Sources/GraphiteIndex/VaultIndex.swift#L203), [:216](../../../Sources/GraphiteIndex/VaultIndex.swift#L216) |
| Staging file name `.<UUID>.tmp` | Written at [AtomicFileWriter.swift:69](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L69), recognized at [FolderAccess.swift:184-189](../../../Sources/GraphiteApple/FolderAccess.swift#L184-L189). The recognizer's comment says staging happens "next to the destination" ([:181-183](../../../Sources/GraphiteApple/FolderAccess.swift#L181-L183)); that is now only the fallback ([AtomicFileWriter.swift:98-105](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L98-L105)). |
| Index folder `Graphite/Indexes` | [VaultIndex.swift:204](../../../Sources/GraphiteIndex/VaultIndex.swift#L204), [:213](../../../Sources/GraphiteIndex/VaultIndex.swift#L213), [:233](../../../Sources/GraphiteIndex/VaultIndex.swift#L233) |
| SQLite companion suffixes `["", "-wal", "-shm"]` | [VaultIndex.swift:220](../../../Sources/GraphiteIndex/VaultIndex.swift#L220), [:234](../../../Sources/GraphiteIndex/VaultIndex.swift#L234), [:247](../../../Sources/GraphiteIndex/VaultIndex.swift#L247) |
| YAML null spellings `["", "~", "null", "Null", "NULL"]` | [NoteProperties.swift:213](../../../Sources/GraphiteCore/NoteProperties.swift#L213), [SearchQuery.swift:842](../../../Sources/GraphiteCore/SearchQuery.swift#L842) |
| "Create the settings file only when the change leaves something to keep, then merge" | [VaultStore.swift:185-202](../../../Sources/GraphiteCore/VaultStore.swift#L185-L202), [CommunityPluginList.swift:59-77](../../../Sources/GraphiteCore/CommunityPluginList.swift#L59-L77) |
| Link format (shortest/relative/absolute) | [AttachmentResolver.swift:21-25](../../../Sources/GraphiteCore/AttachmentResolver.swift#L21-L25), [LinkCompletion.swift:361-365](../../../Sources/GraphiteCore/LinkCompletion.swift#L361-L365) |
| Sort-order titles ("File name (A to Z)" …) | [ObsidianSettings.swift:99-108](../../../Sources/GraphiteCore/ObsidianSettings.swift#L99-L108), [VaultSearch.swift:23-32](../../../Sources/GraphiteIndex/VaultSearch.swift#L23-L32) |
| Resolution cap `50` | [VaultIndex.swift:370](../../../Sources/GraphiteIndex/VaultIndex.swift#L370), [:387](../../../Sources/GraphiteIndex/VaultIndex.swift#L387), [:389](../../../Sources/GraphiteIndex/VaultIndex.swift#L389), [:393](../../../Sources/GraphiteIndex/VaultIndex.swift#L393), [:397](../../../Sources/GraphiteIndex/VaultIndex.swift#L397), [VaultGraph.swift:107](../../../Sources/GraphiteIndex/VaultGraph.swift#L107), [:131](../../../Sources/GraphiteIndex/VaultGraph.swift#L131) |
| Batch size `64` | [VaultIndex.swift:53](../../../Sources/GraphiteIndex/VaultIndex.swift#L53), [GraphiteBenchmarks/main.swift:44](../../../Sources/GraphiteBenchmarks/main.swift#L44), [:46](../../../Sources/GraphiteBenchmarks/main.swift#L46) |

- **Why it matters:** Each pair can drift. The staging pair already has, in its documentation: the recognizer's comment describes the fallback as the rule.
- **Fix direction:** One named owner per row, such as `FileRevision.hexDigest(of:)`, `AtomicFileWriter.stagingFileName`, `IndexLocation`, `YAMLNull.spellings`, `LinkFormat.target(for:from:isNameUnique:)` and `LinkResolution.maximumCandidates`.

#### CC-VAULT-05 Thirteen functions exceed 40 code lines
- **Severity:** Low
- **Evidence (reconnaissance, spot-checked by reading):**
  - `MomentDateFormat.value` 70 ([MomentDateFormat.swift:135-204](../../../Sources/GraphiteCore/MomentDateFormat.swift#L135-L204)).
  - `ApplicationConfigurationObject.scannedMembers` 69 ([ObsidianSettings.swift:358-427](../../../Sources/GraphiteCore/ObsidianSettings.swift#L358-L427)).
  - `NoteProperties.splicedYAML` 63 ([NoteProperties.swift:344-417](../../../Sources/GraphiteCore/NoteProperties.swift#L344-L417)).
  - `SearchQueryParser.tokens` 60 ([SearchQuery.swift:76-136](../../../Sources/GraphiteCore/SearchQuery.swift#L76-L136)).
  - `VaultIndex.searchPage` 59 ([VaultSearch.swift:140-206](../../../Sources/GraphiteIndex/VaultSearch.swift#L140-L206)).
  - `VaultIndex.reconcile` 56.
  - `SearchSQLCompiler.termCondition` 54.
  - `GraphiteBenchmarks.main` 53.
  - `VaultFileOperations.linkUpdates` 49.
  - `VaultIndex.write` 48.
  - `VaultIndex.refresh` 48.
  - `VaultIndex.init` 48.
  - `MomentDateFormat.date` 44.
  - `MomentDateFormat.value` also recomputes all date components, plus an ISO calendar, for every token ([:136-143](../../../Sources/GraphiteCore/MomentDateFormat.swift#L136-L143)).
- **Why it matters:** `searchPage` holds name-first results, paging, time budget, cancellation and excerpt fetching in one loop with a labelled `break`. That is the hardest place in the area to change safely.
- **Fix direction:**
  - `searchPage`: split into `nameMatches`, `nextCandidateBatch`, `acceptCandidates` and `excerpts`.
  - `MomentDateFormat.value`: compute one `MomentDateFields` per call to `string(from:)` and look tokens up in a table.
  - `VaultIndex.init`: move the migrations to an `IndexSchemaMigrations` list.

#### CC-VAULT-06 Size-limit errors name the editor whatever the caller
- **Severity:** Low
- **Evidence:** `AtomicFileWriter.read` throws "This file exceeds the current editor's memory budget." for any `maximumBytes` ([AtomicFileWriter.swift:50](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L50)). The same sentence is copied into the index ([VaultIndex.swift:753](../../../Sources/GraphiteIndex/VaultIndex.swift#L753)). It is reached for `app.json` and `appearance.json` above 1 MiB ([VaultStore.swift:118](../../../Sources/GraphiteCore/VaultStore.swift#L118), [:227](../../../Sources/GraphiteCore/VaultStore.swift#L227)), for link-rewrite reads ([VaultFileOperations.swift:106](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L106)), and for theme files.
- **Why it matters:** A user with a large `app.json` is told about an editor they did not open.
- **Fix direction:** `.tooLarge(path:limitBytes:)` as a typed error (CC-VAULT-02), worded by the presenter per context.

#### CC-VAULT-07 Production code kept only for tests or for an unused option
- **Severity:** Low
- **Evidence:**
  - `VaultIndex.cacheURL(for:)` is public and called only from two test teardowns ([VaultIndex.swift:201-205](../../../Sources/GraphiteIndex/VaultIndex.swift#L201-L205); grep `cacheURL\(for:` finds [UiSidebarPaletteFixTests.swift:27](../../../Tests/GraphiteUITests/UiSidebarPaletteFixTests.swift#L27) and [UiWorkspaceModelFixTests.swift:34](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L34)).
  - `BookmarkList.add(_:toGroup:)` has a group parameter no production caller passes ([Bookmarks.swift:213-216](../../../Sources/GraphiteCore/Bookmarks.swift#L213-L216); every call in [WorkspaceBookmarks.swift](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift) and [MarkdownPane.swift:1092](../../../Sources/GraphiteUI/MarkdownPane.swift#L1092) omits it). The parameter also ignores `update`'s result, so a bookmark added to a group id that no longer exists is dropped without a signal ([:215](../../../Sources/GraphiteCore/Bookmarks.swift#L215)).
  - `FuzzyMatcher.matchWithoutASCIIPath` ([Navigation.swift:41-46](../../../Sources/GraphiteCore/Navigation.swift#L41-L46)) and `VaultIndex.graphLinkResolver()` ([VaultGraph.swift:47-50](../../../Sources/GraphiteIndex/VaultGraph.swift#L47-L50)) are test hooks with no production caller (grep over `Sources/**`).
- **Why it matters:** Dead public API is maintained and documented as if real. The `toGroup` path silently loses data the day a caller uses it.
- **Fix direction:** Delete `cacheURL(for:)` and the test lines that call it. Make `add(_:toGroup:)` return whether the bookmark was placed, or remove the parameter until a "move to group" command exists. Keep the two test hooks only as the contract tests of LSP-VAULT-03 and of the ASCII fast path.

#### CC-VAULT-08 Some names state a narrower or different role than the type has
- **Severity:** Low
- **Evidence:**
  - `IndexedFile.markdown` also holds a canvas's JSON ([VaultIndex.swift:12-13](../../../Sources/GraphiteIndex/VaultIndex.swift#L12-L13)).
  - `VaultListSortOrder` orders the Tags and Properties views, not the vault list ([TagsAndProperties.swift:4-6](../../../Sources/GraphiteCore/TagsAndProperties.swift#L4-L6)).
  - `ApplicationConfigurationObject` also writes `appearance.json` ([ObsidianAppearance.swift:187](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L187)).
  - `PluginConfiguration` serves Obsidian's core Templates and Daily notes plugins, not community plugins ([Templates.swift:96](../../../Sources/GraphiteCore/Templates.swift#L96)).
  - `name_key` and `path_key` hold Unicode-composed text that is not folded, while `folded_name` and `folded_path` hold the folded key ([VaultIndex.swift:327-328](../../../Sources/GraphiteIndex/VaultIndex.swift#L327-L328)). Two "key" spellings for two different normalizations made LSP-VAULT-01 easy to write.
- **Why it matters:** Readers pick the wrong column or type by its name.
- **Fix direction:** Rename to `IndexedFile.text`, `NamedCountSortOrder`, `ObsidianJSONObjectFile`, `ObsidianCorePluginSettingsFile`, and `composed_name`/`composed_path`, or drop those columns after LSP-VAULT-01.

#### CC-VAULT-09 Comments narrate incidents instead of stating the rule
- **Severity:** Low
- **Evidence:**
  - "crashed on the 512 KB stack … (Sep 2026, debug build)" ([YAMLAliasExpansionLimits.swift:11-13](../../../Sources/GraphiteCore/YAMLAliasExpansionLimits.swift#L11-L13)).
  - "nesting it … deadlocked the vault's file actor" ([VaultStore.swift:387-389](../../../Sources/GraphiteCore/VaultStore.swift#L387-L389)).
  - "so `[[éclair]]` missed `Éclair.md`" ([VaultIndex.swift:155-156](../../../Sources/GraphiteIndex/VaultIndex.swift#L155-L156)).
  - "as a suffix it also matched `Other/Folder/Note.md`" ([VaultIndex.swift:386](../../../Sources/GraphiteIndex/VaultIndex.swift#L386)).
  - "and the link to the note being renamed was neither rewritten nor reported" ([VaultFileOperations.swift:329-330](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L329-L330)).
  - That is 5, counted by reading. Most other comments in the area state the current rule and are the area's main documentation.
- **Why it matters:** History in comments ages. The constraint is clear, but the dates and past failures belong in commit messages and test names.
- **Fix direction:** Keep the rule ("trashItem coordinates the move itself on iPadOS, so it must run outside a coordinated write of the same item") and move the incident to the regression test's name.

#### CC-VAULT-10 Tests of the area are named after audit rounds and mix unrelated subjects
- **Severity:** Low
- **Evidence:**
  - Test files named after rounds rather than the type they pin: `CoreFilesSettingsFixTests`, `IndexFileOperationsFixTests`, `IndexVaultIndexFixTests`, `IndexSearchFixTests`, `CoreSearchQueryFixTests`, `CoreLinksFixTests`, `CoreAreaHandoffTests`, `CoreAreaIndexHandoffTests` (listed with `list_files` over `Tests/GraphiteCoreTests` and `Tests/GraphiteIndexTests`).
  - `VaultTests` pins `VaultPath` and `AtomicFileWriter` next to heading editing and PDF coordinate transforms ([VaultTests.swift:5-52](../../../Tests/GraphiteCoreTests/VaultTests.swift#L5-L52), [:131](../../../Tests/GraphiteCoreTests/VaultTests.swift#L131), [:161](../../../Tests/GraphiteCoreTests/VaultTests.swift#L161)).
  - A planning test asserts wall-clock time with `Date()` ([IndexFileOperationsFixTests.swift:142-147](../../../Tests/GraphiteIndexTests/IndexFileOperationsFixTests.swift#L142-L147)).
  - Workspace tests share `UserDefaults.standard` and the real Caches folder ([UiWorkspaceModelFixTests.swift:17-36](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L36)).
- **Why it matters:** A cleanup that moves a type cannot find its tests by name. Timing and shared-preference tests are flaky on slower devices and when run in parallel.
- **Fix direction:**
  - Rename by production type: `AtomicFileWriterTests`, `VaultPathTests`, `VaultStoreFileManagementTests`, `ObsidianSettingsFileTests`, `VaultIndexScanTests`, `VaultFileOperationsTests`.
  - Replace the timing assertion with a query-count assertion.
  - Inject a suite-specific `UserDefaults` and caches folder.

## 5. Defects and latent bugs

#### BUG-VAULT-01 Renaming a file to a name that another file shares except for non-ASCII capitals rewrites links to an ambiguous bare name
- **Trigger:**
  - `Other/éclair.md` exists, and `Linker.md` contains `[[Old]]`.
  - The user renames `Notes/Old.md` to `Notes/Éclair.md` and accepts "Update links". The same happens with any pair that differs only in the capital of a non-ASCII letter (`Über`/`über`, `Δ`/`δ`).
- **Path:**
  1. The planner records the rename as a name change ([VaultFileOperations.swift:97](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L97)). For each link it asks whether the new name is unique ([:181](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L181)).
  2. `nameCount` calls `fileCount(named:excluding:)` ([:360](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L360)). That query compares `name_key = 'Éclair.md' COLLATE NOCASE` ([:392](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L392)). NOCASE folds ASCII only ([VaultIndex.swift:155-156](../../../Sources/GraphiteIndex/VaultIndex.swift#L155-L156)), so `éclair.md` does not count: the result is 0.
  3. The renamed file adds 1 ([VaultFileOperations.swift:361](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L361)). The count is 1, so `isNameUnique` is true.
  4. `LinkRewriter.style` reads `Old` as a bare name ([LinkRewriter.swift:509](../../../Sources/GraphiteCore/LinkRewriter.swift#L509)). `unchangedName` returns nil because the name changed ([:487-493](../../../Sources/GraphiteCore/LinkRewriter.swift#L487-L493)). `pathPart` returns `finished(target.name)`, which is `Éclair` ([:473](../../../Sources/GraphiteCore/LinkRewriter.swift#L473)).
  5. The move writes `[[Éclair]]` into `Linker.md` ([VaultFileOperations.swift:244](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L244)).
  6. Resolving `[[Éclair]]` from `Linker.md`: the direct candidate `Éclair.md` at the root does not exist ([MarkdownSemantics.swift:898-900](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L900), [VaultIndex.swift:370-372](../../../Sources/GraphiteIndex/VaultIndex.swift#L370-L372)). The name lookup by `folded_name = 'éclair.md'` then returns both files ([VaultIndex.swift:393](../../../Sources/GraphiteIndex/VaultIndex.swift#L393), [:399](../../../Sources/GraphiteIndex/VaultIndex.swift#L399)).
  7. Backlinks accept only a single resolution ([VaultIndex.swift:492](../../../Sources/GraphiteIndex/VaultIndex.swift#L492)).
- **Effect:** After an "Update links" that reported success, the link no longer reaches the renamed note in Graphite. Backlinks and the graph drop it, and following it meets two candidates. Obsidian resolves the bare name by its own rule, which can pick the other file.
- **Platforms / reach:** iPad, iPhone, Mac. Normal rename path with link updates. The existing test covers only ASCII names ([FileOperationTests.swift:69-74](../../../Tests/GraphiteIndexTests/FileOperationTests.swift#L69-L74)).
- **Confidence:** Traced within Graphite. Obsidian's choice between the two files is not established by reading.

#### BUG-VAULT-02 A `bookmarks.json` Graphite cannot read shows as "no bookmarks", with no error
- **Trigger:** The vault's `.obsidian/bookmarks.json` is larger than 1 MiB, or the file provider refuses or fails the coordinated read (for example an iCloud placeholder that cannot download offline).
- **Path:**
  1. `reloadBookmarks` calls `store.bookmarks()` ([WorkspaceBookmarks.swift:9](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L9)).
  2. `VaultStore.bookmarks` reads through `configurationData` ([VaultStore.swift:178-180](../../../Sources/GraphiteCore/VaultStore.swift#L178-L180)).
  3. `try? writer.read(url, maximumBytes: 1_048_576)` returns nil. The size check throws `oversized` ([AtomicFileWriter.swift:48-51](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L48-L51)), and a coordination failure throws at [:56-57](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L56-L57); `try?` swallows both ([VaultStore.swift:254-257](../../../Sources/GraphiteCore/VaultStore.swift#L254-L257)).
  4. `BookmarkList(configurationData: nil)` returns an empty list without throwing ([Bookmarks.swift:170-171](../../../Sources/GraphiteCore/Bookmarks.swift#L170-L171)).
  5. The workspace publishes the empty list. The `catch` that would set `errorMessage` never runs ([WorkspaceBookmarks.swift:9-10](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L9-L10)).
  6. Adding a bookmark then fails with the oversize message about "the current editor's memory budget" ([VaultStore.swift:188-193](../../../Sources/GraphiteCore/VaultStore.swift#L188-L193), [:265](../../../Sources/GraphiteCore/VaultStore.swift#L265); CC-VAULT-06).
- **Effect:**
  - Every bookmark the user made in Obsidian is invisible in Graphite, and Graphite says nothing about why.
  - Bookmark-following on rename is skipped, because the guard reads the empty list ([WorkspaceBookmarks.swift:94](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L94)). Bookmarks in the file therefore point at old paths after a rename in Graphite.
  - No data in the file is lost: every write re-reads with `try` and fails ([VaultStore.swift:265](../../../Sources/GraphiteCore/VaultStore.swift#L265)).
- **Platforms / reach:** iPad, iPhone, Mac.
  - Size trigger: rare (about 1 MiB of bookmarks).
  - Provider trigger: any cloud vault offline.
  - The same read path serves `community-plugins.json`, so an unreadable list reads as "no plugins enabled" ([CommunityPluginList.swift:53-55](../../../Sources/GraphiteCore/CommunityPluginList.swift#L53-L55)). It also serves `templates.json` and `daily-notes.json`, which read as defaults ([VaultStore.swift:205-216](../../../Sources/GraphiteCore/VaultStore.swift#L205-L216)).
- **Confidence:** Traced for bookmarks. The plugin runtime's reaction to an empty list was not followed.

#### BUG-VAULT-03 `content:` searches with a regular expression that matches empty text list every canvas
- **Trigger:** The vault has `.canvas` files, and the user searches `content:/^$/`, `content:/^\s*$/` or any `content:` pattern that matches empty text.
- **Path:**
  1. A canvas is read for its links and parsed into non-optional semantics ([VaultIndex.swift:278-280](../../../Sources/GraphiteIndex/VaultIndex.swift#L278-L280); [CanvasLinks.swift:74](../../../Sources/GraphiteCore/CanvasLinks.swift#L74) returns `NoteSemantics`).
  2. `write` stores the canvas with `contentIndexed = 1` ([VaultIndex.swift:324](../../../Sources/GraphiteIndex/VaultIndex.swift#L324)) and an empty search body ([:261-263](../../../Sources/GraphiteIndex/VaultIndex.swift#L261-L263), [:332](../../../Sources/GraphiteIndex/VaultIndex.swift#L332)).
  3. The compiler's content condition is `files.contentIndexed = 1 AND … graphite_regexp(?, body)`, marked exact ([VaultSearch.swift:346](../../../Sources/GraphiteIndex/VaultSearch.swift#L346), [:351-352](../../../Sources/GraphiteIndex/VaultSearch.swift#L351-L352)). Its own comment states that files without indexed text must not match ([:344-345](../../../Sources/GraphiteIndex/VaultSearch.swift#L344-L345)).
  4. Because the condition is exact, the matcher is skipped ([VaultSearch.swift:177](../../../Sources/GraphiteIndex/VaultSearch.swift#L177)), and every canvas row is accepted ([:189-190](../../../Sources/GraphiteIndex/VaultSearch.swift#L189-L190)).
  5. The matcher gives a canvas no content ([VaultSearch.swift:272](../../../Sources/GraphiteIndex/VaultSearch.swift#L272), [SearchQuery.swift:912](../../../Sources/GraphiteCore/SearchQuery.swift#L912)), so the same query inside a non-exact expression (for example combined with `line:`) excludes them. The two paths disagree.
- **Effect:** Canvases appear as content matches for "empty note" searches, while Architecture.md:146 states that files without indexed text never match a content condition.
- **Platforms / reach:** iPad, iPhone, Mac. Normal search path, with an unusual query.
- **Confidence:** Traced.

## 6. What to keep

| # | Design | Evidence | Why it is sound |
| --- | --- | --- | --- |
| 1 | Revision check inside the coordinated write accessor, by full SHA-256 and size | [AtomicFileWriter.swift:76-91](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L76-L91), [:4-21](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L4-L21) | Same-size external edits and deletions are conflicts; no time window between check and replace inside the coordination. Pinned by [VaultTests.swift:36](../../../Tests/GraphiteCoreTests/VaultTests.swift#L36). |
| 2 | Staging in the item-replacement folder on the destination volume, `F_BARRIERFSYNC` before the rename, `F_FULLFSYNC` after | [AtomicFileWriter.swift:67-127](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L67-L127) | A crash never leaves a staged file in a synced vault; power loss leaves the old or the new file. Pinned by [CoreFilesSettingsFixTests.swift:204](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L204). |
| 3 | `VaultPath` as the only path type: NFC, `/`-scalar splitting, `..` refused at the root, symbolic links resolved component by component, re-validated on decode | [VaultPath.swift:26-153](../../../Sources/GraphiteCore/VaultPath.swift#L26-L153) | Closes path escapes and Unicode duplicates for every caller; tested against chained links and combining marks ([CoreFilesSettingsFixTests.swift:56-112](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L56-L112)). |
| 4 | `move` never replaces, allows a case-only rename, and refuses moving a folder into itself by file identity | [VaultStore.swift:307-337](../../../Sources/GraphiteCore/VaultStore.swift#L307-L337) | Correct on case-insensitive volumes, where a name comparison alone is wrong. |
| 5 | Free names plus `.absent` writes | [VaultStore.swift:429-455](../../../Sources/GraphiteCore/VaultStore.swift#L429-L455), [AtomicFileWriter.swift:80](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L80) | The check-then-write race is safe: a name taken in between fails as a conflict instead of overwriting. |
| 6 | Deletion: coordinated deletion before and outside `trashItem`, fallback to the vault's `.trash` | [VaultStore.swift:378-415](../../../Sources/GraphiteCore/VaultStore.swift#L378-L415) | Presenters let go first; nesting deadlocks on iPadOS; a provider without trash still keeps the file. |
| 7 | `app.json` written member by member from the settings the change started from | [ObsidianSettings.swift:224-261](../../../Sources/GraphiteCore/ObsidianSettings.swift#L224-L261), [:288-330](../../../Sources/GraphiteCore/ObsidianSettings.swift#L288-L330) | Keys changed in Obsidian meanwhile survive; unknown keys keep exact bytes and position; duplicate keys read as `JSON.parse` reads them. Pinned by [CoreFilesSettingsFixTests.swift:229-336](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L229-L336). |
| 8 | Read-modify-write of settings files against the file as it is now, with "unchanged leaves the bytes" | [VaultStore.swift:185-202](../../../Sources/GraphiteCore/VaultStore.swift#L185-L202), [:261-269](../../../Sources/GraphiteCore/VaultStore.swift#L261-L269) | A bookmark added in Obsidian between Graphite's read and write is kept. |
| 9 | `JSONValue` and `Bookmark.fields` keep every field, whole numbers whole | [Bookmarks.swift:5-48](../../../Sources/GraphiteCore/Bookmarks.swift#L5-L48) | Unknown bookmark kinds and keys round-trip. |
| 10 | Frontmatter splicing with read-back verification and a fallback | [NoteProperties.swift:72-91](../../../Sources/GraphiteCore/NoteProperties.swift#L72-L91), [:344-417](../../../Sources/GraphiteCore/NoteProperties.swift#L344-L417) | Comments, number spellings and anchors of untouched properties stay byte-exact; a splice that would read differently is refused. |
| 11 | Link rewrites: planned before the move, refused when a link cannot be located, nested replacements merged, BOM kept, each note written only at its planned revision | [VaultFileOperations.swift:88-143](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L143), [:168-199](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L168-L199), [:236-253](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L236-L253); [LinkRewriter.swift:585-641](../../../Sources/GraphiteCore/LinkRewriter.swift#L585-L641) | A real planner/executor split; every failure is reported per note with a reason, never silently. |
| 12 | Index scan: prune only after a complete enumeration; per-file failure isolation; refresh during a scan wins over the scan's older reading | [VaultIndex.swift:586-638](../../../Sources/GraphiteIndex/VaultIndex.swift#L586-L638), [:769-808](../../../Sources/GraphiteIndex/VaultIndex.swift#L769-L808) | A failed listing never deletes rows of files that exist; a save during a scan is never undone. Pinned by [IndexVaultIndexFixTests.swift:241-298](../../../Tests/GraphiteIndexTests/IndexVaultIndexFixTests.swift#L241-L298). |
| 13 | One file coordination per batch of note reads, falling back to one per file | [VaultIndex.swift:731-747](../../../Sources/GraphiteIndex/VaultIndex.swift#L731-L747) | The code comment measures it at a tenth of the cost of per-file coordination ([:728-730](../../../Sources/GraphiteIndex/VaultIndex.swift#L728-L730)), and one bad file costs only itself. |
| 14 | Search pages bounded by count and time, continued by sort position, cancellable, regular expressions time-limited | [VaultSearch.swift:118-206](../../../Sources/GraphiteIndex/VaultSearch.swift#L118-L206), [TimeLimitedRegularExpression.swift:20-41](../../../Sources/GraphiteCore/TimeLimitedRegularExpression.swift#L20-L41) | Typing never holds the database; a hostile pattern cannot hang the app. |
| 15 | `SearchTextTokens` reproduces SQLite's `unicode61` tokenizer | [SearchQuery.swift:393-553](../../../Sources/GraphiteCore/SearchQuery.swift#L393-L553) | The matcher and FTS5 agree, so exact SQL conditions skip per-note checks; pinned by `CoreSearchQueryUnicode61AgreementTests`. |
| 16 | `SearchSQLCompiler` conditions are supersets unless marked exact | [VaultSearch.swift:279-333](../../../Sources/GraphiteIndex/VaultSearch.swift#L279-L333) | `NOT` of an inexact condition becomes "everything", never a false negative. |
| 17 | YAML anchor and alias-expansion bounds before and after composing | [YAMLAliasExpansionLimits.swift:32-102](../../../Sources/GraphiteCore/YAMLAliasExpansionLimits.swift#L32-L102) | Stops "billion laughs" and deep alias chains before any walk; iterative, no recursion. |
| 18 | Conflict versions: discovery never downloads; a kept version is removed only after its separate file is published | [FileVersionConflicts.swift:51-65](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L51-L65), [:105-121](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L105-L121) | Placeholders stay placeholders; no version is lost on a failed copy. |
| 19 | Folder access: bookmark refresh when stale, app-Documents folders remembered by relative path on iOS, scope released on deinit | [FolderAccess.swift:8-21](../../../Sources/GraphiteApple/FolderAccess.swift#L8-L21), [:29-82](../../../Sources/GraphiteApple/FolderAccess.swift#L29-L82) | Survives app updates that move the container and folders moved by the user. |
| 20 | `VaultMonitor`'s one mutable field behind a `Mutex`, serial queue, documented `@unchecked Sendable` | [FolderAccess.swift:131-174](../../../Sources/GraphiteApple/FolderAccess.swift#L131-L174) | The only unsafe-concurrency escape in the Apple files of this area, with its invariant stated. |
| 21 | File recovery outside the vault, as user content, with sequence suffixes and one shared lock | [FileRecovery.swift:4-72](../../../Sources/GraphiteCore/FileRecovery.swift#L4-L72), [:170-189](../../../Sources/GraphiteCore/FileRecovery.swift#L170-L189) | Same-millisecond and concurrent snapshots are all kept ([FileRecoveryTests.swift:83-131](../../../Tests/GraphiteCoreTests/FileRecoveryTests.swift#L83-L131)). |
| 22 | Pure value types for navigation state: `TabLayout`, `NavigationHistory`, `RecentFiles`, `DocumentPlaceMemory`, `VaultList` | [TabLayout.swift:44-401](../../../Sources/GraphiteCore/TabLayout.swift#L44-L401), [Navigation.swift:219-297](../../../Sources/GraphiteCore/Navigation.swift#L219-L297), [DocumentPlaces.swift:50-98](../../../Sources/GraphiteCore/DocumentPlaces.swift#L50-L98), [VaultList.swift:37-102](../../../Sources/GraphiteCore/VaultList.swift#L37-L102) | No I/O; invariants enforced in the type; unit-tested without a host. |
| 23 | `MomentDateFormat.date` accepts a date only if it writes back to the same text | [MomentDateFormat.swift:84-85](../../../Sources/GraphiteCore/MomentDateFormat.swift#L84-L85) | Rejects impossible days (31 April) without a calendar table. |
| 24 | `Int(clampingWholePartOf:)` for untrusted numbers | [WholeNumberConversion.swift:7-15](../../../Sources/GraphiteCore/WholeNumberConversion.swift#L7-L15) | Removes the `Int(_:)` trap on `1e300` and `.inf` everywhere it is used. |

## 7. Blueprint for this area

### Target shape

| Type | Single responsibility | Notes |
| --- | --- | --- |
| `VaultPath`, `DocumentKind` (+ `holdsLinks`) | Path identity and file-kind classification | Unchanged apart from `holdsLinks` (OCP-VAULT-04). `GraphiteError` moves to its own file. |
| `AtomicFileWriter` | Coordinated safe read, replace, copy, folder creation | Unchanged. Owns `stagingFileName`, which `VaultMonitor` reuses. |
| `VaultFiles` (actor) | Read, save, exists, list, create folder, free name | The capability sessions receive (`DocumentFileAccess` is a value of its methods, no protocol). |
| `VaultFileManagement` | Move, duplicate, create folder, delete by method | Holds `VaultFiles`. |
| `FreeFileName` | Pure "Name", "Name 1"… choice from an `isTaken` function | Unit-testable without a disk. |
| `ObsidianConfigurationFile` (enum) | One case per `.obsidian` file: path, owned keys | The one registry of settings file names. |
| `ObsidianJSONObjectFile` (today `ApplicationConfigurationObject`) | Member-preserving JSON object read and write | Used by every settings file (OCP-VAULT-02). |
| `ObsidianConfigurationFiles` | Read state (`missing`/`contents`/`unreadable`) and merge-write each file | Fixes BUG-VAULT-02. |
| `ObsidianSettingsStore` | `app.json` and `appearance.json` with their baselines | The baseline travels in the value returned by the read. |
| `FrontmatterLocator` | The one frontmatter region rule | Replaces 4 regular expressions (CC-VAULT-03). |
| `IndexDatabase`, `IndexSchemaMigrations`, `IndexLocation` | Connection, schema, cache placement | `IndexLocation` takes caches folder and `now`. |
| `IndexRowWriter` | Prepare and write and remove a file's rows | Owns the multi-table deletion. |
| `VaultScanner` (actor) | `reconcile` and `refresh` with `ScanPhase` | Only owner of scan state. |
| `LinkIndexQueries` over `LinkNameTable` | Resolution, backlinks, name counts | SQL and in-memory tables run one contract suite (LSP-VAULT-03). |
| `IndexSearch`, `QuickSwitcherQueries`, `TagAndPropertyQueries`, `GraphQueries`, `PlacedNoteQueries` | One query family each | Read-only over the shared queue. |
| `SearchQueryParser`, `SearchTextTokens`, `SearchMatcher`, `SearchContentParts`, `SearchExcerpts`, `SearchSQLCompiler` | Unchanged types, one file each | `SearchScope` switches spelled out. |
| `ConflictVersionDiscovery`, `ConflictVersionResolution` | Read versions; resolve versions | One production adapter, one test-support fake, one contract suite. |
| `BookmarkKind` | Typed bookmark kinds with `unknown(String)` | `fields` stays the stored truth. |
| Typed `VaultError` cases plus one UI presenter | Facts, not prose | Replaces string payloads (CC-VAULT-02). |

### Ordered steps (each leaves the app building and behaving the same, except where a step fixes a listed bug)

1. **Pin the persisted formats first.** Add golden round-trip tests for VAULT-INV-08 to VAULT-INV-16 and VAULT-INV-24 to VAULT-INV-27, plus a migration-name test (VAULT-INV-17). No production change.
2. **Fix BUG-VAULT-01.** Route `fileCount(named:excluding:)` through `folded_name` and add the planner-versus-resolver contract test with `Éclair.md`/`éclair.md`.
3. **Fix BUG-VAULT-03.** Exclude canvases from content conditions. Either add `IndexedContentState.linksOnly = 3`, written for canvases, with migration `"canvas-links-only-10"` that sets it for existing canvas rows; or add `files.path NOT LIKE '%.canvas'` to the content condition. Add the test `content:/^$/` against a vault with a canvas.
4. **Fix BUG-VAULT-02.** Introduce `ConfigurationFileState`, make `bookmarks()`, `templateSettings()`, `dailyNoteSettings()`, `communityPluginList()` and `propertyTypes()` throw on `unreadable`, and show the error.
5. **Mechanical file splits.** One file per concept for `SearchQuery.swift`, `LinkRewriter.swift`, `VaultPath.swift` (`GraphiteError`), `VaultStore.swift` (`FileNameRules`, `VaultEntry`, `DeletionMethod`). No type changes.
6. **One `FrontmatterLocator`.** Replace the 4 regular expressions, with a test that every former caller sees the same region for LF, CRLF, `...` closers and empty frontmatter.
7. **`ScanPhase` enum** in `VaultIndex`, replacing the three fields; then extract `VaultScanner`.
8. **Index query families.** Move each family out of `VaultIndex` (one per change), starting with `GraphQueries` behind `LinkNameTable`.
9. **`VaultFiles` for sessions.** Introduce `VaultFiles` and move `MarkdownSession` and `CanvasSession` to `DocumentFileAccess`. Then move file management and configuration files out of `VaultStore`, and delete `VaultStore` when it has no members left (no forwarding façade).
10. **Unify the settings writers.** Move `types.json`, `templates.json`, `daily-notes.json` and `bookmarks.json` onto `ObsidianJSONObjectFile`. This intentionally changes output from sorted keys to Obsidian's order; record it in the release notes.
11. **Typed errors.** Replace `GraphiteError` payloads with typed cases and add the UI presenter; rewrite tests that compare messages to compare cases.
12. **`BookmarkKind` and a stable bookmark identity**; split `ConflictVersionStore`; move the test fake into test support with production semantics.

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| VAULT-INV-01 | `write(_:to:expecting:)` succeeds only when the destination is absent (`.absent`) or has exactly the expected SHA-256 and byte size (`.revision`); otherwise it throws `.conflict` and leaves the destination untouched ([AtomicFileWriter.swift:79-83](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L79-L83)). | Same-size external edit, deletion, and creation each yield `.conflict` and unchanged bytes. |
| VAULT-INV-02 | Staging goes to `itemReplacementDirectory` on the destination's volume, else to a hidden `.<UUID>.tmp` beside the destination; the staged file is flushed with `F_BARRIERFSYNC` (or `fsync`) before the rename, and the folder with `F_FULLFSYNC` after ([AtomicFileWriter.swift:67-127](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L67-L127)). `VaultMonitor` ignores names of the form `.<UUID>.tmp` ([FolderAccess.swift:184-189](../../../Sources/GraphiteApple/FolderAccess.swift#L184-L189)). | After a write, the vault folder contains only the destination; a presenter callback for `.<UUID>.tmp` is not reported. |
| VAULT-INV-03 | `FileRevision` is the lowercase hex SHA-256 of the bytes plus their count; `Codable` keys `digest`, `size` ([AtomicFileWriter.swift:4-21](../../../Sources/GraphiteCore/AtomicFileWriter.swift#L4-L21)). Streaming and in-memory digests are equal. | `FileRevision.of(data) == FileRevision.read(url)` for empty, 1 MiB and 1 MiB + 1 files. |
| VAULT-INV-04 | `VaultPath.rawValue` is NFC, has no empty, `.` or `..` components, never starts with `/`, never contains NUL; `..` above the root throws `.outsideVault`; `Codable` form is `{"rawValue": "…"}` and decoding re-validates ([VaultPath.swift:26-55](../../../Sources/GraphiteCore/VaultPath.swift#L26-L55)). | Decomposed `É` equals composed; `a/../../b` throws; decoding `{"rawValue":"../x"}` throws. |
| VAULT-INV-05 | `url(in:)` follows at most 32 symbolic links and throws `.outsideVault` for any resolved location outside the resolved root, also for missing final components ([VaultPath.swift:84-114](../../../Sources/GraphiteCore/VaultPath.swift#L84-L114)). | Chained links out of the vault, link cycles, link to a missing file inside. |
| VAULT-INV-06 | `app.json`: only Graphite keys whose value text differs from the starting settings are written, in place; missing keys are appended in the order of `ownedValueTexts`; output is `{`, then one `  "name": value` line per member (two-space indent) joined by `,` and a line feed, then `}`, and `{}` when empty; an empty or blank file reads as defaults; a non-object is never overwritten; duplicate names keep the first position and the last value ([ObsidianSettings.swift:224-330](../../../Sources/GraphiteCore/ObsidianSettings.swift#L224-L330)). | Golden files: unknown keys, odd number spellings, duplicates, BOM, UTF-16 file; one-key change diff is one line. |
| VAULT-INV-07 | The 16 `app.json` keys and their encodings: `attachmentFolderPath` (`"/"` vault, `"./"` note folder, `"./x"` subfolder, else folder path), `newLinkFormat` (`shortest`/`relative`/`absolute`), `useMarkdownLinks` (inverse of Wikilinks), `strictLineBreaks`, `trashOption` (`system`/`local`/`none`), `alwaysUpdateLinks`, `promptDelete`, `fileSortOrder` (6 raw values), `newFileLocation` (`root`/`current`/`folder`), `newFileFolderPath` (only for `folder`), `autoPairBrackets`, `autoPairMarkdown`, `smartIndentList`, `useTab`, `tabSize` (read clamped to 1…8), `autoConvertHtml`; defaults as in [ObsidianSettings.swift:158-188](../../../Sources/GraphiteCore/ObsidianSettings.swift#L158-L188), [:197-213](../../../Sources/GraphiteCore/ObsidianSettings.swift#L197-L213). | Table-driven read and write of every key and default. |
| VAULT-INV-08 | `.obsidian/bookmarks.json`: an object whose `items` is an array; every field of every item and every other top-level key round-trips; `ctime` is an integer of milliseconds; `subpath` is written with a leading `#`; the file is created only when the change leaves at least one bookmark; an unchanged list leaves the bytes ([Bookmarks.swift:108-191](../../../Sources/GraphiteCore/Bookmarks.swift#L108-L191), [VaultStore.swift:185-202](../../../Sources/GraphiteCore/VaultStore.swift#L185-L202)). | Golden round trip with graph, url and unknown kinds; removing the last bookmark of a missing file writes nothing. |
| VAULT-INV-09 | `.obsidian/types.json`: assignments under `"types"`; an existing key spelled with other capitals keeps its spelling; values are `PropertyType` raw values `text`, `multitext`, `number`, `checkbox`, `date`, `datetime`, `tags`, `aliases`; an unchanged assignment leaves the bytes; a non-object file or `types` value is refused ([VaultStore.swift:137-175](../../../Sources/GraphiteCore/VaultStore.swift#L137-L175), [NoteProperties.swift:5-8](../../../Sources/GraphiteCore/NoteProperties.swift#L5-L8)). | Pinned in part by [CoreFilesSettingsFixTests.swift:29](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L29); add case-spelling test. |
| VAULT-INV-10 | `.obsidian/templates.json` keys `folder`, `dateFormat`, `timeFormat`; `.obsidian/daily-notes.json` keys `format` (written `""` when it equals `YYYY-MM-DD`), `folder`, `template`, `autorun`; other keys kept ([Templates.swift:19-69](../../../Sources/GraphiteCore/Templates.swift#L19-L69)). | Golden round trip with unknown keys. |
| VAULT-INV-11 | Deletion follows `trashOption`: system trash after a coordinated deletion outside it; on any failure, the vault's `.trash` at the root; vault trash names are `Name.ext`, then `Name 1.ext`…; folders keep their whole name ([VaultStore.swift:378-415](../../../Sources/GraphiteCore/VaultStore.swift#L378-L415)). | Delete twice into `.trash`; provider without trash falls back. |
| VAULT-INV-12 | `move` never replaces another item; a case-only rename is allowed; moving a folder into itself is refused by name and by file identity ([VaultStore.swift:307-337](../../../Sources/GraphiteCore/VaultStore.swift#L307-L337)). | Pinned by [CoreFilesSettingsFixTests.swift:167](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L167) and [FileOperationTests.swift:84](../../../Tests/GraphiteIndexTests/FileOperationTests.swift#L84). |
| VAULT-INV-13 | Free names: `uniquePath` trims whitespace and leading dots, refuses a stem containing `/`, `\` or a line feed, tries `Name.ext` then `Name 1.ext` up to `Name 100000.ext`, and never writes a trailing dot; `duplicate` starts at ` 1` ([VaultStore.swift:346-455](../../../Sources/GraphiteCore/VaultStore.swift#L346-L455)). | Pinned by [CoreFilesSettingsFixTests.swift:134](../../../Tests/GraphiteCoreTests/CoreFilesSettingsFixTests.swift#L134). |
| VAULT-INV-14 | `FileNameRules`: refuse empty, leading dot, `/ \ : * ? " < > |`, C0/C1 controls and newlines, and for notes `# ^ [ ] |`; at most 255 − 16 UTF-8 bytes ([VaultStore.swift:35-64](../../../Sources/GraphiteCore/VaultStore.swift#L35-L64)). Vault folder names use the same forbidden and control sets ([VaultList.swift:92-102](../../../Sources/GraphiteCore/VaultList.swift#L92-L102)). | Table of accepted and refused names. |
| VAULT-INV-15 | File recovery layout: `Application Support/Graphite/File Recovery/<vault UUID>/<first 32 hex characters of SHA-256(path)>/path.txt` plus snapshots named `<13-digit milliseconds since 1970>.md` (`%013.0f`), with `_<n>` before `.md` for same-millisecond copies; at most 200 per note, notes over 2 MiB and blank text skipped, newest first ([FileRecovery.swift:25-206](../../../Sources/GraphiteCore/FileRecovery.swift#L25-L206)). | Golden directory listing after three snapshots in one millisecond and a move. |
| VAULT-INV-16 | Index location: `Caches/Graphite/Indexes/<vault UUID>.sqlite` with `-wal` and `-shm`; a legacy file named by the SHA-256 hex of the root's standardized path moves there once, with its journals; other `.sqlite` files whose newest of file and `-wal` modification is older than 30 days are deleted ([VaultIndex.swift:211-249](../../../Sources/GraphiteIndex/VaultIndex.swift#L211-L249)). The index is never inside the vault. | Temporary caches folder with a legacy file and an old file. |
| VAULT-INV-17 | GRDB migration identifiers, in order: `inventory-and-links-1`, `bounded-update-lookups-2`, `filename-search-and-row-identities-3`, `vault-path-markdown-link-targets-4`, `base-properties-and-creation-dates-5`, `unicode-name-keys-6`, `search-whole-note-text-7`, `case-folded-link-keys-8`, `markdown-link-written-targets-9`; FTS5 tokenizer `unicode61 remove_diacritics 2`; SQL functions `graphite_regexp` (argument prefix `c:`/`i:`) and `graphite_folded_key` ([VaultIndex.swift:81-187](../../../Sources/GraphiteIndex/VaultIndex.swift#L81-L187), [VaultSearch.swift:298](../../../Sources/GraphiteIndex/VaultSearch.swift#L298), [:420-422](../../../Sources/GraphiteIndex/VaultSearch.swift#L420-L422)). | Open a database created by each earlier migration set; assert `grdb_migrations` rows. |
| VAULT-INV-18 | `files.contentIndexed` values: 0 not read, 1 indexed, 2 read but not UTF-8 ([VaultIndex.swift:30-37](../../../Sources/GraphiteIndex/VaultIndex.swift#L30-L37)); notes over 8 MiB, not downloaded, or not UTF-8 are not re-read until size or date changes. | Pinned by [IndexVaultIndexFixTests.swift:314](../../../Tests/GraphiteIndexTests/IndexVaultIndexFixTests.swift#L314). |
| VAULT-INV-19 | A scan prunes only after an error-free enumeration; files that failed to be inspected, read or written stay; a file refreshed during a scan is never pruned nor overwritten by the scan's older reading; hidden paths and paths through symbolic links are never indexed ([VaultIndex.swift:572-869](../../../Sources/GraphiteIndex/VaultIndex.swift#L572-L869)). | Pinned by [IndexVaultIndexFixTests.swift:241-420](../../../Tests/GraphiteIndexTests/IndexVaultIndexFixTests.swift#L241-L420). |
| VAULT-INV-20 | Link resolution order: direct candidates (beside the note, then from the root; `./`/`../` note-relative only; leading `/` root only; written extension first), then whole path or path suffix, then file name and, for Wikilinks only, alias; exact spelling wins among case variants; more than one result is returned as ambiguous, at most 50 ([VaultIndex.swift:365-411](../../../Sources/GraphiteIndex/VaultIndex.swift#L365-L411), [MarkdownSemantics.swift:883-903](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L883-L903)). | One contract suite run against SQL and `GraphLinkResolver`. |
| VAULT-INV-21 | Rename link rewriting: a bare name or alias that still finds its target stays as written; a name that becomes ambiguous gets a vault path; vault paths stay vault paths; relative paths are recomputed and keep `./`; `#subpath`, alias, `!`, label and title stay; non-ASCII stays literal or encoded as written; a leading BOM is kept; nothing is written to a note whose links cannot be located; notes are written after the move, only at their planned revision ([LinkRewriter.swift:462-555](../../../Sources/GraphiteCore/LinkRewriter.swift#L462-L555), [VaultFileOperations.swift:88-253](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L253)). | Pinned by `FileOperationTests` and `IndexFileOperationsFixTests`; add the non-ASCII collision case (BUG-VAULT-01). |
| VAULT-INV-22 | Search: at most 200 results per page (default 50), at most 20 name matches first, each read bounded by 5,000 checked candidates or 250 ms, regular expressions limited to 1 s, at most 5 excerpts per result with 70 characters of context, nesting deeper than 32 read flat, a page empty only when the search is finished, continuation by sort value then path ([VaultSearch.swift:100-206](../../../Sources/GraphiteIndex/VaultSearch.swift#L100-L206), [SearchQuery.swift:54](../../../Sources/GraphiteCore/SearchQuery.swift#L54), [:1116](../../../Sources/GraphiteCore/SearchQuery.swift#L1116)). | Pinned in part by `SearchSyntaxTests`, `IndexSearchFixTests`; add a continuation test with inserts between pages. |
| VAULT-INV-23 | `SearchTextTokens` tokenizes exactly as `unicode61 remove_diacritics 2` (Unicode 6.1 tables) ([SearchQuery.swift:393-553](../../../Sources/GraphiteCore/SearchQuery.swift#L393-L553)). | Pinned by `CoreSearchQueryUnicode61AgreementTests`. |
| VAULT-INV-24 | Vault list in `UserDefaults` key `GraphiteKnownVaults` (unreadable copy in `GraphiteKnownVaults.unreadable`, legacy `GraphiteVaultBookmark`), JSON from the default `JSONEncoder`: `{"vaults":[{"id","name","location":{"anchor":{"bookmark":{"_0":<base64>}} or {"applicationDocuments":{}},"relativePath"},"lastKnownPath","lastOpenedDate":<seconds since 2001>,"lastOpenedDocument":{"rawValue"}}]}`, with `lastOpenedDocument` omitted when nil; entries this build cannot decode are written back unchanged ([VaultList.swift:4-38](../../../Sources/GraphiteCore/VaultList.swift#L4-L38), [VaultLibrary.swift:12-16](../../../Sources/GraphiteUI/VaultLibrary.swift#L12-L16), [:69-109](../../../Sources/GraphiteUI/VaultLibrary.swift#L69-L109)). | Golden JSON decode of a stored list from this snapshot, plus one unknown entry. |
| VAULT-INV-25 | Tab layout per vault in `UserDefaults` key `GraphiteTabLayout.<vault UUID>`: `groups[{tabs[{path, isPinned, pluginView{viewType, state}}], activeTabIndex}]`, `focusedGroupIndex`, `splitFraction`, `sidebarPluginViews`, `shownSidebarPluginViewType`, optional members omitted when nil; restore drops missing files and repeated files and keeps at most 2 groups; the split fraction is clamped to 0.25…0.75 when set ([TabLayout.swift:48-54](../../../Sources/GraphiteCore/TabLayout.swift#L48-L54), [:326-444](../../../Sources/GraphiteCore/TabLayout.swift#L326-L444), [WorkspaceTabs.swift:85-87](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L85-L87)). | Golden JSON restore with a missing file, a duplicate and a split fraction of 0.9. |
| VAULT-INV-26 | Document places per vault in `UserDefaults` key `GraphiteDocumentPlaces.<vault UUID>`: `{"placesByPath":{path:{"place":{"note":{"_0":{topLocation, selectionLocation, selectionLength}}} or {"pdf":{"_0":{pageIndex, fractionFromTop}}},"leftAt":<seconds since 2001>}}}`; at most 400, oldest dropped, start places forgotten ([DocumentPlaces.swift:5-98](../../../Sources/GraphiteCore/DocumentPlaces.swift#L5-L98), [WorkspacePlaces.swift:8-10](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L8-L10)). | Golden JSON round trip; 401st place evicts the oldest. |
| VAULT-INV-27 | Deep links: schemes `graphite` and `obsidian`; actions `open` (`file`, `path`), `search` (`query`), `new` (`name`, `file`, `content`, `silent`, `append`, `overwrite`), `daily`, `read` (`file`), `vault/<name>/<file>`, otherwise a plugin action (lowercased) keeping original parameter names; `openingLink` writes `graphite://open?vault=…&file=…` with a note's `.md` dropped and `encodeURIComponent` encoding except `/` ([VaultURI.swift:47-120](../../../Sources/GraphiteCore/VaultURI.swift#L47-L120)). | Table of links parsed and written. |
| VAULT-INV-28 | Conflicted copy stem: `<stem> (Conflicted copy <device> <yyyyMMddHHmm>)`, device name stripped of forbidden, control and `()` characters (and link-breaking ones for notes), at most 40 characters, stem shortened to fit 255 − 16 bytes ([ConflictVersions.swift:45-85](../../../Sources/GraphiteCore/ConflictVersions.swift#L45-L85)). | Pinned by `ConflictVersionTests`. |
| VAULT-INV-29 | Picked folders inside the app's Documents folder are saved as `applicationDocuments` plus a relative path on iOS; elsewhere as bookmark data (`.minimalBookmark` on iOS, `.withSecurityScope` on macOS); a stale bookmark is refreshed on access ([FolderAccess.swift:29-128](../../../Sources/GraphiteApple/FolderAccess.swift#L29-L128)). | Bookmark round trip on macOS; relative path on iOS simulator. |
| VAULT-INV-30 | Drawing file stem `Drawing YYYY-MM-DD HH.MM.SS` in the Gregorian calendar ([AttachmentResolver.swift:38-42](../../../Sources/GraphiteCore/AttachmentResolver.swift#L38-L42)); embeds use `![[…]]` unless Wikilinks are off or the target holds `| [ ] # ^`, then `![](…)` with the unreserved set kept ([:19-33](../../../Sources/GraphiteCore/AttachmentResolver.swift#L19-L33)). | Pinned by `SettingsAndAttachmentTests` and `CoreFilesSettingsFixTests.swift:151`. |
| VAULT-INV-31 | Reading-view task location: UTF-16 offset of the status character and an FNV-1a checksum (offset basis 2166136261, prime 16777619) over the line's UTF-16 units as little-endian bytes, the status left out; marked text is marker, status code point, and optionally marker, offset, marker, checksum ([ReadingTasks.swift:151-173](../../../Sources/GraphiteCore/ReadingTasks.swift#L151-L173)). | Toggle after an edit elsewhere on the line is refused. |
| VAULT-INV-32 | Frontmatter edits change only the edited properties' lines; unchanged properties keep exact YAML (comments, quotes, number spellings, anchors); the frontmatter's own line ending is used ([NoteProperties.swift:72-91](../../../Sources/GraphiteCore/NoteProperties.swift#L72-L91)). | Pinned by `NotePropertiesTests`, `CoreFrontmatterFixTests`. |
| VAULT-INV-33 | YAML bounds: at most `1000 / maximumDepth − 1` anchors; expanded weight at most 65,536 + 4 × source bytes; depth at most `maximumDepth` ([YAMLAliasExpansionLimits.swift:20-102](../../../Sources/GraphiteCore/YAMLAliasExpansionLimits.swift#L20-L102)). | Billion-laughs and deep-chain fixtures are refused without crashing. |
| VAULT-INV-34 | Navigation bounds: history 100 entries, recent files 30, closed tabs 20, a file in at most one tab ([Navigation.swift:224](../../../Sources/GraphiteCore/Navigation.swift#L224), [:277](../../../Sources/GraphiteCore/Navigation.swift#L277), [TabLayout.swift:45-48](../../../Sources/GraphiteCore/TabLayout.swift#L45-L48)). | Pinned by `TabLayoutTests` and `VaultTests`. |
| VAULT-INV-35 | Conflict-version discovery never starts a download: iCloud answers from metadata, other providers' `SF_DATALESS` placeholders are skipped; a version is marked resolved and removed only inside a coordinated write and only after its separate file is published ([FileVersionConflicts.swift:51-169](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L51-L169)). | Contract suite with local `NSFileVersion` objects. |

### Tests that become possible once the seams exist

- **Name-count contract:** for any vault, `LinkIndexQueries.nameCount(name, excluding:)` equals the number of paths the resolver returns for the bare name (closes BUG-VAULT-01).
- **`LinkNameTable` contract:** one suite run against the SQL table and the in-memory table (LSP-VAULT-03).
- **`ConflictVersionResolution` contract:** stale replace, absent destination, missing version, refused coordination and failed removal against both the production adapter and the fake (LSP-VAULT-02).
- **`ObsidianConfigurationFiles` with an injected `VaultFiles`:** unreadable, oversized and missing files give three different states (closes BUG-VAULT-02).
- **`IndexLocation` with an injected caches folder and `now`:** legacy migration and 30-day cleanup without touching the user's Caches.
- **`FreeFileName` as a pure function:** name sequences with an `isTaken` closure, no disk.
- **`ScanPhase` transitions:** begin, refresh during scan, cancel, end, with no database.
- **Sessions with a `DocumentFileAccess` value** backed by an in-memory map, for save, conflict and reload logic without a folder.

## 8. Appendix: raw metrics

### Reconnaissance numbers (verified or corrected)

| Metric | Reconnaissance | This audit |
| --- | --- | --- |
| Files, physical lines, code lines | 34 files, 9789, 7303 | Confirmed by reading every file; 26 of the files are in GraphiteCore. |
| Functions over 40 code lines | 13 (listed in CC-VAULT-05) | Confirmed by reading the 5 longest. |
| Types over 300 code lines | `VaultIndex` 600, `NoteProperties` 347 | Confirmed. `VaultStore` is 340 code lines as a file, but the file also holds `VaultEntry`, `DeletionMethod`, `DeletionOutcome` and `FileNameRules`, so its own declaration is below 300. It is mapped in section 3.1 because it has 24 public methods plus 8 in extensions. |
| Files over 400 code lines | `SearchQuery.swift` 944, `VaultIndex.swift` 633, `VaultSearch.swift` 559, `LinkRewriter.swift` 489 | Confirmed. |
| `try?` | 104 | Not recounted. The cases that matter are in CC-VAULT-01 and BUG-VAULT-02; most others are commented best-effort cleanup (for example [FileRecovery.swift:69](../../../Sources/GraphiteCore/FileRecovery.swift#L69), [VaultIndex.swift:881-884](../../../Sources/GraphiteIndex/VaultIndex.swift#L881-L884)). |
| `static var` | 4 | Not recounted; the ones read are computed (`YAMLAliasExpansion.maximumAnchorCount`, `maximumDepth`, `VaultStore.propertyTypesPath`, `SearchSQLCondition.everything`), with no static mutable state. |
| `@unchecked Sendable` | 2 | Confirmed: `VaultMonitor` ([FolderAccess.swift:135](../../../Sources/GraphiteApple/FolderAccess.swift#L135)) and `RegularExpressionCache` ([VaultSearch.swift:450](../../../Sources/GraphiteIndex/VaultSearch.swift#L450)); both state their invariant. |
| `Date()` / `Date.now` | 1 | `Date.now` at [VaultIndex.swift:240](../../../Sources/GraphiteIndex/VaultIndex.swift#L240); `.now` also appears as a default argument 6 times ([FileRecovery.swift:49](../../../Sources/GraphiteCore/FileRecovery.swift#L49), [:97](../../../Sources/GraphiteCore/FileRecovery.swift#L97), [Bookmarks.swift:108](../../../Sources/GraphiteCore/Bookmarks.swift#L108), [:115](../../../Sources/GraphiteCore/Bookmarks.swift#L115), [:121](../../../Sources/GraphiteCore/Bookmarks.swift#L121), [:127](../../../Sources/GraphiteCore/Bookmarks.swift#L127)) and in the benchmark ([main.swift:48](../../../Sources/GraphiteBenchmarks/main.swift#L48)). |
| `FileManager.default` | 68 | Spot-checked: 21 lines in `VaultStore.swift`, 13 lines in `VaultIndex.swift` and `VaultFileOperations.swift` (grep `FileManager\.default`). |
| `default:` in switch | 36 | Not recounted; 13 in `SearchQuery.swift` (grep `default:`), 2 of them over the app's own `SearchScope` (OCP-VAULT-03). |
| `[String: Any]` | 12 | Not recounted (ISP-VAULT-03). |
| `Task { }` | 1 | The one read is `Task.detached` in `VaultLocator.accessInBackground`, awaited by its caller ([FolderAccess.swift:52-54](../../../Sources/GraphiteApple/FolderAccess.swift#L52-L54)). |

### Counts made in this audit

| Count | Value | Method |
| --- | ---: | --- |
| `VaultStore` public methods (declaration) | 24 | Read [VaultStore.swift:83-455](../../../Sources/GraphiteCore/VaultStore.swift#L83-L455) |
| `VaultStore` methods in other files | 8 | Read the 3 extension blocks |
| Files holding or passing `VaultStore` | 11 (27 lines) | grep `(let|var) store: VaultStore|store: VaultStore[,)]` over `Sources/**` |
| `VaultIndex` instance stored properties | 4 | Read |
| `VaultIndex` public functions across its files | 24 in scope (plus `BaseRecordQueries.swift`) | Read |
| GRDB migrations | 9 | Read [VaultIndex.swift:81-186](../../../Sources/GraphiteIndex/VaultIndex.swift#L81-L186) |
| `ConflictVersionStore` requirements | 6 | Read |
| Test-store divergences from production | 4 | Read both files |
| Bookmark kind string literals | 18 | Read |
| Settings-file JSON writers | 4 | Read |
| Frontmatter regular expressions | 4 | grep `\\A---` |
| SHA-256 hex formatting copies | 5 | Read |
| Thrown `GraphiteError` sentences in scope | 44 | grep per directory (33 Core, 4 Index, 5 Apple, 2 benchmark) |
| Inline `AtomicFileWriter()` constructions | 5 | Read |
| Comments narrating incidents | 5 | Read |
| Findings | 28: 1 High, 12 Medium, 15 Low | This document |
| Bugs | 3 | This document |
| Invariants | 35 | This document |

### Tests read for this area

- **Core:** `VaultTests`, `FileRecoveryTests`, `SettingsAndAttachmentTests`, `CoreFilesSettingsFixTests` (test names read with grep `func test`).
- **Index:** `FileOperationTests`, `IndexFileOperationsFixTests` (lines 1-150 read in full), `IndexVaultIndexFixTests` (test names).
- **UI:** `TestConflictVersionStore` (read in full), `UiWorkspaceModelFixTests` (lines 1-50).
- **Present but only listed by name:** `BookmarkTests`, `VaultListTests`, `TabLayoutTests`, `ConflictVersionTests`, `DocumentPlacesTests`, `LinkGraphTests`, `MentionTests`, `VaultURITests`, `NotePropertiesTests`, `TemplateTests`, `TagsAndPropertiesTests`, `ReadingTaskTests`, `CoreSearchQueryFixTests`, `CoreSearchQueryUnicode61AgreementTests`, `CoreLinksFixTests`, `CoreFrontmatterFixTests`, `IndexTests`, `IndexVaultIndexScanBatchTests`, `CoreLinksFileOperationTests`, `SearchSyntaxTests`, `IndexSearchFixTests`, `CoreSearchQueryIndexSearchTests`, `VaultPlacesTests`, `VaultTagsAndPropertiesTests`, `CanvasLinkTests`.

## 9. Since the snapshot

Delta audit of 2026-10-19. The notebook library (`7f56e00`, `2e1b6a2`, read at `9040705`) added the vault's folder-style file; the other vault changes at `fff794b` are recorded with the shell's in [shell.md](shell.md) section 9.

### New findings

#### CC-VAULT-11 `FolderStyleList.followMove` re-implements `VaultPath.replacingPrefix` by character count and drops a style silently
- **Severity:** Low
- **Rule:** `FR-10`, `FR-58`
- **Evidence:** character counts and `try?` ([FolderStyleList.swift:146-151](../../../Sources/GraphiteCore/FolderStyleList.swift#L146-L151)) instead of [VaultPath.swift:147-152](../../../Sources/GraphiteCore/VaultPath.swift#L147-L152); the comment "A moved path is always valid" is not checked. Introduced in `7f56e00`.
- **Fix direction:** call `replacingPrefix` and keep the entry if it throws.

#### CC-VAULT-12 An unreadable folder-style file is refused but never moved aside, and its format has no golden fixture or failure-injection test
- **Severity:** Medium
- **Rule:** `FR-61`, `FR-95`, `FR-97`
- **Evidence:** a refused file stays in place, so every later update throws ([FolderStyleList.swift:96-117](../../../Sources/GraphiteCore/FolderStyleList.swift#L96-L117), [VaultStoreFolderStyles.swift:19-20](../../../Sources/GraphiteCore/VaultStoreFolderStyles.swift#L19-L20)); the tests use an inline string, not a fixture ([FolderStyleListTests.swift:6-15](../../../Tests/GraphiteCoreTests/FolderStyleListTests.swift#L6-L15)), and no test injects a failing write; round-trip, unknown-field and refusal cases are tested. Introduced in `7f56e00`. Together with `BUG-SHELL-07` this leaves a damaged file in place and the library unusable.
- **Fix direction:** rename an unreadable file aside under a versioned name; a `folder-styles-v1.json` fixture and a failing-write test.

### State changes of earlier findings (fff794b)
- `LSP-VAULT-01`: Open → **Fixed**. Both counts use `WikiLinkResolver.caseFoldedKey` and `folded_name` ([VaultFileOperations.swift:356-364](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L356-L364), [:389-396](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L389-L396)); regression test in `FileOperationTests` (`45a51be`).
- `CC-VAULT-01`: Open → **Partly fixed** (`877045a`). `configurationData` throws unless the file is missing, and bookmarks, templates and daily notes throw (`VaultStoreConfigurationReadingTests`); malformed JSON still becomes defaults ([Templates.swift:20](../../../Sources/GraphiteCore/Templates.swift#L20), [:58](../../../Sources/GraphiteCore/Templates.swift#L58)) and `propertyTypes` still returns `[:]`.
- `DIP-VAULT-02`: Open → **Partly fixed**. The workspace passes its caches folder; the nil fallback inside `VaultIndex` and the legacy `cacheURL(for:)` remain ([VaultIndex.swift:201-212](../../../Sources/GraphiteIndex/VaultIndex.swift#L201-L212)).
